import std/math
import std/options
import std/strformat
import std/sugar
import std/tables

import glfw
import koi
from koi/utils import lerp, invLerp, remap
import nanovg

import cfghelper
import common
import main/actions_ui
import main/appcontext
import main/keyboard
import main/views/statusbar
import ui/all
import utils/all


using a: var AppContext

let QuickRefTabLabels* = @["General", "Editing", "Interface"]

# {{{ Quick keyboard reference definitions

proc sc(sc: AppShortcut): QuickRefItem =
  QuickRefItem(kind: qkShortcut, shortcut: sc)

proc sc(sc: seq[AppShortcut], sepa = '/'; a): QuickRefItem =
  let shortcuts = collect:
    for s in sc: a.keys.shortcuts[s][0]

  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: shortcuts, sepa: sepa)

proc sc(sc: KeyShortcut): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: @[sc])

proc sc(sc: seq[KeyShortcut], sepa = '/'): QuickRefItem =
  QuickRefItem(kind: qkKeyShortcuts, keyShortcuts: sc, sepa: sepa)

proc csc(s: seq[string]): QuickRefItem =
  QuickRefItem(kind: qkCustomShortcuts, customShortcuts: s)

proc desc(s: string): QuickRefItem =
  QuickRefItem(kind: qkDescription, description: s)

const QuickRefSepa = QuickRefItem(kind: qkSeparator)

# {{{ mkQuickRefGeneral()
func mkQuickRefGeneral*(a): seq[seq[QuickRefItem]] =
  @[
    @[
      scShowAboutDialog.sc,      "Show about dialog".desc,
      scToggleQuickReference.sc, "Toggle quick keyboard reference".desc,
      scOpenUserManual.sc,       "Open user manual in browser".desc,
      scEditPreferences.sc,      "Preferences".desc,
      QuickRefSepa,

      scNewMap.sc,            "New map".desc,
      scOpenMap.sc,           "Open map".desc,
      scSaveMap.sc,           "Save map".desc,
      scSaveMapAs.sc,         "Save map as".desc,
      scEditMapProps.sc,      "Edit map properties".desc,
      QuickRefSepa,

      scNewLevel.sc,          "New level".desc,
      scEditLevelProps.sc,    "Edit level properties".desc,
      scEditRegionProps.sc,   "Edit region properties".desc,
      scDeleteLevel.sc,       "Delete level".desc,
      QuickRefSepa,

      scPreviousLevel.sc,     "Previous level".desc,
      scNextLevel.sc,         "Next level".desc,
    ],
    @[
      scUndo.sc,              "Undo last action".desc,
      scRedo.sc,              "Redo last action".desc,

      @[scZoomIn,
        scZoomOut].sc(a=a),   "Zoom in/out".desc,
      QuickRefSepa,

      scToggleWalkMode.sc,        "Toggle walk mode".desc,
      scToggleWasdMode.sc,        "Toggle WASD mode".desc,
      scToggleCellCoords.sc,      "Toggle cell coordinates".desc,
      scToggleCurrentNotePane.sc, "Toggle current note pane".desc,
      scToggleNotesListPane.sc,   "Toggle notes list pane".desc,
      scToggleToolsPane.sc,       "Toggle tools pane".desc,
      scToggleTitleBar.sc,        "Toggle title bar".desc,
      QuickRefSepa,

      scShowNoteTooltip.sc,       "Show note tooltip".desc,
      scShowLinkLines.sc,         "Show all link lines".desc,
      QuickRefSepa,

      scPreviousTheme.sc,     "Previous theme".desc,
      scNextTheme.sc,         "Next theme".desc,
      scReloadTheme.sc,       "Reload current theme".desc,
      scToggleThemeEditor.sc, "Toggle theme editor".desc,
    ]
  ]

