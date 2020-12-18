import algorithm
import browsers
import lenientops
import logging except Level
import macros
import math
import options
import os
import sequtils
import std/monotimes
import strformat
import strutils
import tables
import times

import glad/gl
import glfw
from glfw/wrapper import IconImageObj
import koi
import koi/undomanager
import nanovg
when not defined(DEBUG): import osdialog
import with

import actions
import appconfig
import common
import csdwindow
import drawlevel
import icons
import level
import links
import map
import persistence
import rect
import selection
import theme
import utils


when defined(windows):
  {.link: "icons/gridmonger.res".}

const
  BuildGitHash = staticExec("git rev-parse --short HEAD").strip

# {{{ logError()
proc logError(e: ref Exception) =
  logging.error("Error message: " & e.msg & "\n\nStrack trace:\n" &
                getStackTrace(e))

# }}}

# {{{ Paths
const
# TODO
#  BuildOS = if defined(windows): staticExec("ver")
#            else: staticExec("uname -v")

#  BuildDateTime = if defined(windows): staticExec("date /T") & staticExec("time /T")
#                  else: staticExec("date")

  LogFile = "gridmonger.log"

  DataDir = "data"

  HomeDir = getHomeDir() / "Gridmonger"
  AutosaveDir = HomeDir / "Autosave"
  ConfigDir = getConfigDir() / "Gridmonger"
  ConfigFile = ConfigDir / "gridmonger.ini"

  ThemesDir = "themes"
  ImagesDir = "images"
  ThemeImagesDir = ThemesDir / ImagesDir
  UserThemesDir = ConfigDir / ThemesDir
  UserThemeImagesDir = UserThemesDir / ImagesDir

  ThemeExt = "cfg"

# }}}
# {{{ Constants
const
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

  ThemePaneWidth          = 316.0

const
  MapFileExt = "grm"
  GridmongerMapFileFilter = fmt"Gridmonger Map (*.{MapFileExt}):{MapFileExt}"

const
  SpecialWalls = @[
    wIllusoryWall,
    wInvisibleWall,
    wDoor,
    wLockedDoor,
    wArchway,
    wSecretDoor,
    wOneWayDoorNE,
    wLeverSW,
    wNicheSW,
    wStatueSW,
    wKeyhole,
    wWritingSW
  ]

# }}}
# {{{ AppContext
type
  AppContext = ref object
    win:         CSDWindow
    vg:          NVGContext

    config:      AppConfig

    doc:         Document
    opt:         Options
    ui:          UI
    theme:       Theme
    dialog:      Dialog

    themeEditor: ThemeEditor
    splash:      Splash

    shouldClose: bool


  Document = object
    filename:          string
    map:               Map
    levelStyle:        LevelStyle
    undoManager:       UndoManager[Map, UndoStateData]
    lastAutosaveTime:  MonoTime

  Options = object
    showSplash:        bool
    autoCloseSplash:   bool
    splashTimeoutSecs: Natural
    loadLastMap:       bool
    autosave:          bool
    autosaveFreqMins:  Natural
    disableVSync:      bool

    scrollMargin:      Natural
    showNotesPane:     bool
    showToolsPane:     bool
    showThemePane:     bool

    drawTrail:         bool
    walkMode:          bool
    wasdMode:          bool


  UI = object
    cursor:            Location
    cursorOrient:      CardinalDir
    editMode:          EditMode

    lastCursorViewX:   float
    lastCursorViewY:   float

    selection:         Option[Selection]
    selRect:           Option[SelectionRect]
    copyBuf:           Option[SelectionBuffer]
    nudgeBuf:          Option[SelectionBuffer]
    cutToBuffer:       bool

    statusIcon:        string
    statusMessage:     string
    statusCommands:    seq[string]

    currSpecialWall:   Natural
    currFloorColor:    byte

    levelTopPad:       float
    levelRightPad:     float
    levelBottomPad:    float
    levelLeftPad:      float

    linkSrcLocation:   Location

    drawLevelParams:   DrawLevelParams
    toolbarDrawParams: DrawLevelParams

    levelDrawAreaWidth:  float
    levelDrawAreaHeight: float

    backgroundImage:   Option[Paint]

    buttonStyle:           ButtonStyle
    checkBoxStyle:         CheckboxStyle
    dialogStyle:           koi.DialogStyle
    labelStyle:            LabelStyle
    radioButtonStyle:      RadioButtonsStyle
    textAreaStyle:         TextAreaStyle
    textFieldStyle:        koi.TextFieldStyle

    aboutButtonStyle:      ButtonStyle
    iconRadioButtonsStyle: RadioButtonsStyle
    warningLabelStyle:     LabelStyle


  EditMode = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emClearFloor,
    emColorFloor,
    emSelect,
    emSelectRect
    emPastePreview,
    emMovePreview,
    emNudgePreview,
    emSetCellLink

  Theme = object
    style:                  ThemeStyle
    themeNames:             seq[string]
    currThemeIndex:         Natural
    nextThemeIndex:         Option[Natural]
    themeReloaded:          bool
    levelDropDownStyle:     DropDownStyle
    reinitDrawLevelParams:  bool

  Dialog = object
    preferencesDialog:      PreferencesDialogParams

    saveDiscardDialog:      SaveDiscardDialogParams

    newMapDialog:           NewMapDialogParams
    editMapPropsDialog:     EditMapPropsDialogParams

    newLevelDialog:         NewLevelDialogParams
    editLevelPropsDialog:   EditLevelPropsParams
    resizeLevelDialog:      ResizeLevelDialogParams
    deleteLevelDialog:      DeleteLevelDialogParams

    editNoteDialog:         EditNoteDialogParams
    editLabelDialog:        EditLabelDialogParams


  PreferencesDialogParams = object
    isOpen:       bool
    activeTab:    Natural
    activateFirstTextField: bool

    showSplash:         bool
    autoCloseSplash:    bool
    splashTimeoutSecs:  string
    loadLastMap:        bool
    disableVSync:       bool
    autosave:           bool
    autosaveFreqMins:   string


  SaveDiscardDialogParams = object
    isOpen:       bool
    action:       proc (a: var AppContext)


  NewMapDialogParams = object
    isOpen:       bool
    activateFirstTextField: bool

    name:         string
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string


  EditMapPropsDialogParams = object
    isOpen:       bool
    activateFirstTextField: bool

    name:         string
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string


  DeleteLevelDialogParams = object
    isOpen:       bool

  NewLevelDialogParams = object
    isOpen:       bool
    activeTab:    Natural
    activateFirstTextField: bool

    # General tab
    locationName: string
    levelName:    string
    elevation:    string
    rows:         string
    cols:         string

    # Coordinates tab
    overrideCoordOpts: bool
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string

    # Regions tab
    enableRegions: bool
    regionColumns: string
    regionRows:    string
    perRegionCoords: bool


  EditLevelPropsParams = object
    isOpen:       bool
    activeTab:    Natural
    activateFirstTextField: bool

    # General tab
    locationName: string
    levelName:    string
    elevation:    string

    # Coordinates tab
    overrideCoordOpts: bool
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string

    # Regions tab
    enableRegions: bool
    regionColumns: string
    regionRows:    string
    perRegionCoords: bool


  ResizeLevelDialogParams = object
    isOpen:       bool
    activateFirstTextField: bool

    rows:         string
    cols:         string
    anchor:       ResizeAnchor


  ResizeAnchor = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


  EditNoteDialogParams = object
    isOpen:       bool
    activateFirstTextField: bool

    editMode:     bool
    row:          Natural
    col:          Natural
    kind:         NoteKind
    index:        Natural
    indexColor:   Natural
    customId:     string
    icon:         Natural
    text:         string


  EditLabelDialogParams = object
    isOpen:       bool
    activateFirstTextField: bool

    editMode:     bool
    row:          Natural
    col:          Natural
    text:         string
    color:        Natural


  ThemeEditor = object
    prevState:               ThemeStyle

    sectionUserInterface:    bool
    sectionWidget:           bool
    sectionTextField:        bool
    sectionDialog:           bool
    sectionTitleBar:         bool
    sectionStatusBar:        bool
    sectionLeveldropDown:    bool
    sectionAboutButton:      bool
    sectionSplashImage:      bool

    sectionLevel:            bool
    sectionLevelGeneral:     bool
    sectionGrid:             bool
    sectionOutline:          bool
    sectionShadow:           bool
    sectionBackgroundHatch:  bool
    sectionFloorColors:      bool
    sectionNotes:            bool

    sectionPanes:            bool
    sectionNotesPane:        bool
    sectionToolbarPane:      bool


  Splash = object
    win:           Window
    vg:            NVGContext
    show:          bool
    t0:            MonoTime

    logo:          ImageData
    outline:       ImageData
    shadow:        ImageData

    logoImage:     Image
    outlineImage:  Image
    shadowImage:   Image

    logoPaint:     Paint
    outlinePaint:  Paint
    shadowPaint:   Paint

    updateLogoImage:     bool
    updateOutlineImage:  bool
    updateShadowImage:   bool


var g_app: AppContext

using a: var AppContext

# }}}
# {{{ Keyboard shortcuts

type MoveKeys = object
  left, right, up, down: set[Key]

const MoveKeysCursor = MoveKeys(
  left  : {keyLeft,     keyH, keyKp4},
  right : {keyRight,    keyL, keyKp6},
  up    : {keyUp,       keyK, keyKp8},
  down  : {Key.keyDown, keyJ, keyKp2, keyKp5}
)

type AppShortcut = enum
  scNextTextField,
  scAccept,
  scCancel,
  scDiscard,

# TODO some shortcuts win/mac specific?
# TODO introduce shortcus for everything
let g_appShortcuts = {

  scNextTextField:    @[mkKeyShortcut(keyTab,           {})],

  scAccept:           @[mkKeyShortcut(keyEnter,         {}),
                        mkKeyShortcut(keyKpEnter,       {})],

  scCancel:           @[mkKeyShortcut(keyEscape,        {}),
                        mkKeyShortcut(keyLeftBracket,   {mkCtrl})],

  scDiscard:          @[mkKeyShortcut(keyD,             {mkAlt})],

}.toTable

# }}}

# {{{ setSwapInterval()
proc setSwapInterval(a) =
  glfw.swapInterval(if a.opt.disableVSync: 0 else: 1)

# }}}
# {{{ saveConfig()
proc saveConfig(a) =
  alias(ui, a.ui)
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)
  alias(opt, a.opt)
  alias(theme, a.theme)

  let (xpos, ypos) = if a.win.maximized: a.win.oldPos else: a.win.pos
  let (width, height) = if a.win.maximized: a.win.oldSize else: a.win.size

  let a = AppConfig(
    showSplash: opt.showSplash,
    autoCloseSplash: opt.autoCloseSplash,
    splashTimeoutSecs: opt.splashTimeoutSecs,
    loadLastMap: opt.loadLastMap,
    lastMapFileName: a.doc.filename,

    maximized: a.win.maximized,
    xpos: xpos,
    ypos: ypos,
    width: width,
    height: height,
    disableVSync: opt.disableVSync,

    # TODO use common struct for DISP chunk & this
    themeName: theme.themeNames[theme.currThemeIndex],
    zoomLevel: dp.getZoomLevel(),
    showCellCoords: dp.drawCellCoords,
    showToolsPane: opt.showToolsPane,
    showNotesPane: opt.showNotesPane,
    drawTrail: opt.drawTrail,
    wasdMode: opt.wasdMode,
    walkMode: opt.walkMode,

    currLevel: cur.level,
    cursorRow: cur.row,
    cursorCol: cur.col,
    viewStartRow: dp.viewStartRow,
    viewStartCol: dp.viewStartCol,

    autosave: opt.autosave,
    autosaveFreqMins: opt.autosaveFreqMins
  )

  saveAppConfig(a, ConfigFile)

# }}}
# {{{ loadImage()
proc loadImage(path: string; a): Option[Paint] =
  alias(vg, a.vg)
  try:
    let img = vg.createImage(path, {ifRepeatX, ifRepeatY})

    let (w, h) = vg.imageSize(img)
    let paint = vg.imagePattern(0, 0, w.float, h.float, angle=0, img, alpha=1.0)
    result = paint.some

  except NVGError:
    result = Paint.none

# }}}
# {{{ updateWidgetStyles()
proc updateWidgetStyles(a) =
  alias(s, a.theme.style)
  alias(gs, s.general)
  alias(ws, s.widget)

  # Button
  a.ui.buttonStyle = koi.getDefaultButtonStyle()

  with a.ui.buttonStyle:
    cornerRadius      = gs.cornerRadius
    fillColor         = ws.bgColor
    fillColorHover    = ws.bgColorHover
    fillColorDown     = gs.highlightColor
    fillColorDisabled = ws.bgColorDisabled

    label.color            = ws.textColor
    label.colorHover       = ws.textColor
    label.colorDown        = ws.textColorActive
    label.colorActive      = ws.textColorActive
    label.colorActiveHover = ws.textColorActive
    label.colorDisabled    = ws.textColorDisabled

  # Radio button
  a.ui.radioButtonStyle = koi.getDefaultRadioButtonsStyle()

  with a.ui.radioButtonStyle:
    buttonCornerRadius         = gs.cornerRadius
    buttonFillColor            = ws.bgColor
    buttonFillColorHover       = ws.bgColorHover
    buttonFillColorDown        = gs.highlightColor
    buttonFillColorActive      = gs.highlightColor
    buttonFillColorActiveHover = gs.highlightColor

    label.color            = ws.textColor
    label.colorHover       = ws.textColor
    label.colorDown        = ws.textColorActive
    label.colorActive      = ws.textColorActive
    label.colorActiveHover = ws.textColorActive

  # Icon radio button
  a.ui.iconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()

  with a.ui.iconRadioButtonsStyle:
    buttonPadHoriz             = 4.0
    buttonPadVert              = 4.0
    buttonFillColor            = ws.bgColor
    buttonFillColorHover       = ws.bgColorHover
    buttonFillColorDown        = gs.highlightColor
    buttonFillColorActive      = gs.highlightColor
    buttonFillColorActiveHover = gs.highlightColor

    label.fontSize         = 18.0
    label.color            = ws.textColor
    label.colorHover       = ws.textColor
    label.colorDown        = ws.textColorActive
    label.colorActive      = ws.textColorActive
    label.colorActiveHover = ws.textColorActive
    label.padHoriz         = 0
    label.padHoriz         = 0

  # Text field
  a.ui.textFieldStyle = koi.getDefaultTextFieldStyle()

  with a.ui.textFieldStyle:
    bgCornerRadius      = gs.cornerRadius
    bgFillColor         = ws.bgColor
    bgFillColorHover    = ws.bgColorHover
    bgFillColorActive   = s.textField.bgColorActive
    bgFillColorDisabled = ws.bgColorDisabled
    textColor           = ws.textColor
    textColorHover      = ws.textColor
    textColorActive     = s.textField.textColorActive
    textColorDisabled   = ws.textColorDisabled
    cursorColor         = s.textField.cursorColor
    selectionColor      = s.textField.selectionColor

  # Text area
  a.ui.textAreaStyle = koi.getDefaultTextAreaStyle()

  with a.ui.textAreaStyle:
    bgCornerRadius      = gs.cornerRadius
    bgFillColor         = ws.bgColor
    bgFillColorHover    = lerp(ws.bgColor, ws.bgColorHover, 0.5)
    bgFillColorActive   = s.textField.bgColorActive
    textColor           = ws.textColor
    textColorHover      = ws.textColor
    textColorActive     = s.textField.textColorActive
    cursorColor         = s.textField.cursorColor
    selectionColor      = s.textField.selectionColor

  # Check box
  a.ui.checkBoxStyle = koi.getDefaultCheckBoxStyle()

  with a.ui.checkBoxStyle:
    cornerRadius          = gs.cornerRadius
    fillColor             = ws.bgColor
    fillColorHover        = ws.bgColorHover
    fillColorDown         = gs.highlightColor
    fillColorActive       = gs.highlightColor
    icon.fontSize         = 12.0
    icon.color            = ws.textColor
    icon.colorHover       = ws.textColor
    icon.colorDown        = ws.textColorActive
    icon.colorActive      = ws.textColorActive
    icon.colorActiveHover = ws.textColorActive
    iconActive            = IconCheck
    iconInactive          = NoIcon

  # Dialog style
  a.ui.dialogStyle = koi.getDefaultDialogStyle()

  with a.ui.dialogStyle:
    cornerRadius      = s.dialog.cornerRadius
    backgroundColor   = s.dialog.backgroundColor
    titleBarBgColor   = s.dialog.titleBarBgColor
    titleBarTextColor = s.dialog.titleBarTextColor

    outerBorderColor  = s.dialog.outerBorderColor
    innerBorderColor  = s.dialog.innerBorderColor
    outerBorderWidth  = s.dialog.outerBorderWidth
    innerBorderWidth  = s.dialog.innerBorderWidth

    with shadow:
      enabled         = s.dialog.shadow
      xOffset         = s.dialog.shadowXOffset
      yOffset         = s.dialog.shadowYOffset
      feather         = s.dialog.shadowFeather
      color           = s.dialog.shadowColor

  # Label
  a.ui.labelStyle = koi.getDefaultLabelStyle()

  with a.ui.labelStyle:
    fontSize = 14
    color = s.dialog.textColor
    colorDisabled = s.dialog.textColor.lerp(s.dialog.backgroundColor, 0.7)
    align = haLeft

  # Warning label
  a.ui.warningLabelStyle = koi.getDefaultLabelStyle()

  with a.ui.warningLabelStyle:
    color = s.dialog.warningTextColor
    multiLine = true

  # Level dropDown
  alias(lds, s.levelDropDown)

  a.theme.levelDropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.levelDropDownStyle:
    buttonCornerRadius       = gs.cornerRadius
    buttonFillColor          = lds.buttonColor
    buttonFillColorHover     = lds.buttonColorHover
    buttonFillColorDown      = lds.buttonColor
    buttonFillColorDisabled  = lds.buttonColor
    label.fontSize           = 15.0
    label.color              = lds.textColor
    label.colorHover         = lds.textColor
    label.colorDown          = lds.textColor
    label.colorActive        = lds.textColor
    label.colorDisabled      = lds.textColor
    label.align              = haCenter
    item.align               = haLeft
    item.color               = lds.itemColor
    item.colorHover          = lds.itemColorHover
    itemListCornerRadius     = gs.cornerRadius
    itemListPadHoriz         = 10.0
    itemListFillColor        = lds.itemListColor
    itemBackgroundColorHover = gs.highlightColor

  # About button
  alias(abs, s.aboutButton)

  a.ui.aboutButtonStyle = koi.getDefaultButtonStyle()

  with a.ui.aboutButtonStyle:
    labelOnly        = true
    label.fontSize   = 20.0
    label.padHoriz   = 0
    label.color      = abs.color
    label.colorHover = abs.colorHover
    label.colorDown  = abs.colorActive

