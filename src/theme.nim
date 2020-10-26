import options
import parsecfg
import strformat

import nanovg

import cfghelper
import common
import csdwindow
import utils


const
  GeneralSection       = "general"
  WidgetSection        = "widget"
  TextFieldSection     = "textField"
  DialogSection        = "dialog"
  TitleBarSection      = "titleBar"
  StatusBarSection     = "statusBar"
  LevelDropdownSection = "levelDropdown"
  AboutButtonSection   = "aboutButton"
  LevelSection         = "level"
  NotesPaneSection     = "notesPane"
  ToolbarPaneSection   = "toolbarPane"

# {{{ GeneralStyle
type
  GeneralStyle* = ref object
    backgroundColor*: Color
    backgroundImage*: string
    highlightColor*:  Color

var DefaultGeneralStyle = new GeneralStyle

DefaultGeneralStyle.backgroundColor = gray(0.4)
DefaultGeneralStyle.backgroundImage = ""
DefaultGeneralStyle.highlightColor  = gray(0.4)

# }}}
# {{{ WidgetStyle
type
  WidgetStyle* = ref object
    bgColor*:           Color
    bgColorHover*:      Color
    bgColorDisabled*:   Color
    textColor*:         Color
    textColorDisabled*: Color

var DefaultWidgetStyle = new WidgetStyle

DefaultWidgetStyle.bgColor           = gray(0.4)
DefaultWidgetStyle.bgColorHover      = gray(0.4)
DefaultWidgetStyle.bgColorDisabled   = gray(0.4)
DefaultWidgetStyle.textColor         = gray(0.4)
DefaultWidgetStyle.textColorDisabled = gray(0.4)

# }}}
# {{{ TextFieldStyle
type
  TextFieldStyle* = ref object
    bgColorActive*:     Color
    textColorActive*:   Color
    cursorColor*:       Color
    selectionColor*:    Color

var DefaultTextFieldStyle = new TextFieldStyle

DefaultTextFieldStyle.bgColorActive   = gray(0.4)
DefaultTextFieldStyle.textColorActive = gray(0.4)
DefaultTextFieldStyle.cursorColor     = gray(0.4)
DefaultTextFieldStyle.selectionColor  = gray(0.4)


# }}}
# {{{ DialogStyle
type
  DialogStyle* = ref object
    titleBarBgColor*:   Color
    titleBarTextColor*: Color
    backgroundColor*:   Color
    textColor*:         Color
    warningTextColor*:  Color
    outerBorderColor*:  Color
    innerBorderColor*:  Color
    outerBorderWidth*:  float
    innerBorderWidth*:  float

var DefaultDialogStyle = new DialogStyle

DefaultDialogStyle.titleBarBgColor   = gray(0.4)
DefaultDialogStyle.titleBarTextColor = gray(0.4)
DefaultDialogStyle.backgroundColor   = gray(0.4)
DefaultDialogStyle.textColor         = gray(0.4)
DefaultDialogStyle.warningTextColor  = gray(0.4)
DefaultDialogStyle.outerBorderColor  = gray(0.4)
DefaultDialogStyle.innerBorderColor  = gray(0.4)
DefaultDialogStyle.outerBorderWidth  = 0.0
DefaultDialogStyle.innerBorderWidth  = 0.0

# }}}
# {{{ StatusBarStyle
type
  StatusBarStyle* = ref object
    backgroundColor*:    Color
    textColor*:          Color
    commandBgColor*:     Color
    commandColor*:       Color
    coordsColor*:        Color

var DefaultStatusBarStyle = new StatusBarStyle

DefaultStatusBarStyle.backgroundColor = gray(0.2)
DefaultStatusBarStyle.textColor       = gray(0.8)
DefaultStatusBarStyle.commandBgColor  = gray(0.56)
DefaultStatusBarStyle.commandColor    = gray(0.2)
DefaultStatusBarStyle.coordsColor     = gray(0.6)

# }}}
# {{{ LevelDropdownStyle
type
  LevelDropdownStyle* = ref object
    buttonColor*:       Color
    buttonColorHover*:  Color
    textColor*:         Color
    itemListColor*:     Color
    itemColor*:         Color
    itemColorHover*:    Color

var DefaultLevelDropdownStyle = new LevelDropdownStyle

DefaultLevelDropdownStyle.buttonColor      = gray(0.4)
DefaultLevelDropdownStyle.buttonColorHover = gray(0.4)
DefaultLevelDropdownStyle.textColor        = gray(0.4)
DefaultLevelDropdownStyle.itemListColor    = gray(0.4)
DefaultLevelDropdownStyle.itemColor        = gray(0.4)
DefaultLevelDropdownStyle.itemColorHover   = gray(0.4)

# }}}
# {{{ AboutButtonStyle
type
  AboutButtonStyle* = ref object
    color*:       Color
    colorHover*:  Color
    colorActive*: Color

var DefaultAboutButtonStyle = new AboutButtonStyle

