import dialogs/common

import actions
import cursor


using a: var AppContext

# {{{ openResizeLevelDialog*()
proc openResizeLevelDialog*(a) =
  alias(dlg, a.dialogs.resizeLevel)

  let l = currLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter

  a.dialogs.activeDialog = dlgResizeLevel

# }}}
# {{{ resizeLevelDialog*()
proc resizeLevelDialog*(dlg: var ResizeLevelDialogParams; a) =
  const
    DlgWidth = 270.0
    DlgHeight = 300.0
    LabelWidth = 80.0
    PadYSmall = 32
    PadYLarge = 40

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconEnlarge}  Resize Level",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Columns", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.cols,
    activate = dlg.activateFirstTextField,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
      minInt: LevelColumnsLimits.minInt,
      maxInt: LevelColumnsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  y += PadYSmall
  koi.label(x, y, LabelWidth, h, "Rows", style=a.theme.labelStyle)
  koi.textField(
    x + LabelWidth, y, w=DlgNumberWidth, h,
    dlg.rows,
    constraint = TextFieldConstraint(
      kind:   tckInteger,
      minInt: LevelRowsLimits.minInt,
      maxInt: LevelRowsLimits.maxInt
    ).some,
    style = a.theme.textFieldStyle
  )

  const IconsPerRow = 3

  const AnchorIcons = @[
    IconArrowUpLeft,   IconArrowUp,   IconArrowUpRight,
    IconArrowLeft,     IconCircleInv, IconArrowRight,
    IconArrowDownLeft, IconArrowDown, IconArrowDownRight
  ]

  y += PadYLarge
  koi.label(x, y, LabelWidth, h, "Anchor", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, 35, 35,
    labels = AnchorIcons,
    dlg.anchor,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: IconsPerRow),
    style = a.theme.iconRadioButtonsStyle
  )

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  dlg.activateFirstTextField = false

  # {{{ okAction()
  proc okAction(dlg: ResizeLevelDialogParams; a) =
    let newRows = parseInt(dlg.rows)
    let newCols = parseInt(dlg.cols)

    let align = case dlg.anchor
    of raTopLeft:     NorthWest
    of raTop:         North
    of raTopRight:    NorthEast
    of raLeft:        West
    of raCenter:      {}
    of raRight:       East
    of raBottomLeft:  SouthWest
    of raBottom:      South
    of raBottomRight: SouthEast

    let newCur = actions.resizeLevel(a.doc.map, a.ui.cursor, newRows, newCols,
                                     align, a.doc.undoManager)
    moveCursorTo(newCur, a)

    a.ui.drawTrail = false

    setStatusMessage(IconEnlarge, "Level resized", a)
    closeDialog(a)

  # }}}
  # {{{ cancelAction()
  proc cancelAction(a) =
    closeDialog(a)
  # }}}

  let l = currLevel(a)
  var sizeChanged = false
  try:
    sizeChanged = parseInt(dlg.rows) != l.rows or
                  parseInt(dlg.cols) != l.cols
  except: discard

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled = not sizeChanged,
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.anchor = ResizeAnchor(
      handleGridRadioButton(ke, ord(dlg.anchor), AnchorIcons.len, IconsPerRow)
    )

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a) and sizeChanged: okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# vim: et:ts=2:sw=2:fdm=marker
