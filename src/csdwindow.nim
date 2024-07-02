import std/lenientops
import std/logging as log
import std/strformat

import glfw
import icons
import koi
import nanovg
import with

import common
import utils/misc
import utils/rect


# {{{ Constants
const
  TitleBarFontSize    = 14.0
  TitleBarHeight*     = 26.0
  TitleBarTitlePosX   = 16.0
  TitleBarButtonWidth = 22.0

  TitleBarWindowStandardButtonsLeftPad = 20.0
  TitleBarWindowButtonsRightPad        =  6.0

  TitleBarWindowButtonsTotalWidth = TitleBarButtonWidth*5 +
                                    TitleBarWindowStandardButtonsLeftPad +
                                    TitleBarWindowButtonsRightPad
  WindowResizeEdgeWidth  =  7.0
  WindowResizeCornerSize = 20.0

# }}}
#  {{{ CSDWindow
type
  CSDWindow* = ref object
    modified*: bool
    theme:     WindowTheme

    w: Window  # the wrapper GLFW window

    buttonActiveStyle:   ButtonStyle
    buttonInactiveStyle: ButtonStyle
    title:               string
    maximized:           bool
    maximizing:          bool
    showTitleBar:        bool
    dragState:           WindowDragState
    resizeDir:           WindowResizeDir
    mx0, my0:            float
    posX0, posY0:        int
    size0:               tuple[w, h: int32]
    unmaximizedPos:      tuple[x, y: int32]
    unmaximizedSize:     tuple[w, h: int32]

    oldFocusCaptured, focusCaptured: bool


  WindowDragState = enum
    wdsNone, wdsMoving, wdsResizing

  WindowResizeDir = enum
    wrdNone, wrdN, wrdNW, wrdW, wrdSW, wrdS, wrdSE, wrdE, wrdNE


using win: CSDWindow

var g_window: CSDWindow

# }}}
# {{{ Default style
var DefaultCSDWindowTheme = new WindowTheme

with DefaultCSDWindowTheme:
  titleBackgroundColor         = gray(0.2)
  titleBackgroundInactiveColor = gray(0.1)
  titleColor                   = gray(1.0, 0.7)
  titleInactiveColor           = gray(1.0, 0.4)
  buttonColor                  = gray(1.0, 0.45)
  buttonHoverColor             = gray(1.0, 0.7)
  buttonDownColor              = gray(1.0, 0.9)
  buttonInactiveColor          = gray(1.0, 0.5)
  modifiedFlagColor            = gray(1.0, 0.45)

# }}}

# {{{ GLFW Window adapters
# Just for the functions that actually get used in the app

proc glfwWin*(win): Window =
  win.w

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

proc cursorPos*(win): tuple[x, y: float64] =
  win.w.cursorPos

proc show*(win) =
  win.w.show

proc hide*(win) =
  win.w.hide

proc focus*(win) =
  win.w.focus

proc restore*(win) =
  win.w.restore

proc shouldClose*(win): bool =
  win.w.shouldClose

proc `shouldClose=`*(win; state: bool) =
  win.w.shouldClose = state

proc maximized*(win): bool =
  win.maximized

proc `dropCb=`*(win; f: DropCb) =
  win.w.dropCb = f

# }}}
# {{{ rect()
proc rect(win): Rect[int] =
  let (x1,y1) = win.pos
  let (x2,y2) = (x1 + win.size.w, y1 + win.size.h)
  coordRect(x1,y1, x2,y2)

# }}}

# {{{ workAreaRect()
proc workAreaRect(m: Monitor): Rect[int] =
  let wa = m.workArea
  let (x1,y1) = (wa.x, wa.y)
  let (x2,y2) = (x1 + wa.w, y1 + wa.h)
  coordRect(x1,y1, x2,y2)

# }}}
# {{{ findMonitorByCoord()
proc findMonitorByCoord(x, y: int32): Monitor =
  for m in monitors():
    let r = m.workAreaRect
    if r.contains(x, y):
      return m

  # Use the primary monitor as fallback
  getPrimaryMonitor()

