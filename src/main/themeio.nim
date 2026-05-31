# themeio
#
# Theme load/save/switch and supporting helpers. Reads .gmtheme files from
# the bundled themes dir and user themes dir, parses them via the HOCON
# loader, builds koi widget styles from theme config, and writes user
# themes back on save.
# Side effects: file system reads/writes, AppContext mutation (theme.* and
# styles).

import std/algorithm
import std/logging as log except Level
import std/options
import glfw                  # swapInterval
import std/os
import std/strformat
import std/strutils
import std/unicode

import koi
import nanovg
import with                 # `with` macro

import cfghelper
import common
import main/appcontext
import main/constants       # ThemeExt
import main/logging         # logError
import main/status_msg      # setStatusMessage, setWarningMessage
import ui/csdwindow         # `theme=` setter on CSDWindow
import ui/drawlevel         # initDrawLevelParams
import ui/gfx               # createPattern, colorImage, createAlpha
import ui/icons             # IconFloppy, IconWarning, etc.
import ui/theme as themelib # toLevelTheme/toWindowTheme/etc. (renamed to avoid clash with `a.win.theme=`)
import utils/misc           # alias
import utils/naturalsort


using a: var AppContext

# {{{ setSwapInterval()
proc setSwapInterval*(a) =
  glfw.swapInterval(if a.prefs.vsync: 1 else: 0)

# }}}
# {{{ getFinalUIScaleFactor()
proc getFinalUIScaleFactor*(a): float =
  when defined(macosx):
    a.prefs.scaleFactor
  else:
    a.win.contentScale.xScale * a.prefs.scaleFactor

# }}}
# {{{ updateUIScaleFactor()
proc updateUIScaleFactor*(a) =
  koi.setScale(getFinalUIScaleFactor(a))
  a.theme.updateTheme = true

# }}}
# {{{ currThemeName()
func currThemeName*(a): ThemeName =
  a.theme.themeNames[a.theme.currThemeIndex]

# }}}
# {{{ findThemeIndex()
func findThemeIndex*(name: string; a): Option[Natural] =
  for i, themeName in a.theme.themeNames.mpairs:
    if themeName.name == name:
      return i.Natural.some

# }}}
# {{{ themePath()
func themePath*(theme: ThemeName; a): string =
  let themeDir = if theme.userTheme: a.paths.userThemesDir
                 else: a.paths.themesDir
  themeDir / addFileExt(theme.name, ThemeExt)

# }}}
# {{{ makeUniqueThemeName()
proc makeUniqueThemeName*(themeName: string; a): string =
  var basename = themeName
  var i = 1

  var s = themeName.rsplit(' ', maxsplit=1)
  if s.len == 2:
    try:
      i = parseInt(s[1])
      basename = s[0]
    except ValueError:
      discard

  while true:
    inc(i)
    result = fmt"{basename} {i}"
    if findThemeIndex(result, a).isNone: return

# }}}

# {{{ buildThemeList()
proc buildThemeList*(a) =
  var themeNames: seq[ThemeName] = @[]

  func findThemeWithName(name: string): int =
    for i, themeName in themeNames.mpairs:
      if themeName.name == name: return i
    result = -1

  proc addThemeNames(themesDir: string, userTheme: bool) =
    for path in walkFiles(themesDir / fmt"*.{ThemeExt}"):
      let (_, name, _) = splitFile(path)
      let idx = findThemeWithName(name)
      if idx >= 0:
        themeNames.del(idx)
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: true)
        )
      else:
        themeNames.add(
          ThemeName(name: name, userTheme: userTheme, override: false)
        )

  addThemeNames(a.paths.themesDir, userTheme=false)
  addThemeNames(a.paths.userThemesDir, userTheme=true)

  if themeNames.len == 0:
    raise newException(IOError, "Cannot find any themes, exiting")

  themeNames.sort(
    proc (a, b: ThemeName): int =
      cmpNaturalIgnoreCase(a.name.toRunes, b.name.toRunes)
  )

  a.theme.themeNames = themeNames

# }}}
# {{{ loadTheme()
proc loadTheme*(theme: ThemeName; a) =
  var path = themePath(theme, a)
  log.info(fmt"Loading theme '{theme.name}' from '{path}'")

  # TODO error handling?
  a.theme.config = loadTheme(path)
  a.logfile.flushFile

