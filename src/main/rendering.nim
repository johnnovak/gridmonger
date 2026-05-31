# rendering
#
# All AppContext-aware rendering procs: level + tools pane + note panes +
# theme editor + status bar + quick reference + dialog dispatcher +
# top-level UI orchestrator. ui/drawlevel and ui/csdwindow are the
# AppContext-unaware visual primitives this layer sits on top of.
#
# Side effects: koi + nanovg drawing calls. Reads heavily from AppContext;
# writes back layout/scroll/note-cache state.

import std/algorithm
import std/lenientops
import std/math
import std/monotimes
import std/options
import std/sequtils
import std/setutils
import std/strformat
import std/strutils except splitWhitespace, strip
import std/sugar
import std/tables
import std/times
import std/unicode

import glfw
import koi
from koi/utils import lerp, invLerp, remap
import nanovg
import semver
import with

import cfghelper
import common
import domain/annotations
import domain/level
import domain/map
import domain/regions
import fieldlimits          # FieldLimits
import io/persistence       # NotesListSearchTermLimits
import main/appcontext
import main/constants
import main/cursor
import main/dialogs
import main/events          # handleLevelMouseEvents
import main/keyboard
import main/shortcuts
import main/status_msg
import main/themeio
import main/view
import ui/csdwindow
import ui/drawlevel
import ui/icons
import ui/theme             # DialogCornerRadiusLimits and other limits
import utils/converters
import utils/hocon
import utils/misc as gmUtils
import utils/naturalsort
import utils/rect


using a: var AppContext

# {{{ Level

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

# }}}
# {{{ Tools pane

# {{{ specialWallDrawProc()
proc specialWallDrawProc*(lt: LevelTheme,
                         tt: ToolbarPaneTheme,
                         dp: DrawLevelParams): RadioButtonsDrawProc =

  return proc (vg: NVGContext,
               id: ItemId, x, y, w, h: float,
               buttonIdx, numButtons: Natural, label: string,
               state: WidgetState, style: RadioButtonsStyle) =

    var (bgCol, active) = case state
                          of wsHover:
                            (tt.buttonHoverColor,  false)
                          of wsDown, wsActive, wsActiveHover, wsActiveDown:
                            (lt.cursorColor,       true)
                          else:
                            (tt.buttonNormalColor, false)

    # Nasty stuff, but it's not really worth refactoring everything for
    # this little aesthetic fix...
    let
      savedFloorColor = lt.floorBackgroundColor[0]
      savedForegroundNormalNormalColor = lt.foregroundNormalNormalColor
      savedForegroundLightNormalColor  = lt.foregroundLightNormalColor
      savedBackgroundImage = dp.backgroundImage

    lt.floorBackgroundColor[0] = lerp(lt.backgroundColor, bgCol, bgCol.a)
                                 .withAlpha(1.0)
    if active:
      lt.foregroundNormalNormalColor = lt.foregroundNormalCursorColor
      lt.foregroundLightNormalColor  = lt.foregroundLightCursorColor

    dp.backgroundImage = Paint.none

    const Pad = 5

    vg.beginPath
    vg.fillColor(bgCol)
    vg.rect(x, y, w-Pad, h-Pad)
    vg.fill

    dp.setZoomLevel(lt, 4)
    let ctx = DrawLevelContext(lt: lt, dp: dp, vg: vg)

    var cx = x + 5
    var cy = y + 15

    template drawAtZoomLevel(zl: Natural, body: untyped) =
      vg.save
      # A bit messy... but so is life! =8)
      dp.setZoomLevel(lt, zl)
      vg.intersectScissor(x+4.5, y+3, w-Pad*2-4, h-Pad*2-2)
      body
      dp.setZoomLevel(lt, 4)
      vg.restore

    let ot = Horiz

    case SpecialWalls[buttonIdx]
    of wNone:              discard
    of wWall:              drawSolidWallHoriz(cx, cy, ot, ctx=ctx)
    of wIllusoryWall:      drawIllusoryWallHoriz(cx+2, cy, ot, ctx=ctx)
    of wInvisibleWall:     drawInvisibleWallHoriz(cx-2, cy, ot, ctx=ctx)
    of wDoor:              drawDoorHoriz(cx, cy, ot, ctx=ctx)
    of wLockedDoor:        drawLockedDoorHoriz(cx, cy, ot, ctx=ctx)
    of wArchway:           drawArchwayHoriz(cx, cy, ot, ctx=ctx)

    of wSecretDoor:
      drawAtZoomLevel(6):  drawSecretDoorHoriz(cx-2, cy, ot, ctx=ctx)

    of wOneWayDoorNE:
      drawAtZoomLevel(8):  drawOneWayDoorHorizNE(cx-4, cy+1, ot, ctx=ctx)

    of wLeverSW:
      drawAtZoomLevel(6):  drawLeverHorizSW(cx-2, cy+1, ot, ctx=ctx)

    of wNicheSW:           drawNicheHorizSW(cx, cy, ot, floorColor=0, ctx=ctx)

    of wStatueSW:
      drawAtZoomLevel(6):  drawStatueHorizSW(cx-2, cy+2, ot, ctx=ctx)

    of wKeyhole:
      drawAtZoomLevel(6):  drawKeyholeHoriz(cx-2, cy, ot, ctx=ctx)

    of wWritingSW:
      drawAtZoomLevel(12): drawWritingHorizSW(cx-6, cy+4, ot, ctx=ctx)

    else: discard

    # ...aaaaand restore it!
    lt.floorBackgroundColor[0] = savedFloorColor
    lt.foregroundNormalNormalColor = savedForegroundNormalNormalColor
    lt.foregroundLightNormalColor = savedForegroundLightNormalColor
    dp.backgroundImage = savedBackgroundImage

# }}}
# {{{ renderToolsPane()
proc renderToolsPane*(x, y, w, h: float; a) =
  alias(ui, a.ui)
  alias(lt, a.theme.levelTheme)
  alias(vg, a.vg)

  var
    toolItemsPerColumn = 12
    toolX = x

    colorItemsPerColum = 10
    colorX = x + 3
    colorY = y + 445

  let mainPane = mainPaneRect(a)

  if mainPane.h < ToolsPaneYBreakpoint2:
    colorItemsPerColum = 5
    toolX += 30

  if mainPane.h < ToolsPaneYBreakpoint1:
    toolItemsPerColumn = 6
    toolX -= 30
    colorX += 3
    colorY -= 210

  # Special walls
  koi.radioButtons(
    x = toolX,
    y = y,
    w = 36,
    h = 35,
    labels = newSeq[string](SpecialWalls.len),
    ui.currSpecialWall,
    tooltips = SpecialWallTooltips,
    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: toolItemsPerColumn),

    drawProc = specialWallDrawProc(
      a.theme.levelTheme, a.theme.toolbarPaneTheme, ui.toolbarDrawParams
    ).some
  )

  # Floor colours
  var floorColors = collect:
    for fc in 0..lt.floorBackgroundColor.high:
      calcBlendedFloorColor(fc, lt.floorTransparent, lt)

  koi.radioButtons(
    x = colorX,
    y = colorY,
    w = 30,
    h = 30,
    labels = newSeq[string](lt.floorBackgroundColor.len),
    ui.currFloorColor,
    tooltips = @[],

    layout = RadioButtonsLayout(kind: rblGridVert,
                                itemsPerColumn: colorItemsPerColum),

    drawProc = colorRadioButtonDrawProc(floorColors, lt.cursorColor).some
  )

