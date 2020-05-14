import options
import parsecfg
import strformat

import nanovg

import cfghelper
import common
import csdwindow
import utils


const
  UISection = "ui"
  LevelSection = "level"

  UIGeneralSection       = fmt"{UISection}.general"
  UIWidgetSection        = fmt"{UISection}.widget"
  UITextFieldSection     = fmt"{UISection}.textField"
  UIDialogSection        = fmt"{UISection}.dialog"
  UITitleBarSection      = fmt"{UISection}.titleBar"
  UIStatusBarSection     = fmt"{UISection}.statusBar"
  UILevelDropdownSection = fmt"{UISection}.levelDropdown"

# {{{ UIGeneralStyle
type
  UIGeneralStyle* = ref object
    backgroundColor*: Color
    backgroundImage*: string
    highlightColor*:  Color

var DefaultUIGeneralStyle = new UIGeneralStyle

DefaultUIGeneralStyle.backgroundColor = gray(0.4)
DefaultUIGeneralStyle.backgroundImage = ""
DefaultUIGeneralStyle.highlightColor  = gray(0.4)

# }}}
# {{{ UIWidgetStyle
type
  UIWidgetStyle* = ref object
    bgColor*:           Color
    bgColorHover*:      Color
    bgColorDisabled*:   Color
    textColor*:         Color
    textColorDisabled*: Color

var DefaultUIWidgetStyle = new UIWidgetStyle

DefaultUIWidgetStyle.bgColor           = gray(0.4)
DefaultUIWidgetStyle.bgColorHover      = gray(0.4)
DefaultUIWidgetStyle.bgColorDisabled   = gray(0.4)
DefaultUIWidgetStyle.textColor         = gray(0.4)
DefaultUIWidgetStyle.textColorDisabled = gray(0.4)

# }}}
# {{{ UITextFieldStyle
type
  UITextFieldStyle* = ref object
    bgColorActive*:     Color
    textColorActive*:   Color
    cursorColor*:       Color
    selectionColor*:    Color

var DefaultUITextFieldStyle = new UITextFieldStyle

DefaultUITextFieldStyle.bgColorActive   = gray(0.4)
DefaultUITextFieldStyle.textColorActive = gray(0.4)
DefaultUITextFieldStyle.cursorColor     = gray(0.4)
DefaultUITextFieldStyle.selectionColor  = gray(0.4)


# }}}
# {{{ UIDialogStyle
type
  UIDialogStyle* = ref object
    titleBarBgColor*:   Color
    titleBarTextColor*: Color
    backgroundColor*:   Color
    textColor*:         Color
    warningTextColor*:  Color

var DefaultUIDialogStyle = new UIDialogStyle

DefaultUIDialogStyle.titleBarBgColor   = gray(0.4)
DefaultUIDialogStyle.titleBarTextColor = gray(0.4)
DefaultUIDialogStyle.backgroundColor   = gray(0.4)
DefaultUIDialogStyle.textColor         = gray(0.4)
DefaultUIDialogStyle.warningTextColor  = gray(0.4)

# }}}
# {{{ UIStatusBarStyle
type
  UIStatusBarStyle* = ref object
    backgroundColor*:    Color
    textColor*:          Color
    commandBgColor*:     Color
    commandColor*:       Color
    coordsColor*:        Color

var DefaultUIStatusBarStyle = new UIStatusBarStyle

DefaultUIStatusBarStyle.backgroundColor = gray(0.2)
DefaultUIStatusBarStyle.textColor       = gray(0.8)
DefaultUIStatusBarStyle.commandBgColor  = gray(0.56)
DefaultUIStatusBarStyle.commandColor    = gray(0.2)
DefaultUIStatusBarStyle.coordsColor     = gray(0.6)

# }}}
# {{{ UILevelDropdownStyle
type
  UILevelDropdownStyle* = ref object
    buttonColor*:       Color
    buttonColorHover*:  Color
    textColor*:         Color
    itemListColor*:     Color
    itemColor*:         Color
    itemColorHover*:    Color
    itemBgColorHover*:  Color

