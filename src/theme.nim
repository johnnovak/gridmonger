import options
import streams
import strformat

import koi
import nanovg

import cfghelper
import common
import fieldlimits
import hocon
import strutils
import utils


# {{{ DefaultThemeConfig

const DefaultThemeString = """
  ui {
    window {
      modified-flag = "#ffffff40"

      border {
        color = "#1b1b1bff"
      }
      background {
        color = "#666666ff"
        image = ""
      }
      title {
        background {
          normal = "#2e2e2eff"
          inactive = "#1a1a1aff"
        }
        text {
          normal = "#ffffff80"
          inactive = "#ffffff66"
        }
      }
      button {
        normal = "#ffffff73"
        hover = "#ffffffb3"
        down = "#ffffffe6"
        inactive = "#00000080"
      }
    }

    dialog {
      corner-radius = 6
      background = "#4d4d4dff"
      label = "#ffffffb3"
      warning = "#ffffffec"
      error = "#ff6464ff"

      title {
        background = "#1a1a1aff"
        text = "#d9d9d9ff"
      }
      inner-border {
        color = "#00000000"
        width = 0
      }
      outer-border {
        color = "#00000000"
        width = 0
      }
      shadow {
        enabled = yes
        color = "#000000a8"
        feather = 24
        x-offset = 2
        y-offset = 3
      }
    }

    widget {
      corner-radius = 4

      background {
        normal = "#ffffff80"
        hover = "#ffffffa1"
        active = "#ffa600ff"
        disabled = "#ffffff33"
      }
      foreground {
        normal = "#000000b3"
        active = "#0000009e"
        disabled = "#00000059"
      }
    }

    text-field {
      cursor = "#ffbe00ff"
      selection = "#c8820078"

      edit {
        background = "#ffffff33"
        text = "#ffffffcc"
      }
      scroll-bar {
        normal = "#00000000"
        edit = "#ffffffcc"
      }
    }

    status-bar {
      background = "#262626ff"
      text = "#d1d1d1ff"
      coordinates = "#999999ff"

      command {
        background = "#ffa600e9"
        text = "#333333ff"
      }
    }

    about-button {
      label {
        normal = "#ffffff80"
        hover = "#ffffffb3"
        down = "#ffffffd9"
      }
    }

    about-dialog {
      logo = "#e6e6e6ff"
    }

    splash-image {
      logo = "#202020ff"
      outline = "#e6e6e6ff"
      shadow-alpha = 1
    }
  }

  level {
    general {
      background = "#666666ff"
      line-width = normal
      cursor = "#ffa600ff"
      cursor-guides = "#ffa60033"
      link-marker = "#00b3c8ff"
      selection = "#ff808066"
      paste-preview = "#3399ff66"

      trail {
        normal = "#00000062"
        cursor = "#00000062"
      }
      foreground {
        normal {
          normal = "#1a1a1aff"
          cursor = "#1a1a1aff"
        }
        light {
          normal = "#1a1a1a46"
          cursor = "#1a1a1a46"
        }
      }
      coordinates {
        normal = "#e6e6e6ff"
        highlight = "#ffbf00ff"
      }
      region-border {
        normal = "#ff8080ff"
        empty = "#ff808066"
      }
    }

    background-hatch {
      enabled = yes
      color = "#00000066"
      width = 1
      spacing-factor = 2
    }

    grid {
      background {
        style = solid
        grid = "#0000001a"
      }
      floor {
        style = solid
        grid = "#33333368"
      }
    }

    outline {
      style = cell
      fill-style = solid
      color = "#3d3d3dff"
      width-factor = 0.5
      overscan = no
    }

    shadow {
      inner {
        color = "#0000001a"
        width-factor = 0
      }
      outer {
        color = "#0000001a"
        width-factor = 0
      }
    }

    floor {
      transparent = no
      background = [
        "#f2f2eeff"
        "#6f000097"
        "#ff290074"
        "#ffb30080"
        "#7c652192"
        "#709a0092"
        "#a6c41e63"
        "#0c9ce047"
        "#1c6fac83"
        "#9c559fa6"
      ]
    }

    note {
      marker {
        normal = "#1a1a1ab3"
        cursor = "#1a1a1ab3"
      }
      comment = "#ff3300cc"
      background-shape = circle
      index = "#ffffffff"
      index-background = [
        "#f75c4aff"
        "#ff9c6aff"
        "#00b3c8ff"
        "#13837fff"
      ]

      tooltip {
        background = "#0d0d0dff"
        text = "#e6e6e6ff"
        corner-radius = 5

        shadow {
          color = "#00000064"
        }
      }
    }

    label {
      text = [
        "#353232ff"
        "#ffffffff"
        "#f75c4aff"
        "#00b3c8ff"
      ]
    }

    level-drop-down {
      item-list-background = "#333333ff"
      corner-radius = 5

      button {
        normal = "#00000000"
        hover = "#00000047"
        label = "#ffffffe6"
      }
      item {
        normal = "#ffffffcc"
        hover = "#000000b3"
      }
      shadow {
        color = "#00000064"
      }
    }
  }

  pane {
    notes {
      text = "#e6e6e6ff"
      scroll-bar = "#e6e6e6ff"
      index = "#ffffffff"
      index-background = [
        "#f75c4aff"
        "#fa8d64ff"
        "#00b3c8ff"
        "#1d8d89ff"
      ]
    }

    toolbar {
      button {
        normal = "#e6e6e6ff"
        hover = "#ffffffff"
      }
    }
  }
"""

