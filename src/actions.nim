import std/math
import std/options
import std/sets
import std/strformat
import std/tables

import common
import level
import links
import map
import rect
import selection
import undomanager
import utils


type UndoStateData* = object
  actionName*:   string
  location*:     Location
  undoLocation*: Location

using
  map: var Map
  um:  var UndoManager[Map, UndoStateData]

# {{{ cellAreaAction()
template cellAreaAction(map; loc, undoLoc: Location, rect: Rect[Natural];
                        um; groupWithPrev: bool,
                        actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(
    actionName: actName, location: loc, undoLocation: undoLoc
  )

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    actionMap.levels[loc.level].reindexNotes
    result = usd

  var oldLinks = map.links

  let undoLevel = map.newLevelFrom(loc.level, rect)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level].copyCellsAndAnnotationsFrom(
      destRow  = rect.r1,
      destCol  = rect.c1,
      srcLevel = undoLevel,
      srcRect  = rectN(0, 0, undoLevel.rows, undoLevel.cols)
    )
    m.levels[loc.level].reindexNotes

    # Delete existing links in undo area
    let delRect = rectN(
      rect.r1,
      rect.c1,
      rect.r1 + undoLevel.rows,
      rect.c1 + undoLevel.cols
    )

    m.links = oldLinks
    m.links.debugSanitise
    result = usd

  um.storeUndoState(action, undoAction, groupWithPrev)
  discard action(map)

# }}}
# {{{ singleCellAction()
template singleCellAction(map; loc, undoLoc: Location; um; groupWithPrev: bool,
                          actionName: string; actionMap, actionBody: untyped) =
  let
    c = loc.col
    r = loc.row
    cellRect = rectN(r, c, r+1, c+1)

  cellAreaAction(map, loc, undoLoc, cellRect, um, groupWithPrev,
                 actionName, actionMap, actionBody)

# }}}

# {{{ drawClearFloor*()
proc drawClearFloor*(map; loc, undoLoc: Location, floorColor: Natural;
                     um; groupWithPrev: bool) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev,
                   fmt"Draw/clear floor", m):

    let l = m.levels[loc.level]

    m.clearFloor(loc)
    m.setFloorColor(loc, floorColor)

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(map; loc, undoLoc: Location, floorColor: Natural;
                    um; groupWithPrev: bool) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev,
                   fmt"Set floor colour {EnDash} {floorColor}", m):

    m.setFloorColor(loc, floorColor)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(map; loc: Location, f: Floor, ot: Orientation,
                       floorColor: Natural; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   fmt"Set floor {EnDash} {f}", m):

    m.setFloor(loc, f)
    m.setFloorOrientation(loc, ot)

    if m.isEmpty(loc):
      m.setFloorColor(loc, floorColor)

# }}}
# {{{ toggleFloorOrientation*()
proc toggleFloorOrientation*(map; loc: Location; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Toggle floor orientation", m):

    let newOt = if m.getFloorOrientation(loc) == Horiz: Vert else: Horiz
    m.setFloorOrientation(loc, newOt)

# }}}
# {{{ eraseCell*()
proc eraseCell*(map; loc, undoLoc: Location; um; groupWithPrev: bool) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev,
                   "Erase cell", m):
    m.eraseCell(loc, preserveLabel=true)

# }}}
# {{{ setWall*()
proc setWall*(map; loc, undoLoc: Location, dir: CardinalDir, w: Wall; um;
              groupWithPrev: bool) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev,
                   fmt"Set wall {EnDash} {w}", m):
    m.setWall(loc, dir, w)

# }}}
# {{{ eraseCellWalls*()
proc eraseCellWalls*(map; loc: Location; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Erase cell walls", m):
    m.eraseCellWalls(loc)

# }}}
# {{{ excavateTunnel*()
proc excavateTunnel*(map; loc, undoLoc: Location, floorColor: Natural;
                     dir: Option[CardinalDir] = CardinalDir.none,
                     prevLoc: Option[Location] = Location.none,
                     prevDir: Option[CardinalDir] = CardinalDir.none;
                     um; groupWithPrev: bool) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev,
                   "Excavate tunnel", m):
    m.excavateTunnel(loc, floorColor, dir, prevLoc, prevDir)

# }}}

