import lenientops
import math
import options

import glad/gl
import koi
import nanovg

import common
import map
import selection
import utils


const
  MinZoomLevel = 1
  MaxZoomLevel = 20
  MinGridSize  = 13.0
  ZoomStep     = 2.0

  UltrathinStrokeWidth = 1.0

  MinLineHatchSize = 3
  MaxLineHatchSize = 8

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
  DrawMapContext* = object
    ms*: MapStyle
    dp*: DrawMapParams
    vg*: NVGContext

  MapStyle* = ref object
    backgroundColor*:        Color
    drawColor*:              Color
    lightDrawColor*:         Color
    floorColor*:             Color
    thinLines*:              bool

    bgHatchEnabled*:         bool
    bgHatchColor*:           Color
    bgHatchStrokeWidth*:     float
    bgHatchSpacingFactor*:   float

    coordsColor*:            Color
    coordsHighlightColor*:   Color

    cursorColor*:            Color
    cursorGuideColor*:       Color

    gridStyle*:              GridStyle
    gridColorBackground*:    Color
    gridColorFloor*:         Color

    outlineStyle*:           OutlineStyle
    outlineFillStyle*:       OutlineFillStyle
    outlineOverscan*:        bool
    outlineColor*:           Color
    outlineWidthFactor*:     float

    innerShadowEnabled*:     bool
    innerShadowColor*:       Color
    innerShadowWidthFactor*: float
    outerShadowEnabled*:     bool
    outerShadowColor*:       Color
    outerShadowWidthFactor*: float

    pastePreviewColor*:      Color
    selectionColor*:         Color

    noteMapTextColor*:       Color
    noteMapCommentColor*:    Color
    noteMapIndexColor*:      Color
    noteMapIndexBgColor1*:   Color
    noteMapIndexBgColor2*:   Color
    noteMapIndexBgColor3*:   Color
    noteMapIndexBgColor4*:   Color

    notePaneTextColor*:      Color
    notePaneIndexColor*:     Color
    notePaneIndexBgColor1*:  Color
    notePaneIndexBgColor2*:  Color
    notePaneIndexBgColor3*:  Color
    notePaneIndexBgColor4*:  Color


  GridStyle* = enum
    gsNone, gsSolid, gsLoose, gsDashed

  OutlineStyle* = enum
    osNone, osCell, osSquareEdges, osRoundedEdges, osRoundedEdgesFilled

  OutlineFillStyle* = enum
    ofsSolid, ofsHatched


  DrawMapParams* = ref object
    startX*:       float
    startY*:       float

    cursorRow*:    Natural
    cursorCol*:    Natural

    viewStartRow*: Natural
    viewStartCol*: Natural
    viewRows*:     Natural
    viewCols*:     Natural

    selection*:    Option[Selection]
    selRect*:      Option[SelectionRect]
    pastePreview*: Option[CopyBuffer]

    drawCellCoords*:   bool
    drawCursorGuides*: bool

    # internal
    zoomLevel:          Natural
    gridSize:           float
    cellCoordsFontSize: float

    thinStrokeWidth:    float
    normalStrokeWidth:  float

    thinOffs:           float
    vertTransformXOffs: float

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

using
  ms:  MapStyle
  dp:  DrawMapParams
  ctx: DrawMapContext

# {{{ newDrawMapParams*()
proc newDrawMapParams*(): DrawMapParams =
  result = new DrawMapParams
  for paint in result.lineHatchPatterns.mitems:
    paint.image = NoImage

  result.zoomLevel = MinZoomLevel

# }}}

# {{{ zoomLevel*()
proc getZoomLevel*(dp): Natural = dp.zoomLevel

# }}}
# {{{ setZoomLevel*()
proc setZoomLevel*(dp; ms; zl: Natural) =
  assert zl >= MinZoomLevel
  assert zl <= MaxZoomLevel

  dp.zoomLevel = zl
  dp.gridSize = MinGridSize + zl*ZoomStep

  if zl < 3 or ms.thinLines:
    dp.thinStrokeWidth = 2.0
    dp.normalStrokeWidth = 2.0
    dp.thinOffs = 1.0
    dp.vertTransformXOffs = 0.0

  else:
    dp.thinStrokeWidth = 2.0
    dp.normalStrokeWidth = 3.0
    dp.thinOffs = 0.0
    dp.vertTransformXOffs = 1.0

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

