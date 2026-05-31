# keyboard
#
# Keyboard shortcut definitions, Quick Reference data construction, and the
# event-matching helpers (checkShortcut, isShortcutDown/Up, primaryModDown).
# Two flavours of code live here together:
#   - Pure data: DefaultAppShortcuts table, MoveKeys/WalkKeys structures and
#     constants, setYubn/mapCtrl/addStandardMac variants, toStr overloads
#     without AppContext.
#   - AppContext-aware: updateShortcuts, updateWalkKeys, mkQuickRef*, the
#     sc/toStr overloads taking `a`, event-matching helpers.
# Side effects: none beyond mutating AppContext fields. The event-matching
# procs read from koi events that are passed in as values, so they're
# testable without live input devices.

import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/tables

import glfw
import koi

import common              # HairSp
import main/appcontext
import ui/icons             # IconArrowsHoriz, IconArrowsAll


using a: var AppContext


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

# }}}

# {{{ Keyboard shortcuts

type MoveKeys* = object
  left*, right*, up*, down*: set[Key]

const
  MoveKeysStandard* = MoveKeys(
    left:  {keyLeft,  keyH, keyKp4},
    right: {keyRight, keyL, keyKp6},
    up:    {keyUp,    keyK, keyKp8},
    down:  {keyDown,  keyJ, keyKp2, keyKp5}
  )

  MoveKeysWasd* = MoveKeys(
    left:  MoveKeysStandard.left  + {keyA},
    right: MoveKeysStandard.right + {keyD},
    up:    MoveKeysStandard.up    + {keyW},
    down:  MoveKeysStandard.down  + {Key.keyS}
  )

type DiagonalMoveKeys* = object
  upLeft*, upRight*, downLeft*, downRight*: set[Key]

const
  DiagonalMoveKeysCursor* = DiagonalMoveKeys(
    upLeft:    {keyY, keyKp7},
    upRight:   {keyU, keyKp9},
    downLeft:  {keyB, keyKp1},
    downRight: {keyN, keyKp3}
  )

func `+`(a: WalkKeys, b: WalkKeys): WalkKeys =
  result = WalkKeys(
    forward:     a.forward     + b.forward,
    backward:    a.backward    + b.backward,
    strafeLeft:  a.strafeLeft  + b.strafeLeft,
    strafeRight: a.strafeRight + b.strafeRight,
    turnLeft:    a.turnLeft    + b.turnLeft,
    turnRight:   a.turnRight   + b.turnRight
  )

const
  WalkKeysCursorStrafe* = WalkKeys(
    forward:     {keyUp},
    backward:    {keyDown},
    strafeLeft:  {keyLeft},
    strafeRight: {keyRight},

    # Alt+Left/Right for turning is handled as a special case
    turnLeft:    {},
    turnRight:   {}
  )

  WalkKeysCursorTurn* = WalkKeys(
    forward:     {keyUp},
    backward:    {keyDown},
    turnLeft:    {keyLeft},
    turnRight:   {keyRight},

    # Alt+Left/Right for strafing is handled as a special case
    strafeLeft:  {},
    strafeRight: {}
  )

  WalkKeysKeypad* = WalkKeys(
    forward:     {keyKp8},
    backward:    {keyKp2, keyKp5},
    strafeLeft:  {keyKp4},
    strafeRight: {keyKp6},
    turnLeft:    {keyKp7},
    turnRight:   {keyKp9}
  )

  WalkKeysWasd* = WalkKeys(
    forward:     {keyW},
    backward:    {keyS},
    strafeLeft:  {keyA},
    strafeRight: {keyD},
    turnLeft:    {keyQ},
    turnRight:   {keyE}
  )

func mkWalkKeysCursor*(mode: WalkCursorMode): WalkKeys =
  if mode == wcmStrafe:
    result = WalkKeysKeypad + WalkKeysCursorStrafe
  elif mode == wcmTurn:
    result = WalkKeysKeypad + WalkKeysCursorTurn

