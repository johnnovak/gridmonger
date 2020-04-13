import bitable

import common


using m: Map

proc newMap*(): Map =
  result = new Map
  result.levels = @[]
  result.links = initBiTable[Location, Location]()


# vim: et:ts=2:sw=2:fdm=marker
