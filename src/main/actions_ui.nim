# actions_ui
#
# Undoable + non-undoable action wrappers (the UI-side wrappers around the
# domain action procs in actions.nim). undoAction, redoAction, setFloorAction,
# cycleFloorGroupAction, startExcavateTunnelAction, reloadTheme, selectPrev/
# NextTheme, etc. Also picks up the mode-exit/return-to-normal procs that
# call undoAction (exitMovePreviewMode, exitNudgePreviewMode,
# returnToNormalMode) — they were relocated in Phase 2 to live next to
# undoAction.
# Side effects: AppContext state mutation, status-bar messages, dialog opens.

import std/math
import std/options
import std/strformat
import std/tables

import actions
import common
import domain/all
import main/appcontext
import main/cursor          # moveCursorTo, setCursor
import main/dialogs         # openSaveDiscardMapDialog, openSaveDiscardThemeDialog
import main/mapio           # saveMap, saveMapAs, loadMap
import main/modes           # exitSelectMode, copySelection
import main/panes/statusbar
import ui/all
import undomanager
import utils/all


using a: var AppContext

# {{{ undoAction()
proc undoAction*(a) =
  alias(um, a.doc.undoManager)

  if um.canUndo:
    let
      drawTrail     = a.ui.drawTrail
      undoStateData = um.undo(a.doc.map)
      newCur        = undoStateData.undoLocation
      levelChange   = newCur.levelId != a.ui.cursor.levelId

    a.ui.drawTrail = false

    moveCursorTo(newCur, a)

    if not levelChange:
      a.ui.drawTrail = drawTrail

    setStatusMessage(IconUndo,
                     fmt"Undid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to undo", a=a)

# }}}
# {{{ redoAction()
proc redoAction*(a) =
  alias(um, a.doc.undoManager)

  if um.canRedo:
    let
      drawTrail     = a.ui.drawTrail
      undoStateData = um.redo(a.doc.map)
      newCur        = undoStateData.location
      levelChange   = newCur.levelId != a.ui.cursor.levelId

    a.ui.drawTrail = false

    moveCursorTo(newCur, a)

    if not levelChange:
      a.ui.drawTrail = drawTrail

    setStatusMessage(IconRedo,
                     fmt"Redid action: {undoStateData.actionName}", a)
  else:
    setWarningMessage("Nothing to redo", a=a)

# }}}
# {{{ exitMovePreviewMode()
proc exitMovePreviewMode*(a) =
  undoAction(a)
  a.doc.undoManager.truncateUndoState()
  a.ui.editMode = emNormal
  clearStatusMessage(a)

# }}}
# {{{ exitNudgePreviewMode()
proc exitNudgePreviewMode*(a) =
  alias(ui, a.ui)
  alias(map, a.doc.map)

  let cur = a.ui.cursor

  ui.editMode = emNormal

  # Reset the current level reference to the level in the nudge buffer
  map.levels[cur.levelId] = ui.nudgeBuf.get.level
  ui.nudgeBuf = SelectionBuffer.none

  clearStatusMessage(a)

# }}}
# {{{ returnToNormalMode()
proc returnToNormalMode*(a) =
  alias(ui, a.ui)

  case ui.editMode
  of emNormal: discard

  of emMovePreview:
    exitMovePreviewMode(a)

  of emNudgePreview:
    exitNudgePreviewMode(a)

  of emSelect, emSelectDraw, emSelectErase, emSelectRect:
    exitSelectMode(a)

  else:
    ui.editMode = emNormal
    clearStatusMessage(a)

# }}}

# {{{ setFloorAction()
proc setFloorAction*(f: Floor; a) =
  let orientation = if f in RotatableFloors: dirN
                    elif f in HorizVertFloors:
                      a.doc.map.guessFloorOrientation(a.ui.cursor)
                    else: Horiz

  actions.setFloor(a.doc.map, a.ui.cursor, f, orientation, a.ui.currFloorColor,
                   a.doc.undoManager)

  setStatusMessage(fmt"Set floor type – {f}", a)

