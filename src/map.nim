import bitable

import common


using m: Map

proc newMap*(): Map =
  result = new Map
  result.levels = @[]
  result.teleportLinks = initBiTable[MapLocation, MapLocation]()
  result.pitLinks      = initBiTable[MapLocation, MapLocation]()
  result.entranceLinks = initBiTable[MapLocation, MapLocation]()


# vim: et:ts=2:sw=2:fdm=marker
