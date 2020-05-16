import options
import parsecfg
import strformat
import strscans
import strutils

import nanovg


proc missingValueError(section, key: string) =
  let msg = fmt"Missing value in section='{section}', key='{key}'"
  echo msg

proc invalidValueError(section, key, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value in section='{section}', key='{key}': {value}"
  echo msg

proc getValue*(cfg: Config, section, key: string): string =
  result = cfg.getSectionValue(section, key)
  if result == "":
    missingValueError(section, key)

proc parseColor*(s: string): Option[Color] =
  result = Color.none
  block:
    var r, g, b, a: int
    if scanf(s, "gray($i)$.", g):
      result = gray(g).some
    elif scanf(s, "gray($i,$s$i)$.", g, a):
      result = gray(g, a).some
    elif scanf(s, "rgb($i,$s$i,$s$i)$.", r, g, b):
      result = rgb(r, g, b).some
    elif scanf(s, "rgba($i,$s$i,$s$i,$s$i)$.", r, g, b, a):
      result = rgba(r, g, b, a).some

  if result.isSome: return

  block:
    var r, g, b, a: float
    if scanf(s, "gray($f)$.", g):
      result = gray(g).some
    elif scanf(s, "gray($f,$s$f)$.", g, a):
      result = gray(g, a).some
    elif scanf(s, "rgb($f,$s$f,$s$f)$.", r, g, b):
      result = rgb(r, g, b).some
    elif scanf(s, "rgba($f,$s$f,$s$f,$s$f)$.", r, g, b, a):
      result = rgba(r, g, b, a).some


proc getString*(cfg: Config, section, key: string, s: var string) =
  s = getValue(cfg, section, key)

proc getColor*(cfg: Config, section, key: string, c: var Color) =
  let v = getValue(cfg, section, key)
  let col = parseColor(v)
  if col.isNone:
    invalidValueError(section, key, "color", v)
  else:
    c = col.get

proc getBool*(cfg: Config, section, key: string, b: var bool) =
  let v = getValue(cfg, section, key)
  try:
    b = parseBool(v)
  except ValueError:
    invalidValueError(section, key, "bool", v)

proc getFloat*(cfg: Config, section, key: string, f: var float) =
  let v = getValue(cfg, section, key)
  try:
    f = parseFloat(v)
  except ValueError:
    invalidValueError(section, key, "float", v)

proc getInt*(cfg: Config, section, key: string, i: var int) =
  let v = getValue(cfg, section, key)
  try:
    i = parseInt(v)
  except ValueError:
    invalidValueError(section, key, "int", v)

proc getEnum*[T: enum](cfg: Config, section, key: string, e: var T) =
  let v = getValue(cfg, section, key)
  try:
    e = parseEnum[T](v)
  except ValueError:
    invalidValueError(section, key, "enum", v)
