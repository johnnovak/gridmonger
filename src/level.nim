import algorithm
import options
import tables

import common
import cellgrid
import rect
import selection


using l: Level

# {{{ newLevel*()
proc newLevel*(locationName, levelName: string, elevation: int,
               rows, cols: Natural): Level =

  var l = new Level
  l.locationName = locationName
  l.levelName = levelName
  l.elevation = elevation

  l.overrideCoordOpts = false
  l.coordOpts = CoordinateOptions(
    origin:      coNorthWest,
    rowStyle:    csNumber,
    columnStyle: csNumber,
    rowStart:    1,
    columnStart: 1
  )

  l.regionOpts = RegionOptions(
    enableRegions: false,
    regionColumns: 2,
    regionRows:    2
  )
  l.regionNames = @[]

  l.cellGrid = newCellGrid(rows, cols)
  l.notes = initTable[Natural, Note]()

  result = l

# }}}
# {{{ rows*()
proc rows*(l): Natural {.inline.} =
  l.cellGrid.rows

# }}}
# {{{ cols*()
proc cols*(l): Natural {.inline.} =
  l.cellGrid.cols

# }}}

# {{{ locationKey()
template locationKey(m; r,c: Natural): Natural =
  let h = m.rows
  let w = m.cols
  assert r < h
  assert c < w
  r*w + c

# }}}

# {{{ numNotes*()
proc numNotes*(l): Natural =
  l.notes.len

# }}}
# {{{ hasNote*()
proc hasNote*(l; r,c: Natural): bool {.inline.} =
  let key = locationKey(l, r,c)
  l.notes.hasKey(key)

# }}}
# {{{ getNote*()
proc getNote*(l; r,c: Natural): Note =
  let key = locationKey(l, r,c)
  l.notes[key]

# }}}
# {{{ setNote*()
proc setNote*(l; r,c: Natural, note: Note) =
  let key = locationKey(l, r,c)
  l.notes[key] = note

# }}}
# {{{ delNote*()
proc delNote*(l; r,c: Natural) =
  let key = locationKey(l, r,c)
  if l.notes.hasKey(key):
    l.notes.del(key)

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(l) =
  var keys: seq[int] = @[]
  for k, n in l.notes.pairs():
    if n.kind == nkIndexed:
      keys.add(k)
  sort(keys)
  for i, k in keys.pairs():
    l.notes[k].index = i+1

# }}}
# {{{ allNotes*()
iterator allNotes*(l): (Natural, Natural, Note) =
  for k, note in l.notes.pairs:
    let
      row = k div l.cols
      col = k mod l.cols
    yield (row.Natural, col.Natural, note)

# }}}
# {{{ delNotes()
proc delNotes(l; rect: Rect[Natural]) =
  var toDel: seq[(Natural, Natural)]
  for r,c, _ in l.allNotes:
    if rect.contains(r,c):
      toDel.add((r,c))
  for (r,c) in toDel: l.delNote(r,c)

# }}}
# {{{ convertNoteToComment()
proc convertNoteToComment(l; r,c: Natural) =
  if l.hasNote(r,c):
    let note = l.getNote(r,c)
    if note.kind != nkComment:
      l.delNote(r,c)
      let commentNote = Note(kind: nkComment, text: note.text)
      l.setNote(r,c, commentNote)

# }}}
# {{{ copyNotesFrom()
proc copyNotesFrom(l; destRow, destCol: Natural,
                   src: Level, srcRect: Rect[Natural]) =
  for (r,c, note) in src.allNotes:
    if srcRect.contains(r,c):
      l.setNote(destRow + r - srcRect.r1, destCol + c - srcRect.c1, note)

# }}}

# {{{ getFloor*()
proc getFloor*(l; r,c: Natural): Floor {.inline.} =
  l.cellGrid.getFloor(r,c)

# }}}
# {{{ setFloor*()
proc setFloor*(l; r,c: Natural, f: Floor) =
  l.convertNoteToComment(r,c)
  l.cellGrid.setFloor(r,c, f)

# }}}
# {{{ getFloorOrientation*()
proc getFloorOrientation*(l; r,c: Natural): Orientation {.inline.} =
  l.cellGrid.getFloorOrientation(r,c)

# }}}
# {{{ setFloorOrientation*()
proc setFloorOrientation*(l; r,c: Natural, ot: Orientation) {.inline.} =
  l.cellGrid.setFloorOrientation(r,c, ot)

# }}}
# {{{ getFloorColor*()
proc getFloorColor*(l; r,c: Natural): Natural {.inline.} =
  l.cellGrid.getFloorColor(r,c)

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(l; r,c, col: Natural) {.inline.} =
  l.cellGrid.setFloorColor(r,c, col)

