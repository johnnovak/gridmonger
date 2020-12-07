import lenientops

import glfw
import icons
import koi
import nanovg
import with

import common
import utils
import theme


const
  TitleBarFontSize = 14.0
  TitleBarHeight* = 26.0    # TODO
  TitleBarTitlePosX = 50.0
  TitleBarButtonWidth = 23.0
  TitleBarPinButtonsLeftPad = 4.0
  TitleBarPinButtonTotalWidth = TitleBarPinButtonsLeftPad + TitleBarButtonWidth
  TitleBarWindowButtonsRightPad = 6.0
  TitleBarWindowButtonsTotalWidth = TitleBarButtonWidth*3 +
                                    TitleBarWindowButtonsRightPad

  WindowResizeEdgeWidth = 7.0
  WindowResizeCornerSize = 20.0

#  {{{ CSDWindow
type
  CSDWindow* = ref object
    modified*: bool
    style*:    WindowStyle

    w*: Window  # the wrapper GLFW window

    buttonStyle:         ButtonStyle
    title:               string
    maximized:           bool
    maximizing:          bool
    dragState:           WindowDragState
    resizeDir:           WindowResizeDir
    mx0, my0:            float
    posX0, posY0:        int
    width0, height0:     int32
    oldPosX, oldPosY:    int
    oldWidth, oldHeight: int32

    oldFocusCaptured, focusCaptured: bool


  WindowDragState = enum
    wdsNone, wdsMoving, wdsResizing

  WindowResizeDir = enum
    wrdNone, wrdN, wrdNW, wrdW, wrdSW, wrdS, wrdSE, wrdE, wrdNE


using win: CSDWindow

# }}}

# {{{ Default style
# TODO will be removed
var DefaultCSDWindowStyle = new WindowStyle

with DefaultCSDWindowStyle:
  backgroundColor    = gray(0.2)
  bgColorUnfocused   = gray(0.1)
  textColor          = gray(1.0, 0.7)
  textColorUnfocused = gray(1.0, 0.4)
  buttonColor        = gray(1.0, 0.45)
  buttonColorHover   = gray(1.0, 0.7)
  buttonColorDown    = gray(1.0, 0.9)
  modifiedFlagColor  = gray(1.0, 0.45)

proc getDefaultCSDWindowStyle*(): WindowStyle = DefaultCSDWindowStyle.deepCopy()

# }}}
# # {{{ setStyle()
proc setStyle*(win; s: WindowStyle) = 
  win.style = s

  alias(bs, win.buttonStyle)
  bs = koi.getDefaultButtonStyle()

  bs.labelOnly        = true
  bs.label.padHoriz   = 0
  bs.label.color      = s.buttonColor
  bs.label.colorHover = s.buttonColorHover
  bs.label.colorDown  = s.buttonColorDown

# }}}
# {{{ newCSDWindow*()
proc newCSDWindow*(): CSDWindow =
  result = new CSDWindow

  var cfg = DefaultOpenglWindowConfig
  cfg.resizable = false
  cfg.visible = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = false  # TODO
  cfg.nMultiSamples = 4
  cfg.decorated = false

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  result.w = newWindow(cfg)
  result.setStyle(DefaultCSDWindowStyle)

# }}}
# {{{ GLFW Window adapters
# Just for the functions that actually get used in the app

proc title*(win): string =
  win.title

proc `title=`*(win; title: string) =
  if win.title != title:
    win.title = title
    win.w.title = title

proc pos*(win): tuple[x, y: int32] =
  win.w.pos

proc `pos=`*(win; pos: tuple[x, y: int32]) =
  win.w.pos = pos

proc size*(win): tuple[w, h: int32] =
  win.w.size

proc `size=`*(win; size: tuple[w, h: int32]) =
  win.w.size = size

proc framebufferSize*(win): tuple[w, h: int32] =
  win.w.framebufferSize

proc show*(win) =
  win.w.show()

proc shouldClose*(win): bool =
  win.w.shouldClose

proc `shouldClose=`*(win; state: bool) =
  win.w.shouldClose = state

proc maximized*(win): bool =
  win.maximized

# }}}

# {{{ oldPos*()
proc oldPos*(win): tuple[x, y: int32] =
  (win.oldPosX, win.oldPosY)

# }}}
# {{{ oldSize*()
proc oldSize*(win): tuple[w, h: int32] =
  (win.oldWidth, win.oldHeight)

# }}}

# {{{ restore()
proc restore(win) =
  win.w.pos = (win.oldPosX, win.oldPosY)
  win.w.size = (win.oldWidth, win.oldHeight)
  win.maximized = false