func mkWalkKeysWasd*(walkKeysCursor: WalkKeys): WalkKeys =
  walkKeysCursor + WalkKeysWasd

proc updateWalkKeys*(a) =
  a.keys.walkKeysCursor = mkWalkKeysCursor(a.prefs.walkCursorMode)
  a.keys.walkKeysWasd   = mkWalkKeysWasd(a.keys.walkKeysCursor)

const
  VimMoveKeys*            = {keyH, keyJ, keyK, keyL}
  AllWasdLetterKeys*      = {keyQ, keyW, keyE, keyA, keyS, keyD}
  AllWasdKeypadKeys*      = {keyKp2, keyKp4, keyKp5, keyKp6, keyKp7, keyKp8, keyKp9}
  DiagonalMoveLetterKeys* = {keyY, keyU, keyB, keyN}


# {{{ DefaultAppShortcuts

# The default shortcuts use Ctrl and Ctrl+Alt (suitable for Windows and Linux)

let DefaultAppShortcuts* = {
  # General
  scNextTextField:      @[mkKeyShortcut(keyTab,           {})],

  scAccept:             @[mkKeyShortcut(keyEnter,         {}),
                          mkKeyShortcut(keyKpEnter,       {})],

  scCancel:             @[mkKeyShortcut(keyEscape,        {}),
                          mkKeyShortcut(keyLeftBracket,   {mkCtrl})],

  scDiscard:            @[mkKeyShortcut(keyD,             {mkAlt})],

  scUndo:               @[mkKeyShortcut(keyU,             {}),
                          mkKeyShortcut(keyU,             {mkCtrl}),
                          mkKeyShortcut(keyZ,             {mkCtrl})],

  scRedo:               @[mkKeyShortcut(keyR,             {mkCtrl}),
                          mkKeyShortcut(keyY,             {mkCtrl}),
                          mkKeyShortcut(keyZ,             {mkCtrl, mkShift})],

  # Maps
  scNewMap:             @[mkKeyShortcut(keyN,             {mkCtrl, mkAlt})],
  scOpenMap:            @[mkKeyShortcut(keyO,             {mkCtrl})],
  scSaveMap:            @[mkKeyShortcut(keyS,             {mkCtrl})],
  scSaveMapAs:          @[mkKeyShortcut(keyS,             {mkCtrl, mkShift})],
  scEditMapProps:       @[mkKeyShortcut(keyP,             {mkCtrl, mkAlt})],

  # Levels
  scNewLevel:              @[mkKeyShortcut(keyN,          {mkCtrl})],
  scDeleteLevel:           @[mkKeyShortcut(keyD,          {mkCtrl})],
  scEditLevelProps:        @[mkKeyShortcut(keyP,          {mkCtrl})],
  scResizeLevel:           @[mkKeyShortcut(keyE,          {mkCtrl})],

  # Regions
  scEditRegionProps:    @[mkKeyShortcut(keyR,             {mkCtrl, mkAlt})],

  # Themes
  scReloadTheme:        @[mkKeyShortcut(keyHome,          {mkCtrl})],
  scPreviousTheme:      @[mkKeyShortcut(keyPageUp,        {mkCtrl})],
  scNextTheme:          @[mkKeyShortcut(keyPageDown,      {mkCtrl})],

  # Editing
  scToggleWalkMode:            @[mkKeyShortcut(keyGraveAccent, {})],
  scToggleWasdMode:            @[mkKeyShortcut(keyTab,         {})],
  scToggleDrawTrail:           @[mkKeyShortcut(keyT,           {})],
  scTogglePasteWraparound:     @[mkKeyShortcut(keyW,           {})],

  scCycleFloorGroup1Forward:   @[mkKeyShortcut(key1,      {})],
  scCycleFloorGroup2Forward:   @[mkKeyShortcut(key2,      {})],
  scCycleFloorGroup3Forward:   @[mkKeyShortcut(key3,      {})],
  scCycleFloorGroup4Forward:   @[mkKeyShortcut(key4,      {})],
  scCycleFloorGroup5Forward:   @[mkKeyShortcut(key5,      {})],
  scCycleFloorGroup6Forward:   @[mkKeyShortcut(key6,      {})],
  scCycleFloorGroup7Forward:   @[mkKeyShortcut(key7,      {})],
  scCycleFloorGroup8Forward:   @[mkKeyShortcut(key8,      {})],

  scCycleFloorGroup1Backward:  @[mkKeyShortcut(key1,      {mkShift})],
  scCycleFloorGroup2Backward:  @[mkKeyShortcut(key2,      {mkShift})],
  scCycleFloorGroup3Backward:  @[mkKeyShortcut(key3,      {mkShift})],
  scCycleFloorGroup4Backward:  @[mkKeyShortcut(key4,      {mkShift})],
  scCycleFloorGroup5Backward:  @[mkKeyShortcut(key5,      {mkShift})],
  scCycleFloorGroup6Backward:  @[mkKeyShortcut(key6,      {mkShift})],
  scCycleFloorGroup7Backward:  @[mkKeyShortcut(key7,      {mkShift})],
  scCycleFloorGroup8Backward:  @[mkKeyShortcut(key8,      {mkShift})],

  scExcavateTunnel:            @[mkKeyShortcut(keyD,      {})],
  scEraseCell:                 @[mkKeyShortcut(keyE,      {})],
  scDrawClearFloor:            @[mkKeyShortcut(keyF,      {})],
  scRotateFloorClockwise:      @[mkKeyShortcut(keyO,      {})],
  scRotateFloorAntiClockwise:  @[mkKeyShortcut(keyO,      {mkShift})],

  scSetFloorColor:             @[mkKeyShortcut(keyC,      {})],
  scPickFloorColor:            @[mkKeyShortcut(keyI,      {})],
  scPreviousFloorColor:        @[mkKeyShortcut(keyComma,  {})],
  scNextFloorColor:            @[mkKeyShortcut(keyPeriod, {})],

  scSelectFloorColor1:         @[mkKeyShortcut(key1,      {mkCtrl})],
  scSelectFloorColor2:         @[mkKeyShortcut(key2,      {mkCtrl})],
  scSelectFloorColor3:         @[mkKeyShortcut(key3,      {mkCtrl})],
  scSelectFloorColor4:         @[mkKeyShortcut(key4,      {mkCtrl})],
  scSelectFloorColor5:         @[mkKeyShortcut(key5,      {mkCtrl})],
  scSelectFloorColor6:         @[mkKeyShortcut(key6,      {mkCtrl})],
  scSelectFloorColor7:         @[mkKeyShortcut(key7,      {mkCtrl})],
  scSelectFloorColor8:         @[mkKeyShortcut(key8,      {mkCtrl})],
  scSelectFloorColor9:         @[mkKeyShortcut(key9,      {mkCtrl})],
  scSelectFloorColor10:        @[mkKeyShortcut(key0,      {mkCtrl})],

  scDrawWall:                  @[mkKeyShortcut(keyW,      {})],
  scDrawSpecialWall:           @[mkKeyShortcut(keyR,      {})],

  scDrawWallRepeat:            @[mkKeyShortcut(keyLeftShift,  {}),
                                 mkKeyShortcut(keyRightShift, {})],

  scPreviousSpecialWall:       @[mkKeyShortcut(keyLeftBracket,  {})],
  scNextSpecialWall:           @[mkKeyShortcut(keyRightBracket, {})],

  scSelectSpecialWall1:        @[mkKeyShortcut(key1,      {mkAlt})],
  scSelectSpecialWall2:        @[mkKeyShortcut(key2,      {mkAlt})],
  scSelectSpecialWall3:        @[mkKeyShortcut(key3,      {mkAlt})],
  scSelectSpecialWall4:        @[mkKeyShortcut(key4,      {mkAlt})],
  scSelectSpecialWall5:        @[mkKeyShortcut(key5,      {mkAlt})],
  scSelectSpecialWall6:        @[mkKeyShortcut(key6,      {mkAlt})],
  scSelectSpecialWall7:        @[mkKeyShortcut(key7,      {mkAlt})],
  scSelectSpecialWall8:        @[mkKeyShortcut(key8,      {mkAlt})],
  scSelectSpecialWall9:        @[mkKeyShortcut(key9,      {mkAlt})],
  scSelectSpecialWall10:       @[mkKeyShortcut(key0,      {mkAlt})],
  scSelectSpecialWall11:       @[mkKeyShortcut(keyMinus,  {mkAlt})],
  scSelectSpecialWall12:       @[mkKeyShortcut(keyEqual,  {mkAlt})],

  scEraseTrail:                @[mkKeyShortcut(keyX,      {})],
  scExcavateTrail:             @[mkKeyShortcut(keyD,      {mkCtrl, mkAlt})],
  scClearTrail:                @[mkKeyShortcut(keyX,      {mkCtrl, mkAlt})],

  scJumpToLinkedCell:          @[mkKeyShortcut(keyG,      {})],
  scLinkCell:                  @[mkKeyShortcut(keyG,      {mkShift})],
  # TODO
#  scUnlinkCell:                @[mkKeyShortcut(keyM,      {mkShift})],

  scPreviousLevel:             @[mkKeyShortcut(keyPageUp,     {}),
                                 mkKeyShortcut(keyKpSubtract, {}),
                                 mkKeyShortcut(keyMinus,      {mkCtrl})],

  scNextLevel:                 @[mkKeyShortcut(keyPageDown,   {}),
                                 mkKeyShortcut(keyKpAdd,      {}),
                                 mkKeyShortcut(keyEqual,      {mkCtrl})],

  scZoomIn:                    @[mkKeyShortcut(keyEqual,      {})],
  scZoomOut:                   @[mkKeyShortcut(keyMinus,      {})],

  scMarkSelection:             @[mkKeyShortcut(keyM,          {})],

  scPaste:                     @[mkKeyShortcut(keyP,          {})],
  scPastePreview:              @[mkKeyShortcut(keyP,          {mkShift})],
  scNudgePreview:              @[mkKeyShortcut(keyG,          {mkCtrl})],
  scPasteAccept:               @[mkKeyShortcut(keyP,          {}),
                                 mkKeyShortcut(keyEnter,      {}),
                                 mkKeyShortcut(keyKpEnter,    {})],

  scEditNote:                  @[mkKeyShortcut(keyN,          {}),
                                 mkKeyShortcut(keySemicolon,  {})],

  scEraseNote:                 @[mkKeyShortcut(keyN,          {mkShift}),
                                 mkKeyShortcut(keySemicolon,  {mkShift})],

  scEditLabel:                 @[mkKeyShortcut(keyT,          {mkCtrl})],
  scEraseLabel:                @[mkKeyShortcut(keyT,          {mkShift})],

  scShowNoteTooltip:           @[mkKeyShortcut(keySpace,      {})],
  scShowLinkLines:             @[mkKeyShortcut(keyApostrophe, {})],

  # Select mode
  scSelectionDraw:               @[mkKeyShortcut(keyD,    {})],
  scSelectionErase:              @[mkKeyShortcut(keyE,    {})],
  scSelectionAll:                @[mkKeyShortcut(keyA,    {})],

  scSelectionNone:               @[mkKeyShortcut(keyU,    {}),
                                   mkKeyShortcut(keyX,    {})],

  scSelectionAddRect:            @[mkKeyShortcut(keyR,    {})],
  scSelectionSubRect:            @[mkKeyShortcut(keyS,    {})],

  scSelectionCopy:               @[mkKeyShortcut(keyC,    {}),
                                   mkKeyShortcut(keyY,    {})],

  scSelectionMove:               @[mkKeyShortcut(keyM,    {mkCtrl})],
  scSelectionEraseArea:          @[mkKeyShortcut(keyE,    {mkCtrl})],
  scSelectionFillArea:           @[mkKeyShortcut(keyF,    {mkCtrl})],
  scSelectionSurroundArea:       @[mkKeyShortcut(keyS,    {mkCtrl})],
  scSelectionSetFloorColorArea:  @[mkKeyShortcut(keyC,    {mkCtrl})],
  scSelectionCropArea:           @[mkKeyShortcut(keyR,    {mkCtrl})],

  # Layout
  scToggleCellCoords:      @[mkKeyShortcut(keyC,          {mkAlt})],
  scToggleCurrentNotePane: @[mkKeyShortcut(keyN,          {mkAlt})],
  scToggleNotesListPane:   @[mkKeyShortcut(keyL,          {mkAlt})],
  scToggleToolsPane:       @[mkKeyShortcut(keyT,          {mkAlt})],
  scToggleThemeEditor:     @[mkKeyShortcut(keyF12,        {})],
  scToggleTitleBar:        @[mkKeyShortcut(keyT,          {mkAlt, mkShift})],

  scSaveLayout1:           @[mkKeyShortcut(keyF5,         {mkShift})],
  scSaveLayout2:           @[mkKeyShortcut(keyF6,         {mkShift})],
  scSaveLayout3:           @[mkKeyShortcut(keyF7,         {mkShift})],
  scSaveLayout4:           @[mkKeyShortcut(keyF8,         {mkShift})],

  scRestoreLayout1:        @[mkKeyShortcut(keyF5,         {})],
  scRestoreLayout2:        @[mkKeyShortcut(keyF6,         {})],
  scRestoreLayout3:        @[mkKeyShortcut(keyF7,         {})],
  scRestoreLayout4:        @[mkKeyShortcut(keyF8,         {})],

  scResetUIScaling:        @[mkKeyShortcut(keyF11,        {mkCtrl})],

  # Misc
  scShowAboutDialog:       @[mkKeyShortcut(keyA,          {mkCtrl})],
  scOpenUserManual:        @[mkKeyShortcut(keyF1,         {})],
  scEditPreferences:       @[mkKeyShortcut(keyU,          {mkCtrl, mkAlt})],
  scToggleQuickReference:  @[mkKeyShortcut(keySlash,      {mkShift})]

}.toTable

