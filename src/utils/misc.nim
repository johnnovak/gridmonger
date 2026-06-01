import std/browsers
import std/options
import std/os
import std/strformat
import std/strutils
import std/times

# {{{ alias*()
template alias*(newName: untyped, call: untyped) =
  template newName(): untyped {.redefine.} = call

# }}}
# {{{ first*()
func first*[T](iterable: T): auto =
  for v in iterable:
    return v.some

# }}}

# {{{ durationToFloatMillis*()
proc durationToFloatMillis*(d: Duration): float64 =
  inNanoseconds(d).float64 * 1e-6

# }}}
# {{{ currentLocalDatetimeString*()
proc currentLocalDatetimeString*(): string =
  now().format("yyyy-MM-dd HH:mm:ss")

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
# {{{ findUniquePath*()
proc findUniquePath*(dir: string, name: string, ext: string): string =
  var n = 1
  while true:
    let path = dir / fmt"{name} {n}".addFileExt(ext)
    if fileExists(path): inc(n)
    else: return path

# }}}

# {{{ clampMin*()
func clampMin*[T](x, minLimit: T): T = max(x, minLimit)

# }}}
# {{{ clampMax*()
func clampMax*[T](x, maxLimit: T): T = min(x, maxLimit)

# }}}

# {{{ Implicit int <-> float converters
converter toCfloat*(x: SomeInteger): cfloat = x.cfloat
converter toFloat*(x: SomeInteger): float = x.float

converter toInt32Tuple*(t: (Natural, Natural)): (int32, int32) =
  (t[0].int32, t[1].int32)

# }}}
# {{{ openUserManual*()
proc openUserManual*(manualDir: string) =
  openDefaultBrowser(manualDir / "index.html")

# }}}

# vim: et:ts=2:sw=2:fdm=marker
