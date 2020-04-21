import algorithm
import lenientops
import math
import options
import os
import sequtils
import strformat
import strutils
import tables

import glad/gl
import glfw
import koi
import nanovg
when not defined(DEBUG): import osdialog

import actions
import bitable
import common
import csdwindow
import drawlevel
import icons
import level
import map
import persistence
import rect
import selection
import theme
import undomanager
import utils


# {{{ Constants
const
  ThemesDir = "themes"

  DefaultZoomLevel = 9
  CursorJump = 5

  StatusBarHeight         = 26.0

  LevelTopPad_Coords      = 85.0
  LevelRightPad_Coords    = 50.0
  LevelBottomPad_Coords   = 40.0
  LevelLeftPad_Coords     = 50.0

  LevelTopPad_NoCoords    = 65.0
  LevelRightPad_NoCoords  = 28.0
  LevelBottomPad_NoCoords = 10.0
  LevelLeftPad_NoCoords   = 28.0

  NotesPaneHeight         = 60.0
  NotesPaneTopPad         = 10.0
  NotesPaneRightPad       = 110.0
  NotesPaneBottomPad      = 10.0
  NotesPaneLeftPad        = 20.0

  ToolsPaneWidth          = 60.0
  ToolsPaneTopPad         = 91.0
  ToolsPaneBottomPad      = 30.0


const
  MapFileExt = "grm"
  GridmongerMapFileFilter = fmt"Gridmonger Map (*.{MapFileExt}):{MapFileExt}"

# }}}
# {{{ AppContext
type
  AppContext = ref object
    win:         CSDWindow
    vg:          NVGContext

    doc:         Document
    opt:         Options
    ui:          UI
    theme:       Theme
    dialog:      Dialog

    shouldClose: bool


  Document = object
    filename:          string
    map:               Map
    levelStyle:        LevelStyle
    undoManager:       UndoManager[Map, UndoStateData]

  Options = object
    scrollMargin:      Natural
    showNotesPane:     bool
    showToolsPane:     bool

    drawTrail:         bool
    walkMode:          bool
    wasdMode:          bool


  UI = object
    style:             UIStyle
    cursor:            Location
    cursorOrient:      CardinalDir
    editMode:          EditMode

    selection:         Option[Selection]
    selRect:           Option[SelectionRect]
    copyBuf:           Option[SelectionBuffer]
    nudgeBuf:          Option[SelectionBuffer]

    statusIcon:        string
    statusMessage:     string
    statusCommands:    seq[string]

    currSpecialWall:   Natural
    currFloorColor:    Natural

    levelTopPad:       float
    levelRightPad:     float
    levelBottomPad:    float
    levelLeftPad:      float

    linkSrcLocation:   Location

    drawLevelParams:   DrawLevelParams
    toolbarDrawParams: DrawLevelParams

    levelDrawAreaWidth:  float
    levelDrawAreaHeight: float

    oldPaperPattern:   Paint

    aboutButtonStyle:  ButtonStyle


  EditMode* = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearFloor,
    emSelect,
    emSelectRect
    emPastePreview,
    emNudgePreview,
    emSetTeleportDestination

  Theme = object
    themeNames:           seq[string]
    currThemeIndex:       Natural
    nextThemeIndex:       Option[Natural]
    themeReloaded:        bool
    levelDropdownStyle:   DropdownStyle

  Dialog = object
    saveDiscardDialog:    SaveDiscardDialogParams

    newMapDialog:         NewMapDialogParams
    editMapPropsDialog:   EditMapPropsDialogParams

    newLevelDialog:       NewLevelDialogParams
    editLevelPropsDialog: EditLevelPropsParams
    editNoteDialog:       EditNoteDialogParams
    resizeLevelDialog:    ResizeLevelDialogParams

  SaveDiscardDialogParams = object
    isOpen:       bool
    action:       proc (a: var AppContext)

  NewMapDialogParams = object
    isOpen:       bool
    name:         string

  EditMapPropsDialogParams = object
    isOpen:       bool
    name:         string

  NewLevelDialogParams = object
    isOpen:       bool
    locationName: string
    levelName:    string
    elevation:    string
    rows:         string
    cols:         string

  EditLevelPropsParams = object
    isOpen:       bool
    locationName: string
    levelName:    string
    elevation:    string

  EditNoteDialogParams = object
    isOpen:       bool
    editMode:     bool
    row:          Natural
    col:          Natural
    kind:         NoteKind
    index:        Natural
    indexColor:   Natural
    customId:     string
    icon:         Natural
    text:         string

  ResizeLevelDialogParams = object
    isOpen:       bool
    rows:         string
    cols:         string
    anchor:       ResizeAnchor

  ResizeAnchor = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


var g_app: AppContext

using a: var AppContext

# }}}
# {{{ Keyboard shortcuts

type AppShortcut = enum
  scAccept,
  scCancel,
  scDiscard,

# TODO some shortcuts win/mac specific?
let g_appShortcuts = {

  scAccept:       @[mkKeyShortcut(keyEnter,         {}),
                    mkKeyShortcut(keyKpEnter,       {})],

  scCancel:       @[mkKeyShortcut(keyEscape,        {}),
                    mkKeyShortcut(keyLeftBracket,   {mkCtrl})],

  scDiscard:      @[mkKeyShortcut(keyD,             {mkAlt})],

}.toTable

# }}}
# {{{ Misc
const SpecialWalls = @[
  wIllusoryWall,
  wInvisibleWall,
  wDoor,
  wLockedDoor,
  wArchway,
  wSecretDoor,
  wLeverSW,
  wNicheSW,
  wStatueSW,
  wKeyhole
]

var DialogWarningLabelStyle = koi.getDefaultLabelStyle()
DialogWarningLabelStyle.fontSize = 14
DialogWarningLabelStyle.color = rgb(1.0, 0.4, 0.4)
DialogWarningLabelStyle.align = haLeft

# }}}

# {{{ mapHasLevels()
proc mapHasLevels(a): bool =
  a.doc.map.levels.len > 0

# }}}
# {{{ getCurrSortedLevelIdx()
proc getCurrSortedLevelIdx(a): Natural =
  a.doc.map.findSortedLevelIdxByLevelIdx(a.ui.cursor.level)

# }}}
# {{{ getCurrLevel()
# TODO convert to template
proc getCurrLevel(a): Level =
  a.doc.map.levels[a.ui.cursor.level]

# }}}
# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  a.ui.statusIcon = NoIcon
  a.ui.statusMessage = ""
  a.ui.statusCommands = @[]

# }}}
# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string], a) =
  a.ui.statusIcon = icon
  a.ui.statusMessage = msg
  a.ui.statusCommands = commands

proc setStatusMessage(icon, msg: string, a) =
  setStatusMessage(icon, msg, commands = @[], a)

proc setStatusMessage(msg: string, a) =
  setStatusMessage(NoIcon, msg, commands = @[], a)

# }}}
# {{{ drawStatusBar()
proc drawStatusBar(y: float, winWidth: float, a) =
  alias(vg, a.vg)
  alias(s, a.ui.style.statusBarStyle)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.save()

  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(s.backgroundColor)
  vg.fill()

  # Display current coords
  vg.setFont(14.0)

  if mapHasLevels(a):
    let l = getCurrLevel(a)
    let cursorPos = fmt"({l.rows-1 - a.ui.cursor.row}, {a.ui.cursor.col})"
    let tw = vg.textWidth(cursorPos)

    vg.fillColor(s.coordsColor)
    vg.textAlign(haLeft, vaMiddle)
    discard vg.text(winWidth - tw - 7, ty, cursorPos)

    vg.intersectScissor(0, y, winWidth - tw - 15, StatusBarHeight)

  # Display icon & message
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 13
    CommandTextPadX = 10

  var x = 10.0

  vg.fillColor(s.textColor)
  discard vg.text(IconPosX, ty, a.ui.statusIcon)

  let tx = vg.text(MessagePosX, ty, a.ui.statusMessage)
  x = tx + MessagePadX

  # Display commands, if present
  for i, cmd in a.ui.statusCommands.pairs:
    if i mod 2 == 0:
      let label = cmd
      let w = vg.textWidth(label)

      vg.beginPath()
      vg.roundedRect(x, y+4, w + 10, StatusBarHeight-8, 3)
      vg.fillColor(s.commandBgColor)
      vg.fill()

      vg.fillColor(s.commandColor)
      discard vg.text(x + 5, ty, label)
      x += w + CommandLabelPadX
    else:
      let text = cmd
      vg.fillColor(s.textColor)
      let tx = vg.text(x, ty, text)
      x = tx + CommandTextPadX

  vg.restore()

# }}}

# {{{ openMap()
proc resetCursorAndViewStart(a)

proc openMap(a) =
  when defined(DEBUG): discard
  else:
    let filename = fileDialog(fdOpenFile,
                              filters=GridmongerMapFileFilter)
    if filename != "":
      try:
        a.doc.map = readMap(filename)
        a.doc.filename = filename

        initUndoManager(a.doc.undoManager)

        resetCursorAndViewStart(a)
        setStatusMessage(IconFloppy, fmt"Map '{filename}' loaded", a)

      except CatchableError as e:
        # TODO log stracktrace?
        setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)
# }}}
# {{{ saveMapAction()
proc saveMap(filename: string, a) =
  writeMap(a.doc.map, filename)
  a.doc.undoManager.setLastSaveState()
  setStatusMessage(IconFloppy, fmt"Map '{filename}' saved", a)

