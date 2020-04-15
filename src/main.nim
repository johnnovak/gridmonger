import algorithm
import lenientops
import math
import options
import os
import sequtils
import strformat
import strutils
import sugar
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


# {{{ Constants
const
  ThemesDir = "themes"

  DefaultZoomLevel = 9

  StatusBarHeight = 26.0

  LevelLeftPad           = 50.0
  LevelRightPad          = 113.0
  LevelTopPadCoords      = 85.0
  LevelBottomPadCoords   = 40.0
  LevelTopPadNoCoords    = 65.0
  LevelBottomPadNoCoords = 10.0

  NotesPaneTopPad = 10.0
  NotesPaneHeight = 40.0
  NotesPaneBottomPad = 10.0


const
  MapFileExt * = "grm"
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

    undoManager: UndoManager[Map]

    shouldClose: bool


  Document = object
    filename:          string
    map:               Map
    levelStyle:        LevelStyle

  Options = object
    scrollMargin:      Natural
    showNotesPane:     bool

  UI = object
    style:             UIStyle
    cursor:            Location
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
    levelBottomPad:    float

    linkSrcLocation:   Location

    drawLevelParams:   DrawLevelParams
    toolbarDrawParams: DrawLevelParams

    oldPaperPattern:   Paint


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
  a.ui.statusIcon = ""
  a.ui.statusMessage = ""
  a.ui.statusCommands = @[]

# }}}
# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string], a) =
  a.ui.statusIcon = icon
  a.ui.statusMessage = msg
  a.ui.statusCommands = commands

proc setStatusMessage(icon, msg: string, a) =
  setStatusMessage(icon , msg, commands = @[], a)

proc setStatusMessage(msg: string, a) =
  setStatusMessage(icon = "", msg, commands = @[], a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar(y: float, winWidth: float, a) =
  alias(vg, a.vg)
  alias(s, a.ui.style.statusBarStyle)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
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

    vg.scissor(0, y, winWidth - tw - 15, StatusBarHeight)

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

  vg.resetScissor()

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

        initUndoManager(a.undoManager)

        resetCursorAndViewStart(a)
        setStatusMessage(IconFloppy, fmt"Map '{filename}' loaded", a)

      except CatchableError as e:
        # TODO log stracktrace?
        setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)
# }}}
# {{{ saveMapAction()
proc saveMap(filename: string, a) =
  writeMap(a.doc.map, filename)
  a.undoManager.setLastSaveState()
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
# {{{ Theme support
proc searchThemes(a) =
  for path in walkFiles(fmt"{ThemesDir}/*.cfg"):
    let (_, name, _) = splitFile(path)
    a.theme.themeNames.add(name)
  sort(a.theme.themeNames)

proc findThemeIndex(name: string, a): int =
  for i, n in a.theme.themeNames:
    if n == name:
      return i
  return -1

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
    d.labelFontSize            = 15.0
    d.labelColor               = s.labelColor
    d.labelColorHover          = s.labelColor
    d.labelColorActive         = s.labelColor
    d.labelColorDown           = s.labelColor
    d.labelAlign               = haCenter
    d.itemListFillColor        = s.itemListColor
    d.itemColor                = s.itemColor
    d.itemColorHover           = s.itemColorHover
    d.itemBackgroundColorHover = s.itemBgColorHover
    d.itemAlign                = haLeft
    d.itemListPadHoriz         = 10

# }}}

