import std/options
import std/unittest

import utils/rect

suite "Rect intersect":
  test "fully/partially/non-overlapping/touching":
    let a = rect(-5,2, -1,7)

    # fully overlapping
    check a.intersect(a) == a.some

    # partially overlapping
    check a.intersect(rect(-25,5, -2,20)) == rectI(-5,5, -2,7).some

    # not overlapping
    check a.intersect(rect(-25,2, -21,7)) == Rect[int].none

    # touching
    check a.intersect(rect(-5,7, -3,9)) == Rect[int].none

# vim: et:ts=2:sw=2:fdm=marker
