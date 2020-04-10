import options
import tables

import nanovg


const
  TextVertAlignFactor* = 0.55

type
  UIStyle* = ref object
    backgroundColor*: Color
    backgroundImage*: string

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

proc rectI*(r1,c1, r2,c2: int): Rect[int] =
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
#    nkIndexed, nkCustomId, nkComment, nkIcon  # TODO reorder?
    nkComment, nkIndexed, nkCustomId, nkIcon  # TODO reorder?

  Note* = object
    text*: string
    case kind*: NoteKind
    of nkComment:  discard
    of nkIndexed:  index*, indexColor*: Natural
    of nkCustomId: customId*: string
    of nkIcon:     icon*: Natural

  # (0,0) is the top-left cell of the map
  Map* = ref object
    name*:        string
    rows*, cols*: Natural
    cells*:       seq[Cell]
    notes*:       Table[Natural, Note]

  # TODO introduce CellGrid because now the undomanager and the viewbuffer
  # copies the name, modified too
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
  SelectionBuffer* = object
    map*:       Map
    selection*: Selection

# {{{ Icons

const
  IconArrowDown* = "\uea36"
  IconArrowDownLeft* = "\uea37"
  IconArrowDownRight* = "\uea35"
  IconArrowLeft* = "\uea38"
  IconArrowRight* = "\uea34"
  IconArrowUp* = "\uea32"
  IconArrowUpLeft* = "\uea31"
  IconArrowUpRight* = "\uea33"
  IconArrowsAll* = "\uf047"
  IconArrowsHoriz* = "\ue911"
  IconArrowsVert* = "\ue912"
  IconAsterisk* = "\uf069"
  IconCheck* = "\ue900"
  IconCircle* = "\uf10c"
  IconCircleInv* = "\uf111"
  IconClose* = "\ue901"
  IconCog* = "\ue906"
  IconComment* = "\uf27b"
  IconCommentInv* = "\uf27a"
  IconCopy* = "\uf0c5"
  IconCrop* = "\uea57"
  IconCut* = "\uf0c4"
  IconEraser* = "\uf12d"
  IconFile* = "\uf0f6"
  IconFloppy* = "\uf0c7"
  IconFullscreen* = "\ue989"
  IconFullscreenExit* = "\ue98a"
  IconHand* = "\uf245"
  IconInfo* = "\uf05a"
  IconKeyboard* = "\ue955"
  IconMinus* = "\uea0b"
  IconMouse* = "\ue91d"
  IconNewFile* = "\uf15b"
  IconPaste* = "\uf0ea"
  IconPencil* = "\uf040"
  IconPin* = "\ue91c"
  IconPlus* = "\uea0a"
  IconRedo* = "\uf064"
  IconRotate* = "\uf01e"
  IconSelection* = "\ue90b"
  IconTiles* = "\ue950"
  IconTrash* = "\uf1f8"
  IconUndo* = "\uf112"
  IconWarning* = "\uf071"
  IconWindowClose* = "\uf2d3"
  IconWindowMaximise* = "\uf2d0"
  IconWindowMinimise* = "\uf2d1"
  IconWindowRestore* = "\uf2d2"
  IconZoomIn* = "\uf00e"
  IconZoomOut* = "\uf010"

  IconBed* = "\uf236"
  IconBomb* = "\uf1e2"
  IconBook* = "\ue923"
  IconBox* = "\uf097"
  IconBug* = "\ue909"
  IconBullseye* = "\uf140"
  IconDiamond* = "\uf219"
  IconEnter* = "\uea13"
  IconEquip* = "\ue92e"
  IconExit* = "\uea14"
  IconFlag* = "\uf024"
  IconFlask* = "\uf0c3"
  IconFort* = "\uf286"
  IconGraduation* = "\uf19d"
  IconHeart* = "\uf004"
  IconHome* = "\uf015"
  IconInstitution* = "\uf19c"
  IconKey* = "\uf084"
  IconMale* = "\uf183"
  IconMedkit* = "\uf0fa"
  IconMine* = "\ue90a"
  IconMoney* = "\ue93e"
  IconMug* = "\ue905"
  IconPaw* = "\uf1b0"
  IconPower* = "\ue9b5"
  IconShield* = "\uf132"
  IconShip* = "\ue944"
  IconSkull* = "\ue902"
  IconSpinner* = "\ue910"
  IconStairsDown* = "\ue90c"
  IconStairsUp* = "\ue90d"
  IconStar* = "\ue907"
  IconTree1* = "\uf1bb"
  IconTree2* = "\ue945"
  IconTrophy* = "\uf091"
  IconYinYang* = "\ue952"

const NoteIcons* = @[
  IconAsterisk,
  IconCircle,
  IconCircleInv,
  IconBullseye,
  IconStar,
  IconPower,

  IconSkull,
  IconBug,
  IconBomb,
  IconMine,
  IconPaw,

  IconBox,
  IconMedkit,
  IconHeart,
  IconFlask,
  IconKey,
  IconBook,
  IconEquip,
  IconShield,
  IconTrophy,
  IconFlag,
  IconMoney,
  IconDiamond,

  IconBed,
  IconMug,
  IconHome,
  IconFort,
  IconInstitution,
  IconGraduation,

  IconFloppy,
  IconMale,
  IconShip,
  IconTree1,
  IconTree2,
  IconYinYang,

  # Placeholders
  "1",
  "2",
  "3",
  "4",
  "5"
]

# vim: et:ts=2:sw=2:fdm=marker
