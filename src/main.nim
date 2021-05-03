import algorithm
import browsers
import lenientops
import logging
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
import fieldlimits
import icons
import level
import links
import map
import persistence
import rect
import selection
import theme
import unicode
import utils


when defined(windows):
  {.link: "extras/appicons/windows/gridmonger.res".}

const
  BuildGitHash = strutils.strip(staticExec("git rev-parse --short HEAD"))
  ThemeExt = "cfg"

# {{{ logError()
proc logError(e: ref Exception, msgPrefix: string = "") =
  var msg = "Error message: " & e.msg & "\n\nStack trace:\n" & getStackTrace(e)
  if msgPrefix != "":
    msg = msgPrefix & "\n" & msg

  logging.error(msg)

# }}}

# {{{ Constants
const
  CursorJump   = 5
  ScrollMargin = 3

  StatusBarHeight         = 26.0

  LevelTopPad_Regions     = 28.0

  LevelTopPad_Coords      = 85.0
  LevelRightPad_Coords    = 50.0
  LevelBottomPad_Coords   = 40.0
  LevelLeftPad_Coords     = 50.0


  LevelTopPad_NoCoords    = 65.0
  LevelRightPad_NoCoords  = 28.0
  LevelBottomPad_NoCoords = 10.0
  LevelLeftPad_NoCoords   = 28.0

  NotesPaneHeight         = 62.0
  NotesPaneTopPad         = 10.0
  NotesPaneRightPad       = 50.0
  NotesPaneBottomPad      = 10.0
  NotesPaneLeftPad        = 20.0

  ToolsPaneWidthNarrow    = 60.0
  ToolsPaneWidthWide      = 90.0
  ToolsPaneTopPad         = 91.0
  ToolsPaneBottomPad      = 30.0
  ToolsPaneYBreakpoint1   = 735.0
  ToolsPaneYBreakpoint2   = 885.0

  ThemePaneWidth          = 316.0

const
  MapFileExt = "grm"
  CrashAutosaveFilename = addFileExt("Crash Autosave", MapFileExt)
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

  SpecialWallTooltips = SpecialWalls.mapIt(($it).title())

  FloorsKey1 = @[
    fDoor,
    fLockedDoor,
    fArchway
  ]

  FloorsKey2 = @[
    fSecretDoor,
    fSecretDoorBlock,
    fOneWayDoor1,
    fOneWayDoor2
  ]

  FloorsKey3 = @[
    fPressurePlate,
    fHiddenPressurePlate
  ]

  FloorsKey4 = @[
    fClosedPit,
    fOpenPit,
    fHiddenPit,
    fCeilingPit
  ]

  FloorsKey5 = @[
    fTeleportSource,
    fTeleportDestination,
    fSpinner,
    fInvisibleBarrier
  ]

  FloorsKey6 = @[
    fStairsDown,
    fStairsUp,
    fEntranceDoor,
    fExitDoor
  ]

# }}}
# {{{ AppContext
type
  AppContext = ref object
    win:         CSDWindow
    vg:          NVGContext

    prefs:       Preferences
    path:        Paths

    doc:         Document
    opts:        Options
    ui:          UIState
    dialog:      Dialogs

    theme:       Theme
    themeEditor: ThemeEditor
    splash:      Splash
    aboutLogo:   AboutLogo

    shouldClose: bool


  Paths = object
    dataDir:            string
    userDataDir:        string
    configDir:          string
    manualDir:          string
    autosaveDir:        string

    themesDir:          string
    themeImagesDir:     string
    userThemesDir:      string
    userThemeImagesDir: string

    configFile:         string
    logFile:            string


  Document = object
    filename:          string
    map:               Map
    levelStyle:        LevelStyle
    undoManager:       UndoManager[Map, UndoStateData]
    lastAutosaveTime:  MonoTime

  Options = object
    showNotesPane:     bool
    showToolsPane:     bool
    showThemePane:     bool

    drawTrail:         bool
    walkMode:          bool
    wasdMode:          bool


  UIState = object
    cursor:            Location
    lastCursor:        Location
    cursorOrient:      CardinalDir
    editMode:          EditMode

    lastCursorViewX:   float
    lastCursorViewY:   float

    selection:         Option[Selection]
    selRect:           Option[SelectionRect]
    copyBuf:           Option[SelectionBuffer]
    nudgeBuf:          Option[SelectionBuffer]
    cutToBuffer:       bool
    moveUndoLocation:  Location

    statusIcon:        string
    statusMessage:     string
    statusCommands:    seq[string]

    currSpecialWall:   Natural
    currFloorColor:    byte

    manualNoteTooltipState: ManualNoteTooltipState

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


  ManualNoteTooltipState = object
    show:     bool
    location: Location
    mx:       float
    my:       float


  EditMode = enum
    emNormal,
    emExcavate,
    emDrawWall,
    emDrawWallSpecial,
    emEraseCell,
    emEraseTrail,
    emDrawClearFloor,
    emColorFloor,
    emSelect,
    emSelectRect
    emPastePreview,
    emMovePreview,
    emNudgePreview,
    emSetCellLink

  Theme = object
    style:                  ThemeStyle

    themeNames:             seq[ThemeName]
    currThemeIndex:         Natural
    nextThemeIndex:         Option[Natural]
    themeReloaded:          bool
    reinitDrawLevelParams:  bool

    buttonStyle:            ButtonStyle
    checkBoxStyle:          CheckboxStyle
    dialogStyle:            koi.DialogStyle
    labelStyle:             LabelStyle
    radioButtonStyle:       RadioButtonsStyle
    textAreaStyle:          TextAreaStyle
    textFieldStyle:         koi.TextFieldStyle

    aboutDialogStyle:       koi.DialogStyle
    aboutButtonStyle:       ButtonStyle

    iconRadioButtonsStyle:  RadioButtonsStyle
    warningLabelStyle:      LabelStyle

    levelDropDownStyle:     DropDownStyle
    noteTextAreaStyle:      TextAreaStyle


  ThemeName = object
    name:      string
    userTheme: bool
    override:  bool


  Dialogs = object
    aboutDialog:            AboutDialogParams
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

    editRegionPropsDialog:  EditRegionPropsParams


  AboutDialogParams = object
    isOpen:       bool
    logoPaint:    Paint
    outlinePaint: Paint
    shadowPaint:  Paint


  PreferencesDialogParams = object
    isOpen:             bool
    activeTab:          Natural
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
    activeTab:    Natural
    activateFirstTextField: bool

    name:         string
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  EditMapPropsDialogParams = object
    isOpen:       bool
    activeTab:    Natural
    activateFirstTextField: bool

    name:         string
    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  DeleteLevelDialogParams = object
    isOpen:       bool


  NewLevelDialogParams = object
    isOpen:            bool
    activeTab:         Natural
    activateFirstTextField: bool

    # General tab
    locationName:      string
    levelName:         string
    elevation:         string
    rows:              string
    cols:              string

    # Coordinates tab
    overrideCoordOpts: bool
    origin:            Natural
    rowStyle:          Natural
    columnStyle:       Natural
    rowStart:          string
    columnStart:       string

    # Regions tab
    enableRegions:     bool
    colsPerRegion:     string
    rowsPerRegion:     string
    perRegionCoords:   bool

    # Notes tab
    notes:          string


  EditLevelPropsParams = object
    isOpen:            bool
    activeTab:         Natural
    activateFirstTextField: bool

    # General tab
    locationName:      string
    levelName:         string
    elevation:         string
    notes:          string

    # Coordinates tab
    overrideCoordOpts: bool
    origin:            Natural
    rowStyle:          Natural
    columnStyle:       Natural
    rowStart:          string
    columnStart:       string

    # Regions tab
    enableRegions:     bool
    colsPerRegion:     string
    rowsPerRegion:     string
    perRegionCoords:   bool


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
    kind:         AnnotationKind
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


  EditRegionPropsParams = object
    isOpen:       bool
    activateFirstTextField: bool

    name:         string


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
    sectionAboutDialog:      bool
    sectionSplashImage:      bool

    sectionLevel:            bool
    sectionLevelGeneral:     bool
    sectionGrid:             bool
    sectionOutline:          bool
    sectionShadow:           bool
    sectionBackgroundHatch:  bool
    sectionFloorColors:      bool
    sectionNotes:            bool
    sectionLabels:           bool

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


  AboutLogo = object
    logo:             ImageData
    logoImage:        Image
    logoPaint:        Paint
    updateLogoImage:  bool


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
# TODO introduce shortcuts for everything
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
  glfw.swapInterval(if a.prefs.disableVSync: 0 else: 1)

# }}}
# {{{ savePreferences()
proc savePreferences(a) =
  alias(opts, a.opts)
  alias(theme, a.theme)

  let dp = a.ui.drawLevelParams

  let (xpos, ypos)    = if a.win.maximized: a.win.oldPos  else: a.win.pos
  let (width, height) = if a.win.maximized: a.win.oldSize else: a.win.size

  let cur = a.ui.cursor

  let cfg = AppConfig(
    prefs: a.prefs,

    app: AppState(
      themeName:      theme.themeNames[theme.currThemeIndex].name,

      zoomLevel:      dp.getZoomLevel(),
      currLevel:      cur.level,
      cursorRow:      cur.row,
      cursorCol:      cur.col,
      viewStartRow:   dp.viewStartRow,
      viewStartCol:   dp.viewStartCol,

      showCellCoords: dp.drawCellCoords,
      showToolsPane:  opts.showToolsPane,
      showNotesPane:  opts.showNotesPane,

      wasdMode:       opts.wasdMode,
      walkMode:       opts.walkMode,
      drawTrail:      opts.drawTrail
    ),
    win: WindowState(
      maximized: a.win.maximized,
      xpos:      xpos,
      ypos:      ypos,
      width:     width,
      height:    height
    ),
    misc: MiscState(
      lastMapFileName: a.doc.filename
    )
  )

  saveAppConfig(cfg, a.path.configFile)

# }}}
# {{{ colorImage()
proc colorImage(d: var ImageData, color: Color) =
  for i in 0..<(d.width * d.height):
    d.data[i*4]   = (color.r * 255).byte
    d.data[i*4+1] = (color.g * 255).byte
    d.data[i*4+2] = (color.b * 255).byte

# }}}
# {{{ createImage()
template createImage(d: var ImageData): Image =
  vg.createImageRGBA(
    d.width, d.height,
    data = toOpenArray(d.data, 0, d.size()-1)
  )

# }}}
# {{{ createPattern()
proc createPattern(vg: NVGContext, img: var Image, alpha: float = 1.0,
                   xoffs: float = 0, yoffs: float = 0,
                   scale: float = 1.0): Paint =

  let (w, h) = vg.imageSize(img)
  vg.imagePattern(
    ox=xoffs, oy=yoffs, ex=w*scale, ey=h*scale, angle=0, img, alpha
  )

# }}}
# {{{ loadImage()
proc loadImage(path: string; a): Option[Paint] =
  alias(vg, a.vg)
  try:
    var img = vg.createImage(path, {ifRepeatX, ifRepeatY})
    let paint = vg.createPattern(img, scale=0.5)
    result = paint.some

  except NVGError:
    result = Paint.none

# }}}

# {{{ Helpers/utils

# {{{ viewRow()
func viewRow(row: Natural; a): int =
  row - a.ui.drawLevelParams.viewStartRow

func viewRow(a): int =
  viewRow(a.ui.cursor.row, a)

# }}}
# {{{ viewCol()
func viewCol(col: Natural; a): int =
  col - a.ui.drawLevelParams.viewStartCol

func viewCol(a): int =
  viewCol(a.ui.cursor.col, a)

# }}}
# {{{ mapHasLevels()
func mapHasLevels(a): bool =
  a.doc.map.levels.len > 0

# }}}
# {{{ currSortedLevelIdx()
func currSortedLevelIdx(a): Natural =
  a.doc.map.findSortedLevelIdxByLevelIdx(a.ui.cursor.level)

# }}}
# {{{ currLevel()
func currLevel(a): common.Level =
  a.doc.map.levels[a.ui.cursor.level]

# }}}
# {{{ currRegion()
proc currRegion(a): Option[Region] =
  let l = currLevel(a)
  if l.regionOpts.enabled:
    let rc = a.doc.map.getRegionCoords(a.ui.cursor)
    l.getRegion(rc)
  else:
    Region.none

# }}}
# {{{
func coordOptsForCurrLevel(a): CoordinateOptions =
  a.doc.map.coordOptsForLevel(a.ui.cursor.level)

# }}}
# {{{ setCursor()
proc setCursor(cur: Location; a) =
  a.ui.cursor = cur

  if a.ui.lastCursor.level != a.ui.cursor.level:
    a.opts.drawTrail = false

  if a.opts.drawTrail:
    a.doc.map.setTrail(cur, true)

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
# {{{ setSetLinkDestinationMessage()
proc setSetLinkDestinationMessage(floor: Floor; a) =
  setStatusMessage(IconLink,
                   fmt"Set {linkFloorToString(floor)} destination",
                   @[IconArrowsAll, "select cell",
                   "Enter", "set", "Esc", "cancel"], a)
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
  let dp = a.ui.drawLevelParams

  a.ui.lastCursorViewX = dp.gridSize * viewCol(a)
  a.ui.lastCursorViewY = dp.gridSize * viewRow(a)

# }}}
# {{{ drawAreaWidth()
proc drawAreaWidth(a): float =
  if a.opts.showThemePane: koi.winWidth() - ThemePaneWidth
  else: koi.winWidth()

# }}}
# {{{ drawAreaHeight()
proc drawAreaHeight(a): float =
  koi.winHeight() - TitleBarHeight

# }}}
# {{{ toolsPaneWidth()
proc toolsPaneWidth(): float =
  if koi.winHeight() < ToolsPaneYBreakpoint2: ToolsPaneWidthWide
  else: ToolsPaneWidthNarrow

# }}}
# {{{ updateViewStartAndCursorPosition()
proc updateViewStartAndCursorPosition(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)

  var cur = a.ui.cursor

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

  if l.regionOpts.enabled:
    a.ui.levelTopPad += LevelTopPad_Regions

  dp.startX = ui.levelLeftPad
  dp.startY = TitleBarHeight + ui.levelTopPad

  ui.levelDrawAreaWidth = drawAreaWidth(a) - a.ui.levelLeftPad -
                                             a.ui.levelRightPad

  ui.levelDrawAreaHeight = drawAreaHeight(a) - a.ui.levelTopPad -
                                               a.ui.levelBottomPad -
                                               StatusBarHeight

  if a.opts.showNotesPane:
   ui.levelDrawAreaHeight -= NotesPaneTopPad + NotesPaneHeight +
                             NotesPaneBottomPad

  if a.opts.showToolsPane:
    ui.levelDrawAreaWidth -= toolsPaneWidth()

  dp.viewRows = min(dp.numDisplayableRows(ui.levelDrawAreaHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(ui.levelDrawAreaWidth), l.cols)

  dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow)
  dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol)

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  cur.row = viewEndRow.clamp(dp.viewStartRow, cur.row)
  cur.col = viewEndCol.clamp(dp.viewStartCol, cur.col)

  setCursor(cur, a)
  updateLastCursorViewCoords(a)

