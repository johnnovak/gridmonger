import math

import fieldlimits
import hocon
import logging except Level
import options
import strformat
import strutils

import nanovg



using cfg: HoconNode


proc `$`*(c: Color): string =
  let
    r = round(c.r * 255).int
    g = round(c.g * 255).int
    b = round(c.b * 255).int
    a = round(c.a * 255).int

  fmt"#{r:02x}{g:02x}{b:02x}{a:02x}"


proc getObjectOrEmpty*(cfg; path: string): HoconNode =
  try:
    let n = cfg.get(path)
    if n.kind != hnkObject:
      result = newHoconObject()
    else:
      result = n
  except CatchableError:
    result = newHoconObject()

proc invalidValueError(path, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value for path '{path}': {value}"
  error(msg)


proc getString*(cfg; path: string, default: string): string =
  result = default
  try:
    result = cfg.getString(path)
  except CatchableError as e:
    error(e.msg)


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

proc getColor*(cfg; path: string, default: Color = black()): Color =
  result = default
  try:
    let v = cfg.getString(path)
    if v != "":
      let col = parseColor(v)
      if col.isNone:
        invalidValueError(path, "color", v)
      else:
        result = col.get
  except CatchableError as e:
    error(e.msg)


proc getBool*(cfg; path: string, default: bool): bool =
  result = default
  try:
    result = cfg.getBool(path)
  except CatchableError as e:
    error(e.msg)


proc getFloat*(cfg; path: string, default: float): float =
  result = default
  try:
    result = cfg.getFloat(path)
  except CatchableError as e:
    error(e.msg)

proc getInt*(cfg; path: string, default: int): int =
  result = default
  try:
    result = cfg.getInt(path)
  except CatchableError as e:
    error(e.msg)

proc getNatural*(cfg; path: string, default: Natural): Natural =
  result = default
  try:
    result = cfg.getNatural(path)
  except CatchableError as e:
    error(e.msg)

proc getNatural*(cfg; path: string, limits: FieldLimits,
                 default: Natural): Natural =
  try:
    result = default
    var i: int
    case limits.kind:
    of fkInt:
      i = cfg.getNatural(path)
      result = i.limit(limits)
    else:
      error(fmt"Invalid FieldLimits for Natural type: {limits}")
  except CatchableError as e:
    error(e.msg)


proc getEnum*(cfg; path: string, T: typedesc[enum], default = T.low): T =
  try:
    let v = cfg.getString(path)
    if v != "":
      try:
        result = parseEnum[T](v.toUpper())
      except ValueError:
        invalidValueError(path, "enum", v)
  except CatchableError as e:
    error(e.msg)

# vim: et:ts=2:sw=2:fdm=marker
