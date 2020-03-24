import options
import tables

import nanovg
import glfw

import undomanager


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
  # Rects are endpoint-exclusive
  Rect*[T: SomeNumber | Natural] = object
    x1*, y1*, x2*, y2*: T

proc rectN*(x1, y1, x2, y2: Natural): Rect[Natural] =
  assert x1 < x2
  assert y1 < y2

  result.x1 = x1
  result.y1 = y1
  result.x2 = x2
  result.y2 = y2

proc intersect*[T: SomeNumber | Natural](a, b: Rect[T]): Option[Rect[T]] =
  let
    x = max(a.x1, b.x1)
    y = max(a.y1, b.y1)
    n1 = min(a.x1 + a.width,  b.x1 + b.width)
    n2 = min(a.y1 + a.height, b.y1 + b.height)

  if (n1 >= x and n2 >= y):
    some(Rect[T](
      x1: x,
      y1: y,
      x2: x + n1-x,
      y2: y + n2-y
    ))
  else: none(Rect[T])

func width*[T: SomeNumber | Natural](r: Rect[T]): T = r.x2 - r.x1
func height*[T: SomeNumber | Natural](r: Rect[T]): T = r.y2 - r.y1

func contains*[T: SomeNumber | Natural](r: Rect[T], x, y: T): bool =
  x >= r.x1 and x < r.x2 and y >= r.y1 and y < r.y2


type
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
    fSpinner             = ( 60, "spinner"),
    fTeleport            = ( 70, "teleport"),
    fCustom              = (255, "custom")

  Wall* = enum
    wNone          = (0, "none"),
    wWall          = (10, "wall"),
    wIllusoryWall  = (11, "illusory wall"),
    wInvisibleWall = (12, "invisible wall")
    wDoor          = (20, "door"),
    wLockedDoor    = (21, "locked door"),
    wArchway       = (22, "archway"),
    wSecretDoor    = (23, "secret door"),
    wLever         = (30, "lever")
    wNiche         = (40, "niche")
    wStatue        = (50, "statue")

  Cell* = object
    floor*:            Floor
    floorOrientation*: Orientation
    wallN*, wallW*:    Wall

  NoteKind* = enum
    nkIndexed, nkCustomId, nkComment

  Note* = object
    text*: string
    case kind*: NoteKind
    of nkIndexed:  index*: Natural
    of nkCustomId: customId*: string
    of nkComment:  discard

  # (0,0) is the top-left cell of the map
  Map* = ref object
    name*:  string
    cols*:  Natural
    rows*:  Natural
    cells*: seq[Cell]
    notes*: Table[Natural, Note]

  # TODO introduce CellGrid
  #CellGrid* = ref object
  #  cols*:  Natural
  #  rows*:  Natural
  #  cells*: seq[Cell]


type
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    cols*:  Natural
    rows*:  Natural
    cells*: seq[bool]

  # TODO make ref?
  SelectionRect* = object
    x0*, y0*:   Natural
    rect*:      Rect[Natural]
    selected*:  bool


type
  # TODO make ref?
  CopyBuffer* = object
    map*:       Map
    selection*: Selection

# {{{ Icons

const
  IconArrows* = "\uf047"
  IconAsterisk* = "\uf069"
  IconCheck* = "\uf00c"
  IconClose* = "\uf00d"
  IconCog* = "\uf013"
  IconCopy* = "\uf0c5"
  IconCut* = "\uf0c4"
  IconEraser* = "\uf12d"
  IconFile* = "\uf0f6"
  IconFloppy* = "\uf0c7"
  IconFullscreen* = "\ue90f"
  IconFullscreenExit* = "\ue90e"
  IconHorizArrows* = "\uf07e"
  IconInfo* = "\uf05a"
  IconModAlt* = "\uea51"
  IconModCommand* = "\uea4e"
  IconModCtrl* = "\uea50"
  IconModShift* = "\uea4f"
  IconMouse* = "\ue91c"
  IconPaste* = "\uf0ea"
  IconPencil* = "\uf040"
  IconPin* = "\ue91d"
  IconRedo* = "\uf064"
  IconRotate* = "\uf01e"
  IconSelection* = "\ue90b"
  IconTiles* = "\ue950"
  IconUndo* = "\uf112"
  IconVertArrows* = "\uf07d"
  IconWarning* = "\uf071"
  IconWindowClose* = "\uf2d3"
  IconWindowMaximise* = "\uf2d0"
  IconWindowMinimise* = "\uf2d1"
  IconWindowRestore* = "\uf2d2"
  IconZoomIn* = "\uf00e"
  IconZoomOut* = "\uf010"

  IconStairsDown* = "\ue90c"
  IconStairsUp* = "\ue90d"
  IconEnter* = "\uea13"
  IconExit* = "\uea14"

  IconAnchor* = "\uf13d"
  IconBed* = "\uf236"
  IconBomb* = "\uf1e2"
  IconBook* = "\uf02d"
  IconDiamond* = "\uf219"
  IconEquip* = "\ue92e"
  IconFlag* = "\uf024"
  IconFlask* = "\uf0c3"
  IconFort* = "\uf286"
  IconHeart* = "\uf004"
  IconHome* = "\uf015"
  IconKey* = "\uf084"
  IconMale* = "\uf183"
  IconMedkit* = "\uf0fa"
  IconMoney* = "\ue93e"
  IconMoneyBag* = "\ue909"
  IconMug* = "\ue905"
  IconShield* = "\uf132"
  IconShip* = "\ue944"
  IconSpinner* = "\ue910"
  IconStar* = "\uf005"
  IconTree* = "\ue945"
  IconTrophy* = "\uf091"

const MarkerIcons* = @[
  IconAnchor,
  IconBed,
  IconBomb,
  IconBook,
  IconDiamond,
  IconEquip,
  IconFlag,
  IconFlask,
  IconFort,
  IconHeart,
  IconHome,
  IconKey,
  IconMale,
  IconMedkit,
  IconMoney,
  IconMoneyBag,
  IconMug,
  IconShield,
  IconShip,
  IconSpinner,
  IconStar,
  IconTree,
  IconTrophy
]

#  Icon* = "\u"
# }}}

const
  MapFileExtension* = "grm"


# vim: et:ts=2:sw=2:fdm=marker
