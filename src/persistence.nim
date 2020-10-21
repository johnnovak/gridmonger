import algorithm
import math
import options
import strformat
import strutils
import sugar

import riff

import bitable
import common
import icons
import level
import map


# TODO use app version instead?
const CurrentMapVersion = 1

const
  FourCC_GRDM          = "GRMM"
  FourCC_GRDM_map      = "map "
  FourCC_GRDM_lnks     = "lnks"
  FourCC_GRDM_lvls     = "lvls"
  FourCC_GRDM_lvl      = "lvl "
  FourCC_GRDM_lvl_prop = "prop"
  FourCC_GRDM_lvl_cell = "cell"
  FourCC_GRDM_lvl_note = "note"
  FourCC_GRDM_disp     = "disp"


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
# {{{ V1

# TODO move into nim-riff
proc appendInGroupChunkMsg(msg: string, groupChunkId: Option[string]): string =
  if groupChunkId.isSome:
    msg & fmt" inside a '{groupChunkId.get}' group chunk"
  else: msg

proc chunkOnlyOnceError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"'{chunkId}' chunk can only appear once"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

proc chunkNotFoundError(chunkId: string,
                        groupChunkId: Option[string] = string.none) =
  var msg = fmt"Mandatory '{chunkId}' chunk not found"
  msg = appendInGroupChunkMsg(msg, groupChunkId)
  raiseMapReadError(msg)

proc invalidChunkError(chunkId, groupChunkId: string) =
  var msg = fmt"'{chunkId}' chunk is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)

proc invalidListChunkError(formatTypeId, groupChunkId: string) =
  var msg = fmt"'LIST' chunk with format type '{formatTypeId}' is not allowed"
  msg = appendInGroupChunkMsg(msg, groupChunkId.some)
  raiseMapReadError(msg)


proc checkStringLength(s: string, name: string, minLen, maxLen: int) =
  if s.len < minLen or s.len > maxLen:
    raiseMapReadError(
      fmt"The length of {name} must be between {minLen} and " &
      fmt"{maxLen} bytes, actual length: {s.len}, value: {s}"
    )

proc checkValueRange(v: SomeInteger, name: string,
                     minVal, maxVal: SomeInteger) =
  if v < minVal or v > maxVal:
    raiseMapReadError(
      fmt"The value of {name} must be between {minVal} and " &
      fmt"{maxVal}, actual value: {v}"
    )

proc checkEnum(v: SomeInteger, name: string, E: typedesc[enum]) =
  var valid: bool
  try:
    let ev = $E(v)
    valid = not ev.contains("invalid data")
  except RangeError:
    valid = false

  if not valid:
    raiseMapReadError(fmt"Invalid enum value for {name}: {v}")


using rr: RiffReader

proc readDisplayOptions(rr): MapDisplayOptions =
  discard


proc readLinks(rr): BiTable[Location, Location] =
  var numLinks = rr.read(uint16).int

  proc readLocation(): Location =
    result.level = rr.read(uint16).int
    result.row = rr.read(uint16).Natural
    result.col = rr.read(uint16).Natural

  result = initBiTable[Location, Location](nextPowerOfTwo(numLinks))
  while numLinks > 0:
    let src = readLocation()
    let dest = readLocation()
    result[src] = dest
    dec(numLinks)


proc readLevelProperties_V1(rr): Level =
  let
    locationName = rr.readWStr()
    levelName    = rr.readWStr()
    elevation    = rr.read(int16).int
    numRows      = rr.read(uint16).Natural
    numColumns   = rr.read(uint16).Natural

  checkStringLength(locationName, "lvl.prop.locationName",
                    LevelLocationNameMinLen, LevelLocationNameMaxLen)

  checkStringLength(levelName, "lvl.prop.levelName",
                    LevelNameMinLen, LevelNameMaxLen)

  checkValueRange(elevation, "lvl.prop.elevation",
                  LevelElevationMin, LevelElevationMax)

  checkValueRange(numRows, "lvl.prop.numRows",
                  LevelNumRowsMin, LevelNumRowsMax)

  checkValueRange(numColumns, "lvl.prop.numColumns",
                  LevelNumColumnsMin, LevelNumColumnsMax)

  result = newLevel(locationName, levelName, elevation, numRows, numColumns)


proc readLevelData_V1(rr; numCells: Natural): seq[Cell] =
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
      floorColor: floorColor.Natural,
      wallN: wallN.Wall,
      wallW: wallW.Wall
    )

  result = cells


proc readLevelNotes_V1(rr; l: Level) =
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


