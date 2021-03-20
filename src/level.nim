import options
import tables

import annotations
import common
import cellgrid
import rect
import regions
import selection


using l: Level

const
  # internal IDs, never written to disk
  CopyBufferLevelIndex* = 1_000_000
  MoveBufferLevelIndex* = 1_000_001

# {{{ newLevel*()
const DefaultCoordOpts = CoordinateOptions(
  origin:      coNorthWest,
  rowStyle:    csNumber,
  columnStyle: csNumber,
  rowStart:    1,
  columnStart: 1
)

const DefaultRegionOpts = RegionOptions(
  enabled:         false,
  regionColumns:   2,
  regionRows:      2,
  perRegionCoords: true
)

proc newLevel*(locationName, levelName: string, elevation: int,
               rows, cols: Natural,
               overrideCoordOpts: bool = false,
               coordOpts: CoordinateOptions = DefaultCoordOpts,
               regionOpts: RegionOptions = DefaultRegionOpts): Level =

  var l = new Level
  l.locationName = locationName
  l.levelName = levelName
  l.elevation = elevation

  l.overrideCoordOpts = overrideCoordOpts
  l.coordOpts = coordOpts

  l.regionOpts = regionOpts
  l.regions = initTable[RegionCoords, Region]()

  l.cellGrid = newCellGrid(rows, cols)
  l.annotations = newAnnotations(rows, cols)

  result = l

# }}}

# {{{ CellGrid
# {{{ rows*()
proc rows*(l): Natural {.inline.} =
  l.cellGrid.rows

# }}}
# {{{ cols*()
proc cols*(l): Natural {.inline.} =
  l.cellGrid.cols

# }}}

# {{{ isEmpty*()
proc isEmpty*(l; r,c: Natural): bool {.inline.} =
  l.cellGrid.isEmpty(r,c)

# }}}
# {{{ isNeighbourCellEmpty*()
proc isNeighbourCellEmpty*(l; r,c: Natural, dir: Direction): bool {.inline.} =
  l.cellGrid.isNeighbourCellEmpty(r,c, dir)

# }}}
# {{{ getNeighbourCell*()
proc getNeighbourCell*(l; r,c: Natural,
                       dir: Direction): Option[Cell] {.inline.} =
  l.cellGrid.getNeighbourCell(r,c, dir)

# }}}

# {{{ getFloor*()
proc getFloor*(l; r,c: Natural): Floor {.inline.} =
  l.cellGrid.getFloor(r,c)

# }}}
# {{{ setFloor*()
proc setFloor*(l; r,c: Natural, f: Floor) =
  l.annotations.convertNoteToComment(r,c)
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
  not l.isEmpty(r,c) or not l.isNeighbourCellEmpty(r,c, {dir})

# }}}
# }}}
# {{{ Annotations
# {{{ getAnnotation*()
proc getAnnotation*(l; r,c: Natural): Option[Annotation] =
  l.annotations.getAnnotation(r,c)

# }}}
# {{{ setAnnotation*()
proc setAnnotation*(l; r,c: Natural, a: Annotation) =
  l.annotations.setAnnotation(r,c, a)

# }}}
# {{{ delAnnotation*()
proc delAnnotation*(l; r,c: Natural) =
  l.annotations.delAnnotation(r,c)

# }}}
# {{{ numAnnotations*()
proc numAnnotations*(l): Natural =
  l.annotations.numAnnotations()

# }}}
# {{{ allAnnotations*()
template allAnnotations*(a): (Natural, Natural, Annotation) =
  l.annotations.allAnnotations()

# }}}

# {{{ hasNote*()
proc hasNote*(l; r,c: Natural): bool =
  l.annotations.hasNote(r,c)

# }}}
# {{{ getNote*()
proc getNote*(l; r,c: Natural): Option[Annotation] =
  l.annotations.getNote(r,c)

# }}}
# {{{ allNotes*()
template allNotes*(l): (Natural, Natural, Annotation) =
  l.annotations.allNotes()

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(l) =
  l.annotations.reindexNotes()

# }}}

# {{{ hasLabel*()
proc hasLabel*(l; r,c: Natural): bool =
  l.annotations.hasLabel(r,c)

# }}}
# {{{ getLabel*()
proc getLabel*(l; r,c: Natural): Option[Annotation] =
  l.annotations.getLabel(r,c)

# }}}
# {{{ allLabels*()
template allLabels*(l): (Natural, Natural, Annotation) =
  l.annotations.allLabels()

# }}}
# }}}
# {{{ Regions
# {{{ setRegion*()
proc setRegion*(l; rc: RegionCoords, region: Region) =
  l.regions.setRegion(rc, region)

