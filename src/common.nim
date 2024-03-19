import std/sets
import std/strformat
import std/strutils
import std/tables

import koi
import nanovg

import rect


const
  AppVersion* = staticRead("../CURRENT_VERSION").strip
  CompileYear* = CompileDate[0..3]

  BuildGitHash* = strutils.strip(staticExec("git rev-parse --short HEAD"))

  VersionInfo* = fmt"Version {AppVersion} ({BuildGitHash})"
  FullVersionInfo* = fmt"Gridmonger {VersionInfo} [{hostOS}/{hostCPU}]"
  CompiledAtInfo* = fmt"Compiled at {CompileDate} {CompileTime}"
  DevelopedByInfo* = fmt"Developed by John Novak, 2020-{CompileYear}"

const
  EnDash* = "\u2013"

  TextVertAlignFactor* = 0.55

  MaxLabelWidthInCells* = 15

  MinWindowWidth*  = 640
  MinWindowHeight* = 520


type
  Location* = object
    level*:     Natural
    row*, col*: Natural

type
  CardinalDir* = enum
    dirN = "North"
    dirE = "East"
    dirS = "South"
    dirW = "West"

  Direction* = set[CardinalDir]

  Orientation* = enum
    Horiz = "horizontal"
    Vert  = "vertical"

const
  North*     = {dirN}
  NorthEast* = {dirN, dirE}
  East*      = {dirE}
  SouthEast* = {dirS, dirE}
  South*     = {dirS}
  SouthWest* = {dirS, dirW}
  West*      = {dirW}
  NorthWest* = {dirN, dirW}

proc orientation*(dir: CardinalDir): Orientation =
  case dir
  of dirE, dirW: Horiz
  of dirN, dirS: Vert

proc opposite*(o: Orientation): Orientation =
  case o
  of Horiz: Vert
  of Vert:  Horiz


