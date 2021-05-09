import algorithm
import options
import sequtils
import strformat

import common
import level
import links
import rect
import regions
import tables
import utils
import with


using m: Map

# {{{ newMap*()
proc newMap*(name: string): Map =
  var m = new Map
  m.name = name
  m.levels = @[]
  m.links = initLinks()

  m.coordOpts = CoordinateOptions(
    origin:      coNorthWest,
    rowStyle:    csNumber,
    columnStyle: csNumber,
    rowStart:    1,
    columnStart: 1
  )

  m.sortedLevelNames = @[]
  m.sortedLevelIdxToLevelIdx = initTable[Natural, Natural]()

  result = m

# }}}

# {{{ findSortedLevelIdxByLevelIdx*()
proc findSortedLevelIdxByLevelIdx*(m; i: Natural): Natural =
  for sortedLevelIdx, levelIdx in m.sortedLevelIdxToLevelIdx.pairs:
    if i == levelIdx:
      return sortedLevelIdx
  assert false

# }}}
# {{{ refreshSortedLevelNames*()
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

      return cmp(a.level.levelName, b.level.levelName)
  )
  m.sortedLevelNames = newSeqOfCap[string](m.levels.len)
  m.sortedLevelIdxToLevelIdx.clear()

  for (sortedIdx, levelWithIdx) in sortedLevelsWithIndex.pairs:
    let (level, levelIdx) = levelWithIdx
    m.sortedLevelNames.add(mkSortedLevelName(level))
    m.sortedLevelIdxToLevelIdx[sortedIdx] = levelIdx

# }}}

# {{{ addLevel*()
proc addLevel*(m; l: Level) =
  m.levels.add(l)
  m.refreshSortedLevelNames()

# }}}
# {{{ delLevel*()
proc delLevel*(m; levelIdx: Natural) =
  m.levels.del(levelIdx)
  m.refreshSortedLevelNames()

# }}}

# {{{ hasNote*()
proc hasNote*(m; loc: Location): bool {.inline.} =
  m.levels[loc.level].hasNote(loc.row, loc.col)

# }}}
# {{{ getNote*()
proc getNote*(m; loc: Location): Option[Annotation] {.inline.} =
  m.levels[loc.level].getNote(loc.row, loc.col)

# }}}
# {{{ hasLabel*()
proc hasLabel*(m; loc: Location): bool {.inline.} =
  m.levels[loc.level].hasLabel(loc.row, loc.col)

# }}}
# {{{ getLabel*()
proc getLabel*(m; loc: Location): Option[Annotation] {.inline.} =
  m.levels[loc.level].getLabel(loc.row, loc.col)

# }}}

# {{{ eraseCellLinks*()
proc eraseCellLinks*(m; loc: Location) =
  m.links.delBySrc(loc)
  m.links.delByDest(loc)

# }}}
# {{{ eraseCell*()
proc eraseCell*(m; loc: Location) =
  m.levels[loc.level].eraseCell(loc.row, loc.col)
  m.eraseCellLinks(loc)

# }}}
# {{{ eraseCellWalls*()
proc eraseCellWalls*(m; loc: Location) =
  m.levels[loc.level].eraseCellWalls(loc.row, loc.col)

# }}}

# {{{ isEmpty*()
proc isEmpty*(m; loc: Location): bool {.inline.} =
  m.levels[loc.level].isEmpty(loc.row, loc.col)

# }}}
# {{{ getFloor*()
proc getFloor*(m; loc: Location): Floor {.inline.} =
  m.levels[loc.level].getFloor(loc.row, loc.col)

# }}}
# {{{ setFloor*()
proc setFloor*(m; loc: Location, f: Floor) =
  m.levels[loc.level].setFloor(loc.row, loc.col, f)
  m.eraseCellLinks(loc)

# }}}
# {{{ getFloorOrientation*()
proc getFloorOrientation*(m; loc: Location): Orientation {.inline.} =
  m.levels[loc.level].getFloorOrientation(loc.row, loc.col)

# }}}
# {{{ setFloorOrientation*()
proc setFloorOrientation*(m; loc: Location, ot: Orientation) =
  m.levels[loc.level].setFloorOrientation(loc.row, loc.col, ot)

