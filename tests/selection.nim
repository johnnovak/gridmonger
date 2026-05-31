# selection — migrated from src/domain/selection.nim's `when isMainModule:`
# block. Test the selection bounding-box behavior.

import std/options
import std/unittest

import common
import domain/selection
import utils/rect


suite "Selection bounding box":
  test "tracks min/max of marked cells":
    var s = newSelection(3, 4)
    check s.boundingBox == Rect[Natural].none

    s[0,0] = true
    check s.boundingBox == rectN(0,0, 1,1).some

    s[0,0] = false
    s[1,1] = true
    check s.boundingBox == rectN(1,1, 2,2).some

    s[1,2] = true
    check s.boundingBox == rectN(1,1, 2,3).some

    s[2,3] = true
    check s.boundingBox == rectN(1,1, 3,4).some

  test "fill(false) clears, fill(true) covers all":
    var s = newSelection(3, 4)
    s.fill(true)
    check s.boundingBox == rectN(0,0, 3,4).some

    s.fill(false)
    check s.boundingBox == Rect[Natural].none

  test "single-cell bounding box at various positions":
    var s = newSelection(3, 4)

    s.fill(false)
    s[2,2] = true
    check s.boundingBox == rectN(2,2, 3,3).some

    s.fill(false)
    s[2,3] = true
    check s.boundingBox == rectN(2,3, 3,4).some

    s.fill(false)
    s[0,3] = true
    check s.boundingBox == rectN(0,3, 1,4).some


# vim: et:ts=2:sw=2:fdm=marker