proc saveMapAsAction(a) =
  when not defined(DEBUG):
    var filename = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if filename != "":
      try:
        filename = addFileExt(filename, MapFileExt)
        saveMap(filename, a)
        a.doc.filename = filename
      except CatchableError as e:
        # TODO log stracktrace?
        setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}", a)

proc saveMapAction(a) =
  if a.doc.filename != "": saveMap(a.doc.filename, a)
  else: saveMapAsAction(a)

# }}}
# {{{ searchThemes()
proc searchThemes(a) =
  for path in walkFiles(fmt"{ThemesDir}/*.cfg"):
    let (_, name, _) = splitFile(path)
    a.theme.themeNames.add(name)
  sort(a.theme.themeNames)

# }}}
# {{{ findThemeIndex()
proc findThemeIndex(name: string, a): int =
  for i, n in a.theme.themeNames:
    if n == name:
      return i
  return -1

# }}}
# {{{ loadTheme()
proc loadTheme(index: Natural, a) =
  let name = a.theme.themeNames[index]
  let (uiStyle, levelStyle) = loadTheme(fmt"{ThemesDir}/{name}.cfg")
  a.ui.style = uiStyle

  a.doc.levelStyle = levelStyle

  a.theme.currThemeIndex = index

  # TODO
  var labelStyle = koi.getDefaultLabelStyle()
  labelStyle.fontSize = 14
  labelStyle.color = gray(0.8)
  labelStyle.align = haLeft
  koi.setDefaultLabelStyle(labelStyle)

  # TODO
  alias(s, a.ui.style)

  a.win.setStyle(s.titleBarStyle)

  block:
    alias(d, a.theme.levelDropdownStyle)
    alias(s, s.levelDropdownStyle)

    d = koi.getDefaultDropdownStyle()

    d.buttonFillColor          = s.buttonColor
    d.buttonFillColorHover     = s.buttonColorHover
    d.buttonFillColorDown      = s.buttonColor
    d.buttonFillColorActive    = s.buttonColor
    d.buttonFillColorDisabled  = s.buttonColor
    d.labelFontSize            = 15.0
    d.labelColor               = s.labelColor
    d.labelColorHover          = s.labelColor
    d.labelColorDown           = s.labelColor
    d.labelColorActive         = s.labelColor
    d.labelColorDisabled       = s.labelColor
    d.labelAlign               = haCenter
    d.itemAlign                = haCenter
    d.itemListFillColor        = s.itemListColor
    d.itemColor                = s.itemColor
    d.itemColorHover           = s.itemColorHover
    d.itemBackgroundColorHover = s.itemBgColorHover
    d.itemAlign                = haLeft
    d.itemListPadHoriz         = 10

# }}}

# {{{ getPxRatio()
# TODO move to koi?
proc getPxRatio(a): float =
  let
    (winWidth, _) = a.win.size
    (fbWidth, _) = a.win.framebufferSize
  result = fbWidth / winWidth

# }}}
# {{{ Key handling
# TODO change all into isShorcut* (if possible)
func isKeyDown(ev: Event, keys: set[Key],
               mods: set[ModifierKey] = {}, repeat=false): bool =
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  ev.action in a and ev.key in keys and ev.mods == mods

func isKeyDown(ev: Event, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ev, {key}, mods, repeat)

func isKeyUp(ev: Event, keys: set[Key]): bool =
  ev.action == kaUp and ev.key in keys

proc isShortcutDown(ev: Event, shortcut: AppShortcut, repeat=false): bool =
  if ev.kind == ekKey:
    let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
    if ev.action in a:
      let sc = mkKeyShortcut(ev.key, ev.mods)
      result = sc in g_appShortcuts[shortcut]

# }}}
# {{{ moveCurrGridIcon()

var GridIconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()
GridIconRadioButtonsStyle.buttonPadHoriz = 4.0
GridIconRadioButtonsStyle.buttonPadVert = 4.0
GridIconRadioButtonsStyle.labelFontSize = 18.0
# TODO color schould come from theme
GridIconRadioButtonsStyle.labelColor = gray(0.1)
GridIconRadioButtonsStyle.labelColorHover = gray(0.1)
GridIconRadioButtonsStyle.labelColorDown = gray(0.1)
GridIconRadioButtonsStyle.labelColorActive = gray(0.1)
GridIconRadioButtonsStyle.labelPadHoriz = 0
GridIconRadioButtonsStyle.labelPadHoriz = 0

proc moveCurrGridIcon(numIcons, iconsPerRow: Natural, iconIdx: int,
                      dc: int = 0, dr: int = 0): Natural =
  assert numIcons mod iconsPerRow == 0

  let numRows = ceil(numIcons.float / iconsPerRow).Natural
  var row = iconIdx div iconsPerRow
  var col = iconIdx mod iconsPerRow
  col = floorMod(col+dc, iconsPerRow).Natural
  row = floorMod(row+dr, numRows).Natural
  result = row * iconsPerRow + col

# }}}
# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  a.ui.cursor.level = 0
  a.ui.cursor.row = 0
  a.ui.cursor.col = 0
  a.ui.drawLevelParams.viewStartRow = 0
  a.ui.drawLevelParams.viewStartCol = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(cur, a.ui.cursor)

  let l = getCurrLevel(a)

  if dp.drawCellCoords:
    a.ui.levelTopPad    = LevelTopPad_Coords
    a.ui.levelRightPad  = LevelRightPad_Coords
    a.ui.levelBottomPad = LevelBottomPad_Coords
    a.ui.levelLeftPad   = LevelLeftPad_Coords
  else:
    a.ui.levelTopPad    = LevelTopPad_NoCoords
    a.ui.levelRightPad  = LevelRightPad_NoCoords
    a.ui.levelBottomPad = LevelBottomPad_NoCoords
    a.ui.levelLeftPad   = LevelLeftPad_NoCoords

  dp.startX = ui.levelLeftPad
  dp.startY = TitleBarHeight + ui.levelTopPad

  var drawAreaHeight = koi.winHeight() - TitleBarHeight - StatusBarHeight -
                       ui.levelTopPad - ui.levelBottomPad

  if a.opt.showNotesPane:
   drawAreaHeight -= NotesPaneTopPad + NotesPaneHeight + NotesPaneBottomPad

  var drawAreaWidth = koi.winWidth() - ui.levelLeftPad - ui.levelRightPad

  if a.opt.showToolsPane:
    drawAreaWidth -= ToolsPaneWidth

  ui.levelDrawAreaWidth = drawAreaWidth
  ui.levelDrawAreaHeight = drawAreaHeight

  dp.viewRows = min(dp.numDisplayableRows(drawAreaHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(drawAreaWidth), l.cols)

  dp.viewStartRow = min(max(l.rows - dp.viewRows, 0), dp.viewStartRow)
  dp.viewStartCol = min(max(l.cols - dp.viewCols, 0), dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  cur.row = min(
    max(viewEndRow, dp.viewStartRow),
    cur.row
  )
  cur.col = min(
    max(viewEndCol, dp.viewStartCol),
    cur.col
  )

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, steps: Natural, a) =
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)

  let l = getCurrLevel(a)
  let sm = a.opt.scrollMargin

  case dir:
  of dirE:
    cur.col = min(cur.col + steps, l.cols-1)
    let viewCol = cur.col - dp.viewStartCol
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = min(max(l.cols - dp.viewCols, 0),
                            dp.viewStartCol + (viewCol - viewColMax))

  of dirS:
    cur.row = min(cur.row + steps, l.rows-1)
    let viewRow = cur.row - dp.viewStartRow
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = min(max(l.rows - dp.viewRows, 0),
                            dp.viewStartRow + (viewRow - viewRowMax))

  of dirW:
    cur.col = max(cur.col - steps, 0)
    let viewCol = cur.col - dp.viewStartCol
    if viewCol < sm:
      dp.viewStartCol = max(dp.viewStartCol - (sm - viewCol), 0)

  of dirN:
    cur.row = max(cur.row - steps, 0)
    let viewRow = cur.row - dp.viewStartRow
    if viewRow < sm:
      dp.viewStartRow = max(dp.viewStartRow - (sm - viewRow), 0)


# }}}
# {{{ moveSelStart()
proc moveSelStart(dir: CardinalDir, a) =
  alias(dp, a.ui.drawLevelParams)

  let cols = a.ui.nudgeBuf.get.level.cols
  let rows = a.ui.nudgeBuf.get.level.cols

  case dir:
  of dirE:
    if dp.selStartCol < cols-1: inc(dp.selStartCol)

  of dirS:
    if dp.selStartRow < rows-1: inc(dp.selStartRow)

  of dirW:
    if dp.selStartCol + cols > 1: dec(dp.selStartCol)

  of dirN:
    if dp.selStartRow + rows > 1: dec(dp.selStartRow)


# }}}
# {{{ moveCursorTo()
proc moveCursorTo(loc: Location, a) =
  alias(cur, a.ui.cursor)

  cur.level = loc.level

  let  dx = loc.col - cur.col
  if   dx < 0: moveCursor(dirW, -dx, a)
  elif dx > 0: moveCursor(dirE,  dx, a)

  let  dy = loc.row - cur.row
  if   dy < 0: moveCursor(dirN, -dy, a)
  elif dy > 0: moveCursor(dirS,  dy, a)

# }}}
# {{{ setSelectModeSelectMessage()
proc setSelectModeSelectMessage(a) =
  setStatusMessage(IconSelection, "Mark selection",
                   @["D", "draw", "E", "erase",
                     "R", "add rect", "S", "sub rect",
                     "A", "mark all", "U", "unmark all",
                     "C/Y", "copy", "X", "cut",
                     "Ctrl", "special"], a)