# }}}
# {{{ locationAtMouse()
proc locationAtMouse(a): Option[Location] =
  let dp = a.ui.drawLevelParams

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

  var cur = a.ui.cursor
  cur.row = cur.row + viewRow(newViewStartRow, a)
  cur.col = cur.col + viewCol(newViewStartCol, a)

  setCursor(cur, a)

  dp.viewStartRow = newViewStartRow
  dp.viewStartCol = newViewStartCol

# }}}
# {{{ stepCursor()
proc stepCursor(cur: Location, dir: CardinalDir, steps: Natural; a): Location =
  alias(dp, a.ui.drawLevelParams)

  let l = a.doc.map.levels[cur.level]
  let sm = ScrollMargin
  var cur = cur

  case dir:
  of dirE:
    cur.col = min(cur.col + steps, l.cols-1)
    let viewCol = viewCol(cur.col, a)
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol +
                                                        (viewCol - viewColMax))

  of dirS:
    cur.row = min(cur.row + steps, l.rows-1)
    let viewRow = viewRow(cur.row, a)
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow +
                                                        (viewRow - viewRowMax))

  of dirW:
    cur.col = max(cur.col - steps, 0)
    let viewCol = viewCol(cur.col, a)
    if viewCol < sm:
      dp.viewStartCol = max(dp.viewStartCol - (sm - viewCol), 0)

  of dirN:
    cur.row = max(cur.row - steps, 0)
    let viewRow = viewRow(cur.row, a)
    if viewRow < sm:
      dp.viewStartRow = max(dp.viewStartRow - (sm - viewRow), 0)

  result = cur

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, steps: Natural; a) =
  let cur = stepCursor(a.ui.cursor, dir, steps, a)
  setCursor(cur, a)

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
  var cur = a.ui.cursor
  cur.level = loc.level

  let dx = loc.col - cur.col
  let dy = loc.row - cur.row

  cur = if   dx < 0: stepCursor(cur, dirW, -dx, a)
        elif dx > 0: stepCursor(cur, dirE,  dx, a)
        else: cur

  cur = if   dy < 0: stepCursor(cur, dirN, -dy, a)
        elif dy > 0: stepCursor(cur, dirS,  dy, a)
        else: cur

  setCursor(cur, a)

# }}}
# {{{ centerCursorAt()
proc centerCursorAt(loc: Location; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)

  dp.viewStartRow = (loc.row.int - dp.viewRows div 2).clamp(0, l.rows-1)
  dp.viewStartCol = (loc.col.int - dp.viewCols div 2).clamp(0, l.cols-1)

  moveCursorTo(loc, a)

# }}}

# {{{ enterSelectMode()
proc enterSelectMode(a) =
  let l = currLevel(a)

  a.opts.drawTrail = false
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

  let sel = ui.selection.get
  let bbox = sel.boundingBox()

  if bbox.isSome:
    let bbox = bbox.get

    buf = some(SelectionBuffer(
      selection: newSelectionFrom(sel, bbox),
      level: newLevelFrom(currLevel(a), bbox)
    ))

    ui.cutToBuffer = false

  result = bbox

# }}}

# }}}

# {{{ Theme handling

# {{{ updateWidgetStyles()
proc updateWidgetStyles(a) =
  alias(s, a.theme.style)
  alias(ws, s.ui.widget)
  alias(ts, s.ui.textField)
  alias(ds, s.ui.dialog)

  # Button
  a.theme.buttonStyle = koi.getDefaultButtonStyle()

  with a.theme.buttonStyle:
    cornerRadius      = ws.cornerRadius
    fillColor         = ws.backgroundColor
    fillColorHover    = ws.backgroundHoverColor
    fillColorDown     = ws.backgroundActiveColor
    fillColorDisabled = ws.backgroundDisabledColor

    label.color            = ws.foregroundColor
    label.colorHover       = ws.foregroundColor
    label.colorDown        = ws.foregroundActiveColor
    label.colorActive      = ws.foregroundActiveColor
    label.colorActiveHover = ws.foregroundActiveColor
    label.colorDisabled    = ws.foregroundDisabledColor

  # Radio button
  a.theme.radioButtonStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.radioButtonStyle:
    buttonCornerRadius         = ws.cornerRadius
    buttonFillColor            = ws.backgroundColor
    buttonFillColorHover       = ws.backgroundHoverColor
    buttonFillColorDown        = ws.backgroundActiveColor
    buttonFillColorActive      = ws.backgroundActiveColor
    buttonFillColorActiveHover = ws.backgroundActiveColor

    label.color            = ws.foregroundColor
    label.colorHover       = ws.foregroundColor
    label.colorDown        = ws.foregroundActiveColor
    label.colorActive      = ws.foregroundActiveColor
    label.colorActiveHover = ws.foregroundActiveColor

  # Icon radio button
  a.theme.iconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.iconRadioButtonsStyle:
    buttonPadHoriz             = 4.0
    buttonPadVert              = 4.0
    buttonFillColor            = ws.backgroundColor
    buttonFillColorHover       = ws.backgroundHoverColor
    buttonFillColorDown        = ws.backgroundActiveColor
    buttonFillColorActive      = ws.backgroundActiveColor
    buttonFillColorActiveHover = ws.backgroundActiveColor

    label.fontSize         = 18.0
    label.color            = ws.foregroundColor
    label.colorHover       = ws.foregroundColor
    label.colorDown        = ws.foregroundActiveColor
    label.colorActive      = ws.foregroundActiveColor
    label.colorActiveHover = ws.foregroundActiveColor
    label.padHoriz         = 0
    label.padHoriz         = 0

  # Text field
  a.theme.textFieldStyle = koi.getDefaultTextFieldStyle()

  with a.theme.textFieldStyle:
    bgCornerRadius      = ws.cornerRadius
    bgFillColor         = ws.backgroundColor
    bgFillColorHover    = ws.backgroundHoverColor
    bgFillColorActive   = ts.editBackgroundColor
    bgFillColorDisabled = ws.backgroundDisabledColor
    textColor           = ws.foregroundColor
    textColorHover      = ws.foregroundColor
    textColorActive     = ts.editTextColor
    textColorDisabled   = ws.foregroundDisabledColor
    cursorColor         = ts.cursorColor
    selectionColor      = ts.selectionColor

  # Text area
  a.theme.textAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.textAreaStyle:
    bgCornerRadius    = ws.cornerRadius
    bgFillColor       = ws.backgroundColor
    bgFillColorHover  = lerp(ws.backgroundColor, ws.backgroundHoverColor, 0.5)
    bgFillColorActive = ts.editBackgroundColor
    textColor         = ws.foregroundColor
    textColorHover    = ws.foregroundColor
    textColorActive   = ts.editTextColor
    cursorColor       = ts.cursorColor
    selectionColor    = ts.selectionColor

    with scrollBarStyleNormal:
      let c = ts.scrollBarNormalColor
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

    with scrollBarStyleEdit:
      let c = ts.scrollBarEditColor
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Check box
  a.theme.checkBoxStyle = koi.getDefaultCheckBoxStyle()

  with a.theme.checkBoxStyle:
    cornerRadius          = ws.cornerRadius
    fillColor             = ws.backgroundColor
    fillColorHover        = ws.backgroundHoverColor
    fillColorDown         = ws.backgroundActiveColor
    fillColorActive       = ws.backgroundActiveColor
    icon.fontSize         = 12.0
    icon.color            = ws.foregroundColor
    icon.colorHover       = ws.foregroundColor
    icon.colorDown        = ws.foregroundActiveColor
    icon.colorActive      = ws.foregroundActiveColor
    icon.colorActiveHover = ws.foregroundActiveColor
    iconActive            = IconCheck
    iconInactive          = NoIcon

  # Dialog style
  a.theme.dialogStyle = koi.getDefaultDialogStyle()

  with a.theme.dialogStyle:
    cornerRadius      = ds.cornerRadius
    backgroundColor   = ds.backgroundColor
    titleBarBgColor   = ds.titleBackgroundColor
    titleBarTextColor = ds.titleColor

    outerBorderColor  = ds.outerBorderColor
    innerBorderColor  = ds.innerBorderColor
    outerBorderWidth  = ds.outerBorderWidth
    innerBorderWidth  = ds.innerBorderWidth

    with shadow:
      enabled = ds.shadowEnabled
      xOffset = ds.shadowXOffset
      yOffset = ds.shadowYOffset
      feather = ds.shadowFeather
      color   = ds.shadowColor

  a.theme.aboutDialogStyle = a.theme.dialogStyle.deepCopy()
  a.theme.aboutDialogStyle.drawTitleBar = false

  # Label
  a.theme.labelStyle = koi.getDefaultLabelStyle()

  with a.theme.labelStyle:
    fontSize      = 14
    color         = ds.labelColor
    colorDisabled = ds.labelColor.lerp(ds.backgroundColor, 0.7)
    align         = haLeft

  # Warning label
  a.theme.warningLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.warningLabelStyle:
    color     = ds.warningColor
    multiLine = true

  # Level dropDown
  alias(lds, s.level.levelDropDown)

  a.theme.levelDropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.levelDropDownStyle:
    buttonCornerRadius       = ws.cornerRadius
    buttonFillColor          = lds.buttonColor
    buttonFillColorHover     = lds.buttonHoverColor
    buttonFillColorDown      = lds.buttonColor
    buttonFillColorDisabled  = lds.buttonColor
    label.fontSize           = 15.0
    label.color              = lds.buttonLabelColor
    label.colorHover         = lds.buttonLabelColor
    label.colorDown          = lds.buttonLabelColor
    label.colorActive        = lds.buttonLabelColor
    label.colorDisabled      = lds.buttonLabelColor
    label.align              = haCenter
    item.align               = haLeft
    item.color               = lds.itemColor
    item.colorHover          = lds.itemHoverColor
    itemListCornerRadius     = ws.cornerRadius
    itemListPadHoriz         = 10.0
    itemListFillColor        = lds.itemListBackgroundColor
    itemBackgroundColorHover = ws.backgroundActiveColor

  # About button
  alias(abs, s.ui.aboutButton)

  a.theme.aboutButtonStyle = koi.getDefaultButtonStyle()

  with a.theme.aboutButtonStyle:
    labelOnly        = true
    label.fontSize   = 20.0
    label.padHoriz   = 0
    label.color      = abs.labelColor
    label.colorHover = abs.labelHoverColor
    label.colorDown  = abs.labelDownColor

  # Note text area
  a.theme.noteTextAreaStyle = koi.getDefaultTextAreaStyle()
  with a.theme.noteTextAreaStyle:
    bgFillColor         = black(0)
    bgFillColorHover    = black(0)
    bgFillColorActive   = black(0)
    bgFillColorDisabled = black(0)

    textPadHoriz        = 0.0
    textPadVert         = 0.0
    textFontSize        = 15.0
    textFontFace        = "sans-bold"
    textLineHeight      = 1.4
    textColorDisabled   = s.pane.notes.textColor

    with scrollBarStyleNormal:
      let c = s.pane.notes.scrollBarColor
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

# }}}
# {{{ searchThemes()
proc searchThemes(a) =
  var themeNames: seq[ThemeName] = @[]

  proc findThemeWithName(name: string): int =
    for i in 0..themeNames.high:
      if themeNames[i].name == name: return i
    result = -1

  proc addThemeNames(themesDir: string, userTheme: bool) =
    for path in walkFiles(themesDir / fmt"*.{ThemeExt}"):
      let (_, name, _) = splitFile(path)
      let idx = findThemeWithName(name)
      if idx >= 0:
        themeNames.del(idx)
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: true)
        )
      else:
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: false)
        )

  addThemeNames(a.path.themesDir, userTheme=false)
  addThemeNames(a.path.userThemesDir, userTheme=true)

  if themeNames.len == 0:
    raise newException(IOError, "Could not find any themes, exiting")

  themeNames.sort(
    proc (a, b: ThemeName): int = cmp(a.name, b.name)
  )

  a.theme.themeNames = themeNames

# }}}
# {{{ findThemeIndex()
proc findThemeIndex(name: string; a): int =
  for i in 0..a.theme.themeNames.high:
    if a.theme.themeNames[i].name == name:
      return i
  result = -1

# }}}
# {{{ themePath()
proc themePath(theme: ThemeName; a): string =
  let themeDir = if theme.userTheme: a.path.userThemesDir
                 else: a.path.themesDir
  themeDir / addFileExt(theme.name, ThemeExt)

# }}}
# {{{ loadTheme()
proc loadTheme(theme: ThemeName; a) =
  var path = themePath(theme, a)
  info(fmt"Loading theme '{theme.name}' from '{path}'")

  a.theme.style = loadTheme(path)

# }}}
# {{{ switchTheme()
proc switchTheme(themeIndex: Natural; a) =
  let theme = a.theme.themeNames[themeIndex]
  loadTheme(theme, a)
  updateWidgetStyles(a)

  let bgImageName = a.theme.style.ui.window.backgroundImage

  proc tryLoadImage(path: string; a): Option[Paint] =
    var imgPath = path / bgImageName
    result = loadImage(imgPath, a)
    if result.isNone:
      info(fmt"Couldn't load background image '{imgPath}'")

  if bgImageName != "":
    var image = Paint.none
    if theme.userTheme:
      image = tryLoadImage(a.path.userThemeImagesDir, a)
      info("Attempting to load it from the default theme images directory.")

    if image.isNone:
      image = tryLoadImage(a.path.themeImagesDir, a)

    a.ui.backgroundImage = image
    a.ui.drawLevelParams.backgroundImage = a.ui.backgroundImage
  else:
    a.ui.backgroundImage = Paint.none
    a.ui.drawLevelParams.backgroundImage = Paint.none

  a.doc.levelStyle = a.theme.style.level

  a.ui.drawLevelParams.initDrawLevelParams(a.doc.levelStyle, a.vg,
                                           koi.getPxRatio())

  a.win.setStyle(a.theme.style.ui.window)

  a.theme.currThemeIndex = themeIndex

# }}}

# }}}
# {{{ Key handling
proc hasKeyEvent(): bool =
  koi.hasEvent() and koi.currEvent().kind == ekKey

