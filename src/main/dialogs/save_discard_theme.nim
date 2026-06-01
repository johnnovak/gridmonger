# save_discard_theme dialog
#
# Extracted from main/dialogs.nim. Imports main/dialogs/common for the
# shared 7 field templates, dialog constants, and helpers.
# Side effects: koi + nanovg drawing, AppContext.dialogs mutation.

import main/dialogs/common

import main/themeio              # saveTheme



using a: var AppContext

# {{{ Save/discard theme changes dialog

proc openSaveDiscardThemeDialog*(nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardTheme)
  dlg.nextAction = nextAction
  a.dialogs.activeDialog = dlgSaveDiscardTheme


proc saveDiscardThemeDialog*(dlg: SaveDiscardThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Save Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "You have made changes to the theme.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to save the theme?",
    style=a.theme.labelStyle
  )

  proc okAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    saveTheme(a)
    dlg.nextAction(a)

  proc discardAction(dlg: SaveDiscardThemeDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 3)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Save",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconTrash} Discard",
                style = a.theme.buttonStyle):
    discardAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
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


# vim: et:ts=2:sw=2:fdm=marker
