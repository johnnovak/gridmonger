import lenientops
import math
import options
import strutils
import strformat

import glad/gl
import glfw
from glfw/wrapper import showWindow
import koi
import nanovg
import osdialog

import actions
import common
import drawmap
import map
import persistence
import selection
import undomanager
import utils


const DefaultZoomLevel = 5

const
  TitleBarFontSize = 14.0
  TitleBarHeight = 26.0
  TitleBarTitlePosX = 50.0
  TitleBarButtonWidth = 23.0
  TitleBarPinButtonsLeftPad = 4.0
  TitleBarPinButtonTotalWidth = TitleBarPinButtonsLeftPad + TitleBarButtonWidth
  TitleBarWindowButtonsRightPad = 6.0
  TitleBarWindowButtonsTotalWidth = TitleBarButtonWidth*3 +
                                    TitleBarWindowButtonsRightPad
  StatusBarHeight = 26.0

  MapLeftPad   = 50.0
  MapRightPad  = 120.0
  MapTopPad    = 80.0
  MapBottomPad = 35.0

  WindowResizeEdgeWidth = 10.0
  WindowResizeCornerSize = 20.0
  WindowMinWidth = 400
  WindowMinHeight = 200

# {{{ AppContext
type
  EditMode* = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearGround,
    emSelectDraw,
    emSelectRect
    emPastePreview

  AppContext = ref object
    # Context
    win:            Window
    vg:             NVGContext

    # Dependencies
    undoManager:    UndoManager[Map]

    # Document (TODO group under 'doc'?)
    map:            Map

    # Options (TODO group under 'opts'?)
    scrollMargin:   Natural
    mapStyle:       MapStyle

    # UI state (TODO group under 'ui'?)
    editMode:       EditMode
    cursorCol:      Natural
    cursorRow:      Natural

    currWall:       Wall

    selection:      Option[Selection]
    selRect:        Option[SelectionRect]
    copyBuf:        Option[CopyBuffer]

    currMapLevel:   Natural
    statusIcon:     string
    statusMessage:  string
    statusCommands: seq[string]
    drawMapParams:  DrawMapParams


var g_app: AppContext

using a: var AppContext

# }}}

#{{{ CSDWindow
type
  CSDWindow = object
    title:                  string
    modified:               bool
    maximized:              bool
    maximizing:             bool
    dragState:              WindowDragState
    resizeDir:              WindowResizeDir
    mx0, my0:               float
    posX0, posY0:           int
    width0, height0:        int32
    oldPosX, oldPosY:       int
    oldWidth, oldHeight:    int32
    fastRedrawFrameCounter: int

  WindowDragState = enum
    wdsNone, wdsMoving, wdsResizing

  WindowResizeDir = enum
    wrdNone, wrdN, wrdNW, wrdW, wrdSW, wrdS, wrdSE, wrdE, wrdNE

var g_window: CSDWindow

# }}}
# {{{ restoreWindow()
proc restoreWindow(a) =
  alias(wnd, g_window)

  glfw.swapInterval(0)
  wnd.fastRedrawFrameCounter = 20
  a.win.pos = (wnd.oldPosX, wnd.oldPosY)
  a.win.size = (wnd.oldWidth, wnd.oldHeight)
  wnd.maximized = false

# }}}
# {{{ maximizeWindow()
proc maximizeWindow(a) =
  alias(wnd, g_window)

  # TODO This logic needs to be a bit more sophisticated to support
  # multiple monitors
  let (_, _, w, h) = getPrimaryMonitor().workArea
  (wnd.oldPosX, wnd.oldPosY) = a.win.pos
  (wnd.oldWidth, wnd.oldHeight) = a.win.size

  glfw.swapInterval(0)
  wnd.fastRedrawFrameCounter = 20
  wnd.maximized = true
  wnd.maximizing = true

  a.win.pos = (0, 0)
  a.win.size = (w, h)

  wnd.maximizing = false

# }}}
# {{{ setWindowTitle()
proc setWindowTitle(title: string) =
  g_window.title = title

# }}}
# {{{ setWindowModifiedFlag()
proc setWindowModifiedFlag(modified: bool) =
  g_window.modified = modified

# }}}
# {{{ renderTitleBar()

