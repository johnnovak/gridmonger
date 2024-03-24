# {{{ Imports

import std/algorithm
import std/exitprocs
import std/browsers
import std/lenientops
import std/logging
import std/macros
import std/math
import std/options
import std/os
import std/sequtils
import std/sets
import std/monotimes
import std/streams
import std/strformat
import std/strutils except strip, splitWhitespace
import std/tables
import std/times
import std/unicode

import deps/with
import glad/gl

import glfw
from glfw/wrapper import IconImageObj

import koi
import koi/undomanager
from koi/utils as koiUtils import lerp, invLerp, remap

import nanovg
when not defined(DEBUG): import osdialog

import actions
import cmdline
import converters
import cfghelper
import common
import csdwindow
import drawlevel
import fieldlimits
import hocon
import icons
import level
import map
import persistence
import rect
import selection
import theme
import utils as gmUtils

when defined(windows):
  import platform/windows/appevents
  import platform/windows/console

elif defined(macosx):
  import platform/macos/appevents

# }}}

# {{{ Resources

when defined(windows):
  const arch = when defined(i386): "32" else: "64"
  {.link: fmt"extras/appicons/windows/gridmonger{arch}.res".}

# }}}

# {{{ Constants
const
  ThemeExt = "gmtheme"
  MapFileExt = "gmm"
  BackupFileExt = "bak"

when not defined(DEBUG):
  const
    GridmongerMapFileFilter = fmt"Gridmonger Map (*.{MapFileExt}):{MapFileExt}"

    CrashAutosaveFilename = addFileExt("Crash Autosave", MapFileExt)

const
  CursorJump   = 5
  ScrollMargin = 3

const
  DefaultWindowWidth       = 700
  DefaultWindowHeight      = 800

  StatusBarHeight          = 26.0

  LevelTopPad_Regions      = 28.0

  LevelTopPad_Coords       = 85.0
  LevelRightPad_Coords     = 50.0
  LevelBottomPad_Coords    = 40.0
  LevelLeftPad_Coords      = 50.0

  LevelTopPad_NoCoords     = 65.0
  LevelRightPad_NoCoords   = 28.0
  LevelBottomPad_NoCoords  = 10.0
  LevelLeftPad_NoCoords    = 28.0

  CurrentNotePaneHeight    = 72.0
  CurrentNotePaneTopPad    = 0.0
  CurrentNotePaneRightPad  = 26.0
  CurrentNotePaneBottomPad = 16.0
  CurrentNotePaneLeftPad   = 14.0

  NotesListPaneWidth       = 300.0

  ToolsPaneWidthNarrow     = 60.0
  ToolsPaneWidthWide       = 90.0
  ToolsPaneTopPad          = 65.0
  ToolsPaneBottomPad       = 30.0
  ToolsPaneYBreakpoint1    = 709.0
  ToolsPaneYBreakpoint2    = 859.0

  ThemePaneWidth           = 326.0

const
  SplashTimeoutSecsLimits* = intLimits(min=1, max=10)
  AutosaveFreqMinsLimits*  = intLimits(min=1, max=30)
  WindowWidthLimits*       = intLimits(MinWindowWidth, max=20_000)
  WindowHeightLimits*      = intLimits(MinWindowHeight, max=20_000)

const
  WarningMessageTimeout = initDuration(seconds = 3)
  InfiniteDuration      = initDuration(seconds = int64.high)

const
  SpecialWallTooltips = SpecialWalls.mapIt(($it).title())

  FloorGroup1 = @[
    fDoor,
    fLockedDoor,
    fArchway
  ]

  FloorGroup2 = @[
    fSecretDoor,
    fSecretDoorBlock,
    fOneWayDoor1,
    fOneWayDoor2
  ]

  FloorGroup3 = @[
    fPressurePlate,
    fHiddenPressurePlate
  ]

  FloorGroup4 = @[
    fClosedPit,
    fOpenPit,
    fHiddenPit,
    fCeilingPit
  ]

  FloorGroup5 = @[
    fTeleportSource,
    fTeleportDestination,
    fSpinner,
    fInvisibleBarrier
  ]

  FloorGroup6 = @[
    fStairsDown,
    fStairsUp,
    fEntranceDoor,
    fExitDoor
  ]

  FloorGroup7 = @[
    fBridge
  ]

  FloorGroup8 = @[
    fColumn,
    fStatue
  ]

# }}}
# {{{ AppShortcut

type AppShortcut = enum
  # General
  scNextTextField
  scAccept
  scCancel
  scDiscard
  scUndo
  scRedo

  # Maps
  scNewMap
  scOpenMap
  scSaveMap
  scSaveMapAs
  scEditMapProps

  # Levels
  scNewLevel
  scDeleteLevel
  scEditLevelProps
  scResizeLevel

  # Regions
  scEditRegionProps

  # Themes
  scReloadTheme
  scPreviousTheme
  scNextTheme

  # Editing
  scCycleFloorGroup1Forward
  scCycleFloorGroup2Forward
  scCycleFloorGroup3Forward
  scCycleFloorGroup4Forward
  scCycleFloorGroup5Forward
  scCycleFloorGroup6Forward
  scCycleFloorGroup7Forward
  scCycleFloorGroup8Forward

  scCycleFloorGroup1Backward
  scCycleFloorGroup2Backward
  scCycleFloorGroup3Backward
  scCycleFloorGroup4Backward
  scCycleFloorGroup5Backward
  scCycleFloorGroup6Backward
  scCycleFloorGroup7Backward
  scCycleFloorGroup8Backward

  scExcavateTunnel
  scEraseCell
  scDrawClearFloor
  scToggleFloorOrientation

  scSetFloorColor
  scPickFloorColor
  scPreviousFloorColor
  scNextFloorColor

  scSelectFloorColor1
  scSelectFloorColor2
  scSelectFloorColor3
  scSelectFloorColor4
  scSelectFloorColor5
  scSelectFloorColor6
  scSelectFloorColor7
  scSelectFloorColor8
  scSelectFloorColor9
  scSelectFloorColor10

  scDrawWall
  scDrawWallRepeat
  scDrawSpecialWall
  scPreviousSpecialWall
  scNextSpecialWall

  scSelectSpecialWall1
  scSelectSpecialWall2
  scSelectSpecialWall3
  scSelectSpecialWall4
  scSelectSpecialWall5
  scSelectSpecialWall6
  scSelectSpecialWall7
  scSelectSpecialWall8
  scSelectSpecialWall9
  scSelectSpecialWall10
  scSelectSpecialWall11
  scSelectSpecialWall12

  scEraseTrail
  scExcavateTrail
  scClearTrail

  scJumpToLinkedCell
  scLinkCell

  scPreviousLevel
  scNextLevel

  scZoomIn
  scZoomOut

  scMarkSelection
  scPaste
  scPastePreview
  scNudgePreview
  scPasteAccept

  scEditNote
  scEraseNote
  scEditLabel
  scEraseLabel

  scShowNoteTooltip

  # Select mode
  scSelectionDraw
  scSelectionErase
  scSelectionAll
  scSelectionNone
  scSelectionAddRect
  scSelectionSubRect
  scSelectionCopy
  scSelectionMove
  scSelectionEraseArea
  scSelectionFillArea
  scSelectionSurroundArea
  scSelectionSetFloorColorArea
  scSelectionCropArea

  # Options
  scToggleCellCoords
  scToggleCurrentNotePane
  scToggleNotesListPane
  scToggleToolsPane
  scToggleWalkMode
  scToggleWasdMode
  scToggleDrawTrail
  scToggleTitleBar
  scTogglePasteWraparound

  # Misc
  scShowAboutDialog
  scOpenUserManual
  scToggleThemeEditor
  scEditPreferences
  scToggleQuickReference

# }}}
# {{{ AppContext

type
  AppContext = ref object
    win:         CSDWindow
    vg:          NVGContext

    prefs:       Preferences
    paths:       Paths

    doc:         Document
    opts:        Options
    ui:          UIState
    dialogs:     Dialogs

    theme:       Theme
    themeEditor: ThemeEditor
    quickRef:    QuickRef
    splash:      Splash
    aboutLogo:   AboutLogo

    shouldClose: bool
    updateUI:    bool

    logFile:     File


  WalkCursorMode = enum
    wcmStrafe = (0, "Strafe")
    wcmTurn   = (1, "Turn")

  WalkKeys = object
    forward, backward, strafeLeft, strafeRight, turnLeft, turnRight: set[Key]


  Preferences = object
    showSplash:         bool
    autoCloseSplash:    bool
    splashTimeoutSecs:  Natural

    loadLastMap:        bool
    vsync:              bool

    autosave*:          bool
    autosaveFreqMins:   Natural

    movementWraparound: bool
    openEndedExcavate:  bool
    walkCursorMode:     WalkCursorMode
    yubnMovementKeys:   bool


  Paths = object
    appDir:             string
    dataDir:            string
    logDir:             string
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
    path:               string
    map:                Map
    undoManager:        UndoManager[Map, UndoStateData]
    lastAutosaveTime:   MonoTime

  Options = object
    showCurrentNotePane:  bool
    showNotesListPane:    bool
    showToolsPane:        bool

    drawTrail:            bool
    walkMode:             bool
    wasdMode:             bool

    pasteWraparound:      bool

    showThemeEditor:      bool
    showQuickReference:   bool


  UIState = object
    shortcuts:          Table[AppShortcut, seq[KeyShortcut]]
    quickRefShortcuts:  seq[seq[seq[QuickRefItem]]]
    status:             StatusMessage
    notesListState:     NotesListState

    editMode:           EditMode
    # to restore the previous edit mode when exiting emPanLevel
    prevEditMode:       EditMode

    # Navigation
    # ----------
    cursor:             Location
    prevCursor:         Location
    cursorOrient:       CardinalDir           # used by Walk Mode
    prevMoveDir:        Option[CardinalDir]   # used by the exacavate tool

    walkKeysWasd:       WalkKeys
    walkKeysCursor:     WalkKeys

    panLevelMode:       PanLevelMode

    # Tools
    # -----
    currSpecialWall:         range[0..SpecialWalls.high]
    currFloorColor:          range[0..LevelTheme.floorBackgroundColor.high]

    drawWallRepeatAction:    DrawWallRepeatAction
    drawWallRepeatWall:      Wall
    drawWallRepeatDirection: CardinalDir

    # Selections
    # ----------
    selection:          Option[Selection]
    selRect:            Option[SelectionRect]
    copyBuf:            Option[SelectionBuffer]
    nudgeBuf:           Option[SelectionBuffer]
    pasteUndoLocation:  Location

    # Mouse handling
    # --------------
    mouseCanStartExcavate:  bool
    mouseDragStartX:        float
    mouseDragStartY:        float

    # Cell linking
    # ------------
    linkSrcLocation:        Location
    jumpToDestLocation:     Location
    jumpToSrcLocations:     seq[Location]
    jumpToSrcLocationIdx:   Natural
    lastJumpToSrcLocation:  Location
    wasDrawingTrail:        bool

    # Drawing
    # -------
    drawLevelParams:        DrawLevelParams
    toolbarDrawParams:      DrawLevelParams

    # used by the zooming logic
    prevCursorViewX:        float
    prevCursorViewY:        float

    levelDrawAreaWidth:     float
    levelDrawAreaHeight:    float

    backgroundImage:        Option[Paint]

    manualNoteTooltipState: ManualNoteTooltipState


  ManualNoteTooltipState = object
    show:     bool
    location: Location
    mx:       float
    my:       float


  NotesListState = object
    currFilter:     NotesListFilter
    prevFilter:     NotesListFilter
    showCoords:     bool
    currentRegion:  bool
    linkCursor:     bool
    cache:          seq[NotesListCacheEntry]
    dirty:          bool

  NotesListCacheEntry = object
    id:             ItemId
    row, col:       Natural
    height:         float

  NotesListFilter = object
    typeFilter:     seq[NoteTypeFilter]
    order:          NoteOrder
    searchTerm:     string

  NoteTypeFilter = enum
    nftNone   = "None"
    nftNumber = "Num"
    nftId     = "ID"
    nftIcon   = "Icon"

  NoteOrder = enum
    nfoType   = "Type"
    nfoText   = "Text"


  StatusMessage = object
    icon:           string
    message:        string
    commands:       seq[string]
    warning:        string
    warningColor:   Color
    warningT0:      MonoTime
    warningTimeout: Duration

    keepMessageAfterWarningExpired:  bool


  EditMode = enum
    emNormal
    emColorFloor
    emDrawClearFloor
    emDrawSpecialWall
    emDrawSpecialWallRepeat
    emDrawWall
    emDrawWallRepeat
    emEraseCell
    emEraseTrail
    emExcavateTunnel
    emMovePreview
    emNudgePreview
    emPastePreview
    emSelect
    emSelectDraw
    emSelectErase
    emSelectRect
    emSetCellLink,
    emSelectJumpToLinkSrc

    # Special "momentary" mode; after exiting emPanLevel, the previous edit
    # mode is restored.
    emPanLevel

  PanLevelMode = enum
    dlmCtrlLeftButton
    dlmMiddleButton

  DrawWallRepeatAction = enum
    dwaNone  = "none"
    dwaSet   = "set"
    dwaClear = "clear"

  Theme = object
    config:                   HoconNode
    prevConfig:               HoconNode

    themeNames:               seq[ThemeName]
    currThemeIndex:           Natural
    nextThemeIndex:           Option[Natural]
    hideThemeLoadedMessage:   bool
    themeReloaded:            bool
    updateTheme:              bool
    loadBackgroundImage:      bool

    labelStyle:               LabelStyle
    buttonStyle:              ButtonStyle
    radioButtonStyle:         RadioButtonsStyle
    dropDownStyle:            DropDownStyle
    checkBoxStyle:            CheckboxStyle
    textFieldStyle:           TextFieldStyle
    textAreaStyle:            TextAreaStyle
    dialogStyle:              DialogStyle

    aboutDialogStyle:         DialogStyle
    aboutButtonStyle:         ButtonStyle

    iconRadioButtonsStyle:    RadioButtonsStyle
    warningLabelStyle:        LabelStyle
    errorLabelStyle:          LabelStyle

    levelDropDownStyle:       DropDownStyle
    noteTextAreaStyle:        TextAreaStyle
    notesListScrollViewStyle: ScrollViewStyle

    windowTheme:              WindowTheme
    statusBarTheme:           StatusBarTheme
    notesPaneTheme:           NotesPaneTheme
    toolbarPaneTheme:         ToolbarPaneTheme
    levelTheme:               LevelTheme


  ThemeName = object
    name:      string
    userTheme: bool
    override:  bool

  Dialog = enum
    dlgNone

    dlgAboutDialog
    dlgPreferencesDialog

    dlgSaveDiscardMapDialog

    dlgNewMapDialog
    dlgEditMapPropsDialog

    dlgNewLevelDialog
    dlgEditLevelPropsDialog
    dlgResizeLevelDialog
    dlgDeleteLevelDialog

    dlgEditNoteDialog
    dlgEditLabelDialog

    dlgEditRegionPropsDialog

    dlgSaveDiscardThemeDialog
    dlgCopyThemeDialog
    dlgRenameThemeDialog
    dlgOverwriteThemeDialog
    dlgDeleteThemeDialog


  Dialogs = object
    activeDialog:           Dialog

    aboutDialog:            AboutDialogParams
    preferencesDialog:      PreferencesDialogParams

    saveDiscardMapDialog:   SaveDiscardMapDialogParams

    newMapDialog:           NewMapDialogParams
    editMapPropsDialog:     EditMapPropsDialogParams

    newLevelDialog:         LevelPropertiesDialogParams
    editLevelPropsDialog:   LevelPropertiesDialogParams
    resizeLevelDialog:      ResizeLevelDialogParams

    editNoteDialog:         EditNoteDialogParams
    editLabelDialog:        EditLabelDialogParams

    editRegionPropsDialog:  EditRegionPropsParams

    saveDiscardThemeDialog: SaveDiscardThemeDialogParams
    copyThemeDialog:        CopyThemeDialogParams
    renameThemeDialog:      RenameThemeDialogParams
    overwriteThemeDialog:   OverwriteThemeDialogParams


  AboutDialogParams = object
    logoPaint:    Paint
    outlinePaint: Paint
    shadowPaint:  Paint


  PreferencesDialogParams = object
    activeTab:          Natural
    activateFirstTextField: bool

    # Startup tab
    showSplash:         bool
    autoCloseSplash:    bool
    splashTimeoutSecs:  string
    loadLastMap:        bool

    # General tab
    autosave:           bool
    autosaveFreqMins:   string
    vsync:              bool

    # Editing tab
    movementWraparound: bool
    openEndedExcavate:  bool
    walkCursorMode:     WalkCursorMode
    yubnMovementKeys:   bool


  SaveDiscardMapDialogParams = object
    nextAction:   proc (a: var AppContext)


  NewMapDialogParams = object
    activeTab:    Natural
    activateFirstTextField: bool

    title:        string
    game:         string
    author:       string

    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  EditMapPropsDialogParams = object
    activeTab:    Natural
    activateFirstTextField: bool

    title:        string
    game:         string
    author:       string

    origin:       Natural
    rowStyle:     Natural
    columnStyle:  Natural
    rowStart:     string
    columnStart:  string
    notes:        string


  LevelPropertiesDialogParams = object
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
    notes:              string


  ResizeLevelDialogParams = object
    activateFirstTextField: bool

    rows:         string
    cols:         string
    anchor:       ResizeAnchor


  ResizeAnchor = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


  EditNoteDialogParams = object
    activateFirstTextField: bool
    editMode:     bool
    row:          Natural
    col:          Natural
    kind:         AnnotationKind
    index:        Natural
    indexColor:   range[0..LevelTheme.noteIndexBackgroundColor.high]
    customId:     string
    icon:         range[0..NoteIcons.high]
    text:         string


  EditLabelDialogParams = object
    activateFirstTextField: bool
    editMode:     bool
    row:          Natural
    col:          Natural
    text:         string
    color:        Natural


  EditRegionPropsParams = object
    activateFirstTextField: bool
    name:         string
    notes:        string

  SaveDiscardThemeDialogParams = object
    nextAction:   proc (a: var AppContext)

  CopyThemeDialogParams = object
    activateFirstTextField: bool
    newThemeName: string

  RenameThemeDialogParams = object
    activateFirstTextField: bool
    newThemeName: string


  OverwriteThemeDialogParams = object
    themeName:    string
    nextAction:   proc (a: var AppContext)


  ThemeEditor = object
    modified:                bool

    sectionUserInterface:    bool
    sectionWidget:           bool
    sectionDropDown:         bool
    sectionTextField:        bool
    sectionDialog:           bool
    sectionTitleBar:         bool
    sectionStatusBar:        bool
    sectionLevelDropDown:    bool
    sectionAboutButton:      bool
    sectionAboutDialog:      bool
    sectionQuickHelp:        bool
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

    focusCaptured:           bool


  QuickRef = object
    activeTab:    Natural


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


  QuickRefItemKind = enum
    qkShortcut, qkKeyShortcuts, qkCustomShortcuts, qkDescription, qkSeparator

  QuickRefItem = object
    sepa: char
    case kind: QuickRefItemKind
    of qkShortcut:        shortcut:        AppShortcut
    of qkKeyShortcuts:    keyShortcuts:    seq[KeyShortcut]
    of qkCustomShortcuts: customShortcuts: seq[string]
    of qkDescription:     description:     string
    of qkSeparator:      discard


var g_app: AppContext

using a: var AppContext

# }}}
# {{{ Quick keyboard reference definitions

proc sc(sc: AppShortcut): QuickRefItem =
  QuickRefItem(kind: qkShortcut, shortcut: sc)

proc sc(sc: seq[AppShortcut], sepa = '/'; a): QuickRefItem =
  var shortcuts: seq[KeyShortcut] = @[]
  for s in sc: shortcuts.add(a.ui.shortcuts[s][0])
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: shortcuts, sepa: sepa)

proc sc(sc: KeyShortcut): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: @[sc])

proc sc(sc: seq[KeyShortcut], sepa = '/'): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: sc, sepa: sepa)

proc csc(s: seq[string]): QuickRefItem =
  QuickRefItem(kind: qkCustomShortcuts, customShortcuts: s)

proc desc(s: string): QuickRefItem =
  QuickRefItem(kind: qkDescription, description: s)

const QuickRefSepa = QuickRefItem(kind: qkSeparator)

# {{{ mkQuickRefGeneral()
func mkQuickRefGeneral(a): seq[seq[QuickRefItem]] =
  @[
    @[
      scShowAboutDialog.sc,      "Show about dialog".desc,
      scToggleQuickReference.sc, "Toggle quick keyboard reference".desc,
      scOpenUserManual.sc,       "Open user manual in browser".desc,
      scEditPreferences.sc,      "Preferences".desc,
      QuickRefSepa,

      scNewMap.sc,            "New map".desc,
      scOpenMap.sc,           "Open map".desc,
      scSaveMap.sc,           "Save map".desc,
      scSaveMapAs.sc,         "Save map as".desc,
      scEditMapProps.sc,      "Edit map properties".desc,
      QuickRefSepa,

      scNewLevel.sc,          "New level".desc,
      scEditLevelProps.sc,    "Edit level properties".desc,
      scEditRegionProps.sc,   "Edit region properties".desc,
      scDeleteLevel.sc,       "Delete level".desc,
      QuickRefSepa,

      scPreviousLevel.sc,     "Previous level".desc,
      scNextLevel.sc,         "Next level".desc,
    ],
    @[
      scUndo.sc,              "Undo last action".desc,
      scRedo.sc,              "Redo last action".desc,

      @[scZoomIn,
        scZoomOut].sc(a=a),   "Zoom in/out".desc,
      QuickRefSepa,

      scToggleWalkMode.sc,        "Toggle walk mode".desc,
      scToggleWasdMode.sc,        "Toggle WASD mode".desc,
      scShowNoteTooltip.sc,       "Toggle display note tooltip".desc,
      scToggleCellCoords.sc,      "Toggle cell coordinates".desc,
      scToggleCurrentNotePane.sc, "Toggle current note pane".desc,
      scToggleNotesListPane.sc,   "Toggle notes list pane".desc,
      scToggleToolsPane.sc,       "Toggle tools pane".desc,
      scToggleTitleBar.sc,        "Toggle title bar".desc,
      QuickRefSepa,

      scPreviousTheme.sc,     "Previous theme".desc,
      scNextTheme.sc,         "Next theme".desc,
      scReloadTheme.sc,       "Reload current theme".desc,
      scToggleThemeEditor.sc, "Toggle theme editor".desc,
    ]
  ]

# }}}
# {{{ mkQuickRefEditing()
func mkQuickRefEditing(a): seq[seq[QuickRefItem]] =
  @[
    @[
      scExcavateTunnel.sc,      "Excavate (draw) tunnel".desc,
      scEraseCell.sc,           "Erase cell (clear floor & walls)".desc,
      scDrawClearFloor.sc,      "Draw/clear floor".desc,
      scToggleFloorOrientation.sc, "Toggle floor orientation".desc,
      QuickRefSepa,

      scDrawWall.sc,            "Draw/clear wall".desc,
      scDrawSpecialWall.sc,     "Draw/clear special wall".desc,

      @[scPreviousSpecialWall,
        scNextSpecialWall].sc(a=a), "Previous/next special wall".desc,
      QuickRefSepa,

      @[scPreviousFloorColor,
        scNextFloorColor].sc(a=a), "Previous/next floor colour".desc,

      scSetFloorColor.sc,       "Set floor colour".desc,
      scPickFloorColor.sc,      "Pick floor colour".desc,
      QuickRefSepa,

      scToggleDrawTrail.sc,     "Toggle trail mode".desc,
      scExcavateTrail.sc,       "Excavate trail in current level".desc,
      scClearTrail.sc,          "Clear trail in current level".desc,
      scEraseTrail.sc,          "Erase trail".desc,
      QuickRefSepa,

      scMarkSelection.sc,       "Enter select (mark) mode".desc,
      scPaste.sc,               "Paste copy buffer contents".desc,
      scPastePreview.sc,        "Enter paste preview mode".desc,
      QuickRefSepa,

      scEditNote.sc,            "Create/edit note".desc,
      scEraseNote.sc,           "Erase note".desc,
      scEditLabel.sc,           "Create/edit label".desc,
      scEraseLabel.sc,          "Erase label".desc,
      QuickRefSepa,

    ],
    @[
      scJumpToLinkedCell.sc,    "Jump to other side of link".desc,
      scLinkCell.sc,            "Set link destination".desc,
      QuickRefSepa,

      scResizeLevel.sc,         "Resize level".desc,
      scNudgePreview.sc,        "Nudge level".desc,
      QuickRefSepa,

      @[scCycleFloorGroup1Forward,
        scCycleFloorGroup1Backward].sc(a=a), "Cycle door".desc,

      @[scCycleFloorGroup2Forward,
        scCycleFloorGroup2Backward].sc(a=a), "Cycle special door".desc,

      @[scCycleFloorGroup3Forward,
        scCycleFloorGroup3Backward].sc(a=a), "Cycle pressure plate".desc,

      @[scCycleFloorGroup4Forward,
        scCycleFloorGroup4Backward].sc(a=a), "Cycle pit".desc,

      @[scCycleFloorGroup5Forward,
        scCycleFloorGroup5Backward].sc(a=a), "Cycle special".desc,

      @[scCycleFloorGroup6Forward,
        scCycleFloorGroup6Backward].sc(a=a), "Cycle entry/exit".desc,

      @[scCycleFloorGroup7Forward,
        scCycleFloorGroup7Backward].sc(a=a), "Draw bridge".desc,

      @[scCycleFloorGroup8Forward,
        scCycleFloorGroup8Backward].sc(a=a), "Cycle column/statue".desc,

      QuickRefSepa,

      scSelectSpecialWall1.sc,  "Set special wall: Open door".desc,
      scSelectSpecialWall2.sc,  "Set special wall: Locked door".desc,
      scSelectSpecialWall3.sc,  "Set special wall: Archway".desc,
      scSelectSpecialWall4.sc,  "Set special wall: Secret door".desc,
      scSelectSpecialWall5.sc,  "Set special wall: One-way door".desc,
      scSelectSpecialWall6.sc,  "Set special wall: Illusory wall".desc,
      scSelectSpecialWall7.sc,  "Set special wall: Invisible wall".desc,
      scSelectSpecialWall8.sc,  "Set special wall: Lever".desc,
      scSelectSpecialWall9.sc,  "Set special wall: Niche".desc,
      scSelectSpecialWall10.sc, "Set special wall: Statue".desc,
      scSelectSpecialWall11.sc, "Set special wall: Keyhole".desc,
      scSelectSpecialWall12.sc, "Set special wall: Writing".desc,
      QuickRefSepa,
    ]
  ]

# }}}
# {{{ mkQuickRefDialogs()
func mkQuickRefDialogs(a): seq[seq[QuickRefItem]] =
  @[
    @[
      @[fmt"Ctrl+{IconArrowsHoriz}"].csc, "Move between tabs".desc,

      @[KeyShortcut(key: key1, mods: {mkCtrl}),
        KeyShortcut(key: key9, mods: {mkCtrl})].sc(sepa='-'), "Select tab 1-9".desc,
      QuickRefSepa,

      KeyShortcut(key: keyTab,
                  mods: {mkShift}).sc, "Previous text input field".desc,

      scNextTextField.sc, "Next text input field".desc,
      QuickRefSepa,

      @[fmt"{IconArrowsAll}"].csc, "Change radio button selection".desc,
      QuickRefSepa,

      scAccept.sc,  "Confirm (OK, Save, etc.)".desc,
      scCancel.sc,  "Cancel".desc,
      scDiscard.sc, "Discard".desc,
    ]
  ]

# }}}

func mkQuickRefShortcuts(a): seq[seq[seq[QuickRefItem]]] =
  @[
    mkQuickRefGeneral(a),
    mkQuickRefEditing(a),
    mkQuickRefDialogs(a)
  ]

# }}}
# {{{ Keyboard shortcuts

type MoveKeys = object
  left, right, up, down: set[Key]

const
  MoveKeysCursor = MoveKeys(
    left:  {keyLeft,     keyH, keyKp4},
    right: {keyRight,    keyL, keyKp6},
    up:    {keyUp,       keyK, keyKp8},
    down:  {Key.keyDown, keyJ, keyKp2, keyKp5}
  )

  MoveKeysWasd = MoveKeys(
    left:  MoveKeysCursor.left  + {keyA},
    right: MoveKeysCursor.right + {keyD},
    up:    MoveKeysCursor.up    + {keyW},
    down:  MoveKeysCursor.down  + {Key.keyS}
  )

type DiagonalMoveKeys = object
  upLeft, upRight, downLeft, downRight: set[Key]

const
  DiagonalMoveKeysCursor = DiagonalMoveKeys(
    upLeft:    {keyY, keyKp7},
    upRight:   {keyU, keyKp9},
    downLeft:  {keyB, keyKp1},
    downRight: {keyN, keyKp3}
  )

func `+`(a: WalkKeys, b: WalkKeys): WalkKeys =
  result = WalkKeys(
    forward:     a.forward     + b.forward,
    backward:    a.backward    + b.backward,
    strafeLeft:  a.strafeLeft  + b.strafeLeft,
    strafeRight: a.strafeRight + b.strafeRight,
    turnLeft:    a.turnLeft    + b.turnLeft,
    turnRight:   a.turnRight   + b.turnRight
  )

