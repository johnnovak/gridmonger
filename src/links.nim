import std/math
import std/options
import std/sets
import std/tables

import common
import rect
import selection
import utils


const DefaultInitialSize = 64

using
  l: Links
  vl: var Links

# {{{ initLinks*()
proc initLinks*(initialSize: Natural = DefaultInitialSize): Links =
  result.srcToDest  = initOrderedTable[Location, Location](initialSize)
  result.destToSrcs = initOrderedTable[Location, HashSet[Location]](initialSize)

# }}}

# {{{ len*()
proc len*(l): Natural =
  l.srcToDest.len

# }}}

# {{{ sources*()
iterator sources*(l): Location =
  for src in l.srcToDest.keys:
    yield src

# }}}

# {{{ pairs*()
iterator pairs*(l): tuple[src, dest: Location] =
  for src, dest in l.srcToDest:
    yield (src, dest)

# }}}

# {{{ dump*()
proc dump*(l) =
  for src, dest in l:
    echo "src: ", src, ", dest: ", dest

# }}}
# {{{ debugSanitise*()
proc debugSanitise*(l) =
  when defined(DEBUG):
    var dump = false
    for src, dest in l:
      if src.levelId > 1000 or dest.levelId > 1000:
        dump = true
        break

    if dump:
      echo "========================================================="
      echo "Stack trace:\n" & getStackTrace()
      echo "---------------------------------------------------------"
      l.dump

# }}}
# {{{ delBySrc*()
proc delBySrc*(vl; src: Location) =
  if src notin vl.srcToDest:
    return
  let dest = vl.srcToDest[src]
  vl.destToSrcs[dest].excl(src)
  if vl.destToSrcs[dest].len == 0:
    vl.destToSrcs.del(dest)
  vl.srcToDest.del(src)

# }}}
# {{{ delByDest*()
proc delByDest*(vl; dest: Location) =
  if dest notin vl.destToSrcs:
    return
  let srcs = vl.destToSrcs[dest]
  for src in srcs:
    vl.delBySrc(src)
  vl.destToSrcs.del(dest)

# }}}
# {{{ set*()
proc set*(vl; src, dest: Location) =
  # Edge case: support for overwriting existing link
  # (delete existing links originating from src)
  vl.delBySrc(src)
  vl.delByDest(src)
  # Clear dest only if it's a source
  vl.delBySrc(dest)
  vl.srcToDest[src] = dest
  vl.destToSrcs.mgetOrPut(dest, initHashSet[Location]()).incl(src)

# }}}
# {{{ hasWithSrc*()
proc hasWithSrc*(l; src: Location): bool =
  l.srcToDest.hasKey(src)

# }}}
# {{{ hasWithDest*()
proc hasWithDest*(l; dest: Location): bool =
  l.destToSrcs.hasKey(dest)

# }}}
# {{{ getBySrc*()
proc getBySrc*(l; src: Location): Option[Location] =
  if l.hasWithSrc(src):
    result = l.srcToDest[src].some

# }}}
# {{{ getByDest*()
proc getByDest*(l; dest: Location): Option[HashSet[Location]] =
  if l.hasWithDest(dest):
    result = l.destToSrcs[dest].some

# }}}

# {{{ filterBySrcInRect*()
proc filterBySrcInRect*(l; levelId: Natural, rect: Rect[Natural],
                        sel: Option[Selection] = Selection.none): Links =
  result = initLinks()
  var src: Location
  src.levelId = levelId

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      src.row = r
      src.col = c

      let dest = l.getBySrc(src)
      if dest.isSome:
        if sel.isNone or (sel.isSome and sel.get[r,c]):
          result.set(src, dest.get)

# }}}
# {{{ filterByDestInRect*()
proc filterByDestInRect*(l; levelId: Natural, rect: Rect[Natural],
                         sel: Option[Selection] = Selection.none): Links =
  result = initLinks()
  var dest: Location
  dest.levelId = levelId

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      dest.row = r
      dest.col = c

      let srcs = l.getByDest(dest)
      if srcs.isSome:
        if sel.isNone or (sel.isSome and sel.get[r,c]):
          for src in srcs.get:
            result.set(src, dest)

# }}}

# {{{ addAll*()
proc addAll*(vl, l) =
  for src, dest in l:
    vl.set(src, dest)

# }}}

# {{{ filterByInRect*()
proc filterByInRect*(l; levelId: Natural, rect: Rect[Natural],
                     sel: Option[Selection] = Selection.none): Links =
  result = l.filterBySrcInRect(levelId, rect, sel)
  result.addAll(l.filterByDestInRect(levelId, rect, sel))

# }}}