var g_TitleBarWindowButtonStyle = koi.getDefaultButtonStyle()

g_TitleBarWindowButtonStyle.labelOnly        = true
g_TitleBarWindowButtonStyle.labelColor       = gray(0.45)
g_TitleBarWindowButtonStyle.labelColorHover  = gray(0.7)
g_TitleBarWindowButtonStyle.labelColorActive = gray(0.9)


proc renderTitleBar(a; winWidth: float) =
  alias(vg, a.vg)
  alias(win, a.win)
  alias(wnd, g_window)

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
  let tx = vg.text(TitleBarTitlePosX, ty, wnd.title)

  if wnd.modified:
    vg.fillColor(gray(0.45))
    discard vg.text(tx+10, ty, IconAsterisk)

  # Minimise/maximise/close window buttons
  let x = winWidth - TitleBarWindowButtonsTotalWidth

  if koi.button(x, by, bw, bh, IconWindowMinimise,
                style=g_TitleBarWindowButtonStyle):
    win.iconify()

  if koi.button(x + bw, by, bw, bh,
                if wnd.maximized: IconWindowRestore else: IconWindowMaximise,
                style=g_TitleBarWindowButtonStyle):
    if not wnd.maximizing:  # workaround to avoid double-activation
      if wnd.maximized:
        restoreWindow(a)
      else:
        maximizeWindow(a)

  if koi.button(x + bw*2, by, bw, bh, IconWindowClose,
                style=g_TitleBarWindowButtonStyle):
    win.shouldClose = true

# }}}
# {{{ handleWindowDragEvents()
proc handleWindowDragEvents(a) =
  alias(win, a.win)
  alias(wnd, g_window)

  let
    (winWidth, winHeight) = (koi.winWidth(), koi.winHeight())
    mx = koi.mx()
    my = koi.my()

  case wnd.dragState
  of wdsNone:
    if koi.noActiveItem() and koi.mbLeftDown():
      if my < TitleBarHeight and
         mx > TitleBarPinButtonTotalWidth and
         mx < winWidth - TitleBarWindowButtonsTotalWidth:
        wnd.mx0 = mx
        wnd.my0 = my
        (wnd.posX0, wnd.posY0) = win.pos
        wnd.dragState = wdsMoving
        glfw.swapInterval(0)

    if not wnd.maximized:
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
            wnd.mx0 = mx
            wnd.my0 = my
            wnd.resizeDir = d
            (wnd.posX0, wnd.posY0) = win.pos
            (wnd.width0, wnd.height0) = win.size
            wnd.dragState = wdsResizing
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
        dx = (mx - wnd.mx0).int
        dy = (my - wnd.my0).int

      # Only move or restore the window when we're actually
      # dragging the title bar while holding the LMB down.
      if dx != 0 or dy != 0:

        # LMB-dragging the title bar will restore the window first (we're
        # imitating Windows' behaviour here).
        if wnd.maximized:

          # The restored window is centered horizontally around the cursor.
          (wnd.posX0, wnd.posY0) = ((mx - wnd.oldWidth/2).int32, 0)

          # Fake the last horizontal cursor position to be at the middle of
          # the restored window's width. This is needed so when we're in the
          # "else" branch on the next frame when dragging the restored window,
          # there won't be an unwanted window position jump.
          wnd.mx0 = wnd.oldWidth/2
          wnd.my0 = my

          # ...but we also want to clamp the window position to the visible
          # work area (and adjust the last cursor position accordingly to
          # avoid the position jump in drag mode on the next frame).
          if wnd.posX0 < 0:
            wnd.mx0 += wnd.posX0.float
            wnd.posX0 = 0

          # TODO This logic needs to be a bit more sophisticated to support
          # multiple monitors
          let (_, _, workAreaWidth, _) = getPrimaryMonitor().workArea
          let dx = wnd.posX0 + wnd.oldWidth - workAreaWidth
          if dx > 0:
            wnd.posX0 = workAreaWidth - wnd.oldWidth
            wnd.mx0 += dx.float

          win.pos = (wnd.posX0, wnd.posY0)
          win.size = (wnd.oldWidth, wnd.oldHeight)
          wnd.maximized = false

        else:
          win.pos = (wnd.posX0 + dx, wnd.posY0 + dy)
          (wnd.posX0, wnd.posY0) = win.pos
    else:
      wnd.dragState = wdsNone
      glfw.swapInterval(1)

  of wdsResizing:
    # TODO add support for resizing on edges
    # More standard cursor shapes patch:
    # https://github.com/glfw/glfw/commit/7dbdd2e6a5f01d2a4b377a197618948617517b0e
    if koi.mbLeftDown():
      let
        dx = (mx - wnd.mx0).int32
        dy = (my - wnd.my0).int32

      var
        (newX, newY) = (wnd.posX0, wnd.posY0)
        (newW, newH) = (wnd.width0, wnd.height0)

      case wnd.resizeDir:
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
      (wnd.posX0, wnd.posY0) = (newX, newY)
      win.pos = (newX, newY)

      win.size = (newWidth, newHeight)

      if wnd.resizeDir in {wrdSW, wrdW, wrdNW}:
        wnd.width0 = newWidth

      if wnd.resizeDir in {wrdNE, wrdN, wrdNW}:
        wnd.height0 = newHeight

    else:
      wnd.dragState = wdsNone
      showCursor()
      glfw.swapInterval(1)