# }}}

# {{{ setYubnAppShortcuts()
proc setYubnAppShortcuts*(sc: var Table[AppShortcut, seq[KeyShortcut]]) =
  # Shortcuts that conflicts with the YUBN keys must be removed. All the
  # affected shortcuts have alternatives to they can be invoked even in YUBN
  # mode.

  # Ctrl/Cmd modifiers for jumps are not allowed in YUBN mode as that would
  # conflict with too many shortcuts, but Shift modifiers for panning are
  # allowed.

  # remove keyY mappings
  sc[scSelectionCopy] = @[mkKeyShortcut(keyC, {})]

  # remove keyU mappings
  sc[scUndo]          = @[mkKeyShortcut(keyU, {mkCtrl}),
                          mkKeyShortcut(keyZ, {mkCtrl})]

  sc[scSelectionNone] = @[mkKeyShortcut(keyX, {})]

  # remove keyN mappings
  sc[scEditNote]      = @[mkKeyShortcut(keySemicolon, {})]
  sc[scEraseNote]     = @[mkKeyShortcut(keySemicolon, {mkShift})]

# }}}
# {{{ mapCtrlAltToCtrlShift()
proc mapCtrlAltToCtrlShift*(sc: var Table[AppShortcut, seq[KeyShortcut]]) =
  for appShortcut, keyShortcuts in sc.mpairs:
    if appShortcut == scCancel: continue

    keyShortcuts = keyShortcuts.mapIt:
      if it.mods == {mkCtrl, mkAlt}:
        KeyShortcut(key: it.key, mods: {mkCtrl, mkShift})
      else: it

