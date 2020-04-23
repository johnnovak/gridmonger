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

  echo lvl
  echo ""
  echo rect
  echo ""
  echo "*** oldLinksFrom:"
  oldLinksFrom.dump()
  echo ""
  echo "*** oldLinksTo:"
  oldLinksTo.dump()
  echo ""

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

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ singleCellAction()
template singleCellAction(map; loc: Location; um;
                          actionName: string; actionMap, actionBody: untyped) =
  let
    c = loc.col
    r = loc.row
    cellRect = rectN(r, c, r+1, c+1)

  cellAreaAction(map, loc.level, cellRect, um, actionName, actionMap, actionBody)

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
proc eraseSelection*(map; level: Natural, sel: Selection, bbox: Rect[Natural]; um) =
  cellAreaAction(map, level, bbox, um, "Erase selection", m):
    var loc: Location
    loc.level = level

    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          loc.row = bbox.r1+r
          loc.col = bbox.c1+c
          m.eraseCell(loc)

# }}}
# {{{ fillSelection*()
proc fillSelection*(map; level: Natural, sel: Selection, bbox: Rect[Natural]; um) =
  cellAreaAction(map, level, bbox, um, "Fill selection", m):
    alias(l, m.levels[level])
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          l.eraseCell(row, col)
          l.setFloor(row, col, fEmpty)

# }}}
# {{{ surroundSelection*()
proc surroundSelectionWithWalls*(map; level: Natural, sel: Selection,
                                 bbox: Rect[Natural], um) =
  cellAreaAction(map, level, bbox, um, "Surround selection with walls", m):
    alias(l, m.levels[level])
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c

          proc setWall(l: var Level, dir: CardinalDir) =
            if l.canSetWall(row, col, dir):
              l.setWall(row, col, dir, wWall)

          if sel.isNeighbourCellEmpty(r,c, dirN): l.setWall(dirN)
          if sel.isNeighbourCellEmpty(r,c, dirE): l.setWall(dirE)
          if sel.isNeighbourCellEmpty(r,c, dirS): l.setWall(dirS)
          if sel.isNeighbourCellEmpty(r,c, dirW): l.setWall(dirW)

# }}}
# {{{ paste*()
proc paste*(map; dest: Location, cb: SelectionBuffer; um) =
  let rect = rectN(
    dest.row,
    dest.col,
    dest.row + cb.level.rows,
    dest.col + cb.level.cols
  ).intersect(
    rectN(
      0,
      0,
      map.levels[dest.level].rows,
      map.levels[dest.level].cols)
  )
  if rect.isSome:
    cellAreaAction(map, dest.level, rect.get, um, "Paste buffer", m):
      alias(l, m.levels[dest.level])
      l.paste(dest.row, dest.col, cb.level, cb.selection)

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
    l.paste(destRow, destCol, sb.level, sb.selection)
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
  elif srcFloor == fExitDoor:       destFloor = fExitDoor
  elif srcFloor in LinkStairs:
    if src.level < dest.level: destFloor = fStairsDown
    else: destFloor = fStairsUp

  # TODO fix src stairs if needed

  let linkType = linkFloorToString(srcFloor)
  map.links.dump()

  singleCellAction(map, dest, um,
                   fmt"Set link destination {EnDash} {linkType}", m):
    # support for overwriting existing link support
    # (delete existing links originating from src
    m.links.delBySrc(src)

    m.setFloor(dest, destFloor)
    m.links.set(src, dest)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
