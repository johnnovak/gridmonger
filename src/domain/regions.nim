import std/options
import std/sugar
import std/strutils
import std/tables

import common
import utils/naturalsort


using
  r: Regions
  vr: var Regions


# {{{ initRegion*()
proc initRegion*(name: string, notes: string = ""): Region =
  result.name  = name
  result.notes = notes

# }}}

# {{{ initRegions*()
proc initRegions*(): Regions =
  result.regionsByCoords   = initOrderedTable[RegionCoords, Region]()
  result.sortedRegionNames = @[]

# }}}
# {{{ dump*()
proc dump*(r) =
  for k,v in r.regionsByCoords:
    echo "key: ", k, ", val: ", v
  echo ""

# }}}

# {{{ sortRegions*()
proc sortRegions*(vr) =
  vr.regionsByCoords.sort(
    proc (a, b: tuple[rc: RegionCoords, region: Region]): int =
      return cmpNaturalIgnoreCase(a.region.name, b.region.name)
  )

  vr.sortedRegionNames = collect:
    for _, region in vr.regionsByCoords: region.name

# }}}

# {{{ `[]`*()
proc `[]`*(r; rc: RegionCoords): Option[Region] =
  if r.regionsByCoords.hasKey(rc):
    r.regionsByCoords[rc].some
  else: Region.none

# }}}
# {{{ `[]=`*()
proc `[]=`*(vr; rc: RegionCoords, region: Region) =
  vr.regionsByCoords[rc] = region

# }}}
# {{{ numRegions*()
proc numRegions*(r): Natural =
  # Note that this can return a non-zero value even if regions are disabled
  # the Level's RegionOpts (see `Level.regions` in `common.nim`).
  r.regionsByCoords.len

# }}}
# {{{ sortedRegions*()
iterator sortedRegions*(r): tuple[regionCoords: RegionCoords, region: Region] =
  for rc, region in r.regionsByCoords:
    yield (rc, region)

# }}}

# {{{ findFirstByName*()
proc findFirstByName*(r; name: string): Option[(RegionCoords, Region)] =
  for rc, region in r.regionsByCoords:
    if region.name == name:
      return (rc, region).some
  result = (RegionCoords, Region).none

# }}}
# {{{ isUntitledRegion*()
const UntitledRegionPrefix = "Untitled Region "

proc isUntitledRegion*(r: Region): bool =
  r.name.startsWith(UntitledRegionPrefix)

# }}}
# {{{ nextUntitledRegionName*()
proc nextUntitledRegionName*(r; index: var int): string =
  while true:
    let name = UntitledRegionPrefix & $index
    inc(index)
    var region = r.findFirstByName(name)
    if region.isNone:
      return name

# }}}

# vim: et:ts=2:sw=2:fdm=marker
