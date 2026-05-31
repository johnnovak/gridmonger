# view
#
# Read-only view accessors (currLevel, currRegion, coordOptsForCurrLevel)
# and pane/draw-area dimension calculations (mainPaneRect, toolsPane*,
# calculateLevelDrawArea). Pure mutation of one DrawLevelParams field
# inside calculateLevelDrawArea is the only side effect.
# Side effects: minor AppContext field mutation (start XY in drawLevelParams).

import std/options
import std/tables

import common
import domain/map           # getRegionCoords, coordOptsForLevel, hasLevels, Level type via transitive
import domain/regions       # Region, []*
import koi                  # winWidth, winHeight
import main/appcontext
import main/constants       # NotesListPaneWidth, ThemePaneWidth, StatusBarHeight, ToolsPane*, Level{Top,Right,Bottom,Left}Pad*, CurrentNotePane*
import ui/csdwindow         # titleBarHeight
import utils/converters     # int↔float for clampMin
import utils/misc           # alias, clampMin
import utils/rect           # Rect, coordRect


using a: var AppContext


# {{{ viewRow()
func viewRow*(row: Natural; a): int =
  row - a.ui.drawLevelParams.viewStartRow

func viewRow*(a): int =
  viewRow(a.ui.cursor.row, a)

# }}}
# {{{ viewCol()
proc viewCol*(col: Natural; a): int =
  col - a.ui.drawLevelParams.viewStartCol

func viewCol*(a): int =
  viewCol(a.ui.cursor.col, a)

# }}}
# {{{ currLevel()
func currLevel*(a): Level =
  a.doc.map.levels[a.ui.cursor.levelId]

# }}}
# {{{ currRegion()
func currRegion*(a): Option[Region] =
  let l = currLevel(a)
  if l.regionOpts.enabled:
    let rc = a.doc.map.getRegionCoords(a.ui.cursor)
    l.regions[rc]
  else:
    Region.none

# }}}
# {{{ coordOptsForCurrLevel()
func coordOptsForCurrLevel*(a): CoordinateOptions =
  a.doc.map.coordOptsForLevel(a.ui.cursor.levelId)

# }}}

# {{{ mainPaneRect()
proc mainPaneRect*(a): Rect[int] =
  var
    x1 = 0
    x2 = koi.winWidth()

  if a.layout.showThemeEditor:
    x2 -= ThemePaneWidth

  if a.doc.map.hasLevels and a.layout.showNotesListPane:
    x1 += NotesListPaneWidth.int

  let
    y1 = a.win.titleBarHeight
    y2 = koi.winHeight() - StatusBarHeight

  coordRect(x1.int, y1.int, x2.clampMin(x1+1).int, y2.clampMin(y1+1).int)

# }}}
# {{{ toolsPaneWidth()
proc toolsPaneWidth*(a): float =
  let mainPane = mainPaneRect(a)
  if a.layout.showToolsPane:
    if mainPane.h < ToolsPaneYBreakpoint2: ToolsPaneWidthWide
    else: ToolsPaneWidthNarrow
  else:
    0.0

# }}}
# {{{ toolsPaneHeight()
proc toolsPaneHeight*(mainPaneHeight: float): float =
  if   mainPaneHeight < ToolsPaneYBreakpoint1: 420.0
  elif mainPaneHeight < ToolsPaneYBreakpoint2: 630.0
  else:                                        780.0

# }}}

# {{{ calculateLevelDrawArea()
proc calculateLevelDrawArea*(a): tuple[w, h: float] =
  alias(dp, a.ui.drawLevelParams)
  alias(ui, a.ui)

  let l = currLevel(a)

  var topPad, rightPad, bottomPad, leftPad: float

  if a.ui.showCellCoords:
    topPad    = LevelTopPad_Coords
    rightPad  = LevelRightPad_Coords
    bottomPad = LevelBottomPad_Coords
    leftPad   = LevelLeftPad_Coords
  else:
    topPad    = LevelTopPad_NoCoords
    rightPad  = LevelRightPad_NoCoords
    bottomPad = LevelBottomPad_NoCoords
    leftPad   = LevelLeftPad_NoCoords

  if l.regionOpts.enabled:
    topPad += LevelTopPad_Regions

  let mainPane = mainPaneRect(a)

  dp.startX = mainPane.x1 + leftPad
  dp.startY = mainPane.y1 + topPad

  var
    w = mainPane.w - leftPad - rightPad
    h = mainPane.h - topPad  - bottomPad

  if a.layout.showCurrentNotePane:
   h -= CurrentNotePaneTopPad + CurrentNotePaneHeight +
                                CurrentNotePaneBottomPad

  if a.layout.showToolsPane:
    w -= toolsPaneWidth(a)

  (w, h)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
