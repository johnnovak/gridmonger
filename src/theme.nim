import options
import parsecfg
import re

import nanovg

import drawmap


type ThemeReadError* = object of Exception

proc raiseThemeReadError(s: string) =
  raise newException(ThemeReadError, s)

const MapSection = "map"

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

DefaultMapStyle.noteTextColor          = gray(0.85)
DefaultMapStyle.noteCommentMarkerColor = rgba(1.0, 0.2, 0.0, 0.8)
# }}}

# {{{ parseColor()
#proc parseColor(): Option[Color] =

# }}}
# {{{ getColor()
template getColor(cfg: Config, section, key: string,
                  ms: var MapStyle, default: MapStyle) =
  let v = cfg.getSectionValue(section, key)

# }}}
# {{{ getBool()
#proc getBool(cfg: Config, section, key: string, var color: Color) =

# }}}
# {{{ getFloat()
#proc getFloat(cfg: Config, section, key: string, var color: Color) =

# }}}
# {{{ getGridStyle()
#proc getGridStyle(cfg: Config, section, key: string, var color: Color) =

# }}}
# {{{ getOutlineStyle()
#proc getOutlineStyle(cfg: Config, section, key: string, var color: Color) =

# }}}
# {{{ getOutlineFillStyle()
#proc getOutlineFillStyle(cfg: Config, section, key: string, var color: Color) =

# }}}

# {{{ parseMapSection()
proc parseMapSection(c: Config): MapStyle =
  var ms = new MapStyle
  const M = MapSection
  let D = DefaultMapStyle

  c.getColor(M, "backgroundColor", ms, D)

#  c.getColor(M, "backgroundColor", ms.backgroundColor, D.backgroundColor)
#  c.getColor(M, "drawColor",       ms.drawColor, D.drawColor)
#  c.getColor(M, "lightDrawColor",  ms.lightDrawColor, D.lightDrawColor)
#  c.getColor(M, "floorColor",      ms.floorColor, D.floorColor)
  #[
  c.getBool (M, "thinLines",       ms.thinLines, D.thinLines)

  c.getColor(M, "bgHatchColor",            ms.bgHatchColor, D.bgHatchColor)
  c.getBool (M, "bgHatchEnabled",          ms.bgHatchEnabled, D.bgHatchEnabled)
  c.getFloat(M, "bgHatchStrokeWidth",      ms.bgHatchStrokeWidth, D.bgHatchStrokeWidth)
  c.getFloat(M, "bgHatchSpacingFactor",    ms.bgHatchSpacingFactor, D.bgHatchSpacingFactor)

  c.getColor(M, "coordsColor",             ms.coordsColor, D.coordsColor)
  c.getColor(M, "coordsHighlightColor",    ms.coordsHighlightColor, D.coordsHighlightColor)

  c.getColor(M, "cursorColor",             ms.cursorColor, D.cursorColor)
  c.getColor(M, "cursorGuideColor",        ms.cursorGuideColor, D.cursorGuideColor)

  c.getGridStyle(M, "gridStyle",           ms.gridStyle, D.gridStyle)
  c.getColor    (M, "gridColorBackground", ms.gridColorBackground, D.gridColorBackground)
  c.getColor    (M, "gridColorFloor",      ms.gridColorFloor, D.gridColorFloor)

  c.getOutlineStyle    (M, "outlineStyle",       ms.outlineStyle, D.outlineStyle)
  c.getOutlineFillStyle(M, "outlineFillStyle",   ms.outlineFillStyle, D.outlineFillStyle)
  c.getBool            (M, "outlineOverscan",    ms.outlineOverscan, D.outlineOverscan)
  c.getColor           (M, "outlineColor",       ms.outlineColor, D.outlineColor)
  c.getFloat           (M, "outlineWidthFactor", ms.outlineWidthFactor, D.outlineWidthFactor)

  c.getBool (M, "innerShadowEnabled",      ms.innerShadowEnabled, D.innerShadowEnabled)
  c.getColor(M, "innerShadowColor",        ms.innerShadowColor, D.innerShadowColor)
  c.getFloat(M, "innerShadowWidthFactor",  ms.innerShadowWidthFactor, D.innerShadowWidthFactor)
  c.getBool (M, "outerShadowEnabled",      ms.outerShadowEnabled, D.outerShadowEnabled)
  c.getColor(M, "outerShadowColor",        ms.outerShadowColor, D.outerShadowColor)
  c.getFloat(M, "outerShadowWidthFactor",  ms.outerShadowWidthFactor, D.outerShadowWidthFactor)

  c.getColor(M, "pastePreviewColor",       ms.pastePreviewColor, D.pastePreviewColor)
  c.getColor(M, "selectionColor",          ms.selectionColor, D.selectionColor)

  c.getColor(M, "noteTextColor",           ms.noteTextColor, D.noteTextColor)
  c.getColor(M, "noteCommentMarkerColor",  ms.noteCommentMarkerColor, D.noteCommentMarkerColor)
]#
# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): MapStyle =
  var cfg = loadConfig("config.ini")
  var mapStyle = parseMapSection(cfg)
  result = mapStyle

# }}}

# vim: et:ts=2:sw=2:fdm=marker