# }}}
# {{{ findCurrentMonitor()
proc findCurrentMonitor*(win): Monitor =
  findMonitorByCoord(win.pos.x, win.pos.y)

# }}}
# {{{ snapWindowToVisibleArea*()
proc snapWindowToVisibleArea*(win) =
  let currMonitor = win.findCurrentMonitor
  let workAreaRect = currMonitor.workAreaRect
  let (w, h) = win.size

  if not workAreaRect.contains(win.rect):

    # Clamp window size to the extents of the current monitor
    if w > workAreaRect.w or
       h > workAreaRect.h or
       w < MinWindowWidth or
       h < MinWindowHeight:
      win.size = (w.clamp(MinWindowWidth,  workAreaRect.w.int32),
                  h.clamp(MinWindowHeight, workAreaRect.h.int32))

    # Center window
    let (cx, cy) = (workAreaRect.x1 + (workAreaRect.w div 2),
                    workAreaRect.y1 + (workAreaRect.h div 2))

    win.pos = (cx - (win.size.w div 2),
               cy - (win.size.h div 2))

# }}}

# # {{{ setTheme()
proc setTheme(win; s: WindowTheme) =
  win.theme = s

  win.buttonActiveStyle = koi.getDefaultButtonStyle()
  with win.buttonActiveStyle:
    labelOnly        = true
    label.padHoriz   = 0
    label.color      = s.buttonColor
    label.colorHover = s.buttonHoverColor
    label.colorDown  = s.buttonDownColor

  win.buttonInactiveStyle = koi.getDefaultButtonStyle()
  with win.buttonInactiveStyle:
    labelOnly        = true
    label.padHoriz   = 0
    label.color      = s.buttonInactiveColor
    label.colorHover = s.buttonInactiveColor
    label.colorDown  = s.buttonInactiveColor

# }}}
# # {{{ theme*
proc `theme=`*(win; s: WindowTheme) =
  win.setTheme(s)

# }}}
# {{{ newCSDWindow*()
proc newCSDWindow*(): CSDWindow =
  result = new CSDWindow

  var cfg = DefaultOpenglWindowConfig
  cfg.resizable = false
  cfg.visible = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = false
  cfg.nMultiSamples = 4
  cfg.decorated = false

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  result.w = newWindow(cfg)
  result.setTheme(DefaultCSDWindowTheme)
  result.showTitleBar = true

  setMonitorCb:
    proc(m: Monitor, connected: bool) =
      let state = if connected: "connected" else: "disconnected"
      log.info(fmt"Monitor '{m.name}' has been {state}")

      if not connected:
        snapWindowToVisibleArea(g_window)

# }}}
# {{{ showTitleBar*
proc showTitleBar*(win): bool =
  win.showTitleBar

proc `showTitleBar=`*(win; show: bool) =
  win.showTitleBar = show

# }}}
# {{{ titleBarHeight*
proc titleBarHeight*(win): float =
  if win.showTitleBar: TitleBarHeight else: 0

# }}}
# {{{ unmaximizedPos*
proc unmaximizedPos*(win): tuple[x, y: int32] =
  win.unmaximizedPos

proc `unmaximizedPos=`*(win; pos: tuple[x, y: int32]) =
  win.unmaximizedPos = pos

# }}}
# {{{ unmaximizedSize*
proc unmaximizedSize*(win): tuple[w, h: int32] =
  win.unmaximizedSize

proc `unmaximizedSize=`*(win; size: tuple[w, h: int32]) =
  win.unmaximizedSize = size

# }}}

# {{{ unmaximize*()
proc unmaximize*(win) =
  if win.maximized:
    win.w.pos = win.unmaximizedPos
    win.w.size = win.unmaximizedSize
    win.maximized = false

# }}}
# {{{ maximize*()
proc maximize*(win) =
  if not (win.maximized or win.maximizing):
    let (x, y, w, h) = win.findCurrentMonitor.workArea
    win.unmaximizedPos = win.w.pos
    win.unmaximizedSize = win.w.size

    win.maximized = true
    win.maximizing = true

    win.w.pos = (x, y)
    win.w.size = (w, h)

    win.maximizing = false

