import algorithm
import math
import options
import strformat
import sugar

import riff

import bitable
import common
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
    levelName = rr.readWStr()
    elevation = rr.read(int16).int
    rows = rr.read(uint16).Natural
    cols = rr.read(uint16).Natural

  result = newLevel(locationName, levelName, elevation, rows, cols)


proc readLevelData_V1(rr; numCells: Natural): seq[Cell] =
  var cells: seq[Cell]
  newSeq[Cell](cells, numCells)

  for i in 0..<numCells:
    var c: Cell
    c.floor = rr.read(uint8).Floor
    c.floorOrientation = rr.read(uint8).Orientation
    c.floorColor = rr.read(uint8).Natural
    c.wallN = rr.read(uint8).Wall
    c.wallW = rr.read(uint8).Wall
    cells[i] = c

  result = cells


proc readLevelNotes_V1(rr; l: Level) =
  let numNotes = rr.read(uint16).Natural

  for i in 0..<numNotes:
    let row = rr.read(uint16)
    let col = rr.read(uint16)

    var note = Note(kind: NoteKind(rr.read(uint8)))

    case note.kind
    of nkComment:  discard
    of nkIndexed:
      note.index = rr.read(uint16)
      note.indexColor = rr.read(uint8)

    of nkIcon:
      note.icon = rr.read(uint8)

    of nkCustomId:
      note.customId = rr.readBStr()

    of nkLabel: discard

    note.text = rr.readWStr()
    l.setNote(row, col, note)


proc readLevel(rr): Level =
  let groupChunkId = FourCC_GRDM_lvls.some
  var
    propCursor = Cursor.none
    dataCursor = Cursor.none
    noteCursor = Cursor.none

  while rr.hasNextChunk():
    let ci = rr.nextChunk()
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
  var ml = newSeq[Level]()
  while rr.hasNextChunk():
    let ci = rr.nextChunk()
    if ci.kind == ckGroup:
      case ci.formatTypeId
      of FourCC_GRDM_lvl:
        rr.enterGroup()
        ml.add(readLevel(rr))
        rr.exitGroup()
      else:
        invalidListChunkError(ci.formatTypeId, FourCC_GRDM_lvls)
    else:
      invalidChunkError(ci.id, FourCC_GRDM_lvls)
  result = ml


proc readMap(rr): Map =
  let version = rr.read(uint16).Natural
  if version > CurrentMapVersion:
    raiseMapReadError("Unsupported map file version: {h.version}")

  let name = rr.readBStr()
  result = newMap(name)


# TODO return more than just a single map
proc readMap*(filename: string): Map =
  var rr: RiffReader
  try:
    rr = openRiffFile(filename)

    let riffChunk = rr.currentChunk
    if riffChunk.formatTypeId != FourCC_GRDM:
      raiseMapReadError("Not a Gridmonger map file, " &
          fmt"RIFF formatTypeId: {fourCCToCharStr(riffChunk.formatTypeId)}")

    var
      mapCursor = Cursor.none
      linksCursor = Cursor.none
      levelListCursor = Cursor.none
      displayOptsCursor = Cursor.none

    # Find chunks
    while rr.hasNextChunk():
      let ci = rr.nextChunk()
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

        else: discard   # skip unknown top level chunks

    # Check for mandatory chunks
    if mapCursor.isNone:       chunkNotFoundError(FourCC_GRDM_map)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRDM_lnks)

    # Load chunks
    rr.cursor = mapCursor.get
    let m = readMap(rr)

    rr.cursor = levelListCursor.get
    rr.enterGroup()
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
