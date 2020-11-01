import algorithm
import math
import options
import strformat
import strutils
import sugar
import std/monotimes

import riff

import bitable
import common
import icons
import level
import map
import utils


# TODO use app version instead?
const CurrentMapVersion = 1

# {{{ Field constraints
const
  MapNameMinLen* = 1
  MapNameMaxLen* = 100

  NumLevelsMax* = 999
  LevelLocationNameMinLen* = 1
  LevelLocationNameMaxLen* = 100
  LevelNameMinLen* = 0
  LevelNameMaxLen* = 100
  LevelElevationMin* = -200
  LevelElevationMax* = 200
  LevelNumRowsMin* = 1
  LevelNumRowsMax* = 6666
  LevelNumColumnsMin* = 1
  LevelNumColumnsMax* = 6666

  RegionNameMaxLen* = 100
  RegionColumnsMin* = 2
  RegionColumnsMax* = LevelNumColumnsMax
  RegionRowsMin* = 2
  RegionRowsMax* = LevelNumRowsMax

  CellFloorColorMin* = 0
  CellFloorColorMax* = 8

  NumNotesMax* = 10_000
  NoteTextMaxLen* = 400
  NoteCustomIdMinLen* = 1
  NoteCustomIdMaxLen* = 2
  NoteColorMax* = 3

  NumLinksMax* = 10_000

  ThemeNameMin* = 1
  ThemeNameMax* = 255

  ZoomLevelMin* = 1
  ZoomLevelMax* = 20

# }}}

const
  FourCC_GRDM      = "GRMM"
  FourCC_GRDM_cell = "cell"
  FourCC_GRDM_coor = "coor"
  FourCC_GRDM_disp = "disp"
  FourCC_GRDM_lnks = "lnks"
  FourCC_GRDM_lvl  = "lvl "
  FourCC_GRDM_lvls = "lvls"
  FourCC_GRDM_map  = "map "
  FourCC_GRDM_note = "note"
  FourCC_GRDM_prop = "prop"
  FourCC_GRDM_regn = "regn"


type MapReadError* = object of IOError

proc raiseMapReadError(s: string) =
  raise newException(MapReadError, s)


type
  MapDisplayOptions* = object
    currLevel*:       Natural
    zoomLevel*:       Natural
    cursorRow*:       Natural
    cursorCol*:       Natural
    viewStartRow*:    Natural
    viewStartCol*:    Natural


# {{{ Read
# TODO move utils into nim-riff?
# {{{ appendInGroupChunkMsg()
proc appendInGroupChunkMsg(msg: string, groupChunkId: Option[string]): string =
  if groupChunkId.isSome:
    msg & fmt" inside a '{groupChunkId.get}' group chunk"
  else: msg

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
proc checkStringLength(s: string, name: string, minLen, maxLen: int) =
  if s.len < minLen or s.len > maxLen:
    raiseMapReadError(
      fmt"The length of {name} must be between {minLen} and " &
      fmt"{maxLen} bytes, actual length: {s.len}, value: {s}"
    )

# }}}
# {{{ checkValueRange()
proc checkValueRange(v: SomeInteger, name: string,
                     minVal, maxVal: SomeInteger) =
  if v < minVal or v > maxVal:
    raiseMapReadError(
      fmt"The value of {name} must be between {minVal} and " &
      fmt"{maxVal}, actual value: {v}"
    )

# }}}
# {{{ checkEnum()
proc checkEnum(v: SomeInteger, name: string, E: typedesc[enum]) =
  var valid: bool
  try:
    let ev = $E(v)
    valid = not ev.contains("invalid data")
  except RangeDefect:
    valid = false

  if not valid:
    raiseMapReadError(fmt"Invalid enum value for {name}: {v}")

# }}}

using rr: RiffReader

# {{{ readLocation()
proc readLocation(rr): Location =
  result.level = rr.read(uint16).int
  result.row = rr.read(uint16)
  result.col = rr.read(uint16)

# }}}
# {{{ readDisplayOptions_v1()
proc readDisplayOptions_v1(rr): MapDisplayOptions =
  # TODO
  discard


# }}}
# {{{ readLinks_v1()
proc readLinks_v1(rr): BiTable[Location, Location] =
  var numLinks = rr.read(uint16).int

  result = initBiTable[Location, Location](nextPowerOfTwo(numLinks))
  while numLinks > 0:
    let src = readLocation(rr)
    let dest = readLocation(rr)
    result[src] = dest
    dec(numLinks)

