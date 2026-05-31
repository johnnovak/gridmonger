# init
#
# App initialization and shutdown: splash window, fonts, icons, image
# loaders, graphics context, paths setup, preferences/layout restore from
# config, initApp, cleanup, crashHandler.
# Side effects: GL/glfw window creation, file system reads, config writes
# (in crashHandler), AppContext setup.

import std/lenientops          # float*int arithmetic
import std/logging as log except Level
import std/monotimes
import std/options
import std/os
import std/sequtils          # toSeq
import std/setutils          # fullSet
import std/strformat
import std/times             # initDuration

import glad/gl
import glfw
import koi
import nanovg
import semver
import with

import actions             # UndoStateData
import appevents
import cfghelper
import cmdline
import common
import domain/all
import fieldlimits
import main/actions_ui     # returnToNormalMode etc.
import main/appcontext
import main/configio
import main/constants
import main/cursor
import main/dialogs        # not strictly needed but easier to keep
import main/events         # handleQuickRefKeyEvents, handleGlobalKeyEvents
import main/keyboard
import main/logging
import main/mapio
import main/rendering        # renderUI, renderFrame etc.
import main/panes/statusbar
import main/themeio
import main/versioncheck
import ui/all
import ui/theme as themelib
import undomanager           # newUndoManager
import utils/all



using a: var AppContext

proc renderFramePreCb*(a)
proc renderFrameCb*(a)

# {{{ createSplashWindow()
proc createSplashWindow*(mousePassthrough: bool = false; a) =
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
proc showSplash*(a) =
  alias(s, g_app.splash)

  let (_, _, maxWidth, maxHeight) = g_app.win.findCurrentMonitor().workArea
  let w = (maxWidth * 0.6).int
  let h = (w/s.logo.width * s.logo.height).int

  s.win.size = (w, h)
  s.win.pos = ((maxWidth - w) div 2, (maxHeight - h) div 2)
  s.win.show

  if not a.layout.showThemeEditor:
    koi.setFocusCaptured(true)

# }}}
# {{{ closeSplash()
proc closeSplash*(a) =
  alias(s, a.splash)

  s.win.destroy
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

  if not a.layout.showThemeEditor:
    koi.setFocusCaptured(false)

# }}}

