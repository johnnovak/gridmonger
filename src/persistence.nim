import algorithm
import math
import logging except Level
import options
import std/enumutils
import strformat
import strutils
import sugar
import unicode

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
import rle
import utils


const CurrentMapVersion = 1

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

# }}}
# {{{ Types
type
  MapReadError* = object of IOError

  CompressionType = enum
    ctUncompressed     = 0,
    ctRunLengthEncoded = 1,
    ctZeroes           = 2

  AppState* = object
    themeName*:         string

    zoomLevel*:         range[MinZoomLevel..MaxZoomLevel]
    currLevel*:         Natural
    cursorRow*:         Natural
    cursorCol*:         Natural
    viewStartRow*:      Natural
    viewStartCol*:      Natural

    optShowCellCoords*: bool
    optShowToolsPane*:  bool
    optShowNotesPane*:  bool
    optWasdMode*:       bool
    optWalkMode*:       bool

    currFloorColor*:    range[0..LevelTheme.floorBackgroundColor.high]
    currSpecialWall*:   range[0..SpecialWalls.high]

# }}}
# {{{ FourCCs
const
  FourCC_GRMM      = "GRMM"
  FourCC_GRMM_cell = "cell"
  FourCC_GRMM_coor = "coor"
  FourCC_GRMM_stat = "stat"
  FourCC_GRMM_lnks = "lnks"
  FourCC_GRMM_lvl  = "lvl "
  FourCC_GRMM_lvls = "lvls"
  FourCC_GRMM_map  = "map "
  FourCC_GRMM_anno = "anno"
  FourCC_GRMM_prop = "prop"
  FourCC_GRMM_regn = "regn"
# }}}

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
proc checkStringLength(s: string, name: string, limit: FieldLimits) =
  if s.runeLen < limit.minRuneLen or s.runeLen > limit.maxRuneLen:
    raiseMapReadError(
      fmt"The length of string '{name}' must be between {limit.minRuneLen} " &
      fmt"and {limit.maxRuneLen} UTF-8 code points, " &
      fmt"actual length: {s.runeLen}, value: {s}"
    )

# }}}
# {{{ checkValueRange()
proc checkValueRange[T: SomeInteger](v: T, name: string,
                                     min: T = 0, max: T = 0) =
  if v < min or v > max:
    raiseMapReadError(
      fmt"The value of integer '{name}' must be between {min} and {max}, " &
      fmt"actual value: {v}"
    )

proc checkValueRange[T: SomeInteger](v: T, name: string, limit: FieldLimits) =
  checkValueRange(v, name, T(limit.minInt), T(limit.maxInt))

# }}}
# {{{ checkBool()
proc checkBool(b: uint8, name: string) =
  if b > 1:
    raiseMapReadError(
      fmt"The value of boolean '{name}' must be either 0 or 1, " &
      fmt"actual value: {b}"
    )

# }}}
# {{{ checkEnum()
{.push warning[HoleEnumConv]:off.}

proc checkEnum(v: SomeInteger, name: string, E: typedesc[enum]) =
  try:
    discard E(v).symbolRank
  except IndexDefect:
    raiseMapReadError(fmt"Invalid enum value for {name}: {v}")

{.pop}

# }}}

# {{{ readLocation()
proc readLocation(rr): Location =
  result.level = rr.read(uint16).int
  result.row = rr.read(uint16)
  result.col = rr.read(uint16)

