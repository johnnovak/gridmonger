import algorithm
import math
import options
import strformat

import riff

import bitable
import common
import level
import map


# TODO use app version instead?
const CurrentMapVersion = 1

const
  FourCC_GRDM          = "GRMM"
  FourCC_GRDM_maph     = "maph"
  FourCC_GRDM_lnks     = "lnks"
  FourCC_GRDM_lvls     = "lvls"
  FourCC_GRDM_lvl      = "lvl "
  FourCC_GRDM_lvl_prop = "prop"
  FourCC_GRDM_lvl_cell = "cell"
  FourCC_GRDM_lvl_note = "note"
  FourCC_GRDM_them     = "them"

type
  MapHeaderInfo = object
    version: Natural


type MapReadError* = object of IOError

proc raiseMapReadError(s: string) =
  raise newException(MapReadError, s)

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


proc readLevelProperties_V1(rr): (string, int, Natural, Natural) =
  let
    name  = rr.readWStr()
    level = rr.read(int16).int
    rows  = rr.read(uint16).Natural
    cols  = rr.read(uint16).Natural
  result = (name, level, rows, cols)


proc readLevelData_V1(rr; numCells: Natural): seq[Cell] =
  var cells = newSeqOfCap[Cell](numCells)
  for i in 0..<numCells:
    var c: Cell
    # TODO
    #c.floor = mapFloor(rr.read(uint8)).Floor
    c.floor = rr.read(uint8).Floor
    c.floorOrientation = rr.read(uint8).Orientation
    # TODO
    #c.wallN = mapWall(rr.read(uint8)).Wall
    #c.wallW = mapWall(rr.read(uint8)).Wall
    c.wallN = rr.read(uint8).Wall
    c.wallW = rr.read(uint8).Wall
    cells.add(c)
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

    note.text = rr.readWStr()
    l.setNote(row, col, note)


proc readLevel(rr): Level =
  let groupChunkId = FourCC_GRDM_lvls.some
  var
    propCursor = Cursor.none
    dataCursor = Cursor.none
    annoCursor = Cursor.none

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
        if annoCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_lvl_note, groupChunkId)
        annoCursor = rr.cursor.some
      else:
        invalidChunkError(ci.id, FourCC_GRDM_lvls)
    else:
      invalidChunkError(ci.id, groupChunkId.get)

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvl_prop)
  if dataCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvl_cell)

  rr.cursor = propCursor.get
  let (name, level, rows, cols) = readLevelProperties_V1(rr)
  var l = newLevel(name, level, rows, cols)

  rr.cursor = dataCursor.get
  let numCells = (rows+1) * (cols+1)   # because of the South & East borders
  l.cellGrid.cells = readLevelData_V1(rr, numCells)

  if annoCursor.isSome:
    rr.cursor = annoCursor.get
    readLevelNotes_V1(rr, l)

  result = l


proc readLevelList(rr): seq[Level] =
  var ml = newSeq[Level]()
  while rr.hasNextChunk():
    let ci = rr.nextChunk()
    if ci.kind == ckGroup:
      case ci.formatTypeId
      of FourCC_GRDM_lvl:
        rr.enterGroup()
        ml.add(readLevel(rr))
      else:
        invalidListChunkError(ci.formatTypeId, FourCC_GRDM_lvls)
    else:
      invalidChunkError(ci.id, FourCC_GRDM_lvls)
  result = ml


proc readMapHeader(rr): MapHeaderInfo =
  var h: MapHeaderInfo
  h.version = rr.read(uint16).Natural
  if h.version > CurrentMapVersion:
    raiseMapReadError("Unsupported map file version: {h.version}")
  result = h


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
      mapHeaderCursor = Cursor.none
      linksCursor = Cursor.none
      levelListCursor = Cursor.none
      themeCursor = Cursor.none

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
        of FourCC_GRDM_maph:
          if mapHeaderCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_maph)
          mapHeaderCursor = rr.cursor.some

        of FourCC_GRDM_lnks:
          if linksCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_lnks)
          linksCursor = rr.cursor.some

        of FourCC_GRDM_them:
          if themeCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_them)
          themeCursor = rr.cursor.some

        else: discard   # skip unknown top level chunks

    # Check for mandatory chunks
    if mapHeaderCursor.isNone: chunkNotFoundError(FourCC_GRDM_maph)
    if levelListCursor.isNone: chunkNotFoundError(FourCC_GRDM_lvls)
    if linksCursor.isNone:     chunkNotFoundError(FourCC_GRDM_lnks)

    # Load chunks
    rr.cursor = mapHeaderCursor.get
    discard readMapHeader(rr)

    result = newMap()

    rr.cursor = levelListCursor.get
    rr.enterGroup()
    result.levels = readLevelList(rr)

    rr.cursor = linksCursor.get
    result.links = readLinks(rr)

  except MapReadError as e:
    echo getStackTrace(e)
    raise e
  except CatchableError as e:
    echo getStackTrace(e)
    raise newException(MapReadError, fmt"Error reading map file: {e.msg}", e)
  finally:
    rr.close()

# }}}
# }}}

# {{{ Write

using rw: RiffWriter

proc writeLinks(rw; links: BiTable[Location, Location]) =
  rw.beginChunk(FourCC_GRDM_lnks)
  rw.write(links.len.uint16)

  var sortedKeys = links.keys()
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
  rw.writeWStr(l.name)
  rw.write(l.level.int16)
  rw.write(l.rows.uint16)
  rw.write(l.cols.uint16)
  rw.endChunk()

proc writeLevelCells(rw; cells: seq[Cell]) =
  rw.beginChunk(FourCC_GRDM_lvl_cell)
  for c in cells:
    rw.write(c.floor.uint8)
    rw.write(c.floorOrientation.uint8)
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


proc writeMapHeader(rw) =
  rw.beginChunk(FourCC_GRDM_maph)
  rw.write(CurrentMapVersion.uint16)
  rw.endChunk()


proc writeMap*(m: Map, filename: string) =
  var rw: RiffWriter
  try:
    rw = createRiffFile(filename, FourCC_GRDM)

    # TODO writeMapInfo(rw)
    writeMapHeader(rw)
    writeLevelList(rw, m.levels)
    writeLinks(rw, m.links)
# TODO   writeTheme(rw)

  except MapReadError as e:
    raise e
  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file: {e.msg}", e)
  finally:
    rw.close()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
