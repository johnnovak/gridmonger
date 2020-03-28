import options
import tables

import common
import selection


using m: Map

proc cellIndex(m; r,c: Natural): Natural =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  let w = m.cols+1
  let h = m.rows+1
  assert r < h
  assert c < w
  result = r*w + c

proc `[]=`(m; r,c: Natural, cell: Cell) =
  m.cells[cellIndex(m, r,c)] = cell

proc `[]`(m; r,c: Natural): var Cell =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  result = m.cells[cellIndex(m, r,c)]

proc fill*(m; rect: Rect[Natural], cell: Cell) =
  assert rect.x1 < m.cols
  assert rect.y1 < m.rows
  assert rect.x2 <= m.cols
  assert rect.y2 <= m.rows

  # TODO fill border
  for r in rect.y1..<rect.y2:
    for c in rect.x1..<rect.x2:
      m[r,c] = cell


proc fill*(m; cell: Cell) =
  let rect = rectN(0, 0, m.cols-1, m.rows-1)
  m.fill(rect, cell)

proc initMap(m; rows, cols: Natural) =
  m.name = "Untitled"
  m.rows = rows
  m.cols = cols

  # We're storing one extra row & column at the bottom-right edges ("edge"
  # rows & columns) so we can store the South and East walls of the bottommost
  # row and rightmost column, respectively.
  newSeq(m.cells, (rows+1) * (cols+1))

  m.notes = initTable[Natural, Note]()


proc newMap*(rows, cols: Natural): Map =
  var m = new Map
  m.initMap(rows, cols)
  m.fill(Cell.default)
  result = m


proc copyFrom*(dest: var Map, destRow, destCol: Natural,
               src: Map, srcRect: Rect[Natural]) =
  # This function cannot fail as the copied area is clipped to the extents of
  # the destination area (so nothing gets copied in the worst case).
  let
    # TODO use rect.intersect
    srcRow = srcRect.y1
    srcCol = srcRect.x1
    srcRows  = max(src.rows - srcRow, 0)
    srcCols   = max(src.cols - srcCol, 0)
    destRows = max(dest.rows - destRow, 0)
    destCols  = max(dest.cols - destCol, 0)

    w = min(min(srcCols,  destCols),  srcRect.width)
    h = min(min(srcRows, destRows), srcRect.height)

  for r in 0..<h:
    for c in 0..<w:
      dest[destRow+r, destCol+c] = src[srcRow+r, srcCol+c]

  # Copy the South walls of the bottommost "edge" row
  for c in 0..<w:
    dest[destRow+h, destCol+c].wallN = src[srcRow+h, srcCol+c].wallN

  # Copy the East walls of the rightmost "edge" column
  for r in 0..<h:
    dest[destRow+r, destCol+w].wallW = src[srcRow+r, srcCol+w].wallW


proc copyFrom*(dest: var Map, src: Map) =
  dest.copyFrom(destRow=0, destCol=0,
                src, srcRect=rectN(0, 0, src.cols, src.rows))


proc newMapFrom*(src: Map, rect: Rect[Natural], border: Natural = 0): Map =
  assert rect.x1 < src.cols
  assert rect.y1 < src.rows
  assert rect.x2 <= src.cols
  assert rect.y2 <= src.rows

  var
    destRow = 0
    destCol = 0
    srcRect = rect

  let x1 = srcRect.x1.int - border
  if x1 < 0:
    destCol = -x1
    srcRect.x1 = 0
  else:
    srcRect.x1 = x1

  let y1 = srcRect.y1.int - border
  if y1 < 0:
    destRow = -y1
    srcRect.y1 = 0
  else:
    srcRect.y1 = y1

  inc(srcRect.x2, border)
  inc(srcRect.y2, border)

  var dest = new Map
  dest.initMap(rect.height + border*2, rect.width + border*2)
  dest.copyFrom(destRow, destCol, src, srcRect)
  result = dest


proc newMapFrom*(m): Map =
  newMapFrom(m, rectN(0, 0, m.cols, m.rows))


proc getFloor*(m; r,c: Natural): Floor =
  assert r < m.rows
  assert c < m.cols
  m[r,c].floor

proc setFloor*(m; r,c: Natural, f: Floor) =
  assert r < m.rows
  assert c < m.cols
  m[r,c].floor = f

proc getFloorOrientation*(m; r,c: Natural): Orientation =
  assert r < m.rows
  assert c < m.cols
  m[r,c].floorOrientation

proc setFloorOrientation*(m; r,c: Natural, ot: Orientation) =
  assert r < m.rows
  assert c < m.cols
  m[r,c].floorOrientation = ot


proc getWall*(m; r,c: Natural, dir: CardinalDir): Wall =
  assert r < m.rows
  assert c < m.cols

  case dir
  of dirN: m[r,   c  ].wallN
  of dirW: m[r,   c  ].wallW
  of dirS: m[r+1, c  ].wallN
  of dirE: m[r,   c+1].wallW