# }}}
# {{{ guessFloorOrientation*()
proc guessFloorOrientation*(m; loc: Location): Orientation =
  m.levels[loc.level].guessFloorOrientation(loc.row, loc.col)

# }}}
# {{{ getFloorColor*()
proc getFloorColor*(m; loc: Location): Natural {.inline.} =
  m.levels[loc.level].getFloorColor(loc.row, loc.col)

# }}}
# {{{ setFloorColor*()
proc setFloorColor*(m; loc: Location,
                    floorColor: byte) {.inline.} =
  m.levels[loc.level].setFloorColor(loc.row, loc.col, floorColor)

# }}}

# {{{ getWall*()
proc getWall*(m; loc: Location, dir: CardinalDir): Wall {.inline.} =
  m.levels[loc.level].getWall(loc.row, loc.col, dir)

# }}}
# {{{ setWall*()
proc setWall*(m; loc: Location, dir: CardinalDir, w: Wall) =
  m.levels[loc.level].setWall(loc.row, loc.col, dir, w)

# }}}
# {{{ canSetWall*()
proc canSetWall*(m; loc: Location, dir: CardinalDir): bool =
  m.levels[loc.level].canSetWall(loc.row, loc.col, dir)

# }}}

# {{{ hasTrail*()
proc hasTrail*(m; loc: Location): bool =
  m.levels[loc.level].hasTrail(loc.row, loc.col)

# }}}
# {{{ setTrail*()
proc setTrail*(m; loc: Location, t: bool) =
  m.levels[loc.level].setTrail(loc.row, loc.col, t)

# }}}

# {{{ excavate*()
proc excavate*(m; loc: Location, floorColor: byte) =
  alias(l, m.levels[loc.level])
  alias(c, loc.col)
  alias(r, loc.row)

  let label = m.getLabel(loc)

  m.eraseCell(loc)
  m.setFloor(loc, fBlank)
  m.setFloorColor(loc, floorColor)

  if label.isSome:
    l.setAnnotation(loc.row, loc.col, label.get)

  if r == 0 or l.isEmpty(r-1, c):
    m.setWall(loc, dirN, wWall)
  else:
    m.setWall(loc, dirN, wNone)

  if c == 0 or l.isEmpty(r, c-1):
    m.setWall(loc, dirW, wWall)
  else:
    m.setWall(loc, dirW, wNone)

  if r == l.rows-1 or l.isEmpty(r+1, c):
    m.setWall(loc, dirS, wWall)
  else:
    m.setWall(loc, dirS, wNone)

  if c == l.cols-1 or l.isEmpty(r, c+1):
    m.setWall(loc, dirE, wWall)
  else:
    m.setWall(loc, dirE, wNone)

# }}}

# {{{ getLinkedLocation*()
proc getLinkedLocation*(m; loc: Location): Option[Location] =
  var other = m.links.getBySrc(loc)
  if other.isNone:
    other = m.links.getByDest(loc)

  if other.isSome:
    if isSpecialLevelIndex(other.get.level):
      result = Location.none
    else:
      result = other

# }}}
# {{{ normaliseLinkedStairs*()
proc normaliseLinkedStairs*(m; level: Natural) =
  let l = m.levels[level]

  for r in 0..<l.rows:
    for c in 0..<l.cols:
      let f = l.getFloor(r,c)

      if f in LinkStairs:
        let this = Location(level: level, row: r, col: c)
        let that = m.getLinkedLocation(this)
        if that.isSome:
          let that = that.get

          let thisElevation = m.levels[this.level].elevation
          let thatElevation = m.levels[that.level].elevation

          proc setFloors(thisFloor, thatFloor: Floor) =
            m.levels[this.level].setFloor(this.row, this.col, thisFloor)
            m.levels[that.level].setFloor(that.row, that.col, thatFloor)

          if   thisElevation > thatElevation: setFloors(fStairsDown, fStairsUp)
          elif thisElevation < thatElevation: setFloors(fStairsUp, fStairsDown)

# }}}
# {{{ deleteLinksFromOrToLevel*()
proc deleteLinksFromOrToLevel*(m; level: Natural) =
  var linksToDelete = m.links.filterByLevel(level)
  for src in linksToDelete.keys:
    m.links.delBySrc(src)

# }}}

