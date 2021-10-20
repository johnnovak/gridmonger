import options

import bitable
import common
import rect
import selection
import utils

export bitable


using
  l: Links
  vl: var Links

# {{{ initLinks()
proc initLinks*(): Links =
  result = initBiTable[Location, Location]()

# }}}

# {{{ dump*()
proc dump*(l) =
  for src, dest in l:
    echo "src: ", src, ", dest: ", dest

# }}}
# {{{ set*()
proc set*(vl; src, dest: Location) =
  vl[src] = dest

# }}}
# {{{ hasWithSrc*()
proc hasWithSrc*(l; src: Location): bool =
  l.hasKey(src)

# }}}
# {{{ hasWithDest*()
proc hasWithDest*(l; dest: Location): bool =
  l.hasVal(dest)

# }}}
# {{{ getBySrc*()
proc getBySrc*(l; src: Location): Option[Location] =
  l.getValByKey(src)

# }}}
# {{{ getByDest*()
proc getByDest*(l; dest: Location): Option[Location] =
  l.getKeyByVal(dest)

# }}}
# {{{ delBySrc*()
proc delBySrc*(vl; src: Location) =
  vl.delByKey(src)

# }}}
# {{{ delByDest*()
proc delByDest*(vl; dest: Location) =
  vl.delByVal(dest)

# }}}

# {{{ filterBySrcInRect*()
proc filterBySrcInRect*(l; level: Natural, rect: Rect[Natural],
                        sel: Option[Selection] = Selection.none): Links =
  result = initBiTable[Location, Location]()
  var src: Location
  src.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      src.row = r
      src.col = c

      let dest = l.getValByKey(src)
      if dest.isSome:
        if sel.isNone or (sel.isSome and sel.get[r,c]):
          result[src] = dest.get

# }}}
# {{{ filterByDestInRect*()
proc filterByDestInRect*(l; level: Natural, rect: Rect[Natural],
                         sel: Option[Selection] = Selection.none): Links =
  result = initBiTable[Location, Location]()
  var dest: Location
  dest.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      dest.row = r
      dest.col = c

      let src = l.getKeyByVal(dest)
      if src.isSome:
        if sel.isNone or (sel.isSome and sel.get[r,c]):
          result[src.get] = dest

# }}}
# {{{ filterByInRect*()
proc filterByInRect*(l; level: Natural, rect: Rect[Natural],
                     sel: Option[Selection] = Selection.none): Links =
  result = l.filterBySrcInRect(level, rect, sel)
  result.addAll(l.filterByDestInRect(level, rect, sel))

# }}}

# {{{ filterBySrcLevel*()
proc filterBySrcLevel*(l; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in l:
    if src.level == level:
      result[src] = dest

# }}}
# {{{ filterByDestLevel*()
proc filterByDestLevel*(l; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in l:
    if dest.level == level:
      result[src] = dest

# }}}
# {{{ filterByLevel*()
proc filterByLevel*(l; level: Natural): Links =
  result = l.filterBySrcLevel(level)
  result.addAll(l.filterByDestLevel(level))


# }}}

# {{{ remapLevelIndex*()
proc remapLevelIndex*(vl; oldIndex, newIndex: Natural) =
  var links = vl.filterByLevel(oldIndex)

  for src in links.keys: vl.delBySrc(src)

  for src, dest in links:
    var src = src
    var dest = dest

    if src.level  == oldIndex: src.level  = newIndex
    if dest.level == oldIndex: dest.level = newIndex

    vl.set(src, dest)


# }}}
# {{{ shiftLinksInLevel*()
proc shiftLinksInLevel*(l; level: Natural, rowOffs, colOffs: int,
                        levelRect: Rect[int]): Links =
  result = initLinks()

  for src, dest in l:
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

# }}}

# vim: et:ts=2:sw=2:fdm=marker