# }}}
# {{{ snapToLeft*()
proc snapToLeft*(win) =
  win.unmaximize

  let wa = win.findCurrentMonitor.workArea
  let windowWidth = wa.w div 2
  win.w.pos = (wa.x, wa.y)
  win.w.size = (windowWidth, wa.h)

# }}}
# {{{ snapToRight*()
proc snapToRight*(win) =
  win.unmaximize

  let wa = win.findCurrentMonitor.workArea
  let windowWidth = wa.w div 2
  win.w.pos = (wa.x + windowWidth, wa.y)
  win.w.size = (windowWidth, wa.h)

# }}}

# {{{ renderTitleBar()
proc renderTitleBar(win; vg: NVGContext, winWidth: float) =
  alias(s, win.theme)

  let (bgColor, textColor, modifiedFlagColor, buttonStyle) = if win.w.focused:
    (s.titleBackgroundColor, s.titleColor,
     s.modifiedFlagColor, win.buttonActiveStyle)
  else:
    (s.titleBackgroundInactiveColor, s.titleInactiveColor,
     s.modifiedFlagInactiveColor, win.buttonInactiveStyle)

  let
    bw = TitleBarButtonWidth
    bh = TitleBarFontSize + 4
    by = (TitleBarHeight - bh) / 2
    ty = TitleBarHeight * TextVertAlignFactor

  koi.addDrawLayer(layerWindowDecoration, vg):
    vg.beginPath
    vg.rect(0, 0, winWidth.float, TitleBarHeight)
    vg.fillColor(bgColor)
    vg.fill

    vg.setFont(TitleBarFontSize)
    vg.fillColor(textColor)
    vg.textAlign(haLeft, vaMiddle)

    # Window title & modified flag
    let tx = vg.text(TitleBarTitlePosX, ty, win.title)

    if win.modified:
      vg.fillColor(modifiedFlagColor)
      discard vg.text(tx+10, ty, IconAsterisk)


  # TODO hacky, shouldn't set the current layer from the outside
  let oldCurrLayer = koi.currentLayer()
  koi.setCurrentLayer(layerWindowDecoration)

  # Minimise/maximise/close window buttons
  var x = (winWidth - TitleBarWindowButtonsTotalWidth).float

  if koi.button(x, by, bw.float, bh, IconWindowLeft, style=buttonStyle):
    win.snapToLeft

  x += bw
  if koi.button(x, by, bw, bh, IconWindowRight, style=buttonStyle):
    win.snapToRight

  x += bw + TitleBarWindowStandardButtonsLeftPad
  if koi.button(x, by, bw, bh, IconWindowMinimise, style=buttonStyle):
    win.w.iconify

  x += bw
  if koi.button(x, by, bw, bh,
                if win.maximized: IconWindowRestore else: IconWindowMaximise,
                style=buttonStyle):

    if not win.maximizing:  # workaround to avoid double-activation
      if win.maximized:
        win.unmaximize
      else:
        win.maximize

  x += bw
  if koi.button(x, by, bw, bh, IconWindowClose, style=buttonStyle):
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
    if win.showTitleBar and koi.hasNoActiveItem() and koi.mbLeftDown():
      if my < TitleBarHeight and
         mx > 0 and mx < winWidth - TitleBarWindowButtonsTotalWidth:
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
          of wrdW,  wrdE:  setCursorShape(csResizeEW)
          of wrdN,  wrdS:  setCursorShape(csResizeNS)
          of wrdNW, wrdSE: setCursorShape(csResizeNWSE)
          of wrdNE, wrdSW: setCursorShape(csResizeNESW)
          else: setCursorShape(csArrow)

          if koi.mbLeftDown():
            win.mx0 = mx
            win.my0 = my
            win.resizeDir = d
            (win.posX0, win.posY0) = win.w.pos
            win.size0 = win.w.size
            win.dragState = wdsResizing
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
          let oldWidth = win.unmaximizedSize.w

          # The restored window is centered horizontally around the cursor.
          (win.posX0, win.posY0) = ((mx - oldWidth * 0.5).int32, 0)

          # Fake the last horizontal cursor position to be at the middle of
          # the restored window's width. This is needed so when we're in the
          # "else" branch on the next frame when dragging the restored window,
          # there won't be an unwanted window position jump.
          win.mx0 = oldWidth * 0.5
          win.my0 = my

          # ...but we also want to clamp the window position to the visible
          # work area (and adjust the last cursor position accordingly to
          # avoid the position jump in drag mode on the next frame).
          if win.posX0 < 0:
            win.mx0 += win.posX0.float
            win.posX0 = 0

          let (_, _, workAreaWidth, _) = win.findCurrentMonitor.workArea
          let dx = win.posX0 + oldWidth - workAreaWidth
          if dx > 0:
            win.posX0 = workAreaWidth - oldWidth
            win.mx0 += dx.float

          win.w.pos = (win.posX0, win.posY0)
          win.w.size = (oldWidth, win.unmaximizedSize.h)
          win.maximized = false

        else:
          win.w.pos = (win.posX0 + dx, win.posY0 + dy)
          (win.posX0, win.posY0) = win.w.pos
    else:
      win.dragState = wdsNone

  of wdsResizing:
    if koi.mbLeftDown():
      let
        dx = (mx - win.mx0).int32
        dy = (my - win.my0).int32

      var
        (newX, newY) = (win.posX0, win.posY0)
        (newW, newH) = win.size0

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

      let (newWidth, newHeight) = (max(newW, MinWindowWidth),
                                   max(newH, MinWindowHeight))

      (win.posX0, win.posY0) = (newX, newY)
      win.w.pos = (newX, newY)

      win.w.size = (newWidth, newHeight)

      if win.resizeDir in {wrdSW, wrdW, wrdNW}:
        win.size0.w = newWidth

      if win.resizeDir in {wrdNE, wrdN, wrdNW}:
        win.size0.h = newHeight

    else:
      win.dragState = wdsNone
      koi.showCursor()