# }}}
# {{{ saveTheme(a)
proc saveTheme*(a) =
  try:
    with a.theme.themeNames[a.theme.currThemeIndex]:
      userTheme = true
      override = true

    let themePath = themePath(a.currThemeName, a)
    saveTheme(a.theme.config, themePath)
    a.themeEditor.modified = false

    setStatusMessage(IconFloppy,
                     fmt"User theme '{a.currThemeName.name}' saved", a)

  except CatchableError as e:
    let msgPrefix = fmt"Error saving theme '{a.currThemeName.name}'"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a=a)
  finally:
    a.logFile.flushFile

# }}}
# {{{ deleteTheme()
proc deleteTheme*(theme: ThemeName; a): bool =
  if theme.userTheme:
    try:
      var path = themePath(theme, a)
      log.info(fmt"Deleting theme '{theme.name}' at '{path}'")

      removeFile(path)
      result = true

    except CatchableError as e:
      let msgPrefix = "Error deleting theme"
      logError(e, msgPrefix)
      setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
    finally:
      a.logfile.flushFile

# }}}
# {{{ copyTheme()
proc copyTheme*(theme: ThemeName, newThemeName, newThemePath: string; a): bool =
  try:
    copyFileWithPermissions(themePath(a.currThemeName, a), newThemePath)
    result = true

    setStatusMessage(IconFloppy,
                     fmt"User theme '{newThemeName}' created", a)

  except CatchableError as e:
    let msgPrefix = "Error copying theme"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
  finally:
    a.logfile.flushFile

# }}}
# {{{ renameTheme()
proc renameTheme*(theme: ThemeName,
                 newThemeName, newThemePath: string; a): bool =
  try:
    moveFile(themePath(a.currThemeName, a), newThemePath)
    result = true

    setStatusMessage(IconFloppy,
                     fmt"User theme renamed to '{newThemeName}'", a)

  except CatchableError as e:
    let msgPrefix = "Error renaming theme"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
  finally:
    a.logfile.flushFile

# }}}

# {{{ loadThemeImage()
proc loadThemeImage*(imageName: string, userTheme: bool; a): Option[Paint] =
  if userTheme:
    let imgPath = a.paths.userThemeImagesDir / imageName
    result = loadImage(a.vg, imgPath)
    if result.isNone:
      log.info("Cannot load image from user theme images directory: " &
               fmt"'{imgPath}'. Attempting default theme images directory.")

  let imgPath = a.paths.themeImagesDir / imageName
  result = loadImage(a.vg, imgPath)
  if result.isNone:
    log.error(
      "Cannot load image from default theme images directory: '{imgPath}'"
    )

# }}}
# {{{ loadBackgroundImage()
proc loadBackgroundImage*(theme: ThemeName; a) =
  let bgImageName = a.theme.windowTheme.backgroundImage

  if bgImageName != "":
    a.ui.backgroundImage = loadThemeImage(bgImageName, theme.userTheme, a)
    a.ui.drawLevelParams.backgroundImage = a.ui.backgroundImage
  else:
    a.ui.backgroundImage = Paint.none
    a.ui.drawLevelParams.backgroundImage = Paint.none