# }}}
# {{{ getRegion*()
proc getRegion*(l; rc: RegionCoords): Option[Region] =
  l.regions.getRegion(rc)

# }}}
# {{{ allRegions*()
template allRegions*(l): (RegionCoords, Region) =
  l.regions.allRegions()

# }}}
# {{{ numRegions*()
proc numRegions*(l): Natural =
  l.regions.numRegions()

# }}}
# {{{ regionNames*()
proc regionNames*(l): seq[string] =
  l.regions.regionNames()

# }}}
# {{{ findFirstRegionByName*()
proc findFirstRegionByName*(l; name: string): Option[(RegionCoords, Region)] =
  l.regions.findFirstRegionByName(name)

# }}}
# }}}

# {{{ hasTrail*()
proc hasTrail*(l; r,c: Natural): bool {.inline.} =
  l.cellGrid.hasTrail(r,c)

# }}}
# {{{ setTrail*()
proc setTrail*(l; r,c: Natural, t: bool) {.inline.} =
  l.cellGrid.setTrail(r,c, t)

# }}}
# {{{ calcTrailBoundingBox*()
proc calcTrailBoundingBox*(l): Option[Rect[Natural]] {.inline.} =
  l.cellGrid.calcTrailBoundingBox()

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
  l.setFloor(r,c, fEmpty)
  l.annotations.delAnnotation(r,c)

# }}}

# {{{ paste*()
proc paste*(l; destRow, destCol: int, src: Level,
            sel: Selection, pasteTrail: bool = false): Option[Rect[Natural]] =

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

          if pasteTrail:
            l.setTrail(r,c, src.hasTrail(srcRow, srcCol))

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

          l.annotations.delAnnotation(r,c)
          if src.annotations.hasAnnotation(srcRow, srcCol):
            l.annotations.setAnnotation(
              r,c, src.annotations.getAnnotation(srcRow, srcCol).get
            )

# }}}

# {{{ copyAnnotationsFrom*()
proc copyAnnotationsFrom*(l; destRow, destCol: Natural,
                          src: Level, srcRect: Rect[Natural]) =
  for (r,c, a) in src.annotations.allAnnotations:
    if srcRect.contains(r,c):
      l.annotations.setAnnotation(destRow + r - srcRect.r1,
                                  destCol + c - srcRect.c1, a)

# }}}
# {{{ copyCellsAndAnnotationsFrom*(()
proc copyCellsAndAnnotationsFrom*(l; destRow, destCol: Natural,
               src: Level, srcRect: Rect[Natural]) =

  l.cellGrid.copyFrom(destRow, destCol, src.cellGrid, srcRect)

  l.annotations.delAnnotations(
    rectN(destRow, destCol, destRow + srcRect.rows, destCol + srcRect.cols)
  )

  l.copyAnnotationsFrom(destRow, destCol, src, srcRect)

# }}}
# {{{ newLevelFrom*()
proc newLevelFrom*(src: Level, rect: Rect[Natural], border: Natural=0): Level =
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
  var dest = newLevel(src.locationName, src.levelName, src.elevation,
                      rows = rect.rows + border*2,
                      cols = rect.cols + border*2,
                      src.overrideCoordOpts, src.coordOpts,
                      src.regionOpts)

  dest.copyCellsAndAnnotationsFrom(destRow, destCol, src, srcRect)

  result = dest


proc newLevelFrom*(l): Level =
  newLevelFrom(l, rectN(0, 0, l.rows, l.cols))

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

# {{{ getRegionCoords*()
proc getRegionCoords*(l; r,c: Natural): RegionCoords =
  let regionCol = c div l.regionOpts.regionColumns

  let row = case l.coordOpts.origin
            of coNorthWest: r
            of coSouthWest: l.rows-1 - r

  let regionRow = row div l.regionOpts.regionRows

  RegionCoords(row: regionRow, col: regionCol)

# }}}
# {{{ getRegionCenterLocation*()
proc getRegionCenterLocation*(l; rc: RegionCoords): (Natural, Natural) =
  let cols = l.regionOpts.regionColumns
  let rows = l.regionOpts.regionRows

  let c = (rc.col * cols).int

  let r = case l.coordOpts.origin
          of coNorthWest: rc.row * rows
          of coSouthWest: (l.rows+1).int - (rc.col+1)*cols

  let centerRow = (r + l.regionOpts.regionRows    div 2).clamp(0, l.rows-1)
  let centerCol = (c + l.regionOpts.regionColumns div 2).clamp(0, l.cols-1)

  (centerRow.Natural, centerCol.Natural)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
