# cursor
#
# Cursor and view-scroll movement. setCursor / stepCursor (with wraparound),
# moveCursor / moveCursorDiagonal / moveCursorTo, centerCursorAt,
# locationAtMouse, stepLevelView / moveLevelView, plus reset / update
# helpers. Mutates AppContext.ui.cursor, drawLevelParams, drawTrail,
# prevMoveDir, prevCursorViewXY.
# Side effects: AppContext field mutation; drawTrail action triggers a domain
# write via actions.drawTrail.

import std/math               # floorMod
import std/options
import std/tables

import with                  # `with` macro

import actions               # drawTrail
import common
import domain/all
import koi                   # mx, my
import main/appcontext
import main/constants        # ScrollMargin
import main/view             # viewRow, viewCol, currLevel
import ui/all
import utils/all


using a: var AppContext


# {{{ setCursor()
proc setCursor*(newCur: Location; a) =
  with a:
    if not doc.map.hasLevels:
      return

    if newCur.levelId != ui.cursor.levelId:
      ui.drawTrail = false

    if ui.drawTrail and newCur != ui.cursor:
      actions.drawTrail(doc.map, loc=newCur, undoLoc=ui.prevCursor,
                        doc.undoManager)

    let l = doc.map.levels[newCur.levelId]

    ui.cursor = Location(
      levelId: newCur.levelId,
      row: newCur.row.clamp(0, l.rows - 1),
      col: newCur.col.clamp(0, l.cols - 1)
    )

# }}}
# {{{ stepCursor()
proc moveCursorTo*(loc: Location; a)

proc stepCursor*(cur: Location, dir: CardinalDir, steps: Natural; a): Location =
  if not a.doc.map.hasLevels:
    return

  alias(dp, a.ui.drawLevelParams)

  let l = a.doc.map.levels[cur.levelId]
  let sm = ScrollMargin
  var cur = cur

  let wraparound = a.prefs.movementWraparound

  template stepInc(curPos: Natural, maxPos: Natural) =
    let newPos = curPos + steps
    if newPos > maxPos and wraparound:
      if steps > 1: a.ui.drawTrail = false
      curPos = newPos.floorMod(maxPos + 1)
      moveCursorTo(cur, a)
    else:
      curPos = newPos.clampMax(maxPos)

  template stepDec(curPos: Natural, maxPos: Natural) =
    let newPos = curPos - steps
    let minPos = 0
    if newPos < minPos and wraparound:
      if steps > 1: a.ui.drawTrail = false
      curPos = newPos.floorMod(maxPos + 1)
      moveCursorTo(cur, a)
    else:
      curPos = max(minPos, newPos)

  case dir:
  of dirE:
    stepInc(cur.col, maxPos=(l.cols - 1))

    let viewCol = viewCol(cur.col, a)
    let viewColMax = dp.viewCols-1 - sm
    if viewCol > viewColMax:
      dp.viewStartCol = (l.cols - dp.viewCols).clamp(0, dp.viewStartCol +
                                                        (viewCol - viewColMax))
  of dirS:
    stepInc(cur.row, maxPos=(l.rows - 1))

    let viewRow = viewRow(cur.row, a)
    let viewRowMax = dp.viewRows-1 - sm
    if viewRow > viewRowMax:
      dp.viewStartRow = (l.rows - dp.viewRows).clamp(0, dp.viewStartRow +
                                                        (viewRow - viewRowMax))

  of dirW:
    stepDec(cur.col, maxPos=(l.cols - 1))

    let viewCol = viewCol(cur.col, a)
    if viewCol < sm:
      dp.viewStartCol = (dp.viewStartCol - (sm - viewCol)).clampMin(0)

  of dirN:
    stepDec(cur.row, maxPos=(l.rows - 1))

    let viewRow = viewRow(cur.row, a)
    if viewRow < sm:
      dp.viewStartRow = (dp.viewStartRow - (sm - viewRow)).clampMin(0)

  result = cur

# }}}
# {{{ moveCursor()
proc moveCursor*(dir: CardinalDir, steps: Natural = 1; a) =
  let cur = stepCursor(a.ui.cursor, dir, steps, a)
  if cur != a.ui.cursor:
    if steps > 1:
      a.ui.drawTrail = false
    a.ui.prevMoveDir = dir.some
    setCursor(cur, a)

# }}}
# {{{ moveCursorDiagonal()
proc moveCursorDiagonal*(dir: Direction, steps: Natural = 1; a) =
  assert dir in @[NorthWest, NorthEast, SouthWest, SouthEast]

  let l = currLevel(a)

  var cur = a.ui.cursor
  for i in 0..<steps:
    if not a.prefs.movementWraparound:
      if (dirN in dir and cur.row == 0)        or
         (dirS in dir and cur.row == l.rows-1) or
         (dirW in dir and cur.col == 0)        or
         (dirE in dir and cur.col == l.cols-1):
        return

    for d in dir:
      cur = stepCursor(cur, d, steps=1, a)

  setCursor(cur, a)

# }}}
# {{{ moveCursorTo()
proc moveCursorTo*(loc: Location; a) =
  var cur = a.ui.cursor
  cur.levelId = loc.levelId

  let dx = loc.col - cur.col
  let dy = loc.row - cur.row

  cur = if   dx < 0: stepCursor(cur, dirW, -dx, a)
        elif dx > 0: stepCursor(cur, dirE,  dx, a)
        else: cur

  cur = if   dy < 0: stepCursor(cur, dirN, -dy, a)
        elif dy > 0: stepCursor(cur, dirS,  dy, a)
        else: cur

  setCursor(cur, a)

