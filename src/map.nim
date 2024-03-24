import std/algorithm
import std/options
import std/sequtils
import std/sets
import std/tables

import common
import deps/with
import level
import links
import rect
import regions
import utils


using m: Map

# {{{ newMap*()
proc newMap*(title, game, author, creationTime: string): Map =
  var m = new Map
  m.title        = title
  m.game         = game
  m.author       = author
  m.creationTime = creationTime

  m.levels = @[]
  # Start with dirty until cleared
  m.levelsDirty = true

  m.links = initLinks()

  m.coordOpts = CoordinateOptions(
    origin:      coNorthWest,
    rowStyle:    csNumber,
    columnStyle: csNumber,
    rowStart:    1,
    columnStart: 1
  )

  m.sortedLevelNames   = @[]
  m.sortedLevelIndexes = @[]

  result = m

# }}}

# {{{ sortLevels*()
proc sortLevels*(m) =
  var sortedLevelsWithIndex = zip(m.levels, (0..m.levels.high).toSeq)
  sortedLevelsWithIndex.sort(
    proc (a, b: tuple[level: Level, idx: int]): int =
      var c = cmp(a.level.locationName, b.level.locationName)
      if c != 0: return c

      c = cmp(b.level.elevation, a.level.elevation)
      if c != 0: return c

      return cmp(a.level.levelName, b.level.levelName)
  )

  m.sortedLevelNames   = @[]
  m.sortedLevelIndexes = @[]

  for (level, levelIdx) in sortedLevelsWithIndex:
    m.sortedLevelNames.add(level.getDetailedName())
    m.sortedLevelIndexes.add(levelIdx)

# }}}
# {{{ sortedLevels*()
iterator sortedLevels*(m): tuple[levelIdx: Natural, level: Level] =
  for i in m.sortedLevelIndexes:
    yield (i, m.levels[i])

# }}}
# {{{ findSortedLevelIdxForLevel*()
proc findSortedLevelIdxForLevel*(m; level: Natural): Natural =
  let idx = m.sortedLevelIndexes.find(level)
  assert idx > -1
  idx.Natural

# }}}
# {{{ hasLevels*()
func hasLevels*(m): bool =
  m.levels.len > 0

# }}}
# {{{ addLevel*()
proc addLevel*(m; l: Level) =
  m.levels.add(l)
  m.sortLevels()
  m.levelsDirty = true

# }}}
# {{{ setLevel*()
proc setLevel*(m; idx: Natural, l: Level) =
  m.levels[idx] = l
  m.sortLevels()
  m.levelsDirty = true

# }}}
# {{{ delLevel*()
proc delLevel*(m; levelIdx: Natural) =
  m.levels.del(levelIdx)
  m.sortLevels()
  m.levelsDirty = true

# }}}

# {{{ allNotes*()
iterator allNotes*(m): tuple[loc: Location, note: Annotation] =
  for levelIdx, l in m.levels:
    for note in l.allNotes():
      yield (Location(level: levelIdx, row: note.row, col: note.col),
             note.annotation)
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
proc eraseCell*(m; loc: Location, preserveLabel: bool) =
  alias(l, m.levels[loc.level])
  let label = m.getLabel(loc)

  m.levels[loc.level].eraseCell(loc.row, loc.col)
  m.eraseCellLinks(loc)

  if preserveLabel and label.isSome:
    l.setAnnotation(loc.row, loc.col, label.get)

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
# {{{ clearFloor*()
proc clearFloor*(m; loc: Location) =
  m.levels[loc.level].clearFloor(loc.row, loc.col)
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
                    floorColor: Natural) {.inline.} =
  m.levels[loc.level].setFloorColor(loc.row, loc.col, floorColor.byte)

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

# {{{ excavateTunnel*()
proc excavateTunnel*(m; loc: Location, floorColor: Natural,
                     dir: Option[CardinalDir] = CardinalDir.none,
                     prevLoc: Option[Location] = Location.none,
                     prevDir: Option[CardinalDir] = CardinalDir.none) =
  alias(l, m.levels[loc.level])
  alias(c, loc.col)
  alias(r, loc.row)

  m.eraseCell(loc, preserveLabel=true)
  m.setFloor(loc, fBlank)
  m.setFloorColor(loc, floorColor)

  if dir.isSome and prevDir.isSome and
     dir.get.orientation != prevDir.get.orientation:
    m.excavateTunnel(prevLoc.get, floorColor)

  var wallDirs = @[dirN, dirS, dirE, dirW]
  if dir.isSome:
    wallDirs.delete(wallDirs.find(dir.get))

  for d in wallDirs:
    if l.isNeighbourCellEmpty(r, c, {d}):
      m.setWall(loc, d, wWall)
    else:
      m.setWall(loc, d, wNone)

# }}}

# {{{ getLinkedLocations*()
proc getLinkedLocations*(m; loc: Location): HashSet[Location] =
  let dest = m.links.getBySrc(loc)
  if dest.isSome:
    if not isSpecialLevelIndex(dest.get.level):
      result.incl(dest.get)
  else:
    let srcs = m.links.getByDest(loc)
    if srcs.isSome:
      for src in srcs.get:
        if isSpecialLevelIndex(src.level):
          continue
        result.incl(src)

# }}}

# {{{ normaliseLinkedStairs*()
proc normaliseLinkedStairs*(m; level: Natural) =
  let l = m.levels[level]

  for r in 0..<l.rows:
    for c in 0..<l.cols:
      let f = l.getFloor(r,c)

      if f in LinkStairs:
        let this = Location(level: level, row: r, col: c)
        let that = m.getLinkedLocations(this)
        if that.len > 0:
          assert that.len == 1, "Stairs should not have linked multiple locations"
          let that = that.first.get

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
  for src in linksToDelete.sources:
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
                              rc: RegionCoords): tuple[row, col: Natural] =
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
                      of coSouthWest:
                        -(newRows - srcRect.r2)) div rowsPerRegion

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
               of coSouthWest: src.rows - copyRect.r2) div ro.rowsPerRegion

    colOffs = copyRect.c1 div ro.colsPerRegion

  dest.regions = initRegionsFrom(src.some, dest, rowOffs, colOffs)
  result = dest

# }}}

# vim: et:ts=2:sw=2:fdm=marker