# {{{ getPxRatio()
proc getPxRatio(a): float =
  let
    (winWidth, _) = a.win.size
    (fbWidth, _) = a.win.framebufferSize
  result = fbWidth / winWidth

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
  a.ui.cursor.row = 0
  a.ui.cursor.col = 0
  a.ui.drawLevelParams.viewStartRow = 0
  a.ui.drawLevelParams.viewStartCol = 0

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.ui.drawLevelParams)
  let l = getCurrLevel(a)

  let (winWidth, winHeight) = a.win.size

  dp.startX = LevelLeftPad
  dp.startY = TitleBarHeight + a.ui.levelTopPad

  var drawAreaHeight = winHeight - TitleBarHeight - StatusBarHeight -
                       a.ui.levelTopPad - a.ui.levelBottomPad

  if a.opt.showNotesPane:
   drawAreaHeight -= NotesPaneTopPad + NotesPaneHeight + NotesPaneBottomPad

  let
    drawAreaWidth = winWidth - LevelLeftPad - LevelRightPad

  dp.viewRows = min(dp.numDisplayableRows(drawAreaHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(drawAreaWidth), l.cols)

  dp.viewStartRow = min(max(l.rows - dp.viewRows, 0), dp.viewStartRow)
  dp.viewStartCol = min(max(l.cols - dp.viewCols, 0), dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  a.ui.cursor.row = min(
    max(viewEndRow, dp.viewStartRow),
    a.ui.cursor.row
  )
  a.ui.cursor.col = min(
    max(viewEndCol, dp.viewStartCol),
    a.ui.cursor.col
  )

# }}}
# {{{ showCellCoords()
proc showCellCoords(show: bool, a) =
  alias(dp, a.ui.drawLevelParams)

  if show:
    a.ui.levelTopPad = LevelTopPadCoords
    a.ui.levelBottomPad = LevelBottomPadCoords
    dp.drawCellCoords = true
  else:
    a.ui.levelTopPad = LevelTopPadNoCoords
    a.ui.levelBottomPad = LevelBottomPadNoCoords
    dp.drawCellCoords = false

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, a) =
  alias(dp, a.ui.drawLevelParams)
  let l = getCurrLevel(a)

  var
    cx = a.ui.cursor.col
    cy = a.ui.cursor.row
    sx = dp.viewStartCol
    sy = dp.viewStartRow

  case dir:
  of dirE:
    cx = min(cx+1, l.cols-1)
    if cx - sx > dp.viewCols-1 - a.opt.scrollMargin:
      sx = min(max(l.cols - dp.viewCols, 0), sx+1)

  of dirS:
    cy = min(cy+1, l.rows-1)
    if cy - sy > dp.viewRows-1 - a.opt.scrollMargin:
      sy = min(max(l.rows - dp.viewRows, 0), sy+1)

  of dirW:
    cx = max(cx-1, 0)
    if cx < sx + a.opt.scrollMargin:
      sx = max(sx-1, 0)

  of dirN:
    cy = max(cy-1, 0)
    if cy < sy + a.opt.scrollMargin:
      sy = max(sy-1, 0)

  a.ui.cursor.row = cy
  a.ui.cursor.col = cx
  dp.viewStartRow = sy
  dp.viewStartCol = sx

# }}}
# {{{ moveCursorAndSelStart()
proc moveCursorAndSelStart(dir: CardinalDir, a) =
  moveCursor(dir, a)
  a.ui.drawLevelParams.selStartRow = a.ui.cursor.row
  a.ui.drawLevelParams.selStartCol = a.ui.cursor.col

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
  a.clearStatusMessage()

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

# {{{ openNewMapDialog()
proc openNewMapDialog(a) =
  alias(dlg, a.dialog.newMapDialog)
  dlg.name = ""
  dlg.isOpen = true

# }}}
# {{{ openNewLevelDialog()
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
    dlg.locationName = ""
    dlg.levelName = ""
    dlg.elevation = "0"
    dlg.rows = "16"
    dlg.cols = "16"

  dlg.isOpen = true

# }}}
# {{{ newMapAction()
proc newMapAction(a) =
  if a.undoManager.isModified:
    a.dialog.saveDiscardDialog.isOpen = true
    a.dialog.saveDiscardDialog.action = proc (a: var AppContext) =
      openNewMapDialog(a)
  else:
    openNewMapDialog(a)

# }}}
# {{{ openMapAction()
proc openMapAction(a) =
  alias(dlg, a.dialog.saveDiscardDialog)
  if a.undoManager.isModified:
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

# {{{ drawNotesPane()
proc drawNotesPane(x, y, w, h: float, a) =
  alias(vg, a.vg)
  alias(ls, a.doc.levelStyle)

  let l = getCurrLevel(a)
  let cur = a.ui.cursor

  if not (a.ui.editMode in {emPastePreview, emNudgePreview}) and
     l.hasNote(cur.row, cur.col):

    let note = l.getNote(cur.row, cur.col)
    case note.kind
    of nkIndexed:
      drawIndexedNote(x-40, y-12, note.index, 36,
                      bgColor=ls.notePaneIndexBgColor[note.indexColor],
                      fgColor=ls.notePaneIndexColor, vg)

    of nkCustomId:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(18.0, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-22, y-2, note.customId)

    of nkIcon:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-3, NoteIcons[note.icon])

    of nkComment:
      vg.fillColor(ls.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-2, IconComment)

    vg.fillColor(ls.notePaneTextColor)
    vg.setFont(14.5, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.4)
    vg.scissor(x, y, w, h)
    vg.textBox(x, y, w, note.text)
    vg.resetScissor()