# }}}

# {{{ renderFrame*()

type RenderFramePreProc = proc (win: CSDWindow)
type RenderFrameProc = proc (win: CSDWindow)

var g_renderFramePreProc: RenderFramePreProc
var g_renderFrameProc: RenderFrameProc

proc renderFrame*(win: CSDWindow, vg: NVGContext) =
  if win.w.iconified: return

  # For pre-rendering stuff into FBOs before the main frame starts
  g_renderFramePreProc(win)

  # Main frame drawing starts
  let (winWidth, winHeight) = win.size
  let (fbWidth, fbHeight) = win.framebufferSize

  koi.beginFrame(winWidth, winHeight, fbWidth, fbHeight)

  # Render title bar must precede the window drag event handler because of
  # the overlapping button/resize handle areas
  if win.showTitleBar:
    renderTitleBar(win, vg, winWidth.float)

  handleWindowDragEvents(win)

  if win.dragState == wdsResizing:
    koi.setFocusCaptured(true)

  g_renderFrameProc(win)

  if win.dragState == wdsResizing:
    koi.setFocusCaptured(false)

  # Window border
  koi.addDrawLayer(layerWindowDecoration, vg):
    vg.beginPath
    vg.rect(0.5, 0.5, winWidth.float-1, winHeight.float-1)
    vg.strokeColor(win.theme.borderColor)
    vg.strokeWidth(1.0)
    vg.stroke

  # Main frame drawing ends
  koi.endFrame()

# }}}
# {{{ renderFramePreCb*
proc `renderFramePreCb=`*(win; p: RenderFramePreProc) =
  g_renderFramePreProc = p

# }}}
# {{{ renderFrameCb*
proc `renderFrameCb=`*(win; p: RenderFrameProc) =
  g_window = win
  g_renderFrameProc = p

# }}}

# vim: et:ts=2:sw=2:fdm=marker
