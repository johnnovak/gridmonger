import lenientops

import glfw
import koi
import nanovg

import common


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
  WindowMinWidth = 400
  WindowMinHeight = 200

#  {{{ CSDWindow
type
  CSDWindow* = ref object
    w*: Window  # the wrapper GLFW window

    title:               string
    modified:            bool
    maximized:           bool
    maximizing:          bool
    dragState:           WindowDragState
    resizeDir:           WindowResizeDir
    mx0, my0:            float
    posX0, posY0:        int
    width0, height0:     int32
    oldPosX, oldPosY:    int
    oldWidth, oldHeight: int32

    fastRedrawFrameCounter*: int  # TODO

  WindowDragState = enum
    wdsNone, wdsMoving, wdsResizing

  WindowResizeDir = enum
    wrdNone, wrdN, wrdNW, wrdW, wrdSW, wrdS, wrdSE, wrdE, wrdNE


using win: CSDWindow

# }}}

# {{{ newCSDWindow*()
proc newCSDWindow*(win: Window): CSDWindow =
  result = new CSDWindow
  result.w = win

# }}}
# {{{ restoreWindow*()
proc restoreWindow*(win) =
  glfw.swapInterval(0)
  win.fastRedrawFrameCounter = 20
  win.w.pos = (win.oldPosX, win.oldPosY)
  win.w.size = (win.oldWidth, win.oldHeight)
  win.maximized = false

# }}}
# {{{ maximizeWindow*()
proc maximizeWindow*(win) =
  # TODO This logic needs to be a bit more sophisticated to support
  # multiple monitors
  let (_, _, w, h) = getPrimaryMonitor().workArea
  (win.oldPosX, win.oldPosY) = win.w.pos
  (win.oldWidth, win.oldHeight) = win.w.size

  glfw.swapInterval(0)
  win.fastRedrawFrameCounter = 20
  win.maximized = true
  win.maximizing = true

  win.w.pos = (0, 0)
  win.w.size = (w, h)

  win.maximizing = false

# }}}
# {{{ setWindowTitle*()
proc setWindowTitle*(win; title: string) =
  win.title = title

# }}}
# {{{ setWindowModifiedFlag*()
proc setWindowModifiedFlag*(win; modified: bool) =
  win.modified = modified

# }}}
# {{{ renderTitleBar*()

var g_TitleBarWindowButtonStyle = koi.getDefaultButtonStyle()

g_TitleBarWindowButtonStyle.labelOnly        = true
g_TitleBarWindowButtonStyle.labelColor       = gray(0.45)
g_TitleBarWindowButtonStyle.labelColorHover  = gray(0.7)
g_TitleBarWindowButtonStyle.labelColorActive = gray(0.9)


proc renderTitleBar*(win; vg: NVGContext, winWidth: float) =
  vg.beginPath()
  vg.rect(0, 0, winWidth.float, TitleBarHeight)
  vg.fillColor(gray(0.09))
  vg.fill()

  vg.setFont(TitleBarFontSize)
  vg.fillColor(gray(0.7))
  vg.textAlign(haLeft, vaMiddle)

  let
    bw = TitleBarButtonWidth
    bh = TitleBarFontSize + 4
    by = (TitleBarHeight - bh) / 2
    ty = TitleBarHeight * TextVertAlignFactor

  # Pin window button
  if koi.button(TitleBarPinButtonsLeftPad, by, bw, bh, IconPin,
                style=g_TitleBarWindowButtonStyle):
    # TODO
    discard

  # Window title & modified flag
  let tx = vg.text(TitleBarTitlePosX, ty, win.title)

  if win.modified:
    vg.fillColor(gray(0.45))
    discard vg.text(tx+10, ty, IconAsterisk)

  # Minimise/maximise/close window buttons
  let x = winWidth - TitleBarWindowButtonsTotalWidth

  if koi.button(x, by, bw, bh, IconWindowMinimise,
                style=g_TitleBarWindowButtonStyle):
    win.w.iconify()

  if koi.button(x + bw, by, bw, bh,
                if win.maximized: IconWindowRestore else: IconWindowMaximise,
                style=g_TitleBarWindowButtonStyle):
    if not win.maximizing:  # workaround to avoid double-activation
      if win.maximized:
        restoreWindow(win)
      else:
        maximizeWindow(win)

  if koi.button(x + bw*2, by, bw, bh, IconWindowClose,
                style=g_TitleBarWindowButtonStyle):
    win.w.shouldClose = true

# }}}
# {{{ handleWindowDragEvents*()
proc handleWindowDragEvents*(win) =
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
      glfw.swapInterval(1)

# }}}

# {{{ GLFW Window adapter
# Just for the functions that actually get used in the app

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

# TODO move to koi?
proc isKeyDown*(win; key: Key): bool =
  win.w.isKeyDown(key)

proc resizing*(win): bool =
  win.dragState == wdsResizing

type RenderFrameProc = proc (win: CSDWindow, doHandleEvents: bool)
var g_window: CSDWindow
var g_renderFrameProc: RenderFrameProc

proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  g_renderFrameProc(g_window, doHandleEvents=false)

proc setRenderProc*(win; p: RenderFrameProc) =
  g_renderFrameProc = p
  g_window = win
  win.w.framebufferSizeCb = framebufSizeCb

# }}}

# vim: et:ts=2:sw=2:fdm=marker
