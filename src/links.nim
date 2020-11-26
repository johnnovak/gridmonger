import options

import koi/rect

import bitable
import common
import selection
import utils

export bitable


using
  l: Links
  vl: var Links

proc initLinks*(): Links =
  result = initBiTable[Location, Location]()

proc dump*(l) =
  for src, dest in l.pairs:
    echo "src: ", src, ", dest: ", dest

proc set*(vl; src, dest: Location) =
  vl[src] = dest

proc hasWithSrc*(l; src: Location): bool =
  l.hasKey(src)

proc hasWithDest*(l; dest: Location): bool =
  l.hasVal(dest)

proc getBySrc*(l; src: Location): Location =
  l.getValByKey(src)

proc getByDest*(l; dest: Location): Location =
  l.getKeyByVal(dest)

proc delBySrc*(vl; src: Location) =
  vl.delByKey(src)

proc delByDest*(vl; dest: Location) =
  vl.delByVal(dest)

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


proc remapLevelIndex*(vl; oldIndex, newIndex: Natural) =
  var links = vl.filterByLevel(oldIndex)

  for src in links.keys: vl.delBySrc(src)

  for src, dest in links.pairs:
    var src = src
    var dest = dest
    if src.level  == oldIndex: src.level  = newIndex
    if dest.level == oldIndex: dest.level = newIndex
    vl.set(src, dest)


proc shiftLinksInLevel*(l; level: Natural, rowOffs, colOffs: int,
                        levelRect: Rect[int]): Links =
  result = initLinks()

  for src, dest in l.pairs:
    var src = src
    var dest = dest

    if src.level == level:
      var r = src.row.int + rowOffs
      var c = src.col.int + colOffs
      if levelRect.contains(r,c):
        src.row = r
        src.col = c
      else:
        continue

    if dest.level == level:
      var r = dest.row.int + rowOffs
      var c = dest.col.int + colOffs
      if levelRect.contains(r,c):
        dest.row = r
        dest.col = c
      else:
        continue

    result.set(src, dest)


# vim: et:ts=2:sw=2:fdm=marker
