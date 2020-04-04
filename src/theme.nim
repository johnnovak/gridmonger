import common
import options
import parsecfg
import strformat
import strscans
import strutils

import nanovg

import drawmap


type ThemeParseError* = object of Exception

# TODO remove?
#proc raiseThemeParseError(s: string) =
#  raise newException(ThemeParseError, s)

const UISection = "ui"
const MapSection = "map"

# {{{ UIStyle
var DefaultUIStyle = new UIStyle

DefaultUIStyle.backgroundColor = gray(0.4)
DefaultUIStyle.backgroundImage = ""

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

DefaultMapStyle.noteMapTextColor        = gray(0.85)
DefaultMapStyle.noteMapIndexColor       = gray(0.85)
DefaultMapStyle.noteMapBackgroundColor  = gray(0.0, 0.2)
DefaultMapStyle.notePaneTextColor       = gray(0.1)
DefaultMapStyle.notePaneBackgroundColor = gray(1.0, 0.2)
DefaultMapStyle.noteCommentMarkerColor  = rgba(1.0, 0.2, 0.0, 0.8)

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
#
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
  var ms = DefaultUIStyle.deepCopy()
  const M = UISection

  c.getColor( M, "backgroundColor", ms.backgroundColor)
  c.getString(M, "backgroundImage", ms.backgroundImage)

  result = ms

# }}}
# {{{ parseMapSection()
proc parseMapSection(c: Config): MapStyle =
  var ms = DefaultMapStyle.deepCopy()
  const M = MapSection

  c.getColor(M, "backgroundColor", ms.backgroundColor)
  c.getColor(M, "drawColor",       ms.drawColor)
  c.getColor(M, "lightDrawColor",  ms.lightDrawColor)
  c.getColor(M, "floorColor",      ms.floorColor)
  c.getBool( M, "thinLines",       ms.thinLines)

  c.getColor(M, "bgHatchColor",            ms.bgHatchColor)
  c.getBool( M, "bgHatchEnabled",          ms.bgHatchEnabled)
  c.getFloat(M, "bgHatchStrokeWidth",      ms.bgHatchStrokeWidth)
  c.getFloat(M, "bgHatchSpacingFactor",    ms.bgHatchSpacingFactor)

  c.getColor(M, "coordsColor",             ms.coordsColor)
  c.getColor(M, "coordsHighlightColor",    ms.coordsHighlightColor)

  c.getColor(M, "cursorColor",             ms.cursorColor)
  c.getColor(M, "cursorGuideColor",        ms.cursorGuideColor)

  getEnum[GridStyle](c, M, "gridStyle",    ms.gridStyle)
  c.getColor(M, "gridColorBackground",     ms.gridColorBackground)
  c.getColor(M, "gridColorFloor",          ms.gridColorFloor)

  getEnum[OutlineStyle](c, M, "outlineStyle", ms.outlineStyle)
  getEnum[OutlineFillStyle](c, M, "outlineFillStyle", ms.outlineFillStyle)
  c.getBool(M, "outlineOverscan",          ms.outlineOverscan)
  c.getColor(M, "outlineColor",            ms.outlineColor)
  c.getFloat(M, "outlineWidthFactor",      ms.outlineWidthFactor)

  c.getBool( M, "innerShadowEnabled",      ms.innerShadowEnabled)
  c.getColor(M, "innerShadowColor",        ms.innerShadowColor)
  c.getFloat(M, "innerShadowWidthFactor",  ms.innerShadowWidthFactor)
  c.getBool( M, "outerShadowEnabled",      ms.outerShadowEnabled)
  c.getColor(M, "outerShadowColor",        ms.outerShadowColor)
  c.getFloat(M, "outerShadowWidthFactor",  ms.outerShadowWidthFactor)

  c.getColor(M, "pastePreviewColor",       ms.pastePreviewColor)
  c.getColor(M, "selectionColor",          ms.selectionColor)

  c.getColor(M, "noteMapTextColor",        ms.noteMapTextColor)
  c.getColor(M, "noteMapIndexColor",       ms.noteMapIndexColor)
  c.getColor(M, "noteMapBackgroundColor",  ms.noteMapBackgroundColor)
  c.getColor(M, "noteCommentMarkerColor",  ms.noteCommentMarkerColor)
  c.getColor(M, "notePaneTextColor",       ms.notePaneTextColor)
  c.getColor(M, "notePaneBackgroundColor", ms.notePaneBackgroundColor)
  c.getColor(M, "noteCommentMarkerColor",  ms.noteCommentMarkerColor)

  result = ms

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
