import common
import options
import parsecfg
import strformat
import strscans
import strutils

import nanovg

import csdwindow
import utils


type ThemeParseError* = object of ValueError

# TODO remove?
#proc raiseThemeParseError(s: string) =
#  raise newException(ThemeParseError, s)

const
  UISection = "ui"
  UIButtonSection        = fmt"{UISection}.button"
  UITextFieldSection     = fmt"{UISection}.textField"
  UIDialogSection        = fmt"{UISection}.dialog"
  UITitleBarSection      = fmt"{UISection}.titleBar"
  UIStatusBarSection     = fmt"{UISection}.statusBar"
  UILevelDropdownSection = fmt"{UISection}.levelDropdown"

  LevelSection = "level"

# {{{ UIButtonStyle
type
  UIButtonStyle* = ref object
    bgColor*:           Color
    bgColorHover*:      Color
    bgColorDown*:       Color
    bgColorActive*:     Color
    labelColor*:        Color

var DefaultUIButtonStyle = new UIButtonStyle

DefaultUIButtonStyle.bgColor       = gray(0.4)
DefaultUIButtonStyle.bgColorHover  = gray(0.4)
DefaultUIButtonStyle.bgColorDown   = gray(0.4)
DefaultUIButtonStyle.bgColorActive = gray(0.4)
DefaultUIButtonStyle.labelColor    = gray(0.4)

# }}}
# {{{ UITextFieldStyle
type
  UITextFieldStyle* = ref object
    bgColor*:           Color
    bgColorHover*:      Color
    bgColorActive*:     Color
    textColor*:         Color
    textColorActive*:   Color
    cursorColor*:       Color
    selectionColor*:    Color

var DefaultUITextFieldStyle = new UITextFieldStyle

DefaultUITextFieldStyle.bgColor         = gray(0.4)
DefaultUITextFieldStyle.bgColorHover    = gray(0.4)
DefaultUITextFieldStyle.bgColorActive   = gray(0.4)
DefaultUITextFieldStyle.textColor       = gray(0.4)
DefaultUITextFieldStyle.textColorActive = gray(0.4)
DefaultUITextFieldStyle.cursorColor     = gray(0.4)
DefaultUITextFieldStyle.selectionColor  = gray(0.4)


# }}}
# {{{ UIDialogStyle
type
  UIDialogStyle* = ref object
    labelColor*:        Color
    backgroundColor*:   Color
    titleBarBgColor*:   Color
    titleBarTextColor*: Color

var DefaultUIDialogStyle = new UIDialogStyle

DefaultUIDialogStyle.labelColor        = gray(0.4)
DefaultUIDialogStyle.backgroundColor   = gray(0.4)
DefaultUIDialogStyle.titleBarBgColor   = gray(0.4)
DefaultUIDialogStyle.titleBarTextColor = gray(0.4)

# }}}
# {{{ LevelDropdownStyle
type
  LevelDropdownStyle* = ref object
    buttonColor*:       Color
    buttonColorHover*:  Color
    labelColor*:        Color
    itemListColor*:     Color
    itemColor*:         Color
    itemColorHover*:    Color
    itemBgColorHover*:  Color

var DefaultLevelDropdownStyle = new LevelDropdownStyle

DefaultLevelDropdownStyle.buttonColor      = gray(0.4)
DefaultLevelDropdownStyle.buttonColorHover = gray(0.4)
DefaultLevelDropdownStyle.labelColor       = gray(0.4)
DefaultLevelDropdownStyle.itemListColor    = gray(0.4)
DefaultLevelDropdownStyle.itemColor        = gray(0.4)
DefaultLevelDropdownStyle.itemColorHover   = gray(0.4)
DefaultLevelDropdownStyle.itemBgColorHover = gray(0.4)

# }}}
# {{{ StatusBarStyle
type
  StatusBarStyle* = ref object
    backgroundColor*:  Color
    coordsColor*:      Color
    textColor*:        Color
    commandBgColor*:   Color
    commandColor*:     Color

var DefaultStatusBarStyle = new StatusBarStyle

DefaultStatusBarStyle.backgroundColor  = gray(0.2)
DefaultStatusBarStyle.coordsColor      = gray(0.6)
DefaultStatusBarStyle.textColor        = gray(0.8)
DefaultStatusBarStyle.commandBgColor   = gray(0.56)
DefaultStatusBarStyle.commandColor     = gray(0.2)

# }}}
# {{{ UIStyle
type
  UIStyle* = ref object
    backgroundColor*:    Color
    backgroundImage*:    string
    buttonStyle*:        UIButtonStyle
    textFieldStyle*:     UITextFieldStyle
    dialogStyle*:        UIDialogStyle
    titleBarStyle*:      CSDWindowStyle
    levelDropdownStyle*: LevelDropdownStyle
    statusBarStyle*:     StatusBarStyle

var DefaultUIStyle = new UIStyle

DefaultUIStyle.backgroundColor    = gray(0.4)
DefaultUIStyle.backgroundImage    = ""
DefaultUIStyle.buttonStyle        = DefaultUIButtonStyle
DefaultUIStyle.textFieldStyle     = DefaultUITextFieldStyle
DefaultUIStyle.dialogStyle        = DefaultUIDialogStyle
DefaultUIStyle.titleBarStyle      = getDefaultCSDWindowStyle()
DefaultUIStyle.levelDropdownStyle = DefaultLevelDropdownStyle
DefaultUIStyle.statusBarStyle     = DefaultStatusBarStyle

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

# {{{ missingValueError()
proc missingValueError(section, key: string) =
  let msg = fmt"Missing value in section='{section}', key='{key}'"
  echo msg
  # TODO
