import std/options

type
  RectType = SomeInteger | Natural

  # Rects are endpoint-exclusive
  Rect*[T: RectType] = object
    r1*,c1*, r2*,c2*: T

# {{{ Getters
func rows*[T: RectType](r: Rect[T]): T = r.r2 - r.r1
func cols*[T: RectType](r: Rect[T]): T = r.c2 - r.c1

func x1*[T: RectType](r: Rect[T]): T = r.c1
func y1*[T: RectType](r: Rect[T]): T = r.r1

func x2*[T: RectType](r: Rect[T]): T = r.c2
func y2*[T: RectType](r: Rect[T]): T = r.r2

func w*[T: RectType](r: Rect[T]): T = r.cols
func h*[T: RectType](r: Rect[T]): T = r.rows

# }}}
# {{{ Setters
func `x1=`*[T: RectType](r: var Rect[T], x1: T) = r.c1 = x1
func `y1=`*[T: RectType](r: var Rect[T], y1: T) = r.r1 = y1

func `x2=`*[T: RectType](r: var Rect[T], x2: T) = r.c2 = x2
func `y2=`*[T: RectType](r: var Rect[T], y2: T) = r.r2 = y2

# }}}

# {{{ rect*()
proc rect*[T: RectType](r1,c1, r2,c2: T): Rect[T] =
  assert r1 < r2
  assert c1 < c2

  result.r1 = r1
  result.c1 = c1
  result.r2 = r2
  result.c2 = c2

# }}}
# {{{ rectN*()
proc rectN*(r1,c1, r2,c2: Natural): Rect[Natural] =
  rect(r1,c1, r2,c2)

# }}}
# {{{ rectI*()
proc rectI*(r1,c1, r2,c2: int): Rect[int] =
  rect(r1,c1, r2,c2)

# }}}
# {{{ coordRect*()
proc coordRect*(x1,y1, x2,y2: int): Rect[int] =
  rect(y1,x1, y2,x2)

# }}}

# {{{ area*()
func area*[T: RectType](r: Rect[T]): T =
  r.w * r.h

# }}}
# {{{ intersect*()
proc intersect*[T: RectType](a, b: Rect[T]): Option[Rect[T]] =
  let
    r = max(a.r1, b.r1)
    c = max(a.c1, b.c1)
    nr = min(a.r1 + a.rows, b.r1 + b.rows)
    nc = min(a.c1 + a.cols, b.c1 + b.cols)

  if (nc > c and nr > r):
    let
      r1 = r
      c1 = c
      r2 = r + nr-r
      c2 = c + nc-c

    rect(r1,c1, r2,c2).some

  else:
    none(Rect[T])

# }}}
# {{{ overlaps*()
proc overlaps*[T: RectType](a, b: Rect[T]): bool =
  a.intersect(b).isSome

# }}}
# {{{ contains*()
func contains*[T: RectType](a: Rect[T], r,c: T): bool =
  r >= a.r1 and r < a.r2 and
  c >= a.c1 and c < a.c2

func contains*[T: RectType](a, b: Rect[T]): bool =
  a.contains(b.r1, b.c1) and a.contains(b.r2-1, b.c2-1)

# }}}
# {{{ expand*()
proc expand*[T: RectType](a: var Rect[T], r,c: T) =
  if   r <  a.r1: a.r1 = r
  elif r >= a.r2: a.r2 = r+1

  if   c <  a.c1: a.c1 = c
  elif c >= a.c2: a.c2 = c+1

# }}}
# {{{ shiftHoriz*()
proc shiftHoriz*[T: RectType](a: var Rect[T], d: int) =
  a.c1 += d
  a.c2 += d

# }}}
# {{{ shiftVert*()
proc shiftVert*[T: RectType](a: var Rect[T], d: int) =
  a.r1 += d
  a.r2 += d

# }}}

# {{{ Tests

when isMainModule:
  block:  # intersect
    let a = rect(-5,2, -1,7)

    # fully overlapping
    assert a.intersect(a) == a.some

    # partially overlapping
    assert a.intersect(rect(-25,5, -2,20)) == rectI(-5,5, -2,7).some

    # not overlapping
    assert a.intersect(rect(-25,2, -21,7)) == Rect[int].none

    # touching
    assert a.intersect(rect(-5,7, -3,9)) == Rect[int].none

#  }}}

# vim: et:ts=2:sw=2:fdm=marker
