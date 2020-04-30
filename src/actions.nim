import options
import strformat

import common
import level
import links
import map
import rect
import selection
import undomanager
import utils


type UndoStateData* = object
  actionName*: string
  location*: Location

using
  map: var Map
  m:   var Map
  um:  var UndoManager[Map, UndoStateData]

# {{{ fullLevelAction()
# TODO investigate why we need to use different parameter names in nested
# templates
template fullLevelAction(map; loc: Location; um;
                         actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(actionName: actName, location: loc)

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    result = usd

  let undoLevel = newLevelFrom(map.levels[loc.level])
  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = undoLevel
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ cellAreaAction()
template cellAreaAction(map; lvl: Natural, rect: Rect[Natural]; um;
                        groupWithPrev: bool,
                        actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(
    actionName: actName,
    # TODO raise bug for this (doesn't compile if lvl is renamed to level)
    location: Location(level: lvl, row: rect.r1, col: rect.c1)
  )

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    actionMap.levels[lvl].reindexNotes()
    result = usd

  let oldLinksFrom = map.links.filterBySrcInRect(lvl, rect)
  let oldLinksTo   = map.links.filterByDestInRect(lvl, rect)

  let undoLevel = newLevelFrom(map.levels[lvl], rect)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[lvl].copyFrom(
      destRow = rect.r1,
      destCol = rect.c1,
      src     = undoLevel,
      srcRect = rectN(0, 0, undoLevel.rows, undoLevel.cols)
    )
    m.levels[lvl].reindexNotes()

    # Delete existing links in undo area
    let delRect = rectN(
      rect.r1,
      rect.c1,
      rect.r1 + undoLevel.rows,
      rect.c1 + undoLevel.cols
    )
    for src in m.links.filterBySrcInRect(lvl, delRect).keys:
      m.links.delBySrc(src)

    for src in m.links.filterByDestInRect(lvl, delRect).keys:
      m.links.delBySrc(src)

    m.links.addAll(oldLinksFrom)
    m.links.addAll(oldLinksTo)
    result = usd

  um.storeUndoState(action, undoAction, groupWithPrev)
  discard action(map)

# }}}
# {{{ singleCellAction()
template singleCellAction(map; loc: Location; um;
                          actionName: string; actionMap, actionBody: untyped) =
  let
    c = loc.col
    r = loc.row
    cellRect = rectN(r, c, r+1, c+1)

  cellAreaAction(map, loc.level, cellRect, um, groupWithPrev=false, 
                 actionName, actionMap, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell walls", m):
    m.eraseCellWalls(loc)

# }}}
# {{{ eraseCell*()
proc eraseCell*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell", m):
    m.eraseCell(loc)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(map; level: Natural, sel: Selection,
                     bbox: Rect[Natural]; um) =

  cellAreaAction(map, level, bbox, um, groupWithPrev=false,
                 "Erase selection", m):
    var loc: Location
    loc.level = level

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc)

# }}}
# {{{ fillSelection*()
proc fillSelection*(map; level: Natural, sel: Selection,
                    bbox: Rect[Natural]; um) =

  cellAreaAction(map, level, bbox, um, groupWithPrev=false,
                 "Fill selection", m):
    var loc: Location
    loc.level = level

    for r in bbox.r1..<bbox.r2:
      for c in bbox.c1..<bbox.c2:
        if sel[r,c]:
          loc.row = r
          loc.col = c
          m.eraseCell(loc)
          m.setFloor(loc, fEmpty)

# }}}
# {{{ surroundSelection*()
proc surroundSelectionWithWalls*(map; level: Natural, sel: Selection,
                                 bbox: Rect[Natural], um) =

  cellAreaAction(map, level, bbox, um, groupWithPrev=false,
                 "Surround selection with walls", m):
    var loc: Location
    loc.level = level

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
# {{{ paste*()
proc paste*(map; dest: Location, sb: SelectionBuffer; um;
            groupWithPrev: bool = false,
            actionName: string = "Pasted buffer") =

  let rect = rectN(
    dest.row,
    dest.col,
    dest.row + sb.level.rows,
    dest.col + sb.level.cols
  ).intersect(
    rectN(
      0,
      0,
      map.levels[dest.level].rows,
      map.levels[dest.level].cols)
  )

  if rect.isSome:
    cellAreaAction(map, dest.level, rect.get, um, groupWithPrev, actionName, m):
      alias(l, m.levels[dest.level])

      let bbox = l.paste(dest.row, dest.col, sb.level, sb.selection)

      if bbox.isSome:
        let bbox = bbox.get
        var loc: Location
        loc.level = dest.level

        # Erase links in the paste area
        for r in bbox.r1..<bbox.r2:
          for c in bbox.c1..<bbox.c2:
            loc.row = r
            loc.col = c
            m.eraseCellLinks(loc)

        # Recreate links from the copy buffer
        for s, d in sb.links.pairs():
          echo "src: ", s, ", dest: ", d
          var s = s
          if s.level == CopyBufferLevelIndex:
            s.level = dest.level
            s.row += dest.row
            s.col += dest.col

          var d = d
          if d.level == CopyBufferLevelIndex:
            d.level = dest.level
            d.row += dest.row
            d.col += dest.col

          echo "src: ", s, ", dest: ", d
          echo ""

          m.links.set(s, d)

# }}}
# {{{ setWall*()
proc setWall*(map; loc: Location, dir: CardinalDir, w: Wall; um) =

  singleCellAction(map, loc, um, fmt"Set wall {EnDash} {w}", m):
    m.setWall(loc, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(map; loc: Location, f: Floor; um) =

  singleCellAction(map, loc, um, fmt"Set floor {EnDash} {f}", m):
    m.setFloor(loc, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(map; loc: Location, f: Floor, ot: Orientation; um) =

  singleCellAction(map, loc, um, fmt"Set oriented floor {EnDash} {f}", m):
    m.setFloor(loc, f)
    m.setFloorOrientation(loc, ot)

# }}}
# {{{ excavate*()
proc excavate*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Excavate", m):
    alias(l, m.levels[loc.level])
    alias(c, loc.col)
    alias(r, loc.row)

    m.eraseCell(loc)
    m.setFloor(loc, fEmpty)

    if r == 0 or l.isFloorEmpty(r-1, c):
      m.setWall(loc, dirN, wWall)
    else:
      m.setWall(loc, dirN, wNone)

    if c == 0 or l.isFloorEmpty(r, c-1):
      m.setWall(loc, dirW, wWall)
    else:
      m.setWall(loc, dirW, wNone)

    if r == l.rows-1 or l.isFloorEmpty(r+1, c):
      m.setWall(loc, dirS, wWall)
    else:
      m.setWall(loc, dirS, wNone)

    if c == l.cols-1 or l.isFloorEmpty(r, c+1):
      m.setWall(loc, dirE, wWall)
    else:
      m.setWall(loc, dirE, wNone)

# }}}
# {{{ toggleFloorOrientation*()
proc toggleFloorOrientation*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Toggle floor orientation", m):
    let newOt = if m.getFloorOrientation(loc) == Horiz: Vert else: Horiz
    m.setFloorOrientation(loc, newOt)

# }}}
# {{{ setNote*()
proc setNote*(map; loc: Location, n: Note; um) =

  singleCellAction(map, loc, um, "Set note", m):
    alias(l, m.levels[loc.level])
    l.setNote(loc.row, loc.col, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(map; loc: Location; um) =

  singleCellAction(map, loc, um, "Erase note", m):
    alias(l, m.levels[loc.level])
    l.delNote(loc.row, loc.col)

# }}}

# {{{ resizeLevel*()
proc resizeLevel*(map; loc: Location, newRows, newCols: Natural,
                  align: Direction; um) =

  fullLevelAction(map, loc, um, "Resize level", m):
    alias(l, m.levels[loc.level])
    l = l.resize(newRows, newCols, align)

# }}}
# {{{ cropLevel*()
proc cropLevel*(map; loc: Location, rect: Rect[Natural]; um) =

  # TODO link support
  fullLevelAction(map, loc, um, "Crop level", m):
    m.levels[loc.level] = newLevelFrom(m.levels[loc.level], rect)

# }}}
# {{{ nudgeLevel*()
proc nudgeLevel*(map; loc: Location, destRow, destCol: int,
                 sb: SelectionBuffer; um) =

  let usd = UndoStateData(actionName: "Nudge level", location: loc)

  let oldFromLinks = map.links.filterBySrcLevel(loc.level)
  let oldToLinks   = map.links.filterByDestLevel(loc.level)

  var newFromLinks = initLinks()
  var newToLinks   = initLinks()

  let levelRect = rectI(0, 0, sb.level.rows, sb.level.cols)

  # TODO simplify, reduce duplication of logic?
  for src, dest in oldFromLinks.pairs:
    var r = src.row.int + destRow
    var c = src.col.int + destCol
    if levelRect.contains(r,c):
      let newSrc = Location(level: src.level, row: r, col: c)

      var newDest: Location
      if dest.level == src.level:
        r = dest.row.int + destRow
        c = dest.col.int + destCol

        if levelRect.contains(r,c):
          newDest = Location(level: dest.level, row: r, col: c)
        else:
          continue
      else:
        newDest = dest

      newFromLinks.set(newSrc, newDest)


  for src, dest in oldToLinks.pairs:
    var r = dest.row.int + destRow
    var c = dest.col.int + destCol
    if levelRect.contains(r,c):
      let newDest = Location(level: dest.level, row: r, col: c)

      var newSrc: Location
      if src.level == dest.level:
        r = src.row.int + destRow
        c = src.col.int + destCol

        if levelRect.contains(r,c):
          newSrc = Location(level: src.level, row: r, col: c)
        else:
          continue
      else:
        newSrc = src

      newToLinks.set(newSrc, newDest)


  # The level is cleared for the duration of the nudge operation and it is
  # stored temporarily in the SelectionBuffer
  let action = proc (m: var Map): UndoStateData =
    var l = newLevel(
      sb.level.locationName,
      sb.level.levelName,
      sb.level.elevation,
      sb.level.rows,
      sb.level.cols
    )
    discard l.paste(destRow, destCol, sb.level, sb.selection)
    m.levels[loc.level] = l

    for k in oldFromLinks.keys: m.links.delByKey(k)
    for k in oldToLinks.keys:   m.links.delByKey(k)

    m.links.addAll(newFromLinks)
    m.links.addAll(newToLinks)

    result = usd


  let undoLevel = newLevelFrom(sb.level)
  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = undoLevel

    for k in newFromLinks.keys: m.links.delByKey(k)
    for k in newtoLinks.keys:   m.links.delByKey(k)

    m.links.addAll(oldFromLinks)
    m.links.addAll(oldToLinks)

    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ setLevelProps()
proc setLevelProps*(map; loc: Location, locationName, levelName: string,
                    elevation: int; um) =

  let usd = UndoStateData(actionName: "Edit level properties", location: loc)

  let action = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])
    l.locationName = locationName
    l.levelName = levelName
    l.elevation = elevation
    m.refreshSortedLevelNames()
    result = usd

  alias(l, map.levels[loc.level])
  let oldLocationName = l.locationName
  let oldLevelName = l.levelName
  let oldElevation = l.elevation

  var undoAction = proc (m: var Map): UndoStateData =
    alias(l, m.levels[loc.level])
    l.locationName = oldLocationName
    l.levelName = oldLevelName
    l.elevation = oldElevation
    m.refreshSortedLevelNames()
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# {{{ setLink()
proc setLink*(map; src, dest: Location; um) =
  let srcFloor = map.getFloor(src)

  var destFloor: Floor
  if   srcFloor in LinkPitSources:  destFloor = fCeilingPit
  elif srcFloor == fTeleportSource: destFloor = fTeleportDestination
  elif srcFloor == fDoorEnter:      destFloor = fDoorExit
  elif srcFloor == fDoorExit:       destFloor = fDoorEnter
  elif srcFloor in LinkStairs:
    if map.levels[src.level].elevation < map.levels[dest.level].elevation:
      destFloor = fStairsDown
      # TODO could be made undoable, but probably not worth bothering with it
      map.setFloor(src, fStairsUp)
    else:
      destFloor = fStairsUp
      map.setFloor(src, fStairsDown)

  let level = dest.level
  let linkType = linkFloorToString(srcFloor)

  let usd = UndoStateData(
    actionName: fmt"Set link destination {EnDash} {linkType}",
    location: Location(level: src.level, row: src.row, col: src.col)
  )

  # Do Action
  let action = proc (m: var Map): UndoStateData =
    # edge case: support for overwriting existing link
    # (delete existing links originating from src)
    m.links.delBySrc(src)

    m.setFloor(dest, destFloor)
    m.links.set(src, dest)
    m.levels[level].reindexNotes()
    result = usd

  # Undo Action
  let
    r = dest.row
    c = dest.col
    rect = rectN(r, c, r+1, c+1)  # single cell

  let undoLevel = newLevelFrom(map.levels[level], rect)

  var oldLinks = initLinks()
  if map.links.hasWithSrc(dest):  oldLinks.set(dest, map.links.getBySrc(dest))
  if map.links.hasWithDest(dest): oldLinks.set(map.links.getByDest(dest), dest)
  if map.links.hasWithSrc(src):   oldLinks.set(src, map.links.getBySrc(src))
  if map.links.hasWithDest(src):  oldLinks.set(map.links.getByDest(src), src)

  let undoAction = proc (m: var Map): UndoStateData =
    m.levels[level].copyFrom(
      destRow = rect.r1,
      destCol = rect.c1,
      src     = undoLevel,
      srcRect = rectN(0, 0, 1, 1)  # single cell
    )
    m.levels[level].reindexNotes()

    # Delete existing links in undo area
    m.links.delBySrc(dest)
    m.links.delByDest(dest)

    m.links.addAll(oldLinks)

    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
