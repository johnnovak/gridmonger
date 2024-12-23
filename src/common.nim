import std/hashes
import std/math
import std/options
import std/sets
import std/strformat
import std/strutils
import std/tables

import glfw
import koi
import nanovg
import semver

import utils/rect


const
  ThinSp* = "\u2009"
  HairSp* = "\u200a"
  EnDash* = "\u2013"
  EmDash* = "\u2014"

const
  ProjectHomeUrl* = "https://gridmonger.johnnovak.net/"

  AppVersion*  = parseVersion(staticRead("../CURRENT_VERSION").strip)
  CompileYear* = CompileDate[0..3]

  BuildGitHash* = strutils.strip(staticExec("git rev-parse --short=5 HEAD"))

  VersionString*     = fmt"Version {AppVersion} ({BuildGitHash})"
  FullVersionString* = fmt"Gridmonger {VersionString} [{hostOS}/{hostCPU}]"
  CompiledAt*        = fmt"Compiled at {CompileDate} {CompileTime}"
  DevelopedBy*       = fmt"Developed by John Novak, 2020{EnDash}{CompileYear}"

const
  MinWindowWidth*      = 640
  MinWindowHeight*     = 520

  DefaultWindowWidth*  = 700
  DefaultWindowHeight* = 800

const
  TextVertAlignFactor*  = 0.55
  MaxLabelWidthInCells* = 15


type
  Location* = object
    levelId*:   Natural
    row*, col*: Natural

  CardinalDir* = enum
    dirN = (0, "North")
    dirE = (1, "East")
    dirS = (2, "South")
    dirW = (3, "West")

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

  # When CardinalDir is used to represent a horiz/vert direction
  Horiz* = dirE
  Vert*  = dirN

func isHoriz*(dir: CardinalDir): bool =
  dir in {dirE, dirW}

func isVert*(dir: CardinalDir): bool =
  dir in {dirN, dirS}

func opposite*(dir: CardinalDir): CardinalDir =
  case dir
  of dirN: dirS
  of dirE: dirW
  of dirS: dirN
  of dirW: dirE

func rotateCW*(dir: CardinalDir): CardinalDir =
  CardinalDir(floorMod(ord(dir) + 1, ord(CardinalDir.high) + 1))

func rotateACW*(dir: CardinalDir): CardinalDir =
  CardinalDir(floorMod(ord(dir) - 1, ord(CardinalDir.high) + 1))


type
  Map* = ref object
    title*:            string
    game*:             string
    author*:           string
    creationTime*:     string
    notes*:            string

    levels*:           OrderedTable[Natural, Level]
    levelsDirty*:      bool

    coordOpts*:        CoordinateOptions
    links*:            Links

    sortedLevelIds*:   seq[Natural]
    sortedLevelNames*: seq[string]


  Links* = object
    srcToDest*:  OrderedTable[Location, Location]
    destToSrcs*: OrderedTable[Location, HashSet[Location]]


  CoordinateOptions* = object
    origin*:                 CoordinateOrigin
    rowStyle*, columnStyle*: CoordinateStyle
    rowStart*, columnStart*: int

  CoordinateOrigin* = enum
    coNorthWest = 0
    coSouthWest = 1

  CoordinateStyle* = enum
    csNumber = 0
    csLetter = 1

  Level* = ref object
    # Internal ID, never written to disk
    id*:                Natural

    locationName*:      string
    levelName*:         string
    elevation*:         int
    notes*:             string

    overrideCoordOpts*: bool
    coordOpts*:         CoordinateOptions

    # Note that Regions *can* contain region data even if regions are disabled
    # (regionOpts.enabled = false). This is to preserve the region names and
    # notes when regions are temporarily disabled. Also, we always write the
    # region data into the map file, even if regions are disabled.
    regionOpts*:        RegionOptions
    regions*:           Regions

    annotations*:       Annotations
    cellGrid*:          CellGrid
    dirty*:             bool

  RegionOptions* = object
    enabled*:           bool
    colsPerRegion*:     Natural
    rowsPerRegion*:     Natural
    perRegionCoords*:   bool

  Regions* = object
    regionsByCoords*:   OrderedTable[RegionCoords, Region]
    sortedRegionIds*:   seq[Natural]
    sortedRegionNames*: seq[string]


  # The top-left region has region coordinate (0,0)
  RegionCoords* = object
    row*, col*: Natural

  Region* = object
    name*:  string
    notes*: string

  CellGrid* = ref object
    cols*:  Natural
    rows*:  Natural

    # Cells are stored in row-major order; (0,0) is the top-left cell.
    # We store a cell grid one row & column larger internally.
    cells*: seq[Cell]


  Cell* = object
    floor*:            Floor
    floorOrientation*: CardinalDir
    floorColor*:       byte
    wallN*, wallW*:    Wall
    trail*:            bool

  Floor* = enum
    fEmpty               = ( 0,  "none")
    fBlank               = ( 1,  "blank")
    fDoor                = (20,  "open door")
    fLockedDoor          = (21,  "locked door")
    fArchway             = (22,  "archway")
    fSecretDoorBlock     = (23,  "secret door (block)")
    fSecretDoor          = (24,  "secret door")

    fOneWayDoor          = (25,  "one-way door")
    # for backward compatibility with pre-v4 maps
    fOneWayDoorSW        = (26,  "one-way door")

    fPressurePlate       = (30,  "pressure plate")
    fHiddenPressurePlate = (31,  "hidden pressure plate")
    fClosedPit           = (40,  "closed pit")
    fOpenPit             = (41,  "open pit")
    fHiddenPit           = (42,  "hidden pit")
    fCeilingPit          = (43,  "ceiling pit")
    fStairsDown          = (50,  "stairs down")
    fStairsUp            = (51,  "stairs up")
    fEntranceDoor        = (52,  "entrance door")
    fExitDoor            = (53,  "exit door")
    fSpinner             = (60,  "spinner")
    fTeleportSource      = (70,  "teleport")
    fTeleportDestination = (71,  "teleport destination")
    fInvisibleBarrier    = (80,  "invisible barrier")
    fBridge              = (90,  "bridge")
    fArrow               = (91,  "arrow")
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

  Annotations* = ref object
    cols*, rows*: Natural
    annotations*: OrderedTable[Natural, Annotation]
    dirty*:       bool

  AnnotationKind* = enum
    akComment  = (0, "comment")
    akIndexed  = (1, "indexed")
    akCustomId = (2, "custom ID")
    akIcon     = (3, "icon")
    akLabel    = (4, "label")

  Annotation* = object
    text*: string
    case kind*: AnnotationKind
    of akComment:  discard
    of akIndexed:  index*, indexColor*: Natural
    of akCustomId: customId*: string
    of akIcon:     icon*: Natural
    of akLabel:    labelColor*: Natural

