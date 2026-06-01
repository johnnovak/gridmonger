# dialogs
#
# All dialog procs — about, preferences, save/discard map, new/edit map,
# new/edit/resize/delete level, edit note/label/region, the four theme
# dialogs (save-discard, copy, rename, delete, overwrite) — plus the
# shared dialog helpers (validation templates, common field templates,
# layout helpers, closeDialog).
#
# Each dialog proc both stores transient state (in AppContext.dialogs.X)
# and renders the UI via koi. Triggered by openXxxDialog wrappers that
# set activeDialog; closed by closeDialog which clears activeDialog.
#
# Sub-splitting into one file per dialog is a planned follow-up; the
# 7 shared field-template macros (coordinateFields, regionFields,
# noteFields, etc.) implicitly capture `a` and `dlg` from the caller's
# scope, so per-file splitting requires the facade re-export pattern.
#
# Side effects: drawing via koi/nanovg, AppContext state mutation.

import std/browsers       # openDefaultBrowser
import std/lenientops
import std/math
import std/options
import std/os               # `/`, addFileExt
import std/sequtils
import std/strformat
import std/strutils
import std/tables
import std/times
import std/unicode

import glfw
import koi
import nanovg
import semver
import with

import actions
import appevents
import cfghelper
import common
import domain/all
import io/persistence
import main/appcontext
import main/configio        # saveAppConfig
import main/constants
import main/cursor          # centerCursorAt, moveCursorTo, resetCursorAndViewStart
import main/dialogs/common  # 7 shared templates + dialog constants + helpers
import main/keyboard        # updateShortcuts, primaryModDown, isShortcutDown, toStr
import main/mapio           # saveMap, loadMap
import main/panes/statusbar
import main/themeio
import main/versioncheck    # initVersionChecking
import main/view            # currLevel, currRegion, coordOptsForCurrLevel, calculateLevelDrawArea, mainPaneRect
import ui/all
import undomanager
import utils/all
import utils/misc as gmUtils


using a: var AppContext



# {{{ Save/discard map changes dialog

proc openSaveDiscardMapDialog*(nextAction: proc (a: var AppContext); a) =
  alias(dlg, a.dialogs.saveDiscardMap)
  dlg.nextAction = nextAction
  a.dialogs.activeDialog = dlgSaveDiscardMap


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

  proc okAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    saveMap(a)

    # If the "Save As" dialog gets displayed and the user presses "Cancel",
    # the path remains empty, in which case we abort calling the next action.
    if a.doc.path != "":
      dlg.nextAction(a)

  proc discardAction(dlg: SaveDiscardMapDialogParams; a) =
    closeDialog(a)
    dlg.nextAction(a)

  proc cancelAction(a) =
    closeDialog(a)

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

# {{{ New map dialog

proc openNewMapDialog*(a) =
  alias(dlg, a.dialogs.newMap)

  with a.doc.map.coordOpts:
    dlg.title        = "Untitled Map"
    dlg.game         = ""
    dlg.author       = ""

    dlg.origin       = origin.ord
    dlg.rowStyle     = rowStyle.ord
    dlg.columnStyle  = columnStyle.ord
    dlg.rowStart     = $rowStart
    dlg.columnStart  = $columnStart

    dlg.notes        = ""

  dlg.activeTab = 0

  a.dialogs.activeDialog = dlgNewMap


proc newMapDialog*(dlg: var NewMapDialogParams; a) =
  const
    DlgWidth = 430.0
    DlgHeight = 382.0
    TabWidth = 370.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconNewFile}  New Map",
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
    commonGeneralMapFields(a.doc.map, displayCreationTime=false)

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


  proc okAction(dlg: NewMapDialogParams; a) =
    if validationError != "": return

    a.ui.drawTrail = false

    setNextLevelId(0)

    a.doc.path = ""
    a.doc.map = newMap(dlg.title, dlg.game, dlg.author,
                       creationTime=now().format("yyyy-MM-dd HH:mm:ss"))

    with a.doc.map.coordOpts:
      origin      = CoordinateOrigin(dlg.origin)
      rowStyle    = CoordinateStyle(dlg.rowStyle)
      columnStyle = CoordinateStyle(dlg.columnStyle)
      rowStart    = parseInt(dlg.rowStart)
      columnStart = parseInt(dlg.columnStart)

    a.doc.map.notes = dlg.notes

    initUndoManager(a.doc.undoManager)

    appEvents.updateLastSavedTime()

    resetCursorAndViewStart(a)
    setStatusMessage(IconFile, "New map created", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                disabled=validationError != "", style=a.theme.buttonStyle):
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
# {{{ Edit map properties dialog

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