# }}}

# {{{ Helpers/utils

# {{{ mapHasLevels()
proc mapHasLevels(a): bool =
  a.doc.map.levels.len > 0

# }}}
# {{{ currSortedLevelIdx()
proc currSortedLevelIdx(a): Natural =
  a.doc.map.findSortedLevelIdxByLevelIdx(a.ui.cursor.level)

# }}}
# {{{ currLevel()
proc currLevel(a): Level =
  a.doc.map.levels[a.ui.cursor.level]

# }}}
# {{{ coordOptsForCurrLevel()
proc coordOptsForCurrLevel(a): CoordinateOptions =
  let l = currLevel(a)
  if l.overrideCoordOpts: l.coordOpts else: a.doc.map.coordOpts

# }}}

# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  a.ui.statusIcon = NoIcon
  a.ui.statusMessage = ""
  a.ui.statusCommands = @[]

# }}}
# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string]; a) =
  a.ui.statusIcon = icon
  a.ui.statusMessage = msg
  a.ui.statusCommands = commands

proc setStatusMessage(icon, msg: string; a) =
  setStatusMessage(icon, msg, commands = @[], a)

proc setStatusMessage(msg: string; a) =
  setStatusMessage(NoIcon, msg, commands = @[], a)

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
                     "Ctrl+S", "surround", "Ctrl+R", "crop",
                     "Ctrl+M", "move (cut+paste)",
                     "Ctrl+C", "set color"], a)
# }}}

# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  a.ui.cursor.level = 0
  a.ui.cursor.row = 0
  a.ui.cursor.col = 0
  a.ui.drawLevelParams.viewStartRow = 0
  a.ui.drawLevelParams.viewStartCol = 0

# }}}
# {{{ updateLastCursorViewCoords()
proc updateLastCursorViewCoords(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(cur, a.ui.cursor)

  a.ui.lastCursorViewX = dp.gridSize * (cur.col - dp.viewStartCol)
  a.ui.lastCursorViewY = dp.gridSize * (cur.row - dp.viewStartRow)

# }}}
# {{{ drawAreaWidth()
proc drawAreaWidth(a): float =
  if a.opt.showThemePane: koi.winWidth() - ThemePaneWidth
  else: koi.winWidth()

# }}}
# {{{ drawAreaHeight()
proc drawAreaHeight(a): float =
  # TODO
  koi.winHeight() - TitleBarHeight

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(cur, a.ui.cursor)

  let l = currLevel(a)

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

  ui.levelDrawAreaWidth = drawAreaWidth(a) - a.ui.levelLeftPad -
                                             a.ui.levelRightPad

  ui.levelDrawAreaHeight = drawAreaHeight(a) - a.ui.levelTopPad -
                                               a.ui.levelBottomPad -
                                               StatusBarHeight

  if a.opt.showNotesPane:
   ui.levelDrawAreaHeight -= NotesPaneTopPad + NotesPaneHeight +
                             NotesPaneBottomPad

  if a.opt.showToolsPane:
    ui.levelDrawAreaWidth -= ToolsPaneWidth

  dp.viewRows = min(dp.numDisplayableRows(ui.levelDrawAreaHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(ui.levelDrawAreaWidth), l.cols)

  dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow)
  dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  cur.row = viewEndRow.clamp(dp.viewStartRow, cur.row)
  cur.col = viewEndCol.clamp(dp.viewStartCol, cur.col)

  updateLastCursorViewCoords(a)

# }}}
# {{{ locationAtMouse()
proc locationAtMouse(a): Option[Location] =
  alias(dp, a.ui.drawLevelParams)

  let
    mouseViewRow = ((koi.my() - dp.startY) / dp.gridSize).int
    mouseViewCol = ((koi.mx() - dp.startX) / dp.gridSize).int

    mouseRow = dp.viewStartRow + mouseViewRow
    mouseCol = dp.viewStartCol + mouseViewCol

  if mouseViewRow >= 0 and mouseRow < dp.viewStartRow + dp.viewRows and
     mouseViewCol >= 0 and mouseCol < dp.viewStartCol + dp.viewCols:

    result = Location(
      level: a.ui.cursor.level,
      row: mouseRow,
      col: mouseCol
    ).some
  else:
    result = Location.none

# }}}

# {{{ moveLevel()
proc moveLevel(dir: CardinalDir, steps: Natural; a) =
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)
  let maxViewStartRow = max(l.rows - dp.viewRows, 0)
  let maxViewStartCol = max(l.cols - dp.viewCols, 0)

  var newViewStartCol = dp.viewStartCol
  var newViewStartRow = dp.viewStartRow

  case dir:
  of dirE: newViewStartCol = min(dp.viewStartCol + steps, maxViewStartCol)
  of dirW: newViewStartCol = max(dp.viewStartCol - steps, 0)
  of dirS: newViewStartRow = min(dp.viewStartRow + steps, maxViewStartRow)
  of dirN: newViewStartRow = max(dp.viewStartRow - steps, 0)

  cur.row = cur.row + (newViewStartRow - dp.viewStartRow)
  cur.col = cur.col + (newViewStartCol - dp.viewStartCol)

  dp.viewStartRow = newViewStartRow
  dp.viewStartCol = newViewStartCol

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, steps: Natural; a) =
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)
  let sm = a.opt.scrollMargin

  case dir:
  of dirE:
    cur.col = min(cur.col + steps, l.cols-1)
    let viewCol = cur.col - dp.viewStartCol
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol +
                                                        (viewCol - viewColMax))

  of dirS:
    cur.row = min(cur.row + steps, l.rows-1)
    let viewRow = cur.row - dp.viewStartRow
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow +
                                                        (viewRow - viewRowMax))

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
proc moveSelStart(dir: CardinalDir; a) =
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
proc moveCursorTo(loc: Location; a) =
  alias(cur, a.ui.cursor)

  cur.level = loc.level

  let  dx = loc.col - cur.col
  if   dx < 0: moveCursor(dirW, -dx, a)
  elif dx > 0: moveCursor(dirE,  dx, a)

  let  dy = loc.row - cur.row
  if   dy < 0: moveCursor(dirN, -dy, a)
  elif dy > 0: moveCursor(dirS,  dy, a)

# }}}

# {{{ enterSelectMode()
proc enterSelectMode(a) =
  let l = currLevel(a)

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
proc copySelection(buf: var Option[SelectionBuffer]; a): Option[Rect[Natural]] =
  alias(ui, a.ui)

  proc eraseOrphanedWalls(cb: SelectionBuffer) =
    var l = cb.level
    for r in 0..<l.rows:
      for c in 0..<l.cols:
        l.eraseOrphanedWalls(r,c)

  let sel = ui.selection.get
  let bbox = sel.boundingBox()

  if bbox.isSome:
    let bbox = bbox.get

    buf = some(SelectionBuffer(
      selection: newSelectionFrom(sel, bbox),
      level: newLevelFrom(currLevel(a), bbox)
    ))
    eraseOrphanedWalls(buf.get)

    ui.cutToBuffer = false

  result = bbox

# }}}

# }}}

# {{{ Theme handling

# {{{ searchThemes()
proc searchThemes(a) =
  for path in walkFiles(ThemesDir / fmt"*.{ThemeExt}"):
    let (_, name, _) = splitFile(path)
    a.theme.themeNames.add(name)
  sort(a.theme.themeNames)

# }}}
# {{{ findThemeIndex()
proc findThemeIndex(name: string; a): int =
  for i, n in a.theme.themeNames:
    if n == name:
      return i
  return -1

# }}}
# {{{ themePath()
proc themePath(index: Natural; a): string =
  let name = a.theme.themeNames[index]
  ThemesDir / addFileExt(name, ThemeExt)

# }}}
# {{{ loadTheme()
proc loadTheme(index: Natural; a) =
  let name = a.theme.themeNames[index]
  let path = themePath(index, a)
  info(fmt"Loading theme '{name}' from '{path}'")

  a.theme.style = loadTheme(path)

# }}}
# {{{ switchTheme()
proc switchTheme(themeIndex: Natural; a) =
  loadTheme(themeIndex, a)
  updateWidgetStyles(a)

  let bgImageName = a.theme.style.general.backgroundImage
  if bgImageName != "":
    var imgPath = ThemeImagesDir / bgImageName
    var image = loadImage(imgPath, a)
    if image.isNone:
      info(fmt"Couldn't load background image '{imgPath}'. " &
           "Attempting to load it from the user themes images directory now.")

      imgPath = UserThemeImagesDir / bgImageName
      image = loadImage(imgPath, a)
      if image.isNone:
        logging.error(fmt"Couldn't load background image '{imgPath}'")

    a.ui.backgroundImage = image
    a.ui.drawLevelParams.backgroundImage = a.ui.backgroundImage
  else:
    a.ui.backgroundImage = Paint.none
    a.ui.drawLevelParams.backgroundImage = Paint.none

  a.doc.levelStyle = a.theme.style.level

  a.ui.drawLevelParams.initDrawLevelParams(a.doc.levelStyle, a.vg,
                                           koi.getPxRatio())

  a.win.setStyle(a.theme.style.window)

  a.theme.currThemeIndex = themeIndex

# }}}

# }}}
# {{{ Key handling
proc hasKeyEvent(): bool =
  koi.hasEvent() and koi.currEvent().kind == ekKey

# TODO change all into isShorcut* (if possible)
func isKeyDown(ev: Event, keys: set[Key],
               mods: set[ModifierKey] = {},
               repeat=false): bool =

  # ignore numlock & capslock
  let eventMods = ev.mods - {mkNumLock, mkCapsLock}
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  ev.action in a and ev.key in keys and eventmods == mods


func isKeyDown(ev: Event, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ev, {key}, mods, repeat)

func isKeyUp(ev: Event, keys: set[Key]): bool =
  ev.action == kaUp and ev.key in keys

proc isShortcutDown(ev: Event, shortcut: AppShortcut, repeat=false): bool =
  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}
  if ev.kind == ekKey and ev.action in a:
    let sc = mkKeyShortcut(ev.key, ev.mods)
    result = sc in g_appShortcuts[shortcut]

# }}}
# {{{ Dialogs
const
  DlgItemHeight    = 24.0
  DlgButtonWidth   = 80.0
  DlgButtonPad     = 10.0
  DlgNumberWidth   = 50.0
  DlgCheckBoxSize  = 18.0
  DlgTopPad        = 50.0
  DlgTopNoTabPad   = 60.0
  DlgLeftPad       = 30.0
  DlgTabBottomPad  = 50.0

  DialogLayoutParams = AutoLayoutParams(
    itemsPerRow:      2,
    rowWidth:         370.0,
    labelWidth:       160.0,
    sectionPad:       0.0,
    leftPad:          0.0,
    rightPad:         0.0,
    rowPad:           8.0,
    rowGroupPad:      20.0,
    defaultRowHeight: 24.0
  )

proc calcDialogX(dlgWidth: float; a): float =
  drawAreaWidth(a)*0.5 - dlgWidth*0.5

# {{{ coordinateFields()
template coordinateFields() =
  const LetterLabelWidth = 100

  group:
    koi.label("Origin", style=a.ui.labelStyle)
    koi.radioButtons(
      labels = @["Northwest", "Southwest"],
      dlg.origin,
      style = a.ui.radioButtonStyle
    )

  group:
    koi.label("Column style", style=a.ui.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.columnStyle,
      style = a.ui.radioButtonStyle
    )

    koi.label("Row style", style=a.ui.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.rowStyle,
      style = a.ui.radioButtonStyle
    )

  group:
    let letterLabelX = x + 190

    koi.label("Column offset", style=a.ui.labelStyle)
    var y = koi.currAutoLayoutY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.columnStart,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        min: 0,
        max: LevelNumRowsMax
      ).some,
      style = a.ui.textFieldStyle
    )
    if CoordinateStyle(dlg.columnStyle) == csLetter:
      try:
        let i = parseInt(dlg.columnStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.clamp(0, LevelNumColumnsMax).toLetterCoord,
                  style=a.ui.labelStyle)
      except ValueError:
        discard

    koi.label("Row offset", style=a.ui.labelStyle)
    y = koi.currAutoLayoutY()


    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rowStart,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        min: 0,
        max: LevelNumColumnsMax
      ).some,
      style = a.ui.textFieldStyle
    )
    if CoordinateStyle(dlg.rowStyle) == csLetter:
      try:
        let i = parseInt(dlg.rowStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.clamp(0, LevelNumRowsMax).toLetterCoord,
                  style=a.ui.labelStyle)
      except ValueError:
        discard

# }}}
# {{{ regionFields()
template regionFields() =
  group:
    koi.label("Enable regions", style=a.ui.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.enableRegions, style = a.ui.checkBoxStyle)

    if dlg.enableRegions:
      group:
        koi.label("Region columns", style=a.ui.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.regionColumns,
          activate = dlg.activateFirstTextField,
          constraint = TextFieldConstraint(
            kind: tckInteger,
            min: 2,
            max: LevelNumRowsMax
          ).some,
          style = a.ui.textFieldStyle
        )


        koi.label("Region rows", style=a.ui.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.regionRows,
          constraint = TextFieldConstraint(
            kind: tckInteger,
            min: 2,
            max: LevelNumColumnsMax
          ).some,
          style = a.ui.textFieldStyle
        )

      group:
        koi.label("Per-region coordinates", style=a.ui.labelStyle)

        koi.nextItemHeight(DlgCheckBoxSize)
        koi.checkBox(dlg.perRegionCoords, style = a.ui.checkBoxStyle)

