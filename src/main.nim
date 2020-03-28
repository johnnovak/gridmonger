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

when not defined(DEBUG):
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
  MapTopPad    = 85.0
  MapBottomPad = 35.0

  BottomPaneHeight = 80.0

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
    emClearFloor,
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

    currSpecialWallIdx: Natural

    selection:      Option[Selection]
    selRect:        Option[SelectionRect]
    copyBuf:        Option[CopyBuffer]

    currMapLevel:   Natural
    statusIcon:     string
    statusMessage:  string
    statusCommands: seq[string]

    drawMapParams:     DrawMapParams
    toolbarDrawParams: DrawMapParams


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


proc renderTitleBar(winWidth: float, a) =
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
          (wnd.posX0, wnd.posY0) = ((mx - wnd.oldWidth*0.5).int32, 0)

          # Fake the last horizontal cursor position to be at the middle of
          # the restored window's width. This is needed so when we're in the
          # "else" branch on the next frame when dragging the restored window,
          # there won't be an unwanted window position jump.
          wnd.mx0 = wnd.oldWidth*0.5
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
proc setStatusMessage(icon, msg: string, commands: seq[string], a) =
  a.statusIcon = icon
  a.statusMessage = msg
  a.statusCommands = commands

proc setStatusMessage(icon, msg: string, a) =
  setStatusMessage(icon , msg, commands = @[], a)

proc setStatusMessage(msg: string, a) =
  setStatusMessage(icon = "", msg, commands = @[], a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar(y: float, winWidth: float, a) =
  alias(vg, a.vg)
  alias(m, a.map)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(gray(0.2))
  vg.fill()

  # Display current coords
  vg.setFont(14.0)

  let cursorPos = fmt"({m.rows-1 - a.cursorRow}, {a.cursorCol}, )"
  let tw = vg.textWidth(cursorPos)

  vg.fillColor(gray(0.6))
  vg.textAlign(haLeft, vaMiddle)
  discard vg.text(winWidth - tw - 7, ty, cursorPos)

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
  a.cursorRow = 0
  a.cursorCol = 0
  a.drawMapParams.viewStartRow = 0
  a.drawMapParams.viewStartCol = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.drawMapParams)

  let (winWidth, winHeight) = a.win.size

  let
    drawAreaHeight = winHeight - TitleBarHeight - StatusBarHeight -
                     MapTopPad - MapBottomPad - BottomPaneHeight

    drawAreaWidth = winWidth - MapLeftPad - MapRightPad

  dp.startX = MapLeftPad
  dp.startY = TitleBarHeight + MapTopPad

  dp.viewRows = min(dp.numDisplayableRows(drawAreaHeight), a.map.rows)
  dp.viewCols = min(dp.numDisplayableCols(drawAreaWidth), a.map.cols)

  dp.viewStartRow = min(max(a.map.rows - dp.viewRows, 0), dp.viewStartRow)
  dp.viewStartCol = min(max(a.map.cols - dp.viewCols, 0), dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  a.cursorRow = min(
    max(viewEndRow, dp.viewStartRow),
    a.cursorRow
  )
  a.cursorCol = min(
    max(viewEndCol, dp.viewStartCol),
    a.cursorCol
  )

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, a) =
  alias(dp, a.drawMapParams)

  var
    cx = a.cursorCol
    cy = a.cursorRow
    sx = dp.viewStartCol
    sy = dp.viewStartRow

  case dir:
  of dirE:
    cx = min(cx+1, a.map.cols-1)
    if cx - sx > dp.viewCols-1 - a.scrollMargin:
      sx = min(max(a.map.cols - dp.viewCols, 0), sx+1)

  of dirS:
    cy = min(cy+1, a.map.rows-1)
    if cy - sy > dp.viewRows-1 - a.scrollMargin:
      sy = min(max(a.map.rows - dp.viewRows, 0), sy+1)

  of dirW:
    cx = max(cx-1, 0)
    if cx < sx + a.scrollMargin:
      sx = max(sx-1, 0)

  of dirN:
    cy = max(cy-1, 0)
    if cy < sy + a.scrollMargin:
      sy = max(sy-1, 0)

  a.cursorRow = cy
  a.cursorCol = cx
  dp.viewStartRow = sy
  dp.viewStartCol = sx

# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelectDraw
  a.selection = some(newSelection(a.map.rows, a.map.cols))
  a.drawMapParams.drawCursorGuides = true
  setStatusMessage(IconSelection, "Mark selection",
                   @["D", "draw", "E", "erase", "R", "rectangle",
                     "Ctrl+A/D", "mark/unmark all", "C", "copy", "X", "cut",
                     "Esc", "exit"], a)

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
    for r in 0..<m.rows:
      for c in 0..<m.cols:
        m.eraseOrphanedWalls(r,c)

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
var
  g_newMapDialogOpen: bool
  g_newMapDialog_name: string
  g_newMapDialog_rows: string
  g_newMapDialog_cols: string

proc newMapDialog(a) =
  koi.beginDialog(350, 220, fmt"{IconNewFile}  New map")
  a.clearStatusMessage()

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
  koi.label(x, y, labelWidth, h, "Rows", gray(0.80), fontSize=14.0)
  g_newMapDialog_rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_rows
  )

  y = y + 30
  koi.label(x, y, labelWidth, h, "Columns", gray(0.80), fontSize=14.0)
  g_newMapDialog_cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", g_newMapDialog_cols
  )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(a) =
    initUndoManager(a.undoManager)
    # TODO number error checking
    let rows = parseInt(g_newMapDialog_rows)
    let cols = parseInt(g_newMapDialog_cols)
    a.map = newMap(rows, cols)
    resetCursorAndViewStart(a)
    updateViewStartAndCursorPosition(a)
    setStatusMessage(IconFile, fmt"New {rows}x{cols} map created", a)
    koi.closeDialog()
    g_newMapDialogOpen = false

  proc cancelAction(a) =
    koi.closeDialog()
    g_newMapDialogOpen = false


  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(a)

  koi.endDialog()

# }}}
# {{{ Edit note dialog
var
  g_editNoteDialogOpen: bool
  g_editNoteDialog_type: int
  g_editNoteDialog_customId: string
  g_editNoteDialog_note: string

proc editNoteDialog(a) =
  koi.beginDialog(450, 220, fmt"{IconComment}  Edit Note")
  a.clearStatusMessage()

  let
    dialogWidth = 450.0
    dialogHeight = 220.0
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Type", gray(0.80), fontSize=14.0)
  g_editNoteDialog_type = koi.radioButtons(
    x + labelWidth, y, 232, h,
    labels = @["Number", "Custom", "Comment"],
    tooltips = @["", "", ""],
    g_editNoteDialog_type
  )

  y = y + 40
  koi.label(x, y, labelWidth, h, "Note", gray(0.80), fontSize=14.0)
  g_editNoteDialog_note = koi.textField(
    x + labelWidth, y, 320.0, h, tooltip = "", g_editNoteDialog_note
  )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(a) =
    koi.closeDialog()
    var note = Note(
      kind: NoteKind(g_editNoteDialog_type),
      text: g_editNoteDialog_note
    )
    a.map.setNote(a.cursorRow, a.cursorCol, note)
    g_editNoteDialogOpen = false

  proc cancelAction(a) =
    koi.closeDialog()
    g_editNoteDialogOpen = false

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(a)

  koi.endDialog()

# }}}

# }}}

const SpecialWalls = @[
  wIllusoryWall,
  wInvisibleWall,
  wDoor,
  wLockedDoor,
  wArchway,
  wSecretDoor,
  wLever,
  wNiche,
  wStatue
]

proc drawWallTool(x, y: float, w: Wall, ctx: DrawMapContext) =
  case w
  of wNone:          discard
  of wWall:          drawSolidWallHoriz(x, y, ctx)
  of wIllusoryWall:  drawIllusoryWallHoriz(x, y, ctx)
  of wInvisibleWall: drawInvisibleWallHoriz(x, y, ctx)
  of wDoor:          drawDoorHoriz(x, y, ctx)
  of wLockedDoor:    drawLockedDoorHoriz(x, y, ctx)
  of wArchway:       drawArchwayHoriz(x, y, ctx)
  of wSecretDoor:    drawSecretDoorHoriz(x, y, ctx)
  of wLever:         discard
  of wNiche:         discard
  of wStatue:        discard