const
  WalkKeysCursorStrafe = WalkKeys(
    forward:     {keyUp},
    backward:    {Key.keyDown},
    strafeLeft:  {keyLeft},
    strafeRight: {keyRight},

    # Alt+Left/Right for turning is handled as a special case
    turnLeft:    {},
    turnRight:   {}
  )

  WalkKeysCursorTurn = WalkKeys(
    forward:     {keyUp},
    backward:    {Key.keyDown},
    turnLeft:    {keyLeft},
    turnRight:   {keyRight},

    # Alt+Left/Right for strafing is handled as a special case
    strafeLeft:  {},
    strafeRight: {}
  )

  WalkKeysKeypad = WalkKeys(
    forward:     {keyKp8},
    backward:    {keyKp2, keyKp5},
    strafeLeft:  {keyKp4},
    strafeRight: {keyKp6},
    turnLeft:    {keyKp7},
    turnRight:   {keyKp9}
  )

  WalkKeysWasd = WalkKeys(
    forward:     {keyW},
    backward:    {Key.keyS},
    strafeLeft:  {keyA},
    strafeRight: {keyD},
    turnLeft:    {keyQ},
    turnRight:   {keyE}
  )

func mkWalkKeysCursor(mode: WalkCursorMode): WalkKeys =
  if mode == wcmStrafe:
    result = WalkKeysKeypad + WalkKeysCursorStrafe
  elif mode == wcmTurn:
    result = WalkKeysKeypad + WalkKeysCursorTurn

func mkWalkKeysWasd(walkKeysCursor: WalkKeys): WalkKeys =
  walkKeysCursor + WalkKeysWasd

proc updateWalkKeys(a) =
  a.ui.walkKeysCursor = mkWalkKeysCursor(a.prefs.walkCursorMode)
  a.ui.walkKeysWasd   = mkWalkKeysWasd(a.ui.walkKeysCursor)


const
  AllWasdMoveKeys = {keyQ, keyW, keyE, keyA, Key.keyS, keyD}
  DiagonalMoveLetterKeys = {keyY, keyU, keyB, keyN}


# {{{ DefaultAppShortcuts

# TODO Intoduce win/mac specific shorcuts, switchable at runtime via prefs?
# (e.g. use Cmd instead of Ctrl in shortcuts on Mac; Mac specific text box
# editing shortcuts, etc.)
let DefaultAppShortcuts = {
  # General
  scNextTextField:      @[mkKeyShortcut(keyTab,           {})],

  scAccept:             @[mkKeyShortcut(keyEnter,         {}),
                          mkKeyShortcut(keyKpEnter,       {})],

  scCancel:             @[mkKeyShortcut(keyEscape,        {}),
                          mkKeyShortcut(keyLeftBracket,   {mkCtrl})],

  scDiscard:            @[mkKeyShortcut(keyD,             {mkAlt})],

  scUndo:               @[mkKeyShortcut(keyU,             {}),
                          mkKeyShortcut(keyU,             {mkCtrl}),
                          mkKeyShortcut(keyZ,             {mkCtrl})],

  scRedo:               @[mkKeyShortcut(keyR,             {mkCtrl}),
                          mkKeyShortcut(keyY,             {mkCtrl})],

  # Maps
  scNewMap:             @[mkKeyShortcut(keyN,             {mkCtrl, mkAlt})],
  scOpenMap:            @[mkKeyShortcut(keyO,             {mkCtrl})],
  scSaveMap:            @[mkKeyShortcut(Key.keyS,         {mkCtrl})],
  scSaveMapAs:          @[mkKeyShortcut(Key.keyS,         {mkCtrl, mkShift})],
  scEditMapProps:       @[mkKeyShortcut(keyP,             {mkCtrl, mkAlt})],

  # Levels
  scNewLevel:              @[mkKeyShortcut(keyN,          {mkCtrl})],
  scDeleteLevel:           @[mkKeyShortcut(keyD,          {mkCtrl})],
  scEditLevelProps:        @[mkKeyShortcut(keyP,          {mkCtrl})],
  scResizeLevel:           @[mkKeyShortcut(keyE,          {mkCtrl})],

  # Regions
  scEditRegionProps:    @[mkKeyShortcut(keyR,             {mkCtrl, mkAlt})],

  # Themes
  scReloadTheme:        @[mkKeyShortcut(keyHome,          {mkCtrl})],
  scPreviousTheme:      @[mkKeyShortcut(keyPageUp,        {mkCtrl})],
  scNextTheme:          @[mkKeyShortcut(keyPageDown,      {mkCtrl})],

  # Editing
  scCycleFloorGroup1Forward:   @[mkKeyShortcut(key1,      {})],
  scCycleFloorGroup2Forward:   @[mkKeyShortcut(key2,      {})],
  scCycleFloorGroup3Forward:   @[mkKeyShortcut(key3,      {})],
  scCycleFloorGroup4Forward:   @[mkKeyShortcut(key4,      {})],
  scCycleFloorGroup5Forward:   @[mkKeyShortcut(key5,      {})],
  scCycleFloorGroup6Forward:   @[mkKeyShortcut(key6,      {})],
  scCycleFloorGroup7Forward:   @[mkKeyShortcut(key7,      {})],
  scCycleFloorGroup8Forward:   @[mkKeyShortcut(key8,      {})],

  scCycleFloorGroup1Backward:  @[mkKeyShortcut(key1,      {mkShift})],
  scCycleFloorGroup2Backward:  @[mkKeyShortcut(key2,      {mkShift})],
  scCycleFloorGroup3Backward:  @[mkKeyShortcut(key3,      {mkShift})],
  scCycleFloorGroup4Backward:  @[mkKeyShortcut(key4,      {mkShift})],
  scCycleFloorGroup5Backward:  @[mkKeyShortcut(key5,      {mkShift})],
  scCycleFloorGroup6Backward:  @[mkKeyShortcut(key6,      {mkShift})],
  scCycleFloorGroup7Backward:  @[mkKeyShortcut(key7,      {mkShift})],
  scCycleFloorGroup8Backward:  @[mkKeyShortcut(key8,      {mkShift})],

  scExcavateTunnel:            @[mkKeyShortcut(keyD,      {})],
  scEraseCell:                 @[mkKeyShortcut(keyE,      {})],
  scDrawClearFloor:            @[mkKeyShortcut(keyF,      {})],
  scToggleFloorOrientation:    @[mkKeyShortcut(keyO,      {})],

  scSetFloorColor:             @[mkKeyShortcut(keyC,      {})],
  scPickFloorColor:            @[mkKeyShortcut(keyI,      {})],
  scPreviousFloorColor:        @[mkKeyShortcut(keyComma,  {})],
  scNextFloorColor:            @[mkKeyShortcut(keyPeriod, {})],

  scSelectFloorColor1:         @[mkKeyShortcut(key1,      {mkCtrl})],
  scSelectFloorColor2:         @[mkKeyShortcut(key2,      {mkCtrl})],
  scSelectFloorColor3:         @[mkKeyShortcut(key3,      {mkCtrl})],
  scSelectFloorColor4:         @[mkKeyShortcut(key4,      {mkCtrl})],
  scSelectFloorColor5:         @[mkKeyShortcut(key5,      {mkCtrl})],
  scSelectFloorColor6:         @[mkKeyShortcut(key6,      {mkCtrl})],
  scSelectFloorColor7:         @[mkKeyShortcut(key7,      {mkCtrl})],
  scSelectFloorColor8:         @[mkKeyShortcut(key8,      {mkCtrl})],
  scSelectFloorColor9:         @[mkKeyShortcut(key9,      {mkCtrl})],
  scSelectFloorColor10:        @[mkKeyShortcut(key0,      {mkCtrl})],

  scDrawWall:                  @[mkKeyShortcut(keyW,      {})],
  scDrawSpecialWall:           @[mkKeyShortcut(keyR,      {})],

  scDrawWallRepeat:            @[mkKeyShortcut(keyLeftShift,  {}),
                                 mkKeyShortcut(keyRightShift, {})],

  scPreviousSpecialWall:       @[mkKeyShortcut(keyLeftBracket,  {})],
  scNextSpecialWall:           @[mkKeyShortcut(keyRightBracket, {})],

  scSelectSpecialWall1:        @[mkKeyShortcut(key1,      {mkAlt})],
  scSelectSpecialWall2:        @[mkKeyShortcut(key2,      {mkAlt})],
  scSelectSpecialWall3:        @[mkKeyShortcut(key3,      {mkAlt})],
  scSelectSpecialWall4:        @[mkKeyShortcut(key4,      {mkAlt})],
  scSelectSpecialWall5:        @[mkKeyShortcut(key5,      {mkAlt})],
  scSelectSpecialWall6:        @[mkKeyShortcut(key6,      {mkAlt})],
  scSelectSpecialWall7:        @[mkKeyShortcut(key7,      {mkAlt})],
  scSelectSpecialWall8:        @[mkKeyShortcut(key8,      {mkAlt})],
  scSelectSpecialWall9:        @[mkKeyShortcut(key9,      {mkAlt})],
  scSelectSpecialWall10:       @[mkKeyShortcut(key0,      {mkAlt})],
  scSelectSpecialWall11:       @[mkKeyShortcut(keyMinus,  {mkAlt})],
  scSelectSpecialWall12:       @[mkKeyShortcut(keyEqual,  {mkAlt})],

  scEraseTrail:                @[mkKeyShortcut(keyX,      {})],
  scExcavateTrail:             @[mkKeyShortcut(keyD,      {mkCtrl, mkAlt})],
  scClearTrail:                @[mkKeyShortcut(keyX,      {mkCtrl, mkAlt})],

  scJumpToLinkedCell:          @[mkKeyShortcut(keyG,      {})],
  scLinkCell:                  @[mkKeyShortcut(keyG,      {mkShift})],

  scPreviousLevel:             @[mkKeyShortcut(keyPageUp,     {}),
                                 mkKeyShortcut(keyKpSubtract, {}),
                                 mkKeyShortcut(keyMinus,      {mkCtrl})],

  scNextLevel:                 @[mkKeyShortcut(keyPageDown,   {}),
                                 mkKeyShortcut(keyKpAdd,      {}),
                                 mkKeyShortcut(keyEqual,      {mkCtrl})],

  scZoomIn:                    @[mkKeyShortcut(keyEqual,      {})],
  scZoomOut:                   @[mkKeyShortcut(keyMinus,      {})],

  scMarkSelection:             @[mkKeyShortcut(keyM,          {})],

  scPaste:                     @[mkKeyShortcut(keyP,          {})],
  scPastePreview:              @[mkKeyShortcut(keyP,          {mkShift})],
  scNudgePreview:              @[mkKeyShortcut(keyG,          {mkCtrl})],
  scPasteAccept:               @[mkKeyShortcut(keyP,          {}),
                                 mkKeyShortcut(keyEnter,      {}),
                                 mkKeyShortcut(keyKpEnter,    {})],

  scEditNote:                  @[mkKeyShortcut(keyN,          {}),
                                 mkKeyShortcut(keySemicolon,  {})],

  scEraseNote:                 @[mkKeyShortcut(keyN,          {mkShift}),
                                 mkKeyShortcut(keySemicolon,  {mkShift})],

  scEditLabel:                 @[mkKeyShortcut(keyT,          {mkCtrl})],
  scEraseLabel:                @[mkKeyShortcut(keyT,          {mkShift})],

  scShowNoteTooltip:           @[mkKeyShortcut(keySpace,      {})],

  # Select mode
  scSelectionDraw:               @[mkKeyShortcut(keyD,        {})],
  scSelectionErase:              @[mkKeyShortcut(keyE,        {})],
  scSelectionAll:                @[mkKeyShortcut(keyA,        {})],

  scSelectionNone:               @[mkKeyShortcut(keyU,        {}),
                                   mkKeyShortcut(keyX,        {})],

  scSelectionAddRect:            @[mkKeyShortcut(keyR,        {})],
  scSelectionSubRect:            @[mkKeyShortcut(Key.keyS,    {})],

  scSelectionCopy:               @[mkKeyShortcut(keyC,        {}),
                                   mkKeyShortcut(keyY,        {})],

  scSelectionMove:               @[mkKeyShortcut(keyM,        {mkCtrl})],
  scSelectionEraseArea:          @[mkKeyShortcut(keyE,        {mkCtrl})],
  scSelectionFillArea:           @[mkKeyShortcut(keyF,        {mkCtrl})],
  scSelectionSurroundArea:       @[mkKeyShortcut(Key.keyS,    {mkCtrl})],
  scSelectionSetFloorColorArea:  @[mkKeyShortcut(keyC,        {mkCtrl})],
  scSelectionCropArea:           @[mkKeyShortcut(keyR,        {mkCtrl})],

  # Options
  scToggleCellCoords:      @[mkKeyShortcut(keyC,           {mkAlt})],
  scToggleCurrentNotePane: @[mkKeyShortcut(keyN,           {mkAlt})],
  scToggleNotesListPane:   @[mkKeyShortcut(keyL,           {mkAlt})],
  scToggleToolsPane:       @[mkKeyShortcut(keyT,           {mkAlt})],
  scToggleWalkMode:        @[mkKeyShortcut(keyGraveAccent, {})],
  scToggleWasdMode:        @[mkKeyShortcut(keyTab,         {})],
  scToggleDrawTrail:       @[mkKeyShortcut(keyT,           {})],
  scToggleTitleBar:        @[mkKeyShortcut(keyT,           {mkAlt, mkShift})],
  scTogglePasteWraparound: @[mkKeyShortcut(keyW,           {})],

  # Misc
  scShowAboutDialog:       @[mkKeyShortcut(keyA,           {mkCtrl})],
  scOpenUserManual:        @[mkKeyShortcut(keyF1,          {})],
  scToggleThemeEditor:     @[mkKeyShortcut(keyF12,         {})],
  scEditPreferences:       @[mkKeyShortcut(keyU,           {mkCtrl, mkAlt})],
  scToggleQuickReference:  @[mkKeyShortcut(keySlash,       {mkShift})]

}.toTable

# }}}

# {{{ makeYubnAppShortcuts()
proc mkYubnAppShortcuts(): Table[AppShortcut, seq[KeyShortcut]] =
  var sc = DefaultAppShortcuts

  # remove keyY mappings
  sc[scSelectionCopy] = @[mkKeyShortcut(keyC, {})]

  # remove keyU mappings
  sc[scUndo]          = @[mkKeyShortcut(keyZ, {mkCtrl}),
                          mkKeyShortcut(keyU, {mkCtrl})]

  sc[scSelectionNone] = @[mkKeyShortcut(keyX, {})]

  # remove keyN mappings
  sc[scEditNote]      = @[mkKeyShortcut(keySemicolon, {})]
  sc[scEraseNote]     = @[mkKeyShortcut(keySemicolon, {mkShift})]

  sc

# }}}
# {{{ toStr()
proc toStr(k: Key): string =
  case k
  of key0..key9: $k
  of keyA..keyZ, keyF1..keyF25: ($k).toUpper()
  of keyUnknown: "???"
  of keySpace: "Space"
  of keyApostrophe: "'"
  of keyComma: ","
  of keyMinus: "-"
  of keyPeriod: "."
  of keySlash: "/"
  of keySemicolon: ";"
  of keyEqual: "="
  of keyLeftBracket: "["
  of keyBackslash: "\\"
  of keyRightBracket: "]"
  of keyGraveAccent: "`"

  of keyWorld1: "World1"
  of keyWorld2: "World2"
  of keyEscape: "Esc"
  of keyEnter: "Enter"
  of keyTab: "Tab"
  of keyBackspace: "Bksp"
  of keyInsert: "Ins"
  of keyDelete: "Del"
  of keyRight: "Right"
  of keyLeft: "Left"
  of keyDown: "Down"
  of keyUp: "Up"

  of keyPageUp: "PgUp"
  of keyPageDown: "PgDn"
  of keyHome: "Home"
  of keyEnd: "End"
  of keyCapsLock: "CapsLock"
  of keyScrollLock: "ScrollLock"
  of keyNumLock: "NumLock"
  of keyPrintScreen: "PrtSc"
  of keyPause: "Pause"

  of keyKp0: "kp0"
  of keyKp1: "kp1"
  of keyKp2: "kp2"
  of keyKp3: "kp3"
  of keyKp4: "kp4"
  of keyKp5: "kp5"
  of keyKp6: "kp6"
  of keyKp7: "kp7"
  of keyKp8: "kp8"
  of keyKp9: "kp9"
  of keyKpDecimal: "kp."
  of keyKpDivide: "kp/"
  of keyKpMultiply: "kp*"
  of keyKpSubtract: "kp-"
  of keyKpAdd: "kp+"
  of keyKpEnter: "kpEnter"
  of keyKpEqual: "kp="

  of keyLeftShift: "LShift"
  of keyLeftControl: "LCtrl"
  of keyLeftAlt: "LAlt"
  of keyLeftSuper: "LSuper"
  of keyRightShift: "RShift"
  of keyRightControl: "RCtrl"
  of keyRightAlt: "RAlt"
  of keyRightSuper: "RSuper"
  of keyMenu: "Menu"


proc toStr(k: KeyShortcut): string =
  var s: seq[string] = @[]
  if mkCtrl  in k.mods: s.add("Ctrl")
  if mkShift in k.mods: s.add("Shift")
  if mkAlt   in k.mods: s.add("Alt")
  s.add(k.key.toStr())
  s.join("+")

proc toStr(sc: AppShortcut; a; idx = -1): string =
  var s: seq[string] = @[]
  if idx == -1:
    for k in a.ui.shortcuts[sc]:
      s.add(k.toStr())
    result = s.join("/")
  else:
    result = a.ui.shortcuts[sc][idx].toStr()
# }}}

# }}}

# {{{ Logging

# {{{ rollLogFile(a)
proc rollLogFile(a) =
  alias(p, a.paths)

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
  a.logFile = open(a.paths.logFile, fmWrite)

  var fileLog = newFileLogger(
    a.logFile,
    fmtStr = "[$levelname] $date $time - ",
    levelThreshold = if defined(DEBUG): lvlDebug else: lvlInfo
  )

  addHandler(fileLog)

# }}}
# {{{ logError()
proc logError(e: ref Exception, msgPrefix: string = "") =
  var msg = "Error message: " & e.msg & "\n\nStack trace:\n" & getStackTrace(e)
  if msgPrefix != "":
    msg = msgPrefix & "\n" & msg

  logging.error(msg)

# }}}

# }}}
# {{{ UI helpers

# {{{ viewRow()
func viewRow(row: Natural; a): int =
  row - a.ui.drawLevelParams.viewStartRow

func viewRow(a): int =
  viewRow(a.ui.cursor.row, a)

# }}}
# {{{ viewCol()
proc viewCol(col: Natural; a): int =
  col - a.ui.drawLevelParams.viewStartCol

func viewCol(a): int =
  viewCol(a.ui.cursor.col, a)

# }}}
# {{{ currSortedLevelIdx()
func currSortedLevelIdx(a): Natural =
  a.doc.map.findSortedLevelIdxForLevel(a.ui.cursor.level)

# }}}
# {{{ currLevel()
func currLevel(a): common.Level =
  a.doc.map.levels[a.ui.cursor.level]

# }}}
# {{{ currRegion()
func currRegion(a): Option[Region] =
  let l = currLevel(a)
  if l.regionOpts.enabled:
    let rc = a.doc.map.getRegionCoords(a.ui.cursor)
    l.getRegion(rc)
  else:
    Region.none

# }}}
# {{{ coordOptsForCurrLevel()
func coordOptsForCurrLevel(a): CoordinateOptions =
  a.doc.map.coordOptsForLevel(a.ui.cursor.level)

# }}}

# {{{ setStatusMessage()
proc setStatusMessage(icon, msg: string, commands: seq[string]; a) =
  alias(s, a.ui.status)

  s.icon = icon
  s.message = msg
  s.warning = ""
  s.commands = commands


proc setStatusMessage(icon, msg: string; a) =
  setStatusMessage(icon, msg, commands = @[], a)

proc setStatusMessage(msg: string; a) =
  setStatusMessage(NoIcon, msg, commands = @[], a)

# }}}
# {{{ clearStatusMessage()
proc clearStatusMessage(a) =
  setStatusMessage(NoIcon, msg = "", commands = @[], a)

# }}}
# {{{ setWarningMessage()
proc setWarningMessage(msg: string, keepStatusMessage = false; a) =
  alias(s, a.ui.status)

  s.warning = msg
  s.warningT0 = getMonoTime()
  s.warningTimeout = WarningMessageTimeout
  s.warningColor = a.theme.statusBarTheme.warningTextColor
  s.keepMessageAfterWarningExpired = keepStatusMessage

# }}}
# {{{ setErrorMessage()
proc setErrorMessage(msg: string; a) =
  alias(s, a.ui.status)

  s.warning = msg
  s.warningTimeout = InfiniteDuration
  s.warningColor = a.theme.statusBarTheme.errorTextColor
  s.keepMessageAfterWarningExpired = false

# }}}
# {{{ setSelectModeSelectMessage()
proc setSelectModeSelectMessage(a) =
  setStatusMessage(
    IconSelection, "Mark selection",
    @[scSelectionDraw.toStr(a),    "draw",
      scSelectionErase.toStr(a),   "erase",
      scSelectionAddRect.toStr(a), "add rect",
      scSelectionSubRect.toStr(a), "sub rect",
      scSelectionAll.toStr(a),     "mark all",
      scSelectionNone.toStr(a),    "unmark all",
      scSelectionCopy.toStr(a),    "copy",
      "Ctrl",                      "special"],
    a
  )

# }}}
# {{{ setSelectModeSpecialActionsMessage()
proc setSelectModeSpecialActionsMessage(a) =
  setStatusMessage(
    IconSelection, "Mark selection",
    @[scSelectionEraseArea.toStr(a),         "erase",
      scSelectionFillArea.toStr(a),          "fill",
      scSelectionSurroundArea.toStr(a),      "surround",
      scSelectionCropArea.toStr(a),          "crop",
      scSelectionMove.toStr(a),              "move",
      scSelectionSetFloorColorArea.toStr(a), "set colour"],
    a
  )

# }}}
# {{{ setSetLinkDestinationMessage()
proc setSetLinkDestinationMessage(floor: Floor; a) =
  setStatusMessage(IconLink,
                   fmt"Set {linkFloorToString(floor)} destination",
                   @[IconArrowsAll, "select cell",
                   scAccept.toStr(a, idx=0), "set",
                   scCancel.toStr(a, idx=0), "cancel"], a)
# }}}
# {{{ mkWraparoundMessage()
proc mkWraparoundMessage(a): string =
  "wraparound: " & (if a.opts.pasteWraparound: "on" else: "off")

# }}}
# {{{ setNudgePreviewModeMessage()
proc setNudgePreviewModeMessage(a) =
  setStatusMessage(IconArrowsAll, "Nudge level",
                   @[IconArrowsAll, "nudge",
                   scTogglePasteWraparound.toStr(a), mkWraparoundMessage(a),
                   "Enter", "confirm", "Esc", "cancel"], a)

# }}}
# {{{ setPastePreviewModeMessage()
proc setPastePreviewModeMessage(a) =
  setStatusMessage(IconTiles, "Paste selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "paste", "Esc", "cancel"], a)

# }}}
# {{{ setMovePreviewModeMessage()
proc setMovePreviewModeMessage(a) =
  setStatusMessage(IconTiles, "Move selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "confirm", "Esc", "cancel"], a)

# }}}
# {{{ mainPaneRect()
proc mainPaneRect(a): Rect[int] =
  var
    x1 = 0
    x2 = koi.winWidth()

  if a.opts.showThemeEditor:
    x2 -= ThemePaneWidth

  if a.doc.map.hasLevels and a.opts.showNotesListPane:
    x1 += NotesListPaneWidth.int

  let
    y1 = a.win.titleBarHeight
    y2 = koi.winHeight() - StatusBarHeight

  coordRect(x1.int, y1.int, x2.int, y2.int)

# }}}
# {{{ toolsPaneWidth()
proc toolsPaneWidth(a): float =
  let mainPane = mainPaneRect(a)
  if a.opts.showToolsPane:
    if mainPane.h < ToolsPaneYBreakpoint2: ToolsPaneWidthWide
    else: ToolsPaneWidthNarrow
  else:
    0.0

# }}}
# {{{ toolsPaneHeight()
proc toolsPaneHeight(mainPaneHeight: float): float =
  if   mainPaneHeight < ToolsPaneYBreakpoint1: 420.0
  elif mainPaneHeight < ToolsPaneYBreakpoint2: 630.0
  else:                                        780.0

# }}}

# {{{ calculateLevelDrawArea()
proc calculateLevelDrawArea(a): tuple[w, h: float] =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)

  let l = currLevel(a)

  var topPad, rightPad, bottomPad, leftPad: float

  if dp.drawCellCoords:
    topPad    = LevelTopPad_Coords
    rightPad  = LevelRightPad_Coords
    bottomPad = LevelBottomPad_Coords
    leftPad   = LevelLeftPad_Coords
  else:
    topPad    = LevelTopPad_NoCoords
    rightPad  = LevelRightPad_NoCoords
    bottomPad = LevelBottomPad_NoCoords
    leftPad   = LevelLeftPad_NoCoords

  if l.regionOpts.enabled:
    topPad += LevelTopPad_Regions

  let mainPane = mainPaneRect(a)

  dp.startX = mainPane.x1 + leftPad
  dp.startY = mainPane.y1 + topPad

  var
    w = mainPane.w - leftPad - rightPad
    h = mainPane.h - topPad  - bottomPad

  if a.opts.showCurrentNotePane:
   h -= CurrentNotePaneTopPad + CurrentNotePaneHeight +
                                CurrentNotePaneBottomPad

  if a.opts.showToolsPane:
    w -= toolsPaneWidth(a)

  (w, h)

# }}}

# {{{ setCursor()
proc setCursor(newCur: Location; a) =
  with a:
    if not doc.map.hasLevels:
      return

    if newCur.level != ui.cursor.level:
      opts.drawTrail = false

    if opts.drawTrail and newCur != ui.cursor:
      actions.drawTrail(doc.map, loc=newCur, undoLoc=ui.prevCursor,
                        doc.undoManager)

    let l = doc.map.levels[newCur.level]

    ui.cursor = Location(
      level: newCur.level,
      row: newCur.row.clamp(0, l.rows - 1),
      col: newCur.col.clamp(0, l.cols - 1)
    )

# }}}
# {{{ stepCursor()
proc moveCursorTo(loc: Location; a)

proc stepCursor(cur: Location, dir: CardinalDir, steps: Natural; a): Location =
  if not a.doc.map.hasLevels:
    return

  alias(dp, a.ui.drawLevelParams)

  let l = a.doc.map.levels[cur.level]
  let sm = ScrollMargin
  var cur = cur

  let wraparound = a.prefs.movementWraparound

  template stepInc(curPos: Natural, maxPos: Natural) =
    let newPos = curPos + steps
    if newPos > maxPos and wraparound:
      if steps > 1: a.opts.drawTrail = false
      curPos = newPos.floorMod(maxPos + 1)
      moveCursorTo(cur, a)
    else:
      curPos = min(newPos, maxPos)

  template stepDec(curPos: Natural, maxPos: Natural) =
    let newPos = curPos - steps
    let minPos = 0
    if newPos < minPos and wraparound:
      if steps > 1: a.opts.drawTrail = false
      curPos = newPos.floorMod(maxPos + 1)
      moveCursorTo(cur, a)
    else:
      curPos = max(minPos, newPos)

  case dir:
  of dirE:
    stepInc(cur.col, maxPos=(l.cols - 1))

    let viewCol = viewCol(cur.col, a)
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol +
                                                        (viewCol - viewColMax))
  of dirS:
    stepInc(cur.row, maxPos=(l.rows - 1))

    let viewRow = viewRow(cur.row, a)
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow +
                                                        (viewRow - viewRowMax))

  of dirW:
    stepDec(cur.col, maxPos=(l.cols - 1))

    let viewCol = viewCol(cur.col, a)
    if viewCol < sm:
      dp.viewStartCol = max(dp.viewStartCol - (sm - viewCol), 0)

  of dirN:
    stepDec(cur.row, maxPos=(l.rows - 1))

    let viewRow = viewRow(cur.row, a)
    if viewRow < sm:
      dp.viewStartRow = max(dp.viewStartRow - (sm - viewRow), 0)

  result = cur

# }}}
# {{{ moveCursor()
proc moveCursor(dir: CardinalDir, steps: Natural = 1; a) =
  let cur = stepCursor(a.ui.cursor, dir, steps, a)
  if cur != a.ui.cursor:
    if steps > 1:
      a.opts.drawTrail = false
    a.ui.prevMoveDir = dir.some
    setCursor(cur, a)

# }}}
# {{{ moveCursorDiagonal()
proc moveCursorDiagonal(dir: Direction, steps: Natural = 1; a) =
  assert(dir in @[NorthWest, NorthEast, SouthWest, SouthEast])

  let l = currLevel(a)

  var cur = a.ui.cursor
  for i in 0..<steps:
    if not a.prefs.movementWraparound:
      if (dirN in dir and cur.row == 0)        or
         (dirS in dir and cur.row == l.rows-1) or
         (dirW in dir and cur.col == 0)        or
         (dirE in dir and cur.col == l.cols-1):
        return

    for d in dir:
      cur = stepCursor(cur, d, steps=1, a)

  setCursor(cur, a)

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
# {{{ locationAtMouse()
proc locationAtMouse(clampToBounds=false, a): Option[Location] =
  alias(dp, a.ui.drawLevelParams)

  let
    mouseViewRow = ((koi.my() - dp.startY) / dp.gridSize).int
    mouseViewCol = ((koi.mx() - dp.startX) / dp.gridSize).int

    mouseRow = dp.viewStartRow + mouseViewRow
    mouseCol = dp.viewStartCol + mouseViewCol

  if clampToBounds:
    result = Location(
      level: a.ui.cursor.level,
      row: mouseRow.clamp(dp.viewStartRow, dp.viewStartRow + dp.viewRows-1),
      col: mouseCol.clamp(dp.viewStartCol, dp.viewStartCol + dp.viewCols-1)
    ).some

  else:
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
# {{{ stepLevelView()
proc stepLevelView(dir: CardinalDir; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)
  let maxViewStartRow = max(l.rows - dp.viewRows, 0)
  let maxViewStartCol = max(l.cols - dp.viewCols, 0)

  var newViewStartCol = dp.viewStartCol
  var newViewStartRow = dp.viewStartRow

  case dir:
  of dirE: newViewStartCol = min(dp.viewStartCol + 1, maxViewStartCol)
  of dirW: newViewStartCol = max(dp.viewStartCol - 1, 0)
  of dirS: newViewStartRow = min(dp.viewStartRow + 1, maxViewStartRow)
  of dirN: newViewStartRow = max(dp.viewStartRow - 1, 0)

  var cur = a.ui.cursor
  cur.row = cur.row + viewRow(newViewStartRow, a)
  cur.col = cur.col + viewCol(newViewStartCol, a)
  setCursor(cur, a)

  dp.viewStartRow = newViewStartRow
  dp.viewStartCol = newViewStartCol