type
  Map* = ref object
    title*:        string
    game*:         string
    author*:       string
    creationTime*: string
    notes*:        string

    levels*:       seq[Level]
    coordOpts*:    CoordinateOptions

    links*:        Links

    sortedLevelNames*:         seq[string]
    sortedLevelIdxToLevelIdx*: Table[Natural, Natural]


  Links* = object
    srcToDest*:  OrderedTable[Location, Location]
    destToSrcs*: OrderedTable[Location, HashSet[Location]]


  CoordinateOptions* = object
    origin*:                 CoordinateOrigin
    rowStyle*, columnStyle*: CoordinateStyle
    rowStart*, columnStart*: int

  CoordinateOrigin* = enum
    coNorthWest, coSouthWest

  CoordinateStyle* = enum
    csNumber, csLetter


  Level* = ref object
    locationName*:      string
    levelName*:         string
    elevation*:         int

    overrideCoordOpts*: bool
    coordOpts*:         CoordinateOptions

    notes*:             string

    regionOpts*:        RegionOptions
    regions*:           Regions

    annotations*:       Annotations

    cellGrid*:          CellGrid


  RegionOptions* = object
    enabled*:         bool
    colsPerRegion*:   Natural
    rowsPerRegion*:   Natural
    perRegionCoords*: bool

  Regions* = OrderedTable[RegionCoords, Region]

  RegionCoords* = object
    row*, col*: Natural

  Region* = object
    name*:  string
    notes*: string


  Annotations* = ref object
    cols*, rows*:  Natural
    annotations*:  OrderedTable[Natural, Annotation]

  AnnotationKind* = enum
    akComment, akIndexed, akCustomId, akIcon, akLabel

  Annotation* = object
    text*: string
    case kind*: AnnotationKind
    of akComment:  discard
    of akIndexed:  index*, indexColor*: Natural
    of akCustomId: customId*: string
    of akIcon:     icon*: Natural
    of akLabel:    labelColor*: Natural


  CellGrid* = ref object
    cols*:  Natural
    rows*:  Natural

    # Cells are stored in row-major order; (0,0) is the top-left cell
    cells*: seq[Cell]


  Cell* = object
    floor*:            Floor
    floorOrientation*: Orientation
    floorColor*:       byte
    wallN*, wallW*:    Wall
    trail*:            bool

  Floor* = enum
    fEmpty               = ( 0, "none")
    fBlank               = ( 1, "blank")
    fDoor                = (20, "open door")
    fLockedDoor          = (21, "locked door")
    fArchway             = (22, "archway")
    fSecretDoorBlock     = (23, "secret door (block)")
    fSecretDoor          = (24, "secret door")
    fOneWayDoor1         = (25, "one-way door")
    fOneWayDoor2         = (26, "one-way door")
    fPressurePlate       = (30, "pressure plate")
    fHiddenPressurePlate = (31, "hidden pressure plate")
    fClosedPit           = (40, "closed pit")
    fOpenPit             = (41, "open pit")
    fHiddenPit           = (42, "hidden pit")
    fCeilingPit          = (43, "ceiling pit")
    fStairsDown          = (50, "stairs down")
    fStairsUp            = (51, "stairs up")
    fEntranceDoor        = (52, "entrance door")
    fExitDoor            = (53, "exit door")
    fSpinner             = (60, "spinner")
    fTeleportSource      = (70, "teleport")
    fTeleportDestination = (71, "teleport destination")
    fInvisibleBarrier    = (80, "invisible barrier")
    fBridge              = (90, "bridge")
    fColumn              = (100, "column")
    fStatue              = (110, "statue")

  Wall* = enum
    wNone          = ( 0, "none")
    wWall          = (10, "wall")
    wIllusoryWall  = (11, "illusory wall")
    wInvisibleWall = (12, "invisible wall")
    wDoor          = (20, "open door")
    wLockedDoor    = (21, "locked door")
    wArchway       = (22, "archway")
    wSecretDoor    = (23, "secret door")
    wOneWayDoorNE  = (24, "one-way door")
    wOneWayDoorSW  = (25, "one-way door")
    wLeverNE       = (30, "lever")
    wLeverSW       = (31, "lever")
    wNicheNE       = (40, "niche")
    wNicheSW       = (41, "niche")
    wStatueNE      = (50, "statue")
    wStatueSW      = (51, "statue")
    wKeyhole       = (60, "keyhole")
    wWritingNE     = (70, "writing")
    wWritingSW     = (71, "writing")

const
  SpecialWalls* = @[
    wDoor,
    wLockedDoor,
    wArchway,
    wSecretDoor,
    wOneWayDoorNE,
    wIllusoryWall,
    wInvisibleWall,
    wLeverSW,
    wNicheSW,
    wStatueSW,
    wKeyhole,
    wWritingSW
  ]


type
  # Selections always have the same dimensions as the level the selection was
  # made in. The actual selection rectangle is then retrieved with the
  # boundingBox() method.
  #
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    rows*, cols*: Natural
    cells*:       seq[bool]

  SelectionRect* = object
    startRow*: Natural
    startCol*: Natural
    rect*:     Rect[Natural]
    selected*: bool

  SelectionBuffer* = object
    level*:     Level
    selection*: Selection


type
  LineWidth* = enum
    lwThin   = (0, "Thin")
    lwNormal = (1, "Normal")

  GridStyle* = enum
    gsNone   = (0, "None")
    gsSolid  = (1, "Solid")
    gsLoose  = (2, "Loose")
    gsCross  = (3, "Cross")

  OutlineStyle* = enum
    osNone                = (0, "None")
    osCell                = (1, "Cell")
    osSquareEdges         = (2, "Square Edges")
    osRoundedEdges        = (3, "Rounded Edges")
    osRoundedEdgesFilled  = (4, "Filled Rounded Edges")

  OutlineFillStyle* = enum
    ofsSolid    = (0, "Solid")
    ofsHatched  = (1, "Hatched")

  NoteBackgroundShape* = enum
    nbsCircle    = (0, "Circle")
    nbsRectangle = (1, "Rectangle")


