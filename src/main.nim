import algorithm
import lenientops
import options
import os
import strformat
import strutils

import glad/gl
import glfw
import koi
import nanovg
when not defined(DEBUG): import osdialog

import actions
import common
import csdwindow
import drawmap
import map
import persistence
import selection
import theme
import undomanager
import utils


# {{{ Constants
const
  ThemesDir = "themes"

  DefaultZoomLevel = 5

  StatusBarHeight = 26.0

  MapLeftPad           = 50.0
  MapRightPad          = 120.0
  MapTopPadCoords      = 85.0
  MapBottomPadCoords   = 40.0
  MapTopPadNoCoords    = 65.0
  MapBottomPadNoCoords = 10.0

  NotesPaneTopPad = 10.0
  NotesPaneHeight = 40.0
  NotesPaneBottomPad = 10.0

# }}}
# {{{ AppContext
type
  EditMode* = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearFloor,
    emSelect,
    emSelectRect
    emPastePreview

  AppContext = ref object
    # Context
    win:            CSDWindow
    vg:             NVGContext

    # Dependencies
    undoManager:    UndoManager[Map]

    # Document (TODO group under 'doc'?)
    map:            Map

    # Options (TODO group under 'opts'?)
    scrollMargin:   Natural
    mapStyle:       MapStyle

    # UI state (TODO group under 'ui'?)
    uiStyle:        UIStyle

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

    mapTopPad:      float
    mapBottomPad:   float

    showNotesPane:  bool

    oldPaperPattern: Paint

    # Themes
    themeNames:     seq[string]
    currThemeIndex: Natural
    nextThemeIndex: Option[Natural]
    themeReloaded:  bool

    # Dialogs
    newMapDialog:   NewMapDialogParams
    editNoteDialog: EditNoteDialogParams

    # Images
    oldPaperImage:  Image


  NewMapDialogParams = object
    isOpen:   bool
    name:     string
    rows:     string
    cols:     string

  EditNoteDialogParams = object
    isOpen:   bool
    editMode: bool
    row:      Natural
    col:      Natural
    kind:     NoteKind
    index:    Natural
    customId: string
    text:     string


var g_app: AppContext

using a: var AppContext

# }}}

# {{{ Theme support
proc searchThemes(a) =
  for path in walkFiles(fmt"{ThemesDir}/*.cfg"):
    let (_, name, _) = splitFile(path)
    a.themeNames.add(name)
  sort(a.themeNames)

proc findThemeIndex(name: string, a): int =
  for i, n in a.themeNames:
    if n == name:
      return i
  return -1

proc loadTheme(index: Natural, a) =
  let name = a.themeNames[index]
  (a.uiStyle, a.mapStyle) = loadTheme(fmt"{ThemesDir}/{name}.cfg")
  a.currThemeIndex = index

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

  let cursorPos = fmt"({m.rows-1 - a.cursorRow}, {a.cursorCol})"
  let tw = vg.textWidth(cursorPos)

  vg.fillColor(gray(0.6))
  vg.textAlign(haLeft, vaMiddle)
  discard vg.text(winWidth - tw - 7, ty, cursorPos)

  vg.scissor(0, y, winWidth - tw - 15, StatusBarHeight)

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

  dp.startX = MapLeftPad
  dp.startY = TitleBarHeight + a.mapTopPad

  var drawAreaHeight = winHeight - TitleBarHeight - StatusBarHeight -
                       a.mapTopPad - a.mapBottomPad

  if a.showNotesPane:
   drawAreaHeight -= NotesPaneTopPad + NotesPaneHeight + NotesPaneBottomPad

  let
    drawAreaWidth = winWidth - MapLeftPad - MapRightPad

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
# {{{ showCellCoords()
proc showCellCoords(show: bool, a) =
  alias(dp, a.drawMapParams)

  if show:
    a.mapTopPad = MapTopPadCoords
    a.mapBottomPad = MapBottomPadCoords
    dp.drawCellCoords = true
  else:
    a.mapTopPad = MapTopPadNoCoords
    a.mapBottomPad = MapBottomPadNoCoords
    dp.drawCellCoords = false

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
# {{{ setSelectModeSelectMessage()
proc setSelectModeSelectMessage(a) =
  setStatusMessage(IconSelection, "Mark selection",
                   @["D", "draw", "E", "erase",
                     "R", "add rect", "S", "sub rect",
                     "A", "mark all", "U", "unmark all",
                     "Ctrl", "actions"], a)