proc drawBottomPane(x, y: float, a) =
  alias(vg, a.vg)
  alias(m, a.map)
  alias(ms, a.mapStyle)

  let curRow = a.cursorRow
  let curCol = a.cursorCol

  let note = m.getNote(curRow, curCol)
  if note.isSome:
    let n = note.get

    vg.setFont(14.0)
    vg.fillColor(ms.fgColor)
    vg.textAlign(haLeft, vaMiddle)

    discard vg.text(x, y, n.text)


proc drawWallToolbar(x: float, a) =
  alias(vg, a.vg)
  alias(ms, a.mapStyle)
  alias(dp, a.toolbarDrawParams)

  dp.setZoomLevel(ms, 1)
  let ctx = DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg)

  let
    toolPad = 4.0
    w = dp.gridSize + toolPad*2
    yPad = 2.0

  var y = 100.0

  for i, wall in SpecialWalls.pairs:
    if i == a.currSpecialWallIdx:
      vg.fillColor(rgb(1.0, 0.7, 0))
    else:
      vg.fillColor(gray(0.6))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()

    drawWallTool(x+toolPad, y+toolPad + dp.gridSize*0.5, wall, ctx)
    y += w + yPad


# TODO
proc drawMarkerIconToolbar(x: float, a) =
  alias(vg, a.vg)
  alias(ms, a.mapStyle)
  alias(dp, a.toolbarDrawParams)

  dp.setZoomLevel(ms, 5)
  let ctx = DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg)

  let
    toolPad = 0.0
    w = dp.gridSize + toolPad*2
    yPad = 2.0

  var
    x = x
    y = 100.0

  for i, icon in MarkerIcons.pairs:
    if i > 0 and i mod 3 == 0:
      y = 100.0
      x += w + yPad

    vg.fillColor(gray(0.6))
    vg.beginPath()
    vg.rect(x, y, w, w)
    vg.fill()

    drawIcon(x+toolPad, y+toolPad, 0, 0, icon, ctx)
    y += w + yPad


