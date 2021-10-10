import streams
import strformat

import nanovg

import cfghelper
import common
import fieldlimits
import hocon
import strutils
import utils

# {{{ Limits
const
  DialogCornerRadiusLimits* = floatLimits(min=   0.0, max=20.0)
  DialogBorderWidthLimits*  = floatLimits(min=   0.0, max=30.0)
  ShadowOffsetLimits*       = floatLimits(min= -10.0, max=10.0)
  ShadowFeatherLimits*      = floatLimits(min=   0.0, max=50.0)

  WidgetCornerRadiusLimits* = floatLimits(min=0.0, max=12.0)

  BackgroundHatchWidthLimits*         = floatLimits(min=0.5, max=10.0)
  BackgroundHatchSpacingFactorLimits* = floatLimits(min=1.0, max=10.0)

  OutlineWidthFactorLimits* = floatLimits(min=0.0, max=1.0)
  ShadowWidthFactorLimits*  = floatLimits(min=0.0, max=1.0)

  AlphaLimits* = floatLimits(min=0.0, max=1.0)
# }}}

# {{{ Helpers
proc limit(config: HoconNode, key: string, limits: FieldLimits) =
  var v = config.get(key)
  v.num = v.num.limit(limits)

proc getColorArray(cfg: HoconNode, key: string, colors: var openArray[Color]) =
  for i in 0..colors.high:
    colors[i] = cfg.getColor(fmt"{key}.{i}")
# }}}

# {{{ toLevelStyle*()
proc toLevelStyle*(cfg: HoconNode): LevelStyle =
  alias(s, result)
  s = new LevelStyle

  var p = "general."
  s.lineWidth                 = cfg.getEnum(p & "line-width", LineWidth)
  s.backgroundColor           = cfg.getColor(p & "background")
  s.cursorColor               = cfg.getColor(p & "cursor")
  s.cursorGuidesColor         = cfg.getColor(p & "cursor-guides")
  s.linkMarkerColor           = cfg.getColor(p & "link-marker")
  s.selectionColor            = cfg.getColor(p & "selection")
  s.trailColor                = cfg.getColor(p & "trail")
  s.pastePreviewColor         = cfg.getColor(p & "paste-preview")
  s.foregroundNormalColor     = cfg.getColor(p & "foreground.normal")
  s.foregroundLightColor      = cfg.getColor(p & "foreground.light")
  s.coordinatesNormalColor    = cfg.getColor(p & "coordinates.normal")
  s.coordinatesHighlightColor = cfg.getColor(p & "coordinates.highlight")
  s.regionBorderNormalColor   = cfg.getColor(p & "region-border.normal")
  s.regionBorderEmptyColor    = cfg.getColor(p & "region-border.empty")

  p = "background-hatch."
  s.backgroundHatchEnabled       = cfg.getBool(p & "enabled")
  s.backgroundHatchColor         = cfg.getColor(p & "color")
  s.backgroundHatchWidth         = cfg.getFloat(p & "width")
  s.backgroundHatchSpacingFactor = cfg.getFloat(p & "spacing-factor")

  p = "grid."
  s.gridBackgroundStyle     = cfg.getEnum(p & "background.style", GridStyle)
  s.gridBackgroundGridColor = cfg.getColor(p & "background.grid")
  s.gridFloorStyle          = cfg.getEnum(p & "floor.style", GridStyle)
  s.gridFloorGridColor      = cfg.getColor(p & "floor.grid")

  p = "outline."
  s.outlineStyle       = cfg.getEnum(p & "style", OutlineStyle)
  s.outlineFillStyle   = cfg.getEnum(p & "fill-style", OutlineFillStyle)
  s.outlineColor       = cfg.getColor(p & "color")
  s.outlineWidthFactor = cfg.getFloat(p & "width-factor")
  s.outlineOverscan    = cfg.getBool(p & "overscan")

  p = "shadow."
  s.shadowInnerColor        = cfg.getColor(p & "inner.color")
  s.shadowInnerWidthFactor  = cfg.getFloat(p & "inner.width-factor")
  s.shadowOuterColor        = cfg.getColor(p & "outer.color")
  s.shadowOuterWidthFactor  = cfg.getFloat(p & "outer.width-factor")

  p = "floor."
  s.floorTransparent = cfg.getBool(p & "transparent")

  cfg.getColorArray(p & "background", s.floorBackgroundColor)

  p = "note."
  s.noteMarkerColor     = cfg.getColor(p & "marker")
  s.noteCommentColor    = cfg.getColor(p & "comment")
  s.noteBackgroundShape = cfg.getEnum(p & "background-shape", NoteBackgroundShape)

  cfg.getColorArray(p & "index-background", s.noteIndexBackgroundColor)

  s.noteIndexColor             = cfg.getColor(p & "index")
  s.noteTooltipBackgroundColor = cfg.getColor(p & "tooltip.background")
  s.noteTooltipTextColor       = cfg.getColor(p & "tooltip.text")

  cfg.getColorArray("label.text", s.labelTextColor)

