import dialogs/common

import actions
import cursor


using a: var AppContext

# {{{ openNewLevelDialog*()
proc openNewLevelDialog*(a) =
  alias(dlg, a.dialogs.newLevel)

  let map = a.doc.map
  var co: CoordinateOptions

  if map.hasLevels:
    let l = currLevel(a)
    dlg.locationName = l.locationName
    dlg.levelName = ""
    dlg.elevation = if l.elevation > 0: $(l.elevation + 1)
                    else:               $(l.elevation - 1)
    dlg.rows = $l.rows
    dlg.cols = $l.cols
    dlg.overrideCoordOpts = l.overrideCoordOpts

    co = coordOptsForCurrLevel(a)

  else:
    dlg.locationName = "Untitled Location"
    dlg.levelName = ""
    dlg.elevation = "0"
    dlg.rows = "16"
    dlg.cols = "16"
    dlg.overrideCoordOpts = false

    co = map.coordOpts

  dlg.origin      = co.origin.ord
  dlg.rowStyle    = co.rowStyle.ord
  dlg.columnStyle = co.columnStyle.ord
  dlg.rowStart    = $co.rowStart
  dlg.columnStart = $co.columnStart

  dlg.enableRegions   = false
  dlg.colsPerRegion   = "16"
  dlg.rowsPerRegion   = "16"
  dlg.perRegionCoords = true

  dlg.activeTab = 0

  a.dialogs.activeDialog = dlgNewLevel

# }}}
# {{{ newLevelDialog*()
proc newLevelDialog*(dlg: var LevelPropertiesDialogParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth  = 460.0
    DlgHeight = 436.0
    TabWidth  = 400.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Level",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Coordinates", "Regions", "Notes"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style=a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.rowWidth = DlgWidth-80
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    commonLevelFields(dimensionsDisabled=false)

    group:
      koi.label("Fill with empty floors", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.fillWithEmptyFloors, style=a.theme.checkBoxStyle)

  elif dlg.activeTab == 1:  # Coordinates
    group:
      koi.label("Override map settings", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.overrideCoordOpts, style=a.theme.checkBoxStyle)

      if dlg.overrideCoordOpts:
        coordinateFields()

  elif dlg.activeTab == 2:  # Regions
    regionFields()

  elif dlg.activeTab == 3:  # Notes
    noteFields(DlgWidth)

  koi.endView()


  # Validation
  var validationError = ""
  validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
    if validationError != "": return

    a.ui.drawTrail = false

    let
      rows = parseInt(dlg.rows)
      cols = parseInt(dlg.cols)

    var fillFloorColor: Option[Natural]

    let cur = actions.addNewLevel(
      a.doc.map,
      a.ui.cursor,

      locationName = dlg.locationName,
      levelName    = dlg.levelName,
      elevation    = parseInt(dlg.elevation),

      rows           = rows,
      cols           = cols,
      fillFloorColor = if dlg.fillWithEmptyFloors:
                         a.ui.currFloorColor.Natural.some
                       else: Natural.none,

      dlg.overrideCoordOpts,
      coordOpts = CoordinateOptions(
        origin:      CoordinateOrigin(dlg.origin),
        rowStyle:    CoordinateStyle(dlg.rowStyle),
        columnStyle: CoordinateStyle(dlg.columnStyle),
        rowStart:    parseInt(dlg.rowStart),
        columnStart: parseInt(dlg.columnStart)
      ),

      regionOpts = RegionOptions(
        enabled:         dlg.enableRegions,
        colsPerRegion:   parseInt(dlg.colsPerRegion),
        rowsPerRegion:   parseInt(dlg.rowsPerRegion),
        perRegionCoords: dlg.perRegionCoords
      ),

      dlg.notes,
      a.doc.undoManager
    )
    setCursor(cur, a)

    setStatusMessage(IconFile, fmt"New {rows}×{cols} level created", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


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