# {{{ handleMapEvents()
proc handleMapEvents(a) =
  alias(curRow, a.cursorRow)
  alias(curCol, a.cursorCol)
  alias(um, a.undoManager)
  alias(m, a.map)
  alias(ms, a.mapStyle)
  alias(dp, a.drawMapParams)
  alias(win, a.win)

  proc mkFloorMessage(f: Floor): string =
    fmt"Set floor – {f}"

  proc setFloorOrientationStatusMessage(o: Orientation, a) =
    if o == Horiz:
      setStatusMessage(IconHorizArrows, "Floor orientation set to horizontal", a)
    else:
      setStatusMessage(IconVertArrows, "Floor orientation set to vertical", a)

  proc incZoomLevel(a) =
    incZoomLevel(ms, dp)
    updateViewStartAndCursorPosition(a)

  proc decZoomLevel(a) =
    decZoomLevel(ms, dp)
    updateViewStartAndCursorPosition(a)

  proc cycleFloor(f, first, last: Floor): Floor =
    if f >= first and f <= last:
      result = Floor(ord(f) + 1)
      if result > last: result = first
    else:
      result = first

  proc setFloor(first, last: Floor, a) =
    var f = m.getFloor(curRow, curCol)
    f = cycleFloor(f, first, last)
    let ot = m.guessFloorOrientation(curRow, curCol)
    actions.setOrientedFloor(m, curRow, curCol, f, ot, um)
    setStatusMessage(mkFloorMessage(f), a)


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
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      if ke.isKeyDown(keyLeft, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w - 10, h)
      elif ke.isKeyDown(keyRight, {mkCtrl}):
        let (w, h) = win.size
        win.size = (w + 10, h)

      elif ke.isKeyDown(keyD):
        a.editMode = emExcavate
        setStatusMessage(IconPencil, "Excavate tunnel",
                         @[IconArrows, "draw"], a)
        actions.excavate(m, curRow, curCol, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        setStatusMessage(IconEraser, "Erase cells", @[IconArrows, "erase"], a)
        actions.eraseCell(m, curRow, curCol, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearFloor
        setStatusMessage(IconEraser, "Clear floor",  @[IconArrows, "clear"], a)
        actions.setFloor(m, curRow, curCol, fEmpty, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(m, curRow, curCol, um)
        setFloorOrientationStatusMessage(m.getFloorOrientation(curRow, curCol), a)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall
        setStatusMessage("", "Draw walls", @[IconArrows, "set/clear"], a)

      elif ke.isKeyDown(keyR):
        a.editMode = emDrawWallSpecial
        setStatusMessage("", "Draw wall special", @[IconArrows, "set/clear"], a)

      # TODO
#      elif ke.isKeyDown(keyW) and ke.mods == {mkAlt}:
#        actions.eraseCellWalls(m, curRow, curCol, um)

      elif ke.isKeyDown(key1):
        setFloor(fDoor, fSecretDoor, a)

      elif ke.isKeyDown(key2):
        setFloor(fDoor, fSecretDoor, a)

      elif ke.isKeyDown(key3):
        setFloor(fPressurePlate, fHiddenPressurePlate, a)

      elif ke.isKeyDown(key4):
        setFloor(fClosedPit, fCeilingPit, a)

      elif ke.isKeyDown(key5):
        setFloor(fStairsDown, fStairsUp, a)

      elif ke.isKeyDown(key6):
        let f = fSpinner
        actions.setFloor(m, curRow, curCol, f, um)
        setStatusMessage(mkFloorMessage(f), a)

      elif ke.isKeyDown(key7):
        let f = fTeleport
        actions.setFloor(m, curRow, curCol, f, um)
        setStatusMessage(mkFloorMessage(f), a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if a.currSpecialWallIdx > 0: dec(a.currSpecialWallIdx)
        else: a.currSpecialWallIdx = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if a.currSpecialWallIdx < SpecialWalls.high: inc(a.currSpecialWallIdx)
        else: a.currSpecialWallIdx = 0

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true):
        um.undo(m)
        setStatusMessage(IconUndo, "Undid action", a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        um.redo(m)
        setStatusMessage(IconRedo, "Redid action", a)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if a.copyBuf.isSome:
          actions.paste(m, curRow, curCol, a.copyBuf.get, um)
          setStatusMessage(IconPaste, "Pasted buffer", a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyP, {mkShift}):
        if a.copyBuf.isSome:
          a.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrows, "placement",
                           "Enter/P", "paste", "Esc", "exit"], a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyEqual, repeat=true):
        incZoomLevel(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        decZoomLevel(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyN):
        if m.getFloor(curRow, curCol) == fNone:
          setStatusMessage(IconWarning, "Cannot attach note to empty cell", a)
        else:
          let note = m.getNote(curRow, curCol)
          if note.isSome:
            let n = note.get
            g_editNoteDialog_type = ord(n.kind)
            g_editNoteDialog_note = n.text
          else:
            g_editNoteDialog_type = ord(nkComment)
            g_editNoteDialog_note = ""
          g_editNoteDialogOpen = true

      elif ke.isKeyDown(keyN, {mkCtrl}):
        g_newMapDialog_name = "Level 1"
        g_newMapDialog_rows = $m.rows
        g_newMapDialog_cols = $m.cols
        g_newMapDialogOpen = true

      elif ke.isKeyDown(keyO, {mkCtrl}):
        when not defined(DEBUG):
          let ext = MapFileExtension
          let filename = fileDialog(fdOpenFile,
                                    filters=fmt"Gridmonger Map (*.{ext}):{ext}")
          if filename != "":
            try:
              m = readMap(filename)
              initUndoManager(um)
              resetCursorAndViewStart(a)
              updateViewStartAndCursorPosition(a)
              setStatusMessage(IconFloppy, fmt"Map '{filename}' loaded", a)
            except CatchableError as e:
              # TODO log stracktrace?
              setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)

      elif ke.isKeyDown(keyS, {mkCtrl}):
        when not defined(DEBUG):
          let ext = MapFileExtension
          var filename = fileDialog(fdSaveFile,
                                    filters=fmt"Gridmonger Map (*.{ext}):{ext}")
          if filename != "":
            try:
              if not filename.endsWith(fmt".{ext}"):
                filename &= "." & ext
              writeMap(m, filename)
              setStatusMessage(IconFloppy, fmt"Map saved", a)
            except CatchableError as e:
              # TODO log stracktrace?
              setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}", a)

    of emExcavate, emEraseCell, emClearFloor:
      proc handleMoveKey(dir: CardinalDir, a) =
        if a.editMode == emExcavate:
          moveCursor(dir, a)
          actions.excavate(m, curRow, curCol, um)

        elif a.editMode == emEraseCell:
          moveCursor(dir, a)
          actions.eraseCell(m, curRow, curCol, um)

        elif a.editMode == emClearFloor:
          moveCursor(dir, a)
          actions.setFloor(m, curRow, curCol, fEmpty, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(m, curRow, curCol, dir):
          let w = if m.getWall(curRow, curCol, dir) == wNone: wWall
                  else: wNone
          actions.setWall(m, curRow, curCol, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyW}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWallSpecial:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(m, curRow, curCol, dir):
          let curSpecWall = SpecialWalls[a.currSpecialWallIdx]
          let w = if m.getWall(curRow, curCol, dir) == curSpecWall: wNone
                  else: curSpecWall
          actions.setWall(m, curRow, curCol, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyR}):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emSelectDraw:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      # TODO don't use win
      if   win.isKeyDown(keyD): a.selection.get[curRow, curCol] = true
      elif win.isKeyDown(keyE): a.selection.get[curRow, curCol] = false

      if   ke.isKeyDown(keyA, {mkCtrl}): a.selection.get.fill(true)
      elif ke.isKeyDown(keyD, {mkCtrl}): a.selection.get.fill(false)

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          x0: curCol, y0: curRow,
          rect: rectN(curCol, curRow, curCol+1, curRow+1),
          selected: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC):
        discard copySelection(a)
        exitSelectMode(a)
        setStatusMessage(IconCopy, "Copied to buffer", a)

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconCut, "Cut to buffer", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

    of emSelectRect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      var x1, y1, x2, y2: Natural
      if a.selRect.get.x0 <= curCol:
        x1 = a.selRect.get.x0
        x2 = curCol+1
      else:
        x1 = curCol
        x2 = a.selRect.get.x0 + 1

      if a.selRect.get.y0 <= curRow:
        y1 = a.selRect.get.y0
        y2 = curRow+1
      else:
        y1 = curRow
        y2 = a.selRect.get.y0 + 1

      a.selRect.get.rect = rectN(x1, y1, x2, y2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.selected)
        a.selRect = none(SelectionRect)
        a.editMode = emSelectDraw

    of emPastePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(m, curRow, curCol, a.copyBuf.get, um)
        a.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

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

  # Clear background
  vg.beginPath()
  vg.rect(0, TitleBarHeight, winWidth.float, winHeight.float - TitleBarHeight)
  # TODO
  vg.fillColor(a.mapStyle.bgColor)
  vg.fill()

  # Current level dropdown
  a.currMapLevel = koi.dropdown(
    MapLeftPad, 45, 300, 24.0,   # TODO calc y
    items = @[
      "Level 1 - Legend of Darkmoor",
      "The Beginning",
      "The Dwarf Settlement",
      "You Only Scream Twice"
    ],
    tooltip = "Current map level",
    a.currMapLevel)

  # Map
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = a.cursorRow
    dp.cursorCol = a.cursorCol

    dp.selection = a.selection
    dp.selRect = a.selRect
    dp.pastePreview = if a.editMode == emPastePreview: a.copyBuf
                      else: none(CopyBuffer)

    drawMap(a.map, DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg))

  # Bottom pane
  drawBottomPane(MapLeftPad, winHeight - StatusBarHeight - BottomPaneHeight, a)

  # Toolbar
