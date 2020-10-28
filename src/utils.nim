import hashes

import common


# {{{ alias()
template alias*(newName: untyped, call: untyped) =
  template newName(): untyped = call

# }}}

# {{{ linkFloorToString*()
proc linkFloorToString*(f: Floor): string =
  if   f in (LinkPitSources + LinkPitDestinations): return "pit"
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

  proc toLetter(i: Natural): char = chr(ord('A') + i)

  if x < 26:
    result = $x.toLetter
  elif x < 26*26:
    result = (x div 26 - 1).toLetter & (x mod 26).toLetter
  elif x < 26*26*26:
    let d1 = x mod 26
    var x = x div 26
    let d2 = x mod 26
    let d3 = x div 26 - 1
    result = d3.toLetter & d2.toLetter & d1.toLetter
  else:
    result = ""

# }}}
# {{{ formatColumnCoord*()
proc formatColumnCoord*(col: Natural, co: CoordinateOptions,
                        numCols: Natural): string =
  var x = co.columnStart + col

  case co.columnStyle
  of csNumber: $x
  of csLetter: toLetterCoord(x)

# }}}
# {{{ formatRowCoord*()
proc formatRowCoord*(row: Natural, co: CoordinateOptions,
                     numRows: Natural): string =
  var x = co.rowStart + (
    case co.origin
      of coNorthWest: row
      of coSouthWest: numRows-1 - row
  )

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
