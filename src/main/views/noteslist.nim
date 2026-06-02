import std/algorithm
import std/options
import std/sequtils
import std/strformat
import std/strutils except splitWhitespace, strip
import std/tables
import std/unicode

import koi
import nanovg

import common
import domain/all
import io/persistence
import main/appcontext
import main/cursor
import main/views/currentnote
import main/view
import ui/all
import utils/all


using a: var AppContext

# {{{ toSortOrder()
func toSortOrder(ak: AnnotationKind): int =
  case ak
  of akIndexed:  0
  of akCustomId: 1
  of akIcon:     2
  of akComment:  3
  of akLabel:    4

# }}}
# {{{ sortByNoteType()
func sortByNoteType(x, y: Annotation): int =
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

# }}}
# {{{ sortByTextAndLocation()
func sortByTextAndLocation(locX: Location, x: Annotation,
                           locY: Location, y: Annotation): int =
  var c = cmpNaturalIgnoreCase(x.text.toRunes,
                               y.text.toRunes); if c != 0: return c
  c     = cmp(locX.levelId, locY.levelId);      if c != 0: return c
  c     = cmp(locX.row,     locY.row);          if c != 0: return c
  return  cmp(locX.col,     locY.col)

# }}}

# {{{ rebuildNotesListCache()
proc rebuildNotesListCache(textW: float; a) =
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
proc noteButton(id: ItemId; textX, textY, textW, markerX: float;
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
# {{{ renderNotesListPane*()
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

# vim: et:ts=2:sw=2:fdm=marker