# }}}
# {{{ levelCommonFields()
template levelCommonFields() =
  group:
    koi.label("Location Name", style=a.ui.labelStyle)

    koi.textField(
      dlg.locationName,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: 0,
        maxLen: LevelLocationNameMaxLen
      ).some,
      style = a.ui.textFieldStyle
    )

    koi.label("Level Name", style=a.ui.labelStyle)

    koi.textField(
      dlg.levelName,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: LevelNameMinLen,
        maxLen: LevelNameMaxLen
      ).some,
      style = a.ui.textFieldStyle
    )

  group:
    koi.label("Elevation", style=a.ui.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.elevation,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        min: LevelElevationMin,
        max: LevelElevationMax
      ).some,
      style = a.ui.textFieldStyle
    )

# }}}
# {{{ validateLevelFields()
template validateLevelFields(dlg, map, validationError: untyped) =
  if dlg.locationName == "":
    validationError = mkValidationError("Location name is mandatory")
  else:
    for l in map.levels:
      if l.locationName == dlg.locationName and
         l.levelName == dlg.levelName and
         $l.elevation == dlg.elevation:

        validationError = mkValidationError(
          "A level already exists with the same location name, " &
          "level name and elevation."
        )
        break

# }}}

# {{{ dialogButtonsStartPos()
proc dialogButtonsStartPos(dlgWidth, dlgHeight: float,
                           numButtons: Natural): (float, float) =
  const BorderPad = 15.0

  let x = dlgWidth - numButtons * DlgButtonWidth - BorderPad -
          (numButtons-1) * DlgButtonPad

  let y = dlgHeight - DlgItemHeight - BorderPad

  result = (x, y)

# }}}
# {{{ mkValidationError()
proc mkValidationError(msg: string): string =
  fmt"{IconWarning}   {msg}"

# }}}
# {{{ handleTabNavigation()
proc handleTabNavigation(ke: Event,
                         currTabIndex, maxTabIndex: Natural): Natural =
  result = currTabIndex

  if ke.isKeyDown(MoveKeysCursor.left, {mkCtrl}):
    if    currTabIndex > 0: result = currTabIndex - 1
    else: result = maxTabIndex

  elif ke.isKeyDown(MoveKeysCursor.right, {mkCtrl}):
    if    currTabIndex < maxTabIndex: result = currTabIndex + 1
    else: result = 0

  else:
    let i = ord(ke.key) - ord(key1)
    if ke.action == kaDown and mkCtrl in ke.mods and
      i >= 0 and i <= maxTabIndex:
      result = i

# }}}
# {{{ moveGridPositionWrapping()
proc moveGridPositionWrapping(currIdx: int, dc: int = 0, dr: int = 0,
                              numItems, itemsPerRow: Natural): Natural =
  assert numItems mod itemsPerRow == 0

  let numRows = ceil(numItems.float / itemsPerRow).Natural
  var row = currIdx div itemsPerRow
  var col = currIdx mod itemsPerRow
  col = floorMod(col+dc, itemsPerRow).Natural
  row = floorMod(row+dr, numRows).Natural
  result = row * itemsPerRow + col

# }}}
# {{{ handleGridRadioButton()
proc handleGridRadioButton(ke: Event, currButtonIdx: Natural,
                           numButtons, buttonsPerRow: Natural): Natural =

  proc move(dc: int = 0, dr: int = 0): Natural =
    moveGridPositionWrapping(currButtonIdx, dc, dr, numButtons, buttonsPerRow)

  result =
    if   ke.isKeyDown(MoveKeysCursor.left,  repeat=true): move(dc = -1)
    elif ke.isKeyDown(MoveKeysCursor.right, repeat=true): move(dc =  1)
    elif ke.isKeyDown(MoveKeysCursor.up,    repeat=true): move(dr = -1)
    elif ke.isKeyDown(MoveKeysCursor.down,  repeat=true): move(dr =  1)
    else: currButtonIdx

# }}}
# {{{ colorRadioButtonDrawProc()
proc colorRadioButtonDrawProc(colors: seq[Color],
                              cursorColor: Color): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               state: WidgetState, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    let sw = 2.0
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    var col = colors[buttonIdx]

    if state in {wsHover, wsDown, wsActiveHover}:
      col = col.lerp(white(), 0.15)

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if state in {wsDown, wsActive, wsActiveHover}:
      vg.beginPath()
      vg.strokeColor(cursorColor)
      vg.strokeWidth(sw)
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

# }}}

# {{{ Preferences dialog
proc openPreferencesDialog(a) =
  alias(dlg, a.dialog.preferencesDialog)

  dlg.showSplash = a.opt.showSplash
  dlg.autoCloseSplash = a.opt.autoCloseSplash
  dlg.splashTimeoutSecs = $a.opt.splashTimeoutSecs
  dlg.loadLastMap = a.opt.loadLastMap
  dlg.disableVSync = a.opt.disableVSync
  dlg.autosave = a.opt.autosave
  dlg.autosaveFreqMins = $a.opt.autosaveFreqMins

  dlg.isOpen = true


proc preferencesDialog(dlg: var PreferencesDialogParams; a) =
  const
    DlgWidth = 370.0
    DlgHeight = 375.0
    TabWidth = 180.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCog}  Preferences",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["Startup", "General"]

  koi.radioButtons(
    (DlgWidth - TabWidth) / 2, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.ui.radioButtonStyle
  )

  y += DlgTabBottomPad
  koi.beginView(x, y, 1000, 1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 220
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General

    group:
      koi.label("Show splash image", style=a.ui.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.showSplash, style = a.ui.checkBoxStyle)


      var disabled = not dlg.showSplash
      koi.label("Auto-close splash",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.ui.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autoCloseSplash, disabled=disabled,
                   style = a.ui.checkBoxStyle)


      disabled = not (dlg.showSplash and dlg.autoCloseSplash)
      koi.label("Auto-close timeout (seconds)",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.ui.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.splashTimeoutSecs,
        activate = dlg.activateFirstTextField,
        disabled = disabled,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          min: 1,
          max: 10
        ).some,
        style = a.ui.textFieldStyle
      )

    group:
      koi.label("Load last map", style=a.ui.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.loadLastMap, style = a.ui.checkBoxStyle)


  elif dlg.activeTab == 1:  # General

    group:
      let autosaveDisabled = not dlg.autosave

      koi.label("Autosave", style=a.ui.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autosave, style = a.ui.checkBoxStyle)

      koi.label("Autosave frequency (minutes)",
                state = if autosaveDisabled: wsDisabled else: wsNormal,
                style=a.ui.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.autosaveFreqMins,
        activate = dlg.activateFirstTextField,
        disabled = autosaveDisabled,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          min: 1,
          max: 30
        ).some,
        style = a.ui.textFieldStyle
      )

    group:
      koi.label("Disable vertical sync", style=a.ui.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.disableVSync, style = a.ui.checkBoxStyle)

  koi.endView()


  proc okAction(dlg: var PreferencesDialogParams; a) =
    a.opt.showSplash        = dlg.showSplash
    a.opt.autoCloseSplash   = dlg.autoCloseSplash
    a.opt.splashTimeoutSecs = parseInt(dlg.splashTimeoutSecs).Natural
    a.opt.loadLastMap       = dlg.loadLastMap
    a.opt.disableVSync      = dlg.disableVSync
    a.opt.autosave          = dlg.autosave
    a.opt.autosaveFreqMins  = parseInt(dlg.autosaveFreqMins).Natural

    saveConfig(a)
    setSwapInterval(a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var PreferencesDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                style = a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.ui.buttonStyle):
    cancelAction(dlg, a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Save/discard changes dialog

proc saveMapAction(a)

proc saveDiscardDialog(dlg: var SaveDiscardDialogParams; a) =
  const
    DlgWidth = 350.0
    DlgHeight = 160.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Changes?",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have unsaved changes.",
            style=a.ui.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save your changes first?",
    style=a.ui.labelStyle
  )

  proc saveAction(dlg: var SaveDiscardDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false
    saveMapAction(a)
    dlg.action(a)

  proc discardAction(dlg: var SaveDiscardDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false
    dlg.action(a)

  proc cancelAction(dlg: var SaveDiscardDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.ui.buttonStyle):
    saveAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.ui.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel):  cancelAction(dlg, a)
    elif ke.isShortcutDown(scDiscard): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept):  saveAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New map dialog
proc openNewMapDialog(a) =
  alias(dlg, a.dialog.newMapDialog)
  alias(co, a.doc.map.coordOpts)

  dlg.name        = "Untitled Map"
  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.isOpen = true


proc newMapDialog(dlg: var NewMapDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 375.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Map",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  a.clearStatusMessage()

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.beginView(x, y, 1000, 1000)
  koi.initAutoLayout(DialogLayoutParams)

  koi.label("Name", style=a.ui.labelStyle)
  koi.textField(
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: 0,
      maxLen: MapNameMaxLen
    ).some,
    style = a.ui.textFieldStyle
  )

  coordinateFields()

  koi.endView()

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")

  if validationError != "":
    koi.label(x, DlgHeight - 70, DlgWidth, DlgItemHeight, validationError,
              style=a.ui.warningLabelStyle)


  proc okAction(dlg: var NewMapDialogParams; a) =
    if validationError != "": return

    a.doc.filename = ""
    a.doc.map = newMap(dlg.name)

    alias(co, a.doc.map.coordOpts)
    co.origin      = CoordinateOrigin(dlg.origin)
    co.rowStyle    = CoordinateStyle(dlg.rowStyle)
    co.columnStyle = CoordinateStyle(dlg.columnStyle)
    co.rowStart    = parseInt(dlg.rowStart)
    co.columnStart = parseInt(dlg.columnStart)

    initUndoManager(a.doc.undoManager)

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, "New map created", a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var NewMapDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=validationError != "", style = a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit map properties dialog
proc openMapPropsDialog(a) =
  alias(dlg, a.dialog.editMapPropsDialog)
  dlg.name = $a.doc.map.name

  alias(co, a.doc.map.coordOpts)
  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.isOpen = true


proc editMapPropsDialog(dlg: var EditMapPropsDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 375.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  Edit Map Properties",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.beginView(x, y, 1000, 1000)
  koi.initAutoLayout(DialogLayoutParams)

  koi.label("Name", style=a.ui.labelStyle)
  koi.textField(
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: 0,
      maxLen: MapNameMaxLen
    ).some,
    style = a.ui.textFieldStyle
  )

  coordinateFields()

  koi.endView()

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")

  if validationError != "":
    koi.label(x, DlgHeight - 70, DlgWidth, DlgItemHeight, validationError,
              style=a.ui.warningLabelStyle)


  proc okAction(dlg: var EditMapPropsDialogParams; a) =
    if validationError != "": return

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    actions.setMapProps(a.doc.map, a.ui.cursor, dlg.name, coordOpts,
                        a.doc.undoManager)

    setStatusMessage(IconFile, "Map properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditMapPropsDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New level dialog
proc openNewLevelDialog(a) =
  alias(dlg, a.dialog.newLevelDialog)

  var co: CoordinateOptions

  if mapHasLevels(a):
    let l = currLevel(a)
    dlg.locationName = l.locationName
    dlg.levelName = ""
    dlg.elevation = if   l.elevation > 0: $(l.elevation + 1)
                    elif l.elevation < 0: $(l.elevation - 1)
                    else: "0"
    dlg.rows = $l.rows
    dlg.cols = $l.cols
    dlg.overrideCoordOpts = l.overrideCoordOpts

    co = coordOptsForCurrLevel(a)

  else:
    dlg.locationName = "Untitled Location"
    dlg.levelName = ""
    dlg.elevation = "0"
    dlg.rows = "16"
    dlg.cols = "16"
    dlg.overrideCoordOpts = false

    co = a.doc.map.coordOpts

  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.enableRegions   = false
  dlg.regionColumns   = "16"
  dlg.regionRows      = "16"
  dlg.perRegionCoords = true

  dlg.isOpen = true
  dlg.activeTab = 0


proc newLevelDialog(dlg: var NewLevelDialogParams; a) =
  alias(map, a.doc.map)
  alias(cur, a.ui.cursor)

  const
    DlgWidth = 430.0
    DlgHeight = 436.0
    TabWidth = 300.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Level",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions"]

  koi.radioButtons(
    (DlgWidth - TabWidth) / 2, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.ui.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  koi.initAutoLayout(DialogLayoutParams)

  if dlg.activeTab == 0:  # General

    levelCommonFields()

    group:
      koi.label("Columns", style=a.ui.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.cols,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          min: LevelNumColumnsMin,
          max: LevelNumColumnsMax
        ).some,
        style = a.ui.textFieldStyle
      )

      koi.label("Rows", style=a.ui.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.rows,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          min: LevelNumRowsMin,
          max: LevelNumRowsMax
        ).some,
        style = a.ui.textFieldStyle
      )

  elif dlg.activeTab == 1:  # Coordinates

    group:
      koi.label("Override map settings", style=a.ui.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.overrideCoordOpts, style = a.ui.checkBoxStyle)

      if dlg.overrideCoordOpts:
        coordinateFields()

  elif dlg.activeTab == 2:  # Regions

    regionFields()


  koi.endView()


  # Validation
  var validationError = ""
  validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.ui.warningLabelStyle)


  proc okAction(dlg: var NewLevelDialogParams; a) =
    if validationError != "": return

    let
      rows = parseInt(dlg.rows)
      cols = parseInt(dlg.cols)
      elevation = parseInt(dlg.elevation)

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    let regionOpts = RegionOptions(
      enableRegions   : dlg.enableRegions,
      regionColumns   : parseInt(dlg.regionColumns),
      regionRows      : parseInt(dlg.regionRows),
      perRegionCoords : dlg.perRegionCoords
    )

    cur = actions.addNewLevel(
      a.doc.map, cur, dlg.locationName,
      dlg.levelName, elevation, rows, cols,
      dlg.overrideCoordOpts, coordOpts, regionOpts,
      a.doc.undoManager
    )

    setStatusMessage(IconFile, fmt"New {rows}x{cols} level created", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var NewLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit level properties dialog
proc openEditLevelPropsDialog(a) =
  alias(dlg, a.dialog.editLevelPropsDialog)

  let l = currLevel(a)
  dlg.locationName = l.locationName
  dlg.levelName = l.levelName
  dlg.elevation = $l.elevation

  let co = coordOptsForCurrLevel(a)
  dlg.overrideCoordOpts = l.overrideCoordOpts
  dlg.origin            = co.origin.ord
  dlg.rowStyle          = co.rowStyle.ord
  dlg.columnStyle       = co.columnStyle.ord
  dlg.rowStart          = $co.rowStart
  dlg.columnStart       = $co.columnStart

  let ro = l.regionOpts
  dlg.enableRegions = ro.enableRegions
  dlg.regionColumns = $ro.regionColumns
  dlg.regionRows = $ro.regionRows
  dlg.perRegionCoords = ro.perRegionCoords

  dlg.isOpen = true


proc editLevelPropsDialog(dlg: var EditLevelPropsParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 430.0
    DlgHeight = 436.0
    TabWidth = 300.0

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconNewFile}  Edit Level Properties",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions"]

  koi.radioButtons(
    (DlgWidth - TabWidth) / 2, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.ui.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  koi.initAutoLayout(DialogLayoutParams)

  if dlg.activeTab == 0:  # General

    levelCommonFields()

  elif dlg.activeTab == 1:  # Coordinates

    koi.label("Override map settings", style=a.ui.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.overrideCoordOpts, style = a.ui.checkBoxStyle)

    if dlg.overrideCoordOpts:
      coordinateFields()

  elif dlg.activeTab == 2:  # Regions

    regionFields()

  koi.endView()


  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""

  let l = currLevel(a)
  if dlg.locationName != l.locationName or
     dlg.levelName != l.levelName or
     dlg.elevation != $l.elevation:

    validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.ui.warningLabelStyle)


  proc okAction(dlg: var EditLevelPropsParams; a) =
    if validationError != "": return

    let elevation = parseInt(dlg.elevation)

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    let regionOpts = RegionOptions(
      enableRegions   : dlg.enableRegions,
      regionRows      : parseInt(dlg.regionRows),
      regionColumns   : parseInt(dlg.regionColumns),
      perRegionCoords : dlg.perRegionCoords
    )

    actions.setLevelProps(a.doc.map, a.ui.cursor,
                          dlg.locationName, dlg.levelName, elevation,
                          dlg.overrideCoordOpts, coordOpts, regionOpts,
                          a.doc.undoManager)

    setStatusMessage(fmt"Level properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditLevelPropsParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high)

    if   ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Resize level dialog
proc openResizeLevelDialog(a) =
  alias(dlg, a.dialog.resizeLevelDialog)

  let l = currLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter
  dlg.isOpen = true


proc resizeLevelDialog(dlg: var ResizeLevelDialogParams; a) =
  const
    DlgWidth = 270.0
    DlgHeight = 300.0
    LabelWidth = 80.0
    PadYSmall = 32
    PadYLarge = 40

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCrop}  Resize Level",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Columns", style=a.ui.labelStyle)
  koi.textField(
    x + LabelWidth, y, w = DlgNumberWidth, h,
    dlg.cols,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckInteger,
      min: LevelNumColumnsMin,
      max: LevelNumColumnsMax
    ).some,
    style = a.ui.textFieldStyle
  )

  y += PadYSmall
  koi.label(x, y, LabelWidth, h, "Rows", style=a.ui.labelStyle)
  koi.textField(
    x + LabelWidth, y, w = DlgNumberWidth, h,
    dlg.rows,
    constraint = TextFieldConstraint(
      kind: tckInteger,
      min: LevelNumRowsMin,
      max: LevelNumRowsMax
    ).some,
    style = a.ui.textFieldStyle
  )

  const IconsPerRow = 3

  const AnchorIcons = @[
    IconArrowUpLeft,   IconArrowUp,   IconArrowUpRight,
    IconArrowLeft,     IconCircleInv, IconArrowRight,
    IconArrowDownLeft, IconArrowDown, IconArrowDownRight
  ]

  y += PadYLarge
  koi.label(x, y, LabelWidth, h, "Anchor", style=a.ui.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 35, 35,
    labels = AnchorIcons,
    dlg.anchor,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: IconsPerRow),
    style = a.ui.iconRadioButtonsStyle
  )

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  dlg.activateFirstTextField = false


  proc okAction(dlg: var ResizeLevelDialogParams; a) =
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

    let newCur = actions.resizeLevel(a.doc.map, a.ui.cursor, newRows, newCols,
                                     align, a.doc.undoManager)
    moveCursorTo(newCur, a)

    setStatusMessage(IconCrop, "Level resized", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var ResizeLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.anchor = ResizeAnchor(
      handleGridRadioButton(ke, ord(dlg.anchor), AnchorIcons.len, IconsPerRow)
    )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Delete level dialog
proc openDeleteLevelDialog(a) =
  alias(dlg, a.dialog.deleteLevelDialog)
  dlg.isOpen = true


proc deleteLevelDialog(dlg: var DeleteLevelDialogParams; a) =
  alias(map, a.doc.map)
  alias(cur, a.ui.cursor)
  alias(um, a.doc.undoManager)

  const
    DlgWidth = 350.0
    DlgHeight = 136.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete level?",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "Do you want to delete the current level?",
            style=a.ui.labelStyle)

  proc deleteAction(dlg: var DeleteLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

    cur = actions.deleteLevel(map, cur, um)
    setStatusMessage(IconTrash, "Deleted level", a)


  proc cancelAction(dlg: var DeleteLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.ui.buttonStyle):
    deleteAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel):  cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept):  deleteAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit note dialog
