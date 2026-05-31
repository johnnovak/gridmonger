# {{{ Imports

import std/algorithm
import std/httpclient
import std/lenientops
import std/logging as log except Level
import std/macros
import std/math
import std/monotimes
import std/options
import std/os
import std/sequtils
import std/sets
import std/setutils
import std/strformat
import std/strutils except strip, splitWhitespace
import std/sugar
import std/tables
import std/times
import std/unicode

# Libraries
import glad/gl
import glfw

import koi
from koi/utils import lerp, invLerp, remap

import nanovg

when not defined(DEBUG):
  import osdialog

when defined(windows):
  import platform/windows/console

import semver
import with

# Internal
import actions
import appevents
import cfghelper
import cmdline
import common
import ui/csdwindow
import ui/drawlevel
import ui/gfx
import fieldlimits
import ui/icons
import domain/level
import domain/map
import io/persistence
import domain/regions
import domain/selection
import ui/theme
import undomanager
import utils/converters
import utils/hocon
import utils/misc as gmUtils
import utils/naturalsort
import utils/rect
import utils/webbrowser

import main/appcontext
import main/constants
import main/cursor
import main/keyboard
import main/logging
import main/modes
import main/shortcuts
import main/configio
import main/actions_ui
import main/dialogs
import main/mapio
import main/rendering
import main/status_msg
import main/themeio
import main/versioncheck
import main/view

using a: var AppContext

# }}}

# {{{ Resources

when defined(windows):
  const arch = when defined(i386): "32" else: "64"
  {.link: fmt"extras/appicons/windows/gridmonger{arch}.res".}

# }}}

# {{{ Graphics helpers

# {{{ Dialogs
# {{{ Event handling

# {{{ resetManualNoteTooltip()
proc resetManualNoteTooltip(a) =
  with a.ui.manualNoteTooltipState:
    show = false
    mx = -1
    my = -1

# }}}

# {{{ enterDrawWallMode()
proc enterDrawWallMode(specialWall: bool; a) =
  a.ui.editMode = if specialWall: emDrawSpecialWall else: emDrawWall
  a.ui.drawWallRepeatAction = dwaNone

  if specialWall:
    setDrawSpecialWallActionMessage(a)
  else:
    setDrawWallActionMessage(a)

# }}}
# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents(a) =

  # {{{ moveCursorToMousePos()
  proc moveCursorToMousePos(a) =
    alias(dp, a.ui.drawLevelParams)
    alias(ui, a.ui)

    let loc = locationAtMouse(clampToBounds=true, a)
    if loc.isSome:
      resetManualNoteTooltip(a)
      a.ui.cursor = loc.get
      if ui.editMode in {emPastePreview, emMovePreview}:
        dp.selStartRow = ui.cursor.row
        dp.selStartCol = ui.cursor.col

  # }}}
  # {{{ enterPanLevelMode()
  proc enterPanLevelMode(mode: PanLevelMode; a) =
    alias(ui, a.ui)
    ui.prevEditMode = ui.editMode
    ui.editMode = emPanLevel
    ui.mouseDragStartX = koi.mx()
    ui.mouseDragStartY = koi.my()
    ui.panLevelMode = mode

  # }}}
  # {{{ handleMoveCursorOrPanSimple()
  proc handleMoveCursorOrPanSimple(a) =
    if koi.mbLeftDown():
      if koi.ctrlDown():
        enterPanLevelMode(dlmCtrlLeftButton, a)
      else:
        moveCursorToMousePos(a)
    elif koi.mbMiddleDown():
      enterPanLevelMode(dlmMiddleButton, a)

  # }}}
  # {{{ handlePanLevel()
  proc handlePanLevel(a) =
    alias(ui, a.ui)
    alias(dp, a.ui.drawLevelParams)

    let dx = ui.mouseDragStartX - koi.mx()
    let dy = ui.mouseDragStartY - koi.my()

    const SensitivityMin = 10
    const SensitivityMax = 35

    let sensitivity = remap(
      inMin=MinZoomLevel, inMax=MaxZoomLevel,
      outMin=SensitivityMin, outMax=SensitivityMax,
      dp.getZoomLevel.float
    )
    let colSteps = (dx / sensitivity).int
    let rowSteps = (dy / sensitivity).int

    if colSteps == 0: discard
    else:
      ui.mouseDragStartX = koi.mx()
      if colSteps > 0: moveLevelView(East,  colSteps, a)
      else:            moveLevelView(West, -colSteps, a)

    if rowSteps == 0: discard
    else:
      ui.mouseDragStartY = koi.my()
      if rowSteps > 0: moveLevelView(South,  rowSteps, a)
      else:            moveLevelView(North, -rowSteps, a)

    if ui.editMode == emPanLevel and
      ui.prevEditMode in {emPastePreview, emMovePreview}:
      dp.selStartRow = ui.cursor.row
      dp.selStartCol = ui.cursor.col

  # }}}
  # {{{ handlePanLevelExit()
  proc handlePanLevelExit(a) =
    alias(ui, a.ui)
    case ui.panLevelMode
    of dlmCtrlLeftButton:
      if not koi.ctrlDown() or not koi.mbLeftDown():
        ui.editMode = ui.prevEditMode
    of dlmMiddleButton:
      if not koi.mbMiddleDown():
        ui.editMode = ui.prevEditMode

  # }}}

  alias(ui, a.ui)

  # {{{ WASD mode
  #
  # Bit of a misnomer "WASD-mode" consists of the  Q/W/E/A/S/D keys.
  #
  if a.ui.wasdMode:
    case ui.editMode
    of emNormal:
      if koi.mbLeftDown():
        if ui.mouseCanStartExcavate:
          if koi.shiftDown():
            if koi.ctrlDown():
              enterPanLevelMode(dlmCtrlLeftButton, a)
            else:
              moveCursorToMousePos(a)
          else:
            ui.editMode = emExcavateTunnel
            startExcavateTunnelAction(a)
      else:
        ui.mouseCanStartExcavate = true

      if koi.mbRightDown():
        enterDrawWallMode(specialWall=false, a)

      elif koi.mbMiddleDown():
        if koi.shiftDown():
          enterPanLevelMode(dlmMiddleButton, a)
        else:
          ui.editMode = emEraseCell
          startEraseCellsAction(a)

    of emColorFloor, emDrawClearFloor:
      discard

    of emDrawWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)
      else:
        if koi.mbLeftDown():
          enterDrawWallMode(specialWall=true, a)

    of emDrawWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emDrawSpecialWall:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavate=false
        clearStatusMessage(a)
      else:
        if not koi.mbLeftDown():
          enterDrawWallMode(specialWall=false, a)

    of emDrawSpecialWallRepeat:
      if not koi.mbRightDown():
        ui.editMode = emNormal
        ui.mouseCanStartExcavate = false
        clearStatusMessage(a)

    of emEraseCell:
      if not koi.mbMiddleDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emEraseTrail:
      discard

    of emExcavateTunnel:
      if not koi.mbLeftDown():
        ui.editMode = emNormal
        clearStatusMessage(a)

    of emNudgePreview:
      discard

    of emSelect, emSetCellLink, emPastePreview, emMovePreview:
      handleMoveCursorOrPanSimple(a)

    of emSelectDraw, emSelectErase, emSelectRect:
      if koi.mbLeftDown():
        moveCursorToMousePos(a)

    of emSelectJumpToLinkSrc:
      discard

    of emPanLevel:
      handlePanLevel(a)
      handlePanLevelExit(a)

  # }}}
  # {{{ Normal mode
  else:
    case ui.editMode
    of emNormal, emSelect, emSetCellLink, emPastePreview, emMovePreview:
      handleMoveCursorOrPanSimple(a)

    of emSelectDraw, emSelectErase, emSelectRect:
      if koi.mbLeftDown():
        moveCursorToMousePos(a)

    of emPanLevel:
      handlePanLevel(a)
      handlePanLevelExit(a)

    else: discard
  # }}}

# }}}

# {{{ setSelectJumpToLinkActionMessage()
proc setSelectJumpToLinkSrcActionMessage(a) =
  let currIdx = a.ui.jumpToSrcLocationIdx + 1
  let count = a.ui.jumpToSrcLocations.len
  let floor = a.doc.map.getFloor(a.ui.jumpToDestLocation)

  setStatusMessage(IconLink,
                   fmt"Select {linkFloorToString(floor)} " &
                   fmt"source ({currIdx} of {count})",
                   @[IconArrowsAll, "next/prev", "Enter/Esc", "exit"], a)

# }}}
# {{{ handleGlobalKeyEvents()

template toggleOption(opt: untyped, icon, msg, on, off: string; a) =
  opt = not opt
  let state = if opt: on else: off
  setStatusMessage(icon, msg & " " & state, a)

template toggleShowOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="shown", off="hidden", a)

template toggleOnOffOption(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="on", off="off", a)

proc toggleThemeEditor(a) =
  toggleShowOption(a.layout.showThemeEditor, NoIcon, "Theme editor pane", a)

proc showQuickReference(a) =
  a.ui.showQuickReference = true
  setStatusMessage(
    IconQuestion, "Quick keyboard reference",
    @[fmt"Ctrl{HairSp}+{HairSp}{IconArrowsHoriz}",          "switch tab",
      fmt"Esc{HairSp}/{HairSp}Space{HairSp}/{HairSp}Enter", "exit",
      "F1", "open user manual"], a)

proc toggleTitleBar(a) =
  toggleShowOption(a.layout.showTitleBar, NoIcon, "Title bar", a)
  a.win.showTitleBar = a.layout.showTitleBar