# {{{ filterBySrcLevel*()
proc filterBySrcLevel*(l; levelId: Natural): Links =
  result = initLinks()
  for src, dest in l:
    if src.levelId == levelId:
      result.set(src, dest)

# }}}
# {{{ filterByDestLevel*()
proc filterByDestLevel*(l; levelId: Natural): Links =
  result = initLinks()
  for src, dest in l:
    if dest.levelId == levelId:
      result.set(src, dest)

# }}}
# {{{ filterByLevel*()
proc filterByLevel*(l; levelId: Natural): Links =
  result = l.filterBySrcLevel(levelId)
  result.addAll(l.filterByDestLevel(levelId))


# }}}

# {{{ shiftLinksInLevel*()
proc shiftLinksInLevel*(l; levelId: Natural, rowOffs, colOffs: int,
                        levelRect: Rect[int], wraparound: bool): Links =
  result = initLinks()

  for src, dest in l:
    var src = src
    var dest = dest

    if src.levelId == levelId:
      var r = src.row.int + rowOffs
      var c = src.col.int + colOffs

      if wraparound:
        src.row = r.floorMod(levelRect.rows)
        src.col = c.floorMod(levelRect.cols)
      else:
        if levelRect.contains(r,c):
          src.row = r
          src.col = c
        else:
          continue

    if dest.levelId == levelId:
      var r = dest.row.int + rowOffs
      var c = dest.col.int + colOffs

      if wraparound:
        dest.row = r.floorMod(levelRect.rows)
        dest.col = c.floorMod(levelRect.cols)
      else:
        if levelRect.contains(r,c):
          dest.row = r
          dest.col = c
        else:
          continue

    result.set(src, dest)

# }}}

# {{{ Tests
when isMainModule:
  let loc1 = Location(levelId: 0, row: 0, col: 0)
  let loc2 = Location(levelId: 0, row: 1, col: 0)
  let loc3 = Location(levelId: 0, row: 0, col: 1)
  var l = initLinks()

  assert l.len == 0
  assert not l.hasWithSrc(loc1)
  assert not l.hasWithSrc(loc2)
  assert not l.hasWithDest(loc1)
  assert not l.hasWithDest(loc2)
  assert l.getBySrc(loc1).isNone
  assert l.getBySrc(loc2).isNone
  assert l.getByDest(loc1).isNone
  assert l.getByDest(loc2).isNone
  l.delBySrc(loc1)
  l.delByDest(loc1)

  l.set(loc1, loc2)
  assert l.len == 1
  assert l.hasWithSrc(loc1)
  assert not l.hasWithSrc(loc2)
  assert not l.hasWithDest(loc1)
  assert l.hasWithDest(loc2)
  assert l.getBySrc(loc1) == loc2.some
  assert l.getBySrc(loc2).isNone
  assert l.getByDest(loc1).isNone
  assert l.getByDest(loc2) == [loc1].toHashSet.some

  l.set(loc3, loc2)
  assert l.len == 2
  assert l.hasWithSrc(loc3)
  assert l.hasWithDest(loc2)
  assert l.getBySrc(loc3) == loc2.some
  assert l.getBySrc(loc3) == l.getBySrc(loc1)
  assert l.getByDest(loc2) == [loc1, loc3].toHashSet.some

  l.delByDest(loc2)
  assert l.len == 0

  l.set(loc1, loc2)
  l.set(loc3, loc2)
  assert l.len == 2
  l.set(loc2, loc1)
  assert l.len == 1
  assert l.getBySrc(loc1).isNone
  assert l.getBySrc(loc2) == loc1.some
  assert l.getBySrc(loc3).isNone
  assert l.getByDest(loc1) == [loc2].toHashSet.some
  assert l.getByDest(loc2).isNone
  assert l.getByDest(loc3).isNone

  l.delBySrc(loc2)
  assert l.len == 0

  l.set(loc1, loc2)
  l.set(loc3, loc2)
  assert l.len == 2
  l.set(loc3, loc1)
  assert l.len == 1
  assert l.getBySrc(loc1).isNone
  assert l.getBySrc(loc2).isNone
  assert l.getBySrc(loc3) == loc1.some
  assert l.getByDest(loc1) == [loc3].toHashSet.some
  assert l.getByDest(loc2).isNone
  assert l.getByDest(loc3).isNone

  l.set(loc2, loc1)
  assert l.len == 2
  l.delBySrc(loc3)
  assert l.len == 1
  assert l.getBySrc(loc1).isNone
  assert l.getBySrc(loc2) == loc1.some
  assert l.getBySrc(loc3).isNone
  assert l.getByDest(loc1) == [loc2].toHashSet.some
  assert l.getByDest(loc2).isNone
  assert l.getByDest(loc3).isNone
# }}}

# vim: et:ts=2:sw=2:fdm=marker
