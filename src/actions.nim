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
    m.copyFrom(destRow=rect.r1, destCol=rect.c1,
               src=undoMap, srcRect=rectN(0, 0, rect.height, rect.width))

  um.storeUndoState(undoAction, redoAction=action)
  action(currMap)

# }}}
# {{{ singleCellAction()
template singleCellAction(currMap; r,c: Natural, um;
                          actionMap, actionBody: untyped) =
  cellAreaAction(currMap, rectN(r, c, r+1, c+1), um, actionMap, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, m):
    m.eraseCellWalls(r,c)

# }}}
# {{{ eraseCell*()
proc eraseCell*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, m):
    m.eraseCell(r,c)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, m):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          m.eraseCell(bbox.r1 + r, bbox.c1 + c)

# }}}
# {{{ paste*()
proc paste*(currMap; destRow, destCol: Natural, cb: CopyBuffer, um) =
  let rect = rectN(
    destRow,
    destCol,
    destRow + cb.map.rows,
    destCol + cb.map.cols
  ).intersect(
    rectN(0, 0, currMap.rows, currMap.cols)
  )
  if rect.isSome:
    cellAreaAction(currMap, rect.get, um, m):
      m.paste(destRow, destCol, cb.map, cb.selection)

# }}}
# {{{ setWall*()
proc setWall*(currMap; r,c: Natural, dir: CardinalDir, w: Wall, um) =
  singleCellAction(currMap, r,c, um, m):
    m.setWall(r,c, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(currMap; r,c: Natural, f: Floor, um) =
  singleCellAction(currMap, r,c, um, m):
    m.setFloor(r,c, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(currMap; r,c: Natural, f: Floor, ot: Orientation, um) =
  singleCellAction(currMap, r,c, um, m):
    m.setFloor(r,c, f)
    m.setFloorOrientation(r,c, ot)

# }}}
# {{{ excavate*()
proc excavate*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, m):
    if m.getFloor(r,c) == fNone:
      m.setFloor(r,c, fEmpty)

    if r == 0 or m.getFloor(r-1, c) == fNone:
      m.setWall(r,c, dirN, wWall)
    else:
      m.setWall(r,c, dirN, wNone)

    if c == 0 or m.getFloor(r, c-1) == fNone:
      m.setWall(r,c, dirW, wWall)
    else:
      m.setWall(r,c, dirW, wNone)

    if r == m.rows-1 or m.getFloor(r+1, c) == fNone:
      m.setWall(r,c, dirS, wWall)
    else:
      m.setWall(r,c, dirS, wNone)

    if c == m.cols-1 or m.getFloor(r, c+1) == fNone:
      m.setWall(r,c, dirE, wWall)
    else:
      m.setWall(r,c, dirE, wNone)

# }}}
# {{{ toggleFloorOrientation*()
# TODO unnecessary, remove
proc toggleFloorOrientation*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, m):
    let newOt = if m.getFloorOrientation(r,c) == Horiz: Vert else: Horiz
    m.setFloorOrientation(r,c, newOt)

# }}}
# }}}

# vim: et:ts=2:sw=2:fdm=marker