# }}}
# {{{ centerCursorAt()
proc centerCursorAt*(loc: Location; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)

  dp.viewStartRow = (loc.row.int - dp.viewRows div 2).clamp(0, l.rows-1)
  dp.viewStartCol = (loc.col.int - dp.viewCols div 2).clamp(0, l.cols-1)

  moveCursorTo(loc, a)

# }}}
# {{{ locationAtMouse()
proc locationAtMouse*(clampToBounds=false, a): Option[Location] =
  alias(dp, a.ui.drawLevelParams)

  let
    mouseViewRow = ((koi.my() - dp.startY) / dp.gridSize).int
    mouseViewCol = ((koi.mx() - dp.startX) / dp.gridSize).int

    mouseRow = dp.viewStartRow + mouseViewRow
    mouseCol = dp.viewStartCol + mouseViewCol

  if clampToBounds:
    result = Location(
      levelId: a.ui.cursor.levelId,
      row: mouseRow.clamp(dp.viewStartRow, dp.viewStartRow + dp.viewRows-1),
      col: mouseCol.clamp(dp.viewStartCol, dp.viewStartCol + dp.viewCols-1)
    ).some

  else:
    if mouseViewRow >= 0 and mouseRow < dp.viewStartRow + dp.viewRows and
       mouseViewCol >= 0 and mouseCol < dp.viewStartCol + dp.viewCols:

      result = Location(
        levelId: a.ui.cursor.levelId,
        row: mouseRow,
        col: mouseCol
      ).some
    else:
      result = Location.none

# }}}
# {{{ stepLevelView()
proc stepLevelView*(dir: CardinalDir; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)
  let maxViewStartRow = (l.rows - dp.viewRows).clampMin(0)
  let maxViewStartCol = (l.cols - dp.viewCols).clampMin(0)

  var newViewStartCol = dp.viewStartCol
  var newViewStartRow = dp.viewStartRow

  case dir:
  of dirE: newViewStartCol = (dp.viewStartCol + 1).clampMax(maxViewStartCol)
  of dirW: newViewStartCol = (dp.viewStartCol - 1).clampMin(0)
  of dirS: newViewStartRow = (dp.viewStartRow + 1).clampMax(maxViewStartRow)
  of dirN: newViewStartRow = (dp.viewStartRow - 1).clampMin(0)

  var cur = a.ui.cursor
  cur.row = cur.row + viewRow(newViewStartRow, a)
  cur.col = cur.col + viewCol(newViewStartCol, a)
  setCursor(cur, a)

  dp.viewStartRow = newViewStartRow
  dp.viewStartCol = newViewStartCol

# }}}
# {{{ moveLevelView()
proc moveLevelView*(dir: Direction, steps: Natural = 1; a) =
  alias(dp, a.ui.drawLevelParams)

  a.ui.drawTrail = false

  let l = currLevel(a)
  let maxViewStartRow = (l.rows - dp.viewRows).clampMin(0)
  let maxViewStartCol = (l.cols - dp.viewCols).clampMin(0)

  for i in 0..<steps:
    if (dirN in dir and dp.viewStartRow == 0) or
       (dirS in dir and dp.viewStartRow == maxViewStartRow) or
       (dirW in dir and dp.viewStartCol == 0) or
       (dirE in dir and dp.viewStartCol == maxViewStartCol):
      return

    for d in dir:
      stepLevelView(d, a)

# }}}

# {{{ resetCursorAndViewStart()
proc resetCursorAndViewStart*(a) =
  with a.ui.cursor:
    levelId = 0
    row     = 0
    col     = 0

  with a.ui.drawLevelParams:
    viewStartRow = 0
    viewStartCol = 0

# }}}
# {{{ updateLastCursorViewCoords()
proc updateLastCursorViewCoords*(a) =
  alias(dp, a.ui.drawLevelParams)

  a.ui.prevCursorViewX = dp.gridSize * viewCol(a)
  a.ui.prevCursorViewY = dp.gridSize * viewRow(a)

# }}}
# {{{ updateViewAndCursorPos()
proc updateViewAndCursorPos*(levelDrawWidth, levelDrawHeight: float; a) =
  alias(dp, a.ui.drawLevelParams)

  let l = currLevel(a)

  dp.viewRows = dp.numDisplayableRows(levelDrawHeight).clampMax(l.rows)
  dp.viewCols = dp.numDisplayableCols(levelDrawWidth).clampMax(l.cols)

  let maxViewStartRow = (l.rows - dp.viewRows).clampMin(0)
  let maxViewStartCol = (l.cols - dp.viewCols).clampMin(0)

  if maxViewStartRow < dp.viewStartRow:
    dp.viewStartRow = maxViewStartRow

  if maxViewStartCol < dp.viewStartCol:
    dp.viewStartCol = maxViewStartCol

  let viewEndRow = dp.viewStartRow + dp.viewRows - 1
  let viewEndCol = dp.viewStartCol + dp.viewCols - 1

  let cur = a.ui.cursor
  let newCur = Location(
    levelId: cur.levelId,
    col:     viewEndCol.clamp(dp.viewStartCol, cur.col),
    row:     viewEndRow.clamp(dp.viewStartRow, cur.row)
  )

  if newCur != cur:
    setCursor(newCur, a)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
