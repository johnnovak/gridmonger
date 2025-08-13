import std/math
import std/logging as log
import std/options
import std/strformat
import std/strutils
import std/unicode

import nanovg

import fieldlimits
import utils/colorspace
import utils/hocon


using cfg: HoconNode

# {{{ invalidValueError*()
proc invalidValueError(path, valueType, value: string) =
  let msg = fmt"Invalid {valueType} value for path '{path}': {value}"
  log.error(msg)

# }}}

# {{{ getObjectOrEmpty*()
proc getObjectOrEmpty*(cfg; path: string): HoconNode =
  try:
    let n = cfg.get(path)
    if n.kind != hnkObject:
      result = newHoconObject()
    else:
      result = n
  except CatchableError:
    result = newHoconObject()

# }}}
# {{{ getObjectOpt*()
proc getObjectOpt*(cfg; path: string): Option[HoconNode] =
  try:
    let n = cfg.get(path)
    if n.kind != hnkObject:
      result = HoconNode.none
    else:
      result = n.some
  except CatchableError:
    result = HoconNode.none

# }}}
# {{{ getStringOrDefault*()
proc getStringOrDefault*(cfg; path: string, default: string = ""): string =
  result = default
  try:
    result = cfg.getString(path)
  except CatchableError as e:
    log.error(e.msg)

# }}}

# {{{ `$`*(c: Color)
proc `$`*(c: Color): string =
  let
    r = round(c.r * 255).int
    g = round(c.g * 255).int
    b = round(c.b * 255).int
    a = round(c.a * 255).int
  fmt"#{r:02x}{g:02x}{b:02x}{a:02x}"

# }}}
# {{{ parseColor*()
proc parseColor*(s: string): Option[Color] =
  result = Color.none
  if s.len == 9 and s[0] == '#':
    try:
      let r = s[1..2].parseHexInt
      let g = s[3..4].parseHexInt
      let b = s[5..6].parseHexInt
      let a = s[7..8].parseHexInt
      result = rgba(r/255, g/255, b/255, a/255).some
    except ValueError:
      discard

# }}}
# {{{ getColorOrDefault*()
proc getColorOrDefault*(cfg; path: string, default: Color = black()): Color =
  result = default
  try:
    let v = cfg.getString(path)
    if v != "":
      let col = parseColor(v)
      if col.isNone:
        invalidValueError(path, "color", v)
      else:
        result = transformSrgbColor(col.get, g_colorSpace)
  except CatchableError as e:
    log.error(e.msg)

# }}}

# {{{ getBoolOrDefault*()
proc getBoolOrDefault*(cfg; path: string, default: bool = false): bool =
  result = default
  try:
    result = cfg.getBool(path)
  except CatchableError as e:
    log.error(e.msg)

# }}}
# {{{ getFloatOrDefault*()
proc getFloatOrDefault*(cfg; path: string, default: float = 0): float =
  result = default
  try:
    result = cfg.getFloat(path)
  except CatchableError as e:
    log.error(e.msg)

# }}}
# {{{ getIntOrDefault*()
proc getIntOrDefault*(cfg; path: string, default: int = 0): int =
  result = default
  try:
    result = cfg.getInt(path)
  except CatchableError as e:
    log.error(e.msg)

# }}}
# {{{ getNaturalOrDefault*()
proc getNaturalOrDefault*(cfg; path: string, default: Natural = 0): Natural =
  result = default
  try:
    result = cfg.getNatural(path)
  except CatchableError as e:
    log.error(e.msg)


proc getNaturalOrDefault*(cfg; path: string, limits: FieldLimits,
                          default: Natural = 0): Natural =
  try:
    result = default
    var i: int
    case limits.kind:
    of fkInt:
      i = cfg.getNatural(path)
      result = i.limit(limits)
    else:
      log.error(fmt"Invalid FieldLimits for Natural type: {limits}")
  except CatchableError as e:
    log.error(e.msg)

# }}}

# {{{ getEnumOrDefault*()
proc getEnumOrDefault*(cfg; path: string, T: typedesc[enum]): T =
  try:
    let v = cfg.getString(path)
    if v != "":
      try:
        result = parseEnum[T](v.replace('-', ' ').title)
      except ValueError:
        invalidValueError(path, "enum", v)
  except CatchableError as e:
    log.error(e.msg)

# }}}
# {{{ enumToDashCase*()
proc enumToDashCase*(val: string): string =
  val.toLower.replace(' ', '-')

# }}}

# vim: et:ts=2:sw=2:fdm=marker
