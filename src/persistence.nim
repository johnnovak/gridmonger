import std/algorithm
import std/enumutils
import std/logging as log except Level
import std/math
import std/options
import std/setutils
import std/strformat
import std/strutils
import std/sugar
import std/unicode
import std/tables

import riff

import annotations
import common
import drawlevel
import fieldlimits
import icons
import level
import links
import map
import regions
import utils/misc
import utils/rle


const CurrentMapVersion = 4

# {{{ Debug logging
const DebugIndent = 2
var currDebugIndent = 0

proc initDebugIndent() =
  currDebugIndent = 0

proc pushDebugIndent() =
  currDebugIndent += DebugIndent

proc popDebugIndent() =
  currDebugIndent = max(currDebugIndent - DebugIndent, 0)

template debug(s: string) =
  log.debug(" ".repeat(currDebugIndent) & s)

template warn(s: string) =
  log.warn(" ".repeat(currDebugIndent) & s)

# }}}
# {{{ Field limits
const
  MapTitleLimits*          = strLimits(minRuneLen=1,  maxRuneLen=100)
  MapGameLimits*           = strLimits(minRuneLen=0,  maxRuneLen=100)
  MapAuthorLimits*         = strLimits(minRuneLen=0,  maxRuneLen=100)
  MapCreationTimeLimits*   = strLimits(minRuneLen=19, maxRuneLen=19)

  NotesLimits*             = strLimits(minRuneLen=0, maxRuneLen=8000)

  NumLevelsLimits*         = intLimits(min=0, max=999)
  LevelLocationNameLimits* = strLimits(minRuneLen=1, maxRuneLen=100)
  LevelNameLimits*         = strLimits(minRuneLen=0, maxRuneLen=100)
  LevelElevationLimits*    = intLimits(min= -200, max=200)
  LevelRowsLimits*         = intLimits(min=1, max=6666)
  LevelColumnsLimits*      = intLimits(min=1, max=6666)

  CoordRowStartLimits*     = intLimits(min= -9999, max=9999)
  CoordColumnStartLimits*  = intLimits(min= -9999, max=9999)

  RowsPerRegionLimits*     = intLimits(min=2, max=3333)
  ColumnsPerRegionLimits*  = intLimits(min=2, max=3333)
  RegionRowLimits*         = intLimits(min=0, max=3332)
  RegionColumnLimits*      = intLimits(min=0, max=3332)
  RegionNameLimits*        = strLimits(minRuneLen=1, maxRuneLen=100)

  CellFloorColorLimits*    = intLimits(min=0,
                                       max=LevelTheme.floorBackgroundColor.high)

  NumAnnotationsLimits*    = intLimits(min=0, max=9999)
  NoteTextLimits*          = strLimits(minRuneLen=1, maxRuneLen=4000)
  NoteOptionalTextLimits*  = strLimits(minRuneLen=0, maxRuneLen=4000)
  NoteCustomIdLimits*      = strLimits(minRuneLen=1, maxRuneLen=2)
  NoteColorLimits*         = intLimits(min=0,
                                       max=LevelTheme.floorBackgroundColor.high)
  NoteIconLimits*          = intLimits(min=0, max=NoteIcons.high)

  NumLinksLimits*          = intLimits(min=0, max=9999)
  ThemeNameLimits*         = strLimits(minRuneLen=1, maxRuneLen=100)
  ZoomLevelLimits*         = intLimits(min=MinZoomLevel, max=MaxZoomLevel)
  SpecialWallLimits*       = intLimits(min=0, max=SpecialWalls.high)

  NotesListSearchTermLimits* = strLimits(minRuneLen=0, maxRuneLen=100)

# }}}
# {{{ Types
type
  MapReadError*  = object of IOError
  MapWriteError* = object of IOError

  CompressionType = enum
    ctUncompressed     = (0, "uncompressed")
    ctRunLengthEncoded = (1, "run-length encoded")
    ctZeroes           = (2, "zeroes")

  AppStateNotesListPane* = ref object
    filter*:          NotesListFilter
    linkCursor*:      bool
    viewStartY*:      Natural
    levelSections*:   Table[Natural, bool]
    regionSections*:  Table[tuple[levelId: Natural, rc: RegionCoords], bool]

  AppState* = ref object
    themeName*:              string

    zoomLevel*:              range[MinZoomLevel..MaxZoomLevel]
    currLevelId*:            Natural
    cursorRow*:              Natural
    cursorCol*:              Natural
    viewStartRow*:           Natural
    viewStartCol*:           Natural

    showCellCoords*:      bool
    showToolsPane*:       bool
    showCurrentNotePane*: bool
    showNotesListPane*:   bool
    wasdMode*:            bool
    walkMode*:            bool
    # TODO
    # optPasteWraparound*:            bool

    currFloorColor*:         range[0..LevelTheme.floorBackgroundColor.high]
    currSpecialWall*:        range[0..SpecialWalls.high]

    notesListPaneState*:     Option[AppStateNotesListPane]

# }}}
# {{{ Chunk IDs
const
  # Format type ID
  FourCC_GRMM = "GRMM"

  # Group chunks
  # ============
  FourCC_GRMM_lvl  = "lvl "
  FourCC_GRMM_lvls = "lvls"
  FourCC_GRMM_map  = "map "
  FourCC_GRMM_stat = "stat"

  # Chunks
  # ======

  # Common 'map ' and 'lvl ' subchunks
  FourCC_GRMM_coor = "coor"
  FourCC_GRMM_prop = "prop"

  # 'lvl ' subchunks
  FourCC_GRMM_anno = "anno"
  FourCC_GRMM_cell = "cell"
  FourCC_GRMM_regn = "regn"

  FourCC_GRMM_lnks = "lnks"

  # 'stat' subchunks
  FourCC_GRMM_disp = "disp"
  FourCC_GRMM_notl = "notl"
  FourCC_GRMM_opts = "opts"
  FourCC_GRMM_tool = "tool"

# }}}

proc logError(e: ref Exception) =
  var msg = "Error writing map: " & e.msg &
            "\n\nStack trace:\n" & getStackTrace(e)
  log.error(msg)

