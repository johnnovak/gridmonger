import nanovg

import bitable
import hashes
import rect
import tables


const
  TextVertAlignFactor* = 0.55

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
    levels*:   seq[Level]
    links*:    BiTable[Location, Location]

  Level* = ref object
    name*:     string
    level*:    int
    cellGrid*: CellGrid
    notes*:    Table[Natural, Note]

  LevelStyle* = ref object
    backgroundColor*:        Color
    drawColor*:              Color
    lightDrawColor*:         Color
    floorColor*:             Color
    thinLines*:              bool

    bgHatchEnabled*:         bool
    bgHatchColor*:           Color
    bgHatchStrokeWidth*:     float
    bgHatchSpacingFactor*:   float

    coordsColor*:            Color
    coordsHighlightColor*:   Color

    cursorColor*:            Color
    cursorGuideColor*:       Color

    gridStyle*:              GridStyle
    gridColorBackground*:    Color
    gridColorFloor*:         Color

    outlineStyle*:           OutlineStyle
    outlineFillStyle*:       OutlineFillStyle
    outlineOverscan*:        bool
    outlineColor*:           Color
    outlineWidthFactor*:     float

    innerShadowEnabled*:     bool
    innerShadowColor*:       Color
    innerShadowWidthFactor*: float
    outerShadowEnabled*:     bool
    outerShadowColor*:       Color
    outerShadowWidthFactor*: float

    pastePreviewColor*:      Color
    selectionColor*:         Color

    noteLevelTextColor*:     Color
    noteLevelCommentColor*:  Color
    noteLevelIndexColor*:    Color
    noteLevelIndexBgColor*:  seq[Color]

    notePaneTextColor*:      Color
    notePaneIndexColor*:     Color
    notePaneIndexBgColor*:   seq[Color]


  GridStyle* = enum
    gsNone, gsSolid, gsLoose, gsDashed

  OutlineStyle* = enum
    osNone, osCell, osSquareEdges, osRoundedEdges, osRoundedEdgesFilled

  OutlineFillStyle* = enum
    ofsSolid, ofsHatched

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
    wallN*, wallW*:    Wall

  Floor* = enum
    fNone                = (  0, "blank"),
    fEmpty               = (  1, "empty"),
    fDoor                = ( 20, "door"),
    fLockedDoor          = ( 21, "locked door"),
    fArchway             = ( 22, "archway"),
    fSecretDoor          = ( 23, "secret door"),
    fPressurePlate       = ( 30, "pressure plate"),
    fHiddenPressurePlate = ( 31, "hidden pressure plate"),
    fClosedPit           = ( 40, "closed pit"),
    fOpenPit             = ( 41, "open pit"),
    fHiddenPit           = ( 42, "hidden pit"),
    fCeilingPit          = ( 43, "ceiling pit"),
    fStairsDown          = ( 50, "stairs down"),
    fStairsUp            = ( 51, "stairs up"),
    fExitDoor            = ( 52, "exit door"),
    fSpinner             = ( 60, "spinner"),
    fTeleportSource      = ( 70, "teleport"),
    fTeleportDestination = ( 71, "teleport destination"),

  Wall* = enum
    wNone          = (0, "none"),
    wWall          = (10, "wall"),
    wIllusoryWall  = (11, "illusory wall"),
    wInvisibleWall = (12, "invisible wall")
    wDoor          = (20, "door"),
    wLockedDoor    = (21, "locked door"),
    wArchway       = (22, "archway"),
    wSecretDoor    = (23, "secret door"),
    wLeverNE       = (30, "lever")
    wLeverSW       = (31, "lever")
    wNicheNE       = (40, "niche")
    wNicheSW       = (41, "niche")
    wStatueNE      = (50, "statue")
    wStatueSW      = (51, "statue")
    wKeyhole       = (60, "keyhole")

  NoteKind* = enum
    nkComment, nkIndexed, nkCustomId, nkIcon

  Note* = object
    text*: string
    case kind*: NoteKind
    of nkComment:  discard
    of nkIndexed:  index*, indexColor*: Natural
    of nkCustomId: customId*: string
    of nkIcon:     icon*: Natural


proc hash*(ml: Location): Hash =
  var h: Hash = 0
  h = h !& hash(ml.level)
  h = h !& hash(ml.row)
  h = h !& hash(ml.col)
  result = !$h

proc `<`*(a, b: Location): bool =
  if   a.level < b.level: return true
  elif a.level > b.level: return false

  elif a.row < b.row: return true
  elif a.row > b.row: return false

  elif a.col < b.col: return true
  else: return false


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

# vim: et:ts=2:sw=2:fdm=marker