# }}}
# {{{ moveLevelView()
proc moveLevelView(dir: Direction, steps: Natural = 1; a) =
  alias(dp, a.ui.drawLevelParams)

  a.opts.drawTrail = false

  let l = currLevel(a)
  let maxViewStartRow = max(l.rows - dp.viewRows, 0)
  let maxViewStartCol = max(l.cols - dp.viewCols, 0)

  for i in 0..<steps:
    if (dirN in dir and dp.viewStartRow == 0) or
       (dirS in dir and dp.viewStartRow == maxViewStartRow) or
       (dirW in dir and dp.viewStartCol == 0) or
       (dirE in dir and dp.viewStartCol == maxViewStartCol):
      return

    for d in dir:
      stepLevelView(d, a)

# }}}

# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart(a) =
  with a.ui.cursor:
    level = 0
    row   = 0
    col   = 0

  with a.ui.drawLevelParams:
    viewStartRow = 0
    viewStartCol = 0

# }}}
# {{{ updateLastCursorViewCoords()
proc updateLastCursorViewCoords(a) =
  alias(dp, a.ui.drawLevelParams)

  a.ui.prevCursorViewX = dp.gridSize * viewCol(a)
  a.ui.prevCursorViewY = dp.gridSize * viewRow(a)

# }}}
# {{{ updateViewAndCursorPos()
proc updateViewAndCursorPos(levelDrawWidth, levelDrawHeight: float; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)

  dp.viewRows = min(dp.numDisplayableRows(levelDrawHeight), l.rows)
  dp.viewCols = min(dp.numDisplayableCols(levelDrawWidth), l.cols)

  let maxViewStartRow = max(l.rows - dp.viewRows, 0)
  let maxViewStartCol = max(l.cols - dp.viewCols, 0)

  if maxViewStartRow < dp.viewStartRow:
    dp.viewStartRow = maxViewStartRow

  if maxViewStartCol < dp.viewStartCol:
    dp.viewStartCol = maxViewStartCol

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  let cur = a.ui.cursor
  let newCur = Location(
    level: cur.level,
    col:   viewEndCol.clamp(dp.viewStartCol, cur.col),
    row:   viewEndRow.clamp(dp.viewStartRow, cur.row)
  )

  if newCur != cur:
    setCursor(newCur, a)

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
  let bbox = sel.boundingBox

  if bbox.isSome:
    let bbox = bbox.get

    buf = some(SelectionBuffer(
      selection: newSelectionFrom(sel, bbox),
      level: newLevelFrom(currLevel(a), bbox)
    ))

  result = bbox

# }}}

# {{{ exitMovePreviewMode()
proc undoAction(a)

proc exitMovePreviewMode(a) =
  undoAction(a)
  a.doc.undoManager.truncateUndoState()
  a.ui.editMode = emNormal
  clearStatusMessage(a)

# }}}
# {{{ exitNudgePreviewMode()
proc exitNudgePreviewMode(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)

  let cur = a.ui.cursor

  ui.editMode = emNormal

  # Reset the current level reference to the level in the nudge buffer
  map.levels[cur.level] = ui.nudgeBuf.get.level
  ui.nudgeBuf = SelectionBuffer.none

  clearStatusMessage(a)

# }}}
# {{{ returnToNormalMode()
proc returnToNormalMode(a) =
  alias(ui, a.ui)

  case ui.editMode
  of emNormal: discard

  of emMovePreview:
    exitMovePreviewMode(a)

  of emNudgePreview:
    exitNudgePreviewMode(a)

  of emSelect, emSelectDraw, emSelectErase, emSelectRect:
    exitSelectMode(a)

  else:
    ui.editMode = emNormal
    clearStatusMessage(a)

# }}}

# }}}
# {{{ Graphics helpers

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
# {{{ createAlpha()
proc createAlpha(d: var ImageData) =
  for i in 0..<(d.width * d.height):
    # copy the R component to the alpha channel
    d.data[i*4+3] = d.data[i*4]

# }}}
# {{{ colorImage()
func colorImage(d: var ImageData, color: Color) =
  for i in 0..<(d.width * d.height):
    d.data[i*4]   = (color.r * 255).byte
    d.data[i*4+1] = (color.g * 255).byte
    d.data[i*4+2] = (color.b * 255).byte

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

# {{{ setSwapInterval()
proc setSwapInterval(a) =
  glfw.swapInterval(if a.prefs.vsync: 1 else: 0)

# }}}

# }}}
# {{{ Key event helpers

# {{{ updateShortcuts()
proc updateShortcuts(a) =
  a.ui.shortcuts = if a.prefs.yubnMovementKeys: mkYubnAppShortcuts()
                   else: DefaultAppShortcuts

  a.ui.quickRefShortcuts = mkQuickRefShortcuts(a)

# }}}
# {{{ hasKeyEvent()
proc hasKeyEvent(): bool =
  koi.hasEvent() and koi.currEvent().kind == ekKey

# }}}
# {{{ isKeyDown()
proc isKeyDown(ev: Event, keys: set[Key], mods: set[ModifierKey] = {},
               repeat=false): bool =

  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}

  let numKey = ev.key in keyKp0..keyKpEqual
  let eventMods = if numKey: ev.mods - {mkCapsLock}
                  else:      ev.mods - {mkCapsLock, mkNumLock}

  ev.action in a and ev.key in keys and eventMods == mods


proc isKeyDown(ev: Event, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ev, {key}, mods, repeat)

# }}}
# {{{ checkShortcut()
proc checkShortcut(ev: Event, shortcuts: set[AppShortcut],
                   actions: set[KeyAction], ignoreMods=false; a): bool =
  if ev.kind == ekKey:
    if ev.action in actions:
      let currShortcut = mkKeyShortcut(ev.key, ev.mods)
      for sc in shortcuts:
        if ignoreMods:
          for asc in a.ui.shortcuts[sc]:
            if asc.key == ev.key:
              return true
        else:
          if currShortcut in a.ui.shortcuts[sc]:
            return true

# }}}
# {{{ isShortcutDown()
proc isShortcutDown(ev: Event, shortcuts: set[AppShortcut]; a;
                    repeat=false, ignoreMods=false): bool =
  let actions = if repeat: {kaDown, kaRepeat} else: {kaDown}
  checkShortcut(ev, shortcuts, actions, ignoreMods, a)

proc isShortcutDown(ev: Event, shortcut: AppShortcut; a;
                    repeat=false, ignoreMods=false): bool =
  isShortcutDown(ev, {shortcut}, a, repeat, ignoreMods)

# }}}
# {{{ isShortcutUp()
proc isShortcutUp(ev: Event, shortcuts: set[AppShortcut]; a): bool =
  checkShortcut(ev, shortcuts, actions={kaUp}, ignoreMods=true, a)

proc isShortcutUp(ev: Event, shortcut: AppShortcut; a): bool =
  isShortcutUp(ev, {shortcut}, a)

# }}}

# }}}

# {{{ Theme handling

# {{{ currThemeName()
func currThemeName(a): ThemeName =
  a.theme.themeNames[a.theme.currThemeIndex]

# }}}
# {{{ findThemeIndex()
func findThemeIndex(name: string; a): Option[Natural] =
  for i, themeName in a.theme.themeNames.mpairs:
    if themeName.name == name:
      return i.Natural.some

# }}}
# {{{ themePath()
func themePath(theme: ThemeName; a): string =
  let themeDir = if theme.userTheme: a.paths.userThemesDir
                 else: a.paths.themesDir
  themeDir / addFileExt(theme.name, ThemeExt)

# }}}
# {{{ makeUniqueThemeName()
proc makeUniqueThemeName(themeName: string; a): string =
  var basename = themeName
  var i = 1

  var s = themeName.rsplit(' ', maxsplit=1)
  if s.len == 2:
    try:
      i = parseInt(s[1])
      basename = s[0]
    except ValueError:
      discard

  while true:
    inc(i)
    result = fmt"{basename} {i}"
    if findThemeIndex(result, a).isNone: return

# }}}

# {{{ buildThemeList()
proc buildThemeList(a) =
  var themeNames: seq[ThemeName] = @[]

  func findThemeWithName(name: string): int =
    for i, themeName in themeNames.mpairs:
      if themeName.name == name: return i
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

  addThemeNames(a.paths.themesDir, userTheme=false)
  addThemeNames(a.paths.userThemesDir, userTheme=true)

  if themeNames.len == 0:
    raise newException(IOError, "Cannot find any themes, exiting")

  themeNames.sort(
    proc (a, b: ThemeName): int = cmp(a.name, b.name)
  )

  a.theme.themeNames = themeNames

# }}}
# {{{ loadTheme()
proc loadTheme(theme: ThemeName; a) =
  var path = themePath(theme, a)
  info(fmt"Loading theme '{theme.name}' from '{path}'")

  a.theme.config = loadTheme(path)
  a.logfile.flushFile()

# }}}
# {{{ saveTheme(a)
proc saveTheme(a) =
  try:
    with a.theme.themeNames[a.theme.currThemeIndex]:
      userTheme = true
      override = true

    let themePath = themePath(a.currThemeName, a)
    saveTheme(a.theme.config, themePath)
    a.themeEditor.modified = false

  except CatchableError as e:
    let msgPrefix = fmt"Error saving theme '{a.currThemeName.name}'"
    logError(e, msgPrefix)
    setWarningMessage(fmt"{msgPrefix}: {e.msg}", a=a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ deleteTheme()
proc deleteTheme(theme: ThemeName; a): bool =
  if theme.userTheme:
    try:
      var path = themePath(theme, a)
      info(fmt"Deleting theme '{theme.name}' at '{path}'")

      removeFile(path)
      a.logfile.flushFile()
      result = true
    except CatchableError as e:
      let msgPrefix = "Error deleting theme"
      logError(e, msgPrefix)
      setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)

# }}}
# {{{ copyTheme()
proc copyTheme(theme: ThemeName, newThemePath: string; a): bool =
  try:
    copyFileWithPermissions(themePath(a.currThemeName, a), newThemePath)
    result = true
  except CatchableError as e:
    let msgPrefix = "Error copying theme"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)

# }}}
# {{{ renameTheme()
proc renameTheme(theme: ThemeName, newThemePath: string; a): bool =
  try:
    moveFile(themePath(a.currThemeName, a), newThemePath)
    result = true
  except CatchableError as e:
    let msgPrefix = "Error renaming theme"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)

# }}}

# {{{ loadThemeImage()
proc loadThemeImage(imageName: string, userTheme: bool, a): Option[Paint] =
  if userTheme:
    let imgPath = a.paths.userThemeImagesDir / imageName
    result = loadImage(imgPath, a)
    if result.isNone:
      info("Cannot load image from user theme images directory: " &
           fmt"'{imgPath}'. Attempting default theme images directory.")

  let imgPath = a.paths.themeImagesDir / imageName
  result = loadImage(imgPath, a)
  if result.isNone:
    logging.error(
      "Cannot load image from default theme images directory: '{imgPath}'"
    )

# }}}
# {{{ loadBackgroundImage()
proc loadBackgroundImage(theme: ThemeName; a) =
  let bgImageName = a.theme.windowTheme.backgroundImage

  if bgImageName != "":
    a.ui.backgroundImage = loadThemeImage(bgImageName, theme.userTheme, a)
    a.ui.drawLevelParams.backgroundImage = a.ui.backgroundImage
  else:
    a.ui.backgroundImage = Paint.none
    a.ui.drawLevelParams.backgroundImage = Paint.none

# }}}
# {{{ updateWidgetStyles()
proc updateWidgetStyles(a) =
  alias(cfg, a.theme.config)

  # Button
  a.theme.buttonStyle = koi.getDefaultButtonStyle()

  let w = cfg.getObjectOrEmpty("ui.widget")

  var labelStyle = koi.getDefaultLabelStyle()
  with labelStyle:
    color            = w.getColorOrDefault("foreground.normal")
    colorHover       = color
    colorDown        = w.getColorOrDefault("foreground.active")
    colorActive      = colorDown
    colorActiveHover = colorDown
    colorDisabled    = w.getColorOrDefault("foreground.disabled")

  # Button
  with a.theme.buttonStyle:
    cornerRadius      = w.getFloatOrDefault("corner-radius")
    fillColor         = w.getColorOrDefault("background.normal")
    fillColorHover    = w.getColorOrDefault("background.hover")
    fillColorDown     = w.getColorOrDefault("background.active")
    fillColorDisabled = w.getColorOrDefault("background.disabled")

    label       = labelStyle.deepCopy()
    label.align = haCenter

  # Radio button
  a.theme.radioButtonStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.radioButtonStyle:
    buttonCornerRadius         = w.getFloatOrDefault("corner-radius")
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label       = labelStyle.deepCopy()
    label.align = haCenter

  # Icon radio button
  a.theme.iconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.iconRadioButtonsStyle:
    buttonPadHoriz             = 4.0
    buttonPadVert              = 4.0
    buttonCornerRadius         = 0.0
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label          = labelStyle.deepCopy()
    label.fontSize = 18.0
    label.padHoriz = 0
    label.padHoriz = 0
    label.align    = haCenter

  # Drop down
  let dd = cfg.getObjectOrEmpty("ui.drop-down")

  a.theme.dropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.dropDownStyle:
    buttonCornerRadius      = w.getFloatOrDefault("corner-radius")
    buttonFillColor         = w.getColorOrDefault("background.normal")
    buttonFillColorHover    = w.getColorOrDefault("background.hover")
    buttonFillColorDown     = w.getColorOrDefault("background.active")
    buttonFillColorDisabled = w.getColorOrDefault("background.disabled")

    label          = labelStyle.deepCopy()
    label.padHoriz = 8.0

    itemListCornerRadius     = buttonCornerRadius
    itemBackgroundColorHover = w.getColorOrDefault("background.active")

    if dd.isEmpty():
      itemListFillColor = lerp(cfg.getColorOrDefault("ui.dialog.background"),
                               black(), 0.4)

      item.color        = cfg.getColorOrDefault("ui.dialog.label")
      item.colorHover   = w.getColorOrDefault("foreground.active")
    else:
      itemListFillColor = dd.getColorOrDefault("item-list-background")
      item.color        = dd.getColorOrDefault("item.normal")
      item.colorHover   = dd.getColorOrDefault("item.hover")

  # Text field
  a.theme.textFieldStyle = koi.getDefaultTextFieldStyle()

  let t = cfg.getObjectOrEmpty("ui.text-field")

  with a.theme.textFieldStyle:
    bgCornerRadius      = w.getFloatOrDefault("corner-radius")
    bgFillColor         = w.getColorOrDefault("background.normal")
    bgFillColorHover    = w.getColorOrDefault("background.hover")
    bgFillColorActive   = t.getColorOrDefault("edit.background")
    bgFillColorDisabled = w.getColorOrDefault("background.disabled")
    textColor           = w.getColorOrDefault("foreground.normal")
    textColorHover      = textColor
    textColorActive     = t.getColorOrDefault("edit.text")
    textColorDisabled   = w.getColorOrDefault("foreground.disabled")
    cursorColor         = t.getColorOrDefault("cursor")
    selectionColor      = t.getColorOrDefault("selection")

  # Text area
  a.theme.textAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.textAreaStyle:
    bgCornerRadius    = w.getFloatOrDefault("corner-radius")
    bgFillColor       = w.getColorOrDefault("background.normal")

    bgFillColorHover  = lerp(bgFillColor,
                             w.getColorOrDefault("background.hover"), 0.5)

    bgFillColorActive = t.getColorOrDefault("edit.background")
    textColor         = w.getColorOrDefault("foreground.normal")
    textColorHover    = textColor
    textColorActive   = t.getColorOrDefault("edit.text")
    cursorColor       = t.getColorOrDefault("cursor")
    selectionColor    = t.getColorOrDefault("selection")

    with scrollBarStyleNormal:
      let c = t.getColorOrDefault("scroll-bar.normal")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

    with scrollBarStyleEdit:
      let c = t.getColorOrDefault("scroll-bar.edit")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Check box
  a.theme.checkBoxStyle = koi.getDefaultCheckBoxStyle()

  with a.theme.checkBoxStyle:
    cornerRadius          = w.getFloatOrDefault("corner-radius")
    fillColor             = w.getColorOrDefault("background.normal")
    fillColorHover        = w.getColorOrDefault("background.hover")
    fillColorDown         = w.getColorOrDefault("background.active")
    fillColorActive       = fillColorDown
    fillColorDisabled     = w.getColorOrDefault("background.disabled")

    icon.fontSize         = 12.0
    icon.color            = w.getColorOrDefault("foreground.normal")
    icon.colorHover       = icon.color
    icon.colorDown        = w.getColorOrDefault("foreground.active")
    icon.colorActive      = icon.colorDown
    icon.colorActiveHover = icon.colorDown

    iconActive            = IconCheck
    iconInactive          = NoIcon

  # Dialog style
  a.theme.dialogStyle = koi.getDefaultDialogStyle()

  let d = cfg.getObjectOrEmpty("ui.dialog")

  with a.theme.dialogStyle:
    cornerRadius      = d.getFloatOrDefault("corner-radius")
    backgroundColor   = d.getColorOrDefault("background")
    titleBarBgColor   = d.getColorOrDefault("title.background")
    titleBarTextColor = d.getColorOrDefault("title.text")

    outerBorderColor  = d.getColorOrDefault("outer-border.color")
    innerBorderColor  = d.getColorOrDefault("inner-border.color")
    outerBorderWidth  = d.getFloatOrDefault("outer-border.width")
    innerBorderWidth  = d.getFloatOrDefault("inner-border.width")

    with shadow:
      enabled = d.getBoolOrDefault("shadow.enabled")
      xOffset = d.getFloatOrDefault("shadow.x-offset")
      yOffset = d.getFloatOrDefault("shadow.y-offset")
      feather = d.getFloatOrDefault("shadow.feather")
      color   = d.getColorOrDefault("shadow.color")

  a.theme.aboutDialogStyle = a.theme.dialogStyle.deepCopy()
  a.theme.aboutDialogStyle.drawTitleBar = false

  # Label
  a.theme.labelStyle = koi.getDefaultLabelStyle()

  with a.theme.labelStyle:
    fontSize      = 14
    color         = d.getColorOrDefault("label")
    colorDisabled = color.lerp(d.getColorOrDefault("background"), 0.7)
    align         = haLeft

  # Warning label
  a.theme.warningLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.warningLabelStyle:
    color     = d.getColorOrDefault("warning")
    multiLine = true

  # Error label
  a.theme.errorLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.errorLabelStyle:
    color     = d.getColorOrDefault("error")
    multiLine = true

  # Level drop-down
  let ld = cfg.getObjectOrEmpty("level.level-drop-down")

  a.theme.levelDropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.levelDropDownStyle:
    buttonCornerRadius       = ld.getFloatOrDefault("corner-radius")
    buttonFillColor          = ld.getColorOrDefault("button.normal")
    buttonFillColorHover     = ld.getColorOrDefault("button.hover")
    buttonFillColorDown      = buttonFillColor
    buttonFillColorDisabled  = buttonFillColor

    label.fontSize           = 15.0
    label.color              = ld.getColorOrDefault("button.label")
    label.colorHover         = label.color
    label.colorDown          = label.color
    label.colorActive        = label.color
    label.colorDisabled      = label.color
    label.align              = haCenter

    item.align               = haLeft
    item.color               = ld.getColorOrDefault("item.normal")
    item.colorHover          = ld.getColorOrDefault("item.hover")

    itemListCornerRadius     = buttonCornerRadius
    itemListPadHoriz         = 10.0
    itemListFillColor        = ld.getColorOrDefault("item-list-background")
    itemBackgroundColorHover = w.getColorOrDefault("background.active")

    var ss = koi.getDefaultShadowStyle()
    ss.color = ld.getColorOrDefault("shadow.color")
    ss.cornerRadius = buttonCornerRadius * 1.6
    shadow = ss

  # About button
  let ab = cfg.getObjectOrEmpty("ui.about-button")

  a.theme.aboutButtonStyle = koi.getDefaultButtonStyle()

  with a.theme.aboutButtonStyle:
    labelOnly        = true
    label.fontSize   = 20.0
    label.padHoriz   = 0
    label.color      = ab.getColorOrDefault("label.normal")
    label.colorHover = ab.getColorOrDefault("label.hover")
    label.colorDown  = ab.getColorOrDefault("label.down")

  # Current note pane
  let pn = cfg.getObjectOrEmpty("pane.notes")

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
    textColorDisabled   = pn.getColorOrDefault("text")

    with scrollBarStyleNormal:
      let c = pn.getColorOrDefault("scroll-bar")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Notes list pane
  a.theme.notesListScrollViewStyle = getDefaultScrollViewStyle()

  with a.theme.notesListScrollViewStyle:
    with scrollBarStyle:
      discard
      # TODO

# }}}
# {{{ updateTheme()
proc updateTheme(a) =
  alias(cfg, a.theme.config)

  updateWidgetStyles(a)

  a.theme.statusBarTheme = cfg.getObjectOrEmpty("ui.status-bar")
                              .toStatusBarTheme()

  a.theme.toolbarPaneTheme = cfg.getObjectOrEmpty("pane.toolbar")
                                .toToolbarPaneTheme()

  a.theme.notesPaneTheme = cfg.getObjectOrEmpty("pane.notes")
                              .toNotesPaneTheme()

  a.theme.levelTheme = cfg.getObjectOrEmpty("level").toLevelTheme()

  a.theme.windowTheme = cfg.getObjectOrEmpty("ui.window").toWindowTheme()
  a.win.theme = a.theme.windowTheme

  a.ui.drawLevelParams.initDrawLevelParams(a.theme.levelTheme, a.vg,
                                           koi.getPxRatio())

# }}}
# {{{ switchTheme()
proc switchTheme(themeIndex: Natural; a) =
  let theme = a.theme.themeNames[themeIndex]
  loadTheme(theme, a)

  updateTheme(a)
  loadBackgroundImage(theme, a)

  a.theme.currThemeIndex = themeIndex

  a.themeEditor.modified = false
  a.theme.prevConfig = a.theme.config.deepCopy()

# }}}

# }}}
# {{{ Config handling

# {{{ loadAppConfigOrDefault()
proc loadAppConfigOrDefault(path: string): HoconNode =
  var s: FileStream
  try:
    s = newFileStream(path)
    var p = initHoconParser(s)
    result = p.parse()
  except CatchableError as e:
    logging.warn(
      fmt"Cannot load config file '{path}', using default config. " &
      fmt"Error message: {e.msg}"
    )
    result = newHoconObject()
  finally:
    if s != nil: s.close()

# }}}
# {{{ saveAppConfig()
proc saveAppConfig(cfg: HoconNode, path: string) =
  var s: FileStream
  try:
    s = newFileStream(path, fmWrite)
    cfg.write(s)
  except CatchableError as e:
    logging.error(
      fmt"Cannot write config file '{path}'. Error message: {e.msg}"
    )
  finally:
    if s != nil: s.close()

# }}}
# {{{ saveAppConfig()
proc saveAppConfig(a) =
  alias(dp, a.ui.drawLevelParams)

  let (xpos, ypos) = if a.win.maximized: a.win.unmaximizedPos else: a.win.pos

  let (width, height) = if a.win.maximized: a.win.unmaximizedSize
                        else: a.win.size

  let cur = a.ui.cursor

  var cfg = newHoconObject()

  cfg.set("config-version", AppVersion)

  var p = "preferences."
  cfg.set(p & "load-last-map",                  a.prefs.loadLastMap)
  cfg.set(p & "splash.show-at-startup",         a.prefs.showSplash)
  cfg.set(p & "splash.auto-close",              a.prefs.autoCloseSplash)
  cfg.set(p & "splash.auto-close-timeout-secs", a.prefs.splashTimeoutSecs)
  cfg.set(p & "auto-save.enabled",              a.prefs.autosave)
  cfg.set(p & "auto-save.frequency-mins",       a.prefs.autosaveFreqMins)
  cfg.set(p & "editing.movement-wraparound",    a.prefs.movementWraparound)
  cfg.set(p & "editing.open-ended-excavate",    a.prefs.openEndedExcavate)
  cfg.set(p & "editing.yubn-movement-keys",     a.prefs.yubnMovementKeys)
  cfg.set(p & "editing.walk-cursor-mode",       enumToDashCase($a.prefs.walkCursorMode))
  cfg.set(p & "video.vsync",                    a.prefs.vsync)

  p = "last-state."
  cfg.set(p & "last-document", a.doc.path)
  cfg.set(p & "theme-name",    a.currThemeName.name)

  p = "last-state.ui."
  cfg.set(p & "zoom-level",                    dp.getZoomLevel())
  cfg.set(p & "current-level",                 cur.level)
  cfg.set(p & "cursor.row",                    cur.row)
  cfg.set(p & "cursor.column",                 cur.col)
  cfg.set(p & "view-start.row",                dp.viewStartRow)
  cfg.set(p & "view-start.column",             dp.viewStartCol)
  cfg.set(p & "option.show-cell-coords",       dp.drawCellCoords)
  cfg.set(p & "option.show-tools-pane",        a.opts.showToolsPane)
  cfg.set(p & "option.show-current-note-pane", a.opts.showCurrentNotePane)
  cfg.set(p & "option.show-notes-list-pane",   a.opts.showNotesListPane)
  cfg.set(p & "option.wasd-mode",              a.opts.wasdMode)
  cfg.set(p & "option.walk-mode",              a.opts.walkMode)
  cfg.set(p & "option.paste-wraparound",       a.opts.pasteWraparound)

  p = "last-state.window."
  cfg.set(p & "maximized",      a.win.maximized)
  cfg.set(p & "show-title-bar", a.win.showTitleBar)
  cfg.set(p & "x-position",     xpos)
  cfg.set(p & "y-position",     ypos)
  cfg.set(p & "width",          width)
  cfg.set(p & "height",         height)

  saveAppConfig(cfg, a.paths.configFile)

# }}}

# }}}
# {{{ Map handling

