import lenientops
import math
import options

import glad/gl
import koi
import nanovg

import common
import icons
import level
import rect
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
    drawCursorGuides*: bool

    # internal
    zoomLevel:          Natural
    gridSize:           float
    cellCoordsFontSize: float

    thinStrokeWidth:    float
    normalStrokeWidth:  float

    lineWidth:          LineWidth
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
  ls:  LevelStyle
  dp:  DrawLevelParams
  ctx: DrawLevelContext

# {{{ newDrawLevelParams*()
proc newDrawLevelParams*(): DrawLevelParams =
  result = new DrawLevelParams
  for paint in result.lineHatchPatterns.mitems:
    paint.image = NoImage

  result.zoomLevel = MinZoomLevel

# }}}

# {{{ zoomLevel*()
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
    dp.thinOffs = 1.0
    dp.vertTransformXOffs = 1.0

  elif zl < 3 or dp.lineWidth == lwNormal:
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
  dp.selectionBuffer.isNone and
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
# {{{ initDrawLevelParams
proc initDrawLevelParams*(dp; ls; vg: NVGContext, pxRatio: float) =
  for paint in dp.lineHatchPatterns:
    if paint.image != NoImage:
      vg.deleteImage(paint.image)

  renderLineHatchPatterns(dp, vg, pxRatio, ls.drawColor)

  dp.setZoomLevel(ls, dp.zoomLevel)

# }}}

