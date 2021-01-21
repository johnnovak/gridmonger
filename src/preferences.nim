import options
import parsecfg

import cfghelper
import common


type
  Preferences* = object
    # Startup section
    showSplash*:            bool
    autoCloseSplash*:       bool
    splashTimeoutSecs*:     Natural

    loadLastMap*:           bool
    lastMapFileName*:       string

    # Window section
    maximized*:             bool
    xpos*, ypos*:           int
    width*, height*:        int
    disableVSync*:          bool

    # TODO UI state, use a common structure for preferences and the DISP chunk
    # UI section
    themeName*:             string    # conf & map
    zoomLevel*:             Natural   # conf & map
    showCellCoords*:        bool      # conf & map
    showToolsPane*:         bool      # conf & map
    showNotesPane*:         bool      # conf & map
    drawTrail*:             bool
    wasdMode*:              bool
    walkMode*:              bool

    currLevel*:             Natural
    cursorRow*:             Natural
    cursorCol*:             Natural
    viewStartRow*:          Natural
    viewStartCol*:          Natural

    # Autosave section
    autosave*:              bool
    autosaveFreqMins*:      Natural


const DefaultPreferences = Preferences(
  showSplash: true,
  autoCloseSplash: false,
  splashTimeoutSecs: 3,

  loadLastMap: true,
  lastMapFileName: "",

  maximized: false,
  xpos: -1,
  ypos: -1,
  width: 700,
  height: 800,
  disableVSync: false,

  themeName: "default",
  zoomLevel: 9,
  showCellCoords: true,
  showToolsPane: true,
  showNotesPane: true,
  drawTrail: false,
  wasdMode: false,
  walkMode: false,

  currLevel: 0,
  cursorRow: 0,
  cursorCol: 0,
  viewStartRow: 0,
  viewStartCol: 0,

  autosave: true,
  autosaveFreqMins: 60,
)


const
  StartupSection = "startup"
  ShowSplashKey = "showSplash"
  AutoCloseSplashKey = "autoCloseSplash"
  SplashTimeoutSecsKey = "splashTimeoutSecs"
  LoadLastMapKey = "loadLastMap"
  LastMapFileNameKey = "lastMapFileName"

  WindowSection = "window"
  MaximizedKey = "maximized"
  XposKey = "xpos"
  YposKey = "ypos"
  WidthKey = "width"
  HeightKey = "height"
  DisableVSyncKey = "disableVSync"

  UISection = "ui"
  ThemeNameKey = "themeName"
  ZoomLevelKey = "zoomLevel"
  ShowCellCoordsKey = "showCellCoords"
  ShowToolsPaneKey = "showToolsPane"
  ShowNotesPaneKey = "showNotesPane"
  DrawTrailKey = "drawTrail"
  WasdModeKey = "wasdMode"
  WalkModeKey = "walkMode"

  CurrLevelKey = "currLevel"
  CursorRowKey = "cursorRow"
  CursorColKey = "cursorCol"
  ViewStartRowKey = "viewStartRow"
  ViewStartColKey = "viewStartCol"

  AutoSaveSection = "autosave"
  EnabledKey = "enabled"
  FrequencySecsKey = "frequencySecs"