# {{{ loadMap()
proc loadMap(path: string; a): bool =
  info(fmt"Loading map '{path}'...")

  try:
    let t0 = getMonoTime()
    let (map, appState) = readMapFile(path)
    let dt = getMonoTime() - t0

    a.doc.map = map
    a.doc.path = path
    a.doc.lastAutosaveTime = getMonoTime()

    if appState.isSome:
      let s = appState.get

      a.updateUI = false
      a.theme.nextThemeIndex = findThemeIndex(s.themeName, a)
      a.theme.hideThemeLoadedMessage = true

      with a.opts:
        showToolsPane       = s.optShowToolsPane
        showCurrentNotePane = s.optShowCurrentNotePane
        showNotesListPane   = s.optShowNotesListPane
        wasdMode            = s.optWasdMode
        walkMode            = s.optWalkMode
        drawTrail           = false

      with a.ui.drawLevelParams:
        viewStartRow   = s.viewStartRow
        viewStartCol   = s.viewStartCol
        drawCellCoords = s.optShowCellCoords

      with a.ui.cursor:
        level = s.currLevel
        row   = s.cursorRow
        col   = s.cursorCol

      with a.ui:
        currFloorColor  = s.currFloorColor
        currSpecialWall = s.currSpecialWall

      a.ui.drawLevelParams.setZoomLevel(a.theme.levelTheme, s.zoomLevel)
      a.ui.mouseCanStartExcavate = true

    else:
      resetCursorAndViewStart(a)

    initUndoManager(a.doc.undoManager)

    let message = fmt"Map '{path}' loaded in " &
                  fmt"{durationToFloatMillis(dt):.2f} ms"

    info(message)
    setStatusMessage(IconFloppy, message, a)
    result = true

  except CatchableError as e:
    logError(e)
    setErrorMessage(e.msg, a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ saveMap()
proc saveMap(path: string, autosave, createBackup: bool; a) =
  alias(dp, a.ui.drawLevelParams)

  let cur = a.ui.cursor

  let appState = AppState(
    themeName:              a.currThemeName.name,

    zoomLevel:              dp.getZoomLevel(),
    currLevel:              cur.level,
    cursorRow:              cur.row,
    cursorCol:              cur.col,
    viewStartRow:           dp.viewStartRow,
    viewStartCol:           dp.viewStartCol,

    optShowCellCoords:      dp.drawCellCoords,
    optShowToolsPane:       a.opts.showToolsPane,
    optShowCurrentNotePane: a.opts.showCurrentNotePane,
    optShowNotesListPane:   a.opts.showNotesListPane,
    optWasdMode:            a.opts.wasdMode,
    optWalkMode:            a.opts.walkMode,

    currFloorColor:         a.ui.currFloorColor,
    currSpecialWall:        a.ui.currSpecialWall,
  )

  info(fmt"Saving map to '{path}'")

  if createBackup:
    try:
      if fileExists(path):
        moveFile(path, fmt"{path}.{BackupFileExt}")
    except CatchableError as e:
      let msgPrefix = "Error creating backup file"
      logError(e, msgPrefix)
      setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
      a.logFile.flushFile()
      return

  try:
    writeMapFile(a.doc.map, appState, path)
    a.doc.undoManager.setLastSaveState()

    if not autosave:
      setStatusMessage(IconFloppy, fmt"Map '{path}' saved", a)

  except CatchableError as e:
    logError(e)
    let prefix = if autosave: "Autosave failed: " else: ""
    setErrorMessage(fmt"{prefix}{e.msg}", a)
  finally:
    a.logFile.flushFile()

# }}}
# {{{ handleAutoSaveMap()
proc handleAutoSaveMap(a) =
  if a.prefs.autosave and a.doc.undoManager.isModified:
    let dt = getMonoTime() - a.doc.lastAutosaveTime
    if dt > initDuration(minutes = a.prefs.autosaveFreqMins):
      let path = if a.doc.path == "":
                   a.paths.autosaveDir / addFileExt("Untitled", MapFileExt)
                 else: a.doc.path

      saveMap(path, autosave=true, createBackup=true, a)
      a.doc.lastAutosaveTime = getMonoTime()

# }}}
# {{{ autoSaveMapOnCrash()

when not defined(DEBUG):

  proc autoSaveMapOnCrash(a): string =
    var fname: string
    if a.doc.path == "":
      let (path, _, _) = splitFile(a.doc.path)
      fname = path
    else:
      fname = a.paths.autosaveDir

    fname = fname / CrashAutosaveFilename

    info(fmt"Auto-saving map to '{fname}'")
    saveMap(fname, autosave=false, createBackup=false, a)

    result = fname

# }}}

# }}}
# {{{ Dialogs

# {{{ Constants
const
  DlgItemHeight   = 24.0
  DlgButtonWidth  = 80.0
  DlgButtonPad    = 10.0
  DlgNumberWidth  = 50.0
  DlgCheckBoxSize = 18.0
  DlgTopPad       = 50.0
  DlgTopNoTabPad  = 60.0
  DlgLeftPad      = 30.0
  DlgTabBottomPad = 50.0

  ConfirmDlgWidth  = 350.0
  ConfirmDlgHeight = 160.0

  DialogLayoutParams = AutoLayoutParams(
    itemsPerRow:       2,
    rowWidth:          370.0,
    labelWidth:        160.0,
    sectionPad:        0.0,
    leftPad:           0.0,
    rightPad:          0.0,
    rowPad:            8.0,
    rowGroupPad:       20.0,
    defaultRowHeight:  24.0,
    defaultItemHeight: 24.0
  )

# }}}
# {{{ Helpers

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
    let letterLabelX = x + 152

    koi.label("Column start", style=a.theme.labelStyle)
    var y = koi.autoLayoutNextY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.columnStart,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordColumnStartLimits.minInt,
        maxInt: CoordColumnStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.columnStyle) == csLetter:
      try:
        let i = parseInt(dlg.columnStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
      except ValueError:
        discard

    koi.label("Row start", style=a.theme.labelStyle)
    y = koi.autoLayoutNextY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rowStart,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordRowStartLimits.minInt,
        maxInt: CoordRowStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.rowStyle) == csLetter:
      try:
        let i = parseInt(dlg.rowStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
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
            kind:   tckInteger,
            minInt: RegionColumnLimits.minInt,
            maxInt: RegionColumnLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

        koi.label("Region rows", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.rowsPerRegion,
          constraint = TextFieldConstraint(
            kind:   tckInteger,
            minInt: RegionRowLimits.minInt,
            maxInt: RegionRowLimits.maxInt
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
# {{{ commonLevelFields()
template commonLevelFields(dimensionsDisabled: bool) =
  group:
    koi.label("Location name", style=a.theme.labelStyle)

    koi.textField(
      dlg.locationName,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckString,
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
        kind:   tckInteger,
        minInt: LevelElevationLimits.minInt,
        maxInt: LevelElevationLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Columns", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.cols,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelColumnsLimits.minInt,
        maxInt: LevelColumnsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
      style = a.theme.textFieldStyle
    )

    koi.label("Rows", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rows,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelRowsLimits.minInt,
        maxInt: LevelRowsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
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
# {{{ commonGeneralMapFields()
template commonGeneralMapFields(map: Map, displayCreationTime: bool) =
  group:
    koi.label("Title", style=a.theme.labelStyle)

    koi.textField(
      dlg.title,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapTitleLimits.minRuneLen,
        maxLen: MapTitleLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Game", style=a.theme.labelStyle)

    koi.textField(
      dlg.game,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapGameLimits.minRuneLen,
        maxLen: MapGameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Author", style=a.theme.labelStyle)

    koi.textField(
      dlg.author,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapAuthorLimits.minRuneLen,
        maxLen: MapAuthorLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    if displayCreationTime:
      koi.label("Creation time", style=a.theme.labelStyle)

      koi.textField(
        map.creationTime,
        disabled = true,
        style = a.theme.textFieldStyle
      )

# }}}
# {{{ validateCommonGeneralMapFields()
template validateCommonGeneralMapFields(dlg: untyped): string =
  if dlg.title == "":
    mkValidationError("Title is mandatory")
  else: ""

# }}}

# {{{ calcDialogX()
proc calcDialogX(dlgWidth: float; a): float =
  let mainPane = mainPaneRect(a)
  mainPane.x1 + mainPane.w.float*0.5 - dlgWidth*0.5

# }}}
# {{{ dialogButtonsStartPos()
func dialogButtonsStartPos(dlgWidth, dlgHeight: float,
                           numButtons: Natural): tuple[x, y: float] =
  const BorderPad = 15.0

  let x = dlgWidth - numButtons * DlgButtonWidth - BorderPad -
          (numButtons-1) * DlgButtonPad

  let y = dlgHeight - DlgItemHeight - BorderPad

  result = (x, y)

# }}}
# {{{ mkValidationError()
func mkValidationError(msg: string): string =
  fmt"{IconWarning}   {msg}"

# }}}
# {{{ mkValidationWarning()
func mkValidationWarning(msg: string): string =
  fmt"{IconInfo}   {msg}"

# }}}
# {{{ moveGridPositionWrapping()
func moveGridPositionWrapping(currIdx: int, dc: int = 0, dr: int = 0,
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
func handleGridRadioButton(ke: Event, currButtonIdx: Natural,
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
# {{{ handleTabNavigation()
proc handleTabNavigation(ke: Event,
                         currTabIndex, maxTabIndex: Natural; a): Natural =
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

# {{{ colorRadioButtonDrawProc()
proc colorRadioButtonDrawProc(colors: seq[Color],
                              cursorColor: Color): RadioButtonsDrawProc =

  return proc (vg: NVGContext,
               id: ItemId, x, y, w, h: float,
               buttonIdx, numButtons: Natural, label: string,
               state: WidgetState, style: RadioButtonsStyle) =

    let sw = 2.0
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    var col = colors[buttonIdx]

    let cursorColor = if state == wsHover: cursorColor.withAlpha(0.65)
                      else: cursorColor

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if state in {wsHover, wsDown, wsActive, wsActiveHover, wsActiveDown}:
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

# {{{ closeDialog()
proc closeDialog(a) =
  koi.closeDialog()
  a.dialogs.activeDialog = dlgNone

# }}}

# }}}

# {{{ About dialog

proc openAboutDialog(a) =
  a.dialogs.activeDialog = dlgAboutDialog

proc openUserManual(a)
proc openWebsite(a)

proc aboutDialog(a) =
  alias(al, a.aboutLogo)
  alias(vg, a.vg)

  const
    DlgWidth = 370.0
    DlgHeight = 440.0

  let
    dialogX = floor(calcDialogX(DlgWidth, a))
    dialogY = floor((koi.winHeight() - DlgHeight) * 0.5)

  let logoColor = a.theme.config.getColorOrDefault("ui.about-dialog.logo")

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconQuestion}  About Gridmonger",
                  x=dialogX.some, y=dialogY.some,
                  style=a.theme.aboutDialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad
  let w = DlgWidth
  let h = DlgItemHeight

  if al.logoImage == NoImage or al.updateLogoImage:
    colorImage(al.logo, logoColor)
    if al.logoImage == NoImage:
      al.logoImage = createImage(al.logo)
    else:
      vg.updateImage(al.logoImage, cast[ptr byte](al.logo.data))
    al.updateLogoImage = false

  let scale = DlgWidth / al.logo.width

  al.logoPaint = createPattern(a.vg, al.logoImage, alpha=logoColor.a,
                               xoffs=dialogX, yoffs=dialogY, scale=scale)


  koi.image(0, 0, DlgWidth, DlgHeight, al.logoPaint)

  var labelStyle = a.theme.labelStyle.deepCopy()
  labelStyle.align = haCenter

  y += 265
  koi.label(0, y, w, h, VersionInfo, style=labelStyle)

  y += 25
  koi.label(0, y, w, h, DevelopedByInfo, style=labelStyle)

  x = (DlgWidth - (2*DlgButtonWidth + 1*DlgButtonPad)) * 0.5
  y += 50
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Manual",
                style=a.theme.buttonStyle):
    openUserManual(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Website",
                style=a.theme.buttonStyle):
    openWebsite(a)


  proc closeAction(a) =
    a.aboutLogo.updateLogoImage = true
    closeDialog(a)


  # HACK, HACK, HACK!
  if not a.opts.showThemeEditor:
    if not koi.hasHotItem() and koi.hasEvent():
      let ev = koi.currEvent()
      if ev.kind == ekMouseButton and ev.button == mbLeft and ev.pressed:
        closeAction(a)

  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scCancel, a) or ke.isShortcutDown(scAccept, a):
      closeAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Preferences dialog

proc openPreferencesDialog(a) =
  alias(dlg, a.dialogs.preferencesDialog)

  dlg.showSplash         = a.prefs.showSplash
  dlg.autoCloseSplash    = a.prefs.autoCloseSplash
  dlg.splashTimeoutSecs  = $a.prefs.splashTimeoutSecs
  dlg.loadLastMap        = a.prefs.loadLastMap

  dlg.autosave           = a.prefs.autosave
  dlg.autosaveFreqMins   = $a.prefs.autosaveFreqMins
  dlg.vsync              = a.prefs.vsync

  dlg.movementWraparound = a.prefs.movementWraparound
  dlg.openEndedExcavate  = a.prefs.openEndedExcavate
  dlg.yubnMovementKeys   = a.prefs.yubnMovementKeys
  dlg.walkCursorMode     = a.prefs.walkCursorMode

  a.dialogs.activeDialog = dlgPreferencesDialog


proc preferencesDialog(dlg: var PreferencesDialogParams; a) =
  const
    DlgWidth  = 370.0
    DlgHeight = 306.0
    TabWidth  = 240.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCog}  Preferences",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["Startup", "General", "Editing"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 220
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # Startup
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
          kind:   tckInteger,
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
          kind:   tckInteger,
          minInt: AutosaveFreqMinsLimits.minInt,
          maxInt: AutosaveFreqMinsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )
    group:
      koi.label("Vertical sync", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.vsync, style = a.theme.checkBoxStyle)

  elif dlg.activeTab == 2:  # Editing
    group:
      koi.label("Movement wraparound", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.movementWraparound, style = a.theme.checkBoxStyle)

      koi.label("Open-ended exacavate", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.openEndedExcavate, style = a.theme.checkBoxStyle)

      koi.label("YUBN diagonal movement",
                 style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.yubnMovementKeys, style = a.theme.checkBoxStyle)

      koi.label("Walk mode Left/Right keys", style=a.theme.labelStyle)
      koi.nextItemWidth(80)
      koi.dropDown(dlg.walkCursorMode, style = a.theme.dropDownStyle)

  koi.endView()


  proc okAction(dlg: PreferencesDialogParams; a) =
    # Startup
    a.prefs.showSplash         = dlg.showSplash
    a.prefs.autoCloseSplash    = dlg.autoCloseSplash
    a.prefs.splashTimeoutSecs  = parseInt(dlg.splashTimeoutSecs).Natural
    a.prefs.loadLastMap        = dlg.loadLastMap

    # General
    if not a.prefs.autoSave and dlg.autoSave:
      a.doc.lastAutosaveTime = getMonoTime()

    a.prefs.autosave           = dlg.autosave
    a.prefs.autosaveFreqMins   = parseInt(dlg.autosaveFreqMins).Natural
    a.prefs.vsync              = dlg.vsync

    # Editing
    a.prefs.movementWraparound = dlg.movementWraparound
    a.prefs.openEndedExcavate  = dlg.openEndedExcavate
    a.prefs.yubnMovementKeys   = dlg.yubnMovementKeys
    a.prefs.walkCursorMode     = dlg.walkCursorMode

    saveAppConfig(a)
    setSwapInterval(a)
    updateWalkKeys(a)
    updateShortcuts(a)

    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Save/discard map changes dialog

proc openSaveDiscardMapDialog(nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardMapDialog)
  dlg.nextAction = nextAction
  a.dialogs.activeDialog = dlgSaveDiscardMapDialog


proc saveMap(a)

proc saveDiscardMapDialog(dlg: var SaveDiscardMapDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Map?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made change to the map.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the map?",
    style=a.theme.labelStyle
  )

  proc okAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    saveMap(a)
    dlg.nextAction(a)

  proc discardAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a):  cancelAction(a)
    elif ke.isShortcutDown(scDiscard, a): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept, a):  okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New map dialog

proc openNewMapDialog(a) =
  alias(dlg, a.dialogs.newMapDialog)

  with a.doc.map.coordOpts:
    dlg.title        = "Untitled Map"
    dlg.game         = ""
    dlg.author       = ""

    dlg.origin       = origin.ord
    dlg.rowStyle     = rowStyle.ord
    dlg.columnStyle  = columnStyle.ord
    dlg.rowStart     = $rowStart
    dlg.columnStart  = $columnStart

    dlg.notes        = ""

  dlg.activeTab = 0

  a.dialogs.activeDialog = dlgNewMapDialog


proc newMapDialog(dlg: var NewMapDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Map",
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

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonGeneralMapFields(a.doc.map, displayCreationTime=false)

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = validateCommonGeneralMapFields(dlg)

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: NewMapDialogParams; a) =
    if validationError != "": return

    a.opts.drawTrail = false

    a.doc.path = ""
    a.doc.map = newMap(dlg.title, dlg.game, dlg.author,
                       creationTime=now().format("yyyy-MM-dd HH:mm:ss"))

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
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit map properties dialog

proc openEditMapPropsDialog(a) =
  alias(dlg, a.dialogs.editMapPropsDialog)
  alias(map, a.doc.map)

  dlg.title        = map.title
  dlg.game         = map.game
  dlg.author       = map.author

  with map.coordOpts:
    dlg.origin      = origin.ord
    dlg.rowStyle    = rowStyle.ord
    dlg.columnStyle = columnStyle.ord
    dlg.rowStart    = $rowStart
    dlg.columnStart = $columnStart

  dlg.notes = map.notes

  a.dialogs.activeDialog = dlgEditMapPropsDialog


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

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonGeneralMapFields(a.doc.map, displayCreationTime=true)

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = validateCommonGeneralMapFields(dlg)

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: EditMapPropsDialogParams; a) =
    if validationError != "": return

    let coordOpts = CoordinateOptions(
      origin:      CoordinateOrigin(dlg.origin),
      rowStyle:    CoordinateStyle(dlg.rowStyle),
      columnStyle: CoordinateStyle(dlg.columnStyle),
      rowStart:    parseInt(dlg.rowStart),
      columnStart: parseInt(dlg.columnStart)
    )

    actions.setMapProperties(a.doc.map, a.ui.cursor,
                             dlg.title, dlg.game, dlg.author,
                             coordOpts, dlg.notes, a.doc.undoManager)

    setStatusMessage(IconFile, "Map properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ New level dialog

proc openNewLevelDialog(a) =
  alias(dlg, a.dialogs.newLevelDialog)

  let map = a.doc.map
  var co: CoordinateOptions

  if map.hasLevels:
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

  a.dialogs.activeDialog = dlgNewLevelDialog


proc newLevelDialog(dlg: var LevelPropertiesDialogParams; a) =
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

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonLevelFields(dimensionsDisabled=false)

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
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
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
        origin:      CoordinateOrigin(dlg.origin),
        rowStyle:    CoordinateStyle(dlg.rowStyle),
        columnStyle: CoordinateStyle(dlg.columnStyle),
        rowStart:    parseInt(dlg.rowStart),
        columnStart: parseInt(dlg.columnStart)
      ),

      regionOpts = RegionOptions(
        enabled:         dlg.enableRegions,
        colsPerRegion:   parseInt(dlg.colsPerRegion),
        rowsPerRegion:   parseInt(dlg.rowsPerRegion),
        perRegionCoords: dlg.perRegionCoords
      ),

      dlg.notes,
      a.doc.undoManager
    )
    setCursor(cur, a)

    setStatusMessage(IconFile, fmt"New {rows}×{cols} level created", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit level properties dialog

proc openEditLevelPropsDialog(a) =
  alias(dlg, a.dialogs.editLevelPropsDialog)

  let l = currLevel(a)

  dlg.locationName = l.locationName
  dlg.levelName = l.levelName
  dlg.elevation = $l.elevation
  dlg.rows = $l.rows
  dlg.cols = $l.cols

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

  a.dialogs.activeDialog = dlgEditLevelPropsDialog


proc editLevelPropsDialog(dlg: var LevelPropertiesDialogParams; a) =
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

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonLevelFields(dimensionsDisabled=true)

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
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
    if validationError != "": return

    let elevation = parseInt(dlg.elevation)

    let coordOpts = CoordinateOptions(
      origin:      CoordinateOrigin(dlg.origin),
      rowStyle:    CoordinateStyle(dlg.rowStyle),
      columnStyle: CoordinateStyle(dlg.columnStyle),
      rowStart:    parseInt(dlg.rowStart),
      columnStart: parseInt(dlg.columnStart)
    )

    let regionOpts = RegionOptions(
      enabled:         dlg.enableRegions,
      rowsPerRegion:   parseInt(dlg.rowsPerRegion),
      colsPerRegion:   parseInt(dlg.colsPerRegion),
      perRegionCoords: dlg.perRegionCoords
    )

    actions.setLevelProperties(a.doc.map, a.ui.cursor,
                               dlg.locationName, dlg.levelName, elevation,
                               dlg.overrideCoordOpts, coordOpts, regionOpts,
                               dlg.notes,
                               a.doc.undoManager)

    setStatusMessage(fmt"Level properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Resize level dialog

proc openResizeLevelDialog(a) =
  alias(dlg, a.dialogs.resizeLevelDialog)

  let l = currLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter

  a.dialogs.activeDialog = dlgResizeLevelDialog


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
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.cols,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
      minInt: LevelColumnsLimits.minInt,
      maxInt: LevelColumnsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  y += PadYSmall
  koi.label(x, y, LabelWidth, h, "Rows", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.rows,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
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


  proc okAction(dlg: ResizeLevelDialogParams; a) =
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

    a.opts.drawTrail = false

    setStatusMessage(IconCrop, "Level resized", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.anchor = ResizeAnchor(
      handleGridRadioButton(ke, ord(dlg.anchor), AnchorIcons.len, IconsPerRow)
    )

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Delete level dialog

proc openDeleteLevelDialog(a) =
  a.dialogs.activeDialog = dlgDeleteLevelDialog


proc deleteLevelDialog(a) =
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)

  const
    DlgWidth  = ConfirmDlgWidth
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

  proc okAction(a) =
    a.opts.drawTrail = false

    let cur = actions.deleteLevel(map, a.ui.cursor, um)
    setCursor(cur, a)

    setStatusMessage(IconTrash, "Level deleted", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.theme.buttonStyle):
    okAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit note dialog

proc openEditNoteDialog(a) =
  alias(dlg, a.dialogs.editNoteDialog)

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

  a.dialogs.activeDialog = dlgEditNoteDialog


proc editNoteDialog(dlg: var EditNoteDialogParams; a) =
  let lt = a.theme.levelTheme

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
    x + LabelWidth, y, w=296, h,
    labels = @["None", "Number", "ID", "Icon"],
    dlg.kind,
    style = a.theme.radioButtonStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = lt.noteIndexBackgroundColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of akIndexed:
    koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)

    koi.radioButtons(
      x + LabelWidth, y, 28, 28,
      labels = newSeq[string](lt.noteIndexBackgroundColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc = colorRadioButtonDrawProc(
        lt.noteIndexBackgroundColor.toSeq,
        a.theme.radioButtonStyle.buttonFillColorActive
      ).some
    )

  of akCustomId:
    koi.label(x, y, LabelWidth, h, "ID", style=a.theme.labelStyle)
    koi.textField(
      x + LabelWidth, y, w=DlgNumberWidth, h,
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

  if dlg.kind in {akComment, akIndexed}:
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
    koi.label(x, y, DlgWidth, h, err, style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditNoteDialogParams; a) =
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
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=validationErrors.len > 0,
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.kind = AnnotationKind(
      handleTabNavigation(ke, ord(dlg.kind), ord(akIcon), a)
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

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit label dialog

proc openEditLabelDialog(a) =
  alias(dlg, a.dialogs.editLabelDialog)

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

  a.dialogs.activeDialog = dlgEditLabelDialog


proc editLabelDialog(dlg: var EditLabelDialogParams; a) =
  let lt = a.theme.levelTheme

  const
    DlgWidth = 486.0
    DlgHeight = 288.0
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
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = lt.noteIndexBackgroundColor.len

  koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, w=28, h=28,
    labels = newSeq[string](lt.labelTextColor.len),
    dlg.color,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc = colorRadioButtonDrawProc(
      lt.labelTextColor.toSeq,
      a.theme.radioButtonStyle.buttonFillColorActive
    ).some,
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
              style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditLabelDialogParams; a) =
    if validationError != "": return

    var note = Annotation(kind: akLabel, text: dlg.text, labelColor: dlg.color)
    actions.setLabel(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    setStatusMessage(IconComment, "Set label", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.color = handleGridRadioButton(
      ke, dlg.color, NumIndexColors, buttonsPerRow=NumIndexColors
    )

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit region properties dialog

proc openEditRegionPropertiesDialog(a) =
  alias(dlg, a.dialogs.editRegionPropsDialog)

  let region = currRegion(a).get
  dlg.name  = region.name
  dlg.notes = region.notes

  a.dialogs.activeDialog = dlgEditRegionPropsDialog


proc editRegionPropsDialog(dlg: var EditRegionPropsParams; a) =
  const
    DlgWidth = 486.0
    DlgHeight = 348.0
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
    x + LabelWidth, y, w=294, h,
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: RegionNameLimits.minRuneLen,
      maxLen: RegionNameLimits.maxRuneLen.some
    ).some,
    style = a.theme.textFieldStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Notes", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=149,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")
  else:
    if dlg.name != currRegion(a).get.name:
      for name in l.regionNames:
        if name == dlg.name:
          validationError = mkValidationError(
            "A region already exists with the same name"
          )
          break

  y += 172

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.errorLabelStyle)
    y += h


  proc okAction(dlg: EditRegionPropsParams; a) =
    alias(map, a.doc.map)
    let cur = a.ui.cursor

    let regionCoords = map.getRegionCoords(cur)
    let region = Region(name: dlg.name, notes: dlg.notes)

    actions.setRegionProperties(map, cur, regionCoords, region,
                                a.doc.undoManager)

    setStatusMessage(IconComment, "Region properties updated", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Save/discard theme changes dialog

proc openSaveDiscardThemeDialog(nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardThemeDialog)
  dlg.nextAction = nextAction
  a.dialogs.activeDialog = dlgSaveDiscardThemeDialog


proc saveDiscardThemeDialog(dlg: SaveDiscardThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made changes to the theme.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the theme?",
    style=a.theme.labelStyle
  )

  proc okAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    saveTheme(a)
    dlg.nextAction(a)

  proc discardAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a):  cancelAction(a)
    elif ke.isShortcutDown(scDiscard, a): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept, a):  okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Overwrite theme dialog

proc openOverwriteThemeDialog(themeName: string,
                              nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.overwriteThemeDialog)

  dlg.themeName = themeName
  dlg.nextAction = nextAction

  a.dialogs.activeDialog = dlgOverwriteThemeDialog


proc overwriteThemeDialog(dlg: OverwriteThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Overwrite Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h,
            fmt"User theme '{dlg.themeName}' already exists.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to overwrite it?",
    style=a.theme.labelStyle
  )

  proc okAction(dlg: OverwriteThemeDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  x -= 20
  if koi.button(x, y, DlgButtonWidth+20, h, fmt"{IconCheck} Overwrite",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += 20
  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Copy theme dialog

proc openCopyThemeDialog(a) =
  alias(dlg, a.dialogs.copyThemeDialog)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgCopyThemeDialog


proc copyThemeDialog(dlg: var CopyThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCopy}  Copy Theme",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "New Theme Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=196, h,
    dlg.newThemeName,
    activate = dlg.activateFirstTextField,
    # TODO disallow invalid path chars?
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if not gmUtils.isValidFilename(dlg.newThemeName):
    validationError = "Theme name is invalid"

  var validationWarning = ""
  let idx = findThemeIndex(dlg.newThemeName, a)
  if idx.isSome:
    let theme = a.theme.themeNames[idx.get]
    if theme.userTheme:
      validationWarning = "A user theme with this name already exists"
    else:
      validationWarning = "Built-in theme will be shadowed by this name"

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationError(validationError),
              style=a.theme.errorLabelStyle)

  elif validationWarning != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationWarning(validationWarning),
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: CopyThemeDialogParams; a) =
    closeDialog(a)
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc copyTheme(a) =
      if copyTheme(a.currThemeName, newThemePath, a):
        buildThemeList(a)
        # We need to set the current theme index directly (instead of setting
        # nextThemeIndex) to prevent reloading the theme, thus avoid losing
        # any unsaved changed
        let idx = findThemeIndex(dlg.newThemeName, a)
        if idx.isSome:
          a.theme.currThemeIndex = idx.get

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, nextAction = copyTheme, a)
    else:
      copyTheme(a)



  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Rename theme dialog

proc openRenameThemeDialog(a) =
  alias(dlg, a.dialogs.renameThemeDialog)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgRenameThemeDialog


proc renameThemeDialog(dlg: var RenameThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFile}  Rename Theme",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "New Theme Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=196, h,
    dlg.newThemeName,
    activate = dlg.activateFirstTextField,
    # TODO disallow invalid path chars?
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if not gmUtils.isValidFilename(dlg.newThemeName):
    validationError = "Theme name is invalid"

  var validationWarning = ""
  let idx = findThemeIndex(dlg.newThemeName, a)
  if idx.isSome:
    let theme = a.theme.themeNames[idx.get]
    if theme.userTheme:
      validationWarning = "A user theme with this name already exists"
    else:
      validationWarning = "Built-in theme will be shadowed by this name"

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationError(validationError),
              style=a.theme.errorLabelStyle)

  elif validationWarning != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationWarning(validationWarning),
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: RenameThemeDialogParams; a) =
    closeDialog(a)
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc renameTheme(a) =
      if renameTheme(a.currThemeName, newThemePath, a):
        buildThemeList(a)
        # We need to set the current theme index directly (instead of setting
        # nextThemeIndex) to prevent reloading the theme, thus avoid losing
        # any unsaved changed
        let idx = findThemeIndex(dlg.newThemeName, a)
        if idx.isSome:
          a.theme.currThemeIndex = idx.get

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, nextAction = renameTheme, a)
    else:
      renameTheme(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Delete theme dialog

proc openDeleteThemeDialog(a) =
  a.dialogs.activeDialog = dlgDeleteThemeDialog


proc deleteThemeDialog(a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(
    x, y, DlgWidth, h, "Are you sure you want to delete the theme?",
    style=a.theme.labelStyle
  )

  proc okAction(a) =
    if deleteTheme(a.currThemeName, a):
      buildThemeList(a)
      with a.theme:
        nextThemeIndex = min(currThemeIndex, themeNames.high).Natural.some

    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style = a.theme.buttonStyle):
    okAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# }}}

# {{{ Undoable actions

# {{{ undoAction()
proc undoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canUndo:
    let
      drawTrail = a.opts.drawTrail
      undoStateData = um.undo(a.doc.map)
      newCur = undoStateData.undoLocation
      levelChange = newCur.level != a.ui.cursor.level

    a.opts.drawTrail = false

    moveCursorTo(newCur, a)

    if not levelChange:
      a.opts.drawTrail = drawTrail

    setStatusMessage(IconUndo,
                     fmt"Undid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to undo", a=a)

# }}}
# {{{ redoAction()
proc redoAction(a) =
  alias(um, a.doc.undoManager)

  if um.canRedo:
    let
      drawTrail = a.opts.drawTrail
      undoStateData = um.redo(a.doc.map)
      newCur = undoStateData.location
      levelChange = newCur.level != a.ui.cursor.level

    a.opts.drawTrail = false

    moveCursorTo(newCur, a)

    if not levelChange:
      a.opts.drawTrail = drawTrail

    setStatusMessage(IconRedo,
                     fmt"Redid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to redo", a=a)

# }}}

# {{{ setFloorAction()
proc setFloorAction(f: Floor; a) =
  let ot = a.doc.map.guessFloorOrientation(a.ui.cursor)
  actions.setOrientedFloor(a.doc.map, a.ui.cursor, f, ot, a.ui.currFloorColor,
                           a.doc.undoManager)

  setStatusMessage(fmt"Set floor type – {f}", a)

# }}}
# {{{ cycleFloorGroupAction()
proc cycleFloorGroupAction(floors: seq[Floor], forward: bool; a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    var i = floors.find(floor)
    if i > -1:
      if forward: inc(i) else: dec(i)
      floor = floors[i.floorMod(floors.len)]
    else:
      floor = if forward: floors[0] else: floors[^1]

    setFloorAction(floor, a)
  else:
    setWarningMessage("Cannot set floor type of an empty cell", a=a)

# }}}
# {{{ startExcavateTunnelAction()
proc startExcavateTunnelAction(a) =
  let cur = a.ui.cursor
  a.ui.prevMoveDir = CardinalDir.none

  actions.excavateTunnel(a.doc.map, loc=cur, undoLoc=cur, a.ui.currFloorColor,
                         um=a.doc.undoManager, groupWithPrev=false)

  setStatusMessage(IconPencil, "Excavate tunnel", @[IconArrowsAll,
                   "excavate"], a)

# }}}
# {{{ startEraseCellsAction()
proc startEraseCellsAction(a) =
  let cur = a.ui.cursor
  actions.eraseCell(a.doc.map, loc=cur, undoLoc=cur,
                    a.doc.undoManager, groupWithPrev=false)

  setStatusMessage(IconEraser, "Erase cell", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startEraseTrailAction()
proc startEraseTrailAction(a) =
  let cur = a.ui.cursor
  actions.eraseTrail(a.doc.map, loc=cur, undoLoc=cur, a.doc.undoManager)

  setStatusMessage(IconEraser, "Erase trail", @[IconArrowsAll, "erase"], a)

# }}}

# {{{ setDrawWallActionMessage()

proc mkRepeatWallActionString(name: string; a): string =
  let action = $a.ui.drawWallRepeatAction
  fmt"repeat {action} {name}"


proc doSetDrawWallActionMessage(name: string; a) =
  var commands = @[IconArrowsAll, "set/clear"]

  if a.ui.drawWallRepeatAction != dwaNone:
    commands.add("Shift")
    commands.add(mkRepeatWallActionString(name, a))

  setStatusMessage("", fmt"Draw {name}", commands, a)


proc setDrawWallActionMessage(a) =
  doSetDrawWallActionMessage(name = "wall", a)

# }}}
# {{{ setDrawWallActionRepeatMessage()
proc doSetDrawWallActionRepeatMessage(name: string, a) =
  let icon = if a.ui.drawWallRepeatDirection.orientation == Horiz:
               IconArrowsVert
             else:
               IconArrowsHoriz

  setStatusMessage("", fmt"Draw {name} repeat",
                   @[icon, mkRepeatWallActionString(name, a)], a)


proc setDrawWallActionRepeatMessage(a) =
  doSetDrawWallActionRepeatMessage(name = "wall", a)

# }}}
# {{{ setDrawSpecialWallActionMessage()
proc setDrawSpecialWallActionMessage(a) =
  doSetDrawWallActionMessage(name = "special wall", a)

# }}}
# {{{ setDrawSpecialWallActionRepeatMessage()
proc setDrawSpecialWallActionRepeatMessage(a) =
  doSetDrawWallActionRepeatMessage(name = "special wall", a)

# }}}

# }}}
# {{{ Non-undoable actions

# {{{ openUserManual()
proc openUserManual(a) =
  openDefaultBrowser(a.paths.manualDir / "index.html")

# }}}
# {{{ openWebsite()
proc openWebsite(a) =
  openDefaultBrowser("https://gridmonger.johnnovak.net")

# }}}

# {{{ newMap()
proc newMap(a) =
  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(nextAction = openNewMapDialog, a)
  else:
    openNewMapDialog(a)

# }}}
# {{{ openMap()
proc openMap(a) =

  proc requestOpenMap(a) =
    when defined(DEBUG): discard
    else:
      let path = fileDialog(fdOpenFile, filters=GridmongerMapFileFilter)
      if path != "":
        discard loadMap(path, a)

  proc handleMapModified(a) =
    if a.doc.undoManager.isModified:
      openSaveDiscardMapDialog(nextAction = requestOpenMap, a)
    else:
      requestOpenMap(a)

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = handleMapModified, a)
  else:
    handleMapModified(a)


proc openMap(path: string; a) =
  proc doOpenMap(a) =
    discard loadMap(path, a)

  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(nextAction = doOpenMap, a)
  else:
    doOpenMap(a)

# }}}
# {{{ saveMapAs()
proc saveMapAs(a) =
  when not defined(DEBUG):
    var path = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if path != "":
      path = addFileExt(path, MapFileExt)

      saveMap(path, autosave=false, createBackup=false, a)
      a.doc.path = path

# }}}
# {{{ saveMap()
proc saveMap(a) =
  if a.doc.path == "":
    saveMapAs(a)
  else:
    saveMap(a.doc.path, autosave=false, createBackup=true, a)

# }}}

# {{{ reloadTheme()
proc reloadTheme(a) =

  proc doReloadTheme(a) =
    a.theme.nextThemeIndex = a.theme.currThemeIndex.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = doReloadTheme, a)
  else:
    doReloadTheme(a)

# }}}
# {{{ selectPrevTheme()
proc selectPrevTheme(a) =

  proc prevTheme(a) =
    var i = a.theme.currThemeIndex
    if i == 0: i = a.theme.themeNames.high else: dec(i)
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = prevTheme, a)
  else:
    prevTheme(a)