# {{{ Read

using rr: RiffReader

# TODO move utils into nim-riff?
# {{{ appendInGroupChunkMsg()
proc appendInGroupChunkMsg(msg: string, groupChunkId: Option[string]): string =
  if groupChunkId.isSome:
    msg & fmt" inside a '{groupChunkId.get}' group chunk"
  else: msg

# }}}

# {{{ raiseMapReadError()
proc raiseMapReadError(s: string) {.noReturn.} =
  raise newException(MapReadError, s)

# }}}
# {{{ chunkOnlyOnceError()
proc chunkOnlyOnceError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"'{chunkId}' chunk can only appear once"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

# }}}
# {{{ chunkNotFoundError()
proc chunkNotFoundError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"Mandatory '{chunkId}' chunk not found"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

# }}}
# {{{ invalidChunkError()
proc invalidChunkError(chunkId, groupChunkId: string) =
  var msg = fmt"'{chunkId}' chunk is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)

# }}}
# {{{ invalidListChunkError()
proc invalidListChunkError(formatTypeId, groupChunkId: string) =
  var msg = fmt"'LIST' chunk with format type '{formatTypeId}' is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)

# }}}

# {{{ checkStringLength()
proc checkStringLength(s: string, name: string, limit: FieldLimits,
                       debugLog = true) =
  if debugLog:
    debug(fmt"{name}: {s}")
  if s.runeLen < limit.minRuneLen or s.runeLen > limit.maxRuneLen:
    raiseMapReadError(
      fmt"The length of string '{name}' must be between {limit.minRuneLen} " &
      fmt"and {limit.maxRuneLen} UTF-8 code points, " &
      fmt"actual length: {s.runeLen}, value: {s}"
    )

# }}}
# {{{ checkValueRange()
proc checkValueRange[T: SomeInteger](v: T, name: string,
                                     min: T = 0, max: T = 0, debugLog = true) =
  if debugLog:
    debug(fmt"{name}: {v}")

  if v < min or v > max:
    raiseMapReadError(
      fmt"The value of integer '{name}' must be between {min} and {max}, " &
      fmt"actual value: {v}"
    )

proc checkValueRange[T: SomeInteger](v: T, name: string,
                                     limit: FieldLimits, debugLog = true) =
  checkValueRange(v, name, T(limit.minInt), T(limit.maxInt), debugLog)

# }}}
# {{{ checkBool()
proc checkBool(b: uint8, name: string, debugLog = true) =
  if debugLog:
    debug(fmt"{name}: {b}")
  if b > 1:
    raiseMapReadError(
      fmt"The value of boolean '{name}' must be either 0 or 1, " &
      fmt"actual value: {b}"
    )

# }}}
# {{{ checkEnum()
{.push warning[HoleEnumConv]:off.}

proc checkEnum(v: SomeInteger, name: string, E: typedesc[enum],
               debugLog = true) =
  if debugLog:
    debug(fmt"{name}: {v}")
  try:
    discard E(v).symbolRank
  except IndexDefect:
    raiseMapReadError(fmt"Invalid enum value for {name}: {v}")

{.pop}

# }}}

# {{{ readAppState_preV4()
proc readAppState_preV4(rr; map: Map): AppState =
  debug(fmt"Reading app state...")
  pushDebugIndent()

  let themeName = rr.readBStr()
  checkStringLength(themeName, "stat.themeName", ThemeNameLimits)

  let zoomLevel = rr.read(uint8)
  checkValueRange(zoomLevel, "stat.zoomLevel", ZoomLevelLimits)

  # Cursor position
  let maxLevelIndex = NumLevelsLimits.maxInt-1
  var currLevelIndex = rr.read(uint16).int
  checkValueRange(currLevelIndex, "stat.currLevelIndex", max=maxLevelIndex)

  let l = map.levels[currLevelIndex]

  let cursorRow = rr.read(uint16)
  checkValueRange(cursorRow, "stat.cursorRow", max=l.rows.uint16-1)

  let cursorCol = rr.read(uint16)
  checkValueRange(cursorCol, "stat.cursorCol", max=l.cols.uint16-1)

  let viewStartRow = rr.read(uint16)
  checkValueRange(viewStartRow, "stat.viewStartRow", max=l.rows.uint16-1)

  let viewStartCol = rr.read(uint16)
  checkValueRange(viewStartCol, "stat.viewStartCol", max=l.cols.uint16-1)

  # Options
  let showCellCoords = rr.read(uint8)
  checkBool(showCellCoords, "stat.showCellCoords")

  let showToolsPane = rr.read(uint8)
  checkBool(showToolsPane, "stat.showToolsPane")

  let showCurrentNotePane = rr.read(uint8)
  checkBool(showCurrentNotePane, "stat.showCurrentNotePane")

  let wasdMode = rr.read(uint8)
  checkBool(wasdMode, "stat.wasdMode")

  let walkMode = rr.read(uint8)
  checkBool(walkMode, "stat.walkMode")

  # Tools pane state
  let currFloorColor = rr.read(uint8)
  checkValueRange(currFloorColor, "stat.currFloorColor", CellFloorColorLimits)

  let currSpecialWall = rr.read(uint8)
  checkValueRange(currSpecialWall, "stat.currSpecialWall", SpecialWallLimits)

  result = AppState(
    themeName:       themeName,

    zoomLevel:       zoomLevel,
    currLevelId:     currLevelIndex,
    cursorRow:       cursorRow,
    cursorCol:       cursorCol,
    viewStartRow:    viewStartRow,
    viewStartCol:    viewStartCol,

    showCellCoords:      showCellCoords.bool,
    showToolsPane:       showToolsPane.bool,
    showCurrentNotePane: showCurrentNotePane.bool,
    wasdMode:            wasdMode.bool,
    walkMode:            walkMode.bool,

    currFloorColor:  currFloorColor,
    currSpecialWall: currSpecialWall
  )

  popDebugIndent()

# }}}
# {{{ readLocation()
proc readLocation(rr): Location =
  result.levelId = rr.read(uint16).Natural
  result.row     = rr.read(uint16)
  result.col     = rr.read(uint16)