proc cellX(x: int, dp): float =
  dp.startX + dp.gridSize * x

proc cellY(y: int, dp): float =
  dp.startY + dp.gridSize * y

proc isCursorActive(viewRow, viewCol: Natural, dp): bool =
  dp.pastePreview.isNone and
  dp.viewStartRow + viewRow == dp.cursorRow and
  dp.viewStartCol + viewCol == dp.cursorCol

# }}}

# {{{ renderHatchPatternImage()
proc renderHatchPatternImage(vg: NVGContext, fb: NVGLUFramebuffer,
                             pxRatio: float, strokeColor: Color,
                             spacing: float) =
  let
    (fboWidth, fboHeight) = vg.imageSize(fb.image)
    winWidth = floor(fboWidth.float / pxRatio)
    winHeight = floor(fboHeight.float / pxRatio)

  nvgluBindFramebuffer(fb)

  glViewport(0, 0, fboWidth.GLsizei, fboHeight.GLsizei)
  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth, winHeight, pxRatio)

  var sw = 1.0
  if pxRatio == 1.0:
    if spacing <= 4:
      vg.shapeAntiAlias(false)
    else:
      sw = 0.8

  vg.strokeColor(strokeColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  for i in 0..10:
    vg.moveTo(-2, i*spacing + 2)
    vg.lineTo(i*spacing + 2, -2)
  vg.stroke()

  vg.endFrame()
  vg.shapeAntiAlias(true)

  nvgluBindFramebuffer(nil)

# }}}
# {{{ renderLineHatchPatterns()
proc renderLineHatchPatterns(dp; vg: NVGContext, pxRatio: float,
                             strokeColor: Color) =
  # TODO free images first if calling this multiple times
  for spacing in dp.lineHatchPatterns.low..dp.lineHatchPatterns.high:
    var fb = vg.nvgluCreateFramebuffer(
      width  = spacing * pxRatio.int,
      height = spacing * pxRatio.int,
      {ifRepeatX, ifRepeatY}
    )
    renderHatchPatternImage(vg, fb, pxRatio, strokeColor, spacing.float)

    dp.lineHatchPatterns[spacing] = vg.imagePattern(0, 0,
                                                    spacing.float,
                                                    spacing.float,
                                                    0, fb.image, 1.0)

    fb.image = NoImage  # prevent deleting the image when deleting the FB
    nvgluDeleteFramebuffer(fb)

# }}}
# {{{ initDrawMapParams
proc initDrawMapParams*(dp; ms; vg: NVGContext, pxRatio: float) =
  for paint in dp.lineHatchPatterns:
    if paint.image != NoImage:
      vg.deleteImage(paint.image)

  renderLineHatchPatterns(dp, vg, pxRatio, ms.drawColor)

  dp.setZoomLevel(ms, dp.zoomLevel)

# }}}

# {{{ drawBackground()
proc drawBackground(ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fillColor(ms.backgroundColor)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows

  vg.beginPath()
  vg.rect(dp.startX, dp.startY, w, h)
  vg.fill()

# }}}
# {{{ drawBackgroundHatch()
proc drawBackgroundHatch(ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = ms.bgHatchStrokeWidth

  vg.strokeColor(ms.bgHatchColor)
  vg.strokeWidth(sw)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows
    offs = max(w, h)
    lineSpacing = sw * ms.bgHatchSpacingFactor

  let startX = snap(dp.startX, sw)
  let startY = snap(dp.startY, sw)

  vg.scissor(dp.startX, dp.startY, w, h)

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

  vg.resetScissor()

# }}}
# {{{ drawBackgroundGrid
proc drawBackgroundGrid(ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let strokeWidth = UltrathinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.gridColorBackground)
  vg.strokeWidth(strokeWidth)

  let endX = snap(cellX(dp.viewCols, dp), strokeWidth)
  let endY = snap(cellY(dp.viewRows, dp), strokeWidth)

  vg.beginPath()
  for x in 0..dp.viewCols:
    let x = snap(cellX(x, dp), strokeWidth)
    let y = snap(dp.startY, strokeWidth)
    vg.moveTo(x, y)
    vg.lineTo(x, endY)
  vg.stroke()

  vg.beginPath()
  for y in 0..dp.viewRows:
    let x = snap(dp.startX, strokeWidth)
    let y = snap(cellY(y, dp), strokeWidth)
    vg.moveTo(x, y)
    vg.lineTo(endX, y)
  vg.stroke()

# }}}
# {{{ drawCellCoords()
proc drawCellCoords(m: Map, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fontSize(dp.cellCoordsFontSize)
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

  let fontSize = dp.cellCoordsFontSize

  var x1f, x2f, y1f, y2f: float
  if ms.outlineOverscan:
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
      coord = $col

    setTextHighlight(col == dp.cursorCol)

    discard vg.text(xPos, dp.startY - fontSize*y1f, coord)
    discard vg.text(xPos, endY + fontSize*y2f, coord)

  for r in 0..<dp.viewRows:
    let
      yPos = cellY(r, dp) + dp.gridSize*0.5
      row = dp.viewStartRow + r
      coord = $(m.rows-1 - row)

    setTextHighlight(row == dp.cursorRow)

    discard vg.text(dp.startX - fontSize*x1f, yPos, coord)
    discard vg.text(endX + fontSize*x2f, yPos, coord)


# }}}
# {{{ drawCursor()
proc drawCursor(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fillColor(ms.cursorColor)
  vg.beginPath()
  vg.rect(x, y, dp.gridSize+1, dp.gridSize+1)
  vg.fill()

# }}}
# {{{ drawCursorGuides()
proc drawCursorGuides(m: Map, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

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
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  func isOutline(r,c: Natural): bool =
    not (
      isNeighbourCellEmpty(m, r,c, North)     and
      isNeighbourCellEmpty(m, r,c, NorthEast) and
      isNeighbourCellEmpty(m, r,c, East)      and
      isNeighbourCellEmpty(m, r,c, SouthEast) and
      isNeighbourCellEmpty(m, r,c, South)     and
      isNeighbourCellEmpty(m, r,c, SouthWest) and
      isNeighbourCellEmpty(m, r,c, West)      and
      isNeighbourCellEmpty(m, r,c, NorthWest)
    )

  let sw = UltrathinStrokeWidth

  vg.strokeWidth(sw)
  vg.fillColor(ms.outlineColor)
  vg.strokeColor(ms.outlineColor)
  vg.beginPath()

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      if isOutline(dp.viewStartRow+r, dp.viewStartCol+c):
        let
          x = snap(cellX(c, dp), sw)
          y = snap(cellY(r, dp), sw)

        vg.rect(x, y, dp.gridSize, dp.gridSize)

  vg.fill()
  vg.stroke()

# }}}
# {{{ renderEdgeOutlines()
proc renderEdgeOutlines(viewBuf: Map): OutlineBuf =
  var ol = newOutlineBuf(viewBuf.rows, viewBuf.cols)
  for r in 0..<viewBuf.rows:
    for c in 0..<viewBuf.cols:
      if viewBuf.getFloor(r,c) == fNone:
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
# {{{ drawEdgeOutlines()
proc drawEdgeOutlines(m: Map, ob: OutlineBuf, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  case ms.outlineFillStyle
  of ofsSolid:   vg.fillColor(ms.outlineColor)
  of ofsHatched: vg.fillPaint(dp.lineHatchPatterns[dp.lineHatchSize])

  proc draw(r,c: int, cell: OutlineCell) =
    let
      x = cellX(c, dp)
      y = cellY(r, dp)
      gs = dp.gridSize
      w  = dp.gridSize * ms.outlineWidthFactor + 1
      x1 = x
      x2 = x + gs
      y1 = y
      y2 = y + gs

    proc drawRoundedEdges() =
      vg.beginPath()
      if olN in cell: vg.rect(x1, y1, gs, w)
      if olE in cell: vg.rect(x2-w, y1, w, gs)
      if olS in cell: vg.rect(x1, y2-w, gs, w)
      if olW in cell: vg.rect(x1, y1, w, gs)
      vg.fill()

      if olNW in cell:
        vg.beginPath()
        vg.arc(x1, y1, w, 0, PI*0.5, pwCW)
        vg.lineTo(x1, y1)
        vg.closePath()
        vg.fill()

      if olNE in cell:
        vg.beginPath()
        vg.arc(x2, y1, w, PI*0.5, PI, pwCW)
        vg.lineTo(x2, y1)
        vg.closePath()
        vg.fill()

      if olSE in cell:
        vg.beginPath()
        vg.arc(x2, y2, w, PI, PI*1.5, pwCW)
        vg.lineTo(x2, y2)
        vg.closePath()
        vg.fill()

      if olSW in cell:
        vg.beginPath()
        vg.arc(x1, y2, w, PI*1.5, 0, pwCW)
        vg.lineTo(x1, y2)
        vg.closePath()
        vg.fill()


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


  vg.beginPath()
  var startRow, endRow, startCol, endCol: Natural

  if ms.outlineOverscan:
    let viewEndRow = dp.viewStartRow + dp.viewRows - 1
    startRow = if dp.viewStartRow == 0: 0 else: 1
    endRow = if viewEndRow == m.rows-1: ob.rows-1 else: ob.rows-2

    let viewEndCol = dp.viewStartCol + dp.viewCols - 1
    startCol = if dp.viewStartCol == 0: 0 else: 1
    endCol = if viewEndCol == m.cols-1: ob.cols-1 else: ob.cols-2
  else:
    startRow = 1
    endRow = ob.rows-2
    startCol = 1
    endCol = ob.cols-2

  for r in startRow..endRow:
    for c in startCol..endCol:
      let cell = ob[r,c]
      if not (cell == {}):
        draw(r-1, c-1, cell)
  vg.fill()

# }}}

# {{{ drawIcon*()
proc drawIcon*(x, y, ox, oy: float, icon: string, color: Color, ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.setFont((dp.gridSize*0.53).float)
  vg.fillColor(color)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + dp.gridSize*ox + dp.gridSize*0.51,
                  y + dp.gridSize*oy + dp.gridSize*0.58, icon)


proc drawIcon*(x, y, ox, oy: float, icon: string, ctx) =
  drawIcon(x, y, ox, oy, icon, ctx.ms.drawColor, ctx)

# }}}
# {{{ drawIndexedNote*()
proc drawIndexedNote*(x, y: float, i: Natural, size: float,
                      bgColor, fgColor: Color, vg: NVGContext) =
  vg.fillColor(bgColor)
  vg.beginPath()
  vg.circle(x + size*0.5, y + size*0.5, size*0.35)
  vg.fill()

  vg.setFont((size*0.39).float)
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + size*0.50, y + size*0.53, $i)

proc drawIndexedNote*(x, y: float, i: Natural, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  drawIndexedNote(x, y, i, dp.gridSize,
                  bgColor=ms.noteMapIndexBgColor1,
                  fgColor=ms.noteMapIndexColor, vg)

# }}}
# {{{ drawCustomIdNote*()
proc drawCustomIdNote*(x, y: float, s: string, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.setFont((dp.gridSize * 0.48).float)
  vg.fillColor(ms.noteMapTextColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + dp.gridSize*0.52,
                  y + dp.gridSize*0.55, s)

# }}}
# {{{ drawFloor()
proc drawFloor(x, y: float, color: Color, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = UltrathinStrokeWidth
  vg.strokeColor(ms.gridColorFloor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.fillColor(color)
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

  case ms.gridStyle
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

  of gsDashed:
    discard

# }}}
# {{{ drawSecretDoor()
proc drawSecretDoor(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.beginPath()
  vg.fillPaint(dp.lineHatchPatterns[dp.lineHatchSize])
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

  let bgCol = ms.floorColor
  drawIcon(x-1, y, 0, 0, "S", bgCol, ctx)
  drawIcon(x+1, y, 0, 0, "S", bgCol, ctx)
  drawIcon(x, y-1, 0, 0, "S", bgCol, ctx)
  drawIcon(x, y+1, 0, 0, "S", bgCol, ctx)

  drawIcon(x, y, 0, 0, "S", ctx)

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.drawColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.lightDrawColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawOpenPitWithColor()
proc drawOpenPitWithColor(x, y: float, color: Color, ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    sw = dp.thinStrokeWidth
    sw2 = sw*0.5
    x1 = snap(x + offs - sw2, sw)
    y1 = snap(y + offs - sw2, sw)
    a = dp.gridSize - 2*offs + sw + 1 - dp.thinOffs

  vg.fillColor(color)
  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()

# }}}
# {{{ drawOpenPit()
proc drawOpenPit(x, y: float, ctx) =
  drawOpenPitWithColor(x, y, ctx.ms.drawColor, ctx)

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float, ctx) =
  drawOpenPitWithColor(x, y, ctx.ms.lightDrawColor, ctx)

# }}}
# {{{ drawClosedPitWithColor()
proc drawClosedPitWithColor(x, y: float, color: Color, ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
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
proc drawClosedPit(x, y: float, ctx) =
  drawClosedPitWithColor(x, y, ctx.ms.drawColor, ctx)

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float, ctx) =
  drawClosedPitWithColor(x, y, ctx.ms.lightDrawColor, ctx)

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
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    sw = dp.normalStrokeWidth
    xs = snap(x, sw)
    xe = snap(x + dp.gridSize, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.drawColor)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawIllusoryWallHoriz*()
proc drawIllusoryWallHoriz*(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    sw = dp.normalStrokeWidth
    xs = x
    xe = x + dp.gridSize
    y = snap(y, sw)
    # TODO make zoom dependent
    len = 2.0
    pad = 7.0

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.drawColor)
  vg.strokeWidth(sw)

  var x = xs
  vg.beginPath()
  while x <= xe:
    vg.moveTo(snap(x, sw), y)
    vg.lineTo(snap(min(x+len, xe), sw), y)
    x += pad
  vg.stroke()

# }}}
# {{{ drawInvisibleWallHoriz*()
proc drawInvisibleWallHoriz*(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    o = dp.thinOffs
    sw = dp.normalStrokeWidth
    sw2 = dp.normalStrokeWidth * 2
    xs = snap(x+sw*2+1 - o, sw2)
    xe = snap(x + dp.gridSize-sw*2, sw2)
    y = snap(y, sw2)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.lightDrawColor)
  vg.strokeWidth(sw2)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawDoorHoriz*()
proc drawDoorHoriz*(x, y: float; ctx; fill: bool = false) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    o = dp.thinOffs
    wallLen = (dp.gridSize * 0.25).int
    doorWidthOffs = (if dp.zoomLevel < 4 or ms.thinLines: -1.0 else: 0)
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
  vg.strokeColor(ms.drawColor)
  vg.fillColor(ms.drawColor)

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
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    wallLen = (dp.gridSize * 0.25).int
    xs = x
    y  = y
    x1 = xs + wallLen + dp.thinOffs
    xe = xs + dp.gridSize
    x2 = xe - wallLen - dp.thinOffs

  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.drawColor)

  # Wall start
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  drawIcon(x, y-dp.gridSize*0.5, 0.02, -0.02, "S", ctx)

  # Wall end
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawArchwayHoriz*()
proc drawArchwayHoriz*(x, y: float, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

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
  vg.strokeColor(ms.drawColor)

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

  # We need to use some fudge factor here because of the grid snapping...
  vg.translate(x + dp.vertTransformXOffs, y)
  vg.rotate(degToRad(90.0))

# }}}
# {{{ drawCellFloor()
proc drawCellFloor(viewBuf: Map, viewRow, viewCol: Natural,
                   cursorActive: bool, ctx) =

  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    bufRow = viewRow+1
    bufCol = viewCol+1
    x = cellX(viewCol, dp)
    y = cellY(viewRow, dp)

  template drawOriented(drawProc: untyped) =
    drawBg()
    vg.scissor(x, y, dp.gridSize+1, dp.gridSize+1)

    case viewBuf.getFloorOrientation(bufRow, bufCol):
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

  case viewBuf.getFloor(bufRow, bufCol)
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
# {{{ drawFloors()
proc drawFloors(viewBuf: Map, ctx) =
  alias(dp, ctx.dp)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      drawCellFloor(viewBuf, r,c, isCursorActive(r,c, dp), ctx)

# }}}
# {{{ drawNote()
proc drawNote(x, y: float, note: Note, ctx) =
  alias(ms, ctx.ms)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let w = dp.gridSize*0.4

  case note.kind
  of nkIndexed:
    drawIndexedNote(x, y, note.index, ctx)

  of nkCustomId:
    drawCustomIdNote(x, y, note.customId, ctx)

  of nkComment:
    vg.fillColor(ms.noteMapCommentColor)
    vg.beginPath()
    vg.moveTo(x + dp.gridSize - w, y)
    vg.lineTo(x + dp.gridSize + 1, y + w+1)
    vg.lineTo(x + dp.gridSize + 1, y)
    vg.closePath()
    vg.fill()

  # }}}
# {{{ drawNotes()
proc drawNotes(viewBuf: Map, ctx) =
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let bufRow = viewRow+1
      let bufCol = viewCol+1
      if viewBuf.hasNote(bufRow, bufCol):
        let
          note = viewBuf.getNote(bufRow, bufCol)
          x = cellX(viewCol, dp)
          y = cellY(viewRow, dp)

        drawNote(x, y, note, ctx)

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
# {{{ drawCellWalls()
proc drawCellWalls(viewBuf: Map, viewRow, viewCol: Natural, ctx) =
  let dp = ctx.dp

  let
    bufRow = viewRow+1
    bufCol = viewCol+1
    floorEmpty = viewBuf.getFloor(bufRow, bufCol) == fNone

  drawWall(
    cellX(viewCol, dp),
    cellY(viewRow, dp),
    viewBuf.getWall(bufRow, bufCol, dirN), Horiz, ctx
  )

  drawWall(
    cellX(viewCol, dp),
    cellY(viewRow, dp),
    viewBuf.getWall(bufRow, bufCol, dirW), Vert, ctx
  )

  let viewEndRow = dp.viewRows-1
  if viewRow == viewEndRow:
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow+1, dp),
      viewBuf.getWall(bufRow, bufCol, dirS), Horiz, ctx
    )

  let viewEndCol = dp.viewCols-1
  if viewCol == viewEndCol:
    drawWall(
      cellX(viewCol+1, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(bufRow, bufCol, dirE), Vert, ctx
    )

# }}}
# {{{ drawWalls()
proc drawWalls(viewBuf: Map, ctx) =
  alias(dp, ctx.dp)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      drawCellWalls(viewBuf, r,c, ctx)

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
    viewEndRow = dp.viewStartRow + dp.viewRows - 1
    viewEndCol = dp.viewStartCol + dp.viewCols - 1

  for r in dp.viewStartRow..viewEndRow:
    for c in dp.viewStartCol..viewEndCol:
      let draw = if dp.selRect.isSome:
                   let sr = dp.selRect.get
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
# {{{ drawPastePreviewHighlight()
proc drawPastePreviewHighlight(ctx) =
  alias(dp, ctx.dp)
  alias(ms, ctx.ms)

  let
    sel = dp.pastePreview.get.selection
    viewCursorRow = dp.cursorRow - dp.viewStartRow
    viewCursorCol = dp.cursorCol - dp.viewStartCol
    rows = min(sel.rows, dp.viewRows - viewCursorRow)
    cols = min(sel.cols, dp.viewCols - viewCursorCol)

  for r in 0..<rows:
    for c in 0..<cols:
      if sel[r,c]:
        let x = cellX(viewCursorCol + c, dp)
        let y = cellY(viewCursorRow + r, dp)

        drawCellHighlight(x, y, ms.pastePreviewColor, ctx)

# }}}
# {{{ drawInnerShadows()
proc drawInnerShadows(viewBuf: Map, ctx) =
  alias(dp, ctx.dp)
  alias(ms, ctx.ms)
  alias(vg, ctx.vg)

  vg.fillColor(ms.innerShadowColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ms.innerShadowWidthFactor

  for bufRow in 1..<viewBuf.rows-1:
    for bufCol in 1..<viewBuf.cols-1:
      let viewRow = bufRow-1
      let viewCol = bufCol-1

      if not isCursorActive(viewRow, viewCol, dp):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)

        if viewBuf.getFloor(bufRow, bufCol) != fNone:
          if isNeighbourCellEmpty(viewBuf, bufRow, bufCol, North):
            vg.rect(x, y, dp.gridSize, shadowWidth)

          if isNeighbourCellEmpty(viewBuf, bufRow, bufCol, West):
            vg.rect(x, y, shadowWidth, dp.gridSize)

  vg.fill()
# }}}
# {{{ drawOuterShadows()
proc drawOuterShadows(viewBuf: Map, ctx) =
  alias(dp, ctx.dp)
  alias(ms, ctx.ms)
  alias(vg, ctx.vg)

  vg.fillColor(ms.outerShadowColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ms.outerShadowWidthFactor

  for bufRow in 1..<viewBuf.rows-1:
    for bufCol in 1..<viewBuf.cols-1:
      let viewRow = bufRow-1
      let viewCol = bufCol-1

      if not isCursorActive(viewRow, viewCol, dp):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)

        if viewBuf.getFloor(bufRow, bufCol) == fNone:
          if not isNeighbourCellEmpty(viewBuf, bufRow, bufCol, North):
            vg.rect(x, y, dp.gridSize, shadowWidth)

          if not isNeighbourCellEmpty(viewBuf, bufRow, bufCol, West):
            vg.rect(x, y, shadowWidth, dp.gridSize)

  vg.fill()
# }}}

# {{{ mergePasteAndOutlineBufs*()
proc mergePasteAndOutlineBufs*(viewBuf: Map,
                               outlineBuf: Option[OutlineBuf], ctx) =
  alias(dp, ctx.dp)

  if dp.pastePreview.isSome:
    let startRow = dp.cursorRow - dp.viewStartRow + 1
    let startCol = dp.cursorCol - dp.viewStartCol + 1
    let copyBuf = dp.pastePreview.get.map

    viewBuf.paste(startRow, startCol,
                  src=copyBuf, dp.pastePreview.get.selection)

    if outlineBuf.isSome:
      let ob = outlineBuf.get
      let endRow = min(startRow + copyBuf.rows-1, ob.rows-1)
      let endCol = min(startCol + copyBuf.cols-1, ob.cols-1)

      for r in startRow..endRow:
        for c in startCol..endCol:
          ob[r,c] = {}

# }}}
# {{{ drawMap*()
proc drawMap*(m: Map, ctx) =
  alias(dp, ctx.dp)
  alias(ms, ctx.ms)

  assert dp.viewStartRow + dp.viewRows <= m.rows
  assert dp.viewStartCol + dp.viewCols <= m.cols

  drawBackground(ctx)

  if dp.drawCellCoords:
    drawCellCoords(m, ctx)

  if ms.bgHatchEnabled:
    drawBackgroundHatch(ctx)

  drawBackgroundGrid(ctx)

  let viewBuf = newMapFrom(m,
    rectN(
      dp.viewStartRow,
      dp.viewStartCol,
      dp.viewStartRow + dp.viewRows,
      dp.viewStartCol + dp.viewCols
    ),
    border=1
  )

  let outlineBuf = if ms.outlineStyle >= osSquareEdges:
    renderEdgeOutlines(viewBuf).some
  else:
    OutlineBuf.none

  mergePasteAndOutlineBufs(viewBuf, outlineBuf, ctx)

  if ms.outlineStyle == osCell:
    drawCellOutlines(m, ctx)
  elif outlineBuf.isSome:
    drawEdgeOutlines(m, outlineBuf.get, ctx)

  drawFloors(viewBuf, ctx)
  drawNotes(viewBuf, ctx)

  # TODO finish shadow implementation (draw corners)
  if ms.innerShadowEnabled:
    drawInnerShadows(viewBuf, ctx)

  if ms.outerShadowEnabled:
    drawOuterShadows(viewBuf, ctx)

  if dp.selection.isSome:
    drawSelection(ctx)

  if dp.pastePreview.isSome:
    drawPastePreviewHighlight(ctx)

  # TODO blend selection/preview tint with wall color
  drawWalls(viewBuf, ctx)

  if dp.drawCursorGuides:
    drawCursorGuides(m, ctx)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
