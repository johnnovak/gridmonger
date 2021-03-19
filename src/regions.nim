import options
import tables

import common
import utils


using
  r: Regions
  vr: var Regions

# {{{ initRegions*()
proc initRegions*(): Regions =
  result = initTable[RegionCoords, Region]()

# }}}

# {{{ setRegion*()
proc setRegion*(vr; rc: RegionCoords, region: Region) =
  vr[rc] = region

# }}}
# {{{ getRegion*()
proc getRegion*(r; rc: RegionCoords): Region =
  r[rc]

# }}}
# {{{ allRegions*()
iterator allRegions*(r): (RegionCoords, Region) =
  for rc, r in r.pairs:
    yield (rc, r)

# }}}
# {{{ regionNames*()
proc regionNames*(r): seq[string] =
  result = @[]
  for r in r.values:
    result.add(r.name)

# }}}
# {{{ findFirstRegionByName*()
proc findFirstRegionByName*(r; name: string): Option[(RegionCoords, Region)] =
  for rc, r in r.pairs:
    if r.name == name:
      return (rc, r).some
  result = (RegionCoords, Region).none

# }}}

# vim: et:ts=2:sw=2:fdm=marker