proc openEditNoteDialog(a) =
  alias(dlg, a.dialog.editNoteDialog)
  alias(cur, a.ui.cursor)

  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  if l.hasNote(cur.row, cur.col) and
     l.getNote(cur.row, cur.col).kind != nkLabel:

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


proc editNoteDialog(dlg: var EditNoteDialogParams; a) =
  alias(ls, a.doc.levelStyle)

  const
    DlgWidth = 486.0
    DlgHeight = 410.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Marker", style=a.ui.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 296, h,
    labels = @["None", "Number", "ID", "Icon"],
    dlg.kind,
    style = a.ui.radioButtonStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Text", style=a.ui.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w = 346, h = 92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      minLen: 0,
      maxLen: NoteTextMaxLen
    ).some,
    style = a.ui.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.noteIndexBgColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of nkIndexed:
    koi.label(x, y, LabelWidth, h, "Color", style=a.ui.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 28, 28,
      labels = newSeq[string](ls.noteIndexBgColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc = colorRadioButtonDrawProc(ls.noteIndexBgColor.toSeq,
                                          ls.cursorColor).some
    )

  of nkCustomId:
    koi.label(x, y, LabelWidth, h, "ID", style=a.ui.labelStyle)
    koi.textField(
      x + LabelWidth, y, w = DlgNumberWidth, h,
      dlg.customId,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: 0,
        maxLen: NoteCustomIdMaxLen
      ).some,
      style = a.ui.textFieldStyle
    )

  of nkIcon:
    koi.label(x, y, LabelWidth, h, "Icon", style=a.ui.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 35, 35,
      labels = NoteIcons,
      dlg.icon,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 10),
      style = a.ui.iconRadioButtonsStyle
    )

  of nkComment, nkLabel: discard

  dlg.activateFirstTextField = false

  # Validation
  var validationErrors: seq[string] = @[]

  if dlg.kind in {nkComment, nkIndexed, nkCustomId}:
    if dlg.text == "":
      validationErrors.add(mkValidationError("Text is mandatory"))
  if dlg.kind == nkCustomId:
    if dlg.customId == "":
      validationErrors.add(mkValidationError("ID is mandatory"))
    else:
      for c in dlg.customId:
        if not isAlphaNumeric(c):
          validationErrors.add(
            mkValidationError(
              "ID must contain only alphanumeric characters (a-z, A-Z, 0-9)"
            )
          )
          break

  y += 44

  for err in validationErrors:
    koi.label(x, y, DlgWidth, h, err, style=a.ui.warningLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: var EditNoteDialogParams; a) =
    if validationErrors.len > 0: return

    var note = Note(
      kind: dlg.kind,
      text: dlg.text
    )
    case note.kind
    of nkCustomId: note.customId = dlg.customId
    of nkIndexed:  note.indexColor = dlg.indexColor
    of nkIcon:     note.icon = dlg.icon
    of nkComment, nkLabel: discard

    actions.setNote(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set cell note", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditNoteDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=validationErrors.len > 0,
                style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.kind = NoteKind(
      handleTabNavigation(ke, ord(dlg.kind), ord(nkIcon))
    )

    case dlg.kind
    of nkComment, nkCustomId, nkLabel: discard
    of nkIndexed:
      dlg.indexColor = handleGridRadioButton(
        ke, dlg.indexColor, NumIndexColors, buttonsPerRow=NumIndexColors
      )
    of nkIcon:
      dlg.icon = handleGridRadioButton(
        ke, dlg.icon, NoteIcons.len, IconsPerRow
      )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit label dialog
proc openEditLabelDialog(a) =
  alias(dlg, a.dialog.editLabelDialog)
  alias(cur, a.ui.cursor)

  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  if l.hasNote(cur.row, cur.col) and
     l.getNote(cur.row, cur.col).kind == nkLabel:

    let note = l.getNote(cur.row, cur.col)
    dlg.editMode = true
    dlg.text = note.text
    dlg.color = note.labelColor

  else:
    dlg.editMode = false
    dlg.text = ""
    dlg.color = 0

  dlg.isOpen = true


proc editLabelDialog(dlg: var EditLabelDialogParams; a) =
  alias(ls, a.doc.levelStyle)

  const
    DlgWidth = 492.0
    DlgHeight = 270.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Label"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some, style = a.ui.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Text", style=a.ui.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w = 346, h = 92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      minLen: 0,
      maxLen: NoteTextMaxLen
    ).some,
    style = a.ui.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.noteIndexBgColor.len

  koi.label(x, y, LabelWidth, h, "Color", style=a.ui.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 28, 28,
    labels = newSeq[string](ls.noteIndexBgColor.len), # TODO
    dlg.color,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc = colorRadioButtonDrawProc(ls.noteIndexBgColor.toSeq, # TODO
                                        ls.cursorColor).some,
    style = a.ui.radioButtonStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.text == "":
    validationError = mkValidationError("Text is mandatory")

  y += 44

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError, style=a.ui.warningLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: var EditLabelDialogParams; a) =
    if validationError != "": return

    var note = Note(kind: nkLabel, text: dlg.text, labelColor: dlg.color)
    actions.setLabel(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set label", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditLabelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.ui.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.ui.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.color = handleGridRadioButton(
      ke, dlg.color, NumIndexColors, buttonsPerRow=NumIndexColors  # TODO
    )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# }}}
# {{{ Actions

# {{{ undoAction()
proc undoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canUndo():
    let undoStateData = um.undo(a.doc.map)
    if mapHasLevels(a):
      moveCursorTo(undoStateData.location, a)
    setStatusMessage(IconUndo, fmt"Undid action: {undoStateData.actionName}", a)
  else:
    setStatusMessage(IconWarning, "Nothing to undo", a)

# }}}
# {{{ redoAction()
proc redoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canRedo():
    let undoStateData = um.redo(a.doc.map)
    moveCursorTo(undoStateData.location, a)
    setStatusMessage(IconRedo,
                     fmt"Redid action: {undoStateData.actionName}", a)
  else:
    setStatusMessage(IconWarning, "Nothing to redo", a)
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
# {{{ loadMap()
proc loadMap(filename: string; a): bool =
  info(fmt"Loading map '{filename}'...")

  try:
    let t0 = getMonoTime()
    a.doc.map = readMapFile(filename)
    let dt = getMonoTime() - t0

    a.doc.filename = filename
    a.doc.lastAutosaveTime = getMonoTime()

    initUndoManager(a.doc.undoManager)

    resetCursorAndViewStart(a)

    let message = fmt"Map '{filename}' loaded in " &
                  fmt"{durationToFloatMillis(dt):.2f} ms"

    info(message)
    setStatusMessage(IconFloppy, message, a)
    result = true

  except CatchableError as e:
    logError(e)
    setStatusMessage(IconWarning, fmt"Cannot load map: {e.msg}", a)

# }}}
# {{{ openMap()
proc openMap(a) =
  when defined(DEBUG): discard
  else:
    let filename = fileDialog(fdOpenFile,
                              filters=GridmongerMapFileFilter)
    if filename != "":
      discard loadMap(filename, a)

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
# {{{ saveMap()
proc saveMap(filename: string, autosave: bool = false; a) =
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)

  let mapDisplayOpts = MapDisplayOptions(
    currLevel    : cur.level,
    zoomLevel    : dp.getZoomLevel(),
    cursorRow    : cur.row,
    cursorCol    : cur.col,
    viewStartRow : dp.viewStartRow,
    viewStartCol : dp.viewStartCol
  )

  info(fmt"Saving map to '{filename}'")

  try:
    writeMapFile(a.doc.map, mapDisplayOpts, filename)
    a.doc.undoManager.setLastSaveState()

    if not autosave:
      setStatusMessage(IconFloppy, fmt"Map '{filename}' saved", a)

  except CatchableError as e:
    logError(e)
    let prefix = if autosave: "Autosave failed: " else: ""
    setStatusMessage(IconWarning, fmt"{prefix}Cannot save map: {e.msg}", a)

# }}}
# {{{ saveMapAsAction()
proc saveMapAsAction(a) =
  when not defined(DEBUG):
    var filename = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if filename != "":
      filename = addFileExt(filename, MapFileExt)

      saveMap(filename, autosave=false, a)
      a.doc.filename = filename

# }}}
# {{{ saveMapAction()
proc saveMapAction(a) =
  if a.doc.filename != "": saveMap(a.doc.filename, autosave=false, a)
  else: saveMapAsAction(a)

# }}}
# {{{ reloadThemeAction()
proc reloadThemeAction(a) =
  a.theme.nextThemeIndex = a.theme.currThemeIndex.some

# }}}
# {{{ prevThemeAction()
proc prevThemeAction(a) =
  var i = a.theme.currThemeIndex
  if i == 0: i = a.theme.themeNames.high else: dec(i)
  a.theme.nextThemeIndex = i.some

# }}}
# {{{ nextThemeAction()
proc nextThemeAction(a) =
  var i = a.theme.currThemeIndex
  inc(i)
  if i > a.theme.themeNames.high: i = 0
  a.theme.nextThemeIndex = i.some

# }}}
# {{{ prevLevelAction()
proc prevLevelAction(a) =
  alias(cur, a.ui.cursor)
  var si = currSortedLevelIdx(a)
  if si > 0:
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si - 1]

# }}}
# {{{ nextLevelAction()
proc nextLevelAction(a) =
  alias(cur, a.ui.cursor)
  var si = currSortedLevelIdx(a)
  if si < a.doc.map.levels.len-1:
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si + 1]

# }}}
# {{{ centerCursorAfterZoom()
proc centerCursorAfterZoom(a) =
  alias(cur, a.ui.cursor)
  alias(dp, a.ui.drawLevelParams)

  let viewCol = round(a.ui.lastCursorViewX / dp.gridSize).int
  let viewRow = round(a.ui.lastCursorViewY / dp.gridSize).int
  dp.viewStartCol = max(cur.col - viewCol, 0)
  dp.viewStartRow = max(cur.row - viewRow, 0)

# }}}
# {{{ incZoomLevelAction()
proc incZoomLevelAction(a) =
  incZoomLevel(a.doc.levelStyle, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}
# {{{ decZoomLevelAction()
proc decZoomLevelAction(a) =
  decZoomLevel(a.doc.levelStyle, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}
# {{{ setFloorAction()
proc setFloorAction(f: Floor; a) =
  alias(cur, a.ui.cursor)

  let ot = a.doc.map.guessFloorOrientation(cur)
  actions.setOrientedFloor(a.doc.map, cur, f, ot, a.ui.currFloorColor,
                           a.doc.undoManager)
  setStatusMessage(fmt"Set floor – {f}", a)

# }}}
# {{{ setOrCycleFloorAction()
proc setOrCycleFloorAction(first, last: Floor, forward: bool; a) =
  assert first <= last

  var floor = a.doc.map.getFloor(a.ui.cursor)

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
  actions.excavate(a.doc.map, a.ui.cursor, a.ui.currFloorColor,
                   a.doc.undoManager)

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

# }}}

# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents(a) =
  alias(ui, a.ui)
  alias(opt, a.opt)

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

  else:   # not WASD mode
    if koi.mbLeftDown():
      let loc= locationAtMouse(a)
      if loc.isSome:
        a.ui.cursor = loc.get



