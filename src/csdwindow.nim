import lenientops

import icons
import glad/gl
import glfw
import koi
import nanovg

import common
import utils


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

  WindowResizeEdgeWidth = 10.0
  WindowResizeCornerSize = 20.0

var
  g_resizeRedrawHack = true
  g_resizeNoVsyncHack = true

#  {{{ CSDWindow
type
  CSDWindow* = ref object
    modified*: bool
    style*:    CSDWindowStyle

    w: Window  # the wrapper GLFW window

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

    fastRedrawFrameCounter: int


  CSDWindowStyle* = ref object
    backgroundColor*:    Color
    bgColorUnfocused*:   Color
    textColor*:          Color
    textColorUnfocused*: Color
    modifiedFlagColor*:  Color
    buttonColor*:        Color
    buttonColorHover*:   Color
    buttonColorDown*:    Color

  WindowDragState = enum
    wdsNone, wdsMoving, wdsResizing

  WindowResizeDir = enum
    wrdNone, wrdN, wrdNW, wrdW, wrdSW, wrdS, wrdSE, wrdE, wrdNE


using win: CSDWindow

# }}}

# {{{ Default style
var DefaultCSDWindowStyle = new CSDWindowStyle

DefaultCSDWindowStyle.backgroundColor    = gray(0.2)
DefaultCSDWindowStyle.bgColorUnfocused   = gray(0.1)
DefaultCSDWindowStyle.textColor          = gray(1.0, 0.7)
DefaultCSDWindowStyle.textColorUnfocused = gray(1.0, 0.4)
DefaultCSDWindowStyle.buttonColor        = gray(1.0, 0.45)
DefaultCSDWindowStyle.buttonColorHover   = gray(1.0, 0.7)
DefaultCSDWindowStyle.buttonColorDown    = gray(1.0, 0.9)
DefaultCSDWindowStyle.modifiedFlagColor  = gray(1.0, 0.45)

proc getDefaultCSDWindowStyle*(): CSDWindowStyle = DefaultCSDWindowStyle.deepCopy()

# }}}

# {{{ setStyle()
proc setStyle*(win; s: CSDWindowStyle) = 
  win.style = s

  alias(bs, win.buttonStyle)
  bs = koi.getDefaultButtonStyle()

  bs.labelPadHoriz   = 0
  bs.labelOnly       = true
  bs.labelColor      = s.buttonColor
  bs.labelColorHover = s.buttonColorHover
  bs.labelColorDown  = s.buttonColorDown

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
  if g_resizeNoVsyncHack:
    glfw.swapInterval(0)

  win.fastRedrawFrameCounter = 20
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

  if g_resizeNoVsyncHack:
    glfw.swapInterval(0)

  win.fastRedrawFrameCounter = 20
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

  vg.beginPath()
  vg.rect(0, 0, winWidth.float, TitleBarHeight)
  vg.fillColor(bgColor)
  vg.fill()

  vg.setFont(TitleBarFontSize)
  vg.fillColor(textColor)
  vg.textAlign(haLeft, vaMiddle)

  let
    bw = TitleBarButtonWidth
    bh = TitleBarFontSize + 4
    by = (TitleBarHeight - bh) / 2
    ty = TitleBarHeight * TextVertAlignFactor

  alias(bs, win.buttonStyle)

  # Pin window button
  if koi.button(TitleBarPinButtonsLeftPad, by, bw, bh, IconPin, style=bs):
    # TODO
    discard

  # Window title & modified flag
  let tx = vg.text(TitleBarTitlePosX, ty, win.title)

  if win.modified:
    vg.fillColor(s.modifiedFlagColor)
    discard vg.text(tx+10, ty, IconAsterisk)

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