var DefaultUILevelDropdownStyle = new UILevelDropdownStyle

DefaultUILevelDropdownStyle.buttonColor      = gray(0.4)
DefaultUILevelDropdownStyle.buttonColorHover = gray(0.4)
DefaultUILevelDropdownStyle.textColor        = gray(0.4)
DefaultUILevelDropdownStyle.itemListColor    = gray(0.4)
DefaultUILevelDropdownStyle.itemColor        = gray(0.4)
DefaultUILevelDropdownStyle.itemColorHover   = gray(0.4)
DefaultUILevelDropdownStyle.itemBgColorHover = gray(0.4)

# }}}
# {{{ UIStyle
type
  UIStyle* = ref object
    general*:       UIGeneralStyle
    widget*:        UIWidgetStyle
    textField*:     UITextFieldStyle
    dialog*:        UIDialogStyle
    titleBar*:      CSDWindowStyle
    levelDropdown*: UILevelDropdownStyle
    statusBar*:     UIStatusBarStyle

var DefaultUIStyle = new UIStyle

DefaultUIStyle.general       = DefaultUIGeneralStyle
DefaultUIStyle.widget        = DefaultUIWidgetStyle
DefaultUIStyle.textField     = DefaultUITextFieldStyle
DefaultUIStyle.dialog        = DefaultUIDialogStyle
DefaultUIStyle.titleBar      = getDefaultCSDWindowStyle()
DefaultUIStyle.levelDropdown = DefaultUILevelDropdownStyle
DefaultUIStyle.statusBar     = DefaultUIStatusBarStyle

# }}}

# {{{ DefaultLevelStyle
var DefaultLevelStyle = new LevelStyle

DefaultLevelStyle.backgroundColor      = gray(0.4)
DefaultLevelStyle.drawColor            = gray(0.1)
DefaultLevelStyle.lightDrawColor       = gray(0.6)
DefaultLevelStyle.floorColor           = gray(0.9)
DefaultLevelStyle.lineWidth            = lwNormal

DefaultLevelStyle.bgHatchEnabled       = true
DefaultLevelStyle.bgHatchColor         = gray(0.0, 0.4)
DefaultLevelStyle.bgHatchStrokeWidth   = 1.0
DefaultLevelStyle.bgHatchSpacingFactor = 2.0

DefaultLevelStyle.coordsColor          = gray(0.9)
DefaultLevelStyle.coordsHighlightColor = rgb(1.0, 0.75, 0.0)

DefaultLevelStyle.cursorColor          = rgb(1.0, 0.65, 0.0)
DefaultLevelStyle.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

DefaultLevelStyle.gridStyleBackground  = gsSolid
DefaultLevelStyle.gridStyleFloor       = gsSolid
DefaultLevelStyle.gridColorBackground  = gray(0.0, 0.2)
DefaultLevelStyle.gridColorFloor       = gray(0.0, 0.22)

DefaultLevelStyle.outlineStyle         = osCell
DefaultLevelStyle.outlineFillStyle     = ofsSolid
DefaultLevelStyle.outlineOverscan      = false
DefaultLevelStyle.outlineColor         = gray(0.25)
DefaultLevelStyle.outlineWidthFactor   = 0.5

DefaultLevelStyle.innerShadowEnabled     = false
DefaultLevelStyle.innerShadowColor       = gray(0.0, 0.1)
DefaultLevelStyle.innerShadowWidthFactor = 0.125
DefaultLevelStyle.outerShadowEnabled     = false
DefaultLevelStyle.outerShadowColor       = gray(0.0, 0.1)
DefaultLevelStyle.outerShadowWidthFactor = 0.125

DefaultLevelStyle.selectionColor       = rgba(1.0, 0.5, 0.5, 0.4)
DefaultLevelStyle.pastePreviewColor    = rgba(0.2, 0.6, 1.0, 0.4)

DefaultLevelStyle.noteLevelMarkerColor  = gray(0.85)
DefaultLevelStyle.noteLevelCommentColor = rgba(1.0, 0.2, 0.0, 0.8)
DefaultLevelStyle.noteLevelIndexColor   = gray(0.85)
DefaultLevelStyle.noteLevelIndexBgColor = @[gray(0.0, 0.2),
                                            gray(0.0, 0.2),
                                            gray(0.0, 0.2),
                                            gray(0.0, 0.2)]

