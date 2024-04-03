import std/math
import std/options
import std/strformat

import annotations
import common
import cellgrid
import rect
import regions
import selection


using l: Level

const MoveBufferLevelId* = Natural.high

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
# {{{ cleearFloor*()
proc clearFloor*(l; r,c: Natural) =
  l.cellGrid.setFloor(r,c, fBlank)

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
  l.annotations[r,c]

# }}}
# {{{ setAnnotation*()
proc setAnnotation*(l; r,c: Natural, a: Annotation) =
  l.annotations[r,c] = a

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
template allAnnotations*(a): tuple[row, col: Natural,
                                   annotation: Annotation] =
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
template allNotes*(l): tuple[row, col: Natural, annotation: Annotation] =
  l.annotations.notes()

# }}}
# {{{ reindexNotes*()
proc reindexNotes*(l) =
  l.annotations.reindexNotes

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
template allLabels*(l): tuple[row, col: Natural, annotation: Annotation] =
  l.annotations.allLabels

# }}}
#
# {{{ copyAnnotationsFrom*()
proc copyAnnotationsFrom*(l; destRow, destCol: Natural,
                          srcLevel: Level, srcRect: Rect[Natural]) =
  for r,c, a in srcLevel.annotations.allAnnotations:
    if srcRect.contains(r,c):
      l.annotations[destRow + r - srcRect.r1,
                    destCol + c - srcRect.c1] = a

# }}}

# }}}

# {{{ regionRows*()
proc regionRows*(l; ro: RegionOptions): Natural =
  ceil(l.rows / ro.rowsPerRegion).int

proc regionRows*(l): Natural = l.regionRows(l.regionOpts)

# }}}
# {{{ regionCols*()
proc regionCols*(l; ro: RegionOptions): Natural =
  ceil(l.cols / ro.colsPerRegion).int

proc regionCols*(l): Natural = l.regionCols(l.regionOpts)

# }}}
# {{{ allRegionCoords*()
iterator allRegionCoords*(l): RegionCoords =
  for r in 0..<l.regionRows:
    for c in 0..<l.regionCols:
      yield RegionCoords(row: r, col: c)

# }}}

# {{{ initRegionsFrom*()
proc initRegionsFrom*(srcLevel: Option[Level] = Level.none, destLevel: Level,
                      regionRowOffs: int = 0,
                      regionColOffs: int = 0): Regions =

  var destRegions = initRegions()
  var index = 1

  for destRegionCoord in destLevel.allRegionCoords:
    let srcRegionRow = destRegionCoord.row.int + regionRowOffs
    let srcRegionCol = destRegionCoord.col.int + regionColOffs

    let srcRegion = if srcLevel.isNone or srcRegionRow < 0 or srcRegionCol < 0:
                      Region.none
                    else:
                      let rc = RegionCoords(row: srcRegionRow,
                                            col: srcRegionCol)
                      srcLevel.get.regions[rc]

    if srcRegion.isSome and not srcRegion.get.isUntitledRegion():
      destRegions[destRegionCoord] = srcRegion.get
    else:
      let name = destLevel.regions.nextUntitledRegionName(index)
      destRegions[destRegionCoord] = initRegion(name=name)

  result = destRegions

# }}}

# }}}

# {{{ getDetailedName*()
proc getDetailedName*(l; short = false): string =
  let elevation = if l.elevation == 0: "G" else: $l.elevation
  if l.levelName == "":
    fmt"{l.locationName} ({elevation})"
  else:
    if short:
      fmt"{l.levelName} ({elevation})"
    else:
      fmt"{l.locationName} {EnDash} {l.levelName} ({elevation})"

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
  l.cellGrid.calcTrailBoundingBox

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
  l.setWall(r,c, dirW, wNone)
  l.setWall(r,c, dirS, wNone)
  l.setWall(r,c, dirE, wNone)

# }}}
# {{{ eraseCell*()
proc eraseCell*(l; r,c: Natural) =
  l.eraseCellWalls(r,c)
  l.setFloor(r,c, fEmpty)
  l.annotations.delAnnotation(r,c)

# }}}

# {{{ copyCellsAndAnnotationsFrom*(()
proc copyCellsAndAnnotationsFrom*(l; destRow, destCol: Natural,
                                  srcLevel: Level, srcRect: Rect[Natural]) =

  l.cellGrid.copyFrom(destRow, destCol, srcLevel.cellGrid, srcRect)

  l.annotations.delAnnotations(
    rectN(destRow, destCol, destRow + srcRect.rows, destCol + srcRect.cols)
  )

  l.copyAnnotationsFrom(destRow, destCol, srcLevel, srcRect)

# }}}