# }}}

# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  a.statusIcon = ""
  a.statusMessage = ""
  a.statusCommands = @[]

# }}}
# {{{ setStatusMessage()
proc setStatusMessage(a; icon, msg: string, commands: seq[string]) =
  a.statusIcon = icon
  a.statusMessage = msg
  a.statusCommands = commands

proc setStatusMessage(a; icon, msg: string) =
  a.setStatusMessage(icon , msg, commands = @[])

proc setStatusMessage(a; msg: string) =
  a.setStatusMessage(icon = "", msg, commands = @[])

# }}}
# {{{ renderStatusBar()

proc renderStatusBar(a; y: float, winWidth: float) =
  alias(vg, a.vg)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(gray(0.2))
  vg.fill()

  # Display current coords
  let cursorPos = fmt"({a.cursorCol}, {a.cursorRow})"
  let tw = vg.textWidth(cursorPos)

  vg.setFont(14.0)
  vg.fillColor(gray(0.6))
  vg.textAlign(haLeft, vaMiddle)
  discard vg.text(winWidth - tw - 15, ty, cursorPos)

  vg.scissor(0, y, winWidth - tw - 25, StatusBarHeight)

  # Display icon & message
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 13
    CommandTextPadX = 10

  var x = 10.0

  vg.fillColor(gray(0.8))
  discard vg.text(IconPosX, ty, a.statusIcon)

  let tx = vg.text(MessagePosX, ty, a.statusMessage)
  x = tx + MessagePadX

  # Display commands, if present
  for i, cmd in a.statusCommands.pairs:
    if i mod 2 == 0:
      let label = cmd
      let w = vg.textWidth(label)

      vg.beginPath()
      vg.roundedRect(x, y+4, w + 10, StatusBarHeight-8, 3)
      vg.fillColor(gray(0.56))
      vg.fill()

      vg.fillColor(gray(0.2))
      discard vg.text(x + 5, ty, label)
      x += w + CommandLabelPadX
    else:
      let text = cmd
      vg.fillColor(gray(0.8))
      let tx = vg.text(x, ty, text)
      x = tx + CommandTextPadX

  vg.resetScissor()

# }}}

# {{{ isKeyDown()
func isKeyDown(ke: KeyEvent, keys: set[Key],
               mods: set[ModifierKey] = {}, repeat=false): bool =
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  ke.action in a and ke.key in keys and ke.mods == mods

func isKeyDown(ke: KeyEvent, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ke, {key}, mods, repeat)

func isKeyUp(ke: KeyEvent, keys: set[Key]): bool =
  ke.action == kaUp and ke.key in keys