#  drawMarkerIconToolbar(winWidth - 400.0, a)
  drawWallToolBar(winWidth - 60.0, a)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, winWidth.float, a)

  # Dialogs
  if g_newMapDialogOpen:     newMapDialog(a)
  elif g_editNoteDialogOpen: editNoteDialog(a)

# }}}
# {{{ renderFrame()
proc renderFrame(win: Window, doHandleEvents: bool = true) =
  alias(a, g_app)
  alias(vg, g_app.vg)
  alias(wnd, g_window)

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
  renderTitleBar(winWidth.float, a)

  ######################################################

  updateViewStartAndCursorPosition(a)

  if doHandleEvents:
    handleWindowDragEvents(a)
    handleMapEvents(a)

  renderUI()

  ######################################################

  (winWidth, winHeight) = win.size

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
  ms.bgColor = gray(0.4)

  ms.bgCrosshatchEnabled       = true
  ms.bgCrosshatchColor         = gray(0.0, 0.4)
  ms.bgCrosshatchStrokeWidth   = 1.0
  ms.bgCrosshatchSpacingFactor = 2.0

  ms.coordsEnabled        = true
  ms.coordsColor          = gray(0.9)
  ms.coordsHighlightColor = rgb(1.0, 0.75, 0.0)

  ms.cursorColor          = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

  ms.gridStyle            = gsSolid
  ms.gridColorBackground  = gray(0.0, 0.2)
  ms.gridColorFloor       = gray(0.0, 0.22)

  ms.floorColor           = gray(0.9)
  ms.fgColor              = gray(0.1)
  ms.lightFgColor         = gray(0.6)
  ms.thinStroke           = false

  ms.outlineStyle         = osCell
  ms.outlineFillStyle     = ofsSolid
  ms.outlineOverscan      = false
  ms.outlineColor         = gray(0.25)
  ms.outlineWidthFactor   = 0.5

  ms.selectionColor       = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms


