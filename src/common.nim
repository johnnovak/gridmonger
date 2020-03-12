import options
import tables

import nanovg
import glfw

import undomanager


type
  Orientation* = enum
    Horiz = (0, "horiz")
    Vert  = (1, "vert")

  Direction* = enum
    North = (0, "North")
    East  = (1, "East")
    South = (2, "South")
    West  = (3, "West")


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
  Ground* = enum
    gNone                = (  0, "blank"),
    gEmpty               = (  1, "empty"),
    gClosedDoor          = (  2, "closed door"),
    gOpenDoor            = (  3, "open door"),
    gPressurePlate       = (  4, "pressure plate"),
    gHiddenPressurePlate = (  5, "hidden pressure plate"),
    gClosedPit           = (  6, "closed pit"),
    gOpenPit             = (  7, "open pit"),
    gHiddenPit           = (  8, "hidden pit"),
    gCeilingPit          = (  9, "ceiling pit"),
    gStairsDown          = ( 10, "stairs down"),
    gStairsUp            = ( 11, "stairs up"),
    gSpinner             = ( 12, "spinner"),
    gTeleport            = ( 13, "teleport"),
    gCustom              = (255, "custom")

  Wall* = enum
    wNone          = ( 0, "none"),
    wWall          = ( 1, "wall"),
    wIllusoryWall  = ( 2, "illusory wall"),
    wInvisibleWall = ( 3, "invisible wall")
    wOpenDoor      = ( 4, "closed door"),
    wClosedDoor    = ( 5, "open door"),
    wSecretDoor    = ( 6, "secret door"),
    wLever         = ( 7, "statue")
    wNiche         = ( 8, "niche")
    wStatue        = ( 9, "statue")

  Cell* = object
    ground*:            Ground
    groundOrientation*: Orientation
    wallN*, wallW*:     Wall
    customChar*:        char
    # TODO store separately
#    notes*:            string


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


type
  # (0,0) is the top-left cell of the selection
  Selection* = ref object
    cols*:  Natural
    rows*:  Natural
    cells*: seq[bool]


type
  # TODO make ref?
  SelectionRect* = object
    x0*, y0*:   Natural
    rect*:      Rect[Natural]
    fillValue*: bool

  # TODO make ref?
  CopyBuffer* = object
    map*:       Map
    selection*: Selection