# }}}
# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  a.cursorCol = 0
  a.cursorRow = 0
  a.drawMapParams.viewStartCol = 0
  a.drawMapParams.viewStartRow = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  let
    drawAreaHeight = winHeight - TitleBarHeight - StatusBarHeight -
                     MapTopPad - MapBottomPad

    drawAreaWidth = winWidth - MapLeftPad - MapRightPad

  dp.startX = MapLeftPad
  dp.startY = TitleBarHeight + MapTopPad

  dp.viewCols = min(dp.numDisplayableCols(drawAreaWidth), a.map.cols)
  dp.viewRows = min(dp.numDisplayableRows(drawAreaHeight), a.map.rows)

  dp.viewStartCol = min(max(a.map.cols - dp.viewCols, 0), dp.viewStartCol)
  dp.viewStartRow = min(max(a.map.rows - dp.viewRows, 0), dp.viewStartRow)

  let viewEndCol = dp.viewStartCol + dp.viewCols - 1
  let viewEndRow = dp.viewStartRow + dp.viewRows - 1

  a.cursorCol = min(
    max(viewEndCol, dp.viewStartCol),
    a.cursorCol
  )
  a.cursorRow = min(
    max(viewEndRow, dp.viewStartRow),
    a.cursorRow
  )

# }}}
# {{{ moveCursor()
proc moveCursor(dir: Direction, a) =
  alias(dp, a.drawMapParams)

  var
    cx = a.cursorCol
    cy = a.cursorRow
    sx = dp.viewStartCol
    sy = dp.viewStartRow

  case dir:
  of East:
    cx = min(cx+1, a.map.cols-1)
    if cx - sx > dp.viewCols-1 - a.scrollMargin:
      sx = min(max(a.map.cols - dp.viewCols, 0), sx+1)

  of South:
    cy = min(cy+1, a.map.rows-1)
    if cy - sy > dp.viewRows-1 - a.scrollMargin:
      sy = min(max(a.map.rows - dp.viewRows, 0), sy+1)

  of West:
    cx = max(cx-1, 0)
    if cx < sx + a.scrollMargin:
      sx = max(sx-1, 0)

  of North:
    cy = max(cy-1, 0)
    if cy < sy + a.scrollMargin:
      sy = max(sy-1, 0)

  a.cursorCol = cx
  a.cursorRow = cy
  dp.viewStartCol = sx
  dp.viewStartRow = sy

# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelectDraw
  a.selection = some(newSelection(a.map.cols, a.map.rows))
  a.drawMapParams.drawCursorGuides = true
  a.setStatusMessage(IconSelection, "Mark selection",
                     @["D", "draw", "E", "erase", "R", "rectangle",
                       "Ctrl+A/D", "mark/unmark all", "C", "copy", "X", "cut",
                       "Esc", "exit"])

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.editMode = emNormal
  a.selection = none(Selection)
  a.drawMapParams.drawCursorGuides = false
  a.clearStatusMessage()

# }}}
# {{{ copySelection()
proc copySelection(a): Option[Rect[Natural]] =

  proc eraseOrphanedWalls(cb: CopyBuffer) =
    var m = cb.map
    for c in 0..<m.cols:
      for r in 0..<m.rows:
        m.eraseOrphanedWalls(c,r)

  let sel = a.selection.get

  let bbox = sel.boundingBox()
  if bbox.isSome:
    a.copyBuf = some(CopyBuffer(
      selection: newSelectionFrom(a.selection.get, bbox.get),
      map: newMapFrom(a.map, bbox.get)
    ))
    eraseOrphanedWalls(a.copyBuf.get)

  result = bbox

# }}}

# {{{ Dialogs

# {{{ New map dialog
const NewMapDialogTitle = "  New map"

var
  g_newMapDialog_name: string
  g_newMapDialog_cols: string
  g_newMapDialog_rows: string