# }}}
# {{{ maximize*()
proc maximize*(win) =
  # TODO This logic needs to be a bit more sophisticated to support
  # multiple monitors
  let (_, _, w, h) = getPrimaryMonitor().workArea
  (win.oldPosX, win.oldPosY) = win.w.pos
  (win.oldWidth, win.oldHeight) = win.w.size

  win.maximized = true
  win.maximizing = true

  win.w.pos = (0, 0)
  win.w.size = (w, h)

  win.maximizing = false

# }}}
# {{{ renderTitleBar()
proc renderTitleBar(win; vg: NVGContext, winWidth: float) =
  alias(s, win.style)

  let (bgColor, textColor) = if win.w.focused:
    (s.backgroundColor, s.textColor)
  else:
    (s.bgColorUnfocused, s.textColorUnfocused)

  let
    bw = TitleBarButtonWidth
    bh = TitleBarFontSize + 4
    by = (TitleBarHeight - bh) / 2
    ty = TitleBarHeight * TextVertAlignFactor

  koi.addDrawLayer(layerWindowDecoration, vg):
    vg.beginPath()
    vg.rect(0, 0, winWidth.float, TitleBarHeight)
    vg.fillColor(bgColor)
    vg.fill()

    vg.setFont(TitleBarFontSize)
    vg.fillColor(textColor)
    vg.textAlign(haLeft, vaMiddle)

    # Window title & modified flag
    let tx = vg.text(TitleBarTitlePosX, ty, win.title)

    if win.modified:
      vg.fillColor(s.modifiedFlagColor)
      discard vg.text(tx+10, ty, IconAsterisk)


  alias(bs, win.buttonStyle)

  # TODO hacky, shouldn't set the current layer from the outside
  let oldCurrLayer = koi.currentLayer()
  koi.setCurrentLayer(layerWindowDecoration)

  # Pin window button
  if koi.button(TitleBarPinButtonsLeftPad, by, bw, bh, IconPin, style=bs):
    # TODO
    discard

  # Minimise/maximise/close window buttons
  let x = winWidth - TitleBarWindowButtonsTotalWidth

  if koi.button(x, by, bw, bh, IconWindowMinimise, style=bs):
    win.w.iconify()

  if koi.button(x + bw, by, bw, bh,
                if win.maximized: IconWindowRestore else: IconWindowMaximise,
                style=bs):
    if not win.maximizing:  # workaround to avoid double-activation
      if win.maximized:
        win.restore()
      else:
        win.maximize()

  if koi.button(x + bw*2, by, bw, bh, IconWindowClose, style=bs):
    win.w.shouldClose = true

  koi.setCurrentLayer(oldCurrLayer)

# }}}

# {{{ handleWindowDragEvents()
proc handleWindowDragEvents(win) =
  let
    (winWidth, winHeight) = (koi.winWidth(), koi.winHeight())
    mx = koi.mx()
    my = koi.my()

  case win.dragState
  of wdsNone:
    if koi.hasNoActiveItem() and koi.mbLeftDown():
      if my < TitleBarHeight and
         mx > TitleBarPinButtonTotalWidth and
         mx < winWidth - TitleBarWindowButtonsTotalWidth:
        win.mx0 = mx
        win.my0 = my
        (win.posX0, win.posY0) = win.w.pos
        win.dragState = wdsMoving

    if not win.maximized:
      if not koi.hasHotItem() and koi.hasNoActiveItem():
        let ew = WindowResizeEdgeWidth
        let cs = WindowResizeCornerSize
        let d =
          if   mx < cs            and my < cs:             wrdNW
          elif mx > winWidth - cs and my < cs:             wrdNE
          elif mx > winWidth - cs and my > winHeight - cs: wrdSE
          elif mx < cs            and my > winHeight - cs: wrdSW

          elif mx < ew:             wrdW
          elif mx > winWidth - ew:  wrdE
          elif my < ew:             wrdN
          elif my > winHeight - ew: wrdS

          else: wrdNone

        if d > wrdNone:
          case d
          of wrdW, wrdE: setCursorShape(csHorizResize)
          of wrdN, wrdS: setCursorShape(csVertResize)
          else: setCursorShape(csHand)

          if koi.mbLeftDown():
            win.mx0 = mx
            win.my0 = my
            win.resizeDir = d
            (win.posX0, win.posY0) = win.w.pos
            (win.width0, win.height0) = win.w.size
            win.dragState = wdsResizing
            # TODO maybe hide on OSX only?