# }}}
# {{{ readLevelProperties_v1()
proc readLevelProperties_v1(rr): Level =
  let locationName = rr.readWStr()
  checkStringLength(locationName, "lvl.prop.locationName",
                    LevelLocationNameMinLen, LevelLocationNameMaxLen)

  let levelName = rr.readWStr()
  checkStringLength(levelName, "lvl.prop.levelName",
                    LevelNameMinLen, LevelNameMaxLen)

  let elevation = rr.read(int16).int
  checkValueRange(elevation, "lvl.prop.elevation",
                  LevelElevationMin, LevelElevationMax)

  let numRows = rr.read(uint16)
  checkValueRange(numRows, "lvl.prop.numRows",
                  LevelNumRowsMin, LevelNumRowsMax)

  let numColumns = rr.read(uint16)
  checkValueRange(numColumns, "lvl.prop.numColumns",
                  LevelNumColumnsMin, LevelNumColumnsMax)

  let overrideCoordOpts = rr.read(uint8).bool

  result = newLevel(locationName, levelName, elevation, numRows, numColumns)
  result.overrideCoordOpts = overrideCoordOpts

# }}}
# {{{ readLevelData_v1()
proc readLevelData_v1(rr; numCells: Natural): seq[Cell] =
  var cells: seq[Cell]
  newSeq[Cell](cells, numCells)

  for i in 0..<numCells:
    let floor = rr.read(uint8)
    checkEnum(floor, "lvl.cell.floor", Floor)

    let floorOrientation = rr.read(uint8)
    checkEnum(floorOrientation, "lvl.cell.floorOrientation", Orientation)

    let floorColor = rr.read(uint8)
    checkValueRange(floorColor, "lvl.cell.floorColor",
                    CellFloorColorMin, CellFloorColorMax)

    let wallN = rr.read(uint8)
    checkEnum(wallN, "lvl.cell.wallN", Wall)

    let wallW = rr.read(uint8)
    checkEnum(wallW, "lvl.cell.wallW", Wall)

    cells[i] = Cell(
      floor: floor.Floor,
      floorOrientation: floorOrientation.Orientation,
      floorColor: floorColor,
      wallN: wallN.Wall,
      wallW: wallW.Wall
    )

  result = cells

# }}}
# {{{ readLevelNotes_v1()
proc readLevelNotes_v1(rr; l: Level) =
  let numNotes = rr.read(uint16).Natural
  checkValueRange(numNotes, "lvl.note.numNotes", 0, NumNotesMax)

  for i in 0..<numNotes:
    let row = rr.read(uint16)
    checkValueRange(row, "lvl.note.row", 0, l.rows.uint16-1)

    let col = rr.read(uint16)
    checkValueRange(col, "lvl.note.col", 0, l.cols.uint16-1)

    let kind = rr.read(uint8)
    checkEnum(kind, "lvl.note.kind", NoteKind)

    var note = Note(kind: NoteKind(kind))

    case note.kind
    of nkComment:
      discard

    of nkIndexed:
      let index = rr.read(uint16)
      checkValueRange(index, "lvl.note.index", 0, NumNotesMax)
      note.index = index

      let indexColor = rr.read(uint8)
      checkValueRange(indexColor, "lvl.note.color", 0, NoteColorMax)
      note.indexColor = indexColor

    of nkIcon:
      let icon = rr.read(uint8)
      checkValueRange(icon, "lvl.note.icon", 0, NoteIconMax)
      note.icon = icon

    of nkCustomId:
      let customId = rr.readBStr()
      checkStringLength(customId, "lvl.note.customId",
                        NoteCustomIdMinLen, NoteCustomIdMaxLen)
      note.customId = customId

    of nkLabel: discard

    let text = rr.readWStr()
    let textMinLen = if note.kind in {nkComment, nkLabel}: 1 else: 0
    checkStringLength(text, "lvl.note.text", textMinLen, NoteTextMaxLen)

    note.text = text
    l.setNote(row, col, note)

