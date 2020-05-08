import algorithm
import options
import tables

import common
import cellgrid
import rect
import selection


using l: Level

proc newLevel*(locationName, levelName: string, elevation: int,
               rows, cols: Natural): Level =

  result = new Level
  result.locationName = locationName
  result.levelName = levelName
  result.elevation = elevation
  result.cellGrid = newCellGrid(rows, cols)
  result.notes = initTable[Natural, Note]()


proc rows*(l): Natural {.inline.} = l.cellGrid.rows
proc cols*(l): Natural {.inline.} = l.cellGrid.cols


template locationKey(m; r,c: Natural): Natural =
  let h = m.rows
  let w = m.cols
  assert r < h
  assert c < w
  r*w + c

proc numNotes*(l): Natural =
  l.notes.len

proc hasNote*(l; r,c: Natural): bool {.inline.} =
  let key = locationKey(l, r,c)
  l.notes.hasKey(key)

proc getNote*(l; r,c: Natural): Note =
  let key = locationKey(l, r,c)
  l.notes[key]

proc setNote*(l; r,c: Natural, note: Note) =
  let key = locationKey(l, r,c)
  l.notes[key] = note

proc delNote*(l; r,c: Natural) =
  let key = locationKey(l, r,c)
  if l.notes.hasKey(key):
    l.notes.del(key)

proc reindexNotes*(l) =
  var keys: seq[int] = @[]
  for k, n in l.notes.pairs():
    if n.kind == nkIndexed:
      keys.add(k)
  sort(keys)
  for i, k in keys.pairs():
    l.notes[k].index = i+1

iterator allNotes*(l): (Natural, Natural, Note) =
  for k, note in l.notes.pairs:
    let
      row = k div l.cols
      col = k mod l.cols
    yield (row.Natural, col.Natural, note)

proc delNotes(l; rect: Rect[Natural]) =
  var toDel: seq[(Natural, Natural)]
  for r,c, _ in l.allNotes():
    if rect.contains(r,c):
      toDel.add((r,c))
  for (r,c) in toDel: l.delNote(r,c)

proc convertNoteToComment(l; r,c: Natural) =
  if l.hasNote(r,c):
    let note = l.getNote(r,c)
    if note.kind != nkComment:
      l.delNote(r,c)
      let commentNote = Note(kind: nkComment, text: note.text)
      l.setNote(r,c, commentNote)

proc copyNotesFrom(l; destRow, destCol: Natural,
                   src: Level, srcRect: Rect[Natural]) =
  for (r,c, note) in src.allNotes():
    if srcRect.contains(r,c):
      l.setNote(destRow + r - srcRect.r1, destCol + c - srcRect.c1, note)


proc getFloor*(l; r,c: Natural): Floor {.inline.} =
  l.cellGrid.getFloor(r,c)

proc setFloor*(l; r,c: Natural, f: Floor) =
  l.convertNoteToComment(r,c)
  l.cellGrid.setFloor(r,c, f)

proc getWall*(l; r,c: Natural, dir: CardinalDir): Wall {.inline.} =
  l.cellGrid.getWall(r,c, dir)

proc setWall*(l; r,c: Natural, dir: CardinalDir, w: Wall)  {.inline.} =
  l.cellGrid.setWall(r,c, dir, w)

proc getFloorOrientation*(l; r,c: Natural): Orientation {.inline.} =
  l.cellGrid.getFloorOrientation(r,c)

proc setFloorOrientation*(l; r,c: Natural, ot: Orientation) =
  l.cellGrid.setFloorOrientation(r,c, ot)

proc isNeighbourCellEmpty*(l; r,c: Natural, dir: Direction): bool =
  l.cellGrid.isNeighbourCellEmpty(r,c, dir)

proc isFloorEmpty*(l; r,c: Natural): bool {.inline.} =
  l.cellGrid.isFloorEmpty(r,c)

proc canSetWall*(l; r,c: Natural, dir: CardinalDir): bool =
  l.getFloor(r,c) != fNone or not l.isNeighbourCellEmpty(r,c, {dir})

proc eraseOrphanedWalls*(l; r,c: Natural) =
  template cleanWall(dir: CardinalDir) =
    if l.isNeighbourCellEmpty(r,c, {dir}):
      l.setWall(r,c, dir, wNone)

  if l.isFloorEmpty(r,c):
    cleanWall(dirN)
    cleanWall(dirW)
    cleanWall(dirS)
    cleanWall(dirE)


