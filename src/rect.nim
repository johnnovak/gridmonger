import options

type
  RectType = SomeInteger | Natural

  # Rects are endpoint-exclusive
  Rect*[T: RectType] = object
    r1*,c1*, r2*,c2*: T

# {{{ rectN*()
proc rectN*(r1,c1, r2,c2: Natural): Rect[Natural] =
  assert r1 < r2
  assert c1 < c2

  result.r1 = r1
  result.c1 = c1
  result.r2 = r2
  result.c2 = c2

# }}}
# {{{ rectI*()
proc rectI*(r1,c1, r2,c2: int): Rect[int] =
  assert r1 < r2
  assert c1 < c2

  result.r1 = r1
  result.c1 = c1
  result.r2 = r2
  result.c2 = c2

# }}}

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

# {{{ intersect*()
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

# vim: et:ts=2:sw=2:fdm=marker