# }}}
# {{{ Dialogs
# {{{ Save/discard changes dialog
proc saveDiscardDialog(dlg: var SaveDiscardDialogParams, a) =
  let
    dialogWidth = 350.0
    dialogHeight = 160.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconFloppy}  Save Changes?")
  a.clearStatusMessage()

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

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyEscape):     cancelAction(dlg, a)
    elif ke.isKeyDown(keyD, {mkAlt}): discardAction(dlg, a)
    elif ke.isKeyDown(keyEnter):      saveAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ New level dialog
proc newLevelDialog(dlg: var NewLevelDialogParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 300.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  New Level")
  a.clearStatusMessage()

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
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.locationName
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Level Name")
  dlg.levelName = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.levelName
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Elevation")
  dlg.elevation = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.elevation
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Rows")
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.rows
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Columns")
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.cols
  )

  proc okAction(dlg: var NewLevelDialogParams, a) =
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

  if koi.button(x, y, buttonWidth, h, fmt"{IconCheck} OK"):
    okAction(dlg, a)

  x += buttonWidth + 10
  if koi.button(x, y, buttonWidth, h, fmt"{IconClose} Cancel"):
    cancelAction(dlg, a)

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit level properties dialog
proc editLevelPropsDialog(dlg: var EditLevelPropsParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 224.0

  koi.beginDialog(dialogWidth, dialogHeight,
                  fmt"{IconNewFile}  Edit Level Properties")
  a.clearStatusMessage()

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
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.locationName
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Level Name")
  dlg.levelName = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.levelName
  )

  y += 44
  koi.label(x, y, labelWidth, h, "Elevation")
  dlg.elevation = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.elevation
  )

  proc okAction(dlg: var EditLevelPropsParams, a) =
    # TODO number error checking
    let elevation = parseInt(dlg.elevation)

    actions.setLevelProps(a.doc.map, a.ui.cursor.level,
                          dlg.locationName, dlg.levelName, elevation,
                          a.undoManager)

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

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ New map dialog
proc newMapDialog(dlg: var NewMapDialogParams, a) =
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
  dlg.name = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.name
  )

  proc okAction(dlg: var NewMapDialogParams, a) =
    a.doc.filename = ""
    a.doc.map = newMap(dlg.name)
    initUndoManager(a.undoManager)

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, fmt"New map created", a)

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

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit map properties dialog
proc editMapPropsDialog(dlg: var EditMapPropsDialogParams, a) =
  let
    dialogWidth = 410.0
    dialogHeight = 150.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconNewFile}  Edit Map Properties")
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
  dlg.name = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.name
  )

  proc okAction(dlg: var EditMapPropsDialogParams, a) =
    # TODO should be action
    a.doc.map.name = dlg.name

    setStatusMessage(IconFile, fmt"Map properties updated", a)

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

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

  koi.endDialog()