DefaultLevelStyle.notePaneTextColor    = gray(0.1)
DefaultLevelStyle.notePaneIndexColor   = gray(0.1)
DefaultLevelStyle.notePaneIndexBgColor = @[gray(1.0, 0.2),
                                           gray(1.0, 0.2),
                                           gray(1.0, 0.2),
                                           gray(1.0, 0.2)]

DefaultLevelStyle.linkMarkerColor      = gray(0.85)

# }}}

# {{{ parseUISection()
proc parseUISection(c: Config): UIStyle =
  result = DefaultUIStyle.deepCopy()

  block:
    alias(s, result.general)
    let S = UIGeneralSection

    c.getColor( S, "backgroundColor", s.backgroundColor)
    c.getString(S, "backgroundImage", s.backgroundImage)
    c.getColor( S, "highlightColor",  s.highlightColor)

  block:
    alias(s, result.widget)
    let S = UIWidgetSection

    c.getColor(S, "bgColor",           s.bgColor)
    c.getColor(S, "bgColorHover",      s.bgColorHover)
    c.getColor(S, "bgColorDisabled",   s.bgColorDisabled)
    c.getColor(S, "textColor",         s.textColor)
    c.getColor(S, "textColorDisabled", s.textColorDisabled)

  block:
    alias(s, result.textField)
    let S = UITextFieldSection

    c.getColor(S, "bgColorActive",   s.bgColorActive)
    c.getColor(S, "textColorActive", s.textColorActive)
    c.getColor(S, "cursorColor",     s.cursorColor)
    c.getColor(S, "selectionColor",  s.selectionColor)

  block:
    alias(s, result.dialog)
    let S = UIDialogSection

    c.getColor(S, "titleBarBgColor",   s.titleBarBgColor)
    c.getColor(S, "titleBarTextColor", s.titleBarTextColor)
    c.getColor(S, "backgroundColor",   s.backgroundColor)
    c.getColor(S, "textColor",         s.textColor)
    c.getColor(S, "warningTextColor",  s.warningTextColor)

  block:
    alias(s, result.titleBar)
    let S = UITitleBarSection

    c.getColor(S, "backgroundColor",    s.backgroundColor)
    c.getColor(S, "bgColorUnfocused",   s.bgColorUnfocused)
    c.getColor(S, "textColor",          s.textColor)
    c.getColor(S, "textColorUnfocused", s.textColorUnfocused)
    c.getColor(S, "buttonColor",        s.buttonColor)
    c.getColor(S, "buttonColorHover",   s.buttonColorHover)
    c.getColor(S, "buttonColorDown",    s.buttonColorDown)
    c.getColor(S, "modifiedFlagColor",  s.modifiedFlagColor)

  block:
    alias(s, result.statusBar)
    let S = UIStatusBarSection

    c.getColor(S, "backgroundColor",  s.backgroundColor)
    c.getColor(S, "textColor",        s.textColor)
    c.getColor(S, "commandBgColor",   s.commandBgColor)
    c.getColor(S, "commandColor",     s.commandColor)
    c.getColor(S, "coordsColor",      s.coordsColor)

  block:
    alias(s, result.levelDropdown)
    let S = UILevelDropdownSection

    c.getColor(S, "buttonColor",      s.buttonColor)
    c.getColor(S, "buttonColorHover", s.buttonColorHover)
    c.getColor(S, "textColor",        s.textColor)
    c.getColor(S, "itemListColor",    s.itemListColor)
    c.getColor(S, "itemColor",        s.itemColor)
    c.getColor(S, "itemColorHover",   s.itemColorHover)
    c.getColor(S, "itemBgColorHover", s.itemBgColorHover)

