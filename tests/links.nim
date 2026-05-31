# links — migrated from src/domain/links.nim's when isMainModule block.

import std/options
import std/sets
import std/unittest

import common
import domain/links

suite "Links":
  test "set/get/del round-trip":
    let loc1 = Location(levelId: 0, row: 0, col: 0)
    let loc2 = Location(levelId: 0, row: 1, col: 0)
    let loc3 = Location(levelId: 0, row: 0, col: 1)
    var l = initLinks()

    check l.len == 0
    check not l.hasWithSrc(loc1)
    check not l.hasWithSrc(loc2)
    check not l.hasWithDest(loc1)
    check not l.hasWithDest(loc2)
    check l.getBySrc(loc1).isNone
    check l.getBySrc(loc2).isNone
    check l.getByDest(loc1).isNone
    check l.getByDest(loc2).isNone
    l.delBySrc(loc1)
    l.delByDest(loc1)

    l.set(loc1, loc2)
    check l.len == 1
    check l.hasWithSrc(loc1)
    check not l.hasWithSrc(loc2)
    check not l.hasWithDest(loc1)
    check l.hasWithDest(loc2)
    check l.getBySrc(loc1) == loc2.some
    check l.getBySrc(loc2).isNone
    check l.getByDest(loc1).isNone
    check l.getByDest(loc2) == [loc1].toHashSet.some

    l.set(loc3, loc2)
    check l.len == 2
    check l.hasWithSrc(loc3)
    check l.hasWithDest(loc2)
    check l.getBySrc(loc3) == loc2.some
    check l.getBySrc(loc3) == l.getBySrc(loc1)
    check l.getByDest(loc2) == [loc1, loc3].toHashSet.some

    l.delByDest(loc2)
    check l.len == 0

    l.set(loc1, loc2)
    l.set(loc3, loc2)
    check l.len == 2
    l.set(loc2, loc1)
    check l.len == 1
    check l.getBySrc(loc1).isNone
    check l.getBySrc(loc2) == loc1.some
    check l.getBySrc(loc3).isNone
    check l.getByDest(loc1) == [loc2].toHashSet.some
    check l.getByDest(loc2).isNone
    check l.getByDest(loc3).isNone

    l.delBySrc(loc2)
    check l.len == 0

    l.set(loc1, loc2)
    l.set(loc3, loc2)
    check l.len == 2
    l.set(loc3, loc1)
    check l.len == 1
    check l.getBySrc(loc1).isNone
    check l.getBySrc(loc2).isNone
    check l.getBySrc(loc3) == loc1.some
    check l.getByDest(loc1) == [loc3].toHashSet.some
    check l.getByDest(loc2).isNone
    check l.getByDest(loc3).isNone

    l.set(loc2, loc1)
    check l.len == 2
    l.delBySrc(loc3)
    check l.len == 1
    check l.getBySrc(loc1).isNone
    check l.getBySrc(loc2) == loc1.some
    check l.getBySrc(loc3).isNone
    check l.getByDest(loc1) == [loc2].toHashSet.some
    check l.getByDest(loc2).isNone
    check l.getByDest(loc3).isNone

# vim: et:ts=2:sw=2:fdm=marker
