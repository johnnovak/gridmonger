import std/options
import std/tables

import with

import common
import domain/all
import koi
import main/appcontext
import main/constants
import ui/all
import utils/all


using a: var AppContext

# {{{ resetManualNoteTooltip*()
proc resetManualNoteTooltip*(a) =
  with a.ui.manualNoteTooltipState:
    show = false
    mx = -1
    my = -1

# }}}
# {{{ viewRow*()
func viewRow*(row: Natural; a): int =
  row - a.ui.drawLevelParams.viewStartRow

func viewRow*(a): int =
  viewRow(a.ui.cursor.row, a)

# }}}
# {{{ viewCol*()
proc viewCol*(col: Natural; a): int =
  col - a.ui.drawLevelParams.viewStartCol

func viewCol*(a): int =
  viewCol(a.ui.cursor.col, a)

# }}}
# {{{ currLevel*()
func currLevel*(a): Level =
  a.doc.map.levels[a.ui.cursor.levelId]

# }}}
# {{{ currRegion*()
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

# {{{ mainPaneRect*()
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
# {{{ toolsPaneWidth*()
proc toolsPaneWidth*(a): float =
  let mainPane = mainPaneRect(a)
  if a.layout.showToolsPane:
    if mainPane.h < ToolsPaneYBreakpoint2: ToolsPaneWidthWide
    else: ToolsPaneWidthNarrow
  else:
    0.0

# }}}
# {{{ toolsPaneHeight*()
proc toolsPaneHeight*(mainPaneHeight: float): float =
  if   mainPaneHeight < ToolsPaneYBreakpoint1: 420.0
  elif mainPaneHeight < ToolsPaneYBreakpoint2: 630.0
  else:                                        780.0

# }}}

# vim: et:ts=2:sw=2:fdm=marker
