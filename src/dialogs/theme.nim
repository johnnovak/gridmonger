import std/os

import dialogs/common
import ../theme


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

# }}}
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

# }}}
# {{{ Copy theme dialog

proc openCopyThemeDialog*(a) =
  alias(dlg, a.dialogs.copyTheme)
  dlg.newThemeName = makeUniqueThemeName(a.currThemeName.name, a)
  a.dialogs.activeDialog = dlgCopyTheme


proc copyThemeDialog*(dlg: var CopyThemeDialogParams; a) =
  const
    DlgWidth = 390.0
    DlgHeight = 170.0
    LabelWidth = 135.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCopy}  Copy Theme",
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


  proc okAction(dlg: CopyThemeDialogParams; a) =
    closeDialog(a)
    let newThemePath = a.paths.userThemesDir / addFileExt(dlg.newThemeName,
                                                          ThemeExt)
    proc copyTheme(a) =
      if copyTheme(a.currThemeName, dlg.newThemeName, newThemePath, a):
        buildThemeList(a)
        # We need to set the current theme index directly (instead of setting
        # nextThemeIndex) to prevent reloading the theme, thus avoid losing
        # any unsaved changed
        let idx = findThemeIndex(dlg.newThemeName, a)
        if idx.isSome:
          a.theme.currThemeIndex = idx.get

    if fileExists(newThemePath):
      openOverwriteThemeDialog(dlg.newThemeName, nextAction = copyTheme, a)
    else:
      copyTheme(a)



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

# }}}
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

# }}}
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
