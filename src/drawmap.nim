import lenientops
import math
import options

import glad/gl
import glfw
import koi
import nanovg

import common
import map
import selection


const
  MinZoomLevel = 1
  MaxZoomLevel = 20
  MinGridSize  = 13.0
  ZoomStep     = 2.0

  UltrathinStrokeWidth = 1.0

# Naming conventions
# ------------------
#
# The names `col`, `row` (or `c`, `r`) refer to the zero-based coordinates of
# a cell in a map. The cell in the top-left corner is the origin.
#
# `viewCol` and `viewRow` refer to the zero-based cell coodinates of a rectangular
# subarea of the map (the active view).
#
# Anything with `x` or `y` in the name refers to pixel-coordinates within the
# window's drawing area (top-left corner is the origin).
#
# All drawing procs interpret the passed in `(x,y)` coordinates as the
# upper-left corner of the object (e.g. a cell).
#

# {{{ Types
type
  DrawMapContext* = object
    ms*: MapStyle
    dp*: DrawMapParams
    vg*: NVGContext

  MapStyle* = ref object
    bgColor*:                   Color

    bgCrosshatchColor*:         Color
    bgCrosshatchEnabled*:       bool
    bgCrosshatchStrokeWidth*:   float
    bgCrosshatchSpacingFactor*: float

    coordsEnabled*:             bool
    coordsColor*:               Color
    coordsHighlightColor*:      Color

    cursorColor*:               Color
    cursorGuideColor*:          Color

    gridStyle*:                 GridStyle
    gridColorBackground*:       Color
    gridColorFloor*:            Color

    floorColor*:                Color
    fgColor*:                   Color
    lightFgColor*:              Color
    thinStroke*:                bool

    outlineStyle*:              OutlineStyle
    outlineColor*:              Color
    outlineWidthFactor*:        float

    pastePreviewColor*:         Color
    selectionColor*:            Color

  GridStyle* = enum
    gsNone, gsSolid, gsLoose, gsDashed

  OutlineStyle* = enum
    osNone, osCell, osSquareEdges, osRoundedEdges, osRoundedEdgesFilled


  DrawMapParams* = ref object
    startX*:       float
    startY*:       float

    cursorCol*:    Natural
    cursorRow*:    Natural

    viewStartCol*: Natural
    viewStartRow*: Natural
    viewCols*:     Natural
    viewRows*:     Natural

    selection*:    Option[Selection]
    selRect*:      Option[SelectionRect]
    pastePreview*: Option[CopyBuffer]

    drawCursorGuides*: bool

    # internal
    zoomLevel:          Natural
    gridSize:           float
    coordsFontSize:     float

    thinStrokeWidth:    float
    normalStrokeWidth:  float

    thinOffs:           float
    vertTransformXOffs: float

  Outline = enum
    olN, olNE, olE, olSE, olS, olSW, olW, olNW

  OutlineCell = set[Outline]

  OutlineBuf = ref object
    cols, rows: Natural
    cells: seq[OutlineCell]


proc newOutlineBuf(cols, rows: Natural): OutlineBuf =
  var b = new OutlineBuf
  b.cols = cols
  b.rows = rows
  newSeq(b.cells, b.cols * b.rows)
  result = b

proc `[]=`(b: OutlineBuf, c, r: Natural, cell: OutlineCell) =
  assert c < b.cols
  assert r < b.rows
  b.cells[b.cols*r + c] = cell

proc `[]`(b: OutlineBuf, c, r: Natural): OutlineCell =
  assert c < b.cols
  assert r < b.rows
  result = b.cells[b.cols*r + c]


# }}}

using
  ms:  MapStyle
  dp:  DrawMapParams
  ctx: DrawMapContext


# {{{ zoomLevel*()
proc getZoomLevel*(dp): Natural = dp.zoomLevel

