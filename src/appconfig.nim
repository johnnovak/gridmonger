import logging
import options
import parsecfg
import strformat

import cfghelper
import common
import fieldlimits
import drawlevel
import utils

const
  SplashTimeoutSecsLimits* = intLimits(min=1, max=10)
  AutosaveFreqMinsLimits*  = intLimits(min=1, max=30)
  ZoomLevelLimits*         = intLimits(MinZoomLevel, MaxZoomLevel)
  WindowWidthLimits*       = intLimits(WindowMinWidth, max=20_000)
  WindowHeightLimits*      = intLimits(WindowMinHeight, max=20_000)

type
  AppConfig* = object
    prefs*: Preferences
    app*:   AppState
    win*:   WindowState
    misc*:  MiscState


  Preferences* = object
    showSplash*:        bool
    autoCloseSplash*:   bool
    splashTimeoutSecs*: Natural

    loadLastMap*:       bool
    disableVSync*:      bool

    autosave*:          bool
    autosaveFreqMins*:  Natural


  AppState* = object
    themeName*:      string

    zoomLevel*:      Natural
    currLevel*:      Natural
    cursorRow*:      Natural
    cursorCol*:      Natural
    viewStartRow*:   Natural
    viewStartCol*:   Natural

    showCellCoords*: bool
    showToolsPane*:  bool
    showNotesPane*:  bool

    wasdMode*:       bool
    walkMode*:       bool
    drawTrail*:      bool


  WindowState* = object
    maximized*:      bool
    xpos*, ypos*:    int
    width*, height*: Natural

  MiscState* = object
    lastMapFileName*: string


const DefaultAppConfig = AppConfig(
  prefs: Preferences(
    showSplash: true,
    autoCloseSplash: false,
    splashTimeoutSecs: 3,

    loadLastMap: true,
    disableVSync: false,

    autosave: true,
    autosaveFreqMins: 2
  ),

  win: WindowState(
    maximized: false,
    xpos: -1,
    ypos: -1,
    width: 700,
    height: 800
  ),

  app: AppState(
    themeName: "default",

    zoomLevel: 9,
    currLevel: 0,
    cursorRow: 0,
    cursorCol: 0,
    viewStartRow: 0,
    viewStartCol: 0,

    showCellCoords: true,
    showToolsPane: true,
    showNotesPane: true,

    wasdMode: false,
    walkMode: false,
    drawTrail: false
  ),

  misc: MiscState(
    lastMapFileName: ""
  )
)


const
  # --------------------------------------
  PreferencesSection = "preferences"

  ShowSplashKey = "showSplash"
  AutoCloseSplashKey = "autoCloseSplash"
  SplashTimeoutSecsKey = "splashTimeoutSecs"

  LoadLastMapKey = "loadLastMap"

  DisableVSyncKey = "disableVSync"

  AutosaveKey = "autosave"
  AutosaveFreqMinsKey = "autosaveFreqMins"

  # --------------------------------------
  WindowStateSection = "windowState"

  MaximizedKey = "maximized"
  XposKey = "xpos"
  YposKey = "ypos"
  WidthKey = "width"
  HeightKey = "height"

  # --------------------------------------
  AppStateSection = "appState"

  ThemeNameKey = "themeName"

  ZoomLevelKey = "zoomLevel"
  CurrLevelKey = "currLevel"
  CursorRowKey = "cursorRow"
  CursorColKey = "cursorCol"
  ViewStartRowKey = "viewStartRow"
  ViewStartColKey = "viewStartCol"

  ShowCellCoordsKey = "showCellCoords"
  ShowToolsPaneKey = "showToolsPane"
  ShowNotesPaneKey = "showNotesPane"

  WasdModeKey = "wasdMode"
  WalkModeKey = "walkMode"
  DrawTrailKey = "drawTrail"

  # --------------------------------------
  MiscStateSection = "miscState"

  LastMapFileNameKey = "lastMapFileName"


