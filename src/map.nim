import options
import tables

import common
import selection


using m: Map

proc cellIndex(m; c, r: Natural): Natural =
  # We need to be able to address the bottommost & rightmost "edge" columns
  # & rows within the module.
  let w = m.cols+1
  let h = m.rows+1
  assert c < w
  assert r < h
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
  m.name = "Untitled"
  m.cols = cols
  m.rows = rows

  # We're storing one extra row & column at the bottom-right edges ("edge"
  # columns & rows) so we can store the South and East walls of the bottommost
  # row and rightmost column, respectively.
  newSeq(m.cells, (cols+1) * (rows+1))

  m.notes = initTable[Natural, Note]()


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


proc newMapFrom*(src: Map, rect: Rect[Natural], border: Natural = 0): Map =
  assert rect.x1 < src.cols
  assert rect.y1 < src.rows
  assert rect.x2 <= src.cols
  assert rect.y2 <= src.rows

  var
    destCol = 0
    destRow = 0
    srcRect = rect

  dec(srcRect.x1, border)
  if srcRect.x1 < 0:
    destCol = -srcRect.x1
    srcRect.x1 = 0

  dec(srcRect.y1, border)
  if srcRect.y1 < 0:
    destRow = -srcRect.y1
    srcRect.y1 = 0

  inc(srcRect.x2, border)
  inc(srcRect.y2, border)

  var dest = new Map
  dest.initMap(rect.width + border*2, rect.height + border*2)
  dest.copyFrom(destCol, destRow, src, srcRect)
  result = dest


proc newMapFrom*(m): Map =
  newMapFrom(m, rectN(0, 0, m.cols, m.rows))


proc getFloor*(m; c, r: Natural): Floor =
  assert c < m.cols
  assert r < m.rows
  m[c,r].floor

proc getFloorOrientation*(m; c, r: Natural): Orientation =
  assert c < m.cols
  assert r < m.rows
  m[c,r].floorOrientation

proc setFloorOrientation*(m; c, r: Natural, ot: Orientation) =
  assert c < m.cols
  assert r < m.rows
  m[c,r].floorOrientation = ot


proc setFloor*(m; c, r: Natural, f: Floor) =
  assert c < m.cols
  assert r < m.rows
  m[c,r].floor = f


proc getWall*(m; c, r: Natural, dir: CardinalDir): Wall =
  assert c < m.cols
  assert r < m.rows

  case dir
  of dirN: m[c,   r  ].wallN
  of dirW: m[c,   r  ].wallW
  of dirS: m[c,   r+1].wallN
  of dirE: m[c+1, r  ].wallW


proc isNeighbourCellEmpty*(m; c, r: Natural, dir: Direction): bool =
  assert c < m.cols
  assert r < m.rows

  if dir == North:
    result = r == 0 or m[c, r-1].floor == fNone
  elif dir == NorthEast:
    result = r == 0 or m[c+1, r-1].floor == fNone
  elif dir == East:
    result = m[c+1, r].floor == fNone
  elif dir == SouthEast:
    result = m[c+1, r+1].floor == fNone
  elif dir == South:
    result = m[c, r+1].floor == fNone
  elif dir == SouthWest:
    result = c == 0 or m[c-1, r+1].floor == fNone
  elif dir == West:
    result = c == 0 or m[c-1, r].floor == fNone
  elif dir == NorthWest:
    result = c == 0 or r == 0 or m[c-1, r-1].floor == fNone


proc canSetWall*(m; c, r: Natural, dir: CardinalDir): bool =
  assert c < m.cols
  assert r < m.rows

  m[c,r].floor != fNone or not isNeighbourCellEmpty(m, c, r, {dir})


proc setWall*(m; c, r: Natural, dir: CardinalDir, w: Wall) =
  assert c < m.cols
  assert r < m.rows

  case dir
  of dirN: m[c,   r  ].wallN = w
  of dirW: m[c,   r  ].wallW = w
  of dirS: m[c,   r+1].wallN = w
  of dirE: m[c+1, r  ].wallW = w


proc eraseCellWalls*(m; c, r: Natural) =
  assert c < m.cols
  assert r < m.rows

  m.setWall(c,r, dirN, wNone)
  m.setWall(c,r, dirW,  wNone)
  m.setWall(c,r, dirS, wNone)
  m.setWall(c,r, dirE,  wNone)


proc eraseOrphanedWalls*(m; c, r: Natural) =
  template cleanWall(dir: CardinalDir) =
    if m.isNeighbourCellEmpty(c,r, {dir}):
      m.setWall(c,r, dir, wNone)

  if m.getFloor(c,r) == fNone:
    cleanWall(dirN)
    cleanWall(dirW)
    cleanWall(dirS)
    cleanWall(dirE)


proc eraseCell*(m; c, r: Natural) =
  assert c < m.cols
  assert r < m.rows

  m.eraseCellWalls(c, r)
  m.setFloor(c, r, fNone)


proc guessFloorOrientation*(m; c, r: Natural): Orientation =
  if m.getWall(c, r, dirN) != wNone and m.getWall(c, r, dirS) != wNone: Vert
  else: Horiz


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
          let floor = src.getFloor(c,r)
          m.setFloor(destCol+c, destRow+r, floor)

          template copyWall(dir: CardinalDir) =
            let w = src.getWall(c,r, dir)
            m.setWall(destCol+c, destRow+r, dir, w)

          if floor == fNone:
            m.eraseOrphanedWalls(destCol+c, destRow+r)
          else:
            copyWall(dirN)
            copyWall(dirW)
            copyWall(dirS)
            copyWall(dirE)


proc noteKey(m; c, r: Natural): Natural =
  let w = m.cols
  let h = m.rows
  assert c < w
  assert r < h
  result = w*r + c

proc hasNote*(m; c, r: Natural): bool =
  let key = noteKey(m, c, r)
  m.notes.hasKey(key)

proc getNote*(m; c, r: Natural): Option[Note] =
  let key = noteKey(m, c, r)
  if m.notes.hasKey(key):
    m.notes[key].some
  else:
    Note.none

proc setNote*(m; c, r: Natural, note: Note) =
  let key = noteKey(m, c, r)
  m.notes[key] = note

proc delNote*(m; c, r: Natural) =
  let key = noteKey(m, c, r)
  if m.notes.hasKey(key):
    let note = m.notes[key]
    m.notes.del(key)

    # Renumber indexed notes
    if note.kind == nkIndexed:
      let deletedIndex = note.index
      for n in m.notes.mvalues:
        if n.kind == nkIndexed and deletedIndex > note.index:
          dec(n.index)


iterator notes*(m): (Natural, Natural, Note) =
  for k, note in m.notes.pairs:
    let
      row = k div m.cols
      col = k mod m.cols
    yield (col.Natural, row.Natural, note)


# vim: et:ts=2:sw=2:fdm=marker
