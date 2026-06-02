import std/logging as log except Level
import std/options
import std/strformat
import std/streams
import std/sugar

import cfghelper
import common
import main/appcontext
import main/views/statusbar
import main/theme
import ui/all
import utils/all


using a: var AppContext

# {{{ setLayoutWindowFields()
proc setLayoutWindowFields(l: var Layout; a) =
  l.windowPos    = if a.win.maximized: a.win.unmaximizedPos  else: a.win.pos
  l.windowSize   = if a.win.maximized: a.win.unmaximizedSize else: a.win.size
  l.maximized    = a.win.maximized
  l.showTitleBar = a.win.showTitleBar

# }}}
# {{{ saveLayout*()

proc saveAppConfig*(a)

proc saveLayout*(layoutIdx: Natural; a) =
  assert layoutIdx <= a.savedLayouts.high

  var l = a.layout
  setLayoutWindowFields(l, a)
  a.savedLayouts[layoutIdx] = l.some

  saveAppConfig(a)
  setStatusMessage(IconTiles, fmt"Window layout {layoutIdx+1} saved", a)

# }}}
# {{{ restoreLayout*()
proc restoreLayout*(layout: Layout; a) =
  a.layout = layout

  if layout.maximized: a.win.maximize
  else:                a.win.unmaximize

  if layout.maximized:
    a.win.unmaximizedPos  = layout.windowPos
    a.win.unmaximizedSize = layout.windowSize
  else:
    a.win.pos  = layout.windowPos
    a.win.size = layout.windowSize

  a.win.showTitleBar = layout.showTitleBar

  a.win.snapWindowToVisibleArea


proc restoreLayout*(layoutIdx: Natural; a) =
  assert layoutIdx <= a.savedLayouts.high

  if a.savedLayouts[layoutIdx].isSome:
    restoreLayout(a.savedLayouts[layoutIdx].get, a)

    setStatusMessage(IconTiles, fmt"Window layout {layoutIdx+1} restored", a)
  else:
    setWarningMessage(fmt"Window layout {layoutIdx+1} is not set",a=a)

# }}}

# {{{ loadAppConfigOrDefault*()
proc loadAppConfigOrDefault*(path: string): HoconNode =
  var s: FileStream
  try:
    s = newFileStream(path)
    var p = initHoconParser(s)
    result = p.parse
  except CatchableError as e:
    log.warn(
      fmt"Cannot load config file '{path}', using default config. " &
      fmt"Error message: {e.msg}"
    )
    result = newHoconObject()
  finally:
    if s != nil: s.close

# }}}
# {{{ saveAppConfig*()
proc saveAppConfig*(cfg: HoconNode, path: string; a) =
  var s: FileStream
  try:
    s = newFileStream(path, fmWrite)
    cfg.write(s)
  except CatchableError as e:
    log.error(
      fmt"Cannot write config file '{path}'. Error message: {e.msg}"
    )
  finally:
    a.logfile.flushFile
    if s != nil: s.close


proc saveAppConfig*(a) =
  var cfg = newHoconObject()
  cfg.set("config-version", $AppVersion)

  # Preferences
  var p = "preferences."
  cfg.set(p & "load-last-map",                  a.prefs.loadLastMap)

  cfg.set(p & "splash.show-at-startup",         a.prefs.showSplash)
  cfg.set(p & "splash.auto-close.enabled",      a.prefs.autoCloseSplash)
  cfg.set(p & "splash.auto-close.timeout-secs", a.prefs.splashTimeoutSecs)

  cfg.set(p & "auto-save.enabled",              a.prefs.autosave)
  cfg.set(p & "auto-save.frequency-mins",       a.prefs.autosaveFreqMins)

  cfg.set(p & "editing.movement-wraparound",    a.prefs.movementWraparound)
  cfg.set(p & "editing.yubn-movement-keys",     a.prefs.yubnMovementKeys)

  cfg.set(p & "editing.walk-cursor-mode",
          enumToDashCase($a.prefs.walkCursorMode))

  cfg.set(p & "editing.open-ended-excavate",    a.prefs.openEndedExcavate)

  cfg.set(p & "editing.link-lines-mode",
          enumToDashCase($a.prefs.linkLinesMode))

  cfg.set(p & "interface.vsync",                a.prefs.vsync)
  cfg.set(p & "interface.scale-percentage",    (a.prefs.scaleFactor * 100).int)

  cfg.set(p & "check-for-updates",              a.prefs.checkForUpdates)

  cfg.set(p & "modifier-key-mode", enumToDashCase($a.prefs.modifierKeyMode))

  # Last state
  p = "last-state."
  cfg.set(p & "last-document", if a.doc.path == "": a.doc.lastSavePath
                               else: a.doc.path)

  cfg.set(p & "theme-name", a.currThemeName.name)

  proc mkLayoutObject(layout: Option[Layout]): HoconNode =
    if layout.isSome:
      let l = layout.get
      var obj = newHoconObject()

      obj.set("show-current-note-pane", l.showCurrentNotePane)
      obj.set("show-notes-list-pane",   l.showNotesListPane)
      obj.set("show-tools-pane",        l.showToolsPane)
      obj.set("show-theme-editor",      l.showThemeEditor)

      obj.set("window.pos",  hoconNode(@[l.windowPos.x, l.windowPos.y]))
      obj.set("window.size", hoconNode(@[l.windowSize.w, l.windowSize.h]))
      obj.set("window.maximized",       l.maximized)
      obj.set("window.show-title-bar",  l.showTitleBar)

      result = obj
    else:
      result = hoconNodeNull

  var currLayout = a.layout
  setLayoutWindowFields(currLayout, a)
  # The theme editor is always hidden at startup
  currLayout.showThemeEditor = false

  cfg.set(p & "layout", mkLayoutObject(currLayout.some))

  let layouts = collect:
    for l in a.savedLayouts: mkLayoutObject(l)

  # Layouts
  cfg.set("saved-layouts", hoconNode(layouts))

  saveAppConfig(cfg, a.paths.configFile, a)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
