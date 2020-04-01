import options
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
  RectType = SomeNumber | Natural

  # Rects are endpoint-exclusive
  Rect*[T: RectType] = object
    r1*,c1*, r2*,c2*: T

proc rectN*(r1,c1, r2,c2: Natural): Rect[Natural] =
  assert r1 < r2
  assert c1 < c2

  result.r1 = r1
  result.c1 = c1
  result.r2 = r2
  result.c2 = c2

proc intersect*[T: RectType](a, b: Rect[T]): Option[Rect[T]] =
  let
    r = max(a.r1, b.r1)
    c = max(a.c1, b.c1)
    nr = min(a.r1 + a.rows, b.r1 + b.rows)
    nc = min(a.c1 + a.cols, b.c1 + b.cols)

  if (nc >= c and nr >= r):
    some(Rect[T](
      r1: r,
      c1: c,
      r2: r + nr-r,
      c2: c + nc-c
    ))
  else: none(Rect[T])


func rows*[T: RectType](r: Rect[T]): T = r.r2 - r.r1
func cols*[T: RectType](r: Rect[T]): T = r.c2 - r.c1

func contains*[T: RectType](a: Rect[T], r,c: T): bool =
  r >= a.r1 and r < a.r2 and
  c >= a.c1 and c < a.c2


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
    name*:        string
    rows*, cols*: Natural
    cells*:       seq[Cell]
    notes*:       Table[Natural, Note]

  # TODO introduce CellGrid
  #CellGrid* = ref object
  #  cols*:  Natural
  #  rows*:  Natural
  #  cells*: seq[Cell]


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
  IconComment* = "\uf27b"
  IconCommentInv* = "\uf27a"
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
  IconNewFile* = "\uf15b"
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
