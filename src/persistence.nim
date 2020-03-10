import binstreams

import common
import map


type Stream = FileStream

using s: Stream


const
  FourCC_GRDM_maph     = "maph"
  FourCC_GRDM_mapl     = "mapl"
  FourCC_GRDM_map      = "map"
  FourCC_GRDM_map_prop = "prop"
  FourCC_GRDM_map_data = "data"
  FourCC_GRDM_map_anno = "anno"

type MapReadError* = object of Exception

# {{{ Read
# {{{ V1
proc readMapProperties_V1(s): (Natural, Natural, string) =
  let
    rows = s.read(uint16).Natural
    cols = s.read(uint16).Natural
    nameLen = s.read(uint16)
    name = s.readStr(nameLen)  # TODO read bstr & bzstr

  result = (rows, cols, name)


proc readMapData_V1(s; numCells: Natural): seq[Cell] =
  result = newSeqOfCap[Cell](numCells)
  for i in 0..<numCells:
    var c: Cell
    c.ground = s.read(uint8).Natural
    c.groundOrientation = s.read(uint8).Natural
    c.wallN = s.read(uint8).Natural
    c.wallW = s.read(uint8).Natural
    c.customChar = s.readChar(uint8)
    result.add(c)

proc readMapAnnotations_V1(s; m: Map) =
  discard  # TODO


proc readMapChunk_V1(s; m: Map) =
  var
    rows, cols: Natural
    name: string
    cells: seq[Cell]

  case id
  of FourCC_GRDM_map_prop:
    (rows, cols, name) = s.readMapProperties_V1()

  of FourCC_GRDM_map_data:
    cells = s.readMapData(m)

  of FourCC_GRDM_map_anno:
    discard s.readMapAnnotations(m)   # TODO

  else raise newException(MapReadError,
    fmt"Invalid subchunk ID while reading '{FourCC_GRDM_map}' chunk: " &
    fourCCToCharStr(id)


proc raiseMapReadError(s: string) =
  raise newException(MapReadError, s)


proc read(filename: string): Map =
  # TODO exc handling
  var r = openRiffFile(infile)
  defer: r.close()

  var
    maplChunkCount = 0
    readingMaps: false
    mapRows, mapCols: Natural
    mapName: String
    mapCells = seq[Cell]

  proc readMap(r: RiffReader): Map =
    var
      numPropChunks = 0
      numDataChunks = 0
      numAnnoChunks = 0
      propCursor, dataCursor, annoCursor: Cursor

    while r.hasNextChunk()
      let ci = r.nextChunk()
      if ci.kind == ckChunk:
        case ci.id
        of FourCC_GRDM_map_prop:
          if numPropChunks > 0:
            raiseMapReadError(
              fmt"'{FourCC_GRDM_map_prop}' chunk can only appear once "
              fmt"in a {FourCC_GRDM_map} group chunk")
          else:
            propCursor = r.cursor
            inc(numPropChunks)

        of FourCC_GRDM_map_data:
          if numDataChunks > 0:
            raiseMapReadError(
              fmt"'{FourCC_GRDM_map_data}' chunk can only appear once "
              fmt"in a {FourCC_GRDM_map} group chunk")
          else:
            dataCursor = r.cursor
            inc(numDataChunks)

        of FourCC_GRDM_map_anno:
          if numAnnoChunks > 0:
            raiseMapReadError(
              fmt"'{FourCC_GRDM_map_anno}' chunk can only appear once "
              fmt"in a {FourCC_GRDM_map} group chunk")
          else:
            annoCursor = r.cursor
            inc(numAnnoChunks)
        else:
          raiseMapReadError(
            fmt"{fourCCToCharStr(ci.id)} chunk is not allowed inside a " &
            fmt"'{FourCC_GRDM_mapl}' group chunk"
          )
      else:
        raiseMapReadError(
          fmt"{fourCCToCharStr(ci.formatTypeId)} group chunk is " &
          fmt"'not allowed inside a {FourCC_GRDM_mapl}' group chunk"
        )

    (mapRows, mapCols, mapName) = readMapProperties_V1(r)
    mapCells = readMapData_V1(r)


  proc walkChunks(m: var Map, depth: Natural = 1) =
    while r.hasNextChunk():
      let ci = r.nextChunk()

      if not readingMaps:
        if ci.kind == ckGroup:
          case ci.formatTypeId:
          of FourCC_INFO:
            discard  # TODO

          of FourCC_GRDM_mapl:
            if r.cursor.path.len == 1:
              if maplChunkCount > 1:
              raiseMapReadError(
                fmt"'{FourCC_GRDM_mapl}' chunk can only appear once")

              inc(maplChunkCount)
              r.enterGroup()
              walkChunks(m, depth+1)
            else:
              raiseMapReadError(
                fmt"'{FourCC_GRDM_mapl}' chunk can only appear at the root level")

          of FourCC_GRDM_map:
            if r.cursor.path.len < 2:
              raiseMapReadError(
                fmt"'{FourCC_GRDM_map}' cannot appear at the root level")
            else:
              let parentChunk = r.cursor.path[^2]  # TODO
              if parentChunk.formatTypeId != FourCC_GRDM_mapl:
                raiseMapReadError(
                  fmt"'{FourCC_GRDM_map}' chunk can only appear inside a " &
                  fmt"'{FourCC_GRDM_mapl}' group chunk"
                )

              r.enterGroup()
              readingMaps = true
          else:
            discard

      elif readingMaps:
        readMap

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
