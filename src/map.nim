import algorithm
import sequtils
import strformat
import tables

import bitable
import common
import level
import rect


using m: Map

proc newMap*(name: string): Map =
  var m = new Map
  m.name = name
  m.levels = @[]
  m.links = initBiTable[Location, Location]()

  m.sortedLevelNames = @[]
  m.sortedLevelIdxToLevelIdx = initTable[Natural, Natural]()
  result = m


proc findSortedLevelIdxByLevelIdx*(m; i: Natural): Natural =
  for sortedLevelIdx, levelIdx in m.sortedLevelIdxToLevelIdx.pairs:
    if i == levelIdx:
      return sortedLevelIdx
  assert false


proc refreshSortedLevelNames*(m) =
  proc mkSortedLevelName(l: Level): string =
    let elevation = if l.elevation == 0: "G" else: $l.elevation
    if l.levelName == "":
      fmt"{l.locationName} ({elevation})"
    else:
      fmt"{l.locationName} {EnDash} {l.levelName} ({elevation})"

  var sortedLevelsWithIndex = zip(m.levels, (0..m.levels.high).toSeq)
  sortedLevelsWithIndex.sort(
    proc (a, b: tuple[level: Level, idx: int]): int =
      var c = cmp(a.level.locationName, b.level.locationName)
      if c != 0: return c

      c = cmp(b.level.elevation, a.level.elevation)
      if c != 0: return c

      # TODO ensure two levels with the same elevation & location name
      # cannot have the same level name
      return cmp(a.level.levelName, b.level.levelName)
  )
  m.sortedLevelNames = newSeqOfCap[string](m.levels.len)
  m.sortedLevelIdxToLevelIdx.clear()

  for (sortedIdx, levelWithIdx) in sortedLevelsWithIndex.pairs:
    let (level, levelIdx) = levelWithIdx
    m.sortedLevelNames.add(mkSortedLevelName(level))
    m.sortedLevelIdxToLevelIdx[sortedIdx] = levelIdx


proc addLevel*(m; l: Level) =
  m.levels.add(l)
  m.refreshSortedLevelNames()

proc delLevel*(m; levelIdx: Natural) =
  # TODO update links
  m.levels.del(levelIdx)
  m.refreshSortedLevelNames()


proc delLinkBySrc*(m; src: Location) =
  m.links.delByKey(src)

proc delLinkByDest*(m; dest: Location) =
  m.links.delByVal(dest)

proc getLinksFromRect*(m; level: Natural,
                       rect: Rect[Natural]): Links =
  result = initBiTable[Location, Location]()
  var src: Location
  src.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      src.row = r
      src.col = c
      if m.links.hasKey(src):
        result[src] = m.links.getValByKey(src)


proc getLinksToRect*(m; level: Natural,
                     rect: Rect[Natural]): Links =
  result = initBiTable[Location, Location]()
  var dest: Location
  dest.level = level

  for r in rect.r1..<rect.r2:
    for c in rect.c1..<rect.c2:
      dest.row = r
      dest.col = c
      if m.links.hasVal(dest):
        result[m.links.getKeyByVal(dest)] = dest


proc getLinksFromLevel*(m; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in m.links.pairs:
    if src.level == level:
      result[src] = dest

proc getLinksToLevel*(m; level: Natural): Links =
  result = initBiTable[Location, Location]()
  for src, dest in m.links.pairs:
    if dest.level == level:
      result[src] = dest


proc getFloor*(m; loc: Location): Floor {.inline.} =
  m.levels[loc.level].getFloor(loc.row, loc.col)

proc isFloorEmpty*(m; loc: Location): bool {.inline.} =
  m.levels[loc.level].isFloorEmpty(loc.row, loc.col)

proc setFloor*(m; loc: Location, f: Floor) =
  m.levels[loc.level].setFloor(loc.row, loc.col, f)
  m.delLinkBySrc(loc)
  m.delLinkByDest(loc)

proc getFloorOrientation*(m; loc: Location): Orientation {.inline.} =
  m.levels[loc.level].getFloorOrientation(loc.row, loc.col)

proc setFloorOrientation*(m; loc: Location, ot: Orientation) =
  m.levels[loc.level].setFloorOrientation(loc.row, loc.col, ot)

proc guessFloorOrientation*(m; loc: Location): Orientation =
  m.levels[loc.level].guessFloorOrientation(loc.row, loc.col)


proc getWall*(m; loc: Location, dir: CardinalDir): Wall {.inline.} =
  m.levels[loc.level].getWall(loc.row, loc.col, dir)

proc canSetWall*(m; loc: Location, dir: CardinalDir): bool =
  m.levels[loc.level].canSetWall(loc.row, loc.col, dir)

proc setWall*(m; loc: Location, dir: CardinalDir, w: Wall) =
  m.levels[loc.level].setWall(loc.row, loc.col, dir, w)

#proc eraseOrphanedWalls*(m; loc: Location) =
#  m.levels[loc.level].eraseOrphanedWalls(loc.row, loc.col)

proc eraseCellWalls*(m; loc: Location) =
  m.levels[loc.level].eraseCellWalls(loc.row, loc.col)

proc eraseCell*(m; loc: Location) =
  m.levels[loc.level].eraseCell(loc.row, loc.col)
  m.delLinkBySrc(loc)
  m.delLinkByDest(loc)

#proc paste*(l; destRow, destCol: int, src: Level, sel: Selection) =

#proc copyFrom*(l; destRow, destCol: Natural,

#proc newLevelFrom*(src: Level, rect: Rect[Natural],

#proc newLevelFrom*(l): Level =

#proc resize*(l; newRows, newCols: Natural, align: Direction): Level =

# vim: et:ts=2:sw=2:fdm=marker