# }}}
# {{{ readNotesListPaneState()
proc readNotesListPaneState(rr; map: Map): AppStateNotesListPane =
  debug(fmt"Reading notes list pane state...")

  var s = AppStateNotesListPane()

  # Filters
  let scopeFilter = rr.read(uint8)
  checkEnum(scopeFilter, "stat.notl.scopeFilter", NoteScopeFilter)
  s.filter.scope = scopeFilter.NoteScopeFilter

  # noteType is a bit-vector
  let noteTypeFilter = rr.read(uint8)
  let MaxNoteTypeFilterValue = cast[uint8](NoteTypeFilter.fullSet)

  if noteTypeFilter > MaxNoteTypeFilterValue:
    raiseMapReadError(
      fmt"The value of 'noteTypeFilter' must be between 0 and " &
      fmt"{MaxNoteTypeFilterValue}, actual value: {noteTypeFilter}"
    )
  s.filter.noteType = cast[set[NoteTypeFilter]](noteTypeFilter)

  s.filter.searchTerm = rr.readWStr
  checkStringLength(s.filter.searchTerm, "stat.notl.searchTerm",
                    NotesListSearchTermLimits)

  let orderBy = rr.read(uint8)
  checkEnum(orderBy, "stat.notl.orderBy", NoteOrdering)
  s.filter.orderBy = orderBy.NoteOrdering

  let linkCursor = rr.read(uint8)
  checkBool(linkCursor, "stat.notl.linkCursor")
  s.linkCursor = linkCursor.bool

  s.viewStartY = rr.read(uint32)

  # Section states
  for levelIndex in 0..<map.levels.len:
    let sectionState = rr.read(uint8)
    checkBool(sectionState, "stat.notl.levelSectionState")
    s.levelSections[levelIndex] = sectionState.bool

    let l = map.levels[levelIndex]

    # `numRegions` can be non-zero even if `regionOpts.enabled` is `false`.
    if l.regions.numRegions > 0:

      # Iterate through the regions starting from region coords (0,0)
      # (top-left corner), then go left to right, top to bottom.
      for rc in l.regionCoords:
        let r = l.regions[rc].get

        let regionState = rr.read(uint8)
        checkBool(regionState, "stat.notl.regionSectionState")
        let key = (levelIndex.Natural, rc)
        s.regionSections[key] = regionState.bool

  result = s

# }}}
# {{{ readAppState_V4()
proc readAppState_V4(rr; map: Map): AppState =
  debug(fmt"Reading app state...")
  pushDebugIndent()

  var ci = rr.enterGroup

  var
    dispCursor = Cursor.none
    optsCursor = Cursor.none
    toolCursor = Cursor.none
    notlCursor = Cursor.none

  let groupChunkId = FourCC_GRMM_stat.some

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRMM_disp:
        if dispCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_disp, groupChunkId)
        dispCursor = rr.cursor.some

      of FourCC_GRMM_opts:
        if optsCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_opts, groupChunkId)
        optsCursor = rr.cursor.some

      of FourCC_GRMM_tool:
        if toolCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_tool, groupChunkId)
        toolCursor = rr.cursor.some

      of FourCC_GRMM_notl:
        if notlCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_notl, groupChunkId)
        notlCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRMM_stat)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk:
      ci = rr.nextChunk
    else: break


  var app = AppState(zoomLevel: DefaultZoomLevel)

  # Display state
  if dispCursor.isSome:
    rr.cursor = dispCursor.get

    let themeName = rr.readBStr()
    checkStringLength(themeName, "stat.disp.themeName", ThemeNameLimits)
    app.themeName = themeName

    let zoomLevel = rr.read(uint8)
    checkValueRange(zoomLevel, "stat.disp.zoomLevel", ZoomLevelLimits)
    app.zoomLevel = zoomLevel

    let maxLevelIndex = NumLevelsLimits.maxInt-1
    var currLevelIndex = rr.read(uint16).int
    checkValueRange(currLevelIndex, "stat.disp.currLevelIndex",
                    max=maxLevelIndex)
    app.currLevelId = currLevelIndex

    let l = map.levels[currLevelIndex]

    let cursorRow = rr.read(uint16)
    checkValueRange(cursorRow, "stat.disp.cursorRow", max=l.rows.uint16-1)
    app.cursorRow = cursorRow

    let cursorCol = rr.read(uint16)
    checkValueRange(cursorCol, "stat.disp.cursorCol", max=l.cols.uint16-1)
    app.cursorCol = cursorCol

    let viewStartRow = rr.read(uint16)
    checkValueRange(viewStartRow, "stat.disp.viewStartRow",
                    max=l.rows.uint16-1)
    app.viewStartRow = viewStartRow

    let viewStartCol = rr.read(uint16)
    checkValueRange(viewStartCol, "stat.disp.viewStartCol",
                    max=l.cols.uint16-1)
    app.viewStartCol = viewStartCol

  # Options state
  if optsCursor.isSome:
    rr.cursor = optsCursor.get

    let showCellCoords = rr.read(uint8)
    checkBool(showCellCoords, "stat.opts.showCellCoords")
    app.showCellCoords = showCellCoords.bool

    let showToolsPane = rr.read(uint8)
    checkBool(showToolsPane, "stat.opts.showToolsPane")
    app.showToolsPane = showToolsPane.bool

    let showCurrentNotePane = rr.read(uint8)
    checkBool(showCurrentNotePane, "stat.opts.showCurrentNotePane")
    app.showCurrentNotePane = showCurrentNotePane.bool

    let wasdMode = rr.read(uint8)
    checkBool(wasdMode, "stat.opts.wasdMode")
    app.wasdMode = wasdMode.bool

    let walkMode = rr.read(uint8)
    checkBool(walkMode, "stat.opts.walkMode")
    app.walkMode = walkMode.bool

    # TODO