proc loadAppConfigOrDefault*(fname: string): AppConfig =
  result = DefaultAppConfig

  var cfg: Config
  try:
    cfg = loadConfig(fname)
  except CatchableError as e:
    warn(fmt"Couldn't load config file '{fname}', using default config")
    return result

  alias(p, result.prefs)

  cfg.getBool(   PreferencesSection, ShowSplashKey,        p.showSplash)
  cfg.getBool(   PreferencesSection, AutoCloseSplashKey,   p.autoCloseSplash)

  cfg.getNatural(PreferencesSection, SplashTimeoutSecsKey, p.splashTimeoutSecs,
                 SplashTimeoutSecsLimits)

  cfg.getBool(   PreferencesSection, LoadLastMapKey,       p.loadLastMap)
  cfg.getBool(   PreferencesSection, DisableVSyncKey,      p.disableVSync)
  cfg.getBool(   PreferencesSection, AutosaveKey,          p.autosave)

  cfg.getNatural(PreferencesSection, AutosaveFreqMinsKey,  p.autosaveFreqMins,
                 AutosaveFreqMinsLimits)

  alias(w, result.win)
  var winWidth, winHeight: Natural

  cfg.getBool(   WindowStateSection, MaximizedKey, w.maximized)
  cfg.getNatural(WindowStateSection, XposKey,      w.xpos)
  cfg.getNatural(WindowStateSection, YposKey,      w.ypos)
  cfg.getNatural(WindowStateSection, WidthKey,  winWidth,  WindowWidthLimits)
  cfg.getNatural(WindowStateSection, HeightKey, winHeight, WindowHeightLimits)

  if winWidth  >= WindowMinWidth:  w.width  = winWidth
  if winHeight >= WindowMinHeight: w.height = winHeight

  alias(a, result.app)

  cfg.getString( AppStateSection, ThemeNameKey, a.themeName)

  cfg.getNatural(AppStateSection, ZoomLevelKey, a.zoomLevel, ZoomLevelLimits)

  cfg.getNatural(AppStateSection, CurrLevelKey,      a.currLevel)
  cfg.getNatural(AppStateSection, CursorRowKey,      a.cursorRow)
  cfg.getNatural(AppStateSection, CursorColKey,      a.cursorCol)
  cfg.getNatural(AppStateSection, ViewStartRowKey,   a.viewStartRow)
  cfg.getNatural(AppStateSection, ViewStartColKey,   a.viewStartCol)

  cfg.getBool(   AppStateSection, ShowCellCoordsKey, a.showCellCoords)
  cfg.getBool(   AppStateSection, ShowToolsPaneKey,  a.showToolsPane)
  cfg.getBool(   AppStateSection, ShowNotesPaneKey,  a.showNotesPane)
  cfg.getBool(   AppStateSection, WasdModeKey,       a.wasdMode)
  cfg.getBool(   AppStateSection, WalkModeKey,       a.walkMode)
  cfg.getBool(   AppStateSection, DrawTrailKey,      a.drawTrail)

  alias(m, result.misc)

  cfg.getString(MiscStateSection, LastMapFileNameKey, m.lastMapFileName)


proc toOnOff(b: bool): string =
  if b: "on" else: "off"

proc toYesNo(b: bool): string =
  if b: "yes" else: "no"


proc toConfig(ac: AppConfig): Config =
  var cfg = newConfig()

  alias(p, ac.prefs)

  cfg.setSectionKey(PreferencesSection, ShowSplashKey,        p.showSplash.toYesNo)
  cfg.setSectionKey(PreferencesSection, AutoCloseSplashKey,   p.autoCloseSplash.toYesNo)
  cfg.setSectionKey(PreferencesSection, SplashTimeoutSecsKey, $p.splashTimeoutSecs)
  cfg.setSectionKey(PreferencesSection, LoadLastMapKey,       p.loadLastMap.toYesNo)
  cfg.setSectionKey(PreferencesSection, DisableVSyncKey,      $p.disableVSync)
  cfg.setSectionKey(PreferencesSection, AutosaveKey,          p.autosave.toYesNo)
  cfg.setSectionKey(PreferencesSection, AutosaveFreqMinsKey,  $p.autosaveFreqMins)

  alias(w, ac.win)

  cfg.setSectionKey(WindowStateSection, MaximizedKey, w.maximized.toYesNo)
  cfg.setSectionKey(WindowStateSection, XposKey,      $w.xpos)
  cfg.setSectionKey(WindowStateSection, YposKey,      $w.ypos)
  cfg.setSectionKey(WindowStateSection, WidthKey,     $w.width)
  cfg.setSectionKey(WindowStateSection, HeightKey,    $w.height)

  alias(a, ac.app)

  cfg.setSectionKey(AppStateSection, ThemeNameKey,      a.themeName)
  cfg.setSectionKey(AppStateSection, ZoomLevelKey,      $a.zoomLevel)
  cfg.setSectionKey(AppStateSection, CurrLevelKey,      $a.currLevel)
  cfg.setSectionKey(AppStateSection, CursorRowKey,      $a.cursorRow)
  cfg.setSectionKey(AppStateSection, CursorColKey,      $a.cursorCol)
  cfg.setSectionKey(AppStateSection, ViewStartRowKey,   $a.viewStartRow)
  cfg.setSectionKey(AppStateSection, ViewStartColKey,   $a.viewStartCol)
  cfg.setSectionKey(AppStateSection, ShowCellCoordsKey, a.showCellCoords.toYesNo)
  cfg.setSectionKey(AppStateSection, ShowToolsPaneKey,  a.showToolsPane.toYesNo)
  cfg.setSectionKey(AppStateSection, ShowNotesPaneKey,  a.showNotesPane.toYesNo)
  cfg.setSectionKey(AppStateSection, WasdModeKey,       a.wasdMode.toOnOff)
  cfg.setSectionKey(AppStateSection, WalkModeKey,       a.walkMode.toOnOff)
  cfg.setSectionKey(AppStateSection, DrawTrailKey,      a.drawTrail.toOnOff)

  alias(m, ac.misc)

  cfg.setSectionKey(MiscStateSection, LastMapFileNameKey, m.lastMapFileName)

  result = cfg


proc saveAppConfig*(a: AppConfig, fname: string) =
  try:
    writeConfig(a.toConfig, fname)
  except CatchableError as e:
    error(fmt"Couldn't write config file '{fname}'")