proc paste*(l; destRow, destCol: int, src: Level,
            sel: Selection): Option[Rect[Natural]] =

  let destRect = rectI(
    destRow, destCol,
    destRow + src.rows, destCol + src.cols
  ).intersect(
    rectI(0, 0, l.rows, l.cols)
  )

  if destRect.isSome:
    let dr = destRect.get
    result = rectN(dr.r1, dr.c1, dr.r2, dr.c2).some

    for r in dr.r1..<dr.r2:
      for c in dr.c1..<dr.c2:
        var srcRow = r - dr.r1
        var srcCol = c - dr.c1
        if destRow < 0: inc(srcRow, -destRow)
        if destCol < 0: inc(srcCol, -destCol)

        if sel[srcRow, srcCol]:
          let floor = src.getFloor(srcRow, srcCol)
          l.setFloor(r,c, floor)

          let ot = src.getFloorOrientation(srcRow, srcCol)
          l.setFloorOrientation(r,c, ot)

          template copyWall(dir: CardinalDir) =
            let w = src.getWall(srcRow, srcCol, dir)
            l.setWall(r,c, dir, w)

          if floor.isFloorEmpty:
            l.eraseOrphanedWalls(r,c)
          else:
            copyWall(dirN)
            copyWall(dirW)
            copyWall(dirS)
            copyWall(dirE)

          l.delNote(r,c)
          if src.hasNote(srcRow, srcCol):
            l.setNote(r,c, src.getNote(srcRow, srcCol))


proc copyFrom*(l; destRow, destCol: Natural,
               src: Level, srcRect: Rect[Natural]) =

  l.cellGrid.copyFrom(destRow, destCol, src.cellGrid, srcRect)

  l.delNotes(rectN(destRow, destCol,
                   destRow + srcRect.rows, destCol + srcRect.cols))

  l.copyNotesFrom(destRow, destCol, src, srcRect)


proc newLevelFrom*(src: Level, rect: Rect[Natural],
                   border: Natural = 0): Level =
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

  var dest = newLevel(src.locationName, src.levelName, src.elevation,
                      rect.rows + border*2, rect.cols + border*2)
  dest.copyFrom(destRow, destCol, src, srcRect)

  result = dest


proc newLevelFrom*(l): Level =
  newLevelFrom(l, rectN(0, 0, l.rows, l.cols))


proc eraseCellWalls*(l; r,c: Natural) =
  l.setWall(r,c, dirN, wNone)
  l.setWall(r,c, dirW,  wNone)
  l.setWall(r,c, dirS, wNone)
  l.setWall(r,c, dirE,  wNone)

proc eraseCell*(l; r,c: Natural) =
  l.eraseCellWalls(r,c)
  l.setFloor(r,c, fNone)
  l.delNote(r,c)

proc guessFloorOrientation*(l; r,c: Natural): Orientation =
  if l.getWall(r,c, dirN) != wNone and
     l.getWall(r,c, dirS) != wNone:
    Vert
  else:
    Horiz


proc resize*(l; newRows, newCols: Natural, align: Direction): Level =
  var srcRect = rectI(0, 0, l.rows, l.cols)

  proc shiftHoriz(r: var Rect[int], d: int) =
    r.c1 += d
    r.c2 += d

  proc shiftVert(r: var Rect[int], d: int) =
    r.r1 += d
    r.r2 += d

  if dirE in align:
    srcRect.shiftHoriz(newCols - l.cols)
  elif {dirE, dirW} * align == {}:
    srcRect.shiftHoriz((newCols - l.cols) div 2)

  if dirS in align:
    srcRect.shiftVert(newRows - l.rows)
  elif {dirS, dirN} * align == {}:
    srcRect.shiftVert((newRows - l.rows) div 2)

  let destRect = rectI(0, 0, newRows, newCols)
  var intRect = srcRect.intersect(destRect).get

  var copyRect: Rect[Natural]
  var destRow = 0
  if srcRect.r1 < 0: copyRect.r1 = -srcRect.r1
  else: destRow = srcRect.r1

  var destCol = 0
  if srcRect.c1 < 0: copyRect.c1 = -srcRect.c1
  else: destCol = srcRect.c1

  copyRect.r2 = copyRect.r1 + intRect.rows
  copyRect.c2 = copyRect.c1 + intRect.cols

  result = newLevel(l.locationName, l.levelName, l.elevation,
                    newRows, newCols)

  result.copyFrom(destRow, destCol, l, copyRect)


proc isSpecialLevelIndex*(idx: Natural): bool =
  idx >= CopyBufferLevelIndex

# }}}
