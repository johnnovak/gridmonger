# status_msg
#
# Setters for the status bar message, transient warning/error messages, and
# the mode-specific status messages (select mode, set link destination,
# nudge/paste/move preview, etc.). All operate on AppContext.ui.status.
# Side effects: AppContext field mutation, koi.setFramesLeft().

import std/monotimes
import std/strformat

import common               # NoIcon, Floor, etc.
import glfw                 # mkCtrl
import koi                  # setFramesLeft
import main/appcontext
import main/constants       # WarningMessageTimeout, InfiniteDuration
import main/keyboard        # toStr(AppShortcut)
import ui/icons             # IconWarning, IconGrid, IconLink, IconArrowsAll, IconPaste
import utils/misc           # alias


using a: var AppContext


# {{{ setStatusMessage()
proc setStatusMessage*(icon, msg: string, commands: seq[string]; a) =
  alias(s, a.ui.status)

  s.icon     = icon
  s.message  = msg
  s.commands = commands

  if s.warning.overwrite:
    s.warning.message = ""

  koi.setFramesLeft()


proc setStatusMessage*(icon, msg: string; a) =
  setStatusMessage(icon, msg, commands = @[], a=a)

proc setStatusMessage*(msg: string; a) =
  setStatusMessage(NoIcon, msg, commands = @[], a=a)

# }}}
# {{{ clearStatusMessage()
proc clearStatusMessage*(a) =
  setStatusMessage(msg = "", a=a)

# }}}
# {{{ setWarningMessage()
proc setWarningMessage*(msg: string, icon = IconWarning,
                       timeout = WarningMessageTimeout, overwrite = true,
                       keepStatusMessage = false; a) =
  alias(s, a.ui.status)

  if not s.warning.overwrite:
    return

  s.warning.icon        = icon
  s.warning.message     = msg
  s.warning.color       = a.theme.statusBarTheme.warningTextColor
  s.warning.t0          = getMonoTime()
  s.warning.timeout     = timeout
  s.warning.overwrite   = overwrite
  s.warning.keepMessage = keepStatusMessage

  koi.setFramesLeft()

# }}}
# {{{ setErrorMessage()
proc setErrorMessage*(msg: string; a) =
  alias(s, a.ui.status)

  if not s.warning.overwrite:
    return

  s.warning.icon        = IconWarning
  s.warning.message     = msg
  s.warning.color       = a.theme.statusBarTheme.errorTextColor
  s.warning.timeout     = InfiniteDuration
  s.warning.keepMessage = false

  koi.setFramesLeft()

# }}}
# {{{ setSelectModeSelectMessage()
proc setSelectModeSelectMessage*(a) =
  let special = if a.keys.primaryModKey == mkCtrl: "Ctrl" else: "Cmd"

  setStatusMessage(
    IconGrid, "Mark selection",
    @[scSelectionDraw.toStr(a),    "draw",
      scSelectionErase.toStr(a),   "erase",
      scSelectionAddRect.toStr(a), "add rect",
      scSelectionSubRect.toStr(a), "sub rect",
      scSelectionAll.toStr(a),     "mark all",
      scSelectionNone.toStr(a),    "unmark all",
      scSelectionCopy.toStr(a),    "copy",
      special,                     "special"],
    a
  )

# }}}
# {{{ setSelectModeSpecialActionsMessage()
proc setSelectModeSpecialActionsMessage*(a) =
  setStatusMessage(
    IconGrid, "Mark selection",
    @[scSelectionEraseArea.toStr(a),         "erase",
      scSelectionFillArea.toStr(a),          "fill",
      scSelectionSurroundArea.toStr(a),      "surround",
      scSelectionCropArea.toStr(a),          "crop",
      scSelectionMove.toStr(a),              "move",
      scSelectionSetFloorColorArea.toStr(a), "set colour"],
    a
  )

# }}}
# {{{ setSetLinkDestinationMessage()
proc setSetLinkDestinationMessage*(floor: Floor; a) =
  setStatusMessage(IconLink,
                   fmt"Set {linkFloorToString(floor)} destination",
                   @[IconArrowsAll, "select cell",
                   scAccept.toStr(a, idx=0), "set",
                   scCancel.toStr(a, idx=0), "cancel"], a)
# }}}
# {{{ mkWraparoundMessage()
proc mkWraparoundMessage*(a): string =
  "wraparound: " & (if a.ui.pasteWraparound: "on" else: "off")

# }}}
# {{{ setNudgePreviewModeMessage()
proc setNudgePreviewModeMessage*(a) =
  setStatusMessage(IconArrowsAll, "Nudge level",
                   @[IconArrowsAll, "nudge",
                   scTogglePasteWraparound.toStr(a), mkWraparoundMessage(a),
                   "Enter", "confirm", "Esc", "cancel"], a)

# }}}
# {{{ setPastePreviewModeMessage()
proc setPastePreviewModeMessage*(a) =
  setStatusMessage(IconPaste, "Paste selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "paste", "Esc", "cancel"], a)

# }}}
# {{{ setMovePreviewModeMessage()
proc setMovePreviewModeMessage*(a) =
  setStatusMessage(IconArrowsAll, "Move selection",
                   @[IconArrowsAll, "placement",
                   scTogglePasteWraparound.toStr(a),
                   mkWraparoundMessage(a),
                   "Enter/P", "confirm", "Esc", "cancel"], a)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