# {{{ coordOptsForLevel*()
func coordOptsForLevel*(m; level: Natural): CoordinateOptions =
  let l = m.levels[level]
  if l.overrideCoordOpts: l.coordOpts else: m.coordOpts

# }}}
# {{{ getRegionCoords*()
proc getRegionCoords*(m; loc: Location): RegionCoords =
  let
    l = m.levels[loc.level]

    row = case m.coordOptsForLevel(loc.level).origin
          of coNorthWest: loc.row
          of coSouthWest: max((l.rows-1).int - loc.row, 0)

  result.row = row     div l.regionOpts.rowsPerRegion
  result.col = loc.col div l.regionOpts.colsPerRegion

# }}}
# {{{ getRegionRect*()
proc getRegionRect*(m; level: Natural, rc: RegionCoords): Rect[Natural] =
  let l = m.levels[level]
  var r: Rect[Natural]

  with l.regionOpts:
    r.c1 = rc.col * colsPerRegion
    r.c2 = min(r.c1 + colsPerRegion, l.cols)

    case m.coordOptsForLevel(level).origin
    of coNorthWest:
      r.r1 = rc.row * rowsPerRegion
      r.r2 = min(r.r1 + rowsPerRegion, l.rows)

    of coSouthWest:
      r.r2 = max(l.rows - rc.row*rowsPerRegion, 0)
      r.r1 = max(r.r2.int - rowsPerRegion, 0)

  result = r

# }}}
# {{{ getRegionCenterLocation*()
proc getRegionCenterLocation*(m; level: Natural,
                              rc: RegionCoords): (Natural, Natural) =
  let
    l = m.levels[level]
    r = m.getRegionRect(level, rc)

  let
    centerRow = min(r.r1 + (r.r2-r.r1-1) div 2, l.rows-1)
    centerCol = min(r.c1 + (r.c2-r.c1-1) div 2, l.cols-1)

  (centerRow.Natural, centerCol.Natural)

# }}}
# {{{ reallocateRegions*()
proc reallocateRegions*(m; level: Natural, oldCoordOpts: CoordinateOptions,
                        oldRegionOpts: RegionOptions, oldRegions: Regions) =

  let
    l = m.levels[level]
    coordOpts = m.coordOptsForLevel(level)
    flipVert = coordOpts.origin != oldCoordOpts.origin

  var index = 1

  l.regions = initRegions()

  for rc in l.allRegionCoords:
    let oldRc = if flipVert:
                  RegionCoords(row: l.regionRows(oldRegionOpts)-1 - rc.row,
                               col: rc.col)
                else: rc

    let region = oldRegions.getRegion(oldRc)

    if region.isSome and not region.get.isUntitledRegion():
      l.setRegion(rc, region.get)
    else:
      l.setRegion(rc, Region(name: l.regions.nextUntitledRegionName(index)))

# }}}
# {{{ calcRegionResizeOffsets*()
proc calcRegionResizeOffsets*(
  m; level: Natural, newRows, newCols: Natural, anchor: Direction
 ): tuple[rowOffs, colOffs: int] =

  let l = m.levels[level]
  let srcRect = getSrcRectAlignedToDestRect(l, newRows, newCols, anchor)

  with l.regionOpts:
    result.colOffs = -srcRect.c1 div colsPerRegion

    result.rowOffs = (case m.coordOptsForLevel(level).origin
                      of coNorthWest: -srcRect.r1
                      of coSouthWest: -(newRows - srcRect.r2)) div rowsPerRegion

# }}}

# {{{ newLevelFrom*()
proc newLevelFrom*(m; srcLevel: Natural, srcRect: Rect[Natural]): Level =
  let src = m.levels[srcLevel]
  alias(ro, src.regionOpts)

  var dest = newLevelFrom(src, srcRect)

  # Copy regions
  let (copyRect, _, _) = calcNewLevelFromParams(src, srcRect)

  let
    rowOffs = (case m.coordOptsForLevel(srcLevel).origin
               of coNorthWest: copyRect.r1
               of coSouthWest: src.rows-1 - copyRect.r2) div ro.rowsPerRegion

    colOffs = copyRect.c1 div ro.colsPerRegion

  dest.regions = initRegionsFrom(src.some, dest, rowOffs, colOffs)
  result = dest

# }}}

# vim: et:ts=2:sw=2:fdm=marker