proc isNeighbourCellEmpty*(m; r,c: Natural, dir: Direction): bool =
  assert r < m.rows
  assert c < m.cols

  if dir == North:
    result = r == 0 or m[r-1, c].floor == fNone
  elif dir == NorthEast:
    result = r == 0 or m[r-1, c+1].floor == fNone
  elif dir == East:
    result = m[r, c+1].floor == fNone
  elif dir == SouthEast:
    result = m[r+1, c+1].floor == fNone
  elif dir == South:
    result = m[r+1, c].floor == fNone
  elif dir == SouthWest:
    result = c == 0 or m[r+1, c-1].floor == fNone
  elif dir == West:
    result = c == 0 or m[r, c-1].floor == fNone
  elif dir == NorthWest:
    result = c == 0 or r == 0 or m[r-1, c-1].floor == fNone


proc canSetWall*(m; r,c: Natural, dir: CardinalDir): bool =
  assert r < m.rows
  assert c < m.cols

  m[r,c].floor != fNone or not isNeighbourCellEmpty(m, r,c, {dir})


proc setWall*(m; r,c: Natural, dir: CardinalDir, w: Wall) =
  assert r < m.rows
  assert c < m.cols

  case dir
  of dirN: m[r,   c  ].wallN = w
  of dirW: m[r,   c  ].wallW = w
  of dirS: m[r+1, c  ].wallN = w
  of dirE: m[r,   c+1].wallW = w


proc eraseCellWalls*(m; r,c: Natural) =
  assert r < m.rows
  assert c < m.cols

  m.setWall(r,c, dirN, wNone)
  m.setWall(r,c, dirW,  wNone)
  m.setWall(r,c, dirS, wNone)
  m.setWall(r,c, dirE,  wNone)


proc eraseOrphanedWalls*(m; r,c: Natural) =
  template cleanWall(dir: CardinalDir) =
    if m.isNeighbourCellEmpty(r,c, {dir}):
      m.setWall(r,c, dir, wNone)

  if m.getFloor(r,c) == fNone:
    cleanWall(dirN)
    cleanWall(dirW)
    cleanWall(dirS)
    cleanWall(dirE)


proc eraseCell*(m; r,c: Natural) =
  assert r < m.rows
  assert c < m.cols

  m.eraseCellWalls(r,c)
  m.setFloor(r,c, fNone)


proc guessFloorOrientation*(m; r,c: Natural): Orientation =
  if m.getWall(r,c, dirN) != wNone and
     m.getWall(r,c, dirS) != wNone:
    Vert
  else:
    Horiz


proc paste*(m; destRow, destCol: Natural, src: Map, sel: Selection) =
  let rect = rectN(
    destCol, destRow,
    destCol + src.cols, destRow + src.rows
  ).intersect(
    rectN(0, 0, m.cols, m.rows)
  )
  if rect.isSome:
    for r in 0..<rect.get.height:
      for c in 0..<rect.get.width:
        if sel[r,c]:
          let floor = src.getFloor(r,c)
          m.setFloor(destRow+r, destCol+c, floor)

          template copyWall(dir: CardinalDir) =
            let w = src.getWall(r,c, dir)
            m.setWall(destRow+r, destCol+c, dir, w)

          if floor == fNone:
            m.eraseOrphanedWalls(destRow+r, destCol+c)
          else:
            copyWall(dirN)
            copyWall(dirW)
            copyWall(dirS)
            copyWall(dirE)


proc noteKey(m; r,c: Natural): Natural =
  let h = m.rows
  let w = m.cols
  assert r < h
  assert c < w
  result = r*w + c

proc hasNote*(m; r,c: Natural): bool =
  let key = noteKey(m, r,c)
  m.notes.hasKey(key)

# TODO drop the option
proc getNote*(m; r,c: Natural): Option[Note] =
  let key = noteKey(m, r,c)
  if m.notes.hasKey(key):
    m.notes[key].some
  else:
    Note.none

proc setNote*(m; r,c: Natural, note: Note) =
  let key = noteKey(m, r,c)
  m.notes[key] = note

proc delNote*(m; r,c: Natural) =
  let key = noteKey(m, r,c)
  if m.notes.hasKey(key):
    let note = m.notes[key]
    m.notes.del(key)

    # Renumber indexed notes
    if note.kind == nkIndexed:
      let deletedIndex = note.index
      for n in m.notes.mvalues:
        if n.kind == nkIndexed and deletedIndex > note.index:
          dec(n.index)


proc numNotes*(m): Natural =
  m.notes.len

iterator allNotes*(m): (Natural, Natural, Note) =
  for k, note in m.notes.pairs:
    let
      row = k div m.cols
      col = k mod m.cols
    yield (row.Natural, col.Natural, note)


# vim: et:ts=2:sw=2:fdm=marker