# }}}
# {{{ handleWindowDragEvents()
proc handleWindowDragEvents(win) =
  let
    (winWidth, winHeight) = (koi.winWidth(), koi.winHeight())
    mx = koi.mx()
    my = koi.my()

  case win.dragState
  of wdsNone:
    if koi.noActiveItem() and koi.mbLeftDown():
      if my < TitleBarHeight and
         mx > TitleBarPinButtonTotalWidth and
         mx < winWidth - TitleBarWindowButtonsTotalWidth:
        win.mx0 = mx
        win.my0 = my
        (win.posX0, win.posY0) = win.w.pos
        win.dragState = wdsMoving

        if g_resizeNoVsyncHack:
          glfw.swapInterval(0)

    if not win.maximized:
      if not koi.hasHotItem() and koi.noActiveItem():
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
          of wrdW, wrdE: showHorizResizeCursor()
          of wrdN, wrdS: showVertResizeCursor()
          else: showHandCursor()

          if koi.mbLeftDown():
            win.mx0 = mx
            win.my0 = my
            win.resizeDir = d
            (win.posX0, win.posY0) = win.w.pos
            (win.width0, win.height0) = win.w.size
            win.dragState = wdsResizing
            # TODO maybe hide on OSX only?
#            hideCursor()
#
            if g_resizeNoVsyncHack:
              glfw.swapInterval(0)
        else:
          showArrowCursor()
      else:
        showArrowCursor()

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

      if g_resizeNoVsyncHack:
        glfw.swapInterval(1)

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

      if g_resizeNoVsyncHack:
        glfw.swapInterval(1)

# }}}


type RenderFramePreProc = proc (win: CSDWindow)
type RenderFrameProc = proc (win: CSDWindow, doHandleEvents: bool)

var g_window: CSDWindow
var g_renderFramePreProc: RenderFramePreProc
var g_renderFrameProc: RenderFrameProc

# {{{ csdRenderFrame*()
proc csdRenderFrame*(win: CSDWindow, doHandleEvents: bool = true) =
  let vg = koi.nvgContext()

  g_renderFramePreProc(win)

  #####################################

  var
    (winWidth, winHeight) = win.size
    (fbWidth, fbHeight) = win.framebufferSize
    pxRatio = fbWidth / winWidth

  # Update and render
  glViewport(0, 0, fbWidth, fbHeight)

  glClearColor(0.4, 0.4, 0.4, 1.0)

  glClear(GL_COLOR_BUFFER_BIT or
          GL_DEPTH_BUFFER_BIT or
          GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)
  koi.beginFrame(winWidth.float, winHeight.float)

  # Title bar
  renderTitleBar(win, vg, winWidth.float)

  #####################################

  g_renderFrameProc(win, doHandleEvents=true)

  if doHandleEvents:
    handleWindowDragEvents(win)

  #####################################
  (winWidth, winHeight) = win.size

  # Window border
  vg.beginPath()
  vg.rect(0.5, 0.5, winWidth.float-1, winHeight.float-1)
  vg.strokeColor(gray(0.09))
  vg.strokeWidth(1.0)
  vg.stroke()

  koi.endFrame()
  vg.endFrame()

  glfw.swapBuffers(win.w)  # TODO

  if g_resizeNoVsyncHack:
    if win.fastRedrawFrameCounter > 0:
      dec(win.fastRedrawFrameCounter)
      if win.fastRedrawFrameCounter == 0:
        glfw.swapInterval(1)

# }}}

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  if g_resizeRedrawHack:
    csdRenderFrame(g_window, doHandleEvents=false)
  else:
    discard

proc `renderFramePreCb=`*(win; p: RenderFramePreProc) =
  g_renderFramePreProc = p

proc `renderFrameCb=`*(win; p: RenderFrameProc) =
  g_window = win
  g_renderFrameProc = p
  win.w.framebufferSizeCb = framebufSizeCb

proc setResizeRedrawHack*(enabled: bool) =
  g_resizeRedrawHack = enabled

proc setResizeNoVsyncHack*(enabled: bool) =
  g_resizeNoVsyncHack = enabled

proc getResizeRedrawHack*(): bool =
  g_resizeRedrawHack

proc getResizeNoVsyncHack*(): bool =
  g_resizeNoVsyncHack

# vim: et:ts=2:sw=2:fdm=marker
