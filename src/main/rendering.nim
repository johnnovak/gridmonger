# rendering
#
# All AppContext-aware rendering procs: level + tools pane + note panes +
# theme editor + status bar + quick reference + dialog dispatcher +
# top-level UI orchestrator. ui/drawlevel and ui/csdwindow are the
# AppContext-unaware visual primitives this layer sits on top of.
#
# Side effects: koi + nanovg drawing calls. Reads heavily from AppContext;
# writes back layout/scroll/note-cache state.

import std/algorithm
import std/lenientops
import std/math
import std/monotimes
import std/options
import std/sequtils
import std/setutils
import std/strformat
import std/strutils except splitWhitespace, strip
import std/sugar
import std/tables
import std/times
import std/unicode

import glfw
import koi
from koi/utils import lerp, invLerp, remap
import nanovg
import semver
import with

import cfghelper
import common
import domain/all
import fieldlimits          # FieldLimits
import io/persistence       # NotesListSearchTermLimits
import main/appcontext
import main/constants
import main/cursor
import main/dialogs
import main/events          # handleLevelMouseEvents
import main/keyboard
import main/panes/currentnotepane
import main/panes/levelview
import main/panes/noteslistpane
import main/panes/toolspane
import main/status_msg
import main/themeio
import main/view
import ui/all
import utils/all
import utils/misc as gmUtils


using a: var AppContext

# {{{ Theme editor

var ThemeEditorScrollViewStyle = koi.getDefaultScrollViewStyle()
with ThemeEditorScrollViewStyle:
  vertScrollBarWidth      = 14.0
  scrollBarStyle.thumbPad = 4.0

var ThemeEditorSliderStyle = koi.getDefaultSliderStyle()
with ThemeEditorSliderStyle:
  trackCornerRadius = 8.0
  valueCornerRadius = 6.0

var ThemeEditorAutoLayoutParams = DefaultAutoLayoutParams
with ThemeEditorAutoLayoutParams:
  leftPad    = 14.0
  rightPad   = 16.0
  labelWidth = 185.0