# }}}

# }}}
# {{{ Note panes

# {{{ renderIndexedNote()
proc renderIndexedNote*(x, y: float; size: float; bgColor, fgColor: Color;
                       shape: NoteBackgroundShape; index: Natural; a) =
  alias(vg, a.vg)

  vg.fillColor(bgColor)
  vg.beginPath

  case shape
  of nbsCircle:
    vg.circle(x + size*0.5, y + size*0.5, size*0.38)
  of nbsRectangle:
    let pad = 4.0
    vg.rect(x+pad, y+pad, size-pad*2, size-pad*2)

  vg.fill

  var fontSizeFactor = if   index <  10: 0.4
                       elif index < 100: 0.37
                       else:             0.32

  vg.setFont(size*fontSizeFactor, "sans-bold")
  vg.fillColor(fgColor)
  vg.textAlign(haCenter, vaMiddle)

  discard vg.text(x + size*0.51, y + size*0.54, $index)

# }}}
# {{{ renderNoteMarker()
proc renderNoteMarker*(x, y, w, h: float, note: Annotation, textColor: Color,
                      indexedNoteSize: float = 36.0; a) =
  alias(vg, a.vg)

  let s = a.theme.currentNotePaneTheme

  vg.save

  case note.kind
  of akIndexed:
    renderIndexedNote(x, y-2, size=indexedNoteSize,
                      bgColor=s.indexBackgroundColor[note.indexColor],
                      fgColor=s.indexColor,
                      a.theme.levelTheme.notebackgroundShape,
                      note.index, a)

  of akCustomId:
    vg.fillColor(textColor)
    vg.setFont(18, "sans-black", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+18, y+8, note.customId)

  of akIcon:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+7, NoteIcons[note.icon])

  of akComment:
    vg.fillColor(textColor)
    vg.setFont(19, "sans-bold", horizAlign=haCenter, vertAlign=vaTop)
    discard vg.text(x+20, y+8, IconComment)

  of akLabel: discard

  vg.restore