# }}}
# {{{ mkQuickRefEditing()
func mkQuickRefEditing*(a): seq[seq[QuickRefItem]] =
  @[
    @[
      scExcavateTunnel.sc,      "Excavate (draw) tunnel".desc,
      scEraseCell.sc,           "Erase cell (clear floor & walls)".desc,
      scDrawClearFloor.sc,      "Draw/clear floor".desc,

      scRotateFloorClockwise.sc,
      "Rotate floor clockwise".desc,

      scRotateFloorAntiClockwise.sc,
      "Rotate floor anti-clockwise".desc,
      QuickRefSepa,

      scDrawWall.sc,            "Draw/clear wall".desc,
      scDrawSpecialWall.sc,     "Draw/clear special wall".desc,

      @[scPreviousSpecialWall,
        scNextSpecialWall].sc(a=a), "Previous/next special wall".desc,
      QuickRefSepa,

      @[scPreviousFloorColor,
        scNextFloorColor].sc(a=a), "Previous/next floor colour".desc,

      scSetFloorColor.sc,       "Set floor colour".desc,
      scPickFloorColor.sc,      "Pick floor colour".desc,

      @[KeyShortcut(key: key1, mods: {a.keys.primaryModKey}),
        KeyShortcut(key: key9, mods: {})].sc(sepa='-'),
      "Set floor colour 1-9".desc,

      scSelectFloorColor10.sc,  "Set floor colour 10".desc,

      QuickRefSepa,

      scEraseTrail.sc,          "Erase trail".desc,
      scToggleDrawTrail.sc,     "Toggle trail mode".desc,
      scExcavateTrail.sc,       "Excavate trail in current level".desc,
      scClearTrail.sc,          "Clear trail in current level".desc,
      QuickRefSepa,

      scMarkSelection.sc,       "Enter select (mark) mode".desc,
      scPaste.sc,               "Paste copy buffer contents".desc,
      scPastePreview.sc,        "Enter paste preview mode".desc,
      QuickRefSepa,

      scEditNote.sc,            "Add or edit note".desc,
      scEraseNote.sc,           "Erase note".desc,
      QuickRefSepa,
    ],
    @[
      scEditLabel.sc,           "Add or edit label".desc,
      scEraseLabel.sc,          "Erase label".desc,
      QuickRefSepa,

      scJumpToLinkedCell.sc,    "Jump to other side of link".desc,
      scLinkCell.sc,            "Set link destination".desc,

      # TODO
#      scUnlinkCell.sc,          "Unlink cell".desc,
      QuickRefSepa,

      scResizeLevel.sc,         "Resize level".desc,
      scNudgePreview.sc,        "Nudge level".desc,
      QuickRefSepa,

      @[scCycleFloorGroup1Forward,
        scCycleFloorGroup1Backward].sc(a=a), "Cycle door".desc,

      @[scCycleFloorGroup2Forward,
        scCycleFloorGroup2Backward].sc(a=a), "Cycle special door".desc,

      @[scCycleFloorGroup3Forward,
        scCycleFloorGroup3Backward].sc(a=a), "Cycle pressure plate".desc,

      @[scCycleFloorGroup4Forward,
        scCycleFloorGroup4Backward].sc(a=a), "Cycle pit".desc,

      @[scCycleFloorGroup5Forward,
        scCycleFloorGroup5Backward].sc(a=a), "Cycle special".desc,

      @[scCycleFloorGroup6Forward,
        scCycleFloorGroup6Backward].sc(a=a), "Cycle entry/exit".desc,

      @[scCycleFloorGroup7Forward,
        scCycleFloorGroup7Backward].sc(a=a), "Cycle bridge/arrow".desc,

      @[scCycleFloorGroup8Forward,
        scCycleFloorGroup8Backward].sc(a=a), "Cycle column/statue".desc,

      QuickRefSepa,

      scSelectSpecialWall1.sc,  "Set special wall: Open door".desc,
      scSelectSpecialWall2.sc,  "Set special wall: Locked door".desc,
      scSelectSpecialWall3.sc,  "Set special wall: Archway".desc,
      scSelectSpecialWall4.sc,  "Set special wall: Secret door".desc,
      scSelectSpecialWall5.sc,  "Set special wall: One-way door".desc,
      scSelectSpecialWall6.sc,  "Set special wall: Illusory wall".desc,
      scSelectSpecialWall7.sc,  "Set special wall: Invisible wall".desc,
      scSelectSpecialWall8.sc,  "Set special wall: Lever".desc,
      scSelectSpecialWall9.sc,  "Set special wall: Niche".desc,
      scSelectSpecialWall10.sc, "Set special wall: Statue".desc,
      scSelectSpecialWall11.sc, "Set special wall: Keyhole".desc,
      scSelectSpecialWall12.sc, "Set special wall: Writing".desc,
    ]
  ]

