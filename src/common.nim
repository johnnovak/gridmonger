import strutils
import tables

import koi
import nanovg

import bitable
import rect


const
  AppVersion* = "0.9"
  BuildGitHash* = strutils.strip(staticExec("git rev-parse --short HEAD"))

const
  EnDash* = "\u2013"

  TextVertAlignFactor* = 0.55

  MaxLabelWidthInCells* = 15

  WindowMinWidth* = 640
  WindowMinHeight* = 520


type
  Orientation* = enum
    Horiz = (0, "horiz")
    Vert  = (1, "vert")

  Location* = object
    level*:     Natural
    row*, col*: Natural


type
  CardinalDir* = enum
    dirN  = (0, "North")
    dirE  = (1, "East")
    dirS  = (2, "South")
    dirW  = (3, "West")

  Direction* = set[CardinalDir]

const
  North*     = {dirN}
  NorthEast* = {dirN, dirE}
  East*      = {dirE}
  SouthEast* = {dirS, dirE}
  South*     = {dirS}
  SouthWest* = {dirS, dirW}
  West*      = {dirW}
  NorthWest* = {dirN, dirW}


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


  Links* = BiTable[Location, Location]

  CoordinateOptions* = object
    origin*:                 CoordinateOrigin
    rowStyle*, columnStyle*: CoordinateStyle
    rowStart*, columnStart*: Natural

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

  Regions* = Table[RegionCoords, Region]

  RegionCoords* = object
    row*, col*: Natural

  Region* = object
    name*:  string
    notes*: string


  Annotations* = ref object
    cols*, rows*:  Natural
    annotations*:  Table[Natural, Annotation]

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
    fEmpty               = ( 0, "none"),
    fBlank               = ( 1, "blank"),
    fDoor                = (20, "open door"),
    fLockedDoor          = (21, "locked door"),
    fArchway             = (22, "archway"),
    fSecretDoorBlock     = (23, "secret door (block)"),
    fSecretDoor          = (24, "secret door"),
    fOneWayDoor1         = (25, "one-way door"),
    fOneWayDoor2         = (26, "one-way door"),
    fPressurePlate       = (30, "pressure plate"),
    fHiddenPressurePlate = (31, "hidden pressure plate"),
    fClosedPit           = (40, "closed pit"),
    fOpenPit             = (41, "open pit"),
    fHiddenPit           = (42, "hidden pit"),
    fCeilingPit          = (43, "ceiling pit"),
    fStairsDown          = (50, "stairs down"),
    fStairsUp            = (51, "stairs up"),
    fEntranceDoor        = (52, "entrance door"),
    fExitDoor            = (53, "exit door"),
    fSpinner             = (60, "spinner"),
    fTeleportSource      = (70, "teleport"),
    fTeleportDestination = (71, "teleport destination"),
    fInvisibleBarrier    = (80, "invisible barrier")
    fBridge              = (90, "bridge")

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
    lwThin   = (0, "Thin"),
    lwNormal = (1, "Normal")

  GridStyle* = enum
    gsNone   = (0, "None"),
    gsSolid  = (1, "Solid"),
    gsLoose  = (2, "Loose"),
    gsCross  = (3, "Cross")

  OutlineStyle* = enum
    osNone                = (0, "None"),
    osCell                = (1, "Cell"),
    osSquareEdges         = (2, "Square Edges"),
    osRoundedEdges        = (3, "Rounded Edges"),
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
  WindowStyle* = ref object
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

  StatusBarStyle* = ref object
    backgroundColor*:        Color
    textColor*:              Color
    coordinatesColor*:       Color
    commandBackgroundColor*: Color
    commandTextColor*:       Color

  NotesPaneStyle* = ref object
    textColor*:              Color
    scrollBarColor*:         Color
    indexColor*:             Color
    indexBackgroundColor*:   array[4, Color]

  ToolbarPaneStyle* = ref object
    buttonNormalColor*:      Color
    buttonHoverColor*:       Color


  LevelStyle* = ref object
    lineWidth*:                  LineWidth
    backgroundColor*:            Color
    cursorColor*:                Color
    cursorGuidesColor*:          Color
    linkMarkerColor*:            Color
    selectionColor*:             Color
    trailColor*:                 Color
    pastePreviewColor*:          Color
    foregroundNormalColor*:      Color
    foregroundLightColor*:       Color
    coordinatesNormalColor*:     Color
    coordinatesHighlightColor*:  Color
    regionBorderNormalColor*:    Color
    regionBorderEmptyColor*:     Color

    backgroundHatchEnabled*:       bool
    backgroundHatchColor*:         Color
    backgroundHatchWidth*:         float
    backgroundHatchSpacingFactor*: float

    gridBackgroundStyle*:        GridStyle
    gridBackgroundGridColor*:    Color
    gridFloorStyle*:             GridStyle
    gridFloorGridColor*:         Color

    outlineStyle*:               OutlineStyle
    outlineFillStyle*:           OutlineFillStyle
    outlineColor*:               Color
    outlineWidthFactor*:         float
    outlineOverscan*:            bool

    shadowInnerColor*:           Color
    shadowInnerWidthFactor*:     float
    shadowOuterColor*:           Color
    shadowOuterWidthFactor*:     float

    floorTransparent*:           bool
    floorBackgroundColor*:       array[10, Color]

    noteMarkerColor*:            Color
    noteCommentColor*:           Color
    noteBackgroundShape*:        NoteBackgroundShape
    noteIndexBackgroundColor*:   array[4, Color]
    noteIndexColor*:             Color
    noteTooltipBackgroundColor*: Color
    noteTooltipTextColor*:       Color
    noteTooltipCornerRadius*:    float
    noteTooltipShadowStyle*:     ShadowStyle

    labelTextColor*:             array[4, Color]

# vim: et:ts=2:sw=2:fdm=marker