# }}}
# {{{ renderCurrentNotePane()
proc renderCurrentNotePane*(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let
    l = currLevel(a)
    cur = a.ui.cursor
    note = l.getNote(cur.row, cur.col)

  if note.isSome and not (a.ui.editMode in {emPastePreview, emNudgePreview}):
    let note = note.get
    if note.text == "" or note.kind == akLabel: return

    renderNoteMarker(x, y, w, h, note,
                     textColor=a.theme.currentNotePaneTheme.textColor, a=a)

    var text = note.text
    const TextIndent = 44
    koi.textArea(x+TextIndent, y-1, w-TextIndent, h, text, disabled=true,
                 style=a.theme.noteTextAreaStyle)

# }}}

# {{{ Note sort functions
func toSortOrder*(ak: AnnotationKind): int =
  case ak
  of akIndexed:  0
  of akCustomId: 1
  of akIcon:     2
  of akComment:  3
  of akLabel:    4

func sortByNoteType*(x, y: Annotation): int =
  var c = 0
  if x.kind == y.kind:
    case x.kind:
    of akComment, akLabel: discard
    of akIndexed:
      c   = cmp(x.index,    y.index);    if c != 0: return c
    of akCustomId:
      c   = cmp(x.customId, y.customId); if c != 0: return c
    of akIcon:
      c   = cmp(x.icon,     y.icon);     if c != 0: return c
    return 0
  else:
    cmp(x.kind.toSortOrder, y.kind.toSortOrder)


func sortByTextAndLocation*(locX: Location, x: Annotation,
                           locY: Location, y: Annotation): int =
  var c = cmpNaturalIgnoreCase(x.text.toRunes,
                               y.text.toRunes); if c != 0: return c
  c     = cmp(locX.levelId, locY.levelId);      if c != 0: return c
  c     = cmp(locX.row,     locY.row);          if c != 0: return c
  return  cmp(locX.col,     locY.col)

# }}}
# {{{ rebuildNotesListCache()
proc rebuildNotesListCache*(textW: float; a) =
  alias(vg, a.vg)
  alias(nls, a.ui.notesListState)

  let map = a.doc.map

  # Sort functions
  func sortByTextLocationType(x, y: NotesListCacheEntry): int =
    let noteX = map.getNote(x.location).get
    let noteY = map.getNote(y.location).get
    var c = sortByTextAndLocation(x.location, noteX,
                                  y.location, noteY)
    if c != 0: return c
    sortByNoteType(noteX, noteY)

  func sortByTypeTextLocation(x, y: NotesListCacheEntry): int =
    let noteX = map.getNote(x.location).get
    let noteY = map.getNote(y.location).get
    var c = sortByNoteType(noteX, noteY)
    if c != 0: return c
    sortByTextAndLocation(x.location, noteX,
                          y.location, noteY)

  # Rebuild/reset caches if needed
  const NoteVertPad = 18

  proc toAnnotationKindSet(filter: set[NoteTypeFilter]): set[AnnotationKind] =
    for f in filter:
      case f
      of ntfNone:   result.incl(akComment)
      of ntfNumber: result.incl(akIndexed)
      of ntfId:     result.incl(akCustomId)
      of ntfIcon:   result.incl(akIcon)

  let
    annotationKindFilter = nls.currFilter.noteType.toAnnotationKindSet
    searchTerms = nls.currFilter.searchTerm.strip.toLower.splitWhitespace

  proc maybeAddCacheEntry(s: var seq[NotesListCacheEntry], loc: Location,
                          note: Annotation, vg: NVGContext) =
    if note.kind in annotationKindFilter and
       (searchTerms.len == 0 or
        searchTerms.anyIt(note.text.toLower.contains(it))):

      let
        idString   = fmt"notes-list:{loc.levelId}:{loc.row}:{loc.col}"
        id         = koi.hashId(idString)
        textBounds = vg.textBoxBounds(0, 0, textW, note.text)
        height     = textBounds.y2 - textBounds.y1 + NoteVertPad

      s.add(
        NotesListCacheEntry(kind: nckNote, id: id, location: loc,
                            height: height)
      )

  proc sortCacheEntries(s: var seq[NotesListCacheEntry],
                        orderBy: NoteOrdering) =
    case orderBy
    of noType: s.sort(sortByTypeTextLocation)
    of noText: s.sort(sortByTextLocationType)


  # Clear cache
  nls.cache = @[]

  proc collectLevelNotes(l: Level; a): auto =
    var s = newSeq[NotesListCacheEntry]()
    for r,c, note in l.allNotes:
      s.maybeAddCacheEntry(
        Location(levelId: l.id, row: r, col: c),
        note, vg
      )
    sortCacheEntries(s, nls.currFilter.orderBy)
    s

  proc collectRegionNotes(l: Level, rc: RegionCoords; a): auto =
    var s = newSeq[NotesListCacheEntry]()
    for loc, note in map.regionNotes(l.id, rc):
      s.maybeAddCacheEntry(
        Location(levelId: l.id, row: loc.row, col: loc.col),
        note, vg
      )
    sortCacheEntries(s, nls.currFilter.orderBy)
    s

  proc collectAllRegionNotes(l: Level; a): seq[NotesListCacheEntry] =
    for regionCoords, region in l.regions.sortedRegions:
      let s = collectRegionNotes(l, regionCoords, a)
      if s.len > 0:
        result.add(NotesListCacheEntry(kind: nckRegion,
                                       regionCoords: regionCoords))
        result.add(s)


  case nls.currFilter.scope:
  of nsfMap:
    for levelId in map.sortedLevelIds:
      let l = map.levels[levelId]
      let entries = if l.regionOpts.enabled: collectAllRegionNotes(l, a)
                    else:                    collectLevelNotes(l, a)

      if entries.len > 0:
        nls.cache.add(NotesListCacheEntry(kind: nckLevel, levelId: l.id))
        nls.cache.add(entries)

  of nsfLevel:
    let l = currLevel(a)
    nls.cache = if l.regionOpts.enabled: collectAllRegionNotes(l, a)
                else:                    collectLevelNotes(l, a)

  of nsfRegion:
    let l = currLevel(a)
    nls.cache = if l.regionOpts.enabled:
      let regionCoords = map.getRegionCoords(a.ui.cursor)
      collectRegionNotes(l, regionCoords, a)
    else:
      collectLevelNotes(l, a)

# }}}
# {{{ noteButton()
proc noteButton*(id: ItemId; textX, textY, textW, markerX: float;
                note: Annotation, active: bool): bool =
  alias(ui, g_app.ui)
  alias(nt, g_app.theme.notesListPaneTheme)

  koi.autoLayoutPre()

  let
    (x, y) = addDrawOffset(x=koi.autoLayoutNextX(),
                           y=koi.autoLayoutNextY())

    w = koi.autoLayoutNextItemWidth()
    h = koi.autoLayoutNextItemHeight()

  # Hit testing
  const ScrollBarWidth = 12

  if isHit(x, y, w-ScrollBarWidth, h):
    setHot(id)
    if koi.mbLeftDown() or koi.shiftDown():
      setActive(id)
      result = true

  addDrawLayer(koi.currentLayer(), vg):
    let
      state = if koi.isHot(id) and koi.isActive(id):        wsDown
              elif koi.isHot(id) and koi.hasNoActiveItem(): wsHover
              else:                                         wsNormal

      hover = state in {wsHover, wsDown}

    if active or hover:
      let bgColor = if active: nt.itemBackgroundActiveColor
                    else:      nt.itemBackgroundHoverColor

      vg.beginPath
      vg.fillColor(bgColor)
      vg.rect(x, y, w, h)
      vg.fill

    let textColor = if active:  nt.itemTextActiveColor
                    elif hover: nt.itemTextHoverColor
                    else:       nt.itemTextNormalColor

    if note.kind == akIndexed:
      renderNoteMarker(x + markerX + 3, y+2, w, h, note, textColor,
                       indexedNoteSize=32, g_app)
    else:
      renderNoteMarker(x + markerX, y, w, h, note, textColor, a=g_app)

    vg.setFont(14, "sans-bold")
    vg.fillColor(textColor)
    vg.textLineHeight(1.4)
    vg.textBox(x + textX, y + textY, textW, note.text)

  koi.autoLayoutPost()

# }}}
# {{{ renderNotesListPane()
proc renderNotesListPane*(x, y, w, h: float; a) =
  alias(vg, a.vg)
  alias(ui, a.ui)
  alias(nls, ui.notesListState)
  alias(nt, a.theme.notesListPaneTheme)

  let
    ws  = a.theme.windowTheme
    l   = currLevel(a)
    map = a.doc.map

  const FilterPanelHeight = 169

  const
    LeftPad    = 16
    RightPad   = 16
    TextIndent = 44

  # Top control panel
  vg.beginPath
  vg.rect(x, y, w, FilterPanelHeight)
  vg.fillColor(nt.controlsBackgroundColor)
  vg.fill

  # Notes list background
  vg.beginPath
  vg.rect(x, y+FilterPanelHeight, w, h-FilterPanelHeight)
  vg.fillColor(nt.listBackgroundColor)
  vg.fill

  var
    wx = LeftPad
    wy = y + 18

  let
    wh = 24
    ButtonWidth = 24

  # Scope filter
  koi.radioButtons(
    wx, wy, w=w-LeftPad-RightPad - 30, wh,
    nls.currFilter.scope,
    tooltips = @[
      "All map levels, group by level",
      "Current level only",
      "Current level only, group by region"
   ],
   style = a.theme.radioButtonStyle
  )

  # Link cursor
  var cbStyle = a.theme.checkBoxStyle.deepCopy
  cbStyle.icon.fontSize = 14.0
  cbStyle.iconActive   = IconLink
  cbStyle.iconInactive = IconLink

  nls.prevLinkCursor = nls.linkCursor

  koi.checkBox(
    wx+245, wy, w=ButtonWidth,
    nls.linkCursor,
    tooltip = "Link cursor and notes list",
    style = cbStyle
  )

  # Note types filter
  wy += 33
  if koi.button(wx+245, wy, w=ButtonWidth, wh, "A",
                tooltip = "Show all note types",
                style = a.theme.buttonStyle):
    nls.currFilter.noteType = {ntfNone, ntfNumber, ntfId, ntfIcon}

  koi.multiRadioButtons(
    wx, wy, w=w-LeftPad-RightPad - 30, wh,
    nls.currFilter.noteType, style = a.theme.radioButtonStyle
  )

  # Note text filter
  wy += 44
  koi.label(wx+1, wy, 60, wh, "Search", style=a.theme.labelStyle)

  if koi.button(wx+245, wy, w=ButtonWidth, wh, IconTrash,
                disabled = nls.currFilter.searchTerm.isEmptyOrWhitespace,
                tooltip = "Clear search term",
                style = a.theme.buttonStyle):
    nls.currFilter.searchTerm = ""

  koi.textField(
    wx+64, wy, w=174, wh, nls.currFilter.searchTerm,
    constraint = TextFieldConstraint(
      kind:   tckString,
      minLen: NotesListSearchTermLimits.minRuneLen,
      maxLen: NotesListSearchTermLimits.maxRuneLen.some
    ).some,
    style = a.theme.textFieldStyle
  )

  # Ordering
  wy += 33

  koi.label(wx+1, wy, 60, wh, "Order by", style=a.theme.labelStyle)

  koi.dropDown(
    wx+64, wy, w=65, wh, nls.currFilter.orderBy,
    style = a.theme.dropDownStyle
  )

  # Expand/collapse all
  proc setExpandedStates(expanded: bool; a) =
    case nls.currFilter.scope:
    of nsfMap:
      for k in nls.levelSections.keys:
        nls.levelSections[k] = expanded

      for k in nls.regionSections.keys:
        nls.regionSections[k] = expanded

    of nsfLevel:
      if l.regionOpts.enabled:
        for regionCoords, _ in l.regions.sortedRegions:
          nls.regionSections[(l.id, regionCoords)] = expanded

    of nsfRegion: discard


  let expandCollapseDisabled = case nls.currFilter.scope:
                               of nsfMap:    false
                               of nsfLevel:  not l.regionOpts.enabled
                               of nsfRegion: true

  if koi.button(wx+214, wy, w=ButtonWidth, wh, IconPlusSmall,
                tooltip = "Expand all groups",
                disabled = expandCollapseDisabled,
                style = a.theme.buttonStyle):
    setExpandedStates(expanded=true, a)

  if koi.button(wx+245, wy, w=ButtonWidth, wh, IconMinusSmall,
                tooltip = "Collapse all groups",
                disabled = expandCollapseDisabled,
                style = a.theme.buttonStyle):
    setExpandedStates(expanded=false, a)

  # Rebuild cache if necessary.
  #
  # Make sure to set the font parameters prior to that as the notes' text
  # bounds get calculated when rebuilding the cache.

  vg.setFont(14, "sans-bold")
  vg.textLineHeight(1.4)

  const NoteHorizOffs = -8

  let
    markerX = LeftPad + NoteHorizOffs
    textW   = w - TextIndent - LeftPad - RightPad - NoteHorizOffs

  var cacheRebuilt = false

  if map.levelsDirty or l.dirty or l.annotations.dirty or
     nls.currFilter != nls.prevFilter or
     ui.cursor.levelId != ui.prevCursor.levelId or
     (l.regionOpts.enabled and map.getRegionCoords(ui.cursor) !=
                               map.getRegionCoords(ui.prevCursor)):
    rebuildNotesListCache(textW, a)
    cacheRebuilt = true

  nls.prevFilter = nls.currFilter

  # Handle dirty flags
  if map.levelsDirty:
    for _, l in map.levels:
      if l.id notin nls.levelSections:
        nls.levelSections[l.id] = false

      if l.regionOpts.enabled:
        for regionCoords, _ in l.regions.sortedRegions:
          let key = (l.id, regionCoords)
          if key notin nls.regionSections:
            nls.regionSections[key] = false

    map.levelsDirty = false

  if l.annotations.dirty:
    l.annotations.dirty = false

  if l.dirty:
    l.dirty = false

  # Scroll view with notes
  const ScrollViewId = koi.hashId("notes-panel:scroll-view")

  let scrollViewHeight = h-FilterPanelHeight-1

  if nls.newActiveId.isSome and nls.newViewStartY.isSome:
    # We'll get here in the next frame syncToCursor was triggered in.
    # This one frame delay is necessary to completely eliminate flicker.
    koi.setScrollViewStartY(ScrollViewId, nls.newViewStartY.get)
    nls.activeId = nls.newActiveId

    nls.newActiveId   = ItemId.none
    nls.newViewStartY = float.none


  koi.beginScrollView(ScrollViewId, x,
                      y+FilterPanelHeight+1, w, scrollViewHeight,
                      style=a.theme.notesListScrollViewStyle)

  var lp = DefaultAutoLayoutParams
  lp.itemsPerRow = 1
  lp.rowWidth    = w
  lp.rowPad      = 0
  lp.labelWidth  = w
  lp.leftPad     = 0
  lp.sectionPad  = 0

  initAutoLayout(lp)

  # Sync current note to cursor
  let currNote = map.getNote(ui.cursor)

  if currNote.isNone or not nls.linkCursor:
    nls.activeId = ItemId.none

  # Syncing to cursor is only triggered a single time if we need to change the
  # active list item and the scroll view's position
  #
  # Triggering on cache rebuilds takes care of weird edge such as like
  # deleting a note then undoing it, without changing the cursor position
  # (this works because undo sets the current level's dirty flag).

  let syncToCursor = nls.linkCursor and (
                       cacheRebuilt or
                       (currNote.isSome and (ui.cursor != ui.prevCursor or
                                               not nls.prevLinkCursor))
                     )

  let currNoteInCache = nls.cache.anyIt(it.kind == nckNote and
                                        it.location == ui.cursor)

  if syncToCursor and currNoteInCache:
    if nls.currFilter.scope == nsfMap:
      nls.levelSections[l.id] = true

    if nls.currFilter.scope in {nsfMap, nsfLevel}:
      if l.regionOpts.enabled:
        let rc = map.getRegionCoords(ui.cursor)
        nls.regionSections[(l.id, rc)] = true

  # Render note buttons
  let textX = markerX + TextIndent

  var
    addNote   = true
    currLevel = l
    startY, itemHeight: float

  for e in nls.cache:
    case e.kind
    of nckLevel:
      currLevel = map.levels[e.levelId]
      addNote = koi.sectionHeader(currLevel.getDetailedName(short=true),
                                  nls.levelSections[currLevel.id],
                                  style=a.theme.notesListLevelSectionStyle)

    of nckRegion:
      if nls.currFilter.scope == nsfLevel or nls.levelSections[currLevel.id]:
        let region = currLevel.regions[e.regionCoords].get

        addNote = koi.subsectionHeader(
          region.name,
          nls.regionSections[(currLevel.id, e.regionCoords)],
          style=a.theme.notesListRegionSectionStyle)

    of nckNote:
      if not addNote:
        continue

      const MinHeight = 32
      let
        note   = map.getNote(e.location).get
        height = max(MinHeight, e.height)

      koi.nextRowHeight(height)
      koi.nextItemHeight(height)

      if syncToCursor and ui.cursor == e.location:
        startY          = koi.autoLayoutNextY()
        itemHeight      = height
        # We'll set the new active item in the next frame to eliminate flicker
        nls.newActiveId = e.id.some

      if noteButton(e.id, textX, textY=17, textW, markerX, note,
                    active = (nls.activeId.isSome and
                              nls.activeId.get == e.id)):
        moveCursorTo(e.location, a)
        if nls.linkCursor:
          nls.activeId = e.id.some

  koi.endScrollView()

  if nls.restoreViewStartY:
    koi.setScrollViewStartY(ScrollViewId, nls.viewStartY)
    nls.restoreViewStartY = false

  if syncToCursor and currNoteInCache:
    # We'll set the new view position in the next frame to eliminate flicker
    nls.newViewStartY = (startY - scrollViewHeight * 0.45 + itemHeight).some

  # Needed to save the scroll view position into the map file
  nls.viewStartY = koi.getScrollViewStartY(ScrollViewId)

# }}}
# }}}

# }}}
# {{{ Theme editor

var ThemeEditorScrollViewStyle = koi.getDefaultScrollViewStyle()
with ThemeEditorScrollViewStyle:
  vertScrollBarWidth      = 14.0
  scrollBarStyle.thumbPad = 4.0

var ThemeEditorSliderStyle = koi.getDefaultSliderStyle()
with ThemeEditorSliderStyle:
  trackCornerRadius = 8.0
  valueCornerRadius = 6.0

var ThemeEditorAutoLayoutParams = DefaultAutoLayoutParams
with ThemeEditorAutoLayoutParams:
  leftPad    = 14.0
  rightPad   = 16.0
  labelWidth = 185.0

# {{{ renderThemeEditorProps()
proc renderThemeEditorProps*(x, y, w, h: float; a) =
  alias(te, a.themeEditor)
  alias(cfg, a.theme.config)

  template prop(label: string, path: string, body: untyped)  =
    block:
      koi.label(label)
      koi.setNextId(path)
      body
      if a.theme.prevConfig.getOpt(path) != cfg.getOpt(path):
        te.modified = true

  template stringProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getStringOrDefault(path)
      koi.textfield(val)
      hocon.set(cfg, path, $val)

  template colorProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getColorOrDefault(path)
      koi.color(val)
      hocon.set(cfg, path, $val)

  template boolProp(label: string, path: string) =
    prop(label, path):
      var val = cfg.getBoolOrDefault(path)
      koi.checkBox(val)
      hocon.set(cfg, path, val)

  template floatProp(label: string, path: string, limits: FieldLimits) =
    prop(label, path):
      var val = cfg.getFloatOrDefault(path)
      koi.horizSlider(startVal=limits.minFloat,
                      endVal=limits.maxFloat,
                      val,
                      style=ThemeEditorSliderStyle)
      hocon.set(cfg, path, val)

  template enumProp(label: string, path: string, T: typedesc[enum]) =
    prop(label, path):
      var val = cfg.getEnumOrDefault(path, T)
      koi.dropDown(val)
      hocon.set(cfg, path, enumToDashCase($val))


  koi.beginScrollView(x, y, w, h, style=ThemeEditorScrollViewStyle)

  ThemeEditorAutoLayoutParams.rowWidth = w
  initAutoLayout(ThemeEditorAutoLayoutParams)

  var p: string

  # {{{ User interface section
  if koi.sectionHeader("User Interface", te.sectionUserInterface):

    if koi.subSectionHeader("Window", te.sectionTitleBar):
      p = "ui.window."
      group:
        colorProp("Border",           p & "border.color")

      group:
        colorProp("Background",       p & "background.color")
        let path = p & "background.image"
        stringProp("Background Image", path)

        koi.nextLayoutColumn()
        if koi.button("Reload", disabled=cfg.getString(path) == ""):
          a.theme.loadBackgroundImage = true

      group:
        p = "ui.window.title."
        colorProp("Title Background Normal",   p & "background.normal")
        colorProp("Title Background Inactive", p & "background.inactive")
        colorProp("Title Text Normal",         p & "text.normal")
        colorProp("Title Text Inactive",       p & "text.inactive")

      group:
        p = "ui.window."
        colorProp("Modified Flag Normal",      p & "modified-flag.normal")
        colorProp("Modified Flag Inactive",    p & "modified-flag.inactive")

      group:
        p = "ui.window.button."
        colorProp("Button Normal",    p & "normal")
        colorProp("Button Hover",     p & "hover")
        colorProp("Button Down",      p & "down")
        colorProp("Button Inactive",  p & "inactive")

    if koi.subSectionHeader("Dialog", te.sectionDialog):
      p = "ui.dialog."
      group:
        let CRLimits = DialogCornerRadiusLimits
        floatProp("Corner Radius",    p & "corner-radius", CRLimits)

      group:
        colorProp("Background",       p & "background")
        colorProp("Label",            p & "label")
        colorProp("Warning",          p & "warning")
        colorProp("Error",            p & "error")

      group:
        colorProp("Title Background", p & "title.background")
        colorProp("Title Text",       p & "title.text")

      group:
        let BWLimits = DialogBorderWidthLimits
        colorProp("Outer Border",       p & "outer-border.color")
        floatProp("Outer Border Width", p & "outer-border.width", BWLimits)
        colorProp("Inner Border",       p & "inner-border.color")
        floatProp("Inner Border Width", p & "inner-border.width", BWLimits)

      group:
        boolProp( "Shadow?",         p & "shadow.enabled")
        colorProp("Shadow Colour",   p & "shadow.color")
        floatProp("Shadow Feather",  p & "shadow.feather",  ShadowFeatherLimits)
        floatProp("Shadow X Offset", p & "shadow.x-offset", ShadowOffsetLimits)
        floatProp("Shadow Y Offset", p & "shadow.y-offset", ShadowOffsetLimits)

    if koi.subSectionHeader("Widget", te.sectionWidget):
      p = "ui.widget."
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",       p & "corner-radius", WCRLimits)
      group:
        colorProp("Background Normal",   p & "background.normal")
        colorProp("Background Hover",    p & "background.hover")
        colorProp("Background Active",   p & "background.active")
        colorProp("Background Disabled", p & "background.disabled")
      group:
        colorProp("Foreground Normal",   p & "foreground.normal")
        colorProp("Foreground Active",   p & "foreground.active")
        colorProp("Foreground Disabled", p & "foreground.disabled")

    if koi.subSectionHeader("Drop Down", te.sectionDropdown):
      p = "ui.drop-down."
      group:
        colorProp("Item List Background", p & "item-list-background")

    if koi.subSectionHeader("Text Field", te.sectionTextField):
      p = "ui.text-field."
      group:
        colorProp("Cursor",            p & "cursor")
        colorProp("Selection",         p & "selection")
      group:
        colorProp("Edit Background",   p & "edit.background")
        colorProp("Edit Text",         p & "edit.text")
      group:
        colorProp("Scroll Bar Normal", p & "scroll-bar.normal")
        colorProp("Scroll Bar Edit",   p & "scroll-bar.edit")

    if koi.subSectionHeader("Status Bar", te.sectionStatusBar):
      p = "ui.status-bar."
      group:
        colorProp("Background",        p & "background")
      group:
        colorProp("Text",              p & "text")
        colorProp("Warning",           p & "warning")
        colorProp("Error",             p & "error")
      group:
        colorProp("Coordinates",       p & "coordinates")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("About Button", te.sectionAboutButton):
      p = "ui.about-button."
      colorProp("Label Normal",        p & "label.normal")
      colorProp("Label Hover",         p & "label.hover")
      colorProp("Label Down",          p & "label.down")

    if koi.subSectionHeader("About Dialog", te.sectionAboutDialog):
      let path = "ui.about-dialog.logo"
      colorProp("Logo", path)
      if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
        a.dialogs.about.aboutLogo.updateLogoImage = true

    if koi.subSectionHeader("Quick Help", te.sectionQuickHelp):
      p = "ui.quick-help."
      group:
        colorProp("Background",        p & "background")
        colorProp("Title",             p & "title")
        colorProp("Text",              p & "text")
      group:
        colorProp("Command Background",p & "command.background")
        colorProp("Command",           p & "command.text")

    if koi.subSectionHeader("Splash Image", te.sectionSplashImage):
      group:
        p = "ui.splash-image."
        var path = p & "logo"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateLogoImage = true

        path = p & "outline"
        colorProp("Logo", path)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateOutlineImage = true

        path = p & "shadow-alpha"
        floatProp("Shadow Alpha", path, AlphaLimits)
        if cfg.getOpt(path) != a.theme.prevConfig.getOpt(path):
          a.splash.updateShadowImage = true

      group:
        koi.label("Show Splash")
        koi.checkBox(a.splash.show)

  # }}}
  # {{{ Level section
  if koi.sectionHeader("Level", te.sectionLevel):
    if koi.subSectionHeader("General", te.sectionLevelGeneral):
      p = "level.general."
      group:
        colorProp("Background",               p & "background")
      group:
        enumProp( "Line Width",               p & "line-width", LineWidth)
      group:
        colorProp("Foreground Normal",        p & "foreground.normal.normal")
        colorProp("Foreground Normal Cursor", p & "foreground.normal.cursor")
        colorProp("Foreground Light",         p & "foreground.light.normal")
        colorProp("Foreground Light Cursor",  p & "foreground.light.cursor")
      group:
        colorProp("Link Marker",              p & "link-marker")
        colorProp("Link Line",                p & "link-line")
      group:
        colorProp("Trail Normal",             p & "trail.normal")
        colorProp("Trail Cursor",             p & "trail.cursor")
      group:
        colorProp("Cursor",                   p & "cursor")
        colorProp("Cursor Guides",            p & "cursor-guides")
      group:
        colorProp("Selection",                p & "selection")
        colorProp("Paste Preview",            p & "paste-preview")
      group:
        colorProp("Coordinates Normal",       p & "coordinates.normal")
        colorProp("Coordinates Highlight",    p & "coordinates.highlight")
      group:
        colorProp("Region Border Normal",     p & "region-border.normal")
        colorProp("Region Border Empty",      p & "region-border.empty")

    if koi.subSectionHeader("Background Hatch", te.sectionBackgroundHatch):
      let WidthLimits = BackgroundHatchWidthLimits
      let SpacingLimits = BackgroundHatchSpacingFactorLimits

      p = "level.background-hatch."
      group:
        boolProp("Background Hatch?",     p & "enabled")
      group:
        colorProp("Hatch",                p & "color")
        floatProp("Hatch Stroke Width",   p & "width",          WidthLimits)
        floatProp("Hatch Spacing Factor", p & "spacing-factor", SpacingLimits)

    if koi.subSectionHeader("Grid", te.sectionGrid):
      p = "level.grid."
      group:
        enumProp( "Background Grid Style", p & "background.style", GridStyle)
        # TODO enabled if style != None
        colorProp("Background Grid",       p & "background.grid")
      group:
        enumProp( "Floor Grid Style",      p & "floor.style",      GridStyle)
        # TODO enabled if style != None
        colorProp("Floor Grid",            p & "floor.grid")

    if koi.subSectionHeader("Outline", te.sectionOutline):
      p = "level.outline."
      enumProp( "Style",         p & "style",        OutlineStyle)
      # TODO enabled if Style!=None
      enumProp( "Fill Style",    p & "fill-style",   OutlineFillStyle)
      # TODO enabled if Style>=Square Edges
      colorProp("Outline",       p & "color")
      # TODO enabled if Style>=Square Edges
      floatProp("Width",         p & "width-factor", OutlineWidthFactorLimits)
      boolProp( "Overscan",      p & "overscan")

    if koi.subSectionHeader("Shadow", te.sectionShadow):
      let SWLimits = ShadowWidthFactorLimits
      p = "level.shadow."
      group:
        colorProp("Inner Shadow",       p & "inner.color")
        floatProp("Inner Shadow Width", p & "inner.width-factor", SWLimits)
      group:
        colorProp("Outer Shadow",       p & "outer.color")
        floatProp("Outer Shadow Width", p & "outer.width-factor", SWLimits)

    if koi.subSectionHeader("Floor Colours", te.sectionFloorColors):
      p = "level.floor."
      group:
        boolProp("Transparent?", p & "transparent")

      group:
        colorProp("Colour 1",  p & "background.0")
        colorProp("Colour 2",  p & "background.1")
        colorProp("Colour 3",  p & "background.2")
        colorProp("Colour 4",  p & "background.3")
        colorProp("Colour 5",  p & "background.4")
        colorProp("Colour 6",  p & "background.5")
        colorProp("Colour 7",  p & "background.6")
        colorProp("Colour 8",  p & "background.7")
        colorProp("Colour 9",  p & "background.8")
        colorProp("Colour 10", p & "background.9")

    if koi.subSectionHeader("Notes", te.sectionNotes):
      p = "level.note."
      group:
        colorProp("Marker Normal",      p & "marker.normal")
        colorProp("Marker Cursor",      p & "marker.cursor")
      group:
        colorProp("Comment",            p & "comment")
      group:
        enumProp( "Background Shape",   p & "background-shape",
                  NoteBackgroundShape)

        colorProp("Background 1",       p & "index-background.0")
        colorProp("Background 2",       p & "index-background.1")
        colorProp("Background 3",       p & "index-background.2")
        colorProp("Background 4",       p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Tooltip Background",     p & "tooltip.background")
        colorProp("Tooltip Text",           p & "tooltip.text")
        floatProp("Tooltip Corner Radius ", p & "tooltip.corner-radius",
                  WidgetCornerRadiusLimits)
        colorProp("Tooltip Shadow",         p & "tooltip.shadow.color")

    if koi.subSectionHeader("Labels", te.sectionLabels):
      p = "level.label."
      group:
        colorProp("Label 1", p & "text.0")
        colorProp("Label 2", p & "text.1")
        colorProp("Label 3", p & "text.2")
        colorProp("Label 4", p & "text.3")

    if koi.subSectionHeader("Level Drop Down", te.sectionLevelDropDown):
      p = "level.level-drop-down."
      group:
        colorProp("Button Normal",        p & "button.normal")
        colorProp("Button Hover",         p & "button.hover")
        colorProp("Button Label",         p & "button.label")
      group:
        colorProp("Item List Background", p & "item-list-background")
        colorProp("Item Normal",          p & "item.normal")
        colorProp("Item Hover",           p & "item.hover")
      group:
        let WCRLimits = WidgetCornerRadiusLimits
        floatProp("Corner Radius",        p & "corner-radius", WCRLimits)
      group:
        colorProp("Shadow",               p & "shadow.color")

  # }}}
  # {{{ Panes section

  if koi.sectionHeader("Panes", te.sectionPanes):
    if koi.subSectionHeader("Current Note Pane", te.sectionCurrentNotePane):
      p = "pane.current-note."
      group:
        colorProp("Text",               p & "text")
      group:
        colorProp("Index Background 1", p & "index-background.0")
        colorProp("Index Background 2", p & "index-background.1")
        colorProp("Index Background 3", p & "index-background.2")
        colorProp("Index Background 4", p & "index-background.3")
        colorProp("Index",              p & "index")
      group:
        colorProp("Scroll Bar",         p & "scroll-bar")

    if koi.subSectionHeader("Notes List Pane", te.sectionNotesListPane):
      p = "pane.notes-list."
      group:
        colorProp("Controls Background",       p & "controls-background")
        colorProp("List Background",           p & "list-background")
      group:
        colorProp("Level Section Background",  p & "level-section.background")
        colorProp("Level Section Text",        p & "level-section.text")
      group:
        colorProp("Region Section Background", p & "region-section.background")
        colorProp("Region Section Text",       p & "region-section.text")
      group:
        colorProp("Section Separator",         p & "section-separator")
      group:
        colorProp("Item Background Hover",     p & "item.background.hover")
        colorProp("Item Background Active",    p & "item.background.active")
      group:
        colorProp("Item Text Normal",          p & "item.text.normal")
        colorProp("Item Text Hover",           p & "item.text.hover")
        colorProp("Item Text Active",          p & "item.text.active")
      group:
        colorProp("Scroll Bar",                p & "scroll-bar")

    if koi.subSectionHeader("Toolbar Pane", te.sectionToolbarPane):
      p = "pane.toolbar."
      colorProp("Button",       p & "button.normal")
      colorProp("Button Hover", p & "button.hover")

  # }}}

  koi.endScrollView()

  a.theme.prevConfig = cfg.deepCopy

# }}}
# {{{ renderThemeEditorPane()

proc renderThemeEditorPane*(x, y, w, h: float; a) =
  alias(vg, a.vg)

  let topSectionHeight = 130
  let propsHeight = h - topSectionHeight

  # Background
  vg.beginPath
  vg.rect(x, y, w, h)
  vg.fillColor(gray(0.3))
  vg.fill

  # Left separator line
  vg.strokeWidth(1.0)
  vg.lineCap(lcjSquare)

  vg.beginPath
  vg.moveTo(x+0.5, y)
  vg.lineTo(x+0.5, y+h)
  vg.strokeColor(gray(0.1))
  vg.stroke

  let
    bw = 68.0
    bp = 7.0
    wh = 22.0

  var cx = x
  var cy = y

  # Theme pane title
  const TitleHeight = 34

  vg.beginPath
  vg.rect(x+1, y, w, h=TitleHeight)
  vg.fillColor(gray(0.25))
  vg.fill

  let titleStyle = koi.getDefaultLabelStyle()
  titleStyle.align = haCenter

  cy += 6.0
  koi.label(cx, cy, w, wh, "T  H  E  M  E       E  D  I  T  O  R",
            style=titleStyle)

  # Theme name & action buttons
  vg.beginPath
  vg.rect(x+1, y+TitleHeight, w, h=96)
  vg.fillColor(gray(0.36))
  vg.fill

  cx = x+17
  cy += 45.0
  koi.label(cx, cy, w, wh, "Theme")

  let buttonsDisabled = koi.isDialogOpen()

  let themeNames = collect:
    for t in a.theme.themeNames: t.name

  var themeIndex = a.theme.currThemeIndex

  cx += 55.0
  koi.dropDown(
    cx, cy, w=189.0, wh,
    themeNames,
    themeIndex,
    tooltip = "",
    disabled = buttonsDisabled
  )

  proc switchTheme(a) =
    a.theme.nextThemeIndex = themeIndex.some

  if themeIndex != a.theme.currThemeIndex:
    if a.themeEditor.modified:
      openSaveDiscardThemeDialog(nextAction = switchTheme, a)
    else:
      switchTheme(a)

  # User theme indicator
  cx += 195
  var labelStyle = koi.getDefaultLabelStyle()

  if not a.currThemeName.userTheme:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "U", style=labelStyle)

  # User theme override indicator
  cx += 13
  labelStyle = koi.getDefaultLabelStyle()

  if not a.currThemeName.override:
    labelStyle.color = labelStyle.color.withAlpha(0.3)

  koi.label(cx, cy, 20, wh, "O", style=labelStyle)

  # Theme modified indicator
  cx += 16

  if a.themeEditor.modified:
    koi.label(cx, cy, 20, wh, IconAsterisk, style=koi.getDefaultLabelStyle())

  # Theme action buttons
  cx = x+15
  cy += 40.0

  if koi.button(cx, cy, w=bw, h=wh, "Save", disabled=buttonsDisabled):
    saveTheme(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Copy", disabled=buttonsDisabled):
    openCopyThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Rename",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openRenameThemeDialog(a)

  cx += bw + bp
  if koi.button(cx, cy, w=bw, h=wh, "Delete",
                disabled=not a.currThemeName.userTheme or buttonsDisabled):
    openDeleteThemeDialog(a)

  # Scroll view with properties

  # XXX hack to enable theme editing while a dialog is open
  let fc = koi.focusCaptured()
  koi.setFocusCaptured(a.themeEditor.focusCaptured)

  renderThemeEditorProps(x+1, y+topSectionHeight, w-2, h=propsHeight, a)

  a.themeEditor.focusCaptured = koi.focusCaptured()
  koi.setFocusCaptured(fc)

  a.theme.updateTheme = true

# }}}

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
# {{{ renderQuickReference()

proc renderQuickReference*(x, y, w, h: float; a) =
  alias(vg, a.vg)
  let cfg = a.theme.config

  let
    p = "ui.quick-help."
    bgColor          = cfg.getColorOrDefault(p & "background")
    textColor        = cfg.getColorOrDefault(p & "text")
    titleColor       = cfg.getColorOrDefault(p & "title")
    commandBgColor   = cfg.getColorOrDefault(p & "command.background")
    commandTextColor = cfg.getColorOrDefault(p & "command.text")


  proc renderSection(x, y: float; items: seq[QuickRefItem];
                     colWidth: float; a: AppContext) =

    const
      RowHeight  = 24.0
      SepaHeight = 14.0

    var
      x0 = x
      x  = x
      y  = y
      heightInc = RowHeight

    vg.setFont(14, "sans-bold")

    for item in items:
      case item.kind
      of qkShortcut:
        let shortcuts = a.keys.shortcuts[item.shortcut]
        heightInc = 0.0
        var ys = y
        for sc in shortcuts:
          let shortcut = sc.toStr
          discard renderCommand(x, ys, shortcut,
                                commandBgColor, commandTextColor, a)
          ys += RowHeight
          heightInc += RowHeight
        if shortcuts.len > 1: heightInc += SepaHeight
        x += colWidth

      of qkKeyShortcuts:
        var sx = x
        for idx, sc in item.keyShortcuts:
          let shortcut = sc.toStr
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.keyShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight

      of qkCustomShortcuts:
        var sx = x
        for idx, shortcut in item.customShortcuts:
          var xa = renderCommand(sx, y, shortcut,
                                 commandBgColor, commandTextColor, a)
          if idx < item.customShortcuts.high:
            sx += xa + 13
            vg.fillColor(textColor)
            xa = vg.text(round(sx), round(y), $item.sepa)
            sx += 9
        x += colWidth
        heightInc = RowHeight


      of qkDescription:
        vg.fillColor(textColor)
        discard vg.text(round(x), round(y), item.description)
        x = x0
        y += heightInc

      of qkSeparator:
        y += SepaHeight


  let yOffs = ((h - 840) * 0.5).clampMin(0)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.save
    vg.intersectScissor(x, y, w, h)

  koi.addDrawLayer(koi.currentLayer(), vg):
    # Background
    vg.beginPath
    vg.rect(x, y, w, h)
    vg.fillColor(bgColor)
    vg.fill

    # Title
    vg.setFont(20, "sans-bold")
    vg.fillColor(titleColor)
    vg.textAlign(haCenter, vaMiddle)
    discard vg.text(round(x + w*0.5), 60+yOffs, "Quick Keyboard Reference")

  let
    t = invLerp(MinWindowWidth, 800.0, w).clamp(0.0, 1.0)
    viewWidth = lerp(652.0, 720.0, t)
    columnWidth = lerp(330.0, 350.0, t)
    tabWidth = 400.0

  let radioButtonX = x + (w - tabWidth)*0.5

  koi.radioButtons(
    radioButtonX, 92+yOffs, tabWidth, 24,
    QuickRefTabLabels, a.quickRef.activeTab,
    style = a.theme.radioButtonStyle
  )

  koi.beginScrollView(x = x + (w - viewWidth)*0.5 + 20,
                      y = y + 130+yOffs,
                      w = viewWidth, h = (h - 150))

  let a = a
  var (sx, sy) = addDrawOffset(10, 10)

  const DefaultColWidth = 120.0

  let (viewHeight, col1Width, col2Width) = case a.quickRef.activeTab
  of 0: (520.0, DefaultColWidth, DefaultColWidth)
  of 1: (655.0, DefaultColWidth, DefaultColWidth)
  else: (300.0, DefaultColWidth, DefaultColWidth)

  koi.addDrawLayer(koi.currentLayer(), vg):
    let itemColumns = a.keys.quickRefShortcuts[a.quickRef.activeTab]
    assert(itemColumns.len == 2)
    renderSection(sx, sy, itemColumns[0], col1Width, a)
    sx += columnWidth
    renderSection(sx, sy, itemColumns[1], col2Width, a)

  koi.endScrollView(viewHeight)

  koi.addDrawLayer(koi.currentLayer(), vg):
    vg.restore

# }}}
# {{{ renderDialogs()
proc renderDialogs*(a) =
  alias(dlg, a.dialogs)

  case dlg.activeDialog:
  of dlgNone: discard

  of dlgAbout:
    aboutDialog(dlg.about, a)

  of dlgPreferences:
    preferencesDialog(dlg.preferences, a)

  of dlgSaveDiscardMap:
    saveDiscardMapDialog(dlg.saveDiscardMap, a)

  of dlgNewMap:
    newMapDialog(dlg.newMap, a)

  of dlgEditMapProps:
    editMapPropsDialog(dlg.editMapProps, a)

  of dlgNewLevel:
    newLevelDialog(dlg.newLevel, a)

  of dlgDeleteLevel:
    deleteLevelDialog(a)

  of dlgEditLevelProps:
    editLevelPropsDialog(dlg.editLevelProps, a)

  of dlgEditNote:
    editNoteDialog(dlg.editNote, a)

  of dlgEditLabel:
    editLabelDialog(dlg.editLabel, a)

  of dlgResizeLevel:
    resizeLevelDialog(dlg.resizeLevel, a)

  of dlgEditRegionProps:
    editRegionPropsDialog(dlg.editRegionProps, a)

  of dlgSaveDiscardTheme:
    saveDiscardThemeDialog(dlg.saveDiscardTheme, a)

  of dlgCopyTheme:
    copyThemeDialog(dlg.copyTheme, a)

  of dlgRenameTheme:
    renameThemeDialog(dlg.renameTheme, a)

  of dlgOverwriteTheme:
    overwriteThemeDialog(dlg.overwriteTheme, a)

  of dlgDeleteTheme:
    deleteThemeDialog(a)

# }}}

# {{{ renderUI()
proc renderUI*(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    mainPane = mainPaneRect(a)
    toolsPaneHeight = toolsPaneHeight(mainPane.h)

  # Clear background
  vg.beginPath

  # Make sure the background image extends to the notes list pane if open
  vg.rect(0, mainPane.y1, mainPane.w + mainPane.x1, mainPane.h)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.windowTheme.backgroundColor)

  vg.fill

  if a.ui.showQuickReference:
    var w = koi.winWidth()
    if a.layout.showThemeEditor: w -= ThemePaneWidth

    renderQuickReference(x=0, y=mainPane.y1, w=w, h=mainPane.h, a)

  else:
    if not map.hasLevels:
      renderEmptyMap(a)

    else:
      koi.beginView(x=mainPane.x1, y=mainPane.y1, w=mainPane.w, h=mainPane.h)

      # About button
      if button(x=mainPane.w-55.0, y=19.0, w=20.0, h=DlgItemHeight,
                IconQuestion, style=a.theme.aboutButtonStyle, tooltip="About"):
        openAboutDialog(a)

      renderLevelDropdown(a)

      if currLevel(a).regionOpts.enabled:
        renderRegionDropDown(a)

      let (levelDrawWidth, levelDrawHeight) = calculateLevelDrawArea(a)
      updateViewAndCursorPos(levelDrawWidth, levelDrawHeight, a)
      updateLastCursorViewCoords(a)

      alias(dp, ui.drawLevelParams)

      renderLevel(
        x = dp.startX,
        y = dp.startY,
        w = dp.viewCols * dp.gridSize,
        h = dp.viewRows * dp.gridSize,
        levelDrawWidth  = levelDrawWidth,
        levelDrawHeight = levelDrawHeight,
        a
      )

      renderModeAndOptionIndicators(
        x = mainPane.x1 + LevelLeftPad_NoCoords,
        y = a.win.titleBarHeight + 32,
        a
      )

      if a.layout.showToolsPane:
        renderToolsPane(
          x = mainPane.w - toolsPaneWidth(a),
          y = ToolsPaneTopPad,
          w = toolsPaneWidth(a),
          h = toolsPaneHeight,
          a
        )

      koi.endView()


    if map.hasLevels:
      if a.layout.showCurrentNotePane:
        var paneWidth = mainPane.w - CurrentNotePaneLeftPad -
                                     CurrentNotePaneRightPad

        let totalNotePaneHeight = CurrentNotePaneHeight +
                                  CurrentNotePaneTopPad +
                                  CurrentNotePaneBottomPad

        if mainPane.h - toolsPaneHeight - ToolsPaneTopPad <
           totalNotePaneHeight - 30:
          paneWidth -= toolsPaneWidth(a)

        renderCurrentNotePane(
          x = mainPane.x1 + CurrentNotePaneLeftPad,
          y = mainPane.y2 - CurrentNotePaneHeight - CurrentNotePaneBottomPad,
          w = paneWidth,
          h = CurrentNotePaneHeight,
          a
        )

      if a.layout.showNotesListPane:
        renderNotesListPane(x = 0, y = mainPane.y1,
                            w = NotesListPaneWidth,
                            h = mainPane.h, a)

  # Status bar
  let statusBarY = mainPane.y1 + mainPane.h
  renderStatusBar(0, statusBarY, koi.winWidth(), StatusBarHeight, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.layout.showThemeEditor:
    let
      mainPane = mainPaneRect(a)
      x = mainPane.x1 + mainPane.w
      y = mainPane.y1
      w = ThemePaneWidth
      h = mainPane.h

    renderThemeEditorPane(x, y, w, h, a)

  renderDialogs(a)

  a.ui.prevCursor = a.ui.cursor


# vim: et:ts=2:sw=2:fdm=marker