# }}}
# {{{ mkQuickRefInterface()
func mkQuickRefInterface*(a): seq[seq[QuickRefItem]] =
  @[
    @[
      @[fmt"Ctrl{HairSp}+{HairSp}{IconArrowsHoriz}"].csc,
      "Move between tabs in dialog".desc,

      @[KeyShortcut(key: key1, mods: {mkCtrl}),
        KeyShortcut(key: key9, mods: {})].sc(sepa='-'),
      "Select tab 1-9 in dialog".desc,
      QuickRefSepa,

      KeyShortcut(key: keyTab, mods: {mkShift}).sc,
      "Previous text input field".desc,

      scNextTextField.sc, "Next text input field".desc,
      QuickRefSepa,

      @[fmt"{IconArrowsAll}"].csc, "Change radio button selection".desc,
      QuickRefSepa,

      scAccept.sc,  "Confirm (OK, Save, etc.)".desc,
      scCancel.sc,  "Cancel".desc,
      scDiscard.sc, "Discard".desc,
    ],
    @[
      scSaveLayout1.sc, "Save window layout 1".desc,
      scSaveLayout2.sc, "Save window layout 2".desc,
      scSaveLayout3.sc, "Save window layout 3".desc,
      scSaveLayout4.sc, "Save window layout 4".desc,
      QuickRefSepa,

      scRestoreLayout1.sc, "Restore window layout 1".desc,
      scRestoreLayout2.sc, "Restore window layout 2".desc,
      scRestoreLayout3.sc, "Restore window layout 3".desc,
      scRestoreLayout4.sc, "Restore window layout 4".desc,
      QuickRefSepa,

      scResetUIScaling.sc, "Reset interface scaling".desc
    ]
  ]

# }}}

func mkQuickRefShortcuts*(a): seq[seq[seq[QuickRefItem]]] =
  @[
    mkQuickRefGeneral(a),
    mkQuickRefEditing(a),
    mkQuickRefInterface(a)
  ]


proc updateQuickRefShortcuts*(a) =
  # Call this after main/keyboard.updateShortcuts(a). Can't be called from
  # there because quickref imports keyboard (would cycle).
  a.keys.quickRefShortcuts = mkQuickRefShortcuts(a)

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
# {{{ handleQuickRefKeyEvents()

proc handleQuickRefKeyEvents*(a) =
  if hasKeyEvent():
    let ke = koi.currEvent()

    a.quickRef.activeTab = handleTabNavigation(ke, a.quickRef.activeTab,
                                               QuickRefTabLabels.high, a)

    if   ke.isShortcutDown(scReloadTheme, a):   reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme, a): selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme, a):     selectNextTheme(a)

    elif ke.isShortcutDown(scOpenUserManual, a):    openUserManual(a.paths.manualDir)
    elif ke.isShortcutDown(scToggleThemeEditor, a): toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference, a) or
         ke.isShortcutDown(scAccept, a) or
         ke.isShortcutDown(scCancel, a) or
         isKeyDown(keySpace):

      a.ui.showQuickReference = false
      clearStatusMessage(a)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
