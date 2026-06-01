import main/dialogs/common

import std/browsers
import std/strformat
import semver
import appevents


using a: var AppContext


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

# vim: et:ts=2:sw=2:fdm=marker
