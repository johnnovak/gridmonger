import dialogs/common

import actions
import cursor


using a: var AppContext

# {{{ openDeleteLevelDialog*()
proc openDeleteLevelDialog*(a) =
  a.dialogs.activeDialog = dlgDeleteLevel

# }}}
# {{{ deleteLevelDialog*()
proc deleteLevelDialog*(a) =
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)

  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = 136.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete level?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "Do you want to delete the current level?",
            style=a.theme.labelStyle)

# {{{ okAction()
  proc okAction(a) =
    a.ui.drawTrail = false

    let cur = actions.deleteLevel(map, a.ui.cursor, um)
    setCursor(cur, a)

    setStatusMessage(IconTrash, "Level deleted", a)
    closeDialog(a)

# }}}
# {{{ cancelAction()
  proc cancelAction(a) =
    closeDialog(a)

# }}}

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.theme.buttonStyle):
    okAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