DefaultAboutButtonStyle.color       = gray(0.4)
DefaultAboutButtonStyle.colorHover  = gray(0.4)
DefaultAboutButtonStyle.colorActive = gray(0.4)

# }}}
# {{{ DefaultLevelStyle
var DefaultLevelStyle = new LevelStyle

DefaultLevelStyle.backgroundColor      = gray(0.4)
DefaultLevelStyle.drawColor            = gray(0.1)
DefaultLevelStyle.lightDrawColor       = gray(0.6)
DefaultLevelStyle.lineWidth            = lwNormal

DefaultLevelStyle.floorColor           = @[gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5),
                                           gray(0.5)]

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

DefaultLevelStyle.noteMarkerColor  = gray(0.85)
DefaultLevelStyle.noteCommentColor = rgba(1.0, 0.2, 0.0, 0.8)
DefaultLevelStyle.noteIndexColor   = gray(0.85)
DefaultLevelStyle.noteIndexBgColor = @[gray(0.0, 0.2),
                                       gray(0.0, 0.2),
                                       gray(0.0, 0.2),
                                       gray(0.0, 0.2)]

DefaultLevelStyle.noteTooltipBgColor   = gray(0.05)
DefaultLevelStyle.noteTooltipTextColor = gray(0.95)

DefaultLevelStyle.linkMarkerColor      = gray(0.85)

DefaultLevelStyle.regionBorderColor      = gray(0.25)
DefaultLevelStyle.regionBorderEmptyColor = gray(0.25)

# }}}
# {{{ NotesPaneStyle
type
  NotesPaneStyle* = ref object
    textColor*:      Color
    indexColor*:     Color
    indexBgColor*:   seq[Color]

var DefaultNotesPaneStyle = new NotesPaneStyle

DefaultNotesPaneStyle.textColor    = gray(0.1)
DefaultNotesPaneStyle.indexColor   = gray(0.1)
DefaultNotesPaneStyle.indexBgColor = @[gray(1.0, 0.2),
                                       gray(1.0, 0.2),
                                       gray(1.0, 0.2),
                                       gray(1.0, 0.2)]

# }}}
# {{{ ToolbarPaneStyle
type
  ToolbarPaneStyle* = ref object
    buttonBgColor*:       Color
    buttonBgColorHover*:  Color

var DefaultToolbarPaneStyle = new ToolbarPaneStyle

DefaultToolbarPaneStyle.buttonBgColor       = gray(0.4)
DefaultToolbarPaneStyle.buttonBgColorHover  = gray(0.4)

# }}}

# {{{ ThemeStyle
type
  ThemeStyle* = ref object
    general*:       GeneralStyle
    widget*:        WidgetStyle
    textField*:     TextFieldStyle
    dialog*:        DialogStyle
    titleBar*:      CSDWindowStyle
    statusBar*:     StatusBarStyle
    levelDropdown*: LevelDropdownStyle
    aboutButton*:   AboutButtonStyle
    level*:         LevelStyle
    notesPane*:     NotesPaneStyle
    toolbarPane*:   ToolbarPaneStyle

var DefaultThemeStyle = new ThemeStyle

DefaultThemeStyle.general       = DefaultGeneralStyle
DefaultThemeStyle.widget        = DefaultWidgetStyle
DefaultThemeStyle.textField     = DefaultTextFieldStyle
DefaultThemeStyle.dialog        = DefaultDialogStyle
DefaultThemeStyle.titleBar      = getDefaultCSDWindowStyle()
DefaultThemeStyle.statusBar     = DefaultStatusBarStyle
DefaultThemeStyle.levelDropdown = DefaultLevelDropdownStyle
DefaultThemeStyle.aboutButton   = DefaultAboutButtonStyle
DefaultThemeStyle.level         = DefaultLevelStyle
DefaultThemeStyle.notesPane     = DefaultNotesPaneStyle
DefaultThemeStyle.toolbarPane   = DefaultToolbarPaneStyle

# }}}