# }}}
# {{{ parseLevelSection()
proc parseLevelSection(c: Config): LevelStyle =
  var s = DefaultLevelStyle.deepCopy()
  let S = LevelSection

  c.getColor(S, "backgroundColor",          s.backgroundColor)
  c.getColor(S, "drawColor",                s.drawColor)
  c.getColor(S, "lightDrawColor",           s.lightDrawColor)
  c.getColor(S, "floorColor",               s.floorColor)
  getEnum[LineWidth](c, S, "lineWidth", s.lineWidth)

  c.getBool( S, "bgHatch",                  s.bgHatchEnabled)
  c.getColor(S, "bgHatchColor",             s.bgHatchColor)
  c.getFloat(S, "bgHatchStrokeWidth",       s.bgHatchStrokeWidth)
  c.getFloat(S, "bgHatchSpacingFactor",     s.bgHatchSpacingFactor)

  c.getColor(S, "coordsColor",              s.coordsColor)
  c.getColor(S, "coordsHighlightColor",     s.coordsHighlightColor)

  c.getColor(S, "cursorColor",              s.cursorColor)
  c.getColor(S, "cursorGuideColor",         s.cursorGuideColor)

  getEnum[GridStyle](c, S, "gridStyleBackground", s.gridStyleBackground)
  getEnum[GridStyle](c, S, "gridStyleFloor", s.gridStyleFloor)
  c.getColor(S, "gridColorBackground",      s.gridColorBackground)
  c.getColor(S, "gridColorFloor",           s.gridColorFloor)

  getEnum[OutlineStyle](c, S, "outlineStyle", s.outlineStyle)
  getEnum[OutlineFillStyle](c, S, "outlineFillStyle", s.outlineFillStyle)
  c.getBool( S, "outlineOverscan",          s.outlineOverscan)
  c.getColor(S, "outlineColor",             s.outlineColor)
  c.getFloat(S, "outlineWidthFactor",       s.outlineWidthFactor)

  c.getBool( S, "innerShadow",              s.innerShadowEnabled)
  c.getColor(S, "innerShadowColor",         s.innerShadowColor)
  c.getFloat(S, "innerShadowWidthFactor",   s.innerShadowWidthFactor)
  c.getBool( S, "outerShadow",              s.outerShadowEnabled)
  c.getColor(S, "outerShadowColor",         s.outerShadowColor)
  c.getFloat(S, "outerShadowWidthFactor",   s.outerShadowWidthFactor)

  c.getColor(S, "pastePreviewColor",        s.pastePreviewColor)
  c.getColor(S, "selectionColor",           s.selectionColor)

  c.getColor(S, "noteLevelMarkerColor",     s.noteLevelMarkerColor)
  c.getColor(S, "noteLevelCommentColor",    s.noteLevelCommentColor)
  c.getColor(S, "noteLevelIndexColor",      s.noteLevelIndexColor)
  c.getColor(S, "noteLevelIndexBgColor1",   s.noteLevelIndexBgColor[0])
  c.getColor(S, "noteLevelIndexBgColor2",   s.noteLevelIndexBgColor[1])
  c.getColor(S, "noteLevelIndexBgColor3",   s.noteLevelIndexBgColor[2])
  c.getColor(S, "noteLevelIndexBgColor4",   s.noteLevelIndexBgColor[3])

  c.getColor(S, "notePaneTextColor",        s.notePaneTextColor)
  c.getColor(S, "notePaneIndexColor",       s.notePaneIndexColor)
  c.getColor(S, "notePaneIndexBgColor1",    s.notePaneIndexBgColor[0])
  c.getColor(S, "notePaneIndexBgColor2",    s.notePaneIndexBgColor[1])
  c.getColor(S, "notePaneIndexBgColor3",    s.notePaneIndexBgColor[2])
  c.getColor(S, "notePaneIndexBgColor4",    s.notePaneIndexBgColor[3])

  c.getColor(S, "linkMarkerColor",          s.linkMarkerColor)

  result = s

# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): (UIStyle, LevelStyle) =
  echo fmt"Loading theme '{filename}'..."
  var cfg = loadConfig(filename)

  var uiStyle = parseUISection(cfg)
  var levelStyle = parseLevelSection(cfg)

  result = (uiStyle, levelStyle)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
