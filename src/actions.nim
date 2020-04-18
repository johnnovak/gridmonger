import options
import strformat

import common
import level
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
  m: var Map
  um: var UndoManager[Map, UndoStateData]

# {{{ fullLevelAction()
# TODO investigate why we need to use different parameter names in nested
# templates
template fullLevelAction(map; loc: Location; um;
                         actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(actionName: actName, location: loc)

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    result = usd

  var undoLevel = newLevelFrom(map.levels[loc.level])
  var undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = undoLevel
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ cellAreaAction()
# TODO investigate why we need to use different parameter names in nested
# templates
template cellAreaAction(map; lvl: Natural, rect: Rect[Natural]; um;
                        actName: string, actionMap, actionBody: untyped) =

  let usd = UndoStateData(
    actionName: actName,
    location: Location(level: lvl, row: rect.r1, col: rect.c1)
  )

  let action = proc (actionMap: var Map): UndoStateData =
    actionBody
    actionMap.levels[lvl].reindexNotes()
    result = usd

  var undoLevel = newLevelFrom(map.levels[lvl], rect)

  var undoAction = proc (m: var Map): UndoStateData =
    m.levels[lvl].copyFrom(destRow=rect.r1, destCol=rect.c1, src=undoLevel,
                           srcRect=rectN(0, 0, rect.rows, rect.cols))
    m.levels[lvl].reindexNotes()
    result = usd

  um.storeUndoState(action, undoAction)
  discard action(map)

# }}}
# {{{ singleCellAction()
template singleCellAction(map; loc: Location; um;
                          actionName: string; actionMap, actionBody: untyped) =
  let c = loc.col
  let r = loc.row
  let cellRect = rectN(r, c, r+1, c+1)
  cellAreaAction(map, loc.level, cellRect, um, actionName, actionMap, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell walls", m):
    alias(l, m.levels[loc.level])
    l.eraseCellWalls(loc.row, loc.col)

# }}}

# {{{ eraseCell*()
proc eraseCell*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Erase cell", m):
    alias(l, m.levels[loc.level])
    l.eraseCell(loc.row, loc.col)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(map; level: Natural, sel: Selection, bbox: Rect[Natural]; um) =
  cellAreaAction(map, level, bbox, um, "Erase selection", m):
    alias(l, m.levels[level])
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          l.eraseCell(row, col)

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
    alias(l, m.levels[loc.level])
    l.setWall(loc.row, loc.col, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(map; loc: Location, f: Floor; um) =
  singleCellAction(map, loc, um, fmt"Set floor {EnDash} {f}", m):
    alias(l, m.levels[loc.level])
    l.setFloor(loc.row, loc.col, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(map; loc: Location, f: Floor, ot: Orientation; um) =
  singleCellAction(map, loc, um, fmt"Set oriented floor {EnDash} {f}", m):
    alias(l, m.levels[loc.level])
    l.setFloor(loc.row, loc.col, f)
    l.setFloorOrientation(loc.row, loc.col, ot)

# }}}
# {{{ excavate*()
proc excavate*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Excavate", m):
    alias(l, m.levels[loc.level])
    alias(c, loc.col)
    alias(r, loc.row)

    l.eraseCell(r,c)
    l.setFloor(r,c, fEmpty)

    if r == 0 or l.isFloorEmpty(r-1, c):
      l.setWall(r,c, dirN, wWall)
    else:
      l.setWall(r,c, dirN, wNone)

    if c == 0 or l.isFloorEmpty(r, c-1):
      l.setWall(r,c, dirW, wWall)
    else:
      l.setWall(r,c, dirW, wNone)

    if r == l.rows-1 or l.isFloorEmpty(r+1, c):
      l.setWall(r,c, dirS, wWall)
    else:
      l.setWall(r,c, dirS, wNone)

    if c == l.cols-1 or l.isFloorEmpty(r, c+1):
      l.setWall(r,c, dirE, wWall)
    else:
      l.setWall(r,c, dirE, wNone)

# }}}
# {{{ toggleFloorOrientation*()
proc toggleFloorOrientation*(map; loc: Location; um) =
  singleCellAction(map, loc, um, "Toggle floor orientation", m):
    alias(l, m.levels[loc.level])
    alias(c, loc.col)
    alias(r, loc.row)

    let newOt = if l.getFloorOrientation(r,c) == Horiz: Vert else: Horiz
    l.setFloorOrientation(r,c, newOt)

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
# TODO simplify, use fullLevelAction
proc nudgeLevel*(map; loc: Location, destRow, destCol: int, cb: SelectionBuffer;
                 um) =

  let usd = UndoStateData(actionName: "Nudge level", location: loc)

  # The level is cleared for the duration of the nudge operation and it is
  # stored temporarily in the SelectionBuffer
  let action = proc (m: var Map): UndoStateData =
    var l = newLevel(
      cb.level.locationName,
      cb.level.levelName,
      cb.level.elevation,
      cb.level.rows,
      cb.level.cols
    )
    l.paste(destRow, destCol, cb.level, cb.selection)
    m.levels[loc.level] = l
    result = usd

  var undoLevel = newLevelFrom(cb.level)
  var undoAction = proc (m: var Map): UndoStateData =
    m.levels[loc.level] = undoLevel
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

# vim: et:ts=2:sw=2:fdm=marker