# }}}
# {{{ setSelectModeActionMessage()
proc setSelectModeActionMessage(a) =
  setStatusMessage(IconSelection, "Mark selection",
                   @["Ctrl+E", "erase", "Ctrl+F", "fill",
                     "Ctrl+S", "surround", "Ctrl+R", "crop"], a)
# }}}
# {{{ enterSelectMode()
proc enterSelectMode(a) =
  let l = getCurrLevel(a)

  a.ui.editMode = emSelect
  a.ui.selection = some(newSelection(l.rows, l.cols))
  a.ui.drawLevelParams.drawCursorGuides = true
  setSelectModeSelectMessage(a)

# }}}
# {{{ exitSelectMode()
proc exitSelectMode(a) =
  a.ui.editMode = emNormal
  a.ui.selection = Selection.none
  a.ui.drawLevelParams.drawCursorGuides = false
  clearStatusMessage(a)

# }}}
# {{{ copySelection()
proc copySelection(a): Option[Rect[Natural]] =

  proc eraseOrphanedWalls(cb: SelectionBuffer) =
    var l = cb.level
    for r in 0..<l.rows:
      for c in 0..<l.cols:
        l.eraseOrphanedWalls(r,c)

  let sel = a.ui.selection.get

  let bbox = sel.boundingBox()
  if bbox.isSome:
    a.ui.copyBuf = some(SelectionBuffer(
      selection: newSelectionFrom(a.ui.selection.get, bbox.get),
      level: newLevelFrom(getCurrLevel(a), bbox.get)
    ))
    eraseOrphanedWalls(a.ui.copyBuf.get)

  result = bbox

# }}}

# {{{ Dialogs
# {{{ Save/discard changes dialog
proc saveDiscardDialog(dlg: var SaveDiscardDialogParams, a) =
  let
    dialogWidth = 350.0
    dialogHeight = 160.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconFloppy}  Save Changes?")
  clearStatusMessage(a)

  let
    h = 24.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 50.0

  koi.label(x, y, dialogWidth, h, "You have unsaved changes.")

  y += 24
  koi.label(x, y, dialogWidth, h, "Do you want to save your changes first?")

  proc saveAction(dlg: var SaveDiscardDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false
    saveMapAction(a)
    dlg.action(a)

  proc discardAction(dlg: var SaveDiscardDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false
    dlg.action(a)

  proc cancelAction(dlg: var SaveDiscardDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  x = dialogWidth - 3 * buttonWidth - buttonPad - 20
  y = dialogHeight - h - buttonPad

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} Save"):
    saveAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconTrash} Discard"):
    discardAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  if koi.hasEvent():
    let ke = koi.currEvent()
    if   ke.isShortcutDown(scCancel):  cancelAction(dlg, a)
    elif ke.isShortcutDown(scDiscard): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept):  saveAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ New map dialog
proc openNewMapDialog(a) =
  alias(dlg, a.dialog.newMapDialog)
  dlg.name = "Untitled Map"
  dlg.isOpen = true


proc newMapDialog(dlg: var NewMapDialogParams, a) =
  alias(sc, g_appShortcuts)

  let
    dialogWidth = 410.0
    dialogHeight = 150.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  New Map")
  a.clearStatusMessage()

  let
    h = 24.0
    labelWidth = 130.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Name")
  dlg.name = koi.textField(x + labelWidth, y, 220.0, h, dlg.name)

  proc okAction(dlg: var NewMapDialogParams, a) =
    a.doc.filename = ""
    a.doc.map = newMap(dlg.name)
    initUndoManager(a.doc.undoManager)

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, "New map created", a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var NewMapDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  if koi.hasEvent():
    let ke = koi.currEvent()
    if   ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit map properties dialog
proc openMapPropsDialog(a) =
  alias(dlg, a.dialog.editMapPropsDialog)
  dlg.name = $a.doc.map.name
  dlg.isOpen = true