# }}}
# {{{ readCoordinateOptions_v1*()
proc readCoordinateOptions_v1(rr; parentChunk: string): CoordinateOptions =
  let origin = rr.read(uint8)
  checkEnum(origin, fmt"${parentChunk}.coor.origin", CoordinateOrigin)

  let rowStyle = rr.read(uint8)
  checkEnum(rowStyle, fmt"${parentChunk}.coor.rowStyle", CoordinateStyle)

  let columnStyle = rr.read(uint8)
  checkEnum(columnStyle, fmt"${parentChunk}.coor.columnStyle", CoordinateStyle)

  let rowStart = rr.read(int16)
  let columnStart = rr.read(int16)

  result = CoordinateOptions(
    origin:      origin.CoordinateOrigin,
    rowStyle:    rowStyle.CoordinateStyle,
    columnStyle: columnStyle.CoordinateStyle,
    rowStart:    rowStart,
    columnStart: columnStart
  )

# }}}
# {{{ readRegions_v1*()
proc readRegions_v1(rr): (RegionOptions, seq[string]) =
  let enableRegions = rr.read(uint8).bool

  let regionColumns = rr.read(uint16)
  checkValueRange(regionColumns, "lvl.regn.regionColumns",
                  RegionColumnsMin, RegionColumnsMax)

  let regionRows = rr.read(uint16)
  checkValueRange(regionRows, "lvl.regn.regionRows",
                  RegionRowsMin, RegionRowsMax)

  let perRegionCoords = rr.read(uint8).bool

  let regionOpts = RegionOptions(
    enableRegions:   enableRegions,
    regionColumns:   regionColumns,
    regionRows:      regionRows,
    perRegionCoords: perRegionCoords
  )

  let numRegions = rr.read(uint16).Natural

  var regionNames: seq[string] = @[]
  for i in 0..<numRegions:
    let name = rr.readBStr()
    checkStringLength(name, "lvl.regn.regionName", 0, RegionNameMaxLen)
    regionNames.add(name)

  result = (regionOpts, regionNames)

# }}}
# {{{ readLevel_v1()
proc readLevel_v1(rr): Level =
  let groupChunkId = FourCC_GRDM_lvls.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none
    regnCursor = Cursor.none
    cellCursor = Cursor.none
    noteCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRDM_lvl}' group chunk is empty")

  var ci = rr.enterGroup()

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      of FourCC_GRDM_regn:
        if regnCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_regn, groupChunkId)
        regnCursor = rr.cursor.some

      of FourCC_GRDM_cell:
        if cellCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_cell, groupChunkId)
        cellCursor = rr.cursor.some

      of FourCC_GRDM_note:
        if noteCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_note, groupChunkId)
        noteCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRDM_coor)
  if regnCursor.isNone: chunkNotFoundError(FourCC_GRDM_regn)
  if cellCursor.isNone: chunkNotFoundError(FourCC_GRDM_cell)

  rr.cursor = propCursor.get
  var level = readLevelProperties_v1(rr)

  rr.cursor = coorCursor.get
  level.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  rr.cursor = regnCursor.get
  (level.regionOpts, level.regionNames) = readRegions_v1(rr)

  rr.cursor = cellCursor.get

  # +1 needed because of the south & east borders
  let numCells = (level.rows+1) * (level.cols+1)

  level.cellGrid.cells = readLevelData_v1(rr, numCells)

  if noteCursor.isSome:
    rr.cursor = noteCursor.get
    readLevelNotes_v1(rr, level)

  result = level

# }}}
# {{{ readLevelList_v1()
proc readLevelList_v1(rr): seq[Level] =
  var levels = newSeq[Level]()

  if rr.hasSubChunks():
    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRDM_lvl:
          if levels.len == NumLevelsMax:
            raiseMapReadError(fmt"Map contains more than {NumLevelsMax} levels")

          levels.add(readLevel_v1(rr))
          rr.exitGroup()
        else:
          invalidListChunkError(ci.formatTypeId, FourCC_GRDM_lvls)

      else: # not group chunk
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

  result = levels

# }}}
# {{{ readMapProperties_v1()
proc readMapProperties_v1(rr): Map =
  # TODO is inside Map the best place for this? or introduce a header chunk?
  let version = rr.read(uint16)
  if version > CurrentMapVersion:
    raiseMapReadError(fmt"Unsupported map file version: {version}")

  let name = rr.readBStr()
  checkStringLength(name, "map.prop.name", MapNameMinLen, MapNameMaxLen)

  result = newMap(name)

