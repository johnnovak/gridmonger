import algorithm
import options
import tables

import common
import cellgrid
import rect
import selection


using l: Level

# {{{ newLevel*()
const DefaultCoordOpts = CoordinateOptions(
  origin:      coNorthWest,
  rowStyle:    csNumber,
  columnStyle: csNumber,
  rowStart:    1,
  columnStart: 1
)

const DefaultRegionOpts = RegionOptions(
  enableRegions:   false,
  regionColumns:   2,
  regionRows:      2,
  perRegionCoords: true
)

proc newLevel*(locationName, levelName: string, elevation: int,
               rows, cols: Natural,
               overrideCoordOpts: bool = false,
               coordOpts: CoordinateOptions = DefaultCoordOpts,
               regionOpts: RegionOptions = DefaultRegionOpts,
               regionNames: seq[string]=  @[]): Level =

  var l = new Level
  l.locationName = locationName
  l.levelName = levelName
  l.elevation = elevation

  l.overrideCoordOpts = overrideCoordOpts
  l.coordOpts = coordOpts

  l.regionOpts = regionOpts
  l.regionNames = regionNames

  l.cellGrid = newCellGrid(rows, cols)
  l.annotations = initTable[Natural, Annotation]()

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

# {{{ locationToKey()
template locationToKey(l; r,c: Natural): Natural =
  let h = l.rows
  let w = l.cols
  assert r < h
  assert c < w
  r*w + c

# }}}
# {{{ keyToLocation()
template keyToLocation(l; k: Natural): (Natural, Natural) =
  let
    w = l.cols
    r = (k div w).Natural
    c = (k mod w).Natural
  (r,c)

# }}}

# {{{ isLabel*()
func isLabel*(a: Annotation): bool = a.kind == akLabel

# }}}
# {{{ isNote*()
func isNote*(a: Annotation): bool = not a.isLabel

# }}}

# {{{ hasAnnotation*()
proc hasAnnotation*(l; r,c: Natural): bool {.inline.} =
  let key = l.locationToKey(r,c)
  l.annotations.hasKey(key)

# }}}
# {{{ getAnnotation*()
proc getAnnotation*(l; r,c: Natural): Option[Annotation] =
  let key = l.locationToKey(r,c)
  if l.annotations.hasKey(key):
    result = l.annotations[key].some

# }}}
# {{{ setAnnotation*()
proc setAnnotation*(l; r,c: Natural, a: Annotation) =
  let key = l.locationToKey(r,c)
  l.annotations[key] = a

# }}}
# {{{ delAnnotation*()
proc delAnnotation*(l; r,c: Natural) =
  let key = l.locationToKey(r,c)
  if l.annotations.hasKey(key):
    l.annotations.del(key)

# }}}

# {{{ numAnnotations*()
proc numAnnotations*(l): Natural =
  l.annotations.len

# }}}
# {{{ allAnnotations*()
iterator allAnnotations*(l): (Natural, Natural, Annotation) =
  for k, a in l.annotations.pairs:
    let (r,c) = l.keyToLocation(k)
    yield (r,c, a)

# }}}
# {{{ delAnnotations()
proc delAnnotations(l; rect: Rect[Natural]) =
  var toDel: seq[(Natural, Natural)]

  for r,c, _ in l.allAnnotations:
    if rect.contains(r,c):
      toDel.add((r,c))

  for (r,c) in toDel: l.delAnnotation(r,c)

# }}}
# {{{ copyAnnotationsFrom()
proc copyAnnotationsFrom(l; destRow, destCol: Natural,
                   src: Level, srcRect: Rect[Natural]) =
  for (r,c, a) in src.allAnnotations:
    if srcRect.contains(r,c):
      l.setAnnotation(destRow + r - srcRect.r1, destCol + c - srcRect.c1, a)

# }}}

# {{{ hasNote*()
proc hasNote*(l; r,c: Natural): bool =
  let a = l.getAnnotation(r,c)
  result = a.isSome and a.get.isNote

# }}}
# {{{ getNote*()
proc getNote*(l; r,c: Natural): Option[Annotation] =
  let a = l.getAnnotation(r,c)
  if a.isSome:
    if a.get.isNote: result = a