# }}}
# {{{ readAppState_v1()
proc readAppState_v1(rr; m: Map): AppState =
  debug(fmt"Reading app state...")

  let themeName = rr.readBStr()
  checkStringLength(themeName, "stat.themeName", ThemeNameLimits)

  let zoomLevel = rr.read(uint8)
  checkValueRange(zoomLevel, "stat.zoomLevel", ZoomLevelLimits)

  let maxLevelIndex = NumLevelsLimits.maxInt - 1
  let currLevel = rr.read(uint16).int
  checkValueRange(currLevel, "stat.currLevel", max=maxLevelIndex)

  let l = m.levels[currLevel]

  let cursorRow = rr.read(uint16)
  checkValueRange(cursorRow, "stat.cursorRow", max=l.rows.uint16-1)

  let cursorCol = rr.read(uint16)
  checkValueRange(cursorCol, "stat.cursorCol", max=l.cols.uint16-1)

  let viewStartRow = rr.read(uint16)
  checkValueRange(viewStartRow, "stat.viewStartRow", max=l.rows.uint16-1)

  let viewStartCol = rr.read(uint16)
  checkValueRange(viewStartCol, "stat.viewStartCol", max=l.cols.uint16-1)

  let optShowCellCoords = rr.read(uint8)
  checkBool(optShowCellCoords, "stat.optShowCellCoords")

  let optShowToolsPane = rr.read(uint8)
  checkBool(optShowToolsPane, "stat.optShowToolsPane")

  let optShowNotesPane = rr.read(uint8)
  checkBool(optShowNotesPane, "stat.optShowNotesPane")

  let optWasdMode = rr.read(uint8)
  checkBool(optWasdMode, "stat.optWasdMode")

  let optWalkMode = rr.read(uint8)
  checkBool(optWalkMode, "stat.optWalkMode")

  let currFloorColor = rr.read(uint8)
  checkValueRange(currFloorColor, "stat.currFloorColor", CellFloorColorLimits)

  let currSpecialWall = rr.read(uint8)
  checkValueRange(currSpecialWall, "stat.currSpecialWall", SpecialWallLimits)

  AppState(
    themeName:         themeName,

    zoomLevel:         zoomLevel,
    currLevel:         currLevel,
    cursorRow:         cursorRow,
    cursorCol:         cursorCol,
    viewStartRow:      viewStartRow,
    viewStartCol:      viewStartCol,

    optShowCellCoords: optShowCellCoords.bool,
    optShowToolsPane:  optShowToolsPane.bool,
    optShowNotesPane:  optShowNotesPane.bool,
    optWasdMode:       optWasdMode.bool,
    optWalkMode:       optWalkMode.bool,

    currFloorColor:    currFloorColor,
    currSpecialWall:   currSpecialWall
  )

# }}}
# {{{ readLinks_v1()
proc readLinks_v1(rr; levels: seq[Level]): Links =
  debug(fmt"Reading links...")

  var numLinks = rr.read(uint16).int
  debug(fmt"  numLinks: {numLinks}")
  checkValueRange(numLinks, "links.numLinks", NumLinksLimits)

  result = initBiTable[Location, Location](nextPowerOfTwo(numLinks))

  let maxLevelIndex = NumLevelsLimits.maxInt - 1

  while numLinks > 0:
    let src = readLocation(rr)
    debug(fmt"  src: {src}")
    checkValueRange(src.level, "lnks.srcLevel", max=maxLevelIndex)
    checkValueRange(src.row, "lnks.srcRow",    max=levels[src.level].rows-1)
    checkValueRange(src.col, "lnks.srcColumh", max=levels[src.level].cols-1)

    let dest = readLocation(rr)
    debug(fmt"  dest: {dest}")
    checkValueRange(dest.level, "lnks.destLevel", max=maxLevelIndex)
    checkValueRange(dest.row, "lnks.destRow",    max=levels[dest.level].rows-1)
    checkValueRange(dest.col, "lnks.destColumn", max=levels[dest.level].cols-1)

    result.set(src, dest)
    dec(numLinks)


