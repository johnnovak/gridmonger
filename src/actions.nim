import options

import common
import level
import rect
import selection
import undomanager
import utils


using
  map: var Map
  m: var Map
  um: var UndoManager[Map]

# {{{ fullLevelAction()
template fullLevelAction(map; level: Natural, um;
                         actionName: string, actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody

  var undoLevel = newLevelFrom(map.levels[level])
  var undoAction = proc (m: var Map) =
    m.levels[level] = undoLevel

  um.storeUndoState(actionName, action, undoAction)
  action(map)

# }}}
# {{{ cellAreaAction()
template cellAreaAction(map; level: Natural, rect: Rect[Natural], um;
                        actionName: string, actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody
    actionMap.levels[level].reindexNotes()

  var undoLevel = newLevelFrom(map.levels[level], rect)

  var undoAction = proc (m: var Map) =
    m.levels[level].copyFrom(destRow=rect.r1, destCol=rect.c1, src=undoLevel,
                             srcRect=rectN(0, 0, rect.rows, rect.cols))
    m.levels[level].reindexNotes()

  um.storeUndoState(actionName, action, undoAction)
  action(map)

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
proc eraseCellWalls*(map; loc: Location, um) =
  singleCellAction(map, loc, um, "Erase cell walls", m):
    alias(l, m.levels[loc.level])
    l.eraseCellWalls(loc.row, loc.col)

# }}}
# {{{ eraseCell*()
proc eraseCell*(map; loc: Location, um) =
  singleCellAction(map, loc, um, "Erase cell", m):
    alias(l, m.levels[loc.level])
    l.eraseCell(loc.row, loc.col)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(map; level: Natural, sel: Selection, bbox: Rect[Natural], um) =
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
proc fillSelection*(map; level: Natural, sel: Selection, bbox: Rect[Natural], um) =
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
proc surroundSelectionWithWalls*(map; level: Natural, sel: Selection, bbox: Rect[Natural],
                                 um) =
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
proc paste*(map; dest: Location, cb: SelectionBuffer, um) =
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
proc setWall*(map; loc: Location, dir: CardinalDir, w: Wall, um) =
  singleCellAction(map, loc, um, "Set wall", m):
    alias(l, m.levels[loc.level])
    l.setWall(loc.row, loc.col, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(map; loc: Location, f: Floor, um) =
  singleCellAction(map, loc, um, "Set floor", m):
    alias(l, m.levels[loc.level])
    l.setFloor(loc.row, loc.col, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(map; loc: Location, f: Floor, ot: Orientation, um) =
  singleCellAction(map, loc, um, "Set oriented floor", m):
    alias(l, m.levels[loc.level])
    l.setFloor(loc.row, loc.col, f)
    l.setFloorOrientation(loc.row, loc.col, ot)

# }}}
# {{{ excavate*()
proc excavate*(map; loc: Location, um) =
  singleCellAction(map, loc, um, "Excavate", m):
    alias(l, m.levels[loc.level])
    alias(c, loc.col)
    alias(r, loc.row)

    l.eraseCell(r,c)
    l.setFloor(r,c, fEmpty)

    if r == 0 or l.getFloor(r-1, c) == fNone:
      l.setWall(r,c, dirN, wWall)
    else:
      l.setWall(r,c, dirN, wNone)

    if c == 0 or l.getFloor(r, c-1) == fNone:
      l.setWall(r,c, dirW, wWall)
    else:
      l.setWall(r,c, dirW, wNone)

    if r == l.rows-1 or l.getFloor(r+1, c) == fNone:
      l.setWall(r,c, dirS, wWall)
    else:
      l.setWall(r,c, dirS, wNone)

    if c == l.cols-1 or l.getFloor(r, c+1) == fNone:
      l.setWall(r,c, dirE, wWall)
    else:
      l.setWall(r,c, dirE, wNone)

# }}}
# {{{ toggleFloorOrientation*()
proc toggleFloorOrientation*(map; loc: Location, um) =
  singleCellAction(map, loc, um, "Toggle floor orientation", m):
    alias(l, m.levels[loc.level])
    alias(c, loc.col)
    alias(r, loc.row)

    let newOt = if l.getFloorOrientation(r,c) == Horiz: Vert else: Horiz
    l.setFloorOrientation(r,c, newOt)

# }}}
# {{{ setNote*()
proc setNote*(map; loc: Location, n: Note, um) =
  singleCellAction(map, loc, um, "Set note", m):
    alias(l, m.levels[loc.level])
    l.setNote(loc.row, loc.col, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(map; loc: Location, um) =
  singleCellAction(map, loc, um, "Erase note", m):
    alias(l, m.levels[loc.level])
    l.delNote(loc.row, loc.col)

# }}}
# {{{ resizeLevel*()
proc resizeLevel*(map; level, newRows, newCols: Natural, align: Direction, um) =
  fullLevelAction(map, level, um, "Resize level", m):
    alias(l, m.levels[level])
    l = l.resize(newRows, newCols, align)

# }}}
# {{{ cropLevel*()
proc cropLevel*(map; level: Natural, rect: Rect[Natural], um) =
  fullLevelAction(map, level, um, "Crop level", m):
    m.levels[level] = newLevelFrom(m.levels[level], rect)

# }}}
# {{{ nudgeLevel*()
proc nudgeLevel*(map; level, destRow, destCol: int, cb: SelectionBuffer, um) =
  # The level is cleared for the duration of the nudge operation and it is
  # stored temporarily in the SelectionBuffer
  let action = proc (m: var Map) =
    var l = newLevel(cb.level.name, cb.level.level,
                     cb.level.rows, cb.level.cols)
    l.paste(destRow, destCol, cb.level, cb.selection)
    m.levels[level] = l

  var undoLevel = newLevelFrom(cb.level)
  var undoAction = proc (m: var Map) =
    m.levels[level] = undoLevel

  um.storeUndoState("Nudge level", action, undoAction)
  action(map)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
