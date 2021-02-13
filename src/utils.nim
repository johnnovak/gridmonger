import hashes
import times

import common

# {{{ alias*()
template alias*(newName: untyped, call: untyped) =
  template newName(): untyped = call

# }}}
# {{{ durationToFloatMillis*()
proc durationToFloatMillis*(d: Duration): float64 =
  inNanoseconds(d).float64 * 1e-6

# }}}

# {{{ linkFloorToString*()
proc linkFloorToString*(f: Floor): string =
  if   f in (LinkPitAbove + LinkPitBelow): return "pit"
  elif f in LinkStairs: return "stairs"
  elif f in LinkDoors: return "door"
  elif f in {fTeleportSource, fTeleportDestination}: return "teleport"

# }}}
# {{{ hash*(ml: Location)
proc hash*(ml: Location): Hash =
  var h: Hash = 0
  h = h !& hash(ml.level)
  h = h !& hash(ml.row)
  h = h !& hash(ml.col)
  result = !$h

# }}}
# {{{ `<`*(a, b: Location)
proc `<`*(a, b: Location): bool =
  if   a.level < b.level: return true
  elif a.level > b.level: return false

  elif a.row < b.row: return true
  elif a.row > b.row: return false

  elif a.col < b.col: return true
  else: return false

# }}}
# {{{ toLetterCoord*)
proc toLetterCoord*(x: Natural): string =

  const N = 26  # number of letters in alphabet

  proc toLetter(i: Natural): char = chr(ord('A') + i)

  if x < N:
    result = $x.toLetter
  elif x < N*N:
    result = (x div N - 1).toLetter & (x mod N).toLetter
  elif x < N*N*N:
    let d1 = x mod N
    var x = x div N
    let d2 = x mod N
    let d3 = x div N - 1
    result = d3.toLetter & d2.toLetter & d1.toLetter
  else:
    result = ""

# }}}
# {{{ formatColumnCoord*()
proc formatColumnCoord*(col: Natural, numCols: Natural,
                        co: CoordinateOptions, ro: RegionOptions): string =

  let x = co.columnStart + (if ro.enableRegions and ro.perRegionCoords:
                              col mod ro.regionColumns
                            else: col)

  case co.columnStyle
  of csNumber: $x
  of csLetter: toLetterCoord(x)

# }}}
# {{{ formatRowCoord*()
proc formatRowCoord*(row: Natural, numRows: Natural,
                     co: CoordinateOptions, ro: RegionOptions): string =

  var x = case co.origin
    of coNorthWest: row
    of coSouthWest: numRows-1 - row

  x = co.rowStart + (if ro.enableRegions and ro.perRegionCoords:
                       x mod ro.regionRows
                     else: x)

  case co.rowStyle
  of csNumber: $x
  of csLetter: toLetterCoord(x)

# }}}
# {{{ step*()
proc step*(row, col: int, dir: Direction): (int, int) =
  if   dir == North:     result = (row-1, col)
  elif dir == NorthEast: result = (row-1, col+1)
  elif dir == East:      result = (row,   col+1)
  elif dir == SouthEast: result = (row+1, col+1)
  elif dir == South:     result = (row+1, col)
  elif dir == SouthWest: result = (row+1, col-1)
  elif dir == West:      result = (row,   col-1)
  elif dir == NorthWest: result = (row-1, col-1)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
