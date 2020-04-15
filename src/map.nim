import algorithm
import sequtils
import strformat
import tables

import bitable
import common


using m: Map

proc newMap*(name: string): Map =
  var m = new Map
  m.name = name
  m.levels = @[]
  m.links = initBiTable[Location, Location]()

  m.sortedLevelNames = @[]
  m.sortedLevelIdxToLevelIdx = initTable[Natural, Natural]()
  result = m


proc refreshSortedLevelNames*(m) =
  proc mkSortedLevelName(l: Level): string =
    let elevation = if l.elevation == 0: "G" else: $l.elevation
    let dash = "\u2013"
    if l.levelName == "":
      fmt"{l.locationName} ({elevation})"
    else:
      fmt"{l.locationName} {dash} {l.levelName} ({elevation})"

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
  # TODO recalc links
  m.levels.del(levelIdx)
  m.refreshSortedLevelNames()


# vim: et:ts=2:sw=2:fdm=marker