#            hideCursor()
        else:
          setCursorShape(csArrow)
      else:
        setCursorShape(csArrow)

  of wdsMoving:
    if koi.mbLeftDown():
      let
        dx = (mx - win.mx0).int
        dy = (my - win.my0).int

      # Only move or restore the window when we're actually
      # dragging the title bar while holding the LMB down.
      if dx != 0 or dy != 0:

        # LMB-dragging the title bar will restore the window first (we're
        # imitating Windows' behaviour here).
        if win.maximized:

          # The restored window is centered horizontally around the cursor.
          (win.posX0, win.posY0) = ((mx - win.oldWidth*0.5).int32, 0)

          # Fake the last horizontal cursor position to be at the middle of
          # the restored window's width. This is needed so when we're in the
          # "else" branch on the next frame when dragging the restored window,
          # there won't be an unwanted window position jump.
          win.mx0 = win.oldWidth*0.5
          win.my0 = my

          # ...but we also want to clamp the window position to the visible
          # work area (and adjust the last cursor position accordingly to
          # avoid the position jump in drag mode on the next frame).
          if win.posX0 < 0:
            win.mx0 += win.posX0.float
            win.posX0 = 0

          # TODO This logic needs to be a bit more sophisticated to support
          # multiple monitors
          let (_, _, workAreaWidth, _) = getPrimaryMonitor().workArea
          let dx = win.posX0 + win.oldWidth - workAreaWidth
          if dx > 0:
            win.posX0 = workAreaWidth - win.oldWidth
            win.mx0 += dx.float

          win.w.pos = (win.posX0, win.posY0)
          win.w.size = (win.oldWidth, win.oldHeight)
          win.maximized = false

        else:
          win.w.pos = (win.posX0 + dx, win.posY0 + dy)
          (win.posX0, win.posY0) = win.w.pos
    else:
      win.dragState = wdsNone

  of wdsResizing:
    # TODO add support for resizing on edges
    # More standard cursor shapes patch:
    # https://github.com/glfw/glfw/commit/7dbdd2e6a5f01d2a4b377a197618948617517b0e
    if koi.mbLeftDown():
      let
        dx = (mx - win.mx0).int32
        dy = (my - win.my0).int32

      var
        (newX, newY) = (win.posX0, win.posY0)
        (newW, newH) = (win.width0, win.height0)

      case win.resizeDir:
      of wrdN:
        newY += dy
        newH -= dy
      of wrdNE:
        newY += dy
        newW += dx
        newH -= dy
      of wrdE:
        newW += dx
      of wrdSE:
        newW += dx
        newH += dy
      of wrdS:
        newH += dy
      of wrdSW:
        newX += dx
        newW -= dx
        newH += dy
      of wrdW:
        newX += dx
        newW -= dx
      of wrdNW:
        newX += dx
        newY += dy
        newW -= dx
        newH -= dy
      of wrdNone:
        discard

      let (newWidth, newHeight) = (max(newW, WindowMinWidth), max(newH, WindowMinHeight))

#      if newW >= newWidth and newH >= newHeight:
      (win.posX0, win.posY0) = (newX, newY)
      win.w.pos = (newX, newY)

      win.w.size = (newWidth, newHeight)

      if win.resizeDir in {wrdSW, wrdW, wrdNW}:
        win.width0 = newWidth

      if win.resizeDir in {wrdNE, wrdN, wrdNW}:
        win.height0 = newHeight

    else:
      win.dragState = wdsNone
      showCursor()

# }}}

type RenderFramePreProc = proc (win: CSDWindow)
type RenderFrameProc = proc (win: CSDWindow)

var g_window: CSDWindow
var g_renderFramePreProc: RenderFramePreProc
var g_renderFrameProc: RenderFrameProc

# {{{ renderFrame*()
proc renderFrame*(win: CSDWindow) =
  let vg = koi.nvgContext()

  # For pre-rendering stuff into FBOs before the main frame starts
  g_renderFramePreProc(win)

  let (winWidth, winHeight) = win.size
  let (fbWidth, fbHeight) = win.framebufferSize

  # Main frame drawing starts
  koi.beginFrame(winWidth, winHeight, fbWidth, fbHeight)

  # Render title bar must precede the window drag event handler because of
  # the overlapping button/resize handle areas
  renderTitleBar(win, vg, winWidth.float)
  handleWindowDragEvents(win)

  g_renderFrameProc(win)

  # Window border
  koi.addDrawLayer(layerWindowDecoration, vg):
    vg.beginPath()
    vg.rect(0.5, 0.5, winWidth.float-1, winHeight.float-1)
    # TODO border color
    vg.strokeColor(gray(0.09))
    vg.strokeWidth(1.0)
    vg.stroke()

  # Main frame drawing ends
  koi.endFrame()

  glfw.swapBuffers(win.w)  # TODO

# }}}

proc `renderFramePreCb=`*(win; p: RenderFramePreProc) =
  g_renderFramePreProc = p

proc `renderFrameCb=`*(win; p: RenderFrameProc) =
  g_window = win
  g_renderFrameProc = p

# vim: et:ts=2:sw=2:fdm=marker