# TODO separate into level events and global events?
proc handleGlobalKeyEvents(a) =
  alias(ui,   a.ui)
  alias(map,  a.doc.map)
  alias(um,   a.doc.undoManager)
  alias(opts, a.opts)
  alias(dp,   a.ui.drawLevelParams)

  var l = currLevel(a)

  let yubnMode = a.prefs.yubnMovementKeys

  # {{{ handleMoveWalk()
  proc handleMoveWalk(ke: Event; a) =

    var s = 1
    if mkCtrl in ke.mods:
      if ke.key in AllWasdLetterKeys: return
      else: s = CursorJump

    let
      altDown   = mkAlt   in ke.mods
      shiftDown = mkShift in ke.mods
      isRepeat  = (ke.action == kaRepeat)

      isWasdKey = ke.key in AllWasdLetterKeys or
                  ke.key in AllWasdKeypadKeys

      k = if ui.wasdMode: a.keys.walkKeysWasd
          else:           a.keys.walkKeysCursor

      altAction = altDown and not isWasdKey

    var ke = ke
    ke.mods = ke.mods - {mkAlt, mkCtrl, mkShift}

    proc turnLeft( dir: CardinalDir): auto = dir.rotateACW
    proc turnRight(dir: CardinalDir): auto = dir.rotateCW

    template forward:  auto = ui.cursorOrient
    template backward: auto = turnLeft(turnLeft(ui.cursorOrient))
    template left:     auto = turnLeft(ui.cursorOrient)
    template right:    auto = turnRight(ui.cursorOrient)

    template doAction(dir: CardinalDir, moveAction: bool) =
      if moveAction:
        if shiftDown: moveLevelView({dir}, s, a)
        else:         moveCursor(    dir,  s, a)
      else:
        if not isRepeat: ui.cursorOrient = dir

    if   ke.isKeyDown(k.forward, repeat=true):
      doAction(forward, moveAction = true)

    elif ke.isKeyDown(k.backward, repeat=true):
      doAction(backward, moveAction = true)

    elif ke.isKeyDown(k.turnLeft, repeat=true):
      doAction(left, moveAction = altAction)

    elif ke.isKeyDown(k.turnRight, repeat=true):
      doAction(right, moveAction = altAction)

    elif ke.isKeyDown(k.strafeLeft, repeat=true):
      doAction(left, moveAction = not altAction)

    elif ke.isKeyDown(k.strafeRight, repeat=true):
      doAction(right, moveAction = not altAction)

  # }}}
  # {{{ moveKeyToCardinalDir()
  template moveKeyToCardinalDir(ke: Event, allowWasdKeys: bool,
                                allowRepeat: bool): Option[CardinalDir] =

    let k = if allowWasdKeys and ui.wasdMode: MoveKeysWasd
            else: MoveKeysStandard

    var kk = ke
    kk.mods = {}

    if   kk.isKeyDown(k.left,  repeat=allowRepeat): dirW.some
    elif kk.isKeyDown(k.right, repeat=allowRepeat): dirE.some
    elif kk.isKeyDown(k.up,    repeat=allowRepeat): dirN.some
    elif kk.isKeyDown(k.down,  repeat=allowRepeat): dirS.some
    else: CardinalDir.none

  # }}}
  # {{{ handleMoveKeys()
  template handleMoveKeys(ke: Event, allowWasdKeys, allowRepeat: bool,
                          allowDiagonal: bool, moveHandler: untyped) =

    if allowDiagonal:
      # Ignore Y/U/B/N keys if YUBN movement is not enabled in the prefs
      if not yubnMode and ke.key in DiagonalMoveLetterKeys:
        return

    let mods = ke.mods

    let dir = moveKeyToCardinalDir(ke, allowWasdKeys, allowRepeat)
    if dir.isSome:
      moveHandler(dir.get, mods, a)

    if allowDiagonal:
      let d = DiagonalMoveKeysCursor

      if ke.isKeyDown(d.upLeft, repeat=allowRepeat):
        moveHandler(dirN, mods, a)
        moveHandler(dirW, mods, a)

      elif ke.isKeyDown(d.upRight, repeat=allowRepeat):
        moveHandler(dirN, mods, a)
        moveHandler(dirE, mods, a)

      elif ke.isKeyDown(d.downLeft, repeat=allowRepeat):
        moveHandler(dirS, mods, a)
        moveHandler(dirW, mods, a)

      elif ke.isKeyDown(d.downRight, repeat=allowRepeat):
        moveHandler(dirS, mods, a)
        moveHandler(dirE, mods, a)

  # }}}
  # {{{ handleMoveCursor()
  proc handleMoveCursor(ke: Event; allowPan, allowJump, allowWasdKeys: bool,
                        allowDiagonal: bool; a): bool =

    if allowDiagonal:
      # Ignore Y/U/B/N keys if YUBN movement is not enabled in the prefs
      if not yubnMode and ke.key in DiagonalMoveLetterKeys:
        return

    var s = 1
    if allowJump and a.keys.primaryModKey in ke.mods:
      if ke.key in AllWasdLetterKeys:
        # Disallow Ctrl+Q/W/E/A/S/D jump as it would interfere with other
        # shorcuts
        return

      elif ke.key in DiagonalMoveLetterKeys:
        # Disallow Ctrl+Y/U/B/N panning as it would interfere with other
        # shorcuts
        return

      elif a.prefs.modifierKeyMode == mkmCommandShift and
        ke.key in VimMoveKeys:
        # Disallow Cmd+H/J/K/L jump as Cmd+H conflicts with the macOS
        # "hide window" shortcut
        return

      else:
        s = CursorJump

    let k = if allowWasdKeys and ui.wasdMode: MoveKeysWasd
            else: MoveKeysStandard

    var ke = ke
    ke.mods = ke.mods - {a.keys.primaryModKey}

    result = true

    proc down(key: set[Key]): bool =
      ke.isKeyDown(key, repeat=true)

    proc shiftDown(key: set[Key]): bool =
      ke.isKeyDown(key, {mkShift}, repeat=true)

    if   down(k.left):  moveCursor(dirW, s, a)
    elif down(k.right): moveCursor(dirE, s, a)
    elif down(k.up):    moveCursor(dirN, s, a)
    elif down(k.down):  moveCursor(dirS, s, a)

    elif allowPan:
      if   shiftDown(k.left):  moveLevelView(West, s, a)
      elif shiftDown(k.right): moveLevelView(East, s, a)
      elif shiftDown(k.up):    moveLevelView(North, s, a)
      elif shiftDown(k.down):  moveLevelView(South, s, a)

    if allowDiagonal:
      let d = DiagonalMoveKeysCursor

      if   down(d.upLeft):    moveCursorDiagonal(NorthWest, s, a)
      elif down(d.upRight):   moveCursorDiagonal(NorthEast, s, a)
      elif down(d.downLeft):  moveCursorDiagonal(SouthWest, s, a)
      elif down(d.downRight): moveCursorDiagonal(SouthEast, s, a)

      elif shiftDown(d.upLeft):    moveLevelView(NorthWest, s, a)
      elif shiftDown(d.upRight):   moveLevelView(NorthEast, s, a)
      elif shiftDown(d.downLeft):  moveLevelView(SouthWest, s, a)
      elif shiftDown(d.downRight): moveLevelView(SouthEast, s, a)

    result = false

  # }}}
  # {{{ drawWallRepeatMoveKeyHandler()
  proc drawWallRepeatMoveKeyHandler(dir: CardinalDir, mods: set[ModifierKey];
                                    a) =
    let cur = ui.cursor
    let drawDir = ui.drawWallRepeatDirection

    if dir.isHoriz == drawDir.isVert:
      let newCur = stepCursor(cur, dir, steps=1, a)
      if newCur != cur:
        if map.canSetWall(newCur, drawDir):
          setCursor(newCur, a)
          actions.setWall(map, loc=newCur, undoLoc=cur, drawDir,
                          ui.drawWallRepeatWall, um,
                          groupWithPrev=ui.drawTrail)
          setDrawWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)
    else:
      let direction = if dir.isHoriz: "vertical"
                      else:           "horizontal"

      setWarningMessage(
        fmt"Can only repeat in {direction} direction",
        keepStatusMessage=true, a=a
      )

  # }}}

  if hasKeyEvent():
    let ke = koi.currEvent()
    # TODO eventHandled is not set here, but it's not actually needed (yet)

    case ui.editMode:
    # {{{ emNormal
    of emNormal:
      # TODO revisit tooltip reset logic
      # Reset tooltip display on certain keypresses only
      if not (ke.key == keySpace) and
         not (ke.action == kaUp) and
         not (ke.key in {keyLeftControl,  keyLeftShift,  keyLeftAlt,
                         keyRightControl, keyRightShift, keyRightAlt}):
        resetManualNoteTooltip(a)

      if ui.walkMode: handleMoveWalk(ke, a)
      else:
        if handleMoveCursor(ke, allowPan=true, allowJump=true,
                            allowWasdKeys=true, allowDiagonal=true, a):
          # TODO what's this?
          setStatusMessage("moved", a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true, a=a):
        selectPrevLevel(a)

      elif ke.isShortcutDown(scNextLevel, repeat=true, a=a):
        selectNextLevel(a)

      let cur = ui.cursor

      if not ui.wasdMode and ke.isShortcutDown(scExcavateTunnel, a):
        ui.editMode = emExcavateTunnel
        startExcavateTunnelAction(a)

      elif not (ui.wasdMode and ui.walkMode) and
           ke.isShortcutDown(scEraseCell, a):
        ui.editMode = emEraseCell
        startEraseCellsAction(a)

      elif ke.isShortcutDown(scDrawClearFloor, a):
        ui.editMode = emDrawClearFloor
        setStatusMessage(IconEraser, "Draw/clear floor",
                         @[IconArrowsAll, "draw/clear"], a)

        actions.drawClearFloor(map, loc=cur, undoLoc=cur,
                               ui.currFloorColor, um, groupWithPrev=false)

      elif ke.isShortcutDown({scRotateFloorClockwise,
                              scRotateFloorAntiClockwise}, a):

        let floor = map.getFloor(cur)

        if floor in HorizVertFloors:
          if map.getFloorOrientation(cur).isHoriz:
            setStatusMessage(IconArrowsHoriz,
                             "Floor orientation set to horizontal", a)
            actions.setFloorOrientation(map, cur, dirN, um)

          else:
            setStatusMessage(IconArrowsVert,
                             "Floor orientation set to vertical", a)
            actions.setFloorOrientation(map, cur, dirE, um)


        elif floor in RotatableFloors:
          let
            clockwise = ke.isShortcutDown(scRotateFloorClockwise, a)

            dir = if clockwise: map.getFloorOrientation(cur).rotateCW
                  else:         map.getFloorOrientation(cur).rotateACW

            rotation = if clockwise: "clockwise" else: "anti-clockwise"

          setStatusMessage(IconSpinner, fmt"Rotated floor {rotation}", a)
          actions.setFloorOrientation(map, cur, dir, um)

        elif floor == fEmpty:
          setWarningMessage("Cannot change orientation of an empty cell",
                            a=a)
        else:
          setWarningMessage("Cannot rotate floor", a=a)


      elif ke.isShortcutDown(scSetFloorColor, a):
        ui.editMode = emColorFloor
        setStatusMessage(IconBrush, "Set floor colour",
                         @[IconArrowsAll, "set colour"], a)

        if not map.isEmpty(cur):
          actions.setFloorColor(map, loc=cur, undoLoc=cur,
                                ui.currFloorColor, um, groupWithPrev=false)

      elif not ui.wasdMode and ke.isShortcutDown(scDrawWall, a):
        enterDrawWallMode(specialWall=false, a)

      elif ke.isShortcutDown(scDrawSpecialWall, a):
        enterDrawWallMode(specialWall=true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Forward, a):
        cycleFloorGroupAction(FloorGroup1, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Forward, a):
        cycleFloorGroupAction(FloorGroup2, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Forward, a):
        cycleFloorGroupAction(FloorGroup3, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Forward, a):
        cycleFloorGroupAction(FloorGroup4, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Forward, a):
        cycleFloorGroupAction(FloorGroup5, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Forward, a):
        cycleFloorGroupAction(FloorGroup6, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Forward, a):
        cycleFloorGroupAction(FloorGroup7, forward=true, a)

      elif ke.isShortcutDown(scCycleFloorGroup8Forward, a):
        cycleFloorGroupAction(FloorGroup8, forward=true, a)


      elif ke.isShortcutDown(scCycleFloorGroup1Backward, a):
        cycleFloorGroupAction(FloorGroup1, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup2Backward, a):
        cycleFloorGroupAction(FloorGroup2, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup3Backward, a):
        cycleFloorGroupAction(FloorGroup3, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup4Backward, a):
        cycleFloorGroupAction(FloorGroup4, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup5Backward, a):
        cycleFloorGroupAction(FloorGroup5, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup6Backward, a):
        cycleFloorGroupAction(FloorGroup6, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup7Backward, a):
        cycleFloorGroupAction(FloorGroup7, forward=false, a)

      elif ke.isShortcutDown(scCycleFloorGroup8Backward, a):
        cycleFloorGroupAction(FloorGroup8, forward=false, a)

      elif ke.isShortcutDown(scSelectSpecialWall1, a):  selectSpecialWall(0, a)
      elif ke.isShortcutDown(scSelectSpecialWall2, a):  selectSpecialWall(1, a)
      elif ke.isShortcutDown(scSelectSpecialWall3, a):  selectSpecialWall(2, a)
      elif ke.isShortcutDown(scSelectSpecialWall4, a):  selectSpecialWall(3, a)
      elif ke.isShortcutDown(scSelectSpecialWall5, a):  selectSpecialWall(4, a)
      elif ke.isShortcutDown(scSelectSpecialWall6, a):  selectSpecialWall(5, a)
      elif ke.isShortcutDown(scSelectSpecialWall7, a):  selectSpecialWall(6, a)
      elif ke.isShortcutDown(scSelectSpecialWall8, a):  selectSpecialWall(7, a)
      elif ke.isShortcutDown(scSelectSpecialWall9, a):  selectSpecialWall(8, a)
      elif ke.isShortcutDown(scSelectSpecialWall10, a): selectSpecialWall(9, a)
      elif ke.isShortcutDown(scSelectSpecialWall11, a): selectSpecialWall(10, a)
      elif ke.isShortcutDown(scSelectSpecialWall12, a): selectSpecialWall(11, a)

      elif ke.isShortcutDown(scPreviousSpecialWall, repeat=true, a=a):
        if ui.currSpecialWall > 0: dec(ui.currSpecialWall)
        else: ui.currSpecialWall = SpecialWalls.high

      elif ke.isShortcutDown(scNextSpecialWall, repeat=true, a=a):
        if ui.currSpecialWall < SpecialWalls.high: inc(ui.currSpecialWall)
        else: ui.currSpecialWall = 0

      elif ke.isShortcutDown(scEraseTrail, a):
        if not ui.drawTrail:
          ui.editMode = emEraseTrail
          startEraseTrailAction(a)
        else:
          setWarningMessage("Cannot erase trail when draw trail is on", a=a)

      elif ke.isShortcutDown(scExcavateTrail, a):
        let bbox = l.calcTrailBoundingBox
        if bbox.isSome:
          actions.excavateTrail(map, cur, bbox.get, ui.currFloorColor, um)
          actions.clearTrailInLevel(map, cur, bbox.get, um, groupWithPrev=true,
                                    actionName="Excavate trail in level")

          setStatusMessage(IconShoePrints, "Trail excavated in level", a)
        else:
          setWarningMessage("No trail to excavate", a=a)

      elif ke.isShortcutDown(scClearTrail, a):
        let bbox = l.calcTrailBoundingBox
        if bbox.isSome:
          actions.clearTrailInLevel(map, cur, bbox.get, um)
          setStatusMessage(IconEraser, "Cleared trail in level", a)
        else:
          setWarningMessage("No trail to clear", a=a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true, a=a):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true, a=a):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor, a): pickFloorColor(a)

      elif ke.isShortcutDown(scSelectFloorColor1, a):  selectFloorColor(0, a)
      elif ke.isShortcutDown(scSelectFloorColor2, a):  selectFloorColor(1, a)
      elif ke.isShortcutDown(scSelectFloorColor3, a):  selectFloorColor(2, a)
      elif ke.isShortcutDown(scSelectFloorColor4, a):  selectFloorColor(3, a)
      elif ke.isShortcutDown(scSelectFloorColor5, a):  selectFloorColor(4, a)
      elif ke.isShortcutDown(scSelectFloorColor6, a):  selectFloorColor(5, a)
      elif ke.isShortcutDown(scSelectFloorColor7, a):  selectFloorColor(6, a)
      elif ke.isShortcutDown(scSelectFloorColor8, a):  selectFloorColor(7, a)
      elif ke.isShortcutDown(scSelectFloorColor9, a):  selectFloorColor(8, a)
      elif ke.isShortcutDown(scSelectFloorColor10, a): selectFloorColor(9, a)

      elif ke.isShortcutDown(scUndo, repeat=true, a=a): undoAction(a)
      elif ke.isShortcutDown(scRedo, repeat=true, a=a): redoAction(a)

      elif ke.isShortcutDown(scMarkSelection, a):
        enterSelectMode(a)

      elif ke.isShortcutDown(scPaste, a):
        if ui.copyBuf.isSome:
          actions.pasteSelection(map, loc=cur, undoLoc=cur, ui.copyBuf.get,
                                 pasteBufferLevelId=Natural.none,
                                 wraparound=false, um)

          setStatusMessage(IconPaste, "Buffer pasted", a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scPastePreview, a):
        if ui.copyBuf.isSome:
          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          ui.drawTrail = false
          ui.editMode = emPastePreview

          setPastePreviewModeMessage(a)
        else:
          setWarningMessage("Cannot paste, buffer is empty", a=a)

      elif ke.isShortcutDown(scNudgePreview, a):
        let sel = newSelection(l.rows, l.cols)
        sel.fill(true)

        ui.nudgeBuf = SelectionBuffer(level: l, selection: sel).some

        dp.selStartRow = 0
        dp.selStartCol = 0

        ui.editMode = emNudgePreview
        ui.drawTrail = false

        setNudgePreviewModeMessage(a)

      elif ke.isShortcutDown(scJumpToLinkedCell, a):
        let otherLocs = map.getLinkedLocations(cur)

        if otherLocs.len == 1:
          let otherLoc = otherLocs.first.get
          if map.getLinkedLocations(otherLoc).len > 1:
            ui.lastJumpToSrcLocation = cur
          moveCursorTo(otherLoc, a)

        elif otherLocs.len > 1:
          ui.jumpToSrcLocations = otherLocs.toSeq
          sort(ui.jumpToSrcLocations)

          # Try to continue selecting sources from the last source we left at.
          let oldIdx = ui.jumpToSrcLocations.find(ui.lastJumpToSrcLocation)
          if oldIdx == -1:
            # The source we left at last time doesn't exist (e.g. the user
            # deleted it or wasn't linked to this destination), so reset from
            # beginning.
            ui.jumpToSrcLocationIdx = 0
          else:
            ui.jumpToSrcLocationIdx = oldIdx

          ui.jumpToDestLocation = cur
          ui.lastJumpToSrcLocation = ui.jumpToSrcLocations[ui.jumpToSrcLocationIdx]
          ui.wasDrawingTrail = ui.drawTrail
          ui.drawTrail = false

          moveCursorTo(ui.lastJumpToSrcLocation, a)
          ui.editMode = emSelectJumpToLinkSrc
          setSelectJumpToLinkSrcActionMessage(a)
        else:
          setWarningMessage("Not a linked cell", a=a)

      elif ke.isShortcutDown(scLinkCell, a):
        let floor = map.getFloor(cur)
        if floor in LinkSources:
          ui.linkSrcLocation = cur
          ui.editMode = emSetCellLink
          setSetLinkDestinationMessage(floor, a)
        else:
          setWarningMessage("Cannot link current cell", a=a)

