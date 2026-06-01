# toolspane
#
# The right-side tools pane: special-wall picker + floor-color picker.
# Includes specialWallDrawProc, the custom radio-button draw proc that
# renders mini wall previews in the picker buttons.
# Side effects: koi + nanovg drawing.

import std/options
import std/sugar           # `collect:` macro

import koi
import nanovg

import common
import main/appcontext
import main/constants       # SpecialWallTooltips, ToolsPaneYBreakpoint1/2
import main/dialogs/common  # colorRadioButtonDrawProc
import main/view            # mainPaneRect
import ui/all
import utils/all


using a: var AppContext

# {{{ specialWallDrawProc()
proc specialWallDrawProc*(lt: LevelTheme,
                         tt: ToolbarPaneTheme,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext,
               id: ItemId, x, y, w, h: float,
               buttonIdx, numButtons: Natural, label: string,
               state: WidgetState, style: RadioButtonsStyle) =

    var (bgCol, active) = case state
                          of wsHover:
                            (tt.buttonHoverColor,  false)
                          of wsDown, wsActive, wsActiveHover, wsActiveDown:
                            (lt.cursorColor,       true)
                          else:
                            (tt.buttonNormalColor, false)

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let
      savedFloorColor = lt.floorBackgroundColor[0]
      savedForegroundNormalNormalColor = lt.foregroundNormalNormalColor
      savedForegroundLightNormalColor  = lt.foregroundLightNormalColor
      savedBackgroundImage = dp.backgroundImage

    lt.floorBackgroundColor[0] = lerp(lt.backgroundColor, bgCol, bgCol.a)
                                 .withAlpha(1.0)
    if active:
      lt.foregroundNormalNormalColor = lt.foregroundNormalCursorColor
      lt.foregroundLightNormalColor  = lt.foregroundLightCursorColor

    dp.backgroundImage = Paint.none

    const Pad = 5

    vg.beginPath
    vg.fillColor(bgCol)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill

    dp.setZoomLevel(lt, 4)
    let ctx = DrawLevelContext(lt: lt, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel(zl: Natural, body: untyped) =
      vg.save
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(lt, zl)
      vg.intersectScissor(x+4.5, y+3, w-Pad*2-4, h-Pad*2-2)
      body
      dp.setZoomLevel(lt, 4)
      vg.restore

    let ot = Horiz

    case SpecialWalls[buttonIdx]
    of wNone:              discard
    of wWall:              drawSolidWallHoriz(cx, cy, ot, ctx=ctx)
    of wIllusoryWall:      drawIllusoryWallHoriz(cx+2, cy, ot, ctx=ctx)
    of wInvisibleWall:     drawInvisibleWallHoriz(cx-2, cy, ot, ctx=ctx)
    of wDoor:              drawDoorHoriz(cx, cy, ot, ctx=ctx)
    of wLockedDoor:        drawLockedDoorHoriz(cx, cy, ot, ctx=ctx)
    of wArchway:           drawArchwayHoriz(cx, cy, ot, ctx=ctx)

    of wSecretDoor:
      drawAtZoomLevel(6):  drawSecretDoorHoriz(cx-2, cy, ot, ctx=ctx)

    of wOneWayDoorNE:
      drawAtZoomLevel(8):  drawOneWayDoorHorizNE(cx-4, cy+1, ot, ctx=ctx)

    of wLeverSW:
      drawAtZoomLevel(6):  drawLeverHorizSW(cx-2, cy+1, ot, ctx=ctx)

    of wNicheSW:           drawNicheHorizSW(cx, cy, ot, floorColor=0, ctx=ctx)

    of wStatueSW:
      drawAtZoomLevel(6):  drawStatueHorizSW(cx-2, cy+2, ot, ctx=ctx)

    of wKeyhole:
      drawAtZoomLevel(6):  drawKeyholeHoriz(cx-2, cy, ot, ctx=ctx)

    of wWritingSW:
      drawAtZoomLevel(12): drawWritingHorizSW(cx-6, cy+4, ot, ctx=ctx)

    else: discard

    # ...aaaaand restore it!
    lt.floorBackgroundColor[0] = savedFloorColor
    lt.foregroundNormalNormalColor = savedForegroundNormalNormalColor
    lt.foregroundLightNormalColor = savedForegroundLightNormalColor
    dp.backgroundImage = savedBackgroundImage

# }}}
# {{{ renderToolsPane()
proc renderToolsPane*(x, y, w, h: float; a) =
  alias(ui, a.ui)
  alias(lt, a.theme.levelTheme)
  alias(vg, a.vg)

  var
    toolItemsPerColumn = 12
    toolX = x

    colorItemsPerColum = 10
    colorX = x + 3
    colorY = y + 445

  let mainPane = mainPaneRect(a)

  if mainPane.h < ToolsPaneYBreakpoint2:
    colorItemsPerColum = 5
    toolX += 30

  if mainPane.h < ToolsPaneYBreakpoint1:
    toolItemsPerColumn = 6
    toolX -= 30
    colorX += 3
    colorY -= 210

  # Special walls
  koi.radioButtons(
    x = toolX,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = SpecialWallTooltips,
    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: toolItemsPerColumn),

    drawProc = specialWallDrawProc(
      a.theme.levelTheme, a.theme.toolbarPaneTheme, ui.toolbarDrawParams
    ).some
  )

  # Floor colours
  var floorColors = collect:
    for fc in 0..lt.floorBackgroundColor.high:
      calcBlendedFloorColor(fc, lt.floorTransparent, lt)

  koi.radioButtons(
    x = colorX,
    y = colorY,
    w = 30,
    h = 30,
    labels = newSeq[string](lt.floorBackgroundColor.len),
    ui.currFloorColor,
    tooltips = @[],

    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: colorItemsPerColum),

    drawProc = colorRadioButtonDrawProc(floorColors, lt.cursorColor).some
  )

# }}}

# vim: et:ts=2:sw=2:fdm=marker