# }}}
# {{{ mapCtrlToSuper()
proc mapCtrlToSuper*(sc: var Table[AppShortcut, seq[KeyShortcut]]) =
  for appShortcut, keyShortcuts in sc.mpairs:
    # We always leave this one alone for the Vim enthusiasts :)
    if appShortcut == scCancel: continue

    keyShortcuts = keyShortcuts.mapIt:
      if mkCtrl in it.mods:
        KeyShortcut(key: it.key, mods: it.mods - {mkCtrl} + {mkSuper})
      else: it

# }}}
# {{{ addStandardMacShortcuts()
proc addStandardMacShortcuts*(sc: var Table[AppShortcut, seq[KeyShortcut]]) =

  template addUniqueShortcut(appShortcut: AppShortcut, keyShortcut: KeyShortcut) =
    if keyShortcut notin sc[appShortcut]:
      sc[appShortcut].add(keyShortcut)

  sc[scEditPreferences].add(mkKeyShortcut(keyComma, {mkSuper}))

  addUniqueShortcut(scOpenMap,   mkKeyShortcut(keyO, {mkSuper}))
  addUniqueShortcut(scSaveMap,   mkKeyShortcut(keyS, {mkSuper}))
  addUniqueShortcut(scSaveMapAs, mkKeyShortcut(keyS, {mkSuper, mkShift}))