proc newMapDialog() =
  koi.dialog(350, 220, NewMapDialogTitle):
    let
      dialogWidth = 350.0
      dialogHeight = 220.0
      h = 24.0
      labelWidth = 70.0
      buttonWidth = 80.0
      buttonPad = 15.0

    var
      x = 30.0
      y = 60.0

    koi.label(x, y, labelWidth, h, "Name", gray(0.80), fontSize=14.0)
    g_newMapDialog_name = koi.textField(
      x + labelWidth, y, 220.0, h, tooltip = "", g_newMapDialog_name
    )

    y = y + 50
    koi.label(x, y, labelWidth, h, "Columns", gray(0.80), fontSize=14.0)
    g_newMapDialog_cols = koi.textField(
      x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_cols
    )

    y = y + 30
    koi.label(x, y, labelWidth, h, "Rows", gray(0.80), fontSize=14.0)
    g_newMapDialog_rows = koi.textField(
      x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_rows
    )

    x = dialogWidth - 2 * buttonWidth - buttonPad - 10
    y = dialogHeight - h - buttonPad

    let okAction = proc () =
      initUndoManager(g_app.undoManager)
      g_app.map = newMap(
        parseInt(g_newMapDialog_cols),
        parseInt(g_newMapDialog_rows)
      )
      resetCursorAndViewStart(g_app)
      updateViewStartAndCursorPosition(g_app)
      closeDialog()
      g_app.setStatusMessage(IconFile, "New map created")

    let cancelAction = proc () =
      closeDialog()

    if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
      okAction()

    x += buttonWidth + 10
    if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
      cancelAction()

    for ke in koi.keyBuf():
      if   ke.action == kaDown and ke.key == keyEscape: cancelAction()
      elif ke.action == kaDown and ke.key == keyEnter:  okAction()

# }}}

template defineDialogs() =
  newMapDialog()

# }}}

proc drawWallTool(a; x: float) =
  alias(vg, a.vg)
  var y = 100.0
  let w = 25.0
  let pad = 8.0

  for wall in wIllusoryWall..wStatue:
    if a.currWall == wall:
      vg.fillColor(rgb(1.0, 0.7, 0))
    else:
      vg.fillColor(gray(0.3))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()
    y += w + pad