# {{{ New level dialog

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
# {{{ Edit level properties dialog

proc openEditLevelPropsDialog*(a) =
  alias(dlg, a.dialogs.editLevelProps)

  let l = currLevel(a)

  dlg.locationName = l.locationName
  dlg.levelName = l.levelName
  dlg.elevation = $l.elevation
  dlg.rows = $l.rows
  dlg.cols = $l.cols

  let co = coordOptsForCurrLevel(a)
  dlg.overrideCoordOpts = l.overrideCoordOpts
  dlg.origin            = co.origin.ord
  dlg.rowStyle          = co.rowStyle.ord
  dlg.columnStyle       = co.columnStyle.ord
  dlg.rowStart          = $co.rowStart
  dlg.columnStart       = $co.columnStart

  let ro = l.regionOpts
  dlg.enableRegions   = ro.enabled
  dlg.colsPerRegion   = $ro.colsPerRegion
  dlg.rowsPerRegion   = $ro.rowsPerRegion
  dlg.perRegionCoords = ro.perRegionCoords

  dlg.notes = l.notes

  a.dialogs.activeDialog = dlgEditLevelProps


proc editLevelPropsDialog*(dlg: var LevelPropertiesDialogParams; a) =
  alias(map, a.doc.map)

  const
    DlgWidth = 460.0
    DlgHeight = 436.0
    TabWidth = 400.0

  koi.beginDialog(DlgWidth, DlgHeight,
                  fmt"{IconNewFile}  Edit Level Properties",
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
    commonLevelFields(dimensionsDisabled=true)

  elif dlg.activeTab == 1:  # Coordinates
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


  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""

  let l = currLevel(a)
  if dlg.locationName != l.locationName or
     dlg.levelName != l.levelName or
     dlg.elevation != $l.elevation:

    validateLevelFields(dlg, map, validationError)

  if validationError != "":
    koi.label(x, DlgHeight - 115, DlgWidth - 60, 60, validationError,
              style=a.theme.errorLabelStyle)


  proc okAction(dlg: LevelPropertiesDialogParams; a) =
    if validationError != "": return

    let elevation = parseInt(dlg.elevation)

    let coordOpts = CoordinateOptions(
      origin:      CoordinateOrigin(dlg.origin),
      rowStyle:    CoordinateStyle(dlg.rowStyle),
      columnStyle: CoordinateStyle(dlg.columnStyle),
      rowStart:    parseInt(dlg.rowStart),
      columnStart: parseInt(dlg.columnStart)
    )

    let regionOpts = RegionOptions(
      enabled:         dlg.enableRegions,
      rowsPerRegion:   parseInt(dlg.rowsPerRegion),
      colsPerRegion:   parseInt(dlg.colsPerRegion),
      perRegionCoords: dlg.perRegionCoords
    )

    actions.setLevelProperties(a.doc.map, a.ui.cursor,
                               dlg.locationName, dlg.levelName, elevation,
                               dlg.overrideCoordOpts, coordOpts, regionOpts,
                               dlg.notes,
                               a.doc.undoManager)

    setStatusMessage(IconFile, fmt"Level properties updated", a)
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
# {{{ Resize level dialog

proc openResizeLevelDialog*(a) =
  alias(dlg, a.dialogs.resizeLevel)

  let l = currLevel(a)
  dlg.rows = $l.rows
  dlg.cols = $l.cols
  dlg.anchor = raCenter

  a.dialogs.activeDialog = dlgResizeLevel


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


  proc cancelAction(a) =
    closeDialog(a)

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
# {{{ Delete level dialog

proc openDeleteLevelDialog*(a) =
  a.dialogs.activeDialog = dlgDeleteLevel


proc deleteLevelDialog*(a) =
  alias(map, a.doc.map)
  alias(um, a.doc.undoManager)

  const
    DlgWidth  = ConfirmDlgWidth
    DlgHeight = 136.0

  let h = DlgItemHeight

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconTrash}  Delete level?",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, DlgWidth, h, "Do you want to delete the current level?",
            style=a.theme.labelStyle)

  proc okAction(a) =
    a.ui.drawTrail = false

    let cur = actions.deleteLevel(map, a.ui.cursor, um)
    setCursor(cur, a)

    setStatusMessage(IconTrash, "Level deleted", a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} Delete",
                style=a.theme.buttonStyle):
    okAction(a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
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

# {{{ Edit note dialog

proc openEditNoteDialog*(a) =
  alias(dlg, a.dialogs.editNote)

  let cur = a.ui.cursor
  let l = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let note = l.getNote(cur.row, cur.col)

  if note.isSome:
    let note = note.get
    dlg.editMode = true
    dlg.kind = note.kind
    dlg.text = note.text

    if note.kind == akIndexed:
      dlg.index = note.index
      dlg.indexColor = note.indexColor
    elif note.kind == akIcon:
      dlg.icon = note.icon

    if note.kind == akCustomId:
      dlg.customId = note.customId
    else:
      dlg.customId = ""

  else:
    dlg.editMode = false
    dlg.customId = ""
    dlg.text = ""

  a.dialogs.activeDialog = dlgEditNote


proc editNoteDialog*(dlg: var EditNoteDialogParams; a) =
  let lt = a.theme.levelTheme

  const
    DlgWidth = 486.0
    DlgHeight = 401.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Note"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCommentInv}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  koi.label(x, y, LabelWidth, h, "Marker", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, w=296, h,
    labels = @["None", "Number", "ID", "Icon"],
    dlg.kind,
    style = a.theme.radioButtonStyle
  )

  y += 40
  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = lt.noteIndexBackgroundColor.len
  const IconsPerRow = 10

  case dlg.kind:
  of akIndexed:
    koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)

    koi.radioButtons(
      x + LabelWidth, y, 28, 28,
      labels = newSeq[string](lt.noteIndexBackgroundColor.len),
      dlg.indexColor,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
      drawProc = colorRadioButtonDrawProc(
        lt.noteIndexBackgroundColor.toSeq,
        a.theme.radioButtonStyle.buttonFillColorActive
      ).some
    )

  of akCustomId:
    koi.label(x, y, LabelWidth, h, "ID", style=a.theme.labelStyle)
    koi.textField(
      x + LabelWidth, y, w=DlgNumberWidth, h,
      dlg.customId,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: NoteCustomIdLimits.minRuneLen,
        maxLen: NoteCustomIdLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  of akIcon:
    koi.label(x, y, LabelWidth, h, "Icon", style=a.theme.labelStyle)
    koi.radioButtons(
      x + LabelWidth, y, 35, 35,
      labels = NoteIcons,
      dlg.icon,
      tooltips = @[],
      layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 10),
      style = a.theme.iconRadioButtonsStyle
    )

  of akComment, akLabel: discard

  dlg.activateFirstTextField = false

  # Validation
  var validationErrors: seq[string] = @[]

  if dlg.kind in {akComment, akIndexed}:
    if dlg.text == "":
      validationErrors.add(mkValidationError("Text is mandatory"))

  if dlg.kind == akCustomId:
    if dlg.customId == "":
      validationErrors.add(mkValidationError("ID is mandatory"))
    else:
      for c in dlg.customId:
        if not isAlphaNumeric(c):
          validationErrors.add(
            mkValidationError(
              "ID must contain only alphanumeric characters (a-z, A-Z, 0-9)"
            )
          )
          break

  y += 45

  for err in validationErrors:
    koi.label(x, y, DlgWidth, h, err, style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditNoteDialogParams; a) =
    if validationErrors.len > 0: return

    var note = Annotation(
      kind: dlg.kind,
      text: dlg.text
    )
    case note.kind
    of akCustomId: note.customId = dlg.customId
    of akIndexed:  note.indexColor = dlg.indexColor
    of akIcon:     note.icon = dlg.icon
    of akComment, akLabel: discard

    actions.setNote(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    let msg = "Note " & (if dlg.editMode: "updated" else: "added")
    setStatusMessage(IconComment, msg, a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=validationErrors.len > 0,
                style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.kind = AnnotationKind(
      handleTabNavigation(ke, ord(dlg.kind), ord(akIcon), a)
    )

    case dlg.kind
    of akComment, akCustomId, akLabel: discard
    of akIndexed:
      dlg.indexColor = handleGridRadioButton(
        ke, dlg.indexColor, NumIndexColors, buttonsPerRow=NumIndexColors
      )
    of akIcon:
      dlg.icon = handleGridRadioButton(
        ke, dlg.icon, NoteIcons.len, IconsPerRow
      )

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Edit label dialog

proc openEditLabelDialog*(a) =
  alias(dlg, a.dialogs.editLabel)

  let cur = a.ui.cursor
  let l   = currLevel(a)
  dlg.row = cur.row
  dlg.col = cur.col

  let label = l.getLabel(cur.row, cur.col)

  if label.isSome:
    let label    = label.get
    dlg.editMode = true
    dlg.text     = label.text
    dlg.color    = label.labelColor
  else:
    dlg.editMode = false
    dlg.text     = ""

  a.dialogs.activeDialog = dlgEditLabel


proc editLabelDialog*(dlg: var EditLabelDialogParams; a) =
  let lt = a.theme.levelTheme

  const
    DlgWidth = 486.0
    DlgHeight = 288.0
    LabelWidth = 80.0

  let h = DlgItemHeight

  let title = (if dlg.editMode: "Edit" else: "Add") & " Label"

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconText}  {title}",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopNoTabPad

  koi.label(x, y, LabelWidth, h, "Text", style=a.theme.labelStyle)
  koi.textArea(
    x + LabelWidth, y, w=346, h=92, dlg.text,
    activate = dlg.activateFirstTextField,
    constraint = TextAreaConstraint(
      maxLen: NoteTextLimits.maxRuneLen.some
    ).some,
    style = a.theme.textAreaStyle
  )

  y += 108

  let NumIndexColors = lt.noteIndexBackgroundColor.len

  koi.label(x, y, LabelWidth, h, "Color", style=a.theme.labelStyle)
  koi.radioButtons(
    x + LabelWidth, y, w=28, h=28,
    labels = newSeq[string](lt.labelTextColor.len),
    dlg.color,
    tooltips = @[],
    layout = RadioButtonsLayout(kind: rblGridHoriz, itemsPerRow: 4),
    drawProc = colorRadioButtonDrawProc(
      lt.labelTextColor.toSeq,
      a.theme.radioButtonStyle.buttonFillColorActive
    ).some,
    style = a.theme.radioButtonStyle
  )

  dlg.activateFirstTextField = false

  # Validation
  var validationError = ""
  if dlg.text == "":
    validationError = mkValidationError("Text is mandatory")

  y += 44

  if validationError != "":
    koi.label(x, y, DlgWidth, h, validationError,
              style=a.theme.errorLabelStyle)
    y += h


  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  proc okAction(dlg: EditLabelDialogParams; a) =
    if validationError != "": return

    var note = Annotation(kind: akLabel, text: dlg.text, labelColor: dlg.color)
    actions.setLabel(a.doc.map, a.ui.cursor, note, a.doc.undoManager)

    let msg = "Label " & (if dlg.editMode: "updated" else: "added")
    setStatusMessage(IconText, msg, a)
    closeDialog(a)


  proc cancelAction(a) =
    closeDialog(a)


  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconCheck} OK",
                disabled=(validationError != ""), style=a.theme.buttonStyle):
    okAction(dlg, a)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, h, fmt"{IconClose} Cancel",
                style=a.theme.buttonStyle):
    cancelAction(a)


  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    dlg.color = handleGridRadioButton(
      ke, dlg.color, NumIndexColors, buttonsPerRow=NumIndexColors
    )

    if ke.isShortcutDown(scNextTextField, a):
      dlg.activateFirstTextField = true

    elif ke.isShortcutDown(scCancel, a): cancelAction(a)
    elif ke.isShortcutDown(scAccept, a): okAction(dlg, a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}

# {{{ Edit region properties dialog

proc openEditRegionPropertiesDialog*(a) =
  alias(dlg, a.dialogs.editRegionProps)

  let region = currRegion(a).get
  dlg.name  = region.name
  dlg.notes = region.notes

  a.dialogs.activeDialog = dlgEditRegionProps


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


  proc okAction(dlg: EditRegionPropsParams; a) =
    alias(map, a.doc.map)
    let cur = a.ui.cursor

    let regionCoords = map.getRegionCoords(cur)
    let region = initRegion(name=dlg.name, notes=dlg.notes)

    actions.setRegionProperties(map, cur, regionCoords, region,
                                a.doc.undoManager)

    setStatusMessage(IconFile, "Region properties updated", a)
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
