import options
import strformat

import riff

import common
import map


# TODO use app version instead
const CurrentMapVersion = 1

const
  FourCC_GRDM          = "GRMM"
  FourCC_GRDM_maph     = "maph"
  FourCC_GRDM_mapl     = "mapl"
  FourCC_GRDM_map      = "map "
  FourCC_GRDM_map_prop = "prop"
  FourCC_GRDM_map_cell = "cell"
  FourCC_GRDM_map_note = "note"
  FourCC_GRDM_them     = "them"

type
  MapHeaderInfo = object
    version: Natural


type MapReadError* = object of Exception

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

proc readMapProperties_V1(rr): (Natural, Natural, string) =
  let
    rows = rr.read(uint16).Natural
    cols = rr.read(uint16).Natural
    name = rr.readWStr()
  result = (rows, cols, name)


# TODO remove
proc mapFloor(f: uint8): uint8 =
  result = case f
  of 0:  0
  of 1:  1
  of 10: 20
  of 11: 22
  of 20: 30
  of 21: 31
  of 30: 40
  of 31: 41
  of 32: 42
  of 33: 43
  of 40: 50
  of 41: 51
  of 50: 60
  of 60: 70
  else: f.int

# TODO remove
proc mapWall(w: uint8): uint8 =
  result = case w
  of 21: 22
  else: w.int

proc readMapData_V1(rr; numCells: Natural): seq[Cell] =
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


proc readMapNotes_V1(rr; m: Map) =
  let numNotes = rr.read(uint16).Natural

  for i in 0..<numNotes:
    let row = rr.read(uint16)
    let col = rr.read(uint16)

    var note = Note(kind: NoteKind(rr.read(uint8)))
    case note.kind
    of nkIndexed:  note.index = rr.read(uint16)
    of nkCustomId: note.customId = rr.readBStr()
    of nkComment:  discard

    note.text = rr.readWStr()
    echo note.text
    echo note.text.len

    m.setNote(row, col, note)


proc readMap(rr): Map =
  let groupChunkId = FourCC_GRDM_mapl.some
  var
    propCursor = Cursor.none
    dataCursor = Cursor.none
    annoCursor = Cursor.none

  while rr.hasNextChunk():
    let ci = rr.nextChunk()
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_map_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_prop, groupChunkId)
        propCursor = rr.cursor.some

      of FourCC_GRDM_map_cell:
        if dataCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_cell, groupChunkId)
        dataCursor = rr.cursor.some

      of FourCC_GRDM_map_note:
        if annoCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_note, groupChunkId)
        annoCursor = rr.cursor.some
      else:
        invalidChunkError(ci.id, FourCC_GRDM_mapl)
    else:
      invalidChunkError(ci.id, groupChunkId.get)

  if propCursor.isNone: chunkNotFoundError(FourCC_GRDM_map_prop)
  if dataCursor.isNone: chunkNotFoundError(FourCC_GRDM_map_cell)

  rr.cursor = propCursor.get
  let (rows, cols, name) = readMapProperties_V1(rr)
  var m = new Map
  m.name = name
  m.rows = rows
  m.cols = cols

  rr.cursor = dataCursor.get
  let numCells = (rows+1) * (cols+1)   # because of the South & East borders
  m.cells = readMapData_V1(rr, numCells)

  if annoCursor.isSome:
    rr.cursor = annoCursor.get
    readMapNotes_V1(rr, m)

  result = m


proc readMapList(rr): seq[Map] =
  var ml = newSeq[Map]()
  while rr.hasNextChunk():
    let ci = rr.nextChunk()
    if ci.kind == ckGroup:
      case ci.formatTypeId
      of FourCC_GRDM_map:
        rr.enterGroup()
        ml.add(readMap(rr))
      else:
        invalidListChunkError(ci.formatTypeId, FourCC_GRDM_mapl)
    else:
      invalidChunkError(ci.id, FourCC_GRDM_mapl)
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
      mapListCursor = Cursor.none
      themeCursor = Cursor.none

    # Find chunks
    while rr.hasNextChunk():
      let ci = rr.nextChunk()
      if ci.kind == ckGroup:
        case ci.formatTypeId
        of FourCC_INFO:
          discard  # TODO

        of FourCC_GRDM_mapl:
          if mapListCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_mapl)
          mapListCursor = rr.cursor.some

        else: discard   # skip unknown top level group chunks

      elif ci.kind == ckChunk:
        case ci.id
        of FourCC_GRDM_maph:
          if mapHeaderCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_maph)
          mapHeaderCursor = rr.cursor.some

        of FourCC_GRDM_them:
          if themeCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_them)
          themeCursor = rr.cursor.some

        else: discard   # skip unknown top level chunks

    # Check for mandatory chunks
    if mapHeaderCursor.isNone: chunkNotFoundError(FourCC_GRDM_maph)
    if mapListCursor.isNone: chunkNotFoundError(FourCC_GRDM_mapl)

    # Load chunks
    rr.cursor = mapHeaderCursor.get
    discard readMapHeader(rr)

    rr.cursor = mapListCursor.get
    rr.enterGroup()
    let maps = readMapList(rr)
    result = maps[0]  # TODO

  except CatchableError as e:
    raise newException(MapReadError, fmt"Error reading map file", e)
  finally:
    rr.close()

# }}}
# }}}

# {{{ Write

using rw: RiffWriter

proc writeMapProperties(rw; m: Map) =
  rw.beginChunk(FourCC_GRDM_map_prop)
  rw.write(m.rows.uint16)
  rw.write(m.cols.uint16)
  rw.writeWStr(m.name)
  rw.endChunk()

proc writeMapCells(rw; cells: seq[Cell]) =
  rw.beginChunk(FourCC_GRDM_map_cell)
  for c in cells:
    rw.write(c.floor.uint8)
    rw.write(c.floorOrientation.uint8)
    rw.write(c.wallN.uint8)
    rw.write(c.wallW.uint8)
  rw.endChunk()


proc writeMapNotes(rw; m: Map) =
  rw.beginChunk(FourCC_GRDM_map_note)
  rw.write(m.numNotes.uint16)

  for (row, col, note) in m.allNotes:
    rw.write(row.uint16)
    rw.write(col.uint16)

    rw.write(note.kind.uint8)
    case note.kind
    of nkIndexed:  rw.write(note.index.uint16)
    of nkCustomId: rw.writeBStr(note.customId)
    of nkComment:  discard

    rw.writeWStr(note.text)

  rw.endChunk()


proc writeMap(rw; m: Map) =
  rw.beginListChunk(FourCC_GRDM_map)
  rw.writeMapProperties(m)
  rw.writeMapCells(m.cells)
  rw.writeMapNotes(m)
  rw.endChunk()

proc writeMapList(rw; maps: seq[Map]) =
  rw.beginListChunk(FourCC_GRDM_mapl)
  for m in maps:
    writeMap(rw, m)
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
    writeMapList(rw, @[m])  # TODO
# TODO   writeTheme(rw)

  except CatchableError as e:
    raise newException(MapReadError, fmt"Error writing map file", e)
  finally:
    rw.close()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