# }}}
# {{{ selectNextTheme()
proc selectNextTheme(a) =

  proc nextTheme(a) =
    var i = a.theme.currThemeIndex
    inc(i)
    if i > a.theme.themeNames.high: i = 0
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = nextTheme, a)
  else:
    nextTheme(a)

# }}}

# {{{ selectPrevLevel()
proc selectPrevLevel(a) =
  var si = currSortedLevelIdx(a)
  if si > 0:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIndexes[si - 1]
    setCursor(cur, a)

# }}}
# {{{ selectNextLevel()
proc selectNextLevel(a) =
  var si = currSortedLevelIdx(a)
  if si < a.doc.map.levels.len-1:
    var cur = a.ui.cursor
    cur.level = a.doc.map.sortedLevelIndexes[si + 1]
    setCursor(cur, a)

# }}}
# {{{ centerCursorAfterZoom()
proc centerCursorAfterZoom(a) =
  alias(dp, a.ui.drawLevelParams)
  let cur = a.ui.cursor

  let viewCol = round(a.ui.prevCursorViewX / dp.gridSize).int
  let viewRow = round(a.ui.prevCursorViewY / dp.gridSize).int
  dp.viewStartCol = max(cur.col - viewCol, 0)
  dp.viewStartRow = max(cur.row - viewRow, 0)

# }}}
# {{{ zoomIn()
proc zoomIn(a) =
  incZoomLevel(a.theme.levelTheme, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}
# {{{ zoomOut()
proc zoomOut(a) =
  decZoomLevel(a.theme.levelTheme, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}

# {{{ selectSpecialWall()
proc selectSpecialWall(index: Natural; a) =
  assert index <= SpecialWalls.high
  a.ui.currSpecialWall = index

# }}}
# {{{ selectPrevFloorColor()
proc selectPrevFloorColor(a) =
  if a.ui.currFloorColor > 0: dec(a.ui.currFloorColor)
  else: a.ui.currFloorColor = a.theme.levelTheme.floorBackgroundColor.high

# }}}
# {{{ selectNextFloorColor()
proc selectNextFloorColor(a) =
  if a.ui.currFloorColor < a.theme.levelTheme.floorBackgroundColor.high:
    inc(a.ui.currFloorColor)
  else: a.ui.currFloorColor = 0

# }}}
# {{{ pickFloorColor()
proc pickFloorColor(a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    a.ui.currFloorColor = a.doc.map.getFloorColor(a.ui.cursor)
    setStatusMessage(NoIcon, "Picked floor colour", a)
  else:
    setWarningMessage("Cannot pick floor colour of an empty cell", a=a)

# }}}
# {{{ selectFloorColor()
proc selectFloorColor(index: Natural; a) =
  assert index <= LevelTheme.floorBackgroundColor.high
  a.ui.currFloorColor = index

# }}}

# }}}
# {{{ Event handling

# {{{ resetManualNoteTooltip()
proc resetManualNoteTooltip(a) =
  with a.ui.manualNoteTooltipState:
    show = false
    mx = -1
    my = -1

# }}}

# {{{ enterDrawWallMode()
proc enterDrawWallMode(specialWall: bool; a) =
  a.ui.editMode = if specialWall: emDrawSpecialWall else: emDrawWall
  a.ui.drawWallRepeatAction = dwaNone

  if specialWall:
    setDrawSpecialWallActionMessage(a)
  else:
    setDrawWallActionMessage(a)

# }}}
# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents(a) =

  # {{{ moveCursorToMousePos()
  proc moveCursorToMousePos(a) =
    alias(dp, a.ui.drawLevelParams)
    alias(ui, a.ui)

    let loc = locationAtMouse(clampToBounds=true, a)
    if loc.isSome:
      resetManualNoteTooltip(a)
      a.ui.cursor = loc.get
      if ui.editMode in {emPastePreview, emMovePreview}:
        dp.selStartRow = ui.cursor.row
        dp.selStartCol = ui.cursor.col

  # }}}
  # {{{ enterPanLevelMode()
  proc enterPanLevelMode(mode: PanLevelMode; a) =
    alias(ui, a.ui)
    ui.prevEditMode = ui.editMode
    ui.editMode = emPanLevel;
    ui.mouseDragStartX = koi.mx()
    ui.mouseDragStartY = koi.my()
    ui.panLevelMode = mode

  # }}}
  # {{{ handleMoveCursorOrPanSimple()
  proc handleMoveCursorOrPanSimple(a) =
    if koi.mbLeftDown():
      if koi.ctrlDown():
        enterPanLevelMode(dlmCtrlLeftButton, a)
      else:
        moveCursorToMousePos(a)
    elif koi.mbMiddleDown():
      enterPanLevelMode(dlmMiddleButton, a)

  # }}}
  # {{{ handlePanLevel()
  proc handlePanLevel(a) =
    alias(ui, a.ui)
    alias(dp, a.ui.drawLevelParams)

    let dx = ui.mouseDragStartX - koi.mx()
    let dy = ui.mouseDragStartY - koi.my()

    const SensitivityMin = 10
    const SensitivityMax = 35

    let sensitivity = remap(
      inMin=MinZoomLevel, inMax=MaxZoomLevel,
      outMin=SensitivityMin, outMax=SensitivityMax,
      dp.getZoomLevel().float
    )
    let colSteps = (dx / sensitivity).int
    let rowSteps = (dy / sensitivity).int

    if colSteps == 0: discard
    else:
      ui.mouseDragStartX = koi.mx()
      if colSteps > 0: moveLevelView(East,  colSteps, a)
      else:            moveLevelView(West, -colSteps, a)

    if rowSteps == 0: discard
    else:
      ui.mouseDragStartY = koi.my()
      if rowSteps > 0: moveLevelView(South,  rowSteps, a)
      else:            moveLevelView(North, -rowSteps, a)

    if ui.editMode == emPanLevel and
      ui.prevEditMode in {emPastePreview, emMovePreview}:
      dp.selStartRow = ui.cursor.row
      dp.selStartCol = ui.cursor.col

  # }}}
  # {{{ handlePanLevelExit()
  proc handlePanLevelExit(a) =
    alias(ui, a.ui)
    case ui.panLevelMode
    of dlmCtrlLeftButton:
      if not koi.ctrlDown() or not koi.mbLeftDown():
        ui.editMode = ui.prevEditMode
    of dlmMiddleButton:
      if not koi.mbMiddleDown():
        ui.editMode = ui.prevEditMode

  # }}}

  alias(ui, a.ui)

  # {{{ WASD mode

  if a.opts.wasdMode:
    case ui.editMode
    of emNormal:
      if koi.mbLeftDown():
        if ui.mouseCanStartExcavate:
          if koi.shiftDown():
            if koi.ctrlDown():
              enterPanLevelMode(dlmCtrlLeftButton, a)
            else:
              moveCursorToMousePos(a)
          else:
            ui.editMode = emExcavateTunnel
            startExcavateTunnelAction(a)
      else:
        ui.mouseCanStartExcavate = true

      if koi.mbRightDown():
        enterDrawWallMode(specialWall=false, a)

      elif koi.mbMiddleDown():
        if koi.shiftDown():
          enterPanLevelMode(dlmMiddleButton, a)
        else:
          ui.editMode = emEraseCell
          startEraseCellsAction(a)

    of emColorFloor, emDrawClearFloor:
      discard

    of emDrawWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)
      else:
        if koi.mbLeftDown():
          enterDrawWallMode(specialWall=true, a)

    of emDrawWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emDrawSpecialWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavate=false
        clearStatusMessage(a)
      else:
        if not koi.mbLeftDown():
          enterDrawWallMode(specialWall=false, a)

    of emDrawSpecialWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavate = false
        clearStatusMessage(a)

    of emEraseCell:
      if not koi.mbMiddleDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emEraseTrail:
      discard

    of emExcavateTunnel:
      if not koi.mbLeftDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emNudgePreview:
      discard

    of emSelect, emSetCellLink, emPastePreview, emMovePreview:
      handleMoveCursorOrPanSimple(a)

    of emSelectDraw, emSelectErase, emSelectRect:
      if koi.mbLeftDown():
        moveCursorToMousePos(a)

    of emSelectJumpToLinkSrc:
      discard

    of emPanLevel:
      handlePanLevel(a)
      handlePanLevelExit(a)

  # }}}
  # {{{ Normal mode
  else:
    case ui.editMode
    of emNormal, emSelect, emSetCellLink, emPastePreview, emMovePreview:
      handleMoveCursorOrPanSimple(a)

    of emSelectDraw, emSelectErase, emSelectRect:
      if koi.mbLeftDown():
        moveCursorToMousePos(a)

    of emPanLevel:
      handlePanLevel(a)
      handlePanLevelExit(a)

    else: discard
  # }}}

# }}}

# {{{ setSelectJumpToLinkActionMessage()
proc setSelectJumpToLinkSrcActionMessage(a) =
  let currIdx = a.ui.jumpToSrcLocationIdx + 1
  let count = a.ui.jumpToSrcLocations.len
  let floor = a.doc.map.getFloor(a.ui.jumpToDestLocation)

  setStatusMessage(NoIcon,
                   fmt"Select {linkFloorToString(floor)} source ({currIdx} of {count})",
                   @[IconArrowsAll, "next/prev", "Enter/Esc", "exit"],
                   a)

# }}}
# {{{ handleGlobalKeyEvents()

template toggleOption(opt: untyped, icon, msg, on, off: string; a) =
  opt = not opt
  let state = if opt: on else: off
  setStatusMessage(icon, msg & " " & state, a)

template toggleShowOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="shown", off="hidden", a)

template toggleOnOffOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="on", off="off", a)

proc toggleThemeEditor(a) =
  toggleShowOption(a.opts.showThemeEditor, NoIcon, "Theme editor pane", a)

proc showQuickReference(a) =
  a.opts.showQuickReference = true
  setStatusMessage(IconQuestion, "Quick keyboard reference",
                   @[fmt"Ctrl+{IconArrowsHoriz}", "switch tab",
                     "Esc/Space/Enter", "exit",
                     "F1", "open user manual"], a)

proc toggleTitleBar(a) =
  toggleShowOption(a.win.showTitleBar, NoIcon, "Title bar", a)

