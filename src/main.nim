# {{{ Imports

import std/algorithm
import std/httpclient
import std/lenientops
import std/logging as log except Level
import std/macros
import std/math
import std/monotimes
import std/options
import std/os
import std/sequtils
import std/sets
import std/setutils
import std/strformat
import std/strutils except strip, splitWhitespace
import std/sugar
import std/tables
import std/times
import std/unicode

# Libraries
import glad/gl
import glfw

import koi
from koi/utils import lerp, invLerp, remap

import nanovg

when not defined(DEBUG):
  import osdialog

when defined(windows):
  import platform/windows/console

import semver
import with

# Internal
import actions
import appevents
import cfghelper
import cmdline
import common
import ui/csdwindow
import ui/drawlevel
import ui/gfx
import fieldlimits
import ui/icons
import domain/level
import domain/map
import io/persistence
import domain/regions
import domain/selection
import ui/theme
import undomanager
import utils/converters
import utils/hocon
import utils/misc as gmUtils
import utils/naturalsort
import utils/rect
import utils/webbrowser

import main/actions_ui
import main/appcontext
import main/configio
import main/constants
import main/cursor
import main/dialogs
import main/events
import main/init
import main/keyboard
import main/logging
import main/mapio
import main/modes
import main/rendering
import main/shortcuts
import main/status_msg
import main/themeio
import main/versioncheck
import main/view

using a: var AppContext

# }}}

# {{{ Resources

when defined(windows):
  const arch = when defined(i386): "32" else: "64"
  {.link: fmt"extras/appicons/windows/gridmonger{arch}.res".}

# }}}
# {{{ main()
proc main() =

  appEvents.initOrQuit()

  when defined(windows):
    discard attachOutputToConsole()

  g_app = new AppContext
  alias(a, g_app)

  try:
    initPaths(a)
    createDirs(a)
    initLogger(a)

    log.info(FullVersionString)
    log.info(CompiledAt)
    log.info(fmt"Paths: {a.paths}")

    let (configFile, mapFile, winCfg) = parseCommandLineParams()
    log.info(fmt"Command line parameters: configFile: {configFile}, " &
             fmt"mapFile: {mapFile}, winCfg: {winCfg}")

    initGfx(a)

    # Handle starting the app bundle by opening a map file in Finder on macOS
    #
    # Waiting "a bit" seems to be the only sort-of reliable way to receive the
    # openFile Cocoa event which then gets mapped to the "Open File" app
    # event.
    when defined(macosx):
      sleep(80)

      let event = appEvents.tryRecv()
      if event.isSome and event.get.kind == aeOpenFile:
        initApp(configFile, mapFile=event.get.path.some, winCfg,
                hideSplash=true, a)
      else:
        initApp(configFile, mapFile, winCfg, a=a)

    else: # Windows, Linux
      initApp(configFile, mapFile, winCfg, a=a)

    a.win.show

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)

      if a.dialogs.about.aboutLogo.logo.data == nil:
        loadAboutLogoImage(a)

      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthrough = a.layout.showThemeEditor, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.layout.showThemeEditor:
          a.win.focus

      if a.splash.win != nil:
        glfw.makeContextCurrent(a.splash.win)
        renderFrameSplash(a)
        glFlush()

      # Swap buffers
      if a.updateUI:
        glfw.swapBuffers(a.win.glfwWin)

      if a.splash.win != nil:
        glfw.swapBuffers(a.splash.win)

      # Handle app events
      let event = appEvents.tryRecv()
      if event.isSome:
        let event = event.get
        case event.kind
        of aeFocus:         handleFocusEvent(event, a)
        of aeOpenFile:      handleOpenFileEvent(event, a)
        of aeAutoSave:      handleAutoSaveEvent(event, a)
        of aeVersionUpdate: handleVersionUpdateEvent(event, a)

        koi.setFramesLeft()

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
