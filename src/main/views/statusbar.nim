import std/math
import std/monotimes
import std/strformat
import std/times

import koi
import nanovg

import common
import domain/all
import glfw
import main/appcontext
import main/constants
import main/keyboard
import main/view
import ui/all
import utils/all


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

# {{{ toggleShowOption / toggleOnOffOption
template toggleOption(opt: untyped, icon, msg, on, off: string; a) =
  opt = not opt
  let state = if opt: on else: off
  setStatusMessage(icon, msg & " " & state, a)

template toggleShowOption*(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="shown", off="hidden", a)

template toggleOnOffOption*(opt: untyped, icon, msg: string; a) =
  toggleOption(opt, icon, msg, on="on", off="off", a)

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
# {{{ setSelectJumpToLinkSrcActionMessage()
proc setSelectJumpToLinkSrcActionMessage*(a) =
  let currIdx = a.ui.jumpToSrcLocationIdx + 1
  let count = a.ui.jumpToSrcLocations.len
  let floor = a.doc.map.getFloor(a.ui.jumpToDestLocation)

  setStatusMessage(IconLink,
                   fmt"Select {linkFloorToString(floor)} " &
                   fmt"source ({currIdx} of {count})",
                   @[IconArrowsAll, "next/prev", "Enter/Esc", "exit"], a)

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

# {{{ renderCommand()
proc renderCommand*(x, y: float; command: string; bgColor, textColor: Color;
                   a: AppContext): float =
  alias(vg, a.vg)

  let w = vg.textWidth(command)
  let (x, y) = (round(x), round(y))

  vg.beginPath
  vg.roundedRect(x, y-10, w+10, 18, 3)
  vg.fillColor(bgColor)
  vg.fill

  vg.fillColor(textColor)
  discard vg.text(x+5, y, command)

  result = w


proc renderCommand*(x, y: float; command: string; a): float =
  let s = a.theme.statusBarTheme

  renderCommand(x, y, command,
                bgColor=s.commandBackgroundColor,
                textColor=s.commandTextColor, a)

# }}}
# {{{ renderStatusBar()
proc renderStatusBar*(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(status, a.ui.status)

  let s = a.theme.statusBarTheme

  let ty = h * TextVertAlignFactor

  # Bar background
  vg.save
  vg.translate(x, y)

  vg.beginPath
  vg.rect(0, 0, w, h)
  vg.fillColor(s.backgroundColor)
  vg.fill

  # Display cursor coordinates
  vg.setFont(14, "sans-bold")

  if a.doc.map.hasLevels:
    let
      l = currLevel(a)
      coordOpts = coordOptsForCurrLevel(a)

      cur = a.ui.cursor
      row = formatRowCoord(cur.row, l.rows, coordOpts, l.regionOpts)
      col = formatColumnCoord(cur.col, l.cols, coordOpts, l.regionOpts)

      cursorPos = fmt"({col}, {row})"
      tw = vg.textWidth(cursorPos)

    vg.fillColor(s.coordinatesColor)
    vg.textAlign(haLeft, vaMiddle)
    discard vg.text(w - tw - 7, ty, cursorPos)

    vg.intersectScissor(0, 0, w - tw - 15, h)

  # Display status message or warning
  const
    IconPosX = 10
    MessagePosX = 30
    MessagePadX = 20
    CommandLabelPadX = 14
    CommandTextPadX = 10

  var x = 10.0

  # Clear expired warning messages
  if status.warning.message != "":
    let dt = getMonoTime() - status.warning.t0
    if dt > status.warning.timeout:
      status.warning.message = ""
      status.warning.overwrite = true

      if not status.warning.keepMessage:
        clearStatusMessage(a)
    else:
      koi.setFramesLeft()

  # Display message
  if status.warning.message == "":
    vg.fillColor(s.textColor)
    discard vg.text(IconPosX, ty, status.icon)

    let tx = vg.text(MessagePosX, ty, status.message)
    x = tx + MessagePadX

    # Display commands, if present
    for i, cmd in status.commands:
      if i mod 2 == 0:
        let w = renderCommand(x, ty, cmd, a)
        x += w + CommandLabelPadX
      else:
        let text = cmd
        vg.fillColor(s.textColor)
        let tw = vg.text(round(x), round(ty), text)
        x = tw + CommandTextPadX

  # Display warning
  else:
    vg.fillColor(status.warning.color)
    discard vg.text(IconPosX, ty, status.warning.icon)
    discard vg.text(MessagePosX, ty, status.warning.message)

  vg.restore

# }}}

# vim: et:ts=2:sw=2:fdm=marker
