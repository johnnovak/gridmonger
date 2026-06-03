import std/lenientops
import std/options

import koi
import nanovg

import appcontext
import common
import constants
import cursor
import dialogs/all
import domain/all
import ui/all
import utils/all
import view
import views/currentnote
import views/levelview
import views/noteslist
import views/quickref
import views/statusbar
import views/themepanel
import views/tools


using a: var AppContext

# {{{ calculateLevelDrawArea()
proc calculateLevelDrawArea(a): tuple[w, h: float] =
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

# {{{ renderDialogs*()
proc renderDialogs*(a) =
  alias(dlg, a.dialogs)

  case dlg.activeDialog:
  of dlgNone: discard

  of dlgAbout:
    aboutDialog(dlg.about, a)

  of dlgPreferences:
    preferencesDialog(dlg.preferences, a)

  of dlgSaveDiscardMap:
    saveDiscardMapDialog(dlg.saveDiscardMap, a)

  of dlgNewMap:
    newMapDialog(dlg.newMap, a)

  of dlgEditMapProps:
    editMapPropsDialog(dlg.editMapProps, a)

  of dlgNewLevel:
    newLevelDialog(dlg.newLevel, a)

  of dlgDeleteLevel:
    deleteLevelDialog(a)

  of dlgEditLevelProps:
    editLevelPropsDialog(dlg.editLevelProps, a)

  of dlgEditNote:
    editNoteDialog(dlg.editNote, a)

  of dlgEditLabel:
    editLabelDialog(dlg.editLabel, a)

  of dlgResizeLevel:
    resizeLevelDialog(dlg.resizeLevel, a)

  of dlgEditRegionProps:
    editRegionPropsDialog(dlg.editRegionProps, a)

  of dlgSaveDiscardTheme:
    saveDiscardThemeDialog(dlg.saveDiscardTheme, a)

  of dlgCopyTheme:
    copyThemeDialog(dlg.copyTheme, a)

  of dlgRenameTheme:
    renameThemeDialog(dlg.renameTheme, a)

  of dlgOverwriteTheme:
    overwriteThemeDialog(dlg.overwriteTheme, a)

  of dlgDeleteTheme:
    deleteThemeDialog(a)

# }}}
# {{{ renderUI*()
proc renderUI*(a) =
  alias(ui, a.ui)
  alias(vg, a.vg)
  alias(map, a.doc.map)

  let
    mainPane = mainPaneRect(a)
    toolsPaneHeight = toolsPaneHeight(mainPane.h)

  # Clear background
  vg.beginPath

  # Make sure the background image extends to the notes list pane if open
  vg.rect(0, mainPane.y1, mainPane.w + mainPane.x1, mainPane.h)

  if ui.backgroundImage.isSome:
    vg.fillPaint(ui.backgroundImage.get)
  else:
    vg.fillColor(a.theme.windowTheme.backgroundColor)

  vg.fill

  if a.ui.showQuickReference:
    var w = koi.winWidth()
    if a.layout.showThemeEditor: w -= ThemePaneWidth

    renderQuickReference(x=0, y=mainPane.y1, w=w, h=mainPane.h, a)

  else:
    if not map.hasLevels:
      renderEmptyMap(a)

    else:
      koi.beginView(x=mainPane.x1, y=mainPane.y1, w=mainPane.w, h=mainPane.h)

      # About button
      if button(x=mainPane.w-55.0, y=19.0, w=20.0, h=DlgItemHeight,
                IconQuestion, style=a.theme.aboutButtonStyle, tooltip="About"):
        openAboutDialog(a)

      renderLevelDropdown(a)

      if currLevel(a).regionOpts.enabled:
        renderRegionDropDown(a)

      let (levelDrawWidth, levelDrawHeight) = calculateLevelDrawArea(a)
      updateViewAndCursorPos(levelDrawWidth, levelDrawHeight, a)
      updateLastCursorViewCoords(a)

      alias(dp, ui.drawLevelParams)

      renderLevel(
        x = dp.startX,
        y = dp.startY,
        w = dp.viewCols * dp.gridSize,
        h = dp.viewRows * dp.gridSize,
        levelDrawWidth  = levelDrawWidth,
        levelDrawHeight = levelDrawHeight,
        a
      )

      renderModeAndOptionIndicators(
        x = mainPane.x1 + LevelLeftPad_NoCoords,
        y = a.win.titleBarHeight + 32,
        a
      )

      if a.layout.showToolsPane:
        renderToolsPane(
          x = mainPane.w - toolsPaneWidth(a),
          y = ToolsPaneTopPad,
          w = toolsPaneWidth(a),
          h = toolsPaneHeight,
          a
        )

      koi.endView()


    if map.hasLevels:
      if a.layout.showCurrentNotePane:
        var paneWidth = mainPane.w - CurrentNotePaneLeftPad -
                                     CurrentNotePaneRightPad

        let totalNotePaneHeight = CurrentNotePaneHeight +
                                  CurrentNotePaneTopPad +
                                  CurrentNotePaneBottomPad

        if mainPane.h - toolsPaneHeight - ToolsPaneTopPad <
           totalNotePaneHeight - 30:
          paneWidth -= toolsPaneWidth(a)

        renderCurrentNotePane(
          x = mainPane.x1 + CurrentNotePaneLeftPad,
          y = mainPane.y2 - CurrentNotePaneHeight - CurrentNotePaneBottomPad,
          w = paneWidth,
          h = CurrentNotePaneHeight,
          a
        )

      if a.layout.showNotesListPane:
        renderNotesListPane(x = 0, y = mainPane.y1,
                            w = NotesListPaneWidth,
                            h = mainPane.h, a)

  # Status bar
  let statusBarY = mainPane.y1 + mainPane.h
  renderStatusBar(0, statusBarY, koi.winWidth(), StatusBarHeight, a)

  # Theme editor pane
  # XXX hack, we need to render the theme editor before the dialogs, so
  # that keyboard shortcuts in the the theme editor take precedence (e.g.
  # when pressing ESC to close the colorpicker, the dialog should not close)
  if a.layout.showThemeEditor:
    let
      mainPane = mainPaneRect(a)
      x = mainPane.x1 + mainPane.w
      y = mainPane.y1
      w = ThemePaneWidth
      h = mainPane.h

    renderThemeEditorPane(x, y, w, h, a)

  renderDialogs(a)

  a.ui.prevCursor = a.ui.cursor

# }}}

# vim: et:ts=2:sw=2:fdm=marker
