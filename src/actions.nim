import options

import common
import map
import selection
import undomanager


using
  m: var Map
  currMap: var Map
  um: var UndoManager[Map]

# {{{ fullMapAction()
template fullMapAction(currMap; um;
                       actionName: string, actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody

  var undoMap = newMapFrom(currMap)
  var undoAction = proc (m: var Map) =
    m = undoMap

  um.storeUndoState(actionName, action, undoAction)
  action(currMap)

# }}}
# {{{ cellAreaAction()
template cellAreaAction(currMap; rect: Rect[Natural], um;
                        actionName: string, actionMap, actionBody: untyped) =
  let action = proc (actionMap: var Map) =
    actionBody
    actionMap.reindexNotes()

  var undoMap = newMapFrom(currMap, rect)
  var undoAction = proc (m: var Map) =
    m.copyFrom(destRow=rect.r1, destCol=rect.c1,
               src=undoMap, srcRect=rectN(0, 0, rect.rows, rect.cols))
    m.reindexNotes()

  um.storeUndoState(actionName, action, undoAction)
  action(currMap)

# }}}
# {{{ singleCellAction()
template singleCellAction(currMap; r,c: Natural, um;
                          actionName: string, actionMap, actionBody: untyped) =
  cellAreaAction(currMap, rectN(r, c, r+1, c+1), um,
                 actionName, actionMap, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, "Erase cell walls", m):
    m.eraseCellWalls(r,c)

# }}}
# {{{ eraseCell*()
proc eraseCell*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, "Erase cell", m):
    m.eraseCell(r,c)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, "Erase selection", m):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          m.eraseCell(row, col)

# }}}
# {{{ fillSelection*()
proc fillSelection*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, "Fill selection", m):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          m.eraseCell(row, col)
          m.setFloor(row, col, fEmpty)

# }}}
# {{{ surroundSelection*()
proc surroundSelection*(currMap; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currMap, bbox, um, "Surround selection with walls", m):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c

          proc setWall(m: var Map, dir: CardinalDir) =
            if m.canSetWall(row, col, dir):
              m.setWall(row, col, dir, wWall)

          if sel.isNeighbourCellEmpty(r,c, dirN): m.setWall(dirN)
          if sel.isNeighbourCellEmpty(r,c, dirE): m.setWall(dirE)
          if sel.isNeighbourCellEmpty(r,c, dirS): m.setWall(dirS)
          if sel.isNeighbourCellEmpty(r,c, dirW): m.setWall(dirW)

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
    cellAreaAction(currMap, rect.get, um, "Paste buffer", m):
      m.paste(destRow, destCol, cb.map, cb.selection)

# }}}
# {{{ setWall*()
proc setWall*(currMap; r,c: Natural, dir: CardinalDir, w: Wall, um) =
  singleCellAction(currMap, r,c, um, "Set wall", m):
    m.setWall(r,c, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(currMap; r,c: Natural, f: Floor, um) =
  singleCellAction(currMap, r,c, um, "Set floor", m):
    m.setFloor(r,c, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(currMap; r,c: Natural, f: Floor, ot: Orientation, um) =
  singleCellAction(currMap, r,c, um, "Set oriented floor", m):
    m.setFloor(r,c, f)
    m.setFloorOrientation(r,c, ot)

# }}}
# {{{ excavate*()
proc excavate*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, "Excavate", m):
    m.eraseCell(r,c)
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
proc toggleFloorOrientation*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, "Toggle floor orientation", m):
    let newOt = if m.getFloorOrientation(r,c) == Horiz: Vert else: Horiz
    m.setFloorOrientation(r,c, newOt)

# }}}
# {{{ setNote*()
proc setNote*(currMap; r,c: Natural, n: Note, um) =
  singleCellAction(currMap, r,c, um, "Set note", m):
    m.setNote(r,c, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(currMap; r,c: Natural, um) =
  singleCellAction(currMap, r,c, um, "Erase note", m):
    m.delNote(r,c)

# }}}
# {{{ resizeMap*()
proc resizeMap*(currMap; newRows, newCols: Natural, align: Direction, um) =
  fullMapAction(currMap, um, "Resize map", m):
    m = m.resize(newRows, newCols, align)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