proc readLevel(rr): Level =
  let groupChunkId = FourCC_GRDM_lvls.some
  var
    propCursor = Cursor.none
    dataCursor = Cursor.none
    noteCursor = Cursor.none

  if not rr.hasSubChunks():
    raiseMapReadError(fmt"'{FourCC_GRDM_lvl}' group chunk is empty")

  var ci = rr.enterGroup()

  while true:
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_lvl_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_lvl_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_lvl_cell:
        if dataCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_lvl_cell, groupChunkId)
        dataCursor = rr.cursor.some

      of FourCC_GRDM_lvl_note:
        if noteCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_lvl_note, groupChunkId)
        noteCursor = rr.cursor.some
      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)
    else:
      invalidChunkError(ci.id, groupChunkId.get)

    if rr.hasNextChunk():
      ci = rr.nextChunk()
    else: break

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvl_prop)
  if dataCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvl_cell)

  rr.cursor = propCursor.get
  var level = readLevelProperties_V1(rr)

  rr.cursor = dataCursor.get

  # because of the South & East borders
  let numCells = (level.rows+1) * (level.cols+1)

  level.cellGrid.cells = readLevelData_V1(rr, numCells)

  if noteCursor.isSome:
    rr.cursor = noteCursor.get
    readLevelNotes_V1(rr, level)

  result = level


proc readLevelList(rr): seq[Level] =
  var levels = newSeq[Level]()

  if rr.hasSubChunks():
    var ci = rr.enterGroup()

    while true:
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_GRDM_lvl:
          if levels.len == NumLevelsMax:
            raiseMapReadError(fmt"Map contains more than {NumLevelsMax} levels")

          levels.add(readLevel(rr))
          rr.exitGroup()
        else:
          invalidListChunkError(ci.formatTypeId, FourCC_GRDM_lvls)
      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)

      if rr.hasNextChunk():
        ci = rr.nextChunk()
      else: break

  result = levels


proc readMap(rr): Map =
  let version = rr.read(uint16).Natural
  if version > CurrentMapVersion:
    raiseMapReadError(fmt"Unsupported map file version: {version}")

  let name = rr.readBStr()
  checkStringLength(name, "map.name", MapNameMinLen, MapNameMaxLen)

  result = newMap(name)


# TODO return more than just a single map
proc readMap*(filename: string): Map =
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

        of FourCC_GRDM_lvls:
          if levelListCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lvls)
          levelListCursor = rr.cursor.some

        else: discard   # skip unknown top level group chunks

      elif ci.kind == ckChunk:
        case ci.id
        of FourCC_GRDM_map:
          if mapCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_map)
          mapCursor = rr.cursor.some

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
    let m = readMap(rr)

    rr.cursor = levelListCursor.get
    m.levels = readLevelList(rr)
    m.refreshSortedLevelNames()

    rr.cursor = linksCursor.get
    m.links = readLinks(rr)

    if displayOptsCursor.isSome:
      rr.cursor = displayOptsCursor.get
      discard readDisplayOptions(rr)

    result = m

  except MapReadError as e:
    echo getStackTrace(e)
    raise e
  except CatchableError as e:
    echo getStackTrace(e)
    raise newException(MapReadError, fmt"Error reading map file: {e.msg}", e)
  finally:
    if rr != nil:
      rr.close()

# }}}
# }}}

# {{{ Write

using rw: RiffWriter

proc writeDisplayOptions(rw; opts: MapDisplayOptions) =
  rw.beginChunk(FourCC_GRDM_disp)

  rw.write(opts.currLevel.uint16)
  rw.write(opts.zoomLevel.uint8)
  rw.write(opts.cursorRow.uint16)
  rw.write(opts.cursorCol.uint16)
  rw.write(opts.viewStartRow.uint16)
  rw.write(opts.viewStartCol.uint16)

  rw.endChunk()


proc writeLinks(rw; links: BiTable[Location, Location]) =
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


proc writeLevelProperties(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_lvl_prop)
  rw.writeWStr(l.locationName)
  rw.writeWStr(l.levelName)
  rw.write(l.elevation.int16)
  rw.write(l.rows.uint16)
  rw.write(l.cols.uint16)
  rw.endChunk()

proc writeLevelCells(rw; cells: seq[Cell]) =
  rw.beginChunk(FourCC_GRDM_lvl_cell)
  for c in cells:
    rw.write(c.floor.uint8)
    rw.write(c.floorOrientation.uint8)
    rw.write(c.floorColor.uint8)
    rw.write(c.wallN.uint8)
    rw.write(c.wallW.uint8)
  rw.endChunk()


proc writeLevelNotes(rw; l: Level) =
  rw.beginChunk(FourCC_GRDM_lvl_note)
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


proc writeLevel(rw; l: Level) =
  rw.beginListChunk(FourCC_GRDM_lvl)
  rw.writeLevelProperties(l)
  rw.writeLevelCells(l.cellGrid.cells)
  rw.writeLevelNotes(l)
  rw.endChunk()

proc writeLevelList(rw; levels: seq[Level]) =
  rw.beginListChunk(FourCC_GRDM_lvls)
  for l in levels:
    writeLevel(rw, l)
  rw.endChunk()

proc writeMap(rw; m: Map) =
  rw.beginChunk(FourCC_GRDM_map)
  rw.write(CurrentMapVersion.uint16)
  rw.writeBStr(m.name)
  rw.endChunk()


proc writeMap*(m: Map, opts: MapDisplayOptions, filename: string) =
  var rw: RiffWriter
  try:
    rw = createRiffFile(filename, FourCC_GRDM)

    writeMap(rw, m)
    writeLevelList(rw, m.levels)
    writeLinks(rw, m.links)
    writeDisplayOptions(rw, opts)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file: {e.msg}", e)
  finally:
    rw.close()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