func isKeyDown(ev: Event, keys: set[Key], mods: set[ModifierKey] = {},
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
    koi.label("Origin", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Northwest", "Southwest"],
      dlg.origin,
      style = a.theme.radioButtonStyle
    )

  group:
    koi.label("Column style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.columnStyle,
      style = a.theme.radioButtonStyle
    )

    koi.label("Row style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.rowStyle,
      style = a.theme.radioButtonStyle
    )

  group:
    let letterLabelX = x + 190

    koi.label("Column start", style=a.theme.labelStyle)
    var y = koi.currAutoLayoutY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.columnStart,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        minInt: 0,
        maxInt: LevelColumnsLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.columnStyle) == csLetter:
      try:
        let i = parseInt(dlg.columnStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.clamp(0, LevelColumnsLimits.maxInt).toLetterCoord,
                  style=a.theme.labelStyle)
      except ValueError:
        discard

    koi.label("Row start", style=a.theme.labelStyle)
    y = koi.currAutoLayoutY()


    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rowStart,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        minInt: 0,
        maxInt: LevelRowsLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.rowStyle) == csLetter:
      try:
        let i = parseInt(dlg.rowStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.clamp(0, LevelRowsLimits.maxInt).toLetterCoord,
                  style=a.theme.labelStyle)
      except ValueError:
        discard