#    let pasteWraparound = rr.read(uint8)
#    checkBool(pasteWraparound, "stat.opts.pasteWraparound")
#    app.pasteWraparound = pasteWraparound.bool

  # Tools pane state
  if toolCursor.isSome:
    rr.cursor = toolCursor.get

    let currFloorColor = rr.read(uint8)
    checkValueRange(currFloorColor, "stat.tool.currFloorColor",
                    CellFloorColorLimits)
    app.currFloorColor = currFloorColor

    let currSpecialWall = rr.read(uint8)
    checkValueRange(currSpecialWall, "stat.tool.currSpecialWall",
                    SpecialWallLimits)
    app.currSpecialWall = currSpecialWall

  # Note list pane state
  if notlCursor.isSome:
    rr.cursor = notlCursor.get
    app.notesListPaneState = readNotesListPaneState(rr, map).some

  result = app

  popDebugIndent()

# }}}
# {{{ readLinks()
proc readLinks(
  rr; levels: OrderedTable[Natural, Level]
): tuple[links: Links, warning: string] =

  debug(fmt"Reading links...")
  pushDebugIndent()

  var numLinks = rr.read(uint16).int
  checkValueRange(numLinks, "links.numLinks", NumLinksLimits)

  let maxLevelIndex = NumLevelsLimits.maxInt-1

  pushDebugIndent()

  var links   = initLinks()
  var warning = ""

  while numLinks > 0:
    try:
      let src = readLocation(rr)
      let srcLevel = levels[src.levelId]
      checkValueRange(src.levelId,  "lnks.srcLevel",   max=maxLevelIndex)
      checkValueRange(src.row,      "lnks.srcRow",     max=srcLevel.rows-1)
      checkValueRange(src.col,      "lnks.srcColumh",  max=srcLevel.cols-1)

      let dest = readLocation(rr)
      let destLevel = levels[dest.levelId]
      checkValueRange(dest.levelId, "lnks.destLevel",  max=maxLevelIndex)
      checkValueRange(dest.row,     "lnks.destRow",    max=destLevel.rows-1)
      checkValueRange(dest.col,     "lnks.destColumn", max=destLevel.cols-1)

      links.set(src, dest)

    except MapReadError as e:
      warn("Skipping invalid link: " & e.msg)
      warning = "invalid links have been skipped"

    dec(numLinks)

  result = (links, warning)

  popDebugIndent()
  popDebugIndent()

# }}}
# {{{ readLevelProperties()
proc readLevelProperties(rr): Level =
  debug(fmt"Reading level properties...")
  pushDebugIndent()

  let locationName = rr.readWStr
  checkStringLength(locationName, "lvl.prop.locationName",
                    LevelLocationNameLimits)

  let levelName = rr.readWStr
  checkStringLength(levelName, "lvl.prop.levelName", LevelNameLimits)

  let elevation = rr.read(int16).int
  checkValueRange(elevation, "lvl.prop.elevation", LevelElevationLimits)

  let numRows = rr.read(uint16)
  checkValueRange(numRows, "lvl.prop.numRows", LevelRowsLimits)

  let numColumns = rr.read(uint16)
  checkValueRange(numColumns, "lvl.prop.numColumns", LevelColumnsLimits)

  let overrideCoordOpts = rr.read(uint8)
  checkBool(overrideCoordOpts, "lvl.prop.overrideCoordOpts")

  let notes = rr.readWStr
  checkStringLength(notes, "lvl.prop.notes", NotesLimits)

  result = newLevel(locationName, levelName, elevation, numRows, numColumns)
  result.overrideCoordOpts = overrideCoordOpts.bool
  result.notes = notes

  popDebugIndent()

# }}}
# {{{ readLevelCells()
{.push warning[HoleEnumConv]:off.}

proc readLevelCells(rr; numCells: Natural): seq[Cell] =

  template readLayer(name: string; fieldType: typedesc;
                     field, checkField: untyped) =
    debug("Reading " &  $name & " layer")
    pushDebugIndent()

    let ct = rr.read(uint8)
    checkEnum(ct, "lvl.cell.compressionType", CompressionType)

    let compressionType = ct.CompressionType
    debug("Compression type: " & $compressionType)

    case compressionType:
    of ctUncompressed:
      for c {.inject.} in cells.mitems:
        let data {.inject.} = rr.read(uint8)
        checkField
        field = fieldType(data)

    of ctRunLengthEncoded:
      let compressedSize = rr.read(uint32)
      debug("Compressed size: " & $compressedSize)

      if compressedSize.int > numCells:
        raiseMapReadError(
          "Error decompressing level cell data: invalid compressed size: " &
          $compressedSize & ", numCells: " & $numCells
        )

      if compressedBuf.len < compressedSize.int:
        compressedBuf = newSeq[byte](compressedSize)

      rr.read(compressedBuf, 0, compressedSize)

      var d: RunLengthDecoder
      initRunLengthDecoder(d, compressedBuf)

      for c {.inject.} in cells.mitems:
        let b = d.decode
        if b.isSome:
          let data {.inject.} = b.get
          checkField
          field = fieldType(data)
        else:
          raiseMapReadError(
            "Error decompressing level cell data: premature end of " &
            "compressed stream"
          )

    of ctZeroes:
      for c {.inject.} in cells.mitems:
        field = fieldType(0)

    popDebugIndent()

  debug(fmt"Reading level cells...")
  pushDebugIndent()
  debug(fmt"numCells: {numCells}")

  var cells: seq[Cell]
  newSeq[Cell](cells, numCells)

  var compressedBuf: seq[byte]

  readLayer("floor", Floor): c.floor
  do: checkEnum(data, "lvl.cell.floor", Floor, debugLog=off)

  readLayer("floorOrientation", Orientation): c.floorOrientation
  do: checkEnum(data, "lvl.cell.floorOrientation", Orientation, debugLog=off)

  readLayer("floorColor", byte): c.floorColor
  do: checkValueRange(data, "lvl.cell.floorColor", CellFloorColorLimits, debugLog=off)

  readLayer("wallNorth", Wall): c.wallN
  do: checkEnum(data, "lvl.cell.wallN", Wall, debugLog=off)

  readLayer("wallWest", Wall): c.wallW
  do: checkEnum(data, "lvl.cell.wallW", Wall, debugLog=off)

  readLayer("trail", bool): c.trail
  do: checkBool(data, "lvl.cell.trail", debugLog=off)

  result = cells

  popDebugIndent()

