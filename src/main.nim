import algorithm
import lenientops
import math
import options
import os
import sugar
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
import icons
import map
import persistence
import selection
import theme
import undomanager
import utils


# TODO
const SpecialWalls = @[
  wIllusoryWall,
  wInvisibleWall,
  wDoor,
  wLockedDoor,
  wArchway,
  wSecretDoor,
  wLeverSW,
  wNicheSW,
  wStatueSW
]


# {{{ Constants
const
  ThemesDir = "themes"

  DefaultZoomLevel = 9

  StatusBarHeight = 26.0

  MapLeftPad           = 50.0
  MapRightPad          = 113.0
  MapTopPadCoords      = 85.0
  MapBottomPadCoords   = 40.0
  MapTopPadNoCoords    = 65.0
  MapBottomPadNoCoords = 10.0

  NotesPaneTopPad = 10.0
  NotesPaneHeight = 40.0
  NotesPaneBottomPad = 10.0


const
  MapFileExt * = "grm"
  GridmongerMapFileFilter = fmt"Gridmonger Map (*.{MapFileExt}):{MapFileExt}"

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
    emPastePreview,
    emNudgePreview

  AppContext = ref object
    shouldClose:    bool

    # Context
    win:            CSDWindow
    vg:             NVGContext

    # Dependencies
    undoManager:    UndoManager[Map]

    # Document (TODO group under 'doc'?)
    filename:       string
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
    currFloorColor:     Natural

    selection:      Option[Selection]
    selRect:        Option[SelectionRect]
    copyBuf:        Option[SelectionBuffer]
    nudgeBuf:       Option[SelectionBuffer]

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

    mapDropdownStyle:  DropdownStyle

    # Dialogs
    saveDiscardDialog: SaveDiscardDialogParams
    newMapDialog:      NewMapDialogParams
    editNoteDialog:    EditNoteDialogParams
    resizeMapDialog:   ResizeMapDialogParams

    # Images
    oldPaperImage:  Image

  SaveDiscardDialogParams = object
    isOpen: bool
    action: proc (a: var AppContext)

  NewMapDialogParams = object
    isOpen:   bool
    name:     string
    rows:     string
    cols:     string

  EditNoteDialogParams = object
    isOpen:     bool
    editMode:   bool
    row:        Natural
    col:        Natural
    kind:       NoteKind
    index:      Natural
    indexColor: Natural
    customId:   string
    icon:       Natural
    text:       string

  ResizeMapDialogParams = object
    isOpen:   bool
    rows:     string
    cols:     string
    anchor:   ResizeAnchor

  ResizeAnchor = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


var g_app: AppContext

using a: var AppContext

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
  alias(s, a.uiStyle.statusBarStyle)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(s.backgroundColor)
  vg.fill()

  # Display current coords
  vg.setFont(14.0)

  let cursorPos = fmt"({m.rows-1 - a.cursorRow}, {a.cursorCol})"
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
proc updateViewStartAndCursorPosition(a)

proc openMap(a) =
  when defined(DEBUG): discard
  else:
    let filename = fileDialog(fdOpenFile,
                              filters=GridmongerMapFileFilter)
    if filename != "":
      try:
        a.map = readMap(filename)
        a.filename = filename
        a.win.title = filename

        initUndoManager(a.undoManager)

        resetCursorAndViewStart(a)
        updateViewStartAndCursorPosition(a)
        setStatusMessage(IconFloppy, fmt"Map '{filename}' loaded", a)

      except CatchableError as e:
        # TODO log stracktrace?
        setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)
# }}}
# {{{ saveMap()
proc saveMap(filename: string, a) =
  writeMap(a.map, filename)
  a.undoManager.setLastSaveState()
  setStatusMessage(IconFloppy, fmt"Map '{filename}' saved", a)

proc saveMapAs(a) =
  when not defined(DEBUG):
    var filename = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if filename != "":
      try:
        filename = addFileExt(filename, MapFileExt)
        saveMap(filename, a)
        a.filename = filename
        a.win.title = filename
      except CatchableError as e:
        # TODO log stracktrace?
        setStatusMessage(IconWarning, fmt"Cannot save map: {e.msg}", a)

