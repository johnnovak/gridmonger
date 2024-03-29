import std/algorithm
import std/parseutils
import std/strutils
import std/unicode

import utils

# Original code by Alogani
# From https://github.com/nim-lang/Nim/issues/23462

# {{{ cmpNaturalAscii*()
proc cmpNaturalAscii*(a, b: string): int =
  var
    ai = 0
    bi = 0

  while true:
    if ai > a.high or bi > b.high:
      return a.len - ai - b.len + bi

    if not (a[ai].isDigit and b[bi].isDigit):
      let diff = cmp(a[ai], b[bi])
      if diff != 0:
        return diff

      inc(ai)
      inc(bi)
    else:
      var
        aNum: int
        bNum: int
      ai += parseInt(a[ai..^1], aNum)
      bi += parseInt(b[bi..^1], bNum)

      let diff = cmp(aNum, bNum)
      if diff != 0:
        return diff

# }}}
# {{{ cmpNatural*()
proc cmpNatural*(a, b: seq[Rune]): int =
  var
    ai = 0
    bi = 0

  while true:
    if ai > a.high or bi > b.high:
      return a.len-ai - b.len+bi

    if not (a[ai].isDigit and b[bi].isDigit):
      let diff = if   a[ai] == b[bi]:  0
                 elif a[ai] <% b[bi]: -1
                 else:                 1
      if diff != 0:
        return diff

      inc(ai)
      inc(bi)
    else:
      var aNum, bNum: int
      ai += parseInt($(a[ai..^1]), aNum)
      bi += parseInt($(b[bi..^1]), bNum)

      let diff = cmp(aNum, bNum)
      if diff != 0:
        return diff

# }}}
# {{{ cmpNaturalIgnoreCase*()
proc cmpNaturalIgnoreCase*(a, b: seq[Rune]): int =
  cmpNatural(a, b)
# }}}

# {{{ naturalSortAscii*()
proc naturalSortAscii*(l: openArray[string]): seq[string] =
  l.sorted(cmpNaturalAscii)

# }}}
# {{{ naturalSort*()
proc naturalSort*(l: openArray[seq[Rune]]): seq[seq[Rune]] =
  l.sorted(cmpNatural)

proc naturalSort*(l: openArray[string]): seq[string] =
  var rl = newSeq[seq[Rune]](l.len)
  for i in 0..<l.len:
      rl[i] = l[i].toRunes

  var sorted = naturalSort(rl)

  result = newSeq[string](sorted.len)
  for i in 0..<sorted.len:
      result[i] = $sorted[i]

# }}}


# {{{ Tests
when isMainModule:
  var a = @["d", "a", "cdrom1", "cdrom10", "cdrom102", "cdrom11", "cdrom2",
            "cdrom20", "cdrom3", "cdrom30", "cdrom4", "cdrom40", "cdrom100",
            "cdrom101", "cdrom103", "cdrom110"]


  echo a.naturalSort

  var b = @["!a", "[b"]

  echo b.naturalSort

# }}}

# vim: et:ts=2:sw=2:fdm=marker