{.pop}

# }}}
# {{{ readLevelAnnotations()
proc readLevelAnnotations(rr; l: Level) =
  debug(fmt"Reading level annotations...")
  pushDebugIndent()

  let numAnnotations = rr.read(uint16).Natural
  checkValueRange(numAnnotations, "lvl.anno.numAnnotations",
                  NumAnnotationsLimits)

  for i in 0..<numAnnotations:
    debug(fmt"index: {i}")
    pushDebugIndent()

    let row = rr.read(uint16)
    checkValueRange(row, "lvl.anno.row", max=l.rows.uint16-1)

    let col = rr.read(uint16)
    checkValueRange(col, "lvl.anno.col", max=l.cols.uint16-1)

    let kind = rr.read(uint8)
    checkEnum(kind, "lvl.anno.kind", AnnotationKind)

    var anno = Annotation(kind: AnnotationKind(kind))

    case anno.kind
    of akComment:
      discard

    of akIndexed:
      let index = rr.read(uint16)
      checkValueRange(index, "lvl.anno.index", NumAnnotationsLimits)
      anno.index = index

      let indexColor = rr.read(uint8)
      checkValueRange(indexColor, "lvl.anno.indexColor", NoteColorLimits)
      anno.indexColor = indexColor

    of akIcon:
      let icon = rr.read(uint8)
      checkValueRange(icon, "lvl.anno.icon", NoteIconLimits)
      anno.icon = icon

    of akCustomId:
      let customId = rr.readBStr
      checkStringLength(customId, "lvl.anno.customId", NoteCustomIdLimits)
      anno.customId = customId

    of akLabel:
      let labelColor = rr.read(uint8)
      checkValueRange(labelColor, "lvl.anno.labelColor", NoteColorLimits)
      anno.labelColor = labelColor

    let text = rr.readWStr

    let textLimits = case anno.kind
                     of akComment:  NoteTextLimits
                     of akIndexed:  NoteTextLimits
                     of akCustomId: NoteOptionalTextLimits
                     of akIcon:     NoteOptionalTextLimits
                     of akLabel:    NoteTextLimits

    checkStringLength(text, "lvl.anno.text", textLimits)

    anno.text = text
    l.setAnnotation(row, col, anno)

    popDebugIndent()

  popDebugIndent()

# }}}
# {{{ readCoordinateOptions*()
proc readCoordinateOptions(rr; parentChunk: string): CoordinateOptions =
  debug(fmt"Reading coordinate options...")
  pushDebugIndent()

  var parentChunk = strutils.strip(parentChunk)

  let origin = rr.read(uint8)
  checkEnum(origin, fmt"{parentChunk}.coor.origin", CoordinateOrigin)

  let rowStyle = rr.read(uint8)
  checkEnum(rowStyle, fmt"{parentChunk}.coor.rowStyle", CoordinateStyle)

  let columnStyle = rr.read(uint8)
  checkEnum(columnStyle, fmt"{parentChunk}.coor.columnStyle", CoordinateStyle)

  let rowStart = rr.read(int16)
  checkValueRange(rowStart, fmt"{parentChunk}.coor.rowStart",
                  CoordRowStartLimits)

  let columnStart = rr.read(int16)
  checkValueRange(columnStart, fmt"{parentChunk}.coor.columnStart",
                  CoordColumnStartLimits)

  result = CoordinateOptions(
    origin:      origin.CoordinateOrigin,
    rowStyle:    rowStyle.CoordinateStyle,
    columnStyle: columnStyle.CoordinateStyle,
    rowStart:    rowStart,
    columnStart: columnStart
  )

  popDebugIndent()

# }}}
# {{{ readLevelRegions*()
proc readLevelRegions(rr; levelCols: Natural,
                      version: Natural): tuple[regionOpts: RegionOptions,
                                               regions: Regions] =
  debug(fmt"Reading level regions...")
  pushDebugIndent()

  let enabled = rr.read(uint8)
  checkBool(enabled, "lvl.regn.enabled")

  let rowsPerRegion = rr.read(uint16)
  checkValueRange(rowsPerRegion, "lvl.regn.rowsPerRegion", RowsPerRegionLimits)

  let colsPerRegion = rr.read(uint16)
  checkValueRange(colsPerRegion, "lvl.regn.colsPerRegion",
                  ColumnsPerRegionLimits)

  let perRegionCoords = rr.read(uint8)
  checkBool(perRegionCoords, "lvl.regn.perRegionCoords")

  let regionOpts = RegionOptions(
    enabled:         enabled.bool,
    rowsPerRegion:   rowsPerRegion,
    colsPerRegion:   colsPerRegion,
    perRegionCoords: perRegionCoords.bool
  )

  # Note that regions can be present even if `regionOpts.enabled` is false.
  # We always load regions, even if they are disabled, to preserve their names
  # and notes (see `Level.regions` in `common.nim`).
  let numRegions = rr.read(uint16).Natural
  debug(fmt"numRegions: {numRegions}")

  var regions: Regions = initRegions()

  let regionCols = ceil(levelCols / regionOpts.colsPerRegion).int

  for regionIdx in 0..<numRegions:
    debug(fmt"regionIdx: {regionIdx}")
    pushDebugIndent()

    let regionCoords = if version < 4:
      let row = rr.read(uint16)
      checkValueRange(row, "lvl.regn.region.row", RegionRowLimits)

      let col = rr.read(uint16)
      checkValueRange(col, "lvl.regn.region.column", RegionColumnLimits)

      RegionCoords(row: row, col: col)
    else:
      RegionCoords(row: regionIdx div regionCols,
                   col: regionIdx mod regionCols)

    debug(fmt"regionCoords: {regionCoords}")

    let name = rr.readWStr
    checkStringLength(name, "lvl.regn.region.name", RegionNameLimits)

    let notes = rr.readWStr
    checkStringLength(notes, "lvl.regn.region.notes", NotesLimits)

    # Optimisation: sorting only once at the end speeds up the loading
    # massively
    regions.regionsByCoords[regionCoords] = initRegion(name=name, notes=notes)

    popDebugIndent()

  regions.sortRegions
  result = (regionOpts, regions)

  popDebugIndent()

