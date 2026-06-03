import dialogs/common

import actions


using a: var AppContext

# {{{ openEditRegionPropertiesDialog*()
proc openEditRegionPropertiesDialog*(a) =
  alias(dlg, a.dialogs.editRegionProps)

  let region = currRegion(a).get
  dlg.name  = region.name
  dlg.notes = region.notes

  a.dialogs.activeDialog = dlgEditRegionProps

# }}}
# {{{ editRegionPropsDialog*()
proc editRegionPropsDialog*(dlg: var EditRegionPropsParams; a) =
  const
    DlgWidth = 486.0
    DlgHeight = 348.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let l = currLevel(a)

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconFile}  Edit Region Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Name", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=294, h,
    dlg.name,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind: tckString,
      minLen: RegionNameLimits.minRuneLen,
      maxLen: RegionNameLimits.maxRuneLen.some
    ).some,
    style = a.theme.textFieldStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Notes", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=149,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.name == "":
    validationError = mkValidationError("Name is mandatory")
  else:
    if dlg.name != currRegion(a).get.name:
      for name in l.regions.sortedRegionNames:
        if name == dlg.name:
          validationError = mkValidationError(
            "A region already exists with the same name"
          )
          break

  y += 172

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.errorLabelStyle)
    y += h

# {{{ okAction()
  proc okAction(dlg: EditRegionPropsParams; a) =
    alias(map, a.doc.map)
    let cur = a.ui.cursor

    let regionCoords = map.getRegionCoords(cur)
    let region = initRegion(name=dlg.name, notes=dlg.notes)

    actions.setRegionProperties(map, cur, regionCoords, region,
                                a.doc.undoManager)

    setStatusMessage(IconFile, "Region properties updated", a)
    closeDialog(a)

# }}}
# {{{ cancelAction()
  proc cancelAction(a) =
    closeDialog(a)

# }}}

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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

# vim: et:ts=2:sw=2:fdm=marker
