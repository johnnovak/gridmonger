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
import main/keyboard        # updateShortcuts, primaryModDown, isShortcutDown, toStr
import main/mapio           # saveMap, loadMap
import main/status_msg
import main/themeio
import main/versioncheck    # initVersionChecking
import main/view            # currLevel, currRegion, coordOptsForCurrLevel, calculateLevelDrawArea, mainPaneRect
import ui/all
import undomanager
import utils/all
import utils/misc as gmUtils


using a: var AppContext


# {{{ Constants
const
  DlgItemHeight* = 24.0
  DlgButtonWidth* = 80.0
  DlgButtonPad* = 10.0
  DlgNumberWidth* = 50.0
  DlgCheckBoxSize* = 18.0
  DlgTopPad* = 50.0
  DlgTopNoTabPad* = 60.0
  DlgLeftPad* = 30.0
  DlgTabBottomPad* = 50.0

  ConfirmDlgWidth* = 350.0
  ConfirmDlgHeight* = 160.0

  DialogLayoutParams* = AutoLayoutParams(
    itemsPerRow:       2,
    rowWidth:          370.0,
    labelWidth:        160.0,
    sectionPad:        0.0,
    leftPad:           0.0,
    rightPad:          0.0,
    rowPad:            8.0,
    rowGroupPad:       20.0,
    defaultRowHeight:  24.0,
    defaultItemHeight: 24.0
  )

# }}}
# {{{ Helpers

# {{{ coordinateFields()
template coordinateFields*() =
  const LetterLabelWidth = 100

  group:
    koi.label("Origin", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Northwest", "Southwest"],
      dlg.origin,
      style = a.theme.radioButtonStyle
    )

  group:
    koi.label("Column style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.columnStyle,
      style = a.theme.radioButtonStyle
    )

    koi.label("Row style", style=a.theme.labelStyle)
    koi.radioButtons(
      labels = @["Number", "Letter"],
      dlg.rowStyle,
      style = a.theme.radioButtonStyle
    )

  group:
    koi.label("Column start", style=a.theme.labelStyle)
    var y = koi.autoLayoutNextY()
    let letterLabelX = koi.autoLayoutNextX() + DlgNumberWidth + 14

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.columnStart,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordColumnStartLimits.minInt,
        maxInt: CoordColumnStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )


    if CoordinateStyle(dlg.columnStyle) == csLetter:
      try:
        let i = parseInt(dlg.columnStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
      except ValueError:
        discard

    koi.label("Row start", style=a.theme.labelStyle)
    y = koi.autoLayoutNextY()

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rowStart,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: CoordRowStartLimits.minInt,
        maxInt: CoordRowStartLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )
    if CoordinateStyle(dlg.rowStyle) == csLetter:
      try:
        let i = parseInt(dlg.rowStart)
        koi.label(letterLabelX, y, LetterLabelWidth, DlgItemHeight,
                  i.toLetterCoord, style=a.theme.labelStyle)
      except ValueError:
        discard