# }}}
# {{{ readLevel()
proc readLevel(rr; version: Natural): Level =
  debug(fmt"Reading level...")
  pushDebugIndent()

  let groupChunkId = FourCC_GRMM_lvls.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none
    regnCursor = Cursor.none
    cellCursor = Cursor.none
    annoCursor = Cursor.none

  if not rr.hasSubChunks:
    raiseMapReadError(fmt"'{FourCC_GRMM_lvl}' group chunk is empty")

  var ci = rr.enterGroup

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRMM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRMM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      of FourCC_GRMM_regn:
        if regnCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_regn, groupChunkId)
        regnCursor = rr.cursor.some

      of FourCC_GRMM_cell:
        if cellCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_cell, groupChunkId)
        cellCursor = rr.cursor.some

      of FourCC_GRMM_anno:
        if annoCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_anno, groupChunkId)
        annoCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRMM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk:
      ci = rr.nextChunk
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRMM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRMM_coor)
  if regnCursor.isNone: chunkNotFoundError(FourCC_GRMM_regn)
  if cellCursor.isNone: chunkNotFoundError(FourCC_GRMM_cell)

  rr.cursor = propCursor.get
  var level = readLevelProperties(rr)

  rr.cursor = coorCursor.get
  level.coordOpts = readCoordinateOptions(rr, groupChunkId.get)

  rr.cursor = regnCursor.get
  (level.regionOpts, level.regions) = readLevelRegions(rr, level.cols, version)

  rr.cursor = cellCursor.get

  # +1 is needed because of the south & east borders
  let numCells = (level.rows+1) * (level.cols+1)

  level.cellGrid.cells = readLevelCells(rr, numCells)

  if annoCursor.isSome:
    rr.cursor = annoCursor.get
    readLevelAnnotations(rr, level)

  result = level

  popDebugIndent()

# }}}
# {{{ readLevelList()
proc readLevelList(rr; version: Natural): OrderedTable[Natural, Level] =
  debug(fmt"Reading level list...")
  pushDebugIndent()

  var levels = initOrderedTable[Natural, Level]()

  if rr.hasSubChunks:
    var ci = rr.enterGroup

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRMM_lvl:
          if levels.len > NumLevelsLimits.maxInt:
            raiseMapReadError(
              fmt"Map cannot contain more than {NumLevelsLimits.maxInt} levels"
            )

          # The level IDs must be set to their indices in the map file to
          # ensure they are in sync with link (see writeLinks()).
          let level = readLevel(rr, version)
          levels[level.id] = level

          rr.exitGroup
        else:
          invalidListChunkError(ci.formatTypeId, FourCC_GRMM_lvls)

      else: # not group chunk
        invalidChunkError(ci.id, FourCC_GRMM_lvls)

      if rr.hasNextChunk:
        ci = rr.nextChunk
      else: break

  debug(fmt"{levels.len} levels read")

  result = levels

  popDebugIndent()

# }}}
# {{{ readMapProperties()
proc readMapProperties(rr): tuple[map: Map, version: Natural] =
  debug(fmt"Reading map properties...")
  pushDebugIndent()

  let version = rr.read(uint16).Natural
  debug(fmt"map.prop.version: {version}")
  if version > CurrentMapVersion:
    raiseMapReadError(fmt"Unsupported map file version: {version}")

  let title = rr.readWStr
  checkStringLength(title, "map.prop.title", MapTitleLimits)

  let game = rr.readWStr
  checkStringLength(game, "map.prop.game", MapGameLimits)

  let author = rr.readWStr
  checkStringLength(author, "map.prop.author", MapAuthorLimits)

  let creationTime = rr.readBStr
  checkStringLength(creationTime, "map.prop.creationTime",
                    MapCreationTimeLimits)

  let notes = rr.readWStr
  checkStringLength(notes, "map.prop.notes", NotesLimits)

  let map = newMap(title, game, author, creationTime)
  map.notes = notes

  result = (map, version)

  popDebugIndent()

# }}}
# {{{ readMap()
proc readMap(rr): tuple[map: Map, version: Natural] =
  debug(fmt"Reading GRMM.map chunk...")
  pushDebugIndent()

  let groupChunkId = FourCC_GRMM_map.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none

  if not rr.hasSubChunks:
    raiseMapReadError(fmt"'{FourCC_GRMM_map}' group chunk is empty")

  var ci = rr.enterGroup

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRMM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRMM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRMM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRMM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk:
      ci = rr.nextChunk
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRMM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRMM_coor)

  rr.cursor = propCursor.get
  var (map, version) = readMapProperties(rr)

  rr.cursor = coorCursor.get
  map.coordOpts = readCoordinateOptions(rr, groupChunkId.get)

  result = (map, version)

  popDebugIndent()