# }}}
# {{{ setZoomLevel*()
proc setZoomLevel*(dp; ms; zl: Natural) =
  assert zl >= MinZoomLevel
  assert zl <= MaxZoomLevel

  dp.zoomLevel = zl
  dp.gridSize = MinGridSize + zl*ZoomStep

  if zl < 3 or ms.thinStroke:
    dp.thinStrokeWidth = 2.0
    dp.normalStrokeWidth = 2.0
    dp.thinOffs = 1.0
    dp.vertTransformXOffs = 0.0

  else:
    dp.thinStrokeWidth = 2.0
    dp.normalStrokeWidth = 3.0
    dp.thinOffs = 0.0
    dp.vertTransformXOffs = 1.0

  dp.coordsFontSize = if   zl <= 2:   9.0
                      elif zl <= 3:  10.0
                      elif zl <= 7:  11.0
                      elif zl <= 11: 12.0
                      else:          13.0

# }}}
# {{{ incZoomLevel*()
proc incZoomLevel*(ms; dp) =
  if dp.zoomLevel < MaxZoomLevel:
    dp.setZoomLevel(ms, dp.zoomLevel+1)

# }}}
# {{{ decZoomLevel*()
proc decZoomLevel*(ms; dp) =
  if dp.zoomLevel > MinZoomLevel:
    dp.setZoomLevel(ms, dp.zoomLevel-1)

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

# {{{ utils

# This is needed for drawing crisp lines
func snap(f: float, strokeWidth: float): float =
  let (i, _) = splitDecimal(f)
  let (_, offs) = splitDecimal(strokeWidth*0.5) # either 0 or 0.5
  result = i + offs

proc cellX(x: Natural, dp): float =
  dp.startX + dp.gridSize * x

proc cellY(y: Natural, dp): float =
  dp.startY + dp.gridSize * y

# }}}


proc renderPattern*(vg: NVGContext, fb: NVGLUFramebuffer, pxRatio: float) =
  if fb == nil: return

  let
    (fboWidth, fboHeight) = vg.imageSize(fb.image)
    winWidth = floor(fboWidth.float / pxRatio)
    winHeight = floor(fboHeight.float / pxRatio)

  # Draw some stuff to an FBO as a test
  nvgluBindFramebuffer(fb)

  glViewport(0, 0, fboWidth.GLsizei, fboHeight.GLsizei)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth, winHeight, pxRatio)

  vg.strokeColor(rgb(45, 42, 42))
  vg.strokeWidth(1.0)

  for i in 0..100:
    vg.beginPath()
    vg.moveTo(0, i.float*4)
    vg.lineTo(i.float*4, 0)
    vg.stroke()

#  vg.fillColor(rgba(220, 160, 0, 200))
#  vg.fill()

#[
  let sw = ms.bgCrosshatchStrokeWidth

  vg.fillColor(ms.bgColor)
  vg.strokeColor(ms.bgCrosshatchColor)
  vg.strokeWidth(sw)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows
    offs = max(w, h)
    lineSpacing = sw * ms.bgCrosshatchSpacingFactor

  let startX = snap(0, sw)
  let startY = snap(0, sw)

  vg.beginPath()
  vg.rect(startX, startY, w, h)
  vg.fill()

  var
    x1 = startX - offs
    y1 = startY + offs
    x2 = startX + offs
    y2 = startY - offs

  while x1 < dp.startX + offs:
    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    vg.stroke()

    x1 += lineSpacing
    x2 += lineSpacing
    y1 += lineSpacing
    y2 += lineSpacing
]#
  vg.endFrame()
  nvgluBindFramebuffer(nil)