# }}}
# {{{ regionFields()
template regionFields() =
  group:
    koi.label("Enable regions", style=a.theme.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.enableRegions, style = a.theme.checkBoxStyle)

    if dlg.enableRegions:
      group:
        koi.label("Region columns", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.colsPerRegion,
          activate = dlg.activateFirstTextField,
          constraint = TextFieldConstraint(
            kind: tckInteger,
            minInt: LevelRowsLimits.minInt,
            maxInt: LevelRowsLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )


        koi.label("Region rows", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.rowsPerRegion,
          constraint = TextFieldConstraint(
            kind: tckInteger,
            minInt: LevelColumnsLimits.minInt,
            maxInt: LevelColumnsLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

      group:
        koi.label("Per-region coordinates", style=a.theme.labelStyle)

        koi.nextItemHeight(DlgCheckBoxSize)
        koi.checkBox(dlg.perRegionCoords, style = a.theme.checkBoxStyle)

# }}}
# {{{ noteFields()
template noteFields(dlgWidth: float) =
  koi.label("Notes", style=a.theme.labelStyle)

  koi.textArea(
    x=0, y=28, w=dlgWidth-60, h=187,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

# }}}
# {{{ levelCommonFields()
template levelCommonFields() =
  group:
    koi.label("Location name", style=a.theme.labelStyle)

    koi.textField(
      dlg.locationName,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: LevelLocationNameLimits.minRuneLen,
        maxLen: LevelLocationNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Level name", style=a.theme.labelStyle)

    koi.textField(
      dlg.levelName,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: LevelNameLimits.minRuneLen,
        maxLen: LevelNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Elevation", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.elevation,
      constraint = TextFieldConstraint(
        kind: tckInteger,
        minInt: LevelElevationLimits.minInt,
        maxInt: LevelElevationLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
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

  if ke.isKeyDown(MoveKeysCursor.left, {mkCtrl}) or
     ke.isKeyDown(keyTab, {mkCtrl, mkShift}):
    if    currTabIndex > 0: result = currTabIndex - 1
    else: result = maxTabIndex

  elif ke.isKeyDown(MoveKeysCursor.right, {mkCtrl}) or
       ke.isKeyDown(keyTab, {mkCtrl}):
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


# {{{ About dialog
proc openAboutDialog(a) =
  a.dialog.aboutDialog.isOpen = true

proc openUserManualAction(a)
proc openWebsiteAction(a)
proc openForumAction(a)

proc aboutDialog(dlg: var AboutDialogParams; a) =
  alias(al, a.aboutLogo)
  alias(vg, a.vg)

  let ts = a.theme.style

  const
    DlgWidth = 370.0
    DlgHeight = 440.0

  let
    dialogX = floor(calcDialogX(DlgWidth, a))
    dialogY = floor((koi.winHeight() - DlgHeight) * 0.5)

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconQuestion}  About Gridmonger",
                  x=dialogX.some, y=dialogY.some,
                  style=a.theme.aboutDialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad
  let w = DlgWidth
  let h = DlgItemHeight

  if al.logoImage == NoImage or al.updateLogoImage:
    colorImage(al.logo, ts.ui.aboutDialog.logoColor)
    if al.logoImage == NoImage:
      al.logoImage = createImage(al.logo)
    else:
      vg.updateImage(al.logoImage, cast[ptr byte](al.logo.data))
    al.updateLogoImage = false

  let scale = DlgWidth / al.logo.width

  al.logoPaint = createPattern(a.vg, al.logoImage,
                               alpha=ts.ui.aboutDialog.logoColor.a,
                               xoffs=dialogX, yoffs=dialogY, scale=scale)


  koi.image(0, 0, DlgWidth.float, DlgHeight.float, al.logoPaint)

  var labelStyle = a.theme.labelStyle.deepCopy()
  labelStyle.align = haCenter

  y += 265
  koi.label(0, y, w, h, fmt"version {AppVersion}  ({BuildGitHash})",
            style=labelStyle)

  y += 25
  koi.label(0, y, w, h, "Developed by John Novak, 2019-2021", style=labelStyle)

  x = (DlgWidth - (3*DlgButtonWidth + 2*DlgButtonPad)) * 0.5
  y += 50
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Manual",
                style=a.theme.buttonStyle):
    openUserManualAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Website",
                style=a.theme.buttonStyle):
    openWebsiteAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Forum",
                style=a.theme.buttonStyle):
    openForumAction(a)

  proc closeAction(dlg: var AboutDialogParams; a) =
    a.aboutLogo.updateLogoImage = true
    koi.closeDialog()
    dlg.isOpen = false


  # HACK, HACK, HACK!
  if not a.opts.showThemePane:
    if not koi.hasHotItem() and koi.hasEvent():
      let ev = koi.currEvent()
      if ev.kind == ekMouseButton and ev.button == mbLeft and ev.pressed:
        closeAction(dlg, a)

  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scCancel) or ke.isShortcutDown(scAccept):
      closeAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Preferences dialog
proc openPreferencesDialog(a) =
  alias(dlg, a.dialog.preferencesDialog)

  dlg.showSplash = a.prefs.showSplash
  dlg.autoCloseSplash = a.prefs.autoCloseSplash
  dlg.splashTimeoutSecs = $a.prefs.splashTimeoutSecs
  dlg.loadLastMap = a.prefs.loadLastMap
  dlg.disableVSync = a.prefs.disableVSync
  dlg.autosave = a.prefs.autosave
  dlg.autosaveFreqMins = $a.prefs.autosaveFreqMins

  dlg.isOpen = true


proc preferencesDialog(dlg: var PreferencesDialogParams; a) =
  const
    DlgWidth = 370.0
    DlgHeight = 296.0
    TabWidth = 180.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCog}  Preferences",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["Startup", "General"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad
  koi.beginView(x, y, 1000, 1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 220
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General

    group:
      koi.label("Show splash image", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.showSplash, style = a.theme.checkBoxStyle)


      var disabled = not dlg.showSplash
      koi.label("Auto-close splash",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autoCloseSplash, disabled=disabled,
                   style = a.theme.checkBoxStyle)


      disabled = not (dlg.showSplash and dlg.autoCloseSplash)
      koi.label("Auto-close timeout (seconds)",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.splashTimeoutSecs,
        activate = dlg.activateFirstTextField,
        disabled = disabled,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          minInt: SplashTimeoutSecsLimits.minInt,
          maxInt: SplashTimeoutSecsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Load last map", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.loadLastMap, style = a.theme.checkBoxStyle)


  elif dlg.activeTab == 1:  # General

    group:
      let autosaveDisabled = not dlg.autosave

      koi.label("Autosave", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autosave, style = a.theme.checkBoxStyle)

      koi.label("Autosave frequency (minutes)",
                state = if autosaveDisabled: wsDisabled else: wsNormal,
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.autosaveFreqMins,
        activate = dlg.activateFirstTextField,
        disabled = autosaveDisabled,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          minInt: AutosaveFreqMinsLimits.minInt,
          maxInt: AutosaveFreqMinsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Disable vertical sync", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.disableVSync, style = a.theme.checkBoxStyle)

  koi.endView()


  proc okAction(dlg: var PreferencesDialogParams; a) =
    a.prefs.showSplash        = dlg.showSplash
    a.prefs.autoCloseSplash   = dlg.autoCloseSplash
    a.prefs.splashTimeoutSecs = parseInt(dlg.splashTimeoutSecs).Natural
    a.prefs.loadLastMap       = dlg.loadLastMap
    a.prefs.disableVSync      = dlg.disableVSync
    a.prefs.autosave          = dlg.autosave
    a.prefs.autosaveFreqMins  = parseInt(dlg.autosaveFreqMins).Natural

    savePreferences(a)
    setSwapInterval(a)

    koi.closeDialog()
    dlg.isOpen = false

  proc cancelAction(dlg: var PreferencesDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
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
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have unsaved changes.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save your changes first?",
    style=a.theme.labelStyle
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
                style = a.theme.buttonStyle):
    saveAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
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

  with a.doc.map.coordOpts:
    dlg.name        = "Untitled Map"
    dlg.origin      = origin.ord
    dlg.rowStyle    = rowStyle.ord
    dlg.columnStyle = columnStyle.ord
    dlg.rowStart    = $rowStart
    dlg.columnStart = $columnStart
    dlg.notes       = ""

  dlg.activeTab = 0
  dlg.isOpen = true


proc newMapDialog(dlg: var NewMapDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Map",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  a.clearStatusMessage()

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    group:
      koi.label("Name", style=a.theme.labelStyle)

      koi.textField(
        dlg.name,
        activate = dlg.activateFirstTextField,
        constraint = TextFieldConstraint(
          kind: tckString,
          minLen: MapNameLimits.minRuneLen,
          maxLen: MapNameLimits.maxRuneLen.some
        ).some,
        style = a.theme.textFieldStyle
      )

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: var NewMapDialogParams; a) =
    if validationError != "": return

    a.opts.drawTrail = false

    a.doc.filename = ""
    a.doc.map = newMap(dlg.name)

    with a.doc.map.coordOpts:
      origin      = CoordinateOrigin(dlg.origin)
      rowStyle    = CoordinateStyle(dlg.rowStyle)
      columnStyle = CoordinateStyle(dlg.columnStyle)
      rowStart    = parseInt(dlg.rowStart)
      columnStart = parseInt(dlg.columnStart)

    a.doc.map.notes = dlg.notes

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
                disabled=validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
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
# {{{ Edit map properties dialog
proc openEditMapPropsDialog(a) =
  alias(dlg, a.dialog.editMapPropsDialog)
  alias(map, a.doc.map)

  dlg.name = $map.name

  with map.coordOpts:
    dlg.origin      = origin.ord
    dlg.rowStyle    = rowStyle.ord
    dlg.columnStyle = columnStyle.ord
    dlg.rowStart    = $rowStart
    dlg.columnStart = $columnStart

  dlg.notes = map.notes
  dlg.isOpen = true


proc editMapPropsDialog(dlg: var EditMapPropsDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  Edit Map Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    group:
      koi.label("Name", style=a.theme.labelStyle)
      koi.textField(
        dlg.name,
        activate = dlg.activateFirstTextField,
        constraint = TextFieldConstraint(
          kind: tckString,
          minLen: MapNameLimits.minRuneLen,
          maxLen: MapNameLimits.maxRuneLen.some
        ).some,
        style = a.theme.textFieldStyle
      )

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: var EditMapPropsDialogParams; a) =
    if validationError != "": return

    let coordOpts = CoordinateOptions(
      origin      : CoordinateOrigin(dlg.origin),
      rowStyle    : CoordinateStyle(dlg.rowStyle),
      columnStyle : CoordinateStyle(dlg.columnStyle),
      rowStart    : parseInt(dlg.rowStart),
      columnStart : parseInt(dlg.columnStart)
    )

    actions.setMapProperties(a.doc.map, a.ui.cursor, dlg.name, coordOpts,
                             dlg.notes, a.doc.undoManager)

    setStatusMessage(IconFile, "Map properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditMapPropsDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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

# {{{ New level dialog
proc openNewLevelDialog(a) =
  alias(dlg, a.dialog.newLevelDialog)
  let map = a.doc.map

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

    co = map.coordOpts

  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.enableRegions   = false
  dlg.colsPerRegion   = "16"
  dlg.rowsPerRegion   = "16"
  dlg.perRegionCoords = true

  dlg.activeTab = 0
  dlg.isOpen = true


proc newLevelDialog(dlg: var NewLevelDialogParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 460.0
    DlgHeight = 436.0
    TabWidth = 400.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Level",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    levelCommonFields()

    group:
      koi.label("Columns", style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.cols,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          minInt: LevelColumnsLimits.minInt,
          maxInt: LevelColumnsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

      koi.label("Rows", style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.rows,
        constraint = TextFieldConstraint(
          kind: tckInteger,
          minInt: LevelRowsLimits.minInt,
          maxInt: LevelRowsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

  elif dlg.activeTab == 1:  # Coordinates
    group:
      koi.label("Override map settings", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.overrideCoordOpts, style = a.theme.checkBoxStyle)

      if dlg.overrideCoordOpts:
        coordinateFields()

  elif dlg.activeTab == 2:  # Regions
    regionFields()

  elif dlg.activeTab == 3:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = ""
  validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: var NewLevelDialogParams; a) =
    if validationError != "": return

    a.opts.drawTrail = false

    let
      rows = parseInt(dlg.rows)
      cols = parseInt(dlg.cols)

    let cur = actions.addNewLevel(
      a.doc.map,
      a.ui.cursor,
      locationName = dlg.locationName,
      levelName = dlg.levelName,
      elevation = parseInt(dlg.elevation),
      rows = rows,
      cols = cols,
      dlg.overrideCoordOpts,

      coordOpts = CoordinateOptions(
        origin      : CoordinateOrigin(dlg.origin),
        rowStyle    : CoordinateStyle(dlg.rowStyle),
        columnStyle : CoordinateStyle(dlg.columnStyle),
        rowStart    : parseInt(dlg.rowStart),
        columnStart : parseInt(dlg.columnStart)
      ),

      regionOpts = RegionOptions(
        enabled         : dlg.enableRegions,
        colsPerRegion   : parseInt(dlg.colsPerRegion),
        rowsPerRegion   : parseInt(dlg.rowsPerRegion),
        perRegionCoords : dlg.perRegionCoords
      ),

      dlg.notes,
      a.doc.undoManager
    )
    setCursor(cur, a)

    setStatusMessage(IconFile, fmt"New {rows}x{cols} level created", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var NewLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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
  dlg.enableRegions   = ro.enabled
  dlg.colsPerRegion   = $ro.colsPerRegion
  dlg.rowsPerRegion   = $ro.rowsPerRegion
  dlg.perRegionCoords = ro.perRegionCoords

  dlg.notes = l.notes

  dlg.isOpen = true


proc editLevelPropsDialog(dlg: var EditLevelPropsParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 460.0
    DlgHeight = 436.0
    TabWidth = 400.0

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconNewFile}  Edit Level Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, 1000, 1000)
  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    levelCommonFields()

  elif dlg.activeTab == 1:  # Coordinates
    koi.label("Override map settings", style=a.theme.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.overrideCoordOpts, style = a.theme.checkBoxStyle)

    if dlg.overrideCoordOpts:
      coordinateFields()

  elif dlg.activeTab == 2:  # Regions
    regionFields()

  elif dlg.activeTab == 3:  # Notes
    noteFields(DlgWidth)

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
              style=a.theme.warningLabelStyle)


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
      enabled         : dlg.enableRegions,
      rowsPerRegion   : parseInt(dlg.rowsPerRegion),
      colsPerRegion   : parseInt(dlg.colsPerRegion),
      perRegionCoords : dlg.perRegionCoords
    )

    actions.setLevelProperties(a.doc.map, a.ui.cursor,
                               dlg.locationName, dlg.levelName, elevation,
                               dlg.overrideCoordOpts, coordOpts, regionOpts,
                               dlg.notes,
                               a.doc.undoManager)

    setStatusMessage(fmt"Level properties updated", a)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditLevelPropsParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Columns", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w = DlgNumberWidth, h,
    dlg.cols,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckInteger,
      minInt: LevelColumnsLimits.minInt,
      maxInt: LevelColumnsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  y += PadYSmall
  koi.label(x, y, LabelWidth, h, "Rows", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w = DlgNumberWidth, h,
    dlg.rows,
    constraint = TextFieldConstraint(
      kind: tckInteger,
      minInt: LevelRowsLimits.minInt,
      maxInt: LevelRowsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  const IconsPerRow = 3

  const AnchorIcons = @[
    IconArrowUpLeft,   IconArrowUp,   IconArrowUpRight,
    IconArrowLeft,     IconCircleInv, IconArrowRight,
    IconArrowDownLeft, IconArrowDown, IconArrowDownRight
  ]

  y += PadYLarge
  koi.label(x, y, LabelWidth, h, "Anchor", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 35, 35,
    labels = AnchorIcons,
    dlg.anchor,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: IconsPerRow),
    style = a.theme.iconRadioButtonsStyle
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
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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
  alias(um, a.doc.undoManager)

  const
    DlgWidth = 350.0
    DlgHeight = 136.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete level?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "Do you want to delete the current level?",
            style=a.theme.labelStyle)

  proc deleteAction(dlg: var DeleteLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false

    a.opts.drawTrail = false

    let cur = actions.deleteLevel(map, a.ui.cursor, um)
    setStatusMessage(IconTrash, "Level deleted", a)
    setCursor(cur, a)


  proc cancelAction(dlg: var DeleteLevelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.theme.buttonStyle):
    deleteAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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

  let cur = a.ui.cursor

  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let note = l.getNote(cur.row, cur.col)

  if note.isSome:
    let note = note.get
    dlg.editMode = true
    dlg.kind = note.kind
    dlg.text = note.text

    if note.kind == akIndexed:
      dlg.index = note.index
      dlg.indexColor = note.indexColor
    elif note.kind == akIcon:
      dlg.icon = note.icon

    if note.kind == akCustomId:
      dlg.customId = note.customId
    else:
      dlg.customId = ""

  else:
    dlg.editMode = false
    dlg.customId = ""
    dlg.text = ""

  dlg.isOpen = true


proc editNoteDialog(dlg: var EditNoteDialogParams; a) =
  let ls = a.doc.levelStyle

  const
    DlgWidth = 486.0
    DlgHeight = 401.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "Marker", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 296, h,
    labels = @["None", "Number", "ID", "Icon"],
    dlg.kind,
    style = a.theme.radioButtonStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w = 346, h = 92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.note.indexBackgroundColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of akIndexed:
    koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 28, 28,
      labels = newSeq[string](ls.note.indexBackgroundColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc = colorRadioButtonDrawProc(ls.note.indexBackgroundColor.toSeq,
                                          ls.general.cursorColor).some
    )

  of akCustomId:
    koi.label(x, y, LabelWidth, h, "ID", style=a.theme.labelStyle)
    koi.textField(
      x + LabelWidth, y, w = DlgNumberWidth, h,
      dlg.customId,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: NoteCustomIdLimits.minRuneLen,
        maxLen: NoteCustomIdLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  of akIcon:
    koi.label(x, y, LabelWidth, h, "Icon", style=a.theme.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 35, 35,
      labels = NoteIcons,
      dlg.icon,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 10),
      style = a.theme.iconRadioButtonsStyle
    )

  of akComment, akLabel: discard

  dlg.activateFirstTextField = false

  # Validation
  var validationErrors: seq[string] = @[]

  if dlg.kind in {akComment, akIndexed, akCustomId}:
    if dlg.text == "":
      validationErrors.add(mkValidationError("Text is mandatory"))
  if dlg.kind == akCustomId:
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

  y += 45

  for err in validationErrors:
    koi.label(x, y, DlgWidth, h, err, style=a.theme.warningLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: var EditNoteDialogParams; a) =
    if validationErrors.len > 0: return

    var note = Annotation(
      kind: dlg.kind,
      text: dlg.text
    )
    case note.kind
    of akCustomId: note.customId = dlg.customId
    of akIndexed:  note.indexColor = dlg.indexColor
    of akIcon:     note.icon = dlg.icon
    of akComment, akLabel: discard

    actions.setNote(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set cell note", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditNoteDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=validationErrors.len > 0,
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.kind = AnnotationKind(
      handleTabNavigation(ke, ord(dlg.kind), ord(akIcon))
    )

    case dlg.kind
    of akComment, akCustomId, akLabel: discard
    of akIndexed:
      dlg.indexColor = handleGridRadioButton(
        ke, dlg.indexColor, NumIndexColors, buttonsPerRow=NumIndexColors
      )
    of akIcon:
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

  let cur = a.ui.cursor

  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let label = l.getLabel(cur.row, cur.col)

  if label.isSome:
    let label = label.get
    dlg.editMode = true
    dlg.text = label.text
    dlg.color = label.labelColor
  else:
    dlg.editMode = false
    dlg.text = ""
    dlg.color = 0

  dlg.isOpen = true


proc editLabelDialog(dlg: var EditLabelDialogParams; a) =
  let ls = a.doc.levelStyle

  const
    DlgWidth = 486.0
    DlgHeight = 285.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Label"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w = 346, h = 92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = ls.note.indexBackgroundColor.len

  koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 28, 28,
    labels = newSeq[string](ls.label.color.len),
    dlg.color,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc = colorRadioButtonDrawProc(ls.label.color.toSeq,
                                        ls.general.cursorColor).some,
    style = a.theme.radioButtonStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.text == "":
    validationError = mkValidationError("Text is mandatory")

  y += 44

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.warningLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: var EditLabelDialogParams; a) =
    if validationError != "": return

    var note = Annotation(kind: akLabel, text: dlg.text, labelColor: dlg.color)
    actions.setLabel(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set label", a)
    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditLabelDialogParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.color = handleGridRadioButton(
      ke, dlg.color, NumIndexColors, buttonsPerRow=NumIndexColors
    )

    if ke.isShortcutDown(scNextTextField):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel): cancelAction(dlg, a)
    elif ke.isShortcutDown(scAccept): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit region properties dialog
proc openEditRegionPropertiesDialog(a) =
  alias(dlg, a.dialog.editRegionPropsDialog)

  dlg.name = currRegion(a).get.name
  dlg.isOpen = true


proc editRegionPropsDialog(dlg: var EditRegionPropsParams; a) =

  const
    DlgWidth = 430.0
    DlgHeight = 190.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let l = currLevel(a)

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconCommentInv}  Edit Region Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w = 294, h,
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: RegionNameLimits.minRuneLen,
      maxLen: RegionNameLimits.maxRuneLen.some
    ).some,
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")
  else:
    if dlg.name != currRegion(a).get.name:
      for name in l.regionNames():
        if name == dlg.name:
          validationError = mkValidationError(
            "A region already exists with the same name"
          )
          break

  y += 44

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.warningLabelStyle)
    y += h


  proc okAction(dlg: var EditRegionPropsParams; a) =
    alias(map, a.doc.map)
    let cur = a.ui.cursor

    setStatusMessage(IconComment, "Region properties updated", a)

    let regionCoords = map.getRegionCoords(cur)
    let region = Region(name: dlg.name)

    actions.setRegionProperties(map, cur, regionCoords, region,
                                a.doc.undoManager)

    koi.closeDialog()
    dlg.isOpen = false


  proc cancelAction(dlg: var EditRegionPropsParams; a) =
    koi.closeDialog()
    dlg.isOpen = false


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(dlg, a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

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

# {{{ openUserManualAction()
proc openUserManualAction(a) =
  openDefaultBrowser(a.path.manualDir / "index.html")

# }}}
# {{{ openWebsiteAction()
proc openWebsiteAction(a) =
  openDefaultBrowser("https://gridmonger.johnnovak.net")

# }}}
# {{{ openForumAction()
proc openForumAction(a) =
  openDefaultBrowser("https://gridmonger.johnnovak.net")

# }}}

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
    logError(e, "Error loading map")
    setStatusMessage(IconWarning, fmt"Error loading map: {e.msg}", a)

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
  let dp = a.ui.drawLevelParams

  let cur = a.ui.cursor

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
    logError(e, "Error saving map")
    let prefix = if autosave: "Autosave failed: " else: ""
    setStatusMessage(IconWarning, fmt"{prefix}Error saving map: {e.msg}", a)

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
  var si = currSortedLevelIdx(a)
  if si > 0:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si - 1]
    setCursor(cur, a)

# }}}
# {{{ nextLevelAction()
proc nextLevelAction(a) =
  var si = currSortedLevelIdx(a)
  if si < a.doc.map.levels.len-1:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIdxToLevelIdx[si + 1]
    setCursor(cur, a)

# }}}

# {{{ centerCursorAfterZoom()
proc centerCursorAfterZoom(a) =
  let dp = a.ui.drawLevelParams
  let cur = a.ui.cursor

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
  let ot = a.doc.map.guessFloorOrientation(a.ui.cursor)
  actions.setOrientedFloor(a.doc.map, a.ui.cursor, f, ot, a.ui.currFloorColor,
                           a.doc.undoManager)
  setStatusMessage(fmt"Set floor type – {f}", a)

# }}}
# {{{ setOrCycleFloorAction()
proc setOrCycleFloorAction(floors: seq[Floor], forward: bool; a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    var i = floors.find(floor)
    if i > -1:
      if forward: inc(i) else: dec(i)
      floor = floors[floorMod(i, floors.len)]
    else:
      floor = if forward: floors[0] else: floors[^1]

    setFloorAction(floor, a)
  else:
    setStatusMessage(IconWarning, "Cannot set floor type of an empty cell", a)

# }}}
# {{{ startExcavateAction()
proc startExcavateAction(a) =
  actions.excavate(a.doc.map, a.ui.cursor, a.ui.currFloorColor,
                   a.doc.undoManager)

  setStatusMessage(IconPencil, "Excavate tunnel", @[IconArrowsAll,
                   "excavate"], a)

# }}}
# {{{ startEraseCellsAction()
proc startEraseCellsAction(a) =
  actions.eraseCell(a.doc.map, a.ui.cursor, a.doc.undoManager)
  setStatusMessage(IconEraser, "Erase cell", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startEraseTrailAction()
proc startEraseTrailAction(a) =
  a.doc.map.setTrail(a.ui.cursor, false)
  setStatusMessage(IconEraser, "Erase trail", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startDrawWallsAction()
proc startDrawWallsAction(a) =
  setStatusMessage("", "Draw walls", @[IconArrowsAll, "set/clear"], a)

# }}}
# {{{ startDrawWallsSpecialAction()
proc startDrawWallsSpecialAction(a) =
  setStatusMessage("", "Draw walls special", @[IconArrowsAll, "set/clear"], a)

# }}}
# {{{ prevFloorColorAction()
proc prevFloorColorAction(a) =
  if a.ui.currFloorColor > 0: dec(a.ui.currFloorColor)
  else: a.ui.currFloorColor = a.doc.levelStyle.floorColor.color.high.byte

# }}}
# {{{ nextFloorColorAction()
proc nextFloorColorAction(a) =
  if a.ui.currFloorColor < a.doc.levelStyle.floorColor.color.high.byte:
    inc(a.ui.currFloorColor)
  else: a.ui.currFloorColor = 0

# }}}

# }}}
# {{{ Drawing

# {{{ drawEmptyMap()
proc drawEmptyMap(a) =
  alias(vg, a.vg)

  let ls = a.doc.levelStyle

  vg.setFont(size=22)
  vg.fillColor(ls.general.foregroundColor)
  vg.textAlign(haCenter, vaMiddle)
  var y = drawAreaHeight(a) * 0.5
  discard vg.text(drawAreaWidth(a) * 0.5, y, "Empty map")

# }}}
# {{{ drawNoteTooltip()
proc drawNoteTooltip(x, y: float, note: Annotation, a) =
  alias(vg, a.vg)
  alias(ui, a.ui)

  let dp = a.ui.drawLevelParams

  if note.text != "":
    const PadX = 10
    const PadY = 8

    var
      noteBoxX = x
      noteBoxY = y
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

    vg.fillColor(a.theme.style.level.note.tooltipBackgroundColor)
    vg.beginPath()
    vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH, 5)
    vg.fill()

    vg.fillColor(a.theme.style.level.note.tooltipColor)
    vg.textBox(noteBoxX + PadX, noteBoxY + PadY, noteTextW, note.text)

# }}}
# {{{ drawModeAndOptionIndicators()
proc drawModeAndOptionIndicators(a) =
  alias(vg, a.vg)
  alias(ui, a.ui)

  let ls = a.doc.levelStyle

  var x = ui.levelLeftPad
  let y = TitleBarHeight + 32

  vg.save()

  vg.fillColor(ls.general.coordinatesHighlightColor)

  if a.opts.wasdMode:
    vg.setFont(15)
    discard vg.text(x, y, fmt"WASD+{IconMouse}")
    x += 80

  if a.opts.drawTrail:
    vg.setFont(19)
    discard vg.text(x, y+1, IconShoePrints)

# }}}
# {{{ drawStatusBar()
proc drawStatusBar(y: float, winWidth: float; a) =
  alias(vg, a.vg)

  let s = a.theme.style.ui.statusBar

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

    vg.fillColor(s.coordinatesColor)
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
      vg.fillColor(s.commandBackgroundColor)
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

# {{{ resetManualNoteTooltip()
proc resetManualNoteTooltip(a) =
  with a.ui.manualNoteTooltipState:
    show = false
    mx = -1
    my = -1

# }}}
# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents(a) =
  alias(ui, a.ui)
  alias(opts, a.opts)

  if opts.wasdMode:
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
      else:
        if koi.mbLeftDown():
          ui.editMode = emDrawWallSpecial
          startDrawWallsSpecialAction(a)

    elif ui.editMode == emDrawWallSpecial:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)
      else:
        if not koi.mbLeftDown():
          ui.editMode = emDrawWall
          startDrawWallsAction(a)

    elif ui.editMode == emEraseCell:
      if not koi.mbMiddleDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

  else:  # not WASD mode
    if koi.mbLeftDown():
      let loc = locationAtMouse(a)
      if loc.isSome:
        a.ui.cursor = loc.get
        resetManualNoteTooltip(a)

# }}}
# {{{ handleGlobalKeyEvents()
# TODO separate into level events and global events?
proc handleGlobalKeyEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)
  alias(opts, a.opts)

  let dp = a.ui.drawLevelParams

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

  proc toggleOption(opt: var bool, icon, msg, on, off: string; a) =
    opt = not opt
    let state = if opt: on else: off
    setStatusMessage(icon, fmt"{msg} {state}", a)

  proc toggleShowOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="shown", off="hidden", a)

  proc toggleOnOffOption(opt: var bool, icon, msg: string; a) =
    toggleOption(opt, icon, msg, on="on", off="off", a)


  proc handleMoveWalk(ke: Event; a) =
    let k = if opts.wasdMode: WalkKeysWasd else: WalkKeysCursor

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
    let k = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor

    if   ke.isKeyDown(k.left,  repeat=true): moveHandler(dirW, a)
    elif ke.isKeyDown(k.right, repeat=true): moveHandler(dirE, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveHandler(dirN, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveHandler(dirS, a)


  proc handleMoveCursor(ke: Event, k: MoveKeys,
                        allowPan, allowJump: bool; a): bool =
    const j = CursorJump
    result = true

    if   ke.isKeyDown(k.left,  repeat=true): moveCursor(dirW, 1, a)
    elif ke.isKeyDown(k.right, repeat=true): moveCursor(dirE, 1, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveCursor(dirN, 1, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveCursor(dirS, 1, a)
    elif allowPan:
      if   ke.isKeyDown(k.left,  {mkShift}, repeat=true): moveLevel(dirW, 1, a)
      elif ke.isKeyDown(k.right, {mkShift}, repeat=true): moveLevel(dirE, 1, a)
      elif ke.isKeyDown(k.up,    {mkShift}, repeat=true): moveLevel(dirN, 1, a)
      elif ke.isKeyDown(k.down,  {mkShift}, repeat=true): moveLevel(dirS, 1, a)

    const mkCS = {mkCtrl, mkShift}

    if not a.opts.wasdMode and allowJump:
      if   ke.isKeyDown(k.left,  {mkCtrl}, repeat=true): moveCursor(dirW, j, a)
      elif ke.isKeyDown(k.right, {mkCtrl}, repeat=true): moveCursor(dirE, j, a)
      elif ke.isKeyDown(k.up,    {mkCtrl}, repeat=true): moveCursor(dirN, j, a)
      elif ke.isKeyDown(k.down,  {mkCtrl}, repeat=true): moveCursor(dirS, j, a)
      elif allowPan:
        if   ke.isKeyDown(k.left,  mkCS, repeat=true): moveLevel(dirW, j, a)
        elif ke.isKeyDown(k.right, mkCS, repeat=true): moveLevel(dirE, j, a)
        elif ke.isKeyDown(k.up,    mkCS, repeat=true): moveLevel(dirN, j, a)
        elif ke.isKeyDown(k.down,  mkCS, repeat=true): moveLevel(dirS, j, a)

    result = false


  proc handleMoveCursor(ke: Event, k: MoveKeys; a): bool =
    handleMoveCursor(ke, k, allowPan=true, allowJump=true, a)

  if hasKeyEvent():
    let ke = koi.currEvent()
    # TODO eventHandled is not set here, but it's not actually needed (yet)

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # Reset tooltip display on certain keypresses only
      if not (ke.key == keySpace) and
         not (ke.action == kaUp) and
         not (ke.key in {keyLeftControl,  keyLeftShift,  keyLeftAlt,
                         keyRightControl, keyRightShift, keyRightAlt}):
        resetManualNoteTooltip(a)

      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor
        if handleMoveCursor(ke, moveKeys, a):
          setStatusMessage("moved", a)

      if ke.isKeyDown({keyPageUp, keyKpSubtract}, repeat=true) or
         ke.isKeyDown(keyMinus, {mkCtrl}, repeat=true):
        prevLevelAction(a)

      elif ke.isKeyDown({keyPageDown, keyKpAdd}, repeat=true) or
           ke.isKeyDown(keyEqual, {mkCtrl}, repeat=true):
        nextLevelAction(a)

      let cur = a.ui.cursor

      if not opts.wasdMode and ke.isKeyDown(keyD):
        ui.editMode = emExcavate
        startExcavateAction(a)

      elif not (opts.wasdMode and opts.walkMode) and ke.isKeyDown(keyE):
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

      elif ke.isKeyDown(keyF):
        ui.editMode = emDrawClearFloor
        setStatusMessage(IconEraser, "Draw/clear floor",
                         @[IconArrowsAll, "draw/clear"], a)
        actions.drawClearFloor(map, cur, ui.currFloorColor, um)

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
        setStatusMessage(IconEraser, "Set floor color",
                         @[IconArrowsAll, "set color"], a)

        if not map.isEmpty(cur):
          actions.setFloorColor(map, cur, ui.currFloorColor, um)

      elif not opts.wasdMode and ke.isKeyDown(keyW):
        ui.editMode = emDrawWall
        startDrawWallsAction(a)

      elif ke.isKeyDown(keyR):
        ui.editMode = emDrawWallSpecial
        startDrawWallsSpecialAction(a)

      elif ke.isKeyDown(key1) or ke.isKeyDown(key1, {mkShift}):
        setOrCycleFloorAction(FloorsKey1, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key2) or ke.isKeyDown(key2, {mkShift}):
        setOrCycleFloorAction(FloorsKey2, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key3) or ke.isKeyDown(key3, {mkShift}):
        setOrCycleFloorAction(FloorsKey3, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key4) or ke.isKeyDown(key4, {mkShift}):
        setOrCycleFloorAction(FloorsKey4, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key5) or ke.isKeyDown(key5, {mkShift}):
        setOrCycleFloorAction(FloorsKey5, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(key6) or ke.isKeyDown(key6, {mkShift}):
        setOrCycleFloorAction(FloorsKey6, forward=not koi.shiftDown(), a)

      elif ke.isKeyDown(keyLeftBracket, repeat=true):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isKeyDown(keyRightBracket, repeat=true):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isKeyDown(keyX):
        ui.editMode = emEraseTrail
        startEraseTrailAction(a)

      elif ke.isKeyDown(keyD, {mkCtrl, mkAlt}):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.excavateTrail(map, cur, bbox.get, ui.currFloorColor, um)
          actions.clearTrail(map, cur, bbox.get, um,
                             groupWithPrev=true, actionName="Excavate trail")
          setStatusMessage(IconEraser, "Trail excavated", a)
        else:
          setStatusMessage(IconWarning, "No trail to excavate", a)

      elif ke.isKeyDown(keyX, {mkCtrl, mkAlt}):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.clearTrail(map, cur, bbox.get, um)
          setStatusMessage(IconEraser, "Trail cleared", a)
        else:
          setStatusMessage(IconWarning, "No trail to clear", a)

      elif ke.isKeyDown(keyComma,  repeat=true): prevFloorColorAction(a)
      elif ke.isKeyDown(keyPeriod, repeat=true): nextFloorColorAction(a)

      elif ke.isKeyDown(keyI):
        a.ui.currFloorColor = map.getFloorColor(cur).byte

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
                                 pasteBufferLevelIndex=CopyBufferLevelIndex,
                                 undoLoc=cur, um)
          if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

          setStatusMessage(IconPaste, "Buffer pasted", a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyP, {mkShift}):
        if ui.copyBuf.isSome:
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          opts.drawTrail = false
          ui.editMode = emPastePreview
          setStatusMessage(IconTiles, "Paste preview",
                           @[IconArrowsAll, "placement",
                           "Enter/P", "paste", "Esc", "exit"], a)
        else:
          setStatusMessage(IconWarning, "Cannot paste, buffer is empty", a)

      elif ke.isKeyDown(keyG, {mkCtrl}):
        let sel = newSelection(l.rows, l.cols)
        sel.fill(true)
        ui.nudgeBuf = SelectionBuffer(level: l, selection: sel).some
        map.levels[cur.level] = newLevel(
          l.locationName, l.levelName, l.elevation,
          l.rows, l.cols,
          l.overrideCoordOpts, l.coordOpts,
          l.regionOpts
        )

        dp.selStartRow = 0
        dp.selStartCol = 0

        ui.editMode = emNudgePreview
        opts.drawTrail = false
        setStatusMessage(IconArrowsAll, "Nudge preview",
                         @[IconArrowsAll, "nudge",
                         "Enter", "confirm", "Esc", "exit"], a)


      elif ke.isKeyDown(keyG):
        let otherLoc = map.getLinkedLocation(cur)
        if otherLoc.isSome:
          moveCursorTo(otherLoc.get, a)
        else:
          setStatusMessage(IconWarning, "Not a linked cell", a)

      elif ke.isKeyDown(keyG, {mkShift}):
        let floor = map.getFloor(cur)
        if floor in LinkSources:
          ui.linkSrcLocation = cur
          ui.editMode = emSetCellLink
          setSetLinkDestinationMessage(floor, a)
        else:
          setStatusMessage(IconWarning, "Cannot link current cell", a)

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
        if map.hasNote(cur):
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)
        else:
          setStatusMessage(IconWarning, "No note to erase in cell", a)

      elif ke.isKeyDown(keyT, {mkShift}):
        if map.hasLabel(cur):
          actions.eraseLabel(map, cur, um)
          setStatusMessage(IconEraser, "Label erased", a)
        else:
          setStatusMessage(IconWarning, "No label to erase in cell", a)

      elif ke.isKeyDown(keySpace):
        if ui.manualNoteTooltipState.show:
          resetManualNoteTooltip(a)
        else:
          if map.hasNote(cur):
            with ui.manualNoteTooltipState:
              show = true
              location = cur
              mx = koi.mx()
              my = koi.my()

      elif ke.isKeyDown(keyT, {mkCtrl}):
        openEditLabelDialog(a)

      elif ke.isKeyDown(keyU, {mkCtrl, mkAlt}):
        openPreferencesDialog(a)

      elif ke.isKeyDown(keyN, {mkCtrl}):
        if map.levels.len < NumLevelsLimits.maxInt:
          openNewLevelDialog(a)
        else:
          setStatusMessage(
            IconWarning,
            "Cannot add new level: maximum number of levels has been reached " &
            fmt"({NumLevelsLimits.maxInt})", a
          )

      elif ke.isKeyDown(keyD, {mkCtrl}):
        openDeleteLevelDialog(a)

      elif ke.isKeyDown(keyN, {mkCtrl, mkAlt}):
        newMapAction(a)

      elif ke.isKeyDown(keyP, {mkCtrl}):
        openEditLevelPropsDialog(a)

      elif ke.isKeyDown(keyP, {mkCtrl, mkAlt}):
        openEditMapPropsDialog(a)

      elif ke.isKeyDown(keyE, {mkCtrl}):
        openResizeLevelDialog(a)

      elif ke.isKeyDown(keyR, {mkCtrl, mkAlt}):
        if l.regionOpts.enabled:
          openEditRegionPropertiesDialog(a)
        else:
          setStatusMessage(
            IconWarning,
            "Cannot edit region properties: regions are not enabled for level",
            a
          )

      elif ke.isKeyDown(keyO, {mkCtrl}):              openMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl}):          saveMapAction(a)
      elif ke.isKeyDown(Key.keyS, {mkCtrl, mkShift}): saveMapAsAction(a)

      elif ke.isKeyDown(keyHome, {mkCtrl}):     reloadThemeAction(a)
      elif ke.isKeyDown(keyPageUp, {mkCtrl}):   prevThemeAction(a)
      elif ke.isKeyDown(keyPageDown, {mkCtrl}): nextThemeAction(a)

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

      elif ke.isKeyDown(keyA, {mkCtrl}):
        openAboutDialog(a)

      # Toggle options
      elif ke.isKeyDown(keyC, {mkAlt}):
        toggleShowOption(dp.drawCellCoords, NoIcon, "Cell coordinates", a)

      elif ke.isKeyDown(keyN, {mkAlt}):
        toggleShowOption(opts.showNotesPane, NoIcon, "Notes pane", a)

      elif ke.isKeyDown(keyT, {mkAlt}):
        toggleShowOption(opts.showToolsPane, NoIcon, "Tools pane", a)

      elif ke.isKeyDown(keyGraveAccent):
        opts.walkMode = not opts.walkMode
        let msg = if opts.walkMode: "Walk mode" else: "Normal mode"
        setStatusMessage(msg, a)

      elif ke.isKeyDown(keyTab):
        toggleOnOffOption(opts.wasdMode, IconMouse, "WASD mode", a)

      elif ke.isKeyDown(keyT):
        map.setTrail(cur, true)
        toggleOnOffOption(opts.drawTrail, IconShoePrints, "Draw trail", a)

      elif ke.isKeyDown(keyF12):
        toggleShowOption(opts.showThemePane, NoIcon, "Theme editor pane", a)

    # }}}
    # {{{ emExcavate, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor
    of emExcavate, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys,
                                 allowPan=false, allowJump=false, a)

      let cur = a.ui.cursor

      if cur != a.ui.lastCursor:
        if   ui.editMode == emExcavate:
          actions.excavate(map, cur, ui.currFloorColor, um)

        elif ui.editMode == emEraseCell:
          actions.eraseCell(map, cur, um)

        elif ui.editMode == emEraseTrail:
          map.setTrail(cur, false)

        elif ui.editMode == emDrawClearFloor:
          actions.drawClearFloor(map, cur, ui.currFloorColor, um)

        elif ui.editMode == emColorFloor:
          if not map.isEmpty(cur):
            actions.setFloorColor(map, cur, ui.currFloorColor, um)

      if not opts.wasdMode and ke.isKeyUp({keyD}):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isKeyUp({keyC, keyE, keyF, keyX}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir; a) =
        let cur = a.ui.cursor

        if map.canSetWall(cur, dir):
          let w = if map.getWall(cur, dir) == wWall: wNone
                  else: wWall
          actions.setWall(map, cur, dir, w, um)
        else:
          setStatusMessage(IconWarning, "Cannot set wall of an empty cell", a)

      handleMoveKeys(ke, handleMoveKey)

      if not opts.wasdMode and ke.isKeyUp({keyW}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWallSpecial
    of emDrawWallSpecial:
      proc handleMoveKey(dir: CardinalDir; a) =
        let cur = a.ui.cursor

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
        else:
          setStatusMessage(IconWarning, "Cannot set wall of an empty cell", a)

      handleMoveKeys(ke, handleMoveKey)

      if ke.isKeyUp({keyR}):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      discard handleMoveCursor(ke, MoveKeysCursor, a)

      let cur = a.ui.cursor

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

        # delete links from a previous cut to buffer operation if it hasn't
        # been pasted yet
        map.deleteLinksFromOrToLevel(CopyBufferLevelIndex)

        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            level: cur.level,
            col: bbox.c1,
            row: bbox.r1
          )
          actions.cutSelection(map, bboxTopLeft, bbox, selection,
                               linkDestLevelIndex=CopyBufferLevelIndex, um)
          ui.cutToBuffer = true

          exitSelectMode(a)

          var cur = cur
          cur.row = bbox.r1
          cur.col = bbox.c1
          setCursor(cur, a)

          setStatusMessage(IconCut, "Cut selection to buffer", a)

      elif ke.isKeyDown(keyM, {mkCtrl}):
        let selection = ui.selection.get
        let bbox = copySelection(ui.nudgeBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            level: cur.level,
            col: bbox.c1,
            row: bbox.r1
          )
          ui.moveUndoLocation = bboxTopLeft

          actions.cutSelection(map, bboxTopLeft, bbox, selection,
                               linkDestLevelIndex=MoveBufferLevelIndex, um)
          exitSelectMode(a)

          # Enter paste preview mode
          var cur = cur
          cur.row = bbox.r1
          cur.col = bbox.c1
          setCursor(cur, a)

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

      elif ke.isKeyDown(keyComma,  repeat=true): prevFloorColorAction(a)
      elif ke.isKeyDown(keyPeriod, repeat=true): nextFloorColorAction(a)

      elif ke.isKeyDown(keyEscape):
        exitSelectMode(a)
        a.clearStatusMessage()

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      discard handleMoveCursor(ke, MoveKeysCursor, a)

      let cur = a.ui.cursor

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
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      let cur = a.ui.cursor

      a.ui.drawLevelParams.selStartRow = cur.row
      a.ui.drawLevelParams.selStartCol = cur.col

      if ke.isKeyDown({keyEnter, keyP}):
        actions.pasteSelection(map, cur, ui.copyBuf.get,
                               pasteBufferLevelIndex=CopyBufferLevelIndex,
                               undoLoc=cur, um, pasteTrail=true)

        if ui.cutToBuffer: ui.copyBuf = SelectionBuffer.none

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

    # }}}
    # {{{ emMovePreview
    of emMovePreview:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      let cur = a.ui.cursor

      a.ui.drawLevelParams.selStartRow = cur.row
      a.ui.drawLevelParams.selStartCol = cur.col

      if ke.isKeyDown({keyEnter, keyP}):
        actions.pasteSelection(map, cur, ui.nudgeBuf.get,
                               pasteBufferLevelIndex=MoveBufferLevelIndex,
                               undoLoc=ui.moveUndoLocation, um,
                               groupWithPrev=true, actionName="Move selection")

        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Moved selection", a)

      elif ke.isKeyDown(keyEqual, repeat=true): incZoomLevelAction(a)
      elif ke.isKeyDown(keyMinus, repeat=true): decZoomLevelAction(a)

      elif ke.isKeyDown(keyEscape):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      handleMoveKeys(ke, moveSelStart)

      let cur = a.ui.cursor

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

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

    # }}}
    # {{{ emSetCellLink
    of emSetCellLink:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let moveKeys = if opts.wasdMode: MoveKeysWasd else: MoveKeysCursor
        discard handleMoveCursor(ke, moveKeys, a)

      if ke.isKeyDown({keyPageUp, keyKpSubtract}, repeat=true) or
         ke.isKeyDown(keyMinus, {mkCtrl}, repeat=true):
        prevLevelAction(a)

      elif ke.isKeyDown({keyPageDown, keyKpAdd}, repeat=true) or
           ke.isKeyDown(keyEqual, {mkCtrl}, repeat=true):
        nextLevelAction(a)

      let cur = a.ui.cursor

      if cur != a.ui.lastCursor:
        let floor = map.getFloor(ui.linkSrcLocation)
        setSetLinkDestinationMessage(floor, a)

      if ke.isKeyDown(keyEnter):
        if map.isEmpty(cur):
          setStatusMessage(IconWarning,
                           "Cannot set link destination to an empty cell", a)

        elif cur == ui.linkSrcLocation:
          setStatusMessage(IconWarning,
                           "Cannot set link destination to the source cell", a)
        else:
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

      elif ke.isKeyDown(keyF1):
        openUserManualAction(a)

    # }}}

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  if hasKeyEvent():
    let ke = koi.currEvent()

    if   ke.isKeyDown(keyN,        {mkCtrl, mkAlt}):   newMapAction(a)
    elif ke.isKeyDown(keyP,        {mkCtrl, mkAlt}):   openEditMapPropsDialog(a)

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

    elif ke.isKeyDown(keyF1):
      openUserManualAction(a)

# }}}

# {{{ Rendering

# {{{ renderLevel()
proc renderLevel(a) =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opts, a.opts)

  let l = currLevel(a)

  let i = instantiationInfo(fullPaths=true)
  let id = koi.generateId(i.filename, i.line, "gridmonger-level")

  updateViewStartAndCursorPosition(a)

  if ui.lastCursor != ui.cursor:
    resetManualNoteTooltip(a)

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
    if opts.walkMode and
       ui.editMode in {emNormal, emExcavate, emEraseCell, emDrawClearFloor}:
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
  const
    NoteTooltipXOffs = 16
    NoteTooltipYOffs = 20

  var mouseOverCellWithNote = false
  var note: Option[Annotation]

  if koi.isHot(id) and
     not (opts.wasdMode and isActive(id)) and
     (koi.mx() != ui.manualNoteTooltipState.mx or
      koi.my() != ui.manualNoteTooltipState.my):

    let loc = locationAtMouse(a)
    if loc.isSome:
      let loc = loc.get

      note = l.getNote(loc.row, loc.col)
      if note.isSome:
        mouseOverCellWithNote = true
        resetManualNoteTooltip(a)


  if ui.manualNoteTooltipState.show:
    let loc = ui.manualNoteTooltipState.location
    note = l.getNote(loc.row, loc.col)

  if note.isSome:
    var x, y: float

    if mouseOverCellWithNote:
      x = koi.mx() + NoteTooltipXOffs
      y = koi.my() + NoteTooltipYOffs

    elif ui.manualNoteTooltipState.show:
      x = dp.startX + viewCol(a) * dp.gridSize + NoteTooltipXOffs
      y = dp.startY + viewRow(a) * dp.gridSize + NoteTooltipYOffs

    drawNoteTooltip(x, y, note.get, a)


  a.ui.lastCursor = a.ui.cursor

# }}}
# {{{ renderToolsPane()

# {{{ specialWallDrawProc()
proc specialWallDrawProc(ls: LevelStyle,
                         ts: PaneToolbarStyle,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext, buttonIdx: Natural, label: string,
               state: WidgetState, first, last: bool,
               x, y, w, h: float, style: RadioButtonsStyle) =

    var col = case state
              of wsActive:      ls.general.cursorColor
              of wsHover:       ts.buttonHoverColor
              of wsActiveHover: ls.general.cursorColor
              of wsDown:        ls.general.cursorColor
              else:             ts.buttonColor

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let savedFloorColor = ls.floorColor.color[0]
    let savedBackgroundImage = dp.backgroundImage

    ls.floorColor.color[0] = lerp(ls.general.backgroundColor, col, col.a)
                               .withAlpha(1.0)
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

    let ot = Horiz

    case SpecialWalls[buttonIdx]
    of wNone:              discard
    of wWall:              drawSolidWallHoriz(cx, cy, ot, ctx=ctx)
    of wIllusoryWall:      drawIllusoryWallHoriz(cx+2, cy, ot, ctx=ctx)
    of wInvisibleWall:     drawInvisibleWallHoriz(cx-2, cy, ot, ctx=ctx)
    of wDoor:              drawDoorHoriz(cx, cy, ot, ctx=ctx)
    of wLockedDoor:        drawLockedDoorHoriz(cx, cy, ot, ctx=ctx)
    of wArchway:           drawArchwayHoriz(cx, cy, ot, ctx=ctx)

    of wSecretDoor:
      drawAtZoomLevel(6):  drawSecretDoorHoriz(cx-2, cy, ot, ctx=ctx)

    of wOneWayDoorNE:
      drawAtZoomLevel(8):  drawOneWayDoorHorizNE(cx-4, cy+1, ot, ctx=ctx)

    of wLeverSW:
      drawAtZoomLevel(6):  drawLeverHorizSW(cx-2, cy+1, ot, ctx=ctx)

    of wNicheSW:           drawNicheHorizSW(cx, cy, ot, floorColor=0, ctx=ctx)

    of wStatueSW:
      drawAtZoomLevel(6):  drawStatueHorizSW(cx-2, cy+2, ot, ctx=ctx)

    of wKeyhole:
      drawAtZoomLevel(6):  drawKeyholeHoriz(cx-2, cy, ot, ctx=ctx)

    of wWritingSW:
      drawAtZoomLevel(12): drawWritingHorizSW(cx-6, cy+4, ot, ctx=ctx)

    else: discard

    # ...aaaaand restore it!
    ls.floorColor.color[0] = savedFloorColor
    dp.backgroundImage = savedBackgroundImage

# }}}

proc renderToolsPane(x, y, w, h: float; a) =
  alias(ui, a.ui)

  let ls = a.doc.levelStyle
  let ts = a.theme.style.pane.toolbar

  var
    toolItemsPerColumn = 12
    toolX = x

    colorItemsPerColum = 10
    colorX = x + 3
    colorY = y + 445

  if koi.winHeight() < ToolsPaneYBreakpoint2:
    colorItemsPerColum = 5
    toolX += 30

  if koi.winHeight() < ToolsPaneYBreakpoint1:
    toolItemsPerColumn = 6
    toolX -= 30
    colorX += 3
    colorY -= 210

  # Draw special walls
  koi.radioButtons(
    x = toolX,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = SpecialWallTooltips,
    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: toolItemsPerColumn),

    drawProc = specialWallDrawProc(ls, ts, ui.toolbarDrawParams).some
  )

  # Draw floor colors
  var floorColors = newSeqOfCap[Color](ls.floorColor.color.len)

  for fc in 0..ls.floorColor.color.high:
    let c = calcBlendedFloorColor(fc, ls.floorColor.transparentFloor, ls)
    floorColors.add(c)

  koi.radioButtons(
    x = colorX,
    y = colorY,
    w = 30,
    h = 30,
    labels = newSeq[string](ls.floorColor.color.len),
    ui.currFloorColor,
    tooltips = @[],

    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: colorItemsPerColum),

    drawProc = colorRadioButtonDrawProc(floorColors,
                                        ls.general.cursorColor).some
  )

# }}}
# {{{ renderNotesPane()
proc renderNotesPane(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let s = a.theme.style.pane.notes

  let
    l = currLevel(a)
    cur = a.ui.cursor
    note = l.getNote(cur.row, cur.col)

  if note.isSome and not (a.ui.editMode in {emPastePreview, emNudgePreview}):
    let note = note.get
    if note.text == "" or note.kind == akLabel: return

    vg.save()

    case note.kind
    of akIndexed:
      drawIndexedNote(x, y-12, note.index, 36,
                      bgColor=s.indexBackgroundColor[note.indexColor],
                      fgColor=s.indexColor, vg)

    of akCustomId:
      vg.fillColor(s.textColor)
      vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+18, y-2, note.customId)

    of akIcon:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-3, NoteIcons[note.icon])

    of akComment:
      vg.fillColor(s.textColor)
      vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
      discard vg.text(x+20, y-2, IconComment)

    of akLabel: discard


    var text = note.text
    koi.textArea(x+40, y-11, w-20, h+10, text, disabled=true,
                 style=a.theme.noteTextAreaStyle)

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

  let ts = a.theme.style

  proc handleUndo() =
    discard

  macro prop(label: static[string], path: untyped): untyped =

    proc getRefObjType(sym: NimNode): NimNode =
      sym.getTypeImpl[0].getTypeImpl

    proc findProp(objType: NimNode, name: string): NimNode =
      let recList = objType[2]
      for identDef in recList:
        let propName = identDef[0].strVal
        if propName == name:
          let propType = identDef[1]
          return propType
      error("Cannot find property: " & name)

    let
      pathStr = path.repr
      pathArr = pathStr.split(".")
      sectionName = pathArr[0]
      subsectionName = pathArr[1]
      propNameWithIndex = pathArr[2]

    let
      p = propNameWithIndex.find('[')
      propName = if p > -1: propNameWithIndex.substr(0, p-1)
                 else: propNameWithIndex

    let
      rootObjType = getRefObjType(ThemeStyle.getTypeInst)
      sectionObjType = findProp(rootObjType, sectionName).getRefObjType
      subsectionObjType = findProp(sectionObjType, subsectionName).getRefObjType
      propType = findProp(subsectionObjType, propName)

    let fullPath = parseExpr("ts." & pathStr)

    result = nnkStmtList.newTree
    result.add quote do:
      koi.label(`label`)
      koi.setNextId(`pathStr`)

    if propType == Color.getTypeInst or
       # a bit hacky; all arrays are of type Color
       propType.getTypeImpl.kind == nnkBracketExpr:
      result.add quote do:
        koi.color(`fullPath`)

    elif propType == float.getTypeInst:
      let limitSym = newIdentNode(
        sectionName.capitalizeAscii() &
        subsectionName.capitalizeAscii() &
        propName.capitalizeAscii() &
        "Limits"
      )

      result.add quote do:
        # TODO limits
        koi.horizSlider(startVal=`limitSym`.minFloat,
                        endVal=`limitSym`.maxFloat,
                        `fullPath`,
                        style=ThemeEditorSliderStyle)

    elif propType == bool.getTypeInst:
      result.add quote do:
        koi.checkBox(`fullPath`)

    elif propType.getTypeImpl.kind == nnkEnumTy:
      result.add quote do:
        koi.dropDown(`fullPath`)

    else:
      echo propType.treeRepr
      error("Unknown type: " & propType.strVal)