# {{{ drawBackground()
proc drawBackground(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fillColor(ls.backgroundColor)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows

  vg.beginPath()
  vg.rect(dp.startX, dp.startY, w, h)
  vg.fill()

# }}}
# {{{ drawBackgroundHatch()
proc drawBackgroundHatch(ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = ls.bgHatchStrokeWidth

  vg.save()

  vg.strokeColor(ls.bgHatchColor)
  vg.strokeWidth(sw)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows
    offs = max(w, h)
    lineSpacing = sw * ls.bgHatchSpacingFactor

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
proc drawCellCoords(l: Level, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.fontSize(dp.cellCoordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fontFace("sans-bold")
      vg.fillColor(ls.coordsHighlightColor)
    else:
      vg.fontFace("sans")
      vg.fillColor(ls.coordsColor)

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
      coord = $col

    setTextHighlight(col == dp.cursorCol)

    discard vg.text(xPos, dp.startY - fontSize*y1f, coord)
    discard vg.text(xPos, endY + fontSize*y2f, coord)

  for r in 0..<dp.viewRows:
    let
      yPos = cellY(r, dp) + dp.gridSize*0.5
      row = dp.viewStartRow + r
      coord = $(l.rows - 1 - row)

    setTextHighlight(row == dp.cursorRow)

    discard vg.text(dp.startX - fontSize*x1f, yPos, coord)
    discard vg.text(endX + fontSize*x2f, yPos, coord)


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

  vg.fillColor(ls.cursorGuideColor)
  vg.strokeColor(ls.cursorGuideColor)
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
proc drawCellOutlines(l: Level, ctx) =
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

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      if isOutline(dp.viewStartRow+r, dp.viewStartCol+c):
        let x = snap(cellX(c, dp), sw)
        let y = snap(cellY(r, dp), sw)

        vg.rect(x, y, dp.gridSize, dp.gridSize)

  vg.fill()
  vg.stroke()

# }}}
# {{{ renderEdgeOutlines()
proc renderEdgeOutlines(viewBuf: Level): OutlineBuf =
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
proc drawEdgeOutlines(l: Level, ob: OutlineBuf, ctx) =
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
  var startRow, endRow, startCol, endCol: Natural

  if ls.outlineOverscan:
    let viewEndRow = dp.viewStartRow + dp.viewRows - 1
    startRow = if dp.viewStartRow == 0: 0 else: 1
    endRow = if viewEndRow == l.rows-1: ob.rows-1 else: ob.rows-2

    let viewEndCol = dp.viewStartCol + dp.viewCols - 1
    startCol = if dp.viewStartCol == 0: 0 else: 1
    endCol = if viewEndCol == l.cols-1: ob.cols-1 else: ob.cols-2
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

# {{{ drawGrid()
proc drawGrid(x, y: float, color: Color, gridStyle: GridStyle; ctx) =
  alias(ls, ctx.ls)
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
# {{{ drawFloorBg()
proc drawFloorBg(x, y: float, color: Color, ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.beginPath()
  vg.fillColor(color)
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

# }}}
# {{{ drawIcon()
proc drawIcon(x, y, ox, oy: float, icon: string,
              gridSize: float, color: Color, fontSizeFactor: float,
              vg: NVGContext) =

  vg.setFont(gridSize * fontSizeFactor)
  vg.fillColor(color)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + gridSize*ox + gridSize*0.51,
                  y + gridSize*oy + gridSize*0.58, icon)

template drawIcon(x, y, ox, oy: float, icon: string, ctx) =
  drawIcon(x, y, ox, oy, icon, ctx.dp.gridSize, ctx.ls.drawColor,
          DefaultIconFontSizeFactor, ctx.vg)

# }}}
# {{{ drawIndexedNote*()
proc drawIndexedNote*(x, y: float, i: Natural, size: float,
                      bgColor, fgColor: Color, vg: NVGContext) =
  vg.fillColor(bgColor)
  vg.beginPath()
  vg.circle(x + size*0.5, y + size*0.5, size*0.35)
  vg.fill()

  vg.setFont((size*0.4).float)
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + size*0.51, y + size*0.54, $i)

proc drawIndexedNote(x, y: float, index: Natural, colorIdx: Natural, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  drawIndexedNote(x, y, index, dp.gridSize,
                  bgColor=ls.noteLevelIndexBgColor[colorIdx],
                  fgColor=ls.noteLevelIndexColor, vg)

# }}}
# {{{ drawCustomIdNote()
proc drawCustomIdNote(x, y: float, s: string, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  vg.setFont((dp.gridSize * 0.48).float)
  vg.fillColor(ls.noteLevelMarkerColor)
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + dp.gridSize*0.52,
                  y + dp.gridSize*0.55, s)

# }}}

# {{{ drawTrail()
proc drawTrail(x, y: float, ctx) =
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

  let a = dp.gridSize - 2*offs + sw + 1 - dp.thinOffs

  vg.fillColor(ls.lightDrawColor)
  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()

# }}}
# {{{ drawSecretDoor()
proc drawSecretDoor(x, y: float, isCursorActive: bool, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)

  alias(vg, ctx.vg)

  vg.beginPath()
  vg.fillPaint(dp.lineHatchPatterns[dp.lineHatchSize])
  vg.rect(x, y, dp.gridSize, dp.gridSize)
  vg.fill()

  let
    icon = "S"
    bgCol = if isCursorActive: ls.cursorColor else: ls.floorColor
    fontSizeFactor = DefaultIconFontSizeFactor
    gs = dp.gridSize

  drawIcon(x-2, y, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x+2, y, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x, y-2, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)
  drawIcon(x, y+2, 0, 0, icon, gs, bgCol, fontSizeFactor, vg)

  drawIcon(x, y, 0, 0, icon, gs, ls.drawColor, fontSizeFactor, vg)

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ls.drawColor)
  vg.strokeWidth(sw)

  vg.beginPath()
  vg.rect(snap(x + offs, sw), snap(y + offs, sw), a, a)
  vg.stroke()

# }}}
# {{{ drawHiddenPressurePlate()
proc drawHiddenPressurePlate(x, y: float, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1 - dp.thinOffs
    sw = dp.thinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ls.lightDrawColor)
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

  var x1, y1: float
  if dp.lineWidth == lwThin:
    x1 = x + offs
    y1 = y + offs
  else:
    let sw2 = sw*0.5
    x1 = snap(x + offs - sw2, sw)
    y1 = snap(y + offs - sw2, sw)

  let a = dp.gridSize - 2*offs + sw + 1 - dp.thinOffs

  vg.fillColor(color)
  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()

# }}}
# {{{ drawOpenPit()
proc drawOpenPit(x, y: float, ctx) =
  drawOpenPitWithColor(x, y, ctx.ls.drawColor, ctx)

# }}}
# {{{ drawCeilingPit()
proc drawCeilingPit(x, y: float, ctx) =
  drawOpenPitWithColor(x, y, ctx.ls.lightDrawColor, ctx)

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
  drawClosedPitWithColor(x, y, ctx.ls.drawColor, ctx)

# }}}
# {{{ drawHiddenPit()
proc drawHiddenPit(x, y: float, ctx) =
  drawClosedPitWithColor(x, y, ctx.ls.lightDrawColor, ctx)

# }}}
# {{{ drawStairsDown()
proc drawStairsDown(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconStairsDown, ctx)

# }}}
# {{{ drawStairsUp()
proc drawStairsUp(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconStairsUp, ctx)

# }}}
# {{{ drawExitDoor()
proc drawExitDoor(x, y: float, ctx) =
  drawIcon(x, y, 0.05, 0, IconExit, ctx.dp.gridSize, ctx.ls.drawColor,
           fontSizeFactor=0.7, ctx.vg)

# }}}
# {{{ drawSpinner()
proc drawSpinner(x, y: float, ctx) =
  drawIcon(x, y, 0.06, 0, IconSpinner, ctx)

# }}}
# {{{ drawTeleportSource()
proc drawTeleportSource(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconTeleport, ctx.dp.gridSize, ctx.ls.drawColor,
           fontSizeFactor=0.7, ctx.vg)

# }}}
# {{{ drawTeleportDestination()
proc drawTeleportDestination(x, y: float, ctx) =
  drawIcon(x, y, 0, 0, IconTeleport, ctx.dp.gridSize, ctx.ls.lightDrawColor,
           fontSizeFactor=0.7, ctx.vg)

# }}}

# {{{ drawSolidWallHoriz*()
proc drawSolidWallHoriz*(x, y: float, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    sw = dp.normalStrokeWidth
    xs = snap(x, sw)
    xe = snap(x + dp.gridSize, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ls.drawColor)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawIllusoryWallHoriz*()
proc drawIllusoryWallHoriz*(x, y: float, ctx) =
  alias(ls, ctx.ls)
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
  vg.strokeColor(ls.drawColor)
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
  alias(ls, ctx.ls)
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
  vg.strokeColor(ls.lightDrawColor)
  vg.strokeWidth(sw2)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

# }}}
# {{{ drawDoorHoriz*()
proc drawDoorHoriz*(x, y: float, ctx; fill: bool = false) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    o = dp.thinOffs
    wallLen = (dp.gridSize * 0.25).int
    doorWidthOffs = -o # (if dp.zoomLevel < 4 or ls.thinLines: -1.0 else: 0)
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
  vg.strokeColor(ls.drawColor)
  vg.fillColor(ls.drawColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1+1, sw), snap(y, sw))
  vg.stroke()

  # Door
  sw = dp.thinStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  if fill:
    if dp.lineWidth == lwThin:
      vg.rect(x1+1, y1-o, x2-x1, y2-y1+2+o)
    else:
      vg.rect(snap(x1, sw), snap(y1-o-1, sw), x2-x1+1, y2-y1+3+o)
    vg.fill()
  else:
    vg.rect(snap(x1+1, sw), snap(y1-o, sw), x2-x1-1, y2-y1+1+o)
    vg.stroke()

  # Wall end
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
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
  alias(ls, ctx.ls)
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
  vg.strokeColor(ls.drawColor)

  # Wall start
  vg.lineCap(lcjSquare)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  drawIcon(x, y-dp.gridSize*0.5, 0.02, -0.02, "S", dp.gridSize, ls.drawColor,
           fontSizeFactor=0.43, ctx.vg)

  # Wall end
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawArchwayHoriz*()
proc drawArchwayHoriz*(x, y: float, ctx) =
  alias(ls, ctx.ls)
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
  vg.strokeColor(ls.drawColor)

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
# {{{ drawLeverHoriz*()
proc drawLeverHoriz*(x, y: float, northEast: bool, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    sw = dp.normalStrokeWidth
    xs = snap(x, sw)
    xe = snap(x + dp.gridSize, sw)
    y = snap(y, sw)

  # Draw wall
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ls.drawColor)
  vg.strokeWidth(sw)
  vg.moveTo(xs, y)
  vg.lineTo(xe, y)
  vg.stroke()

  # Draw lever
  let lw = floor(dp.gridSize*0.2)
  var lx, ly: float

  if dp.lineWidth == lwThin:
    lx = floor(x + (dp.gridSize-lw)*0.5 + 0.5)
    ly = if northEast: y-0.5 else: y-lw+0.5
  else:
    lx = snap(x + (dp.gridSize-lw)*0.5 + 0.5, sw)
    ly = if northEast: y else: y-lw

  vg.fillColor(ls.drawColor)
  vg.beginPath()
  vg.rect(lx, ly, lw, lw)
  vg.fill()


proc drawLeverHorizNE*(x, y: float, ctx) =
  drawLeverHoriz(x, y, northEast=true, ctx)

proc drawLeverHorizSW*(x, y: float, ctx) =
  drawLeverHoriz(x, y, northEast=false, ctx)

# }}}
# {{{ drawNicheHoriz*()
proc drawNicheHoriz*(x, y: float, northEast: bool, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    wallLenOffs = (if dp.zoomLevel < 2: -1.0 else: 0)
    wallLen = (dp.gridSize * 0.25).int + wallLenOffs
    nicheDepth = round(dp.gridSize * 0.15)
    xs = x
    y  = y
    x1 = xs + wallLen + dp.thinOffs
    xe = xs + dp.gridSize
    x2 = xe - wallLen - dp.thinOffs
    yn = if northEast: y-nicheDepth else: y+nicheDepth

  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ls.drawColor)

  vg.fillColor(ls.floorColor)
  vg.beginPath()
  vg.rect(x1, y, x2-x1, yn-y)
  vg.fill()

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(yn, sw))
  vg.lineTo(snap(x2, sw), snap(yn, sw))
  vg.lineTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()


proc drawNicheHorizNE*(x, y: float, ctx) =
  drawNicheHoriz(x, y, northEast=true, ctx)

proc drawNicheHorizSW*(x, y: float, ctx) =
  drawNicheHoriz(x, y, northEast=false, ctx)

# }}}
# {{{ drawStatueHoriz*()
proc drawStatueHoriz*(x, y: float, northEast: bool, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ls.drawColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x, sw), snap(y, sw))
  vg.lineTo(snap(x + dp.gridSize, sw), snap(y, sw))
  vg.stroke()

  # Arc
  const da = 1.3
  let
    cx = x + dp.gridSize*0.5
    dy = dp.gridSize*0.07
    cy = if northEast: y-dy else: y+dy
    ca = if northEast: PI*0.5 else: 3*PI*0.5
    a1 = ca-da
    a2 = ca+da

  vg.fillColor(ls.drawColor)
  vg.beginPath()
  vg.arc(cx, cy, dp.gridSize*0.27, a1, a2, pwCW)
  vg.fill()


proc drawStatueHorizNE*(x, y: float, ctx) =
  drawStatueHoriz(x, y, northEast=true, ctx)

proc drawStatueHorizSW*(x, y: float, ctx) =
  drawStatueHoriz(x, y, northEast=false, ctx)

# }}}
# {{{ drawKeyholeHoriz*()
proc drawKeyholeHoriz*(x, y: float, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    boxLen = (dp.gridSize * 0.25).int
    xs = x
    x1 = xs + (dp.gridSize - boxLen)*0.5
    x2 = x1 + boxLen
    xe = x + dp.gridSize

  var sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ls.drawColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1+1, sw), snap(y, sw))
  vg.stroke()

  # Keyhole border
  sw = dp.thinStrokeWidth
  let
    kx = snap(x1, sw)
    ky = snap(y-boxLen*0.5, sw)
    kl = boxLen.float

  vg.strokeWidth(sw)
  vg.fillColor(ls.floorColor)
  vg.beginPath()
  vg.rect(kx, ky, kl, kl)
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
    vg.fillColor(ls.drawColor)
    vg.beginPath()
    vg.rect(kx+i, ky+i, h, h)
    vg.fill()

  # Wall end
  sw = dp.normalStrokeWidth
  vg.strokeWidth(sw)
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
proc drawCellFloor(viewBuf: Level, viewRow, viewCol: Natural, ctx) =
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let
    bufRow = viewRow+1
    bufCol = viewCol+1
    x = cellX(viewCol, dp)
    y = cellY(viewRow, dp)

  template drawOriented(drawProc: untyped) =
    vg.save()

    vg.intersectScissor(x, y, dp.gridSize+1, dp.gridSize+1)

    case viewBuf.getFloorOrientation(bufRow, bufCol):
    of Horiz:
      drawProc(x, y + floor(dp.gridSize*0.5), ctx)
    of Vert:
      setVertTransform(x + floor(dp.gridSize*0.5), y, ctx)
      drawProc(0, 0, ctx)
      vg.resetTransform()

    vg.restore()

  template draw(drawProc: untyped) =
    drawProc(x, y, ctx)

  case viewBuf.getFloor(bufRow, bufCol)
  of fNone:                discard
  of fEmpty:               discard
  of fTrail:               draw(drawTrail)
  of fDoor:                drawOriented(drawDoorHoriz)
  of fLockedDoor:          drawOriented(drawLockedDoorHoriz)
  of fArchway:             drawOriented(drawArchwayHoriz)

  of fSecretDoor:          drawSecretDoor(x, y,
                                          isCursorActive(viewRow, viewCol, dp),
                                          ctx)

  of fPressurePlate:       draw(drawPressurePlate)
  of fHiddenPressurePlate: draw(drawHiddenPressurePlate)
  of fClosedPit:           draw(drawClosedPit)
  of fOpenPit:             draw(drawOpenPit)
  of fHiddenPit:           draw(drawHiddenPit)
  of fCeilingPit:          draw(drawCeilingPit)
  of fStairsDown:          draw(drawStairsDown)
  of fStairsUp:            draw(drawStairsUp)
  of fExitDoor:            draw(drawExitDoor)
  of fSpinner:             draw(drawSpinner)
  of fTeleportSource:      draw(drawTeleportSource)
  of fTeleportDestination: draw(drawTeleportDestination)