# }}}
# {{{ toStr()
proc toStr*(k: Key): string =
  case k
  of key0..key9: $k
  of keyA..keyZ, keyF1..keyF25: ($k).toUpper

  of keyUnknown:      "???"
  of keySpace:        "Space"
  of keyApostrophe:   "'"
  of keyComma:        ","
  of keyMinus:        "-"
  of keyPeriod:       "."
  of keySlash:        "/"
  of keySemicolon:    ";"
  of keyEqual:        "="
  of keyLeftBracket:  "["
  of keyBackslash:    "\\"
  of keyRightBracket: "]"
  of keyGraveAccent:  "`"

  of keyWorld1:       "World1"
  of keyWorld2:       "World2"
  of keyEscape:       "Esc"
  of keyEnter:        "Enter"
  of keyTab:          "Tab"
  of keyBackspace:    "Bksp"
  of keyInsert:       "Ins"
  of keyDelete:       "Del"
  of keyRight:        "Right"
  of keyLeft:         "Left"
  of keyDown:         "Down"
  of keyUp:           "Up"

  of keyPageUp:       "PgUp"
  of keyPageDown:     "PgDn"
  of keyHome:         "Home"
  of keyEnd:          "End"
  of keyCapsLock:     "CapsLock"
  of keyScrollLock:   "ScrollLock"
  of keyNumLock:      "NumLock"
  of keyPrintScreen:  "PrtSc"
  of keyPause:        "Pause"

  of keyKp0:          "kp0"
  of keyKp1:          "kp1"
  of keyKp2:          "kp2"
  of keyKp3:          "kp3"
  of keyKp4:          "kp4"
  of keyKp5:          "kp5"
  of keyKp6:          "kp6"
  of keyKp7:          "kp7"
  of keyKp8:          "kp8"
  of keyKp9:          "kp9"
  of keyKpDecimal:    "kp."
  of keyKpDivide:     "kp/"
  of keyKpMultiply:   "kp*"
  of keyKpSubtract:   "kp-"
  of keyKpAdd:        "kp+"
  of keyKpEnter:      "kpEnter"
  of keyKpEqual:      "kp="

  of keyLeftShift:    "LShift"
  of keyLeftControl:  "LCtrl"
  of keyLeftAlt:      "LAlt"
  of keyLeftSuper:    "LSuper"
  of keyRightShift:   "RShift"
  of keyRightControl: "RCtrl"
  of keyRightAlt:     "RAlt"
  of keyRightSuper:   "RSuper"
  of keyMenu:         "Menu"


