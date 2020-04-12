import options

import common
import level
import rect
import selection
import undomanager


using
  l: var Level
  currLevel: var Level
  um: var UndoManager[Level]

# {{{ fullLevelAction()
template fullLevelAction(currLevel; um;
                         actionName: string, actionLevel, actionBody: untyped) =
  let action = proc (actionLevel: var Level) =
    actionBody

  var undoLevel = newLevelFrom(currLevel)
  var undoAction = proc (l: var Level) =
    l = undoLevel

  um.storeUndoState(actionName, action, undoAction)
  action(currLevel)

# }}}
# {{{ cellAreaAction()
template cellAreaAction(currLevel; rect: Rect[Natural], um;
                        actionName: string, actionLevel, actionBody: untyped) =
  let action = proc (actionLevel: var Level) =
    actionBody
    actionLevel.reindexNotes()

  var undoLevel = newLevelFrom(currLevel, rect)
  var undoAction = proc (l: var Level) =
    l.copyFrom(destRow=rect.r1, destCol=rect.c1,
               src=undoLevel, srcRect=rectN(0, 0, rect.rows, rect.cols))
    l.reindexNotes()

  um.storeUndoState(actionName, action, undoAction)
  action(currLevel)

# }}}
# {{{ singleCellAction()
template singleCellAction(currLevel; r,c: Natural, um;
                          actionName: string, actionLevel, actionBody: untyped) =
  cellAreaAction(currLevel, rectN(r, c, r+1, c+1), um,
                 actionName, actionLevel, actionBody)

# }}}

# {{{ eraseCellWalls*()
proc eraseCellWalls*(currLevel; r,c: Natural, um) =
  singleCellAction(currLevel, r,c, um, "Erase cell walls", l):
    l.eraseCellWalls(r,c)

# }}}
# {{{ eraseCell*()
proc eraseCell*(currLevel; r,c: Natural, um) =
  singleCellAction(currLevel, r,c, um, "Erase cell", l):
    l.eraseCell(r,c)

# }}}
# {{{ eraseSelection*()
proc eraseSelection*(currLevel; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currLevel, bbox, um, "Erase selection", l):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          l.eraseCell(row, col)

# }}}
# {{{ fillSelection*()
proc fillSelection*(currLevel; sel: Selection, bbox: Rect[Natural], um) =
  cellAreaAction(currLevel, bbox, um, "Fill selection", l):
    for r in 0..<sel.rows:
      for c in 0..<sel.cols:
        if sel[r,c]:
          let row = bbox.r1+r
          let col = bbox.c1+c
          l.eraseCell(row, col)
          l.setFloor(row, col, fEmpty)

# }}}
# {{{ surroundSelection*()
proc surroundSelectionWithWalls*(currLevel; sel: Selection, bbox: Rect[Natural],
                                 um) =
  cellAreaAction(currLevel, bbox, um, "Surround selection with walls", l):
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
proc paste*(currLevel; destRow, destCol: Natural, cb: SelectionBuffer, um) =
  let rect = rectN(
    destRow,
    destCol,
    destRow + cb.level.rows,
    destCol + cb.level.cols
  ).intersect(
    rectN(0, 0, currLevel.rows, currLevel.cols)
  )
  if rect.isSome:
    cellAreaAction(currLevel, rect.get, um, "Paste buffer", l):
      l.paste(destRow, destCol, cb.level, cb.selection)

# }}}
# {{{ setWall*()
proc setWall*(currLevel; r,c: Natural, dir: CardinalDir, w: Wall, um) =
  singleCellAction(currLevel, r,c, um, "Set wall", l):
    l.setWall(r,c, dir, w)

# }}}
# {{{ setFloor*()
proc setFloor*(currLevel; r,c: Natural, f: Floor, um) =
  singleCellAction(currLevel, r,c, um, "Set floor", l):
    l.setFloor(r,c, f)

# }}}
# {{{ setOrientedFloor*()
proc setOrientedFloor*(currLevel; r,c: Natural, f: Floor, ot: Orientation, um) =
  singleCellAction(currLevel, r,c, um, "Set oriented floor", l):
    l.setFloor(r,c, f)
    l.setFloorOrientation(r,c, ot)

# }}}
# {{{ excavate*()
proc excavate*(currLevel; r,c: Natural, um) =
  singleCellAction(currLevel, r,c, um, "Excavate", l):
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
proc toggleFloorOrientation*(currLevel; r,c: Natural, um) =
  singleCellAction(currLevel, r,c, um, "Toggle floor orientation", l):
    let newOt = if l.getFloorOrientation(r,c) == Horiz: Vert else: Horiz
    l.setFloorOrientation(r,c, newOt)

# }}}
# {{{ setNote*()
proc setNote*(currLevel; r,c: Natural, n: Note, um) =
  singleCellAction(currLevel, r,c, um, "Set note", l):
    l.setNote(r,c, n)

# }}}
# {{{ eraseNote*()
proc eraseNote*(currLevel; r,c: Natural, um) =
  singleCellAction(currLevel, r,c, um, "Erase note", l):
    l.delNote(r,c)

# }}}
# {{{ resizeLevel*()
proc resizeLevel*(currLevel; newRows, newCols: Natural, align: Direction, um) =
  fullLevelAction(currLevel, um, "Resize level", l):
    l = l.resize(newRows, newCols, align)

# }}}
# {{{ cropLevel*()
proc cropLevel*(currLevel; rect: Rect[Natural], um) =
  fullLevelAction(currLevel, um, "Crop level", l):
    l = newLevelFrom(l, rect)

# }}}
# {{{ nudgeLevel*()
proc nudgeLevel*(currLevel; destRow, destCol: int, cb: SelectionBuffer, um) =
  # The level is cleared for the duration of the nudge operation and it is
  # stored temporarily in the SelectionBuffer
  let action = proc (l: var Level) =
    l = newLevel(l.name, l.level, l.rows, l.cols)
    l.paste(destRow, destCol, cb.level, cb.selection)

  var undoLevel = newLevelFrom(cb.level)
  var undoAction = proc (l: var Level) =
    l = undoLevel

  um.storeUndoState("Nudge level", action, undoAction)
  action(currLevel)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
