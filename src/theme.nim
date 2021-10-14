import options
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
  var v = config.getOpt(key)
  if v.isSome and v.get.kind == hnkNumber:
    v.get.num = v.get.num.limit(limits)

proc getColorOrDefaultArray(cfg: HoconNode, key: string, colors: var openArray[Color]) =
  for i in 0..colors.high:
    colors[i] = cfg.getColorOrDefault(fmt"{key}.{i}")
# }}}

# {{{ toLevelStyle*()
proc toLevelStyle*(cfg: HoconNode): LevelStyle =
  alias(s, result)
  s = new LevelStyle

  var p = "general."
  s.lineWidth                 = cfg.getEnumOrDefault(p & "line-width", LineWidth)
  s.backgroundColor           = cfg.getColorOrDefault(p & "background")
  s.cursorColor               = cfg.getColorOrDefault(p & "cursor")
  s.cursorGuidesColor         = cfg.getColorOrDefault(p & "cursor-guides")
  s.linkMarkerColor           = cfg.getColorOrDefault(p & "link-marker")
  s.selectionColor            = cfg.getColorOrDefault(p & "selection")
  s.trailColor                = cfg.getColorOrDefault(p & "trail")
  s.pastePreviewColor         = cfg.getColorOrDefault(p & "paste-preview")
  s.foregroundNormalColor     = cfg.getColorOrDefault(p & "foreground.normal")
  s.foregroundLightColor      = cfg.getColorOrDefault(p & "foreground.light")
  s.coordinatesNormalColor    = cfg.getColorOrDefault(p & "coordinates.normal")
  s.coordinatesHighlightColor = cfg.getColorOrDefault(p & "coordinates.highlight")
  s.regionBorderNormalColor   = cfg.getColorOrDefault(p & "region-border.normal")
  s.regionBorderEmptyColor    = cfg.getColorOrDefault(p & "region-border.empty")

  p = "background-hatch."
  s.backgroundHatchEnabled       = cfg.getBoolOrDefault(p & "enabled")
  s.backgroundHatchColor         = cfg.getColorOrDefault(p & "color")
  s.backgroundHatchWidth         = cfg.getFloatOrDefault(p & "width")
  s.backgroundHatchSpacingFactor = cfg.getFloatOrDefault(p & "spacing-factor")

  p = "grid."
  s.gridBackgroundStyle     = cfg.getEnumOrDefault(p & "background.style", GridStyle)
  s.gridBackgroundGridColor = cfg.getColorOrDefault(p & "background.grid")
  s.gridFloorStyle          = cfg.getEnumOrDefault(p & "floor.style", GridStyle)
  s.gridFloorGridColor      = cfg.getColorOrDefault(p & "floor.grid")

  p = "outline."
  s.outlineStyle       = cfg.getEnumOrDefault(p & "style", OutlineStyle)
  s.outlineFillStyle   = cfg.getEnumOrDefault(p & "fill-style", OutlineFillStyle)
  s.outlineColor       = cfg.getColorOrDefault(p & "color")
  s.outlineWidthFactor = cfg.getFloatOrDefault(p & "width-factor")
  s.outlineOverscan    = cfg.getBoolOrDefault(p & "overscan")

  p = "shadow."
  s.shadowInnerColor        = cfg.getColorOrDefault(p & "inner.color")
  s.shadowInnerWidthFactor  = cfg.getFloatOrDefault(p & "inner.width-factor")
  s.shadowOuterColor        = cfg.getColorOrDefault(p & "outer.color")
  s.shadowOuterWidthFactor  = cfg.getFloatOrDefault(p & "outer.width-factor")

  p = "floor."
  s.floorTransparent = cfg.getBoolOrDefault(p & "transparent")

  cfg.getColorOrDefaultArray(p & "background", s.floorBackgroundColor)

  p = "note."
  s.noteMarkerColor     = cfg.getColorOrDefault(p & "marker")
  s.noteCommentColor    = cfg.getColorOrDefault(p & "comment")
  s.noteBackgroundShape = cfg.getEnumOrDefault(p & "background-shape", NoteBackgroundShape)

  cfg.getColorOrDefaultArray(p & "index-background", s.noteIndexBackgroundColor)

  s.noteIndexColor             = cfg.getColorOrDefault(p & "index")
  s.noteTooltipBackgroundColor = cfg.getColorOrDefault(p & "tooltip.background")
  s.noteTooltipTextColor       = cfg.getColorOrDefault(p & "tooltip.text")

  cfg.getColorOrDefaultArray("label.text", s.labelTextColor)

# }}}
# {{{ toWindowStyle*()
proc toWindowStyle*(cfg: HoconNode): WindowStyle =
  alias(s, result)
  s = new WindowStyle

  s.modifiedFlagColor            = cfg.getColorOrDefault("modified-flag")
  s.backgroundColor              = cfg.getColorOrDefault("background.color")
  s.backgroundImage              = cfg.getStringOrDefault("background.image")
  s.titleBackgroundColor         = cfg.getColorOrDefault("title.background.normal")
  s.titleBackgroundInactiveColor = cfg.getColorOrDefault("title.background.inactive")
  s.titleColor                   = cfg.getColorOrDefault("title.text.normal")
  s.titleInactiveColor           = cfg.getColorOrDefault("title.text.inactive")
  s.buttonColor                  = cfg.getColorOrDefault("button.normal")
  s.buttonHoverColor             = cfg.getColorOrDefault("button.hover")
  s.buttonDownColor              = cfg.getColorOrDefault("button.down")

# }}}
# {{{ toStatusBarStyle*()
proc toStatusBarStyle*(cfg: HoconNode): StatusBarStyle =
  alias(s, result)
  s = new StatusBarStyle

  s.backgroundColor        = cfg.getColorOrDefault("background")
  s.textColor              = cfg.getColorOrDefault("text")
  s.coordinatesColor       = cfg.getColorOrDefault("coordinates")
  s.commandBackgroundColor = cfg.getColorOrDefault("command.background")
  s.commandTextColor       = cfg.getColorOrDefault("command.text")

# }}}
# {{{ toNotesPaneStyle*()
proc toNotesPaneStyle*(cfg: HoconNode): NotesPaneStyle =
  alias(s, result)
  s = new NotesPaneStyle

  s.textColor      = cfg.getColorOrDefault("text")
  s.scrollBarColor = cfg.getColorOrDefault("scroll-bar")
  s.indexColor     = cfg.getColorOrDefault("index")

  cfg.getColorOrDefaultArray("index-background", s.indexBackgroundColor)

# }}}
# {{{ toToolbarPaneStyle*()
proc toToolbarPaneStyle*(cfg: HoconNode): ToolbarPaneStyle =
  alias(s, result)
  s = new ToolbarPaneStyle

  s.buttonNormalColor = cfg.getColorOrDefault("button.normal")
  s.buttonHoverColor  = cfg.getColorOrDefault("button.hover")
# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): HoconNode =
  var s: FileStream
  try:
    s = newFileStream(filename)
    var p = initHoconParser(s)
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
  finally:
    if s != nil: s.close()

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