# }}}
# {{{ getWall*()
proc getWall*(l; r,c: Natural, dir: CardinalDir): Wall {.inline.} =
  l.cellGrid.getWall(r,c, dir)

# }}}
# {{{ setWall*()
proc setWall*(l; r,c: Natural, dir: CardinalDir, w: Wall) {.inline.} =
  l.cellGrid.setWall(r,c, dir, w)

# }}}
# {{{ getNeighbourCell*()
proc getNeighbourCell*(l; r,c: Natural,
                       dir: Direction): Option[Cell] {.inline.} =
  l.cellGrid.getNeighbourCell(r,c, dir)

# }}}
# {{{ isNeighbourCellEmpty*()
proc isNeighbourCellEmpty*(l; r,c: Natural, dir: Direction): bool {.inline.} =
  l.cellGrid.isNeighbourCellEmpty(r,c, dir)

# }}}
# {{{ isEmpty*()
proc isEmpty*(l; r,c: Natural): bool {.inline.} =
  l.cellGrid.isEmpty(r,c)

# }}}
# {{{ canSetWall*()
proc canSetWall*(l; r,c: Natural, dir: CardinalDir): bool {.inline.} =
  l.getFloor(r,c) != fNone or not l.isNeighbourCellEmpty(r,c, {dir})

# }}}

# {{{ eraseOrphanedWalls*()
proc eraseOrphanedWalls*(l; r,c: Natural) =
  template cleanWall(dir: CardinalDir) =
    if l.isNeighbourCellEmpty(r,c, {dir}):
      l.setWall(r,c, dir, wNone)

  if l.isEmpty(r,c):
    cleanWall(dirN)
    cleanWall(dirW)
    cleanWall(dirS)
    cleanWall(dirE)

# }}}
# {{{ eraseCellWalls*()
proc eraseCellWalls*(l; r,c: Natural) =
  l.setWall(r,c, dirN, wNone)
  l.setWall(r,c, dirW,  wNone)
  l.setWall(r,c, dirS, wNone)
  l.setWall(r,c, dirE,  wNone)

# }}}
# {{{ eraseCell*()
proc eraseCell*(l; r,c: Natural) =
  l.eraseCellWalls(r,c)
  l.setFloor(r,c, fNone)
  l.delNote(r,c)

# }}}

# {{{ guessFloorOrientation*()
proc guessFloorOrientation*(l; r,c: Natural): Orientation =
  if l.getWall(r,c, dirN) != wNone and
     l.getWall(r,c, dirS) != wNone:
    Vert
  else:
    Horiz

# }}}
# {{{ calcResizeParams*()
proc calcResizeParams*(
  l; newRows, newCols: Natural, align: Direction
 ): tuple[destRow, destCol: Natural, copyRect: Rect[Natural]] =

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

  result = (destRow.Natural, destCol.Natural, copyRect)

# }}}
# {{{ isSpecialLevelIndex*()
proc isSpecialLevelIndex*(idx: Natural): bool =
  idx >= CopyBufferLevelIndex

# }}}

# {{{ paste*()
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

          let floorColor = src.getFloorColor(srcRow, srcCol)
          l.setFloorColor(r,c, floorColor)

          let ot = src.getFloorOrientation(srcRow, srcCol)
          l.setFloorOrientation(r,c, ot)

          template copyWall(dir: CardinalDir) =
            let w = src.getWall(srcRow, srcCol, dir)
            l.setWall(r,c, dir, w)

          if floor.isEmpty:
            l.eraseOrphanedWalls(r,c)
          else:
            copyWall(dirN)
            copyWall(dirW)
            copyWall(dirS)
            copyWall(dirE)

          l.delNote(r,c)
          if src.hasNote(srcRow, srcCol):
            l.setNote(r,c, src.getNote(srcRow, srcCol))

# }}}

# {{{ copyFrom*(()
proc copyFrom*(l; destRow, destCol: Natural,
               src: Level, srcRect: Rect[Natural]) =

  l.cellGrid.copyFrom(destRow, destCol, src.cellGrid, srcRect)

  l.delNotes(rectN(destRow, destCol,
                   destRow + srcRect.rows, destCol + srcRect.cols))

  l.copyNotesFrom(destRow, destCol, src, srcRect)

# }}}
# {{{ newLevelFrom*()
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

  dest.overrideCoordOpts = src.overrideCoordOpts
  dest.coordOpts = src.coordOpts
  dest.regionOpts = src.regionOpts
  dest.regionNames = src.regionNames

  result = dest

# }}}
# {{{ newLevelFrom*()
proc newLevelFrom*(l): Level =
  newLevelFrom(l, rectN(0, 0, l.rows, l.cols))

# }}}


# vim: et:ts=2:sw=2:fdm=marker
