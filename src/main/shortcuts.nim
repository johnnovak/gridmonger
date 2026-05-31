# shortcuts
#
# AppShortcut enum (the canonical list of user-facing keyboard actions) and
# the data types used to describe shortcuts in the Quick Reference overlay.
# Side effects: none (pure data + type definitions).
#
# Pure helpers (DefaultAppShortcuts table, setYubn/mapCtrl variants, toStr
# overloads) currently still live in main.nim; they'll migrate here in
# follow-up commits. AppContext-aware shortcut procs (updateShortcuts,
# checkShortcut, sc/toStr overloads taking `a`) belong in main/keyboard.nim.

import koi  # KeyShortcut


# {{{ AppShortcut
type AppShortcut* = enum
  # General
  scNextTextField
  scAccept
  scCancel
  scDiscard
  scUndo
  scRedo

  # Maps
  scNewMap
  scOpenMap
  scSaveMap
  scSaveMapAs
  scEditMapProps

  # Levels
  scNewLevel
  scDeleteLevel
  scEditLevelProps
  scResizeLevel

  # Regions
  scEditRegionProps

  # Themes
  scReloadTheme
  scPreviousTheme
  scNextTheme

  # Editing
  scToggleWalkMode
  scToggleWasdMode
  scToggleDrawTrail
  scTogglePasteWraparound

  scCycleFloorGroup1Forward
  scCycleFloorGroup2Forward
  scCycleFloorGroup3Forward
  scCycleFloorGroup4Forward
  scCycleFloorGroup5Forward
  scCycleFloorGroup6Forward
  scCycleFloorGroup7Forward
  scCycleFloorGroup8Forward

  scCycleFloorGroup1Backward
  scCycleFloorGroup2Backward
  scCycleFloorGroup3Backward
  scCycleFloorGroup4Backward
  scCycleFloorGroup5Backward
  scCycleFloorGroup6Backward
  scCycleFloorGroup7Backward
  scCycleFloorGroup8Backward

  scExcavateTunnel
  scEraseCell
  scDrawClearFloor
  scRotateFloorClockwise
  scRotateFloorAntiClockwise

  scSetFloorColor
  scPickFloorColor
  scPreviousFloorColor
  scNextFloorColor

  scSelectFloorColor1
  scSelectFloorColor2
  scSelectFloorColor3
  scSelectFloorColor4
  scSelectFloorColor5
  scSelectFloorColor6
  scSelectFloorColor7
  scSelectFloorColor8
  scSelectFloorColor9
  scSelectFloorColor10

  scDrawWall
  scDrawWallRepeat
  scDrawSpecialWall
  scPreviousSpecialWall
  scNextSpecialWall

  scSelectSpecialWall1
  scSelectSpecialWall2
  scSelectSpecialWall3
  scSelectSpecialWall4
  scSelectSpecialWall5
  scSelectSpecialWall6
  scSelectSpecialWall7
  scSelectSpecialWall8
  scSelectSpecialWall9
  scSelectSpecialWall10
  scSelectSpecialWall11
  scSelectSpecialWall12

  scEraseTrail
  scExcavateTrail
  scClearTrail

  scJumpToLinkedCell
  scLinkCell
  # TODO
#  scUnlinkCell

  scPreviousLevel
  scNextLevel

  scZoomIn
  scZoomOut

  scMarkSelection
  scPaste
  scPastePreview
  scNudgePreview
  scPasteAccept

  scEditNote
  scEraseNote
  scEditLabel
  scEraseLabel

  scShowNoteTooltip
  scShowLinkLines

  # Select mode
  scSelectionDraw
  scSelectionErase
  scSelectionAll
  scSelectionNone
  scSelectionAddRect
  scSelectionSubRect
  scSelectionCopy
  scSelectionMove
  scSelectionEraseArea
  scSelectionFillArea
  scSelectionSurroundArea
  scSelectionSetFloorColorArea
  scSelectionCropArea

  # Layout
  scToggleCellCoords
  scToggleCurrentNotePane
  scToggleNotesListPane
  scToggleToolsPane
  scToggleThemeEditor
  scToggleTitleBar

  scSaveLayout1
  scSaveLayout2
  scSaveLayout3
  scSaveLayout4

  scRestoreLayout1
  scRestoreLayout2
  scRestoreLayout3
  scRestoreLayout4

  scResetUIScaling

  # Misc
  scShowAboutDialog
  scOpenUserManual
  scEditPreferences
  scToggleQuickReference

# }}}
# {{{ QuickRefItem types
type
  QuickRefItemKind* = enum
    qkShortcut, qkKeyShortcuts, qkCustomShortcuts, qkDescription, qkSeparator

  QuickRefItem* = object
    sepa*: char
    case kind*: QuickRefItemKind
    of qkShortcut:        shortcut*:        AppShortcut
    of qkKeyShortcuts:    keyShortcuts*:    seq[KeyShortcut]
    of qkCustomShortcuts: customShortcuts*: seq[string]
    of qkDescription:     description*:     string
    of qkSeparator:       discard

# }}}

# vim: et:ts=2:sw=2:fdm=marker
