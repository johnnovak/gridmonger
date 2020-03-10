import binstreams
import options
import strformat

import riff

import common
import map


using rr: RiffReader


const
  FourCC_GRDM_maph     = "maph"
  FourCC_GRDM_mapl     = "mapl"
  FourCC_GRDM_map      = "map "
  FourCC_GRDM_map_prop = "prop"
  FourCC_GRDM_map_data = "data"
  FourCC_GRDM_map_anno = "anno"
  FourCC_GRDM_thme     = "thme"

type MapReadError* = object of Exception

proc raiseMapReadError(s: string) =
  raise newException(MapReadError, s)

# {{{ Read
# {{{ V1
proc readMapProperties_V1(rr): (Natural, Natural, string) =
  let
    rows = rr.read(uint16).Natural
    cols = rr.read(uint16).Natural
    nameLen = rr.read(uint16)
    name = rr.readStr(nameLen)  # TODO read bstr & bzstr

  result = (rows, cols, name)


proc readMapData_V1(rr; numCells: Natural): seq[Cell] =
  result = newSeqOfCap[Cell](numCells)
  for i in 0..<numCells:
    var c: Cell
    c.ground = rr.read(uint8).Ground
    c.groundOrientation = rr.read(uint8).Orientation
    c.wallN = rr.read(uint8).Wall
    c.wallW = rr.read(uint8).Wall
    c.customChar = rr.readChar()
    result.add(c)

proc readMapAnnotations_V1(s; m: Map) =
  discard  # TODO


proc chunkOnlyOnceError(chunkId: string,
                        containerChunkId: Option[string] = string.none) =
  var msg = fmt"'{chunkId}' chunk can only appear once"
  if containerChunkId.isSome:
    msg &= fmt" in '{containerChunkId.get}' group chunk"
  raiseMapReadError(msg)

proc chunkNotFoundError(chunkId: string,
                        containerChunkId: Option[string] = string.none) =
  var msg = fmt"'{chunkId}' chunk not found"
  if containerChunkId.isSome:
    msg &= fmt" in '{containerChunkId.get}' group chunk"
  raiseMapReadError(msg)

proc chunkInvalidNestingError(chunkId, containerChunkId: string) =
  raiseMapReadError(
    fmt"'{chunkId}' chunk is not allowed inside " &
    fmt"'{containerChunkId}' group chunk")

proc readMapChunk(r: RiffReader): Map =
  let containerChunkId = FourCC_GRDM_mapl.some
  var
    propCursor = Cursor.none
    dataCursor = Cursor.none
    annoCursor = Cursor.none

  while r.hasNextChunk():
    let ci = r.nextChunk()
    if ci.kind == ckChunk:
      case ci.id
      of FourCC_GRDM_map_prop:
        if propCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_prop, containerChunkId)
        propCursor = r.cursor.some

      of FourCC_GRDM_map_data:
        if dataCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_data, containerChunkId)
        dataCursor = r.cursor.some

      of FourCC_GRDM_map_anno:
        if annoCursor.isSome:
          chunkOnlyOnceError(FourCC_GRDM_map_anno, containerChunkId)
        annoCursor = r.cursor.some
      else:
        chunkInvalidNestingError(ci.id, FourCC_GRDM_mapl)
    else:
      raiseMapReadError(
        fmt"'{ci.formatTypeId}' group chunk is " &
        fmt"'not allowed inside a {FourCC_GRDM_mapl}' group chunk")

  if   propCursor.isNone: chunkNotFoundError(FourCC_GRDM_map_prop)
  elif dataCursor.isNone: chunkNotFoundError(FourCC_GRDM_map_data)

  r.cursor = propCursor.get
  let (rows, cols, name) = readMapProperties_V1(r)
  result = new Map
  result.name = name
  result.cols = cols
  result.rows = rows

  r.cursor = dataCursor.get
  result.cells = readMapData_V1(r)

  if annoCursor.isSome:
    r.cursor = annoCursor.get
    readMapAnnotations_V1(r)  # TODO


proc read(filename: string): Map =
  # TODO exc handling
  var r = openRiffFile(infile)
  defer: r.close()

  var
    maphCursor = Cursor.none
    maplCursor = Cursor.none
    thmeCursor = Cursor.none
    readingMaps = false

  proc walkChunks(m: var Map) =
    while r.hasNextChunk():
      let ci = r.nextChunk()

      if not readingMaps:
        if ci.kind == ckGroup:
          case ci.formatTypeId:
          of FourCC_INFO:
            discard  # TODO

          of FourCC_GRDM_mapl:
            if r.cursor.path.len == 1:
              if maplCursor.isSome: chunkOnlyOnceError(FourCC_GRDM_mapl)
              r.enterGroup()
              walkChunks(m)
            else:
              raiseMapReadError(
                fmt"'{FourCC_GRDM_mapl}' chunk can only appear at root level")

          of FourCC_GRDM_map:
            if r.cursor.path.len < 2:
              raiseMapReadError(
                fmt"'{FourCC_GRDM_map}' cannot appear at the root level")

            let parentChunk = r.cursor.path[^2]  # TODO
            if parentChunk.formatTypeId != FourCC_GRDM_mapl:
              chunkInvalidNestingError(FourCC_GRDM_map, FourCC_GRDM_mapl)
            r.enterGroup()
            readingMaps = true
            walkChunks(m)
          else:
            discard   # skip unknown top level chunks

        elif ci.kind == ckChunk:
          case ci.id
          of FourCC_GRDM_maph:
          of FourCC_GRDM_thme:

      elif readingMaps:
        let map = r.readMapChunk()

    r.exitGroup()


  let ci = r.currentChunk
  if ci.formatTypeId != FourCC_GRDM_map:
    raiseMapReadError(
      fmt"Not a map file, RIFF formatTypeId: {fourCCToCharStr(id)}")

  result = new Map
  walkChunks()

# }}}
# }}}

# {{{ Write

proc writeMapProperties(s; m: Map) =
  s.write(m.rows.uint16)
  s.write(m.cols.uint16)
  s.write(m.name.len.uint16)
  s.writeStr(m.name)

proc writeMapData(s; m: Map) =
  for c in m.cells:
    s.write(c.ground.uint8)
    s.write(c.groundOrientation.uint8)
    s.write(c.wallN.uint8)
    s.write(c.wallW.uint8)
    s.writeChar(c.customChar)

proc writeMapAnnotations(s; m: Map) =
  s.beginChunk(FourCC_GRDM_map_anno)
  let numAnnotations = 0'u16  # TODO
  s.write(numAnnotations)
  s.endChunk()

proc writeMapChunk(s; m: Map) =
  s.beginListChunk(FourCC_GRDM_map)

  s.beginChunk(FourCC_GRDM_map_prop)
  s.writeMapProperties(m)
  s.endChunk()

  s.beginChunk(FourCC_GRDM_map_data)
  s.writeMapData(m)
  s.endChunk()

  s.beginChunk(FourCC_GRDM_map_anno)
  s.writeMapAnnotations(m)
  s.endChunk()

  s.endChunk()

# }}}


# vim: et:ts=2:sw=2:fdm=marker