proc toStr*(k: KeyShortcut): string =
  var s: seq[string] = @[]
  if   mkSuper in k.mods: s.add("Cmd")
  elif mkCtrl  in k.mods: s.add("Ctrl")

  if mkShift in k.mods: s.add("Shift")
  if mkAlt   in k.mods: s.add("Alt")

  s.add(k.key.toStr)
  s.join(fmt"{HairSp}+{HairSp}")


proc toStr*(sc: AppShortcut; a; idx = -1): string =
  if idx == -1:
    var s = collect:
      for k in a.keys.shortcuts[sc]: k.toStr
    result = s.join(fmt"{HairSp}/{HairSp}")
  else:
    result = a.keys.shortcuts[sc][idx].toStr
# }}}

# }}}

# {{{ Key event helpers

# {{{ updateShortcuts()
proc updateShortcuts*(a) =
  # The default shortcuts use Ctrl and Ctrl+Alt
  a.keys.shortcuts     = DefaultAppShortcuts
  a.keys.primaryModKey = mkCtrl

  if a.prefs.yubnMovementKeys:
    a.keys.shortcuts.setYubnAppShortcuts

  when defined(macosx):
    case a.prefs.modifierKeyMode
    of mkmControlAlt: discard

    of mkmCommandShift:
      a.keys.primaryModKey = mkSuper
      a.keys.shortcuts.mapCtrlAltToCtrlShift
      a.keys.shortcuts.mapCtrlToSuper

    # Make the standard Cmd-based Open, Save, Save As, and Preferences
    # shortcuts always available, even in Ctrl+Alt modifier mode.
    a.keys.shortcuts.addStandardMacShortcuts

  a.keys.quickRefShortcuts = mkQuickRefShortcuts(a)

