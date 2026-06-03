import dialogs/common

import mapio


using a: var AppContext

# {{{ openSaveDiscardMapDialog*()
proc openSaveDiscardMapDialog*(nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardMap)
  dlg.nextAction = nextAction
  a.dialogs.activeDialog = dlgSaveDiscardMap

# }}}
# {{{ saveDiscardMapDialog*()
proc saveDiscardMapDialog*(dlg: var SaveDiscardMapDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Map?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made change to the map.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the map?",
    style=a.theme.labelStyle
  )

  # {{{ okAction()
  proc okAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    saveMap(a)

    # If the "Save As" dialog gets displayed and the user presses "Cancel",
    # the path remains empty, in which case we abort calling the next action.
    if a.doc.path != "":
      dlg.nextAction(a)

  # }}}
  # {{{ discardAction()
  proc discardAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  # }}}
  # {{{ cancelAction()
  proc cancelAction(a) =
    closeDialog(a)

  # }}}

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style=a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a):  cancelAction(a)
    elif ke.isShortcutDown(scDiscard, a): discardAction(dlg, a)
    elif ke.isShortcutDown(scAccept, a):  okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
