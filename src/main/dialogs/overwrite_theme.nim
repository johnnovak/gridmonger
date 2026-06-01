# overwrite_theme dialog
#
# Extracted from main/dialogs.nim. Imports main/dialogs/common for the
# shared 7 field templates, dialog constants, and helpers.
# Side effects: koi + nanovg drawing, AppContext.dialogs mutation.

import main/dialogs/common



using a: var AppContext

# {{{ Overwrite theme dialog

proc openOverwriteThemeDialog*(themeName: string,
                              nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.overwriteTheme)

  dlg.themeName = themeName
  dlg.nextAction = nextAction

  a.dialogs.activeDialog = dlgOverwriteTheme


proc overwriteThemeDialog*(dlg: OverwriteThemeDialogParams; a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFloppy}  Overwrite Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h,
            fmt"User theme '{dlg.themeName}' already exists.",
            style=a.theme.labelStyle)

  y += h
  koi.label(
    x, y, DlgWidth, h, "Do you want to overwrite it?",
    style=a.theme.labelStyle
  )

  proc okAction(dlg: OverwriteThemeDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  x -= 20
  if koi.button(x, y, DlgButtonWidth+20, h, fmt"{IconCheck} Overwrite",
                style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += 20
  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if   ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()


# vim: et:ts=2:sw=2:fdm=marker
