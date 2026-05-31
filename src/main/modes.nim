# modes
#
# Pure UI-state mode transitions: enterSelectMode / exitSelectMode /
# copySelection. The other previously-scattered mode procs (exitMovePreview,
# exitNudgePreview, returnToNormalMode) call into undoAction and live with
# the action wrappers instead.
# Side effects: AppContext.ui field mutation, status-bar messages.

import std/options

import common               # newSelection, EditMode (emSelect, emNormal)
import domain/selection     # Selection, SelectionBuffer, newSelectionFrom, boundingBox
import domain/level         # newLevelFrom
import main/appcontext
import main/status_msg      # setSelectModeSelectMessage, clearStatusMessage
import main/view            # currLevel
import utils/misc           # alias
import utils/rect           # Rect


using a: var AppContext


# {{{ enterSelectMode()
proc enterSelectMode*(a) =
  let l = currLevel(a)

  a.ui.drawTrail = false
  a.ui.editMode = emSelect
  a.ui.selection = some(newSelection(l.rows, l.cols))
  a.ui.drawLevelParams.drawCursorGuides = true
  setSelectModeSelectMessage(a)

# }}}
# {{{ exitSelectMode()
proc exitSelectMode*(a) =
  a.ui.editMode = emNormal
  a.ui.selection = Selection.none
  a.ui.drawLevelParams.drawCursorGuides = false
  clearStatusMessage(a)

# }}}
# {{{ copySelection()
proc copySelection*(buf: var Option[SelectionBuffer]; a): Option[Rect[Natural]] =
  alias(ui, a.ui)

  let sel = ui.selection.get
  let bbox = sel.boundingBox

  if bbox.isSome:
    let bbox = bbox.get

    buf = some(SelectionBuffer(
      selection: newSelectionFrom(sel, bbox),
      level: newLevelFrom(currLevel(a), bbox)
    ))

  result = bbox

# }}}

# vim: et:ts=2:sw=2:fdm=marker
