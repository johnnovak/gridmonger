import options

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
  assert rect.x1 < s.cols
  assert rect.y1 < s.rows
  assert rect.x2 <= s.cols
  assert rect.y2 <= s.rows

  for r in rect.y1..<rect.y2:
    for c in rect.x1..<rect.x2:
      s[r,c] = v


proc fill*(s; v: bool) =
  let r = rectN(0, 0, s.cols, s.rows)
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
    srcCol   = srcRect.x1
    srcRow   = srcRect.y1
    srcCols  = max(src.cols - srcCol, 0)
    srcRows  = max(src.rows - srcRow, 0)
    destCols = max(dest.cols - destCol, 0)
    destRows = max(dest.rows - destRow, 0)

    cols = min(min(srcCols, destCols), srcRect.width)
    rows = min(min(srcRows, destRows), srcRect.height)

  for r in 0..<rows:
    for c in 0..<cols:
      dest[destRow+r, destCol+c] = src[srcRow+r, srcCol+c]


proc copyFrom*(dest: var Selection, src: Selection) =
  dest.copyFrom(destRow=0, destCol=0, src, rectN(0, 0, src.cols, src.rows))


proc newSelectionFrom*(src: Selection, rect: Rect[Natural]): Selection =
  assert rect.x1 < src.cols
  assert rect.y1 < src.rows
  assert rect.x2 <= src.cols
  assert rect.y2 <= src.rows

  var dest = new Selection
  dest.initSelection(rect.width, rect.height)
  dest.copyFrom(destRow=0, destCol=0, src, srcRect=rect)
  result = dest


proc newSelectionFrom*(s): Selection =
  newSelectionFrom(s, rectN(0, 0, s.cols, s.rows))


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

    return rectN(c1, r1, c2+1, r2+1).some
  else:
    return Rect[Natural].none


# vim: et:ts=2:sw=2:fdm=marker