# {{{ copyCell()
proc copyCell(destLevel: Level, destRow, destCol: Natural,
              srcLevel: Level, srcRow, srcCol: Natural,
              pasteTrail: bool = false) =

  let floor = srcLevel.getFloor(srcRow, srcCol)
  destLevel.setFloor(destRow, destCol, floor)

  let floorColor = srcLevel.getFloorColor(srcRow, srcCol)
  destLevel.setFloorColor(destRow, destCol, floorColor)

  let ot = srcLevel.getFloorOrientation(srcRow, srcCol)
  destLevel.setFloorOrientation(destRow, destCol, ot)

  if pasteTrail:
    destLevel.setTrail(destRow, destCol, srcLevel.hasTrail(srcRow, srcCol))

  template copyWall(dir: CardinalDir) =
    let w = srcLevel.getWall(srcRow, srcCol, dir)
    destLevel.setWall(destRow, destCol, dir, w)

  if floor.isEmpty:
    destLevel.eraseOrphanedWalls(destRow, destCol)
  else:
    copyWall(dirN)
    copyWall(dirW)
    copyWall(dirS)
    copyWall(dirE)

  destLevel.annotations.delAnnotation(destRow, destCol)

  let a = srcLevel.annotations[srcRow, srcCol]
  if a.isSOme:
    destLevel.annotations[destRow, destCol] = a.get

# }}}
# {{{ paste*()
proc paste*(l; destRow, destCol: int, srcLevel: Level, sel: Selection,
            pasteTrail: bool = false): Option[Rect[Natural]] =

  let destRect = rectI(
    destRow, destCol,
    destRow + srcLevel.rows, destCol + srcLevel.cols
  ).intersect(
    rectI(0,0, l.rows, l.cols)
  )

  if destRect.isSome:
    let d = destRect.get
    result = rectN(d.r1, d.c1, d.r2, d.c2).some

    for r in d.r1..<d.r2:
      for c in d.c1..<d.c2:
        var srcRow = r - d.r1
        var srcCol = c - d.c1
        if destRow < 0: inc(srcRow, -destRow)
        if destCol < 0: inc(srcCol, -destCol)

        if sel[srcRow, srcCol]:
          copyCell(destLevel=l, destRow=r, destCol=c,
                   srcLevel, srcRow, srcCol, pasteTrail)

# }}}
# {{{ pasteWithWraparound*()
proc pasteWithWraparound*(l; destRow, destCol: int, srcLevel: Level,
                          sel: Selection, pasteTrail: bool = false,
                          levelRows, levelCols: Natural,
                          selStartRow, selStartCol: int,
                          destStartRow:  Natural = 0,
                          destStartCol:  Natural = 0,
                          destRowOffset: Natural = 0,
                          destColOffset: Natural = 0): Option[Rect[Natural]] =

  # The 'dest' params are for working with the "oversized" paste preview
  # buffers.

#  echo "---------------------------------"
#  echo fmt"destLevel: {l.rows} x {l.cols}, destRow: {destRow}, destCol: {destCol}"
#  echo fmt"srcLevel: {srcLevel.rows} x {srcLevel.cols}, selection: {sel.rows} x {sel.cols}"
#  echo fmt"levelRows: {levelRows}, levelCols: {levelCols}"
#  echo fmt"selStartRow: {selStartRow}, selStartCol: {selStartCol}"
#  echo fmt"destStartRow: {destStartRow}, destStartCol: {destStartCol}"
#  echo fmt"destRowOffset: {destRowOffset}, destColOffset: {destColOffset}"

  for srcRow in 0..<srcLevel.rows:
    for srcCol in 0..<srcLevel.cols:
      if sel[srcRow, srcCol]:
        # Don't allow large levels to wrap around multiple times
        if srcRow >= levelRows or srcCol >= levelCols:
          continue

        let
          wrappedRow = (selStartRow + srcRow).floorMod(levelRows)
          wrappedCol = (selStartCol + srcCol).floorMod(levelCols)

          dr = wrappedRow.int + destRowOffset - destStartRow
          dc = wrappedCol.int + destColOffset - destStartCol

        if wrappedRow >= destStartRow and dr < l.rows and
           wrappedCol >= destStartCol and dc < l.cols:

          copyCell(destLevel=l, destRow=dr, destCol=dc,
                   srcLevel, srcRow, srcCol, pasteTrail)

# }}}

# {{{ guessFloorOrientation*()
proc guessFloorOrientation*(l; r,c: Natural): Orientation =
  if l.getWall(r,c, dirN) != wNone and
     l.getWall(r,c, dirS) != wNone:
    Vert
  else:
    Horiz

# }}}
# {{{ getSrcRectAlignedToDestRect*()
proc getSrcRectAlignedToDestRect*(
  l; newRows, newCols: Natural, anchor: Direction
): Rect[int] =

  var srcRect = rectI(0, 0, l.rows, l.cols)

  # Align srcRect to destRect
  srcRect.shiftHoriz(
    if    dirE in anchor:              newCols - l.cols
    elif {dirE, dirW} * anchor == {}: (newCols - l.cols) div 2
    else:                              0
  )

  srcRect.shiftVert(
    if    dirS in anchor:              newRows - l.rows
    elif {dirS, dirN} * anchor == {}: (newRows - l.rows) div 2
    else:                              0
  )

  result = srcRect