# }}}
# {{{ cycleFloorGroupAction()
proc cycleFloorGroupAction*(floors: seq[Floor], forward: bool; a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    var i = floors.find(floor)
    if i > -1:
      if forward: inc(i) else: dec(i)
      floor = floors[i.floorMod(floors.len)]
    else:
      floor = if forward: floors[0] else: floors[^1]

    setFloorAction(floor, a)
  else:
    setWarningMessage("Cannot set floor type of an empty cell", a=a)

# }}}
# {{{ startExcavateTunnelAction()
proc startExcavateTunnelAction*(a) =
  let cur = a.ui.cursor
  a.ui.prevMoveDir = CardinalDir.none

  actions.excavateTunnel(a.doc.map, loc=cur, undoLoc=cur, a.ui.currFloorColor,
                         um=a.doc.undoManager, groupWithPrev=false)

  setStatusMessage(IconPencil, "Excavate tunnel", @[IconArrowsAll,
                   "excavate"], a)

# }}}
# {{{ startEraseCellsAction()
proc startEraseCellsAction*(a) =
  let cur = a.ui.cursor
  actions.eraseCell(a.doc.map, loc=cur, undoLoc=cur,
                    a.doc.undoManager, groupWithPrev=false)

  setStatusMessage(IconEraser, "Erase cell", @[IconArrowsAll, "erase"], a)

# }}}
# {{{ startEraseTrailAction()
proc startEraseTrailAction*(a) =
  let cur = a.ui.cursor
  actions.eraseTrail(a.doc.map, loc=cur, undoLoc=cur, a.doc.undoManager)

  setStatusMessage(IconEraser, "Erase trail", @[IconArrowsAll, "erase"], a)

# }}}

# {{{ setDrawWallActionMessage()

proc mkRepeatWallActionString*(name: string; a): string =
  let action = $a.ui.drawWallRepeatAction
  fmt"repeat {action} {name}"


proc doSetDrawWallActionMessage*(name: string; a) =
  var commands = @[IconArrowsAll, "set/clear"]

  if a.ui.drawWallRepeatAction != dwaNone:
    commands.add("Shift")
    commands.add(mkRepeatWallActionString(name, a))

  setStatusMessage(IconBorders, fmt"Draw {name}", commands, a)


proc setDrawWallActionMessage*(a) =
  doSetDrawWallActionMessage(name = "wall", a)

# }}}
# {{{ setDrawWallActionRepeatMessage()
proc doSetDrawWallActionRepeatMessage*(name: string, a) =
  let icon = if a.ui.drawWallRepeatDirection.isHoriz: IconArrowsVert
             else:                                    IconArrowsHoriz

  setStatusMessage(IconBorders, fmt"Draw {name} repeat",
                   @[icon, mkRepeatWallActionString(name, a)], a)


proc setDrawWallActionRepeatMessage*(a) =
  doSetDrawWallActionRepeatMessage(name = "wall", a)

# }}}
# {{{ setDrawSpecialWallActionMessage()
proc setDrawSpecialWallActionMessage*(a) =
  doSetDrawWallActionMessage(name = "special wall", a)

# }}}
# {{{ setDrawSpecialWallActionRepeatMessage()
proc setDrawSpecialWallActionRepeatMessage*(a) =
  doSetDrawWallActionRepeatMessage(name = "special wall", a)

# }}}

# }}}
# {{{ Non-undoable actions

# {{{ newMap()
proc newMap*(a) =
  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(nextAction = openNewMapDialog, a)
  else:
    openNewMapDialog(a)

# }}}
# {{{ openMap()
proc openMap*(a) =

  proc requestOpenMap(a) =
    when defined(DEBUG): discard
    else:
      let path = fileDialog(fdOpenFile, filters=GridmongerMapFileFilter)
      if path != "":
        discard loadMap(path, a)

  proc handleMapModified(a) =
    if a.doc.undoManager.isModified:
      openSaveDiscardMapDialog(nextAction = requestOpenMap, a)
    else:
      requestOpenMap(a)

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = handleMapModified, a)
  else:
    handleMapModified(a)


proc openMap*(path: string; a) =
  proc doOpenMap(a) =
    discard loadMap(path, a)

  if a.doc.undoManager.isModified:
    openSaveDiscardMapDialog(nextAction = doOpenMap, a)
  else:
    doOpenMap(a)

# }}}

# {{{ reloadTheme()
proc reloadTheme*(a) =

  proc doReloadTheme(a) =
    a.theme.nextThemeIndex = a.theme.currThemeIndex.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = doReloadTheme, a)
  else:
    doReloadTheme(a)

# }}}
# {{{ selectPrevTheme()
proc selectPrevTheme*(a) =

  proc prevTheme(a) =
    var i = a.theme.currThemeIndex
    if i == 0: i = a.theme.themeNames.high else: dec(i)
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = prevTheme, a)
  else:
    prevTheme(a)

# }}}
# {{{ selectNextTheme()
proc selectNextTheme*(a) =

  proc nextTheme(a) =
    var i = a.theme.currThemeIndex
    inc(i)
    if i > a.theme.themeNames.high: i = 0
    a.theme.nextThemeIndex = i.some

  if a.themeEditor.modified:
    openSaveDiscardThemeDialog(nextAction = nextTheme, a)
  else:
    nextTheme(a)

