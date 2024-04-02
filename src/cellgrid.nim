import std/options

import common
import rect
import utils


using g: CellGrid

# {{{ cellIndex()
template cellIndex(g; r,c: Natural): Natural =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  let w = g.cols+1
  let h = g.rows+1
  assert r < h
  assert c < w
  r*w + c

# }}}
# {{{ `[]=`()
proc `[]=`(g; r,c: Natural, cell: Cell) {.inline.} =
  g.cells[cellIndex(g, r,c)] = cell

# }}}
# {{{ `[]`()
proc `[]`(g; r,c: Natural): var Cell {.inline.} =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  result = g.cells[cellIndex(g, r,c)]

# }}}

# {{{ fill*()
proc fill*(g; rect: Rect[Natural], cell: Cell) =
  assert rect.r1 < g.rows
  assert rect.c1 < g.cols
  assert rect.r2 <= g.rows
  assert rect.c2 <= g.cols

  for r in rect.r1..rect.r2:
    for c in rect.c1..rect.c2:
      g[r,c] = cell

proc fill*(g; cell: Cell) =
  let rect = rectN(0, 0, g.rows, g.cols)
  g.fill(rect, cell)

# }}}
# {{{ newCellGrid*()
proc newCellGrid*(rows, cols: Natural): CellGrid =
  var g = new CellGrid
  g.rows = rows
  g.cols = cols

  # We're storing one extra row & column at the bottom-right edges ("edge"
  # rows & columns) so we can store the South and East walls of the bottommost
  # row and rightmost column, respectively.
  newSeq(g.cells, (rows+1) * (cols+1))

  g.fill(Cell.default)
  result = g

# }}}

# {{{ getWall*()
proc getWall*(g; r,c: Natural, dir: CardinalDir): Wall {.inline.} =
  assert r < g.rows
  assert c < g.cols

  case dir
  of dirN: g[r,   c  ].wallN
  of dirW: g[r,   c  ].wallW
  of dirS: g[r+1, c  ].wallN
  of dirE: g[r,   c+1].wallW

# }}}
# {{{ setWall*()
proc setWall*(g; r,c: Natural, dir: CardinalDir, w: Wall) {.inline.} =
  assert r < g.rows
  assert c < g.cols

  case dir
  of dirN: g[r,   c  ].wallN = w
  of dirW: g[r,   c  ].wallW = w
  of dirS: g[r+1, c  ].wallN = w
  of dirE: g[r,   c+1].wallW = w

# }}}

# {{{ getFloor*()
proc getFloor*(g; r,c: Natural): Floor {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floor

# }}}
# {{{ setFloor*()
proc setFloor*(g; r,c: Natural, f: Floor) {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floor = f

# }}}
# {{{ getFloorOrientation*()
proc getFloorOrientation*(g; r,c: Natural): Orientation {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floorOrientation

# }}}
# {{{ setFloorOrientation*()
proc setFloorOrientation*(g; r,c: Natural, ot: Orientation) {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floorOrientation = ot

# }}}
# {{{ getFloorColor*()
proc getFloorColor*(g; r,c: Natural): byte {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floorColor

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(g; r,c: Natural, col: byte) {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].floorColor = col

# }}}

# {{{ hasTrail*()
proc hasTrail*(g; r,c: Natural): bool {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].trail

# }}}
# {{{ setTrail*()
proc setTrail*(g; r,c: Natural, t: bool) {.inline.} =
  assert r < g.rows
  assert c < g.cols
  g[r,c].trail = t

# }}}
# {{{ calcTrailBoundingBox*()
proc calcTrailBoundingBox*(g): Option[Rect[Natural]] =
  var bbox = Rect[Natural].none
  for r in 0..<g.rows:
    for c in 0..<g.cols:
      if g.hasTrail(r,c):
        if bbox.isNone: bbox = rectN(r, c, r+1, c+1).some
        else: bbox.get.expand(r,c)

  result = bbox

# }}}
#
# {{{ isEmpty*()
proc isEmpty*(f: Floor): bool {.inline.} =
  f == fEmpty

proc isEmpty*(c: Cell): bool {.inline.} =
  c.floor.isEmpty

proc isEmpty*(g; r,c: Natural): bool {.inline.} =
  g[r,c].isEmpty

# }}}
# {{{ copyFrom*()
proc copyFrom*(g; destRow, destCol: Natural,
               src: CellGrid, srcRect: Rect[Natural]) =
  # This function cannot fail as the copied area is clipped to the extents of
  # the destination area (so nothing gets copied in the worst case).
  let
    srcCol = srcRect.c1
    srcRow = srcRect.r1
    # TODO use clamp
    srcRows = max(src.rows - srcRow, 0)
    srcCols = max(src.cols - srcCol, 0)
    destRows = max(g.rows - destRow, 0)
    destCols = max(g.cols - destCol, 0)

    # TODO use clamp
    rows = min(min(srcRows, destRows), srcRect.rows)
    cols = min(min(srcCols, destCols), srcRect.cols)

  for r in 0..<rows:
    for c in 0..<cols:
      g[destRow+r, destCol+c] = src[srcRow+r, srcCol+c]

  # Copy the South walls of the bottommost "edge" row
  for c in 0..<cols:
    g[destRow+rows, destCol+c].wallN = src[srcRow+rows, srcCol+c].wallN

  # Copy the East walls of the rightmost "edge" column
  for r in 0..<rows:
    g[destRow+r, destCol+cols].wallW = src[srcRow+r, srcCol+cols].wallW

# }}}
# {{{ getNeighbourCell*()
proc getNeighbourCell*(g; r,c: Natural, dir: Direction): Option[Cell] =

  func step(row, col: int, dir: Direction): (int, int) =
    if   dir == North:     result = (row-1, col)
    elif dir == NorthEast: result = (row-1, col+1)
    elif dir == East:      result = (row,   col+1)
    elif dir == SouthEast: result = (row+1, col+1)
    elif dir == South:     result = (row+1, col)
    elif dir == SouthWest: result = (row+1, col-1)
    elif dir == West:      result = (row,   col-1)
    elif dir == NorthWest: result = (row-1, col-1)

  let (nr, nc) = step(r,c, dir)
  if nr < 0 or nc < 0 or nr >= g.rows or nc >= g.cols: Cell.none
  else: g[nr,nc].some

# }}}
# {{{ isNeighbourCellEmpty*()
proc isNeighbourCellEmpty*(g; r,c: Natural, dir: Direction): bool =
  let c = getNeighbourCell(g, r,c, dir)
  if c.isNone: true
  else: c.get.isEmpty

# }}}

# vim: et:ts=2:sw=2:fdm=marker
