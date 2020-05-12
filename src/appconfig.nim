import os
import options
import parsecfg

import cfghelper
import common


type
  AppConfig* = object
    showSplash*:            bool
    loadLastFile*:          bool
    lastFileName*:          string

    maximized*:             bool
    xpos*, ypos*:           int
    width*, height*:        int
    resizeRedrawHack*:      bool
    resizeNoVsyncHack*:     bool

    themeName*:             string
    zoomLevel*:             Natural
    showCellCoords*:        bool
    showToolsPane*:         bool
    showNotesPane*:         bool
    drawTrail*:             bool
    wasdMode*:              bool
    walkMode*:              bool

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
  resizeRedrawHack:  false,
  resizeNoVsyncHack: false,

  themeName: "default",
  zoomLevel: 9,
  showCellCoords: true,
  showToolsPane: true,
  showNotesPane: true,
  drawTrail: false,
  wasdMode: false,
  walkMode: false,

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
  ResizeRedrawHackKey = "resizeRedrawHack"
  ResizeNoVsyncHackKey = "resizeNoVsyncHack"

  UISection = "ui"
  ThemeNameKey = "themeName"
  ZoomLevelKey = "zoomLevel"
  ShowCellCoordsKey = "showCellCoords"
  ShowToolsPaneKey = "showToolsPane"
  ShowNotesPaneKey = "showNotesPane"
  DrawTrailKey = "drawTrail"
  WasdModeKey = "wasdMode"
  WalkModeKey = "walkMode"

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
  cfg.getInt( WindowSection, XposKey,              a.xpos)
  cfg.getInt( WindowSection, YposKey,              a.ypos)
  cfg.getInt( WindowSection, WidthKey,             a.width)
  cfg.getInt( WindowSection, HeightKey,            a.height)
  cfg.getBool(WindowSection, ResizeRedrawHackKey,  a.resizeRedrawHack)
  cfg.getBool(WindowSection, ResizeNoVsyncHackKey, a.resizeNoVsyncHack)

  cfg.getString(UISection, ThemeNameKey,           a.themeName)
  cfg.getInt(   UISection, ZoomLevelKey,           a.zoomLevel)
  cfg.getBool(  UISection, ShowCellCoordsKey,      a.showCellCoords)
  cfg.getBool(  UISection, ShowToolsPaneKey,       a.showToolsPane)
  cfg.getBool(  UISection, ShowNotesPaneKey,       a.showNotesPane)
  cfg.getBool(  UISection, DrawTrailKey,           a.drawTrail)
  cfg.getBool(  UISection, WasdModeKey,            a.wasdMode)
  cfg.getBool(  UISection, WalkModeKey,            a.walkMode)

  cfg.getInt(AutoSaveSection, FrequencySecsKey,    a.autoSaveFrequencySecs)
  cfg.getInt(AutoSaveSection, SlotsKey,            a.autoSaveSlots)

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
  cfg.setSectionKey(WindowSection, ResizeRedrawHackKey,  a.resizeRedrawHack.toOnOff)
  cfg.setSectionKey(WindowSection, ResizeNoVsyncHackKey, a.resizeNoVsyncHack.toOnOff)

  cfg.setSectionKey(UISection, ThemeNameKey,             a.themeName)
  cfg.setSectionKey(UISection, ZoomLevelKey,             $a.zoomLevel)
  cfg.setSectionKey(UISection, ShowCellCoordsKey,        a.showCellCoords.toYesNo)
  cfg.setSectionKey(UISection, ShowToolsPaneKey,         a.showToolsPane.toYesNo)
  cfg.setSectionKey(UISection, ShowNotesPaneKey,         a.showNotesPane.toYesNo)
  cfg.setSectionKey(UISection, DrawTrailKey,             a.drawTrail.toOnOff)
  cfg.setSectionKey(UISection, WasdModeKey,              a.wasdMode.toOnOff)
  cfg.setSectionKey(UISection, WalkModeKey,              a.walkMode.toOnOff)

  cfg.setSectionKey(AutoSaveSection, FrequencySecsKey, $a.autoSaveFrequencySecs)
  cfg.setSectionKey(AutoSaveSection, SlotsKey,         $a.autoSaveSlots)

  result = cfg


proc saveAppConfig*(a: AppConfig, fname: string) =
  writeConfig(a.toConfig, fname)