# {{{ loadAndSetIcon()
proc loadAndSetIcon*(a) =
  alias(p, a.paths)

  var icons: array[5, IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width  = img.width.int32
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
proc loadFonts*(a) =
  alias(p, a.paths)

  proc loadFont(fontName: string, path: string; a): Font =
    try:
      a.vg.createFont(fontName, path)
    except CatchableError as e:
      log.error(fmt"Cannot load font '{path}'")
      raise e

  discard         loadFont("sans",       p.dataDir / "Roboto-Regular.ttf", a)
  let boldFont  = loadFont("sans-bold",  p.dataDir / "Roboto-Bold.ttf", a)
  let blackFont = loadFont("sans-black", p.dataDir / "Roboto-Black.ttf", a)
  let iconFont  = loadFont("icon",       p.dataDir / "GridmongerIcons.ttf", a)

  discard addFallbackFont(a.vg, boldFont, iconFont)
  discard addFallbackFont(a.vg, blackFont, iconFont)

# }}}
# {{{ loadSplashmages()
proc loadSplashImages*(a) =
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
proc loadAboutLogoImage*(a) =
  alias(al, a.dialogs.about.aboutLogo)

  al.logo = loadImage(a.paths.dataDir / "logo-small.png")
  createAlpha(al.logo)

# }}}

# {{{ initGfx()
proc initGfx*(a) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    log.error("Error initialising OpenGL")
    quit(QuitFailure)

  let version  = cast[cstring](glGetString(GL_VERSION))
  let vendor   = cast[cstring](glGetString(GL_VENDOR))
  let renderer = cast[cstring](glGetString(GL_RENDERER))

  let msg = fmt"""
GPU info:
  Vendor:   {vendor}
  Renderer: {renderer}
  Version:  {version}"""

  log.info(msg)

  nvgInit(getProcAddress)
  let vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

  koi.init(vg, getProcAddress)

  a.win = win
  a.vg = vg

# }}}
# {{{ initPaths()
proc initPaths*(a) =
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
proc createDirs*(a) =
  alias(p, a.paths)

  createDir(p.userDataDir)
  createDir(p.configDir)
  createDir(p.logDir)
  createDir(p.autosaveDir)
  createDir(p.userThemesDir)
  createDir(p.userThemeImagesDir)

# }}}
# {{{ initPreferences()
proc initPreferences*(cfg: HoconNode; a) =
  let prefs = cfg.getObjectOrEmpty("preferences")

  with a.prefs:
    showSplash = prefs.getBoolOrDefault("splash.show-at-startup", true)

    autoCloseSplash = prefs.getBoolOrDefault("splash.auto-close.enabled", false)

    splashTimeoutSecs = prefs.getNaturalOrDefault(
                          "splash.auto-close.timeout-secs", 3
                        ).limit(SplashTimeoutSecsLimits)

    loadLastMap = prefs.getBoolOrDefault("load-last-map", true)

    autosave = prefs.getBoolOrDefault("auto-save.enabled", true)
    autosaveFreqMins = prefs.getNaturalOrDefault(
                         "auto-save.frequency-mins", 2
                       ).limit(AutosaveFreqMinsLimits)

    vsync = prefs.getBoolOrDefault("interface.vsync", true)

    scaleFactor = prefs.getIntOrDefault("interface.scale-percentage", 100)
                       .limit(UIScaleFactorLimits).float / 100

    checkForUpdates = prefs.getBoolOrDefault("check-for-updates", true)

    if prefs.getOpt("modifier-key-mode").isSome:
      modifierKeyMode = prefs.getEnumOrDefault("modifier-key-mode",
                                                ModifierKeyMode)
      when not defined(macosx):
        # Revert it to Ctrl+Alt if using a config copied from a Mac
        modifierKeyMode = mkmControlAlt
    else:
      modifierKeyMode = when defined(macosx): mkmCommandShift
                        else: mkmControlAlt

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

    yubnMovementKeys = prefs.getBoolOrDefault("editing.yubn-movement-keys")

    walkCursorMode = prefs.getEnumOrDefault("editing.walk-cursor-mode",
                                            WalkCursorMode)

    openEndedExcavate = prefs.getBoolOrDefault("editing.open-ended-excavate")

    linkLinesMode = prefs.getEnumOrDefault("editing.link-lines-mode",
                                            LinkLinesMode)

# }}}
# {{{ restoreLayoutsFromConfog()
proc restoreLayoutsFromConfig*(cfg: HoconNode; a) =
  proc toLayout(cfg: HoconNode): Layout =
    var l = Layout(
      showCurrentNotePane: cfg.getBoolOrDefault("show-current-note-pane",
                                                 true),
      showNotesListPane: cfg.getBoolOrDefault("show-notes-list-pane", false),
      showToolsPane:     cfg.getBoolOrDefault("show-tools-pane",      true),
      showThemeEditor:   cfg.getBoolOrDefault("show-theme-editor",    false)
    )

    let
      w = cfg.getNaturalOrDefault("window.size.0", DefaultWindowWidth)
             .limit(WindowWidthLimits)

      h = cfg.getNaturalOrDefault("window.size.1", DefaultWindowHeight)
             .limit(WindowHeightLimits)

    # Default to displaying the window centered on the primary monitor
    let
      (_, _, defaultMaxWidth,
             defaultMaxHeight) = glfw.getPrimaryMonitor().workArea

      cx = (defaultMaxWidth  - w) div 2
      cy = (defaultMaxHeight - h) div 2

      x = cfg.getIntOrDefault("window.pos.0", cx)
      y = cfg.getIntOrDefault("window.pos.1", cy)

    l.windowSize   = (w, h)
    l.windowPos    = (x, y)
    l.maximized    = cfg.getBoolOrDefault("window.maximized",      false)
    l.showTitleBar = cfg.getBoolOrDefault("window.show-title-bar", true)

    result = l


  a.layout = cfg.getObjectOrEmpty("last-state.layout").toLayout
  # The theme editor is always hidden at startup
  a.layout.showThemeEditor = false

  restoreLayout(a.layout, a)


  proc maybeSetSavedLayout(idx: Natural; a) =
    var obj = cfg.getObjectOpt(fmt"saved-layouts.{idx}")
    if obj.isSome:
      a.savedLayouts[idx] = obj.get.toLayout.some

  for idx in 0..a.savedLayouts.high:
    maybeSetSavedLayout(idx, a)

# }}}
# {{{ applyWindowConfigOverrides()
proc applyWindowConfigOverrides*(cfg: WindowConfig; a) =
  if cfg.layout.isSome:
    restoreLayout(cfg.layout.get, a)

  let (x, y) = a.win.pos
  if cfg.x.isSome: a.win.pos = (cfg.x.get, y)
  if cfg.y.isSome: a.win.pos = (x, cfg.y.get)

  let (width, height) = a.win.size
  if cfg.width.isSome:  a.win.size = (cfg.width.get, height)
  if cfg.height.isSome: a.win.size = (width, cfg.height.get)

  if cfg.maximized.isSome:
    if cfg.maximized.get: a.win.maximize
    else:                 a.win.unmaximize

  if cfg.showTitleBar.isSome:
    a.win.showTitleBar = cfg.showTitleBar.get

  a.win.snapWindowToVisibleArea

# }}}
# {{{ initApp()
proc dropCb*(window: Window, paths: PathDropInfo)

proc initApp*(configFile: Option[string], mapFile: Option[string],
             winCfg: WindowConfig, hideSplash = false; a) =

  if configFile.isSome:
    a.paths.configFile = configFile.get

  let cfg = loadAppConfigOrDefault(a.paths.configFile)
  initPreferences(cfg, a)

  if a.prefs.autosave:
    appEvents.setAutoSaveTimeout(
      initDuration(minutes = a.prefs.autosaveFreqMins)
    )
  else: appEvents.disableAutoSave()

  with a.ui.notesListState:
    currFilter.scope    = nsfLevel
    currFilter.noteType = NoteTypeFilter.fullSet
    currFilter.orderBy  = noType

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

  a.ui.drawLevelParams.setZoomLevel(a.theme.levelTheme, DefaultZoomLevel)

  a.ui.status.warning.overwrite = true

  # Init map & load last map, or map from command line
  a.doc.map = newMap("Untitled Map", game="", author="",
                     creationTime=currentLocalDatetimeString())

  let mapFileName = if mapFile.isSome: mapFile.get
                    else: cfg.getStringOrDefault("last-state.last-document", "")

  if mapFileName != "":
    discard loadMap(mapFileName, a)
  else:
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  updateWalkKeys(a)
  updateShortcuts(a)
  updateLastCursorViewCoords(a)

  a.ui.toolbarDrawParams = newDrawLevelParams()

  a.splash.show = not hideSplash and a.prefs.showSplash
  a.splash.t0 = getMonoTime()

  updateUIScaleFactor(a)
  setSwapInterval(a)

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePreCb(g_app)
  a.win.renderFrameCb    = proc (win: CSDWindow) = renderFrameCb(g_app)

  when not defined(macosx):
    a.win.contentScaleCb = windowContentScaleCb

  a.win.dropCb = dropCb

  restoreLayoutsFromConfig(cfg, a)
  applyWindowConfigOverrides(winCfg, a)

  if a.prefs.checkForUpdates:
    initVersionChecking(a)
    appEvents.fetchLatestVersion()

# }}}
# {{{ cleanup()
proc cleanup*(a) =
  log.info("Exiting app...")

  koi.deinit()

  nvgDeleteContext(a.vg)
  if a.splash.vg != nil:
    nvgDeleteContext(a.splash.vg)

  a.win.glfwWin.destroy
  if a.splash.win != nil:
    a.splash.win.destroy

  glfw.terminate()

  log.info("Cleanup successful, bye!")

  if a.logFile != nil:
    a.logFile.close

# }}}
# {{{ crashHandler()

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
        msg &= "Could not autosave map.\n\n"
      else:
        msg &= "The map has been autosaved as '" &
               crashAutosavePath

    msg &= "\n\nIf the problem persists, please refer to the " &
           fmt"'Get Involved' section on the website at {ProjectHomeUrl}"

    when not defined(DEBUG):
      discard osdialog_message(mblError, mbbOk, msg.cstring)

    if a.logFile != nil:
      logError(e, "An unexpected error has occured, exiting")

    quit(QuitFailure)

# }}}


# {{{ windowContentScaleCb()
proc windowContentScaleCb*(window: Window, xscale, yscale: float) =
  g_app.updateUIScaleFactor()
  g_app.updateUI = true

# }}}
# {{{ renderFramePreCb()
proc renderFramePreCb*(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      a.theme.themeReloaded = (themeIndex == a.theme.currThemeIndex)
      switchTheme(themeIndex, a)

    except CatchableError as e:
      logError(e, "Error loading theme when switching theme")
      a.logfile.flushFile

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


proc renderFrameCb*(a) =

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
  if a.layout.showThemeEditor:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if a.ui.showQuickReference: handleQuickRefKeyEvents(a)
    elif a.doc.map.hasLevels:     handleGlobalKeyEvents(a)
    else:                         handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.layout.showThemeEditor and a.win.glfwWin.focused:
      glfw.makeContextCurrent(a.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(a.win.glfwWin)
      a.win.focus

  if not a.layout.showThemeEditor or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash*(a) =
  alias(s, a.splash)
  alias(vg, s.vg)

  let cfg = a.theme.config

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth.float / winWidth.float

  glViewport(0, 0, fbWidth.GLsizei, fbHeight.GLsizei)

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

  vg.beginPath
  vg.rect(0, 0, winWidth, winHeight)

  vg.fillPaint(s.shadowPaint)
  vg.fill

  vg.fillPaint(s.outlinePaint)
  vg.fill

  vg.fillPaint(s.logoPaint)
  vg.fill

  vg.endFrame


  if not a.layout.showThemeEditor and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.layout.showThemeEditor:
      not a.splash.show
    else:
      let autoClose =
        if not a.layout.showThemeEditor and a.prefs.autoCloseSplash:
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
    a.win.focus

# }}}


# {{{ handleFocusEvent()
proc handleFocusEvent*(event: AppEvent; a) =
  a.win.requestAttention

# }}}
# {{{ handleOpenFileEvent()
proc handleOpenFileEvent*(event: AppEvent; a) =
  closeDialog(a)
  returnToNormalMode(a)
  openMap(event.path, a)
  # TODO not needed on macOS at least
#  a.win.restore
  a.win.focus

# }}}
# {{{ handleAutoSaveEvent()
proc handleAutoSaveEvent*(event: AppEvent; a) =
  if a.doc.undoManager.isModified:
    var path = if a.doc.path == "": a.doc.lastSavePath
               else: a.doc.path
    if path == "":
      path = findUniquePath(dir=a.paths.autosaveDir, name=UntitledName,
                            ext=MapFileExt)

    saveMap(path, autosave=true, createBackup=true, a)

# }}}
# {{{ handleVersionUpdateEvent()
proc handleVersionUpdateEvent*(event: AppEvent; a) =
  a.latestVersion     = event.versionInfo
  a.versionFetchError = event.error

  if a.latestVersion.isSome:
    let v = a.latestVersion.get
    if v.version > AppVersion and a.dialogs.activeDialog != dlgAbout:
      setWarningMessage(
        "Good news! A more recent version of Gridmonger is available: " &
        fmt"v{v.version} — {v.message}",
        icon=IconMug,
        keepStatusMessage=true, timeout=initDuration(seconds = 7),
        overwrite=false, a=a
      )

# }}}

# {{{ dropCb()
proc dropCb*(window: Window, paths: PathDropInfo) =
  if paths.len > 0:
    let path = paths.items.toSeq[0]
    handleOpenFileEvent(AppEvent(kind: aeOpenFile, path: $path), g_app)

# }}}

# }}}



# vim: et:ts=2:sw=2:fdm=marker