# TODO separate into level events and global events?
proc handleGlobalKeyEvents(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)
  alias(opts, a.opts)
  alias(dp, a.ui.drawLevelParams)

  var l = currLevel(a)

  let yubnMode = a.prefs.yubnMovementKeys

  proc turnLeft(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) - 1, ord(CardinalDir.high) + 1))

  proc turnRight(dir: CardinalDir): CardinalDir =
    CardinalDir(floorMod(ord(dir) + 1, ord(CardinalDir.high) + 1))

  template backward(): auto = turnLeft(turnLeft(ui.cursorOrient))
  template left():     auto = turnLeft(ui.cursorOrient)
  template right():    auto = turnRight(ui.cursorOrient)

  # {{{ handleMoveWalk()
  proc handleMoveWalk(ke: Event; a) =
    var s = 1
    if mkCtrl in ke.mods:
      if ke.key in AllWasdMoveKeys: return
      else: s = CursorJump

    let altDown = mkAlt in ke.mods

    var ke = ke
    ke.mods = ke.mods - {mkCtrl, mkAlt}

    let k = if opts.wasdMode: ui.walkKeysWasd else: ui.walkKeysCursor

    if   ke.isKeyDown(k.forward,  repeat=true):
      moveCursor(ui.cursorOrient, s, a)

    elif ke.isKeyDown(k.backward, repeat=true):
      moveCursor(backward(), s, a)

    elif ke.isKeyDown(k.forward,  {mkShift}, repeat=true):
      moveLevelView({ui.cursorOrient}, s, a)

    elif ke.isKeyDown(k.backward, {mkShift}, repeat=true):
      moveLevelView({backward()}, s, a)

    case a.prefs.walkCursorMode:
    of wcmStrafe:
      if   ke.isKeyDown(k.strafeLeft,             repeat=true) or
           ke.isKeyDown(k.strafeLeft,  {mkShift}, repeat=true):
        if altDown: ui.cursorOrient = left()
        else:       moveCursor(left(), s, a)

      elif ke.isKeyDown(k.strafeRight,            repeat=true) or
           ke.isKeyDown(k.strafeRight, {mkShift}, repeat=true):
        if altDown: ui.cursorOrient = right()
        else:       moveCursor(right(), s, a)

    of wcmTurn:
      if   ke.isKeyDown(k.turnLeft) or
           ke.isKeyDown(k.turnLeft, {mkShift}):
        if altDown: moveCursor(left(), s, a)
        else:       ui.cursorOrient = left()

      elif ke.isKeyDown(k.turnRight) or
           ke.isKeyDown(k.turnRight, {mkShift}):
        if altDown: moveCursor(right(), s, a)
        else:       ui.cursorOrient = right()

  # }}}
  # {{{ moveKeyToCardinalDir()
  template moveKeyToCardinalDir(ke: Event, allowWasdKeys: bool,
                                allowRepeat: bool): Option[CardinalDir] =

    let k = if allowWasdKeys and opts.wasdMode: MoveKeysWasd
            else: MoveKeysCursor

    var kk = ke
    kk.mods = {}

    if   kk.isKeyDown(k.left,  repeat=allowRepeat): dirW.some
    elif kk.isKeyDown(k.right, repeat=allowRepeat): dirE.some
    elif kk.isKeyDown(k.up,    repeat=allowRepeat): dirN.some
    elif kk.isKeyDown(k.down,  repeat=allowRepeat): dirS.some
    else: CardinalDir.none

  # }}}
  # {{{ handleMoveKeys()
  template handleMoveKeys(ke: Event, allowWasdKeys, allowRepeat: bool,
                          allowDiagonal: bool, moveHandler: untyped) =

    if allowDiagonal:
      # Ignore Y/U/B/N keys if YUBN movement is not enabled in the prefs
      if not yubnMode and ke.key in DiagonalMoveLetterKeys:
        return

    let mods = ke.mods

    let dir = moveKeyToCardinalDir(ke, allowWasdKeys, allowRepeat)
    if dir.isSome:
      moveHandler(dir.get, mods, a)

    if allowDiagonal:
      let d = DiagonalMoveKeysCursor

      if ke.isKeyDown(d.upLeft, repeat=allowRepeat):
        moveHandler(dirN, mods, a)
        moveHandler(dirW, mods, a)

      elif ke.isKeyDown(d.upRight, repeat=allowRepeat):
        moveHandler(dirN, mods, a)
        moveHandler(dirE, mods, a)

      elif ke.isKeyDown(d.downLeft, repeat=allowRepeat):
        moveHandler(dirS, mods, a)
        moveHandler(dirW, mods, a)

      elif ke.isKeyDown(d.downRight, repeat=allowRepeat):
        moveHandler(dirS, mods, a)
        moveHandler(dirE, mods, a)

  # }}}
  # {{{ handleMoveCursor()
  proc handleMoveCursor(ke: Event; allowPan, allowJump, allowWasdKeys: bool,
                        allowDiagonal: bool; a): bool =

    if allowDiagonal:
      # Ignore Y/U/B/N keys if YUBN movement is not enabled in the prefs
      if not yubnMode and ke.key in DiagonalMoveLetterKeys:
        return

    var s = 1
    if allowJump and mkCtrl in ke.mods:
      if ke.key in AllWasdMoveKeys:
        # Disallow Ctrl+Q/W/E/A/S/D jump as it would interfere with shorcuts
        return

      elif ke.key in DiagonalMoveLetterKeys:
        # Disallow Ctrl+Y/U/B/N panning as it would interfere with shorcuts
        return
      else:
        s = CursorJump

    let k = if allowWasdKeys and opts.wasdMode: MoveKeysWasd
            else: MoveKeysCursor

    var ke = ke
    ke.mods = ke.mods - {mkCtrl}

    result = true

    if   ke.isKeyDown(k.left,  repeat=true): moveCursor(dirW, s, a)
    elif ke.isKeyDown(k.right, repeat=true): moveCursor(dirE, s, a)
    elif ke.isKeyDown(k.up,    repeat=true): moveCursor(dirN, s, a)
    elif ke.isKeyDown(k.down,  repeat=true): moveCursor(dirS, s, a)
    elif allowPan:
      if   ke.isKeyDown(k.left,  {mkShift}, repeat=true): moveLevelView(West,  s, a)
      elif ke.isKeyDown(k.right, {mkShift}, repeat=true): moveLevelView(East,  s, a)
      elif ke.isKeyDown(k.up,    {mkShift}, repeat=true): moveLevelView(North, s, a)
      elif ke.isKeyDown(k.down,  {mkShift}, repeat=true): moveLevelView(South, s, a)

    if allowDiagonal:
      let d = DiagonalMoveKeysCursor

      # move cursor
      if ke.isKeyDown(d.upLeft, repeat=true):
        moveCursorDiagonal(NorthWest, s, a)

      elif ke.isKeyDown(d.upRight, repeat=true):
        moveCursorDiagonal(NorthEast, s, a)

      elif ke.isKeyDown(d.downLeft, repeat=true):
        moveCursorDiagonal(SouthWest, s, a)

      elif ke.isKeyDown(d.downRight, repeat=true):
        moveCursorDiagonal(SouthEast, s, a)

      # move level
      elif ke.isKeyDown(d.upLeft, {mkShift}, repeat=true):
        moveLevelView(NorthWest, s, a)

      elif ke.isKeyDown(d.upRight, {mkShift}, repeat=true):
        moveLevelView(NorthEast, s, a)

      elif ke.isKeyDown(d.downLeft, {mkShift}, repeat=true):
        moveLevelView(SouthWest, s, a)

      elif ke.isKeyDown(d.downRight, {mkShift}, repeat=true):
        moveLevelView(SouthEast, s, a)

    result = false

  # }}}
  # {{{ drawWallRepeatMoveKeyHandler()
  proc drawWallRepeatMoveKeyHandler(dir: CardinalDir, mods: set[ModifierKey];
                                    a) =
    let cur = ui.cursor
    let drawDir = ui.drawWallRepeatDirection

    if dir.orientation == drawDir.orientation.opposite:
      let newCur = stepCursor(cur, dir, steps=1, a)
      if newCur != cur:
        if map.canSetWall(newCur, drawDir):
          setCursor(newCur, a)
          actions.setWall(map, loc=newCur, undoLoc=cur, drawDir,
                          ui.drawWallRepeatWall, um,
                          groupWithPrev=opts.drawTrail)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)
    else:
      setWarningMessage(
        fmt"Can only repeat in {dir.orientation.opposite} direction",
        keepStatusMessage=true, a=a
      )

  # }}}

  if hasKeyEvent():
    let ke = koi.currEvent()
    # TODO eventHandled is not set here, but it's not actually needed (yet)

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # TODO revisit tooltip reset logic
      # Reset tooltip display on certain keypresses only
      if not (ke.key == keySpace) and
         not (ke.action == kaUp) and
         not (ke.key in {keyLeftControl,  keyLeftShift,  keyLeftAlt,
                         keyRightControl, keyRightShift, keyRightAlt}):
        resetManualNoteTooltip(a)

      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        if handleMoveCursor(ke, allowPan=true, allowJump=true,
                            allowWasdKeys=true, allowDiagonal=true, a):
          setStatusMessage("moved", a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true, a=a): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true, a=a): selectNextLevel(a)

      let cur = ui.cursor

      if not opts.wasdMode and ke.isShortcutDown(scExcavateTunnel, a):
        ui.editMode = emExcavateTunnel
        startExcavateTunnelAction(a)

      elif not (opts.wasdMode and opts.walkMode) and
           ke.isShortcutDown(scEraseCell, a):
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

      elif ke.isShortcutDown(scDrawClearFloor, a):
        ui.editMode = emDrawClearFloor
        setStatusMessage(IconEraser, "Draw/clear floor",
                         @[IconArrowsAll, "draw/clear"], a)

        actions.drawClearFloor(map, loc=cur, undoLoc=cur,
                               ui.currFloorColor, um, groupWithPrev=false)

      elif ke.isShortcutDown(scToggleFloorOrientation, a):
        let floor = map.getFloor(cur)

        if floor != fEmpty:
          actions.toggleFloorOrientation(map, cur, um)
          if map.getFloorOrientation(cur) == Horiz:
            setStatusMessage(IconArrowsHoriz,
                             "Floor orientation set to horizontal", a)
          else:
            setStatusMessage(IconArrowsVert,
                             "Floor orientation set to vertical", a)
        else:
          setWarningMessage("Cannot set floor orientation of an empty cell",
                            a=a)

      elif ke.isShortcutDown(scSetFloorColor, a):
        ui.editMode = emColorFloor
        setStatusMessage(IconEraser, "Set floor colour",
                         @[IconArrowsAll, "set colour"], a)

        if not map.isEmpty(cur):
          actions.setFloorColor(map, loc=cur, undoLoc=cur,
                                ui.currFloorColor, um, groupWithPrev=false)

      elif not opts.wasdMode and ke.isShortcutDown(scDrawWall, a):
        enterDrawWallMode(specialWall=false, a)

      elif ke.isShortcutDown(scDrawSpecialWall, a):
        enterDrawWallMode(specialWall=true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Forward, a):
        cycleFloorGroupAction(FloorGroup1, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Forward, a):
        cycleFloorGroupAction(FloorGroup2, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Forward, a):
        cycleFloorGroupAction(FloorGroup3, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Forward, a):
        cycleFloorGroupAction(FloorGroup4, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Forward, a):
        cycleFloorGroupAction(FloorGroup5, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Forward, a):
        cycleFloorGroupAction(FloorGroup6, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Forward, a):
        cycleFloorGroupAction(FloorGroup7, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup8Forward, a):
        cycleFloorGroupAction(FloorGroup8, forward=true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Backward, a):
        cycleFloorGroupAction(FloorGroup1, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Backward, a):
        cycleFloorGroupAction(FloorGroup2, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Backward, a):
        cycleFloorGroupAction(FloorGroup3, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Backward, a):
        cycleFloorGroupAction(FloorGroup4, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Backward, a):
        cycleFloorGroupAction(FloorGroup5, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Backward, a):
        cycleFloorGroupAction(FloorGroup6, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Backward, a):
        cycleFloorGroupAction(FloorGroup7, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup8Backward, a):
        cycleFloorGroupAction(FloorGroup8, forward=false, a)

      elif ke.isShortcutDown(scSelectSpecialWall1, a):  selectSpecialWall(0, a)
      elif ke.isShortcutDown(scSelectSpecialWall2, a):  selectSpecialWall(1, a)
      elif ke.isShortcutDown(scSelectSpecialWall3, a):  selectSpecialWall(2, a)
      elif ke.isShortcutDown(scSelectSpecialWall4, a):  selectSpecialWall(3, a)
      elif ke.isShortcutDown(scSelectSpecialWall5, a):  selectSpecialWall(4, a)
      elif ke.isShortcutDown(scSelectSpecialWall6, a):  selectSpecialWall(5, a)
      elif ke.isShortcutDown(scSelectSpecialWall7, a):  selectSpecialWall(6, a)
      elif ke.isShortcutDown(scSelectSpecialWall8, a):  selectSpecialWall(7, a)
      elif ke.isShortcutDown(scSelectSpecialWall9, a):  selectSpecialWall(8, a)
      elif ke.isShortcutDown(scSelectSpecialWall10, a): selectSpecialWall(9, a)
      elif ke.isShortcutDown(scSelectSpecialWall11, a): selectSpecialWall(10, a)
      elif ke.isShortcutDown(scSelectSpecialWall12, a): selectSpecialWall(11, a)

      elif ke.isShortcutDown(scPreviousSpecialWall, repeat=true, a=a):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isShortcutDown(scNextSpecialWall, repeat=true, a=a):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isShortcutDown(scEraseTrail, a):
        if not opts.drawTrail:
          ui.editMode = emEraseTrail
          startEraseTrailAction(a)
        else:
          setWarningMessage("Cannot erase trail when draw trail is on", a=a)

      elif ke.isShortcutDown(scExcavateTrail, a):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.excavateTrail(map, cur, bbox.get, ui.currFloorColor, um)
          actions.clearTrailInLevel(map, cur, bbox.get, um, groupWithPrev=true,
                                    actionName="Excavate trail in level")

          setStatusMessage(IconPencil, "Trail excavated in level", a)
        else:
          setWarningMessage("No trail to excavate", a=a)

      elif ke.isShortcutDown(scClearTrail, a):
        let bbox = l.calcTrailBoundingBox()
        if bbox.isSome:
          actions.clearTrailInLevel(map, cur, bbox.get, um)
          setStatusMessage(IconEraser, "Cleared trail in level", a)
        else:
          setWarningMessage("No trail to clear", a=a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true, a=a):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true, a=a):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor, a): pickFloorColor(a)

      elif ke.isShortcutDown(scSelectFloorColor1, a):  selectFloorColor(0, a)
      elif ke.isShortcutDown(scSelectFloorColor2, a):  selectFloorColor(1, a)
      elif ke.isShortcutDown(scSelectFloorColor3, a):  selectFloorColor(2, a)
      elif ke.isShortcutDown(scSelectFloorColor4, a):  selectFloorColor(3, a)
      elif ke.isShortcutDown(scSelectFloorColor5, a):  selectFloorColor(4, a)
      elif ke.isShortcutDown(scSelectFloorColor6, a):  selectFloorColor(5, a)
      elif ke.isShortcutDown(scSelectFloorColor7, a):  selectFloorColor(6, a)
      elif ke.isShortcutDown(scSelectFloorColor8, a):  selectFloorColor(7, a)
      elif ke.isShortcutDown(scSelectFloorColor9, a):  selectFloorColor(8, a)
      elif ke.isShortcutDown(scSelectFloorColor10, a): selectFloorColor(9, a)

      elif ke.isShortcutDown(scUndo, repeat=true, a=a): undoAction(a)
      elif ke.isShortcutDown(scRedo, repeat=true, a=a): redoAction(a)

      elif ke.isShortcutDown(scMarkSelection, a):
        enterSelectMode(a)

      elif ke.isShortcutDown(scPaste, a):
        if ui.copyBuf.isSome:
          actions.pasteSelection(map, loc=cur, undoLoc=cur, ui.copyBuf.get,
                                 pasteBufferLevelIndex=Natural.none,
                                 wraparound=false, um)

          setStatusMessage(IconPaste, "Buffer pasted", a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scPastePreview, a):
        if ui.copyBuf.isSome:
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          opts.drawTrail = false
          ui.editMode = emPastePreview

          setPastePreviewModeMessage(a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scNudgePreview, a):
        let sel = newSelection(l.rows, l.cols)
        sel.fill(true)

        # The level is cleared for the duration of the nudge operation and it
        # is stored temporarily in the SelectionBuffer.
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

        setNudgePreviewModeMessage(a)

      elif ke.isShortcutDown(scJumpToLinkedCell, a):
        let otherLocs = map.getLinkedLocations(cur)

        if otherLocs.len == 1:
          let otherLoc = otherLocs.first.get
          if map.getLinkedLocations(otherLoc).len > 1:
            ui.lastJumpToSrcLocation = cur
          moveCursorTo(otherLoc, a)

        elif otherLocs.len > 1:
          ui.jumpToSrcLocations = otherLocs.toSeq
          sort(ui.jumpToSrcLocations)

          # Try to continue selecting sources from the last source we left at.
          let oldIdx = ui.jumpToSrcLocations.find(ui.lastJumpToSrcLocation)
          if oldIdx == -1:
            # The source we left at last time doesn't exist (e.g. the user deleted
            # it or wasn't linked to this destination), so reset from beginning.
            ui.jumpToSrcLocationIdx = 0
          else:
            ui.jumpToSrcLocationIdx = oldIdx

          ui.jumpToDestLocation = cur
          ui.lastJumpToSrcLocation = ui.jumpToSrcLocations[ui.jumpToSrcLocationIdx]
          ui.wasDrawingTrail = opts.drawTrail
          opts.drawTrail = false

          moveCursorTo(ui.lastJumpToSrcLocation, a)
          ui.editMode = emSelectJumpToLinkSrc
          setSelectJumpToLinkSrcActionMessage(a)
        else:
          setWarningMessage("Not a linked cell", a=a)

      elif ke.isShortcutDown(scLinkCell, a):
        let floor = map.getFloor(cur)
        if floor in LinkSources:
          ui.linkSrcLocation = cur
          ui.editMode = emSetCellLink
          setSetLinkDestinationMessage(floor, a)
        else:
          setWarningMessage("Cannot link current cell", a=a)

      elif ke.isShortcutDown(scZoomIn, repeat=true, a=a):
        zoomIn(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel()}", a)

      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a):
        zoomOut(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel()}", a)

      elif ke.isShortcutDown(scEditNote, a):
        if map.isEmpty(cur):
          setWarningMessage("Cannot attach note to empty cell", a=a)
        else:
          openEditNoteDialog(a)

      elif ke.isShortcutDown(scEraseNote, a):
        if map.hasNote(cur):
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)
        else:
          setWarningMessage("No note to erase in cell", a=a)

      elif ke.isShortcutDown(scEditLabel, a):
        openEditLabelDialog(a)

      elif ke.isShortcutDown(scEraseLabel, a):
        if map.hasLabel(cur):
          actions.eraseLabel(map, cur, um)
          setStatusMessage(IconEraser, "Label erased", a)
        else:
          setWarningMessage("No label to erase in cell", a=a)

      elif ke.isShortcutDown(scShowNoteTooltip, a):
        if ui.manualNoteTooltipState.show:
          resetManualNoteTooltip(a)
        else:
          if map.hasNote(cur):
            with ui.manualNoteTooltipState:
              show = true
              location = cur
              mx = koi.mx()
              my = koi.my()

      elif ke.isShortcutDown(scEditPreferences, a): openPreferencesDialog(a)

      elif ke.isShortcutDown(scNewLevel, a):
        if map.levels.len < NumLevelsLimits.maxInt:
          openNewLevelDialog(a)
        else:
          setWarningMessage(
            "Cannot add new level: maximum number of levels has been reached " &
            fmt"({NumLevelsLimits.maxInt})", a=a
          )

      elif ke.isShortcutDown(scDeleteLevel, a):
        openDeleteLevelDialog(a)

      elif ke.isShortcutDown(scNewMap, a): newMap(a)
      elif ke.isShortcutDown(scEditMapProps, a): openEditMapPropsDialog(a)

      elif ke.isShortcutDown(scEditLevelProps, a):
        openEditLevelPropsDialog(a)

      elif ke.isShortcutDown(scResizeLevel, a):
        openResizeLevelDialog(a)

      elif ke.isShortcutDown(scEditRegionProps, a):
        if l.regionOpts.enabled:
          openEditRegionPropertiesDialog(a)
        else:
          setWarningMessage(
            "Cannot edit region properties: regions are not enabled for level",
            a=a
          )

      elif ke.isShortcutDown(scOpenMap, a):       openMap(a)
      elif ke.isShortcutDown(scSaveMap, a):       saveMap(a)
      elif ke.isShortcutDown(scSaveMapAs, a):     saveMapAs(a)

      elif ke.isShortcutDown(scReloadTheme, a):   reloadTheme(a)
      elif ke.isShortcutDown(scPreviousTheme, a): selectPrevTheme(a)
      elif ke.isShortcutDown(scNextTheme, a):     selectNextTheme(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

      elif ke.isShortcutDown(scShowAboutDialog, a):
        openAboutDialog(a)

      elif ke.isShortcutDown(scToggleThemeEditor, a):
        toggleThemeEditor(a)

      elif ke.isShortcutDown(scToggleQuickReference, a):
        showQuickReference(a)

      # Toggle options
      elif ke.isShortcutDown(scToggleCellCoords, a):
        toggleShowOption(dp.drawCellCoords, NoIcon, "Cell coordinates", a)

      elif ke.isShortcutDown(scToggleCurrentNotePane, a):
        toggleShowOption(opts.showCurrentNotePane, NoIcon,
                         "Current note pane", a)

      elif ke.isShortcutDown(scToggleNotesListPane, a):
        toggleShowOption(opts.showNotesListPane, NoIcon,
                         "Note list pane", a)

      elif ke.isShortcutDown(scToggleToolsPane, a):
        toggleShowOption(opts.showToolsPane, NoIcon, "Tools pane", a)

      elif ke.isShortcutDown(scToggleWalkMode, a):
        opts.walkMode = not opts.walkMode
        let msg = if opts.walkMode: "Walk mode" else: "Normal mode"
        setStatusMessage(msg, a)

      elif ke.isShortcutDown(scToggleWasdMode, a):
        toggleOnOffOption(opts.wasdMode, IconMouse, "WASD mode", a)

      elif ke.isShortcutDown(scToggleDrawTrail, a):
        if not opts.drawTrail:
          actions.drawTrail(map, loc=cur, undoLoc=cur, um)
        toggleOnOffOption(opts.drawTrail, IconShoePrints, "Draw trail", a)

      elif ke.isShortcutDown(scToggleTitleBar, a):
        toggleTitleBar(a)

    # }}}
    # {{{ emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor
    of emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor:
      let prevMoveDir = a.ui.prevMoveDir

      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        let allowDiagonal = ui.editMode != emExcavateTunnel
        discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                                 allowWasdKeys=true,
                                 allowDiagonal=allowDiagonal, a)
      let cur = ui.cursor

      if cur != ui.prevCursor:
        if   ui.editMode == emExcavateTunnel:
          if a.prefs.openEndedExcavate:
            let dir = if opts.walkMode: ui.cursorOrient.some
                      else: moveKeyToCardinalDir(ke, allowWasdKeys=true,
                                                 allowRepeat=true)

            actions.excavateTunnel(map, loc=cur, undoLoc=ui.prevCursor,
                                   ui.currFloorColor, dir,
                                   prevDir=prevMoveDir,
                                   prevLoc=ui.prevCursor.some,
                                   um, groupWithPrev=opts.drawTrail)
          else:
            actions.excavateTunnel(a.doc.map, loc=cur, undoLoc=cur,
                                   a.ui.currFloorColor,
                                   um=um, groupWithPrev=opts.drawTrail)

        elif ui.editMode == emEraseCell:
          actions.eraseCell(map, loc=cur, undoLoc=ui.prevCursor,
                            um, groupWithPrev=opts.drawTrail)

        elif ui.editMode == emEraseTrail:
          actions.eraseTrail(map, loc=cur, undoLoc=cur, um)

        elif ui.editMode == emDrawClearFloor:
          actions.drawClearFloor(map, loc=cur, undoLoc=ui.prevCursor,
                                 ui.currFloorColor,
                                 um, groupWithPrev=opts.drawTrail)

        elif ui.editMode == emColorFloor:
          if not map.isEmpty(cur):
            actions.setFloorColor(map, loc=cur, undoLoc=ui.prevCursor,
                                  ui.currFloorColor,
                                  um, groupWithPrev=opts.drawTrail)

      if not opts.wasdMode and ke.isShortcutUp(scExcavateTunnel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isShortcutUp({scEraseCell, scDrawClearFloor, scEraseTrail,
                          scSetFloorColor}, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        let cur = ui.cursor

        if map.canSetWall(cur, dir):
          let w = if map.getWall(cur, dir) == wWall: wNone
                  else: wWall

          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, loc=cur, undoLoc=cur, dir, w, um,
                          groupWithPrev=false)

          setDrawWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if not opts.wasdMode and ke.isShortcutUp(scDrawWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat, ignoreMods=true, a=a):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawWallRepeat
          setDrawWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat, a):
        setDrawWallActionMessage(a)

    # }}}
    # {{{ emDrawWallRepeat
    of emDrawWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     allowDiagonal=false, drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat, a):
        ui.editMode = emDrawWall
        setDrawWallActionMessage(a)

      if not opts.wasdMode and ke.isShortcutUp(scDrawWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawSpecialWall
    of emDrawSpecialWall:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        let cur = ui.cursor

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

          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, loc=cur, undoLoc=cur, dir, w, um,
                          groupWithPrev=false)

          setDrawSpecialWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if ke.isShortcutUp(scDrawSpecialWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat, ignoreMods=true, a=a):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawSpecialWallRepeat
          setDrawSpecialWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat, a):
        setDrawSpecialWallActionMessage(a)

    # }}}
    # {{{ emDrawSpecialWallRepeat
    of emDrawSpecialWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     allowDiagonal=false, drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat, a):
        ui.editMode = emDrawSpecialWall
        setDrawSpecialWallActionMessage(a)

      if ke.isShortcutUp(scDrawSpecialWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      if   koi.ctrlDown(): setSelectModeSpecialActionsMessage(a)
      else:                setSelectModeSelectMessage(a)

      if   ke.isShortcutDown(scSelectionDraw, a):
        ui.selection.get[cur.row, cur.col] = true
        ui.editMode = emSelectDraw

      elif ke.isShortcutDown(scSelectionErase, a):
        ui.selection.get[cur.row, cur.col] = false
        ui.editMode = emSelectErase

      elif ke.isShortcutDown(scSelectionAll, a):  ui.selection.get.fill(true)

      elif ke.isShortcutDown(scSelectionNone, a):
        ui.selection.get.fill(false)

      elif ke.isShortcutDown({scSelectionAddRect, scSelectionSubRect}, a):
        ui.editMode = emSelectRect
        ui.selRect = some(SelectionRect(
          startRow: cur.row,
          startCol: cur.col,
          rect: rectN(cur.row, cur.col, cur.row+1, cur.col+1),
          selected: ke.isShortcutDown(scSelectionAddRect, a)
        ))

      elif ke.isShortcutDown(scSelectionCopy, a):
        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isShortcutDown(scSelectionMove, a):
        let selection = ui.selection.get
        let bbox = copySelection(ui.nudgeBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            level: cur.level,
            col: bbox.c1,
            row: bbox.r1
          )
          ui.pasteUndoLocation = bboxTopLeft

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
          setMovePreviewModeMessage(a)

      elif ke.isShortcutDown(scSelectionEraseArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.eraseSelection(map, cur.level, selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isShortcutDown(scSelectionFillArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.fillSelection(map, cur.level, selection, bbox.get,
                                ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Filled selection", a)

      elif ke.isShortcutDown(scSelectionSurroundArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.surroundSelectionWithWalls(map, cur.level, selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Surrounded selection with walls", a)

      elif ke.isShortcutDown(scSelectionSetFloorColorArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.setSelectionFloorColor(map, cur.level, selection,
                                         bbox.get, ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Set floor colour of selection", a)

      elif ke.isShortcutDown(scSelectionCropArea, a):
        let sel = ui.selection.get
        let bbox = sel.boundingBox
        if bbox.isSome:
          let newCur = actions.cropLevel(map, cur, bbox.get, um)
          moveCursorTo(newCur, a)
          exitSelectMode(a)
          setStatusMessage(IconPencil, "Cropped level to selection", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true, a=a):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true, a=a):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor, a): pickFloorColor(a)

      elif ke.isShortcutDown(scCancel, a):
        exitSelectMode(a)
        a.clearStatusMessage()

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

    # }}}
    # {{{ emSelectDraw, emSelectErase
    of emSelectDraw, emSelectErase:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor
      ui.selection.get[cur.row, cur.col] = ui.editMode == emSelectDraw

      if ke.isShortcutUp({scSelectionDraw, scSelectionErase}, a):
        ui.editMode = emSelect

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

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

      if ke.isShortcutUp({scSelectionAddRect, scSelectionSubRect}, a):
        ui.selection.get.fill(ui.selRect.get.rect, ui.selRect.get.selected)
        ui.selRect = SelectionRect.none
        ui.editMode = emSelect

    # }}}
    # {{{ emPastePreview
    of emPastePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        opts.pasteWraparound = not opts.pasteWraparound
        setPastePreviewModeMessage(a)

      elif ke.isShortcutDown(scPreviousLevel, repeat=true, a=a): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true, a=a): selectNextLevel(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPasteAccept, a):
        actions.pasteSelection(map, loc=cur, undoLoc=cur, ui.copyBuf.get,
                               pasteBufferLevelIndex=Natural.none,
                               wraparound=opts.pasteWraparound,
                               um, pasteTrail=true)
        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

    # }}}
    # {{{ emMovePreview
    of emMovePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        opts.pasteWraparound = not opts.pasteWraparound
        setMovePreviewModeMessage(a)

      elif ke.isShortcutDown(scPreviousLevel, repeat=true, a=a): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true, a=a): selectNextLevel(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPasteAccept, a):
        actions.pasteSelection(map, loc=cur, undoLoc=ui.pasteUndoLocation,
                               ui.nudgeBuf.get,
                               pasteBufferLevelIndex=MoveBufferLevelIndex.some,
                               wraparound=opts.pasteWraparound,
                               um, groupWithPrev=true,
                               actionName="Move selection")
        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Moved selection", a)

      elif ke.isShortcutDown(scCancel, a):
        exitMovePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        alias(dp, a.ui.drawLevelParams)

        let cols = a.ui.nudgeBuf.get.level.cols
        let rows = a.ui.nudgeBuf.get.level.rows

        let step = if mkCtrl in mods: CursorJump else: 1

        case dir:
        of dirE: dp.selStartCol = min(dp.selStartCol + step,  cols-1)
        of dirS: dp.selStartRow = min(dp.selStartRow + step,  rows-1)
        of dirW: dp.selStartCol = max(dp.selStartCol - step, -cols+1)
        of dirN: dp.selStartRow = max(dp.selStartRow - step, -rows+1)


      handleMoveKeys(ke, allowWasdKeys=false, allowRepeat=true,
                     allowDiagonal=true, handleMoveKey)

      let cur = ui.cursor

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        opts.pasteWraparound = not opts.pasteWraparound
        setNudgePreviewModeMessage(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scAccept, a):
        let newCur = actions.nudgeLevel(map, cur,
                                        dp.selStartRow, dp.selStartCol,
                                        ui.nudgeBuf.get,
                                        wraparound=opts.pasteWraparound, um)
        moveCursorTo(newCur, a)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isShortcutDown(scCancel, a):
        exitNudgePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

    # }}}
    # {{{ emSetCellLink
    of emSetCellLink:
      if opts.walkMode: handleMoveWalk(ke, a)
      else:
        discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                                 allowWasdKeys=true, allowDiagonal=false, a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true, a=a): selectPrevLevel(a)
      elif ke.isShortcutDown(scNextLevel,     repeat=true, a=a): selectNextLevel(a)

      let cur = ui.cursor

      if cur != ui.prevCursor:
        let floor = map.getFloor(ui.linkSrcLocation)
        setSetLinkDestinationMessage(floor, a)

      if ke.isShortcutDown(scAccept, a):
        if map.isEmpty(cur):
          setWarningMessage("Cannot set link destination to an empty cell",
                            keepStatusMessage=true, a=a)

        elif cur == ui.linkSrcLocation:
          setWarningMessage("Cannot set link destination to the source cell",
                            keepStatusMessage=true, a=a)
        else:
          actions.setLink(map, src=ui.linkSrcLocation, dest=cur,
                          ui.currFloorColor, um)

          ui.editMode = emNormal

          let linkType = linkFloorToString(map.getFloor(cur))
          setStatusMessage(IconLink,
                           fmt"{capitalizeAscii(linkType)} link destination set",
                           a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a)

    # }}}
    # {{{ emSelectJumpToLinkSrc
    of emSelectJumpToLinkSrc:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        var destIdx: int
        case dir:
        of dirE, dirN:
          destIdx = ui.jumpToSrcLocationIdx + 1
        of dirW, dirS:
          destIdx = ui.jumpToSrcLocationIdx - 1

        ui.jumpToSrcLocationIdx = destIdx.floorMod(ui.jumpToSrcLocations.len)
        ui.lastJumpToSrcLocation = ui.jumpToSrcLocations[ui.jumpToSrcLocationIdx]

        moveCursorTo(ui.lastJumpToSrcLocation, a)
        setSelectJumpToLinkSrcActionMessage(a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if ke.isShortcutDown(scAccept, a) or ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        if ui.wasDrawingTrail:
          actions.drawTrail(map, loc=ui.cursor, undoLoc=ui.jumpToDestLocation, um)
          opts.drawTrail = true
        clearStatusMessage(a)

      elif ke.isShortcutDown(scJumpToLinkedCell, a):
        moveCursorTo(ui.jumpToDestLocation, a)
        ui.editMode = emNormal
        if ui.wasDrawingTrail:
          opts.drawTrail = true
        clearStatusMessage(a)

    # }}}
    of emPanLevel:
      discard

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  let yubnMode = a.prefs.yubnMovementKeys

  if hasKeyEvent():
    let ke = koi.currEvent()

    if   ke.isShortcutDown(scNewMap, a):            newMap(a)
    elif ke.isShortcutDown(scEditMapProps, a):      openEditMapPropsDialog(a)

    elif ke.isShortcutDown(scOpenMap, a):           openMap(a)
    elif ke.isShortcutDown(scSaveMap, a):           saveMap(a)
    elif ke.isShortcutDown(scSaveMapAs, a):         saveMapAs(a)

    elif ke.isShortcutDown(scNewLevel, a):
      openNewLevelDialog(a)

    elif ke.isShortcutDown(scReloadTheme, a):       reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme, a):     selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme, a):         selectNextTheme(a)

    elif ke.isShortcutDown(scEditPreferences, a):   openPreferencesDialog(a)

    elif ke.isShortcutDown(scUndo, repeat=true, a=a): undoAction(a)
    elif ke.isShortcutDown(scRedo, repeat=true, a=a): redoAction(a)

    elif ke.isShortcutDown(scOpenUserManual, a):    openUserManual(a)
    elif ke.isShortcutDown(scShowAboutDialog, a):   openAboutDialog(a)

    elif ke.isShortcutDown(scToggleThemeEditor, a):
      toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference, a):
      showQuickReference(a)

    # Toggle options
    elif ke.isShortcutDown(scToggleTitleBar, a):
      toggleTitleBar(a)

# }}}
# {{{ handleQuickRefKeyEvents()

let QuickRefTabLabels = @["General", "Editing", "Dialogs"]

proc handleQuickRefKeyEvents(a) =
  if hasKeyEvent():
    let ke = koi.currEvent()

    a.quickRef.activeTab = handleTabNavigation(ke, a.quickRef.activeTab,
                                               QuickRefTabLabels.high, a)

    if   ke.isShortcutDown(scReloadTheme, a):   reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme, a): selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme, a):     selectNextTheme(a)

    elif ke.isShortcutDown(scOpenUserManual, a):    openUserManual(a)
    elif ke.isShortcutDown(scToggleThemeEditor, a): toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference, a) or
         ke.isShortcutDown(scAccept, a) or
         ke.isShortcutDown(scCancel, a) or
         isKeyDown(keySpace):

      a.opts.showQuickReference = false
      clearStatusMessage(a)

# }}}

# }}}

# {{{ Rendering

# {{{ Level

# {{{ renderLevelDropdown()
proc renderLevelDropdown(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    mainPane   = mainPaneRect(a)
    levelNames = map.sortedLevelNames

  var sortedLevelIdx = currSortedLevelIdx(a)
  let prevSortedLevelIdx = sortedLevelIdx

  vg.fontSize(a.theme.levelDropDownStyle.label.fontSize)

  # Level drop-down
  let levelDropDownWidth = round(
    vg.textWidth(levelNames[sortedLevelIdx]) +
    a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
  )

  koi.dropDown(
    x = round(mainPane.w - levelDropDownWidth) * 0.5,
    y = 19.0,
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
    cur.level = map.sortedLevelIndexes[sortedLevelIdx]
    setCursor(cur, a)

# }}}
# {{{ renderRegionDropDown()
proc renderRegionDropDown(a) =
  alias(ui, a.ui)

  let
    l = currLevel(a)
    currRegion = currRegion(a)
    mainPane = mainPaneRect(a)

  if currRegion.isSome:
    var sortedRegionNames = l.regionNames()
    sort(sortedRegionNames)

    let currRegionName = currRegion.get.name
    var sortedRegionIdx = sortedRegionNames.find(currRegionName)
    let prevSortedRegionIdx = sortedRegionIdx

    let regionDropDownWidth = round(
      a.vg.textWidth(currRegionName) +
      a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
    )

    koi.dropDown(
      x = round(mainPane.x1 + (mainPane.w - regionDropDownWidth) * 0.5),
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

      let (r, c) = a.doc.map.getRegionCenterLocation(ui.cursor.level,
                                                     regionCoords)

      centerCursorAt(Location(level: ui.cursor.level, row: r, col: c), a)

# }}}
# {{{ renderModeAndOptionIndicators()
proc renderModeAndOptionIndicators(x, y: float; a) =
  alias(vg, a.vg)
  alias(ui, a.ui)

  let lt = a.theme.levelTheme

  vg.save()

  vg.fillColor(lt.coordinatesHighlightColor)

  var x = x

  if a.opts.wasdMode:
    vg.setFont(15, "sans-bold")
    discard vg.text(x, y, fmt"WASD+{IconMouse}")
    x += 80

  if a.opts.drawTrail:
    vg.setFont(19, "sans-bold")
    discard vg.text(x, y+1, IconShoePrints)

  vg.restore()

# }}}
# {{{ renderNoteTooltip()
proc renderNoteTooltip(x, y: float, levelDrawWidth, levelDrawHeight: float,
                       note: Annotation, a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(dp, a.ui.drawLevelParams)
  alias(lt, a.theme.levelTheme)

  if note.text != "":
    const PadX = 10
    const PadY = 8

    var
      noteBoxX = x
      noteBoxY = y
      noteBoxW = 250.0
      textX = noteBoxX + PadX
      textY = noteBoxY + PadY

    vg.setFont(14, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.5)

    let
      breakWidth = noteBoxW - PadX*2
      bounds = vg.textBoxBounds(textX, textY, breakWidth, note.text)

      noteTextH = bounds.y2 - bounds.y1
      noteTextW = bounds.x2 - bounds.x1
      noteBoxH = noteTextH + PadY*2

    noteBoxW = noteTextW + PadX*2

    let
      xOver = noteBoxX + noteBoxW - (dp.startX + levelDrawWidth)
      yOver = noteBoxY + noteBoxH - (dp.startY + levelDrawHeight)

    if xOver > 0:
      noteBoxX -= xOver
      textX -= xOver

    if yOver > 0:
      let offs = noteBoxH + 22
      noteBoxY -= offs
      textY -= offs

    vg.drawShadow(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                  lt.noteTooltipShadowStyle)

    vg.fillColor(a.theme.levelTheme.noteTooltipBackgroundColor)
    vg.beginPath()
    vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                   r=lt.noteTooltipCornerRadius)
    vg.fill()

    vg.fillColor(a.theme.levelTheme.noteTooltipTextColor)
    vg.textBox(textX, textY, breakWidth, note.text)

# }}}

# {{{ renderLevel()
proc renderLevel(x, y, w, h: float,
                 levelDrawWidth, levelDrawHeight: float; a) =

  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opts, a.opts)

  let
    l = currLevel(a)
    i = instantiationInfo(fullPaths=true)
    id = koi.generateId(i.filename, i.line, "gridmonger-level")

  if ui.prevCursor != ui.cursor:
    resetManualNoteTooltip(a)

  # Hit testing
  if koi.isHit(x, y, w, h):
    koi.setHot(id)
    if koi.hasNoActiveItem() and
       (koi.mbLeftDown() or koi.mbRightDown() or koi.mbMiddleDown()):
      koi.setActive(id)

  if isActive(id):
    handleLevelMouseEvents(a)

  # Draw level
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow     = ui.cursor.row
    dp.cursorCol     = ui.cursor.col
    dp.cellCoordOpts = coordOptsForCurrLevel(a)
    dp.regionOpts    = l.regionOpts

    dp.pasteWraparound  = opts.pasteWraparound
    dp.selectionWraparound = (opts.pasteWraparound and
                              ui.editMode != emNudgePreview)

    if opts.walkMode and
       ((ui.editMode in {emNormal, emExcavateTunnel, emEraseCell,
                         emDrawClearFloor}) or
        (ui.editMode == emPanLevel and ui.prevEditMode == emNormal)):
      dp.cursorOrient = ui.cursorOrient.some
    else:
      dp.cursorOrient = CardinalDir.none

    dp.selection = ui.selection
    dp.selectionRect = ui.selRect

    dp.selectionBuffer = (
      if ui.editMode == emPastePreview or
        (ui.editMode == emPanLevel and
         ui.prevEditMode == emPastePreview): ui.copyBuf

      elif ui.editMode in {emMovePreview, emNudgePreview} or
        (ui.editMode == emPanLevel and
         ui.prevEditMode in {emMovePreview, emNudgePreview}): ui.nudgeBuf

      else: SelectionBuffer.none
    )

    drawLevel(
      a.doc.map,
      ui.cursor.level,
      DrawLevelContext(lt: a.theme.levelTheme, dp: dp, vg: a.vg)
    )

  # Draw note tooltip
  const
    NoteTooltipXOffs = 16
    NoteTooltipYOffs = 20

  var mouseOverCellWithNote = false
  var note: Option[Annotation]

  if koi.isHot(id) and
     ui.editMode == emNormal and
     not (opts.wasdMode and isActive(id)) and
     (koi.mx() != ui.manualNoteTooltipState.mx or
      koi.my() != ui.manualNoteTooltipState.my):

    let loc = locationAtMouse(clampToBounds=false, a)
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

    renderNoteTooltip(x, y, levelDrawWidth, levelDrawHeight, note.get, a)

# }}}
# {{{ renderEmptyMap()
proc renderEmptyMap(a) =
  alias(vg, a.vg)

  let lt = a.theme.levelTheme

  vg.setFont(22, "sans-bold")
  vg.fillColor(lt.foregroundNormalNormalColor)
  vg.textAlign(haCenter, vaMiddle)

  let mainPane = mainPaneRect(a)
  var y = mainPane.h.float * 0.5
  discard vg.text(mainPane.x1 + mainPane.w.float * 0.5, y, "Empty map")

# }}}

# }}}
# {{{ Tools pane

# {{{ specialWallDrawProc()
proc specialWallDrawProc(lt: LevelTheme,
                         tt: ToolbarPaneTheme,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext,
               id: ItemId, x, y, w, h: float,
               buttonIdx, numButtons: Natural, label: string,
               state: WidgetState, style: RadioButtonsStyle) =

    var (bgCol, active) = case state
                          of wsHover:
                            (tt.buttonHoverColor,  false)
                          of wsDown, wsActive, wsActiveHover, wsActiveDown:
                            (lt.cursorColor,       true)
                          else:
                            (tt.buttonNormalColor, false)

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let
      savedFloorColor = lt.floorBackgroundColor[0]
      savedForegroundNormalNormalColor = lt.foregroundNormalNormalColor
      savedForegroundLightNormalColor  = lt.foregroundLightNormalColor
      savedBackgroundImage = dp.backgroundImage

    lt.floorBackgroundColor[0] = lerp(lt.backgroundColor, bgCol, bgCol.a)
                                 .withAlpha(1.0)
    if active:
      lt.foregroundNormalNormalColor = lt.foregroundNormalCursorColor
      lt.foregroundLightNormalColor  = lt.foregroundLightCursorColor

    dp.backgroundImage = Paint.none

    const Pad = 5

    vg.beginPath()
    vg.fillColor(bgCol)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill()

    dp.setZoomLevel(lt, 4)
    let ctx = DrawLevelContext(lt: lt, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel(zl: Natural, body: untyped) =
      vg.save()
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(lt, zl)
      vg.intersectScissor(x+4.5, y+3, w-Pad*2-4, h-Pad*2-2)
      body
      dp.setZoomLevel(lt, 4)
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
    lt.floorBackgroundColor[0] = savedFloorColor
    lt.foregroundNormalNormalColor = savedForegroundNormalNormalColor
    lt.foregroundLightNormalColor = savedForegroundLightNormalColor
    dp.backgroundImage = savedBackgroundImage

# }}}
# {{{ renderToolsPane()
proc renderToolsPane(x, y, w, h: float; a) =
  alias(ui, a.ui)
  alias(lt, a.theme.levelTheme)
  alias(vg, a.vg)

#  vg.beginPath()
#  vg.strokeWidth(1)
#  vg.strokeColor(green())
#  vg.rect(x, y, w, h)
#  vg.stroke()

  var
    toolItemsPerColumn = 12
    toolX = x

    colorItemsPerColum = 10
    colorX = x + 3
    colorY = y + 445

  let mainPane = mainPaneRect(a)

  if mainPane.h < ToolsPaneYBreakpoint2:
    colorItemsPerColum = 5
    toolX += 30

  if mainPane.h < ToolsPaneYBreakpoint1:
    toolItemsPerColumn = 6
    toolX -= 30
    colorX += 3
    colorY -= 210

  # Special walls
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

    drawProc = specialWallDrawProc(
      a.theme.levelTheme, a.theme.toolbarPaneTheme, ui.toolbarDrawParams
    ).some
  )

  # Floor colours
  var floorColors = newSeqOfCap[Color](lt.floorBackgroundColor.len)

  for fc in 0..lt.floorBackgroundColor.high:
    let c = calcBlendedFloorColor(fc, lt.floorTransparent, lt)
    floorColors.add(c)

  koi.radioButtons(
    x = colorX,
    y = colorY,
    w = 30,
    h = 30,
    labels = newSeq[string](lt.floorBackgroundColor.len),
    ui.currFloorColor,
    tooltips = @[],

    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: colorItemsPerColum),

    drawProc = colorRadioButtonDrawProc(floorColors, lt.cursorColor).some
  )

# }}}

# }}}
# {{{ Note panes

# {{{ renderIndexedNote()
proc renderIndexedNote(x, y: float; size: float; bgColor, fgColor: Color;
                       shape: NoteBackgroundShape; index: Natural; a) =
  alias(vg, a.vg)

  vg.fillColor(bgColor)
  vg.beginPath()

  case shape
  of nbsCircle:
    vg.circle(x + size*0.5, y + size*0.5, size*0.38)
  of nbsRectangle:
    let pad = 4.0
    vg.rect(x+pad, y+pad, size-pad*2, size-pad*2)

  vg.fill()

  var fontSizeFactor = if   index <  10: 0.4
                       elif index < 100: 0.37
                       else:             0.32

  vg.setFont(size*fontSizeFactor, "sans-bold")
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + size*0.51, y + size*0.54, $index)