proc createLightMapStyle(): MapStyle =
  var ms = new MapStyle
#  ms.bgColor = rgb(248, 248, 244)
  ms.bgColor = rgb(182, 184, 184)

  ms.bgCrosshatchEnabled       = false
  ms.bgCrosshatchColor         = gray(0.0, 0.0)
  ms.bgCrosshatchStrokeWidth   = 1.0
  ms.bgCrosshatchSpacingFactor = 2.0

  ms.coordsEnabled        = false
  ms.coordsColor          = rgb(34, 32, 32)
  ms.coordsHighlightColor = rgb(34, 32, 32)

  ms.cursorColor          = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

  ms.gridStyle            = gsLoose
  ms.gridColorBackground  = gray(0.0, 0.0)
  ms.gridColorFloor       = gray(0.0, 0.22)

  ms.floorColor           = rgb(248, 248, 244)
  ms.fgColor              = rgb(45, 42, 42)
  ms.lightFgColor         = rgba(45, 42, 42, 70)
  ms.thinStroke           = true

  ms.outlineStyle         = osRoundedEdges
  ms.outlineFillStyle     = ofsHatched
  ms.outlineOverscan      = true
  ms.outlineColor         = rgb(154, 156, 156)
  ms.outlineWidthFactor   = 0.25

  ms.selectionColor       = rgba(1.0, 0.5, 0.5, 0.5)
  ms.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.5)
  result = ms


proc createSepiaMapStyle(): MapStyle =
  var ms = new MapStyle
  ms.bgColor = rgb(221, 204, 187)

  ms.bgCrosshatchColor         = gray(0.0, 0.15)
  ms.bgCrosshatchEnabled       = true
  ms.bgCrosshatchStrokeWidth   = 1.0
  ms.bgCrosshatchSpacingFactor = 3.0

  ms.coordsEnabled        = true
  ms.coordsColor          = gray(0.0, 0.4)
  ms.coordsHighlightColor = gray(0.0, 0.8)

  ms.cursorColor          = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

  ms.gridStyle            = gsSolid
  ms.gridColorBackground  = gray(0.0, 0.0)
  ms.gridColorFloor       = rgba(180, 168, 154, 150)

  ms.floorColor           = rgb(248, 248, 244)
  ms.fgColor              = rgb(67, 67, 63)
  ms.lightFgColor         = rgb(176, 167, 167)
  ms.thinStroke           = true

  ms.outlineStyle         = osSquareEdges
  ms.outlineFillStyle     = ofsSolid
  ms.outlineOverscan      = false
  ms.outlineColor         = rgb(180, 168, 154)
  ms.outlineWidthFactor   = 0.3

  ms.selectionColor       = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms


proc createGrimrock1MapStyle(): MapStyle =
  var ms = new MapStyle
  ms.bgColor = rgb(152, 124, 99)

  ms.bgCrosshatchColor         = gray(0.0, 0.15)
  ms.bgCrosshatchEnabled       = true
  ms.bgCrosshatchStrokeWidth   = 1.0
  ms.bgCrosshatchSpacingFactor = 3.0

  ms.coordsEnabled        = true
  ms.coordsColor          = gray(0.0, 0.4)
  ms.coordsHighlightColor = gray(0.0, 0.8)

  ms.cursorColor          = rgb(1.0, 0.65, 0.0)
  ms.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

  ms.gridStyle            = gsSolid
  ms.gridColorBackground  = gray(0.0, 0.0)
  ms.gridColorFloor       = rgb(148, 123, 102)

  ms.floorColor           = rgb(182, 155, 135)
  ms.fgColor              = rgb(60, 44, 28)
  ms.lightFgColor         = rgb(130, 114, 94)
  ms.thinStroke           = true

  ms.outlineStyle         = osNone
  ms.outlineFillStyle     = ofsSolid
  ms.outlineOverscan      = false
  ms.outlineColor         = rgb(180, 168, 154)
  ms.outlineWidthFactor   = 0.3

  ms.selectionColor       = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms


