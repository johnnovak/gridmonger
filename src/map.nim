import options
import tables

import common
import selection


using m: Map

proc noteKey(m; r,c: Natural): Natural =
  let h = m.rows
  let w = m.cols
  assert r < h
  assert c < w
  result = r*w + c

proc hasNote*(m; r,c: Natural): bool =
  let key = noteKey(m, r,c)
  m.notes.hasKey(key)

proc getNote*(m; r,c: Natural): Note =
  let key = noteKey(m, r,c)
  m.notes[key]

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


proc delNotes(m; rect: Rect[Natural]) =
  var toDel: seq[(Natural, Natural)]
  for r,c, _ in m.allNotes():
    if rect.contains(r,c):
      toDel.add((r,c))

  for (r,c) in toDel: m.delNote(r,c)

proc maxNoteIndex*(m): Natural =
  for n in m.notes.values():
    if n.kind == nkIndexed:
      result = max(result, n.index)


proc copyNotesFrom(m; destRow, destCol: Natural,
                   src: Map, srcRect: Rect[Natural]) =
  for (r,c, note) in src.allNotes():
    if srcRect.contains(r,c):
      m.setNote(destRow + r - srcRect.r1, destCol + c - srcRect.c1, note)


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
  assert rect.r1 < m.rows
  assert rect.c1 < m.cols
  assert rect.r2 <= m.rows
  assert rect.c2 <= m.cols

  # TODO fill border
  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      m[r,c] = cell


proc fill*(m; cell: Cell) =
  let rect = rectN(0, 0, m.rows, m.cols)
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


proc copyFrom*(m; destRow, destCol: Natural,
               src: Map, srcRect: Rect[Natural]) =
  # This function cannot fail as the copied area is clipped to the extents of
  # the destination area (so nothing gets copied in the worst case).
  let
    # TODO use rect.intersect
    srcCol = srcRect.c1
    srcRow = srcRect.r1
    srcRows = max(src.rows - srcRow, 0)
    srcCols = max(src.cols - srcCol, 0)
    destRows = max(m.rows - destRow, 0)
    destCols = max(m.cols - destCol, 0)

    rows = min(min(srcRows, destRows), srcRect.rows)
    cols = min(min(srcCols,  destCols),  srcRect.cols)

  for r in 0..<rows:
    for c in 0..<cols:
      m[destRow+r, destCol+c] = src[srcRow+r, srcCol+c]

  # Copy the South walls of the bottommost "edge" row
  for c in 0..<cols:
    m[destRow+rows, destCol+c].wallN = src[srcRow+rows, srcCol+c].wallN

  # Copy the East walls of the rightmost "edge" column
  for r in 0..<rows:
    m[destRow+r, destCol+cols].wallW = src[srcRow+r, srcCol+cols].wallW

  m.delNotes(rectN(destRow, destCol,
                   destRow + srcRect.rows, destCol + srcRect.cols))

  m.copyNotesFrom(destRow, destCol, src, srcRect)


proc copyFrom*(m; src: Map) =
  m.copyFrom(destRow=0, destCol=0,
             src, srcRect=rectN(0, 0, src.rows, src.cols))


proc newMapFrom*(src: Map, rect: Rect[Natural], border: Natural = 0): Map =
  assert rect.r1 < src.rows
  assert rect.c1 < src.cols
  assert rect.r2 <= src.rows
  assert rect.c2 <= src.cols

  var
    destRow = 0
    destCol = 0
    srcRect = rect

  let r1 = srcRect.r1.int - border
  if r1 < 0:
    destRow = -r1
    srcRect.r1 = 0
  else:
    srcRect.r1 = r1

  let c1 = srcRect.c1.int - border
  if c1 < 0:
    destCol = -c1
    srcRect.c1 = 0
  else:
    srcRect.c1 = c1

  inc(srcRect.r2, border)
  inc(srcRect.c2, border)

  var dest = newMap(rect.rows + border*2, rect.cols + border*2)
  dest.copyFrom(destRow, destCol, src, srcRect)

  result = dest


proc newMapFrom*(m): Map =
  newMapFrom(m, rectN(0, 0, m.rows, m.cols))


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
  m.delNote(r,c)


proc guessFloorOrientation*(m; r,c: Natural): Orientation =
  if m.getWall(r,c, dirN) != wNone and
     m.getWall(r,c, dirS) != wNone:
    Vert
  else:
    Horiz


proc paste*(m; destRow, destCol: Natural, src: Map, sel: Selection) =
  let destRect = rectN(
    destRow,
    destCol,
    destRow + src.rows,
    destCol + src.cols
  ).intersect(
    rectN(0, 0, m.rows, m.cols)
  )
  if destRect.isSome:
    for r in 0..<destRect.get.rows:
      for c in 0..<destRect.get.cols:
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

          m.delNote(destRow+r, destCol+c)
          if src.hasNote(r,c):
            m.setNote(destRow+r, destCol+c, src.getNote(r,c))


# vim: et:ts=2:sw=2:fdm=marker
