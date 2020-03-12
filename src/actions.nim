import options

import common
import map
import selection
import undomanager


using
  currMap: var Map
  um: var UndoManager[Map]

# {{{ Non-undoable actions
# }}}

# {{{ Undoable actions
# {{{ cellAreaAction()
template cellAreaAction(currMap; rect: Rect[Natural], um;
                        actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody

  var undoMap = newMapFrom(currMap, rect)
  var undoAction = proc (m: var Map) =
    m.copyFrom(destCol=rect.x1, destRow=rect.y1,
               undoMap, rectN(0, 0, rect.width, rect.height))

  um.storeUndoState(undoAction, redoAction=action)
  action(currMap)

# }}}
# {{{ singleCellAction()
template singleCellAction(currMap; c, r: Natural, um;
                          actionMap, actionBody: untyped) =
  cellAreaAction(currMap, rectN(c, r, c+1, r+1), um, actionMap, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(currMap; c, r: Natural, um) =
  singleCellAction(currMap, c, r, um, m):
    m.eraseCellWalls(c, r)

# }}}
# {{{ eraseCell*()
proc eraseCell*(currMap; c, r: Natural, um) =
  singleCellAction(currMap, c, r, um, m):
    m.eraseCell(c, r)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, m):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[c,r]:
          m.eraseCell(bbox.x1 + c, bbox.y1 + r)

# }}}
# {{{ paste*()
proc paste*(currMap; destCol, destRow: Natural, cb: CopyBuffer, um) =
  let rect = rectN(
    destCol,
    destRow,
    destCol + cb.map.cols,
    destRow + cb.map.rows
  ).intersect(
    rectN(0, 0, currMap.cols, currMap.rows)
  )
  if rect.isSome:
    cellAreaAction(currMap, rect.get, um, m):
      m.paste(destCol, destRow, cb.map, cb.selection)

# }}}
# {{{ setWall*()
proc setWall*(currMap; c, r: Natural, dir: Direction, w: Wall, um) =
  singleCellAction(currMap, c, r, um, m):
    m.setWall(c, r, dir, w)

# }}}
# {{{ setGround*()
proc setGround*(currMap; c, r: Natural, g: Ground, um) =
  singleCellAction(currMap, c, r, um, m):
    m.setGround(c, r, g)

# }}}
# {{{ excavate*()
proc excavate*(currMap; c, r: Natural, um) =
  singleCellAction(currMap, c, r, um, m):
    if m.getGround(c,r) == gNone:
      m.setGround(c,r, gEmpty)

    if r == 0 or m.getGround(c,r-1) == gNone:
      m.setWall(c,r, North, wWall)
    else:
      m.setWall(c,r, North, wNone)

    if c == 0 or m.getGround(c-1,r) == gNone:
      m.setWall(c,r, West, wWall)
    else:
      m.setWall(c,r, West, wNone)

    if r == m.rows-1 or m.getGround(c,r+1) == gNone:
      m.setWall(c,r, South, wWall)
    else:
      m.setWall(c,r, South, wNone)

    if c == m.cols-1 or m.getGround(c+1,r) == gNone:
      m.setWall(c,r, East, wWall)
    else:
      m.setWall(c,r, East, wNone)

# }}}
# {{{ toggleGroundOrientation*()
# TODO unnecessary
proc toggleGroundOrientation*(currMap; c, r: Natural, um) =
  singleCellAction(currMap, c, r, um, m):
    let newOt = if m.getGroundOrientation(c, r) == Horiz: Vert else: Horiz
    m.setGroundOrientation(c, r, newOt)

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