# }}}
# {{{ drawBackgroundGrid()
proc drawBackgroundGrid(viewBuf: Level, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let
        bufRow = viewRow+1
        bufCol = viewCol+1

      if viewBuf.isFloorEmpty(bufRow, bufCol):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)
        drawGrid(x, y, ls.gridColorBackground, ls.gridStyleBackground, ctx)

# }}}
# {{{ drawCellBackgroundsAndGrid()
proc drawCellBackgroundsAndGrid(viewBuf: Level, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)

  for viewRow in 0..<dp.viewRows:
    for viewCol in 0..<dp.viewCols:
      let
        bufRow = viewRow+1
        bufCol = viewCol+1

      if not viewBuf.isFloorEmpty(bufRow, bufCol):
        let x = cellX(viewCol, dp)
        let y = cellY(viewRow, dp)
        drawFloorBg(x, y, ls.floorColor, ctx)
        drawGrid(x, y, ls.gridColorFloor, ls.gridStyleFloor, ctx)

# }}}
# {{{ drawFloors()
proc drawFloors(viewBuf: Level, ctx) =
  alias(dp, ctx.dp)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      drawCellFloor(viewBuf, r,c, ctx)

# }}}
# {{{ drawNote()
proc drawNote(x, y: float, note: Note, ctx) =
  alias(ls, ctx.ls)
  alias(dp, ctx.dp)
  alias(vg, ctx.vg)

  let w = dp.gridSize*0.3

  case note.kind
  of nkComment:  discard
  of nkIndexed:  drawIndexedNote(x, y, note.index, note.indexColor, ctx)
  of nkCustomId: drawCustomIdNote(x, y, note.customId, ctx)

  of nkIcon:     drawIcon(x, y, 0, 0, NoteIcons[note.icon],
                          dp.gridSize, ls.noteLevelMarkerColor,
                          DefaultIconFontSizeFactor, vg)

  if note.kind != nkIndexed and note.text != "":
    vg.fillColor(ls.noteLevelCommentColor)
    vg.beginPath()
    vg.moveTo(x + dp.gridSize - w, y)
    vg.lineTo(x + dp.gridSize + 1, y + w+1)
    vg.lineTo(x + dp.gridSize + 1, y)
    vg.closePath()
    vg.fill()

  # }}}