# }}}
# # {{{ readMapFile*()
# TODO return display related info and info chunk data as well
proc readMapFile*(path: string): tuple[map: Map,
                                       appState: Option[AppState],
                                       warning: string] =
  initDebugIndent()

  var rr: RiffReader
  try:
    rr = openRiffFile(path)

    let riffChunk = rr.currentChunk
    if riffChunk.formatTypeId != FourCC_GRMM:
      raiseMapReadError(
        fmt"Not a Gridmonger map file, " &
        fmt"RIFF formatTypeId: {fourCCToCharStr(riffChunk.formatTypeId)}"
      )

    debug(fmt"Map headers OK")

    var
      mapCursor           = Cursor.none
      linksCursor         = Cursor.none
      levelListCursor     = Cursor.none
      appStateCursor      = Cursor.none
      appStateGroupCursor = Cursor.none

    # Find chunks
    if not rr.hasSubchunks:
      raiseMapReadError("RIFF chunk contains no subchunks")

    var ci = rr.enterGroup

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRMM_map:
          debug(fmt"GRMM.map group chunk found")
          if mapCursor.isSome: chunkOnlyOnceError(FourCC_GRMM_map)
          mapCursor = rr.cursor.some

        of FourCC_GRMM_lvls:
          debug(fmt"GRMM.lvls group chunk found")
          if levelListCursor.isSome: chunkOnlyOnceError(FourCC_GRMM_lvls)
          levelListCursor = rr.cursor.some

        of FourCC_GRMM_stat:
          debug(fmt"GRMM.stat group chunk found")
          if appStateGroupCursor.isSome: chunkOnlyOnceError(FourCC_GRMM_stat)
          appStateGroupCursor = rr.cursor.some

        else:
          debug(fmt"Skiping unknown top level group chunk, " &
                fmt"formatTypeID: {fourCCToCharStr(ci.formatTypeID)}")

      elif ci.kind == ckChunk:
        case ci.id
        of FourCC_GRMM_lnks:
          debug(fmt"GRMM.lnks chunk found")
          if linksCursor.isSome: chunkOnlyOnceError(FourCC_GRMM_lnks)
          linksCursor = rr.cursor.some

        of FourCC_GRMM_stat:
          debug(fmt"GRMM.stat chunk found")
          if appStateCursor.isSome: chunkOnlyOnceError(FourCC_GRMM_stat)
          appStateCursor = rr.cursor.some

        else:
          debug(fmt"Skiping unknown top level chunk, " &
                fmt"chunkId: {fourCCToCharStr(ci.id)}")

      if rr.hasNextChunk:
        ci = rr.nextChunk
      else: break

    # Check for mandatory chunks
    if mapCursor.isNone:       chunkNotFoundError(FourCC_GRMM_map)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRMM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRMM_lnks)

    # Load chunks
    rr.cursor = mapCursor.get
    let (map, version) = readMap(rr)

    rr.cursor  = levelListCursor.get
    map.levels = readLevelList(rr, version)
    map.sortLevels

    rr.cursor = linksCursor.get
    var warning = ""
    (map.links, warning) = readLinks(rr, map.levels)

    let appState = if appStateCursor.isSome:
      rr.cursor = appStateCursor.get
      readAppState_preV4(rr, map).some

    elif appStateGroupCursor.isSome:
      rr.cursor = appStateGroupCursor.get
      readAppState_V4(rr, map).some
    else:
      AppState.none

    # Level IDs start from zero when loading a map
    setNextLevelId(map.levels.len)

    result = (map, appState, warning)

  except MapReadError as e:
    logError(e)
    raise newException(MapReadError,
                       fmt"{e.msg} (at file position {rr.getFilePos})", e)
  except CatchableError as e:
    logError(e)
    raise newException(MapReadError, e.msg, e)
  finally:
    if rr != nil: rr.close

# }}}

# }}}
# {{{ Write

using rw: RiffWriter

var g_runLengthEncoder: RunLengthEncoder

# {{{ writeNotesListPaneState()
proc writeNotesListPaneState(rw; map: Map, s: AppState) =
  if s.notesListPaneState.isNone:
    return

  let nls = s.notesListPaneState.get

  rw.chunk(FourCC_GRMM_notl):
    rw.write(nls.filter.scope.uint8)

    # noteType is a bit-vector
    rw.write(cast[uint8](nls.filter.noteType))

    rw.writeWStr(nls.filter.searchTerm)
    rw.write(nls.filter.orderBy.uint8)
    rw.write(nls.linkCursor.uint8)
    rw.write(nls.viewStartY.uint32)

    for levelId in map.sortedLevelIds:
      rw.write(nls.levelSections.getOrDefault(levelId, false).uint8)

      let l = map.levels[levelId]

      # `numRegions` can be non-zero even if `regionOpts.enabled` is `false`.
      if l.regions.numRegions > 0:

        # Iterate through the regions starting from region coords (0,0)
        # (top-left corner), then go left to right, top to bottom.
        for rc in l.regionCoords:
          let r = l.regions[rc].get
          let key = (levelId, rc)
          rw.write(nls.regionSections.getOrDefault(key, false).uint8)

# }}}
# {{{ writeAppState()
proc writeAppState(rw; map: Map, s: AppState) =
  rw.listChunk(FourCC_GRMM_stat):

    # Display state
    rw.chunk(FourCC_GRMM_disp):
      rw.writeBStr(s.themeName)

      let currLevelIndex = map.sortedLevelIds.find(s.currLevelId)
      assert currLevelIndex > -1

      rw.write(s.zoomLevel.uint8)
      rw.write(currLevelIndex.uint16)
      rw.write(s.cursorRow.uint16)
      rw.write(s.cursorCol.uint16)
      rw.write(s.viewStartRow.uint16)
      rw.write(s.viewStartCol.uint16)

    # Options state
    rw.chunk(FourCC_GRMM_opts):
      rw.write(s.showCellCoords.uint8)
      rw.write(s.showToolsPane.uint8)
      rw.write(s.showCurrentNotePane.uint8)
      rw.write(s.wasdMode.uint8)
      rw.write(s.walkMode.uint8)
      # TODO
#      rw.write(s.optPasteWraparound.uint8)

    # Tools pane state
    rw.chunk(FourCC_GRMM_tool):
      rw.write(s.currFloorColor.uint8)
      rw.write(s.currSpecialWall.uint8)

    # Notes list pane state
    writeNotesListPaneState(rw, map, s)

# }}}
# {{{ writeLinks()
proc writeLinks(rw; map: Map) =
  rw.chunk(FourCC_GRMM_lnks):
    rw.write(map.links.len.uint16)

    # We map level IDs to their indices in sortedLevelIds when writing the
    # links. Because we write the levels in the order they appear in
    # sortedLevelIds, the indices will point to the correct levels.
    #
    # When loading the levels back, we assign the the first level ID 0, the
    # second ID 1, etc. (their indices as they appear in the map file) to
    # ensure the level IDs are in sync with the links.

    let levelIdToIndex = collect:
      for idx, id in map.sortedLevelIds: {id: idx}

    var sortedKeys = collect:
      for k in map.links.sources: k

    sort(sortedKeys)

    proc writeLocation(loc: Location) =
      rw.write(levelIdToIndex[loc.levelId].uint16)
      rw.write(loc.row.uint16)
      rw.write(loc.col.uint16)

    for src in sortedKeys:
      let dest = map.links.getBySrc(src).get
      writeLocation(src)
      writeLocation(dest)