# }}}
# {{{ calcResizeParams*()
proc calcResizeParams*(
  l; newRows, newCols: Natural, anchor: Direction
): tuple[copyRect: Rect[Natural], destRow, destCol: Natural] =

  let
    srcRect = getSrcRectAlignedToDestRect(l, newRows, newCols, anchor)
    destRect = rectI(0, 0, newRows, newCols)
    intRect = srcRect.intersect(destRect).get

  var
    copyRect: Rect[Natural]
    destRow, destCol: int

  if srcRect.r1 < 0: copyRect.r1 = -srcRect.r1
  else: destRow = srcRect.r1

  if srcRect.c1 < 0: copyRect.c1 = -srcRect.c1
  else: destCol = srcRect.c1

  copyRect.r2 = copyRect.r1 + intRect.rows
  copyRect.c2 = copyRect.c1 + intRect.cols

  result = (copyRect, destRow.Natural, destCol.Natural)

# }}}
# {{{ isSpecialLevelId*()
proc isSpecialLevelId*(id: Natural): bool =
  id >= MoveBufferLevelId

# }}}

# {{{ newLevel*()

var g_levelIdCounter = 0

const DefaultCoordOpts = CoordinateOptions(
  origin:      coNorthWest,
  rowStyle:    csNumber,
  columnStyle: csNumber,
  rowStart:    1,
  columnStart: 1
)

const DefaultRegionOpts = RegionOptions(
  enabled:         false,
  rowsPerRegion:   2,
  colsPerRegion:   2,
  perRegionCoords: true
)

proc newLevel*(locationName, levelName: string, elevation: int,
               rows, cols: Natural,
               overrideCoordOpts = false,
               coordOpts: CoordinateOptions = DefaultCoordOpts,
               regionOpts: RegionOptions = DefaultRegionOpts,
               notes: string = "",
               initRegions = true,
               overrideId: Option[Natural] = Natural.none): Level =

  var l = new Level

  if overrideId.isSome:
    l.id = overrideId.get
  else:
    l.id = g_levelIdCounter
    inc(g_levelIdCounter)

  l.locationName = locationName
  l.levelName    = levelName
  l.elevation    = elevation

  l.overrideCoordOpts = overrideCoordOpts
  l.coordOpts = coordOpts

  l.cellGrid = newCellGrid(rows, cols)
  l.annotations = newAnnotations(rows, cols)

  l.regionOpts = regionOpts

  l.notes = notes

  if initRegions and l.regionOpts.enabled:
    l.regions = initRegionsFrom(destLevel=l)

  l.dirty = true

  result = l

# }}}
# {{{ calcNewLevelFromParams*()
proc calcNewLevelFromParams*(
  srcLevel: Level, srcRect: Rect[Natural], border: Natural = 0
): tuple[copyRect: Rect[Natural], destRow, destCol: Natural] =

  assert srcRect.r1  < srcLevel.rows
  assert srcRect.c1  < srcLevel.cols
  assert srcRect.r2 <= srcLevel.rows
  assert srcRect.c2 <= srcLevel.cols

  var
    copyRect: Rect[Natural]
    destRow, destCol: int

  let r1 = srcRect.r1.int - border
  if r1 < 0:
    destRow = -r1
    copyRect.r1 = 0
  else:
    destRow = 0
    copyRect.r1 = r1

  let c1 = srcRect.c1.int - border
  if c1 < 0:
    destCol = -c1
    copyRect.c1 = 0
  else:
    destCol = 0
    copyRect.c1 = c1

  copyRect.r2 = srcRect.r2 + border
  copyRect.c2 = srcRect.c2 + border

  result = (copyRect, destRow.Natural, destCol.Natural)

# }}}
# {{{ newLevelFrom*()

# NOTE: This method doesn't copy the regions.

proc newLevelFrom*(srcLevel: Level, srcRect: Rect[Natural],
                   border: Natural = 0,
                   overrideId: Option[Natural] = Natural.none): Level =

  let (copyRect, destRow, destCol) = calcNewLevelFromParams(srcLevel, srcRect,
                                                            border)

  result = newLevel(
    srcLevel.locationName, srcLevel.levelName, srcLevel.elevation,
    rows = srcRect.rows + border*2,
    cols = srcRect.cols + border*2,
    srcLevel.overrideCoordOpts, srcLevel.coordOpts, srcLevel.regionOpts,
    srcLevel.notes,
    initRegions = false,
    overrideId = overrideId
  )

  result.copyCellsAndAnnotationsFrom(destRow, destCol, srcLevel, copyRect)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
