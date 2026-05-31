# levelview pane
#
# Everything that renders directly into the central level view: the level
# itself, the level/region dropdowns above it, the mode/option indicators
# at the top, the manual note tooltip overlay, and the empty-map fallback.
# Side effects: koi + nanovg drawing; reads + minor writes to AppContext.ui
# (drawLevelParams, drawTrail, etc.).

import std/math               # round
import std/options
import std/strformat
import std/strutils except splitWhitespace, strip
import std/tables

import koi
import nanovg

import common
import domain/all
import main/actions_ui      # toggleOption/toggleShowOption helpers? actually not — but keep for now
import main/appcontext
import main/constants
import main/cursor
import main/events          # handleLevelMouseEvents
import main/keyboard
import main/panes/statusbar
import main/themeio
import main/view
import ui/all
import utils/all
import utils/misc as gmUtils


using a: var AppContext

# {{{ renderLevelDropdown()
proc renderLevelDropdown*(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    cur      = a.ui.cursor
    mainPane = mainPaneRect(a)

  var sortedLevelIdx = map.sortedLevelIds.find(cur.levelId)
  assert sortedLevelIdx > -1
  let prevSortedLevelIdx = sortedLevelIdx

  # Set width dynamically
  vg.fontSize(a.theme.levelDropDownStyle.label.fontSize)

  let levelDropDownWidth = round(
    vg.textWidth(map.sortedLevelNames[sortedLevelIdx]) +
    a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
  )

  koi.dropDown(
    x = round(mainPane.w - levelDropDownWidth) * 0.5,
    y = 19.0,
    w = levelDropDownWidth,
    h = 24.0,
    map.sortedLevelNames,
    sortedLevelIdx,
    tooltip = "",
    disabled = not (ui.editMode in {emNormal, emSetCellLink}),
    style = a.theme.levelDropDownStyle
  )

  if sortedLevelIdx != prevSortedLevelIdx:
    var cur = cur
    cur.levelId = map.sortedLevelIds[sortedLevelIdx]
    setCursor(cur, a)

# }}}
# {{{ renderRegionDropDown()
proc renderRegionDropDown*(a) =
  alias(ui, a.ui)

  let
    l = currLevel(a)
    currRegion = currRegion(a)
    mainPane = mainPaneRect(a)

  if currRegion.isSome:
    let currRegionName = currRegion.get.name
    var sortedRegionIdx = l.regions.sortedRegionNames.find(currRegionName)
    let prevSortedRegionIdx = sortedRegionIdx

    let regionDropDownWidth = round(
      a.vg.textWidth(currRegionName) +
      a.theme.levelDropDownStyle.label.padHoriz*2 + 8.0
    )

    koi.dropDown(
      x = round(mainPane.w - regionDropDownWidth) * 0.5,
      y = 49.0,
      w = regionDropDownWidth,
      h = 24.0,
      l.regions.sortedRegionNames,
      sortedRegionIdx,
      tooltip = "",
      disabled = not (ui.editMode in {emNormal, emSetCellLink}),
      style = a.theme.levelDropDownStyle
    )

    if sortedRegionIdx != prevSortedRegionIdx :
      let currRegionName = l.regions.sortedRegionNames[sortedRegionIdx]
      let (regionCoords, _) = l.regions.findFirstByName(currRegionName).get

      let (r, c) = a.doc.map.getRegionCenterLocation(ui.cursor.levelId,
                                                     regionCoords)

      centerCursorAt(Location(levelId: ui.cursor.levelId, row: r, col: c), a)

# }}}
# {{{ renderModeAndOptionIndicators()
proc renderModeAndOptionIndicators*(x, y: float; a) =
  alias(vg, a.vg)
  alias(ui, a.ui)

  let lt = a.theme.levelTheme

  vg.save

  vg.fillColor(lt.coordinatesHighlightColor)

  var x = x

  if a.ui.wasdMode:
    vg.setFont(15, "sans-bold")
    discard vg.text(x, y, fmt"WASD+{IconMouse}")
    x += 80

  if a.ui.drawTrail:
    vg.setFont(19, "sans-bold")
    discard vg.text(x, y+1, IconShoePrints)

  vg.restore

# }}}
# {{{ renderNoteTooltip()
proc renderNoteTooltip*(x, y: float, levelDrawWidth, levelDrawHeight: float,
                       note: Annotation, a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(dp, a.ui.drawLevelParams)
  alias(lt, a.theme.levelTheme)

  if note.text != "":
    const PadX = 10
    const PadY = 8

    var
      noteBoxX = x
      noteBoxY = y
      noteBoxW = 250.0
      textX = noteBoxX + PadX
      textY = noteBoxY + PadY

    vg.setFont(14, "sans-bold", horizAlign=haLeft, vertAlign=vaTop)
    vg.textLineHeight(1.5)

    let
      breakWidth = noteBoxW - PadX*2
      bounds = vg.textBoxBounds(textX, textY, breakWidth, note.text)

      noteTextH = bounds.y2 - bounds.y1
      noteTextW = bounds.x2 - bounds.x1
      noteBoxH = noteTextH + PadY*2

    noteBoxW = noteTextW + PadX*2

    let
      xOver = noteBoxX + noteBoxW - (dp.startX + levelDrawWidth)
      yOver = noteBoxY + noteBoxH - (dp.startY + levelDrawHeight)

    if xOver > 0:
      noteBoxX -= xOver
      textX -= xOver

    if yOver > 0:
      let offs = noteBoxH + 22
      noteBoxY -= offs
      textY -= offs

    vg.drawShadow(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                  lt.noteTooltipShadowStyle)

    vg.fillColor(a.theme.levelTheme.noteTooltipBackgroundColor)
    vg.beginPath
    vg.roundedRect(noteBoxX, noteBoxY, noteBoxW, noteBoxH,
                   r=lt.noteTooltipCornerRadius)
    vg.fill

    vg.fillColor(a.theme.levelTheme.noteTooltipTextColor)
    vg.textBox(textX, textY, breakWidth, note.text)

# }}}

# {{{ renderLevel()
proc renderLevel*(x, y, w, h: float,
                 levelDrawWidth, levelDrawHeight: float; a) =

  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)
  alias(opts, a.opts)

  let
    l = currLevel(a)
    i = instantiationInfo(fullPaths=true)
    id = koi.generateId(i.filename, i.line, "gridmonger-level")

  if ui.prevCursor != ui.cursor:
    resetManualNoteTooltip(a)

  # Hit testing
  if koi.isHit(x, y, w, h):
    koi.setHot(id)
    if koi.hasNoActiveItem() and
       (koi.mbLeftDown() or koi.mbRightDown() or koi.mbMiddleDown()):
      koi.setActive(id)

  if isActive(id):
    handleLevelMouseEvents(a)

  # Draw level
  if dp.viewRows > 0 and dp.viewCols > 0:
    dp.cursorRow     = ui.cursor.row
    dp.cursorCol     = ui.cursor.col
    dp.cellCoordOpts = coordOptsForCurrLevel(a)
    dp.regionOpts    = l.regionOpts

    dp.pasteWraparound     = ui.pasteWraparound
    dp.selectionWraparound = (ui.pasteWraparound and
                              ui.editMode != emNudgePreview)

    if ui.walkMode and
       ((ui.editMode in {emNormal, emExcavateTunnel, emEraseCell,
                         emDrawClearFloor}) or
        (ui.editMode == emPanLevel and ui.prevEditMode == emNormal)):
      dp.cursorOrient = ui.cursorOrient.some
    else:
      dp.cursorOrient = CardinalDir.none

    dp.selection     = ui.selection
    dp.selectionRect = ui.selRect

    dp.selectionBuffer = (
      if ui.editMode == emPastePreview or
        (ui.editMode == emPanLevel and
         ui.prevEditMode == emPastePreview): ui.copyBuf

      elif ui.editMode in {emMovePreview, emNudgePreview} or
        (ui.editMode == emPanLevel and
         ui.prevEditMode in {emMovePreview, emNudgePreview}): ui.nudgeBuf

      else: SelectionBuffer.none
    )

    dp.drawLevel      = ui.editMode != emNudgePreview
    dp.drawCellCoords = a.ui.showCellCoords

    # Configure draw link lines
    dp.drawLinkLines    = false
    dp.drawAllLinkLines = false

    case a.prefs.linkLinesMode:
    of llmManual: discard
    of llmCurrentCell:
      dp.drawLinkLines    = true
    of llmAlways:
      dp.drawLinkLines    = true
      dp.drawAllLinkLines = true

    # The momentary toggle always shows all links lines
    if ui.momentaryShowLinkLines:
      dp.drawLinkLines    = true
      dp.drawAllLinkLines = true

    drawLevel(
      a.doc.map,
      ui.cursor.levelId,
      DrawLevelContext(lt: a.theme.levelTheme, dp: dp, vg: a.vg)
    )

  # Draw note tooltip
  const
    NoteTooltipXOffs = 16
    NoteTooltipYOffs = 20

  var mouseOverCellWithNote = false
  var note: Option[Annotation]

  if koi.isHot(id) and
     ui.editMode == emNormal and
     not (ui.wasdMode and isActive(id)) and
     (koi.mx() != ui.manualNoteTooltipState.mx or
      koi.my() != ui.manualNoteTooltipState.my):

    let loc = locationAtMouse(clampToBounds=false, a)
    if loc.isSome:
      let loc = loc.get

      note = l.getNote(loc.row, loc.col)
      if note.isSome:
        mouseOverCellWithNote = true
        resetManualNoteTooltip(a)


  if ui.manualNoteTooltipState.show:
    let loc = ui.manualNoteTooltipState.location
    note = l.getNote(loc.row, loc.col)

  if note.isSome:
    var x, y: float

    if mouseOverCellWithNote:
      x = koi.mx() + NoteTooltipXOffs
      y = koi.my() + NoteTooltipYOffs

    elif ui.manualNoteTooltipState.show:
      x = dp.startX + viewCol(a) * dp.gridSize + NoteTooltipXOffs
      y = dp.startY + viewRow(a) * dp.gridSize + NoteTooltipYOffs

    renderNoteTooltip(x, y, levelDrawWidth, levelDrawHeight, note.get, a)

# }}}
# {{{ renderEmptyMap()
proc renderEmptyMap*(a) =
  alias(vg, a.vg)

  let lt = a.theme.levelTheme

  vg.setFont(22, "sans-bold")
  vg.fillColor(lt.foregroundNormalNormalColor)
  vg.textAlign(haCenter, vaMiddle)

  let mainPane = mainPaneRect(a)
  var y = mainPane.h.float * 0.5
  discard vg.text(mainPane.x1 + mainPane.w.float * 0.5, y, "Empty map")

# }}}

# vim: et:ts=2:sw=2:fdm=marker