proc loadPreferences*(fname: string): Preferences =
  var cfg = loadConfig(fname)

  var a = DefaultPreferences.deepCopy()

  cfg.getBool(   StartupSection, ShowSplashKey,        a.showSplash)
  cfg.getBool(   StartupSection, AutoCloseSplashKey,   a.autoCloseSplash)
  cfg.getNatural(StartupSection, SplashTimeoutSecsKey, a.splashTimeoutSecs)
  cfg.getBool(   StartupSection, LoadLastMapKey,       a.loadLastMap)
  cfg.getString( StartupSection, LastMapFileNameKey,   a.lastMapFileName)

  cfg.getBool(    WindowSection, MaximizedKey,    a.maximized)
  cfg.getNatural( WindowSection, XposKey,         a.xpos)
  cfg.getNatural( WindowSection, YposKey,         a.ypos)
  cfg.getNatural( WindowSection, WidthKey,        a.width)
  cfg.getNatural( WindowSection, HeightKey,       a.height)
  cfg.getBool(    WindowSection, DisableVSyncKey, a.disableVSync)

  cfg.getString( UISection, ThemeNameKey,      a.themeName)
  cfg.getNatural(UISection, ZoomLevelKey,      a.zoomLevel)
  cfg.getBool(   UISection, ShowCellCoordsKey, a.showCellCoords)
  cfg.getBool(   UISection, ShowToolsPaneKey,  a.showToolsPane)
  cfg.getBool(   UISection, ShowNotesPaneKey,  a.showNotesPane)
  cfg.getBool(   UISection, DrawTrailKey,      a.drawTrail)
  cfg.getBool(   UISection, WasdModeKey,       a.wasdMode)
  cfg.getBool(   UISection, WalkModeKey,       a.walkMode)

  cfg.getNatural(UISection, CurrLevelKey,    a.currLevel)
  cfg.getNatural(UISection, CursorRowKey,    a.cursorRow)
  cfg.getNatural(UISection, CursorColKey,    a.cursorCol)
  cfg.getNatural(UISection, ViewStartRowKey, a.viewStartRow)
  cfg.getNatural(UISection, ViewStartColKey, a.viewStartCol)

  cfg.getBool(   AutoSaveSection, EnabledKey,       a.autosave)
  cfg.getNatural(AutoSaveSection, FrequencySecsKey, a.autosaveFreqMins)

  if a.width  < WindowMinWidth:  a.width  = DefaultPreferences.width
  if a.height < WindowMinHeight: a.height = DefaultPreferences.height

  result = a


proc toOnOff(b: bool): string =
  if b: "on" else: "off"

proc toYesNo(b: bool): string =
  if b: "yes" else: "no"


proc toConfig(a: Preferences): Config =
  var cfg = newConfig()

  cfg.setSectionKey(StartupSection, ShowSplashKey,        a.showSplash.toYesNo)
  cfg.setSectionKey(StartupSection, AutoCloseSplashKey,   a.autoCloseSplash.toYesNo)
  cfg.setSectionKey(StartupSection, SplashTimeoutSecsKey, $a.splashTimeoutSecs)
  cfg.setSectionKey(StartupSection, LoadLastMapKey,       a.loadLastMap.toYesNo)
  cfg.setSectionKey(StartupSection, LastMapFileNameKey,   a.lastMapFileName)

  cfg.setSectionKey(WindowSection, MaximizedKey,     a.maximized.toYesNo)
  cfg.setSectionKey(WindowSection, XposKey,          $a.xpos)
  cfg.setSectionKey(WindowSection, YposKey,          $a.ypos)
  cfg.setSectionKey(WindowSection, WidthKey,         $a.width)
  cfg.setSectionKey(WindowSection, HeightKey,        $a.height)
  cfg.setSectionKey(WindowSection, DisableVSyncKey,  $a.disableVSync)

  cfg.setSectionKey(UISection, ThemeNameKey,         a.themeName)
  cfg.setSectionKey(UISection, ZoomLevelKey,         $a.zoomLevel)
  cfg.setSectionKey(UISection, ShowCellCoordsKey,    a.showCellCoords.toYesNo)
  cfg.setSectionKey(UISection, ShowToolsPaneKey,     a.showToolsPane.toYesNo)
  cfg.setSectionKey(UISection, ShowNotesPaneKey,     a.showNotesPane.toYesNo)
  cfg.setSectionKey(UISection, DrawTrailKey,         a.drawTrail.toOnOff)
  cfg.setSectionKey(UISection, WasdModeKey,          a.wasdMode.toOnOff)
  cfg.setSectionKey(UISection, WalkModeKey,          a.walkMode.toOnOff)

  cfg.setSectionKey(UISection, CurrLevelKey,         $a.currLevel)
  cfg.setSectionKey(UISection, CursorRowKey,         $a.cursorRow)
  cfg.setSectionKey(UISection, CursorColKey,         $a.cursorCol)
  cfg.setSectionKey(UISection, ViewStartRowKey,      $a.viewStartRow)
  cfg.setSectionKey(UISection, ViewStartColKey,      $a.viewStartCol)

  cfg.setSectionKey(AutoSaveSection, EnabledKey,       a.autosave.toYesNo)
  cfg.setSectionKey(AutoSaveSection, FrequencySecsKey, $a.autosaveFreqMins)

  result = cfg


proc savePreferences*(a: Preferences, fname: string) =
  writeConfig(a.toConfig, fname)