# }}}
# {{{ readMap_v1()
proc readMap_v1(rr): Map =
  let groupChunkId = FourCC_GRDM_map.some
  var
    propCursor = Cursor.none
    coorCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRDM_map}' group chunk is empty")

  var ci = rr.enterGroup()

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_coor:
        if coorCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_coor, groupChunkId)
        coorCursor = rr.cursor.some

      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

    else: # group chunk
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_prop)
  if coorCursor.isNone: chunkNotFoundError(FourCC_GRDM_coor)

  rr.cursor = propCursor.get
  var map = readMapProperties_v1(rr)

  rr.cursor = coorCursor.get
  map.coordOpts = readCoordinateOptions_v1(rr, groupChunkId.get)

  result = map

# }}}
# # {{{ readMapFile*()
# TODO return display related info and info chunk data as well
proc readMapFile*(filename: string): Map =
  let t0 = getMonoTime()

  var rr: RiffReader
  try:
    rr = openRiffFile(filename)

    let riffChunk = rr.currentChunk
    if riffChunk.formatTypeId != FourCC_GRDM:
      raiseMapReadError(
        fmt"Not a Gridmonger map file, " &
        fmt"RIFF formatTypeId: {fourCCToCharStr(riffChunk.formatTypeId)}"
      )

    var
      mapCursor = Cursor.none
      linksCursor = Cursor.none
      levelListCursor = Cursor.none
      displayOptsCursor = Cursor.none

    # Find chunks
    if not rr.hasSubchunks():
      raiseMapReadError("RIFF chunk contains no subchunks")

    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_INFO:
          discard  # TODO

        of FourCC_GRDM_map:
          if mapCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_map)
          mapCursor = rr.cursor.some

        of FourCC_GRDM_lvls:
          if levelListCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lvls)
          levelListCursor = rr.cursor.some

        else: discard   # skip unknown top level group chunks

      elif ci.kind == ckChunk:
        case ci.id

        of FourCC_GRDM_lnks:
          if linksCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lnks)
          linksCursor = rr.cursor.some

        of FourCC_GRDM_disp:
          if displayOptsCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_disp)
          displayOptsCursor = rr.cursor.some

        else:
          echo fmt"Skiping unknown top level chunk, " &
               fmt"chunkId: {fourCCToCharStr(ci.id)}"

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

    # Check for mandatory chunks
    if mapCursor.isNone:       chunkNotFoundError(FourCC_GRDM_map)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRDM_lnks)

    # Load chunks
    rr.cursor = mapCursor.get
    let m = readMap_v1(rr)

    rr.cursor = levelListCursor.get
    m.levels = readLevelList_v1(rr)
    m.refreshSortedLevelNames()

    rr.cursor = linksCursor.get
    m.links = readLinks_v1(rr)

    if displayOptsCursor.isSome:
      rr.cursor = displayOptsCursor.get
      discard readDisplayOptions_v1(rr)

    result = m

  except MapReadError as e:
    echo getStackTrace(e)
    raise e
  except CatchableError as e:
    echo getStackTrace(e)
    raise newException(MapReadError, fmt"Error reading map file: {e.msg}", e)
  finally:
    if rr != nil: rr.close()

    let dt = getMonoTime() - t0
    # TODO log this
    echo "Map loaded in {nanosToFloatMillis(dt.ticks):.4f} ms"

# }}}
# }}}

# {{{ Write

using rw: RiffWriter

# {{{ writeDisplayOptions_v1()
proc writeDisplayOptions_v1(rw; opts: MapDisplayOptions) =
  rw.beginChunk(FourCC_GRDM_disp)

  rw.write(opts.currLevel.uint16)
  rw.write(opts.zoomLevel.uint8)
  rw.write(opts.cursorRow.uint16)
  rw.write(opts.cursorCol.uint16)
  rw.write(opts.viewStartRow.uint16)
  rw.write(opts.viewStartCol.uint16)

  rw.endChunk()

# }}}
# {{{ writeLinks_v1()
proc writeLinks_v1(rw; links: BiTable[Location, Location]) =
  rw.beginChunk(FourCC_GRDM_lnks)
  rw.write(links.len.uint16)

  var sortedKeys = collect(newSeqOfCap(links.len)):
    for k in links.keys(): k

  sort(sortedKeys)

  proc writeLocation(loc: Location) =
    rw.write(loc.level.uint16)
    rw.write(loc.row.uint16)
    rw.write(loc.col.uint16)

  for src in sortedKeys:
    let dest = links[src]
    writeLocation(src)
    writeLocation(dest)

  rw.endChunk()

