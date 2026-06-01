# frame
#
# Top-level UI orchestrator. renderUI walks the visible layout — level view,
# pane panes, status bar, theme editor, dialog overlay — and dispatches to
# the per-pane render procs in main/views/. renderDialogs dispatches to the
# active dialog handler in main/dialogs.
# Side effects: koi + nanovg drawing calls.

import std/lenientops
import std/options

import koi
import nanovg

import common
import domain/all
import main/appcontext
import main/constants
import main/cursor                  # updateLastCursorViewCoords
import main/dialogs                 # the per-dialog procs
import main/dialogs/about
import main/dialogs/common          # DlgItemHeight
import main/dialogs/preferences
import main/views/currentnote   # renderCurrentNotePane
import main/views/levelview         # renderLevel, renderLevelDropdown, renderRegionDropDown, renderEmptyMap, renderModeAndOptionIndicators
import main/views/noteslist    # renderNotesListPane
import main/views/quickref          # renderQuickReference
import main/views/statusbar         # renderStatusBar
import main/views/themepanel        # renderThemeEditorPane
import main/views/tools         # renderToolsPane
import main/view                    # mainPaneRect, currLevel, calculateLevelDrawArea, toolsPane*, updateViewAndCursorPos
import ui/all
import utils/all                    # rect.h/w accessors, alias


using a: var AppContext

# {{{ renderDialogs()
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

# {{{ renderUI()
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


# vim: et:ts=2:sw=2:fdm=marker
