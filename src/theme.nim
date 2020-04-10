import common
import options
import parsecfg
import strformat
import strscans
import strutils

import nanovg

import csdwindow
import drawmap
import utils


type ThemeParseError* = object of Exception

# TODO remove?
#proc raiseThemeParseError(s: string) =
#  raise newException(ThemeParseError, s)

const UISection = "ui"
const UIWindowSection      = fmt"{UISection}.window"
const UIMapDropdownSection = fmt"{UISection}.mapDropdown"

const MapSection = "map"

# {{{ MapDropdownStyle
type
  MapDropdownStyle* = ref object
    buttonColor*:       Color
    buttonColorHover*:  Color
    labelColor*:        Color
    itemListColor*:     Color
    itemColor*:         Color
    itemColorHover*:    Color
    itemBgColorHover*:  Color

var DefaultMapDropdownStyle = new MapDropdownStyle

DefaultMapDropdownStyle.buttonColor      = gray(0.4)
DefaultMapDropdownStyle.buttonColorHover = gray(0.4)
DefaultMapDropdownStyle.labelColor       = gray(0.4)
DefaultMapDropdownStyle.itemListColor    = gray(0.4)
DefaultMapDropdownStyle.itemColor        = gray(0.4)
DefaultMapDropdownStyle.itemColorHover   = gray(0.4)
DefaultMapDropdownStyle.itemBgColorHover = gray(0.4)

# }}}
# {{{ UIStyle
type
  UIStyle* = ref object
    backgroundColor*:     Color
    backgroundImage*:     string
    windowStyle*:         CSDWindowStyle
    mapDropdownStyle*:    MapDropdownStyle

var DefaultUIStyle = new UIStyle

DefaultUIStyle.backgroundColor  = gray(0.4)
DefaultUIStyle.backgroundImage  = ""
DefaultUIStyle.windowStyle      = getDefaultCSDWindowStyle()
DefaultUIStyle.mapDropdownStyle = DefaultMapDropdownStyle

# }}}

# {{{ DefaultMapStyle
var DefaultMapStyle = new MapStyle

DefaultMapStyle.backgroundColor = gray(0.4)
DefaultMapStyle.drawColor       = gray(0.1)
DefaultMapStyle.lightDrawColor  = gray(0.6)
DefaultMapStyle.floorColor      = gray(0.9)
DefaultMapStyle.thinLines       = false

DefaultMapStyle.bgHatchEnabled       = true
DefaultMapStyle.bgHatchColor         = gray(0.0, 0.4)
DefaultMapStyle.bgHatchStrokeWidth   = 1.0
DefaultMapStyle.bgHatchSpacingFactor = 2.0

DefaultMapStyle.coordsColor          = gray(0.9)
DefaultMapStyle.coordsHighlightColor = rgb(1.0, 0.75, 0.0)

DefaultMapStyle.cursorColor          = rgb(1.0, 0.65, 0.0)
DefaultMapStyle.cursorGuideColor     = rgba(1.0, 0.65, 0.0, 0.2)

DefaultMapStyle.gridStyle            = gsSolid
DefaultMapStyle.gridColorBackground  = gray(0.0, 0.2)
DefaultMapStyle.gridColorFloor       = gray(0.0, 0.22)

DefaultMapStyle.outlineStyle         = osCell
DefaultMapStyle.outlineFillStyle     = ofsSolid
DefaultMapStyle.outlineOverscan      = false
DefaultMapStyle.outlineColor         = gray(0.25)
DefaultMapStyle.outlineWidthFactor   = 0.5

DefaultMapStyle.innerShadowEnabled     = false
DefaultMapStyle.innerShadowColor       = gray(0.0, 0.1)
DefaultMapStyle.innerShadowWidthFactor = 0.125
DefaultMapStyle.outerShadowEnabled     = false
DefaultMapStyle.outerShadowColor       = gray(0.0, 0.1)
DefaultMapStyle.outerShadowWidthFactor = 0.125

DefaultMapStyle.selectionColor         = rgba(1.0, 0.5, 0.5, 0.4)
DefaultMapStyle.pastePreviewColor      = rgba(0.2, 0.6, 1.0, 0.4)

DefaultMapStyle.noteMapTextColor       = gray(0.85)
DefaultMapStyle.noteMapCommentColor    = rgba(1.0, 0.2, 0.0, 0.8)
DefaultMapStyle.noteMapIndexColor      = gray(0.85)
DefaultMapStyle.noteMapIndexBgColor    = [gray(0.0, 0.2),
                                          gray(0.0, 0.2),
                                          gray(0.0, 0.2),
                                          gray(0.0, 0.2)]