# }}}
# {{{ Edit note dialog
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
  a.clearStatusMessage()

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
      tooltips = @[],
      ord(dlg.kind)
    )
  )

  y += 40
  koi.label(x, y, labelWidth, h, "Text")
  dlg.text = koi.textField(
    x + labelWidth, y, 355, h, tooltip = "", dlg.text
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
      tooltips = @[],
      dlg.indexColor,
      layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc=colorRadioButtonDrawProc(ls.noteLevelIndexBgColor,
                                        ls.cursorColor).some
    )

  of nkCustomId:
    koi.label(x, y, labelWidth, h, "ID")
    dlg.customId = koi.textField(
      x + labelWidth, y, 50.0, h, tooltip = "", dlg.customId
    )

  of nkIcon:
    koi.label(x, y, labelWidth, h, "Icon")
    dlg.icon = koi.radioButtons(
      x + labelWidth, y, 35, 35,
      labels = NoteIcons,
      tooltips = @[],
      dlg.icon,
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

    actions.setNote(a.doc.map, a.ui.cursor, note, a.undoManager)

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

  for ke in koi.keyBuf():
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

    elif ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

    koi.setFramesLeft()

  koi.endDialog()

# }}}
# {{{ Resize level dialog

proc resizeLevelDialog(dlg: var ResizeLevelDialogParams, a) =

  let dialogWidth = 270.0
  let dialogHeight = 300.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCrop}  Resize Level")
  a.clearStatusMessage()

  let
    h = 24.0
    labelWidth = 70.0
    buttonWidth = 80.0
    buttonPad = 15.0

  var x = 30.0
  var y = 60.0

  koi.label(x, y, labelWidth, h, "Rows")
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.rows
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Columns")
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.cols
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
    tooltips = @["Top-left", "Top", "Top-right",
                 "Left", "Center", "Right",
                 "Bottom-left", "Bottom", "Bottom-right"],
    ord(dlg.anchor),
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

    actions.resizeLevel(a.doc.map, a.ui.cursor.level, newRows, newCols, align,
                        a.undoManager)

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

  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyH, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dc= -1).ResizeAnchor

    elif ke.isKeyDown(keyL, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dc=1).ResizeAnchor

    elif ke.isKeyDown(keyK, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dr= -1).ResizeAnchor

    elif ke.isKeyDown(keyJ, repeat=true):
      dlg.anchor = moveIcon(ord(dlg.anchor), dr=1).ResizeAnchor

    elif ke.isKeyDown(keyEscape): cancelAction(dlg, a)
    elif ke.isKeyDown(keyEnter):  okAction(dlg, a)

    koi.setFramesLeft()

  koi.endDialog()

# }}}
# }}}

