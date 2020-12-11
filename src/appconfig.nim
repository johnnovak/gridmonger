import options
import parsecfg

import cfghelper
import common


type
  AppConfig* = object
    # startup section
    showSplash*:            bool
    loadLastFile*:          bool
    lastFileName*:          string

    # window section
    maximized*:             bool
    xpos*, ypos*:           int
    width*, height*:        int

    # TODO UI state, use a common structure for appconfig and the DISP chunk
    # ui section
    themeName*:             string
    zoomLevel*:             Natural
    showCellCoords*:        bool
    showToolsPane*:         bool
    showNotesPane*:         bool
    drawTrail*:             bool
    wasdMode*:              bool
    walkMode*:              bool

    currLevel*:             Natural
    cursorRow*:             Natural
    cursorCol*:             Natural
    viewStartRow*:          Natural
    viewStartCol*:          Natural

    # autosave section
    autoSaveFrequencySecs*: int
    autoSaveSlots*:         Natural


const DefaultAppConfig = AppConfig(
  showSplash: true,
  loadLastFile: true,
  lastFileName: "",

  maximized: false,
  xpos:   -1,
  ypos:   -1,
  width:  700,
  height: 800,

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

  autoSaveFrequencySecs: 180,
  autoSaveSlots: 3
)


const
  StartupSection = "startup"
  ShowSplashKey = "showSplash"
  LoadLastFileKey = "loadLastFile"
  LastFileNameKey = "lastFileName"

  WindowSection = "window"
  MaximizedKey = "maximized"
  XposKey = "xpos"
  YposKey = "ypos"
  WidthKey = "width"
  HeightKey = "height"

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
  FrequencySecsKey = "frequencySecs"
  SlotsKey = "slots"


proc loadAppConfig*(fname: string): AppConfig =
  var cfg = loadConfig(fname)

  var a = DefaultAppConfig.deepCopy()

  cfg.getBool(  StartupSection, ShowSplashKey,     a.showSplash)
  cfg.getBool(  StartupSection, LoadLastFileKey,   a.loadLastFile)
  cfg.getString(StartupSection, LastFileNameKey,   a.lastFileName)

  cfg.getBool(WindowSection, MaximizedKey,         a.maximized)
  cfg.getNatural( WindowSection, XposKey,          a.xpos)
  cfg.getNatural( WindowSection, YposKey,          a.ypos)
  cfg.getNatural( WindowSection, WidthKey,         a.width)
  cfg.getNatural( WindowSection, HeightKey,        a.height)

  cfg.getString(UISection, ThemeNameKey,           a.themeName)
  cfg.getNatural(   UISection, ZoomLevelKey,       a.zoomLevel)
  cfg.getBool(  UISection, ShowCellCoordsKey,      a.showCellCoords)
  cfg.getBool(  UISection, ShowToolsPaneKey,       a.showToolsPane)
  cfg.getBool(  UISection, ShowNotesPaneKey,       a.showNotesPane)
  cfg.getBool(  UISection, DrawTrailKey,           a.drawTrail)
  cfg.getBool(  UISection, WasdModeKey,            a.wasdMode)
  cfg.getBool(  UISection, WalkModeKey,            a.walkMode)

  cfg.getNatural(UISection, CurrLevelKey,           a.currLevel)
  cfg.getNatural(UISection, CursorRowKey,           a.cursorRow)
  cfg.getNatural(UISection, CursorColKey,           a.cursorCol)
  cfg.getNatural(UISection, ViewStartRowKey,        a.viewStartRow)
  cfg.getNatural(UISection, ViewStartColKey,        a.viewStartCol)

  cfg.getNatural(AutoSaveSection, FrequencySecsKey, a.autoSaveFrequencySecs)
  cfg.getNatural(AutoSaveSection, SlotsKey,         a.autoSaveSlots)

  if a.width  < WindowMinWidth:  a.width  = DefaultAppConfig.width
  if a.height < WindowMinHeight: a.height = DefaultAppConfig.height

  result = a


proc toOnOff(b: bool): string =
  if b: "on" else: "off"

proc toYesNo(b: bool): string =
  if b: "yes" else: "no"


proc toConfig(a: AppConfig): Config =
  var cfg = newConfig()

  cfg.setSectionKey(StartupSection, ShowSplashKey,       a.showSplash.toYesNo)
  cfg.setSectionKey(StartupSection, LoadLastFileKey,     a.loadLastFile.toYesNo)
  cfg.setSectionKey(StartupSection, LastFileNameKey,     a.lastFileName)

  cfg.setSectionKey(WindowSection, MaximizedKey,         a.maximized.toYesNo)
  cfg.setSectionKey(WindowSection, XposKey,              $a.xpos)
  cfg.setSectionKey(WindowSection, YposKey,              $a.ypos)
  cfg.setSectionKey(WindowSection, WidthKey,             $a.width)
  cfg.setSectionKey(WindowSection, HeightKey,            $a.height)

  cfg.setSectionKey(UISection, ThemeNameKey,             a.themeName)
  cfg.setSectionKey(UISection, ZoomLevelKey,             $a.zoomLevel)
  cfg.setSectionKey(UISection, ShowCellCoordsKey,        a.showCellCoords.toYesNo)
  cfg.setSectionKey(UISection, ShowToolsPaneKey,         a.showToolsPane.toYesNo)
  cfg.setSectionKey(UISection, ShowNotesPaneKey,         a.showNotesPane.toYesNo)
  cfg.setSectionKey(UISection, DrawTrailKey,             a.drawTrail.toOnOff)
  cfg.setSectionKey(UISection, WasdModeKey,              a.wasdMode.toOnOff)
  cfg.setSectionKey(UISection, WalkModeKey,              a.walkMode.toOnOff)

  cfg.setSectionKey(UISection, CurrLevelKey,             $a.currLevel)
  cfg.setSectionKey(UISection, CursorRowKey,             $a.cursorRow)
  cfg.setSectionKey(UISection, CursorColKey,             $a.cursorCol)
  cfg.setSectionKey(UISection, ViewStartRowKey,          $a.viewStartRow)
  cfg.setSectionKey(UISection, ViewStartColKey,          $a.viewStartCol)

  cfg.setSectionKey(AutoSaveSection, FrequencySecsKey, $a.autoSaveFrequencySecs)
  cfg.setSectionKey(AutoSaveSection, SlotsKey,         $a.autoSaveSlots)

  result = cfg


proc saveAppConfig*(a: AppConfig, fname: string) =
  writeConfig(a.toConfig, fname)