# }}}
# {{{ hasKeyEvent()
proc hasKeyEvent*: bool =
  koi.hasEvent() and koi.currEvent().kind == ekKey

# }}}
# {{{ isKeyDown()
proc isKeyDown*(ev: Event, keys: set[Key], mods: set[ModifierKey] = {},
               repeat=false): bool =

  let a = if repeat: {kaDown, kaRepeat} else: {kaDown}

  let numKey = ev.key in keyKp0..keyKpEqual
  let eventMods = if numKey: ev.mods - {mkCapsLock}
                  else:      ev.mods - {mkCapsLock, mkNumLock}

  ev.action in a and ev.key in keys and eventMods == mods


proc isKeyDown*(ev: Event, key: Key,
               mods: set[ModifierKey] = {}, repeat=false): bool =
  isKeyDown(ev, {key}, mods, repeat)

# }}}
# {{{ checkShortcut()
proc checkShortcut*(ev: Event, shortcuts: set[AppShortcut],
                   actions: set[KeyAction], ignoreMods=false; a): bool =
  if ev.kind == ekKey:
    if ev.action in actions:
      let currShortcut = mkKeyShortcut(ev.key, ev.mods)
      for sc in shortcuts:
        if ignoreMods:
          for asc in a.keys.shortcuts[sc]:
            if asc.key == ev.key:
              return true
        else:
          if currShortcut in a.keys.shortcuts[sc]:
            return true

# }}}
# {{{ isShortcutDown()
proc isShortcutDown*(ev: Event, shortcuts: set[AppShortcut]; a;
                    repeat=false, ignoreMods=false): bool =
  let actions = if repeat: {kaDown, kaRepeat} else: {kaDown}
  checkShortcut(ev, shortcuts, actions, ignoreMods, a)

proc isShortcutDown*(ev: Event, shortcut: AppShortcut; a;
                    repeat=false, ignoreMods=false): bool =
  isShortcutDown(ev, {shortcut}, a, repeat, ignoreMods)

# }}}
# {{{ isShortcutUp()
proc isShortcutUp*(ev: Event, shortcuts: set[AppShortcut]; a): bool =
  checkShortcut(ev, shortcuts, actions={kaUp}, ignoreMods=true, a)

proc isShortcutUp*(ev: Event, shortcut: AppShortcut; a): bool =
  isShortcutUp(ev, {shortcut}, a)

# }}}
# {{{ primaryModDown()
proc primaryModDown*(a): bool =
  if   a.keys.primaryModKey == mkCtrl:  koi.ctrlDown()
  elif a.keys.primaryModKey == mkSuper: koi.superDown()
  else: false

# }}}
# }}}


# vim: et:ts=2:sw=2:fdm=marker