# }}}
# {{{ writeCoordinateOptions_v1()
proc writeCoordinateOptions_v1(rw; co: CoordinateOptions) =
  rw.beginChunk(FourCC_GRDM_coor)

  rw.write(co.origin.uint8)
  rw.write(co.rowStyle.uint8)
  rw.write(co.columnStyle.uint8)
  rw.write(co.rowStart.int16)
  rw.write(co.columnStart.int16)

  rw.endChunk()

# }}}
# {{{ writeRegions_v1()
proc writeRegions_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_regn)

  rw.write(l.regionOpts.enableRegions.uint8)
  rw.write(l.regionOpts.regionColumns.uint16)
  rw.write(l.regionOpts.regionRows.uint16)
  rw.write(l.regionOpts.perRegionCoords.uint8)

  rw.write(l.regionNames.len.uint16)
  for name in l.regionNames:
    rw.writeBStr(name)

  rw.endChunk()

# }}}
# # {{{ writeLevelProperties_v1()
proc writeLevelProperties_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_prop)

  rw.writeWStr(l.locationName)
  rw.writeWStr(l.levelName)
  rw.write(l.elevation.int16)

  rw.write(l.rows.uint16)
  rw.write(l.cols.uint16)

  rw.write(l.overrideCoordOpts.uint8)

  rw.endChunk()

# }}}
# {{{ writeLevelCells_v1()
proc writeLevelCells_v1(rw; cells: seq[Cell]) =
  rw.beginChunk(FourCC_GRDM_cell)

  for c in cells:
    rw.write(c.floor.uint8)
    rw.write(c.floorOrientation.uint8)
    rw.write(c.floorColor.uint8)
    rw.write(c.wallN.uint8)
    rw.write(c.wallW.uint8)

  rw.endChunk()

# }}}
# {{{ writeLevelNotes_v1()
proc writeLevelNotes_v1(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_note)

  rw.write(l.numNotes.uint16)

  for (row, col, note) in l.allNotes:
    rw.write(row.uint16)
    rw.write(col.uint16)

    rw.write(note.kind.uint8)
    case note.kind
    of nkComment: discard
    of nkIndexed:
      rw.write(note.index.uint16)
      rw.write(note.indexColor.uint8)

    of nkCustomId:
      rw.writeBStr(note.customId)

    of nkIcon:
      rw.write(note.icon.uint8)

    of nkLabel: discard

    rw.writeWStr(note.text)

  rw.endChunk()

# }}}
# {{{ writeLevel_v1()
proc writeLevel_v1(rw; l: Level) =
  rw.beginListChunk(FourCC_GRDM_lvl)

  writeLevelProperties_v1(rw, l)
  writeCoordinateOptions_v1(rw, l.coordOpts)
  writeRegions_v1(rw, l)
  writeLevelCells_v1(rw, l.cellGrid.cells)
  writeLevelNotes_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeLevelList_v1()
proc writeLevelList_v1(rw; levels: seq[Level]) =
  rw.beginListChunk(FourCC_GRDM_lvls)

  for l in levels:
    writeLevel_v1(rw, l)

  rw.endChunk()

# }}}
# {{{ writeMapProperties_v1()
proc writeMapProperties_v1(rw; m: Map) =
  rw.beginChunk(FourCC_GRDM_prop)

  rw.write(CurrentMapVersion.uint16)
  rw.writeBStr(m.name)

  rw.endChunk()

# }}}
# {{{ writeMap_v1()
proc writeMap_v1(rw; m: Map) =
  rw.beginListChunk(FourCC_GRDM_map)

  writeMapProperties_v1(rw, m)
  writeCoordinateOptions_v1(rw, m.coordOpts)

  rw.endChunk()

# }}}
# {{{ writeMapFile*()
proc writeMapFile*(m: Map, opts: MapDisplayOptions, filename: string) =
  var rw: RiffWriter
  try:
    rw = createRiffFile(filename, FourCC_GRDM)

    writeMap_v1(rw, m)
    writeLevelList_v1(rw, m.levels)
    writeLinks_v1(rw, m.links)
    writeDisplayOptions_v1(rw, opts)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file: {e.msg}", e)
  finally:
    if rw != nil: rw.close()

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