# {{{ renderThemeEditorProps()
proc renderThemeEditorProps*(x, y, w, h: float; a) =
  alias(te, a.themeEditor)
  alias(cfg, a.theme.config)

  template prop(label: string, path: string, body: untyped)  =
    block:
      koi.label(label)
      koi.setNextId(path)
      body
      if a.theme.prevConfig.getOpt(path) != cfg.getOpt(path):
        te.modified = true

  template stringProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getStringOrDefault(path)
      koi.textfield(val)
      hocon.set(cfg, path, $val)

  template colorProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getColorOrDefault(path)
      koi.color(val)
      hocon.set(cfg, path, $val)

  template boolProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getBoolOrDefault(path)
      koi.checkBox(val)
      hocon.set(cfg, path, val)

  template floatProp(label: string, path: string, limits: FieldLimits) =
    prop(label, path):
      var val = cfg.getFloatOrDefault(path)
      koi.horizSlider(startVal=limits.minFloat,
                      endVal=limits.maxFloat,
                      val,
                      style=ThemeEditorSliderStyle)
      hocon.set(cfg, path, val)

  template enumProp(label: string, path: string, T: typedesc[enum]) =
    prop(label, path):
      var val = cfg.getEnumOrDefault(path, T)
      koi.dropDown(val)
      hocon.set(cfg, path, enumToDashCase($val))


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  var p: string

  # {{{ User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      p = "ui.window."
      group:
        colorProp("Border",           p & "border.color")

      group:
        colorProp("Background",       p & "background.color")
        let path = p & "background.image"
        stringProp("Background Image", path)

        koi.nextLayoutColumn()
        if koi.button("Reload", disabled=cfg.getString(path) == ""):
          a.theme.loadBackgroundImage = true

      group:
        p = "ui.window.title."
        colorProp("Title Background Normal",   p & "background.normal")
        colorProp("Title Background Inactive", p & "background.inactive")
        colorProp("Title Text Normal",         p & "text.normal")
        colorProp("Title Text Inactive",       p & "text.inactive")

      group:
        p = "ui.window."
        colorProp("Modified Flag Normal",      p & "modified-flag.normal")
        colorProp("Modified Flag Inactive",    p & "modified-flag.inactive")

      group:
        p = "ui.window.button."
        colorProp("Button Normal",    p & "normal")
        colorProp("Button Hover",     p & "hover")
        colorProp("Button Down",      p & "down")
        colorProp("Button Inactive",  p & "inactive")

    if koi.subSectionHeader("Dialog", te.sectionDialog):
      p = "ui.dialog."
      group:
        let CRLimits = DialogCornerRadiusLimits
        floatProp("Corner Radius",    p & "corner-radius", CRLimits)

      group:
        colorProp("Background",       p & "background")
        colorProp("Label",            p & "label")
        colorProp("Warning",          p & "warning")
        colorProp("Error",            p & "error")

      group:
        colorProp("Title Background", p & "title.background")
        colorProp("Title Text",       p & "title.text")

      group:
        let BWLimits = DialogBorderWidthLimits
        colorProp("Outer Border",       p & "outer-border.color")
        floatProp("Outer Border Width", p & "outer-border.width", BWLimits)
        colorProp("Inner Border",       p & "inner-border.color")
        floatProp("Inner Border Width", p & "inner-border.width", BWLimits)

      group:
        boolProp( "Shadow?",         p & "shadow.enabled")
        colorProp("Shadow Colour",   p & "shadow.color")
        floatProp("Shadow Feather",  p & "shadow.feather",  ShadowFeatherLimits)
        floatProp("Shadow X Offset", p & "shadow.x-offset", ShadowOffsetLimits)
        floatProp("Shadow Y Offset", p & "shadow.y-offset", ShadowOffsetLimits)

    if koi.subSectionHeader("Widget", te.sectionWidget):
      p = "ui.widget."
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",       p & "corner-radius", WCRLimits)
      group:
        colorProp("Background Normal",   p & "background.normal")
        colorProp("Background Hover",    p & "background.hover")
        colorProp("Background Active",   p & "background.active")
        colorProp("Background Disabled", p & "background.disabled")
      group:
        colorProp("Foreground Normal",   p & "foreground.normal")
        colorProp("Foreground Active",   p & "foreground.active")
        colorProp("Foreground Disabled", p & "foreground.disabled")

    if koi.subSectionHeader("Drop Down", te.sectionDropdown):
      p = "ui.drop-down."
      group:
        colorProp("Item List Background", p & "item-list-background")

    if koi.subSectionHeader("Text Field", te.sectionTextField):
      p = "ui.text-field."
      group:
        colorProp("Cursor",            p & "cursor")
        colorProp("Selection",         p & "selection")
      group:
        colorProp("Edit Background",   p & "edit.background")
        colorProp("Edit Text",         p & "edit.text")
      group:
        colorProp("Scroll Bar Normal", p & "scroll-bar.normal")
        colorProp("Scroll Bar Edit",   p & "scroll-bar.edit")

    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      p = "ui.status-bar."
      group:
        colorProp("Background",        p & "background")
      group:
        colorProp("Text",              p & "text")
        colorProp("Warning",           p & "warning")
        colorProp("Error",             p & "error")
      group:
        colorProp("Coordinates",       p & "coordinates")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      p = "ui.about-button."
      colorProp("Label Normal",        p & "label.normal")
      colorProp("Label Hover",         p & "label.hover")
      colorProp("Label Down",          p & "label.down")

    if koi.subSectionHeader("About Dialog", te.sectionAboutDialog):
      let path = "ui.about-dialog.logo"
      colorProp("Logo", path)
      if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
        a.dialogs.about.aboutLogo.updateLogoImage = true

    if koi.subSectionHeader("Quick Help", te.sectionQuickHelp):
      p = "ui.quick-help."
      group:
        colorProp("Background",        p & "background")
        colorProp("Title",             p & "title")
        colorProp("Text",              p & "text")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        p = "ui.splash-image."
        var path = p & "logo"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateLogoImage = true

        path = p & "outline"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateOutlineImage = true

        path = p & "shadow-alpha"
        floatProp("Shadow Alpha", path, AlphaLimits)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      p = "level.general."
      group:
        colorProp("Background",               p & "background")
      group:
        enumProp( "Line Width",               p & "line-width", LineWidth)
      group:
        colorProp("Foreground Normal",        p & "foreground.normal.normal")
        colorProp("Foreground Normal Cursor", p & "foreground.normal.cursor")
        colorProp("Foreground Light",         p & "foreground.light.normal")
        colorProp("Foreground Light Cursor",  p & "foreground.light.cursor")
      group:
        colorProp("Link Marker",              p & "link-marker")
        colorProp("Link Line",                p & "link-line")
      group:
        colorProp("Trail Normal",             p & "trail.normal")
        colorProp("Trail Cursor",             p & "trail.cursor")
      group:
        colorProp("Cursor",                   p & "cursor")
        colorProp("Cursor Guides",            p & "cursor-guides")
      group:
        colorProp("Selection",                p & "selection")
        colorProp("Paste Preview",            p & "paste-preview")
      group:
        colorProp("Coordinates Normal",       p & "coordinates.normal")
        colorProp("Coordinates Highlight",    p & "coordinates.highlight")
      group:
        colorProp("Region Border Normal",     p & "region-border.normal")
        colorProp("Region Border Empty",      p & "region-border.empty")

    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      let WidthLimits = BackgroundHatchWidthLimits
      let SpacingLimits = BackgroundHatchSpacingFactorLimits

      p = "level.background-hatch."
      group:
        boolProp("Background Hatch?",     p & "enabled")
      group:
        colorProp("Hatch",                p & "color")
        floatProp("Hatch Stroke Width",   p & "width",          WidthLimits)
        floatProp("Hatch Spacing Factor", p & "spacing-factor", SpacingLimits)

    if koi.subSectionHeader("Grid", te.sectionGrid):
      p = "level.grid."
      group:
        enumProp( "Background Grid Style", p & "background.style", GridStyle)
        # TODO enabled if style != None
        colorProp("Background Grid",       p & "background.grid")
      group:
        enumProp( "Floor Grid Style",      p & "floor.style",      GridStyle)
        # TODO enabled if style != None
        colorProp("Floor Grid",            p & "floor.grid")

    if koi.subSectionHeader("Outline", te.sectionOutline):
      p = "level.outline."
      enumProp( "Style",         p & "style",        OutlineStyle)
      # TODO enabled if Style!=None
      enumProp( "Fill Style",    p & "fill-style",   OutlineFillStyle)
      # TODO enabled if Style>=Square Edges
      colorProp("Outline",       p & "color")
      # TODO enabled if Style>=Square Edges
      floatProp("Width",         p & "width-factor", OutlineWidthFactorLimits)
      boolProp( "Overscan",      p & "overscan")

    if koi.subSectionHeader("Shadow", te.sectionShadow):
      let SWLimits = ShadowWidthFactorLimits
      p = "level.shadow."
      group:
        colorProp("Inner Shadow",       p & "inner.color")
        floatProp("Inner Shadow Width", p & "inner.width-factor", SWLimits)
      group:
        colorProp("Outer Shadow",       p & "outer.color")
        floatProp("Outer Shadow Width", p & "outer.width-factor", SWLimits)

    if koi.subSectionHeader("Floor Colours", te.sectionFloorColors):
      p = "level.floor."
      group:
        boolProp("Transparent?", p & "transparent")

      group:
        colorProp("Colour 1",  p & "background.0")
        colorProp("Colour 2",  p & "background.1")
        colorProp("Colour 3",  p & "background.2")
        colorProp("Colour 4",  p & "background.3")
        colorProp("Colour 5",  p & "background.4")
        colorProp("Colour 6",  p & "background.5")
        colorProp("Colour 7",  p & "background.6")
        colorProp("Colour 8",  p & "background.7")
        colorProp("Colour 9",  p & "background.8")
        colorProp("Colour 10", p & "background.9")

    if koi.subSectionHeader("Notes", te.sectionNotes):
      p = "level.note."
      group:
        colorProp("Marker Normal",      p & "marker.normal")
        colorProp("Marker Cursor",      p & "marker.cursor")
      group:
        colorProp("Comment",            p & "comment")
      group:
        enumProp( "Background Shape",   p & "background-shape",
                  NoteBackgroundShape)

        colorProp("Background 1",       p & "index-background.0")
        colorProp("Background 2",       p & "index-background.1")
        colorProp("Background 3",       p & "index-background.2")
        colorProp("Background 4",       p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Tooltip Background",     p & "tooltip.background")
        colorProp("Tooltip Text",           p & "tooltip.text")
        floatProp("Tooltip Corner Radius ", p & "tooltip.corner-radius",
                  WidgetCornerRadiusLimits)
        colorProp("Tooltip Shadow",         p & "tooltip.shadow.color")

    if koi.subSectionHeader("Labels", te.sectionLabels):
      p = "level.label."
      group:
        colorProp("Label 1", p & "text.0")
        colorProp("Label 2", p & "text.1")
        colorProp("Label 3", p & "text.2")
        colorProp("Label 4", p & "text.3")

    if koi.subSectionHeader("Level Drop Down", te.sectionLevelDropDown):
      p = "level.level-drop-down."
      group:
        colorProp("Button Normal",        p & "button.normal")
        colorProp("Button Hover",         p & "button.hover")
        colorProp("Button Label",         p & "button.label")
      group:
        colorProp("Item List Background", p & "item-list-background")
        colorProp("Item Normal",          p & "item.normal")
        colorProp("Item Hover",           p & "item.hover")
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",        p & "corner-radius", WCRLimits)
      group:
        colorProp("Shadow",               p & "shadow.color")

  # }}}
  # {{{ Panes section

  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Current Note Pane", te.sectionCurrentNotePane):
      p = "pane.current-note."
      group:
        colorProp("Text",               p & "text")
      group:
        colorProp("Index Background 1", p & "index-background.0")
        colorProp("Index Background 2", p & "index-background.1")
        colorProp("Index Background 3", p & "index-background.2")
        colorProp("Index Background 4", p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Scroll Bar",         p & "scroll-bar")

    if koi.subSectionHeader("Notes List Pane", te.sectionNotesListPane):
      p = "pane.notes-list."
      group:
        colorProp("Controls Background",       p & "controls-background")
        colorProp("List Background",           p & "list-background")
      group:
        colorProp("Level Section Background",  p & "level-section.background")
        colorProp("Level Section Text",        p & "level-section.text")
      group:
        colorProp("Region Section Background", p & "region-section.background")
        colorProp("Region Section Text",       p & "region-section.text")
      group:
        colorProp("Section Separator",         p & "section-separator")
      group:
        colorProp("Item Background Hover",     p & "item.background.hover")
        colorProp("Item Background Active",    p & "item.background.active")
      group:
        colorProp("Item Text Normal",          p & "item.text.normal")
        colorProp("Item Text Hover",           p & "item.text.hover")
        colorProp("Item Text Active",          p & "item.text.active")
      group:
        colorProp("Scroll Bar",                p & "scroll-bar")

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      p = "pane.toolbar."
      colorProp("Button",       p & "button.normal")
      colorProp("Button Hover", p & "button.hover")

  # }}}

  koi.endScrollView()

  a.theme.prevConfig = cfg.deepCopy

# }}}
# {{{ renderThemeEditorPane()

proc renderThemeEditorPane*(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let topSectionHeight = 130
  let propsHeight = h - topSectionHeight

  # Background
  vg.beginPath
  vg.rect(x, y, w, h)
  vg.fillColor(gray(0.3))
  vg.fill

  # Left separator line
  vg.strokeWidth(1.0)
  vg.lineCap(lcjSquare)

  vg.beginPath
  vg.moveTo(x+0.5, y)
  vg.lineTo(x+0.5, y+h)
  vg.strokeColor(gray(0.1))
  vg.stroke

  let
    bw = 68.0
    bp = 7.0
    wh = 22.0

  var cx = x
  var cy = y

  # Theme pane title
  const TitleHeight = 34

  vg.beginPath
  vg.rect(x+1, y, w, h=TitleHeight)
  vg.fillColor(gray(0.25))
  vg.fill

  let titleStyle = koi.getDefaultLabelStyle()
  titleStyle.align = haCenter

  cy += 6.0
  koi.label(cx, cy, w, wh, "T  H  E  M  E       E  D  I  T  O  R",
            style=titleStyle)

  # Theme name & action buttons
  vg.beginPath
  vg.rect(x+1, y+TitleHeight, w, h=96)
  vg.fillColor(gray(0.36))
  vg.fill

  cx = x+17
  cy += 45.0
  koi.label(cx, cy, w, wh, "Theme")

  let buttonsDisabled = koi.isDialogOpen()

  let themeNames = collect:
    for t in a.theme.themeNames: t.name

  var themeIndex = a.theme.currThemeIndex

  cx += 55.0
  koi.dropDown(
    cx, cy, w=189.0, wh,
    themeNames,
    themeIndex,
    tooltip = "",
    disabled = buttonsDisabled
  )

  proc switchTheme(a) =
    a.theme.nextThemeIndex = themeIndex.some

  if themeIndex != a.theme.currThemeIndex:
    if a.themeEditor.modified:
      openSaveDiscardThemeDialog(nextAction = switchTheme, a)
    else:
      switchTheme(a)

  # User theme indicator
  cx += 195
  var labelStyle = koi.getDefaultLabelStyle()

  if not a.currThemeName.userTheme:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "U", style=labelStyle)

  # User theme override indicator
  cx += 13
  labelStyle = koi.getDefaultLabelStyle()

  if not a.currThemeName.override:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "O", style=labelStyle)

  # Theme modified indicator
  cx += 16

  if a.themeEditor.modified:
    koi.label(cx, cy, 20, wh, IconAsterisk, style=koi.getDefaultLabelStyle())

  # Theme action buttons
  cx = x+15
  cy += 40.0

  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    saveTheme(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Copy", disabled=buttonsDisabled):
    openCopyThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Rename",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openRenameThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openDeleteThemeDialog(a)

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(a.themeEditor.focusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  a.themeEditor.focusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  a.theme.updateTheme = true

# }}}

# }}}

# {{{ renderCommand()
proc renderCommand*(x, y: float; command: string; bgColor, textColor: Color;
                   a: AppContext): float =
  alias(vg, a.vg)

  let w = vg.textWidth(command)
  let (x, y) = (round(x), round(y))

  vg.beginPath
  vg.roundedRect(x, y-10, w+10, 18, 3)
  vg.fillColor(bgColor)
  vg.fill

  vg.fillColor(textColor)
  discard vg.text(x+5, y, command)

  result = w


proc renderCommand*(x, y: float; command: string; a): float =
  let s = a.theme.statusBarTheme

  renderCommand(x, y, command,
                bgColor=s.commandBackgroundColor,
                textColor=s.commandTextColor, a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar*(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(status, a.ui.status)

  let s = a.theme.statusBarTheme

  let ty = h * TextVertAlignFactor

  # Bar background
  vg.save
  vg.translate(x, y)

  vg.beginPath
  vg.rect(0, 0, w, h)
  vg.fillColor(s.backgroundColor)
  vg.fill

  # Display cursor coordinates
  vg.setFont(14, "sans-bold")

  if a.doc.map.hasLevels:
    let
      l = currLevel(a)
      coordOpts = coordOptsForCurrLevel(a)

      cur = a.ui.cursor
      row = formatRowCoord(cur.row, l.rows, coordOpts, l.regionOpts)
      col = formatColumnCoord(cur.col, l.cols, coordOpts, l.regionOpts)

      cursorPos = fmt"({col}, {row})"
      tw = vg.textWidth(cursorPos)

    vg.fillColor(s.coordinatesColor)
    vg.textAlign(haLeft, vaMiddle)
    discard vg.text(w - tw - 7, ty, cursorPos)

    vg.intersectScissor(0, 0, w - tw - 15, h)

  # Display status message or warning
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 14
    CommandTextPadX = 10

  var x = 10.0

  # Clear expired warning messages
  if status.warning.message != "":
    let dt = getMonoTime() - status.warning.t0
    if dt > status.warning.timeout:
      status.warning.message = ""
      status.warning.overwrite = true

      if not status.warning.keepMessage:
        clearStatusMessage(a)
    else:
      koi.setFramesLeft()

  # Display message
  if status.warning.message == "":
    vg.fillColor(s.textColor)
    discard vg.text(IconPosX, ty, status.icon)

    let tx = vg.text(MessagePosX, ty, status.message)
    x = tx + MessagePadX

    # Display commands, if present
    for i, cmd in status.commands:
      if i mod 2 == 0:
        let w = renderCommand(x, ty, cmd, a)
        x += w + CommandLabelPadX
      else:
        let text = cmd
        vg.fillColor(s.textColor)
        let tw = vg.text(round(x), round(ty), text)
        x = tw + CommandTextPadX

  # Display warning
  else:
    vg.fillColor(status.warning.color)
    discard vg.text(IconPosX, ty, status.warning.icon)
    discard vg.text(MessagePosX, ty, status.warning.message)

  vg.restore

# }}}
# {{{ renderQuickReference()

proc renderQuickReference*(x, y, w, h: float; a) =
  alias(vg, a.vg)
  let cfg = a.theme.config

  let
    p = "ui.quick-help."
    bgColor          = cfg.getColorOrDefault(p & "background")
    textColor        = cfg.getColorOrDefault(p & "text")
    titleColor       = cfg.getColorOrDefault(p & "title")
    commandBgColor   = cfg.getColorOrDefault(p & "command.background")
    commandTextColor = cfg.getColorOrDefault(p & "command.text")


  proc renderSection(x, y: float; items: seq[QuickRefItem];
                     colWidth: float; a: AppContext) =

    const
      RowHeight  = 24.0
      SepaHeight = 14.0

    var
      x0 = x
      x  = x
      y  = y
      heightInc = RowHeight

    vg.setFont(14, "sans-bold")

    for item in items:
      case item.kind
      of qkShortcut:
        let shortcuts = a.keys.shortcuts[item.shortcut]
        heightInc = 0.0
        var ys = y
        for sc in shortcuts:
          let shortcut = sc.toStr
          discard renderCommand(x, ys, shortcut,
                                commandBgColor, commandTextColor, a)
          ys += RowHeight
          heightInc += RowHeight
        if shortcuts.len > 1: heightInc += SepaHeight
        x += colWidth

      of qkKeyShortcuts:
        var sx = x
        for idx, sc in item.keyShortcuts:
          let shortcut = sc.toStr
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.keyShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight

      of qkCustomShortcuts:
        var sx = x
        for idx, shortcut in item.customShortcuts:
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.customShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight


      of qkDescription:
        vg.fillColor(textColor)
        discard vg.text(round(x), round(y), item.description)
        x = x0
        y += heightInc

      of qkSeparator:
        y += SepaHeight


  let yOffs = ((h - 840) * 0.5).clampMin(0)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.save
    vg.intersectScissor(x, y, w, h)

  koi.addDrawLayer(koi.currentLayer(), vg):
    # Background
    vg.beginPath
    vg.rect(x, y, w, h)
    vg.fillColor(bgColor)
    vg.fill

    # Title
    vg.setFont(20, "sans-bold")
    vg.fillColor(titleColor)
    vg.textAlign(haCenter, vaMiddle)
    discard vg.text(round(x + w*0.5), 60+yOffs, "Quick Keyboard Reference")

  let
    t = invLerp(MinWindowWidth, 800.0, w).clamp(0.0, 1.0)
    viewWidth = lerp(652.0, 720.0, t)
    columnWidth = lerp(330.0, 350.0, t)
    tabWidth = 400.0

  let radioButtonX = x + (w - tabWidth)*0.5

  koi.radioButtons(
    radioButtonX, 92+yOffs, tabWidth, 24,
    QuickRefTabLabels, a.quickRef.activeTab,
    style = a.theme.radioButtonStyle
  )

  koi.beginScrollView(x = x + (w - viewWidth)*0.5 + 20,
                      y = y + 130+yOffs,
                      w = viewWidth, h = (h - 150))

  let a = a
  var (sx, sy) = addDrawOffset(10, 10)

  const DefaultColWidth = 120.0

  let (viewHeight, col1Width, col2Width) = case a.quickRef.activeTab
  of 0: (520.0, DefaultColWidth, DefaultColWidth)
  of 1: (655.0, DefaultColWidth, DefaultColWidth)
  else: (300.0, DefaultColWidth, DefaultColWidth)

  koi.addDrawLayer(koi.currentLayer(), vg):
    let itemColumns = a.keys.quickRefShortcuts[a.quickRef.activeTab]
    assert(itemColumns.len == 2)
    renderSection(sx, sy, itemColumns[0], col1Width, a)
    sx += columnWidth
    renderSection(sx, sy, itemColumns[1], col2Width, a)

  koi.endScrollView(viewHeight)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.restore

# }}}
# {{{ renderDialogs()
proc renderDialogs*(a) =
  alias(dlg, a.dialogs)

  case dlg.activeDialog:
  of dlgNone: discard

  of dlgAbout:
    aboutDialog(dlg.about, a)

  of dlgPreferences:
    preferencesDialog(dlg.preferences, a)

  of dlgSaveDiscardMap:
    saveDiscardMapDialog(dlg.saveDiscardMap, a)

  of dlgNewMap:
    newMapDialog(dlg.newMap, a)

  of dlgEditMapProps:
    editMapPropsDialog(dlg.editMapProps, a)

  of dlgNewLevel:
    newLevelDialog(dlg.newLevel, a)

  of dlgDeleteLevel:
    deleteLevelDialog(a)

  of dlgEditLevelProps:
    editLevelPropsDialog(dlg.editLevelProps, a)

  of dlgEditNote:
    editNoteDialog(dlg.editNote, a)

  of dlgEditLabel:
    editLabelDialog(dlg.editLabel, a)

  of dlgResizeLevel:
    resizeLevelDialog(dlg.resizeLevel, a)

  of dlgEditRegionProps:
    editRegionPropsDialog(dlg.editRegionProps, a)

  of dlgSaveDiscardTheme:
    saveDiscardThemeDialog(dlg.saveDiscardTheme, a)

  of dlgCopyTheme:
    copyThemeDialog(dlg.copyTheme, a)

  of dlgRenameTheme:
    renameThemeDialog(dlg.renameTheme, a)

  of dlgOverwriteTheme:
    overwriteThemeDialog(dlg.overwriteTheme, a)

  of dlgDeleteTheme:
    deleteThemeDialog(a)

# }}}

# {{{ renderUI()
proc renderUI*(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    mainPane = mainPaneRect(a)
    toolsPaneHeight = toolsPaneHeight(mainPane.h)

  # Clear background
  vg.beginPath

  # Make sure the background image extends to the notes list pane if open
  vg.rect(0, mainPane.y1, mainPane.w + mainPane.x1, mainPane.h)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.windowTheme.backgroundColor)

  vg.fill

  if a.ui.showQuickReference:
    var w = koi.winWidth()
    if a.layout.showThemeEditor: w -= ThemePaneWidth

    renderQuickReference(x=0, y=mainPane.y1, w=w, h=mainPane.h, a)

  else:
    if not map.hasLevels:
      renderEmptyMap(a)

    else:
      koi.beginView(x=mainPane.x1, y=mainPane.y1, w=mainPane.w, h=mainPane.h)

      # About button
      if button(x=mainPane.w-55.0, y=19.0, w=20.0, h=DlgItemHeight,
                IconQuestion, style=a.theme.aboutButtonStyle, tooltip="About"):
        openAboutDialog(a)

      renderLevelDropdown(a)

      if currLevel(a).regionOpts.enabled:
        renderRegionDropDown(a)

      let (levelDrawWidth, levelDrawHeight) = calculateLevelDrawArea(a)
      updateViewAndCursorPos(levelDrawWidth, levelDrawHeight, a)
      updateLastCursorViewCoords(a)

      alias(dp, ui.drawLevelParams)

      renderLevel(
        x = dp.startX,
        y = dp.startY,
        w = dp.viewCols * dp.gridSize,
        h = dp.viewRows * dp.gridSize,
        levelDrawWidth  = levelDrawWidth,
        levelDrawHeight = levelDrawHeight,
        a
      )

      renderModeAndOptionIndicators(
        x = mainPane.x1 + LevelLeftPad_NoCoords,
        y = a.win.titleBarHeight + 32,
        a
      )

      if a.layout.showToolsPane:
        renderToolsPane(
          x = mainPane.w - toolsPaneWidth(a),
          y = ToolsPaneTopPad,
          w = toolsPaneWidth(a),
          h = toolsPaneHeight,
          a
        )

      koi.endView()


    if map.hasLevels:
      if a.layout.showCurrentNotePane:
        var paneWidth = mainPane.w - CurrentNotePaneLeftPad -
                                     CurrentNotePaneRightPad

        let totalNotePaneHeight = CurrentNotePaneHeight +
                                  CurrentNotePaneTopPad +
                                  CurrentNotePaneBottomPad

        if mainPane.h - toolsPaneHeight - ToolsPaneTopPad <
           totalNotePaneHeight - 30:
          paneWidth -= toolsPaneWidth(a)

        renderCurrentNotePane(
          x = mainPane.x1 + CurrentNotePaneLeftPad,
          y = mainPane.y2 - CurrentNotePaneHeight - CurrentNotePaneBottomPad,
          w = paneWidth,
          h = CurrentNotePaneHeight,
          a
        )

      if a.layout.showNotesListPane:
        renderNotesListPane(x = 0, y = mainPane.y1,
                            w = NotesListPaneWidth,
                            h = mainPane.h, a)

  # Status bar
  let statusBarY = mainPane.y1 + mainPane.h
  renderStatusBar(0, statusBarY, koi.winWidth(), StatusBarHeight, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.layout.showThemeEditor:
    let
      mainPane = mainPaneRect(a)
      x = mainPane.x1 + mainPane.w
      y = mainPane.y1
      w = ThemePaneWidth
      h = mainPane.h

    renderThemeEditorPane(x, y, w, h, a)

  renderDialogs(a)

  a.ui.prevCursor = a.ui.cursor


# vim: et:ts=2:sw=2:fdm=marker
