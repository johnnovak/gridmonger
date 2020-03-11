import options

import common
import selection


using m: Map

proc cellIndex(m; c, r: Natural): Natural =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  let w = m.cols+1
  let h = m.rows+1
  assert c < w+1
  assert r < h+1
  result = w*r + c

proc `[]=`(m; c, r: Natural, cell: Cell) =
  m.cells[cellIndex(m, c, r)] = cell

proc `[]`(m; c, r: Natural): var Cell =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  result = m.cells[cellIndex(m, c, r)]

proc fill*(m; rect: Rect[Natural], cell: Cell) =
  assert rect.x1 < m.cols
  assert rect.y1 < m.rows
  assert rect.x2 <= m.cols
  assert rect.y2 <= m.rows

  # TODO fill border
  for r in rect.y1..<rect.y2:
    for c in rect.x1..<rect.x2:
      m[c,r] = cell


proc fill*(m; cell: Cell) =
  let rect = rectN(0, 0, m.cols-1, m.rows-1)
  m.fill(rect, cell)

proc initMap(m; cols, rows: Natural) =
  m.cols = cols
  m.rows = rows

  # We're storing one extra row & column at the bottom-right edges ("edge"
  # columns & rows) so we can store the South and East walls of the bottommost
  # row and rightmost column, respectively.
  newSeq(m.cells, (cols+1) * (rows+1))

proc newMap*(cols, rows: Natural): Map =
  var m = new Map
  m.initMap(cols, rows)
  m.fill(Cell.default)
  result = m


proc copyFrom*(dest: var Map, destCol, destRow: Natural,
               src: Map, srcRect: Rect[Natural]) =
  # This function cannot fail as the copied area is clipped to the extents of
  # the destination area (so nothing gets copied in the worst case).
  let
    # TODO use rect.intersect
    srcCol = srcRect.x1
    srcRow = srcRect.y1
    srcCols   = max(src.cols - srcCol, 0)
    srcRows  = max(src.rows - srcRow, 0)
    destCols  = max(dest.cols - destCol, 0)
    destRows = max(dest.rows - destRow, 0)

    w = min(min(srcCols,  destCols),  srcRect.width)
    h = min(min(srcRows, destRows), srcRect.height)

  for r in 0..<h:
    for c in 0..<w:
      dest[destCol+c, destRow+r] = src[srcCol+c, srcRow+r]

  # Copy the South walls of the bottommost "edge" row
  for c in 0..<w:
    dest[destCol+c, destRow+h].wallN = src[srcCol+c, srcRow+h].wallN

  # Copy the East walls of the rightmost "edge" column
  for r in 0..<h:
    dest[destCol+w, destRow+r].wallW = src[srcCol+w, srcRow+r].wallW


proc copyFrom*(dest: var Map, src: Map) =
  dest.copyFrom(destCol=0, destRow=0, src, rectN(0, 0, src.cols, src.rows))


proc newMapFrom*(src: Map, rect: Rect[Natural]): Map =
  assert rect.x1 < src.cols
  assert rect.y1 < src.rows
  assert rect.x2 <= src.cols
  assert rect.y2 <= src.rows

  var dest = new Map
  dest.initMap(rect.width, rect.height)
  dest.copyFrom(destCol=0, destRow=0, src, srcRect=rect)
  result = dest


proc newMapFrom*(m): Map =
  newMapFrom(m, rectN(0, 0, m.cols, m.rows))


proc getGround*(m; c, r: Natural): Ground =
  assert c < m.cols
  assert r < m.rows
  m[c,r].ground

proc getGroundOrientation*(m; c, r: Natural): Orientation =
  assert c < m.cols
  assert r < m.rows
  m[c,r].groundOrientation

proc setGroundOrientation*(m; c, r: Natural, ot: Orientation) =
  assert c < m.cols
  assert r < m.rows
  m[c,r].groundOrientation = ot

proc setGround*(m; c, r: Natural, f: Ground) =
  assert c < m.cols
  assert r < m.rows
  m[c,r].ground = f


proc getWall*(m; c, r: Natural, dir: Direction): Wall =
  assert c < m.cols
  assert r < m.rows

  case dir
  of North: m[c,   r  ].wallN
  of West:  m[c,   r  ].wallW
  of South: m[c,   r+1].wallN
  of East:  m[c+1, r  ].wallW


proc isNeighbourCellEmpty*(m; c, r: Natural, dir: Direction): bool =
  assert c < m.cols
  assert r < m.rows

  case dir
  of North: r == 0        or m[c,   r-1].ground == gNone
  of West:  c == 0        or m[c-1, r  ].ground == gNone
  of South: r == m.rows-1 or m[c,   r+1].ground == gNone
  of East:  c == m.cols-1 or m[c+1, r  ].ground == gNone


proc canSetWall*(m; c, r: Natural, dir: Direction): bool =
  assert c < m.cols
  assert r < m.rows

  m[c,r].ground != gNone or not isNeighbourCellEmpty(m, c, r, dir)


proc setWall*(m; c, r: Natural, dir: Direction, w: Wall) =
  assert c < m.cols
  assert r < m.rows

  case dir
  of North: m[c,   r  ].wallN = w
  of West:  m[c,   r  ].wallW = w
  of South: m[c,   r+1].wallN = w
  of East:  m[c+1, r  ].wallW = w


proc eraseCellWalls*(m; c, r: Natural) =
  assert c < m.cols
  assert r < m.rows

  m.setWall(c,r, North, wNone)
  m.setWall(c,r, West,  wNone)
  m.setWall(c,r, South, wNone)
  m.setWall(c,r, East,  wNone)


proc eraseOrphanedWalls*(m; c, r: Natural) =
  template cleanWall(dir: Direction) =
    if m.isNeighbourCellEmpty(c,r, dir):
      m.setWall(c,r, dir, wNone)

  if m.getGround(c,r) == gNone:
    cleanWall(North)
    cleanWall(West)
    cleanWall(South)
    cleanWall(East)


proc eraseCell*(m; c, r: Natural) =
  assert c < m.cols
  assert r < m.rows

  m.eraseCellWalls(c, r)
  m.setGround(c, r, gNone)


proc paste*(m; destCol, destRow: Natural, src: Map, sel: Selection) =
  let rect = rectN(
    destCol,
    destRow,
    destCol + src.cols,
    destRow + src.rows
  ).intersect(
    rectN(0, 0, m.cols, m.rows)
  )
  if rect.isSome:
    for c in 0..<rect.get.width:
      for r in 0..<rect.get.height:
        if sel[c,r]:
          let ground = src.getGround(c,r)
          m.setGround(destCol+c, destRow+r, ground)

          template copyWall(dir: Direction) =
            let w = src.getWall(c,r, dir)
            m.setWall(destCol+c, destRow+r, dir, w)

          if ground == gNone:
            m.eraseOrphanedWalls(destCol+c, destRow+r)
          else:
            copyWall(North)
            copyWall(West)
            copyWall(South)
            copyWall(East)

# vim: et:ts=2:sw=2:fdm=marker