# }}}
# {{{ allNotes*()
iterator allNotes*(l): (Natural, Natural, Annotation) =
  for k, a in l.annotations.pairs:
    if a.isNote:
      let (r,c) = l.keyToLocation(k)
      yield (r,c, a)
    else:
      continue

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(l) =
  var keys: seq[int] = @[]
  for k, n in l.annotations.pairs():
    if n.kind == akIndexed:
      keys.add(k)

  sort(keys)
  for i, k in keys.pairs():
    l.annotations[k].index = i+1

# }}}

# {{{ hasLabel*()
proc hasLabel*(l; r,c: Natural): bool =
  let a = l.getAnnotation(r,c)
  result = a.isSome and a.get.isLabel

# }}}
# {{{ getLabel*()
proc getLabel*(l; r,c: Natural): Option[Annotation] =
  let a = l.getAnnotation(r,c)
  if a.isSome:
    if a.get.isLabel: result = a

# }}}
# {{{ allLabels*()
iterator allLabels*(l): (Natural, Natural, Annotation) =
  for k, a in l.annotations.pairs:
    if a.isLabel:
      let (r,c) = l.keyToLocation(k)
      yield (r,c, a)
    else:
      continue

# }}}

# {{{ isNeighbourCellEmpty*()
proc isNeighbourCellEmpty*(l; r,c: Natural, dir: Direction): bool {.inline.} =
  l.cellGrid.isNeighbourCellEmpty(r,c, dir)

# }}}
# {{{ isEmpty*()
proc isEmpty*(l; r,c: Natural): bool {.inline.} =
  l.cellGrid.isEmpty(r,c)

# }}}
# {{{ getFloor*()
proc getFloor*(l; r,c: Natural): Floor {.inline.} =
  l.cellGrid.getFloor(r,c)

# }}}
# {{{ convertNoteToComment()
proc convertNoteToComment(l; r,c: Natural) =
  let a = l.getAnnotation(r,c)
  if a.isSome:
    let note = a.get
    if note.kind != akComment:
      l.delAnnotation(r,c)

    if note.kind != akLabel:
      let comment = Annotation(kind: akComment, text: note.text)
      l.setAnnotation(r,c, comment)

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
proc getFloorColor*(l; r,c: Natural): byte {.inline.} =
  l.cellGrid.getFloorColor(r,c)

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(l; r,c: Natural, col: byte) {.inline.} =
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
# {{{ canSetWall*()
proc canSetWall*(l; r,c: Natural, dir: CardinalDir): bool {.inline.} =
  l.getFloor(r,c) != fNone or not l.isNeighbourCellEmpty(r,c, {dir})

# }}}
# {{{ getNeighbourCell*()
proc getNeighbourCell*(l; r,c: Natural,
                       dir: Direction): Option[Cell] {.inline.} =
  l.cellGrid.getNeighbourCell(r,c, dir)

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
  l.delAnnotation(r,c)

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

          l.delAnnotation(r,c)
          if src.hasAnnotation(srcRow, srcCol):
            l.setAnnotation(r,c, src.getAnnotation(srcRow, srcCol).get)

# }}}

# {{{ copyCellsAndAnnotationsFrom*(()
proc copyCellsAndAnnotationsFrom*(l; destRow, destCol: Natural,
               src: Level, srcRect: Rect[Natural]) =

  l.cellGrid.copyFrom(destRow, destCol, src.cellGrid, srcRect)

  l.delAnnotations(rectN(destRow, destCol,
                   destRow + srcRect.rows, destCol + srcRect.cols))

  l.copyAnnotationsFrom(destRow, destCol, src, srcRect)

# }}}
# {{{ newLevelFrom*()
proc newLevelFrom*(src: Level, rect: Rect[Natural],
                   border: Natural=0): Level =
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

  # TODO region names needs to be updated when resizing the level
  # (search for newRegionNames and update all occurences)
  let newRegionNames = src.regionNames

  var dest = newLevel(src.locationName, src.levelName, src.elevation,
                      rows = rect.rows + border*2,
                      cols = rect.cols + border*2,
                      src.overrideCoordOpts, src.coordOpts,
                      src.regionOpts, newRegionNames)

  dest.copyCellsAndAnnotationsFrom(destRow, destCol, src, srcRect)

  result = dest

# }}}
# {{{ newLevelFrom*()
proc newLevelFrom*(l): Level =
  newLevelFrom(l, rectN(0, 0, l.rows, l.cols))

# }}}

# vim: et:ts=2:sw=2:fdm=marker