# {{{ handleMapEvents()
proc handleMapEvents(a) =
  alias(curX, a.cursorCol)
  alias(curY, a.cursorRow)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(dp, a.drawMapParams)
  alias(win, a.win)

  proc mkFloorMessage(g: Ground): string =
    fmt"Set floor – {g}"

  proc setFloorOrientationStatusMessage(a; o: Orientation) =
    if o == Horiz:
      a.setStatusMessage(IconHorizArrows, "Floor orientation set to horizontal")
    else:
      a.setStatusMessage(IconVertArrows, "Floor orientation set to vertical")

  proc incZoomLevel(a) =
    a.drawMapParams.incZoomLevel()
    updateViewStartAndCursorPosition(a)

  proc decZoomLevel(a) =
    a.drawMapParams.decZoomLevel()
    updateViewStartAndCursorPosition(a)


  let (winWidth, winHeight) = win.size

  const
    MoveKeysLeft  = {keyLeft,  keyH, keyKp4}
    MoveKeysRight = {keyRight, keyL, keyKp6}
    MoveKeysUp    = {keyUp,    keyK, keyKp8}
    MoveKeysDown  = {keyDown,  keyJ, keyKp2}

  # TODO these should be part of the map component event handler
  for ke in koi.keyBuf():
    case a.editMode:
    of emNormal:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      if ke.isKeyDown(keyLeft, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w - 10, h)
      elif ke.isKeyDown(keyRight, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w + 10, h)

      elif ke.isKeyDown(keyD):
        a.editMode = emExcavate
        a.setStatusMessage(IconPencil, "Excavate tunnel",
                           @[IconArrows, "draw"])
        actions.excavate(m, curX, curY, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        a.setStatusMessage(IconEraser, "Erase cells", @[IconArrows, "erase"])
        actions.eraseCell(m, curX, curY, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearGround
        a.setStatusMessage(IconEraser, "Clear floor",  @[IconArrows, "clear"])
        actions.setGround(m, curX, curY, gEmpty, um)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall
        a.setStatusMessage("", "Draw walls", @[IconArrows, "set/clear"])

      elif ke.isKeyDown(keyR):
        a.editMode = emDrawWallSpecial
        a.setStatusMessage("", "Draw wall special", @[IconArrows, "set/clear"])

      # TODO
#      elif ke.isKeyDown(keyW) and ke.mods == {mkAlt}:
#        actions.eraseCellWalls(m, curX, curY, um)

      elif ke.isKeyDown(key1):
        if m.getGround(curX, curY) == gClosedDoor:
          actions.toggleGroundOrientation(m, curX, curY, um)
          a.setFloorOrientationStatusMessage(
            m.getGroundOrientation(curX, curY)
          )
        else:
          let g = gClosedDoor
          actions.setGround(m, curX, curY, g, um)
          a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key2):
        if m.getGround(curX, curY) == gOpenDoor:
          actions.toggleGroundOrientation(m, curX, curY, um)
          a.setFloorOrientationStatusMessage(
            m.getGroundOrientation(curX, curY)
          )
        else:
          let g = gOpenDoor
          actions.setGround(m, curX, curY, g, um)
          a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key3):
        var g = m.getGround(curX, curY)
        g = if g == gPressurePlate: gHiddenPressurePlate else: gPressurePlate
        actions.setGround(m, curX, curY, g, um)
        a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key4):
        var g = m.getGround(curX, curY)
        if g >= gClosedPit and g <= gCeilingPit:
          g = Ground(ord(g) + 1)
          if g > gCeilingPit: g = gClosedPit
        else:
          g = gClosedPit
        actions.setGround(m, curX, curY, g, um)
        a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key5):
        var g = m.getGround(curX, curY)
        g = if g == gStairsDown: gStairsUp else: gStairsDown
        actions.setGround(m, curX, curY, g, um)
        a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key6):
        let g = gSpinner
        actions.setGround(m, curX, curY, g, um)
        a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(key7):
        let g = gTeleport
        actions.setGround(m, curX, curY, g, um)
        a.setStatusMessage(mkFloorMessage(g))

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if a.currWall > wIllusoryWall: dec(a.currWall)
        else: a.currWall = a.currWall.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if a.currWall < Wall.high: inc(a.currWall)
        else: a.currWall = wIllusoryWall

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true):
        um.undo(m)
        a.setStatusMessage(IconUndo, "Undid action")

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        um.redo(m)
        a.setStatusMessage(IconRedo, "Redid action")

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if a.copyBuf.isSome:
          actions.paste(m, curX, curY, a.copyBuf.get, um)
          a.setStatusMessage(IconPaste, "Pasted buffer")
        else:
          a.setStatusMessage(IconWarning, "Cannot paste, buffer is empty")

      elif ke.isKeyDown(keyP, {mkShift}):
        if a.copyBuf.isSome:
          a.editMode = emPastePreview
          a.setStatusMessage(IconTiles, "Paste preview",
                             @[IconArrows, "placement",
                             "Enter/P", "paste", "Esc", "exit"])
        else:
          a.setStatusMessage(IconWarning, "Cannot paste, buffer is empty")

      elif ke.isKeyDown(keyEqual, repeat=true):
        a.incZoomLevel()
        a.setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}")

      elif ke.isKeyDown(keyMinus, repeat=true):
        a.decZoomLevel()
        a.setStatusMessage(IconZoomOut,
          fmt"Zoomed out – level {dp.getZoomLevel()}")

      elif ke.isKeyDown(keyN, {mkCtrl}):
        g_newMapDialog_name = "Level 1"
        g_newMapDialog_cols = $a.map.cols
        g_newMapDialog_rows = $a.map.rows
        openDialog(NewMapDialogTitle)

      elif ke.isKeyDown(keyO, {mkCtrl}):
        let ext = MapFileExtension
        let filename = fileDialog(fdOpenFile,
                                  filters=fmt"Gridmonger Map (*.{ext}):{ext}")
        if filename != "":
          try:
            a.map = readMap(filename)
            initUndoManager(a.undoManager)
            resetCursorAndViewStart(a)
            updateViewStartAndCursorPosition(g_app)
            a.setStatusMessage(IconFloppy, "Map loaded")
          except CatchableError as e:
            # TODO log stracktrace?
            a.setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}")

      elif ke.isKeyDown(keyS, {mkCtrl}):
        let ext = MapFileExtension
        var filename = fileDialog(fdSaveFile,
                                  filters=fmt"Gridmonger Map (*.{ext}):{ext}")
        if filename != "":
          try:
            # TODO .grm suffix
            if not filename.endsWith(fmt".{ext}"):
              filename &= "." & ext
            writeMap(a.map, filename)
            a.setStatusMessage(IconFloppy, fmt"Map saved")
          except CatchableError as e:
            # TODO log stracktrace?
            a.setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}")

    of emExcavate, emEraseCell, emClearGround:
      proc handleMoveKey(dir: Direction, a) =
        if a.editMode == emExcavate:
          moveCursor(dir, a)
          actions.excavate(m, curX, curY, um)

        elif a.editMode == emEraseCell:
          moveCursor(dir, a)
          actions.eraseCell(m, curX, curY, um)

        elif a.editMode == emClearGround:
          moveCursor(dir, a)
          actions.setGround(m, curX, curY, gEmpty, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(South, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWall:
      proc handleMoveKey(dir: Direction, a) =
        if canSetWall(m, curX, curY, dir):
          let w = if m.getWall(curX, curY, dir) == wNone: wWall
                  else: wNone
          actions.setWall(m, curX, curY, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(South, a)

      elif ke.isKeyUp({keyW}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWallSpecial:
      proc handleMoveKey(dir: Direction, a) =
        if canSetWall(m, curX, curY, dir):
          let w = if m.getWall(curX, curY, dir) == a.currWall: wNone
                  else: a.currWall
          actions.setWall(m, curX, curY, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(West, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(East, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(North, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(South, a)

      elif ke.isKeyUp({keyR}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emSelectDraw:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      # TODO don't use win
      if   win.isKeyDown(keyD): a.selection.get[curX, curY] = true
      elif win.isKeyDown(keyE): a.selection.get[curX, curY] = false

      if   ke.isKeyDown(keyA, {mkCtrl}): a.selection.get.fill(true)
      elif ke.isKeyDown(keyD, {mkCtrl}): a.selection.get.fill(false)

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          x0: curX, y0: curY,
          rect: rectN(curX, curY, curX+1, curY+1),
          fillValue: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC):
        discard copySelection(a)
        exitSelectMode(a)
        a.setStatusMessage(IconCopy, "Copied to buffer")

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        a.setStatusMessage(IconCut, "Cut to buffer")

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

    of emSelectRect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      var x1, y1, x2, y2: Natural
      if a.selRect.get.x0 <= curX:
        x1 = a.selRect.get.x0
        x2 = curX+1
      else:
        x1 = curX
        x2 = a.selRect.get.x0 + 1

      if a.selRect.get.y0 <= curY:
        y1 = a.selRect.get.y0
        y2 = curY+1
      else:
        y1 = curY
        y2 = a.selRect.get.y0 + 1

      a.selRect.get.rect = rectN(x1, y1, x2, y2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.fillValue)
        a.selRect = none(SelectionRect)
        a.editMode = emSelectDraw

    of emPastePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(West, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(East, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(North, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(South, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(m, curX, curY, a.copyBuf.get, um)
        a.editMode = emNormal
        a.setStatusMessage(IconPaste, "Pasted buffer contents")

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        a.editMode = emNormal
        a.clearStatusMessage()
# }}}

# {{{ renderUI()
proc renderUI() =
  alias(a, g_app)
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  alias(vg, a.vg)

  # Current level dropdown
  a.currMapLevel = koi.dropdown(
    50, 45, 300, 24.0,
    items = @[
      "Level 1 - Legend of Darkmoor",
      "The Beginning",
      "The Dwarf Settlement",
      "You Only Scream Twice"
    ],
    tooltip = "Current map level",
    a.currMapLevel)

  # Map
  if dp.viewCols > 0 and dp.viewRows > 0:
    dp.cursorCol = a.cursorCol
    dp.cursorRow = a.cursorRow

    dp.selection = a.selection
    dp.selRect = a.selRect
    dp.pastePreview = if a.editMode == emPastePreview: a.copyBuf
                      else: none(CopyBuffer)

    drawMap(a.map, DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg))

  # Toolbar
  drawWallTool(a, winWidth - 60.0)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(a, statusBarY, winWidth.float)

# }}}
# {{{ renderFrame()
proc renderFrame(win: Window, doHandleEvents: bool = true) =
  alias(a, g_app)
  alias(vg, g_app.vg)
  alias(wnd, g_window)

  let
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

  # Clear background
  vg.beginPath()
  vg.rect(0, 0, winWidth.float, winHeight.float)
  vg.fillColor(gray(0.4))
  vg.fill()

  # Title bar
  renderTitleBar(a, winWidth.float)

  ######################################################

  updateViewStartAndCursorPosition(a)
  defineDialogs()

  if doHandleEvents:
    handleWindowDragEvents(a)
    handleMapEvents(a)

  renderUI()

  ######################################################

  # Window border
  vg.beginPath()
  vg.rect(0.5, 0.5, winWidth.float-1, winHeight.float-1)
  vg.strokeColor(gray(0.09))
  vg.strokeWidth(1.0)
  vg.stroke()

  koi.endFrame()
  vg.endFrame()

  glfw.swapBuffers(win)

  if wnd.fastRedrawFrameCounter > 0:
    dec(wnd.fastRedrawFrameCounter)
    if wnd.fastRedrawFrameCounter == 0:
      glfw.swapInterval(1)

# }}}
# {{{ framebufSizeCb()
proc framebufSizeCb(win: Window, size: tuple[w, h: int32]) =
  renderFrame(win, doHandleEvents=false)

# }}}

# {{{ Init & cleanup
proc createDefaultMapStyle(): MapStyle =
  var ms = new MapStyle
  ms.cellCoordsColor     = gray(0.9)
  ms.cellCoordsColorHi   = rgb(1.0, 0.75, 0.0)
  ms.cursorColor         = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor    = rgba(1.0, 0.65, 0.0, 0.2)
  ms.defaultFgColor      = gray(0.1)
  ms.groundColor         = gray(0.9)
  ms.gridColorBackground = gray(0.0, 0.3)
  ms.gridColorGround     = gray(0.0, 0.2)
  ms.mapBackgroundColor  = gray(0.0, 0.7)
  ms.mapOutlineColor     = gray(0.23)
  ms.selectionColor      = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor   = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms

proc initDrawMapParams(a) =
  alias(dp, a.drawMapParams)

  dp.drawOutline = true
  dp.drawCursorGuides = false


proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 800, h: 600)
  cfg.title = "Gridmonger v0.1"
  cfg.resizable = false
  cfg.visible = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.debugContext = true
  cfg.nMultiSamples = 4
  cfg.decorated = false
  cfg.floating = false

  when defined(macosx):
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  newWindow(cfg)


proc loadData(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add regular font.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add bold font.\n"

  let emojiFont = vg.createFont("emoji", "data/GridmongerIcons.ttf")
  if emojiFont == NoFont:
    quit "Could not load emoji font.\n"

  g_icon1 = vg.createImage("data/icon1.png")
  if g_icon1 == NoImage:
    quit fmt"Could not load icon1"

  discard addFallbackFont(vg, regularFont, emojiFont)
  discard addFallbackFont(vg, boldFont, emojiFont)


proc init(): Window =
  g_app = new AppContext

  glfw.initialize()

  var win = createWindow()
  g_app.win = win

  var flags = {nifStencilStrokes, nifDebug}
  g_app.vg = nvgInit(getProcAddress, flags)
  if g_app.vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(g_app.vg)

  setWindowTitle("Eye of the Beholder III")
  setWindowModifiedFlag(true)

  g_app.map = newMap(16, 16)
  g_app.mapStyle = createDefaultMapStyle()
  g_app.undoManager = newUndoManager[Map]()
  g_app.currWall = wIllusoryWall
  g_app.setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!")

  g_app.drawMapParams = new DrawMapParams
  initDrawMapParams(g_app)
  g_app.drawMapParams.setZoomLevel(DefaultZoomLevel)
  g_app.scrollMargin = 3

  koi.init(g_app.vg)
  win.framebufferSizeCb = framebufSizeCb
  glfw.swapInterval(1)

  win.pos = (150, 150)  # TODO for development
  wrapper.showWindow(win.getHandle())

  result = win


proc cleanup() =
  koi.deinit()
  nvgDeinit(g_app.vg)
  glfw.terminate()

# }}}

proc main() =
  let win = init()
  while not win.shouldClose:
    if koi.shouldRenderNextFrame():
      glfw.pollEvents()
    else:
      glfw.waitEvents()
    renderFrame(win)
  cleanup()

main()

# vim: et:ts=2:sw=2:fdm=marker