# }}}
# {{{ readLevelProperties_v1()
proc readLevelProperties_v1(rr): Level =
  debug(fmt"Reading level properties...")

  let locationName = rr.readWStr()
  debug(fmt"  locationName: {locationName}")
  checkStringLength(locationName, "lvl.prop.locationName",
                    LevelLocationNameLimits)

  let levelName = rr.readWStr()
  debug(fmt"  levelName: {levelName}")
  checkStringLength(levelName, "lvl.prop.levelName", LevelNameLimits)

  let elevation = rr.read(int16).int
  debug(fmt"  elevation: {elevation}")
  checkValueRange(elevation, "lvl.prop.elevation", LevelElevationLimits)

  let numRows = rr.read(uint16)
  debug(fmt"  numRows: {numRows}")
  checkValueRange(numRows, "lvl.prop.numRows", LevelRowsLimits)

  let numColumns = rr.read(uint16)
  debug(fmt"  numColumns: {numColumns}")
  checkValueRange(numColumns, "lvl.prop.numColumns", LevelColumnsLimits)

  let overrideCoordOpts = rr.read(uint8)
  debug(fmt"  overrideCoordOpts: {overrideCoordOpts}")
  checkBool(overrideCoordOpts, "lvl.prop.overrideCoordOpts")

  let notes = rr.readWStr()
  debug(fmt"  notes: {notes}")
  checkStringLength(notes, "lvl.prop.notes", NotesLimits)

  result = newLevel(locationName, levelName, elevation, numRows, numColumns)
  result.overrideCoordOpts = overrideCoordOpts.bool
  result.notes = notes

# }}}
# {{{ readLevelCells_v1()
{.push warning[HoleEnumConv]:off.}

proc readLevelCells_v1(rr; numCells: Natural): seq[Cell] =

  template readLayer(fieldType: typedesc, field, checkField: untyped) =
    let ct = rr.read(uint8)
    checkEnum(ct, "lvl.cell.compressionType", CompressionType)

    case CompressionType(ct)
    of ctUncompressed:
      for c {.inject.} in cells.mitems:
        let data {.inject.} = rr.read(uint8)
        checkField
        field = fieldType(data)

    of ctRunLengthEncoded:
      let compressedSize = rr.read(uint32)
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
        let b = d.decode()
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

  debug(fmt"Reading level cells...")

  var cells: seq[Cell]
  newSeq[Cell](cells, numCells)

  var compressedBuf: seq[byte]

  readLayer(Floor): c.floor
  do: checkEnum(data, "lvl.cell.floor", Floor)

  readLayer(Orientation): c.floorOrientation
  do: checkEnum(data, "lvl.cell.floorOrientation", Orientation)

  readLayer(byte): c.floorColor
  do: checkValueRange(data, "lvl.cell.floorColor", CellFloorColorLimits)

  readLayer(Wall): c.wallN
  do: checkEnum(data, "lvl.cell.wallN", Wall)

  readLayer(Wall): c.wallW
  do: checkEnum(data, "lvl.cell.wallW", Wall)

  readLayer(bool): c.trail
  do: checkBool(data, "lvl.cell.trail")

  result = cells

{.pop}