# {{{ drawBgCrosshatch()
proc drawBgCrosshatch(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let strokeWidth = ms.bgCrosshatchStrokeWidth

  vg.fillColor(ms.bgColor)
  vg.strokeColor(ms.bgCrosshatchColor)
  vg.strokeWidth(strokeWidth)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows
    offs = max(w, h)
    lineSpacing = strokeWidth * ms.bgCrosshatchSpacingFactor

  let startX = snap(dp.startX, strokeWidth)
  let startY = snap(dp.startY, strokeWidth)

  vg.scissor(dp.startX, dp.startY, w, h)

  vg.beginPath()
  vg.rect(startX, startY, w, h)
  vg.fill()

  var
    x1 = startX - offs
    y1 = startY + offs
    x2 = startX + offs
    y2 = startY - offs

  while x1 < dp.startX + offs:
    vg.beginPath()
    vg.moveTo(x1, y1)
    vg.lineTo(x2, y2)
    vg.stroke()

    x1 += lineSpacing
    x2 += lineSpacing
    y1 += lineSpacing
    y2 += lineSpacing

  vg.resetScissor()

# }}}
# {{{ drawBackgroundGrid
proc drawBackgroundGrid(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let strokeWidth = UltrathinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.gridColorBackground)
  vg.strokeWidth(strokeWidth)

  let endX = snap(cellX(dp.viewCols, dp), strokeWidth)
  let endY = snap(cellY(dp.viewRows, dp), strokeWidth)

  for x in 0..dp.viewCols:
    let x = snap(cellX(x, dp), strokeWidth)
    let y = snap(dp.startY, strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(x, endY)
    vg.stroke()

  for y in 0..dp.viewRows:
    let x = snap(dp.startX, strokeWidth)
    let y = snap(cellY(y, dp), strokeWidth)
    vg.beginPath()
    vg.moveTo(x, y)
    vg.lineTo(endX, y)
    vg.stroke()

# }}}
# {{{ drawCellCoords()
proc drawCellCoords(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fontSize(dp.coordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fontFace("sans-bold")
      vg.fillColor(ms.coordsHighlightColor)
    else: 
      vg.fontFace("sans")
      vg.fillColor(ms.coordsColor)

  let endX = dp.startX + dp.gridSize * dp.viewCols
  let endY = dp.startY + dp.gridSize * dp.viewRows

  let fontSize = dp.coordsFontSize

  for c in 0..<dp.viewCols:
    let
      xPos = cellX(c, dp) + dp.gridSize*0.5
      col = dp.viewStartCol + c
      coord = $col

    setTextHighlight(col == dp.cursorCol)

    discard vg.text(xPos, dp.startY - fontSize, coord)
    discard vg.text(xPos, endY + fontSize*1.4, coord)

  for r in 0..<dp.viewRows:
    let
      yPos = cellY(r, dp) + dp.gridSize*0.5
      row = dp.viewStartRow + r
      coord = $(m.rows-1 - row)

    setTextHighlight(row == dp.cursorRow)

    discard vg.text(dp.startX - fontSize*1.2, yPos, coord)
    discard vg.text(endX + fontSize*1.6, yPos, coord)


# }}}
# {{{ drawCursor()
proc drawCursor(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fillColor(ms.cursorColor)
  vg.beginPath()
  vg.rect(x+1, y+1, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawCursorGuides()
proc drawCursorGuides(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    x = cellX(dp.cursorCol - dp.viewStartCol, dp)
    y = cellY(dp.cursorRow - dp.viewStartRow, dp)
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows

  vg.fillColor(ms.cursorGuideColor)
  vg.strokeColor(ms.cursorGuideColor)
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
# {{{ drawCellOutlines()
proc drawCellOutlines(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  func isOutline(c, r: Natural): bool =
    not (
      isNeighbourCellEmpty(m, c, r, North)     and
      isNeighbourCellEmpty(m, c, r, NorthEast) and
      isNeighbourCellEmpty(m, c, r, East)      and
      isNeighbourCellEmpty(m, c, r, SouthEast) and
      isNeighbourCellEmpty(m, c, r, South)     and
      isNeighbourCellEmpty(m, c, r, SouthWest) and
      isNeighbourCellEmpty(m, c, r, West)      and
      isNeighbourCellEmpty(m, c, r, NorthWest)
    )

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      if isOutline(dp.viewStartCol+c, dp.viewStartRow+r):
        let
          sw = UltrathinStrokeWidth
          x = snap(cellX(c, dp), sw)
          y = snap(cellY(r, dp), sw)

        vg.strokeWidth(sw)
        vg.fillColor(ms.outlineColor)
        vg.strokeColor(ms.outlineColor)

        vg.beginPath()
        vg.rect(x, y, dp.gridSize, dp.gridSize)
        vg.fill()
        vg.stroke()

# }}}
# {{{ generateEdgeOutlines()
proc generateEdgeOutlines(m: Map): OutlineBuf =
  var ol = newOutlineBuf(m.cols, m.rows)
  for r in 0..<m.rows:
    for c in 0..<m.cols:
      var cell: OutlineCell
      if not isNeighbourCellEmpty(m, c, r, North): cell.incl(olN)
      else:
        if not isNeighbourCellEmpty(m, c, r, NorthWest): cell.incl(olNW)
        if not isNeighbourCellEmpty(m, c, r, NorthEast): cell.incl(olNE)

      if not isNeighbourCellEmpty(m, c, r, East):
        cell.incl(olE)
        cell.excl(olNE)
      else:
        if not isNeighbourCellEmpty(m, c, r, SouthEast): cell.incl(olSE)

      if not isNeighbourCellEmpty(m, c, r, South):
        cell.incl(olS)
        cell.excl(olSE)
      else:
        if not isNeighbourCellEmpty(m, c, r, SouthWest): cell.incl(olSW)

      if not isNeighbourCellEmpty(m, c, r, West):
        cell.incl(olW)
        cell.excl(olSW)
        cell.excl(olNW)

      ol[c,r] = cell

    result = ol

# }}}
# {{{ drawEdgeOutlines()
proc drawEdgeOutlines(ob: OutlineBuf, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

#  vg.fillColor(ms.outlineColor)
#  var img = vg.imagePattern(0, 0, 4, 4, 0, g_crosshatch, 1.0)
  var img = vg.imagePattern(0, 0, 100, 100, 0, g_fb.image, 1.0)
  vg.fillPaint(img)

  proc draw(x, y: float, cell: OutlineCell) =
    let
      gs = dp.gridSize
      w  = (dp.gridSize * ms.outlineWidthFactor)+1
      x1 = x
      x2 = x + gs
      y1 = y
      y2 = y + gs

    proc drawRoundedEdges() =
      if olN in cell:
        vg.beginPath()
        vg.rect(x1, y1, gs, w)
        vg.fill()
      else:
        if olNW in cell:
          vg.beginPath()
          vg.arc(x1, y1, w, 0, PI*1.75, pwCW)
          vg.fill()
        if olNE in cell:
          vg.beginPath()
          vg.arc(x2, y1, w, PI*1.5, PI, pwCW)
          vg.fill()

      if olE in cell:
        vg.beginPath()
        vg.rect(x2-w, y1, w, gs)
        vg.fill()
      elif olSE in cell:
        vg.beginPath()
        vg.arc(x2, y2, w, PI, PI*0.5, pwCW)
        vg.fill()

      if olS in cell:
        vg.beginPath()
        vg.rect(x1, y2-w, gs, w)
        vg.fill()
      elif olSW in cell:
        vg.beginPath()
        vg.arc(x1, y2, w, PI*0.5, 0, pwCW)
        vg.fill()

      if olW in cell:
        vg.beginPath()
        vg.rect(x1, y1, w, gs)
        vg.fill()


    proc drawSquareEdges() =
      if olN in cell:
        vg.beginPath()
        vg.rect(x1, y1, gs, w)
        vg.fill()
      else:
        if olNW in cell:
          vg.beginPath()
          vg.rect(x1, y1, w, w)
          vg.fill()
        if olNE in cell:
          vg.beginPath()
          vg.rect(x2-w, y1, w, w)
          vg.fill()

      if olE in cell:
        vg.beginPath()
        vg.rect(x2-w, y1, w, gs)
        vg.fill()
      elif olSE in cell:
        vg.beginPath()
        vg.rect(x2-w, y2-w, w, w)
        vg.fill()

      if olS in cell:
        vg.beginPath()
        vg.rect(x1, y2-w, gs, w)
        vg.fill()
      elif olSW in cell:
        vg.beginPath()
        vg.rect(x1, y2-w, w, w)
        vg.fill()

      if olW in cell:
        vg.beginPath()
        vg.rect(x1, y1, w, gs)
        vg.fill()


    proc drawFilled() =
      vg.beginPath()
      vg.rect(x1, y1, gs, gs)
      vg.fill()


    if ms.outlineStyle == osRoundedEdges:
        drawRoundedEdges()

    elif ms.outlineStyle == osRoundedEdgesFilled:
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

    elif ms.outlineStyle == osSquareEdges:
      drawSquareEdges()


  for r in 0..<ob.rows:
    for c in 0..<ob.cols:
      let
        cell = ob[c,r]
        x = cellX(c, dp)
        y = cellY(r, dp)
      draw(x, y, cell)

# }}}

# {{{ drawIcon*()
proc drawIcon*(x, y, ox, oy: float, icon: string, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.setFont((dp.gridSize*0.53).float)
  vg.fillColor(ms.fgColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + dp.gridSize*ox + dp.gridSize*0.51,
                  y + dp.gridSize*oy + dp.gridSize*0.58, icon)

# }}}
# {{{ drawFloor()
proc drawFloor(x, y: float, color: Color, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let sw = UltrathinStrokeWidth

  vg.beginPath()
  vg.fillColor(color)
  vg.strokeColor(ms.gridColorFloor)
  vg.strokeWidth(sw)
  vg.rect(snap(x, sw), snap(y, sw), dp.gridSize, dp.gridSize)
  vg.fill()

  case ms.gridStyle
  of gsNone: discard

  of gsSolid:
    vg.stroke()

  of gsLoose:
    let
      offs = dp.gridSize * 0.2
      x1 = x + offs
      y1 = y + offs
      x2 = x + dp.gridSize - offs
      y2 = y + dp.gridSize - offs

    vg.strokeColor(ms.lightFgColor)
    vg.strokeWidth(sw)

    vg.beginPath()
    vg.moveTo(snap(x1, sw), snap(y, sw))
    vg.lineTo(snap(x2, sw), snap(y, sw))
    vg.stroke()

    vg.beginPath()
    vg.moveTo(snap(x, sw), snap(y1, sw))
    vg.lineTo(snap(x, sw), snap(y2, sw))
    vg.stroke()

  of gsDashed:
    discard

# }}}
# {{{ drawSecretDoor()
proc drawSecretDoor(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

#  vg.beginPath()
#  vg.fillColor(gray(0.7))
#  vg.rect(x+1, y+1, dp.gridSize-1, dp.gridSize-1)
#  vg.fill()

  drawIcon(x, y, 0, 0, "S", ctx)

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.fgColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.lightFgColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawClosedPit()
proc drawClosedPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.fgColor)
  vg.strokeWidth(sw)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)
    x2 = snap(x + offs + a, sw)
    y2 = snap(y + offs + a, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1+1, y1+1)
  vg.lineTo(x2-1, y2-1)
  vg.stroke()
  vg.beginPath()
  vg.moveTo(x2-1, y1+1)
  vg.lineTo(x1+1, y2-1)
  vg.stroke()

# }}}
# {{{ drawOpenPit()
proc drawOpenPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(ms.fgColor)
  vg.fillColor(ms.fgColor)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.lightFgColor)
  vg.strokeWidth(sw)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)
    x2 = snap(x + offs + a, sw)
    y2 = snap(y + offs + a, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.stroke()

  vg.beginPath()
  vg.moveTo(x1+1, y1+1)
  vg.lineTo(x2-1, y2-1)
  vg.stroke()
  vg.beginPath()
  vg.moveTo(x2-1, y1+1)
  vg.lineTo(x1+1, y2-1)
  vg.stroke()

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(ms.lightFgColor)
  vg.fillColor(ms.lightFgColor)

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawStairsDown()
proc drawStairsDown(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconStairsDown, ctx)

# }}}
# {{{ drawStairsUp()
proc drawStairsUp(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconStairsUp, ctx)

# }}}
# {{{ drawSpinner()
proc drawSpinner(x, y: float, ctx) =
  drawIcon(x, y, 0.06, 0, IconSpinner, ctx)

# }}}
# {{{ drawTeleport()
proc drawTeleport(x, y: float, ctx) =
  discard

# }}}
# {{{ drawCustom()
proc drawCustom(x, y: float, ctx) =
  discard

# }}}

# {{{ drawSolidWallHoriz*()
proc drawSolidWallHoriz*(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = dp.normalStrokeWidth
    xs = snap(x, sw)
    xe = snap(x + dp.gridSize, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.fgColor)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawIllusoryWallHoriz*()
proc drawIllusoryWallHoriz*(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = dp.normalStrokeWidth
    xs = x
    xe = x + dp.gridSize
    y = snap(y, sw)

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.fgColor)
  vg.strokeWidth(sw)

  var x = xs
  while x <= xe:
    vg.beginPath()
    vg.moveTo(snap(x, sw), y)
    vg.lineTo(snap(min(x+sw*1, xe), sw), y)
    vg.stroke()
    x += sw*3

# }}}
# {{{ drawInvisibleWallHoriz*()
proc drawInvisibleWallHoriz*(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    o = dp.thinOffs
    sw = dp.normalStrokeWidth
    sw2 = dp.normalStrokeWidth * 2
    xs = snap(x+sw*2+1 - o, sw2)
    xe = snap(x + dp.gridSize-sw*2, sw2)
    y = snap(y, sw2)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.lightFgColor)
  vg.strokeWidth(sw2)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawDoorHoriz*()
proc drawDoorHoriz*(x, y: float; ctx; fill: bool = false) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    o = dp.thinOffs
    wallLen = (dp.gridSize * 0.25).int
    doorWidthOffs = (if dp.zoomLevel < 4 or ms.thinStroke: -1.0 else: 0)
    doorWidth = round(dp.gridSize * 0.1) + doorWidthOffs
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen - o
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.fgColor)
  vg.fillColor(ms.fgColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door
  sw = dp.thinStrokeWidth
  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.rect(snap(x1+1, sw), snap(y1-o, sw), x2-x1-1, y2-y1+1+o)
  vg.stroke()
  if fill: vg.fill()

  # Wall end
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawLockedDoorHoriz*()
proc drawLockedDoorHoriz*(x, y: float, ctx) =
  drawDoorHoriz(x, y, ctx, fill=true)

# }}}
# {{{ drawSecretDoorHoriz*()
proc drawSecretDoorHoriz*(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    wallLen = (dp.gridSize * 0.25).int
    xs = x
    y  = y
    x1 = xs + wallLen + dp.thinOffs
    xe = xs + dp.gridSize
    x2 = xe - wallLen - dp.thinOffs

  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.fgColor)

  # Wall start
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  drawIcon(x, y-dp.gridSize/2, 0.02, -0.02, "S", ctx)

  # Wall end
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawArchwayHoriz*()
proc drawArchwayHoriz*(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    wallLenOffs = (if dp.zoomLevel < 2: -1.0 else: 0)
    wallLen = (dp.gridSize * 0.3).int + wallLenOffs
    doorWidth = round(dp.gridSize * 0.075)
    xs = x
    y  = y
    x1 = xs + wallLen + dp.thinOffs
    xe = xs + dp.gridSize
    x2 = xe - wallLen - dp.thinOffs
    y1 = y - doorWidth
    y2 = y + doorWidth

  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.fgColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door opening
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(x1, sw), snap(y1, sw))
  vg.lineTo(snap(x1, sw), snap(y2, sw))
  vg.stroke()

  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y1, sw))
  vg.lineTo(snap(x2, sw), snap(y2, sw))
  vg.stroke()

  # Wall end
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}

# {{{ setVertTransform()
proc setVertTransform(x, y: float, ctx) =
  let dp = ctx.dp
  let vg = ctx.vg

  vg.translate(x + dp.vertTransformXOffs, y)
  vg.rotate(degToRad(90.0))

  # We need to use some fudge factor here because of the grid snapping...
#  vg.translate(0, 0)

# }}}
# {{{ drawFloor()
proc drawFloor(viewBuf: Map, viewCol, viewRow: Natural,
               cursorActive: bool, ctx) =

  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let x = cellX(viewCol, dp)
  let y = cellY(viewRow, dp)

  template drawOriented(drawProc: untyped) =
    drawBg()
    vg.scissor(x, y, dp.gridSize+1, dp.gridSize+1)

    case viewBuf.getFloorOrientation(viewCol, viewRow):
    of Horiz:
      drawProc(x, y + floor(dp.gridSize*0.5), ctx)
    of Vert:
      setVertTransform(x + floor(dp.gridSize*0.5), y, ctx)
      drawProc(0, 0, ctx)
      vg.resetTransform()
    vg.resetScissor()

  template draw(drawProc: untyped) =
    drawBg()
    drawProc(x, y, ctx)

  proc drawBg() =
    drawFloor(x, y, ms.floorColor, ctx)
    if cursorActive:
      drawCursor(x, y, ctx)

  case viewBuf.getFloor(viewCol, viewRow)
  of fNone:
    if cursorActive:
      drawCursor(x, y, ctx)

  of fEmpty:               drawBg()
  of fDoor:                drawOriented(drawDoorHoriz)
  of fLockedDoor:          drawOriented(drawLockedDoorHoriz)
  of fArchway:             drawOriented(drawArchwayHoriz)
  of fSecretDoor:          draw(drawSecretDoor)
  of fPressurePlate:       draw(drawPressurePlate)
  of fHiddenPressurePlate: draw(drawHiddenPressurePlate)
  of fClosedPit:           draw(drawClosedPit)
  of fOpenPit:             draw(drawOpenPit)
  of fHiddenPit:           draw(drawHiddenPit)
  of fCeilingPit:          draw(drawCeilingPit)
  of fStairsDown:          draw(drawStairsDown)
  of fStairsUp:            draw(drawStairsUp)
  of fSpinner:             draw(drawSpinner)
  of fTeleport:            draw(drawTeleport)
  of fCustom:              draw(drawCustom)

# }}}
# {{{ drawWall()
proc drawWall(x, y: float, wall: Wall, ot: Orientation, ctx) =
  let vg = ctx.vg

  template drawOriented(drawProc: untyped) =
    case ot:
    of Horiz:
      drawProc(x, y, ctx)
    of Vert:
      setVertTransform(x, y, ctx)
      drawProc(0, 0, ctx)
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
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

# }}}
# {{{ drawWalls()
proc drawWalls(viewBuf: Map, viewCol, viewRow: Natural, ctx) =
  let dp = ctx.dp

  let groundEmpty = viewBuf.getFloor(viewCol, viewRow) == fNone

  if viewRow > 0 or (viewRow == 0 and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, dirN), Horiz, ctx
    )

  if viewCol > 0 or (viewCol == 0 and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, dirW), Vert, ctx
    )

  let viewEndCol = dp.viewCols-1
  if viewCol < viewEndCol or (viewCol == viewEndCol and not groundEmpty):
    drawWall(
      cellX(viewCol+1, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, dirE), Vert, ctx
    )

  let viewEndRow = dp.viewRows-1
  if viewRow < viewEndRow or (viewRow == viewEndRow and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow+1, dp),
      viewBuf.getWall(viewCol, viewRow, dirS), Horiz, ctx
    )

# }}}
# {{{ drawCellHighlight()
proc drawCellHighlight(x, y: float, color: Color, ctx) =
  let vg = ctx.vg
  let dp = ctx.dp

  vg.beginPath()
  vg.fillColor(color)
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawSelection()
proc drawSelection(ctx) =
  let dp = ctx.dp

  let
    sel = dp.selection.get
    color = ctx.ms.selectionColor
    viewEndCol = dp.viewStartCol + dp.viewCols - 1
    viewEndRow = dp.viewStartRow + dp.viewRows - 1

  for c in dp.viewStartCol..viewEndCol:
    for r in dp.viewStartRow..viewEndRow:
      let draw = if dp.selRect.isSome:
                   let sr = dp.selRect.get
                   if sr.fillValue:
                     sel[c,r] or sr.rect.contains(c,r)
                   else:
                     not sr.rect.contains(c,r) and sel[c,r]
                 else: sel[c,r]
      if draw:
        let x = cellX(c - dp.viewStartCol, dp)
        let y = cellY(r - dp.viewStartRow, dp)

        drawCellHighlight(x, y, color, ctx)

# }}}
# {{{ drawPastePreviewHighlight()
proc drawPastePreviewHighlight(ctx) =
  let dp = ctx.dp
  let ms = ctx.ms

  let
    sel = dp.pastePreview.get.selection
    viewCursorCol = dp.cursorCol - dp.viewStartCol
    viewCursorRow = dp.cursorRow - dp.viewStartRow
    cols = min(sel.cols, dp.viewCols - viewCursorCol)
    rows = min(sel.rows, dp.viewRows - viewCursorRow)

  for c in 0..<cols:
    for r in 0..<rows:
      if sel[c,r]:
        let x = cellX(viewCursorCol + c, dp)
        let y = cellY(viewCursorRow + r, dp)

        drawCellHighlight(x, y, ms.pastePreviewColor, ctx)

# }}}

# {{{ drawMap*()
proc drawMap*(m: Map, ctx) =
  let dp = ctx.dp
  let ms = ctx.ms

  assert dp.viewStartCol + dp.viewCols <= m.cols
  assert dp.viewStartRow + dp.viewRows <= m.rows

  if ms.coordsEnabled:
    drawCellCoords(m, ctx)

  if ms.bgCrosshatchEnabled:
    drawBgCrosshatch(ctx)

  drawBackgroundGrid(ctx)

  let viewBuf = newMapFrom(m,
    rectN(
      dp.viewStartCol,
      dp.viewStartRow,
      dp.viewStartCol + dp.viewCols,
      dp.viewStartRow + dp.viewRows
    )
  )

  if ms.outlineStyle > osNone:
    if ms.outlineStyle == osCell:
      drawCellOutlines(m, ctx)
    else:
      let outlineBuf = generateEdgeOutlines(viewBuf)
      drawEdgeOutlines(outlineBuf, ctx)

  if dp.pastePreview.isSome:
    viewBuf.paste(dp.cursorCol - dp.viewStartCol,
                  dp.cursorRow - dp.viewStartRow,
                  dp.pastePreview.get.map,
                  dp.pastePreview.get.selection)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      let cursorActive = dp.viewStartCol+c == dp.cursorCol and
                         dp.viewStartRow+r == dp.cursorRow
      drawFloor(viewBuf, c, r, cursorActive, ctx)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      drawWalls(viewBuf, c, r, ctx)

  if dp.drawCursorGuides:
    drawCursorGuides(m, ctx)

  if dp.selection.isSome:
    drawSelection(ctx)

  if dp.pastePreview.isSome:
    drawPastePreviewHighlight(ctx)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
