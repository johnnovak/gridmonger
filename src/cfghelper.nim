import fieldlimits
import logging except Level
import options
import parsecfg
import strformat
import strutils

import nanovg

import hocon


using cfg: HoconNode

proc invalidValueError(key, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value for key '{key}': {value}"
  error(msg)

proc getString*(cfg; key: string): string =
  cfg.get(key).str

proc parseColor*(s: string): Option[Color] =
  result = Color.none
  if s.len == 9 and s[0] == '#':
    try:
      let r = s[1..2].parseHexInt()
      let g = s[3..4].parseHexInt()
      let b = s[5..6].parseHexInt()
      let a = s[7..8].parseHexInt()
      result = rgba(r/255, g/255, b/255, a/255).some
    except ValueError:
      discard

proc getColor*(cfg; key: string): Color =
  let v = cfg.get(key).str
  if v != "":
    let col = parseColor(v)
    if col.isNone:
      invalidValueError(key, "color", v)
    else:
      result = col.get

proc getBool*(cfg; key: string): bool =
  let v = cfg.get(key).str
  if v != "":
    try:
      result = parseBool(v)
    except ValueError:
      invalidValueError(key, "bool", v)

proc getFloat*(cfg; key: string): float =
  cfg.get(key).num

proc getInt*(cfg; key: string): int =
  cfg.get(key).num.int

proc getNatural*(cfg; key: string): Natural =
  var i = cfg.getInt(key)
  if i >= 0:
    result = i.Natural
  else:
    invalidValueError(key, "natural", $i)


proc getNatural*(cfg; key: string, limits: FieldLimits): Natural =
  var i: int
  case limits.kind:
  of fkInt:
    i = cfg.getInt(key)
    result = i.limit(limits)
  else:
    error(fmt"Invalid FieldLimits for Natural type: {limits}")

  if i >= 0:
    result = i.Natural
  else:
    invalidValueError(key, "natural", $i)


proc getEnum*(cfg; key: string, T: typedesc[enum]): T =
  let v = cfg.get(key).str
  if v != "":
    try:
      result = parseEnum[T](v.toUpper())
    except ValueError:
      invalidValueError(key, "enum", v)