#      elif ke.isShortcutDown(scUnlinkCell, a):
#        let otherLocs = map.getLinkedLocations(cur)
#        if otherLocs.len >= 1:
#          actions.unlinkCell(map, cur, um)
#          setStatusMessage(IconEraser, "Cell unlinked", a)
#        else:
#          setWarningMessage("Not a linked cell", a=a)

      elif ke.isShortcutDown(scZoomIn, repeat=true, a=a):
        zoomIn(a)
        setStatusMessage(IconZoomIn,
          fmt"Zoomed in – level {dp.getZoomLevel}", a)

      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a):
        zoomOut(a)
        setStatusMessage(IconZoomOut,
                         fmt"Zoomed out – level {dp.getZoomLevel}", a)

      elif ke.isShortcutDown(scEditNote, a):
        if map.isEmpty(cur):
          setWarningMessage("Cannot attach note to empty cell", a=a)
        else:
          openEditNoteDialog(a)

      elif ke.isShortcutDown(scEraseNote, a):
        if map.hasNote(cur):
          actions.eraseNote(map, cur, um)
          setStatusMessage(IconEraser, "Note erased", a)
        else:
          setWarningMessage("No note to erase in cell", a=a)

      elif ke.isShortcutDown(scEditLabel, a):
        openEditLabelDialog(a)

      elif ke.isShortcutDown(scEraseLabel, a):
        if map.hasLabel(cur):
          actions.eraseLabel(map, cur, um)
          setStatusMessage(IconEraser, "Label erased", a)
        else:
          setWarningMessage("No label to erase in cell", a=a)

      elif ke.isShortcutDown(scShowNoteTooltip, a):
        if ui.manualNoteTooltipState.show:
          resetManualNoteTooltip(a)
        else:
          if map.hasNote(cur):
            with ui.manualNoteTooltipState:
              show = true
              location = cur
              mx = koi.mx()
              my = koi.my()

      elif ke.isShortcutDown(scShowLinkLines, a):
        ui.momentaryShowLinkLines = true

      elif ke.isShortcutUp(scShowLinkLines, a):
        ui.momentaryShowLinkLines = false

      elif ke.isShortcutDown(scEditPreferences, a): openPreferencesDialog(a)

      elif ke.isShortcutDown(scNewLevel, a):
        if map.levels.len < NumLevelsLimits.maxInt:
          openNewLevelDialog(a)
        else:
          setWarningMessage(
            "Cannot add new level: maximum number of levels has been reached " &
            fmt"({NumLevelsLimits.maxInt})", a=a
          )

      elif ke.isShortcutDown(scDeleteLevel, a):
        openDeleteLevelDialog(a)

      elif ke.isShortcutDown(scNewMap, a): newMap(a)
      elif ke.isShortcutDown(scEditMapProps, a): openEditMapPropsDialog(a)

      elif ke.isShortcutDown(scEditLevelProps, a):
        openEditLevelPropsDialog(a)

      elif ke.isShortcutDown(scResizeLevel, a):
        openResizeLevelDialog(a)

      elif ke.isShortcutDown(scEditRegionProps, a):
        if l.regionOpts.enabled:
          openEditRegionPropertiesDialog(a)
        else:
          setWarningMessage(
            "Cannot edit region properties: regions are not enabled for level",
            a=a
          )

      elif ke.isShortcutDown(scOpenMap, a):       openMap(a)
      elif ke.isShortcutDown(scSaveMap, a):       saveMap(a)
      elif ke.isShortcutDown(scSaveMapAs, a):     saveMapAs(a)

      elif ke.isShortcutDown(scReloadTheme, a):   reloadTheme(a)
      elif ke.isShortcutDown(scPreviousTheme, a): selectPrevTheme(a)
      elif ke.isShortcutDown(scNextTheme, a):     selectNextTheme(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

      elif ke.isShortcutDown(scShowAboutDialog, a):
        openAboutDialog(a)

      elif ke.isShortcutDown(scToggleThemeEditor, a):
        toggleThemeEditor(a)

      elif ke.isShortcutDown(scToggleQuickReference, a):
        showQuickReference(a)

      # Toggle editing options
      elif ke.isShortcutDown(scToggleWalkMode, a):
        ui.walkMode = not ui.walkMode
        let msg = if ui.walkMode: "Walk mode" else: "Normal mode"
        setStatusMessage(msg, a)

      elif ke.isShortcutDown(scToggleWasdMode, a):
        toggleOnOffOption(ui.wasdMode, IconMouse, "WASD mode", a)

      elif ke.isShortcutDown(scToggleDrawTrail, a):
        if not ui.drawTrail:
          actions.drawTrail(map, loc=cur, undoLoc=cur, um)
        toggleOnOffOption(ui.drawTrail, IconShoePrints, "Draw trail", a)

      # Toggle layout options
      elif ke.isShortcutDown(scToggleCellCoords, a):
        toggleShowOption(a.ui.showCellCoords, NoIcon, "Cell coordinates", a)

      elif ke.isShortcutDown(scToggleCurrentNotePane, a):
        toggleShowOption(a.layout.showCurrentNotePane, NoIcon,
                         "Current note pane", a)

      elif ke.isShortcutDown(scToggleNotesListPane, a):
        toggleShowOption(a.layout.showNotesListPane, NoIcon,
                         "Note list pane", a)

      elif ke.isShortcutDown(scToggleToolsPane, a):
        toggleShowOption(a.layout.showToolsPane, NoIcon, "Tools pane", a)

      elif ke.isShortcutDown(scToggleTitleBar, a):
        toggleTitleBar(a)

      # Save/restore layout
      elif ke.isShortcutDown(scSaveLayout1, a): saveLayout(0, a)
      elif ke.isShortcutDown(scSaveLayout2, a): saveLayout(1, a)
      elif ke.isShortcutDown(scSaveLayout3, a): saveLayout(2, a)
      elif ke.isShortcutDown(scSaveLayout4, a): saveLayout(3, a)

      elif ke.isShortcutDown(scRestoreLayout1, a): restoreLayout(0, a)
      elif ke.isShortcutDown(scRestoreLayout2, a): restoreLayout(1, a)
      elif ke.isShortcutDown(scRestoreLayout3, a): restoreLayout(2, a)
      elif ke.isShortcutDown(scRestoreLayout4, a): restoreLayout(3, a)

      elif ke.isShortcutDown(scResetUIScaling, a):
        a.prefs.scaleFactor = 1.0
        updateUIScaleFactor(a)
        setStatusMessage("Interface scaling reset to default", a)

    # }}}
    # {{{ emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor, emColorFloor
    of emExcavateTunnel, emEraseCell, emEraseTrail, emDrawClearFloor,
       emColorFloor:
      let prevMoveDir = a.ui.prevMoveDir

      if ui.walkMode: handleMoveWalk(ke, a)
      else:
        let allowDiagonal = ui.editMode != emExcavateTunnel
        discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                                 allowWasdKeys=true,
                                 allowDiagonal=allowDiagonal, a)
      let cur = ui.cursor

      if cur != ui.prevCursor:
        if   ui.editMode == emExcavateTunnel:
          if a.prefs.openEndedExcavate:
            let dir = if ui.walkMode: ui.cursorOrient.some
                      else: moveKeyToCardinalDir(ke, allowWasdKeys=true,
                                                 allowRepeat=true)

            actions.excavateTunnel(map, loc=cur, undoLoc=ui.prevCursor,
                                   ui.currFloorColor, dir,
                                   prevDir=prevMoveDir,
                                   prevLoc=ui.prevCursor.some,
                                   um, groupWithPrev=ui.drawTrail)
          else:
            actions.excavateTunnel(a.doc.map, loc=cur, undoLoc=cur,
                                   a.ui.currFloorColor,
                                   um=um, groupWithPrev=ui.drawTrail)

        elif ui.editMode == emEraseCell:
          actions.eraseCell(map, loc=cur, undoLoc=ui.prevCursor,
                            um, groupWithPrev=ui.drawTrail)

        elif ui.editMode == emEraseTrail:
          actions.eraseTrail(map, loc=cur, undoLoc=cur, um)

        elif ui.editMode == emDrawClearFloor:
          actions.drawClearFloor(map, loc=cur, undoLoc=ui.prevCursor,
                                 ui.currFloorColor,
                                 um, groupWithPrev=ui.drawTrail)

        elif ui.editMode == emColorFloor:
          if not map.isEmpty(cur):
            actions.setFloorColor(map, loc=cur, undoLoc=ui.prevCursor,
                                  ui.currFloorColor,
                                  um, groupWithPrev=ui.drawTrail)

      if not ui.wasdMode and ke.isShortcutUp(scExcavateTunnel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      if ke.isShortcutUp({scEraseCell, scDrawClearFloor, scEraseTrail,
                          scSetFloorColor}, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawWall
    of emDrawWall:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        let cur = ui.cursor

        if map.canSetWall(cur, dir):
          let w = if map.getWall(cur, dir) == wWall: wNone
                  else: wWall

          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, loc=cur, undoLoc=cur, dir, w, um,
                          groupWithPrev=false)

          setDrawWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if not ui.wasdMode and ke.isShortcutUp(scDrawWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat, ignoreMods=true, a=a):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawWallRepeat
          setDrawWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat, a):
        setDrawWallActionMessage(a)

    # }}}
    # {{{ emDrawWallRepeat
    of emDrawWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     allowDiagonal=false, drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat, a):
        ui.editMode = emDrawWall
        setDrawWallActionMessage(a)

      if not ui.wasdMode and ke.isShortcutUp(scDrawWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emDrawSpecialWall
    of emDrawSpecialWall:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        let cur = ui.cursor

        if map.canSetWall(cur, dir):
          var curSpecWall = SpecialWalls[ui.currSpecialWall]

          if   curSpecWall == wOneWayDoorNE:
            if dir in {dirS, dirW}: curSpecWall = wOneWayDoorSW
          elif curSpecWall == wLeverSW:
            if dir in {dirN, dirE}: curSpecWall = wLeverNE
          elif curSpecWall == wNicheSW:
            if dir in {dirN, dirE}: curSpecWall = wNicheNE
          elif curSpecWall == wStatueSw:
            if dir in {dirN, dirE}: curSpecWall = wStatueNE
          elif curSpecWall == wWritingSW:
            if dir in {dirN, dirE}: curSpecWall = wWritingNE

          let w = if map.getWall(cur, dir) == curSpecWall: wNone
                  else: curSpecWall

          ui.drawWallRepeatAction = if w == wNone: dwaClear else: dwaSet
          ui.drawWallRepeatWall = w
          ui.drawWallRepeatDirection = dir

          actions.setWall(map, loc=cur, undoLoc=cur, dir, w, um,
                          groupWithPrev=false)

          setDrawSpecialWallActionMessage(a)
        else:
          setWarningMessage("Cannot set wall of an empty cell",
                            keepStatusMessage=true, a=a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if ke.isShortcutUp(scDrawSpecialWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scDrawWallRepeat, ignoreMods=true, a=a):
        if ui.drawWallRepeatAction == dwaNone:
          setWarningMessage("Set or clear wall in current cell first",
                            keepStatusMessage=true, a=a)
        else:
          ui.editMode = emDrawSpecialWallRepeat
          setDrawSpecialWallActionRepeatMessage(a)

      elif ke.isShortcutUp(scDrawWallRepeat, a):
        setDrawSpecialWallActionMessage(a)

    # }}}
    # {{{ emDrawSpecialWallRepeat
    of emDrawSpecialWallRepeat:
      # HACK remove shift modifier
      var ke = ke
      ke.mods = {}

      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=true,
                     allowDiagonal=false, drawWallRepeatMoveKeyHandler)

      if ke.isShortcutUp(scDrawWallRepeat, a):
        ui.editMode = emDrawSpecialWall
        setDrawSpecialWallActionMessage(a)

      if ke.isShortcutUp(scDrawSpecialWall, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

    # }}}
    # {{{ emSelect
    of emSelect:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      if primaryModDown(a): setSelectModeSpecialActionsMessage(a)
      else:                 setSelectModeSelectMessage(a)

      if   ke.isShortcutDown(scSelectionDraw, a):
        ui.selection.get[cur.row, cur.col] = true
        ui.editMode = emSelectDraw

      elif ke.isShortcutDown(scSelectionErase, a):
        ui.selection.get[cur.row, cur.col] = false
        ui.editMode = emSelectErase

      elif ke.isShortcutDown(scSelectionAll, a):  ui.selection.get.fill(true)

      elif ke.isShortcutDown(scSelectionNone, a):
        ui.selection.get.fill(false)

      elif ke.isShortcutDown({scSelectionAddRect, scSelectionSubRect}, a):
        ui.editMode = emSelectRect
        ui.selRect = some(SelectionRect(
          startRow: cur.row,
          startCol: cur.col,
          rect: rectN(cur.row, cur.col, cur.row+1, cur.col+1),
          selected: ke.isShortcutDown(scSelectionAddRect, a)
        ))

      elif ke.isShortcutDown(scSelectionCopy, a):
        let bbox = copySelection(ui.copyBuf, a)
        if bbox.isSome:
          exitSelectMode(a)
          setStatusMessage(IconCopy, "Copied selection to buffer", a)

      elif ke.isShortcutDown(scSelectionMove, a):
        let selection = ui.selection.get
        let bbox = copySelection(ui.nudgeBuf, a)
        if bbox.isSome:
          let bbox = bbox.get
          var bboxTopLeft = Location(
            levelId: cur.levelId,
            col:     bbox.c1,
            row:     bbox.r1
          )
          ui.pasteUndoLocation = bboxTopLeft

          actions.cutSelection(map, bboxTopLeft, bbox, selection,
                               linkDestLevelId=MoveBufferLevelId, um)
          exitSelectMode(a)

          # Enter paste preview mode
          var cur = cur
          cur.row = bbox.r1
          cur.col = bbox.c1
          setCursor(cur, a)

          dp.selStartRow = cur.row
          dp.selStartCol = cur.col

          ui.editMode = emMovePreview
          setMovePreviewModeMessage(a)

      elif ke.isShortcutDown(scSelectionEraseArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.eraseSelection(map, cur.levelId, selection, bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconEraser, "Erased selection", a)

      elif ke.isShortcutDown(scSelectionFillArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.fillSelection(map, cur.levelId, selection, bbox.get,
                                ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconFill, "Filled selection", a)

      elif ke.isShortcutDown(scSelectionSurroundArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.surroundSelectionWithWalls(map, cur.levelId, selection,
                                             bbox.get, um)
          exitSelectMode(a)
          setStatusMessage(IconBorders, "Surrounded selection with walls", a)

      elif ke.isShortcutDown(scSelectionSetFloorColorArea, a):
        let selection = ui.selection.get
        let bbox = selection.boundingBox
        if bbox.isSome:
          actions.setSelectionFloorColor(map, cur.levelId, selection,
                                         bbox.get, ui.currFloorColor, um)
          exitSelectMode(a)
          setStatusMessage(IconBrush, "Set floor colour of selection", a)

      elif ke.isShortcutDown(scSelectionCropArea, a):
        let sel = ui.selection.get
        let bbox = sel.boundingBox
        if bbox.isSome:
          let newCur = actions.cropLevel(map, cur, bbox.get, um)
          moveCursorTo(newCur, a)
          exitSelectMode(a)
          setStatusMessage(IconCrop, "Cropped level to selection", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPreviousFloorColor, repeat=true, a=a):
        selectPrevFloorColor(a)

      elif ke.isShortcutDown(scNextFloorColor, repeat=true, a=a):
        selectNextFloorColor(a)

      elif ke.isShortcutDown(scPickFloorColor, a): pickFloorColor(a)

      elif ke.isShortcutDown(scCancel, a):
        exitSelectMode(a)
        a.clearStatusMessage

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

    # }}}
    # {{{ emSelectDraw, emSelectErase
    of emSelectDraw, emSelectErase:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor
      ui.selection.get[cur.row, cur.col] = ui.editMode == emSelectDraw

      if ke.isShortcutUp({scSelectionDraw, scSelectionErase}, a):
        ui.editMode = emSelect

    # }}}
    # {{{ emSelectRect
    of emSelectRect:
      discard handleMoveCursor(ke, allowPan=false, allowJump=false,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      var r1,c1, r2,c2: Natural
      if ui.selRect.get.startRow <= cur.row:
        r1 = ui.selRect.get.startRow
        r2 = cur.row+1
      else:
        r1 = cur.row
        r2 = ui.selRect.get.startRow + 1

      if ui.selRect.get.startCol <= cur.col:
        c1 = ui.selRect.get.startCol
        c2 = cur.col+1
      else:
        c1 = cur.col
        c2 = ui.selRect.get.startCol + 1

      ui.selRect.get.rect = rectN(r1,c1, r2,c2)

      if ke.isShortcutUp({scSelectionAddRect, scSelectionSubRect}, a):
        ui.selection.get.fill(ui.selRect.get.rect, ui.selRect.get.selected)
        ui.selRect = SelectionRect.none
        ui.editMode = emSelect

    # }}}
    # {{{ emPastePreview
    of emPastePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        ui.pasteWraparound = not ui.pasteWraparound
        setPastePreviewModeMessage(a)

      elif ke.isShortcutDown(scPreviousLevel, repeat=true, a=a):
        selectPrevLevel(a)

      elif ke.isShortcutDown(scNextLevel, repeat=true, a=a):
        selectNextLevel(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPasteAccept, a):
        actions.pasteSelection(map, loc=cur, undoLoc=cur, ui.copyBuf.get,
                               pasteBufferLevelId=Natural.none,
                               wraparound=ui.pasteWraparound,
                               um, pasteTrail=true)
        ui.editMode = emNormal
        setStatusMessage(IconPaste, "Pasted buffer contents", a)

      elif ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

    # }}}
    # {{{ emMovePreview
    of emMovePreview:
      discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                               allowWasdKeys=false, allowDiagonal=true, a)
      let cur = ui.cursor

      dp.selStartRow = cur.row
      dp.selStartCol = cur.col

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        ui.pasteWraparound = not ui.pasteWraparound
        setMovePreviewModeMessage(a)

      elif ke.isShortcutDown(scPreviousLevel, repeat=true, a=a):
        selectPrevLevel(a)

      elif ke.isShortcutDown(scNextLevel, repeat=true, a=a):
        selectNextLevel(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scPasteAccept, a):
        actions.pasteSelection(map, loc=cur, undoLoc=ui.pasteUndoLocation,
                               ui.nudgeBuf.get,
                               pasteBufferLevelId=MoveBufferLevelId.some,
                               wraparound=ui.pasteWraparound,
                               um, groupWithPrev=true,
                               actionName="Move selection")
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Moved selection", a)

      elif ke.isShortcutDown(scCancel, a):
        exitMovePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

    # }}}
    # {{{ emNudgePreview
    of emNudgePreview:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        alias(dp, a.ui.drawLevelParams)

        let cols = a.ui.nudgeBuf.get.level.cols
        let rows = a.ui.nudgeBuf.get.level.rows

        let step = if mkCtrl in mods: CursorJump else: 1

        case dir:
        of dirE: dp.selStartCol = (dp.selStartCol + step).clampMax( cols-1)
        of dirS: dp.selStartRow = (dp.selStartRow + step).clampMax( rows-1)
        of dirW: dp.selStartCol = (dp.selStartCol - step).clampMin(-cols+1)
        of dirN: dp.selStartRow = (dp.selStartRow - step).clampMin(-rows+1)


      handleMoveKeys(ke, allowWasdKeys=false, allowRepeat=true,
                     allowDiagonal=true, handleMoveKey)

      let cur = ui.cursor

      if ke.isShortcutDown(scTogglePasteWraparound, a):
        ui.pasteWraparound = not ui.pasteWraparound
        setNudgePreviewModeMessage(a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scAccept, a):
        let newCur = actions.nudgeLevel(map, cur,
                                        dp.selStartRow, dp.selStartCol,
                                        ui.nudgeBuf.get,
                                        wraparound=ui.pasteWraparound, um)
        moveCursorTo(newCur, a)
        ui.editMode = emNormal
        setStatusMessage(IconArrowsAll, "Nudged map", a)

      elif ke.isShortcutDown(scCancel, a):
        exitNudgePreviewMode(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

    # }}}
    # {{{ emSetCellLink
    of emSetCellLink:
      if ui.walkMode: handleMoveWalk(ke, a)
      else:
        discard handleMoveCursor(ke, allowPan=true, allowJump=true,
                                 allowWasdKeys=true, allowDiagonal=false, a)

      if   ke.isShortcutDown(scPreviousLevel, repeat=true, a=a):
        selectPrevLevel(a)

      elif ke.isShortcutDown(scNextLevel, repeat=true, a=a):
        selectNextLevel(a)

      let cur = ui.cursor

      if cur != ui.prevCursor:
        let floor = map.getFloor(ui.linkSrcLocation)
        setSetLinkDestinationMessage(floor, a)

      if ke.isShortcutDown(scAccept, a):
        if map.isEmpty(cur):
          setWarningMessage("Cannot set link destination to an empty cell",
                            keepStatusMessage=true, a=a)

        elif cur == ui.linkSrcLocation:
          setWarningMessage("Cannot set link destination to the source cell",
                            keepStatusMessage=true, a=a)
        else:
          actions.setLink(map, src=ui.linkSrcLocation, dest=cur,
                          ui.currFloorColor, um)

          ui.editMode = emNormal

          let linkType = linkFloorToString(map.getFloor(cur))
          setStatusMessage(
            IconLink, fmt"{capitalizeAscii(linkType)} link destination set", a)

      elif ke.isShortcutDown(scZoomIn,  repeat=true, a=a): zoomIn(a)
      elif ke.isShortcutDown(scZoomOut, repeat=true, a=a): zoomOut(a)

      elif ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        clearStatusMessage(a)

      elif ke.isShortcutDown(scOpenUserManual, a):
        openUserManual(a.paths.manualDir)

    # }}}
    # {{{ emSelectJumpToLinkSrc
    of emSelectJumpToLinkSrc:
      proc handleMoveKey(dir: CardinalDir, mods: set[ModifierKey]; a) =
        var destIdx: int
        case dir:
        of dirE, dirN:
          destIdx = ui.jumpToSrcLocationIdx + 1
        of dirW, dirS:
          destIdx = ui.jumpToSrcLocationIdx - 1

        ui.jumpToSrcLocationIdx = destIdx.floorMod(ui.jumpToSrcLocations.len)
        ui.lastJumpToSrcLocation = ui.jumpToSrcLocations[ui.jumpToSrcLocationIdx]

        moveCursorTo(ui.lastJumpToSrcLocation, a)
        setSelectJumpToLinkSrcActionMessage(a)


      handleMoveKeys(ke, allowWasdKeys=true, allowRepeat=false,
                     allowDiagonal=false, handleMoveKey)

      if ke.isShortcutDown(scAccept, a) or ke.isShortcutDown(scCancel, a):
        ui.editMode = emNormal
        if ui.wasDrawingTrail:
          actions.drawTrail(map, loc=ui.cursor,
                            undoLoc=ui.jumpToDestLocation, um)
          ui.drawTrail = true
        clearStatusMessage(a)

      elif ke.isShortcutDown(scJumpToLinkedCell, a):
        moveCursorTo(ui.jumpToDestLocation, a)
        ui.editMode = emNormal
        if ui.wasDrawingTrail:
          ui.drawTrail = true
        clearStatusMessage(a)

    # }}}
    of emPanLevel:
      discard

# }}}
# {{{ handleGlobalKeyEvents_NoLevels()
proc handleGlobalKeyEvents_NoLevels(a) =
  let yubnMode = a.prefs.yubnMovementKeys

  if hasKeyEvent():
    let ke = koi.currEvent()

    if   ke.isShortcutDown(scNewMap, a):            newMap(a)
    elif ke.isShortcutDown(scEditMapProps, a):      openEditMapPropsDialog(a)

    elif ke.isShortcutDown(scOpenMap, a):           openMap(a)
    elif ke.isShortcutDown(scSaveMap, a):           saveMap(a)
    elif ke.isShortcutDown(scSaveMapAs, a):         saveMapAs(a)

    elif ke.isShortcutDown(scNewLevel, a):
      openNewLevelDialog(a)

    elif ke.isShortcutDown(scReloadTheme, a):       reloadTheme(a)
    elif ke.isShortcutDown(scPreviousTheme, a):     selectPrevTheme(a)
    elif ke.isShortcutDown(scNextTheme, a):         selectNextTheme(a)

    elif ke.isShortcutDown(scEditPreferences, a):   openPreferencesDialog(a)

    elif ke.isShortcutDown(scUndo, repeat=true, a=a): undoAction(a)
    elif ke.isShortcutDown(scRedo, repeat=true, a=a): redoAction(a)

    elif ke.isShortcutDown(scOpenUserManual, a):    openUserManual(a.paths.manualDir)
    elif ke.isShortcutDown(scShowAboutDialog, a):   openAboutDialog(a)

    elif ke.isShortcutDown(scToggleThemeEditor, a):
      toggleThemeEditor(a)

    elif ke.isShortcutDown(scToggleQuickReference, a):
      showQuickReference(a)

    # Toggle options
    elif ke.isShortcutDown(scToggleTitleBar, a):
      toggleTitleBar(a)

# }}}
# {{{ handleQuickRefKeyEvents()

let QuickRefTabLabels = @["General", "Editing", "Interface"]

proc handleQuickRefKeyEvents(a) =
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

# }}}

# {{{ windowContentScaleCb()
proc windowContentScaleCb(window: Window, xscale, yscale: float) =
  g_app.updateUIScaleFactor()
  g_app.updateUI = true

# }}}
# {{{ renderFramePreCb()
proc renderFramePreCb(a) =

  proc loadPendingTheme(themeIndex: Natural, a) =
    try:
      a.theme.themeReloaded = (themeIndex == a.theme.currThemeIndex)
      switchTheme(themeIndex, a)

    except CatchableError as e:
      logError(e, "Error loading theme when switching theme")
      a.logfile.flushFile

      let name = a.theme.themeNames[themeIndex].name

      setErrorMessage(fmt"Cannot load theme '{name}': {e.msg}", a)

      a.theme.nextThemeIndex = Natural.none

    # nextThemeIndex will be reset at the start of the current frame after
    # displaying the status message

  if a.theme.nextThemeIndex.isSome:
    loadPendingTheme(a.theme.nextThemeIndex.get, a)

  a.win.title = a.doc.map.title
  a.win.modified = a.doc.undoManager.isModified

  if a.theme.updateTheme:
    a.theme.updateTheme = false
    updateTheme(a)

  if a.theme.loadBackgroundImage:
    a.theme.loadBackgroundImage = false
    loadBackgroundImage(a.currThemeName, a)

  a.updateUI = true

# }}}
# {{{ renderFrameCb()

proc closeSplash(a)

proc renderFrameCb(a) =

  proc displayThemeLoadedMessage(a) =
    let themeName = a.currThemeName.name
    if a.theme.themeReloaded:
      setStatusMessage(fmt"Theme '{themeName}' reloaded", a)
      a.theme.themeReloaded = false
    else:
      setStatusMessage(fmt"Theme '{themeName}' loaded", a)

  if a.theme.nextThemeIndex.isSome:
    if a.theme.hideThemeLoadedMessage:
      a.theme.hideThemeLoadedMessage = false
    else:
      displayThemeLoadedMessage(a)
    a.theme.nextThemeIndex = Natural.none

  proc handleWindowClose(a) =
    proc saveConfigAndExit(a) =
      saveAppConfig(a)
      a.shouldClose = true

    proc handleMapModified(a) =
      if a.doc.undoManager.isModified:
        openSaveDiscardMapDialog(nextAction = saveConfigAndExit, a)
      else:
        saveConfigAndExit(a)

    when defined(NO_QUIT_DIALOG):
      saveConfigAndExit(a)
    else:
      if a.themeEditor.modified:
        openSaveDiscardThemeDialog(nextAction = handleMapModified, a)
      else:
        handleMapModified(a)

  # XXX HACK: If the theme pane is shown, widgets are handled first, then
  # the global shortcuts, so widget-specific shorcuts can take precedence
  var uiRendered = false
  if a.layout.showThemeEditor:
    renderUI(a)
    uiRendered = true

  if a.splash.win == nil:
    if a.ui.showQuickReference: handleQuickRefKeyEvents(a)
    elif a.doc.map.hasLevels:     handleGlobalKeyEvents(a)
    else:                         handleGlobalKeyEvents_NoLevels(a)

  else:
    if not a.layout.showThemeEditor and a.win.glfwWin.focused:
      glfw.makeContextCurrent(a.splash.win)
      closeSplash(a)
      glfw.makeContextCurrent(a.win.glfwWin)
      a.win.focus

  if not a.layout.showThemeEditor or not uiRendered:
    renderUI(a)

  if a.win.shouldClose:
    a.win.shouldClose = false
    handleWindowClose(a)

# }}}
# {{{ renderFrameSplash()
proc renderFrameSplash(a) =
  alias(s, a.splash)
  alias(vg, s.vg)

  let cfg = a.theme.config

  let
    (winWidth, winHeight) = s.win.size
    (fbWidth, fbHeight) = s.win.framebufferSize
    pxRatio = fbWidth.float / winWidth.float

  glViewport(0, 0, fbWidth.GLsizei, fbHeight.GLsizei)

  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)

  vg.beginFrame(winWidth, winHeight, pxRatio)

  if s.logoImage == NoImage or s.updateLogoImage:
    colorImage(s.logo, cfg.getColorOrDefault("ui.splash-image.logo"))
    if s.logoImage == NoImage:
      s.logoImage = createImage(s.logo)
    else:
      vg.updateImage(s.logoImage, cast[ptr byte](s.logo.data))
    s.updateLogoImage = false

  if s.outlineImage == NoImage or s.updateOutlineImage:
    colorImage(s.outline, cfg.getColorOrDefault("ui.splash-image.outline"))
    if s.outlineImage == NoImage:
      s.outlineImage = createImage(s.outline)
    else:
      vg.updateImage(s.outlineImage, cast[ptr byte](s.outline.data))
    s.updateOutlineImage = false

  if s.shadowImage == NoImage or s.updateShadowImage:
    colorImage(s.shadow, black())
    if s.shadowImage == NoImage:
      s.shadowImage = createImage(s.shadow)
    else:
      vg.updateImage(s.shadowImage, cast[ptr byte](s.shadow.data))
    s.updateShadowImage = false


  let scale = winWidth / s.logo.width

  s.logoPaint = createPattern(vg, s.logoImage, scale=scale)

  s.outlinePaint = createPattern(vg, s.outlineImage, scale=scale)

  s.shadowPaint = createPattern(
    vg, s.shadowImage,
    alpha=cfg.getFloatOrDefault("ui.splash-image.shadow-alpha"),
    scale=scale
  )

  vg.beginPath
  vg.rect(0, 0, winWidth, winHeight)

  vg.fillPaint(s.shadowPaint)
  vg.fill

  vg.fillPaint(s.outlinePaint)
  vg.fill

  vg.fillPaint(s.logoPaint)
  vg.fill

  vg.endFrame


  if not a.layout.showThemeEditor and a.splash.win.shouldClose:
    a.shouldClose = true

  proc shouldCloseSplash(a): bool =
    alias(w, a.splash.win)

    if a.layout.showThemeEditor:
      not a.splash.show
    else:
      let autoClose =
        if not a.layout.showThemeEditor and a.prefs.autoCloseSplash:
          let dt = getMonoTime() - a.splash.t0
          koi.setFramesLeft()
          dt > initDuration(seconds = a.prefs.splashTimeoutSecs)
        else: false

      w.isKeyDown(keyEscape) or
      w.isKeyDown(keySpace) or
      w.isKeyDown(keyEnter) or
      w.isKeyDown(keyKpEnter) or
      w.mouseButtonDown(mbLeft) or
      w.mouseButtonDown(mbRight) or
      w.mouseButtonDown(mbMiddle) or autoClose

  if shouldCloseSplash(a):
    closeSplash(a)
    a.win.focus

# }}}

# {{{ Init & cleanup

# {{{ createSplashWindow()
proc createSplashWindow(mousePassthrough: bool = false; a) =
  alias(s, a.splash)

  var cfg = DefaultOpenglWindowConfig
  cfg.visible = false
  cfg.resizable = false
  cfg.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  cfg.nMultiSamples = 4
  cfg.transparentFramebuffer = true
  cfg.decorated = false
  cfg.floating = true
  cfg.mousePassthrough = mousePassthrough

  when defined(windows):
    cfg.hideFromTaskbar = true
  else:
    cfg.version = glv32
    cfg.forwardCompat = true
    cfg.profile = opCoreProfile

  s.win = newWindow(cfg)
  s.win.title = "Gridmonger Splash Image"
  s.vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

# }}}
# {{{ showSplash()
proc showSplash(a) =
  alias(s, g_app.splash)

  let (_, _, maxWidth, maxHeight) = g_app.win.findCurrentMonitor().workArea
  let w = (maxWidth * 0.6).int
  let h = (w/s.logo.width * s.logo.height).int

  s.win.size = (w, h)
  s.win.pos = ((maxWidth - w) div 2, (maxHeight - h) div 2)
  s.win.show

  if not a.layout.showThemeEditor:
    koi.setFocusCaptured(true)

# }}}
# {{{ closeSplash()
proc closeSplash(a) =
  alias(s, a.splash)

  s.win.destroy
  s.win = nil

  s.vg.deleteImage(s.logoImage)
  s.vg.deleteImage(s.outlineImage)
  s.vg.deleteImage(s.shadowImage)

  s.logoImage = NoImage
  s.outlineImage = NoImage
  s.shadowImage = NoImage

  nvgDeleteContext(s.vg)
  s.vg = nil

  s.show = false

  if not a.layout.showThemeEditor:
    koi.setFocusCaptured(false)

# }}}

# {{{ loadAndSetIcon()
proc loadAndSetIcon(a) =
  alias(p, a.paths)

  var icons: array[5, IconImageObj]

  proc add(idx: Natural, img: ImageData) =
    icons[idx].width  = img.width.int32
    icons[idx].height = img.height.int32
    icons[idx].pixels = cast[ptr uint8](img.data)

  var icon32  = loadImage(p.dataDir / "icon32.png")
  var icon48  = loadImage(p.dataDir / "icon48.png")
  var icon64  = loadImage(p.dataDir / "icon64.png")
  var icon128 = loadImage(p.dataDir / "icon128.png")
  var icon256 = loadImage(p.dataDir / "icon256.png")

  add(0, icon32)
  add(1, icon48)
  add(2, icon64)
  add(3, icon128)
  add(4, icon256)

  a.win.glfwWin.icons = icons

# }}}
# {{{ loadFonts()
proc loadFonts(a) =
  alias(p, a.paths)

  proc loadFont(fontName: string, path: string; a): Font =
    try:
      a.vg.createFont(fontName, path)
    except CatchableError as e:
      log.error(fmt"Cannot load font '{path}'")
      raise e

  discard         loadFont("sans",       p.dataDir / "Roboto-Regular.ttf", a)
  let boldFont  = loadFont("sans-bold",  p.dataDir / "Roboto-Bold.ttf", a)
  let blackFont = loadFont("sans-black", p.dataDir / "Roboto-Black.ttf", a)
  let iconFont  = loadFont("icon",       p.dataDir / "GridmongerIcons.ttf", a)

  discard addFallbackFont(a.vg, boldFont, iconFont)
  discard addFallbackFont(a.vg, blackFont, iconFont)

# }}}
# {{{ loadSplashmages()
proc loadSplashImages(a) =
  alias(s, a.splash)
  alias(p, a.paths)

  s.logo    = loadImage(p.dataDir / "logo.png")
  s.outline = loadImage(p.dataDir / "logo-outline.png")
  s.shadow  = loadImage(p.dataDir / "logo-shadow.png")

  createAlpha(s.logo)
  createAlpha(s.outline)
  createAlpha(s.shadow)

# }}}
# {{{ loadAboutLogoImage()
proc loadAboutLogoImage(a) =
  alias(al, a.dialogs.about.aboutLogo)

  al.logo = loadImage(a.paths.dataDir / "logo-small.png")
  createAlpha(al.logo)

# }}}

# {{{ initGfx()
proc initGfx(a) =
  glfw.initialize()
  let win = newCSDWindow()

  if not gladLoadGL(getProcAddress):
    log.error("Error initialising OpenGL")
    quit(QuitFailure)

  let version  = cast[cstring](glGetString(GL_VERSION))
  let vendor   = cast[cstring](glGetString(GL_VENDOR))
  let renderer = cast[cstring](glGetString(GL_RENDERER))

  let msg = fmt"""
GPU info:
  Vendor:   {vendor}
  Renderer: {renderer}
  Version:  {version}"""

  log.info(msg)

  nvgInit(getProcAddress)
  let vg = nvgCreateContext({nifStencilStrokes, nifAntialias})

  koi.init(vg, getProcAddress)

  a.win = win
  a.vg = vg

# }}}
# {{{ initPaths()
proc initPaths(a) =
  alias(p, a.paths)

  const ImagesDir = "Images"

  p.appDir = getAppDir()

  const ConfigDir = "Config"
  let portableMode = dirExists(p.appDir / ConfigDir)

  let resourcesDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      normalizedPath(p.appDir / ".." / "Resources")
    else:
      p.appDir

  p.dataDir   = resourcesDir / "Data"
  p.manualDir = resourcesDir / "Manual"
  p.themesDir = resourcesDir / "Themes"
  p.themeImagesDir = p.themesDir / ImagesDir

  p.userDataDir = if portableMode:
    p.appDir
  else:
    when defined(macosx):
      getHomeDir() / "Library/Application Support/Gridmonger"
    else:
      getConfigDir() / "Gridmonger"

  p.configDir = p.userDataDir / ConfigDir
  p.configFile = p.configDir / "gridmonger.cfg"

  p.logDir = p.userDataDir / "Logs"
  p.logFile = p.logDir / "gridmonger.log"

  p.autosaveDir = p.userDataDir / "Autosaves"

  p.userThemesDir = p.userDataDir / "User Themes"
  p.userThemeImagesDir = p.userThemesDir / ImagesDir

# }}}
# {{{ createDirs()
proc createDirs(a) =
  alias(p, a.paths)

  createDir(p.userDataDir)
  createDir(p.configDir)
  createDir(p.logDir)
  createDir(p.autosaveDir)
  createDir(p.userThemesDir)
  createDir(p.userThemeImagesDir)

# }}}
# {{{ initPreferences()
proc initPreferences(cfg: HoconNode; a) =
  let prefs = cfg.getObjectOrEmpty("preferences")

  with a.prefs:
    showSplash = prefs.getBoolOrDefault("splash.show-at-startup", true)

    autoCloseSplash = prefs.getBoolOrDefault("splash.auto-close.enabled", false)

    splashTimeoutSecs = prefs.getNaturalOrDefault(
                          "splash.auto-close.timeout-secs", 3
                        ).limit(SplashTimeoutSecsLimits)

    loadLastMap = prefs.getBoolOrDefault("load-last-map", true)

    autosave = prefs.getBoolOrDefault("auto-save.enabled", true)
    autosaveFreqMins = prefs.getNaturalOrDefault(
                         "auto-save.frequency-mins", 2
                       ).limit(AutosaveFreqMinsLimits)

    vsync = prefs.getBoolOrDefault("interface.vsync", true)

    scaleFactor = prefs.getIntOrDefault("interface.scale-percentage", 100)
                       .limit(UIScaleFactorLimits).float / 100

    checkForUpdates = prefs.getBoolOrDefault("check-for-updates", true)

    if prefs.getOpt("modifier-key-mode").isSome:
      modifierKeyMode = prefs.getEnumOrDefault("modifier-key-mode",
                                                ModifierKeyMode)
      when not defined(macosx):
        # Revert it to Ctrl+Alt if using a config copied from a Mac
        modifierKeyMode = mkmControlAlt
    else:
      modifierKeyMode = when defined(macosx): mkmCommandShift
                        else: mkmControlAlt

    const MovementWraparoundKey = "editing.movement-wraparound"
    if prefs.getOpt(MovementWraparoundKey).isSome:
      movementWraparound = prefs.getBoolOrDefault(
        MovementWraparoundKey, false
      )
    else:
      # TODO deprecated keys; drop support for these after a few releases
      let MovementWraparoundKey_v110 = "editing.movement-wrap-around"
      if prefs.getOpt(MovementWraparoundKey_v110).isSome:
        movementWraparound = prefs.getBoolOrDefault(
          MovementWraparoundKey_v110, false
        )
      else:
        let MovementWraparoundKey_v100 = "movement-wrap-around"
        movementWraparound = prefs.getBoolOrDefault(
          MovementWraparoundKey_v100, false
        )

    yubnMovementKeys = prefs.getBoolOrDefault("editing.yubn-movement-keys")

    walkCursorMode = prefs.getEnumOrDefault("editing.walk-cursor-mode",
                                            WalkCursorMode)

    openEndedExcavate = prefs.getBoolOrDefault("editing.open-ended-excavate")

    linkLinesMode = prefs.getEnumOrDefault("editing.link-lines-mode",
                                            LinkLinesMode)

# }}}
# {{{ restoreLayoutsFromConfog()
proc restoreLayoutsFromConfig(cfg: HoconNode; a) =
  proc toLayout(cfg: HoconNode): Layout =
    var l = Layout(
      showCurrentNotePane: cfg.getBoolOrDefault("show-current-note-pane",
                                                 true),
      showNotesListPane: cfg.getBoolOrDefault("show-notes-list-pane", false),
      showToolsPane:     cfg.getBoolOrDefault("show-tools-pane",      true),
      showThemeEditor:   cfg.getBoolOrDefault("show-theme-editor",    false)
    )

    let
      w = cfg.getNaturalOrDefault("window.size.0", DefaultWindowWidth)
             .limit(WindowWidthLimits)

      h = cfg.getNaturalOrDefault("window.size.1", DefaultWindowHeight)
             .limit(WindowHeightLimits)

    # Default to displaying the window centered on the primary monitor
    let
      (_, _, defaultMaxWidth,
             defaultMaxHeight) = glfw.getPrimaryMonitor().workArea

      cx = (defaultMaxWidth  - w) div 2
      cy = (defaultMaxHeight - h) div 2

      x = cfg.getIntOrDefault("window.pos.0", cx)
      y = cfg.getIntOrDefault("window.pos.1", cy)

    l.windowSize   = (w, h)
    l.windowPos    = (x, y)
    l.maximized    = cfg.getBoolOrDefault("window.maximized",      false)
    l.showTitleBar = cfg.getBoolOrDefault("window.show-title-bar", true)

    result = l


  a.layout = cfg.getObjectOrEmpty("last-state.layout").toLayout
  # The theme editor is always hidden at startup
  a.layout.showThemeEditor = false

  restoreLayout(a.layout, a)


  proc maybeSetSavedLayout(idx: Natural; a) =
    var obj = cfg.getObjectOpt(fmt"saved-layouts.{idx}")
    if obj.isSome:
      a.savedLayouts[idx] = obj.get.toLayout.some

  for idx in 0..a.savedLayouts.high:
    maybeSetSavedLayout(idx, a)

# }}}
# {{{ applyWindowConfigOverrides()
proc applyWindowConfigOverrides(cfg: WindowConfig; a) =
  if cfg.layout.isSome:
    restoreLayout(cfg.layout.get, a)

  let (x, y) = a.win.pos
  if cfg.x.isSome: a.win.pos = (cfg.x.get, y)
  if cfg.y.isSome: a.win.pos = (x, cfg.y.get)

  let (width, height) = a.win.size
  if cfg.width.isSome:  a.win.size = (cfg.width.get, height)
  if cfg.height.isSome: a.win.size = (width, cfg.height.get)

  if cfg.maximized.isSome:
    if cfg.maximized.get: a.win.maximize
    else:                 a.win.unmaximize

  if cfg.showTitleBar.isSome:
    a.win.showTitleBar = cfg.showTitleBar.get

  a.win.snapWindowToVisibleArea

# }}}
# {{{ initApp()
proc dropCb(window: Window, paths: PathDropInfo)

proc initApp(configFile: Option[string], mapFile: Option[string],
             winCfg: WindowConfig, hideSplash = false; a) =

  if configFile.isSome:
    a.paths.configFile = configFile.get

  let cfg = loadAppConfigOrDefault(a.paths.configFile)
  initPreferences(cfg, a)

  if a.prefs.autosave:
    appEvents.setAutoSaveTimeout(
      initDuration(minutes = a.prefs.autosaveFreqMins)
    )
  else: appEvents.disableAutoSave()

  with a.ui.notesListState:
    currFilter.scope    = nsfLevel
    currFilter.noteType = NoteTypeFilter.fullSet
    currFilter.orderBy  = noType

  loadFonts(a)
  loadAndSetIcon(a)

  a.doc.undoManager = newUndoManager[Map, UndoStateData]()
  a.ui.drawLevelParams = newDrawLevelParams()

  buildThemeList(a)

  const DefaultThemeName = "Default"

  var themeIndex = findThemeIndex(
    cfg.getStringOrDefault("last-state.theme-name", DefaultThemeName), a
  )
  if themeIndex.isNone:
    themeIndex = findThemeIndex(DefaultThemeName, a)

  if themeIndex.isSome:
    switchTheme(themeIndex.get, a)
  else:
    a.theme.config = DefaultThemeConfig

  a.ui.drawLevelParams.setZoomLevel(a.theme.levelTheme, DefaultZoomLevel)

  a.ui.status.warning.overwrite = true

  # Init map & load last map, or map from command line
  a.doc.map = newMap("Untitled Map", game="", author="",
                     creationTime=currentLocalDatetimeString())

  let mapFileName = if mapFile.isSome: mapFile.get
                    else: cfg.getStringOrDefault("last-state.last-document", "")

  if mapFileName != "":
    discard loadMap(mapFileName, a)
  else:
    setStatusMessage(IconMug, "Welcome to Gridmonger, adventurer!", a)

  updateWalkKeys(a)
  updateShortcuts(a)
  updateLastCursorViewCoords(a)

  a.ui.toolbarDrawParams = newDrawLevelParams()

  a.splash.show = not hideSplash and a.prefs.showSplash
  a.splash.t0 = getMonoTime()

  updateUIScaleFactor(a)
  setSwapInterval(a)

  # Init window
  a.win.renderFramePreCb = proc (win: CSDWindow) = renderFramePreCb(g_app)
  a.win.renderFrameCb    = proc (win: CSDWindow) = renderFrameCb(g_app)

  when not defined(macosx):
    a.win.contentScaleCb = windowContentScaleCb

  a.win.dropCb = dropCb

  restoreLayoutsFromConfig(cfg, a)
  applyWindowConfigOverrides(winCfg, a)

  if a.prefs.checkForUpdates:
    initVersionChecking(a)
    appEvents.fetchLatestVersion()

# }}}
# {{{ cleanup()
proc cleanup(a) =
  log.info("Exiting app...")

  koi.deinit()

  nvgDeleteContext(a.vg)
  if a.splash.vg != nil:
    nvgDeleteContext(a.splash.vg)

  a.win.glfwWin.destroy
  if a.splash.win != nil:
    a.splash.win.destroy

  glfw.terminate()

  log.info("Cleanup successful, bye!")

  if a.logFile != nil:
    a.logFile.close

# }}}
# {{{ crashHandler()

when not defined(DEBUG):

  proc crashHandler(e: ref Exception, a) =
    let doAutosave = a.doc.path != ""
    var crashAutosavePath = ""

    if doAutosave:
      try:
        crashAutosavePath = autoSaveMapOnCrash(a)
      except Exception as e:
        if a.logFile != nil:
          logError(e, "Error autosaving map on crash")

    var msg = "A fatal error has occured, Gridmonger will now exit.\n\n"

    if doAutoSave:
      if crashAutosavePath == "":
        msg &= "Could not autosave map.\n\n"
      else:
        msg &= "The map has been autosaved as '" &
               crashAutosavePath

    msg &= "\n\nIf the problem persists, please refer to the " &
           fmt"'Get Involved' section on the website at {ProjectHomeUrl}"

    when not defined(DEBUG):
      discard osdialog_message(mblError, mbbOk, msg.cstring)

    if a.logFile != nil:
      logError(e, "An unexpected error has occured, exiting")

    quit(QuitFailure)

# }}}

# }}}
# {{{ App events

# {{{ handleFocusEvent()
proc handleFocusEvent(event: AppEvent; a) =
  a.win.requestAttention

# }}}
# {{{ handleOpenFileEvent()
proc handleOpenFileEvent(event: AppEvent; a) =
  closeDialog(a)
  returnToNormalMode(a)
  openMap(event.path, a)
  # TODO not needed on macOS at least
#  a.win.restore
  a.win.focus

# }}}
# {{{ handleAutoSaveEvent()
proc handleAutoSaveEvent(event: AppEvent; a) =
  if a.doc.undoManager.isModified:
    var path = if a.doc.path == "": a.doc.lastSavePath
               else: a.doc.path
    if path == "":
      path = findUniquePath(dir=a.paths.autosaveDir, name=UntitledName,
                            ext=MapFileExt)

    saveMap(path, autosave=true, createBackup=true, a)

# }}}
# {{{ handleVersionUpdateEvent()
proc handleVersionUpdateEvent(event: AppEvent; a) =
  a.latestVersion     = event.versionInfo
  a.versionFetchError = event.error

  if a.latestVersion.isSome:
    let v = a.latestVersion.get
    if v.version > AppVersion and a.dialogs.activeDialog != dlgAbout:
      setWarningMessage(
        "Good news! A more recent version of Gridmonger is available: " &
        fmt"v{v.version} — {v.message}",
        icon=IconMug,
        keepStatusMessage=true, timeout=initDuration(seconds = 7),
        overwrite=false, a=a
      )

# }}}

# {{{ dropCb()
proc dropCb(window: Window, paths: PathDropInfo) =
  if paths.len > 0:
    let path = paths.items.toSeq[0]
    handleOpenFileEvent(AppEvent(kind: aeOpenFile, path: $path), g_app)

# }}}

# }}}

# {{{ main()
proc main() =

  appEvents.initOrQuit()

  when defined(windows):
    discard attachOutputToConsole()

  g_app = new AppContext
  alias(a, g_app)

  try:
    initPaths(a)
    createDirs(a)
    initLogger(a)

    log.info(FullVersionString)
    log.info(CompiledAt)
    log.info(fmt"Paths: {a.paths}")

    let (configFile, mapFile, winCfg) = parseCommandLineParams()
    log.info(fmt"Command line parameters: configFile: {configFile}, " &
             fmt"mapFile: {mapFile}, winCfg: {winCfg}")

    initGfx(a)

    # Handle starting the app bundle by opening a map file in Finder on macOS
    #
    # Waiting "a bit" seems to be the only sort-of reliable way to receive the
    # openFile Cocoa event which then gets mapped to the "Open File" app
    # event.
    when defined(macosx):
      sleep(80)

      let event = appEvents.tryRecv()
      if event.isSome and event.get.kind == aeOpenFile:
        initApp(configFile, mapFile=event.get.path.some, winCfg,
                hideSplash=true, a)
      else:
        initApp(configFile, mapFile, winCfg, a=a)

    else: # Windows, Linux
      initApp(configFile, mapFile, winCfg, a=a)

    a.win.show

    while not a.shouldClose:
      # Render app
      glfw.makeContextCurrent(a.win.glfwWin)

      if a.dialogs.about.aboutLogo.logo.data == nil:
        loadAboutLogoImage(a)

      csdwindow.renderFrame(a.win, a.vg)
      glFlush()

      # Render splash
      if a.splash.win == nil and a.splash.show:
        createSplashWindow(mousePassthrough = a.layout.showThemeEditor, a)
        glfw.makeContextCurrent(a.splash.win)

        if a.splash.logo.data == nil:
          loadSplashImages(a)
        showSplash(a)
        if a.layout.showThemeEditor:
          a.win.focus

      if a.splash.win != nil:
        glfw.makeContextCurrent(a.splash.win)
        renderFrameSplash(a)
        glFlush()

      # Swap buffers
      if a.updateUI:
        glfw.swapBuffers(a.win.glfwWin)

      if a.splash.win != nil:
        glfw.swapBuffers(a.splash.win)

      # Handle app events
      let event = appEvents.tryRecv()
      if event.isSome:
        let event = event.get
        case event.kind
        of aeFocus:         handleFocusEvent(event, a)
        of aeOpenFile:      handleOpenFileEvent(event, a)
        of aeAutoSave:      handleAutoSaveEvent(event, a)
        of aeVersionUpdate: handleVersionUpdateEvent(event, a)

        koi.setFramesLeft()

      # Poll/wait for events
      if koi.shouldRenderNextFrame():
        glfw.pollEvents()
      else:
        glfw.waitEvents()

    cleanup(a)

  except CatchableError as e:
    when defined(DEBUG): raise e
    else: crashHandler(e, a)

# }}}

main()

# vim: et:ts=2:sw=2:fdm=marker