#    echo result.repr

#[
    if te.prevState.`section`.`prop`[`index`] != ts.`section`.`prop`[`index`]:
      handleUndo()
]#


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  # {{{ User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      group:
        prop("Background",                ui.window.backgroundColor)
      group:
        prop("Title Background",          ui.window.titleBackgroundColor)
        prop("Title Background Inactive", ui.window.titleBackgroundInactiveColor)
        prop("Title",                     ui.window.titleColor)
        prop("Title Inactive",            ui.window.titleInactiveColor)
        prop("Modified Flag",             ui.window.modifiedFlagColor)
      group:
        prop("Button",                    ui.window.buttonColor)
        prop("Button Hover",              ui.window.buttonHoverColor)
        prop("Button Down",               ui.window.buttonDownColor)

    if koi.subSectionHeader("Dialog", te.sectionDialog):
      group:
        prop("Corner Radius",      ui.dialog.cornerRadius)
        prop("Title Background",   ui.dialog.titleBackgroundColor)
        prop("Title",              ui.dialog.titleColor)
        prop("Background",         ui.dialog.backgroundColor)
        prop("Label",              ui.dialog.labelColor)
        prop("Warning",            ui.dialog.warningColor)
      group:
        prop("Outer Border",       ui.dialog.outerBorderColor)
        prop("Outer Border Width", ui.dialog.outerBorderWidth)
        prop("Inner Border",       ui.dialog.innerBorderColor)
        prop("Inner Border Width", ui.dialog.innerBorderWidth)
      group:
        prop("Shadow?",            ui.dialog.shadowEnabled)
        prop("Shadow X Offset",    ui.dialog.shadowXOffset)
        prop("Shadow Y Offset",    ui.dialog.shadowYOffset)
        prop("Shadow Feather",     ui.dialog.shadowFeather)
        prop("Shadow Color",       ui.dialog.shadowColor)

    if koi.subSectionHeader("Widget", te.sectionWidget):
      group:
        prop("Corner Radius",       ui.widget.cornerRadius)
      group:
        prop("Background",          ui.widget.backgroundColor)
        prop("Background Hover",    ui.widget.backgroundHoverColor)
        prop("Background Active",   ui.widget.backgroundActiveColor)
        prop("Background Disabled", ui.widget.backgroundDisabledColor)
      group:
        prop("Foreground",          ui.widget.foregroundColor)
        prop("Foreground Active",   ui.widget.foregroundActiveColor)
        prop("Foreground Disabled", ui.widget.foregroundDisabledColor)

    if koi.subSectionHeader("Text Field", te.sectionTextField):
      group:
        prop("Edit Background",   ui.textField.editBackgroundColor)
        prop("Edit Text",         ui.textField.editTextColor)
      group:
        prop("Cursor",            ui.textField.cursorColor)
        prop("Selection",         ui.textField.selectionColor)
      group:
        prop("Scroll Bar Normal", ui.textField.scrollBarNormalColor)
        prop("Scroll Bar Edit",   ui.textField.scrollBarEditColor)

    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      group:
        prop("Background",         ui.statusBar.backgroundColor)
        prop("Text",               ui.statusBar.textColor)
      group:
        prop("Command Background", ui.statusBar.commandBackgroundColor)
        prop("Command",            ui.statusBar.commandColor)
        prop("Coordinates",        ui.statusBar.coordinatesColor)

    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      prop("Color", ui.aboutButton.labelColor)
      prop("Hover", ui.aboutButton.labelHoverColor)
      prop("Down",  ui.aboutButton.labelDownColor)


    if koi.subSectionHeader("About Dialog", te.sectionAboutDialog):
      koi.label("Logo")
      koi.color(ts.ui.aboutDialog.logoColor)
      if ts.ui.aboutDialog.logoColor != te.prevState.ui.aboutDialog.logoColor:
        a.aboutLogo.updateLogoImage = true


    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        koi.label("Logo")
        koi.color(ts.ui.splashImage.logoColor)
        if ts.ui.splashImage.logoColor != te.prevState.ui.splashImage.logoColor:
          a.splash.updateLogoImage = true

        koi.label("Outline")
        koi.color(ts.ui.splashImage.outlineColor)
        if ts.ui.splashImage.outlineColor != te.prevState.ui.splashImage.outlineColor:
          a.splash.updateOutlineImage = true

        koi.label("Shadow Alpha")
        koi.horizSlider(startVal=AlphaLimits.minFloat,
                        endVal=AlphaLimits.maxFloat,
                        ts.ui.splashImage.shadowAlpha,
                        style=ThemeEditorSliderStyle)

        if ts.ui.splashImage.shadowAlpha != te.prevState.ui.splashImage.shadowAlpha:
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      group:
        prop("Background",            level.general.backgroundColor)
      group:
        prop("Foreground",            level.general.foregroundColor)
        prop("Foreground Light",      level.general.foregroundLightColor)
        prop("Line Width",            level.general.lineWidth)
      group:
        prop("Coordinates",           level.general.coordinatesColor)
        prop("Coordinates Highlight", level.general.coordinatesHighlightColor)
      group:
        prop("Cursor",                level.general.cursorColor)
        prop("Cursor Guides",         level.general.cursorGuidesColor)
      group:
        prop("Selection",             level.general.selectionColor)
        prop("Paste Preview",         level.general.pastePreviewColor)
      group:
        prop("Link Marker",           level.general.linkMarkerColor)
      group:
        prop("Trail",                 level.general.trailColor)
      group:
        prop("Region Border",         level.general.regionBorderColor)
        prop("Region Border Empty",   level.general.regionBorderEmptyColor)

    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      prop("Background Hatch?",  level.backgroundHatch.enabled)
      prop("Hatch",              level.backgroundHatch.color)
      prop("Hatch Stroke Width", level.backgroundHatch.width)
      prop("Hatch Spacing",      level.backgroundHatch.spacingFactor)

    if koi.subSectionHeader("Grid", te.sectionGrid):
      prop("Background Grid Style", level.grid.backgroundStyle)
      prop("Background Grid",       level.grid.backgroundGridColor)
      prop("Floor Grid Style",      level.grid.floorStyle)
      prop("Floor Grid",            level.grid.floorGridColor)

    if koi.subSectionHeader("Outline", te.sectionOutline):
      prop("Style",         level.outline.style)
      prop("Fill Style",    level.outline.fillStyle)
      prop("Outline",       level.outline.color)
      prop("Outline Width", level.outline.widthFactor)
      prop("Overscan",      level.outline.overscanEnabled)

    if koi.subSectionHeader("Shadow", te.sectionShadow):
      group:
        prop("Inner Shadow",       level.shadow.innerColor)
        prop("Inner Shadow Width", level.shadow.innerWidthFactor)
      group:
        prop("Outer Shadow",       level.shadow.outerColor)
        prop("Outer Shadow Width", level.shadow.outerWidthFactor)

    if koi.subSectionHeader("Floor Colors", te.sectionFloorColors):
      prop("Transparent Floor", level.floorColor.transparentFloor)
      prop("Floor 1",           level.floorColor.color[0])
      prop("Floor 2",           level.floorColor.color[1])
      prop("Floor 3",           level.floorColor.color[2])
      prop("Floor 4",           level.floorColor.color[3])
      prop("Floor 5",           level.floorColor.color[4])
      prop("Floor 6",           level.floorColor.color[5])
      prop("Floor 7",           level.floorColor.color[6])
      prop("Floor 8",           level.floorColor.color[7])
      prop("Floor 9",           level.floorColor.color[8])
      prop("Floor 10",          level.floorColor.color[9])

    if koi.subSectionHeader("Notes", te.sectionNotes):
      group:
        prop("Marker",             level.note.markerColor)
        prop("Comment",            level.note.commentColor)
      group:
        prop("Index Background 1", level.note.indexBackgroundColor[0])
        prop("Index Background 2", level.note.indexBackgroundColor[1])
        prop("Index Background 3", level.note.indexBackgroundColor[2])
        prop("Index Background 4", level.note.indexBackgroundColor[3])
        prop("Index",              level.note.indexColor)
      group:
        prop("Tooltip Background", level.note.tooltipBackgroundColor)
        prop("Tooltip",            level.note.tooltipColor)

    if koi.subSectionHeader("Labels", te.sectionLabels):
      group:
        prop("Label Color 1", level.label.color[0])
        prop("Label Color 2", level.label.color[1])
        prop("Label Color 3", level.label.color[2])
        prop("Label Color 4", level.label.color[3])

    if koi.subSectionHeader("Level Drop Down", te.sectionLeveldropDown):
      group:
        prop("Button",               level.levelDropDown.buttonColor)
        prop("Button Hover",         level.levelDropDown.buttonHoverColor)
        prop("Button Label",         level.levelDropDown.buttonLabelColor)
      group:
        prop("Item List Background", level.levelDropDown.itemListBackgroundColor)
        prop("Item",                 level.levelDropDown.itemColor)
        prop("Item Hover",           level.levelDropDown.itemHoverColor)

  # }}}
  # {{{ Panes section
  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Notes Pane", te.sectionNotesPane):
      group:
        prop("Text",               pane.notes.textColor)
      group:
        prop("Index Background 1", pane.notes.indexBackgroundColor[0])
        prop("Index Background 2", pane.notes.indexBackgroundColor[1])
        prop("Index Background 3", pane.notes.indexBackgroundColor[2])
        prop("Index Background 4", pane.notes.indexBackgroundColor[3])
        prop("Index",              pane.notes.indexColor)
      group:
        prop("Scroll Bar",         pane.notes.scrollBarColor)

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      prop("Button ",      pane.toolbar.buttonColor)
      prop("Button Hover", pane.toolbar.buttonHoverColor)

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
  vg.strokeWidth(1.0)
  vg.lineCap(lcjSquare)

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

  var betaStyle = getDefaultLabelStyle()
  betaStyle.color = a.theme.style.ui.widget.backgroundActiveColor
  koi.label(cx + 265, cy, 40, wh, fmt"beta", style=betaStyle)

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
    a.theme.themeNames[a.theme.currThemeIndex].name,
    disabled=true
  )

  cx = x+15
  cy += 40.0

  let buttonsDisabled = koi.isDialogOpen()

  if koi.button(cx, cy, w=bw, h=wh, "New", disabled=true):
    discard

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    let theme = a.theme.themeNames[a.theme.currThemeIndex]
    let themePath = themePath(theme, a)
    # TODO