# }}}
# {{{ readLevelAnnotations_v1()
proc readLevelAnnotations_v1(rr; l: Level) =
  debug(fmt"Reading level annotations...")

  let numAnnotations = rr.read(uint16).Natural
  debug(fmt"  numAnnotations: {numAnnotations}")
  checkValueRange(numAnnotations, "lvl.anno.numAnnotations",
                  NumAnnotationsLimits)

  for i in 0..<numAnnotations:
    debug(fmt"  annotation index: {i}")

    let row = rr.read(uint16)
    debug(fmt"  row: {row}")
    checkValueRange(row, "lvl.anno.row", max=l.rows.uint16-1)

    let col = rr.read(uint16)
    debug(fmt"  col: {col}")
    checkValueRange(col, "lvl.anno.col", max=l.cols.uint16-1)

    let kind = rr.read(uint8)
    debug(fmt"  kind: {kind}")
    checkEnum(kind, "lvl.anno.kind", AnnotationKind)

    var anno = Annotation(kind: AnnotationKind(kind))

    case anno.kind
    of akComment:
      discard

    of akIndexed:
      let index = rr.read(uint16)
      debug(fmt"    index: {index}")
      checkValueRange(index, "lvl.anno.index", NumAnnotationsLimits)
      anno.index = index

      let indexColor = rr.read(uint8)
      debug(fmt"    indexColor: {indexColor}")
      checkValueRange(indexColor, "lvl.anno.indexColor", NoteColorLimits)
      anno.indexColor = indexColor

    of akIcon:
      let icon = rr.read(uint8)
      debug(fmt"    icon: {icon}")
      checkValueRange(icon, "lvl.anno.icon", NoteIconLimits)
      anno.icon = icon

    of akCustomId:
      let customId = rr.readBStr()
      debug(fmt"    customId: {customId}")
      checkStringLength(customId, "lvl.anno.customId", NoteCustomIdLimits)
      anno.customId = customId

    of akLabel:
      let labelColor = rr.read(uint8)
      debug(fmt"    labelColor: {labelColor}")
      checkValueRange(labelColor, "lvl.anno.labelColor", NoteColorLimits)
      anno.labelColor = labelColor

    let text = rr.readWStr()
    debug(fmt"    text: {text}")

    let textLimits = case anno.kind
                     of akComment:  NoteTextLimits
                     of akIndexed:  NoteTextLimits
                     of akCustomId: NoteOptionalTextLimits
                     of akIcon:     NoteOptionalTextLimits
                     of akLabel:    NoteTextLimits

    checkStringLength(text, "lvl.anno.text", textLimits)

    anno.text = text
    l.setAnnotation(row, col, anno)

# }}}
# {{{ readCoordinateOptions_v1*()
proc readCoordinateOptions_v1(rr; parentChunk: string): CoordinateOptions =
  debug(fmt"Reading coordinate options...")

  let origin = rr.read(uint8)
  checkEnum(origin, fmt"${parentChunk}.coor.origin", CoordinateOrigin)

  let rowStyle = rr.read(uint8)
  checkEnum(rowStyle, fmt"${parentChunk}.coor.rowStyle", CoordinateStyle)

  let columnStyle = rr.read(uint8)
  checkEnum(columnStyle, fmt"${parentChunk}.coor.columnStyle", CoordinateStyle)

  let rowStart = rr.read(int16)
  checkValueRange(rowStart, fmt"${parentChunk}.coor.rowStart",
                  CoordRowStartLimits)

  let columnStart = rr.read(int16)
  checkValueRange(columnStart, fmt"${parentChunk}.coor.columnStart",
                  CoordColumnStartLimits)

  result = CoordinateOptions(
    origin:      origin.CoordinateOrigin,
    rowStyle:    rowStyle.CoordinateStyle,
    columnStyle: columnStyle.CoordinateStyle,
    rowStart:    rowStart,
    columnStart: columnStart
  )

# }}}
# {{{ readLevelRegions_v1*()
proc readLevelRegions_v1(rr): (RegionOptions, Regions) =
  debug(fmt"Reading level regions...")

  let enabled = rr.read(uint8)
  checkBool(enabled, "lvl.regn.enabled")

  let rowsPerRegion = rr.read(uint16)
  checkValueRange(rowsPerRegion, "lvl.regn.rowsPerRegion", RowsPerRegionLimits)

  let colsPerRegion = rr.read(uint16)
  checkValueRange(colsPerRegion, "lvl.regn.colsPerRegion",
                  ColumnsPerRegionLimits)

  let perRegionCoords = rr.read(uint8)
  checkBool(perRegionCoords, "lvl.cell.perRegionCoords")

  let regionOpts = RegionOptions(
    enabled:         enabled.bool,
    rowsPerRegion:   rowsPerRegion,
    colsPerRegion:   colsPerRegion,
    perRegionCoords: perRegionCoords.bool
  )

  debug(fmt"  Regions opts: {regionOpts}")

  let numRegions = rr.read(uint16).Natural
  debug(fmt"  Num regions: {numRegions}")

  var regions: Regions = initRegions()

  for i in 0..<numRegions:
    let row = rr.read(uint16)
    checkValueRange(row, "lvl.regn.region.row", RegionRowLimits)

    let col = rr.read(uint16)
    checkValueRange(col, "lvl.regn.region.column", RegionColumnLimits)

    let name = rr.readWStr()
    checkStringLength(name, "lvl.regn.region.name", RegionNameLimits)

    let notes = rr.readWStr()
    checkStringLength(notes, "lvl.regn.region.notes", NotesLimits)

    debug(fmt"    regionIndex: {i}, row: {row}, col: {col}, name: {name}, " &
          fmt"notes: {notes}")

    regions.setRegion(
      RegionCoords(row: row, col: col),
      Region(name: name, notes: notes)
    )

  result = (regionOpts, regions)

