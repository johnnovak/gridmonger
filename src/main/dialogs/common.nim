# dialogs/common
#
# Shared infrastructure for per-dialog files:
#   - Dialog constants (DlgItemHeight, DlgButtonWidth, DialogLayoutParams, etc.)
#   - 7 shared field templates (coordinateFields, regionFields, noteFields,
#     commonLevelFields, validateLevelFields, commonGeneralMapFields,
#     validateCommonGeneralMapFields) — implicitly capture `a` and `dlg`
#     from the caller's lexical scope, so per-dialog files MUST import this
#     to use them.
#   - Layout/validation helpers (calcDialogX, dialogButtonsStartPos,
#     mkValidation*, moveGridPositionWrapping, handleGridRadioButton,
#     colorRadioButtonDrawProc, closeDialog).
#
# Re-exports the heavyweights every dialog needs (appcontext, keyboard,
# statusbar etc.) so per-dialog files don't need 15+ import lines each.
# Side effects: koi + nanovg drawing, AppContext.dialogs mutation.

import std/lenientops
import std/math
import std/options
import std/sequtils         # toSeq
import std/strformat
import std/strutils
import std/tables
import std/times

import glfw
import koi
import nanovg
import with

import cfghelper
import ../../common as gmcommon  # disambiguate from this file (src/main/dialogs/common)
import domain/all as gmdomain
import io/persistence as gmpersist
import main/appcontext
import main/constants          # ThemePaneWidth
import main/keyboard          # isShortcutDown, isKeyDown, toStr, handleTabNavigation
import main/panes/statusbar   # setStatusMessage, clearStatusMessage
import main/view              # mainPaneRect, currLevel, etc.
import ui/all as gmui
import utils/all as gmutilsall
import utils/misc as gmUtils

# Per-dialog files just `import main/dialogs/common` to get the dialog
# constants, templates, helpers, AND the workhorse modules they all need
# (AppContext, koi, the standard library bits, nanovg, etc.). They still
# import dialog-specific extras explicitly (themeio for theme dialogs,
# mapio for save dialogs, etc.).

export options, math, sequtils, strformat, strutils, tables, times, lenientops
export glfw, koi, nanovg, with
export cfghelper, gmcommon, gmdomain, gmpersist, gmUtils, gmui, gmutilsall
export appcontext, constants, keyboard, statusbar, view


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

# vim: et:ts=2:sw=2:fdm=marker
