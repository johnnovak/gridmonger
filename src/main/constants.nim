# constants
#
# Project-wide compile-time constants for the gridmonger app: file extensions,
# UI sizing/padding, validation limits, floor groupings, message timeouts.
# Side effects: none (compile-time data only).

import std/sequtils
import std/strutils
import std/times

when not defined(DEBUG):
  import std/strformat

import common
import fieldlimits


# {{{ Constants
const
  ThemeExt*          = "gmtheme"
  MapFileExt*        = "gmm"
  BackupFileExt*     = "bak"
  CrashAutosaveName* = "Crash Autosave"
  UntitledName*      = "Untitled"

when not defined(DEBUG):
  const GridmongerMapFileFilter* = "Gridmonger Map" &
                                   fmt" (*.{MapFileExt}):{MapFileExt}"

const
  CursorJump*   = 5
  ScrollMargin* = 3

const
  StatusBarHeight*          = 26.0

  LevelTopPad_Regions*      = 28.0

  LevelTopPad_Coords*       = 85.0
  LevelRightPad_Coords*     = 50.0
  LevelBottomPad_Coords*    = 40.0
  LevelLeftPad_Coords*      = 50.0

  LevelTopPad_NoCoords*     = 65.0
  LevelRightPad_NoCoords*   = 28.0
  LevelBottomPad_NoCoords*  = 10.0
  LevelLeftPad_NoCoords*    = 28.0

  CurrentNotePaneHeight*    = 72.0
  CurrentNotePaneTopPad*    = 0.0
  CurrentNotePaneRightPad*  = 26.0
  CurrentNotePaneBottomPad* = 16.0
  CurrentNotePaneLeftPad*   = 14.0

  NotesListPaneWidth*       = 300.0

  ToolsPaneWidthNarrow*     = 60.0
  ToolsPaneWidthWide*       = 90.0
  ToolsPaneTopPad*          = 65.0
  ToolsPaneBottomPad*       = 30.0
  ToolsPaneYBreakpoint1*    = 709.0
  ToolsPaneYBreakpoint2*    = 859.0

  ThemePaneWidth*           = 326.0

const
  SplashTimeoutSecsLimits* = intLimits(min=1, max=10)
  AutosaveFreqMinsLimits*  = intLimits(min=1, max=30)
  WindowWidthLimits*       = intLimits(MinWindowWidth, max=20_000)
  WindowHeightLimits*      = intLimits(MinWindowHeight, max=20_000)
  UIScaleFactorLimits*     = intLimits(min=100, max=500)

const
  WarningMessageTimeout* = initDuration(seconds = 3)
  InfiniteDuration*      = initDuration(seconds = int64.high)

const
  SpecialWallTooltips* = SpecialWalls.mapIt(($it).capitalizeAscii)

  FloorGroup1* = @[
    fDoor,
    fLockedDoor,
    fArchway
  ]

  FloorGroup2* = @[
    fSecretDoor,
    fSecretDoorBlock,
    fOneWayDoor
  ]

  FloorGroup3* = @[
    fPressurePlate,
    fHiddenPressurePlate
  ]

  FloorGroup4* = @[
    fClosedPit,
    fOpenPit,
    fHiddenPit,
    fCeilingPit
  ]

  FloorGroup5* = @[
    fTeleportSource,
    fTeleportDestination,
    fSpinner,
    fInvisibleBarrier
  ]

  FloorGroup6* = @[
    fStairsDown,
    fStairsUp,
    fEntranceDoor,
    fExitDoor
  ]

  FloorGroup7* = @[
    fBridge,
    fArrow
  ]

  FloorGroup8* = @[
    fColumn,
    fStatue
  ]

# }}}

# vim: et:ts=2:sw=2:fdm=marker