# }}}
# {{{ setSelectModeActionMessage()
proc setSelectModeActionMessage(a) =
  setStatusMessage(IconSelection, "Mark selection",
                   @["Ctrl+C", "copy", "Ctrl+X", "cut",
                     "Ctrl+E", "erase", "Ctrl+F", "fill",
                     "Ctrl+S", "surround"], a)
# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  a.editMode = emSelect
  a.selection = some(newSelection(a.map.rows, a.map.cols))
  a.drawMapParams.drawCursorGuides = true
  setSelectModeSelectMessage(a)

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.editMode = emNormal
  a.selection = Selection.none
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

# {{{ drawNotesPane()
proc drawNotesPane(x, y, w, h: float, a) =
  alias(vg, a.vg)
  alias(m, a.map)
  alias(ms, a.mapStyle)

  let curRow = a.cursorRow
  let curCol = a.cursorCol

  if a.editMode != emPastePreview and m.hasNote(curRow, curCol):
    let note = m.getNote(curRow, curCol)

    case note.kind
    of nkIndexed:
      drawIndexedNote(x-40, y-12, note.index, 36,
                      bgColor=ms.notePaneBackgroundColor,
                      fgColor=ms.notePaneTextColor, vg)

    of nkCustomId:
      vg.fillColor(ms.notePaneTextColor)
      vg.setFont(18.0, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-22, y-2, note.customId)

    of nkComment:
      vg.fillColor(ms.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-2, IconComment)

    vg.fillColor(ms.notePaneTextColor)
    vg.setFont(14.5, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.4)
    vg.scissor(x, y, w, h)
    vg.textBox(x, y, w, note.text)
    vg.resetScissor()


# }}}
# {{{ drawWallToolbar
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

proc drawWallToolbar(x: float, a) =
  alias(vg, a.vg)
  alias(ms, a.mapStyle)
  alias(dp, a.toolbarDrawParams)

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

# }}}
# {{{ drawMarkerIcons()
proc drawMarkerIcons(x: float, a) =
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

# }}}

# {{{ Dialogs

# {{{ New map dialog
proc newMapDialog(dlg: var NewMapDialogParams, a) =
  let
    dialogWidth = 350.0
    dialogHeight = 220.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  New map")
  a.clearStatusMessage()

  let
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Name", gray(0.80), fontSize=14.0)
  dlg.name = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.name
  )

  y = y + 50
  koi.label(x, y, labelWidth, h, "Rows", gray(0.80), fontSize=14.0)
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.rows
  )

  y = y + 30
  koi.label(x, y, labelWidth, h, "Columns", gray(0.80), fontSize=14.0)
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.cols
  )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(dlg: var NewMapDialogParams, a) =
    initUndoManager(a.undoManager)
    # TODO number error checking
    let rows = parseInt(dlg.rows)
    let cols = parseInt(dlg.cols)
    a.map = newMap(rows, cols)
    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, fmt"New {rows}x{cols} map created", a)
    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var NewMapDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false


  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(dlg, a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit note dialog

proc editNoteDialog(dlg: var EditNoteDialogParams, a) =
  let
    dialogWidth = 470.0
    dialogHeight = 320.0
    title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCommentInv}  {title}")
  a.clearStatusMessage()

  let
    h = 24.0
    labelWidth = 80.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Type", gray(0.80), fontSize=14.0)
  dlg.kind = NoteKind(
    koi.radioButtons(
      x + labelWidth, y, 250, h,
      labels = @["Number", "Custom ID", "Comment"],
      tooltips = @["", "", ""],
      ord(dlg.kind)
    )
  )
  y += 40

  koi.label(x, y, labelWidth, h, "Note", gray(0.80), fontSize=14.0)
  dlg.text = koi.textField(
    x + labelWidth, y, 320.0, h, tooltip = "", dlg.text
  )
  y = y + 32

  if dlg.kind == nkCustomId:
    koi.label(x, y, labelWidth, h, "Custom ID", gray(0.80), fontSize=14.0)
    dlg.customId = koi.textField(
      x + labelWidth, y, 50.0, h, tooltip = "", dlg.customId
    )

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(dlg: var EditNoteDialogParams, a) =
    var note = Note(
      kind: dlg.kind,
      text: dlg.text
    )
    if note.kind == nkCustomId:
      note.customId = dlg.customId

    actions.setNote(a.map, dlg.row, dlg.col, note, a.undoManager)

    setStatusMessage(IconComment, "Set cell note", a)
    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var EditNoteDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  for ke in koi.keyBuf():
    if   ke.action == kaDown and ke.key == keyEscape: cancelAction(dlg, a)
    elif ke.action == kaDown and ke.key == keyEnter:  okAction(dlg, a)

  koi.endDialog()

