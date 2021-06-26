import fieldlimits
import logging except Level
import options
import parsecfg
import strformat
import strscans
import strutils

import nanovg


proc invalidValueError(section, key, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value in section='{section}', key='{key}': {value}"
  error(msg)

proc getValue*(cfg: Config, section, key: string): string =
  cfg.getSectionValue(section, key)

proc getString*(cfg: Config, section, key: string, s: var string) =
  s = getValue(cfg, section, key)

proc parseColor(s: string): Option[Color] =
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

proc getColor*(cfg: Config, section, key: string, c: var Color) =
  let v = getValue(cfg, section, key)
  if v != "":
    let col = parseColor(v)
    if col.isNone:
      invalidValueError(section, key, "color", v)
    else:
      c = col.get

proc getBool*(cfg: Config, section, key: string, b: var bool) =
  let v = getValue(cfg, section, key)
  if v != "":
    try:
      b = parseBool(v)
    except ValueError:
      invalidValueError(section, key, "bool", v)

proc getFloat*(cfg: Config, section, key: string, f: var float) =
  let v = getValue(cfg, section, key)
  if v != "":
    try:
      f = parseFloat(v)
    except ValueError:
      invalidValueError(section, key, "float", v)

proc getInt*(cfg: Config, section, key: string, i: var int) =
  let v = getValue(cfg, section, key)
  if v != "":
    try:
      i = parseInt(v)
    except ValueError:
      invalidValueError(section, key, "int", v)

proc getNatural*(cfg: Config, section, key: string, n: var int) =
  var i: int
  getInt(cfg, section, key, i)
  if i >= 0:
    n = i.Natural
  else:
    invalidValueError(section, key, "natural", $i)


proc getNatural*(cfg: Config, section, key: string, n: var int,
                 limits: FieldLimits) =
  var i: int

  case limits.kind:
  of fkInt:
    getInt(cfg, section, key, i)
    i = i.limit(limits)
  else:
    error(fmt"Invalid FieldLimits for Natural type: {limits}")

  if i >= 0:
    n = i.Natural
  else:
    invalidValueError(section, key, "natural", $i)


proc getEnum*[T: enum](cfg: Config, section, key: string, e: var T) =
  let v = getValue(cfg, section, key)
  if v != "":
    try:
      e = parseEnum[T](v)
    except ValueError:
      invalidValueError(section, key, "enum", v)

