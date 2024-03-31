import std/algorithm
import std/parseutils
import std/strutils
import std/unicode

# This is a slight adaptation of Alogani's code from here:
# https://github.com/nim-lang/Nim/issues/23462

# {{{ isDigit*()
# List of zero converted from ttps://www.fileformat.info/info/unicode/category/Nd/list.htm
const allZeros = [
  48,    1632,  1776,  1984,  2406, 2534, 2662, 2790,  2918,  3046,  3174,
  3302,  3430,  3558,  3664,  3792, 3872, 4160, 4240,  6112,  6160,  6470,
  6608,  6784,  6800,  6992,  7088, 7232, 7248, 42528, 43216, 43264, 43472,
  43504, 43600, 44016, 65296, 4170, 4307, 4358, 4367,  4371,  4381,  4399,
  4421,  4429,  4453,  4460,  4467, 4494, 4501, 4549,  4565,  4570,  4597,
  5798,  5804,  5813,  7548,  7549, 7550, 7550, 7551,  7700,  7727,  7759,
  7829,  8127
]

func toDigitImpl(r: Rune): int =
  let codePoint = ord(r)
  for z in allZeros:
    # not a binary search, because first runes are more common
    if codePoint > z:
      return codePoint - z
  return -1

func isDigit*(r: Rune): bool =
  let digit = r.toDigitImpl
  digit in {0..9}

func toDigit*(r: Rune): int =
  result = r.toDigitImpl
  if result notin {0..9}:
    raise newException(RangeDefect, "rune is not a valid digit")

# }}}
# {{{ rawParseInt()
proc newIntegerOutOfRangeError(): ref ValueError =
  newException(ValueError, "Parsed integer outside of valid range")


proc rawParseInt(s: openArray[Rune], b: var BiggestInt): int =
  var
    sign: BiggestInt = -1
    i = 0
  if i < s.len:
    if s[i] == '+'.Rune: inc(i)
    elif s[i] == '-'.Rune:
      inc(i)
      sign = 1

  if i < s.len:
    b = 0
    while i < s.len and (let c = toDigitImpl(s[i]); c in {0..9}):
      if b >= (low(BiggestInt) + c) div 10:
        b = b * 10 - c
      else:
        raise newIntegerOutOfRangeError()
      inc(i)
      while i < s.len and s[i] == '_'.Rune: inc(i) # underscores are allowed and ignored
    if sign == -1 and b == low(BiggestInt):
      raise newIntegerOutOfRangeError()
    else:
      b = b * sign
      result = i

# }}}

# {{{ Comparator implementations
func cmpIgnoreCase(a, b: char): int =
    ord(a.toLowerAscii) - ord(b.toLowerAscii)

func cmp(a, b: Rune): int =
    a.int - b.int

func cmpIgnoreCase(a, b: Rune): int =
    a.toLower.int - b.toLower.int

template cmpNaturalImpl(a, b: string, comparator: untyped): auto =
  var ai = 0
  var bi = 0
  while true:
    if ai > high(a) or bi > high(b):
      return a.len - ai - b.len + bi
    if not (a[ai].isDigit and b[bi].isDigit):
      let diff = comparator(a[ai], b[bi])
      if diff != 0:
        return diff
      ai += 1; bi += 1
    else:
      var
        aNum: int
        bNum: int
      ai += parseInt(a[ai .. ^1], aNum)
      bi += parseInt(b[bi .. ^1], bNum)
      let diff = cmp(aNum, bNum)
      if diff != 0:
        return diff

template cmpNaturalImpl(a, b: seq[Rune], comparator: untyped): auto =
  var ai = 0
  var bi = 0
  while true:
    if ai > high(a) or bi > high(b):
      return a.len - ai - b.len + bi
    if not(a[ai].isDigit and b[bi].isDigit):
      let diff = comparator(a[ai], b[bi])
      if diff != 0:
        return diff
      ai += 1; bi += 1
    else:
      var
        aNum: Biggestint
        bNum: Biggestint
      ai += rawParseInt(a[ai..^1], aNum)
      bi += rawParseInt(b[bi..^1], bNum)
      let diff = cmp(aNum, bNum)
      if diff != 0:
        return diff

# }}}

# {{{ cmpNatural*()
func cmpNatural*(a, b: string): int =
  cmpNaturalImpl(a, b, cmp)

func cmpNatural*(a, b: seq[Rune]): int =
  cmpNaturalImpl(a, b, cmp)

# }}}
# {{{ cmpNaturalIgnoreCase*()
func cmpNaturalIgnoreCase*(a, b: string): int =
  cmpNaturalImpl(a, b, cmpIgnoreCase)

func cmpNaturalIgnoreCase*(a, b: seq[Rune]): int =
  cmpNaturalImpl(a, b, cmpIgnoreCase)

# }}}

# {{{ naturalSort*()
func naturalSort*(l: openArray[string]): seq[string] =
  l.sorted(cmpNatural)

func naturalSort*(l: openArray[seq[Rune]]): seq[seq[Rune]] =
  l.sorted(cmpNatural)

# }}}
# {{{ naturalSortUtf8*()
proc naturalSortUtf8*(l: openArray[string]): seq[string] =
  var rl = newSeq[seq[Rune]](l.len)
  for i in 0..<l.len:
    rl[i] = l[i].toRunes

  var sorted = naturalSort(rl)

  result = newSeq[string](sorted.len)
  for i in 0..<sorted.len:
    result[i] = $sorted[i]

# }}}
# {{{ naturalSortIgnoreCase*(()
func naturalSortIgnoreCase*(l: openArray[string]): seq[string] =
  l.sorted(cmpNaturalIgnoreCase)

func naturalSortIgnoreCase*(l: openArray[seq[Rune]]): seq[seq[Rune]] =
  l.sorted(cmpNaturalIgnoreCase)

proc naturalSortIgnoreCase*(l: openArray[string]): seq[string] =
  var rl = newSeq[seq[Rune]](l.len)
  for i in 0..<l.len:
    rl[i] = l[i].toRunes

  var sorted = naturalSortIgnoreCase(rl)

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
