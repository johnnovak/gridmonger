import lenientops
import math
import options

import koi
import nanovg

import common
import map
import selection


const
  MinZoomLevel* = 1
  MaxZoomLevel* = 10

  UltrathinStrokeWidth = 1.0
  ThinStrokeWidth      = 2.0
  NormalStrokeWidth    = 3.0

  VertTransformYFudgeFactor = -1.0



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

  # TODO use better names
  MapStyle* = ref object
    cellCoordsColor*:     Color
    cellCoordsColorHi*:   Color
    cursorColor*:         Color
    cursorGuideColor*:    Color
    defaultFgColor*:      Color
    groundColor*:         Color
    gridColorBackground*: Color
    gridColorGround*:     Color
    mapBackgroundColor*:  Color
    mapOutlineColor*:     Color
    pastePreviewColor*:   Color
    selectionColor*:      Color

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

    drawOutline*:      bool
    drawCursorGuides*: bool

    # internal
    zoomLevel:          Natural
    gridSize:           float
    cellCoordsFontSize: float

    vertTransformYFudgeFactor: float

# }}}

using
  dp:  DrawMapParams
  ctx: DrawMapContext

# {{{ zoomLevel*()
proc getZoomLevel*(dp): Natural = dp.zoomLevel

# }}}
# {{{ setZoomLevel*()
proc setZoomLevel*(dp; zl: Natural) =
  assert zl >= MinZoomLevel
  assert zl <= MaxZoomLevel
  let
    MinGridSize = 19.44
    ZoomFactor = 1.08

  dp.zoomLevel = zl
  dp.gridSize = floor(MinGridSize * pow(ZoomFactor, zl.float))

  dp.cellCoordsFontSize = if   zl <= 3: 11.0
                          elif zl <= 7: 12.0
                          else:         13.0

# }}}
# {{{ incZoomLevel*()
proc incZoomLevel*(dp) =
  if dp.zoomLevel < MaxZoomLevel:
    setZoomLevel(dp, dp.zoomLevel+1)

# }}}
# {{{ decZoomLevel*()
proc decZoomLevel*(dp) =
  if dp.zoomLevel > MinZoomLevel:
    setZoomLevel(dp, dp.zoomLevel-1)

# }}}
# {{{ numDisplayableRows*()
proc numDisplayableRows*(dp; height: float): Natural =
  max(height / dp.gridSize, 0).int

# }}}
# {{{ numDisplayableCols*()
proc numDisplayableCols*(dp; width: float): Natural =
  max(width / dp.gridSize, 0).int

# }}}

# {{{ utils

# This is needed for drawing crisp lines
func snap(f: float, strokeWidth: float): float =
  let (i, _) = splitDecimal(f)
  let (_, offs) = splitDecimal(strokeWidth/2)
  result = i + offs

proc cellX(x: Natural, dp): float =
  dp.startX + dp.gridSize * x