proc saveMap(a) =
  if a.filename != "": saveMap(a.filename, a)
  else: saveMapAs(a)

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

  # TODO
  var labelStyle = koi.getDefaultLabelStyle()
  labelStyle.fontSize = 14
  labelStyle.color = gray(0.8)
  labelStyle.align = haLeft
  koi.setDefaultLabelStyle(labelStyle)

  # TODO
  alias(s, a.uiStyle)

  a.win.setStyle(s.titleBarStyle)

  block:
    alias(d, a.mapDropdownStyle)
    alias(s, s.mapDropdownStyle)

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
    d.itemAlign                = haCenter
    d.itemListPadHoriz         = 0

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
# {{{ moveCursorAndSelStart()
proc moveCursorAndSelStart(dir: CardinalDir, a) =
  moveCursor(dir, a)
  a.drawMapParams.selStartRow = a.cursorRow
  a.drawMapParams.selStartCol = a.cursorCol

# }}}
# {{{ moveSelStart()
proc moveSelStart(dir: CardinalDir, a) =
  alias(dp, a.drawMapParams)

  let cols = a.nudgeBuf.get.map.cols
  let rows = a.nudgeBuf.get.map.cols

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

  proc eraseOrphanedWalls(cb: SelectionBuffer) =
    var m = cb.map
    for r in 0..<m.rows:
      for c in 0..<m.cols:
        m.eraseOrphanedWalls(r,c)

  let sel = a.selection.get

  let bbox = sel.boundingBox()
  if bbox.isSome:
    a.copyBuf = some(SelectionBuffer(
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

  if not (a.editMode in {emPastePreview, emNudgePreview}) and
     m.hasNote(curRow, curCol):

    let note = m.getNote(curRow, curCol)
    case note.kind
    of nkIndexed:
      drawIndexedNote(x-40, y-12, note.index, 36,
                      bgColor=ms.notePaneIndexBgColor[note.indexColor],
                      fgColor=ms.notePaneIndexColor, vg)

    of nkCustomId:
      vg.fillColor(ms.notePaneTextColor)
      vg.setFont(18.0, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-22, y-2, note.customId)

    of nkIcon:
      vg.fillColor(ms.notePaneTextColor)
      vg.setFont(19.0, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x-20, y-3, NoteIcons[note.icon])

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
# {{{ Dialogs
# {{{ Save/discard changes dialog
proc saveDiscardDialog(dlg: var SaveDiscardDialogParams, a) =
  let
    dialogWidth = 350.0
    dialogHeight = 160.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconFloppy}  Save changes?")
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
    saveMap(a)
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
# {{{ New map dialog
proc openNewMapDialog(a) =
  a.newMapDialog.name = ""
  a.newMapDialog.rows = $a.map.rows
  a.newMapDialog.cols = $a.map.cols
  a.newMapDialog.isOpen = true

proc newMapDialog(dlg: var NewMapDialogParams, a) =
  let
    dialogWidth = 350.0
    dialogHeight = 224.0

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

  koi.label(x, y, labelWidth, h, "Name")
  dlg.name = koi.textField(
    x + labelWidth, y, 220.0, h, tooltip = "", dlg.name
  )

  y += 40
  koi.label(x, y, labelWidth, h, "Rows")
  dlg.rows = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.rows
  )

  y += 32
  koi.label(x, y, labelWidth, h, "Columns")
  dlg.cols = koi.textField(
    x + labelWidth, y, 60.0, h, tooltip = "", dlg.cols
  )

  proc okAction(dlg: var NewMapDialogParams, a) =
    # TODO number error checking
    let rows = parseInt(dlg.rows)
    let cols = parseInt(dlg.cols)

    a.map = newMap(rows, cols)
    a.filename = ""
    a.win.title = "[Untitled]"

    initUndoManager(a.undoManager)

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, fmt"New {rows}x{cols} map created", a)

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
# {{{ Edit note dialog
proc indexColorDrawProc(ms: MapStyle): RadioButtonsDrawProc =
  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               hover, active, down, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var col = ms.noteMapIndexBgColor[buttonIdx]

    if hover:
      col = col.lerp(white(), 0.3)
    if down:
      col = col.lerp(black(), 0.3)

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if active:
      vg.beginPath()
      vg.strokeColor(ms.cursorColor)
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
  let ms = a.mapStyle

  let
    dialogWidth = 500.0
    dialogHeight = 370.0
    title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCommentInv}  {title}")
  a.clearStatusMessage()

  let
    h = 24.0
    radioButtonSize = 20
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

  const NumIndexColors = ms.noteMapIndexBgColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of nkIndexed:
    koi.label(x, y, labelWidth, h, "Color")
    dlg.indexColor = koi.radioButtons(
      x + labelWidth, y, 28, 28,
      labels = newSeq[string](ms.noteMapIndexBgColor.len),
      tooltips = @[],
      dlg.indexColor,
      layout=RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc=indexColorDrawProc(ms).some
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
# {{{ Resize map dialog

proc resizeMapDialog(dlg: var ResizeMapDialogParams, a) =
  let ms = a.mapStyle

  let
    dialogWidth = 270.0
    dialogHeight = 300.0

  koi.beginDialog(dialogWidth, dialogHeight, fmt"{IconCrop}  Resize Map")
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

  proc okAction(dlg: var ResizeMapDialogParams, a) =
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

    actions.resizeMap(a.map, newRows, newCols, align, a.undoManager)

    setStatusMessage(IconCrop, "Map resized", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var ResizeMapDialogParams, a) =
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
      setStatusMessage(IconArrowsHoriz, "Floor orientation set to horizontal", a)
    else:
      setStatusMessage(IconArrowsVert, "Floor orientation set to vertical", a)

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
                         @[IconArrowsAll, "draw"], a)
        actions.excavate(m, curRow, curCol, um)

      elif ke.isKeyDown(keyE):
        a.editMode = emEraseCell
        setStatusMessage(IconEraser, "Erase cells",
                         @[IconArrowsAll, "erase"], a)
        actions.eraseCell(m, curRow, curCol, um)

      elif ke.isKeyDown(keyF):
        a.editMode = emClearFloor
        setStatusMessage(IconEraser, "Clear floor",
                         @[IconArrowsAll, "clear"], a)
        actions.setFloor(m, curRow, curCol, fEmpty, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(m, curRow, curCol, um)
        setFloorOrientationStatusMessage(
          m.getFloorOrientation(curRow, curCol), a)

      elif ke.isKeyDown(keyW):
        a.editMode = emDrawWall
        setStatusMessage("", "Draw walls", @[IconArrowsAll, "set/clear"], a)

      elif ke.isKeyDown(keyR):
        a.editMode = emDrawWallSpecial
        setStatusMessage("", "Draw wall special",
                         @[IconArrowsAll, "set/clear"], a)

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

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyU, repeat=true):
        if um.canUndo():
          let actionName = um.undo(m)
          updateViewStartAndCursorPosition(a)
          setStatusMessage(IconUndo, fmt"Undid action: {actionName}", a)
        else:
          setStatusMessage(IconWarning, "Nothing to undo", a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyR, {mkCtrl}, repeat=true):
        if um.canRedo():
          let actionName = um.redo(m)
          updateViewStartAndCursorPosition(a)
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
          dp.selStartRow = a.cursorRow
          dp.selStartCol = a.cursorCol

          a.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "paste", "Esc", "exit"], a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyG, {mkCtrl}):
        # TODO warning when map is empty?
        let sel = newSelection(a.map.rows, a.map.cols)
        sel.fill(true)
        a.nudgeBuf = SelectionBuffer(map: a.map, selection: sel).some
        a.map = newMap(a.map.rows, a.map.cols)

        dp.selStartRow = 0
        dp.selStartCol = 0

        a.editMode = emNudgePreview
        setStatusMessage(IconArrowsAll, "Nudge preview",
                         @[IconArrowsAll, "nudge",
                         "Enter", "confirm", "Esc", "exit"], a)

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
        if m.getFloor(curRow, curCol) == fNone:
          setStatusMessage(IconWarning, "No note to delete in cell", a)
        else:
          actions.eraseNote(a.map, curRow, curCol, a.undoManager)
          setStatusMessage(IconEraser, "Note erased", a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        if a.undoManager.isModified:
          a.saveDiscardDialog.isOpen = true
          a.saveDiscardDialog.action = openNewMapDialog
        else:
          openNewMapDialog(a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        a.resizeMapDialog.rows = $a.map.rows
        a.resizeMapDialog.cols = $a.map.cols
        a.resizeMapDialog.anchor = raCenter
        a.resizeMapDialog.isOpen = true

      elif ke.isKeyDown(keyO, {mkCtrl}):
        alias(dlg, a.saveDiscardDialog)
        if a.undoManager.isModified:
          dlg.isOpen = true
          dlg.action = openMap
        else:
          openMap(a)

      elif ke.isKeyDown(keyS, {mkCtrl}):
        saveMap(a)

      elif ke.isKeyDown(keyS, {mkCtrl, mkShift}):
        saveMapAs(a)

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
          var curSpecWall = SpecialWalls[a.currSpecialWallIdx]
          if   curSpecWall == wLeverSw:
            if dir in {dirN, dirE}: curSpecWall = wLeverNE
          elif curSpecWall == wNicheSw:
            if dir in {dirN, dirE}: curSpecWall = wNicheNE
          elif curSpecWall == wStatueSw:
            if dir in {dirN, dirE}: curSpecWall = wStatueNE

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
        let bbox = copySelection(a)
        if bbox.isSome:
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
          actions.surroundSelectionWithWalls(m, a.copyBuf.get.selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isKeyDown(keyR, {mkCtrl}):
        let sel = a.selection.get
        let bbox = sel.boundingBox()
        if bbox.isSome:
          actions.cropMap(m, bbox.get, um)
          updateViewStartAndCursorPosition(a)
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
      if ke.isKeyDown(MoveKeysLeft,  repeat=true):
        moveCursorAndSelStart(dirW, a)

      if ke.isKeyDown(MoveKeysRight, repeat=true):
        moveCursorAndSelStart(dirE, a)

      if ke.isKeyDown(MoveKeysUp,    repeat=true):
        moveCursorAndSelStart(dirN, a)

      if ke.isKeyDown(MoveKeysDown,  repeat=true):
        moveCursorAndSelStart(dirS, a)

      elif ke.isKeyDown({keyEnter, keyP}):
        actions.paste(m, curRow, curCol, a.copyBuf.get, um)
        a.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        a.editMode = emNormal
        a.clearStatusMessage()

    of emNudgePreview:
      if ke.isKeyDown(MoveKeysLeft,  repeat=true): moveSelStart(dirW, a)
      if ke.isKeyDown(MoveKeysRight, repeat=true): moveSelStart(dirE, a)
      if ke.isKeyDown(MoveKeysUp,    repeat=true): moveSelStart(dirN, a)
      if ke.isKeyDown(MoveKeysDown,  repeat=true): moveSelStart(dirS, a)

      elif ke.isKeyDown(keyEnter):
        actions.nudgeMap(m, dp.selStartRow, dp.selStartCol, a.nudgeBuf.get, um)
        a.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isKeyDown(keyEqual, repeat=true): a.incZoomLevel()
      elif ke.isKeyDown(keyMinus, repeat=true): a.decZoomLevel()

      elif ke.isKeyDown(keyEscape):
        a.editMode = emNormal
        a.map = a.nudgeBuf.get.map
        a.nudgeBuf = SelectionBuffer.none
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
  alias(ms, a.mapStyle)

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

  const MapDropdownWidth = 320
  # Current level dropdown
  a.currMapLevel = koi.dropdown(
    (winWidth - MapDropdownWidth)*0.5, 45, MapDropdownWidth, 24.0,   # TODO calc y
    items = @[
      "Level 1 - Legend of Darkmoor",
      "The Beginning",
      "The Dwarf Settlement",
      "You Only Scream Twice"
    ],
    tooltip = "Current map level",
    a.currMapLevel,
    style = a.mapDropdownStyle
  )

  # Map
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = a.cursorRow
    dp.cursorCol = a.cursorCol

    dp.selection = a.selection
    dp.selectionRect = a.selRect

    dp.selectionBuffer =
      if a.editMode == emPastePreview: a.copyBuf
      elif a.editMode == emNudgePreview: a.nudgeBuf
      else: SelectionBuffer.none

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
  var drawProc: RadioButtonsDrawProc =
    proc (vg: NVGContext, buttonIdx: Natural, label: string,
          hover, active, down, first, last: bool,
          x, y, w, h: float, style: RadioButtonsStyle) =

      let ms = a.mapStyle
      let dp = a.toolbarDrawParams

      var col = if active: ms.cursorColor else: ms.floorColor

      if hover:
        col = col.lerp(white(), 0.3)
      if down:
        col = col.lerp(black(), 0.3)

      const Pad = 5

      vg.beginPath()
      vg.fillColor(col)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.fill()

      dp.setZoomLevel(ms, 4)
      let ctx = DrawMapContext(ms: a.mapStyle, dp: dp, vg: vg)

      var cx = x + 5
      var cy = y + 15

      template drawAtZoomLevel6(body: untyped) =
        # A bit messy... but so is life! =8)
        dp.setZoomLevel(ms, 6)
        vg.scissor(x+4.5, y+3, dp.gridSize-3, dp.gridSize-2)
        body
        dp.setZoomLevel(ms, 4)
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
      of wStatueSW:      discard
      else: discard


  a.currSpecialWallIdx = koi.radioButtons(
    winWidth - 60.0, 90, 36, 35,
    labels = newSeq[string](SpecialWalls.len),
    tooltips = @[],
    a.currSpecialWallIdx,
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 20),
    drawProc=drawProc.some
  )

  var drawColorProc: RadioButtonsDrawProc =
    proc (vg: NVGContext, buttonIdx: Natural, label: string,
          hover, active, down, first, last: bool,
          x, y, w, h: float, style: RadioButtonsStyle) =

      var col = ms.noteMapIndexBgColor[buttonIdx]

      if hover:
        col = col.lerp(white(), 0.3)
      if down:
        col = col.lerp(black(), 0.3)

      const Pad = 5
      const SelPad = 3

      var cx, cy, cw, ch: float
      if active:
        vg.beginPath()
        vg.strokeColor(ms.cursorColor)
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

  a.currFloorColor = koi.radioButtons(
#    winWidth - 50.0, 90, 28, 28,
    winWidth - 57.0, 440, 29, 29,
    labels = newSeq[string](4),
    tooltips = @[],
    a.currFloorColor,
    layout=RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 8),
    drawProc=drawColorProc.some
  )

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  renderStatusBar(statusBarY, winWidth.float, a)

  # Dialogs
  if   a.saveDiscardDialog.isOpen: saveDiscardDialog(a.saveDiscardDialog, a)
  elif a.newMapDialog.isOpen:      newMapDialog(a.newMapDialog, a)
  elif a.editNoteDialog.isOpen:    editNoteDialog(a.editNoteDialog, a)
  elif a.resizeMapDialog.isOpen:   resizeMapDialog(a.resizeMapDialog, a)

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

  a.win.modified = a.undoManager.isModified

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

  if win.shouldClose:
    win.shouldClose = false
    when defined(NO_QUIT_DIALOG):
      a.shouldClose = true
    else:
      if not koi.isDialogActive():
        if a.undoManager.isModified:
          a.saveDiscardDialog.isOpen = true
          a.saveDiscardDialog.action = proc (a) = a.shouldClose = true
          koi.setFramesLeft()
        else:
          a.shouldClose = true
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

  showCellCoords(true, a)
  a.showNotesPane = true

  setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  a.map = newMap(16, 16)

  let filename = "EOB III - Crystal Tower L2 notes.grm"
# let filename = "drawtest.grm"
#  let filename = "notetest.grm"
#  let filename = "pool-of-radiance-library.grm"
  a.map = readMap(filename)
  a.filename = filename
  a.win.title = filename

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
