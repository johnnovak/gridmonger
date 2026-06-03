import std/logging as log except Level
import std/monotimes
import std/options
import std/os
import std/strformat
import std/tempfiles

import with

import appcontext
import appevents
import common
import configio
import constants
import cursor
import io/persistence
import logging
import theme
import ui/all
import undomanager
import utils/all
import views/statusbar

when not defined(DEBUG):
  import osdialog


using a: var AppContext

# {{{ loadMap*()
proc loadMap*(path: string; a): bool =
  log.info(fmt"Loading map '{path}'...")

  try:
    let
      t0 = getMonoTime()
      (map, appState, warning) = readMapFile(path)
      dt = getMonoTime() - t0

    a.doc.map  = map
    a.doc.path = path

    if appState.isSome:
      let s = appState.get

      a.updateUI = false
      a.theme.nextThemeIndex = findThemeIndex(s.themeName, a)
      a.theme.hideThemeLoadedMessage = true

      with a.ui.drawLevelParams:
        viewStartRow   = s.viewStartRow
        viewStartCol   = s.viewStartCol

      with a.ui.cursor:
        levelId = s.currLevelId
        row   = s.cursorRow
        col   = s.cursorCol

      with a.ui:
        currFloorColor  = s.currFloorColor
        currSpecialWall = s.currSpecialWall
        showCellCoords  = s.showCellCoords
        wasdMode        = s.wasdMode
        walkMode        = s.walkMode
        pasteWraparound = s.pasteWraparound
        drawTrail       = false

      if s.notesListPaneState.isSome:
        let nls = s.notesListPaneState.get
        with a.ui.notesListState:
          currFilter        = nls.filter
          linkCursor        = nls.linkCursor
          viewStartY        = nls.viewStartY.float
          restoreViewStartY = true
          levelSections     = nls.levelSections
          regionSections    = nls.regionSections

      a.ui.drawLevelParams.setZoomLevel(a.theme.levelTheme, s.zoomLevel)
      a.ui.mouseCanStartExcavate = true

    else:
      resetCursorAndViewStart(a)

    initUndoManager(a.doc.undoManager)

    appEvents.updateLastSavedTime()

    var message = fmt"Map '{path}' loaded"
    when defined(DEBUG):
      message &= fmt" in {durationToFloatMillis(dt):.2f} ms"

    if warning.len > 0:
      message &= fmt" with warnings: {warning}"

    if warning.len > 0:
      log.warn(message)
      setWarningMessage(message, a=a)
    else:
      log.info(message)
      setStatusMessage(IconFloppy, message, a)

    # So at least we can restore the last loaded map in case of a crash
    saveAppConfig(a)
    result = true

  except CatchableError as e:
    let msgPrefix = "Error loading map"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
  finally:
    a.logFile.flushFile

# }}}

# {{{ saveMap*()
proc saveMap*(path: string, autosave, createBackup: bool; a) =
  alias(dp, a.ui.drawLevelParams)
  alias(nls, a.ui.notesListState)

  let cur = a.ui.cursor

  let appState = AppState(
    themeName:              a.currThemeName.name,

    zoomLevel:              dp.getZoomLevel,
    currLevelId:            cur.levelId,
    cursorRow:              cur.row,
    cursorCol:              cur.col,
    viewStartRow:           dp.viewStartRow,
    viewStartCol:           dp.viewStartCol,

    showCellCoords:         a.ui.showCellCoords,
    wasdMode:               a.ui.wasdMode,
    walkMode:               a.ui.walkMode,
    pasteWraparound:        a.ui.pasteWraparound,

    currFloorColor:         a.ui.currFloorColor,
    currSpecialWall:        a.ui.currSpecialWall,

    notesListPaneState:     AppStateNotesListPane(
                              filter:         nls.currFilter,
                              linkCursor:     nls.linkCursor,
                              viewStartY:     nls.viewStartY.Natural,
                              levelSections:  nls.levelSections,
                              regionSections: nls.regionSections
                            ).some
  )

  log.info(fmt"Saving map to '{path}'")

  if createBackup:
    try:
      if fileExists(path):
        copyFile(path, fmt"{path}.{BackupFileExt}")
    except CatchableError as e:
      let msgPrefix = "Error creating backup file"
      logError(e, msgPrefix)
      setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)
      return

  let (dir, name, _) = splitFile(path)
  let tempPath = genTempPath(prefix=fmt"{name} ", suffix=".gmm.tmp", dir=dir)

  try:
    writeMapFile(a.doc.map, appState, tempPath)
    moveFile(tempPath, path)

    a.doc.lastSavePath = path
    a.doc.undoManager.setLastSaveState

    if not autosave:
      setStatusMessage(IconFloppy, fmt"Map '{path}' saved", a)
      appEvents.updateLastSavedTime()

  except CatchableError as e:
    let msgPrefix = if autosave: "Autosaving map failed"
                    else: "Saving map failed"
    logError(e, msgPrefix)
    setErrorMessage(fmt"{msgPrefix}: {e.msg}", a)

    if fileExists(tempPath):
      removeFile(tempPath)
  finally:
    a.logFile.flushFile

# }}}
# {{{ autoSaveMapOnCrash*()

when not defined(DEBUG):

  proc autoSaveMapOnCrash*(a): string =
    let (dir, name) = if a.doc.path == "":
      (a.paths.autosaveDir, UntitledName)
    else:
      let (dir, name, _) = splitFile(a.doc.path)
      (dir, name)

    let path = findUniquePath(dir, fmt"{name} {CrashAutosaveName}", MapFileExt)

    log.info(fmt"Autosaving map to '{path}'")
    saveMap(path, autosave=false, createBackup=false, a)

    result = path

# }}}
# {{{ saveMapAs*()
proc saveMapAs*(a) =
  when not defined(DEBUG):
    var path = fileDialog(fdSaveFile, filters=GridmongerMapFileFilter)
    if path != "":
      path = addFileExt(path, MapFileExt)

      saveMap(path, autosave=false, createBackup=false, a)
      a.doc.path = path

      # So at least we can restore the same map file in case of a crash
      saveAppConfig(a)

# }}}
# {{{ saveMap*()
proc saveMap*(a) =
  if a.doc.path == "":
    saveMapAs(a)
  else:
    saveMap(a.doc.path, autosave=false, createBackup=true, a)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