# }}}

# }}}

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
        if um.canUndo():
          let actionName = um.undo(m)
          setStatusMessage(IconUndo, fmt"Undid action: {actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to undo", a)


      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true):
        if um.canRedo():
          let actionName = um.redo(m)
          setStatusMessage(IconRedo, fmt"Redid action: {actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to redo", a)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)
        koi.setFramesLeft()

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
          alias(dlg, a.editNoteDialog)
          dlg.row = curRow
          dlg.col = curCol

          if m.hasNote(curRow, curCol):
            let note = m.getNote(curRow, curCol)
            dlg.editMode = true
            dlg.kind = note.kind
            dlg.text = note.text

            if note.kind == nkIndexed:
              dlg.index = note.index

            if note.kind == nkCustomId:
              dlg.customId = note.customId
            else:
              dlg.customId = ""

          else:
            dlg.editMode = false
            dlg.customId = ""
            dlg.text = ""

          dlg.isOpen = true

      elif ke.isKeyDown(keyN, {mkShift}):
        if m.getFloor(curRow, curCol) == fNone:
          setStatusMessage(IconWarning, "No note to delete in cell", a)
        else:
          actions.eraseNote(a.map, curRow, curCol, a.undoManager)
          setStatusMessage(IconEraser, "Note erased", a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        alias(dlg, a.newMapDialog)
        dlg.name = "Level 1"
        dlg.rows = $m.rows
        dlg.cols = $m.cols
        dlg.isOpen = true

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
              filename = addFileExt(filename, ext)
              writeMap(m, filename)
              setStatusMessage(IconFloppy, fmt"Map saved", a)
            except CatchableError as e:
              # TODO log stracktrace?
              setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}", a)

      elif ke.isKeyDown(keyR, {mkAlt,mkCtrl}):
        a.nextThemeIndex = a.currThemeIndex.some
        koi.setFramesLeft()

      elif ke.isKeyDown(keyPageUp, {mkAlt,mkCtrl}):
        var i = a.currThemeIndex
        if i == 0: i = a.themeNames.high else: dec(i)
        a.nextThemeIndex = i.some
        koi.setFramesLeft()

      elif ke.isKeyDown(keyPageDown, {mkAlt,mkCtrl}):
        var i = a.currThemeIndex
        inc(i)
        if i > a.themeNames.high: i = 0
        a.nextThemeIndex = i.some
        koi.setFramesLeft()

      # Toggle options
      elif ke.isKeyDown(keyC, {mkAlt}):
        var state: string
        if dp.drawCellCoords:
          showCellCoords(false, a)
          state = "off"
        else:
          showCellCoords(true, a)
          state = "on"

        updateViewStartAndCursorPosition(a)
        setStatusMessage(fmt"Cell coordinates turned {state}", a)

      elif ke.isKeyDown(keyN, {mkAlt}):
        if a.showNotesPane:
          setStatusMessage(fmt"Notes pane shown", a)
          a.showNotesPane = false
        else:
          setStatusMessage(fmt"Notes pane hidden", a)
          a.showNotesPane = true

        updateViewStartAndCursorPosition(a)

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

    of emSelect:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      if win.isKeyDown(keyLeftControl) or win.isKeyDown(keyRightControl):
        setSelectModeActionMessage(a)
      else:
        setSelectModeSelectMessage(a)

      # TODO don't use win
      if   win.isKeyDown(keyD): a.selection.get[curRow, curCol] = true
      elif win.isKeyDown(keyE): a.selection.get[curRow, curCol] = false

      if   ke.isKeyDown(keyA): a.selection.get.fill(true)
      elif ke.isKeyDown(keyU): a.selection.get.fill(false)

      if ke.isKeyDown({keyR, keyS}):
        a.editMode = emSelectRect
        a.selRect = some(SelectionRect(
          startRow: curRow,
          startCol: curCol,
          rect: rectN(curRow, curCol, curRow+1, curCol+1),
          selected: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown(keyC, {mkCtrl}):
        discard copySelection(a)
        exitSelectMode(a)
        setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isKeyDown(keyX, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconCut, "Cut selection to buffer", a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isKeyDown(keyF, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.fillSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconPencil, "Filled selection", a)

      elif ke.isKeyDown(keyS, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.surroundSelection(m, a.copyBuf.get.selection, bbox.get, um)
        exitSelectMode(a)
        setStatusMessage(IconPencil, "Surrounded selection with walls", a)

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

      var r1,c1, r2,c2: Natural
      if a.selRect.get.startRow <= curRow:
        r1 = a.selRect.get.startRow
        r2 = curRow+1
      else:
        r1 = curRow
        r2 = a.selRect.get.startRow + 1

      if a.selRect.get.startCol <= curCol:
        c1 = a.selRect.get.startCol
        c2 = curCol+1
      else:
        c1 = curCol
        c2 = a.selRect.get.startCol + 1

      a.selRect.get.rect = rectN(r1,c1, r2,c2)

      if ke.isKeyUp({keyR, keyS}):
        a.selection.get.fill(a.selRect.get.rect, a.selRect.get.selected)
        a.selRect = SelectionRect.none
        a.editMode = emSelect

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

# {{{ getPxRatio()
proc getPxRatio(a): float =
  let
    (winWidth, _) = a.win.size
    (fbWidth, _) = a.win.framebufferSize
  result = fbWidth / winWidth

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

  # TODO extend logic for other images
  if a.uiStyle.backgroundImage == "old-paper":
    vg.fillPaint(a.oldPaperPattern)
  else:
    vg.fillColor(a.uiStyle.backgroundColor)
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
                      else: CopyBuffer.none

    drawMap(a.map, DrawMapContext(ms: a.mapStyle, dp: dp, vg: a.vg))

  if a.showNotesPane:
    drawNotesPane(
      x = MapLeftPad,
      y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
      w = winWidth - MapLeftPad*2,  # TODO
      h = NotesPaneHeight,
      a
    )

  # Toolbar
#  drawMarkerIconToolbar(winWidth - 400.0, a)
  drawWallToolBar(winWidth - 60.0, a)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, winWidth.float, a)

  # Dialogs
  if a.newMapDialog.isOpen:     newMapDialog(a.newMapDialog, a)
  elif a.editNoteDialog.isOpen: editNoteDialog(a.editNoteDialog, a)

# }}}
# {{{ renderFramePre()
proc renderFramePre(win: CSDWindow) =
  alias(a, g_app)

  if a.nextThemeIndex.isSome:
    let themeIndex = a.nextThemeIndex.get
    a.themeReloaded = themeIndex == a.currThemeIndex
    loadTheme(themeIndex, a)
    a.drawMapParams.initDrawMapParams(a.mapStyle, a.vg, getPxRatio(a))
    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message

# }}}
# {{{ renderFrame()
proc renderFrame(win: CSDWindow, doHandleEvents: bool = true) =
  alias(a, g_app)

  if a.nextThemeIndex.isSome:
    let themeName = a.themeNames[a.currThemeIndex]
    if a.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
    else:
      setStatusMessage(fmt"Switched to '{themeName}' theme", a)
    a.nextThemeIndex = Natural.none

  updateViewStartAndCursorPosition(a)

  if doHandleEvents:
    handleMapEvents(a)

  renderUI()

# }}}

# {{{ Init & cleanup
proc initDrawMapParams(a) =
  alias(dp, a.drawMapParams)
  dp = newDrawMapParams()
  dp.drawCellCoords   = true
  dp.drawCursorGuides = false
  dp.initDrawMapParams(a.mapStyle, a.vg, getPxRatio(a))


proc loadImages(vg: NVGContext, a) =
  let img = vg.createImage("data/old-paper.jpg", {ifRepeatX, ifRepeatY})

  # TODO use exceptions instead
  if img == NoImage:
    quit "Could not load old paper image.\n"

  let (w, h) = vg.imageSize(img)
  a.oldPaperPattern = vg.imagePattern(0, 0, w.float, h.float, angle=0,
                                      img, alpha=1.0)


proc loadFonts(vg: NVGContext) =
  let regularFont = vg.createFont("sans", "data/Roboto-Regular.ttf")
  if regularFont == NoFont:
    quit "Could not add regular font.\n"

  let boldFont = vg.createFont("sans-bold", "data/Roboto-Bold.ttf")
  if boldFont == NoFont:
    quit "Could not add bold font.\n"

  let blackFont = vg.createFont("sans-black", "data/Roboto-Black.ttf")
  if blackFont == NoFont:
    quit "Could not add black font.\n"

  let iconFont = vg.createFont("icon", "data/GridmongerIcons.ttf")
  if iconFont == NoFont:
    quit "Could not load icon font.\n"

  discard addFallbackFont(vg, boldFont, iconFont)
  discard addFallbackFont(vg, blackFont, iconFont)


# TODO clean up
proc initGfx(): (CSDWindow, NVGContext) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    quit "Error initialising OpenGL"

  let vg = nvgInit(getProcAddress, {nifStencilStrokes, nifAntialias})
  if vg == nil:
    quit "Error creating NanoVG context"

  koi.init(vg)

  result = (win, vg)


proc initApp(win: CSDWindow, vg: NVGContext) =
  alias(a, g_app)

  a = new AppContext
  a.win = win
  a.vg = vg
  a.undoManager = newUndoManager[Map]()

  loadFonts(vg)
  loadImages(vg, a)

  searchThemes(a)
  var themeIndex = findThemeIndex("oldpaper", a)
  if themeIndex == -1:
    themeIndex = 0
  loadTheme(themeIndex, a)

  initDrawMapParams(a)
  a.drawMapParams.setZoomLevel(a.mapStyle, DefaultZoomLevel)
  a.scrollMargin = 3

  a.toolbarDrawParams = a.drawMapParams.deepCopy
  a.toolbarDrawParams.setZoomLevel(a.mapStyle, 1)

  showCellCoords(true, a)
  a.showNotesPane = true

  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

#  a.map = newMap(16, 16)
  a.map = readMap("EOB III - Crystal Tower L2 notes.grm")
#  a.map = readMap("drawtest.grm")
#  a.map = readMap("notetest.grm")
#  a.map = readMap("pool-of-radiance-library.grm")
#  a.map = readMap("library.grm")

  a.win.renderFramePreCb = renderFramePre
  a.win.renderFrameCb = renderFrame

  a.win.title = "Eye of the Beholder III"
  a.win.modified = true
  # TODO for development
  a.win.size = (960, 1040)
  a.win.pos = (960, 0)
#  a.win.size = (700, 900)
#  a.win.pos = (900, 0)
  a.win.show()


proc cleanup() =
  koi.deinit()
  nvgDeinit(g_app.vg)
  glfw.terminate()

# }}}
# {{{ main()
proc main() =
  let (win, vg) = initGfx()
  initApp(win, vg)

  while not g_app.win.shouldClose:
    if koi.shouldRenderNextFrame():
      glfw.pollEvents()
    else:
      glfw.waitEvents()
    csdRenderFrame(g_app.win)
  cleanup()
# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