# {{{ handleLevelEvents()
proc handleLevelEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(cur, a.ui.cursor)
  alias(um, a.undoManager)
  alias(dp, a.ui.drawLevelParams)
  alias(ls, a.doc.levelStyle)
  alias(win, a.win)

  var l = getCurrLevel(a)

  proc mkFloorMessage(f: Floor): string =
    fmt"Set floor – {f}"

  proc setFloorOrientationStatusMessage(o: Orientation, a) =
    if o == Horiz:
      setStatusMessage(IconArrowsHoriz, "Floor orientation set to horizontal", a)
    else:
      setStatusMessage(IconArrowsVert, "Floor orientation set to vertical", a)

  proc incZoomLevel(a) =
    incZoomLevel(ls, dp)

  proc decZoomLevel(a) =
    decZoomLevel(ls, dp)

  proc setFloor(f: Floor, a) =
    let ot = l.guessFloorOrientation(cur.row, cur.col)
    actions.setOrientedFloor(map, cur, f, ot, um)
    setStatusMessage(mkFloorMessage(f), a)

  proc setOrCycleFloor(first, last: Floor, forward: bool, a) =
    assert first <= last

    var floor = l.getFloor(cur.row, cur.col)
    if floor >= first and floor <= last:
      var f = ord(floor)
      let first = ord(first)
      let last = ord(last)
      if forward: inc(f) else: dec(f)
      floor = (first + floorMod(f-first, last-first+1)).Floor
    else:
      floor = if forward: first else: last
    setFloor(floor, a)

  const
    MoveKeysLeft  = {keyLeft,  keyH, keyKp4}
    MoveKeysRight = {keyRight, keyL, keyKp6}
    MoveKeysUp    = {keyUp,    keyK, keyKp8}
    MoveKeysDown  = {keyDown,  keyJ, keyKp2}

  # TODO these should be part of the level component event handler
  for ke in koi.keyBuf():
    case ui.editMode:
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
        ui.editMode = emExcavate
        setStatusMessage(IconPencil, "Excavate tunnel",
                         @[IconArrowsAll, "draw"], a)
        actions.excavate(map, cur, um)

      elif ke.isKeyDown(keyE):
        ui.editMode = emEraseCell
        setStatusMessage(IconEraser, "Erase cells",
                         @[IconArrowsAll, "erase"], a)
        actions.eraseCell(map, cur, um)

      elif ke.isKeyDown(keyF):
        ui.editMode = emClearFloor
        setStatusMessage(IconEraser, "Clear floor",
                         @[IconArrowsAll, "clear"], a)
        actions.setFloor(map, cur, fEmpty, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(map, cur, um)
        setFloorOrientationStatusMessage(
          l.getFloorOrientation(cur.row, cur.col), a)

      elif ke.isKeyDown(keyW):
        ui.editMode = emDrawWall
        setStatusMessage("", "Draw walls", @[IconArrowsAll, "set/clear"], a)

      elif ke.isKeyDown(keyR):
        ui.editMode = emDrawWallSpecial
        setStatusMessage("", "Draw wall special",
                         @[IconArrowsAll, "set/clear"], a)

      elif ke.isKeyDown(key1) or ke.isKeyDown(key1, {mkShift}):
        setOrCycleFloor(fDoor, fSecretDoor, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key2) or ke.isKeyDown(key2, {mkShift}):
        setOrCycleFloor(fPressurePlate, fHiddenPressurePlate,
                        forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key3) or ke.isKeyDown(key3, {mkShift}):
        setOrCycleFloor(fClosedPit, fCeilingPit,
                        forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key4) or ke.isKeyDown(key4, {mkShift}):
        setFloor(fTeleportSource, a)

      elif ke.isKeyDown(key5) or ke.isKeyDown(key5, {mkShift}):
        setOrCycleFloor(fStairsDown, fExitDoor,
                        forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key6) or ke.isKeyDown(key6, {mkShift}):
        setFloor(fSpinner, a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyU, repeat=true):
        if um.canUndo():
          let actionName = um.undo(map)
          # TODO move cursor to action
          setStatusMessage(IconUndo, fmt"Undid action: {actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to undo", a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyR, {mkCtrl}, repeat=true):
        if um.canRedo():
          let actionName = um.redo(map)
          # TODO move cursor to action
          setStatusMessage(IconRedo, fmt"Redid action: {actionName}", a)
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
            cur = dest
          else:
            setStatusMessage(IconWarning, "Teleport has no destination set", a)

        elif l.getFloor(cur.row, cur.col) == fTeleportDestination:
          let dest = cur
          let src = map.links.getKeyByVal(dest)
          cur = src

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
        incZoomLevel(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        decZoomLevel(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyN):
        if l.getFloor(cur.row, cur.col) == fNone:
          setStatusMessage(IconWarning, "Cannot attach note to empty cell", a)
        else:
          alias(dlg, a.dialog.editNoteDialog)
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

      elif ke.isKeyDown(keyN, {mkShift}):
        if l.getFloor(cur.row, cur.col) == fNone:
          setStatusMessage(IconWarning, "No note to delete in cell", a)
        else:
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        openNewLevelDialog(a)

      elif ke.isKeyDown(keyN, {mkCtrl, mkAlt}):
        newMapAction(a)

      elif ke.isKeyDown(keyP, {mkCtrl}):
        alias(dlg, a.dialog.editLevelPropsDialog)
        dlg.locationName = l.locationName
        dlg.levelName = l.levelName
        dlg.elevation = $l.elevation
        dlg.isOpen = true

      elif ke.isKeyDown(keyP, {mkCtrl, mkAlt}):
        alias(dlg, a.dialog.editMapPropsDialog)
        dlg.name = $map.name
        dlg.isOpen = true

      elif ke.isKeyDown(keyE, {mkCtrl}):
        alias(dlg, a.dialog.resizeLevelDialog)
        dlg.rows = $l.rows
        dlg.cols = $l.cols
        dlg.anchor = raCenter
        dlg.isOpen = true

      elif ke.isKeyDown(keyO, {mkCtrl}):              openMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl}):          saveMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl, mkShift}): saveMapAsAction(a)

      elif ke.isKeyDown(keyR, {mkAlt,mkCtrl}):        reloadThemeAction(a)
      elif ke.isKeyDown(keyPageUp, {mkAlt,mkCtrl}):   prevThemeAction(a)
      elif ke.isKeyDown(keyPageDown, {mkAlt,mkCtrl}): nextThemeAction(a)

      # Toggle options
      elif ke.isKeyDown(keyC, {mkAlt}):
        var state: string
        if dp.drawCellCoords:
          showCellCoords(false, a)
          state = "off"
        else:
          showCellCoords(true, a)
          state = "on"

        setStatusMessage(fmt"Cell coordinates turned {state}", a)

      elif ke.isKeyDown(keyN, {mkAlt}):
        if a.opt.showNotesPane:
          setStatusMessage(fmt"Notes pane shown", a)
          a.opt.showNotesPane = false
        else:
          setStatusMessage(fmt"Notes pane hidden", a)
          a.opt.showNotesPane = true

    of emExcavate, emEraseCell, emClearFloor:
      proc handleMoveKey(dir: CardinalDir, a) =
        if ui.editMode == emExcavate:
          moveCursor(dir, a)
          actions.excavate(map, cur, um)

        elif ui.editMode == emEraseCell:
          moveCursor(dir, a)
          actions.eraseCell(map, cur, um)

        elif ui.editMode == emClearFloor:
          moveCursor(dir, a)
          actions.setFloor(map, cur, fEmpty, um)

      if ke.isKeyDown(MoveKeysLeft,  repeat=true): handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyD, keyE, keyF}):
        ui.editMode = emNormal
        a.clearStatusMessage()

    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, a) =
        if canSetWall(l, cur.row, cur.col, dir):
          let w = if l.getWall(cur.row, cur.col, dir) == wWall: wNone
                  else: wWall
          actions.setWall(map, cur, dir, w, um)

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyW}):
        ui.editMode = emNormal
        a.clearStatusMessage()

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

      if ke.isKeyDown(MoveKeysLeft):  handleMoveKey(dirW, a)
      if ke.isKeyDown(MoveKeysRight): handleMoveKey(dirE, a)
      if ke.isKeyDown(MoveKeysUp):    handleMoveKey(dirN, a)
      if ke.isKeyDown(MoveKeysDown):  handleMoveKey(dirS, a)

      elif ke.isKeyUp({keyR}):
        ui.editMode = emNormal
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
      if   win.isKeyDown(keyD): ui.selection.get[cur.row, cur.col] = true
      elif win.isKeyDown(keyE): ui.selection.get[cur.row, cur.col] = false

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

      elif ke.isKeyDown(keyC, {mkCtrl}):
        let bbox = copySelection(a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isKeyDown(keyX, {mkCtrl}):
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
          actions.cropLevel(map, cur.level, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Cropped map to selection", a)

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

    of emPastePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true):
        moveCursorAndSelStart(dirW, a)

      if ke.isKeyDown(MoveKeysRight, repeat=true):
        moveCursorAndSelStart(dirE, a)

      if ke.isKeyDown(MoveKeysUp,    repeat=true):
        moveCursorAndSelStart(dirN, a)

      if ke.isKeyDown(MoveKeysDown,  repeat=true):
        moveCursorAndSelStart(dirS, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(map, cur, ui.copyBuf.get, um)
        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        a.clearStatusMessage()

    of emNudgePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveSelStart(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveSelStart(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveSelStart(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveSelStart(dirS, a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEnter):
        actions.nudgeLevel(map, cur.level,
                           dp.selStartRow, dp.selStartCol, ui.nudgeBuf.get, um)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        map.levels[cur.level] = ui.nudgeBuf.get.level
        ui.nudgeBuf = SelectionBuffer.none
        a.clearStatusMessage()

    of emSetTeleportDestination:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveCursor(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveCursor(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveCursor(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveCursor(dirS, a)

      if ke.isKeyDown(keyEnter):
        setFloor(fTeleportDestination, a)
        map.links[ui.linkSrcLocation] = cur
        ui.editMode = emNormal
        setStatusMessage(IconTeleport, "Teleport destination set", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        a.clearStatusMessage()


# }}}
# {{{ handleLevelEventsNoLevels()
proc handleLevelEventsNoLevels(a) =
  for ke in koi.keyBuf():
    if   ke.isKeyDown(keyN,        {mkCtrl, mkAlt}):   newMapAction(a)
    elif ke.isKeyDown(keyO,        {mkCtrl}):          openMapAction(a)
    elif ke.isKeyDown(Key.keyS,    {mkCtrl}):          saveMapAction(a)
    elif ke.isKeyDown(Key.keyS,    {mkCtrl, mkShift}): saveMapAsAction(a)

    elif ke.isKeyDown(keyN,        {mkCtrl}):          openNewLevelDialog(a)

    elif ke.isKeyDown(keyR,        {mkAlt, mkCtrl}):   reloadThemeAction(a)
    elif ke.isKeyDown(keyPageUp,   {mkAlt, mkCtrl}):   prevThemeAction(a)
    elif ke.isKeyDown(keyPageDown, {mkAlt, mkCtrl}):   nextThemeAction(a)

# }}}
# {{{ renderUI()

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
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(ls, 6)
      vg.scissor(x+4.5, y+3, dp.gridSize-3, dp.gridSize-2)
      body
      dp.setZoomLevel(ls, 4)
      vg.resetScissor()

    case SpecialWalls[buttonIdx]
    of wNone:          discard
    of wWall:          drawSolidWallHoriz(cx, cy, ctx)
    of wIllusoryWall:  drawIllusoryWallHoriz(cx+2, cy, ctx)
    of wInvisibleWall: drawInvisibleWallHoriz(cx, cy, ctx)
    of wDoor:          drawDoorHoriz(cx, cy, ctx)
    of wLockedDoor:    drawLockedDoorHoriz(cx, cy, ctx)
    of wArchway:       drawArchwayHoriz(cx, cy, ctx)

    of wSecretDoor:
      drawAtZoomLevel6: drawSecretDoorHoriz(cx-2, cy, ctx)

    of wLeverSW:
      drawAtZoomLevel6: drawLeverHorizSW(cx-2, cy+1, ctx)

    of wNicheSW:       drawNicheHorizSW(cx, cy, ctx)

    of wStatueSW:
      drawAtZoomLevel6: drawStatueHorizSW(cx-2, cy+2, ctx)

    of wKeyhole:
      drawAtZoomLevel6: drawKeyholeHoriz(cx-2, cy, ctx)

    else: discard


proc renderUI() =
  alias(a, g_app)
  alias(ui, a.ui)
  alias(dp, a.ui.drawLevelParams)
  alias(ls, a.doc.levelStyle)
  alias(vg, a.vg)
  alias(dlg, a.dialog)

  let (winWidth, winHeight) = a.win.size

  # Clear background
  vg.beginPath()
  vg.rect(0, TitleBarHeight, winWidth.float, winHeight.float - TitleBarHeight)

  # TODO extend logic for other images
  if ui.style.backgroundImage == "old-paper":
    vg.fillPaint(ui.oldPaperPattern)
  else:
    vg.fillColor(ui.style.backgroundColor)
  vg.fill()

  if mapHasLevels(a):
    const LevelDropdownWidth = 320

    let sortedLevelIdx = koi.dropdown(
      (winWidth - LevelDropdownWidth)*0.5, 45, LevelDropdownWidth, 24.0,   # TODO calc y
      a.doc.map.sortedLevelNames,
      tooltip = "Current map level",
      getCurrSortedLevelIdx(a),
      style = a.theme.levelDropdownStyle
    )
    ui.cursor.level = a.doc.map.sortedLevelIdxToLevelIdx[sortedLevelIdx]

    updateViewStartAndCursorPosition(a)

    # Draw current level
    if dp.viewRows > 0 and dp.viewCols > 0:
      dp.cursorRow = ui.cursor.row
      dp.cursorCol = ui.cursor.col

      dp.selection = ui.selection
      dp.selectionRect = ui.selRect

      dp.selectionBuffer =
        if ui.editMode == emPastePreview: ui.copyBuf
        elif ui.editMode == emNudgePreview: ui.nudgeBuf
        else: SelectionBuffer.none

      drawLevel(getCurrLevel(a), DrawLevelContext(ls: ls, dp: dp, vg: a.vg))

    if a.opt.showNotesPane:
      drawNotesPane(
        x = LevelLeftPad,
        y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
        w = winWidth - LevelLeftPad*2,  # TODO
        h = NotesPaneHeight,
        a
      )

    # Right-side toolbar
    ui.currSpecialWall = koi.radioButtons(
      winWidth - 60.0, 90, 36, 35,
      labels = newSeq[string](SpecialWalls.len),
      tooltips = @[],
      ui.currSpecialWall,
      layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 20),
      drawProc=specialWallDrawProc(ls, ui.toolbarDrawParams).some
    )

    ui.currFloorColor = koi.radioButtons(
  #    winWidth - 50.0, 90, 28, 28,
      winWidth - 57.0, 460, 30, 30,
      labels = newSeq[string](4),
      tooltips = @[],
      ui.currFloorColor,
      layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 8),
      drawProc=colorRadioButtonDrawProc(ls.noteLevelIndexBgColor,
                                        ls.cursorColor).some
    )

  else:
    vg.fontSize(22)
    vg.fillColor(ls.drawColor)
    vg.textAlign(haCenter, vaMiddle)
    var y = winHeight*0.5
    discard vg.text(winWidth*0.5 , y, "Empty map")

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, winWidth.float, a)

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
  a.win.modified = a.undoManager.isModified

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
    if mapHasLevels(a): handleLevelEvents(a)
    else:               handleLevelEventsNoLevels(a)

  renderUI()

  if win.shouldClose:
    win.shouldClose = false
    when defined(NO_QUIT_DIALOG):
      a.shouldClose = true
    else:
      if not koi.isDialogActive():
        if a.undoManager.isModified:
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
  a.undoManager = newUndoManager[Map]()

  loadFonts(vg)
  loadImages(vg, a)

  searchThemes(a)
  var themeIndex = findThemeIndex("oldpaper", a)
  if themeIndex == -1: themeIndex = 0
  loadTheme(themeIndex, a)

  # TODO proper init
  a.doc.map = newMap("Untitled")

  initDrawLevelParams(a)
  a.ui.drawLevelParams.setZoomLevel(a.doc.levelStyle, DefaultZoomLevel)
  a.opt.scrollMargin = 3

  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  showCellCoords(true, a)
  a.opt.showNotesPane = true

  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

#  let filename = "EOB III - Crystal Tower L2 notes.grm"
#  let filename = "EOB III - Crystal Tower L2.grm"
# let filename = "drawtest.grm"
#  let filename = "notetest.grm"
#  let filename = "pool-of-radiance-library.grm"
#  let filename = "teleport-test.grm"
#  a.doc.map = readMap(filename)
#  a.doc.filename = filename

  a.win.renderFramePreCb = renderFramePre
  a.win.renderFrameCb = renderFrame

  # TODO for development
#  a.win.size = (960, 1040)
#  a.win.pos = (960, 0)
  a.win.size = (700, 900)
  a.win.pos = (900, 0)
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
