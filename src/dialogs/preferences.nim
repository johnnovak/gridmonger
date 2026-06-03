import dialogs/common

import appevents
import configio
import ../theme


using a: var AppContext

# {{{ openPreferencesDialog*()
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

# }}}
# {{{ openPreferencesDialog*()
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

  # {{{ General
  if dlg.activeTab == 0:
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

  # }}}
  # {{{ Editing
  elif dlg.activeTab == 1:
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

  # }}}
  # {{{ Interface
  elif dlg.activeTab == 2:
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

    # }}}

  koi.endView()

  # {{{ okAction()
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
    # NOTE: quick-ref shortcut tables won't be refreshed until the next
    # app start — quickref imports actions_ui (-> dialogs), so dialogs
    # can't import quickref without a cycle. Minor UX issue: after
    # changing modifier-key mode in prefs, the quick-ref overlay shows
    # stale shortcuts until restart.

    closeDialog(a)

    setStatusMessage(IconCog, "Preferences updated", a)

  # }}}
  # {{{ cancelAction()
  proc cancelAction(a) =
    closeDialog(a)

  # }}}

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

# vim: et:ts=2:sw=2:fdm=marker
