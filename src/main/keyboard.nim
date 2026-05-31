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
import ui/all


using a: var AppContext


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

  # NOTE: callers must follow this with `updateQuickRefShortcuts(a)` from
  # panes/quickref. We can't call it here because that would be a cycle
  # (quickref.nim imports keyboard.nim).

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
# {{{ handleTabNavigation()
proc handleTabNavigation*(ke: Event,
                         currTabIndex, maxTabIndex: Natural; a): Natural =
  result = currTabIndex

  if ke.isKeyDown(MoveKeysStandard.left, {mkCtrl}):
    if    currTabIndex > 0: result = currTabIndex - 1
    else: result = maxTabIndex

  elif ke.isKeyDown(MoveKeysStandard.right, {mkCtrl}):
    if    currTabIndex < maxTabIndex: result = currTabIndex + 1
    else: result = 0

  else:
    let i = ord(ke.key) - ord(key1)
    if ke.action == kaDown and mkCtrl in ke.mods and
      i >= 0 and i <= maxTabIndex:
      result = i

# }}}
# }}}


# vim: et:ts=2:sw=2:fdm=marker