# {{{ drawTrail*()
proc drawTrail*(map; loc, undoLoc: Location; um) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev=false,
                   "Draw trail", m):
    m.setTrail(loc, on)

# }}}
# {{{ eraseTrail*()
proc eraseTrail*(map; loc, undoLoc: Location; um) =

  singleCellAction(map, loc, undoLoc, um, groupWithPrev=false,
                   "Erase trail", m):
    m.setTrail(loc, off)

# }}}
# {{{ excavateTrail*()
proc excavateTrail*(map; loc: Location, bbox: Rect[Natural],
                    floorColor: Natural; um) =

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Excavate trail in level", m):

    var loc = loc

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        loc.row = r
        loc.col = c

        if m.hasTrail(loc):
          if m.isEmpty(loc):
            m.excavateTunnel(loc, floorColor)
          else:
            m.setFloorColor(loc, floorColor)

# }}}
# {{{ clearTrailInLevel*()
proc clearTrailInLevel*(map; loc: Location, bbox: Rect[Natural]; um;
                        groupWithPrev = false;
                        actionName = "Clear trail in level") =

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev, actionName, m):
    var loc = loc

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        loc.row = r
        loc.col = c
        m.setTrail(loc, off)

# }}}

# {{{ setNote*()
proc setNote*(map; loc: Location, n: Annotation; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Set note", m):

    let l = m.levels[loc.level]
    if n.kind != akComment:
      m.clearFloor(loc)

    l.setAnnotation(loc.row, loc.col, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(map; loc: Location; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Erase note", m):

    let l = m.levels[loc.level]
    if m.hasNote(loc):
      l.delAnnotation(loc.row, loc.col)

# }}}
# {{{ setLabel*()
proc setLabel*(map; loc: Location, n: Annotation; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Set label", m):

    if not m.isEmpty(loc):
      m.clearFloor(loc)

    let l = m.levels[loc.level]
    l.setAnnotation(loc.row, loc.col, n)

# }}}
# {{{ eraseLabel*()
proc eraseLabel*(map; loc: Location; um) =

  singleCellAction(map, loc, loc, um, groupWithPrev=false,
                   "Erase label", m):

    let l = m.levels[loc.level]
    if m.hasLabel(loc):
      l.delAnnotation(loc.row, loc.col)

# }}}

# {{{ setLink*()
proc setLink*(map; src, dest: Location, floorColor: Natural; um) =
  let srcFloor = map.getFloor(src)
  let linkType = linkFloorToString(srcFloor)

  let usd = UndoStateData(
    actionName: fmt"Set link destination {EnDash} {linkType}",
    location: dest,
    undoLocation: src
  )

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let srcFloor = m.getFloor(src)

    var destFloor: Floor
    if   srcFloor in LinkPitSources:       destFloor = fCeilingPit
    elif srcFloor == fTeleportSource:      destFloor = fTeleportDestination
    elif srcFloor == fTeleportDestination: destFloor = fTeleportSource
    elif srcFloor == fEntranceDoor:        destFloor = fExitDoor
    elif srcFloor == fExitDoor:            destFloor = fEntranceDoor
    elif srcFloor in LinkStairs:
      let
        srcElevation  = m.levels[src.level].elevation
        destElevation = m.levels[dest.level].elevation

      if srcElevation < destElevation:
        destFloor = fStairsDown
        m.setFloor(src, fStairsUp)

      elif srcElevation > destElevation:
        destFloor = fStairsUp
        m.setFloor(src, fStairsDown)

      else:
        destFloor = if srcFloor == fStairsUp: fStairsDown else: fStairsUp

    # Don't reset the floor if we are linking to an existing teleport
    # destination. This allows for multiple teleport sources leading to the same
    # destination. TODO: Do we want to allow this for other link sources?
    if not (destFloor == fTeleportDestination and
            m.getFloor(dest) == destFloor):
      m.setFloor(dest, destFloor)

    if srcFloor == fTeleportDestination:
      assert destFloor == fTeleportSource
      # Reverse set to allow teleport destination having multiple sources.
      m.links.set(dest, src)
    else:
      m.links.set(src, dest)

    m.levels[dest.level].reindexNotes
    result = usd

  # Undo action
  let
    r = dest.row
    c = dest.col
    rect = rectN(r, c, r+1, c+1)  # single cell

  let undoLevel = map.newLevelFrom(dest.level, rect)

  var oldLinks = initLinks()

  var oldDest = map.links.getBySrc(dest)
  if oldDest.isSome: oldLinks.set(dest, oldDest.get)

  var oldSrcs = map.links.getByDest(dest)
  if oldSrcs.isSome:
    for oldSrc in oldSrcs.get: oldLinks.set(oldSrc, dest)

  oldDest = map.links.getBySrc(src)
  if oldDest.isSome: oldLinks.set(src, oldDest.get)

  oldSrcs = map.links.getByDest(src)
  if oldSrcs.isSome:
    for oldSrc in oldSrcs.get: oldLinks.set(oldSrc, src)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[dest.level].copyCellsAndAnnotationsFrom(
      destRow  = rect.r1,
      destCol  = rect.c1,
      srcLevel = undoLevel,
      srcRect  = rectN(0, 0, 1, 1)  # single cell
    )
    m.levels[dest.level].reindexNotes

    # Delete existing links in undo area
    m.links.delBySrc(dest)
    m.links.delByDest(dest)

    m.links.addAll(oldLinks)

    result = usd


  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# {{{ eraseSelection*()
proc eraseSelection*(map; level: Natural, sel: Selection,
                     bbox: Rect[Natural]; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Erase selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc, preserveLabel=true)

# }}}
# {{{ fillSelection*()
proc fillSelection*(map; level: Natural, sel: Selection,
                    bbox: Rect[Natural], floorColor: Natural; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Fill selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc, preserveLabel=true)
          m.clearFloor(loc)
          m.setFloorColor(loc, floorColor)

# }}}
# {{{ surroundSelection*()
proc surroundSelectionWithWalls*(map; level: Natural, sel: Selection,
                                 bbox: Rect[Natural]; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Surround selection with walls", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c

          proc setWall(m: var Map, dir: CardinalDir) =
            if m.canSetWall(loc, dir):
              m.setWall(loc, dir, wWall)

          if sel.isNeighbourCellEmpty(r,c, dirN): setWall(m, dirN)
          if sel.isNeighbourCellEmpty(r,c, dirE): setWall(m, dirE)
          if sel.isNeighbourCellEmpty(r,c, dirS): setWall(m, dirS)
          if sel.isNeighbourCellEmpty(r,c, dirW): setWall(m, dirW)

# }}}
# {{{ setSelectionFloorColor*()
proc setSelectionFloorColor*(map; level: Natural, sel: Selection,
                             bbox: Rect[Natural], floorColor: Natural; um) =

  let loc = Location(level: level, row: bbox.r1, col: bbox.c1)

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Set floor colour of selection", m):

    var loc = Location(level: level)

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c

          if not m.isEmpty(loc):
            m.setFloorColor(loc, floorColor)

# }}}
# {{{ cutSelection*()
proc cutSelection*(map; loc: Location, bbox: Rect[Natural], sel: Selection,
                   linkDestLevelIndex: Natural; um) =

  let level = loc.level
  var oldLinks = map.links.filterByInRect(level, bbox, sel.some)
  map.links.debugSanitise

  proc transformAndCollectLinks(origLinks: Links, selection: Selection,
                                bbox: Rect[Natural]): Links =
    result = initLinks()

    for src, dest in origLinks:
      var src = src
      var dest = dest
      var addLink = false

      # Transform location so it's relative to the top-left corner of the
      # buffer
      if selection[src.row, src.col] and
         src.level == level and bbox.contains(src.row, src.col):

        src.level = linkDestLevelIndex
        src.row = src.row - bbox.r1
        src.col = src.col - bbox.c1
        addLink = true

      if selection[dest.row, dest.col] and
         dest.level == level and bbox.contains(dest.row, dest.col):

        dest.level = linkDestLevelIndex
        dest.row = dest.row - bbox.r1
        dest.col = dest.col - bbox.c1
        addLink = true

      if addLink:
        result.set(src, dest)


  let newLinks = transformAndCollectLinks(oldLinks, sel, bbox)

  cellAreaAction(map, loc, loc, bbox, um, groupWithPrev=false,
                 "Cut selection", m):

    for s in oldLinks.sources:
      m.links.delBySrc(s)

    m.links.addAll(newLinks)
    m.links.debugSanitise()

    var l: Location
    l.level = level

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          l.row = r
          l.col = c

          m.eraseCell(l, preserveLabel=false)

# }}}
# {{{ pasteSelection*()
proc pasteSelection*(map; loc, undoLoc: Location, sb: SelectionBuffer,
                     pasteBufferLevelIndex: Option[Natural],
                     wraparound: bool; um;
                     groupWithPrev = false, pasteTrail = false,
                     actionName = "Pasted buffer") =

  let rect = if wraparound:
    let
      levelRows = map.levels[loc.level].rows
      levelCols = map.levels[loc.level].cols

    var rect = rectN(
      loc.row,
      loc.col,
      loc.row + sb.level.rows,
      loc.col + sb.level.cols
    )

    if rect.r2 >= levelRows:
      rect.r1 = 0
      rect.r2 = levelRows

    if rect.c2 >= levelCols:
      rect.c1 = 0
      rect.c2 = levelCols

    rect

  else:
    rectN(
      loc.row,
      loc.col,
      loc.row + sb.level.rows,
      loc.col + sb.level.cols

    ).intersect(
      rectN(
        0,
        0,
        map.levels[loc.level].rows,
        map.levels[loc.level].cols)
    ).get


  cellAreaAction(map, loc, undoLoc, rect, um, groupWithPrev, actionName, m):
    let l = m.levels[loc.level]

    var destRect: Option[Rect[Natural]]
    if wraparound:
      discard l.pasteWithWraparound(destRow=loc.row, destCol=loc.col,
                                    srcLevel=sb.level, sb.selection,
                                    pasteTrail=true,
                                    levelRows=l.rows,
                                    levelCols=l.cols,
                                    selStartRow=loc.row,
                                    selStartCol=loc.col)
      destRect = rect.some
    else:
      destRect = l.paste(loc.row, loc.col,
                         sb.level, sb.selection, pasteTrail)

    if destRect.isSome:
      let destRect = destRect.get

      # Add paste location offset & account for potential wraparound
      func offsetLocation(t: Location): Location =
        Location(level: loc.level,
                 row: (t.row + loc.row).floorMod(l.rows),
                 col: (t.col + loc.col).floorMod(l.cols))

      # Erase existing map links in the paste area (taking selection into
      # account)
      for r in 0..<sb.level.rows:
        for c in 0..<sb.level.cols:
          if sb.selection[r, c]:
            m.eraseCellLinks(
              offsetLocation(Location(level: loc.level, row: r, col: c))
            )

      if pasteBufferLevelIndex.isSome:
        # Recreate links from the paste buffer
        var
          linksToDeleteBySrc  = newSeq[Location]()
          linksToDeleteByDest = newSeq[Location]()
          linksToAdd          = initLinks()

        # It's more efficient to just iterate through all links in the map in
        # one go
        for src, dest in m.links:
          var
            src = src
            dest = dest
            addLink = false
            srcInside = true
            destInside = true

          # Link starting from a paste buffer location (pointing to either
          # a map location, or to another paste buffer location)
          if src.level == pasteBufferLevelIndex.get:
            linksToDeleteBySrc.add(src)

            src = offsetLocation(src)

            # We need this check because the full paste rect might get clipped
            # if wraparound is off
            srcInside = destRect.contains(src.row, src.col)
            addLink = true

          # Link pointing to a paste buffer location (from either a map
          # location, or from another paste buffer location)
          if dest.level == pasteBufferLevelIndex.get:
            linksToDeleteByDest.add(dest)

            dest = offsetLocation(dest)

            # We need this check because the full paste rect might get clipped
            # if wraparound is off
            destInside = destRect.contains(dest.row, dest.col)
            addLink = true

          if addLink and srcInside and destInside:
            linksToAdd.set(src, dest)

        # Delete paste buffer links
        for s in linksToDeleteBySrc:  m.links.delBySrc(s)
        for s in linksToDeleteByDest: m.links.delByDest(s)

        # Recreate links between real map locations
        m.links.addAll(linksToAdd)

      m.normaliseLinkedStairs(loc.level)

# }}}

# {{{ addNewLevel*()
proc addNewLevel*(map; loc: Location,
                  locationName, levelName: string, elevation: int,
                  rows, cols: Natural,
                  overrideCoordOpts: bool, coordOpts: CoordinateOptions,
                  regionOpts: RegionOptions,
                  notes: string;
                  um): Location =

  let usd = UndoStateData(
    actionName: "New level", location: loc, undoLocation: loc
  )

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let newLevel = newLevel(locationName, levelName, elevation,
                            rows, cols,
                            overrideCoordOpts, coordOpts,
                            regionOpts,
                            notes)
    m.addLevel(newLevel)

    var usd = usd
    usd.location.level = m.levels.high
    result = usd

  # Undo action
  let undoAction = proc (m: var Map): UndoStateData =
    let level = m.levels.high
    m.delLevel(level)

    for src in m.links.filterByLevel(level).sources:
      m.links.delBySrc(src)
      m.links.debugSanitise

    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ deleteLevel*()
proc deleteLevel*(map; loc: Location; um): Location =

  let usd = UndoStateData(
    actionName: "Delete level", location: loc, undoLocation: loc
  )

  let oldLinks = map.links.filterByLevel(loc.level)

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let adjustLinks = loc.level < m.levels.high

    let currSortedLevelIdx = m.findSortedLevelIdxForLevel(usd.location.level)

    # If the deleted level wasn't the last, moves the last level into
    # the "hole" created by the delete
    m.delLevel(loc.level)

    for src in oldLinks.sources:
      m.links.delBySrc(src)

    if adjustLinks:
      let oldLevelIdx = m.levels.high+1
      let newLevelIdx = loc.level
      m.links.remapLevelIndex(oldLevelIdx, newLevelIdx)
      m.links.debugSanitise

    var usd = usd
    if m.levels.len == 0:
      usd.location.level = 0
    else:
      usd.location.level = m.sortedLevelIndexes[
        min(currSortedLevelIdx, m.levels.high)
      ]

    result = usd


  # Undo action
  let undoLevel = map.levels[loc.level].deepCopy

  let undoAction = proc (m: var Map): UndoStateData =
    let restoredLevel = undoLevel.deepCopy

    if loc.level > m.levels.high:
      m.addLevel(restoredLevel)
    else:
      # Move to the end
      let lastLevel = m.levels[loc.level]
      m.addLevel(lastLevel)
      m.setLevel(idx=loc.level, restoredLevel)
      m.sortLevels

      m.links.remapLevelIndex(oldIndex = loc.level, newIndex = m.levels.high)
      m.links.debugSanitise

    m.links.addAll(oldLinks)
    m.links.debugSanitise

    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ resizeLevel*()
proc resizeLevel*(map; loc: Location, newRows, newCols: Natural,
                  anchor: Direction; um): Location =

  let usd = UndoStateData(
    actionName: "Resize level", location: loc, undoLocation: loc
  )

  # Do action
  let
    levelId = map.levels[loc.level].id

    oldLinks = map.links.filterByLevel(loc.level)

    (copyRect, destRow, destCol) =
      map.levels[loc.level].calcResizeParams(newRows, newCols, anchor)

    newLevelRect = rectI(0, 0, newRows, newCols)
    rowOffs = destRow.int - copyRect.r1
    colOffs = destCol.int - copyRect.c1

    newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                          newLevelRect, wraparound=false)

  let action = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])

    var newLevel = newLevel(l.locationName, l.levelName, l.elevation,
                            newRows, newCols,
                            l.overrideCoordOpts, l.coordOpts,
                            l.regionOpts,
                            l.notes,
                            initRegions=false)
    newLevel.id = levelId
    newLevel.copyCellsAndAnnotationsFrom(destRow, destCol, l, copyRect)

    # Adjust links
    for src in oldLinks.sources: m.links.delBySrc(src)
    m.links.addAll(newLinks)
    m.links.debugSanitise

    # Adjust regions
    let (regionOffsRow, regionOffsCol) = calcRegionResizeOffsets(
      m, loc.level, newRows, newCols, anchor
    )

    newLevel.regions = initRegionsFrom(srcLevel=l.some, destLevel=newLevel,
                                       regionOffsRow, regionOffsCol)
    l = newLevel

    var usd = usd
    let loc = usd.location
    usd.location.col = (loc.col.int + colOffs).clamp(0, newCols-1).Natural
    usd.location.row = (loc.row.int + rowOffs).clamp(0, newRows-1).Natural
    result = usd


  # Undo action
  let
    undoLevel = map.levels[loc.level].deepCopy
    oldRegions = map.levels[loc.level].regions

  let undoAction = proc (m: var Map): UndoStateData =
    m.setLevel(idx=loc.level, undoLevel.deepCopy)

    for src in newLinks.sources: m.links.delBySrc(src)
    m.links.addAll(oldLinks)
    m.links.debugSanitise

    m.levels[loc.level].regions = oldRegions

    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ cropLevel*()
proc cropLevel*(map; loc: Location, cropRect: Rect[Natural]; um): Location =

  let usd = UndoStateData(
    actionName: "Crop level", location: loc, undoLocation: loc
  )

  # Do action
  let
    levelId = map.levels[loc.level].id

    oldLinks = map.links.filterByLevel(loc.level)

    newLevelRect = rectI(0, 0, cropRect.rows, cropRect.cols)
    rowOffs = -cropRect.r1
    colOffs = -cropRect.c1

    newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                          newLevelRect, wraparound=false)

  let action = proc (m: var Map): UndoStateData =
    var newLevel = m.newLevelFrom(loc.level, cropRect)
    newLevel.id = levelId
    m.setLevel(idx=loc.level, newLevel)

    # Adjust links
    for src in oldLinks.sources:m.links.delBySrc(src)
    m.links.addAll(newLinks)
    m.links.debugSanitise

    var usd = usd
    usd.location.col = max(usd.location.col.int + colOffs, 0).Natural
    usd.location.row = max(usd.location.row.int + rowOffs, 0).Natural
    result = usd


  # Undo action
  let
    undoLevel = map.levels[loc.level].deepCopy
    oldRegions = map.levels[loc.level].regions

  let undoAction = proc (m: var Map): UndoStateData =
    m.setLevel(idx=loc.level, undoLevel.deepCopy)

    for src in newLinks.sources: m.links.delBySrc(src)
    m.links.addAll(oldLinks)
    m.links.debugSanitise

    m.levels[loc.level].regions = oldRegions

    result = usd


  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ nudgeLevel*()
proc nudgeLevel*(map; loc: Location, rowOffs, colOffs: int,
                 sb: SelectionBuffer, wraparound: bool; um): Location =

  let usd = UndoStateData(
    actionName: "Nudge level", location: loc, undoLocation: loc
  )

  let
    levelId = map.levels[loc.level].id

    levelRect = rectI(0, 0, sb.level.rows, sb.level.cols)

    oldLinks = map.links.filterByLevel(loc.level)
    newLinks = oldLinks.shiftLinksInLevel(loc.level, rowOffs, colOffs,
                                          levelRect, wraparound)
  map.links.debugSanitise

  # Do action
  let action = proc (m: var Map): UndoStateData =
    var l = newLevel(
      sb.level.locationName, sb.level.levelName, sb.level.elevation,
      sb.level.rows, sb.level.cols,
      sb.level.overrideCoordOpts, sb.level.coordOpts,
      sb.level.regionOpts,
      sb.level.notes,
      initRegions=false
    )

    l.id = levelId

    if wraparound:
      discard l.pasteWithWraparound(destRow=rowOffs, destCol=colOffs,
                                    srcLevel=sb.level, sb.selection,
                                    pasteTrail=true,
                                    levelRows=sb.level.rows,
                                    levelCols=sb.level.cols,
                                    selStartRow=rowOffs,
                                    selStartCol=colOffs)
    else:
      discard l.paste(rowOffs, colOffs, sb.level, sb.selection,
                      pasteTrail=true)

    m.setLevel(idx=loc.level, l)

    for src in oldLinks.sources: m.links.delBySrc(src)
    m.links.addAll(newLinks)
    m.links.debugSanitise

    var usd = usd
    usd.location.row = max(usd.location.row + rowOffs, 0)
    usd.location.col = max(usd.location.col + colOffs, 0)
    result = usd


  # Undo action
  let undoLevel = sb.level.deepCopy

  let undoAction = proc (m: var Map): UndoStateData =
    m.setLevel(idx=loc.level, undoLevel.deepCopy)

    for src in newLinks.sources: m.links.delBySrc(src)
    m.links.addAll(oldLinks)
    m.links.debugSanitise

    result = usd

  um.storeUndoState(action, undoAction)
  action(map).location

# }}}
# {{{ setLevelProperties*()
proc setLevelProperties*(map; loc: Location, locationName, levelName: string,
                         elevation: int, overrideCoordOpts: bool,
                         coordOpts: CoordinateOptions,
                         regionOpts: RegionOptions,
                         notes: string;
                         um) =

  let usd = UndoStateData(
    actionName: "Edit level properties", location: loc, undoLocation: loc
  )

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let l = m.levels[loc.level]

    let
      oldCoordOpts = m.coordOptsForLevel(loc.level)
      oldRegionOpts = l.regionOpts
      oldRegions = l.regions

    let adjustLinkedStairs = l.elevation != elevation

    let reallocateRegions = regionOpts != oldRegionOpts or
                            overrideCoordOpts != l.overrideCoordOpts or
                            (overrideCoordOpts and coordOpts != l.coordOpts)

    l.locationName      = locationName
    l.levelName         = levelName
    l.elevation         = elevation
    l.overrideCoordOpts = overrideCoordOpts
    l.coordOpts         = coordOpts
    l.regionOpts        = regionOpts
    l.notes             = notes
    l.dirty             = true

    if adjustLinkedStairs:
      m.normaliseLinkedStairs(loc.level)

    if reallocateRegions:
      m.reallocateRegions(loc.level, oldCoordOpts, oldRegionOpts, oldRegions)

    m.sortLevels
    result = usd


  let l = map.levels[loc.level]
  let
    oldLocationName      = l.locationName
    oldLevelName         = l.levelName
    oldElevation         = l.elevation
    oldOverrideCoordOpts = l.overrideCoordOpts
    oldCoordOpts         = l.coordOpts
    oldRegionOpts        = l.regionOpts
    oldRegions           = l.regions


  # Undo action
  var undoAction = proc (m: var Map): UndoStateData =
    let l = m.levels[loc.level]

    let adjustLinkedStairs = l.elevation != oldElevation

    l.locationName      = oldLocationName
    l.levelName         = oldLevelName
    l.elevation         = oldElevation
    l.overrideCoordOpts = oldOverrideCoordOpts
    l.coordOpts         = oldCoordOpts
    l.regionOpts        = oldRegionOpts
    l.regions           = oldRegions
    l.dirty             = true

    if adjustLinkedStairs:
      m.normaliseLinkedStairs(loc.level)

    m.sortLevels
    result = usd


  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# {{{ setMapProperties*()
proc setMapProperties*(map; loc: Location; title, game, author: string;
                       coordOpts: CoordinateOptions; notes: string; um) =

  let usd = UndoStateData(
    actionName: "Edit map properties", location: loc, undoLocation: loc
  )

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let oldCoordOpts = m.coordOpts

    m.title        = title
    m.game         = game
    m.author       = author
    m.notes        = notes
    m.coordOpts    = coordOpts

    if coordOpts != oldCoordOpts:
      for levelIdx, l in m.levels:
        if l.regionOpts.enabled and not l.overrideCoordOpts:
          m.reallocateRegions(levelIdx, oldCoordOpts,
                              oldRegionOpts = l.regionOpts,
                              oldRegions = l.regions)
    result = usd


  # Undo action
  let
    oldTitle     = map.title
    oldGame      = map.game
    oldAuthor    = map.author
    oldNotes     = map.notes
    oldCoordOpts = map.coordOpts

  var oldRegions = initTable[int, Regions]()

  for levelIdx, l in map.levels:
    if not l.overrideCoordOpts:
      oldRegions[levelIdx] = l.regions


  var undoAction = proc (m: var Map): UndoStateData =
    m.title        = oldTitle
    m.game         = oldGame
    m.author       = oldAuthor
    m.notes        = oldNotes
    m.coordOpts    = oldCoordOpts

    for levelIdx, l in m.levels.mpairs:
      if not l.overrideCoordOpts:
        l.regions = oldRegions[levelIdx]

    result = usd


  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# {{{ setRegionProperties*()
proc setRegionProperties*(map; loc: Location, rc: RegionCoords,
                          region: Region; um) =

  let usd = UndoStateData(
    actionName: "Edit region properties", location: loc, undoLocation: loc
  )

  # Do action
  let action = proc (m: var Map): UndoStateData =
    let l = m.levels[loc.level]
    l.setRegion(rc, region)
    result = usd

  # Undo action
  let l = map.levels[loc.level]
  let oldRegion = l.getRegion(rc).get

  var undoAction = proc (m: var Map): UndoStateData =
    let l = m.levels[loc.level]
    l.setRegion(rc, oldRegion)
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
