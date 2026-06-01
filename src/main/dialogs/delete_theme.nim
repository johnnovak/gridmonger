# delete_theme dialog
#
# Extracted from main/dialogs.nim. Imports main/dialogs/common for the
# shared 7 field templates, dialog constants, and helpers.
# Side effects: koi + nanovg drawing, AppContext.dialogs mutation.

import main/dialogs/common

import main/themeio              # deleteTheme, buildThemeList



using a: var AppContext

# {{{ Delete theme dialog

proc openDeleteThemeDialog*(a) =
  a.dialogs.activeDialog = dlgDeleteTheme


proc deleteThemeDialog*(a) =
  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = ConfirmDlgHeight

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete Theme?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(
    x, y, DlgWidth, h, "Are you sure you want to delete this theme?",
    style=a.theme.labelStyle
  )

  proc okAction(a) =
    if deleteTheme(a.currThemeName, a):
      buildThemeList(a)
      with a.theme:
        nextThemeIndex = currThemeIndex.clampMax(themeNames.high).some

    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style = a.theme.buttonStyle):
    okAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
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