proc createGrimrock2MapStyle(): MapStyle =
  var ms = new MapStyle
  ms.bgColor = rgb(154, 130, 113)

  ms.bgCrosshatchColor         = gray(0.0, 0.25)
  ms.bgCrosshatchEnabled       = true
  ms.bgCrosshatchStrokeWidth   = 1.0
  ms.bgCrosshatchSpacingFactor = 3.0

  ms.coordsEnabled        = true
  ms.coordsColor          = gray(0.0, 0.4)
  ms.coordsHighlightColor = rgb(255, 180, 111)

  ms.cursorColor          = rgb(255, 180, 111)
  ms.cursorGuideColor     = rgba(255, 180, 111, 60)

  ms.gridStyle            = gsSolid
  ms.gridColorBackground  = gray(0.0, 0.0)
  ms.gridColorFloor       = rgb(148, 123, 102)

  ms.floorColor           = rgb(193, 180, 169)
  ms.fgColor              = rgb(49, 42, 36)
  ms.lightFgColor         = rgba(125, 113, 100, 220)
  ms.thinStroke           = true

  ms.outlineStyle         = osNone
  ms.outlineFillStyle     = ofsSolid
  ms.outlineOverscan      = false
  ms.outlineColor         = rgb(180, 168, 154)
  ms.outlineWidthFactor   = 0.3

  ms.selectionColor       = rgba(1.0, 0.5, 0.5, 0.4)
  ms.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.4)
  result = ms



proc initDrawMapParams(a) =
  alias(dp, a.drawMapParams)

  dp.drawCursorGuides = false


proc createWindow(): Window =
  var cfg = DefaultOpenglWindowConfig
  cfg.size = (w: 960, h: 1040)
#  cfg.size = (w: 600, h: 400)
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

  discard addFallbackFont(vg, regularFont, emojiFont)
  discard addFallbackFont(vg, boldFont, emojiFont)


# TODO clean up
proc init(): Window =
  alias(a, g_app)

  a = new AppContext

  glfw.initialize()

  var win = createWindow()
  a.win = win

  var flags = {nifStencilStrokes, nifDebug, nifAntialias}

  a.vg = nvgInit(getProcAddress, flags)
  if a.vg == nil:
    quit "Error creating NanoVG context"

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  loadData(a.vg)

  setWindowTitle("Eye of the Beholder III")
  setWindowModifiedFlag(true)

  a.map = newMap(16, 16)
  a.mapStyle = createDefaultMapStyle()
#  a.mapStyle = createLightMapStyle()
#  a.mapStyle = createSepiaMapStyle()
#  a.mapStyle = createGrimrock1MapStyle()
#  a.mapStyle = createGrimrock2MapStyle()
  a.undoManager = newUndoManager[Map]()
  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  a.drawMapParams = new DrawMapParams
  initDrawMapParams(a)
  a.drawMapParams.setZoomLevel(a.mapStyle, DefaultZoomLevel)
  a.scrollMargin = 3

  var
    (winWidth, winHeight) = win.size
    (fbWidth, fbHeight) = win.framebufferSize
    pxRatio = fbWidth / winWidth

  a.drawMapParams.renderLineHatchPatterns(a.vg, pxRatio, a.mapStyle.fgColor)

  a.toolbarDrawParams = a.drawMapParams.deepCopy
  a.toolbarDrawParams.setZoomLevel(a.mapStyle, 1)

  a.map = readMap("EOB III - Crystal Tower L2.grm")
#  a.map = readMap("drawtest.grm")

  koi.init(a.vg)
  win.framebufferSizeCb = framebufSizeCb
  glfw.swapInterval(1)

  win.pos = (960, 0)  # TODO for development
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
