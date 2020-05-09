import options

import bitable
import common
import rect
import selection

export bitable


using l: Links
using vl: var Links

proc initLinks*(): Links =
  result = initBiTable[Location, Location]()

proc dump*(l) =
  for src, dest in l.pairs:
    echo "src: ", src, ", dest: ", dest

proc set*(l: var Links; src, dest: Location) =
  l[src] = dest

proc hasWithSrc*(l; src: Location): bool =
  l.hasKey(src)

proc hasWithDest*(l; dest: Location): bool =
  l.hasVal(dest)

proc getBySrc*(l; src: Location): Location =
  l.getValByKey(src)

proc getByDest*(l; dest: Location): Location =
  l.getKeyByVal(dest)

proc delBySrc*(l: var Links; src: Location) =
  l.delByKey(src)

proc delByDest*(l: var Links; dest: Location) =
  l.delByVal(dest)

proc filterBySrcInRect*(l; level: Natural, rect: Rect[Natural],
                        sel: Option[Selection] = Selection.none): Links =
  result = initBiTable[Location, Location]()
  var src: Location
  src.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      src.row = r
      src.col = c
      if l.hasKey(src) and (sel.isNone or (sel.isSome and sel.get[r,c])):
        let dest = l.getValByKey(src)
        result[src] = dest


proc filterByDestInRect*(l; level: Natural, rect: Rect[Natural],
                         sel: Option[Selection] = Selection.none): Links =
  result = initBiTable[Location, Location]()
  var dest: Location
  dest.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      dest.row = r
      dest.col = c
      if l.hasVal(dest) and (sel.isNone or (sel.isSome and sel.get[r,c])):
        let src = l.getKeyByVal(dest)
        result[src] = dest


proc filterByInRect*(l; level: Natural, rect: Rect[Natural],
                     sel: Option[Selection] = Selection.none): Links =
  result = l.filterBySrcInRect(level, rect, sel)
  result.addAll(l.filterByDestInRect(level, rect, sel))


proc filterBySrcLevel*(l; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in l.pairs:
    if src.level == level:
      result[src] = dest

proc filterByDestLevel*(l; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in l.pairs:
    if dest.level == level:
      result[src] = dest

proc filterByLevel*(l; level: Natural): Links =
  result = l.filterBySrcLevel(level)
  result.addAll(l.filterByDestLevel(level))


# vim: et:ts=2:sw=2:fdm=marker