# }}}
# {{{ readLevel_v1()
proc readLevel_v1(rr): Level =
  debug(fmt"Reading level...")

  let groupChunkId = FourCC_GRMM_lvls.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none
    regnCursor = Cursor.none
    cellCursor = Cursor.none
    annoCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRMM_lvl}' group chunk is empty")

  var ci = rr.enterGroup()

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

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRMM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRMM_coor)
  if regnCursor.isNone: chunkNotFoundError(FourCC_GRMM_regn)
  if cellCursor.isNone: chunkNotFoundError(FourCC_GRMM_cell)

  rr.cursor = propCursor.get
  var level = readLevelProperties_v1(rr)

  rr.cursor = coorCursor.get
  level.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  rr.cursor = regnCursor.get
  (level.regionOpts, level.regions) = readLevelRegions_v1(rr)

  rr.cursor = cellCursor.get

  # +1 needed because of the south & east borders
  let numCells = (level.rows+1) * (level.cols+1)

  level.cellGrid.cells = readLevelCells_v1(rr, numCells)

  if annoCursor.isSome:
    rr.cursor = annoCursor.get
    readLevelAnnotations_v1(rr, level)

  result = level

# }}}
# {{{ readLevelList_v1()
proc readLevelList_v1(rr): seq[Level] =
  debug(fmt"Reading level list...")

  var levels = newSeq[Level]()

  if rr.hasSubChunks():
    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRMM_lvl:
          if levels.len > NumLevelsLimits.maxInt:
            raiseMapReadError(
              fmt"Map cannot contain more than {NumLevelsLimits.maxInt} levels"
            )

          levels.add(readLevel_v1(rr))
          rr.exitGroup()
        else:
          invalidListChunkError(ci.formatTypeId, FourCC_GRMM_lvls)

      else: # not group chunk
        invalidChunkError(ci.id, FourCC_GRMM_lvls)

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

  result = levels

# }}}
# {{{ readMapProperties_v1()
proc readMapProperties_v1(rr): Map =
  debug(fmt"Reading map properties...")

  let version = rr.read(uint16)
  debug(fmt"  version: {version}")
  if version > CurrentMapVersion:
    raiseMapReadError(fmt"Unsupported map file version: {version}")

  let title = rr.readWStr()
  debug(fmt"  title: {title}")
  checkStringLength(title, "map.prop.title", MapTitleLimits)

  let game = rr.readWStr()
  debug(fmt"  game: {game}")
  checkStringLength(game, "map.prop.game", MapGameLimits)

  let author = rr.readWStr()
  debug(fmt"  author: {author}")
  checkStringLength(author, "map.prop.author", MapAuthorLimits)

  let creationTime = rr.readBStr()
  debug(fmt"  creationTime: {creationTime}")
  checkStringLength(creationTime, "map.prop.creationTime",
                    MapCreationTimeLimits)

  let notes = rr.readWStr()
  debug(fmt"  notes: {notes}")
  checkStringLength(notes, "map.prop.notes", NotesLimits)

  result = newMap(title, game, author, creationTime)
  result.notes = notes