#    saveTheme(theme, themePath)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Props", disabled=true):
    discard

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete", disabled=true):
    discard

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(g_themeEditorPropsFocusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  g_themeEditorPropsFocusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  # TODO ultimately we'll do most of switchTheme here (extract etc),
  # but at the end of the frame and lazily somehow (only if something has
  # changed), because sometimes we need to precalc stuff when the style
  # changes
  updateWidgetStyles(a)

  a.theme.reinitDrawLevelParams = true

  a.win.setStyle(a.theme.style.ui.window)

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

  if not a.opts.showThemePane:
    koi.setFocusCaptured(true)

# }}}
# {{{ closeSplash()
proc closeSplash(a) =
  alias(s, a.splash)

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

  if not a.opts.showThemePane:
    koi.setFocusCaptured(false)

# }}}

# {{{ handleAutosave()
proc handleAutosave(a) =
  if a.prefs.autosave and a.doc.undoManager.isModified:
    let dt = getMonoTime() - a.doc.lastAutosaveTime
    if dt > initDuration(minutes = a.prefs.autosaveFreqMins):
      let filename = if a.doc.filename == "":
                       a.path.autosaveDir / addFileExt("Untitled", MapFileExt)
                     else: a.doc.filename

      saveMap(filename, autosave=true, a)
      a.doc.lastAutosaveTime = getMonoTime()

# }}}
# {{{ autoSaveOnCrash()
proc autoSaveOnCrash(a): string =
  var fname: string
  if a.doc.filename == "":
    let (path, _, _) = splitFile(a.doc.filename)
    fname = path
  else:
    fname = a.path.autosaveDir

  fname = fname / CrashAutosaveFilename

  info(fmt"Auto-saving map to '{fname}'")
  saveMap(fname, autosave=false, a)

  result = fname

# }}}

# {{{ Main render/UI loop

# {{{ renderUI()
proc renderUI(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(dlg, a.dialog)
  alias(map, a.doc.map)

  let winHeight = koi.winHeight()
  let uiWidth = drawAreaWidth(a)

  # Clear background
  vg.beginPath()
  vg.rect(0, TitleBarHeight, uiWidth, winHeight - TitleBarHeight)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.style.ui.window.backgroundColor)

  vg.fill()

  # About button
  if button(x = uiWidth - 55, y = 45, w = 20, h = DlgItemHeight, IconQuestion,
            style = a.theme.aboutButtonStyle, tooltip = "About"):
    openAboutDialog(a)

  if not mapHasLevels(a):
    drawEmptyMap(a)

  else:
    let levelNames = map.sortedLevelNames
    var sortedLevelIdx = currSortedLevelIdx(a)
    let prevSortedLevelIdx = sortedLevelIdx

    vg.fontSize(a.theme.levelDropDownStyle.label.fontSize)

    # Level drop-down
    let levelDropDownWidth = round(
      vg.textWidth(levelNames[sortedLevelIdx]) +
      a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
    )

    koi.dropDown(
      x = round((uiWidth - levelDropDownWidth) * 0.5),
      y = 45.0,
      w = levelDropDownWidth,
      h = 24.0,
      levelNames,
      sortedLevelIdx,
      tooltip = "",
      disabled = not (ui.editMode in {emNormal, emSetCellLink}),
      style = a.theme.levelDropDownStyle
    )

    if sortedLevelIdx != prevSortedLevelIdx:
      var cur = ui.cursor
      cur.level = map.sortedLevelIdxToLevelIdx[sortedLevelIdx]
      setCursor(cur, a)

    let l = currLevel(a)

    # Region drop-down
    if l.regionOpts.enabled:
      let currRegion = currRegion(a)
      if currRegion.isSome:
        var sortedRegionNames = l.regionNames()
        sort(sortedRegionNames)

        let currRegionName = currRegion.get.name
        var sortedRegionIdx = sortedRegionNames.find(currRegionName)
        let prevSortedRegionIdx = sortedRegionIdx

        let regionDropDownWidth = round(
          vg.textWidth(currRegionName) +
          a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
        )

        koi.dropDown(
          x = round((uiWidth - regionDropDownWidth) * 0.5),
          y = 73.0,
          w = regionDropDownWidth,
          h = 24.0,
          sortedRegionNames,
          sortedRegionIdx,
          tooltip = "",
          disabled = not (ui.editMode in {emNormal, emSetCellLink}),
          style = a.theme.levelDropDownStyle
        )

        if sortedRegionIdx != prevSortedRegionIdx :
          let currRegionName = sortedRegionNames[sortedRegionIdx]
          let (regionCoords, _) = l.findFirstRegionByName(currRegionName).get

          let (r, c) = map.getRegionCenterLocation(a.ui.cursor.level,
                                                   regionCoords)

          centerCursorAt(Location(level: ui.cursor.level, row: r, col: c), a)

    # Render level & panes
    renderLevel(a)

    if a.opts.showNotesPane:
      renderNotesPane(
        x = NotesPaneLeftPad,
        y = winHeight - StatusBarHeight - NotesPaneHeight - NotesPaneBottomPad,
        w = uiWidth - toolsPaneWidth() - NotesPaneLeftPad - NotesPaneRightPad,
        h = NotesPaneHeight,
        a
      )

    if a.opts.showToolsPane:
      renderToolsPane(
        x = uiWidth - toolsPaneWidth(),
        y = ToolsPaneTopPad,
        w = toolsPaneWidth(),
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
  if a.opts.showThemePane:
    let
      x = uiWidth
      y = TitleBarHeight
      w = ThemePaneWidth
      h = drawAreaHeight(a)

    renderThemeEditorPane(x, y, w, h, a)

  # Dialogs
  if dlg.aboutDialog.isOpen:
    aboutDialog(dlg.aboutDialog, a)

  elif dlg.preferencesDialog.isOpen:
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

  elif dlg.editRegionPropsDialog.isOpen:
    editRegionPropsDialog(dlg.editRegionPropsDialog, a)

# }}}
# {{{ renderFramePre()
proc renderFramePre(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      switchTheme(themeIndex, a)
      a.theme.themeReloaded = themeIndex == a.theme.currThemeIndex

    except CatchableError as e:
      logError(e, "Error loading theme when switching theme")
      let name = a.theme.themeNames[themeIndex].name
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
    let themeName = a.theme.themeNames[a.theme.currThemeIndex].name
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
    else:
      setStatusMessage(fmt"Switched to '{themeName}' theme", a)

  if a.theme.nextThemeIndex.isSome:
    displayThemeLoadedMessage(a)
    a.theme.nextThemeIndex = Natural.none

  proc handleWindowClose(a) =
    proc saveConfigAndExit(a) =
      savePreferences(a)
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


  # XXX HACK: If the theme pane is shown, widgets are handled first, then
  # the global shortcuts, so widget-specific shorcuts can take precedence
  var uiRendered = false
  if a.opts.showThemePane:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if mapHasLevels(a): handleGlobalKeyEvents(a)
    else:               handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.opts.showThemePane and a.win.glfwWin.focused:
      glfw.makeContextCurrent(a.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(a.win.glfwWin)
      a.win.focus()

  if not a.opts.showThemePane or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash(a) =
  alias(s, a.splash)
  alias(vg, s.vg)

  let ts = a.theme.style

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth / winWidth

  glViewport(0, 0, fbWidth, fbHeight)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth.float, winHeight.float, pxRatio)

  if s.logoImage == NoImage or s.updateLogoImage:
    colorImage(s.logo, ts.ui.splashImage.logoColor)
    if s.logoImage == NoImage:
      s.logoImage = createImage(s.logo)
    else:
      vg.updateImage(s.logoImage, cast[ptr byte](s.logo.data))
    s.updateLogoImage = false

  if s.outlineImage == NoImage or s.updateOutlineImage:
    colorImage(s.outline, ts.ui.splashImage.outlineColor)
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


  let scale = winWidth / s.logo.width

  s.logoPaint = createPattern(vg, s.logoImage, scale=scale)

  s.outlinePaint = createPattern(vg, s.outlineImage, scale=scale)

  s.shadowPaint = createPattern(vg, s.shadowImage,
                                alpha=ts.ui.splashImage.shadowAlpha,
                                scale=scale)

  vg.beginPath()
  vg.rect(0, 0, winWidth.float, winHeight.float)

  vg.fillPaint(s.shadowPaint)
  vg.fill()

  vg.fillPaint(s.outlinePaint)
  vg.fill()

  vg.fillPaint(s.logoPaint)
  vg.fill()

  vg.endFrame()


  if not a.opts.showThemePane and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.opts.showThemePane:
      not a.splash.show
    else:
      let autoClose =
        if not a.opts.showThemePane and a.prefs.autoCloseSplash:
          let dt = getMonoTime() - a.splash.t0
          koi.setFramesLeft()
          dt > initDuration(seconds = a.prefs.splashTimeoutSecs)
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

# {{{ initPaths()
proc initPaths(a) =
  alias(p, a.path)

  p.dataDir = "Data"

  const ConfigDir = "Config"
  let portableMode = dirExists(ConfigDir)

  if portableMode:
    p.userDataDir = "."
  else:
    p.userDataDir = getConfigDir() / "Gridmonger"

  p.manualDir = "Manual"
  p.autosaveDir = p.userDataDir / "Autosave"

  p.themesDir = "Themes"
  p.userThemesDir = p.userDataDir / "User Themes"

  const ImagesDir = "Images"
  p.themeImagesDir = p.themesDir / ImagesDir
  p.userThemeImagesDir = p.userThemesDir / ImagesDir

  p.logFile = p.userDataDir / "gridmonger.log"
  p.configDir = p.userDataDir / ConfigDir
  p.configFile = p.configDir / "gridmonger.cfg"

  createDir(p.userDataDir)
  createDir(p.configDir)
  createDir(p.autosaveDir)
  createDir(p.userThemesDir)
  createDir(p.userThemeImagesDir)

# }}}
# {{{ loadAndSetIcon()
proc loadAndSetIcon(a) =
  alias(p, a.path)

  var icons: array[5, wrapper.IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width = img.width.int32
    icons[idx].height = img.height.int32
    icons[idx].pixels = cast[ptr cuchar](img.data)

  var icon32 = loadImage(p.dataDir / "icon32.png")
  var icon48 = loadImage(p.dataDir / "icon48.png")
  var icon64 = loadImage(p.dataDir / "icon64.png")
  var icon128 = loadImage(p.dataDir / "icon128.png")
  var icon256 = loadImage(p.dataDir / "icon256.png")

  add(0, icon32)
  add(1, icon48)
  add(2, icon64)
  add(3, icon128)
  add(4, icon256)

  a.win.glfwWin.icons = icons

# }}}
# {{{ loadFonts()
proc loadFonts(a) =
  alias(p, a.path)

  proc loadFont(fontName: string, filename: string; a): Font =
    try:
      a.vg.createFont(fontName, filename)
    except CatchableError as e:
      logging.error(fmt"Cannot load font '{filename}'")
      raise e

  discard loadFont("sans", p.dataDir / "Roboto-Regular.ttf", a)
  let boldFont = loadFont("sans-bold", p.dataDir / "Roboto-Bold.ttf", a)
  let blackFont = loadFont("sans-black", p.dataDir / "Roboto-Black.ttf", a)
  let iconFont = loadFont("icon", p.dataDir / "GridmongerIcons.ttf", a)

  discard addFallbackFont(a.vg, boldFont, iconFont)
  discard addFallbackFont(a.vg, blackFont, iconFont)

# }}}
# {{{ createAlpha()
proc createAlpha(d: var ImageData) =
  for i in 0..<(d.width * d.height):
    # copy the R component to the alpha channel
    d.data[i*4+3] = d.data[i*4]

# }}}
# {{{ loadSplashmages()
proc loadSplashImages(a) =
  alias(s, a.splash)
  alias(p, a.path)

  s.logo    = loadImage(p.dataDir / "logo.png")
  s.outline = loadImage(p.dataDir / "logo-outline.png")
  s.shadow  = loadImage(p.dataDir / "logo-shadow.png")

  createAlpha(s.logo)
  createAlpha(s.outline)
  createAlpha(s.shadow)

# }}}
# {{{ loadAboutLogoImage()
proc loadAboutLogoImage(a) =
  alias(al, a.aboutLogo)

  al.logo = loadImage(a.path.dataDir / "logo-small.png")
  createAlpha(al.logo)

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
proc initGfx(a) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    logging.error("Error initialising OpenGL")
    quit(QuitFailure)

  let version  = cast[cstring](glGetString(GL_VERSION))
  let vendor   = cast[cstring](glGetString(GL_VENDOR))
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

  a.win = win
  a.vg = vg

# }}}
# {{{ rollLogFile(a)
proc rollLogFile(a) =
  alias(p, a.path)

  let fileNames = @[
    p.logFile & ".bak3",
    p.logFile & ".bak2",
    p.logFile & ".bak1",
    p.logFile
  ]

  for i, fname in fileNames:
    if fileExists(fname):
      if i == 0:
        discard tryRemoveFile(fname)
      else:
        try:
          moveFile(fname, fileNames[i-1])
        except CatchableError:
          discard

# }}}
# {{{ initLogger(a)
proc initLogger(a) =
  rollLogFile(a)
  var fileLog = newFileLogger(a.path.logFile,
                              fmtStr="[$levelname] $date $time - ",
                              levelThreshold=lvlDebug)
  addHandler(fileLog)

# }}}
# {{{ initApp()
proc initApp(a) =
  let cfg = loadAppConfigOrDefault(a.path.configFile)
  a.prefs = cfg.prefs

  loadFonts(a)
  loadAndSetIcon(a)
  setDefaultWidgetStyles(a)

  a.doc.undoManager = newUndoManager[Map, UndoStateData]()
  a.ui.drawLevelParams = newDrawLevelParams()

  searchThemes(a)
  var themeIndex = findThemeIndex(cfg.app.themeName, a)
  if themeIndex == -1: themeIndex = 0
  switchTheme(themeIndex, a)

  a.opts.showNotesPane = cfg.app.showNotesPane
  a.opts.showToolsPane = cfg.app.showToolsPane
  a.opts.drawTrail = cfg.app.drawTrail
  a.opts.walkMode = cfg.app.walkMode
  a.opts.wasdMode = cfg.app.wasdMode

  a.ui.drawLevelParams.drawCellCoords = cfg.app.showCellCoords
  a.ui.drawLevelParams.setZoomLevel(a.doc.levelStyle, cfg.app.zoomLevel)

  if a.prefs.loadLastMap and cfg.misc.lastMapFileName != "":
    if not loadMap(cfg.misc.lastMapFileName, a):
      a.doc.map = newMap("Untitled Map")
  else:
    a.doc.map = newMap("Untitled Map")
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  # TODO check values?
  # TODO timestamp check to determine whether to read the DISP info from the
  # conf or from the file
  a.ui.drawLevelParams.viewStartRow = cfg.app.viewStartRow
  a.ui.drawLevelParams.viewStartCol = cfg.app.viewStartCol

  if cfg.app.currLevel > a.doc.map.levels.high:
    a.ui.cursor.level = 0
    a.ui.cursor.row = 0
    a.ui.cursor.col = 0
  else:
    a.ui.cursor.level = cfg.app.currLevel
    a.ui.cursor.row = cfg.app.cursorRow
    a.ui.cursor.col = cfg.app.cursorCol

  updateLastCursorViewCoords(a)

  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  a.splash.show = a.prefs.showSplash
  a.splash.t0 = getMonoTime()
  setSwapInterval(a)

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePre(g_app)
  a.win.renderFrameCb = proc (win: CSDWindow) = renderFrame(g_app)

  # Set window size & position
  let (_, _, maxWidth, maxHeight) = getPrimaryMonitor().workArea

  let width  = cfg.win.width
  let height = cfg.win.height

  var xpos = cfg.win.xpos
  if xpos < 0: xpos = (maxWidth - width) div 2

  var ypos = cfg.win.ypos
  if ypos < 0: ypos = (maxHeight - height) div 2

  a.win.size = (width.int, height.int)
  a.win.pos = (xpos, ypos)

  if cfg.win.maximized:
    a.win.maximize()

  a.win.show()

# }}}
# {{{ createSplashWindow()
proc createSplashWindow(mousePassthru: bool = false; a) =
  alias(s, a.splash)

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

  nvgDeleteContext(a.vg)
  if a.splash.vg != nil:
    nvgDeleteContext(a.splash.vg)

  a.win.glfwWin.destroy()
  if a.splash.win != nil:
    a.splash.win.destroy()

  glfw.terminate()

  info("Cleanup successful, bye!")

# }}}
# {{{ crashHandler() =
proc crashHandler(e: ref Exception, a) =
  let doAutosave = a.doc.filename != ""
  var crashAutosavePath = ""

  if doAutosave:
    try:
      crashAutosavePath = autoSaveOnCrash(a)
    except Exception as e:
      logError(e, "Error autosaving map on crash")

  var msg = "A fatal error has occured, Gridmonger will now exit.\n\n"

  if doAutoSave:
    if crashAutosavePath == "":
      msg &= fmt"Autosaving the map has been unsuccesful.\n\n"
    else:
      msg &= "The map has been successfully autosaved as '" &
             crashAutosavePath & "'\n\n"

    msg &= "If the problem persists, please refer to the 'Reporting " &
           "problems' section of the user manual to report the issue."

  when not defined(DEBUG):
    discard osdialog_message(mblError, mbbOk, msg)

  logError(e, "An unexpected error has occured, the application will now exit")

  quit(QuitFailure)

# }}}
# }}}

# {{{ main()
proc main() =
  g_app = new AppContext
  var a = g_app

  initPaths(a)
  initLogger(a)

  info(fmt"Gridmonger v{AppVersion} ({BuildGitHash}), " &
       fmt"compiled at {CompileDate} {CompileTime}")

  info(fmt"Paths: {a.path}")

  try:
    initGfx(a)
    initApp(a)

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)

      if a.aboutLogo.logo.data == nil:
        loadAboutLogoImage(a)

      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthru = a.opts.showThemePane, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.opts.showThemePane:
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
    crashHandler(e, a)

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
