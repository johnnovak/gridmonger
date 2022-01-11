import lenientops
import math
import options

import glad/gl
import koi
import nanovg

import annotations
import bitable
import cellgrid
import common
import icons
import level
import links
import rect
import selection
import utils


const
  MinZoomLevel* = 1
  MaxZoomLevel* = 20
  MinGridSize   = 13.0
  ZoomStep      = 2.0

  UltrathinStrokeWidth = 1.0

  MinLineHatchSize = 3
  MaxLineHatchSize = 8

  DefaultIconFontSizeFactor = 0.53


# Naming conventions
# ------------------
#
# The names `row`, `col` (or `r`, `c`) refer to the zero-based coordinates of
# a cell in a map. The cell in the top-left corner is the origin.
#
# `viewRow` and `viewCol` refer to the zero-based cell coodinates of
# a rectangular subarea of the map (the active view).
#
# Anything with `x` or `y` in the name refers to pixel-coordinates within the
# window's drawing area (top-left corner is the origin).
#
# All drawing procs interpret the passed in `(x,y)` coordinates as the
# upper-left corner of the object (e.g. a cell).
#

# {{{ Types
type
  DrawLevelContext* = object
    ls*: LevelStyle
    dp*: DrawLevelParams
    vg*: NVGContext

  DrawLevelParams* = ref object
    startX*:       float
    startY*:       float

    cursorRow*:    Natural
    cursorCol*:    Natural
    cursorOrient*: Option[CardinalDir]

    viewStartRow*: Natural
    viewStartCol*: Natural
    viewRows*:     Natural
    viewCols*:     Natural

    backgroundImage*: Option[Paint]

    # The current selection; it has the same dimensions as the map
    selection*:        Option[Selection]

    # Used for drawing the rect highlight in rect draw mode
    selectionRect*:    Option[SelectionRect]

    # Used as either the copy buffer or the nudge buffer
    selectionBuffer*:  Option[SelectionBuffer]

    # Start drawing coords for the selection buffer (can be negative)
    selStartRow*:      int
    selStartCol*:      int

    drawCellCoords*:   bool
    cellCoordOpts*:    CoordinateOptions
    regionOpts*:       RegionOptions

    drawCursorGuides*: bool

    # internal
    zoomLevel:          Natural
    gridSize:           float
    cellCoordsFontSize: float

    thinStrokeWidth:    float
    normalStrokeWidth:  float

    lineWidth:          LineWidth

    # Various correction factors
    vertTransformXOffs:    float
    vertRegionBorderYOffs: float

    lineHatchPatterns:  LineHatchPatterns
    lineHatchSize:      range[MinLineHatchSize..MaxLineHatchSize]


  Outline = enum
    olN, olNE, olE, olSE, olS, olSW, olW, olNW

  OutlineCell = set[Outline]

  OutlineBuf = ref object
    rows, cols: Natural
    cells:      seq[OutlineCell]

  LineHatchPatterns = array[MinLineHatchSize..MaxLineHatchSize, Paint]


proc newOutlineBuf(rows, cols: Natural): OutlineBuf =
  var b = new OutlineBuf
  b.rows = rows
  b.cols = cols
  newSeq(b.cells, b.rows * b.cols)
  result = b

proc `[]=`(b: OutlineBuf, r,c: Natural, cell: OutlineCell) =
  assert r < b.rows
  assert c < b.cols
  b.cells[r*b.cols + c] = cell

proc `[]`(b: OutlineBuf, r,c: Natural): OutlineCell =
  assert r < b.rows
  assert c < b.cols
  result = b.cells[r*b.cols + c]

# }}}

const
  ViewBufBorder = MaxLabelWidthInCells

using
  ls:  LevelStyle
  dp:  DrawLevelParams
  ctx: DrawLevelContext

# {{{ newDrawLevelParams*()
{.push warning[ProveInit]:off.}

proc newDrawLevelParams*(): DrawLevelParams =
  result = new DrawLevelParams
  for paint in result.lineHatchPatterns.mitems:
    paint.image = NoImage

  result.zoomLevel = MinZoomLevel

{.pop}
# }}}

# {{{ getZoomLevel*()
proc getZoomLevel*(dp): Natural = dp.zoomLevel

# }}}
# {{{ setZoomLevel*()
proc setZoomLevel*(dp; ls; zl: Natural) =
  assert zl >= MinZoomLevel
  assert zl <= MaxZoomLevel

  dp.zoomLevel = zl
  dp.gridSize = MinGridSize + zl*ZoomStep

  dp.lineWidth = ls.lineWidth

  if dp.lineWidth == lwThin:
    dp.thinStrokeWidth = 1.0
    dp.normalStrokeWidth = 1.0
    dp.vertTransformXOffs = 1.0
    dp.vertRegionBorderYOffs = 0.0

  elif zl < 3 or dp.lineWidth == lwNormal:
    dp.thinStrokeWidth = 2.0
    dp.normalStrokeWidth = 2.0
    dp.vertTransformXOffs = 0.0
    dp.vertRegionBorderYOffs = -1.0

  dp.cellCoordsFontSize = if   zl <= 2:   9.0
                          elif zl <= 3:  10.0
                          elif zl <= 7:  11.0
                          elif zl <= 11: 12.0
                          else:          13.0

  dp.lineHatchSize = if   zl ==  1: 3
                     elif zl <=  5: 4
                     elif zl <=  9: 5
                     elif zl <= 12: 6
                     elif zl <= 17: 7
                     else:          8

# }}}
# {{{ incZoomLevel*()
proc incZoomLevel*(ls; dp) =
  if dp.zoomLevel < MaxZoomLevel:
    dp.setZoomLevel(ls, dp.zoomLevel+1)

# }}}
# {{{ decZoomLevel*()
proc decZoomLevel*(ls; dp) =
  if dp.zoomLevel > MinZoomLevel:
    dp.setZoomLevel(ls, dp.zoomLevel-1)

# }}}
# {{{ numDisplayableRows*()
proc numDisplayableRows*(dp; height: float): Natural =
  max(height / dp.gridSize, 0).int

# }}}
# {{{ numDisplayableCols*()
proc numDisplayableCols*(dp; width: float): Natural =
  max(width / dp.gridSize, 0).int

# }}}
# {{{ gridSize*()
proc gridSize*(dp): float = dp.gridSize

# }}}

# {{{ Utils

# This is needed for drawing crisp lines
func snap(f: float, strokeWidth: float): float =
  let (i, _) = splitDecimal(f)
  let (_, offs) = splitDecimal(strokeWidth*0.5) # either 0 or 0.5
  result = i + offs

proc cellX(x: int, dp): float =
  dp.startX + dp.gridSize * x

proc cellY(y: int, dp): float =
  dp.startY + dp.gridSize * y

proc isCursorActive(viewRow, viewCol: Natural, dp): bool =
  dp.selectionBuffer.isNone and
  dp.viewStartRow + viewRow == dp.cursorRow and
  dp.viewStartCol + viewCol == dp.cursorCol

proc setVertTransform(x, y: float; ctx) =
  let dp = ctx.dp
  let vg = ctx.vg

  # We need to use some fudge factor here because of the grid snapping...
  vg.translate(x + dp.vertTransformXOffs, y)
  vg.rotate(degToRad(90.0))

# }}}

# {{{ renderLineHatchPatterns()
proc renderLineHatchPatterns(dp; vg: NVGContext, pxRatio: float,
                             strokeColor: Color) =

  for spacing in dp.lineHatchPatterns.low..dp.lineHatchPatterns.high:
    var sp = spacing * pxRatio

    var image = vg.renderToImage(
      width  = sp.int,
      height = sp.int,
      getPxRatio(),
      {ifRepeatX, ifRepeatY}
    ):
      var sw: float
      if pxRatio == 1.0:
        if spacing <= 4:
          sw = 1.0
          vg.shapeAntiAlias(false)
        else:
          sw = 0.8
      else:
        sw = 2.0

      vg.strokeColor(strokeColor)
      vg.strokeWidth(sw)

      vg.beginPath()
      for i in 0..10:
        vg.moveTo(-2, i*sp + 2.0)
        vg.lineTo(i*sp + 2.0, -2)
      vg.stroke()

      vg.shapeAntiAlias(true)


    dp.lineHatchPatterns[spacing] = vg.imagePattern(
      ox=0, oy=0, ex=spacing.float, ey=spacing.float, angle=0,
      image, alpha=1.0
    )

# }}}
# {{{ initDrawLevelParams
proc initDrawLevelParams*(dp; ls; vg: NVGContext, pxRatio: float) =
  for paint in dp.lineHatchPatterns:
    if paint.image != NoImage:
      vg.deleteImage(paint.image)

  renderLineHatchPatterns(dp, vg, pxRatio, ls.foregroundNormalColor)

  dp.setZoomLevel(ls, dp.zoomLevel)

# }}}
# {{{ calcBlendedFloorColor*()
func calcBlendedFloorColor*(floorColor: Natural, transparentFloor: bool = false;
                            ls: LevelStyle): Color =
  let fc = ls.floorBackgroundColor[floorColor]

  if transparentFloor: fc
  else:
    let fc0 = ls.floorBackgroundColor[0]
    let baseBg = lerp(ls.backgroundColor.withAlpha(1.0),
                      fc0.withAlpha(1.0),
                      fc0.a)
    lerp(baseBg, fc, fc.a)

