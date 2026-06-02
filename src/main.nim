import std/logging as log except Level
import std/options
import std/os
import std/strformat

import glad/gl
import glfw
import koi

when defined(windows):
  import platform/windows/console

import appevents
import cmdline
import common
import ui/csdwindow
import utils/misc as gmUtils

import main/appcontext
import main/init
import main/logging

using a: var AppContext

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
