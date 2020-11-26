import options

import koi/rect

import common


using s: Selection

proc `[]=`*(s; r,c: Natural, v: bool) =
  assert r < s.rows
  assert c < s.cols
  s.cells[r*s.cols + c] = v

proc `[]`*(s; r,c: Natural): bool =
  assert r < s.rows
  assert c < s.cols
  result = s.cells[r*s.cols + c]


proc fill*(s; rect: Rect[Natural], v: bool) =
  assert rect.r1 < s.rows
  assert rect.c1 < s.cols
  assert rect.r2 <= s.rows
  assert rect.c2 <= s.cols

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      s[r,c] = v


proc fill*(s; v: bool) =
  let r = rectN(0, 0, s.rows, s.cols)
  s.fill(r, v)

proc initSelection(s; rows, cols: Natural) =
  s.rows = rows
  s.cols = cols
  newSeq(s.cells, s.rows * s.cols)

proc newSelection*(rows, cols: Natural): Selection =
  var s = new Selection
  s.initSelection(rows, cols)
  result = s


proc copyFrom*(dest: var Selection, destRow, destCol: Natural,
               src: Selection, srcRect: Rect[Natural]) =
  let
    srcRow   = srcRect.r1
    srcCol   = srcRect.c1
    srcRows  = max(src.rows - srcRow, 0)
    srcCols  = max(src.cols - srcCol, 0)
    destRows = max(dest.rows - destRow, 0)
    destCols = max(dest.cols - destCol, 0)

    rows = min(min(srcRows, destRows), srcRect.rows)
    cols = min(min(srcCols, destCols), srcRect.cols)

  for r in 0..<rows:
    for c in 0..<cols:
      dest[destRow+r, destCol+c] = src[srcRow+r, srcCol+c]


proc copyFrom*(dest: var Selection, src: Selection) =
  dest.copyFrom(destRow=0, destCol=0, src, rectN(0, 0, src.rows, src.cols))


proc newSelectionFrom*(src: Selection, rect: Rect[Natural]): Selection =
  assert rect.r1 < src.rows
  assert rect.c1 < src.cols
  assert rect.r2 <= src.rows
  assert rect.c2 <= src.cols

  var dest = new Selection
  dest.initSelection(rect.rows, rect.cols)
  dest.copyFrom(destRow=0, destCol=0, src, srcRect=rect)
  result = dest


proc newSelectionFrom*(s): Selection =
  newSelectionFrom(s, rectN(0, 0, s.rows, s.cols))


proc boundingBox*(s): Option[Rect[Natural]] =
  proc isRowEmpty(r: Natural): bool =
    for c in 0..<s.cols:
      if s[r,c]: return false
    return true

  proc isColEmpty(c: Natural): bool =
    for r in 0..<s.rows:
      if s[r,c]: return false
    return true

  var
    r1 = 0
    c1 = 0
    r2 = s.rows-1
    c2 = s.cols-1

  while r1 < s.rows and isRowEmpty(r1): inc(r1)

  if r1 < s.rows-1:
    while c1 < s.cols and isColEmpty(c1): inc(c1)
    while c2 > 0      and isColEmpty(c2): dec(c2)
    while r2 > 0      and isRowEmpty(r2): dec(r2)

    return rectN(r1, c1, r2+1, c2+1).some
  else:
    return Rect[Natural].none


proc isNeighbourCellEmpty*(s; r,c: Natural, dir: CardinalDir): bool =
  assert r < s.rows
  assert c < s.cols

  case dir
  of dirN: result = r == 0        or not s[r-1, c  ]
  of dirE: result = c == s.cols-1 or not s[  r, c+1]
  of dirS: result = r == s.rows-1 or not s[r+1, c  ]
  of dirW: result = c == 0        or not s[  r, c-1]


# vim: et:ts=2:sw=2:fdm=marker