# }}}

# {{{ selectPrevLevel()
proc selectPrevLevel*(a) =
  alias(map, a.doc.map)

  var cur = a.ui.cursor
  let levelIdx = map.sortedLevelIds.find(cur.levelId)
  assert levelIdx > -1

  if levelIdx > 0:
    cur.levelId = map.sortedLevelIds[levelIdx-1]
    setCursor(cur, a)

# }}}
# {{{ selectNextLevel()
proc selectNextLevel*(a) =
  alias(map, a.doc.map)

  var cur = a.ui.cursor
  let levelIdx = map.sortedLevelIds.find(cur.levelId)
  assert levelIdx > -1

  if levelIdx < map.sortedLevelNames.high:
    cur.levelId = map.sortedLevelIds[levelIdx+1]
    setCursor(cur, a)

# }}}
# {{{ centerCursorAfterZoom()
proc centerCursorAfterZoom*(a) =
  alias(dp, a.ui.drawLevelParams)
  let cur = a.ui.cursor

  let viewCol = round(a.ui.prevCursorViewX / dp.gridSize).int
  let viewRow = round(a.ui.prevCursorViewY / dp.gridSize).int
  dp.viewStartCol = (cur.col - viewCol).clampMin(0)
  dp.viewStartRow = (cur.row - viewRow).clampMin(0)

# }}}
# {{{ zoomIn()
proc zoomIn*(a) =
  incZoomLevel(a.theme.levelTheme, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}
# {{{ zoomOut()
proc zoomOut*(a) =
  decZoomLevel(a.theme.levelTheme, a.ui.drawLevelParams)
  centerCursorAfterZoom(a)

# }}}

# {{{ selectSpecialWall()
proc selectSpecialWall*(index: Natural; a) =
  assert index <= SpecialWalls.high
  a.ui.currSpecialWall = index

# }}}
# {{{ selectPrevFloorColor()
proc selectPrevFloorColor*(a) =
  if a.ui.currFloorColor > 0: dec(a.ui.currFloorColor)
  else: a.ui.currFloorColor = a.theme.levelTheme.floorBackgroundColor.high

# }}}
# {{{ selectNextFloorColor()
proc selectNextFloorColor*(a) =
  if a.ui.currFloorColor < a.theme.levelTheme.floorBackgroundColor.high:
    inc(a.ui.currFloorColor)
  else: a.ui.currFloorColor = 0

# }}}
# {{{ pickFloorColor()
proc pickFloorColor*(a) =
  var floor = a.doc.map.getFloor(a.ui.cursor)

  if floor != fEmpty:
    a.ui.currFloorColor = a.doc.map.getFloorColor(a.ui.cursor)
    setStatusMessage(IconColorPicker, "Picked floor colour", a)
  else:
    setWarningMessage("Cannot pick floor colour of an empty cell", a=a)

# }}}
# {{{ selectFloorColor()
proc selectFloorColor*(index: Natural; a) =
  assert index <= LevelTheme.floorBackgroundColor.high
  a.ui.currFloorColor = index

# }}}

# {{{ enterDrawWallMode()
proc enterDrawWallMode*(specialWall: bool; a) =
  a.ui.editMode = if specialWall: emDrawSpecialWall else: emDrawWall
  a.ui.drawWallRepeatAction = dwaNone

  if specialWall:
    setDrawSpecialWallActionMessage(a)
  else:
    setDrawWallActionMessage(a)

# }}}
# {{{ toggleThemeEditor()
proc toggleThemeEditor*(a) =
  toggleShowOption(a.layout.showThemeEditor, NoIcon, "Theme editor pane", a)

# }}}
# {{{ showQuickReference()
proc showQuickReference*(a) =
  a.ui.showQuickReference = true
  setStatusMessage(
    IconQuestion, "Quick keyboard reference",
    @[fmt"Ctrl{HairSp}+{HairSp}{IconArrowsHoriz}",          "switch tab",
      fmt"Esc{HairSp}/{HairSp}Space{HairSp}/{HairSp}Enter", "exit",
      "F1", "open user manual"], a)

# }}}
# {{{ toggleTitleBar()
proc toggleTitleBar*(a) =
  toggleShowOption(a.layout.showTitleBar, NoIcon, "Title bar", a)
  a.win.showTitleBar = a.layout.showTitleBar

# }}}


# vim: et:ts=2:sw=2:fdm=marker