const
  LinkPitSources*      = {fClosedPit, fOpenPit, fHiddenPit}
  LinkPitDestinations* = {fCeilingPit}
  LinkTeleports*       = {fTeleportSource, fTeleportDestination}
  LinkStairs*          = {fStairsDown, fStairsUp}
  LinkDoors*           = {fEntranceDoor, fExitDoor}

  LinkSources* = LinkPitSources + LinkTeleports + LinkStairs + LinkDoors

type
  WindowTheme* = ref object
    borderColor*:                  Color
    backgroundColor*:              Color
    backgroundImage*:              string
    titleBackgroundColor*:         Color
    titleBackgroundInactiveColor*: Color
    titleColor*:                   Color
    titleInactiveColor*:           Color
    buttonColor*:                  Color
    buttonHoverColor*:             Color
    buttonDownColor*:              Color
    buttonInactiveColor*:          Color
    modifiedFlagColor*:            Color
    modifiedFlagInactiveColor*:    Color

  StatusBarTheme* = ref object
    backgroundColor*:              Color
    textColor*:                    Color
    warningTextColor*:             Color
    errorTextColor*:               Color
    coordinatesColor*:             Color
    commandBackgroundColor*:       Color
    commandTextColor*:             Color

  NotesPaneTheme* = ref object
    textColor*:                    Color
    scrollBarColor*:               Color
    indexColor*:                   Color
    indexBackgroundColor*:         array[4, Color]

  ToolbarPaneTheme* = ref object
    buttonNormalColor*:            Color
    buttonHoverColor*:             Color


  LevelTheme* = ref object
    lineWidth*:                    LineWidth
    backgroundColor*:              Color
    cursorColor*:                  Color
    cursorGuidesColor*:            Color
    linkMarkerColor*:              Color
    selectionColor*:               Color
    trailNormalColor*:             Color
    trailCursorColor*:             Color
    pastePreviewColor*:            Color
    foregroundNormalNormalColor*:  Color
    foregroundNormalCursorColor*:  Color
    foregroundLightNormalColor*:   Color
    foregroundLightCursorColor*:   Color
    coordinatesNormalColor*:       Color
    coordinatesHighlightColor*:    Color
    regionBorderNormalColor*:      Color
    regionBorderEmptyColor*:       Color

    backgroundHatchEnabled*:       bool
    backgroundHatchColor*:         Color
    backgroundHatchWidth*:         float
    backgroundHatchSpacingFactor*: float

    gridBackgroundStyle*:          GridStyle
    gridBackgroundGridColor*:      Color
    gridFloorStyle*:               GridStyle
    gridFloorGridColor*:           Color

    outlineStyle*:                 OutlineStyle
    outlineFillStyle*:             OutlineFillStyle
    outlineColor*:                 Color
    outlineWidthFactor*:           float
    outlineOverscan*:              bool

    shadowInnerColor*:             Color
    shadowInnerWidthFactor*:       float
    shadowOuterColor*:             Color
    shadowOuterWidthFactor*:       float

    floorTransparent*:             bool
    floorBackgroundColor*:         array[10, Color]

    noteMarkerNormalColor*:        Color
    noteMarkerCursorColor*:        Color
    noteCommentColor*:             Color
    noteBackgroundShape*:          NoteBackgroundShape
    noteIndexBackgroundColor*:     array[4, Color]
    noteIndexColor*:               Color
    noteTooltipBackgroundColor*:   Color
    noteTooltipTextColor*:         Color
    noteTooltipCornerRadius*:      float
    noteTooltipShadowStyle*:       ShadowStyle

    labelTextColor*:               array[4, Color]


# vim: et:ts=2:sw=2:fdm=marker