# }}}
# {{{ regionFields()
template regionFields*() =
  group:
    koi.label("Enable regions", style=a.theme.labelStyle)

    koi.nextItemHeight(DlgCheckBoxSize)
    koi.checkBox(dlg.enableRegions, style = a.theme.checkBoxStyle)

    if dlg.enableRegions:
      group:
        koi.label("Region columns", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.colsPerRegion,
          activate = dlg.activateFirstTextField,
          constraint = TextFieldConstraint(
            kind:   tckInteger,
            minInt: RegionColumnLimits.minInt,
            maxInt: RegionColumnLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

        koi.label("Region rows", style=a.theme.labelStyle)

        koi.nextItemWidth(DlgNumberWidth)
        koi.textField(
          dlg.rowsPerRegion,
          constraint = TextFieldConstraint(
            kind:   tckInteger,
            minInt: RegionRowLimits.minInt,
            maxInt: RegionRowLimits.maxInt
          ).some,
          style = a.theme.textFieldStyle
        )

      group:
        koi.label("Per-region coordinates", style=a.theme.labelStyle)

        koi.nextItemHeight(DlgCheckBoxSize)
        koi.checkBox(dlg.perRegionCoords, style = a.theme.checkBoxStyle)

# }}}
# {{{ noteFields()
template noteFields*(dlgWidth: float) =
  koi.label("Notes", style=a.theme.labelStyle)

  koi.textArea(
    x=0, y=28, w=dlgWidth-60, h=187,
    dlg.notes,
    activate = dlg.activateFirstTextField,
     constraint = TextAreaConstraint(
       maxLen: NotesLimits.maxRuneLen.some
     ).some,
    style = a.theme.textAreaStyle
  )

# }}}
# {{{ commonLevelFields()
template commonLevelFields*(dimensionsDisabled: bool) =
  group:
    koi.label("Location name", style=a.theme.labelStyle)

    koi.textField(
      dlg.locationName,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind:   tckString,
        minLen: LevelLocationNameLimits.minRuneLen,
        maxLen: LevelLocationNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Level name", style=a.theme.labelStyle)

    koi.textField(
      dlg.levelName,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: LevelNameLimits.minRuneLen,
        maxLen: LevelNameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Elevation", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.elevation,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelElevationLimits.minInt,
        maxInt: LevelElevationLimits.maxInt
      ).some,
      style = a.theme.textFieldStyle
    )

  group:
    koi.label("Columns", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.cols,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelColumnsLimits.minInt,
        maxInt: LevelColumnsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
      style = a.theme.textFieldStyle
    )

    koi.label("Rows", style=a.theme.labelStyle)

    koi.nextItemWidth(DlgNumberWidth)
    koi.textField(
      dlg.rows,
      constraint = TextFieldConstraint(
        kind:   tckInteger,
        minInt: LevelRowsLimits.minInt,
        maxInt: LevelRowsLimits.maxInt
      ).some,
      disabled = dimensionsDisabled,
      style = a.theme.textFieldStyle
    )

# }}}
# {{{ validateLevelFields()
template validateLevelFields*(dlg, map, validationError: untyped) =
  if dlg.locationName == "":
    validationError = mkValidationError("Location name is mandatory")
  else:
    for _, l in map.levels:
      if l.locationName == dlg.locationName and
         l.levelName == dlg.levelName and
         $l.elevation == dlg.elevation:

        validationError = mkValidationError(
          "A level already exists with the same location name, " &
          "level name and elevation."
        )
        break

# }}}
# {{{ commonGeneralMapFields()
template commonGeneralMapFields*(map: Map, displayCreationTime: bool) =
  group:
    koi.label("Title", style=a.theme.labelStyle)

    koi.textField(
      dlg.title,
      activate = dlg.activateFirstTextField,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapTitleLimits.minRuneLen,
        maxLen: MapTitleLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Game", style=a.theme.labelStyle)

    koi.textField(
      dlg.game,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapGameLimits.minRuneLen,
        maxLen: MapGameLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    koi.label("Author", style=a.theme.labelStyle)

    koi.textField(
      dlg.author,
      constraint = TextFieldConstraint(
        kind: tckString,
        minLen: MapAuthorLimits.minRuneLen,
        maxLen: MapAuthorLimits.maxRuneLen.some
      ).some,
      style = a.theme.textFieldStyle
    )

    if displayCreationTime:
      koi.label("Creation time", style=a.theme.labelStyle)

      koi.textField(
        map.creationTime,
        disabled = true,
        style = a.theme.textFieldStyle
      )

# }}}
# {{{ validateCommonGeneralMapFields()
template validateCommonGeneralMapFields*(dlg: untyped): string =
  if dlg.title == "":
    mkValidationError("Title is mandatory")
  else: ""

# }}}

# {{{ calcDialogX()
proc calcDialogX*(dlgWidth: float; a): float =
  var w = koi.winWidth()

  if a.layout.showThemeEditor:
    w -= ThemePaneWidth

  w.float*0.5 - dlgWidth*0.5

# }}}
# {{{ dialogButtonsStartPos()
func dialogButtonsStartPos*(dlgWidth, dlgHeight: float,
                           numButtons: Natural): tuple[x, y: float] =
  const BorderPad = 15.0

  let x = dlgWidth - numButtons * DlgButtonWidth - BorderPad -
          (numButtons-1) * DlgButtonPad

  let y = dlgHeight - DlgItemHeight - BorderPad

  result = (x, y)

# }}}
# {{{ mkValidationError()
func mkValidationError*(msg: string): string =
  fmt"{IconWarning}   {msg}"

# }}}
# {{{ mkValidationWarning()
func mkValidationWarning*(msg: string): string =
  fmt"{IconInfo}   {msg}"

# }}}
# {{{ moveGridPositionWrapping()
func moveGridPositionWrapping*(currIdx: int, dc: int = 0, dr: int = 0,
                              numItems, itemsPerRow: Natural): Natural =
  assert numItems mod itemsPerRow == 0

  let numRows = ceil(numItems.float / itemsPerRow).Natural
  var row = currIdx div itemsPerRow
  var col = currIdx mod itemsPerRow
  col = floorMod(col+dc, itemsPerRow).Natural
  row = floorMod(row+dr, numRows).Natural
  result = row * itemsPerRow + col

# }}}
# {{{ handleGridRadioButton()
func handleGridRadioButton*(ke: Event, currButtonIdx: Natural,
                           numButtons, buttonsPerRow: Natural): Natural =

  proc move(dc: int = 0, dr: int = 0): Natural =
    moveGridPositionWrapping(currButtonIdx, dc, dr, numButtons, buttonsPerRow)

  result =
    if   ke.isKeyDown(MoveKeysStandard.left,  repeat=true): move(dc = -1)
    elif ke.isKeyDown(MoveKeysStandard.right, repeat=true): move(dc =  1)
    elif ke.isKeyDown(MoveKeysStandard.up,    repeat=true): move(dr = -1)
    elif ke.isKeyDown(MoveKeysStandard.down,  repeat=true): move(dr =  1)
    else: currButtonIdx

# }}}
# {{{ handleTabNavigation()
proc handleTabNavigation*(ke: Event,
                         currTabIndex, maxTabIndex: Natural; a): Natural =
  result = currTabIndex

  if ke.isKeyDown(MoveKeysStandard.left, {mkCtrl}):
    if    currTabIndex > 0: result = currTabIndex - 1
    else: result = maxTabIndex

  elif ke.isKeyDown(MoveKeysStandard.right, {mkCtrl}):
    if    currTabIndex < maxTabIndex: result = currTabIndex + 1
    else: result = 0

  else:
    let i = ord(ke.key) - ord(key1)
    if ke.action == kaDown and mkCtrl in ke.mods and
      i >= 0 and i <= maxTabIndex:
      result = i

# }}}

# {{{ colorRadioButtonDrawProc()
proc colorRadioButtonDrawProc*(colors: seq[Color],
                              cursorColor: Color): RadioButtonsDrawProc =

  return proc (vg: NVGContext,
               id: ItemId, x, y, w, h: float,
               buttonIdx, numButtons: Natural, label: string,
               state: WidgetState, style: RadioButtonsStyle) =

    let sw = 2.0
    let (x, y, w, h) = snapToGrid(x, y, w, h, sw)

    var col = colors[buttonIdx]

    let cursorColor = if state == wsHover: cursorColor.withAlpha(0.65)
                      else: cursorColor

    const Pad = 5
    const SelPad = 3

    var cx, cy, cw, ch: float
    if state in {wsHover, wsDown, wsActive, wsActiveHover, wsActiveDown}:
      vg.beginPath
      vg.strokeColor(cursorColor)
      vg.strokeWidth(sw)
      vg.rect(x, y, w-Pad, h-Pad)
      vg.stroke

      cx = x+SelPad
      cy = y+SelPad
      cw = w-Pad-SelPad*2
      ch = h-Pad-SelPad*2

    else:
      cx = x
      cy = y
      cw = w-Pad
      ch = h-Pad

    vg.beginPath
    vg.fillColor(col)
    vg.rect(cx, cy, cw, ch)
    vg.fill

# }}}

# {{{ closeDialog()
proc closeDialog*(a) =
  koi.closeDialog()
  a.dialogs.activeDialog = dlgNone

# }}}

# }}}

# {{{ About dialog
proc openAboutDialog*(a) =
  if a.latestVersion.isNone:
    appEvents.fetchLatestVersion()

  a.dialogs.activeDialog = dlgAbout


proc aboutDialog*(dlg: var AboutDialogParams; a) =
  alias(al, dlg.aboutLogo)
  alias(vg, a.vg)

  let
    DlgWidth  = 390
    DlgHeight = if a.prefs.checkForUpdates: 470 else: 438

  let
    dialogX = floor(calcDialogX(DlgWidth, a))
    dialogY = floor((koi.winHeight() - DlgHeight) * 0.5)

  let logoColor = a.theme.config.getColorOrDefault("ui.about-dialog.logo")

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconQuestion}  About Gridmonger",
                  x=dialogX.some, y=dialogY.some,
                  style=a.theme.aboutDialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad
  let w = DlgWidth
  let h = DlgItemHeight

  if al.logoImage == NoImage or al.updateLogoImage:
    colorImage(al.logo, logoColor)
    if al.logoImage == NoImage:
      al.logoImage = createImage(al.logo)
    else:
      vg.updateImage(al.logoImage, cast[ptr byte](al.logo.data))
    al.updateLogoImage = false

  let scale = DlgWidth / al.logo.width

  al.logoPaint = createPattern(a.vg, al.logoImage, alpha=logoColor.a,
                               xoffs=dialogX, yoffs=dialogY, scale=scale)


  koi.image(0, 0, DlgWidth, DlgHeight, al.logoPaint)

  var labelStyle = a.theme.labelStyle.deepCopy
  labelStyle.align = haCenter

  y += 275
  koi.label(0, y, w, h, VersionString, style=labelStyle)

  y += 25
  koi.label(0, y, w, h, DevelopedBy, style=labelStyle)

  # Check for updates
  if a.prefs.checkForUpdates:
    y += 32

    if a.latestVersion.isSome or a.versionFetchError.isSome:
      let st = labelStyle.deepCopy

      var msg: string
      if a.latestVersion.isSome:
        let v = a.latestVersion.get
        msg = if v.version > AppVersion:
                fmt"A more recent version is available: v{v.version}"
              else: "You're running the latest version."

      else:
        msg = "Error fetching version information"

      st.color = a.theme.warningLabelStyle.color
      koi.label(0, y, w, h, msg, style=st)

  # Buttons
  x = (DlgWidth - (2*DlgButtonWidth + 1*DlgButtonPad)) * 0.5
  y += 40
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Manual",
                style=a.theme.buttonStyle):
    openUserManual(a.paths.manualDir)

  x += DlgButtonWidth + DlgButtonPad
  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, "Website",
                style=a.theme.buttonStyle):
    openDefaultBrowser(ProjectHomeUrl)


  proc closeAction(a) =
    a.dialogs.about.aboutLogo.updateLogoImage = true
    closeDialog(a)


  # HACK, HACK, HACK!
  if not a.layout.showThemeEditor:
    if not koi.hasHotItem() and koi.hasEvent():
      let ev = koi.currEvent()
      if ev.kind == ekMouseButton and ev.button == mbLeft and ev.pressed:
        closeAction(a)

  if hasKeyEvent():
    let ke = koi.currEvent()
    var eventHandled = true

    if ke.isShortcutDown(scCancel, a) or ke.isShortcutDown(scAccept, a):
      closeAction(a)
    else: eventHandled = false

    if eventHandled: setEventHandled()

  koi.endDialog()

# }}}
# {{{ Preferences dialog

proc openPreferencesDialog*(a) =
  alias(dlg, a.dialogs.preferences)

  dlg.loadLastMap        = a.prefs.loadLastMap
  dlg.autosave           = a.prefs.autosave
  dlg.autosaveFreqMins   = $a.prefs.autosaveFreqMins
  dlg.checkForUpdates    = a.prefs.checkForUpdates

  dlg.showSplash         = a.prefs.showSplash
  dlg.autoCloseSplash    = a.prefs.autoCloseSplash
  dlg.splashTimeoutSecs  = $a.prefs.splashTimeoutSecs
  dlg.vsync              = a.prefs.vsync
  dlg.scalePercentage    = round(a.prefs.scaleFactor * 100)
  dlg.modifierKeyMode    = ord(a.prefs.modifierKeyMode)

  dlg.movementWraparound = a.prefs.movementWraparound
  dlg.yubnMovementKeys   = a.prefs.yubnMovementKeys
  dlg.walkCursorMode     = a.prefs.walkCursorMode
  dlg.linkLinesMode      = a.prefs.linkLinesMode
  dlg.openEndedExcavate  = a.prefs.openEndedExcavate

  a.dialogs.activeDialog = dlgPreferences


proc preferencesDialog*(dlg: var PreferencesDialogParams; a) =
  const
    DlgWidth  = 440.0
    DlgHeight = 420.0
    TabWidth  = 380.0

  koi.beginDialog(DlgWidth, DlgHeight, fmt"{IconCog}  Preferences",
                  x = calcDialogX(DlgWidth, a).some,
                  style = a.theme.dialogStyle)

  clearStatusMessage(a)

  var x = DlgLeftPad
  var y = DlgTopPad

  let tabLabels = @["General", "Editing", "Interface"]

  koi.radioButtons(
    (DlgWidth - TabWidth) * 0.5, y, TabWidth, DlgItemHeight,
    tabLabels, dlg.activeTab,
    style = a.theme.radioButtonStyle
  )

  y += DlgTabBottomPad

  koi.beginView(x, y, w=1000, h=1000)

  var lp = DialogLayoutParams
  lp.labelWidth = 220
  koi.initAutoLayout(lp)

  if dlg.activeTab == 0:  # General
    group:
      koi.label("Load last map", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.loadLastMap, style = a.theme.checkBoxStyle)

    group:
      let autosaveDisabled = not dlg.autosave

      koi.label("Autosave", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autosave, style = a.theme.checkBoxStyle)

      koi.label("Autosave frequency (minutes)",
                state = if autosaveDisabled: wsDisabled else: wsNormal,
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.autosaveFreqMins,
        activate = dlg.activateFirstTextField,
        disabled = autosaveDisabled,
        constraint = TextFieldConstraint(
          kind:   tckInteger,
          minInt: AutosaveFreqMinsLimits.minInt,
          maxInt: AutosaveFreqMinsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Check for updates", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.checkForUpdates, style=a.theme.checkBoxStyle)


  elif dlg.activeTab == 1:  # Editing
    group:
      koi.label("Movement wraparound", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.movementWraparound, style=a.theme.checkBoxStyle)

      koi.label("YUBN diagonal movement",
                 style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.yubnMovementKeys, style=a.theme.checkBoxStyle)

      koi.label("Walk mode Left/Right keys", style=a.theme.labelStyle)
      koi.nextItemWidth(70)
      koi.dropDown(dlg.walkCursorMode, style=a.theme.dropDownStyle)

    group:
      koi.label("Show link lines", style=a.theme.labelStyle)
      koi.nextItemWidth(120)
      koi.dropDown(dlg.linkLinesMode, style=a.theme.dropDownStyle)

    group:
      koi.label("Open-ended exacavate", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.openEndedExcavate, style=a.theme.checkBoxStyle)


  elif dlg.activeTab == 2:  # Interface
    group:
      koi.label("Show splash image", style=a.theme.labelStyle)
      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.showSplash, style = a.theme.checkBoxStyle)

      var disabled = not dlg.showSplash
      koi.label("Auto-close splash",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.autoCloseSplash, disabled=disabled,
                   style = a.theme.checkBoxStyle)


      disabled = not (dlg.showSplash and dlg.autoCloseSplash)
      koi.label("Auto-close timeout (seconds)",
                state=(if disabled: wsDisabled else: wsNormal),
                style=a.theme.labelStyle)

      koi.nextItemWidth(DlgNumberWidth)
      koi.textField(
        dlg.splashTimeoutSecs,
        activate = dlg.activateFirstTextField,
        disabled = disabled,
        constraint = TextFieldConstraint(
          kind:   tckInteger,
          minInt: SplashTimeoutSecsLimits.minInt,
          maxInt: SplashTimeoutSecsLimits.maxInt
        ).some,
        style = a.theme.textFieldStyle
      )

    group:
      koi.label("Vertical sync", style=a.theme.labelStyle)

      koi.nextItemHeight(DlgCheckBoxSize)
      koi.checkBox(dlg.vsync, style=a.theme.checkBoxStyle)


      koi.label("Interface scaling", style=a.theme.labelStyle)

      var st = a.theme.sliderStyle
      st.valuePrecision = 0
      st.valueSuffix    = "%"

      koi.nextItemWidth(135)
      koi.horizSlider(
        startVal = UIScaleFactorLimits.minInt,
        endVal   = UIScaleFactorLimits.maxInt,
        dlg.scalePercentage,
        style = st
      )

      koi.label("")
      koi.nextItemWidth(170)
      koi.label(fmt"{scResetUIScaling.toStr(a)} resets scaling",
                style=a.theme.labelStyle)

    group:
      when defined(macosx):
        koi.label("Shortcut modifier keys", style=a.theme.labelStyle)
        koi.nextItemWidth(135)

        var items = @[
          fmt"Ctrl, Ctrl{HairSp}+{HairSp}Alt",
          fmt"Cmd, Cmd{HairSp}+{HairSp}Shift"
        ]
        koi.dropDown(items, dlg.modifierKeyMode, style=a.theme.dropDownStyle)


  koi.endView()


  proc okAction(dlg: PreferencesDialogParams; a) =
    # General
    a.prefs.loadLastMap        = dlg.loadLastMap

    let
      autosaveTurnedOn = not a.prefs.autosave and dlg.autosave
      oldFreqMins      = a.prefs.autosaveFreqMins
      newFreqMins      = parseInt(dlg.autosaveFreqMins).Natural

    a.prefs.autosave           = dlg.autosave
    a.prefs.autosaveFreqMins   = newFreqMins

    if a.prefs.autosave:
      if autosaveTurnedOn or oldFreqMins != newFreqMins:
        appEvents.updateLastSavedTime()
        appEvents.setAutoSaveTimeout(initDuration(minutes = newFreqMins))
    else:
      appEvents.disableAutoSave()

    a.prefs.checkForUpdates    = dlg.checkForUpdates

    if not a.prefs.checkForUpdates and dlg.checkForUpdates:
      # Check for updates was just enabled
      initVersionChecking(a)
      appEvents.fetchLatestVersion()


    # Interface
    a.prefs.showSplash         = dlg.showSplash
    a.prefs.autoCloseSplash    = dlg.autoCloseSplash
    a.prefs.splashTimeoutSecs  = parseInt(dlg.splashTimeoutSecs).Natural

    let lastScaleFactor = a.prefs.scaleFactor
    a.prefs.scaleFactor        = round(dlg.scalePercentage) / 100

    if a.prefs.scaleFactor != lastScaleFactor:
      a.theme.updateTheme = true

    a.prefs.vsync              = dlg.vsync

    a.prefs.modifierKeyMode    = cast[ModifierKeyMode](dlg.modifierKeyMode)

    # Editing
    a.prefs.movementWraparound = dlg.movementWraparound
    a.prefs.yubnMovementKeys   = dlg.yubnMovementKeys
    a.prefs.walkCursorMode     = dlg.walkCursorMode
    a.prefs.linkLinesMode      = dlg.linkLinesMode
    a.prefs.openEndedExcavate  = dlg.openEndedExcavate

    saveAppConfig(a)
    updateUIScaleFactor(a)
    setSwapInterval(a)
    updateWalkKeys(a)
    updateShortcuts(a)

    closeDialog(a)

    setStatusMessage(IconCog, "Preferences updated", a)


  proc cancelAction(a) =
    closeDialog(a)

  (x, y) = dialogButtonsStartPos(DlgWidth, DlgHeight, 2)

  if koi.button(x, y, DlgButtonWidth, DlgItemHeight, fmt"{IconCheck} OK",
                style=a.theme.buttonStyle):
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