# }}}
# {{{ writeCoordinateOptions()
proc writeCoordinateOptions(rw; co: CoordinateOptions) =
  rw.chunk(FourCC_GRMM_coor):
    rw.write(co.origin.uint8)
    rw.write(co.rowStyle.uint8)
    rw.write(co.columnStyle.uint8)
    rw.write(co.rowStart.int16)
    rw.write(co.columnStart.int16)

# }}}
# {{{ writeLevelRegions()
proc writeLevelRegions(rw; l: Level) =
  rw.chunk(FourCC_GRMM_regn):
    rw.write(l.regionOpts.enabled.uint8)
    rw.write(l.regionOpts.rowsPerRegion.uint16)
    rw.write(l.regionOpts.colsPerRegion.uint16)
    rw.write(l.regionOpts.perRegionCoords.uint8)

    rw.write(l.regions.numRegions.uint16)

    # `numRegions` can be non-zero even if `regionOpts.enabled` is `false`.
    # We always write regions if they are present to preserve their names and
    # notes (see `Level.regions` in `common.nim`).
    if l.regions.numRegions > 0:

      # Write regions row by row starting from region coords (0,0)
      # (top-left corner), then go left to right, top to bottom.
      for rc in l.regionCoords:
        let r = l.regions[rc].get
        rw.writeWStr(r.name)
        rw.writeWStr(r.notes)

# }}}
# # {{{ writeLevelProperties()
proc writeLevelProperties(rw; l: Level) =
  rw.chunk(FourCC_GRMM_prop):
    rw.writeWStr(l.locationName)
    rw.writeWStr(l.levelName)
    rw.write(l.elevation.int16)

    rw.write(l.rows.uint16)
    rw.write(l.cols.uint16)

    rw.write(l.overrideCoordOpts.uint8)

    rw.writeWStr(l.notes)

# }}}
# {{{ writeLevelCells()
proc writeLevelCells(rw; cells: seq[Cell]) =

  template writeLayer(field: untyped) =
    alias(e, g_runLengthEncoder)

    var allZeroes = true
    for c {.inject.} in cells:
      if field.uint8 != 0:
        allZeroes = false
        break

    if allZeroes:
      rw.write(ctZeroes.uint8)
    else:
      initRunLengthEncoder(e, cells.len)

      var compressFailed = false
      for c {.inject.} in cells:
        if not e.encode(field.uint8):
          compressFailed = true
          break
      if not e.flush:
        compressFailed = true

      let compressRatio = (e.encodedLength + 4) / cells.len
      if not compressFailed and compressRatio < 0.9:
        rw.write(ctRunLengthEncoded.uint8)
        rw.write(e.encodedLength.uint32)
        rw.write(e.buf, 0, e.encodedLength)
      else:
        rw.write(ctUncompressed.uint8)
        for c {.inject.} in cells:
          rw.write(field.uint)


  rw.chunk(FourCC_GRMM_cell):
    writeLayer: c.floor
    writeLayer: c.floorOrientation
    writeLayer: c.floorColor
    writeLayer: c.wallN
    writeLayer: c.wallW
    writeLayer: c.trail

# }}}
# {{{ writeLevelAnnotations()
proc writeLevelAnnotations(rw; l: Level) =
  rw.chunk(FourCC_GRMM_anno):
    rw.write(l.numAnnotations.uint16)

    for row, col, anno in l.allAnnotations:
      rw.write(row.uint16)
      rw.write(col.uint16)

      rw.write(anno.kind.uint8)
      case anno.kind
      of akComment: discard
      of akIndexed:
        rw.write(anno.index.uint16)
        rw.write(anno.indexColor.uint8)

      of akCustomId:
        rw.writeBStr(anno.customId)

      of akIcon:
        rw.write(anno.icon.uint8)

      of akLabel:
        rw.write(anno.labelColor.uint8)

      rw.writeWStr(anno.text)

# }}}
# {{{ writeLevel()
proc writeLevel(rw; l: Level) =
  rw.listChunk(FourCC_GRMM_lvl):
    writeLevelProperties(rw, l)
    writeCoordinateOptions(rw, l.coordOpts)
    writeLevelRegions(rw, l)
    writeLevelCells(rw, l.cellGrid.cells)
    writeLevelAnnotations(rw, l)

# }}}
# {{{ writeLevelList()
proc writeLevelList(rw; map: Map) =
  rw.listChunk(FourCC_GRMM_lvls):
    # We must write the levels in sortedLevelIds order to ensure the links
    # are in sync with the level IDs (see writeLinks()).
    for levelId in map.sortedLevelIds:
      writeLevel(rw, map.levels[levelId])

# }}}
# {{{ writeMapProperties()
proc writeMapProperties(rw; map: Map) =
  rw.chunk(FourCC_GRMM_prop):
    rw.write(CurrentMapVersion.uint16)
    rw.writeWStr(map.title)
    rw.writeWStr(map.game)
    rw.writeWStr(map.author)
    rw.writeBStr(map.creationTime)
    rw.writeWStr(map.notes)

# }}}
# {{{ writeMap()
proc writeMap(rw; map: Map) =
  rw.listChunk(FourCC_GRMM_map):
    writeMapProperties(rw, map)
    writeCoordinateOptions(rw, map.coordOpts)

# }}}
# {{{ writeMapFile*()
proc writeMapFile*(map: Map, appState: AppState, path: string) =
  initDebugIndent()

  var rw: RiffWriter
  try:
    rw = createRiffFile(path, FourCC_GRMM)

    writeMap(rw, map)
    writeLevelList(rw, map)
    writeLinks(rw, map)
    writeAppState(rw, map, appState)

  except CatchableError as e:
    logError(e)
    raise newException(MapWriteError, fmt"Error writing map file: {e.msg}", e)
  finally:
    if rw != nil: rw.close

# }}}

# }}}

# vim: et:ts=2:sw=2:fdm=marker
