import unicode

type
  FieldLimitsKind* = enum
    fkString, fkInt, fkFloat

  FieldLimits* = object
    case kind*: FieldLimitsKind
    of fkString:
      minRuneLen*, maxRuneLen*: Natural
    of fkInt:
      minInt*, maxInt*: int
    of fkFloat:
      minFloat*, maxFloat*: float

proc strLimits*(minRuneLen, maxRuneLen: Natural): FieldLimits =
  result.kind = fkString
  result.minRuneLen = minRuneLen
  result.maxRuneLen = maxRuneLen

proc intLimits*(min, max: int): FieldLimits =
  result.kind = fkInt
  result.minInt = min
  result.maxInt = max

proc floatLimits*(min, max: float): FieldLimits =
  result.kind = fkFloat
  result.minFloat = min
  result.maxFloat = max

proc check*(s: string, limit: FieldLimits): bool =
  s.runeLen >= limit.minRuneLen and
  s.runeLen <= limit.maxRuneLen

proc check*(i: SomeInteger, limit: FieldLimits): bool =
  i >= limit.minInt and i <= limit.maxInt

proc check*(i: SomeFloat, limit: FieldLimits): bool =
  i >= limit.minFloat and i <= limit.maxFloat

proc limit*(s: string, limit: FieldLimits): string =
  if   s.runeLen > limit.maxRuneLen: s.runeSubStr(0, limit.maxRuneLen)
  elif s.runeLen < limit.minRuneLen: s.alignLeft(limit.minRuneLen)
  else: s

proc limit*[T: SomeInteger](i: T, limit: FieldLimits): T =
  i.clamp(limit.minInt, limit.maxInt)

proc limit*[T: SomeFloat](i: T, limit: FieldLimits): T =
  i.clamp(limit.minFloat, limit.maxFloat)