# }}}
# {{{ handleGlobalKeyEvents()
# TODO separate into level events and global events
proc handleGlobalKeyEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(cur, a.ui.cursor)
  alias(um, a.doc.undoManager)
  alias(dp, a.ui.drawLevelParams)
  alias(opt, a.opt)
  alias(ls, a.doc.levelStyle)

  var l = currLevel(a)

  type
    WalkKeys = object
      forward, backward, strafeLeft, strafeRight, turnLeft, turnRight: set[Key]

  const
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
    if map.isEmpty(cur):
      actions.setFloor(map, cur, fTrail, ui.currFloorColor, um)

  proc toggleOption(opt: var bool, icon, msg, on, off: string; a) =
    opt = not opt
    let state = if opt: on else: off
    setStatusMessage(icon, fmt"{msg} {state}", a)

  proc toggleShowOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="shown", off="hidden", a)

  proc toggleOnOffOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="on", off="off", a)


  proc handleMoveWalk(ke: Event; a) =
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


  template handleMoveKeys(ke: Event, moveHandler: untyped) =
    let k = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor

    if   ke.isKeyDown(k.left,  repeat=true): moveHandler(dirW, a)
    elif ke.isKeyDown(k.right, repeat=true): moveHandler(dirE, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveHandler(dirN, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveHandler(dirS, a)


  proc handleMoveCursor(ke: Event, k: MoveKeys; a): bool =
    const j = CursorJump
    result = true

    if   ke.isKeyDown(k.left,  repeat=true): moveCursor(dirW, 1, a)
    elif ke.isKeyDown(k.right, repeat=true): moveCursor(dirE, 1, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveCursor(dirN, 1, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveCursor(dirS, 1, a)

    elif ke.isKeyDown(k.left,  {mkCtrl}, repeat=true): moveCursor(dirW, j, a)
    elif ke.isKeyDown(k.right, {mkCtrl}, repeat=true): moveCursor(dirE, j, a)
    elif ke.isKeyDown(k.up,    {mkCtrl}, repeat=true): moveCursor(dirN, j, a)
    elif ke.isKeyDown(k.down,  {mkCtrl}, repeat=true): moveCursor(dirS, j, a)

    elif ke.isKeyDown(k.left,  {mkShift}, repeat=true): moveLevel(dirW, 1, a)
    elif ke.isKeyDown(k.right, {mkShift}, repeat=true): moveLevel(dirE, 1, a)
    elif ke.isKeyDown(k.up,    {mkShift}, repeat=true): moveLevel(dirN, 1, a)
    elif ke.isKeyDown(k.down,  {mkShift}, repeat=true): moveLevel(dirS, 1, a)

    elif ke.isKeyDown(k.left,  {mkCtrl, mkShift}, repeat=true): moveLevel(dirW, j, a)
    elif ke.isKeyDown(k.right, {mkCtrl, mkShift}, repeat=true): moveLevel(dirE, j, a)
    elif ke.isKeyDown(k.up,    {mkCtrl, mkShift}, repeat=true): moveLevel(dirN, j, a)
    elif ke.isKeyDown(k.down,  {mkCtrl, mkShift}, repeat=true): moveLevel(dirS, j, a)

    result = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    # TODO eventHandled is not set here, but it's not actually needed (yet)

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # This to prevent creating an undoable action for every turn in walk
      # mode
      let prevCursor = cur

      if opt.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        if handleMoveCursor(ke, moveKeys, a):
          setStatusMessage("moved", a)

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
        actions.setFloor(map, cur, fEmpty, ui.currFloorColor, um)

      elif ke.isKeyDown(keyO):
        actions.toggleFloorOrientation(map, cur, um)
        if map.getFloorOrientation(cur) == Horiz:
          setStatusMessage(IconArrowsHoriz,
                           "Floor orientation set to horizontal", a)
        else:
          setStatusMessage(IconArrowsVert,
                           "Floor orientation set to vertical", a)

      elif ke.isKeyDown(keyC):
        ui.editMode = emColorFloor
        setStatusMessage(IconEraser, "Set color",
                         @[IconArrowsAll, "set color"], a)

        let floor = map.getFloor(cur)
        if floor != fNone:
          actions.setFloorColor(map, cur, ui.currFloorColor, um)

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
        setOrCycleFloorAction(fStairsDown, fDoorExit,
                              forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key6) or ke.isKeyDown(key6, {mkShift}):
        setFloorAction(fSpinner, a)

      elif ke.isKeyDown(key7) or ke.isKeyDown(key7, {mkShift}):
        setFloorAction(fInvisibleBarrier, a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isKeyDown(keyComma, repeat=true):
        if ui.currFloorColor > 0: dec(ui.currFloorColor)
        else: ui.currFloorColor = ls.floorColor.high.byte

      elif ke.isKeyDown(keyPeriod, repeat=true):
        if ui.currFloorColor < ls.floorColor.high.byte: inc(ui.currFloorColor)
        else: ui.currFloorColor = 0

      elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyU, repeat=true):
        undoAction(a)

      elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true) or
           ke.isKeyDown(keyR, {mkCtrl}, repeat=true):
        redoAction(a)

      elif ke.isKeyDown(keyM):
        enterSelectMode(a)

      elif ke.isKeyDown(keyP):
        if ui.copyBuf.isSome:
          actions.pasteSelection(map, cur, ui.copyBuf.get,
                                 linkSrcLevelIndex=CopyBufferLevelIndex, um)
          if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

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
          l.locationName, l.levelName, l.elevation,
          l.rows, l.cols,
          l.overrideCoordOpts, l.coordOpts,
          l.regionOpts, l.regionNames
        )

        dp.selStartRow = 0
        dp.selStartCol = 0

        ui.editMode = emNudgePreview
        setStatusMessage(IconArrowsAll, "Nudge preview",
                         @[IconArrowsAll, "nudge",
                         "Enter", "confirm", "Esc", "exit"], a)

      elif ke.isKeyDown(keyG):
        let floor = map.getFloor(cur)
        let linkType = capitalizeAscii(linkFloorToString(floor))

        proc jumpToDest(a): bool =
          let src = cur
          if map.links.hasWithSrc(src):
            let dest = map.links.getBySrc(src)
            if isSpecialLevelIndex(dest.level):
              result = false
            else:
              moveCursorTo(dest, a)
              result = true

        proc jumpToSrc(a): bool =
          let dest = cur
          if map.links.hasWithDest(dest):
            let src = map.links.getByDest(dest)
            if isSpecialLevelIndex(src.level):
              result = false
            else:
              moveCursorTo(src, a)
              result = true

        if floor in (LinkPitSources + {fTeleportSource}):
          if not jumpToDest(a):
            setStatusMessage(IconWarning,
                             fmt"{linkType} is not linked to a destination", a)

        elif floor in (LinkPitDestinations + {fTeleportDestination}):
          if not jumpToSrc(a):
            setStatusMessage(IconWarning,
                             fmt"{linkType} is not linked to a source", a)

        elif floor in (LinkStairs + LinkDoors):
          if not jumpToDest(a):
            if not jumpToSrc(a):
              setStatusMessage(IconWarning, fmt"{linktype} is not linked", a)

        else:
          setStatusMessage(IconWarning, "Not a linked cell", a)


      elif ke.isKeyDown(keyG, {mkShift}):
        let floor = map.getFloor(cur)
        if floor in LinkSources:
          ui.linkSrcLocation = cur
          ui.editMode = emSetCellLink

          # TODO icon per type
          setStatusMessage(IconLink,
                           fmt"Set {linkFloorToString(floor)} destination",
                           @[IconArrowsAll, "select cell",
                           "Enter", "set", "Esc", "cancel"], a)
        else:
          setStatusMessage(IconWarning,
                           "Cannot link current cell", a)

      elif ke.isKeyDown(keyEqual, repeat=true):
        incZoomLevelAction(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyMinus, repeat=true):
        decZoomLevelAction(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isKeyDown(keyN):
        if map.isEmpty(cur):
          setStatusMessage(IconWarning, "Cannot attach note to empty cell", a)
        else:
          openEditNoteDialog(a)

      elif ke.isKeyDown(keyN, {mkShift}):
        if not map.hasNote(cur):
          setStatusMessage(IconWarning, "No note to erase in cell", a)
        else:
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)

      elif ke.isKeyDown(keyT, {mkShift}):
        if not (map.hasNote(cur) and map.getNote(cur).kind == nkLabel):
          setStatusMessage(IconWarning, "No label to erase in cell", a)
        else:
          actions.eraseLabel(map, cur, um)
          setStatusMessage(IconEraser, "Label erased", a)

#[ TODO
      elif ke.isKeyDown(keyD, {mkCtrl, mkAlt}):
        actions.excavateTrail(map, cur, um)
        setStatusMessage(IconEraser, "Trail excavated", a)

      elif ke.isKeyDown(keyC, {mkCtrl, mkAlt}):
        actions.clearTrail(map, cur, um)
        setStatusMessage(IconEraser, "Trail cleared", a)
]#
      elif ke.isKeyDown(keyT, {mkCtrl}):
        openEditLabelDialog(a)

      elif ke.isKeyDown(keyU, {mkCtrl, mkAlt}):
        openPreferencesDialog(a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        openNewLevelDialog(a)

      elif ke.isKeyDown(keyD, {mkCtrl}):
        openDeleteLevelDialog(a)

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

      elif ke.isKeyDown(keyF12):
        toggleShowOption(opt.showThemePane, NoIcon, "Theme editor pane", a)

    # }}}
    # {{{ emExcavate, emEraseCell, emClearFloor, emColorFloor
    of emExcavate, emEraseCell, emClearFloor, emColorFloor:
      # This to prevent creating an undoable action for every turn in walk
      # mode
      let prevCursor = cur

      if opt.walkMode: handleMoveWalk(ke, a)
      else:
        # TODO disallow cursor jump with ctrl
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      if cur != prevCursor:
        if   ui.editMode == emExcavate:
          actions.excavate(map, cur, ui.currFloorColor, um)

        elif ui.editMode == emEraseCell:
          actions.eraseCell(map, cur, um)

        elif ui.editMode == emClearFloor:
          actions.setFloor(map, cur, fEmpty, ui.currFloorColor, um)

        elif ui.editMode == emColorFloor:
          let floor = map.getFloor(cur)
          if floor != fNone:
            actions.setFloorColor(map, cur, ui.currFloorColor, um)

      if not opt.wasdMode and ke.isKeyUp({keyD, keyE}):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isKeyUp({keyF, keyC}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir; a) =
        if map.canSetWall(cur, dir):
          let w = if map.getWall(cur, dir) == wWall: wNone
                  else: wWall
          actions.setWall(map, cur, dir, w, um)

      handleMoveKeys(ke, handleMoveKey)

      if not opt.wasdMode and ke.isKeyUp({keyW}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWallSpecial
    of emDrawWallSpecial:
      proc handleMoveKey(dir: CardinalDir; a) =
        if map.canSetWall(cur, dir):
          var curSpecWall = SpecialWalls[ui.currSpecialWall]
          if   curSpecWall == wOneWayDoorNE:
            if dir in {dirS, dirW}: curSpecWall = wOneWayDoorSW
          elif curSpecWall == wLeverSW:
            if dir in {dirN, dirE}: curSpecWall = wLeverNE
          elif curSpecWall == wNicheSW:
            if dir in {dirN, dirE}: curSpecWall = wNicheNE
          elif curSpecWall == wStatueSw:
            if dir in {dirN, dirE}: curSpecWall = wStatueNE
          elif curSpecWall == wWritingSW:
            if dir in {dirN, dirE}: curSpecWall = wWritingNE

          let w = if map.getWall(cur, dir) == curSpecWall: wNone
                  else: curSpecWall
          actions.setWall(map, cur, dir, w, um)

      handleMoveKeys(ke, handleMoveKey)

      if ke.isKeyUp({keyR}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      discard handleMoveCursor(ke, MoveKeysCursor, a)

      if koi.ctrlDown(): setSelectModeActionMessage(a)
      else:              setSelectModeSelectMessage(a)

      if   koi.isKeyDown(keyD): ui.selection.get[cur.row, cur.col] = true
      elif koi.isKeyDown(keyE): ui.selection.get[cur.row, cur.col] = false

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
        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isKeyDown(keyX):
        let selection = ui.selection.get
        # TODO !!! clear links with CopyBufferLevelIndex from map first!
        # (because there might be an "unpasted" selection in the "cut buffer")
        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          actions.cutSelection(map, cur, bbox, selection,
                               linkDestLevelIndex=CopyBufferLevelIndex, um)
          ui.cutToBuffer = true

          exitSelectMode(a)
          cur.row = bbox.r1
          cur.col = bbox.c1
          setStatusMessage(IconCut, "Cut selection to buffer", a)

      elif ke.isKeyDown(keyM, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = copySelection(ui.nudgeBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          actions.cutSelection(map, cur, bbox, selection,
                               linkDestLevelIndex=MoveBufferLevelIndex, um)
          exitSelectMode(a)

          # Enter paste preview mode
          cur.row = bbox.r1
          cur.col = bbox.c1
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          ui.editMode = emMovePreview
          setStatusMessage(IconTiles, "Move selection",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "confirm", "Esc", "cancel"], a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = selection.boundingBox()
        if bbox.isSome:
          actions.eraseSelection(map, cur.level, selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isKeyDown(keyF, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = selection.boundingBox()
        if bbox.isSome:
          actions.fillSelection(map, cur.level, selection, bbox.get,
                                ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Filled selection", a)

      elif ke.isKeyDown(Key.keyS, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = selection.boundingBox()
        if bbox.isSome:
          actions.surroundSelectionWithWalls(map, cur.level, selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isKeyDown(Key.keyC, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = selection.boundingBox()
        if bbox.isSome:
          actions.setSelectionFloorColor(map, cur.level, selection,
                                         bbox.get, ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isKeyDown(keyR, {mkCtrl}):
        let sel = ui.selection.get
        let bbox = sel.boundingBox()
        if bbox.isSome:
          let newCur = actions.cropLevel(map, cur, bbox.get, um)
          moveCursorTo(newCur, a)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Cropped level to selection", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      discard handleMoveCursor(ke, MoveKeysCursor, a)

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
      if opt.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      a.ui.drawLevelParams.selStartRow = a.ui.cursor.row
      a.ui.drawLevelParams.selStartCol = a.ui.cursor.col

      if ke.isKeyDown({keyEnter, keyP}):
        actions.pasteSelection(map, cur, ui.copyBuf.get,
                               linkSrcLevelIndex=CopyBufferLevelIndex, um)

        if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emMovePreview
    of emMovePreview:
      if opt.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      a.ui.drawLevelParams.selStartRow = a.ui.cursor.row
      a.ui.drawLevelParams.selStartCol = a.ui.cursor.col

      if ke.isKeyDown({keyEnter, keyP}):
        actions.pasteSelection(map, cur, ui.nudgeBuf.get,
                               linkSrcLevelIndex=MoveBufferLevelIndex,
                               um, groupWithPrev=true,
                               actionName="Move selection")

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Moved selection", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      handleMoveKeys(ke, moveSelStart)

      if   ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEnter):
        let newCur = actions.nudgeLevel(map, cur,
                                        dp.selStartRow, dp.selStartCol,
                                        ui.nudgeBuf.get, um)
        moveCursorTo(newCur, a)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        map.levels[cur.level] = ui.nudgeBuf.get.level
        ui.nudgeBuf = SelectionBuffer.none
        clearStatusMessage(a)

    # }}}
    # {{{ emSetCellLink
    of emSetCellLink:
      if opt.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opt.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      if ke.isKeyDown({keyPageUp, keyKpSubtract}) or
         ke.isKeyDown(keyMinus, {mkCtrl}):
        prevLevelAction(a)

      elif ke.isKeyDown({keyPageDown, keyKpAdd}) or
           ke.isKeyDown(keyEqual, {mkCtrl}):
        nextLevelAction(a)

      elif ke.isKeyDown(keyEnter):
        actions.setLink(map, src=ui.linkSrcLocation, dest=cur,
                        ui.currFloorColor, um)
        ui.editMode = emNormal
        let linkType = linkFloorToString(map.getFloor(cur))
        setStatusMessage(IconLink,
                         fmt"{capitalizeAscii(linkType)} link destination set",
                         a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  if hasKeyEvent():
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

    elif ke.isKeyDown(keyU,        {mkCtrl, mkAlt}):   openPreferencesDialog(a)

    elif ke.isKeyDown(keyZ, {mkCtrl}, repeat=true) or
         ke.isKeyDown(keyU, repeat=true):
      undoAction(a)

    elif ke.isKeyDown(keyY, {mkCtrl}, repeat=true) or
         ke.isKeyDown(keyR, {mkCtrl}, repeat=true):
      redoAction(a)

# }}}

# {{{ Drawing/rendering

# {{{ drawEmptyMap()
proc drawEmptyMap(a) =
  alias(vg, a.vg)
  alias(ls, a.doc.levelStyle)

  vg.setFont(size=22)
  vg.fillColor(ls.drawColor)
  vg.textAlign(haCenter, vaMiddle)
  var y = drawAreaHeight(a) * 0.5
  discard vg.text(drawAreaWidth(a) * 0.5, y, "Empty map")

# }}}
# {{{ drawNoteTooltip()
proc drawNoteTooltip(note: Note, a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(dp, a.ui.drawLevelParams)

  if note.text != "":
    const PadX = 10
    const PadY = 8

    var
      noteBoxX = koi.mx() + 16
      noteBoxY = koi.my() + 20
      noteBoxW = 250.0

    vg.setFont(14, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.5)

    let
      bounds = vg.textBoxBounds(noteBoxX + PadX,
                                noteBoxY + PadY,
                                noteBoxW - PadX*2, note.text)
      noteTextH = bounds.y2 - bounds.y1
      noteTextW = bounds.x2 - bounds.x1
      noteBoxH = noteTextH + PadY*2

    noteBoxW = noteTextW + PadX*2

    let
      xOver = noteBoxX + noteBoxW - (dp.startX + ui.levelDrawAreaWidth)
      yOver = noteBoxY + noteBoxH - (dp.startY + ui.levelDrawAreaHeight)

    if xOver > 0:
      noteBoxX -= xOver

    if yOver > 0:
      noteBoxY -= noteBoxH + 22

    vg.drawShadow(noteBoxX, noteBoxY, noteBoxW, noteBoxH)

    vg.fillColor(a.theme.style.level.noteTooltipBgColor)
    vg.beginPath()
    vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH, 5)
    vg.fill()

    vg.fillColor(a.theme.style.level.noteTooltipTextColor)
    vg.textBox(noteBoxX + PadX, noteBoxY + PadY, noteTextW, note.text)

# }}}
# {{{ renderLevel()
proc renderLevel(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opt, a.opt)

  let l = currLevel(a)

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
    if koi.hasNoActiveItem() and
       (koi.mbLeftDown() or koi.mbRightDown() or koi.mbMiddleDown()):
      koi.setActive(id)

  if koi.isHot(id) and isActive(id):
    handleLevelMouseEvents(a)

  # Draw level
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow = ui.cursor.row
    dp.cursorCol = ui.cursor.col
    dp.cellCoordOpts = coordOptsForCurrLevel(a)
    dp.regionOpts = l.regionOpts

    dp.cursorOrient = CardinalDir.none
    if opt.walkMode and
       ui.editMode in {emNormal, emExcavate, emEraseCell, emClearFloor}:
      dp.cursorOrient = ui.cursorOrient.some

    dp.selection = ui.selection
    dp.selectionRect = ui.selRect

    dp.selectionBuffer =
      if   ui.editMode == emPastePreview: ui.copyBuf
      elif ui.editMode in {emMovePreview, emNudgePreview}: ui.nudgeBuf
      else: SelectionBuffer.none

    drawLevel(
      a.doc.map,
      ui.cursor.level,
      DrawLevelContext(ls: a.doc.levelStyle, dp: dp, vg: a.vg)
    )

  # Draw note tooltip
  if koi.isHot(id):
    if not (opt.wasdMode and isActive(id)):

      let locOpt = locationAtMouse(a)
      if locOpt.isSome:
        let loc = locOpt.get

        if l.hasNote(loc.row, loc.col):
          let note = l.getNote(loc.row, loc.col)
          if note.kind != nkLabel:
            drawNoteTooltip(note, a)

# }}}
# {{{ renderToolsPane()
# {{{ specialWallDrawProc()
proc specialWallDrawProc(ls: LevelStyle,
                         ts: ToolbarPaneStyle,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               state: WidgetState, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var col = case state
              of wsActive:      ls.cursorColor
              of wsHover:       ts.buttonBgColorHover
              of wsActiveHover: ls.cursorColor
              of wsDown:        ls.cursorColor
              else:             ts.buttonBgColor

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let savedFloorColor = ls.floorColor[0]
    let savedBackgroundImage = dp.backgroundImage

    ls.floorColor[0] = lerp(ls.backgroundColor, col, col.a).withAlpha(1.0)
    dp.backgroundImage = Paint.none

    const Pad = 5

    vg.beginPath()
    vg.fillColor(col)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill()

    dp.setZoomLevel(ls, 4)
    let ctx = DrawLevelContext(ls: ls, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel(zl: Natural, body: untyped) =
      vg.save()
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(ls, zl)
      vg.intersectScissor(x+4.5, y+3, w-Pad*2-4, h-Pad*2-2)
      body
      dp.setZoomLevel(ls, 4)
      vg.restore()

    case SpecialWalls[buttonIdx]
    of wNone:              discard
    of wWall:              drawSolidWallHoriz(cx, cy, ctx=ctx)
    of wIllusoryWall:      drawIllusoryWallHoriz(cx+2, cy, ctx=ctx)
    of wInvisibleWall:     drawInvisibleWallHoriz(cx-2, cy, ctx=ctx)
    of wDoor:              drawDoorHoriz(cx, cy, ctx=ctx)
    of wLockedDoor:        drawLockedDoorHoriz(cx, cy, ctx=ctx)
    of wArchway:           drawArchwayHoriz(cx, cy, ctx=ctx)

    of wSecretDoor:
      drawAtZoomLevel(6):  drawSecretDoorHoriz(cx-2, cy, ctx=ctx)

    of wOneWayDoorNE:
      drawAtZoomLevel(8):  drawOneWayDoorHorizNE(cx-4, cy+1, ctx=ctx)

    of wLeverSW:
      drawAtZoomLevel(6):  drawLeverHorizSW(cx-2, cy+1, ctx=ctx)

    of wNicheSW:           drawNicheHorizSW(cx, cy, floorColor=0, ctx=ctx)

    of wStatueSW:
      drawAtZoomLevel(6):  drawStatueHorizSW(cx-2, cy+2, ctx=ctx)

    of wKeyhole:
      drawAtZoomLevel(6):  drawKeyholeHoriz(cx-2, cy, ctx=ctx)

    of wWritingSW:
      drawAtZoomLevel(12): drawWritingHorizSW(cx-6, cy+4, ctx=ctx)

    else: discard

    # ...aaaaand restore it!
    ls.floorColor[0] = savedFloorColor
    dp.backgroundImage = savedBackgroundImage

# }}}

proc renderToolsPane(x, y, w, h: float; a) =
  alias(ui, a.ui)
  alias(ls, a.doc.levelStyle)
  alias(ts, a.theme.style.toolbarPane)

  koi.radioButtons(
    x = x,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 20),
    drawProc = specialWallDrawProc(ls, ts, ui.toolbarDrawParams).some
  )

  koi.radioButtons(
    x = x + 3,
    y = y + 446,
    w = 30,
    h = 30,
    labels = newSeq[string](ls.floorColor.len),
    ui.currFloorColor,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridVert, itemsPerColumn: 9),
    drawProc = colorRadioButtonDrawProc(ls.floorColor.toSeq, ls.cursorColor).some
  )

# }}}
# {{{ drawNotesPane()
proc drawNotesPane(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(s, a.theme.style.notesPane)

  let l = currLevel(a)
  let cur = a.ui.cursor

  if not (a.ui.editMode in {emPastePreview, emNudgePreview}) and
     l.hasNote(cur.row, cur.col):

    let note = l.getNote(cur.row, cur.col)
    if note.text == "" or note.kind == nkLabel: return

    vg.save()

    case note.kind
    of nkIndexed:
      drawIndexedNote(x, y-12, note.index, 36,
                      bgColor=s.indexBgColor[note.indexColor],
                      fgColor=s.indexColor, vg)

    of nkCustomId:
      vg.fillColor(s.textColor)
      vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+18, y-2, note.customId)

    of nkIcon:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-3, NoteIcons[note.icon])

    of nkComment:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-2, IconComment)

    of nkLabel: discard

    vg.fillColor(s.textColor)
    vg.setFont(15, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.4)
    vg.intersectScissor(x+40, y, w-40, h)
    vg.textBox(x+40, y, w-40, note.text)

    vg.restore()

# }}}
# {{{ drawModeAndOptionIndicators()
proc drawModeAndOptionIndicators(a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(ls, a.doc.levelStyle)

  var x = ui.levelLeftPad
  let y = TitleBarHeight + 32

  vg.save()

  vg.fillColor(ls.coordsHighlightColor)

  if a.opt.wasdMode:
    vg.setFont(15.0)
    discard vg.text(x, y, fmt"WASD+{IconMouse}")
    x += 80

  if a.opt.drawTrail:
    vg.setFont(19)
    discard vg.text(x, y+1, IconShoePrints)

  vg.restore()

# }}}
# {{{ drawStatusBar()
proc drawStatusBar(y: float, winWidth: float; a) =
  alias(vg, a.vg)
  alias(s, a.theme.style.statusBar)

  let ty = y + StatusBarHeight * TextVertAlignFactor

  # Bar background
  vg.save()

  vg.beginPath()
  vg.rect(0, y, winWidth, StatusBarHeight)
  vg.fillColor(s.backgroundColor)
  vg.fill()

  # Display cursor coordinates
  vg.setFont(14)

  if mapHasLevels(a):
    let
      l = currLevel(a)
      coordOpts = coordOptsForCurrLevel(a)
      row = formatRowCoord(a.ui.cursor.row, l.rows, coordOpts, l.regionOpts)
      col = formatColumnCoord(a.ui.cursor.col, l.cols, coordOpts, l.regionOpts)
      cursorPos = fmt"({col}, {row})"
      tw = vg.textWidth(cursorPos)

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

# }}}
# {{{ Theme editor

var ThemeEditorScrollViewStyle = getDefaultScrollViewStyle()
with ThemeEditorScrollViewStyle:
  vertScrollBarWidth = 14.0
  with scrollBarStyle:
    thumbPad = 4.0

var ThemeEditorSliderStyle = getDefaultSliderStyle()
with ThemeEditorSliderStyle:
  trackCornerRadius = 8.0
  valueCornerRadius = 6.0

var ThemeEditorAutoLayoutParams = DefaultAutoLayoutParams
with ThemeEditorAutoLayoutParams:
  leftPad = 14.0
  rightPad = 16.0

# {{{ renderThemeEditorProps()
proc renderThemeEditorProps(x, y, w, h: float; a) =
  alias(te, a.themeEditor)
  alias(ts, a.theme.style)


  proc handleUndo() =
    discard

  macro prop(name: static[string], section: untyped, prop: untyped,
             widget: untyped): untyped =

    result = quote do:
      koi.label(`name`)
      `widget`
      if te.prevState.`section`.`prop` != ts.`section`.`prop`:
        handleUndo()


  macro prop(name: static[string],
             section: untyped, prop: untyped, index: static[int],
             widget: untyped): untyped =

    result = quote do:
      koi.label(`name`)
      `widget`
      if te.prevState.`section`.`prop`[`index`] != ts.`section`.`prop`[`index`]:
        handleUndo()


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  # {{{ User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      group:
        prop("Background", general, backgroundColor):
          koi.color(ts.general.backgroundColor)

      group:
        prop("Title Background", window, backgroundColor):
          koi.color(ts.window.backgroundColor)

        prop("Title Background Inactive", window, bgColorUnfocused):
          koi.color(ts.window.bgColorUnfocused)

        prop("Title", window, textColor):
          koi.color(ts.window.textColor)

        prop("Title Inactive", window, textColorUnfocused):
          koi.color(ts.window.textColorUnfocused)

        prop("Modified Flag", window, modifiedFlagColor):
          koi.color(ts.window.modifiedFlagColor)

      group:
        prop("Button", window, buttonColor):
          koi.color(ts.window.buttonColor)

        prop("Button Hover", window, buttonColorHover):
          koi.color(ts.window.buttonColorHover)

        prop("Button Down", window, buttonColorDown):
          koi.color(ts.window.buttonColorDown)


    if koi.subSectionHeader("Dialog", te.sectionDialog):
      group:
        prop("Corner Radius", dialog, cornerRadius):
          koi.horizSlider(startVal=WidgetCornerRadiusLimits.min,
                          endVal=WidgetCornerRadiusLimits.max,
                          ts.dialog.cornerRadius,
                          style=ThemeEditorSliderStyle)

        prop("Title Background", dialog, titleBarBgColor):
          koi.color(ts.dialog.titleBarBgColor)

        prop("Title", dialog, titleBarTextColor):
          koi.color(ts.dialog.titleBarTextColor)

        prop("Background", dialog, backgroundColor):
          koi.color(ts.dialog.backgroundColor)

        prop("Label", dialog, textColor):
          koi.color(ts.dialog.textColor)

        prop("Warning", dialog, warningTextColor):
          koi.color(ts.dialog.warningTextColor)

      group:
        prop("Outer Border", dialog, outerBorderColor):
          koi.color(ts.dialog.outerBorderColor)

        prop("Outer Border Width", dialog, outerBorderWidth):
          koi.horizSlider(startVal=DialogBorderWidthLimits.min,
                          endVal=DialogBorderWidthLimits.max,
                          ts.dialog.outerBorderWidth,
                          style=ThemeEditorSliderStyle)

        prop("Inner Border", dialog, innerBorderColor):
          koi.color(ts.dialog.innerBorderColor)

        prop("Inner Border Width", dialog, innerBorderWidth):
          koi.horizSlider(startVal=DialogBorderWidthLimits.min,
                          endVal=DialogBorderWidthLimits.max,
                          ts.dialog.innerBorderWidth,
                          style=ThemeEditorSliderStyle)

      group:
        prop("Shadow?", dialog, shadow):
          koi.checkBox(ts.dialog.shadow)

        prop("Shadow X Offset", dialog, shadowXOffset):
          koi.horizSlider(startVal=DialogShadowOffsetLimits.min,
                          endVal=DialogShadowOffsetLimits.max,
                          ts.dialog.shadowXOffset,
                          style=ThemeEditorSliderStyle)

        prop("Shadow Y Offset", dialog, shadowYOffset):
          koi.horizSlider(startVal=DialogShadowOffsetLimits.min,
                          endVal=DialogShadowOffsetLimits.max,
                          ts.dialog.shadowYOffset,
                          style=ThemeEditorSliderStyle)

        prop("Shadow Feather", dialog, shadowFeather):
          koi.horizSlider(startVal=DialogShadowFeatherLimits.min,
                          endVal=DialogShadowFeatherLimits.max,
                          ts.dialog.shadowFeather,
                          style=ThemeEditorSliderStyle)

        prop("Shadow Color", dialog, shadowColor):
          koi.color(ts.dialog.shadowColor)


    if koi.subSectionHeader("Widget", te.sectionWidget):
      group:
        prop("Corner Radius", general, cornerRadius):
          koi.horizSlider(startVal=WidgetCornerRadiusLimits.min,
                          endVal=WidgetCornerRadiusLimits.max,
                          ts.general.cornerRadius,
                          style=ThemeEditorSliderStyle)

      group:
        prop("Background", widget, bgColor):
          koi.color(ts.widget.bgColor)

        prop("Background Hover", widget, bgColorHover):
          koi.color(ts.widget.bgColorHover)

        prop("Background Active", general, highlightColor):
          koi.color(ts.general.highlightColor)

        prop("Background Disabled", widget, bgColorDisabled):
          koi.color(ts.widget.bgColorDisabled)

      group:
        prop("Foreground", widget, textColor):
          koi.color(ts.widget.textColor)

        prop("Foreground Active", widget, textColorActive):
          koi.color(ts.widget.textColorActive)

        prop("Foreground Disabled", widget, textColorDisabled):
          koi.color(ts.widget.textColorDisabled)


    if koi.subSectionHeader("Text Field", te.sectionTextField):
      prop("Edit Background", textField, bgColorActive):
        koi.color(ts.textField.bgColorActive)

      prop("Edit Text", textField, textColorActive):
        koi.color(ts.textField.textColorActive)

      prop("Cursor", textField, cursorColor):
        koi.color(ts.textField.cursorColor)

      prop("Selection", textField, selectionColor):
        koi.color(ts.textField.selectionColor)


    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      group:
        prop("Background", statusBar, backgroundColor):
            koi.color(ts.statusBar.backgroundColor)

        prop("Text", statusBar, textColor):
          koi.color(ts.statusBar.textColor)

      group:
        prop("Command Background", statusBar, commandBgColor):
          koi.color(ts.statusBar.commandBgColor)

        prop("Command", statusBar, commandColor):
          koi.color(ts.statusBar.commandColor)

        prop("Coordinates", statusBar, coordsColor):
          koi.color(ts.statusBar.coordsColor)


    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      prop("Color", aboutButton, color):
        koi.color(ts.aboutButton.color)

      prop("Hover", aboutButton, colorHover):
        koi.color(ts.aboutButton.colorHover)

      prop("Down", aboutButton, colorActive):
        koi.color(ts.aboutButton.colorActive)


    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        koi.label("Logo")
        koi.color(ts.splashImage.logoColor)
        if ts.splashImage.logoColor != te.prevState.splashImage.logoColor:
          a.splash.updateLogoImage = true

        koi.label("Outline")
        koi.color(ts.splashImage.outlineColor)
        if ts.splashImage.outlineColor != te.prevState.splashImage.outlineColor:
          a.splash.updateOutlineImage = true

        prop("Shadow Alpha", splashImage, shadowAlpha):
          koi.horizSlider(startVal=AlphaLimits.min, endVal=AlphaLimits.max,
                          ts.splashImage.shadowAlpha,
                          style=ThemeEditorSliderStyle)

        if ts.splashImage.shadowAlpha != te.prevState.splashImage.shadowAlpha:
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      group:
        prop("Background", level, backgroundColor):
          koi.color(ts.level.backgroundColor)

        prop("Foreground", level, drawColor):
          koi.color(ts.level.drawColor)

        prop("Foreground Light", level, lightDrawColor):
          koi.color(ts.level.lightDrawColor)

        prop("Line Width", level, lineWidth):
          koi.dropDown(LineWidth, ts.level.lineWidth)

      group:
        prop("Coordinates", level, coordsColor):
          koi.color(ts.level.coordsColor)

        prop("Coordinates Highlight", level, coordsHighlightColor):
          koi.color(ts.level.coordsHighlightColor)

        prop("Cursor", level, cursorColor):
          koi.color(ts.level.cursorColor)

        prop("Cursor Guides", level, cursorGuideColor):
          koi.color(ts.level.cursorGuideColor)

      group:
        prop("Selection", level, selectionColor):
          koi.color(ts.level.selectionColor)

        prop("Paste Preview", level, pastePreviewColor):
          koi.color(ts.level.pastePreviewColor)

      group:
        prop("Link Marker", level, linkMarkerColor):
          koi.color(ts.level.linkMarkerColor)

      group:
        prop("Region Border", level, regionBorderColor):
          koi.color(ts.level.regionBorderColor)

        prop("Region Border Empty", level, regionBorderEmptyColor):
          koi.color(ts.level.regionBorderEmptyColor)


    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      prop("Background Hatch?", level, bgHatch):
        koi.checkBox(ts.level.bgHatch)

      prop("Hatch", level, bgHatchColor):
        koi.color(ts.level.bgHatchColor)

      prop("Hatch Stroke Width", level, bgHatchStrokeWidth):
        koi.horizSlider(startVal=HatchStrokeWidthLimits.min,
                        endVal=HatchStrokeWidthLimits.max,
                        ts.level.bgHatchStrokeWidth,
                        style=ThemeEditorSliderStyle)

      prop("Hatch Spacing", level, bgHatchSpacingFactor):
        koi.horizSlider(startVal=HatchSpacingLimits.min,
                        endVal=HatchSpacingLimits.max,
                        ts.level.bgHatchSpacingFactor,
                        style=ThemeEditorSliderStyle)


    if koi.subSectionHeader("Grid", te.sectionOutline):
      prop("Background Grid Style", level, gridStyleBackground):
        koi.dropDown(GridStyle, ts.level.gridStyleBackground)

      prop("Background Grid", level, gridColorBackground):
        koi.color(ts.level.gridColorBackground)

      prop("Floor Grid Style", level, gridStyleFloor):
        koi.dropDown(GridStyle, ts.level.gridStyleFloor)

      prop("Floor grid", level, gridColorFloor):
        koi.color(ts.level.gridColorFloor)


    if koi.subSectionHeader("Outline", te.sectionOutline):
      prop("Style", level, outlineStyle):
        koi.dropDown(OutlineStyle, ts.level.outlineStyle)

      prop("Fill Style", level, outlineFillStyle):
        koi.dropDown(OutlineFillStyle, ts.level.outlineFillStyle)

      prop("Outline", level, outlineColor):
        koi.color(ts.level.outlineColor)

      prop("Outline Width", level, outlineWidthFactor):
        koi.horizSlider(startVal=LevelOutlineWidthLimits.min,
                        endVal=LevelOutlineWidthLimits.max,
                        ts.level.outlineWidthFactor,
                        style=ThemeEditorSliderStyle)

      prop("Overscan", level, outlineOverscan):
        koi.checkBox(ts.level.outlineOverscan)


    if koi.subSectionHeader("Shadow", te.sectionShadow):
      group:
        prop("Inner Shadow", level, innerShadowColor):
          koi.color(ts.level.innerShadowColor)

        prop("Inner Shadow Width", level, innerShadowWidthFactor):
          koi.horizSlider(startVal=LevelShadowWidthLimits.min,
                          endVal=LevelShadowWidthLimits.max,
                          ts.level.innerShadowWidthFactor,
                          style=ThemeEditorSliderStyle)

      group:
        prop("Outer Shadow", level, outerShadowColor):
          koi.color(ts.level.outerShadowColor)

        prop("Outer Shadow Width", level, outerShadowWidthFactor):
          koi.horizSlider(startVal=LevelShadowWidthLimits.min,
                          endVal=LevelShadowWidthLimits.max,
                          ts.level.outerShadowWidthFactor,
                          style=ThemeEditorSliderStyle)


    if koi.subSectionHeader("Floor Colors", te.sectionFloorColors):
      prop("Floor 1", level, floorColor, 0):
        koi.color(ts.level.floorColor[0])

      prop("Floor 2", level, floorColor, 1):
        koi.color(ts.level.floorColor[1])

      prop("Floor 3", level, floorColor, 2):
        koi.color(ts.level.floorColor[2])

      prop("Floor 4", level, floorColor, 3):
        koi.color(ts.level.floorColor[3])

      prop("Floor 5", level, floorColor, 4):
        koi.color(ts.level.floorColor[4])

      prop("Floor 6", level, floorColor, 5):
        koi.color(ts.level.floorColor[5])

      prop("Floor 7", level, floorColor, 6):
        koi.color(ts.level.floorColor[6])

      prop("Floor 8", level, floorColor, 7):
        koi.color(ts.level.floorColor[7])

      prop("Floor 9", level, floorColor, 8):
        koi.color(ts.level.floorColor[8])


    if koi.subSectionHeader("Notes", te.sectionNotes):
      group:
        prop("Marker", level, noteMarkerColor):
          koi.color(ts.level.noteMarkerColor)

        prop("Comment", level, noteCommentColor):
          koi.color(ts.level.noteCommentColor)

      group:
        prop("Index Background 1", level, noteIndexBgColor, 0):
          koi.color(ts.level.noteIndexBgColor[0])

        prop("Index Background 2", level, noteIndexBgColor, 1):
          koi.color(ts.level.noteIndexBgColor[1])

        prop("Index Background 3", level, noteIndexBgColor, 2):
          koi.color(ts.level.noteIndexBgColor[2])

        prop("Index Background 4", level, noteIndexBgColor, 3):
          koi.color(ts.level.noteIndexBgColor[3])

        prop("Index", level, noteIndexColor):
          koi.color(ts.level.noteIndexColor)

      group:
        prop("Tooltip Background", level, noteTooltipBgColor):
          koi.color(ts.level.noteTooltipBgColor)

        prop("Tooltip", level, noteTooltipTextColor):
          koi.color(ts.level.noteTooltipTextColor)


    if koi.subSectionHeader("Level Drop Down", te.sectionLeveldropDown):
      group:
        prop("Button", leveldropDown, buttonColor):
          koi.color(ts.leveldropDown.buttonColor)

        prop("Button Hover", leveldropDown, buttonColorHover):
          koi.color(ts.leveldropDown.buttonColorHover)

        prop("Button Label", leveldropDown, textColor):
          koi.color(ts.leveldropDown.textColor)

      group:
        prop("Item List Background", leveldropDown, itemListColor):
          koi.color(ts.leveldropDown.itemListColor)

        prop("Item", leveldropDown, itemColor):
          koi.color(ts.leveldropDown.itemColor)

        prop("Item Hover", leveldropDown, itemColorHover):
          koi.color(ts.leveldropDown.itemColorHover)


  # }}}
  # {{{ Panes section
  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Notes Pane", te.sectionNotesPane):
      prop("Text", notesPane, textColor):
        koi.color(ts.notesPane.textColor)

      prop("Index Background 1", notesPane, indexBgColor, 0):
        koi.color(ts.notesPane.indexBgColor[0])

      prop("Index Background 2", notesPane, indexBgColor, 1):
        koi.color(ts.notesPane.indexBgColor[1])

      prop("Index Background 3", notesPane, indexBgColor, 2):
        koi.color(ts.notesPane.indexBgColor[2])

      prop("Index Background 4", notesPane, indexBgColor, 3):
        koi.color(ts.notesPane.indexBgColor[3])

      prop("Index", notesPane, indexColor):
        koi.color(ts.notesPane.indexColor)

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      prop("Button ", toolbarPane, buttonBgColor):
        koi.color(ts.toolbarPane.buttonBgColor)

      prop("Button Hover", toolbarPane, buttonBgColorHover):
        koi.color(ts.toolbarPane.buttonBgColorHover)

  # }}}

  koi.endScrollView()

  te.prevState = ts.deepCopy()

# }}}
# {{{ renderThemeEditorPane()

var g_themeEditorPropsFocusCaptured: bool

proc renderThemeEditorPane(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let topSectionHeight = 130
  let propsHeight = h - topSectionHeight

  # Background
  vg.beginPath()
  vg.rect(x, y, w, h)
  vg.fillColor(gray(0.3))
  vg.fill()

  # Left separator line
  vg.beginPath()
  vg.moveTo(x+0.5, y)
  vg.lineTo(x+0.5, y+h)
  vg.strokeColor(gray(0.1))
  vg.stroke()

  let
    bw = 66.0
    bp = 7.0
    wh = 22.0

  var cx = x
  var cy = y

  # Theme pane title
  const TitleHeight = 34

  vg.beginPath()
  vg.rect(x+1, y, w, h=TitleHeight)
  vg.fillColor(gray(0.25))
  vg.fill()

  let titleStyle = getDefaultLabelStyle()
  titleStyle.align = haCenter

  cy += 6.0
  koi.label(cx, cy, w, wh, fmt"T  H  E  M  E       E  D  I  T  O  R",
            style=titleStyle)

  # Theme name & action buttons
  vg.beginPath()
  vg.rect(x+1, y+TitleHeight, w, h=96)
  vg.fillColor(gray(0.36))
  vg.fill()

  cx = x+15
  cy += 45.0
  koi.label(cx, cy, w, wh, fmt"Theme")

  cx += 60.0
  koi.textField(
    cx, cy, w=225.0, wh,
    a.theme.themeNames[a.theme.currThemeIndex],
    disabled=true
  )

  cx = x+15
  cy += 40.0

  let buttonsDisabled = koi.isDialogOpen()

  if koi.button(cx, cy, w=bw, h=wh, "New", disabled=buttonsDisabled):
    discard

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    saveTheme(a.theme.style, themePath(a.theme.currThemeIndex, a))
    discard

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Props", disabled=buttonsDisabled):
    discard

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete", disabled=buttonsDisabled):
    discard

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(g_themeEditorPropsFocusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  g_themeEditorPropsFocusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  # TODO ultimately we'll do most of switchTheme here (extract etc)
  # but at the end of the frame and lazily somehow (only if something has
  # changed), because sometimes we need to precalc stuff when the style
  # changes
  updateWidgetStyles(a)

  a.theme.reinitDrawLevelParams = true

  a.win.setStyle(a.theme.style.window)

# }}}

# }}}

# {{{ showSplash()
proc showSplash(a) =
  alias(s, g_app.splash)

  let (_, _, maxWidth, maxHeight) = getPrimaryMonitor().workArea
  let w = (maxWidth * 0.6).int32
  let h = (w/s.logo.width * s.logo.height).int32

  s.win.size = (w, h)
  s.win.pos = ((maxWidth - w) div 2, (maxHeight - h) div 2)
  s.win.show()

# }}}
# {{{ closeSplash()
proc closeSplash(a) =
  alias(s, g_app.splash)

  s.win.destroy()
  s.win = nil

  s.vg.deleteImage(s.logoImage)
  s.vg.deleteImage(s.outlineImage)
  s.vg.deleteImage(s.shadowImage)

  s.logoImage = NoImage
  s.outlineImage = NoImage
  s.shadowImage = NoImage

  nvgDeleteContext(s.vg)
  s.vg = nil

  s.show = false

# }}}

# {{{ handleAutosave()
proc handleAutosave(a) =
  if a.opt.autosave and a.doc.undoManager.isModified:
    let dt = getMonoTime() - a.doc.lastAutosaveTime
    if dt > initDuration(minutes = a.opt.autosaveFreqMins):
      let filename = if a.doc.filename == "":
                       AutosaveDir / addFileExt("untitled", MapFileExt)
                     else: a.doc.filename

      saveMap(filename, autosave=true, a)
      a.doc.lastAutosaveTime = getMonoTime()

# }}}

# {{{ Main render/UI loop

# {{{ renderUI()
proc renderUI(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(dlg, a.dialog)

  let winHeight = koi.winHeight()
  let uiWidth = drawAreaWidth(a)

  # Clear background
  vg.beginPath()
  # TODO shouldn't have to calculate visible window area manually
  vg.rect(0, TitleBarHeight, uiWidth, winHeight - TitleBarHeight)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.style.general.backgroundColor)

  vg.fill()

  # About button
  if button(x = uiWidth - 55, y = 45, w = 20, h = DlgItemHeight, IconQuestion,
            style = ui.aboutButtonStyle):
    # TODO
    discard

  if not mapHasLevels(a):
    drawEmptyMap(a)
  else:
    let levelItems = a.doc.map.sortedLevelNames
    var sortedLevelIdx = currSortedLevelIdx(a)

    vg.fontSize(a.theme.levelDropDownStyle.label.fontSize)

    let levelDropDownWidth = round(
      vg.textWidth(levelItems[sortedLevelIdx]) +
      a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
    )

    koi.dropDown(
      x = round((uiWidth - levelDropDownWidth) * 0.5),
      y = 45.0,
      w = levelDropDownWidth,
      h = 24.0,   # TODO calc y
      levelItems,
      sortedLevelIdx,
      tooltip = "",
      disabled = not (ui.editMode in {emNormal, emSetCellLink}),
      style = a.theme.levelDropDownStyle
    )
    ui.cursor.level = a.doc.map.sortedLevelIdxToLevelIdx[sortedLevelIdx]

    renderLevel(a)

    if a.opt.showNotesPane:
      drawNotesPane(
        x = NotesPaneLeftPad,
        y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
        w = uiWidth - NotesPaneLeftPad - NotesPaneRightPad,
        h = NotesPaneHeight,
        a
      )

    if a.opt.showToolsPane:
      renderToolsPane(
        x = uiWidth - ToolsPaneWidth,
        y = ToolsPaneTopPad,
        w = ToolsPaneWidth,
        h = winHeight - StatusBarHeight - ToolsPaneBottomPad,
        a
      )

    drawModeAndOptionIndicators(a)

  # Status bar
  let statusBarY = winHeight - StatusBarHeight
  drawStatusBar(statusBarY, uiWidth.float, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.opt.showThemePane:
    let
      x = uiWidth
      y = TitleBarHeight
      w = ThemePaneWidth
      h = drawAreaHeight(a)

    renderThemeEditorPane(x, y, w, h, a)

  # Dialogs
  if dlg.preferencesDialog.isOpen:
    preferencesDialog(dlg.preferencesDialog, a)

  elif dlg.saveDiscardDialog.isOpen:
    saveDiscardDialog(dlg.saveDiscardDialog, a)

  elif dlg.newMapDialog.isOpen:
    newMapDialog(dlg.newMapDialog, a)

  elif dlg.editMapPropsDialog.isOpen:
    editMapPropsDialog(dlg.editMapPropsDialog, a)

  elif dlg.newLevelDialog.isOpen:
    newLevelDialog(dlg.newLevelDialog, a)

  elif dlg.deleteLevelDialog.isOpen:
    deleteLevelDialog(dlg.deleteLevelDialog, a)

  elif dlg.editLevelPropsDialog.isOpen:
    editLevelPropsDialog(dlg.editLevelPropsDialog, a)

  elif dlg.editNoteDialog.isOpen:
    editNoteDialog(dlg.editNoteDialog, a)

  elif dlg.editLabelDialog.isOpen:
    editLabelDialog(dlg.editLabelDialog, a)

  elif dlg.resizeLevelDialog.isOpen:
    resizeLevelDialog(dlg.resizeLevelDialog, a)

# }}}
# {{{ renderFramePre()
proc renderFramePre(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      switchTheme(themeIndex, a)
      a.theme.themeReloaded = themeIndex == a.theme.currThemeIndex

    except CatchableError as e:
      logError(e)
      let name = a.theme.themeNames[themeIndex]
      setStatusMessage(IconWarning, fmt"Cannot load theme '{name}': {e.msg}", a)
      a.theme.nextThemeIndex = Natural.none

    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message


  if a.theme.nextThemeIndex.isSome:
    loadPendingTheme(a.theme.nextThemeIndex.get, a)

  a.win.title = a.doc.map.name
  a.win.modified = a.doc.undoManager.isModified

  if a.theme.reinitDrawLevelParams:
    a.theme.reinitDrawLevelParams = false
    a.ui.drawLevelParams.initDrawLevelParams(a.doc.levelStyle, a.vg,
                                             koi.getPxRatio())

# }}}
# {{{ renderFrame()
proc renderFrame(a) =

  proc displayThemeLoadedMessage(a) =
    let themeName = a.theme.themeNames[a.theme.currThemeIndex]
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
    else:
      setStatusMessage(fmt"Switched to '{themeName}' theme", a)

  if a.theme.nextThemeIndex.isSome:
    displayThemeLoadedMessage(a)
    a.theme.nextThemeIndex = Natural.none

  proc handleWindowClose(a) =
    proc saveConfigAndExit(a) =
      saveConfig(a)
      a.shouldClose = true

    when defined(NO_QUIT_DIALOG):
      saveConfigAndExit(a)
    else:
      if not koi.isDialogOpen():
        if a.doc.undoManager.isModified:
          a.dialog.saveDiscardDialog.isOpen = true
          a.dialog.saveDiscardDialog.action = proc (a) = saveConfigAndExit(a)
        else:
          saveConfigAndExit(a)


  # XXX HACK: If the theme pane is shown, widgets are handled first, then then
  # the global shortcuts, so widget-specific shorcuts can take precedence
  var uiRendered = false
  if a.opt.showThemePane:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if mapHasLevels(a): handleGlobalKeyEvents(a)
    else:               handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.opt.showThemePane and a.win.glfwWin.focused:
      glfw.makeContextCurrent(g_app.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(g_app.win.glfwWin)
      g_app.win.focus()

  if not a.opt.showThemePane or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash(a) =
  alias(s, a.splash)
  alias(vg, s.vg)
  alias(ts, a.theme.style)

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth / winWidth

  glViewport(0, 0, fbWidth, fbHeight)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)

  proc colorImage(d: var ImageData, color: Color) =
    for i in 0..<(d.width * d.height):
      d.data[i*4]   = (color.r * 255).byte
      d.data[i*4+1] = (color.g * 255).byte
      d.data[i*4+2] = (color.b * 255).byte

  template createImage(d: var ImageData): Image =
    vg.createImageRGBA(
      d.width, d.height,
      data = toOpenArray(d.data, 0, d.size()-1)
    )

  template createPattern(img: var Image, alpha: float = 1.0): Paint =
    let scale = fbWidth / s.logo.width / pxRatio

    let (w, h) = vg.imageSize(img)
    vg.imagePattern(
      ox=0, oy=0, ex=w*scale, ey=h*scale, angle=0, img, alpha
    )

  if s.logoImage == NoImage or s.updateLogoImage:
    colorImage(s.logo, ts.splashImage.logoColor)
    if s.logoImage == NoImage:
      s.logoImage = createImage(s.logo)
    else:
      vg.updateImage(s.logoImage, cast[ptr byte](s.logo.data))
    s.updateLogoImage = false

  if s.outlineImage == NoImage or s.updateOutlineImage:
    colorImage(s.outline, ts.splashImage.outlineColor)
    if s.outlineImage == NoImage:
      s.outlineImage = createImage(s.outline)
    else:
      vg.updateImage(s.outlineImage, cast[ptr byte](s.outline.data))
    s.updateOutlineImage = false

  if s.shadowImage == NoImage or s.updateShadowImage:
    colorImage(s.shadow, black())
    if s.shadowImage == NoImage:
      s.shadowImage = createImage(s.shadow)
    else:
      vg.updateImage(s.shadowImage, cast[ptr byte](s.shadow.data))
    s.updateShadowImage = false


  s.logoPaint = createPattern(s.logoImage)
  s.outlinePaint = createPattern(s.outlineImage)
  s.shadowPaint = createPattern(s.shadowImage,
                                alpha=ts.splashImage.shadowAlpha)

  vg.beginPath()
  vg.rect(0, 0, winWidth.float, winHeight.float)

  vg.fillPaint(s.shadowPaint)
  vg.fill()

  vg.fillPaint(s.outlinePaint)
  vg.fill()

  vg.fillPaint(s.logoPaint)
  vg.fill()

  vg.endFrame()


  if not a.opt.showThemePane and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.opt.showThemePane:
      not a.splash.show
    else:
      let autoClose =
        if not a.opt.showThemePane and a.opt.autoCloseSplash:
          let dt = getMonoTime() - a.splash.t0
          koi.setFramesLeft()
          dt > initDuration(seconds = a.opt.splashTimeoutSecs)
        else: false

      w.isKeyDown(keyEscape) or
      w.isKeyDown(keySpace) or
      w.isKeyDown(keyEnter) or
      w.isKeyDown(keyKpEnter) or
      w.mouseButtonDown(mbLeft) or
      w.mouseButtonDown(mbRight) or
      w.mouseButtonDown(mbMiddle) or
      autoClose

  if shouldCloseSplash(a):
    closeSplash(a)
    a.win.focus()

# }}}

# }}}
# {{{ Init & cleanup

# {{{ loadAndSetIcon()
proc loadAndSetIcon(a) =
  var icons: array[5, wrapper.IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width = img.width.int32
    icons[idx].height = img.height.int32
    icons[idx].pixels = cast[ptr cuchar](img.data)

  var icon32 = loadImage(DataDir / "icon32.png")
  var icon48 = loadImage(DataDir / "icon48.png")
  var icon64 = loadImage(DataDir / "icon64.png")
  var icon128 = loadImage(DataDir / "icon128.png")
  var icon256 = loadImage(DataDir / "icon256.png")

  add(0, icon32)
  add(1, icon48)
  add(2, icon64)
  add(3, icon128)
  add(4, icon256)

  a.win.glfwWin.icons = icons

# }}}
# {{{ loadFonts()
proc loadFonts(vg: NVGContext) =
  discard vg.createFont("sans", DataDir / "Roboto-Regular.ttf")
  let boldFont = vg.createFont("sans-bold", DataDir / "Roboto-Bold.ttf")
  let blackFont = vg.createFont("sans-black", DataDir / "Roboto-Black.ttf")
  let iconFont = vg.createFont("icon", DataDir / "GridmongerIcons.ttf")

  discard addFallbackFont(vg, boldFont, iconFont)
  discard addFallbackFont(vg, blackFont, iconFont)

# }}}
# {{{ loadSplashImages()
proc loadSplashImages(a) =
  alias(s, g_app.splash)

  s.logo = loadImage(DataDir / "logo.png")
  s.outline = loadImage(DataDir / "logo-outline.png")
  s.shadow = loadImage(DataDir / "logo-shadow.png")

  proc createAlpha(d: var ImageData) =
    for i in 0..<(d.width * d.height):
      # copy the R component to the alpha channel
      d.data[i*4+3] = d.data[i*4]

  createAlpha(s.logo)
  createAlpha(s.outline)
  createAlpha(s.shadow)

# }}}
# {{{ setDefaultWidgetStyles()
proc setDefaultWidgetStyles(a) =
  var s = koi.getDefaultCheckBoxStyle()

  s.icon.fontSize = 12.0
  s.iconActive    = IconCheck
  s.iconInactive  = NoIcon

  koi.setDefaultCheckboxStyle(s)

# }}}
# {{{ initGfx()
proc initGfx(a): (CSDWindow, NVGContext) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    logging.error("Error initialising OpenGL")
    quit(QuitFailure)

  let version = cast[cstring](glGetString(GL_VERSION))
  let vendor = cast[cstring](glGetString(GL_VENDOR))
  let renderer = cast[cstring](glGetString(GL_RENDERER))

  let msg = fmt"""
GPU info
  Vendor:   {vendor}
  Renderer: {renderer}
  Version:  {version}"""

  info(msg)

  nvgInit(getProcAddress)
  let vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

  koi.init(vg, getProcAddress)

  result = (win, vg)

# }}}
# {{{ initApp()
proc initApp(win: CSDWindow, vg: NVGContext) =
  alias(a, g_app)

  createDir(ConfigDir)
  createDir(AutosaveDir)
  createDir(UserThemesDir)

  let cfg = loadAppConfig(ConfigFile)

  loadFonts(vg)

  a = new AppContext
  a.win = win
  a.vg = vg

  loadAndSetIcon(a)

  setDefaultWidgetStyles(a)

  a.doc.undoManager = newUndoManager[Map, UndoStateData]()

  a.ui.drawLevelParams = newDrawLevelParams()

  searchThemes(a)
  var themeIndex = findThemeIndex(cfg.themeName, a)
  if themeIndex == -1: themeIndex = 0
  switchTheme(themeIndex, a)

  a.opt.scrollMargin = 3
  a.opt.showSplash = cfg.showSplash
  a.opt.autoCloseSplash = cfg.autoCloseSplash
  a.opt.splashTimeoutSecs = cfg.splashTimeoutSecs
  a.opt.loadLastMap = cfg.loadLastMap
  a.opt.disableVSync = cfg.disableVSync
  a.opt.autosave = cfg.autosave
  a.opt.autosaveFreqMins = cfg.autosaveFreqMins

  a.opt.showNotesPane = cfg.showNotesPane
  a.opt.showToolsPane = cfg.showToolsPane
  a.opt.drawTrail = cfg.drawTrail
  a.opt.walkMode = cfg.walkMode
  a.opt.wasdMode = cfg.wasdMode

  a.ui.drawLevelParams.drawCellCoords = cfg.showCellCoords
  a.ui.drawLevelParams.setZoomLevel(a.doc.levelStyle,
                                    clamp(cfg.zoomLevel, MinZoomLevel, MaxZoomLevel))

  if cfg.loadLastMap and cfg.lastMapFileName != "":
    if not loadMap(cfg.lastMapFileName, a):
      a.doc.map = newMap("Untitled Map")
  else:
    a.doc.map = newMap("Untitled Map")
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  # TODO check values?
  # TODO timestamp check to determine whether to read the DISP info from the
  # conf or from the file
  a.ui.drawLevelParams.viewStartRow = cfg.viewStartRow
  a.ui.drawLevelParams.viewStartCol = cfg.viewStartCol

  if cfg.currLevel > a.doc.map.levels.high:
    a.ui.cursor.level = 0
    a.ui.cursor.row = 0
    a.ui.cursor.col = 0
  else:
    a.ui.cursor.level = cfg.currLevel
    a.ui.cursor.row = cfg.cursorRow
    a.ui.cursor.col = cfg.cursorCol

  updateLastCursorViewCoords(a)

  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  a.splash.show = a.opt.showSplash
  a.splash.t0 = getMonoTime()
  setSwapInterval(a)

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePre(a)
  a.win.renderFrameCb = proc (win: CSDWindow) = renderFrame(a)

  # Set window size & position
  let (_, _, maxWidth, maxHeight) = getPrimaryMonitor().workArea

  let width = cfg.width.clamp(WindowMinWidth, maxWidth)
  let height = cfg.height.clamp(WindowMinHeight, maxHeight)

  var xpos = cfg.xpos
  if xpos < 0: xpos = (maxWidth - width) div 2

  var ypos = cfg.ypos
  if ypos < 0: ypos = (maxHeight - height) div 2

  a.win.size = (width, height)
  a.win.pos = (xpos, ypos)

  if cfg.maximized:
    a.win.maximize()

  a.win.show()

  info("App init completed")

# }}}
# {{{ createSplashWindow()
proc createSplashWindow(mousePassthru: bool = false; a) =
  alias(s, g_app.splash)

  var cfg = DefaultOpenglWindowConfig
  cfg.visible = false
  cfg.resizable = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.nMultiSamples = 4
  cfg.transparentFramebuffer = true
  cfg.decorated = false
  cfg.floating = true

  when defined(windows):
    cfg.hideFromTaskbar = true
    cfg.mousePassthru = mousePassthru
  else:
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  s.win = newWindow(cfg)
  s.vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

# }}}
# {{{ cleanup()
proc cleanup(a) =
  info("Exiting app...")

  koi.deinit()

  nvgDeleteContext(g_app.vg)
  if a.splash.vg != nil:
    nvgDeleteContext(g_app.splash.vg)

  a.win.glfwWin.destroy()
  if a.splash.win != nil:
    a.splash.win.destroy()

  glfw.terminate()

  info("Cleanup successful, bye!")

# }}}

# }}}

# {{{ main()
proc main() =
  alias(a, g_app)

  discard tryRemoveFile(LogFile)
  var fileLog = newFileLogger(LogFile, fmtStr="[$levelname] $date $time - ", bufSize=0)
  addHandler(fileLog)

  # TODO
#  info(fmt"Gridmonger v{AppVersion} ({BuildGitHash}), compiled on {BuildOS} at {BuildDateTime}")
  info(fmt"Gridmonger v{AppVersion} ({BuildGitHash})")
  info(fmt"HomeDir = {HomeDir}")
  info(fmt"ConfigFile = {ConfigFile}")
  info(fmt"UserThemesDir = {UserThemesDir}")

  try:
    let (win, vg) = initGfx(a)
    initApp(win, vg)

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)
      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthru = a.opt.showThemePane, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.opt.showThemePane:
          a.win.focus()

      if a.splash.win != nil:
        glfw.makeContextCurrent(a.splash.win)
        renderFrameSplash(a)
        glFlush()

      # Swap buffers
      glfw.swapBuffers(a.win.glfwWin)

      if a.splash.win != nil:
        glfw.swapBuffers(a.splash.win)

      handleAutosave(a)

      # Poll/wait for events
      if koi.shouldRenderNextFrame():
        glfw.pollEvents()
      else:
        glfw.waitEventsTimeout(15)

    cleanup(a)

  except Exception as e:
    fatal("A fatal error has occured, the application will now exit: \n" &
          e.msg & "\n\n" & getStackTrace(e))

    quit(QuitFailure)

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