# }}}
# {{{ readMap_v1()
proc readMap_v1(rr): Map =
  debug(fmt"Reading GRMM.map chunk...")

  let groupChunkId = FourCC_GRMM_map.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRMM_map}' group chunk is empty")

  var ci = rr.enterGroup()

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

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRMM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRMM_coor)

  rr.cursor = propCursor.get
  var map = readMapProperties_v1(rr)

  rr.cursor = coorCursor.get
  map.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  result = map

# }}}
# # {{{ readMapFile*()
# TODO return display related info and info chunk data as well
proc readMapFile*(filename: string): (Map, Option[AppState]) =
  var rr: RiffReader
  try:
    rr = openRiffFile(filename)

    let riffChunk = rr.currentChunk
    if riffChunk.formatTypeId != FourCC_GRMM:
      raiseMapReadError(
        fmt"Not a Gridmonger map file, " &
        fmt"RIFF formatTypeId: {fourCCToCharStr(riffChunk.formatTypeId)}"
      )

    debug(fmt"Map headers OK")

    var
      mapCursor = Cursor.none
      linksCursor = Cursor.none
      levelListCursor = Cursor.none
      appStateCursor = Cursor.none

    # Find chunks
    if not rr.hasSubchunks():
      raiseMapReadError("RIFF chunk contains no subchunks")

    var ci = rr.enterGroup()

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

        else: discard   # skip unknown top level group chunks

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

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

    # Check for mandatory chunks
    if mapCursor.isNone:       chunkNotFoundError(FourCC_GRMM_map)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRMM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRMM_lnks)

    # Load chunks
    rr.cursor = mapCursor.get
    let m = readMap_v1(rr)

    rr.cursor = levelListCursor.get
    m.levels = readLevelList_v1(rr)
    m.refreshSortedLevelNames()

    rr.cursor = linksCursor.get
    m.links = readLinks_v1(rr, m.levels)

    if appStateCursor.isSome:
      rr.cursor = appStateCursor.get
      let appState = readAppState_v1(rr, m)
      result = (m, appState.some)
    else:
      result = (m, AppState.none)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error reading map file: {e.msg}", e)
  finally:
    if rr != nil: rr.close()

# }}}
# }}}
# {{{ Write

using rw: RiffWriter

var g_runLengthEncoder: RunLengthEncoder

# {{{ writeAppState_v1()
proc writeAppState_v1(rw; s: AppState) =
  rw.beginChunk(FourCC_GRMM_stat)

  rw.writeBStr(s.themeName)

  rw.write(s.zoomLevel.uint8)
  rw.write(s.currLevel.uint16)
  rw.write(s.cursorRow.uint16)
  rw.write(s.cursorCol.uint16)
  rw.write(s.viewStartRow.uint16)
  rw.write(s.viewStartCol.uint16)

  rw.write(s.optShowCellCoords.uint8)
  rw.write(s.optShowToolsPane.uint8)
  rw.write(s.optShowNotesPane.uint8)
  rw.write(s.optWasdMode.uint8)
  rw.write(s.optWalkMode.uint8)

  rw.write(s.currFloorColor.uint8)
  rw.write(s.currSpecialWall.uint8)

  rw.endChunk()

# }}}
# {{{ writeLinks_v1()
proc writeLinks_v1(rw; links: Links) =
  rw.beginChunk(FourCC_GRMM_lnks)
  rw.write(links.len.uint16)

  var sortedKeys = collect(newSeqOfCap(links.len)):
    for k in links.keys(): k

  sort(sortedKeys)

  proc writeLocation(loc: Location) =
    rw.write(loc.level.uint16)
    rw.write(loc.row.uint16)
    rw.write(loc.col.uint16)

  for src in sortedKeys:
    let dest = links[src].get
    writeLocation(src)
    writeLocation(dest)

  rw.endChunk()

