# rename_theme dialog
#
# Extracted from main/dialogs.nim. Imports main/dialogs/common for the
# shared 7 field templates, dialog constants, and helpers.
# Side effects: koi + nanovg drawing, AppContext.dialogs mutation.

import main/dialogs/common
import main/dialogs/overwrite_theme  # openOverwriteThemeDialog

import std/os
import main/themeio              # renameTheme, makeUniqueThemeName, themePath, buildThemeList



using a: var AppContext

# {{{ Rename theme dialog

proc openRenameThemeDialog*(a) =
  alias(dlg, a.dialogs.renameTheme)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgRenameTheme


proc renameThemeDialog*(dlg: var RenameThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconFile}  Rename Theme",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "New theme name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=196, h,
    dlg.newThemeName,
    activate = dlg.activateFirstTextField,
    # TODO disallow invalid path chars?
    style = a.theme.textFieldStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if not gmUtils.isValidFilename(dlg.newThemeName):
    validationError = "Theme name is invalid"

  var validationWarning = ""
  let idx = findThemeIndex(dlg.newThemeName, a)
  if idx.isSome:
    let theme = a.theme.themeNames[idx.get]
    if theme.userTheme:
      validationWarning = "A user theme with this name already exists"
    else:
      validationWarning = "Built-in theme will be shadowed by this name"

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationError(validationError),
              style=a.theme.errorLabelStyle)

  elif validationWarning != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight,
              mkValidationWarning(validationWarning),
              style=a.theme.warningLabelStyle)


  proc okAction(dlg: RenameThemeDialogParams; a) =
    closeDialog(a)
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc renameTheme(a) =
      if renameTheme(a.currThemeName, dlg.newThemeName, newThemePath, a):
        buildThemeList(a)
        # We need to set the current theme index directly (instead of setting
        # nextThemeIndex) to prevent reloading the theme, thus avoid losing
        # any unsaved changed
        let idx = findThemeIndex(dlg.newThemeName, a)
        if idx.isSome:
          a.theme.currThemeIndex = idx.get

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, nextAction = renameTheme, a)
    else:
      renameTheme(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = validationError != "", style = a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style = a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()


# vim: et:ts=2:sw=2:fdm=marker