#  raiseThemeParseError(msg)

# }}}
# {{{ invalidValueError
proc invalidValueError(section, key, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value in section='{section}', key='{key}': {value}"
  echo msg
  # TODO
#  raiseThemeParseError(msg)

# }}}
# {{{ getValue()
proc getValue(cfg: Config, section, key: string): string =
  result = cfg.getSectionValue(section, key)
  if result == "":
    missingValueError(section, key)

# }}}
# {{{ parseColor()
proc parseColor(s: string): Option[Color] =
  result = Color.none
  block:
    var r, g, b, a: int
    if scanf(s, "gray($i)$.", g):
      result = gray(g).some
    elif scanf(s, "gray($i,$s$i)$.", g, a):
      result = gray(g, a).some
    elif scanf(s, "rgb($i,$s$i,$s$i)$.", r, g, b):
      result = rgb(r, g, b).some
    elif scanf(s, "rgba($i,$s$i,$s$i,$s$i)$.", r, g, b, a):
      result = rgba(r, g, b, a).some

  if result.isSome: return

  block:
    var r, g, b, a: float
    if scanf(s, "gray($f)$.", g):
      result = gray(g).some
    elif scanf(s, "gray($f,$s$f)$.", g, a):
      result = gray(g, a).some
    elif scanf(s, "rgb($f,$s$f,$s$f)$.", r, g, b):
      result = rgb(r, g, b).some
    elif scanf(s, "rgba($f,$s$f,$s$f,$s$f)$.", r, g, b, a):
      result = rgba(r, g, b, a).some

# }}}

# {{{ getString()
proc getString(cfg: Config, section, key: string, s: var string) =
  s = getValue(cfg, section, key)

# }}}
# {{{ getColor()
proc getColor(cfg: Config, section, key: string, c: var Color) =
  let v = getValue(cfg, section, key)
  let col = parseColor(v)
  if col.isNone:
    invalidValueError(section, key, "color", v)
  else:
    c = col.get

# }}}
# {{{ getBool()
proc getBool(cfg: Config, section, key: string, b: var bool) =
  let v = getValue(cfg, section, key)
  try:
    b = parseBool(v)
  except ValueError:
    invalidValueError(section, key, "bool", v)

# }}}
# {{{ getFloat()
proc getFloat(cfg: Config, section, key: string, f: var float) =
  let v = getValue(cfg, section, key)
  try:
    f = parseFloat(v)
  except ValueError:
    invalidValueError(section, key, "float", v)

# }}}
# {{{ getEnum()
proc getEnum[T: enum](cfg: Config, section, key: string, e: var T) =
  let v = getValue(cfg, section, key)
  try:
    e = parseEnum[T](v)
  except ValueError:
    invalidValueError(section, key, "enum", v)

# }}}

# {{{ parseUISection()
proc parseUISection(c: Config): UIStyle =
  result = DefaultUIStyle.deepCopy()

  block:
    alias(s, result)
    let S = UISection

    c.getColor( S, "backgroundColor", s.backgroundColor)
    c.getString(S, "backgroundImage", s.backgroundImage)

  block:
    alias(s, result.buttonStyle)
    let S = UIButtonSection

    c.getColor(S, "bgColor",       s.bgColor)
    c.getColor(S, "bgColorHover",  s.bgColorHover)
    c.getColor(S, "bgColorDown",   s.bgColorDown)
    c.getColor(S, "bgColorActive", s.bgColorActive)
    c.getColor(S, "labelColor",    s.labelColor)

  block:
    alias(s, result.textFieldStyle)
    let S = UITextFieldSection

    c.getColor(S, "bgColor",         s.bgColor)
    c.getColor(S, "bgColorHover",    s.bgColorHover)
    c.getColor(S, "bgColorActive",   s.bgColorActive)
    c.getColor(S, "textColor",       s.textColor)
    c.getColor(S, "textColorActive", s.textColorActive)
    c.getColor(S, "cursorColor",     s.cursorColor)
    c.getColor(S, "selectionColor",  s.selectionColor)

  block:
    alias(s, result.dialogStyle)
    let S = UIDialogSection

    c.getColor(S, "labelColor",        s.labelColor)
    c.getColor(S, "backgroundColor",   s.backgroundColor)
    c.getColor(S, "titleBarBgColor",   s.titleBarBgColor)
    c.getColor(S, "titleBarTextColor", s.titleBarTextColor)

  block:
    alias(s, result.titleBarStyle)
    let S = UITitleBarSection

    c.getColor(S, "backgroundColor",   s.backgroundColor)
    c.getColor(S, "buttonColor",       s.buttonColor)
    c.getColor(S, "buttonColorHover",  s.buttonColorHover)
    c.getColor(S, "buttonColorDown",   s.buttonColorDown)
    c.getColor(S, "textColor",         s.textColor)
    c.getColor(S, "modifiedFlagColor", s.modifiedFlagColor)

  block:
    alias(s, result.statusBarStyle)
    let S = UIStatusBarSection

    c.getColor(S, "backgroundColor",  s.backgroundColor)
    c.getColor(S, "coordsColor",      s.coordsColor)
    c.getColor(S, "textColor",        s.textColor)
    c.getColor(S, "commandBgColor",   s.commandBgColor)
    c.getColor(S, "commandColor",     s.commandColor)

  block:
    alias(s, result.levelDropdownStyle)
    let S = UILevelDropdownSection

    c.getColor(S, "buttonColor",      s.buttonColor)
    c.getColor(S, "buttonColorHover", s.buttonColorHover)
    c.getColor(S, "labelColor",       s.labelColor)
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
