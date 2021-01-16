import tables

import bitable
import rect


const
  AppVersion* = "0.1"

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
    name*:        string
    levels*:      seq[Level]
    links*:       Links
    coordOpts*:   CoordinateOptions

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


  RegionOptions* = object
    enableRegions*:   bool
    regionColumns*:   Natural
    regionRows*:      Natural
    perRegionCoords*: bool


  Level* = ref object
    locationName*:      string
    levelName*:         string
    elevation*:         int

    overrideCoordOpts*: bool
    coordOpts*:         CoordinateOptions

    regionOpts*:        RegionOptions
    regionNames*:       seq[string]

    cellGrid*:          CellGrid
    annotations*:       Table[Natural, Annotation]

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

  CellGrid* = ref object
    cols*:  Natural
    rows*:  Natural

    # Cells are stored in row-major order; (0,0) is the top-left cell
    cells*: seq[Cell]

  Location* = object
    level*:     Natural
    row*, col*: Natural

  Cell* = object
    floor*:            Floor
    floorOrientation*: Orientation
    floorColor*:       byte
    wallN*, wallW*:    Wall
    # TODO
    # trail*:            bool

  Floor* = enum
    fNone                = ( 0, "blank"),
    fEmpty               = ( 1, "empty"),  # TODO rename to blank? interferes with isFloorEmpty
    fTrail               = ( 2, "trail"),  # TODO remove, there will be a separate trail layer
    fDoor                = (20, "door"),
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
    fDoorEnter           = (52, "entrance door"),
    fDoorExit            = (53, "exit door"),
    fSpinner             = (60, "spinner"),
    fTeleportSource      = (70, "teleport"),
    fTeleportDestination = (71, "teleport destination"),
    fInvisibleBarrier    = (80, "invisible barrier")

  Wall* = enum
    wNone          = ( 0, "none")
    wWall          = (10, "wall")
    wIllusoryWall  = (11, "illusory wall")
    wInvisibleWall = (12, "invisible wall")
    wDoor          = (20, "door")
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


const
  LinkPitSources*      = {fClosedPit, fOpenPit, fHiddenPit}
  LinkPitDestinations* = {fCeilingPit}
  LinkStairs*          = {fStairsDown, fStairsUp}
  LinkDoors*           = {fDoorEnter, fDoorExit}

  LinkSources* = LinkPitSources + LinkStairs + LinkDoors + {fTeleportSource}

  LinkDestinations* = LinkPitDestinations + LinkStairs + LinkDoors +
                      {fTeleportDestination}


type
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    rows*, cols*: Natural
    cells*:       seq[bool]

  # TODO make ref?
  SelectionRect* = object
    startRow*: Natural
    startCol*: Natural
    rect*:     Rect[Natural]
    selected*: bool

  # TODO make ref?
  SelectionBuffer* = object
    level*:     Level
    selection*: Selection

const
  # internal IDs, never written to disk
  CopyBufferLevelIndex* = 1_000_000
  MoveBufferLevelIndex* = 1_000_001


# vim: et:ts=2:sw=2:fdm=marker
