import os
import common
import options
import parsecfg
import strformat
import strscans
import strutils

import cfghelper


type
  AppConfig* = object
    maximized*:             bool
    xpos*, ypos*:           int
    width*, height*:        int

    themeName*:             string

    autoSaveFrequencySecs*: int
    autoSaveSlots*:         Natural

    loadLastFile*:          bool
    lastFileName*:          string

    showSplash*:            bool

    resizeRedrawHack*:      bool
    resizeNoVsyncHack*:     bool


const DefaultAppConfig = AppConfig(
  maximized: false,
  xpos:   -1,
  ypos:   -1,
  width:  700,
  height: 800,

  themeName: "default",

  autoSaveFrequencySecs: 180,
  autoSaveSlots: 3,

  loadLastFile: true,
  lastFileName: "",

  showSplash: true,

  resizeRedrawHack:  false,
  resizeNoVsyncHack: false
)


const
  StartupSection = "startup"
  WindowSection = "window"
  ThemeSection = "theme"
  AutoSaveSection = "autosave"


proc loadAppConfig*(fname: string): AppConfig =
  var cfg = loadConfig(fname)

  var a = DefaultAppConfig.deepCopy()

  cfg.getBool(  StartupSection, "loadLastFile",   a.loadLastFile)
  cfg.getString(StartupSection, "lastFileName",   a.lastFileName)
  cfg.getBool(  StartupSection, "showSplash",     a.showSplash)

  cfg.getBool(WindowSection, "maximized",         a.maximized)
  cfg.getInt( WindowSection, "xpos",              a.xpos)
  cfg.getInt( WindowSection, "ypos",              a.ypos)
  cfg.getInt( WindowSection, "width",             a.width)
  cfg.getInt( WindowSection, "height",            a.height)
  cfg.getBool(WindowSection, "resizeRedrawHack",  a.resizeRedrawHack)
  cfg.getBool(WindowSection, "resizeNoVsyncHack", a.resizeNoVsyncHack)

  cfg.getString(ThemeSection, "themeName",        a.themeName)

  cfg.getInt(AutoSaveSection, "frequencySecs",    a.autoSaveFrequencySecs)
  cfg.getInt(AutoSaveSection, "slots",            a.autoSaveSlots)

  result = a


proc saveAppConfig*(fname: string): bool =
  try:
    createDir(fname)
    # TODO

    result = true
  except OSError:
    result = false

