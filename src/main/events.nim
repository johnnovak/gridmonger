import std/algorithm
import std/math
import std/options
import std/sequtils
import std/sets
import std/strformat
import std/strutils
import std/tables

import glfw
import koi
from koi/utils import lerp, invLerp, remap
import with

import actions
import io/persistence
import common
import domain/level
import domain/map
import domain/selection
import main/actions_ui
import main/appcontext
import main/configio
import main/constants
import main/cursor
import main/dialogs
import main/keyboard
import main/mapio
import main/views/statusbar
import main/theme
import main/view
import ui/csdwindow
import ui/drawlevel
import ui/icons
import utils/misc
import utils/rect


using a: var AppContext

# {{{ setSelectModeSpecialActionsMessage()
proc setSelectModeSpecialActionsMessage(a) =
  setStatusMessage(
    IconGrid, "Mark selection",
    @[scSelectionEraseArea.toStr(a),         "erase",
      scSelectionFillArea.toStr(a),          "fill",
      scSelectionSurroundArea.toStr(a),      "surround",
      scSelectionCropArea.toStr(a),          "crop",
      scSelectionMove.toStr(a),              "move",
      scSelectionSetFloorColorArea.toStr(a), "set colour"],
    a
  )

# }}}
# {{{ setSelectJumpToLinkSrcActionMessage()
proc setSelectJumpToLinkSrcActionMessage(a) =
  let currIdx = a.ui.jumpToSrcLocationIdx + 1
  let count = a.ui.jumpToSrcLocations.len
  let floor = a.doc.map.getFloor(a.ui.jumpToDestLocation)

  setStatusMessage(IconLink,
                   fmt"Select {linkFloorToString(floor)} " &
                   fmt"source ({currIdx} of {count})",
                   @[IconArrowsAll, "next/prev", "Enter/Esc", "exit"], a)

# }}}
# {{{ setSetLinkDestinationMessage()
proc setSetLinkDestinationMessage(floor: Floor; a) =
  setStatusMessage(IconLink,
                   fmt"Set {linkFloorToString(floor)} destination",
                   @[IconArrowsAll, "select cell",
                   scAccept.toStr(a, idx=0), "set",
                   scCancel.toStr(a, idx=0), "cancel"], a)
# }}}

# {{{ mkWraparoundMessage()
proc mkWraparoundMessage(a): string =
  "wraparound: " & (if a.ui.pasteWraparound: "on" else: "off")

# }}}
# {{{ setNudgePreviewModeMessage()
proc setNudgePreviewModeMessage(a) =
  setStatusMessage(IconArrowsAll, "Nudge level",
                   @[IconArrowsAll, "nudge",
                   scTogglePasteWraparound.toStr(a), mkWraparoundMessage(a),
                   "Enter", "confirm", "Esc", "cancel"], a)

# }}}
# {{{ setPastePreviewModeMessage()
proc setPastePreviewModeMessage(a) =
  setStatusMessage(IconPaste, "Paste selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "paste", "Esc", "cancel"], a)

# }}}
# {{{ setMovePreviewModeMessage()
proc setMovePreviewModeMessage(a) =
  setStatusMessage(IconArrowsAll, "Move selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "confirm", "Esc", "cancel"], a)

# }}}

# {{{ handleLevelMouseEvents()
proc handleLevelMouseEvents*(a) =

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

# {{{ handleGlobalKeyEvents()

# TODO separate into level events and global events?
# {{{ handleMoveWalk()
proc handleMoveWalk(ke: Event; a) =
  alias(ui, a.ui)

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
# {{{ handleMoveCursor()
proc handleMoveCursor(ke: Event; allowPan, allowJump, allowWasdKeys: bool,
                      allowDiagonal: bool; a): bool =
  alias(ui, a.ui)

  if allowDiagonal:
    # Ignore Y/U/B/N keys if YUBN movement is not enabled in the prefs
    if not a.prefs.yubnMovementKeys and ke.key in DiagonalMoveLetterKeys:
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
  alias(ui,  a.ui)
  alias(map, a.doc.map)
  alias(um,  a.doc.undoManager)

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

proc handleGlobalKeyEvents*(a) =
  alias(ui,   a.ui)
  alias(map,  a.doc.map)
  alias(um,   a.doc.undoManager)
  alias(opts, a.opts)
  alias(dp,   a.ui.drawLevelParams)

  var l = currLevel(a)

  let yubnMode = a.prefs.yubnMovementKeys

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
proc handleGlobalKeyEvents_NoLevels*(a) =
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

# vim: et:ts=2:sw=2:fdm=marker
