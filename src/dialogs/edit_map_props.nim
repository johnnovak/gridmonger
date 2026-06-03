import dialogs/common

import actions


using a: var AppContext

# {{{ openEditMapPropsDialog*()
proc openEditMapPropsDialog*(a) =
  alias(dlg, a.dialogs.editMapProps)
  alias(map, a.doc.map)

  dlg.title        = map.title
  dlg.game         = map.game
  dlg.author       = map.author

  with map.coordOpts:
    dlg.origin      = origin.ord
    dlg.rowStyle    = rowStyle.ord
    dlg.columnStyle = columnStyle.ord
    dlg.rowStart    = $rowStart
    dlg.columnStart = $columnStart

  dlg.notes = map.notes

  a.dialogs.activeDialog = dlgEditMapProps

# }}}
# {{{ editMapPropsDialog*()
proc editMapPropsDialog*(dlg: var EditMapPropsDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  Edit Map Properties",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style=a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 120
  lp.rowWidth = DlgWidth-90
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonGeneralMapFields(a.doc.map, displayCreationTime=true)

  elif dlg.activeTab == 1:  # Coordinates
    coordinateFields()

  elif dlg.activeTab == 2:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = validateCommonGeneralMapFields(dlg)

  if validationError != "":
    koi.label(x, DlgHeight-76, DlgWidth, DlgItemHeight, validationError,
              style=a.theme.errorLabelStyle)

# {{{ okAction()
  proc okAction(dlg: EditMapPropsDialogParams; a) =
    if validationError != "": return

    let coordOpts = CoordinateOptions(
      origin:      CoordinateOrigin(dlg.origin),
      rowStyle:    CoordinateStyle(dlg.rowStyle),
      columnStyle: CoordinateStyle(dlg.columnStyle),
      rowStart:    parseInt(dlg.rowStart),
      columnStart: parseInt(dlg.columnStart)
    )

    actions.setMapProperties(a.doc.map, a.ui.cursor,
                             dlg.title, dlg.game, dlg.author,
                             coordOpts, dlg.notes, a.doc.undoManager)

    setStatusMessage(IconFile, "Map properties updated", a)
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

  dlg.activateFirstTextField = false


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.activeTab = handleTabNavigation(ke, dlg.activeTab, tabLabels.high, a)

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