func isLabel*(a: Annotation): bool =
  a.kind == akLabel

func isNote*(a: Annotation): bool =
  not a.isLabel


let
  HorizVertFloors* = {
    fArchway,
    fDoor,
    fLockedDoor,
    fSecretDoor,
    fBridge
  }

  RotatableFloors* = {
    fArrow,
    fOneWayDoor
  }

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
    startRow*:    Natural
    startCol*:    Natural
    rect*:        Rect[Natural]
    selected*:    bool

  SelectionBuffer* = object
    level*:       Level
    selection*:   Selection


type
  LineWidth* = enum
    lwThin   = (0, "Thin")
    lwNormal = (1, "Normal")

  GridStyle* = enum
    gsNone  = (0, "None")
    gsSolid = (1, "Solid")
    gsLoose = (2, "Loose")
    gsCross = (3, "Cross")

  OutlineStyle* = enum
    osNone               = (0, "None")
    osCell               = (1, "Cell")
    osSquareEdges        = (2, "Square Edges")
    osRoundedEdges       = (3, "Rounded Edges")
    osRoundedEdgesFilled = (4, "Filled Rounded Edges")

  OutlineFillStyle* = enum
    ofsSolid   = (0, "Solid")
    ofsHatched = (1, "Hatched")

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


func linkFloorToString*(f: Floor): string =
  if   f in LinkPitSources:      return "pit"
  elif f in LinkPitDestinations: return "pit"
  elif f in LinkStairs:          return "stairs"
  elif f in LinkDoors:           return "door"
  elif f in LinkTeleports:       return "teleport"

func hash*(rc: RegionCoords): Hash =
  var h: Hash = 0
  h = h !& hash(rc.row)
  h = h !& hash(rc.col)
  !$h

func hash*(l: Location): Hash =
  var h: Hash = 0
  h = h !& hash(l.levelId)
  h = h !& hash(l.row)
  h = h !& hash(l.col)
  !$h

func `<`*(a, b: Location): bool =
  if   a.levelId < b.levelId: true
  elif a.levelId > b.levelId: false

  elif a.row < b.row: true
  elif a.row > b.row: false

  elif a.col < b.col: true
  else: false


type
  NotesListFilter* = object
    scope*:      NoteScopeFilter
    noteType*:   set[NoteTypeFilter]
    searchTerm*: string
    orderBy*:    NoteOrdering

  NoteScopeFilter* = enum
    nsfMap    = "Map"
    nsfLevel  = "Level"
    nsfRegion = "Region"

  NoteTypeFilter* = enum
    ntfNone   = ("None")
    ntfNumber = ("Num")
    ntfId     = ("ID")
    ntfIcon   = ("Icon")

  NoteOrdering* = enum
    noType    = "Type"
    noText    = "Text"


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


  CurrentNotePaneTheme* = ref object
    textColor*:                    Color
    indexColor*:                   Color
    indexBackgroundColor*:         array[4, Color]


  NotesListPaneTheme* = ref object
    controlsBackgroundColor*:      Color
    listBackgroundColor*:          Color

    itemBackgroundHoverColor*:     Color
    itemBackgroundActiveColor*:    Color
    itemTextNormalColor*:          Color
    itemTextHoverColor*:           Color
    itemTextActiveColor*:          Color


  ToolbarPaneTheme* = ref object
    buttonNormalColor*:            Color
    buttonHoverColor*:             Color


  LevelTheme* = ref object
    lineWidth*:                    LineWidth
    backgroundColor*:              Color
    cursorColor*:                  Color
    cursorGuidesColor*:            Color
    linkMarkerColor*:              Color
    linkLineColor*:                Color
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


# {{{ App events

type
  AppEventKind* = enum
    aeFocus, aeOpenFile, aeAutoSave, aeVersionUpdate

  AppEvent* = object
    case kind*: AppEventKind
    of aeOpenFile:
      path*: string
    of aeVersionUpdate:
      versionInfo*: Option[VersionInfo]
      error*:       Option[CatchableError]
    else: discard

  VersionInfo* = object
    version*: Version
    message*: string

var
  g_appEventCh*: Channel[AppEvent]

proc sendAppEvent*(event: AppEvent) =
  g_appEventCh.send(event)
  # Main event loop might be stuck at waitEvents(), so wake it up
  glfw.postEmptyEvent()

# }}}


# vim: et:ts=2:sw=2:fdm=marker