# }}}
# {{{ writeCoordinateOptions_v1()
proc writeCoordinateOptions_v1(rw; co: CoordinateOptions) =
  rw.beginChunk(FourCC_GRMM_coor)

  rw.write(co.origin.uint8)
  rw.write(co.rowStyle.uint8)
  rw.write(co.columnStyle.uint8)
  rw.write(co.rowStart.int16)
  rw.write(co.columnStart.int16)

  rw.endChunk()

# }}}
# {{{ writeLevelRegions_v1()
proc writeLevelRegions_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRMM_regn)

  rw.write(l.regionOpts.enabled.uint8)
  rw.write(l.regionOpts.rowsPerRegion.uint16)
  rw.write(l.regionOpts.colsPerRegion.uint16)
  rw.write(l.regionOpts.perRegionCoords.uint8)

  rw.write(l.numRegions.uint16)

  for rc, r in l.allRegions:
    rw.write(rc.row.uint16)
    rw.write(rc.col.uint16)
    rw.writeWStr(r.name)
    rw.writeWStr(r.notes)

  rw.endChunk()

# }}}
# # {{{ writeLevelProperties_v1()
proc writeLevelProperties_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRMM_prop)

  rw.writeWStr(l.locationName)
  rw.writeWStr(l.levelName)
  rw.write(l.elevation.int16)

  rw.write(l.rows.uint16)
  rw.write(l.cols.uint16)

  rw.write(l.overrideCoordOpts.uint8)

  rw.writeWStr(l.notes)

  rw.endChunk()

# }}}
# {{{ writeLevelCells_v1()
proc writeLevelCells_v1(rw; cells: seq[Cell]) =

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
      if not e.flush():
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


  rw.beginChunk(FourCC_GRMM_cell)

  writeLayer: c.floor
  writeLayer: c.floorOrientation
  writeLayer: c.floorColor
  writeLayer: c.wallN
  writeLayer: c.wallW
  writeLayer: c.trail

  rw.endChunk()

# }}}
# {{{ writeLevelAnnotations_v1()
proc writeLevelAnnotations_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRMM_anno)

  rw.write(l.numAnnotations.uint16)

  for (row, col, anno) in l.allAnnotations:
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

  rw.endChunk()

# }}}
# {{{ writeLevel_v1()
proc writeLevel_v1(rw; l: Level) =
  rw.beginListChunk(FourCC_GRMM_lvl)

  writeLevelProperties_v1(rw, l)
  writeCoordinateOptions_v1(rw, l.coordOpts)
  writeLevelRegions_v1(rw, l)
  writeLevelCells_v1(rw, l.cellGrid.cells)
  writeLevelAnnotations_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeLevelList_v1()
proc writeLevelList_v1(rw; levels: seq[Level]) =
  rw.beginListChunk(FourCC_GRMM_lvls)

  for l in levels:
    writeLevel_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeMapProperties_v1()
proc writeMapProperties_v1(rw; m: Map) =
  rw.beginChunk(FourCC_GRMM_prop)

  rw.write(CurrentMapVersion.uint16)
  rw.writeWStr(m.title)
  rw.writeWStr(m.game)
  rw.writeWStr(m.author)
  rw.writeBStr(m.creationTime)
  rw.writeWStr(m.notes)

  rw.endChunk()

# }}}
# {{{ writeMap_v1()
proc writeMap_v1(rw; m: Map) =
  rw.beginListChunk(FourCC_GRMM_map)

  writeMapProperties_v1(rw, m)
  writeCoordinateOptions_v1(rw, m.coordOpts)

  rw.endChunk()

# }}}
# {{{ writeMapFile*()
proc writeMapFile*(m: Map, appState: AppState, filename: string) =
  var rw: RiffWriter
  try:
    rw = createRiffFile(filename, FourCC_GRMM)

    writeMap_v1(rw, m)
    writeLevelList_v1(rw, m.levels)
    writeLinks_v1(rw, m.links)
    writeAppState_v1(rw, appState)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file: {e.msg}", e)
  finally:
    if rw != nil: rw.close()

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