# {{{ parseTheme()
proc parseTheme(c: Config): ThemeStyle =
  result = DefaultThemeStyle.deepCopy()

  block:
    alias(s, result.general)
    let S = GeneralSection

    c.getColor( S, "backgroundColor", s.backgroundColor)
    c.getString(S, "backgroundImage", s.backgroundImage)
    c.getColor( S, "highlightColor",  s.highlightColor)

  block:
    alias(s, result.widget)
    let S = WidgetSection

    c.getColor(S, "bgColor",           s.bgColor)
    c.getColor(S, "bgColorHover",      s.bgColorHover)
    c.getColor(S, "bgColorDisabled",   s.bgColorDisabled)
    c.getColor(S, "textColor",         s.textColor)
    c.getColor(S, "textColorDisabled", s.textColorDisabled)

  block:
    alias(s, result.textField)
    let S = TextFieldSection

    c.getColor(S, "bgColorActive",   s.bgColorActive)
    c.getColor(S, "textColorActive", s.textColorActive)
    c.getColor(S, "cursorColor",     s.cursorColor)
    c.getColor(S, "selectionColor",  s.selectionColor)

  block:
    alias(s, result.dialog)
    let S = DialogSection

    c.getColor(S, "titleBarBgColor",   s.titleBarBgColor)
    c.getColor(S, "titleBarTextColor", s.titleBarTextColor)
    c.getColor(S, "backgroundColor",   s.backgroundColor)
    c.getColor(S, "textColor",         s.textColor)
    c.getColor(S, "warningTextColor",  s.warningTextColor)
    c.getColor(S, "outerBorderColor",  s.outerBorderColor)
    c.getColor(S, "innerBorderColor",  s.innerBorderColor)
    c.getFloat(S, "outerBorderWidth",  s.outerBorderWidth)
    c.getFloat(S, "innerBorderWidth",  s.innerBorderWidth)

  block:
    alias(s, result.titleBar)
    let S = TitleBarSection

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
    let S = StatusBarSection

    c.getColor(S, "backgroundColor",  s.backgroundColor)
    c.getColor(S, "textColor",        s.textColor)
    c.getColor(S, "commandBgColor",   s.commandBgColor)
    c.getColor(S, "commandColor",     s.commandColor)
    c.getColor(S, "coordsColor",      s.coordsColor)

  block:
    alias(s, result.levelDropdown)
    let S = LevelDropdownSection

    c.getColor(S, "buttonColor",      s.buttonColor)
    c.getColor(S, "buttonColorHover", s.buttonColorHover)
    c.getColor(S, "textColor",        s.textColor)
    c.getColor(S, "itemListColor",    s.itemListColor)
    c.getColor(S, "itemColor",        s.itemColor)
    c.getColor(S, "itemColorHover",   s.itemColorHover)

  block:
    alias(s, result.aboutButton)
    let S = AboutButtonSection

    c.getColor(S, "color",            s.color)
    c.getColor(S, "colorHover",       s.colorHover)
    c.getColor(S, "colorActive",      s.colorActive)

  block:
    alias(s, result.level)
    let S = LevelSection

    c.getColor(S, "backgroundColor",          s.backgroundColor)
    c.getColor(S, "drawColor",                s.drawColor)
    c.getColor(S, "lightDrawColor",           s.lightDrawColor)
    getEnum[LineWidth](c, S, "lineWidth", s.lineWidth)

    c.getColor(S, "floorColor1",              s.floorColor[0])
    c.getColor(S, "floorColor2",              s.floorColor[1])
    c.getColor(S, "floorColor3",              s.floorColor[2])
    c.getColor(S, "floorColor4",              s.floorColor[3])
    c.getColor(S, "floorColor5",              s.floorColor[4])
    c.getColor(S, "floorColor6",              s.floorColor[5])
    c.getColor(S, "floorColor7",              s.floorColor[6])
    c.getColor(S, "floorColor8",              s.floorColor[7])
    c.getColor(S, "floorColor9",              s.floorColor[8])

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

    c.getColor(S, "noteMarkerColor",          s.noteMarkerColor)
    c.getColor(S, "noteCommentColor",         s.noteCommentColor)
    c.getColor(S, "noteIndexColor",           s.noteIndexColor)
    c.getColor(S, "noteIndexBgColor1",        s.noteIndexBgColor[0])
    c.getColor(S, "noteIndexBgColor2",        s.noteIndexBgColor[1])
    c.getColor(S, "noteIndexBgColor3",        s.noteIndexBgColor[2])
    c.getColor(S, "noteIndexBgColor4",        s.noteIndexBgColor[3])

    c.getColor(S, "noteTooltipBgColor",       s.noteTooltipBgColor)
    c.getColor(S, "noteTooltipTextColor",     s.noteTooltipTextColor)

    c.getColor(S, "linkMarkerColor",          s.linkMarkerColor)

    c.getColor(S, "regionBorderColor",        s.regionBorderColor)
    c.getColor(S, "regionBorderEmptyColor",   s.regionBorderEmptyColor)

  block:
    alias(s, result.notesPane)
    let S = NotesPaneSection

    c.getColor(S, "textColor",                s.textColor)
    c.getColor(S, "indexColor",               s.indexColor)
    c.getColor(S, "indexBgColor1",            s.indexBgColor[0])
    c.getColor(S, "indexBgColor2",            s.indexBgColor[1])
    c.getColor(S, "indexBgColor3",            s.indexBgColor[2])
    c.getColor(S, "indexBgColor4",            s.indexBgColor[3])

  block:
    alias(s, result.toolbarPane)
    let S = ToolbarPaneSection

    c.getColor(S, "buttonBgColor",            s.buttonBgColor)
    c.getColor(S, "buttonBgColorHover",       s.buttonBgColorHover)

# }}}

# {{{ loadTheme*()
proc loadTheme*(filename: string): ThemeStyle =
  echo fmt"Loading theme '{filename}'..."
  var cfg = loadConfig(filename)
  result = parseTheme(cfg)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
