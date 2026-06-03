import std/monotimes
import std/options
import std/tables
import std/times

import glfw
import koi
import nanovg

import actions
import common
import ui/all
import undomanager
import utils/all

type
  AppContext* = ref object
    win*:          CSDWindow
    vg*:           NVGContext

    prefs*:        Preferences
    paths*:        Paths
    keys*:         Keys
    ui*:           UIState
    dialogs*:      Dialogs
    layout*:       Layout
    savedLayouts*: array[4, Option[Layout]]

    theme*:        Theme
    themeEditor*:  ThemeEditor
    quickRef*:     QuickRef
    splash*:       Splash

    doc*:          Document

    shouldClose*:  bool
    updateUI*:     bool

    logFile*:      File

    latestVersion*:     Option[VersionInfo]
    versionFetchError*: Option[CatchableError]


  WalkCursorMode* = enum
    wcmStrafe = (0, "Strafe")
    wcmTurn   = (1, "Turn")

  WalkKeys* = object
    forward*, backward*, strafeLeft*, strafeRight*, turnLeft*, turnRight*: set[Key]


  LinkLinesMode* = enum
    llmManual      = (0, "Manual toggle")
    llmCurrentCell = (1, "Current cell")
    llmAlways      = (2, "Always")


  Preferences* = object
    # Startup tab
    loadLastMap*:        bool
    autosave*:          bool
    autosaveFreqMins*:   Natural
    checkForUpdates*:    bool

    # Interface tab
    showSplash*:         bool
    autoCloseSplash*:    bool
    splashTimeoutSecs*:  Natural
    vsync*:              bool
    scaleFactor*:        float
    modifierKeyMode*:    ModifierKeyMode   # macOS only

    # Editing tab
    movementWraparound*: bool
    walkCursorMode*:     WalkCursorMode
    yubnMovementKeys*:   bool
    linkLinesMode*:      LinkLinesMode
    openEndedExcavate*:  bool


  Paths* = object
    appDir*:             string
    dataDir*:            string
    logDir*:             string
    userDataDir*:        string
    configDir*:          string
    manualDir*:          string
    autosaveDir*:        string

    themesDir*:          string
    themeImagesDir*:     string
    userThemesDir*:      string
    userThemeImagesDir*: string

    configFile*:         string
    logFile*:            string

  ModifierKeyMode* = enum
    mkmControlAlt   = (0, "Control Alt")
    mkmCommandShift = (1, "Command Shift")

  Keys* = object
    shortcuts*:          Table[AppShortcut, seq[KeyShortcut]]
    quickRefShortcuts*:  seq[seq[seq[QuickRefItem]]]
    walkKeysWasd*:       WalkKeys
    walkKeysCursor*:     WalkKeys
    primaryModKey*:      ModifierKey

  Document* = object
    path*:               string
    lastSavePath*:       string
    map*:                Map
    undoManager*:        UndoManager[Map, UndoStateData]


  UIState* = object
    # Editing
    # -------
    editMode*:           EditMode
    # to restore the previous edit mode when exiting emPanLevel
    prevEditMode*:       EditMode

    pasteWraparound*:    bool

    # Navigation
    # ----------
    cursor*:             Location
    prevCursor*:         Location
    cursorOrient*:       CardinalDir           # used by Walk Mode
    prevMoveDir*:        Option[CardinalDir]   # used by the exacavate tool

    showCellCoords*:     bool
    drawTrail*:          bool
    walkMode*:           bool
    wasdMode*:           bool

    panLevelMode*:       PanLevelMode

    # Tools
    # -----
    currSpecialWall*:         range[0..SpecialWalls.high]
    currFloorColor*:          range[0..LevelTheme.floorBackgroundColor.high]

    drawWallRepeatAction*:    DrawWallRepeatAction
    drawWallRepeatWall*:      Wall
    drawWallRepeatDirection*: CardinalDir

    # Selections
    # ----------
    selection*:          Option[Selection]
    selRect*:            Option[SelectionRect]
    copyBuf*:            Option[SelectionBuffer]
    nudgeBuf*:           Option[SelectionBuffer]
    pasteUndoLocation*:  Location

    # Mouse handling
    # --------------
    mouseCanStartExcavate*:  bool
    mouseDragStartX*:        float
    mouseDragStartY*:        float

    # Cell linking
    # ------------
    linkSrcLocation*:        Location
    jumpToDestLocation*:     Location
    jumpToSrcLocations*:     seq[Location]
    jumpToSrcLocationIdx*:   Natural
    lastJumpToSrcLocation*:  Location
    wasDrawingTrail*:        bool

    momentaryShowLinkLines*: bool

    # Drawing
    # -------
    drawLevelParams*:        DrawLevelParams
    toolbarDrawParams*:      DrawLevelParams

    # used by the zooming logic
    prevCursorViewX*:        float
    prevCursorViewY*:        float

    levelDrawAreaWidth*:     float
    levelDrawAreaHeight*:    float

    backgroundImage*:        Option[Paint]

    manualNoteTooltipState*: ManualNoteTooltipState

    # Misc
    # ----
    status*:              StatusMessage
    notesListState*:      NotesListState
    showQuickReference*:  bool


  Layout* = object
    showCurrentNotePane*: bool
    showNotesListPane*:   bool
    showToolsPane*:       bool
    showThemeEditor*:     bool

    windowPos*:           tuple[x, y: int]
    windowSize*:          tuple[w, h: int]
    maximized*:           bool
    showTitleBar*:        bool


  ManualNoteTooltipState* = object
    show*:     bool
    location*: Location
    mx*:       float
    my*:       float


  NotesListState* = object
    currFilter*:        NotesListFilter
    prevFilter*:        NotesListFilter
    linkCursor*:        bool
    prevLinkCursor*:    bool

    levelSections*:     Table[Natural, bool]
    regionSections*:    Table[tuple[levelId: Natural, rc: RegionCoords], bool]

    cache*:             seq[NotesListCacheEntry]

    activeId*:          Option[ItemId]
    viewStartY*:        float
    restoreViewStartY*: bool
    newViewStartY*:     Option[float]
    newActiveId*:       Option[ItemId]


  NotesListCacheEntryKind* = enum
    nckNote, nckLevel, nckRegion

  NotesListCacheEntry* = object
    case kind*: NotesListCacheEntryKind
    of nckNote:
      id*:           ItemId
      location*:     Location
      height*:       float
    of nckLevel:
      levelId*:      Natural
    of nckRegion:
      regionCoords*: RegionCoords


  StatusMessage* = object
    icon*:        string
    message*:     string
    commands*:    seq[string]
    warning*:     WarningStatusMessage

  WarningStatusMessage* = object
    icon*:        string
    message*:     string
    color*:       Color
    t0*:          MonoTime
    timeout*:     Duration
    overwrite*:   bool
    keepMessage*: bool


  EditMode* = enum
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
    emSetCellLink
    emSelectJumpToLinkSrc

    # Special "momentary" mode; after exiting emPanLevel, the previous edit
    # mode is restored.
    emPanLevel

  PanLevelMode* = enum
    dlmCtrlLeftButton
    dlmMiddleButton

  DrawWallRepeatAction* = enum
    dwaNone  = "none"
    dwaSet   = "set"
    dwaClear = "clear"


  Theme* = object
    config*:                   HoconNode
    prevConfig*:               HoconNode

    themeNames*:               seq[ThemeName]
    currThemeIndex*:           Natural
    nextThemeIndex*:           Option[Natural]
    hideThemeLoadedMessage*:   bool
    themeReloaded*:            bool
    updateTheme*:              bool
    loadBackgroundImage*:      bool

    labelStyle*:               LabelStyle
    buttonStyle*:              ButtonStyle
    radioButtonStyle*:         RadioButtonsStyle
    dropDownStyle*:            DropDownStyle
    checkBoxStyle*:            CheckboxStyle
    sliderStyle*:              SliderStyle
    textFieldStyle*:           TextFieldStyle
    textAreaStyle*:            TextAreaStyle
    dialogStyle*:              DialogStyle

    aboutDialogStyle*:         DialogStyle
    aboutButtonStyle*:         ButtonStyle

    iconRadioButtonsStyle*:    RadioButtonsStyle
    warningLabelStyle*:        LabelStyle
    errorLabelStyle*:          LabelStyle

    levelDropDownStyle*:       DropDownStyle
    noteTextAreaStyle*:        TextAreaStyle

    notesListLevelSectionStyle*:  SectionHeaderStyle
    notesListRegionSectionStyle*: SectionHeaderStyle
    notesListScrollViewStyle*:    ScrollViewStyle

    windowTheme*:              WindowTheme
    statusBarTheme*:           StatusBarTheme
    currentNotePaneTheme*:     CurrentNotePaneTheme
    notesListPaneTheme*:       NotesListPaneTheme
    toolbarPaneTheme*:         ToolbarPaneTheme
    levelTheme*:               LevelTheme


  ThemeName* = object
    name*:      string
    userTheme*: bool
    override*:  bool


  Dialog* = enum
    dlgNone

    dlgAbout
    dlgPreferences

    dlgSaveDiscardMap

    dlgNewMap
    dlgEditMapProps

    dlgNewLevel
    dlgEditLevelProps
    dlgResizeLevel
    dlgDeleteLevel

    dlgEditNote
    dlgEditLabel

    dlgEditRegionProps

    dlgSaveDiscardTheme
    dlgCopyTheme
    dlgRenameTheme
    dlgOverwriteTheme
    dlgDeleteTheme


  Dialogs* = object
    activeDialog*:     Dialog

    about*:            AboutDialogParams
    preferences*:      PreferencesDialogParams

    saveDiscardMap*:   SaveDiscardMapDialogParams

    newMap*:           NewMapDialogParams
    editMapProps*:     EditMapPropsDialogParams

    newLevel*:         LevelPropertiesDialogParams
    editLevelProps*:   LevelPropertiesDialogParams
    resizeLevel*:      ResizeLevelDialogParams

    editNote*:         EditNoteDialogParams
    editLabel*:        EditLabelDialogParams

    editRegionProps*:  EditRegionPropsParams

    saveDiscardTheme*: SaveDiscardThemeDialogParams
    copyTheme*:        CopyThemeDialogParams
    renameTheme*:      RenameThemeDialogParams
    overwriteTheme*:   OverwriteThemeDialogParams


  AboutDialogParams* = object
    aboutLogo*:          AboutLogo

  AboutLogo* = object
    logo*:               ImageData
    logoImage*:          Image
    logoPaint*:          Paint
    updateLogoImage*:    bool


  PreferencesDialogParams* = object
    activeTab*:          Natural
    activateFirstTextField*: bool

    # General tab
    loadLastMap*:        bool
    autosave*:           bool
    autosaveFreqMins*:   string
    checkForUpdates*:    bool

    # Interface tab
    showSplash*:         bool
    autoCloseSplash*:    bool
    splashTimeoutSecs*:  string
    vsync*:              bool
    scalePercentage*:    float
    modifierKeyMode*:    Natural

    # Editing tab
    movementWraparound*: bool
    walkCursorMode*:     WalkCursorMode
    yubnMovementKeys*:   bool
    linkLinesMode*:      LinkLinesMode
    openEndedExcavate*:  bool


  SaveDiscardMapDialogParams* = object
    nextAction*:   proc (a: var AppContext)


  NewMapDialogParams* = object
    activeTab*:    Natural
    activateFirstTextField*: bool

    title*:        string
    game*:         string
    author*:       string

    origin*:       Natural
    rowStyle*:     Natural
    columnStyle*:  Natural
    rowStart*:     string
    columnStart*:  string
    notes*:        string


  EditMapPropsDialogParams* = object
    activeTab*:    Natural
    activateFirstTextField*: bool

    title*:        string
    game*:         string
    author*:       string

    origin*:       Natural
    rowStyle*:     Natural
    columnStyle*:  Natural
    rowStart*:     string
    columnStart*:  string
    notes*:        string


  LevelPropertiesDialogParams* = object
    activeTab*:           Natural
    activateFirstTextField*: bool

    # General tab
    locationName*:        string
    levelName*:           string
    elevation*:           string
    rows*:                string
    cols*:                string
    fillWithEmptyFloors*: bool

    # Coordinates tab
    overrideCoordOpts*:   bool
    origin*:              Natural
    rowStyle*:            Natural
    columnStyle*:         Natural
    rowStart*:            string
    columnStart*:         string

    # Regions tab
    enableRegions*:       bool
    colsPerRegion*:       string
    rowsPerRegion*:       string
    perRegionCoords*:     bool

    # Notes tab
    notes*:                string


  ResizeLevelDialogParams* = object
    activateFirstTextField*: bool

    rows*:         string
    cols*:         string
    anchor*:       ResizeAnchor


  ResizeAnchor* = enum
    raTopLeft,    raTop,    raTopRight,
    raLeft,       raCenter, raRight,
    raBottomLeft, raBottom, raBottomRight


  EditNoteDialogParams* = object
    activateFirstTextField*: bool
    editMode*:     bool
    row*:          Natural
    col*:          Natural
    kind*:         AnnotationKind
    index*:        Natural
    indexColor*:   range[0..LevelTheme.noteIndexBackgroundColor.high]
    customId*:     string
    icon*:         range[0..NoteIcons.high]
    text*:         string


  EditLabelDialogParams* = object
    activateFirstTextField*: bool
    editMode*:     bool
    row*:          Natural
    col*:          Natural
    text*:         string
    color*:        Natural


  EditRegionPropsParams* = object
    activateFirstTextField*: bool
    name*:         string
    notes*:        string

  SaveDiscardThemeDialogParams* = object
    nextAction*:   proc (a: var AppContext)

  CopyThemeDialogParams* = object
    activateFirstTextField*: bool
    newThemeName*: string

  RenameThemeDialogParams* = object
    activateFirstTextField*: bool
    newThemeName*: string


  OverwriteThemeDialogParams* = object
    themeName*:    string
    nextAction*:   proc (a: var AppContext)


  ThemeEditor* = object
    modified*:                bool

    sectionUserInterface*:    bool
    sectionWidget*:           bool
    sectionDropDown*:         bool
    sectionTextField*:        bool
    sectionDialog*:           bool
    sectionTitleBar*:         bool
    sectionStatusBar*:        bool
    sectionLevelDropDown*:    bool
    sectionAboutButton*:      bool
    sectionAboutDialog*:      bool
    sectionQuickHelp*:        bool
    sectionSplashImage*:      bool

    sectionLevel*:            bool
    sectionLevelGeneral*:     bool
    sectionGrid*:             bool
    sectionOutline*:          bool
    sectionShadow*:           bool
    sectionBackgroundHatch*:  bool
    sectionFloorColors*:      bool
    sectionNotes*:            bool
    sectionLabels*:           bool

    sectionPanes*:            bool
    sectionCurrentNotePane*:  bool
    sectionNotesListPane*:    bool
    sectionToolbarPane*:      bool

    focusCaptured*:           bool


  QuickRef* = object
    activeTab*:    Natural


  Splash* = object
    win*:           Window
    vg*:            NVGContext
    show*:          bool
    t0*:            MonoTime

    logo*:          ImageData
    outline*:       ImageData
    shadow*:        ImageData

    logoImage*:     Image
    outlineImage*:  Image
    shadowImage*:   Image

    logoPaint*:     Paint
    outlinePaint*:  Paint
    shadowPaint*:   Paint

    updateLogoImage*:     bool
    updateOutlineImage*:  bool
    updateShadowImage*:   bool


var g_app*: AppContext

# vim: et:ts=2:sw=2:fdm=marker