proc cellY(y: Natural, dp): float =
  dp.startY + dp.gridSize * y

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
proc drawCellCoords(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fontFace("sans")
  vg.fontSize(dp.cellCoordsFontSize)
  vg.textAlign(haCenter, vaMiddle)

  proc setTextHighlight(on: bool) =
    if on:
      vg.fillColor(ms.cellCoordsColorHi)
    else:
      vg.fillColor(ms.cellCoordsColor)
      vg.fontFace("sans")

  let endX = dp.startX + dp.gridSize * dp.viewCols
  let endY = dp.startY + dp.gridSize * dp.viewRows

  let fontSize = dp.cellCoordsFontSize

  for x in 0..<dp.viewCols:
    let
      xPos = cellX(x, dp) + dp.gridSize/2
      coord = $(dp.viewStartCol + x)

    setTextHighlight(x == dp.cursorCol)

    discard vg.text(xPos, dp.startY - fontSize, coord)
    discard vg.text(xPos, endY + fontSize*1.25, coord)

  for y in 0..<dp.viewRows:
    let
      yPos = cellY(y, dp) + dp.gridSize/2
      coord = $(dp.viewStartRow + y)

    setTextHighlight(y == dp.cursorRow)

    discard vg.text(dp.startX - fontSize*1.2, yPos, coord)
    discard vg.text(endX + fontSize*1.2, yPos, coord)


# }}}
# {{{ drawMapBackground()
proc drawMapBackground(ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let strokeWidth = UltrathinStrokeWidth

  vg.strokeColor(ms.mapBackgroundColor)
  vg.strokeWidth(strokeWidth)

  let
    w = dp.gridSize * dp.viewCols
    h = dp.gridSize * dp.viewRows
    offs = max(w, h)
    lineSpacing = strokeWidth * 2

  let startX = snap(dp.startX, strokeWidth)
  let startY = snap(dp.startY, strokeWidth)

  vg.scissor(startX, startY, w, h)

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
# {{{ drawCursor()
proc drawCursor(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  vg.fillColor(ms.cursorColor)
  vg.beginPath()
  vg.rect(x+1, y+1, dp.gridSize-1, dp.gridSize-1)
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
# {{{ drawOutline()
proc drawOutline(m: Map, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  func check(col, row: int): bool =
    let c = max(min(col, m.cols-1), 0)
    let r = max(min(row, m.rows-1), 0)
    m.getGround(c, r) != gNone

  func isOutline(c, r: Natural): bool =
    check(c,   r+1) or
    check(c+1, r+1) or
    check(c+1, r  ) or
    check(c+1, r-1) or
    check(c  , r-1) or
    check(c-1, r-1) or
    check(c-1, r  ) or
    check(c-1, r+1)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      if isOutline(dp.viewStartCol+c, dp.viewStartRow+r):
        let
          sw = UltrathinStrokeWidth
          x = snap(cellX(c, dp), sw)
          y = snap(cellY(r, dp), sw)

        vg.strokeWidth(sw)
        vg.fillColor(ms.mapOutlineColor)
        vg.strokeColor(ms.mapOutlineColor)

        vg.beginPath()
        vg.rect(x, y, dp.gridSize, dp.gridSize)
        vg.fill()
        vg.stroke()

# }}}

# {{{ drawGround()
proc drawGround(x, y: float, color: Color, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let sw = UltrathinStrokeWidth

  vg.beginPath()
  vg.fillColor(color)
  vg.strokeColor(ms.gridColorGround)
  vg.strokeWidth(sw)
  vg.rect(snap(x, sw), snap(y, sw), dp.gridSize, dp.gridSize)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawPressurePlate()
proc drawPressurePlate(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    offs = (dp.gridSize * 0.3).int
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(ms.defaultFgColor)
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
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjRound)
  vg.strokeColor(gray(0.5))
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
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(ms.defaultFgColor)
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
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)
  vg.fillColor(ms.defaultFgColor)

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
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeColor(gray(0.5))
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
    a = dp.gridSize - 2*offs + 1
    sw = ThinStrokeWidth

  vg.lineCap(lcjSquare)
  vg.strokeWidth(sw)
  vg.strokeColor(gray(0.5))
  vg.fillColor(gray(0.5))

  let
    x1 = snap(x + offs, sw)
    y1 = snap(y + offs, sw)

  vg.beginPath()
  vg.rect(x1, y1, a, a)
  vg.fill()
  vg.stroke()

# }}}
# {{{ drawIcon()
proc drawIcon(x, y, ox, oy: float, icon: string, ctx) =
  let vg = ctx.vg
  let dp = ctx.dp
  let (bounds, tx) = vg.textBounds(x, y, icon)

  vg.setFont((dp.gridSize*0.6).float)
  vg.fillColor(gray(0))
  vg.textAlign(haCenter, vaMiddle)
  discard vg.text(x + dp.gridSize*ox + dp.gridSize*0.51,
                  y + dp.gridSize*oy + dp.gridSize*0.58, icon)

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

# {{{ drawSolidWallHoriz()
proc drawSolidWallHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = NormalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(ms.defaultFgColor)
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawIllusoryWallHoriz()
proc drawIllusoryWallHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = NormalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(rgb(1.0, 0.5, 0.5))
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawInvisibleWallHoriz()
proc drawInvisibleWallHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    sw = NormalStrokeWidth
    x = snap(x, sw)
    y = snap(y, sw)

  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.strokeColor(rgb(0.3, 1.0, 0.3))
  vg.strokeWidth(sw)
  vg.moveTo(x, y)
  vg.lineTo(x + dp.gridSize, y)
  vg.stroke()

# }}}
# {{{ drawOpenDoorHoriz()
proc drawOpenDoorHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    wallLen = (dp.gridSize * 0.3).int
    doorWidth = round(dp.gridSize * 0.1)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)

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
  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawClosedDoorHoriz()
proc drawClosedDoorHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    wallLen = (dp.gridSize * 0.25).int
    doorWidth = round(dp.gridSize * 0.1)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(ms.defaultFgColor)

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door
  vg.lineCap(lcjSquare)
  sw = ThinStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.rect(snap(x1, sw) + 1, snap(y1, sw), x2-x1-1, y2-y1+1)
  vg.stroke()

  # Wall end
  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(x2+1, sw), snap(y, sw))
  vg.lineTo(snap(xe, sw), snap(y, sw))
  vg.stroke()

# }}}
# {{{ drawSecretDoorHoriz()
proc drawSecretDoorHoriz(x, y: float, ctx) =
  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let
    wallLen = (dp.gridSize * 0.25).int
    doorWidth = round(dp.gridSize * 0.1)
    xs = x
    y  = y
    x1 = xs + wallLen
    xe = xs + dp.gridSize
    x2 = xe - wallLen
    y1 = y - doorWidth
    y2 = y + doorWidth

  var sw = NormalStrokeWidth
  vg.strokeWidth(sw)
  vg.strokeColor(rgb(1.0, 0, 0.5))

  # Wall start
  vg.lineCap(lcjRound)
  vg.beginPath()
  vg.moveTo(snap(xs, sw), snap(y, sw))
  vg.lineTo(snap(x1, sw), snap(y, sw))
  vg.stroke()

  # Door
  vg.lineCap(lcjSquare)
  sw = ThinStrokeWidth
  vg.strokeWidth(sw)
  vg.beginPath()
  vg.rect(snap(x1, sw) + 1, snap(y1, sw), x2-x1-1, y2-y1+1)
  vg.stroke()

  # Wall end
  sw = NormalStrokeWidth
  vg.strokeWidth(sw)
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

  vg.translate(x, y)
  vg.rotate(degToRad(90.0))

  # We need to use some fudge factor here because of the grid snapping...
  vg.translate(0, dp.vertTransformYFudgeFactor)

# }}}
# {{{ drawGround()
proc drawGround(viewBuf: Map, viewCol, viewRow: Natural,
                cursorActive: bool, ctx) =

  let ms = ctx.ms
  let dp = ctx.dp
  let vg = ctx.vg

  let x = cellX(viewCol, dp)
  let y = cellY(viewRow, dp)

  template drawOriented(drawProc: untyped) =
    drawBg()
    case viewBuf.getGroundOrientation(viewCol, viewRow):
    of Horiz:
      drawProc(x, y + floor(dp.gridSize/2), ctx)
    of Vert:
      setVertTransform(x + floor(dp.gridSize/2), y, ctx)
      drawProc(0, 0, ctx)
      vg.resetTransform()

  template draw(drawProc: untyped) =
    drawBg()
    drawProc(x, y, ctx)

  proc drawBg() =
    drawGround(x, y, ms.groundColor, ctx)
    if cursorActive:
      drawCursor(x, y, ctx)

  case viewBuf.getGround(viewCol, viewRow)
  of gNone:
    if cursorActive:
      drawCursor(x, y, ctx)

  of gEmpty:               drawBg()
  of gClosedDoor:          drawOriented(drawClosedDoorHoriz)
  of gOpenDoor:            drawOriented(drawOpenDoorHoriz)
  of gPressurePlate:       draw(drawPressurePlate)
  of gHiddenPressurePlate: draw(drawHiddenPressurePlate)
  of gClosedPit:           draw(drawClosedPit)
  of gOpenPit:             draw(drawOpenPit)
  of gHiddenPit:           draw(drawHiddenPit)
  of gCeilingPit:          draw(drawCeilingPit)
  of gStairsDown:          draw(drawStairsDown)
  of gStairsUp:            draw(drawStairsUp)
  of gSpinner:             draw(drawSpinner)
  of gTeleport:            draw(drawTeleport)
  of gCustom:              draw(drawCustom)

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
  of wOpenDoor:      drawOriented(drawOpenDoorHoriz)
  of wClosedDoor:    drawOriented(drawClosedDoorHoriz)
  of wSecretDoor:    drawOriented(drawSecretDoorHoriz)
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

# }}}
# {{{ drawWalls()
proc drawWalls(viewBuf: Map, viewCol, viewRow: Natural, ctx) =
  let dp = ctx.dp

  let groundEmpty = viewBuf.getGround(viewCol, viewRow) == gNone

  if viewRow > 0 or (viewRow == 0 and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, North), Horiz, ctx
    )

  if viewCol > 0 or (viewCol == 0 and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, West), Vert, ctx
    )

  let viewEndCol = dp.viewCols-1
  if viewCol < viewEndCol or (viewCol == viewEndCol and not groundEmpty):
    drawWall(
      cellX(viewCol+1, dp),
      cellY(viewRow, dp),
      viewBuf.getWall(viewCol, viewRow, East), Vert, ctx
    )

  let viewEndRow = dp.viewRows-1
  if viewRow < viewEndRow or (viewRow == viewEndRow and not groundEmpty):
    drawWall(
      cellX(viewCol, dp),
      cellY(viewRow+1, dp),
      viewBuf.getWall(viewCol, viewRow, South), Horiz, ctx
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

  assert dp.viewStartCol + dp.viewCols <= m.cols
  assert dp.viewStartRow + dp.viewRows <= m.rows

  drawCellCoords(ctx)
  drawMapBackground(ctx)
  drawBackgroundGrid(ctx)

  let viewBuf = newMapFrom(m,
    rectN(
      dp.viewStartCol,
      dp.viewStartRow,
      dp.viewStartCol + dp.viewCols,
      dp.viewStartRow + dp.viewRows
    )
  )

  if dp.drawOutline:
    drawOutline(m, ctx)

  if dp.pastePreview.isSome:
    viewBuf.paste(dp.cursorCol - dp.viewStartCol,
                  dp.cursorRow - dp.viewStartRow,
                  dp.pastePreview.get.map,
                  dp.pastePreview.get.selection)

  for r in 0..<dp.viewRows:
    for c in 0..<dp.viewCols:
      let cursorActive = dp.viewStartCol+c == dp.cursorCol and
                         dp.viewStartRow+r == dp.cursorRow
      drawGround(viewBuf, c, r, cursorActive, ctx)

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