# }}}
# {{{ updateWidgetStyles()
proc updateWidgetStyles*(a) =
  alias(cfg, a.theme.config)

  # Button
  a.theme.buttonStyle = koi.getDefaultButtonStyle()

  let w = cfg.getObjectOrEmpty("ui.widget")

  var labelStyle = koi.getDefaultLabelStyle()
  with labelStyle:
    color            = w.getColorOrDefault("foreground.normal")
    colorHover       = color
    colorDown        = w.getColorOrDefault("foreground.active")
    colorActive      = colorDown
    colorActiveHover = colorDown
    colorDisabled    = w.getColorOrDefault("foreground.disabled")

  # Button
  with a.theme.buttonStyle:
    cornerRadius      = w.getFloatOrDefault("corner-radius")
    fillColor         = w.getColorOrDefault("background.normal")
    fillColorHover    = w.getColorOrDefault("background.hover")
    fillColorDown     = w.getColorOrDefault("background.active")
    fillColorDisabled = w.getColorOrDefault("background.disabled")

    label       = labelStyle.deepCopy
    label.align = haCenter

  # Radio button
  a.theme.radioButtonStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.radioButtonStyle:
    buttonCornerRadius         = w.getFloatOrDefault("corner-radius")
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label       = labelStyle.deepCopy
    label.align = haCenter

  # Icon radio button
  a.theme.iconRadioButtonsStyle = koi.getDefaultRadioButtonsStyle()

  with a.theme.iconRadioButtonsStyle:
    buttonPadHoriz             = 4.0
    buttonPadVert              = 4.0
    buttonCornerRadius         = 0.0
    buttonFillColor            = w.getColorOrDefault("background.normal")
    buttonFillColorHover       = w.getColorOrDefault("background.hover")
    buttonFillColorDown        = w.getColorOrDefault("background.active")
    buttonFillColorActive      = buttonFillColorDown
    buttonFillColorActiveHover = buttonFillColorDown

    label          = labelStyle.deepCopy
    label.fontSize = 18.0
    label.padHoriz = 0
    label.padHoriz = 0
    label.align    = haCenter

  # Drop down
  a.theme.dropDownStyle = koi.getDefaultDropDownStyle()

  let dd = cfg.getObjectOrEmpty("ui.drop-down")

  with a.theme.dropDownStyle:
    buttonCornerRadius      = w.getFloatOrDefault("corner-radius")
    buttonFillColor         = w.getColorOrDefault("background.normal")
    buttonFillColorHover    = w.getColorOrDefault("background.hover")
    buttonFillColorDown     = buttonFillColor
    buttonFillColorDisabled = w.getColorOrDefault("background.disabled")

    label          = labelStyle.deepCopy
    label.padHoriz = 8.0

    itemListCornerRadius     = buttonCornerRadius
    itemBackgroundColorHover = w.getColorOrDefault("background.active")
    itemListFillColor        = dd.getColorOrDefault("item-list-background")

    item.color        = cfg.getColorOrDefault("ui.dialog.label")
    item.colorHover   = w.getColorOrDefault("foreground.active")

  # Text field
  a.theme.textFieldStyle = koi.getDefaultTextFieldStyle()

  let t = cfg.getObjectOrEmpty("ui.text-field")

  with a.theme.textFieldStyle:
    bgCornerRadius      = w.getFloatOrDefault("corner-radius")
    bgFillColor         = w.getColorOrDefault("background.normal")
    bgFillColorHover    = w.getColorOrDefault("background.hover")
    bgFillColorActive   = t.getColorOrDefault("edit.background")
    bgFillColorDisabled = w.getColorOrDefault("background.disabled")
    textColor           = w.getColorOrDefault("foreground.normal")
    textColorHover      = textColor
    textColorActive     = t.getColorOrDefault("edit.text")
    textColorDisabled   = w.getColorOrDefault("foreground.disabled")
    cursorColor         = t.getColorOrDefault("cursor")
    selectionColor      = t.getColorOrDefault("selection")

  # Text area
  a.theme.textAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.textAreaStyle:
    bgCornerRadius    = w.getFloatOrDefault("corner-radius")
    bgFillColor       = w.getColorOrDefault("background.normal")

    bgFillColorHover  = lerp(bgFillColor,
                             w.getColorOrDefault("background.hover"), 0.5)

    bgFillColorActive = t.getColorOrDefault("edit.background")
    textColor         = w.getColorOrDefault("foreground.normal")
    textColorHover    = textColor
    textColorActive   = t.getColorOrDefault("edit.text")
    cursorColor       = t.getColorOrDefault("cursor")
    selectionColor    = t.getColorOrDefault("selection")

    with scrollBarStyleNormal:
      let c = t.getColorOrDefault("scroll-bar.normal")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

    with scrollBarStyleEdit:
      let c = t.getColorOrDefault("scroll-bar.edit")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Default check box (for the theme editor)
  var cbs = koi.getDefaultCheckBoxStyle()
  with cbs:
    fillColorActive       = black(0.3)
    fillColorDown         = fillColorActive
    fillColorActiveHover  = fillColorActive
    icon.fontSize         = 12.0
    icon.colorHover       = icon.color
    icon.colorActiveHover = icon.colorActive
    iconActive            = IconCheck
    iconInactive          = NoIcon

  koi.setDefaultCheckboxStyle(cbs)

  # Check box
  a.theme.checkBoxStyle = koi.getDefaultCheckBoxStyle()

  with a.theme.checkBoxStyle:
    cornerRadius          = w.getFloatOrDefault("corner-radius")
    fillColor             = w.getColorOrDefault("background.normal")
    fillColorHover        = w.getColorOrDefault("background.hover")
    fillColorDown         = w.getColorOrDefault("background.active")
    fillColorActive       = fillColorDown
    fillColorActiveHover  = fillColorDown
    fillColorDisabled     = w.getColorOrDefault("background.disabled")

    icon.fontSize         = 12.0
    icon.color            = w.getColorOrDefault("foreground.normal")
    icon.colorHover       = icon.color
    icon.colorDown        = w.getColorOrDefault("foreground.active")
    icon.colorActive      = icon.colorDown
    icon.colorActiveHover = icon.colorDown

    iconActive            = IconCheck
    iconInactive          = NoIcon

  # Slider
  a.theme.sliderStyle = koi.getDefaultSliderStyle()

  with a.theme.sliderStyle:
    trackFillColor        = w.getColorOrDefault("background.normal")
    trackFillColorHover   = w.getColorOrDefault("background.hover")
    trackFillColorDown    = trackFillColor

    sliderColor           = w.getColorOrDefault("background.active")
    sliderColorHover      = sliderColor
    sliderColorDown       = sliderColor

    label = labelStyle.deepCopy
    label.align = haCenter

    value = labelStyle.deepCopy
    value.align = haCenter

  # Dialog style
  a.theme.dialogStyle = koi.getDefaultDialogStyle()

  let d = cfg.getObjectOrEmpty("ui.dialog")

  with a.theme.dialogStyle:
    cornerRadius      = d.getFloatOrDefault("corner-radius")
    backgroundColor   = d.getColorOrDefault("background")
    titleBarBgColor   = d.getColorOrDefault("title.background")
    titleBarTextColor = d.getColorOrDefault("title.text")

    outerBorderColor  = d.getColorOrDefault("outer-border.color")
    innerBorderColor  = d.getColorOrDefault("inner-border.color")
    outerBorderWidth  = d.getFloatOrDefault("outer-border.width")
    innerBorderWidth  = d.getFloatOrDefault("inner-border.width")

    with shadow:
      enabled = d.getBoolOrDefault("shadow.enabled")
      xOffset = d.getFloatOrDefault("shadow.x-offset")
      yOffset = d.getFloatOrDefault("shadow.y-offset")
      feather = d.getFloatOrDefault("shadow.feather")
      color   = d.getColorOrDefault("shadow.color")

  a.theme.aboutDialogStyle = a.theme.dialogStyle.deepCopy
  a.theme.aboutDialogStyle.drawTitleBar = false

  # Label
  a.theme.labelStyle = koi.getDefaultLabelStyle()

  with a.theme.labelStyle:
    fontSize      = 14
    color         = d.getColorOrDefault("label")
    colorDisabled = color.lerp(d.getColorOrDefault("background"), 0.7)
    align         = haLeft

  # Warning label
  a.theme.warningLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.warningLabelStyle:
    color     = d.getColorOrDefault("warning")
    multiLine = true

  # Error label
  a.theme.errorLabelStyle = koi.getDefaultLabelStyle()

  with a.theme.errorLabelStyle:
    color     = d.getColorOrDefault("error")
    multiLine = true

  # Level drop down
  let ld = cfg.getObjectOrEmpty("level.level-drop-down")

  a.theme.levelDropDownStyle = koi.getDefaultDropDownStyle()

  with a.theme.levelDropDownStyle:
    buttonCornerRadius       = ld.getFloatOrDefault("corner-radius")
    buttonFillColor          = ld.getColorOrDefault("button.normal")
    buttonFillColorHover     = ld.getColorOrDefault("button.hover")
    buttonFillColorDown      = buttonFillColor
    buttonFillColorDisabled  = buttonFillColor

    label.fontSize           = 15.0
    label.color              = ld.getColorOrDefault("button.label")
    label.colorHover         = label.color
    label.colorDown          = label.color
    label.colorActive        = label.color
    label.colorDisabled      = label.color
    label.align              = haCenter

    item.align               = haLeft
    item.color               = ld.getColorOrDefault("item.normal")
    item.colorHover          = ld.getColorOrDefault("item.hover")

    itemListCornerRadius     = buttonCornerRadius
    itemListPadHoriz         = 10.0
    itemListFillColor        = ld.getColorOrDefault("item-list-background")
    itemBackgroundColorHover = w.getColorOrDefault("background.active")

    var ss = koi.getDefaultShadowStyle()
    ss.color = ld.getColorOrDefault("shadow.color")
    ss.cornerRadius = buttonCornerRadius * 1.6
    shadow = ss

  # About button
  let ab = cfg.getObjectOrEmpty("ui.about-button")

  a.theme.aboutButtonStyle = koi.getDefaultButtonStyle()

  with a.theme.aboutButtonStyle:
    strokeWidth       = 0
    fillColor         = black().withAlpha(0)
    fillColorHover    = black().withAlpha(0)
    fillColorDown     = black().withAlpha(0)
    fillColorDisabled = black().withAlpha(0)
    label.fontSize    = 20.0
    label.padHoriz    = 0
    label.color       = ab.getColorOrDefault("label.normal")
    label.colorHover  = ab.getColorOrDefault("label.hover")
    label.colorDown   = ab.getColorOrDefault("label.down")

  # Current note pane
  let pn = cfg.getObjectOrEmpty("pane.current-note")

  a.theme.noteTextAreaStyle = koi.getDefaultTextAreaStyle()

  with a.theme.noteTextAreaStyle:
    bgFillColor         = black(0)
    bgFillColorHover    = black(0)
    bgFillColorActive   = black(0)
    bgFillColorDisabled = black(0)

    textPadHoriz        = 0.0
    textPadVert         = 0.0
    textFontSize        = 15.0
    textFontFace        = "sans-bold"
    textLineHeight      = 1.4
    textColorDisabled   = pn.getColorOrDefault("text")

    with scrollBarStyleNormal:
      let c = pn.getColorOrDefault("scroll-bar")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  # Notes list pane
  let nlp = cfg.getObjectOrEmpty("pane.notes-list")

  a.theme.notesListScrollViewStyle = koi.getDefaultScrollViewStyle()

  with a.theme.notesListScrollViewStyle:
    with scrollBarStyle:
      let c = nlp.getColorOrDefault("scroll-bar")
      thumbFillColor      = c.withAlpha(0.4)
      thumbFillColorHover = c.withAlpha(0.5)
      thumbFillColorDown  = c.withAlpha(0.6)

  a.theme.notesListLevelSectionStyle = koi.getDefaultSectionHeaderStyle()

  with a.theme.notesListLevelSectionStyle:
    backgroundColor = nlp.getColorOrDefault("level-section.background")
    label.color     = nlp.getColorOrDefault("level-section.text")
    triangleColor   = nlp.getColorOrDefault("level-section.text")
    separatorColor  = nlp.getColorOrDefault("section-separator")

  a.theme.notesListRegionSectionStyle = koi.getDefaultSubSectionHeaderStyle()

  with a.theme.notesListRegionSectionStyle:
    backgroundColor = nlp.getColorOrDefault("region-section.background")
    label.color     = nlp.getColorOrDefault("region-section.text")
    triangleColor   = nlp.getColorOrDefault("region-section.text")
    separatorColor  = nlp.getColorOrDefault("section-separator")