proc editMapPropsDialog(dlg: var EditMapPropsDialogParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 150.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  Edit Map Properties")
  clearStatusMessage(a)

  let
    h = 24.0
    labelWidth = 130.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Name")
  dlg.name = koi.textField(x + labelWidth, y, 220.0, h, dlg.name)

  proc okAction(dlg: var EditMapPropsDialogParams, a) =
    # TODO should be action
    a.doc.map.name = dlg.name

    setStatusMessage(IconFile, "Map properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var EditMapPropsDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  if koi.hasEvent():
    let ke = koi.currEvent()
    if   ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ New level dialog
proc openNewLevelDialog(a) =
  alias(dlg, a.dialog.newLevelDialog)

  if mapHasLevels(a):
    let l = getCurrLevel(a)
    dlg.locationName = l.locationName
    dlg.levelName = ""
    dlg.elevation = if   l.elevation > 0: $(l.elevation + 1)
                    elif l.elevation < 0: $(l.elevation - 1)
                    else: "0"
    dlg.rows = $l.rows
    dlg.cols = $l.cols
  else:
    dlg.locationName = "Untitled Location"
    dlg.levelName = ""
    dlg.elevation = "0"
    dlg.rows = "16"
    dlg.cols = "16"

  dlg.isOpen = true


proc newLevelDialog(dlg: var NewLevelDialogParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 334.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  New Level")
  clearStatusMessage(a)

  let
    h = 24.0
    labelWidth = 130.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Location Name")
  dlg.locationName = koi.textField(
    x + labelWidth, y, 220.0, h, dlg.locationName
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Level Name")
  dlg.levelName = koi.textField(
    x + labelWidth, y, 220.0, h, dlg.levelName
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Elevation")
  dlg.elevation = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.elevation
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Rows")
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.rows
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Columns")
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.cols
  )

  # Validation
  var validationError = ""
  if dlg.locationName == "":
    validationError = fmt"{IconWarning}  Location name is mandatory"

  y += 44

  if validationError != "":
    koi.label(x, y, dialogWidth, h, validationError,
              style=DialogWarningLabelStyle)

  proc okAction(dlg: var NewLevelDialogParams, a) =
    if validationError != "": return

    # TODO number error checking
    let
      rows = parseInt(dlg.rows)
      cols = parseInt(dlg.cols)
      elevation = parseInt(dlg.elevation)

      newLevel = newLevel(dlg.locationName, dlg.levelName, elevation,
                          rows, cols)

    a.doc.map.addLevel(newLevel)
    a.ui.cursor.level = a.doc.map.levels.high

    setStatusMessage(IconFile, fmt"New {rows}x{cols} level created", a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var NewLevelDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK",
                disabled=validationError != ""):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  if koi.hasEvent():
    let ke = koi.currEvent()
    if   ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit level properties dialog
proc openEditLevelPropsDialog(a) =
  alias(dlg, a.dialog.editLevelPropsDialog)

  let l = getCurrLevel(a)
  dlg.locationName = l.locationName
  dlg.levelName = l.levelName
  dlg.elevation = $l.elevation
  dlg.isOpen = true


proc editLevelPropsDialog(dlg: var EditLevelPropsParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 224.0

  koi.beginDialog(dialogWidth, dialogHeight,
                  fmt"{IconNewFile}  Edit Level Properties")
  clearStatusMessage(a)

  let
    h = 24.0
    labelWidth = 130.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var
    x = 30.0
    y = 60.0

  koi.label(x, y, labelWidth, h, "Location Name")
  dlg.locationName = koi.textField(
    x + labelWidth, y, 220.0, h, dlg.locationName
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Level Name")
  dlg.levelName = koi.textField(
    x + labelWidth, y, 220.0, h, dlg.levelName
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Elevation")
  dlg.elevation = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.elevation
  )

  proc okAction(dlg: var EditLevelPropsParams, a) =
    # TODO number error checking
    let elevation = parseInt(dlg.elevation)

    actions.setLevelProps(a.doc.map, a.ui.cursor,
                          dlg.locationName, dlg.levelName, elevation,
                          a.doc.undoManager)

    setStatusMessage(fmt"Level properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var EditLevelPropsParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  if koi.hasEvent():
    let ke = koi.currEvent()
    if   ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Resize level dialog
proc openResizeLevelDialog(a) =
  alias(dlg, a.dialog.resizeLevelDialog)

  let l = getCurrLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter
  dlg.isOpen = true


proc resizeLevelDialog(dlg: var ResizeLevelDialogParams, a) =

  let dialogWidth = 270.0
  let dialogHeight = 300.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCrop}  Resize Level")
  clearStatusMessage(a)

  let
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var x = 30.0
  var y = 60.0

  koi.label(x, y, labelWidth, h, "Rows")
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.rows
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Columns")
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, dlg.cols
  )

  const IconsPerRow = 3

  const AnchorIcons = @[
    IconArrowUpLeft,   IconArrowUp,   IconArrowUpRight,
    IconArrowLeft,     IconCircleInv, IconArrowRight,
    IconArrowDownLeft, IconArrowDown, IconArrowDownRight
  ]

  y += 40
  koi.label(x, y, labelWidth, h, "Anchor")
  dlg.anchor = koi.radioButtons(
    x + labelWidth, y, 35, 35,
    labels = AnchorIcons,
    ord(dlg.anchor),
    tooltips = @["Top-left", "Top", "Top-right",
                 "Left", "Center", "Right",
                 "Bottom-left", "Bottom", "Bottom-right"],
    layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: IconsPerRow),
    style=GridIconRadioButtonsStyle
  ).ResizeAnchor

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(dlg: var ResizeLevelDialogParams, a) =
    # TODO number error checking
    let newRows = parseInt(dlg.rows)
    let newCols = parseInt(dlg.cols)

    let align = case dlg.anchor
    of raTopLeft:     NorthWest
    of raTop:         North
    of raTopRight:    NorthEast
    of raLeft:        West
    of raCenter:      {}
    of raRight:       East
    of raBottomLeft:  SouthWest
    of raBottom:      South
    of raBottomRight: SouthEast

    actions.resizeLevel(a.doc.map, a.ui.cursor, newRows, newCols, align,
                        a.doc.undoManager)

    setStatusMessage(IconCrop, "Level resized", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var ResizeLevelDialogParams, a) =
    koi.closeDialog()
    dlg.isOpen = false

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  proc moveIcon(iconIDx: Natural, dc: int = 0, dr: int = 0): Natural =
    moveCurrGridIcon(AnchorIcons.len, IconsPerRow, iconIdx, dc, dr)

  if koi.hasEvent() and koi.currEvent().kind == ekKey:
    let ke = koi.currEvent()
    if   ke.isKeyDown(keyH, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dc= -1).ResizeAnchor

    elif ke.isKeyDown(keyL, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dc=1).ResizeAnchor

    elif ke.isKeyDown(keyK, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dr= -1).ResizeAnchor

    elif ke.isKeyDown(keyJ, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dr=1).ResizeAnchor

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

    koi.setFramesLeft()

  koi.endDialog()

# }}}
# {{{ Edit note dialog
proc openEditNoteDialog(a) =
  alias(dlg, a.dialog.editNoteDialog)
  alias(cur, a.ui.cursor)

  let l = getCurrLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  if l.hasNote(cur.row, cur.col):
    let note = l.getNote(cur.row, cur.col)
    dlg.editMode = true
    dlg.kind = note.kind
    dlg.text = note.text

    if note.kind == nkIndexed:
      dlg.index = note.index
      dlg.indexColor = note.indexColor
    elif note.kind == nkIcon:
      dlg.icon = note.icon

    if note.kind == nkCustomId:
      dlg.customId = note.customId
    else:
      dlg.customId = ""

  else:
    dlg.editMode = false
    dlg.customId = ""
    dlg.text = ""

  dlg.isOpen = true


proc colorRadioButtonDrawProc(colors: seq[Color],
                              cursorColor: Color): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               hover, active, down, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var col = colors[buttonIdx]

    if hover:
      col = col.lerp(white(), 0.3)
    if down:
      col = col.lerp(black(), 0.3)

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if active:
      vg.beginPath()
      vg.strokeColor(cursorColor)
      vg.strokeWidth(2)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.stroke()

      cx = x+SelPad
      cy = y+SelPad
      cw = w-Pad-SelPad*2
      ch = h-Pad-SelPad*2

    else:
      cx = x
      cy = y
      cw = w-Pad
      ch = h-Pad

    vg.beginPath()
    vg.fillColor(col)
    vg.rect(cx, cy, cw, ch)
    vg.fill()


proc editNoteDialog(dlg: var EditNoteDialogParams, a) =
  alias(ls, a.doc.levelStyle)
  let
    dialogWidth = 500.0
    dialogHeight = 370.0
    title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCommentInv}  {title}")
  clearStatusMessage(a)

  let
    h = 24.0
    labelWidth = 80.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var x = 30.0
  var y = 60.0

  koi.label(x, y, labelWidth, h, "Marker")
  dlg.kind = NoteKind(
    koi.radioButtons(
      x + labelWidth, y, 282, h,
      labels = @["None", "Number", "ID", "Icon"],
      ord(dlg.kind)
    )
  )

  y += 40
  koi.label(x, y, labelWidth, h, "Text")
  dlg.text = koi.textField(
    x + labelWidth, y, 355, h, dlg.text
  )

  y += 64

  let NumIndexColors = ls.noteLevelIndexBgColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of nkIndexed:
    koi.label(x, y, labelWidth, h, "Color")
    dlg.indexColor = koi.radioButtons(
      x + labelWidth, y, 28, 28,
      labels = newSeq[string](ls.noteLevelIndexBgColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc=colorRadioButtonDrawProc(ls.noteLevelIndexBgColor,
                                        ls.cursorColor).some
    )

  of nkCustomId:
    koi.label(x, y, labelWidth, h, "ID")
    dlg.customId = koi.textField(
      x + labelWidth, y, 50.0, h, dlg.customId
    )

  of nkIcon:
    koi.label(x, y, labelWidth, h, "Icon")
    dlg.icon = koi.radioButtons(
      x + labelWidth, y, 35, 35,
      labels = NoteIcons,
      dlg.icon,
      tooltips = @[],
      layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 10),
      style=GridIconRadioButtonsStyle
    )

  of nkComment: discard

  x = dialogWidth - 2 * buttonWidth - buttonPad - 10
  y = dialogHeight - h - buttonPad

  proc okAction(dlg: var EditNoteDialogParams, a) =
    var note = Note(
      kind: dlg.kind,
      text: dlg.text
    )
    case note.kind
    of nkCustomId: note.customId = dlg.customId
    of nkIndexed:  note.indexColor = dlg.indexColor
    of nkIcon:     note.icon = dlg.icon
    of nkComment:  discard

    actions.setNote(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

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

  proc moveIcon(iconIdx: Natural, dc: int = 0, dr: int = 0): Natural =
    moveCurrGridIcon(NoteIcons.len, IconsPerRow, iconIdx, dc, dr)

  if koi.hasEvent() and koi.currEvent().kind == ekKey:
    let ke = koi.currEvent()

    if   ke.isKeyDown(key1, {mkCtrl}):
      dlg.kind = nkComment

    elif ke.isKeyDown(key2, {mkCtrl}):
      dlg.kind = nkIndexed

    elif ke.isKeyDown(key3, {mkCtrl}):
      dlg.kind = nkCustomId

    elif ke.isKeyDown(key4, {mkCtrl}):
      dlg.kind = nkIcon

    elif ke.isKeyDown(keyH, {mkCtrl}):
      if dlg.kind > NoteKind.low: dec(dlg.kind)
      else: dlg.kind = NoteKind.high

    elif ke.isKeyDown(keyL, {mkCtrl}):
      if dlg.kind < NoteKind.high: inc(dlg.kind)
      else: dlg.kind = NoteKind.low

    elif ke.isKeyDown(keyH, repeat=true):
      case dlg.kind
      of nkComment, nkCustomId: discard
      of nkIndexed:
        dlg.indexColor = floorMod(dlg.indexColor.int - 1, NumIndexColors).Natural
      of nkIcon:
        dlg.icon = moveIcon(dlg.icon, dc= -1)

    elif ke.isKeyDown(keyL, repeat=true):
      case dlg.kind
      of nkComment, nkCustomId: discard
      of nkIndexed:
        dlg.indexColor = floorMod(dlg.indexColor + 1, NumIndexColors).Natural
      of nkIcon:
        dlg.icon = moveIcon(dlg.icon, dc=1)

    elif ke.isKeyDown(keyK, repeat=true):
      case dlg.kind
      of nkComment, nkIndexed, nkCustomId: discard
      of nkIcon: dlg.icon = moveIcon(dlg.icon, dr= -1)

    elif ke.isKeyDown(keyJ, repeat=true):
      case dlg.kind
      of nkComment, nkIndexed, nkCustomId: discard
      of nkIcon: dlg.icon = moveIcon(dlg.icon, dr=1)

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)

    koi.setFramesLeft()

  koi.endDialog()

# }}}
# }}}

# {{{ newMapAction()
proc newMapAction(a) =
  if a.doc.undoManager.isModified:
    a.dialog.saveDiscardDialog.isOpen = true
    a.dialog.saveDiscardDialog.action = proc (a: var AppContext) =
      openNewMapDialog(a)
  else:
    openNewMapDialog(a)

# }}}
# {{{ openMapAction()
proc openMapAction(a) =
  alias(dlg, a.dialog.saveDiscardDialog)
  if a.doc.undoManager.isModified:
    dlg.isOpen = true
    dlg.action = openMap
  else:
    openMap(a)

# }}}
# {{{ reloadThemeAction()
proc reloadThemeAction(a) =
  a.theme.nextThemeIndex = a.theme.currThemeIndex.some
  koi.setFramesLeft()

# }}}
# {{{ prevThemeAction()
proc prevThemeAction(a) =
  var i = a.theme.currThemeIndex
  if i == 0: i = a.theme.themeNames.high else: dec(i)
  a.theme.nextThemeIndex = i.some
  koi.setFramesLeft()

# }}}
# {{{ nextThemeAction()
proc nextThemeAction(a) =
  var i = a.theme.currThemeIndex
  inc(i)
  if i > a.theme.themeNames.high: i = 0
  a.theme.nextThemeIndex = i.some
  koi.setFramesLeft()

# }}}
# {{{ prevLevelAction()
proc prevLevelAction(a) =
  alias(cur, a.ui.cursor)
  if cur.level > 0:
    dec(cur.level)

# }}}
# {{{ nextLevelAction()
proc nextLevelAction(a) =
  alias(cur, a.ui.cursor)
  if cur.level < a.doc.map.levels.len-1:
    inc(cur.level)

# }}}
# {{{ incZoomLevelAction()
proc incZoomLevelAction(a) =
  incZoomLevel(a.doc.levelStyle, a.ui.drawLevelParams)

# }}}
# {{{ decZoomLevelAction()
proc decZoomLevelAction(a) =
  decZoomLevel(a.doc.levelStyle, a.ui.drawLevelParams)

# }}}
# {{{ setFloorAction()
proc setFloorAction(f: Floor, a) =
  alias(cur, a.ui.cursor)

  let ot = getCurrLevel(a).guessFloorOrientation(cur.row, cur.col)
  actions.setOrientedFloor(a.doc.map, cur, f, ot, a.doc.undoManager)
  setStatusMessage(fmt"Set floor – {f}", a)

# }}}
# {{{ setOrCycleFloorAction()
proc setOrCycleFloorAction(first, last: Floor, forward: bool, a) =
  assert first <= last

  alias(cur, a.ui.cursor)

  var floor = getCurrLevel(a).getFloor(cur.row, cur.col)

  if floor >= first and floor <= last:
    var f = ord(floor)
    let first = ord(first)
    let last = ord(last)
    if forward: inc(f) else: dec(f)
    floor = (first + floorMod(f-first, last-first+1)).Floor
  else:
    floor = if forward: first else: last

  setFloorAction(floor, a)

# }}}
# {{{ startExcavateAction()
proc startExcavateAction(a) =
  actions.excavate(a.doc.map, a.ui.cursor, a.doc.undoManager)
  setStatusMessage(IconPencil, "Excavate tunnel", @[IconArrowsAll, "draw"], a)

# }}}
# {{{ startEraseCellsAction()
proc startEraseCellsAction(a) =
  actions.eraseCell(a.doc.map, a.ui.cursor, a.doc.undoManager)
  setStatusMessage(IconEraser, "Erase cells", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startDrawWallsAction()
proc startDrawWallsAction(a) =
  setStatusMessage("", "Draw walls", @[IconArrowsAll, "set/clear"], a)

# }}}

# {{{ drawEmptyMap()
proc drawEmptyMap(a) =
  alias(vg, a.vg)
  alias(ls, a.doc.levelStyle)

  vg.save()

  vg.fontSize(22)
  vg.fillColor(ls.drawColor)
  vg.textAlign(haCenter, vaMiddle)
  var y = koi.winHeight() * 0.5
  discard vg.text(koi.winWidth() * 0.5, y, "Empty map")

  vg.save()

# }}}
# {{{ renderLevel()
proc renderLevel(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opt, a.opt)
  alias(vg, a.vg)

  let i = instantiationInfo(fullPaths=true)
  let id = koi.generateId(i.filename, i.line, "gridmonger-level")

  updateViewStartAndCursorPosition(a)

  let
    x = dp.startX
    y = dp.startY
    w = dp.viewCols * dp.gridSize
    h = dp.viewRows * dp.gridSize

  # Hit testing
  if koi.isHit(x, y, w, h):
    koi.setHot(id)
    if koi.noActiveItem() and
       (koi.mbLeftDown() or koi.mbRightDown() or koi.mbMiddleDown()):
      koi.setActive(id)

  # We're only handling the mouse events inside the level "widget" because
  # all keyboard events are global.
  if koi.isHot(id):
    if isActive(id):
      if opt.wasdMode:
        if ui.editMode == emNormal:
          if koi.mbLeftDown():
            ui.editMode = emExcavate
            startExcavateAction(a)

          elif koi.mbRightDown():
            ui.editMode = emDrawWall
            startDrawWallsAction(a)

          elif koi.mbMiddleDown():
            ui.editMode = emEraseCell
            startEraseCellsAction(a)

        elif ui.editMode == emExcavate:
          if not koi.mbLeftDown():
            ui.editMode = emNormal
            clearStatusMessage(a)

        elif ui.editMode == emDrawWall:
          if not koi.mbRightDown():
            ui.editMode = emNormal
            clearStatusMessage(a)

        elif ui.editMode == emEraseCell:
          if not koi.mbMiddleDown():
            ui.editMode = emNormal
            clearStatusMessage(a)

  # Draw level
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = ui.cursor.row
    dp.cursorCol = ui.cursor.col

    dp.cursorOrient = CardinalDir.none
    if opt.walkMode and
       ui.editMode in {emNormal, emExcavate, emEraseCell, emClearFloor}:
      dp.cursorOrient = ui.cursorOrient.some

    dp.selection = ui.selection
    dp.selectionRect = ui.selRect

    dp.selectionBuffer =
      if ui.editMode == emPastePreview: ui.copyBuf
      elif ui.editMode == emNudgePreview: ui.nudgeBuf
      else: SelectionBuffer.none

    drawLevel(getCurrLevel(a), DrawLevelContext(ls: a.doc.levelStyle,
                                                dp: dp, vg: a.vg))

  if koi.isHot(id):
    if not (opt.wasdMode and isActive(id)):
      let
        mouseViewRow = ((koi.my() - dp.startY) / dp.gridSize).int
        mouseViewCol = ((koi.mx() - dp.startX) / dp.gridSize).int

        mouseRow = dp.viewStartRow + mouseViewRow
        mouseCol = dp.viewStartCol + mouseViewCol

      if mouseViewRow >= 0 and mouseRow < dp.viewStartRow + dp.viewRows and
         mouseViewCol >= 0 and mouseCol < dp.viewStartCol + dp.viewCols:

        let l = getCurrLevel(a)

        if l.hasNote(mouseRow, mouseCol):
          let note = l.getNote(mouseRow, mouseCol)

          if note.text != "":
            const PadX = 10
            const PadY = 8

            var noteBoxX = koi.mx() + 16
            var noteBoxY = koi.my() + 14
            let noteBoxW = 220.0

            vg.setFont(14.0, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
            vg.textLineHeight(1.5)

            let
              bounds = vg.textBoxBounds(noteBoxX + PadX,
                                        noteBoxY + PadY,
                                        noteBoxW - PadX*2, note.text)
              noteTextH = bounds.y2 - bounds.y1
              noteTextW = bounds.x2 - bounds.x1
              noteBoxH = noteTextH + PadY*2

              xOver = noteBoxX + noteBoxW - (dp.startX + ui.levelDrawAreaWidth)
              yOver = noteBoxY + noteBoxH - (dp.startY + ui.levelDrawAreaHeight)

            if xOver > 0:
              noteBoxX -= xOver
              if yOver <= 0: noteBoxY += 8

            if yOver > 0:
              noteBoxY -= noteBoxH + 22

            vg.fillColor(rgba(20, 20, 28, 240))
            vg.beginPath()
            vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH, 5)
            vg.fill()

            vg.fillColor(rgb(252, 252, 255))
            vg.textBox(noteBoxX + PadX, noteBoxY + PadY, noteTextW, note.text)


# }}}
# {{{ renderToolsPane()
# {{{ specialWallDrawProc()
proc specialWallDrawProc(ls: LevelStyle,
                         dp: DrawLevelParams): RadioButtonsDrawProc =
  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               hover, active, down, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var col = if active: ls.cursorColor else: ls.floorColor

    if hover:
      col = col.lerp(white(), 0.3)
    if down:
      col = col.lerp(black(), 0.3)

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let savedFloorColor = ls.floorColor
    ls.floorColor = gray(0, 0)  # transparent

    const Pad = 5

    vg.beginPath()
    vg.fillColor(col)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill()

    dp.setZoomLevel(ls, 4)
    let ctx = DrawLevelContext(ls: ls, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel6(body: untyped) =
      vg.save()
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(ls, 6)
      vg.intersectScissor(x+4.5, y+3, dp.gridSize-3, dp.gridSize-2)
      body
      dp.setZoomLevel(ls, 4)
      vg.restore()

    case SpecialWalls[buttonIdx]
    of wNone:           discard
    of wWall:           drawSolidWallHoriz(cx, cy, ctx)
    of wIllusoryWall:   drawIllusoryWallHoriz(cx+2, cy, ctx)
    of wInvisibleWall:  drawInvisibleWallHoriz(cx, cy, ctx)
    of wDoor:           drawDoorHoriz(cx, cy, ctx)
    of wLockedDoor:     drawLockedDoorHoriz(cx, cy, ctx)
    of wArchway:        drawArchwayHoriz(cx, cy, ctx)

    of wSecretDoor:
      drawAtZoomLevel6: drawSecretDoorHoriz(cx-2, cy, ctx)

    of wLeverSW:
      drawAtZoomLevel6: drawLeverHorizSW(cx-2, cy+1, ctx)

    of wNicheSW:        drawNicheHorizSW(cx, cy, ctx)

    of wStatueSW:
      drawAtZoomLevel6: drawStatueHorizSW(cx-2, cy+2, ctx)

    of wKeyhole:
      drawAtZoomLevel6: drawKeyholeHoriz(cx-2, cy, ctx)

    else: discard

    # ...aaaaand restore it!
    ls.floorColor = savedFloorColor

# }}}

proc renderToolsPane(x, y, w, h: float, a) =
  alias(ui, a.ui)
  alias(ls, a.doc.levelStyle)

  ui.currSpecialWall = koi.radioButtons(
    x = x,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 20),
    drawProc=specialWallDrawProc(ls, ui.toolbarDrawParams).some
  )

  ui.currFloorColor = koi.radioButtons(
    x = x + 3,
    y = y + 374,
    w = 30,
    h = 30,
    labels = newSeq[string](4),
    ui.currFloorColor,
    tooltips = @[],
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 8),
    drawProc=colorRadioButtonDrawProc(ls.noteLevelIndexBgColor,
                                      ls.cursorColor).some
  )

# }}}
# {{{ drawNotesPane()
proc drawNotesPane(x, y, w, h: float, a) =
  alias(vg, a.vg)
  alias(ls, a.doc.levelStyle)

  vg.save()

  let l = getCurrLevel(a)
  let cur = a.ui.cursor

  if not (a.ui.editMode in {emPastePreview, emNudgePreview}) and
     l.hasNote(cur.row, cur.col):

    let note = l.getNote(cur.row, cur.col)
    case note.kind
    of nkIndexed:
      drawIndexedNote(x, y-12, note.index, 36,
                      bgColor=ls.notePaneIndexBgColor[note.indexColor],
                      fgColor=ls.notePaneIndexColor, vg)

    of nkCustomId:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(18.0, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+18, y-2, note.customId)

    of nkIcon:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-3, NoteIcons[note.icon])

    of nkComment:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-2, IconComment)

    vg.fillColor(ls.notePaneTextColor)
    vg.setFont(14.5, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.4)
    vg.intersectScissor(x+40, y, w-40, h)
    vg.textBox(x+40, y, w-40, note.text)

  vg.restore()

# }}}
# {{{ drawModeAndOptionIndicators()
proc drawModeAndOptionIndicators(a) =
  alias(vg, a.vg)
  alias(ls, a.doc.levelStyle)

  let winWidth = koi.winWidth().float
  let y = koi.winHeight().float - 50

  vg.save()

  vg.setFont(16.0, horizAlign=haRight, vertAlign=vaMiddle)
  vg.fillColor(ls.coordsHighlightColor)

  if a.opt.drawTrail:
    vg.fontSize(20)
    discard vg.text(winWidth - 17, y-61, IconShoePrints)
    vg.fontSize(16)

  vg.textAlign(haRight)

  var mode = if a.opt.walkMode: "Walk" else: "Normal"
  discard vg.text(winWidth - 15, y, mode)

  if a.opt.wasdMode:
    discard vg.text(winWidth - 15, y-28, fmt"WASD+{IconMouse}")

  vg.restore()

# }}}

# {{{ handleGlobalKeyEvents()
proc handleGlobalKeyEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(cur, a.ui.cursor)
  alias(um, a.doc.undoManager)
  alias(dp, a.ui.drawLevelParams)
  alias(opt, a.opt)

  var l = getCurrLevel(a)

  type
    MoveKeys = object
      left, right, up, down: set[Key]

    WalkKeys = object
      forward, backward, strafeLeft, strafeRight, turnLeft, turnRight: set[Key]

  const
    MoveKeysCursor = MoveKeys(
      left  : {keyLeft,     keyH, keyKp4},
      right : {keyRight,    keyL, keyKp6},
      up    : {keyUp,       keyK, keyKp8},
      down  : {Key.keyDown, keyJ, keyKp2, keyKp5}
    )

    MoveKeysWasd = MoveKeys(
      left  : MoveKeysCursor.left  + {keyA},
      right : MoveKeysCursor.right + {keyD},
      up    : MoveKeysCursor.up    + {keyW},
      down  : MoveKeysCursor.down  + {Key.keyS}
    )

    WalkKeysCursor = WalkKeys(
      forward     : {keyKp8, keyUp},
      backward    : {keyKp2, keyKp5, Key.keyDown},
      strafeLeft  : {keyKp4, keyLeft},
      strafeRight : {keyKp6, keyRight},
      turnLeft    : {keyKp7},
      turnRight   : {keyKp9}
    )

    WalkKeysWasd = WalkKeys(
      forward     : WalkKeysCursor.forward     + {keyW},
      backward    : WalkKeysCursor.backward    + {Key.keyS},
      strafeLeft  : WalkKeysCursor.strafeLeft  + {keyA},
      strafeRight : WalkKeysCursor.strafeRight + {keyD},
      turnLeft    : WalkKeysCursor.turnLeft    + {keyQ},
      turnRight   : WalkKeysCursor.turnRight   + {keyE}
    )

  proc turnLeft(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) - 1, ord(CardinalDir.high) + 1))

  proc turnRight(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) + 1, ord(CardinalDir.high) + 1))

  proc setTrailAtCursor(a) =
    if l.isFloorEmpty(cur.row, cur.col):
      actions.setFloor(map, cur, fTrail, um)

  proc toggleOption(opt: var bool, icon, msg, on, off: string; a) =
    opt = not opt
    let state = if opt: on else: off
    setStatusMessage(icon, fmt"{msg} {state}", a)

  proc toggleShowOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="shown", off="hidden", a)

  proc toggleOnOffOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="on", off="off", a)


  template handleMoveWalk() =
    let k = if opt.wasdMode: WalkKeysWasd else: WalkKeysCursor

    if ke.isKeyDown(k.forward, repeat=true):
      moveCursor(ui.cursorOrient, steps=1, a)

    elif ke.isKeyDown(k.backward, repeat=true):
      let backward = turnLeft(turnLeft(ui.cursorOrient))
      moveCursor(backward, steps=1, a)

    elif ke.isKeyDown(k.strafeLeft, repeat=true):
      let left = turnLeft(ui.cursorOrient)
      moveCursor(left, steps=1, a)

    elif ke.isKeyDown(k.strafeRight, repeat=true):
      let right = turnRight(ui.cursorOrient)
      moveCursor(right, steps=1, a)

    elif ke.isKeyDown(k.turnLeft, repeat=true):
      ui.cursorOrient = turnLeft(ui.cursorOrient)

    elif ke.isKeyDown(k.turnRight, repeat=true):
      ui.cursorOrient = turnRight(ui.cursorOrient)


  template handleMoveKeys(moveHandler: untyped) =
    let k = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor

    if   ke.isKeyDown(k.left,  repeat=true): moveHandler(dirW, a)
    elif ke.isKeyDown(k.right, repeat=true): moveHandler(dirE, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveHandler(dirN, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveHandler(dirS, a)


  template handleMoveCursor(k: MoveKeys) =
    const j = CursorJump

    if   ke.isKeyDown(k.left,  repeat=true): moveCursor(dirW, 1, a)
    elif ke.isKeyDown(k.right, repeat=true): moveCursor(dirE, 1, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveCursor(dirN, 1, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveCursor(dirS, 1, a)

    elif ke.isKeyDown(k.left,  {mkCtrl}, repeat=true): moveCursor(dirW, j, a)
    elif ke.isKeyDown(k.right, {mkCtrl}, repeat=true): moveCursor(dirE, j, a)
    elif ke.isKeyDown(k.up,    {mkCtrl}, repeat=true): moveCursor(dirN, j, a)
    elif ke.isKeyDown(k.down,  {mkCtrl}, repeat=true): moveCursor(dirS, j, a)


  if koi.hasEvent() and koi.currEvent().kind == ekKey:
    let ke = koi.currEvent()

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # This to prevent creating an undoable action for every turn in walk
      # mode
      let prevCursor = cur

      if opt.walkMode: handleMoveWalk()
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        handleMoveCursor(moveKeys)

      if opt.drawTrail and cur != prevCursor:
        setTrailAtCursor(a)

      elif ke.isKeyDown({keyPageUp, keyKpSubtract}) or
         ke.isKeyDown(keyMinus, {mkCtrl}):
        prevLevelAction(a)

      elif ke.isKeyDown({keyPageDown, keyKpAdd}) or
           ke.isKeyDown(keyEqual, {mkCtrl}):
        nextLevelAction(a)

      elif not opt.wasdMode and ke.isKeyDown(keyD):
        ui.editMode = emExcavate
        startExcavateAction(a)

      elif not opt.wasdMode and ke.isKeyDown(keyE):
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

      elif ke.isKeyDown(keyF):
        ui.editMode = emClearFloor
        setStatusMessage(IconEraser, "Clear floor",
                         @[IconArrowsAll, "clear"], a)
        actions.setFloor(map, cur, fEmpty, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(map, cur, um)
        if l.getFloorOrientation(cur.row, cur.col) == Horiz:
          setStatusMessage(IconArrowsHoriz,
                           "Floor orientation set to horizontal", a)
        else:
          setStatusMessage(IconArrowsVert,
                           "Floor orientation set to vertical", a)

      elif not opt.wasdMode and ke.isKeyDown(keyW):
        ui.editMode = emDrawWall
        startDrawWallsAction(a)

      elif ke.isKeyDown(keyR):
        ui.editMode = emDrawWallSpecial
        setStatusMessage("", "Draw wall special",
                         @[IconArrowsAll, "set/clear"], a)

      elif ke.isKeyDown(key1) or ke.isKeyDown(key1, {mkShift}):
        setOrCycleFloorAction(fDoor, fSecretDoor,
                               forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key2) or ke.isKeyDown(key2, {mkShift}):
        setOrCycleFloorAction(fPressurePlate, fHiddenPressurePlate,
                              forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key3) or ke.isKeyDown(key3, {mkShift}):
        setOrCycleFloorAction(fClosedPit, fCeilingPit,
                              forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key4) or ke.isKeyDown(key4, {mkShift}):
        setFloorAction(fTeleportSource, a)

      elif ke.isKeyDown(key5) or ke.isKeyDown(key5, {mkShift}):
        setOrCycleFloorAction(fStairsDown, fExitDoor,
                              forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key6) or ke.isKeyDown(key6, {mkShift}):
        setFloorAction(fSpinner, a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyU, repeat=true):
        if um.canUndo():
          let undoStateData = um.undo(map)
          moveCursorTo(undoStateData.location, a)
          setStatusMessage(IconUndo,
                           fmt"Undid action: {undoStateData.actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to undo", a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyR, {mkCtrl}, repeat=true):
        if um.canRedo():
          let undoStateData = um.redo(map)
          moveCursorTo(undoStateData.location, a)
          setStatusMessage(IconRedo,
                           fmt"Redid action: {undoStateData.actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to redo", a)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)
        koi.setFramesLeft()

      elif ke.isKeyDown(keyP):
        if ui.copyBuf.isSome:
          actions.paste(map, cur, ui.copyBuf.get, um)
          setStatusMessage(IconPaste, "Pasted buffer", a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyP, {mkShift}):
        if ui.copyBuf.isSome:
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          ui.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "paste", "Esc", "exit"], a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyG, {mkCtrl}):
        # TODO warning when map is empty?
        let sel = newSelection(l.rows, l.cols)
        sel.fill(true)
        ui.nudgeBuf = SelectionBuffer(level: l, selection: sel).some
        map.levels[cur.level] = newLevel(
          l.locationName, l.levelName, l.elevation, l.rows, l.cols
        )

        dp.selStartRow = 0
        dp.selStartCol = 0

        ui.editMode = emNudgePreview
        setStatusMessage(IconArrowsAll, "Nudge preview",
                         @[IconArrowsAll, "nudge",
                         "Enter", "confirm", "Esc", "exit"], a)

      elif ke.isKeyDown(keyG):
        if l.getFloor(cur.row, cur.col) == fTeleportSource:
          if map.links.hasKey(cur):
            let dest = map.links[cur]
            moveCursorTo(dest, a)
          else:
            setStatusMessage(IconWarning, "Teleport has no destination set", a)

        elif l.getFloor(cur.row, cur.col) == fTeleportDestination:
          let dest = cur
          let src = map.links.getKeyByVal(dest)
          moveCursorTo(src, a)

        else:
          setStatusMessage(IconWarning, "Current cell is not a teleport", a)

      elif ke.isKeyDown(keyG, {mkShift}):
        if l.getFloor(cur.row, cur.col) == fTeleportSource:
          ui.linkSrcLocation = cur
          ui.editMode = emSetTeleportDestination
          setStatusMessage(IconTeleport, "Set teleport destination",
                           @[IconArrowsAll, "select cell",
                           "Enter", "confirm", "Esc", "cancel"], a)
        else:
          setStatusMessage(IconWarning,
                           "Current cell is not a teleport source", a)

      elif ke.isKeyDown(keyEqual, repeat=true):
        incZoomLevelAction(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        decZoomLevelAction(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyN):
        if l.isFloorEmpty(cur.row, cur.col):
          setStatusMessage(IconWarning, "Cannot attach note to empty cell", a)
        else:
          openEditNoteDialog(a)

      elif ke.isKeyDown(keyN, {mkShift}):
        if l.isFloorEmpty(cur.row, cur.col):
          setStatusMessage(IconWarning, "No note to delete in cell", a)
        else:
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        openNewLevelDialog(a)

      elif ke.isKeyDown(keyN, {mkCtrl, mkAlt}):
        newMapAction(a)

      elif ke.isKeyDown(keyP, {mkCtrl}):
        openEditLevelPropsDialog(a)

      elif ke.isKeyDown(keyP, {mkCtrl, mkAlt}):
        openMapPropsDialog(a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        openResizeLevelDialog(a)

      elif ke.isKeyDown(keyO, {mkCtrl}):              openMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl}):          saveMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl, mkShift}): saveMapAsAction(a)

      elif ke.isKeyDown(keyR, {mkAlt,mkCtrl}):        reloadThemeAction(a)
      elif ke.isKeyDown(keyPageUp, {mkAlt,mkCtrl}):   prevThemeAction(a)
      elif ke.isKeyDown(keyPageDown, {mkAlt,mkCtrl}): nextThemeAction(a)

      # Toggle options
      elif ke.isKeyDown(keyC, {mkAlt}):
        toggleShowOption(dp.drawCellCoords, NoIcon, "Cell coordinates", a)

      elif ke.isKeyDown(keyN, {mkAlt}):
        toggleShowOption(opt.showNotesPane, NoIcon, "Notes pane", a)

      elif ke.isKeyDown(keyT, {mkAlt}):
        toggleShowOption(opt.showToolsPane, NoIcon, "Tools pane", a)

      elif ke.isKeyDown(keyBackslash):
        opt.walkMode = not opt.walkMode
        let msg = if opt.walkMode: "Walk mode" else: "Normal mode"
        setStatusMessage(msg, a)

      elif ke.isKeyDown(keyTab):
        toggleOnOffOption(opt.wasdMode, IconMouse, "WASD mode", a)

      elif ke.isKeyDown(keyT):
        toggleOnOffOption(opt.drawTrail, IconShoePrints, "Draw trail", a)

    # }}}
    # {{{ emExcavate, emEraseCell, emClearFloor
    of emExcavate, emEraseCell, emClearFloor:
      # This to prevent creating an undoable action for every turn in walk
      # mode
      let prevCursor = cur

      if opt.walkMode: handleMoveWalk()
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        handleMoveCursor(moveKeys)

      if cur != prevCursor:
        if   ui.editMode == emExcavate:   actions.excavate(map, cur, um)
        elif ui.editMode == emEraseCell:  actions.eraseCell(map, cur, um)
        elif ui.editMode == emClearFloor: actions.setFloor(map, cur, fEmpty, um)

      if not opt.wasdMode and ke.isKeyUp({keyD, keyE}):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isKeyUp({keyF}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(l, cur.row, cur.col, dir):
          let w = if l.getWall(cur.row, cur.col, dir) == wWall: wNone
                  else: wWall
          actions.setWall(map, cur, dir, w, um)

      handleMoveKeys(handleMoveKey)

      if not opt.wasdMode and ke.isKeyUp({keyW}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWallSpecial
    of emDrawWallSpecial:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(l, cur.row, cur.col, dir):
          var curSpecWall = SpecialWalls[ui.currSpecialWall]
          if   curSpecWall == wLeverSw:
            if dir in {dirN, dirE}: curSpecWall = wLeverNE
          elif curSpecWall == wNicheSw:
            if dir in {dirN, dirE}: curSpecWall = wNicheNE
          elif curSpecWall == wStatueSw:
            if dir in {dirN, dirE}: curSpecWall = wStatueNE

          let w = if l.getWall(cur.row, cur.col, dir) == curSpecWall: wNone
                  else: curSpecWall
          actions.setWall(map, cur, dir, w, um)

      handleMoveKeys(handleMoveKey)

      if ke.isKeyUp({keyR}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      handleMoveCursor(MoveKeysCursor)

      if koi.ctrlDown(): setSelectModeActionMessage(a)
      else:              setSelectModeSelectMessage(a)

      if   koi.keyDown(keyD): ui.selection.get[cur.row, cur.col] = true
      elif koi.keyDown(keyE): ui.selection.get[cur.row, cur.col] = false

      if   ke.isKeyDown(keyA): ui.selection.get.fill(true)
      elif ke.isKeyDown(keyU): ui.selection.get.fill(false)

      if ke.isKeyDown({keyR, Key.keyS}):
        ui.editMode = emSelectRect
        ui.selRect = some(SelectionRect(
          startRow: cur.row,
          startCol: cur.col,
          rect: rectN(cur.row, cur.col, cur.row+1, cur.col+1),
          selected: ke.isKeyDown(keyR)
        ))

      elif ke.isKeyDown({keyC, keyY}):
        let bbox = copySelection(a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isKeyDown(keyX):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(map, cur.level,
                                 ui.copyBuf.get.selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconCut, "Cut selection to buffer", a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.eraseSelection(map, cur.level,
                                 ui.copyBuf.get.selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isKeyDown(keyF, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.fillSelection(map, cur.level,
                                ui.copyBuf.get.selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Filled selection", a)

      elif ke.isKeyDown(Key.keyS, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          actions.surroundSelectionWithWalls(map, cur.level,
                                             ui.copyBuf.get.selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isKeyDown(keyR, {mkCtrl}):
        let sel = ui.selection.get
        let bbox = sel.boundingBox()
        if bbox.isSome:
          actions.cropLevel(map, cur, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Cropped map to selection", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      handleMoveCursor(MoveKeysCursor)

      var r1,c1, r2,c2: Natural
      if ui.selRect.get.startRow <= cur.row:
        r1 = ui.selRect.get.startRow
        r2 = cur.row+1
      else:
        r1 = cur.row
        r2 = ui.selRect.get.startRow + 1

      if ui.selRect.get.startCol <= cur.col:
        c1 = ui.selRect.get.startCol
        c2 = cur.col+1
      else:
        c1 = cur.col
        c2 = ui.selRect.get.startCol + 1

      ui.selRect.get.rect = rectN(r1,c1, r2,c2)

      if ke.isKeyUp({keyR, Key.keyS}):
        ui.selection.get.fill(ui.selRect.get.rect, ui.selRect.get.selected)
        ui.selRect = SelectionRect.none
        ui.editMode = emSelect

    # }}}
    # {{{ emPastePreview
    of emPastePreview:
      if opt.walkMode: handleMoveWalk()
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        handleMoveCursor(moveKeys)

      a.ui.drawLevelParams.selStartRow = a.ui.cursor.row
      a.ui.drawLevelParams.selStartCol = a.ui.cursor.col

      if ke.isKeyDown({keyEnter, keyP}):
        actions.paste(map, cur, ui.copyBuf.get, um)
        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      handleMoveKeys(moveSelStart)

      if   ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEnter):
        actions.nudgeLevel(map, cur, dp.selStartRow, dp.selStartCol,
                           ui.nudgeBuf.get, um)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        map.levels[cur.level] = ui.nudgeBuf.get.level
        ui.nudgeBuf = SelectionBuffer.none
        clearStatusMessage(a)

    # }}}
    # {{{ emSetTeleportDestination
    of emSetTeleportDestination:
      if opt.walkMode: handleMoveWalk()
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        handleMoveCursor(moveKeys)

      if ke.isKeyDown({keyPageUp, keyKpSubtract}) or
         ke.isKeyDown(keyMinus, {mkCtrl}):
        prevLevelAction(a)

      elif ke.isKeyDown({keyPageDown, keyKpAdd}) or
           ke.isKeyDown(keyEqual, {mkCtrl}):
        nextLevelAction(a)

      elif ke.isKeyDown(keyEnter):
        setFloorAction(fTeleportDestination, a)
        map.links[ui.linkSrcLocation] = cur
        ui.editMode = emNormal
        setStatusMessage(IconTeleport, "Teleport destination set", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  if koi.hasEvent() and koi.currEvent().kind == ekKey:
    let ke = koi.currEvent()

    if   ke.isKeyDown(keyN,        {mkCtrl, mkAlt}):   newMapAction(a)
    elif ke.isKeyDown(keyP,        {mkCtrl, mkAlt}):   openMapPropsDialog(a)

    elif ke.isKeyDown(keyO,        {mkCtrl}):          openMapAction(a)
    elif ke.isKeyDown(Key.keyS,    {mkCtrl}):          saveMapAction(a)
    elif ke.isKeyDown(Key.keyS,    {mkCtrl, mkShift}): saveMapAsAction(a)

    elif ke.isKeyDown(keyN,        {mkCtrl}):          openNewLevelDialog(a)

    elif ke.isKeyDown(keyR,        {mkCtrl, mkAlt}):   reloadThemeAction(a)
    elif ke.isKeyDown(keyPageUp,   {mkCtrl, mkAlt}):   prevThemeAction(a)
    elif ke.isKeyDown(keyPageDown, {mkCtrl, mkAlt}):   nextThemeAction(a)

# }}}

# {{{ renderUI()
proc renderUI() =
  alias(a, g_app)
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(dlg, a.dialog)

  let winWidth = koi.winWidth()
  let winHeight = koi.winHeight()

  # Clear background
  vg.beginPath()
  # TODO shouldn't calculate visible window area manually
  vg.rect(0, TitleBarHeight, winWidth.float, winHeight.float - TitleBarHeight)

  # TODO extend logic for other images
  if ui.style.backgroundImage == "old-paper":
    vg.fillPaint(ui.oldPaperPattern)
  else:
    vg.fillColor(ui.style.backgroundColor)
  vg.fill()

  # About button
  if button(x = winWidth - 55, y = 45, w = 20, h = 24, IconQuestion,
            style = ui.aboutButtonStyle):
    # TODO
    discard

  if not mapHasLevels(a):
    drawEmptyMap(a)
  else:
    let levelItems = a.doc.map.sortedLevelNames
    let levelSelectedItem = getCurrSortedLevelIdx(a)

    vg.fontSize(a.theme.levelDropdownStyle.labelFontSize)
    let levelDropdownWidth = vg.textWidth(levelItems[levelSelectedItem]) +
                             a.theme.levelDropdownStyle.labelPadHoriz * 2 + 8

    let sortedLevelIdx = koi.dropdown(
      x = (winWidth - levelDropdownWidth)*0.5,
      y = 45,
      w = levelDropdownWidth,
      h = 24.0,   # TODO calc y
      levelItems,
      levelSelectedItem,
      tooltip = "",
      disabled = not (ui.editMode in {emNormal, emSetTeleportDestination}),
      style = a.theme.levelDropdownStyle
    )
    ui.cursor.level = a.doc.map.sortedLevelIdxToLevelIdx[sortedLevelIdx]

    renderLevel(a)

    if a.opt.showNotesPane:
      drawNotesPane(
        x = NotesPaneLeftPad,
        y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
        w = winWidth - NotesPaneLeftPad - NotesPaneRightPad,
        h = NotesPaneHeight,
        a
      )

    if a.opt.showToolsPane:
      renderToolsPane(
        x = winWidth - ToolsPaneWidth,
        y = ToolsPaneTopPad,
        w = ToolsPaneWidth,
        h = winHeight - StatusBarHeight - ToolsPaneBottomPad,
        a
      )

    drawModeAndOptionIndicators(a)


  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  drawStatusBar(statusBarY, winWidth.float, a)

  # Dialogs
  if dlg.saveDiscardDialog.isOpen:
    saveDiscardDialog(dlg.saveDiscardDialog, a)

  elif dlg.newMapDialog.isOpen:
    newMapDialog(dlg.newMapDialog, a)

  elif dlg.editMapPropsDialog.isOpen:
    editMapPropsDialog(dlg.editMapPropsDialog, a)

  elif dlg.newLevelDialog.isOpen:
    newLevelDialog(dlg.newLevelDialog, a)

  elif dlg.editLevelPropsDialog.isOpen:
    editLevelPropsDialog(dlg.editLevelPropsDialog, a)

  elif dlg.editNoteDialog.isOpen:
    editNoteDialog(dlg.editNoteDialog, a)

  elif dlg.resizeLevelDialog.isOpen:
    resizeLevelDialog(dlg.resizeLevelDialog, a)

# }}}
# {{{ renderFramePre()
proc renderFramePre(win: CSDWindow) =
  alias(a, g_app)

  if a.theme.nextThemeIndex.isSome:
    let themeIndex = a.theme.nextThemeIndex.get
    a.theme.themeReloaded = themeIndex == a.theme.currThemeIndex
    loadTheme(themeIndex, a)
    a.ui.drawLevelParams.initDrawLevelParams(a.doc.levelStyle, a.vg,
                                             getPxRatio(a))
    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message

  a.win.title = a.doc.map.name
  a.win.modified = a.doc.undoManager.isModified

# }}}
# {{{ renderFrame()
proc renderFrame(win: CSDWindow, doHandleEvents: bool = true) =
  alias(a, g_app)

  if a.theme.nextThemeIndex.isSome:
    let themeName = a.theme.themeNames[a.theme.currThemeIndex]
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
    else:
      setStatusMessage(fmt"Switched to '{themeName}' theme", a)
    a.theme.nextThemeIndex = Natural.none

  if doHandleEvents:
    if mapHasLevels(a): handleGlobalKeyEvents(a)
    else:               handleGlobalKeyEvents_NoLevels(a)

  renderUI()

  if win.shouldClose:
    win.shouldClose = false
    when defined(NO_QUIT_DIALOG):
      a.shouldClose = true
    else:
      # TODO can we get rid of the isDialogOpen check somehow? (and then
      # remove from the koi API)
      if not koi.isDialogOpen():
        if a.doc.undoManager.isModified:
          a.dialog.saveDiscardDialog.isOpen = true
          a.dialog.saveDiscardDialog.action = proc (a) = a.shouldClose = true
          koi.setFramesLeft()
        else:
          a.shouldClose = true

# }}}

# {{{ Init & cleanup
proc initDrawLevelParams(a) =
  alias(dp, a.ui.drawLevelParams)

  dp = newDrawLevelParams()
  dp.drawCellCoords   = true
  dp.drawCursorGuides = false
  dp.initDrawLevelParams(a.doc.levelStyle, a.vg, getPxRatio(a))


proc loadImages(vg: NVGContext, a) =
  let img = vg.createImage("data/old-paper.jpg", {ifRepeatX, ifRepeatY})

  # TODO use exceptions instead (in the nanovg wrapper)
  if img == NoImage:
    quit "Could not load old paper image.\n"

  let (w, h) = vg.imageSize(img)
  a.ui.oldPaperPattern = vg.imagePattern(0, 0, w.float, h.float, angle=0,
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
  a.doc.undoManager = newUndoManager[Map, UndoStateData]()

  loadFonts(vg)
  loadImages(vg, a)


  let bs = koi.getDefaultButtonStyle()

  bs.labelFontSize   = 20.0
  bs.labelPadHoriz   = 0
  bs.labelOnly       = true
  bs.labelColor      = gray(1.0, 0.5)
  bs.labelColorHover = gray(1.0, 0.7)
  bs.labelColorDown  = gray(1.0, 0.9)

  a.ui.aboutButtonStyle = bs


  searchThemes(a)
  var themeIndex = findThemeIndex("beholder", a)
  if themeIndex == -1: themeIndex = 0
  loadTheme(themeIndex, a)

  # TODO proper init
  a.doc.map = newMap("Untitled Map")

  initDrawLevelParams(a)
  a.ui.drawLevelParams.setZoomLevel(a.doc.levelStyle, DefaultZoomLevel)
  a.opt.scrollMargin = 3

  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  a.ui.drawLevelParams.drawCellCoords = true
  a.opt.showNotesPane = true
  a.opt.showToolsPane = true

  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  let filename = "EOB III - Crystal Tower L2 notes.grm"
#  let filename = "EOB III - Crystal Tower L2.grm"
# let filename = "drawtest.grm"
#  let filename = "notetest.grm"
#  let filename = "pool-of-radiance-library.grm"
#  let filename = "teleport-test.grm"
#  let filename = "moveto-test.grm"
#  let filename = "pool-of-radiance-multi.grm"
  a.doc.map = readMap(filename)
  a.doc.filename = filename

  a.win.renderFramePreCb = renderFramePre
  a.win.renderFrameCb = renderFrame

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

  while not g_app.shouldClose:
    if koi.shouldRenderNextFrame():
      glfw.pollEvents()
    else:
      glfw.waitEvents()
    csdRenderFrame(g_app.win)

  cleanup()

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
