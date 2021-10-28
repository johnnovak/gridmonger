import hashes
import typetraits
import strutils
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
  if   f in (LinkPitSources + LinkPitDestinations): return "pit"
  elif f in LinkStairs: return "stairs"
  elif f in LinkDoors: return "door"
  elif f in LinkTeleports: return "teleport"

# }}}
# {{{ hash*(l: Location)
proc hash*(l: Location): Hash =
  var h: Hash = 0
  h = h !& hash(l.level)
  h = h !& hash(l.row)
  h = h !& hash(l.col)
  result = !$h

# }}}
# {{{ hash*(rc: RegionCoords)
proc hash*(rc: RegionCoords): Hash =
  var h: Hash = 0
  h = h !& hash(rc.row)
  h = h !& hash(rc.col)
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

  let x = co.columnStart + (if ro.enabled and ro.perRegionCoords:
                               col mod ro.colsPerRegion
                            else: col)

  case co.columnStyle
  of csNumber: $x
  of csLetter: toLetterCoord(x)

# }}}
# {{{ formatRowCoord*()
proc formatRowCoord*(row: Natural, numRows: Natural,
                     coordOpts: CoordinateOptions, regionOpts: RegionOptions): string =

  var x = case coordOpts.origin
    of coNorthWest: row
    of coSouthWest: numRows-1 - row

  x = coordOpts.rowStart + (if regionOpts.enabled and
                               regionOpts.perRegionCoords:
                              x mod regionOpts.rowsPerRegion
                            else: x)

  case coordOpts.rowStyle
  of csNumber: $x
  of csLetter: toLetterCoord(x)

# }}}

# {{{ isValidFilename*()
func isValidFilename*(filename: string): bool =
  const MaxLen = 259
  const InvalidFilenameChars = {'/', '\\', ':', '*', '?', '"', '<', '>',
                                '|', '^', '\0'}

  if filename.len == 0 or filename.len > MaxLen or
    filename[0] == ' ' or filename[^1] == ' ' or filename[^1] == '.' or
    find(filename, InvalidFilenameChars) != -1: false
  else: true

# }}}

# vim: et:ts=2:sw=2:fdm=marker