# }}}
# {{{ updateTheme()
proc updateTheme*(a) =
  alias(cfg, a.theme.config)

  updateWidgetStyles(a)

  a.theme.statusBarTheme = cfg.getObjectOrEmpty("ui.status-bar")
                              .toStatusBarTheme

  a.theme.toolbarPaneTheme = cfg.getObjectOrEmpty("pane.toolbar")
                                .toToolbarPaneTheme

  a.theme.currentNotePaneTheme = cfg.getObjectOrEmpty("pane.current-note")
                                    .toCurrentNotePaneTheme

  a.theme.notesListPaneTheme = cfg.getObjectOrEmpty("pane.notes-list")
                                  .toNotesListPaneTheme

  a.theme.levelTheme = cfg.getObjectOrEmpty("level").toLevelTheme

  a.theme.windowTheme = cfg.getObjectOrEmpty("ui.window").toWindowTheme
  a.win.theme = a.theme.windowTheme

  a.ui.drawLevelParams.initDrawLevelParams(
    a.theme.levelTheme, a.vg,
    scaleFactor = getFinalUIScaleFactor(a),
    pxRatio = koi.getPxRatio()
  )

# }}}
# {{{ switchTheme()
proc switchTheme*(themeIndex: Natural; a) =
  let theme = a.theme.themeNames[themeIndex]
  loadTheme(theme, a)

  updateTheme(a)
  loadBackgroundImage(theme, a)

  a.theme.currThemeIndex = themeIndex

  a.themeEditor.modified = false
  a.theme.prevConfig = a.theme.config.deepCopy

# }}}


# vim: et:ts=2:sw=2:fdm=marker