DefaultMapStyle.notePaneTextColor      = gray(0.1)
DefaultMapStyle.notePaneIndexColor     = gray(0.1)
DefaultMapStyle.notePaneIndexBgColor   = [gray(1.0, 0.2),
                                          gray(1.0, 0.2),
                                          gray(1.0, 0.2),
                                          gray(1.0, 0.2)]

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
    let M = UISection

    c.getColor( M, "backgroundColor", s.backgroundColor)
    c.getString(M, "backgroundImage", s.backgroundImage)

  block:
    alias(s, result.windowStyle)
    let M = UIWindowSection

    c.getColor(M, "backgroundColor",   s.backgroundColor)
    c.getColor(M, "buttonColor",       s.buttonColor)
    c.getColor(M, "buttonColorHover",  s.buttonColorHover)
    c.getColor(M, "buttonColorDown",   s.buttonColorDown)
    c.getColor(M, "textColor",         s.textColor)
    c.getColor(M, "modifiedFlagColor", s.modifiedFlagColor)

  block:
    alias(s, result.mapDropdownStyle)
    let M = UIMapDropdownSection

    c.getColor(M, "buttonColor",      s.buttonColor)
    c.getColor(M, "buttonColorHover", s.buttonColorHover)
    c.getColor(M, "labelColor",       s.labelColor)
    c.getColor(M, "itemListColor",    s.itemListColor)
    c.getColor(M, "itemColor",        s.itemColor)
    c.getColor(M, "itemColorHover",   s.itemColorHover)
    c.getColor(M, "itemBgColorHover", s.itemBgColorHover)

# }}}
# {{{ parseMapSection()
proc parseMapSection(c: Config): MapStyle =
  var s = DefaultMapStyle.deepCopy()
  let M = MapSection

  c.getColor(M, "backgroundColor",          s.backgroundColor)
  c.getColor(M, "drawColor",                s.drawColor)
  c.getColor(M, "lightDrawColor",           s.lightDrawColor)
  c.getColor(M, "floorColor",               s.floorColor)
  c.getBool( M, "thinLines",                s.thinLines)

  c.getBool( M, "bgHatch",                  s.bgHatchEnabled)
  c.getColor(M, "bgHatchColor",             s.bgHatchColor)
  c.getFloat(M, "bgHatchStrokeWidth",       s.bgHatchStrokeWidth)
  c.getFloat(M, "bgHatchSpacingFactor",     s.bgHatchSpacingFactor)

  c.getColor(M, "coordsColor",              s.coordsColor)
  c.getColor(M, "coordsHighlightColor",     s.coordsHighlightColor)

  c.getColor(M, "cursorColor",              s.cursorColor)
  c.getColor(M, "cursorGuideColor",         s.cursorGuideColor)

  getEnum[GridStyle](c, M, "gridStyle",     s.gridStyle)
  c.getColor(M, "gridColorBackground",      s.gridColorBackground)
  c.getColor(M, "gridColorFloor",           s.gridColorFloor)

  getEnum[OutlineStyle](c, M, "outlineStyle", s.outlineStyle)
  getEnum[OutlineFillStyle](c, M, "outlineFillStyle", s.outlineFillStyle)
  c.getBool( M, "outlineOverscan",          s.outlineOverscan)
  c.getColor(M, "outlineColor",             s.outlineColor)
  c.getFloat(M, "outlineWidthFactor",       s.outlineWidthFactor)

  c.getBool( M, "innerShadow",              s.innerShadowEnabled)
  c.getColor(M, "innerShadowColor",         s.innerShadowColor)
  c.getFloat(M, "innerShadowWidthFactor",   s.innerShadowWidthFactor)
  c.getBool( M, "outerShadow",              s.outerShadowEnabled)
  c.getColor(M, "outerShadowColor",         s.outerShadowColor)
  c.getFloat(M, "outerShadowWidthFactor",   s.outerShadowWidthFactor)

  c.getColor(M, "pastePreviewColor",        s.pastePreviewColor)
  c.getColor(M, "selectionColor",           s.selectionColor)

  c.getColor(M, "noteMapTextColor",         s.noteMapTextColor)
  c.getColor(M, "noteMapCommentColor",      s.noteMapCommentColor)
  c.getColor(M, "noteMapIndexColor",        s.noteMapIndexColor)
  c.getColor(M, "noteMapIndexBgColor1",     s.noteMapIndexBgColor[0])
  c.getColor(M, "noteMapIndexBgColor2",     s.noteMapIndexBgColor[1])
  c.getColor(M, "noteMapIndexBgColor3",     s.noteMapIndexBgColor[2])
  c.getColor(M, "noteMapIndexBgColor4",     s.noteMapIndexBgColor[3])

  c.getColor(M, "notePaneTextColor",        s.notePaneTextColor)
  c.getColor(M, "notePaneIndexColor",       s.notePaneIndexColor)
  c.getColor(M, "notePaneIndexBgColor1",    s.notePaneIndexBgColor[0])
  c.getColor(M, "notePaneIndexBgColor2",    s.notePaneIndexBgColor[1])
  c.getColor(M, "notePaneIndexBgColor3",    s.notePaneIndexBgColor[2])
  c.getColor(M, "notePaneIndexBgColor4",    s.notePaneIndexBgColor[3])

  result = s

# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): (UIStyle, MapStyle) =
  echo fmt"Loading theme '{filename}'..."
  var cfg = loadConfig(filename)

  var uiStyle = parseUISection(cfg)
  var mapStyle = parseMapSection(cfg)

  result = (uiStyle, mapStyle)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