# }}}
# {{{ setLevelClippingRect()
proc setLevelClippingRect(l: Level; ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  let (ox, oy, ow, oh) =
    if dp.regionOpts.enabled:
      case dp.lineWidth
      of lwNormal: (-1, -1,  3,  3)
      of lwThin:   ( 0, -1,  2,  2)
    else:
      case dp.lineWidth
      of lwNormal: (-1, -1,  2,  2)
      of lwThin:   ( 0,  0,  1,  1)

  var
    x = dp.startX + ox
    y = dp.startY + oy
    w = dp.gridSize * dp.viewCols + ow
    h = dp.gridSize * dp.viewRows + oh

  if ls.outlineOverscan:
    let
      gs = dp.gridSize
      viewEndRow = dp.viewStartRow + dp.viewRows-1
      viewEndCol = dp.viewStartCol + dp.viewCols-1

    if dp.viewStartRow == 0:
      y -= gs
      h += gs

    if dp.viewStartCol == 0:
      x -= gs
      w += gs

    if viewEndRow == l.rows-1: h += gs
    if viewEndCol == l.cols-1: w += gs

  vg.intersectScissor(x, y, w, h)

# }}}

proc toBufRow(viewRow: Natural): Natural = viewRow + ViewBufBorder

proc toBufCol(viewCol: Natural): Natural = viewCol + ViewBufBorder

# {{{ forAllViewCells_CellCoords()
template forAllViewCells_CellCoords(body: untyped) =
  for viewRow {.inject.} in 0..<dp.viewRows:
    for viewCol {.inject.} in 0..<dp.viewCols:
      let row {.inject.} = dp.viewStartRow + viewRow
      let col {.inject.} = dp.viewStartCol + viewCol
      body
# }}}

# {{{ drawBackground()
proc drawBackground(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fillColor(ls.backgroundColor)

  let
    w = dp.gridSize * dp.viewCols + 1
    h = dp.gridSize * dp.viewRows + 1

  vg.beginPath()
  vg.rect(dp.startX, dp.startY, w, h)
  vg.fill()

# }}}
# {{{ drawBackgroundHatch()
proc drawBackgroundHatch(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = ls.backgroundHatchWidth

  vg.save()

  vg.strokeColor(ls.backgroundHatchColor)
  vg.strokeWidth(sw)

  let
    w = dp.gridSize * dp.viewCols + 1
    h = dp.gridSize * dp.viewRows + 1
    offs = max(w, h)
    lineSpacing = sw * ls.backgroundHatchSpacingFactor

  let startX = snap(dp.startX, sw)
  let startY = snap(dp.startY, sw)

  vg.intersectScissor(dp.startX, dp.startY, w, h)

  var
    x1 = startX - offs
    y1 = startY + offs
    x2 = startX + offs
    y2 = startY - offs

  vg.beginPath()
  while x1 < dp.startX + offs:
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    x1 += lineSpacing
    x2 += lineSpacing
    y1 += lineSpacing
    y2 += lineSpacing
  vg.stroke()

  vg.restore()

# }}}
# {{{ drawCellCoords()
proc drawCellCoords(l: Level; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fontSize(dp.cellCoordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fontFace("sans-bold")
      vg.fillColor(ls.coordinatesHighlightColor)
    else:
      vg.fontFace("sans")
      vg.fillColor(ls.coordinatesNormalColor)

  let endX = dp.startX + dp.gridSize * dp.viewCols
  let endY = dp.startY + dp.gridSize * dp.viewRows

  let fontSize = dp.cellCoordsFontSize

  var x1f, x2f, y1f, y2f: float
  if ls.outlineOverscan:
    x1f = 1.7
    x2f = 1.8
    y1f = 1.5
    y2f = 1.8
  else:
    x1f = 1.3
    x2f = 1.5
    y1f = 1.2
    y2f = 1.4

  for c in 0..<dp.viewCols:
    let
      xPos = cellX(c, dp) + dp.gridSize*0.5
      col = dp.viewStartCol + c
      coord = formatColumnCoord(col, l.cols, dp.cellCoordOpts, dp.regionOpts)

    setTextHighlight(col == dp.cursorCol)

    discard vg.text(xPos, dp.startY - fontSize*y1f, coord)
    discard vg.text(xPos, endY + fontSize*y2f, coord)

  for r in 0..<dp.viewRows:
    let
      yPos = cellY(r, dp) + dp.gridSize*0.5
      row = dp.viewStartRow + r
      coord = formatRowCoord(row, l.rows, dp.cellCoordOpts, dp.regionOpts)

    setTextHighlight(row == dp.cursorRow)

    discard vg.text(dp.startX - fontSize*x1f, yPos, coord)
    discard vg.text(endX + fontSize*x2f, yPos, coord)


# }}}
# {{{ drawCellOutlines()
proc drawCellOutlines(l: Level; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  func isOutline(r,c: Natural): bool =
    not (
      isNeighbourCellEmpty(l, r,c, North)     and
      isNeighbourCellEmpty(l, r,c, NorthEast) and
      isNeighbourCellEmpty(l, r,c, East)      and
      isNeighbourCellEmpty(l, r,c, SouthEast) and
      isNeighbourCellEmpty(l, r,c, South)     and
      isNeighbourCellEmpty(l, r,c, SouthWest) and
      isNeighbourCellEmpty(l, r,c, West)      and
      isNeighbourCellEmpty(l, r,c, NorthWest)
    )

  let sw = UltrathinStrokeWidth

  vg.strokeWidth(sw)
  vg.fillColor(ls.outlineColor)
  vg.strokeColor(ls.outlineColor)
  vg.beginPath()

  forAllViewCells_CellCoords:
    if l.isEmpty(row, col) and isOutline(row, col):
      let x = snap(cellX(viewCol, dp), sw)
      let y = snap(cellY(viewRow, dp), sw)

      vg.rect(x, y, dp.gridSize, dp.gridSize)

  vg.fill()
  vg.stroke()

# }}}
# {{{ drawCellHighlight()
proc drawCellHighlight(x, y: float; color: Color; ctx) =
  let vg = ctx.vg
  let dp = ctx.dp

  vg.beginPath()
  vg.fillColor(color)
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawCursor()
proc drawCursor(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let viewRow = dp.cursorRow - dp.viewStartRow
  let viewCol = dp.cursorCol - dp.viewStartCol

  if viewRow >= 0 and viewRow < dp.viewRows and
     viewCol >= 0 and viewCol < dp.viewCols:

    let
      x = cellX(viewCol, dp)
      y = cellY(viewRow, dp)
      a = dp.gridSize
      a2 = a*0.5

    vg.fillColor(ls.cursorColor)
    vg.beginPath()

    if dp.cursorOrient.isSome:
      case dp.cursorOrient.get
      of dirN:
        vg.moveTo(x,    y+a)
        vg.lineTo(x+a2, y)
        vg.lineTo(x+a,  y+a)

      of dirE:
        vg.moveTo(x,   y)
        vg.lineTo(x+a, y+a2)
        vg.lineTo(x,   y+a)

      of dirS:
        vg.moveTo(x, y)
        vg.lineTo(x+a2, y+a)
        vg.lineTo(x+a, y)

      of dirW:
        vg.moveTo(x+a, y)
        vg.lineTo(x,   y+a2)
        vg.lineTo(x+a, y+a)
    else:
      vg.rect(x, y, a, a)

    vg.fill()

# }}}
# {{{ drawCursorGuides()
proc drawCursorGuides(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    x = cellX(dp.cursorCol - dp.viewStartCol, dp)
    y = cellY(dp.cursorRow - dp.viewStartRow, dp)
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows

  vg.fillColor(ls.cursorGuidesColor)
  vg.strokeColor(ls.cursorGuidesColor)
  let sw = UltrathinStrokeWidth
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x, sw), snap(dp.startY, sw), dp.gridSize, h)
  vg.fill()
  vg.stroke()

  vg.beginPath()
  vg.rect(snap(dp.startX, sw), snap(y, sw), w, dp.gridSize)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawEdgeOutlines()
proc drawEdgeOutlines(l: Level, ob: OutlineBuf; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  case ls.outlineFillStyle
  of ofsSolid:   vg.fillColor(ls.outlineColor)
  of ofsHatched: vg.fillPaint(dp.lineHatchPatterns[dp.lineHatchSize])

  proc draw(r,c: int, cell: OutlineCell) =
    let
      x = cellX(c, dp)
      y = cellY(r, dp)
      gs = dp.gridSize
      w  = dp.gridSize * ls.outlineWidthFactor + 1
      x1 = x
      x2 = x + gs
      y1 = y
      y2 = y + gs

    proc drawRoundedEdges() =
      if olN in cell: vg.rect(x1, y1, gs, w)
      if olE in cell: vg.rect(x2-w, y1, w, gs)
      if olS in cell: vg.rect(x1, y2-w, gs, w)
      if olW in cell: vg.rect(x1, y1, w, gs)

      if olNW in cell:
        vg.moveTo(x1, y1)
        vg.arc(x1, y1, w, 0, PI*0.5, pwCW)
        vg.lineTo(x1, y1)
        vg.closePath()

      if olNE in cell:
        vg.moveTo(x2, y1)
        vg.arc(x2, y1, w, PI*0.5, PI, pwCW)
        vg.lineTo(x2, y1)
        vg.closePath()

      if olSE in cell:
        vg.moveTo(x2, y2)
        vg.arc(x2, y2, w, PI, PI*1.5, pwCW)
        vg.lineTo(x2, y2)
        vg.closePath()

      if olSW in cell:
        vg.moveTo(x1, y2)
        vg.arc(x1, y2, w, PI*1.5, 0, pwCW)
        vg.lineTo(x1, y2)
        vg.closePath()


    proc drawSquareEdges() =
      if olN in cell:    vg.rect(x1, y1, gs, w)
      else:
        if olNW in cell: vg.rect(x1, y1, w, w)
        if olNE in cell: vg.rect(x2-w, y1, w, w)

      if olE in cell:    vg.rect(x2-w, y1, w, gs)
      elif olSE in cell: vg.rect(x2-w, y2-w, w, w)

      if olS in cell:    vg.rect(x1, y2-w, gs, w)
      elif olSW in cell: vg.rect(x1, y2-w, w, w)

      if olW in cell:    vg.rect(x1, y1, w, gs)


    proc drawFilled() =
      vg.rect(x1, y1, gs, gs)

    if ls.outlineStyle == osRoundedEdges:
        drawRoundedEdges()

    elif ls.outlineStyle == osRoundedEdgesFilled:
      if cell == {olNW, olNE, olSW, olSE} or
         cell == {olNW, olNE, olS} or
         cell == {olSW, olSE, olN} or
         cell == {olNE, olSE, olw} or
         cell == {olNW, olSW, olE} or
         cell == {olS, olW, olNE} or
         cell == {olN, olW, olSE} or
         cell == {olS, olE, olNW} or
         cell == {olN, olE, olSW}:
        drawFilled()
      else:
        drawRoundedEdges()

    elif ls.outlineStyle == osSquareEdges:
      drawSquareEdges()


  vg.beginPath()

  var
    startBufRow = ViewBufBorder
    startBufCol = ViewBufBorder
    endBufRow   = ob.rows - ViewBufBorder-1
    endBufCol   = ob.cols - ViewBufBorder-1

  if ls.outlineOverscan:
    if dp.viewstartrow == 0: dec(startBufRow)
    if dp.viewStartCol == 0: dec(startBufCol)

    let viewEndRow = dp.viewStartRow + dp.viewRows-1
    if viewEndRow == l.rows-1: inc(endBufRow)

    let viewEndCol = dp.viewStartCol + dp.viewCols-1
    if viewEndCol == l.cols-1: inc(endBufCol)

  for bufRow in startBufRow..endBufRow:
    for bufCol in startBufCol..endBufCol:
      let cell = ob[bufRow, bufCol]
      if not (cell == {}):
        let viewRow = bufRow - ViewBufBorder
        let viewCol = bufCol - ViewBufBorder
        draw(viewRow, viewCol, cell)

  vg.fill()

# }}}
# {{{ drawFloorBg()
proc drawFloorBg(x, y: float; color: Color; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)
  alias(ls, ctx.ls)

  vg.beginPath()
  vg.rect(x, y, dp.gridSize, dp.gridSize)

  vg.fillColor(ls.backgroundColor)
  vg.fill()
  vg.fillColor(color)
  vg.fill()

# }}}
# {{{ drawTrail()
proc drawTrail(x, y: float; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.38).int
    sw = dp.thinStrokeWidth

  var x1, y1: float
  if dp.lineWidth == lwThin:
    x1 = x + offs
    y1 = y + offs
  else:
    let sw2 = sw*0.5
    x1 = snap(x + offs - sw2, sw)
    y1 = snap(y + offs - sw2, sw)

  let a = dp.gridSize - 2*offs + sw

  vg.fillColor(ls.trailColor)
  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()

# }}}
# {{{ drawGrid()
proc drawGrid(x, y: float; color: Color; gridStyle: GridStyle; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = UltrathinStrokeWidth
  vg.strokeColor(color)
  vg.strokeWidth(sw)

  case gridStyle
  of gsNone: discard

  of gsSolid:
    let
      x1 = x
      y1 = y
      x2 = x + dp.gridSize
      y2 = y + dp.gridSize

    vg.beginPath()
    vg.moveTo(snap(x1, sw), snap(y, sw))
    vg.lineTo(snap(x2, sw), snap(y, sw))
    vg.moveTo(snap(x, sw), snap(y1, sw))
    vg.lineTo(snap(x, sw), snap(y2, sw))
    vg.stroke()

  of gsLoose:
    let
      offs = dp.gridSize * 0.2
      x1 = x + offs
      y1 = y + offs
      x2 = x + dp.gridSize - offs
      y2 = y + dp.gridSize - offs

    vg.beginPath()
    vg.moveTo(snap(x1, sw), snap(y, sw))
    vg.lineTo(snap(x2, sw), snap(y, sw))
    vg.moveTo(snap(x, sw), snap(y1, sw))
    vg.lineTo(snap(x, sw), snap(y2, sw))
    vg.stroke()

  of gsCross:
    let
      offs = dp.gridSize * 0.2
      x1 = x + offs
      x2 = x + dp.gridSize - offs
      xe = x + dp.gridSize

      y1 = y + offs
      y2 = y + dp.gridSize - offs
      ye = y + dp.gridSize

    vg.beginPath()
    vg.moveTo(snap(x, sw), snap(y, sw))
    vg.lineTo(snap(x1, sw), snap(y, sw))
    vg.moveTo(snap(x2, sw), snap(y, sw))
    vg.lineTo(snap(xe, sw), snap(y, sw))

    vg.moveTo(snap(x, sw), snap(y, sw))
    vg.lineTo(snap(x, sw), snap(y1, sw))
    vg.moveTo(snap(x, sw), snap(y2, sw))
    vg.lineTo(snap(x, sw), snap(ye, sw))
    vg.stroke()

# }}}
# {{{ drawIcon()
proc drawIcon(x, y, ox, oy: float; icon: string, gridSize: float;
              color: Color; fontSizeFactor: float; vg: NVGContext) =

  vg.setFont(gridSize * fontSizeFactor)
  vg.fillColor(color)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + gridSize*ox + gridSize*0.51,
                  y + gridSize*oy + gridSize*0.58, icon)

template drawIcon(x, y, ox, oy: float; icon: string; color: Color; ctx) =
  drawIcon(x, y, ox, oy, icon, ctx.dp.gridSize, color,
          DefaultIconFontSizeFactor, ctx.vg)

# }}}
# {{{ drawIndexedNote()
proc drawIndexedNote(x, y: float; index, colorIdx: Natural;
                     isCursorActive: bool; ctx) =
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  let size = ctx.dp.gridSize

  let shape = ls.noteBackgroundShape
  let bgColor = if isCursorActive and shape == nbsRectangle:
                  ls.cursorColor
                else: ls.noteIndexBackgroundColor[colorIdx]

  vg.fillColor(bgColor)
  vg.beginPath()

  case shape:
  of nbsCircle:
    vg.circle(x + size*0.5, y + size*0.5, size*0.35)
  of nbsRectangle:
    vg.rect(x, y, size, size)

  vg.fill()

  # TODO debug
  let index = if index < 5: index
              elif index < 10: index * 5
              else: index * 10
  # TODO debug

  var fontSizeFactor = if   index <  10: 0.43
                       elif index < 100: 0.4
                       else:             0.35

  if shape == nbsRectangle: fontSizeFactor *= 1.1

  vg.setFont((size*fontSizeFactor).float)
  vg.fillColor(ls.noteIndexColor)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + size*0.51, y + size*0.54, $index)

# }}}
# {{{ drawCustomIdNote()
proc drawCustomIdNote(x, y: float; s: string; color: Color; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.setFont((dp.gridSize * 0.48).float)
  vg.fillColor(color)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + dp.gridSize*0.52,
                  y + dp.gridSize * TextVertAlignFactor, s)

# }}}
# {{{ drawNote()
proc drawNote(x, y: float; note: Annotation; isCursorActive: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  template getNoteMarkerColor(): Color =
    if isCursorActive: ls.noteMarkerCursorColor else: ls.noteMarkerColor

  case note.kind
  of akComment:  discard
  of akIndexed:  drawIndexedNote(x, y, note.index, note.indexColor,
                                 isCursorActive, ctx)
  of akCustomId: drawCustomIdNote(x, y, note.customId, getNoteMarkerColor(),
                                  ctx)

  of akIcon:     drawIcon(x, y, 0, 0, NoteIcons[note.icon],
                          dp.gridSize, getNoteMarkerColor(),
                          DefaultIconFontSizeFactor, vg)

  of akLabel:    discard

  if note.kind != akIndexed:
    let w = dp.gridSize*0.3

    vg.fillColor(ls.noteCommentColor)
    vg.beginPath()
    vg.moveTo(x + dp.gridSize - w, y)
    vg.lineTo(x + dp.gridSize + 1, y + w+1)
    vg.lineTo(x + dp.gridSize + 1, y)
    vg.closePath()
    vg.fill()

  # }}}
# {{{ drawLabel()
proc drawLabel(x, y: float; label: Annotation; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.save()

  let w = dp.gridSize * dp.viewCols
  let h = dp.gridSize * dp.viewRows
  vg.intersectScissor(dp.startX, dp.startY, w, h)

  vg.beginPath()

  vg.setFont((dp.gridSize * 0.48).float)
  vg.fillColor(ls.labelTextColor[label.labelColor])
  vg.textAlign(haLeft, vaMiddle)
  vg.textLineHeight(1.2)

  vg.textBox(
    x + dp.gridSize * 0.22,
    y + dp.gridSize * TextVertAlignFactor,
    MaxLabelWidthInCells * dp.gridSize,
    label.text
  )

  vg.restore()

# }}}
# {{{ drawLinkMarker()
proc drawLinkMarker(x, y: float; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)
  alias(ls, ctx.ls)

  let w = dp.gridSize*0.3

  vg.fillColor(ls.linkMarkerColor)
  vg.beginPath()
  vg.moveTo(x,   y + dp.gridSize - w)
  vg.lineTo(x,   y + dp.gridSize)
  vg.lineTo(x+w, y + dp.gridSize)
  vg.closePath()
  vg.fill()

# }}}

# {{{ drawShadows_IterateViewBuf()
template drawShadows_IterateViewBuf(body: untyped) =
  for bufRow {.inject.} in ViewBufBorder..<viewBuf.rows - ViewBufBorder:
    for bufCol {.inject.} in ViewBufBorder..<viewBuf.cols - ViewBufBorder:
      let viewRow = bufRow - ViewBufBorder
      let viewCol = bufCol - ViewBufBorder

      if not isCursorActive(viewRow, viewCol, dp):
        let x {.inject.} = cellX(viewCol, dp)
        let y {.inject.} = cellY(viewRow, dp)
        body

# }}}
# {{{ drawInnerShadows()
proc drawInnerShadows(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  vg.fillColor(ls.shadowInnerColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ls.shadowInnerWidthFactor

  drawShadows_IterateViewBuf:
    if not viewBuf.isEmpty(bufRow, bufCol):
      let emptyN  = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, North)
      let emptyW  = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, West)
      let emptyNW = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, NorthWest)

      if emptyN:
        let offs = if not emptyW and not emptyNW: shadowWidth else: 0
        vg.rect(x+offs, y, dp.gridSize-offs, shadowWidth)

      if emptyW:
        let offs = if not emptyN and not emptyNW: shadowWidth else: 0
        vg.rect(x, y+offs, shadowWidth, dp.gridSize-offs)

      if not emptyN and not emptyW and emptyNW:
        vg.rect(x, y, shadowWidth, shadowWidth)

  vg.fill()

# }}}
# {{{ drawOuterShadows()
proc drawOuterShadows(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  vg.fillColor(ls.shadowOuterColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ls.shadowOuterWidthFactor

  drawShadows_IterateViewBuf:
    if viewBuf.isEmpty(bufRow, bufCol):
      let emptyN  = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, North)
      let emptyW  = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, West)
      let emptyNW = viewBuf.isNeighbourCellEmpty(bufRow, bufCol, NorthWest)

      if not emptyN:
        let offs = if emptyW and emptyNW: shadowWidth else: 0
        vg.rect(x+offs, y, dp.gridSize-offs, shadowWidth)

      if not emptyW:
        let offs = if emptyN and emptyNW: shadowWidth else: 0
        vg.rect(x, y+offs, shadowWidth, dp.gridSize-offs)

      if emptyN and emptyW and not emptyNW:
        vg.rect(x, y, shadowWidth, shadowWidth)

  vg.fill()

# }}}

template getForegroundNormalColor(isCursorActive: bool; ctx): Color =
  if isCursorActive: ctx.ls.foregroundNormalCursorColor
  else: ctx.ls.foregroundNormalColor

template getForegroundLightColor(isCursorActive: bool; ctx): Color =
  if isCursorActive: ctx.ls.foregroundLightCursorColor
  else: ctx.ls.foregroundLightColor

# {{{ Draw wall types
# {{{ setWallStyle()
proc setWallStyle(isCursorActive, regionBorder: bool; ctx): (float, float,
                                                             float, float) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let (sw, color, lineCap, xoffs) = if regionBorder:
    (dp.normalStrokeWidth + 1, ls.regionBorderNormalColor, lcjSquare, 1.0)
  else:
    let color = getForegroundNormalColor(isCursorActive, ctx)
    (dp.normalStrokeWidth, color, lcjRound, 0.0)

  vg.strokeWidth(sw)
  vg.strokeColor(color)
  vg.lineCap(linecap)

  let xsOffs = if regionBorder:
                 case ls.lineWidth:
                 of lwThin: 1.0
                 of lwNormal: 0.0
               else: 0.0

  let xeOffs = if regionBorder:
                 case ls.lineWidth:
                 of lwThin: 0.0
                 of lwNormal: -1.0
               else: 0.0

  (sw, xoffs, xsOffs, xeOffs)

# }}}

# {{{ regionBorderYAdjustment()
func regionBorderYAdjustment(orientation: Orientation,
                             regionBorder: bool; ctx): float =

  if orientation == Vert and regionBorder: ctx.dp.vertRegionBorderYOffs
  else: 0

# }}}

# {{{ drawSolidWallHoriz*()
proc drawSolidWallHoriz*(x, y: float; orientation: Orientation,
                         isCursorActive, regionBorder: bool = false; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let (sw, _, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder, ctx)

  let
    xs = snap(x + xsOffs, sw)
    xe = snap(x + dp.gridSize + xeOffs, sw)
    y = snap(y + regionBorderYAdjustment(orientation, regionBorder, ctx), sw)

  vg.beginPath()
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawIllusoryWallHoriz*()
proc drawIllusoryWallHoriz*(x, y: float; orientation: Orientation;
                            isCursorActive, regionBorder: bool = false; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let (sw, _, _, _) = setWallStyle(isCursorActive, regionBorder, ctx)

  let
    xs = x
    xe = x + dp.gridSize
    y = snap(y + regionBorderYAdjustment(orientation, regionBorder, ctx), sw)
    # TODO make zoom dependent
    len = 2.0
    pad = 7.0

  vg.lineCap(lcjSquare)

  var x = xs
  vg.beginPath()
  while x <= xe:
    vg.moveTo(snap(x, sw), y)
    vg.lineTo(snap(min(x+len, xe), sw), y)
    x += pad
  vg.stroke()

# }}}
# {{{ drawInvisibleWallHoriz*()
proc drawInvisibleWallHoriz*(x, y: float; orientation: Orientation;
                             isCursorActive, regionBorder: bool = false; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let color = getForegroundLightColor(isCursorActive, ctx)

  var sw = dp.normalStrokeWidth * 2
  if dp.lineWidth == lwThin: sw *= 2
  let
    xs = x+sw
    xe = x + dp.gridSize
    y = snap(y, sw)
    len = 1.0
    pad = sw*2

  vg.lineCap(lcjSquare)
  vg.strokeColor(color)
  vg.strokeWidth(sw)

  var x = xs
  vg.beginPath()
  while x <= xe:
    vg.moveTo(snap(x, sw), y)
    vg.lineTo(snap(min(x+len, xe), sw), y)
    x += pad
  vg.stroke()

# }}}
# {{{ drawDoorHoriz*()
proc drawDoorHoriz*(x, y: float; orientation: Orientation;
                    isCursorActive, regionBorder, fill: bool = false; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, xoffs, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder,
                                                 ctx)

  let
    wallLen = (dp.gridSize * 0.25).int
    doorWidth = round(dp.gridSize * 0.1) - 1
    xs = x + xsOffs
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize + xeOffs - xsOffs
    x2 = xe - wallLen - 1
    y1 = y - doorWidth
    y2 = y + doorWidth

  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  # Wall start
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1+1-xoffs, sw), snap(wy, sw))

  # Wall end
  vg.moveTo(snap(x2+xoffs, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  # Door
  sw = dp.thinStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(color)
  vg.fillColor(color)
  vg.lineCap(lcjSquare)

  vg.beginPath()

  if fill:
    if dp.lineWidth == lwThin:
      vg.rect(x1+1, y1-1, x2-x1, y2-y1+2+1)
    else:
      vg.rect(snap(x1, sw), snap(y1-2, sw), x2-x1+1, y2-y1+4)
    vg.fill()
  else:
    vg.rect(snap(x1+1, sw), snap(y1-1, sw), x2-x1-1, y2-y1+2)
    vg.stroke()

# }}}
# {{{ drawLockedDoorHoriz*()
proc drawLockedDoorHoriz*(x, y: float; orientation: Orientation;
                          isCursorActive, regionBorder: bool = false; ctx) =
  drawDoorHoriz(x, y, orientation, isCursorActive, regionBorder, fill=true, ctx)

# }}}
# {{{ drawSecretDoorHoriz*()
proc drawSecretDoorHoriz*(x, y: float; orientation: Orientation;
                          isCursorActive, regionBorder: bool = false; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, xoffs, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder,
                                                 ctx)

  let
    wallLen = (dp.gridSize * 0.25).int
    xs = x + xsOffs
    y  = y
    x1 = xs + wallLen + 1 - xsOffs
    xe = xs + dp.gridSize + xeOffs - xsOffs
    x2 = xe - wallLen - 1

  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  # Wall start
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1, sw), snap(wy, sw))

  # Wall end
  vg.moveTo(snap(x2+xoffs, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  drawIcon(x, y-dp.gridSize*0.5, 0.01, -0.04, "S", dp.gridSize,
           color, fontSizeFactor=0.43, ctx.vg)

# }}}
# {{{ drawArchwayHoriz*()
proc drawArchwayHoriz*(x, y: float; orientation: Orientation;
                       isCursorActive, regionBorder: bool = false; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, xoffs, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder,
                                                 ctx)

  let
    wallLenOffs = (if dp.zoomLevel < 2: -1.0 else: 0)
    wallLen = (dp.gridSize * 0.3).int + wallLenOffs
    doorWidth = round(dp.gridSize * 0.075)
    xs = x + xsOffs
    y  = y
    x1 = xs + wallLen + 1
    xe = xs + dp.gridSize + xeOffs - xsOffs
    x2 = xe - wallLen - 1
    y1 = y - doorWidth
    y2 = y + doorWidth

  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  # Wall start
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1-xoffs, sw), snap(wy, sw))

  # Wall end
  vg.moveTo(snap(x2+xoffs, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  # Door opening
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(color)
  vg.lineCap(lcjSquare)

  vg.beginPath()
  vg.moveTo(snap(x1, sw), snap(y1, sw))
  vg.lineTo(snap(x1, sw), snap(y2, sw))
  vg.moveTo(snap(x2, sw), snap(y1, sw))
  vg.lineTo(snap(x2, sw), snap(y2, sw))
  vg.stroke()

# }}}
# {{{ drawOneWayDoorHoriz*()
proc drawOneWayDoorHoriz*(x, y: float; orientation: Orientation;
                          isCursorActive, regionBorder, northEast: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, xoffs, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder,
                                                 ctx)

  let
    wallLen = (dp.gridSize * 0.28).int
    xs = x + xsOffs
    y  = y
    x1 = xs + wallLen + 1 - xsOffs
    xe = xs + dp.gridSize + xeOffs - xsOffs
    x2 = xe - wallLen - 1

  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  # Wall start
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1+xoffs + xeOffs, sw), snap(wy, sw))

  # Wall end
  vg.moveTo(snap(x2+xoffs, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  var ox, oy: float
  var icon: string

  # Arrow
  ox = 0.011
  if northEast:
    icon = IconThinArrowUp
    oy = -0.06
  else:
    icon = IconThinArrowDown
    oy = 0.02

  drawIcon(x, y-dp.gridSize*0.5, ox, oy, icon,
           dp.gridSize, color, fontSizeFactor=0.46, ctx.vg)


proc drawOneWayDoorHorizNE*(x, y: float; orientation: Orientation;
                            isCursorActive, regionBorder: bool = false; ctx) =
  drawOneWayDoorHoriz(x, y, orientation, isCursorActive, regionBorder,
                      northEast=true, ctx)

proc drawOneWayDoorHorizSW*(x, y: float; orientation: Orientation;
                            isCursorActive, regionBorder: bool = false; ctx) =
  drawOneWayDoorHoriz(x, y, orientation, isCursorActive, regionBorder,
                      northEast=false, ctx)

# }}}
# {{{ drawLeverHoriz*()
proc drawLeverHoriz*(x, y: float; orientation: Orientation;
                     isCursorActive, regionBorder, northEast: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  # Draw lever
  let
    lw = floor(dp.gridSize*0.2)
    sw = dp.normalStrokeWidth
    y = snap(y, sw)
    color = getForegroundNormalColor(isCursorActive, ctx)

  var lx, ly: float

  if dp.lineWidth == lwThin:
    lx = floor(x + (dp.gridSize-lw)*0.5 + 0.5)
    ly = if northEast: y-0.5 else: y-lw+0.5
  else:
    lx = snap(x + (dp.gridSize-lw)*0.5 + 0.5, sw)
    ly = if northEast: y else: y-lw

  vg.fillColor(color)
  vg.beginPath()
  vg.rect(lx, ly, lw, lw)
  vg.fill()

  drawSolidWallHoriz(x, y, orientation, isCursorActive, regionBorder, ctx)


proc drawLeverHorizNE*(x, y: float; orientation: Orientation;
                       isCursorActive, regionBorder: bool = false; ctx) =
  drawLeverHoriz(x, y, orientation, isCursorActive, regionBorder,
                 northEast=true, ctx)

proc drawLeverHorizSW*(x, y: float; orientation: Orientation;
                       isCursorActive, regionBorder: bool = false; ctx) =
  drawLeverHoriz(x, y, orientation, isCursorActive, regionBorder,
                 northEast=false, ctx)

# }}}
# {{{ drawNicheHoriz*()
proc drawNicheHoriz*(x, y: float; orientation: Orientation;
                     isCursorActive, regionBorder, northEast: bool;
                     floorColor: Natural; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, xoffs, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder,
                                                 ctx)

  let
    wallLenOffs = (if dp.zoomLevel < 2: -1.0 else: 0)
    wallLen = (dp.gridSize * 0.25).int + wallLenOffs
    nicheDepth = round(dp.gridSize * 0.15)
    xs = x + xsOffs
    y  = y
    x1 = xs + wallLen + 1
    xe = xs + dp.gridSize + xeOffs - xsOffs
    x2 = xe - wallLen - 1
    yn = if northEast: y-nicheDepth else: y+nicheDepth

  # Background
  vg.beginPath()
  vg.rect(x1, y, x2-x1, yn-y)

  if dp.backgroundImage.isSome:
    vg.fillPaint(dp.backgroundImage.get)
  else:
    vg.fillColor(ls.backgroundColor)

  vg.fill()
  vg.fillColor(ls.floorBackgroundColor[floorColor])
  vg.fill()

  # Wall
  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  let o = if dp.lineWidth == lwThin: 1 else: 0

  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1-xoffs+o, sw), snap(wy, sw))

  vg.moveTo(snap(x2+xoffs + xeOffs, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  # Niche
  sw = dp.normalStrokeWidth

  vg.strokeWidth(sw)
  vg.strokeColor(ls.foregroundNormalColor)
  vg.lineCap(lcjRound)

  vg.beginPath()
  vg.moveTo(snap(x1, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(yn, sw))
  vg.lineTo(snap(x2, sw), snap(yn, sw))
  vg.lineTo(snap(x2, sw), snap(y, sw))
  vg.stroke()


proc drawNicheHorizNE*(x, y: float; orientation: Orientation;
                       floorColor: Natural;
                       isCursorActive, regionBorder: bool = false; ctx) =
  drawNicheHoriz(x, y, orientation, isCursorActive, regionBorder,
                 northEast=true, floorColor, ctx)

proc drawNicheHorizSW*(x, y: float; orientation: Orientation;
                       floorColor: Natural;
                       isCursorActive, regionBorder: bool = false; ctx) =
  drawNicheHoriz(x, y, orientation, isCursorActive, regionBorder,
                 northEast=false, floorColor, ctx)

# }}}
# {{{ drawStatueHoriz*()
proc drawStatueHoriz*(x, y: float; orientation: Orientation;
                      isCursorActive, regionBorder, northEast: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  # Statue
  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(color)

  const da = 1.3
  let
    cx = x + dp.gridSize*0.5
    dy = dp.gridSize*0.07
    cy = if northEast: y-dy else: y+dy
    ca = if northEast: PI*0.5 else: 3*PI*0.5
    a1 = ca-da
    a2 = ca+da

  vg.fillColor(color)
  vg.beginPath()
  vg.arc(cx, cy, dp.gridSize*0.27, a1, a2, pwCW)
  vg.fill()

  drawSolidWallHoriz(x, y, orientation, isCursorActive, regionBorder, ctx)


proc drawStatueHorizNE*(x, y: float; orientation: Orientation;
                        isCursorActive, regionBorder: bool = false; ctx) =
  drawStatueHoriz(x, y, orientation, isCursorActive, regionBorder,
                 northEast=true, ctx)

proc drawStatueHorizSW*(x, y: float; orientation: Orientation;
                        isCursorActive, regionBorder: bool = false; ctx) =
  drawStatueHoriz(x, y, orientation, isCursorActive, regionBorder,
                  northEast=false, ctx)

# }}}
# {{{ drawKeyholeHoriz*()
proc drawKeyholeHoriz*(x, y: float; orientation: Orientation;
                       isCursorActive, regionBorder: bool = false; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  var (sw, _, xsOffs, xeOffs) = setWallStyle(isCursorActive, regionBorder, ctx)

  let
    boxLen = (dp.gridSize * 0.25).int
    xs = x + xsOffs
    x1 = xs + (dp.gridSize - boxLen)*0.5
    x2 = x1 + boxLen
    xe = x + dp.gridSize + xeOffs

  let wy = y + regionBorderYAdjustment(orientation, regionBorder, ctx)

  # Wall start
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(wy, sw))
  vg.lineTo(snap(x1, sw), snap(wy, sw))

  # Wall end
  vg.moveTo(snap(x2, sw), snap(wy, sw))
  vg.lineTo(snap(xe, sw), snap(wy, sw))
  vg.stroke()

  # Keyhole border
  sw = dp.thinStrokeWidth
  let
    kx = snap(x1, sw)
    ky = snap(y-boxLen*0.5, sw)
    kl = boxLen.float

  vg.strokeWidth(sw)
  vg.strokeColor(ls.foregroundNormalColor)
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.rect(kx, ky, kl, kl)

  if dp.backgroundImage.isSome:
    vg.fillPaint(dp.backgroundImage.get)
  else:
    vg.fillColor(ls.floorBackgroundColor[0])

  vg.fill()
  vg.stroke()

  # Keyhole
  var i, h: float
  if dp.lineWidth == lwThin:
    i = 3.5
    h = kl-7
  else:
    i = 3
    h = kl-6

  if h >= 2:
    vg.fillColor(ls.foregroundNormalColor)
    vg.beginPath()
    vg.rect(kx+i, ky+i, h, h)
    vg.fill()

# }}}
# {{{ drawWritingHoriz*()
proc drawWritingHoriz*(x, y: float; orientation: Orientation;
                       isCursorActive, regionBorder, northEast: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  drawSolidWallHoriz(x, y, orientation, isCursorActive, regionBorder, ctx)

  let oy = if northEast: -0.33 else: -0.72

  let color = getForegroundNormalColor(isCursorActive, ctx)

  drawIcon(x, y, 0, oy, IconWriting, dp.gridSize, color,
           fontSizeFactor=0.7, vg)

proc drawWritingHorizNE*(x, y: float; orientation: Orientation;
                         isCursorActive, regionBorder: bool = false; ctx) =
  drawWritingHoriz(x, y, orientation, isCursorActive, regionBorder,
                   northEast=true, ctx)

proc drawWritingHorizSW*(x, y: float; orientation: Orientation;
                         isCursorActive, regionBorder: bool = false; ctx) =
  drawWritingHoriz(x, y, orientation, isCursorActive, regionBorder,
                   northEast=false, ctx)

# }}}

# {{{ drawEmptyRegionBorderWallHoriz*()
proc drawEmptyRegionBorderWallHoriz*(x, y: float; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let (xsOffs, xeOffs) = case dp.lineWidth
                         of lwThin:   (1, -1)
                         of lwNormal: (0, -3)

  let
    sw = dp.normalStrokeWidth + 1
    xs = snap(x + xsOffs, sw)
    xe = snap(x + dp.gridSize + xeOffs, sw)
    y = snap(y, sw)

  vg.lineCap(lcjSquare)
  vg.beginPath()

  vg.strokeColor(ls.regionBorderEmptyColor)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawEmptyRegionBorderWallVert*()
proc drawEmptyRegionBorderWallVert*(x, y: float; ctx) =
  alias(vg, ctx.vg)

  setVertTransform(x, y, ctx)
  drawEmptyRegionBorderWallHoriz(x=0, y=ctx.dp.vertRegionBorderYOffs, ctx)
  vg.resetTransform()

# }}}
# {{{ drawRegionBorderEdgeHoriz*()
proc drawRegionBorderEdgeHoriz*(x, y: float; color: Color; west: bool; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  const EdgeLen = 10

  let sw = dp.normalStrokeWidth + 1
  let y = snap(y, sw)

  var xs, xe: float
  if west:
    xs = snap(x + (if dp.lineWidth == lwNormal: 0 else: 1), sw)
    xe = xs + EdgeLen
  else:
    xs = snap(x + dp.gridSize-(if dp.lineWidth == lwNormal: 3 else: 1), sw)
    xe = xs - EdgeLen

  vg.lineCap(lcjSquare)
  vg.beginPath()

  vg.strokeColor(color)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawRegionBorderEdgeVert*()
proc drawRegionBorderEdgeVert*(x, y: float; color: Color; north: bool; ctx) =
  alias(vg, ctx.vg)

  setVertTransform(x, y, ctx)
  drawRegionBorderEdgeHoriz(0, (if ctx.dp.lineWidth == lwThin: 0 else: -1),
                            color, north, ctx)
  vg.resetTransform()

# }}}
# }}}
# {{{ Draw floor types

# {{{ drawSecretDoorBlock()
proc drawSecretDoorBlock(x, y: float; floorColor: Natural;
                         isCursorActive: bool; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)

  alias(vg, ctx.vg)

  vg.beginPath()
  vg.fillPaint(dp.lineHatchPatterns[dp.lineHatchSize])
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

  let
    icon = "S"
    fontSizeFactor = DefaultIconFontSizeFactor
    gs = dp.gridSize

  var bgCol = calcBlendedFloorColor(floorColor, ls=ctx.ls)
  # TODO extract
  if isCursorActive:
    bgCol = lerp(bgCol, ls.cursorColor, ls.cursorColor.a)
              .withAlpha(1.0)

  let o = if dp.zoomLevel > 11: 3 else: 2

  drawIcon(x-o, y, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x+o, y, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x, y-o, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x, y+o, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)

  drawIcon(x, y, 0, 0, icon, gs, getForegroundNormalColor(isCursorActive, ctx),
           fontSizeFactor, vg)

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float; isCursorActive: bool; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs
    sw = dp.thinStrokeWidth
    color = getForegroundNormalColor(isCursorActive, ctx)

  vg.lineCap(lcjRound)
  vg.strokeColor(color)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float; isCursorActive: bool; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs
    sw = dp.thinStrokeWidth
    color = getForegroundLightColor(isCursorActive, ctx)

  vg.lineCap(lcjRound)
  vg.strokeColor(color)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawOpenPitWithColor()
proc drawOpenPitWithColor(x, y: float; color: Color; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    sw = dp.thinStrokeWidth

  var x1, y1: float
  if dp.lineWidth == lwThin:
    x1 = x + offs
    y1 = y + offs
  else:
    let sw2 = sw*0.5
    x1 = snap(x + offs - sw2, sw)
    y1 = snap(y + offs - sw2, sw)

  let a = dp.gridSize - 2*offs + sw

  vg.fillColor(color)
  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()

# }}}
# {{{ drawOpenPit()
proc drawOpenPit(x, y: float; isCursorActive: bool; ctx) =
  drawOpenPitWithColor(x, y, getForegroundNormalColor(isCursorActive, ctx), ctx)

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float; isCursorActive: bool; ctx) =
  drawOpenPitWithColor(x, y, getForegroundLightColor(isCursorActive, ctx), ctx)

# }}}
# {{{ drawClosedPitWithColor()
proc drawClosedPitWithColor(x, y: float; color: Color; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs
    sw = dp.thinStrokeWidth
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)
    x2 = snap(x + offs + a, sw)
    y2 = snap(y + offs + a, sw)

  vg.lineCap(lcjSquare)
  vg.strokeColor(color)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.moveTo(x1+1, y1+1)
  vg.lineTo(x2-1, y2-1)
  vg.moveTo(x2-1, y1+1)
  vg.lineTo(x1+1, y2-1)
  vg.stroke()

# }}}
# {{{ drawClosedPit()
proc drawClosedPit(x, y: float; isCursorActive: bool; ctx) =
  drawClosedPitWithColor(x, y, getForegroundNormalColor(isCursorActive, ctx),
                         ctx)

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float; isCursorActive: bool; ctx) =
  drawClosedPitWithColor(x, y, getForegroundLightColor(isCursorActive, ctx),
                         ctx)

# }}}
# {{{ drawStairsDown()
proc drawStairsDown(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0, 0, IconStairsDown,
           getForegroundNormalColor(isCursorActive, ctx), ctx)

# }}}
# {{{ drawStairsUp()
proc drawStairsUp(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0, 0, IconStairsUp,
           getForegroundNormalColor(isCursorActive, ctx), ctx)

# }}}
# {{{ drawDoorEnter()
proc drawDoorEnter(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0.05, 0, IconDoorEnter, ctx.dp.gridSize,
           getForegroundNormalColor(isCursorActive, ctx),
           fontSizeFactor=0.6, ctx.vg)

# }}}
# {{{ drawDoorExit()
proc drawDoorExit(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0.05, 0, IconDoorExit, ctx.dp.gridSize,
           getForegroundNormalColor(isCursorActive, ctx),
           fontSizeFactor=0.6, ctx.vg)

# }}}
# {{{ drawSpinner()
proc drawSpinner(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0.06, 0, IconSpinner,
           getForegroundNormalColor(isCursorActive, ctx), ctx)

# }}}
# {{{ drawTeleportSource()
proc drawTeleportSource(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0, 0, IconTeleport, ctx.dp.gridSize,
           getForegroundNormalColor(isCursorActive, ctx),
           fontSizeFactor=0.7, ctx.vg)

# }}}
# {{{ drawTeleportDestination()
proc drawTeleportDestination(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0, 0, IconTeleport, ctx.dp.gridSize,
           getForegroundLightColor(isCursorActive, ctx),
           fontSizeFactor=0.7, ctx.vg)

# }}}
# {{{ drawInvisibleBarrier()
proc drawInvisibleBarrier(x, y: float; isCursorActive: bool; ctx) =
  drawIcon(x, y, 0, 0.015, IconBarrier, ctx.dp.gridSize,
           getForegroundLightColor(isCursorActive, ctx),
           fontSizeFactor=1.0, ctx.vg)

# }}}
# {{{ drawBridge()
proc drawBridge(x, y: float; orientation: Orientation; isCursorActive: bool;
                ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    wallLenOffs = (if dp.zoomLevel < 2: -1.0 else: 0)
    wallLen = (dp.gridSize * 0.25).int + wallLenOffs
    xs = x
    x1 = xs + wallLen + 1
    xe = xs + dp.gridSize
    x2 = xe - wallLen - 1
    yo = round(dp.gridSize * 0.1)
    y1 = y - yo
    y2 = y + dp.gridSize + yo

  let w = x2 - x1
  let h = dp.gridSize + 2*yo

  let fc0 = ls.floorBackgroundColor[0]
  var bgCol = lerp(ls.backgroundColor.withAlpha(1.0),
                    fc0.withAlpha(1.0),
                    fc0.a)

  let color = getForegroundNormalColor(isCursorActive, ctx)

  vg.beginPath()
  vg.fillColor(bgCol)
  vg.rect(x1, y1, w, h)
  vg.fill()

  var sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(color)
  vg.lineCap(lcjSquare)

  vg.beginPath()
  vg.moveTo(snap(x1, sw), snap(y1, sw))
  vg.lineTo(snap(x1, sw), snap(y2, sw))
  vg.moveTo(snap(x2, sw), snap(y1, sw))
  vg.lineTo(snap(x2, sw), snap(y2, sw))
  vg.stroke()

  # Shading
  sw = 1.0
  let numLines = 6
  let step = h / numLines
  var yy = y1 + step/2

  vg.strokeWidth(sw)
  vg.beginPath()

  for i in 1..numLines:
    vg.moveTo(snap(x1, sw), snap(yy, sw))
    vg.lineTo(snap(x2, sw), snap(yy, sw))
    yy += step

  vg.stroke()

# }}}
# }}}

# {{{ drawBackgroundGrid()
proc drawBackgroundGrid(viewBuf: Level; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    w = dp.gridSize * dp.viewCols + 1
    h = dp.gridSize * dp.viewRows + 1

  vg.save()
  vg.intersectScissor(dp.startX, dp.startY, w, h)

  for viewRow in 0..dp.viewRows:
    for viewCol in 0..dp.viewCols:
      if viewBuf.isEmpty(toBufRow(viewRow), toBufCol(viewCol)):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)
        drawGrid(x, y, ls.gridBackgroundGridColor, ls.gridBackgroundStyle,
                 ctx)

  vg.restore()

# }}}
# {{{ drawCellBackgroundsAndGrid()
proc drawCellBackgroundsAndGrid(viewBuf: Level; ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let bufRow = toBufRow(viewRow)
      let bufCol = toBufCol(viewCol)

      if not viewBuf.isEmpty(bufRow, bufCol):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)
        let floorColor = calcBlendedFloorColor(
          viewBuf.getFloorColor(bufRow, bufCol),
          ls.floorTransparent,
          ctx.ls
        )
        drawFloorBg(x, y, floorColor, ctx)
        drawGrid(x, y, ls.gridFloorGridColor, ls.gridFloorStyle, ctx)

# }}}
# {{{ drawCellFloor()
proc drawCellFloor(viewBuf: Level, viewRow, viewCol: int; ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    bufRow = toBufRow(viewRow)
    bufCol = toBufCol(viewCol)
    f = viewBuf.getFloor(bufRow, bufCol)
    x = cellX(viewCol, dp)
    y = cellY(viewRow, dp)
    isCursorActive = isCursorActive(viewRow, viewCol, dp)

  template drawOriented(drawProc: untyped, offsetFactor = 0.5) =
    let orientation = viewBuf.getFloorOrientation(bufRow, bufCol)

    case orientation
    of Horiz:
      drawProc(x, y + floor(dp.gridSize * offsetFactor), orientation,
               isCursorActive=isCursorActive, ctx=ctx)
    of Vert:
      setVertTransform(x + floor(dp.gridSize*(1 - offsetFactor)), y, ctx)
      drawProc(0, 0, orientation, isCursorActive=isCursorActive, ctx=ctx)
      vg.resetTransform()

  template draw(drawProc: untyped) =
    drawProc(x, y, isCursorActive=isCursorActive, ctx)


  vg.save()

  if f != fBridge:
    vg.intersectScissor(x, y, dp.gridSize+1, dp.gridSize+1)

  case f
  of fEmpty:               discard
  of fBlank:               discard
  of fDoor:                drawOriented(drawDoorHoriz)
  of fLockedDoor:          drawOriented(drawLockedDoorHoriz)
  of fArchway:             drawOriented(drawArchwayHoriz)
  of fSecretDoorBlock:     drawSecretDoorBlock(
                             x, y,
                             viewBuf.getFloorColor(bufRow, bufCol),
                             isCursorActive(viewRow, viewCol, dp),
                             ctx
                           )
  of fSecretDoor:          drawOriented(drawSecretDoorHoriz)
  of fOneWayDoor1:         drawOriented(drawOneWayDoorHorizNE)
  of fOneWayDoor2:         drawOriented(drawOneWayDoorHorizSW)
  of fPressurePlate:       draw(drawPressurePlate)
  of fHiddenPressurePlate: draw(drawHiddenPressurePlate)
  of fClosedPit:           draw(drawClosedPit)
  of fOpenPit:             draw(drawOpenPit)
  of fHiddenPit:           draw(drawHiddenPit)
  of fCeilingPit:          draw(drawCeilingPit)
  of fStairsDown:          draw(drawStairsDown)
  of fStairsUp:            draw(drawStairsUp)
  of fEntranceDoor:        draw(drawDoorEnter)
  of fExitDoor:            draw(drawDoorExit)
  of fSpinner:             draw(drawSpinner)
  of fTeleportSource:      draw(drawTeleportSource)
  of fTeleportDestination: draw(drawTeleportDestination)
  of fInvisibleBarrier:    draw(drawInvisibleBarrier)
  of fBridge:              drawOriented(drawBridge, offsetFactor=0)

  vg.restore()

# }}}
# {{{ drawFloors()
proc drawFloors(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let 
        bufRow = toBufRow(viewRow)
        bufCol = toBufCol(viewCol)
        f = viewBuf.getFloor(bufRow, bufCol)

      if f != fBridge:
        drawCellFloor(viewBuf, viewRow, viewCol, ctx)

# }}}
# {{{ drawBridges()
proc drawBridges(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let 
        bufRow = toBufRow(viewRow)
        bufCol = toBufCol(viewCol)
        f = viewBuf.getFloor(bufRow, bufCol)

      if f == fBridge:
        drawCellFloor(viewBuf, viewRow, viewCol, ctx)

# }}}
# {{{ drawTrail()
proc drawTrail(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let bufRow = toBufRow(viewRow)
      let bufCol = toBufCol(viewCol)

      if viewBuf.hasTrail(bufRow, bufCol):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)
        drawTrail(x, y, ctx)

# }}}

# {{{ drawLabels()
proc drawLabels(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  let rect = rectN(
    ViewBufBorder,
    0,
    viewBuf.rows - ViewBufBorder,
    viewBuf.cols - ViewBufBorder
  )

  for bufRow, bufCol, label in viewBuf.allLabels:
    if rect.contains(bufRow, bufCol):
      let
        viewRow = bufRow - ViewBufBorder
        viewCol = bufCol - ViewBufBorder
        x = cellX(viewCol, dp)
        y = cellY(viewRow, dp)

      drawLabel(x, y, label, ctx)

# }}}
# {{{ drawLinkMarkers()
proc drawLinkMarkers(map: Map, level: Natural; ctx) =
  alias(dp, ctx.dp)

  var loc: Location
  loc.level = level

  forAllViewCells_CellCoords:
    (loc.row, loc.col) = (row, col)

    let srcLoc = map.links.getBySrc(loc)
    let destLoc = map.links.getByDest(loc)

    if (srcLoc.isSome  and not isSpecialLevelIndex(srcLoc.get.level)) or
       (destLoc.isSome and not isSpecialLevelIndex(destLoc.get.level)):

      let x = cellX(viewCol, dp)
      let y = cellY(viewRow, dp)
      drawLinkMarker(x, y, ctx)

# }}}
# {{{ drawNotes()
proc drawNotes(viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  let rect = rectN(
    ViewBufBorder,
    ViewBufBorder,
    viewBuf.rows - ViewBufBorder,
    viewBuf.cols - ViewBufBorder
  )

  for bufRow, bufCol, note in viewBuf.allNotes:
    if rect.contains(bufRow, bufCol):
      let
        viewRow = bufRow - ViewBufBorder
        viewCol = bufCol - ViewBufBorder
        x = cellX(viewCol, dp)
        y = cellY(viewRow, dp)

      drawNote(x, y, note, isCursorActive(viewRow, viewCol, dp), ctx)

# }}}

# {{{ drawWall()
proc drawWall(x, y: float; wall: Wall, orientation: Orientation,
              viewBuf: Level; viewRow, viewCol: Natural;
              regionBorder: bool; ctx) =

  alias(vg, ctx.vg)
  alias(dp, ctx.dp)

  let
    bufRow = toBufRow(viewRow)
    bufCol = toBufRow(viewCol)
    isCursorActive = isCursorActive(viewRow, viewCol, dp)

  template drawOriented(drawProc: untyped) =
    case orientation
    of Horiz:
      drawProc(x, y, orientation, regionBorder, ctx=ctx)
    of Vert:
      setVertTransform(x, y, ctx)
      drawProc(0, 0, orientation,
               isCursorActive=isCursorActive, regionBorder=regionBorder,
               ctx=ctx)
      vg.resetTransform()

  template drawOrientedWithFloorColor(drawProc: untyped, floorColor: Natural) =
    case orientation
    of Horiz:
      drawProc(x, y, orientation, floorColor,
               isCursorActive=isCursorActive, regionBorder=regionBorder,
               ctx=ctx)
    of Vert:
      setVertTransform(x, y, ctx)
      drawProc(0, 0, orientation, floorColor,
               isCursorActive=isCursorActive, regionBorder=regionBorder,
               ctx=ctx)
      vg.resetTransform()

  case wall
  of wNone:          discard
  of wWall:          drawOriented(drawSolidWallHoriz)
  of wIllusoryWall:  drawOriented(drawIllusoryWallHoriz)
  of wInvisibleWall: drawOriented(drawInvisibleWallHoriz)
  of wDoor:          drawOriented(drawDoorHoriz)
  of wLockedDoor:    drawOriented(drawLockedDoorHoriz)
  of wArchway:       drawOriented(drawArchwayHoriz)
  of wSecretDoor:    drawOriented(drawSecretDoorHoriz)
  of wOneWayDoorNE:  drawOriented(drawOneWayDoorHorizNE)
  of wOneWayDoorSW:  drawOriented(drawOneWayDoorHorizSW)
  of wLeverNE:       drawOriented(drawLeverHorizNE)
  of wLeverSW:       drawOriented(drawLeverHorizSW)
  of wStatueNE:      drawOriented(drawStatueHorizNE)
  of wStatueSW:      drawOriented(drawStatueHorizSW)
  of wWritingNE:     drawOriented(drawWritingHorizNE)
  of wWritingSW:     drawOriented(drawWritingHorizSW)
  of wKeyhole:       drawOriented(drawKeyholeHoriz)

  of wNicheNE:
    let floorColor = case orientation
    of Horiz: viewBuf.getFloorColor(bufRow, bufCol)
    of Vert:  viewBuf.getFloorColor(bufRow, bufCol-1)
    drawOrientedWithFloorColor(drawNicheHorizNE, floorColor)

  of wNicheSW:
    let floorColor = case orientation
    of Horiz: viewBuf.getFloorColor(bufRow-1, bufCol)
    of Vert:  viewBuf.getFloorColor(bufRow,   bufCol)
    drawOrientedWithFloorColor(drawNicheHorizSW, floorColor)

# }}}
# {{{ drawCellWallsNorth()
proc drawCellWallsNorth(viewBuf: Level, viewRow: Natural,
                        regionBorder: bool; ctx) =
  alias(dp, ctx.dp)

  let bufRow = toBufRow(viewRow)

  for viewCol in 0..<dp.viewCols:
    let bufCol = toBufCol(viewCol)

    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(bufRow, bufCol, dirN), Horiz,
      viewBuf, bufRow, bufCol,
      regionBorder,
      ctx
    )

# }}}
# {{{ drawCellWallsWest()
proc drawCellWallsWest(viewBuf: Level, viewCol: Natural,
                       regionBorder: bool; ctx) =
  alias(dp, ctx.dp)

  let bufCol = toBufCol(viewCol)

  for viewRow in 0..<dp.viewRows:
    let bufRow = toBufRow(viewRow)

    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(bufRow, bufCol, dirW), Vert,
      viewBuf, bufRow, bufCol,
      regionBorder,
      ctx
    )

# }}}
# {{{ drawEmptyRegionBorderNorth()
proc drawEmptyRegionBorderNorth(viewBuf: Level, viewRow: Natural; ctx) =
  alias(dp, ctx.dp)

  let bufRow = toBufRow(viewRow)

  for viewCol in 0..<dp.viewCols:
    let bufCol = toBufCol(viewCol)

    if viewBuf.getWall(bufRow, bufCol, dirN) == wNone:
      drawEmptyRegionBorderWallHoriz(
        cellX(viewCol, dp),
        cellY(viewRow, dp),
        ctx
      )

# }}}
# {{{ drawEmptyRegionBorderWest()
proc drawEmptyRegionBorderWest(viewBuf: Level, viewCol: Natural; ctx) =
  alias(dp, ctx.dp)

  let bufCol = toBufCol(viewCol)

  for viewRow in 0..<dp.viewRows:
    let bufRow = toBufRow(viewRow)

    if viewBuf.getWall(bufRow, bufCol, dirW) == wNone:
      drawEmptyRegionBorderWallVert(
        cellX(viewCol, dp),
        cellY(viewRow, dp),
        ctx
      )

# }}}
# {{{ drawWalls()
proc drawWalls(l: Level, viewBuf: Level; ctx) =
  alias(dp, ctx.dp)
  alias(ro, dp.regionOpts)

  for viewRow in 0..dp.viewRows:
    let row = case dp.cellCoordOpts.origin
              of coNorthWest: dp.viewStartRow + viewRow
              of coSouthWest: (l.rows - (dp.viewStartRow + viewRow))

    let regionBorder =
        ro.enabled and
        row > 0 and row < l.rows and
        row mod ro.rowsPerRegion == 0

    if not regionBorder:
      drawCellWallsNorth(viewBuf, viewRow, regionBorder=false, ctx)

  for viewCol in 0..dp.viewCols:
    let col = dp.viewStartCol + viewCol
    let regionBorder = ro.enabled and
                       col > 0 and col < l.cols and
                       col mod ro.colsPerRegion == 0
    if not regionBorder:
      drawCellWallsWest(viewBuf, viewCol, regionBorder=false, ctx)

# }}}

# {{{ drawRegionBorderRows()
template drawRegionBorderRows(l: Level; viewBuf: Level; ctx;
                              viewRow, body: untyped) =
  alias(dp, ctx.dp)

  let rr = dp.regionOpts.rowsPerRegion
  var startViewRow = (dp.viewStartRow div rr) * rr - dp.viewStartRow

  if dp.cellCoordOpts.origin == coSouthWest:
    startViewRow += l.rows mod rr

  if startViewRow < 0:
    startViewRow += rr

  for viewRow in countup(startViewRow, dp.viewRows, step=rr):
    let row = dp.viewStartRow + viewRow
    if row > 0 and row < l.rows:
      body

# }}}
# {{{ drawRegionBorderCols()
template drawRegionBorderCols(l: Level; viewBuf: Level; ctx;
                              viewCol, body: untyped) =
  alias(dp, ctx.dp)

  let rc = dp.regionOpts.colsPerRegion

  var startViewCol = (dp.viewStartCol div rc) * rc - dp.viewStartCol
  if startViewCol < 0:
    startViewCol += rc

  for viewCol in countup(startViewCol, dp.viewCols, step=rc):
    let col = dp.viewStartCol + viewCol
    if col > 0 and col < l.cols:
      body

# }}}
# {{{ drawRegionBorders()
proc drawRegionBorders(l: Level, viewBuf: Level; ctx) =
  alias(dp, ctx.dp)

  drawRegionBorderRows(l, viewBuf, ctx, viewRow):
    drawEmptyRegionBorderNorth(viewBuf, viewRow, ctx)
    drawCellWallsNorth(viewBuf, viewRow, regionBorder=true, ctx)

  drawRegionBorderCols(l, viewBuf, ctx, viewCol):
    drawEmptyRegionBorderWest(viewBuf, viewCol, ctx)
    drawCellWallsWest(viewBuf, viewCol, regionBorder=true, ctx)

# }}}
# {{{ drawRegionBorderOverhang()
proc drawRegionBorderOverhang(l: Level, viewBuf: Level; ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)

  drawRegionBorderRows(l, viewBuf, ctx, viewRow):
    let
      y = cellY(viewRow, dp)
      bufRow = toBufRow(viewRow)
      firstBufCol = ViewBufBorder-1
      lastBufCol = ViewBufBorder + dp.viewCols

    var color = if viewBuf.getWall(bufRow, firstBufCol, dirN) == wNone:
      ls.regionBorderEmptyColor
    else:
      ls.regionBorderNormalColor

    drawRegionBorderEdgeHoriz(cellX(-1, dp), y, color, west=false, ctx)

    color = if viewBuf.getWall(bufRow, lastBufCol, dirN) == wNone:
      ls.regionBorderEmptyColor
    else:
      ls.regionBorderNormalColor

    drawRegionBorderEdgeHoriz(cellX(dp.viewCols, dp), y, color, west=true, ctx)


  drawRegionBorderCols(l, viewBuf, ctx, viewCol):
    let
      x = cellX(viewCol, dp)
      bufCol = toBufCol(viewCol)
      firstBufRow = ViewBufBorder-1
      lastBufRow = ViewBufBorder + dp.viewRows

    var color = if viewBuf.getWall(firstBufRow, bufCol, dirW) == wNone:
      ls.regionBorderEmptyColor
    else:
      ls.regionBorderNormalColor

    drawRegionBorderEdgeVert(x, cellY(-1, dp), color, north=false, ctx)

    color = if viewBuf.getWall(lastBufRow, bufCol, dirW) == wNone:
      ls.regionBorderEmptyColor
    else:
      ls.regionBorderNormalColor

    drawRegionBorderEdgeVert(x, cellY(dp.viewRows, dp), color, north=true,
                             ctx)

# }}}

# {{{ drawSelection()
proc drawSelection(ctx) =
  let dp = ctx.dp

  let
    sel = dp.selection.get
    color = ctx.ls.selectionColor
    viewEndRow = dp.viewStartRow + dp.viewRows - 1
    viewEndCol = dp.viewStartCol + dp.viewCols - 1

  for r in dp.viewStartRow..viewEndRow:
    for c in dp.viewStartCol..viewEndCol:
      let draw = if dp.selectionRect.isSome:
                   let sr = dp.selectionRect.get
                   if sr.selected:
                     sel[r,c] or sr.rect.contains(r,c)
                   else:
                     not sr.rect.contains(r,c) and sel[r,c]
                 else: sel[r,c]
      if draw:
        let x = cellX(c - dp.viewStartCol, dp)
        let y = cellY(r - dp.viewStartRow, dp)

        drawCellHighlight(x, y, color, ctx)

# }}}
# {{{ drawSelectionHighlight()
proc drawSelectionHighlight(ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)

  let
    sel = dp.selectionBuffer.get.selection
    viewSelStartRow = dp.selStartRow - dp.viewStartRow
    viewSelStartCol = dp.selStartCol - dp.viewStartCol
    rows = min(sel.rows, dp.viewRows - viewSelStartRow)
    cols = min(sel.cols, dp.viewCols - viewSelStartCol)

  for r in 0..<rows:
    for c in 0..<cols:
      if sel[r,c] and viewSelStartRow + r >= 0 and viewSelStartCol + c >= 0:
        let x = cellX(viewSelStartCol + c, dp)
        let y = cellY(viewSelStartRow + r, dp)

        drawCellHighlight(x, y, ls.pastePreviewColor, ctx)

# }}}

# {{{ renderEdgeOutlines()
proc renderEdgeOutlines(viewBuf: Level): OutlineBuf =
  var ol = newOutlineBuf(viewBuf.rows, viewBuf.cols)

  let borderOffs = ViewBufBorder-1

  for r in borderOffs..<viewBuf.rows-borderOffs:
    for c in borderOffs..<viewBuf.cols-borderOffs:

      if viewBuf.isEmpty(r,c):
        var cell: OutlineCell

        if not isNeighbourCellEmpty(viewBuf, r,c, North): cell.incl(olN)
        else:
          if not isNeighbourCellEmpty(viewBuf, r,c, NorthWest): cell.incl(olNW)
          if not isNeighbourCellEmpty(viewBuf, r,c, NorthEast): cell.incl(olNE)

        if not isNeighbourCellEmpty(viewBuf, r,c, East):
          cell.incl(olE)
          cell.excl(olNE)
        else:
          if not isNeighbourCellEmpty(viewBuf, r,c, SouthEast): cell.incl(olSE)

        if not isNeighbourCellEmpty(viewBuf, r,c, South):
          cell.incl(olS)
          cell.excl(olSE)
        else:
          if not isNeighbourCellEmpty(viewBuf, r,c, SouthWest): cell.incl(olSW)

        if not isNeighbourCellEmpty(viewBuf, r,c, West):
          cell.incl(olW)
          cell.excl(olSW)
          cell.excl(olNW)

        ol[r,c] = cell

    result = ol

# }}}
# {{{ mergeSelectionAndOutlineBuffers()
proc mergeSelectionAndOutlineBuffers(viewBuf: Level,
                                     outlineBuf: Option[OutlineBuf], dp) =
  if dp.selectionBuffer.isSome:
    let startRow = dp.selStartRow - dp.viewStartRow + ViewBufBorder
    let startCol = dp.selStartCol - dp.viewStartCol + ViewBufBorder
    let copyBuf = dp.selectionBuffer.get.level

    discard viewBuf.paste(startRow, startCol,
                          src=copyBuf, dp.selectionBuffer.get.selection)

    if outlineBuf.isSome:
      let ob = outlineBuf.get
      let endRow = min(startRow + copyBuf.rows-1, ob.rows-1)
      let endCol = min(startCol + copyBuf.cols-1, ob.cols-1)

      let sr = max(startRow, 0)
      let sc = max(startCol, 0)
      for r in sr..endRow:
        for c in sc..endCol:
          ob[r,c] = {}

# }}}

# {{{ drawLevel*()
proc drawLevel*(map: Map, level: Natural; ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)
  alias(l, map.levels[level])

  let viewBuf = newLevelFrom(l,
    rectN(
      dp.viewStartRow,
      dp.viewStartCol,
      dp.viewStartRow + dp.viewRows,
      dp.viewStartCol + dp.viewCols
    ),
    border = ViewBufBorder
  )

  assert dp.viewStartRow + dp.viewRows <= l.rows
  assert dp.viewStartCol + dp.viewCols <= l.cols

  vg.save()

  setLevelClippingRect(l, ctx)

  if ls.backgroundHatchEnabled:
    drawBackgroundHatch(ctx)
  else:
    drawBackground(ctx)

  # outlineBuf has the same dimensions as viewBuf
  let outlineBuf = if ls.outlineStyle >= osSquareEdges:
    renderEdgeOutlines(viewBuf).some
  else:
    OutlineBuf.none

  mergeSelectionAndOutlineBuffers(viewBuf, outlineBuf, dp)

  drawBackgroundGrid(viewBuf, ctx)

  if ls.outlineStyle == osCell:
    drawCellOutlines(l, ctx)
  elif outlineBuf.isSome:
    drawEdgeOutlines(l, outlineBuf.get, ctx)

  drawCellBackgroundsAndGrid(viewBuf, ctx)

  let drawSelectionBuffer = dp.selectionBuffer.isSome
  if not drawSelectionBuffer:
    drawCursor(ctx)

  drawFloors(viewBuf, ctx)
  drawTrail(viewBuf, ctx)
  drawNotes(viewBuf, ctx)

  if not drawSelectionBuffer:
    drawLinkMarkers(map, level, ctx)

  if ls.shadowInnerWidthFactor > 0:
    drawInnerShadows(viewBuf, ctx)

  if ls.shadowOuterWidthFactor > 0:
    drawOuterShadows(viewBuf, ctx)

  drawWalls(l, viewBuf, ctx)
  drawBridges(viewBuf, ctx)

  if dp.regionOpts.enabled:
    drawRegionBorders(l, viewBuf, ctx)

  drawLabels(viewBuf, ctx)

  if dp.selection.isSome:
    drawSelection(ctx)

  if drawSelectionBuffer:
    drawSelectionHighlight(ctx)

  if dp.drawCursorGuides:
    drawCursorGuides(ctx)

  setLevelClippingRect(l, ctx)

  vg.restore()

  if dp.drawCellCoords:
    drawCellCoords(l, ctx)

  if dp.regionOpts.enabled:
    drawRegionBorderOverhang(l, viewBuf, ctx)

# }}}

# vim: et:ts=2:sw=2:fdm=marker