# {{{ drawNotes()
proc drawNotes(viewBuf: Level, ctx) =
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
  of wLeverNE:       drawOriented(drawLeverHorizNE)
  of wLeverSW:       drawOriented(drawLeverHorizSW)
  of wNicheNE:       drawOriented(drawNicheHorizNE)
  of wNicheSW:       drawOriented(drawNicheHorizSW)
  of wStatueNE:      drawOriented(drawStatueHorizNE)
  of wStatueSW:      drawOriented(drawStatueHorizSW)
  of wKeyhole:       drawOriented(drawKeyholeHoriz)

# }}}
# {{{ drawCellWalls()
proc drawCellWalls(viewBuf: Level, viewRow, viewCol: Natural, ctx) =
  alias(dp, ctx.dp)

  let bufRow = viewRow+1
  let bufCol = viewCol+1

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
proc drawWalls(viewBuf: Level, ctx) =
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
# {{{ drawInnerShadows()
proc drawInnerShadows(viewBuf: Level, ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  vg.fillColor(ls.innerShadowColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ls.innerShadowWidthFactor

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
proc drawOuterShadows(viewBuf: Level, ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)
  alias(vg, ctx.vg)

  vg.fillColor(ls.outerShadowColor)
  vg.beginPath()

  let shadowWidth = dp.gridSize * ls.outerShadowWidthFactor

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

# {{{ mergeSelectionAndOutlineBuffers()
proc mergeSelectionAndOutlineBuffers(viewBuf: Level,
                                     outlineBuf: Option[OutlineBuf], dp) =
  if dp.selectionBuffer.isSome:
    let startRow = dp.selStartRow - dp.viewStartRow + 1
    let startCol = dp.selStartCol - dp.viewStartCol + 1
    let copyBuf = dp.selectionBuffer.get.level

    viewBuf.paste(startRow, startCol,
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
proc drawLevel*(l: Level, ctx) =
  alias(dp, ctx.dp)
  alias(ls, ctx.ls)

  assert dp.viewStartRow + dp.viewRows <= l.rows
  assert dp.viewStartCol + dp.viewCols <= l.cols

  if ls.bgHatchEnabled:
    drawBackgroundHatch(ctx)
  else:
    drawBackground(ctx)

  let viewBuf = newLevelFrom(l,
    rectN(
      dp.viewStartRow,
      dp.viewStartCol,
      dp.viewStartRow + dp.viewRows,
      dp.viewStartCol + dp.viewCols
    ),
    border=1
  )

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

  if dp.selectionBuffer.isNone:
    drawCursor(ctx)

  drawFloors(viewBuf, ctx)
  drawNotes(viewBuf, ctx)

  # TODO finish shadow implementation (draw corners)
  if ls.innerShadowEnabled:
    drawInnerShadows(viewBuf, ctx)

  if ls.outerShadowEnabled:
    drawOuterShadows(viewBuf, ctx)

  drawWalls(viewBuf, ctx)

  if dp.selection.isSome:
    drawSelection(ctx)

  if dp.selectionBuffer.isSome:
    drawSelectionHighlight(ctx)

  if dp.drawCursorGuides:
    drawCursorGuides(ctx)

  if dp.drawCellCoords:
    drawCellCoords(l, ctx)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