# }}}
# {{{ toWindowStyle*()
proc toWindowStyle*(cfg: HoconNode): WindowStyle =
  alias(s, result)
  s = new WindowStyle

  s.modifiedFlagColor            = cfg.getColor("modified-flag")
  s.backgroundColor              = cfg.getColor("background.color")
  s.backgroundImage              = cfg.getString("background.image")
  s.titleBackgroundColor         = cfg.getColor("title.background.normal")
  s.titleBackgroundInactiveColor = cfg.getColor("title.background.inactive")
  s.titleColor                   = cfg.getColor("title.text.normal")
  s.titleInactiveColor           = cfg.getColor("title.text.inactive")
  s.buttonColor                  = cfg.getColor("button.normal")
  s.buttonHoverColor             = cfg.getColor("button.hover")
  s.buttonDownColor              = cfg.getColor("button.down")

# }}}
# {{{ toStatusBarStyle*()
proc toStatusBarStyle*(cfg: HoconNode): StatusBarStyle =
  alias(s, result)
  s = new StatusBarStyle

  s.backgroundColor        = cfg.getColor("background")
  s.textColor              = cfg.getColor("text")
  s.coordinatesColor       = cfg.getColor("coordinates")
  s.commandBackgroundColor = cfg.getColor("command.background")
  s.commandTextColor       = cfg.getColor("command.text")

# }}}
# {{{ toNotesPaneStyle*()
proc toNotesPaneStyle*(cfg: HoconNode): NotesPaneStyle =
  alias(s, result)
  s = new NotesPaneStyle

  s.textColor      = cfg.getColor("text")
  s.scrollBarColor = cfg.getColor("scroll-bar")
  s.indexColor     = cfg.getColor("index")

  cfg.getColorArray("index-background", s.indexBackgroundColor)

# }}}
# {{{ toToolbarPaneStyle*()
proc toToolbarPaneStyle*(cfg: HoconNode): ToolbarPaneStyle =
  alias(s, result)
  s = new ToolbarPaneStyle

  s.buttonNormalColor = cfg.getColor("button.normal")
  s.buttonHoverColor  = cfg.getColor("button.hover")
# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): HoconNode =
  var p = initHoconParser(newFileStream(filename))
  let cfg = p.parse()

  cfg.limit("ui.dialog.corner-radius",      DialogCornerRadiusLimits)
  cfg.limit("ui.dialog.outer-border.width", DialogBorderWidthLimits)
  cfg.limit("ui.dialog.inner-border.width", DialogBorderWidthLimits)
  cfg.limit("ui.dialog.shadow.feather",     ShadowFeatherLimits)
  cfg.limit("ui.dialog.shadow.x-offset",    ShadowOffsetLimits)
  cfg.limit("ui.dialog.shadow.y-offset",    ShadowOffsetLimits)

  cfg.limit("ui.widget.corner-radius",      WidgetCornerRadiusLimits)

  cfg.limit("ui.splash-image.shadow-alpha", AlphaLimits)

  cfg.limit("level.background-hatch.width",          BackgroundHatchWidthLimits)
  cfg.limit("level.background-hatch.spacing-factor", BackgroundHatchSpacingFactorLimits)

  cfg.limit("level.outline.width-factor",   OutlineWidthFactorLimits)

  cfg.limit("level.shadow.inner.width-factor", ShadowWidthFactorLimits)
  cfg.limit("level.shadow.outer.width-factor", ShadowWidthFactorLimits)

  result = cfg

# }}}
# {{{ saveTheme*()
proc saveTheme*(config: HoconNode, filename: string) =
  var s: FileStream
  try:
    s = newFileStream(filename, fmWrite)
    config.write(s)
  finally:
    if s != nil: s.close()

# }}}
#
# vim: et:ts=2:sw=2:fdm=marker
