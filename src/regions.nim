import std/options
import std/sugar
import std/strutils
import std/tables

import common
import utils


using
  r: Regions
  vr: var Regions


# {{{ initRegion*()
var g_regionIdCounter = 0

proc initRegion*(name: string, notes: string = ""): Region =
  result.id = g_regionIdCounter
  inc(g_regionIdCounter)

  result.name = name
  result.notes = notes

# }}}

# {{{ initRegions*()
proc initRegions*(): Regions =
  result.regionsByCoords = initOrderedTable[RegionCoords, Region]()

# }}}
# {{{ dump*()
proc dump*(r) =
  for k,v in r.regionsByCoords:
    echo "key: ", k, ", val: ", v
  echo ""

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
  r.regionsByCoords.len

# }}}
# {{{ allRegions*()
iterator allRegions*(r): tuple[regionCoords: RegionCoords, region: Region] =
  for rc, region in r.regionsByCoords:
    yield (rc, region)

# }}}
# {{{ regionNames*()
proc sortedRegionNames*(r): seq[string] =
  result = collect:
    for r in r.regionsByCoords.values: r.name

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