# }}}
# {{{ renderNoteMarker()
proc renderNoteMarker(x, y, w, h: float, note: Annotation, textColor: Color,
                      indexedNoteSize: float = 36.0; a) =
  alias(vg, a.vg)

  let s = a.theme.notesPaneTheme

  vg.save()

  case note.kind
  of akIndexed:
    renderIndexedNote(x, y-2, size=indexedNoteSize,
                      bgColor=s.indexBackgroundColor[note.indexColor],
                      fgColor=s.indexColor,
                      a.theme.levelTheme.notebackgroundShape,
                      note.index, a)

  of akCustomId:
    vg.fillColor(textColor)
    vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+18, y+8, note.customId)

  of akIcon:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+7, NoteIcons[note.icon])

  of akComment:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+8, IconComment)

  of akLabel: discard

  vg.restore()

# }}}
# {{{ renderCurrentNotePane()
proc renderCurrentNotePane(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let
    l = currLevel(a)
    cur = a.ui.cursor
    note = l.getNote(cur.row, cur.col)

  if note.isSome and not (a.ui.editMode in {emPastePreview, emNudgePreview}):
    let note = note.get
    if note.text == "" or note.kind == akLabel: return

    renderNoteMarker(x, y, w, h, note,
                     textColor=a.theme.notesPaneTheme.textColor, a=a)

    var text = note.text
    const TextIndent = 44
    koi.textArea(x+TextIndent, y-1, w-TextIndent, h, text, disabled=true,
                 style=a.theme.noteTextAreaStyle)

# }}}
# {{{ renderNotesListPane()

proc toAnnotationKindSet(filter: seq[NoteTypeFilter]): set[AnnotationKind] =
  for f in filter:
    case f
    of nftNone:   result.incl(akComment)
    of nftNumber: result.incl(akIndexed)
    of nftId:     result.incl(akCustomId)
    of nftIcon:   result.incl(akIcon)

# {{{ Note sort functions
func toSortOrder(ak: AnnotationKind): int =
  case ak
  of akIndexed:  0
  of akCustomId: 1
  of akIcon:     2
  of akComment:  3
  of akLabel:    4

func sortByNoteType(a, b: Annotation): int =
  var c = 0
  if a.kind == b.kind:
    case a.kind:
    of akComment, akLabel: discard
    of akIndexed:
      c   = cmp(a.index,    b.index);    if c != 0: return c
    of akCustomId:
      c   = cmp(a.customId, b.customId); if c != 0: return c
    of akIcon:
      c   = cmp(a.icon,     b.icon);     if c != 0: return c
    return 0
  else:
    cmp(a.kind.toSortOrder, b.kind.toSortOrder)

func sortByTextAndLocation(locA: tuple[row, col: Natural], a: Annotation,
                           locB: tuple[row, col: Natural], b: Annotation): int =
  var c = cmpIgnoreCase(a.text, b.text); if c != 0: return c
  c     = cmp(locA.row, locB.row);       if c != 0: return c
  return  cmp(locA.col, locB.col)

# }}}
# {{{ noteButton()
proc noteButton(id: ItemId; textX, textY, textW, markerX: float;
                note: Annotation): bool =
  alias(ui, g_app.ui)

  koi.autoLayoutPre()

  let
    (x, y) = addDrawOffset(x=koi.autoLayoutNextX(),
                           y=koi.autoLayoutNextY())

    w = koi.autoLayoutNextItemWidth()
    h = koi.autoLayoutNextItemHeight()

  # Hit testing
  const ScrollBarWidth = 12

  if isHit(x, y, w-ScrollBarWidth, h):
    setHot(id)
    if (koi.mbLeftDown() or koi.shiftDown()) and koi.hasNoActiveItem():
      setActive(id)
      result = true

  addDrawLayer(koi.currentLayer(), vg):
    let state = if   koi.isHot(id) and koi.hasNoActiveItem(): wsHover
                elif koi.isHot(id) and koi.isActive(id):      wsDown
                else:                                         wsNormal

    if state in {wsHover, wsDown}:
      vg.beginPath()
      vg.fillColor(black(0.2))
      vg.rect(x, y, w, h)
      vg.fill()

    let textColor =
      case state
      of wsDisabled, wsNormal, wsActive, wsActiveHover: white(0.7)
      of wsHover, wsDown, wsActiveDown:                 white()

    if note.kind == akIndexed:
      renderNoteMarker(x + markerX + 3, y+2, w, h, note, textColor,
                       indexedNoteSize=32, g_app)
    else:
      renderNoteMarker(x + markerX, y, w, h, note, textColor, a=g_app)

    vg.setFont(14, "sans-bold")
    vg.fillColor(textColor)
    vg.textLineHeight(1.4)
    vg.textBox(x + textX, y + textY, textW, note.text)

  koi.autoLayoutPost()

# }}}

# {{{ renderNotesListPane()
proc renderNotesListPane(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(nls, ui.notesListState)

  let
    ws = a.theme.windowTheme
    l  = currLevel(a)

  const
    TopPad     = 137
    LeftPad    = 16
    RightPad   = 16
    TextIndent = 44

  # Background
  vg.beginPath()
  vg.rect(x, y, w, h)
  vg.fillColor(lerp(ws.backgroundColor, black, 0.25))
  vg.fill()

  # Filters & search
  vg.beginPath()
  vg.rect(x, y, w, TopPad)
  vg.fillColor(lerp(ws.backgroundColor, black, 0.15))
  vg.fill()

  var
    wx = LeftPad
    wy = 44
    wh = 24

  if koi.button(wx+244, wy, w=24, wh, "A",
                tooltip = "Show all note types",
                style = a.theme.buttonStyle):
    nls.currFilter.typeFilter = @[nftNone, nftNumber, nftId, nftIcon]

  koi.multiRadioButtons(
    wx, wy, w=w-LeftPad-RightPad - 32, wh,
    nls.currFilter.typeFilter, style = a.theme.radioButtonStyle
  )

  wy += 44
  koi.label(wx+3, wy, 60, wh, "Order by", style=a.theme.labelStyle)

  koi.dropDown(
    wx+68, wy, w=78, wh, nls.currFilter.order, style = a.theme.dropDownStyle
  )

  discard koi.button(
    wx+161, wy, w=45, wh, "(X,Y)",
    tooltip = "Show note coordinates",
    style = a.theme.buttonStyle
  )

  var cbStyle = a.theme.checkBoxStyle.deepCopy()
  cbStyle.icon.fontSize = 14.0
  cbStyle.iconActive    = "R"
  cbStyle.iconInactive  = "R"

  koi.checkBox(
    wx+213, wy, w=24,
    nls.currentRegion,
    tooltip = "Show only notes from the current region",
    style = cbStyle
  )

  cbStyle = a.theme.checkBoxStyle.deepCopy()
  cbStyle.icon.fontSize = 14.0
  cbStyle.iconActive   = IconLink
  cbStyle.iconInactive = IconLink

  koi.checkBox(
    wx+244, wy, w=24,
    nls.linkCursor,
    tooltip = "Link cursor and note selection",
    style = cbStyle
  )

  wy += 33
  koi.label(wx+3, wy, 60, wh, "Search", style=a.theme.labelStyle)

  if koi.button(wx+244, wy, w=24, wh, IconTrash,
                tooltip = "Clear search term",
                style = a.theme.buttonStyle):
    nls.currFilter.searchTerm = ""

  koi.textField(
    wx+68, wy, w=169, wh,
    nls.currFilter.searchTerm,
    style = a.theme.textFieldStyle
  )

  # Determine note list dirty state
  if nls.currFilter != nls.prevFilter:
    nls.dirty = true

  elif l.annotations.dirty:
    nls.dirty = true
    l.annotations.dirty = false

  elif ui.cursor.level != ui.prevCursor.level:
    nls.dirty = true


  const
    NoteHorizOffs  = -8
    NoteVertPad    = 18

  let
    markerX = LeftPad + NoteHorizOffs
    textX   = markerX + TextIndent
    textW   = w - TextIndent - LeftPad - RightPad - NoteHorizOffs

  template setFont() =
    vg.setFont(14, "sans-bold")
    vg.textLineHeight(1.4)

  # Refresh cache if needed
  if nls.dirty:
    let annotationKindFilter = nls.currFilter.typeFilter.toAnnotationKindSet

    setFont()

    nls.cache = newSeqOfCap[NotesListCacheEntry](l.numAnnotations())

    let searchTerms = nls.currFilter.searchTerm.strip.toLower.splitWhitespace

    for (r,c, note) in l.allNotes():
      if note.kind in annotationKindFilter:
        if searchTerms.len > 0:
          var found = false
          for term in searchTerms:
            if note.text.toLower.contains(term):
              found = true
              break
          if not found: continue

        let
          idString   = fmt"notes-list:{r}:{c}"
          id         = hashId(idString)
          textBounds = vg.textBoxBounds(textX, y, textW, note.text)
          height     = textBounds.y2 - textBounds.y1 + NoteVertPad

        nls.cache.add(
          NotesListCacheEntry(id: id, row: r, col: c, height: height)
        )

    func sortByTextLocationType(a, b: NotesListCacheEntry): int =
      let noteA = l.getNote(a.row, a.col).get
      let noteB = l.getNote(b.row, b.col).get
      var c = sortByTextAndLocation((a.row, a.col), noteA,
                                    (b.row, b.col), noteB)
      if c != 0: return c
      sortByNoteType(noteA, noteB)

    func sortByTypeTextLocation(a, b: NotesListCacheEntry): int =
      let noteA = l.getNote(a.row, a.col).get
      let noteB = l.getNote(b.row, b.col).get
      var c = sortByNoteType(noteA, noteB)
      if c != 0: return c
      sortByTextAndLocation((a.row, a.col), noteA,
                            (b.row, b.col), noteB)

    case nls.currFilter.order
    of nfoType: nls.cache.sort(sortByTypeTextLocation)
    of nfoText: nls.cache.sort(sortByTextLocationType)

    nls.prevFilter = nls.currFilter
    nls.dirty = false

  # Scroll view with notes
  koi.beginScrollView(x, y+TopPad, w, h-TopPad,
                      style=a.theme.notesListScrollViewStyle)

  var lp = DefaultAutoLayoutParams
  lp.itemsPerRow = 1
  lp.rowWidth    = w
  lp.rowPad      = 0
  lp.labelWidth  = w
  lp.leftPad     = 0
  lp.sectionPad  = 0

  initAutoLayout(lp)

  # Render note buttons
  setFont()

  for e in nls.cache:
    let note = l.getNote(e.row, e.col).get

    const MinHeight = 32
    let height = max(MinHeight, e.height)

    koi.nextRowHeight(height)
    koi.nextItemHeight(height)

    if noteButton(e.id, textX, textY=17, textW, markerX, note):
      moveCursorTo(Location(level: ui.cursor.level, row: e.row, col: e.col), a)

  koi.endScrollView()

# }}}
# }}}

# }}}
# {{{ Theme editor

var ThemeEditorScrollViewStyle = getDefaultScrollViewStyle()
with ThemeEditorScrollViewStyle:
  vertScrollBarWidth      = 14.0
  scrollBarStyle.thumbPad = 4.0

var ThemeEditorSliderStyle = getDefaultSliderStyle()
with ThemeEditorSliderStyle:
  trackCornerRadius = 8.0
  valueCornerRadius = 6.0

var ThemeEditorAutoLayoutParams = DefaultAutoLayoutParams
with ThemeEditorAutoLayoutParams:
  leftPad    = 14.0
  rightPad   = 16.0
  labelWidth = 185.0

# {{{ renderThemeEditorProps()
proc renderThemeEditorProps(x, y, w, h: float; a) =
  alias(te, a.themeEditor)
  alias(cfg, a.theme.config)

  template prop(label: string, path: string, body: untyped)  =
    block:
      koi.label(label)
      koi.setNextId(path)
      body
      if a.theme.prevConfig.getOpt(path) != cfg.getOpt(path):
        te.modified = true

  template stringProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getStringOrDefault(path)
      koi.textfield(val)
      hocon.set(cfg, path, $val)

  template colorProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getColorOrDefault(path)
      koi.color(val)
      hocon.set(cfg, path, $val)

  template boolProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getBoolOrDefault(path)
      koi.checkBox(val)
      hocon.set(cfg, path, val)

  template floatProp(label: string, path: string, limits: FieldLimits) =
    prop(label, path):
      var val = cfg.getFloatOrDefault(path)
      koi.horizSlider(startVal=limits.minFloat,
                      endVal=limits.maxFloat,
                      val,
                      style=ThemeEditorSliderStyle)
      hocon.set(cfg, path, val)

  template enumProp(label: string, path: string, T: typedesc[enum]) =
    prop(label, path):
      var val = cfg.getEnumOrDefault(path, T)
      koi.dropDown(val)
      hocon.set(cfg, path, enumToDashCase($val))


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  var p: string

  # {{{ -- User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      p = "ui.window."
      group:
        colorProp("Border",           p & "border.color")

      group:
        colorProp("Background",       p & "background.color")
        let path = p & "background.image"
        stringProp("Background Image", path)

        koi.nextLayoutColumn()
        if koi.button("Reload", disabled=cfg.getString(path) == ""):
          a.theme.loadBackgroundImage = true

      group:
        p = "ui.window.title."
        colorProp("Title Background Normal",   p & "background.normal")
        colorProp("Title Background Inactive", p & "background.inactive")
        colorProp("Title Text Normal",         p & "text.normal")
        colorProp("Title Text Inactive",       p & "text.inactive")

      group:
        p = "ui.window."
        colorProp("Modified Flag Normal",      p & "modified-flag.normal")
        colorProp("Modified Flag Inactive",    p & "modified-flag.inactive")

      group:
        p = "ui.window.button."
        colorProp("Button Normal",    p & "normal")
        colorProp("Button Hover",     p & "hover")
        colorProp("Button Down",      p & "down")
        colorProp("Button Inactive",  p & "inactive")

    if koi.subSectionHeader("Dialog", te.sectionDialog):
      p = "ui.dialog."
      group:
        let CRLimits = DialogCornerRadiusLimits
        floatProp("Corner Radius",    p & "corner-radius", CRLimits)
        colorProp("Background",       p & "background")
        colorProp("Label",            p & "label")
        colorProp("Warning",          p & "warning")
        colorProp("Error",            p & "error")

      group:
        colorProp("Title Background", p & "title.background")
        colorProp("Title Text",       p & "title.text")

      group:
        let BWLimits = DialogBorderWidthLimits
        colorProp("Outer Border",       p & "outer-border.color")
        floatProp("Outer Border Width", p & "outer-border.width", BWLimits)
        colorProp("Inner Border",       p & "inner-border.color")
        floatProp("Inner Border Width", p & "inner-border.width", BWLimits)

      group:
        boolProp( "Shadow?",         p & "shadow.enabled")
        colorProp("Shadow Colour",   p & "shadow.color")
        floatProp("Shadow Feather",  p & "shadow.feather",  ShadowFeatherLimits)
        floatProp("Shadow X Offset", p & "shadow.x-offset", ShadowOffsetLimits)
        floatProp("Shadow Y Offset", p & "shadow.y-offset", ShadowOffsetLimits)

    if koi.subSectionHeader("Widget", te.sectionWidget):
      p = "ui.widget."
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",       p & "corner-radius", WCRLimits)
      group:
        colorProp("Background Normal",   p & "background.normal")
        colorProp("Background Hover",    p & "background.hover")
        colorProp("Background Active",   p & "background.active")
        colorProp("Background Disabled", p & "background.disabled")
      group:
        colorProp("Foreground Normal",   p & "foreground.normal")
        colorProp("Foreground Active",   p & "foreground.active")
        colorProp("Foreground Disabled", p & "foreground.disabled")

    if koi.subSectionHeader("Drop Down", te.sectionDropdown):
      p = "ui.drop-down."
      group:
        colorProp("Item List Background", p & "item-list-background")
        colorProp("Item Normal",          p & "item.normal")
        colorProp("Item Hover",           p & "item.hover")

    if koi.subSectionHeader("Text Field", te.sectionTextField):
      p = "ui.text-field."
      group:
        colorProp("Cursor",            p & "cursor")
        colorProp("Selection",         p & "selection")
      group:
        colorProp("Edit Background",   p & "edit.background")
        colorProp("Edit Text",         p & "edit.text")
      group:
        colorProp("Scroll Bar Normal", p & "scroll-bar.normal")
        colorProp("Scroll Bar Edit",   p & "scroll-bar.edit")

    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      p = "ui.status-bar."
      group:
        colorProp("Background",        p & "background")
        colorProp("Text",              p & "text")
        colorProp("Warning",           p & "warning")
        colorProp("Error",             p & "error")
        colorProp("Coordinates",       p & "coordinates")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      p = "ui.about-button."
      colorProp("Label Normal",        p & "label.normal")
      colorProp("Label Hover",         p & "label.hover")
      colorProp("Label Down",          p & "label.down")

    if koi.subSectionHeader("About Dialog", te.sectionAboutDialog):
      let path = "ui.about-dialog.logo"
      colorProp("Logo", path)
      if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
        a.aboutLogo.updateLogoImage = true

    if koi.subSectionHeader("Quick Help", te.sectionQuickHelp):
      p = "ui.quick-help."
      group:
        colorProp("Background",        p & "background")
        colorProp("Title",             p & "title")
        colorProp("Text",              p & "text")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        p = "ui.splash-image."
        var path = p & "logo"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateLogoImage = true

        path = p & "outline"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateOutlineImage = true

        path = p & "shadow-alpha"
        floatProp("Shadow Alpha", path, AlphaLimits)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ -- Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      p = "level.general."
      group:
        colorProp("Background",            p & "background")
      group:
        enumProp( "Line Width",            p & "line-width", LineWidth)
      group:
        colorProp("Foreground Normal",        p & "foreground.normal.normal")
        colorProp("Foreground Normal Cursor", p & "foreground.normal.cursor")
        colorProp("Foreground Light",         p & "foreground.light.normal")
        colorProp("Foreground Light Cursor",  p & "foreground.light.cursor")
      group:
        colorProp("Link Marker",           p & "link-marker")
      group:
        colorProp("Trail Normal",          p & "trail.normal")
        colorProp("Trail Cursor",          p & "trail.cursor")
      group:
        colorProp("Cursor",                p & "cursor")
        colorProp("Cursor Guides",         p & "cursor-guides")
      group:
        colorProp("Selection",             p & "selection")
        colorProp("Paste Preview",         p & "paste-preview")
      group:
        colorProp("Coordinates Normal",    p & "coordinates.normal")
        colorProp("Coordinates Highlight", p & "coordinates.highlight")
      group:
        colorProp("Region Border Normal",  p & "region-border.normal")
        colorProp("Region Border Empty",   p & "region-border.empty")

    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      let WidthLimits = BackgroundHatchWidthLimits
      let SpacingLimits = BackgroundHatchSpacingFactorLimits

      p = "level.background-hatch."
      boolProp("Background Hatch?",     p & "enabled")
      colorProp("Hatch Colour",         p & "color")
      floatProp("Hatch Stroke Width",   p & "width",          WidthLimits)
      floatProp("Hatch Spacing Factor", p & "spacing-factor", SpacingLimits)

    if koi.subSectionHeader("Grid", te.sectionGrid):
      p = "level.grid."
      group:
        colorProp("Background Grid",       p & "background.grid")
        enumProp( "Background Grid Style", p & "background.style", GridStyle)
      group:
        colorProp("Floor Grid",            p & "floor.grid")
        enumProp( "Floor Grid Style",      p & "floor.style",      GridStyle)

    if koi.subSectionHeader("Outline", te.sectionOutline):
      p = "level.outline."
      enumProp( "Style",         p & "style",        OutlineStyle)
      enumProp( "Fill Style",    p & "fill-style",   OutlineFillStyle)
      colorProp("Outline",       p & "color")
      floatProp("Width",         p & "width-factor", OutlineWidthFactorLimits)
      boolProp( "Overscan",      p & "overscan")

    if koi.subSectionHeader("Shadow", te.sectionShadow):
      let SWLimits = ShadowWidthFactorLimits
      p = "level.shadow."
      group:
        colorProp("Inner Shadow",       p & "inner.color")
        floatProp("Inner Shadow Width", p & "inner.width-factor", SWLimits)
      group:
        colorProp("Outer Shadow",       p & "outer.color")
        floatProp("Outer Shadow Width", p & "outer.width-factor", SWLimits)

    if koi.subSectionHeader("Floor Colours", te.sectionFloorColors):
      p = "level.floor."
      boolProp("Transparent?", p & "transparent")

      colorProp("Color 1",  p & "background.0")
      colorProp("Color 2",  p & "background.1")
      colorProp("Color 3",  p & "background.2")
      colorProp("Color 4",  p & "background.3")
      colorProp("Color 5",  p & "background.4")
      colorProp("Color 6",  p & "background.5")
      colorProp("Color 7",  p & "background.6")
      colorProp("Color 8",  p & "background.7")
      colorProp("Color 9",  p & "background.8")
      colorProp("Color 10", p & "background.9")

    if koi.subSectionHeader("Notes", te.sectionNotes):
      p = "level.note."
      group:
        colorProp("Marker Normal",      p & "marker.normal")
        colorProp("Marker Cursor",      p & "marker.cursor")
        colorProp("Comment",            p & "comment")
      group:
        enumProp( "Background Shape",   p & "background-shape",
                  NoteBackgroundShape)

        colorProp("Background 1",       p & "index-background.0")
        colorProp("Background 2",       p & "index-background.1")
        colorProp("Background 3",       p & "index-background.2")
        colorProp("Background 4",       p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Tooltip Background",     p & "tooltip.background")
        colorProp("Tooltip Text",           p & "tooltip.text")
        floatProp("Tooltip Corner Radius ", p & "tooltip.corner-radius",
                  WidgetCornerRadiusLimits)
        colorProp("Tooltip Shadow",         p & "tooltip.shadow.color")

    if koi.subSectionHeader("Labels", te.sectionLabels):
      p = "level.label."
      group:
        colorProp("Label 1", p & "text.0")
        colorProp("Label 2", p & "text.1")
        colorProp("Label 3", p & "text.2")
        colorProp("Label 4", p & "text.3")

    if koi.subSectionHeader("Level Drop Down", te.sectionLevelDropDown):
      p = "level.level-drop-down."
      group:
        colorProp("Button Normal",        p & "button.normal")
        colorProp("Button Hover",         p & "button.hover")
        colorProp("Button Label",         p & "button.label")
      group:
        colorProp("Item List Background", p & "item-list-background")
        colorProp("Item Normal",          p & "item.normal")
        colorProp("Item Hover",           p & "item.hover")
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",        p & "corner-radius", WCRLimits)
      group:
        colorProp("Shadow",               p & "shadow.color")

  # }}}
  # {{{ -- Panes section

  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Notes Pane", te.sectionNotesPane):
      p = "pane.notes."
      group:
        colorProp("Text",               p & "text")
      group:
        colorProp("Index Background 1", p & "index-background.0")
        colorProp("Index Background 2", p & "index-background.1")
        colorProp("Index Background 3", p & "index-background.2")
        colorProp("Index Background 4", p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Scroll Bar",         p & "scroll-bar")

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      p = "pane.toolbar."
      colorProp("Button",       p & "button.normal")
      colorProp("Button Hover", p & "button.hover")

  # }}}

  koi.endScrollView()

  a.theme.prevConfig = cfg.deepCopy()

# }}}
# {{{ renderThemeEditorPane()

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
    bw = 68.0
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
  koi.label(cx, cy, w, wh, "T  H  E  M  E       E  D  I  T  O  R",
            style=titleStyle)

  # Theme name & action buttons
  vg.beginPath()
  vg.rect(x+1, y+TitleHeight, w, h=96)
  vg.fillColor(gray(0.36))
  vg.fill()

  cx = x+17
  cy += 45.0
  koi.label(cx, cy, w, wh, "Theme")

  let buttonsDisabled = koi.isDialogOpen()

  var themeNames = newSeq[string]()
  for t in a.theme.themeNames:
    themeNames.add(t.name)

  var themeIndex = a.theme.currThemeIndex

  cx += 55.0
  koi.dropDown(
    cx, cy, w=189.0, wh,
    themeNames,
    themeIndex,
    tooltip = "",
    disabled = buttonsDisabled
  )

  proc switchTheme(a) =
    a.theme.nextThemeIndex = themeIndex.some

  if themeIndex != a.theme.currThemeIndex:
    if a.themeEditor.modified:
      openSaveDiscardThemeDialog(nextAction = switchTheme, a)
    else:
      switchTheme(a)

  # User theme indicator
  cx += 195
  var labelStyle = getDefaultLabelStyle()

  if not a.currThemeName.userTheme:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "U", style=labelStyle)

  # User theme override indicator
  cx += 13
  labelStyle = getDefaultLabelStyle()

  if not a.currThemeName.override:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "O", style=labelStyle)

  # Theme modified indicator
  cx += 16

  if a.themeEditor.modified:
    koi.label(cx, cy, 20, wh, IconAsterisk, style=getDefaultLabelStyle())

  # Theme action buttons
  cx = x+15
  cy += 40.0

  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    saveTheme(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Copy", disabled=buttonsDisabled):
    openCopyThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Rename",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openRenameThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openDeleteThemeDialog(a)

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(a.themeEditor.focusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  a.themeEditor.focusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  a.theme.updateTheme = true

# }}}

# }}}

# {{{ renderCommand()
proc renderCommand(x, y: float; command: string; bgColor, textColor: Color;
                   a: AppContext): float =
  alias(vg, a.vg)

  let w = vg.textWidth(command)
  let (x, y) = (round(x), round(y))

  vg.beginPath()
  vg.roundedRect(x, y-10, w+10, 18, 3)
  vg.fillColor(bgColor)
  vg.fill()

  vg.fillColor(textColor)
  discard vg.text(x+5, y, command)

  result = w


proc renderCommand(x, y: float; command: string; a): float =
  let s = a.theme.statusBarTheme

  renderCommand(x, y, command,
                bgColor=s.commandBackgroundColor, textColor=s.commandTextColor,
                a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(status, a.ui.status)

  let s = a.theme.statusBarTheme

  let ty = h * TextVertAlignFactor

  # Bar background
  vg.save()
  vg.translate(x, y)

  vg.beginPath()
  vg.rect(0, 0, w, h)
  vg.fillColor(s.backgroundColor)
  vg.fill()

  # Display cursor coordinates
  vg.setFont(14, "sans-bold")

  if a.doc.map.hasLevels:
    let
      l = currLevel(a)
      coordOpts = coordOptsForCurrLevel(a)

      cur = a.ui.cursor
      row = formatRowCoord(cur.row, l.rows, coordOpts, l.regionOpts)
      col = formatColumnCoord(cur.col, l.cols, coordOpts, l.regionOpts)

      cursorPos = fmt"({col}, {row})"
      tw = vg.textWidth(cursorPos)

    vg.fillColor(s.coordinatesColor)
    vg.textAlign(haLeft, vaMiddle)
    discard vg.text(w - tw - 7, ty, cursorPos)

    vg.intersectScissor(0, 0, w - tw - 15, h)

  # Display status message or warning
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 14
    CommandTextPadX = 10

  var x = 10.0

  # Clear expired warning messages
  if status.warning != "":
    let dt = getMonoTime() - status.warningT0
    if dt > status.warningTimeout:
      status.warning = ""

      if not status.keepMessageAfterWarningExpired:
        clearStatusMessage(a)

  # Display message
  if status.warning == "":
    vg.fillColor(s.textColor)
    discard vg.text(IconPosX, ty, status.icon)

    let tx = vg.text(MessagePosX, ty, status.message)
    x = tx + MessagePadX

    # Display commands, if present
    for i, cmd in status.commands:
      if i mod 2 == 0:
        let w = renderCommand(x, ty, cmd, a)
        x += w + CommandLabelPadX
      else:
        let text = cmd
        vg.fillColor(s.textColor)
        let tw = vg.text(round(x), round(ty), text)
        x = tw + CommandTextPadX

  # Display warning
  else:
    vg.fillColor(status.warningColor)
    discard vg.text(IconPosX, ty, IconWarning)
    discard vg.text(MessagePosX, ty, status.warning)

  vg.restore()

# }}}
# {{{ renderQuickReference()

proc renderQuickReference(x, y, w, h: float; a) =
  alias(vg, a.vg)
  let cfg = a.theme.config

  let
    p = "ui.quick-help."
    bgColor          = cfg.getColorOrDefault(p & "background")
    textColor        = cfg.getColorOrDefault(p & "text")
    titleColor       = cfg.getColorOrDefault(p & "title")
    commandBgColor   = cfg.getColorOrDefault(p & "command.background")
    commandTextColor = cfg.getColorOrDefault(p & "command.text")


  proc renderSection(x, y: float; items: seq[QuickRefItem];
                     colWidth: float; a: AppContext) =

    const
      RowHeight = 24.0
      SepaHeight = 14.0

    var
      x0 = x
      x  = x
      y  = y
      heightInc = RowHeight

    vg.setFont(14, "sans-bold")

    for item in items:
      case item.kind
      of qkShortcut:
        let shortcuts = a.ui.shortcuts[item.shortcut]
        heightInc = 0.0
        var ys = y
        for sc in shortcuts:
          let shortcut = sc.toStr()
          discard renderCommand(x, ys, shortcut,
                                commandBgColor, commandTextColor, a)
          ys += RowHeight
          heightInc += RowHeight
        if shortcuts.len > 1: heightInc += SepaHeight
        x += colWidth

      of qkKeyShortcuts:
        var sx = x
        for idx, sc in item.keyShortcuts:
          let shortcut = sc.toStr()
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.keyShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight

      of qkCustomShortcuts:
        var sx = x
        for idx, shortcut in item.customShortcuts:
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.customShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight


      of qkDescription:
        vg.fillColor(textColor)
        discard vg.text(round(x), round(y), item.description)
        x = x0
        y += heightInc

      of qkSeparator:
        y += SepaHeight


  let yOffs = max((h - 840) * 0.5, 0)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.save()
    vg.intersectScissor(x, y, w, h)

  koi.addDrawLayer(koi.currentLayer(), vg):
    # Background
    vg.beginPath()
    vg.rect(x, y, w, h)
    vg.fillColor(bgColor)
    vg.fill()

    # Title
    vg.setFont(20, "sans-bold")
    vg.fillColor(titleColor)
    vg.textAlign(haCenter, vaMiddle)
    discard vg.text(round(x + w*0.5), 60+yOffs, "Quick Keyboard Reference")

  let
    t = invLerp(MinWindowWidth, 800.0, w).clamp(0.0, 1.0)
    viewWidth = lerp(622.0, 680.0, t)
    columnWidth = lerp(300.0, 330.0, t)
    tabWidth = 400.0

  let radioButtonX = x + (w - tabWidth)*0.5

  koi.radioButtons(
    radioButtonX, 92+yOffs, tabWidth, 24,
    QuickRefTabLabels, a.quickRef.activeTab,
    style = a.theme.radioButtonStyle
  )

  koi.beginScrollView(x = x + (w - viewWidth)*0.5 + 4,
                      y = y + 150+yOffs,
                      w = viewWidth, h = (h - 176))

  let a = a
  var (sx, sy) = addDrawOffset(10, 10)

  const DefaultColWidth = 105.0

  let (viewHeight, colWidth) = case a.quickRef.activeTab
  of 0: (520.0, DefaultColWidth)
  of 1: (655.0, DefaultColWidth)
  else: (300.0, DefaultColWidth + 30)

  koi.addDrawLayer(koi.currentLayer(), vg):
    let items = a.ui.quickRefShortcuts[a.quickRef.activeTab]
    if items.len == 1: sx = radioButtonX + 70
    for r in items:
      renderSection(sx, sy, r, colWidth, a)
      sx += columnWidth

  koi.endScrollView(viewHeight)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.restore()

# }}}
# {{{ renderDialogs()
proc renderDialogs(a) =
  alias(dlg, a.dialogs)

  case dlg.activeDialog:
  of dlgNone: discard

  of dlgAboutDialog:
    aboutDialog(a)

  of dlgPreferencesDialog:
    preferencesDialog(dlg.preferencesDialog, a)

  of dlgSaveDiscardMapDialog:
    saveDiscardMapDialog(dlg.saveDiscardMapDialog, a)

  of dlgNewMapDialog:
    newMapDialog(dlg.newMapDialog, a)

  of dlgEditMapPropsDialog:
    editMapPropsDialog(dlg.editMapPropsDialog, a)

  of dlgNewLevelDialog:
    newLevelDialog(dlg.newLevelDialog, a)

  of dlgDeleteLevelDialog:
    deleteLevelDialog(a)

  of dlgEditLevelPropsDialog:
    editLevelPropsDialog(dlg.editLevelPropsDialog, a)

  of dlgEditNoteDialog:
    editNoteDialog(dlg.editNoteDialog, a)

  of dlgEditLabelDialog:
    editLabelDialog(dlg.editLabelDialog, a)

  of dlgResizeLevelDialog:
    resizeLevelDialog(dlg.resizeLevelDialog, a)

  of dlgEditRegionPropsDialog:
    editRegionPropsDialog(dlg.editRegionPropsDialog, a)

  of dlgSaveDiscardThemeDialog:
    saveDiscardThemeDialog(dlg.saveDiscardThemeDialog, a)

  of dlgCopyThemeDialog:
    copyThemeDialog(dlg.copyThemeDialog, a)

  of dlgRenameThemeDialog:
    renameThemeDialog(dlg.renameThemeDialog, a)

  of dlgOverwriteThemeDialog:
    overwriteThemeDialog(dlg.overwriteThemeDialog, a)

  of dlgDeleteThemeDialog:
    deleteThemeDialog(a)

# }}}
#
# {{{ renderUI()
proc renderUI(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    mainPane = mainPaneRect(a)
    toolsPaneHeight = toolsPaneHeight(mainPane.h)

  # Clear background
  vg.beginPath()

  # Make sure the background image extends to the notes list pane if open
  vg.rect(0, mainPane.y1, mainPane.w + mainPane.x1, mainPane.h)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.windowTheme.backgroundColor)

  vg.fill()

  if a.opts.showQuickReference:
    var w = winWidth()
    if a.opts.showThemeEditor: w -= ThemePaneWidth

    renderQuickReference(x=0, y=mainPane.y1, w=w, h=mainPane.h, a)

  else:
    if not map.hasLevels:
      renderEmptyMap(a)

    else:
      koi.beginView(x=mainPane.x1, y=mainPane.y1, w=mainPane.w, h=mainPane.h)

      # About button
      if button(x=mainPane.w-55.0, y=19.0, w=20.0, h=DlgItemHeight,
                IconQuestion, style=a.theme.aboutButtonStyle, tooltip="About"):
        openAboutDialog(a)

      renderLevelDropdown(a)

      if currLevel(a).regionOpts.enabled:
        renderRegionDropDown(a)

      let (levelDrawWidth, levelDrawHeight) = calculateLevelDrawArea(a)
      updateViewAndCursorPos(levelDrawWidth, levelDrawHeight, a)
      updateLastCursorViewCoords(a)

      alias(dp, ui.drawLevelParams)

      renderLevel(
        x = dp.startX,
        y = dp.startY,
        w = dp.viewCols * dp.gridSize,
        h = dp.viewRows * dp.gridSize,
        levelDrawWidth  = levelDrawWidth,
        levelDrawHeight = levelDrawHeight,
        a
      )

      renderModeAndOptionIndicators(
        x = mainPane.x1 + LevelLeftPad_NoCoords,
        y = a.win.titleBarHeight + 32,
        a
      )

      if a.opts.showToolsPane:
        renderToolsPane(
          x = mainPane.w - toolsPaneWidth(a),
          y = ToolsPaneTopPad,
          w = toolsPaneWidth(a),
          h = toolsPaneHeight,
          a
        )

      koi.endView()


    if map.hasLevels:
      if a.opts.showCurrentNotePane:
        var paneWidth = mainPane.w - CurrentNotePaneLeftPad -
                                     CurrentNotePaneRightPad

        let totalNotePaneHeight = CurrentNotePaneHeight +
                                  CurrentNotePaneTopPad +
                                  CurrentNotePaneBottomPad

        if mainPane.h - toolsPaneHeight - ToolsPaneTopPad <
           totalNotePaneHeight - 30:
          paneWidth -= toolsPaneWidth(a)

        renderCurrentNotePane(
          x = mainPane.x1 + CurrentNotePaneLeftPad,
          y = mainPane.y2 - CurrentNotePaneHeight - CurrentNotePaneBottomPad,
          w = paneWidth,
          h = CurrentNotePaneHeight,
          a
        )

      if a.opts.showNotesListPane:
        renderNotesListPane(x = 0, y = mainPane.y1,
                            w = NotesListPaneWidth,
                            h = mainPane.h, a)

  # Status bar
  let statusBarY = mainPane.y1 + mainPane.h
  renderStatusBar(0, statusBarY, winWidth(), StatusBarHeight, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.opts.showThemeEditor:
    let
      mainPane = mainPaneRect(a)
      x = mainPane.x1 + mainPane.w
      y = mainPane.y1
      w = ThemePaneWidth
      h = mainPane.h

    renderThemeEditorPane(x, y, w, h, a)

  renderDialogs(a)

  a.ui.prevCursor = a.ui.cursor

# }}}

# {{{ renderFramePreCb()
proc renderFramePreCb(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      a.theme.themeReloaded = (themeIndex == a.theme.currThemeIndex)
      switchTheme(themeIndex, a)

    except CatchableError as e:
      logError(e, "Error loading theme when switching theme")
      let name = a.theme.themeNames[themeIndex].name

      setErrorMessage(fmt"Cannot load theme '{name}': {e.msg}", a)

      a.theme.nextThemeIndex = Natural.none

    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message


  if a.theme.nextThemeIndex.isSome:
    loadPendingTheme(a.theme.nextThemeIndex.get, a)

  a.win.title = a.doc.map.title
  a.win.modified = a.doc.undoManager.isModified

  if a.theme.updateTheme:
    a.theme.updateTheme = false
    updateTheme(a)

  if a.theme.loadBackgroundImage:
    a.theme.loadBackgroundImage = false
    loadBackgroundImage(a.currThemeName, a)

  a.updateUI = true

# }}}
# {{{ renderFrameCb()

proc closeSplash(a)

proc renderFrameCb(a) =

  proc displayThemeLoadedMessage(a) =
    let themeName = a.currThemeName.name
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
      a.theme.themeReloaded = false
    else:
      setStatusMessage(fmt"Theme '{themeName}' loaded", a)

  if a.theme.nextThemeIndex.isSome:
    if a.theme.hideThemeLoadedMessage:
      a.theme.hideThemeLoadedMessage = false
    else:
      displayThemeLoadedMessage(a)
    a.theme.nextThemeIndex = Natural.none

  proc handleWindowClose(a) =
    proc saveConfigAndExit(a) =
      saveAppConfig(a)
      a.shouldClose = true

    proc handleMapModified(a) =
      if a.doc.undoManager.isModified:
        openSaveDiscardMapDialog(nextAction = saveConfigAndExit, a)
      else:
        saveConfigAndExit(a)

    when defined(NO_QUIT_DIALOG):
      saveConfigAndExit(a)
    else:
      if a.themeEditor.modified:
        openSaveDiscardThemeDialog(nextAction = handleMapModified, a)
      else:
        handleMapModified(a)

  # XXX HACK: If the theme pane is shown, widgets are handled first, then
  # the global shortcuts, so widget-specific shorcuts can take precedence
  var uiRendered = false
  if a.opts.showThemeEditor:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if a.opts.showQuickReference: handleQuickRefKeyEvents(a)
    elif a.doc.map.hasLevels:     handleGlobalKeyEvents(a)
    else:                         handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.opts.showThemeEditor and a.win.glfwWin.focused:
      glfw.makeContextCurrent(a.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(a.win.glfwWin)
      a.win.focus()

  if not a.opts.showThemeEditor or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash(a) =
  alias(s, a.splash)
  alias(vg, s.vg)

  let cfg = a.theme.config

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth.float / winWidth.float

  glViewport(0, 0, fbWidth, fbHeight)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth, winHeight, pxRatio)

  if s.logoImage == NoImage or s.updateLogoImage:
    colorImage(s.logo, cfg.getColorOrDefault("ui.splash-image.logo"))
    if s.logoImage == NoImage:
      s.logoImage = createImage(s.logo)
    else:
      vg.updateImage(s.logoImage, cast[ptr byte](s.logo.data))
    s.updateLogoImage = false

  if s.outlineImage == NoImage or s.updateOutlineImage:
    colorImage(s.outline, cfg.getColorOrDefault("ui.splash-image.outline"))
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

  s.shadowPaint = createPattern(
    vg, s.shadowImage,
    alpha=cfg.getFloatOrDefault("ui.splash-image.shadow-alpha"),
    scale=scale
  )

  vg.beginPath()
  vg.rect(0, 0, winWidth, winHeight)

  vg.fillPaint(s.shadowPaint)
  vg.fill()

  vg.fillPaint(s.outlinePaint)
  vg.fill()

  vg.fillPaint(s.logoPaint)
  vg.fill()

  vg.endFrame()


  if not a.opts.showThemeEditor and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.opts.showThemeEditor:
      not a.splash.show
    else:
      let autoClose =
        if not a.opts.showThemeEditor and a.prefs.autoCloseSplash:
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
      w.mouseButtonDown(mbMiddle) or autoClose

  if shouldCloseSplash(a):
    closeSplash(a)
    a.win.focus()

# }}}

# }}}

# {{{ Init & cleanup

# {{{ createSplashWindow()
proc createSplashWindow(mousePassthrough: bool = false; a) =
  alias(s, a.splash)

  var cfg = DefaultOpenglWindowConfig
  cfg.visible = false
  cfg.resizable = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.nMultiSamples = 4
  cfg.transparentFramebuffer = true
  cfg.decorated = false
  cfg.floating = true
  cfg.mousePassthrough = mousePassthrough

  when defined(windows):
    cfg.hideFromTaskbar = true
  else:
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  s.win = newWindow(cfg)
  s.win.title = "Gridmonger Splash Image"
  s.vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

# }}}
# {{{ showSplash()
proc showSplash(a) =
  alias(s, g_app.splash)

  let (_, _, maxWidth, maxHeight) = g_app.win.findCurrentMonitor().workArea
  let w = (maxWidth * 0.6).int32
  let h = (w/s.logo.width * s.logo.height).int32

  s.win.size = (w, h)
  s.win.pos = ((maxWidth - w) div 2, (maxHeight - h) div 2)
  s.win.show()

  if not a.opts.showThemeEditor:
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

  if not a.opts.showThemeEditor:
    koi.setFocusCaptured(false)

# }}}

# {{{ loadAndSetIcon()
proc loadAndSetIcon(a) =
  alias(p, a.paths)

  var icons: array[5, wrapper.IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width = img.width.int32
    icons[idx].height = img.height.int32
    icons[idx].pixels = cast[ptr uint8](img.data)

  var icon32  = loadImage(p.dataDir / "icon32.png")
  var icon48  = loadImage(p.dataDir / "icon48.png")
  var icon64  = loadImage(p.dataDir / "icon64.png")
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
  alias(p, a.paths)

  proc loadFont(fontName: string, path: string; a): Font =
    try:
      a.vg.createFont(fontName, path)
    except CatchableError as e:
      logging.error(fmt"Cannot load font '{path}'")
      raise e

  discard         loadFont("sans",       p.dataDir / "Roboto-Regular.ttf", a)
  let boldFont  = loadFont("sans-bold",  p.dataDir / "Roboto-Bold.ttf", a)
  let blackFont = loadFont("sans-black", p.dataDir / "Roboto-Black.ttf", a)
  let iconFont  = loadFont("icon",       p.dataDir / "GridmongerIcons.ttf", a)

  discard addFallbackFont(a.vg, boldFont, iconFont)
  discard addFallbackFont(a.vg, blackFont, iconFont)

# }}}
# {{{ loadSplashmages()
proc loadSplashImages(a) =
  alias(s, a.splash)
  alias(p, a.paths)

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

  al.logo = loadImage(a.paths.dataDir / "logo-small.png")
  createAlpha(al.logo)

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
GPU info:
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
# {{{ initPaths()
proc initPaths(a) =
  alias(p, a.paths)

  const ImagesDir = "Images"

  p.appDir = getAppDir()

  const ConfigDir = "Config"
  let portableMode = dirExists(p.appDir / ConfigDir)

  let resourcesDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      normalizedPath(p.appDir / ".." / "Resources")
    else:
      p.appDir

  p.dataDir   = resourcesDir / "Data"
  p.manualDir = resourcesDir / "Manual"
  p.themesDir = resourcesDir / "Themes"
  p.themeImagesDir = p.themesDir / ImagesDir

  p.userDataDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      getHomeDir() / "Library/Application Support/Gridmonger"
    else:
      getConfigDir() / "Gridmonger"

  p.configDir = p.userDataDir / ConfigDir
  p.configFile = p.configDir / "gridmonger.cfg"

  p.logDir = p.userDataDir / "Logs"
  p.logFile = p.logDir / "gridmonger.log"

  p.autosaveDir = p.userDataDir / "Autosaves"

  p.userThemesDir = p.userDataDir / "User Themes"
  p.userThemeImagesDir = p.userThemesDir / ImagesDir

# }}}
# {{{ createDirs()
proc createDirs(a) =
  alias(p, a.paths)

  createDir(p.userDataDir)
  createDir(p.configDir)
  createDir(p.logDir)
  createDir(p.autosaveDir)
  createDir(p.userThemesDir)
  createDir(p.userThemeImagesDir)

# }}}
# {{{ initPreferences()
proc initPreferences(cfg: HoconNode; a) =
  let prefs = cfg.getObjectOrEmpty("preferences")

  with a.prefs:
    showSplash         = prefs.getBoolOrDefault("splash.show-at-startup", true)

    autoCloseSplash    = prefs.getBoolOrDefault("splash.auto-close", false)

    splashTimeoutSecs  = prefs.getNaturalOrDefault(
                           "splash.auto-close-timeout-secs", 3
                         ).limit(SplashTimeoutSecsLimits)

    loadLastMap        = prefs.getBoolOrDefault("load-last-map", true)

    autosave           = prefs.getBoolOrDefault("auto-save.enabled", true)

    autosaveFreqMins   = prefs.getNaturalOrDefault(
                           "auto-save.frequency-mins", 2
                         ).limit(AutosaveFreqMinsLimits)

    vsync = prefs.getBoolOrDefault("video.vsync", true)

    const MovementWraparoundKey = "editing.movement-wraparound"
    if prefs.getOpt(MovementWraparoundKey).isSome:
      movementWraparound = prefs.getBoolOrDefault(
        MovementWraparoundKey, false
      )
    else:
      # TODO deprecated keys; drop support for these after a few releases
      let MovementWraparoundKey_v110 = "editing.movement-wrap-around"
      if prefs.getOpt(MovementWraparoundKey_v110).isSome:
        movementWraparound = prefs.getBoolOrDefault(
          MovementWraparoundKey_v110, false
        )
      else:
        let MovementWraparoundKey_v100 = "movement-wrap-around"
        movementWraparound = prefs.getBoolOrDefault(
          MovementWraparoundKey_v100, false
        )

    openEndedExcavate = prefs.getBoolOrDefault("editing.open-ended-excavate")
    yubnMovementKeys = prefs.getBoolOrDefault("editing.yubn-movement-keys")

    walkCursorMode = prefs.getEnumOrDefault("editing.walk-cursor-mode",
                                            WalkCursorMode)

# }}}
# {{{ restoreUIStateFromConfig()
proc restoreUIStateFromConfig(cfg: HoconNode, a) =
  let uiCfg = cfg.getObjectOrEmpty("last-state.ui")

  with a.opts:
    const ShowCurrentNotePaneKey = "option.show-current-note-pane"
    if uiCfg.getOpt(ShowCurrentNotePaneKey).isSome:
      showCurrentNotePane = uiCfg.getBoolOrDefault(
        ShowCurrentNotePaneKey, true
      )
    else:
      # TODO deprecated keys; drop support for these after a few releases
      const ShowCurrentNotePaneKey_v110 = "option.show-notes-pane"
      if uiCfg.getOpt(ShowCurrentNotePaneKey_v110).isSome:
        showCurrentNotePane = uiCfg.getBoolOrDefault(
          ShowCurrentNotePaneKey_v110, true
        )

    showNotesListPane = uiCfg.getBoolOrDefault("option.show-notes-list-pane", true)
    showToolsPane     = uiCfg.getBoolOrDefault("option.show-tools-pane",      true)
    walkMode          = uiCfg.getBoolOrDefault("option.walk-mode",            false)
    wasdMode          = uiCfg.getBoolOrDefault("option.wasd-mode",            false)
    pasteWraparound   = uiCfg.getBoolOrDefault("option.paste-wraparound",     false)

  a.ui.drawLevelParams.setZoomLevel(
    a.theme.levelTheme,
    uiCfg.getNaturalOrDefault("zoom-level", 9).limit(ZoomLevelLimits)
  )

  with a.ui.drawLevelParams:
    viewStartRow = uiCfg.getNaturalOrDefault("view-start.row", 0)
    viewStartCol = uiCfg.getNaturalOrDefault("view-start.column", 0)
    drawCellCoords = uiCfg.getBoolOrDefault("option.show-cell-coords", true)

  with a.ui.cursor:
    let currLevel = uiCfg.getNaturalOrDefault("current-level", 0)

    if currLevel > a.doc.map.levels.high:
      resetCursorAndViewStart(a)
    else:
      level = currLevel
      row   = uiCfg.getNaturalOrDefault("cursor.row",    0)
      col   = uiCfg.getNaturalOrDefault("cursor.column", 0)

# }}}

# {{{ handleOpenFileEvent()
proc handleOpenFileEvent(path: string; a) =
  closeDialog(a)
  returnToNormalMode(a)
  openMap(path, a)
  # TODO not needed on macOS at least
#  a.win.restore()
  a.win.focus()
  koi.setFramesLeft()

# }}}
# {{{ dropCb()
proc dropCb(window: Window, paths: PathDropInfo) =
  if paths.len > 0:
    let path = paths.items.toSeq[0]
    handleOpenFileEvent($path, g_app)

# }}}

# {{{ initApp()
proc initApp(configFile: Option[string], mapFile: Option[string],
             winCfg: HoconNode, hideSplash = false; a) =

  if configFile.isSome:
    a.paths.configFile = configFile.get

  let cfg = loadAppConfigOrDefault(a.paths.configFile)
  initPreferences(cfg, a)

  # TODO init from config
  with a.ui.notesListState:
    currFilter.typeFilter = @[nftNone, nftNumber, nftId, nftIcon]
    currFilter.order      = nfoType
    dirty                 = true

  loadFonts(a)
  loadAndSetIcon(a)

  a.doc.undoManager = newUndoManager[Map, UndoStateData]()
  a.ui.drawLevelParams = newDrawLevelParams()

  buildThemeList(a)

  const DefaultThemeName = "Default"

  var themeIndex = findThemeIndex(
    cfg.getStringOrDefault("last-state.theme-name", DefaultThemeName), a
  )
  if themeIndex.isNone:
    themeIndex = findThemeIndex(DefaultThemeName, a)

  if themeIndex.isSome:
    switchTheme(themeIndex.get, a)
  else:
    a.theme.config = DefaultThemeConfig

  # Init map & load last map, or map from command line
  a.doc.map = newMap("Untitled Map", game="", author="",
                     creationTime=currentLocalDatetimeString())

  let mapFileName = if mapFile.isSome: mapFile.get
                    else: cfg.getStringOrDefault("last-state.last-document", "")

  if mapFileName != "":
    discard loadMap(mapFileName, a)
  else:
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  restoreUIStateFromConfig(cfg, a)

  updateWalkKeys(a)
  updateShortcuts(a)
  updateLastCursorViewCoords(a)

  a.ui.toolbarDrawParams = a.ui.drawLevelParams.deepCopy

  a.splash.show = not hideSplash and a.prefs.showSplash
  a.splash.t0 = getMonoTime()
  setSwapInterval(a)

  a.updateUI = true

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePreCb(g_app)
  a.win.renderFrameCb = proc (win: CSDWindow) = renderFrameCb(g_app)
  a.win.renderFrameCb = proc (win: CSDWindow) = renderFrameCb(g_app)

  a.win.dropCb = dropCb

  # Set window size & position
  let mergedWinCfg = cfg.getObjectOrEmpty("last-state.window")
  mergedWinCfg.merge(winCfg)

  let width  = mergedWinCfg.getNaturalOrDefault("width", DefaultWindowWidth)
                           .limit(WindowWidthLimits)

  let height = mergedWinCfg.getNaturalOrDefault("height", DefaultWindowHeight)
                           .limit(WindowWidthLimits)

  let (_, _, defaultMaxWidth, defaultMaxHeight) = getPrimaryMonitor().workArea

  let defaultXPos = (defaultMaxWidth - width) div 2
  var xpos = mergedWinCfg.getIntOrDefault("x-position", defaultXPos)

  let defaultYPos = (defaultMaxHeight - height) div 2
  var ypos = mergedWinCfg.getIntOrDefault("y-position", defaultYPos)

  a.win.size = (width.int, height.int)
  a.win.pos = (xpos, ypos)

  if mergedWinCfg.getBoolOrDefault("maximized", false):
    a.win.maximize()

  a.win.showTitleBar = mergedWinCfg.getBoolOrDefault("show-title-bar", true)
  a.win.snapWindowToVisibleArea()

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

  if a.logFile != nil:
    a.logFile.close()

# }}}
# {{{ crashHandler() =

when not defined(DEBUG):

  proc crashHandler(e: ref Exception, a) =
    let doAutosave = a.doc.path != ""
    var crashAutosavePath = ""

    if doAutosave:
      try:
        crashAutosavePath = autoSaveMapOnCrash(a)
      except Exception as e:
        if a.logFile != nil:
          logError(e, "Error autosaving map on crash")

    var msg = "A fatal error has occured, Gridmonger will now exit.\n\n"

    if doAutoSave:
      if crashAutosavePath == "":
        msg &= "Autosaving map has been unsuccesful.\n\n"
      else:
        msg &= "The map has been successfully autosaved as '" &
               crashAutosavePath

    msg &= "\n\nIf the problem persists, please refer to the 'Get Involved' " &
           "section on the website at https://gridmonger.johnnovak.net"

    when not defined(DEBUG):
      discard osdialog_message(mblError, mbbOk, msg.cstring)

    if a.logFile != nil:
      logError(e, "An unexpected error has occured, exiting")

    quit(QuitFailure)

# }}}

# }}}

# {{{ main()
proc main() =

  if not appEvents.initOrQuit():
    # TODO error
    discard
    quit(QuitFailure)

  addExitProc(appEvents.shutdown)

  when defined(windows):
    discard attachOutputToConsole()

  g_app = new AppContext
  alias(a, g_app)

  a.doc.lastAutosaveTime = getMonoTime()

  try:
    initPaths(a)
    createDirs(a)
    initLogger(a)

    info(FullVersionInfo)
    info(CompiledAtInfo)
    info(fmt"Paths: {a.paths}")

    let (configFile, mapFile, winCfg) = parseCommandLineParams()
    info(fmt"Command line parameters: configFile: {configFile}, " &
         fmt"mapFile: {mapFile}, winCfg: {winCfg}")

    initGfx(a)

    # Handle starting the app bundle by opening a map file in Finder on macOS
    #
    # Waiting "a bit" seems to be the only sort-of reliable way to receive the
    # openFile Cocoa event which then gets mapped to the "Open File" app
    # event.
    when defined(macosx):
      sleep(80)

      let event = appEvents.tryReceiveEvent()
      if event.isSome and event.get.kind == aeOpenFile:
        initApp(configFile, mapFile=event.get.path.some, winCfg,
                hideSplash=true, a)
      else:
        initApp(configFile, mapFile, winCfg, a=a)

    else: # Windows, Linux
      initApp(configFile, mapFile, winCfg, a=a)

    a.win.show()

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)

      if a.aboutLogo.logo.data == nil:
        loadAboutLogoImage(a)

      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthrough = a.opts.showThemeEditor, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.opts.showThemeEditor:
          a.win.focus()

      if a.splash.win != nil:
        glfw.makeContextCurrent(a.splash.win)
        renderFrameSplash(a)
        glFlush()

      # Swap buffers
      if a.updateUI:
        glfw.swapBuffers(a.win.glfwWin)

      if a.splash.win != nil:
        glfw.swapBuffers(a.splash.win)

      handleAutoSaveMap(a)

      # Handle app events
      let event = appEvents.tryReceiveEvent()
      if event.isSome:
        let event = event.get
        case event.kind
        of aeFocus:
          a.win.focus()
          koi.setFramesLeft()

        of aeOpenFile:
          handleOpenFileEvent(event.path, a)

      # Poll/wait for events
      if koi.shouldRenderNextFrame():
        glfw.pollEvents()
      else:
        glfw.waitEvents()

    cleanup(a)

  except CatchableError as e:
    when defined(DEBUG): raise e
    else: crashHandler(e, a)

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