let s = newStringStream(DefaultThemeString)
var p = initHoconParser(s)
let DefaultThemeConfig = p.parse()

# }}}

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
  for i,c in colors.mpairs:
    c = cfg.getColorOrDefault(fmt"{key}.{i}")
# }}}

# {{{ toLevelStyle*()
proc toLevelStyle*(cfg: HoconNode): LevelStyle =
  alias(s, result)
  s = new LevelStyle

  var p = "general."
  s.lineWidth                   = cfg.getEnumOrDefault(p & "line-width", LineWidth)
  s.backgroundColor             = cfg.getColorOrDefault(p & "background")
  s.cursorColor                 = cfg.getColorOrDefault(p & "cursor")
  s.cursorGuidesColor           = cfg.getColorOrDefault(p & "cursor-guides")
  s.linkMarkerColor             = cfg.getColorOrDefault(p & "link-marker")
  s.selectionColor              = cfg.getColorOrDefault(p & "selection")
  s.trailNormalColor            = cfg.getColorOrDefault(p & "trail.normal")
  s.trailCursorColor            = cfg.getColorOrDefault(p & "trail.cursor")
  s.pastePreviewColor           = cfg.getColorOrDefault(p & "paste-preview")
  s.foregroundNormalNormalColor = cfg.getColorOrDefault(p & "foreground.normal.normal")
  s.foregroundNormalCursorColor = cfg.getColorOrDefault(p & "foreground.normal.cursor")
  s.foregroundLightNormalColor  = cfg.getColorOrDefault(p & "foreground.light.normal")
  s.foregroundLightCursorColor  = cfg.getColorOrDefault(p & "foreground.light.cursor")
  s.coordinatesNormalColor      = cfg.getColorOrDefault(p & "coordinates.normal")
  s.coordinatesHighlightColor   = cfg.getColorOrDefault(p & "coordinates.highlight")
  s.regionBorderNormalColor     = cfg.getColorOrDefault(p & "region-border.normal")
  s.regionBorderEmptyColor      = cfg.getColorOrDefault(p & "region-border.empty")

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
  s.noteMarkerNormalColor = cfg.getColorOrDefault(p & "marker.normal")
  s.noteMarkerCursorColor = cfg.getColorOrDefault(p & "marker.cursor")
  s.noteCommentColor      = cfg.getColorOrDefault(p & "comment")
  s.noteBackgroundShape   = cfg.getEnumOrDefault(p & "background-shape", NoteBackgroundShape)

  cfg.getColorOrDefaultArray(p & "index-background", s.noteIndexBackgroundColor)

  s.noteIndexColor             = cfg.getColorOrDefault(p & "index")
  s.noteTooltipBackgroundColor = cfg.getColorOrDefault(p & "tooltip.background")
  s.noteTooltipTextColor       = cfg.getColorOrDefault(p & "tooltip.text")

  let cr = cfg.getFloatOrDefault(p & "tooltip.corner-radius")
  s.noteTooltipCornerRadius = cr

  var ss = koi.getDefaultShadowStyle()
  ss.color = cfg.getColorOrDefault(p & "tooltip.shadow.color")
  ss.cornerRadius = cr * 1.6
  s.noteTooltipShadowStyle = ss

  cfg.getColorOrDefaultArray("label.text", s.labelTextColor)

# }}}
# {{{ toWindowStyle*()
proc toWindowStyle*(cfg: HoconNode): WindowStyle =
  alias(s, result)
  s = new WindowStyle

  s.borderColor                  = cfg.getColorOrDefault("border.color")
  s.backgroundColor              = cfg.getColorOrDefault("background.color")
  s.backgroundImage              = cfg.getStringOrDefault("background.image")
  s.titleBackgroundColor         = cfg.getColorOrDefault("title.background.normal")
  s.titleBackgroundInactiveColor = cfg.getColorOrDefault("title.background.inactive")
  s.titleColor                   = cfg.getColorOrDefault("title.text.normal")
  s.titleInactiveColor           = cfg.getColorOrDefault("title.text.inactive")
  s.modifiedFlagColor            = cfg.getColorOrDefault("modified-flag")
  s.buttonColor                  = cfg.getColorOrDefault("button.normal")
  s.buttonHoverColor             = cfg.getColorOrDefault("button.hover")
  s.buttonDownColor              = cfg.getColorOrDefault("button.down")
  s.buttonInactiveColor          = cfg.getColorOrDefault("button.inactive")

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

    cfg.limit("level.note.tooltip.corner-radius", WidgetCornerRadiusLimits)

    cfg.limit("level.outline.width-factor",   OutlineWidthFactorLimits)

    cfg.limit("level.shadow.inner.width-factor", ShadowWidthFactorLimits)
    cfg.limit("level.shadow.outer.width-factor", ShadowWidthFactorLimits)

    result = DefaultThemeConfig.deepCopy()
    result.merge(cfg)

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
