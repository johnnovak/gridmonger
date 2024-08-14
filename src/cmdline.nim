import std/options
import std/parseopt
import std/strformat
import std/strutils

import common

# {{{ WindowConfig*
type
  WindowConfig* = object
    layout*:         Option[Natural]
    x*, y*:          Option[int]
    width*, height*: Option[int]
    maximized*:      Option[bool]
    showTitleBar*:   Option[bool]

# }}}

# {{{ printHelp()
proc printHelp() =
  echo """
Usage:
  gridmonger [OPTIONS] [FILE]

Options:
  -c, --configFile:PATH       Use this config file

  -l, --layout:INT            Restore window layout N (from 1 to 4)

  -x, --xpos:INT              Override window X position
  -y, --ypos:INT              Override window Y position
  -w, --width:INT             Override window width
  -h, --height:INT            Override window height
  -m, --maximized:on|off      Override maximized state
  -t, --showTitleBar:on|off   Override show title bar state

      --help                  Print help
      --version               Print version information"""

# }}}
# {{{ printVersion()
proc printVersion() =
  echo fmt"""
{FullVersionString}
{CompiledAt}

{DevelopedBy}
{ProjectHomeUrl}"""

# }}}
# {{{ quitWithError()
proc quitWithError(msg: string) {.noReturn.} =
  when defined(windows):
    echo ""
  quit(fmt"Error: {msg}", QuitFailure)

# }}}
# {{{ checkOptArgumentProvided()
proc checkOptArgumentProvided(opt, arg: string) =
  if arg == "":
    quitWithError(fmt"missing argument for option '{opt}'")

# }}}
# {{{ parseIntOpt()
proc parseIntOpt(opt, arg: string): int =
  checkOptArgumentProvided(opt, arg)
  try:
    parseInt(arg)
  except CatchableError:
    quitWithError(fmt"invalid integer argument for option '{opt}': {arg}")

# }}}
# {{{ parseBoolOpt()
proc parseBoolOpt(opt, arg: string): bool =
  checkOptArgumentProvided(opt, arg)
  try:
    parseBool(arg)
  except CatchableError:
    quitWithError(fmt"invalid boolean argument for option '{opt}': {arg}")

# }}}
# {{{ parseCommandLineParams*()
proc parseCommandLineParams*(): tuple[configFile, mapFile: Option[string],
                                      winCfg: WindowConfig] =
  var
    configFile, mapFile: Option[string]
    numArgs = 0
    winCfg: WindowConfig

  for kind, opt, arg in getopt():
    case kind
    of cmdArgument:
      if numArgs == 1:
        quitWithError("cannot provide more than file argument")
      mapFile = opt.some
      inc(numArgs)

    of cmdLongOption, cmdShortOption:
      case opt
      of "layout", "l":
        let layout = parseIntOpt(opt, arg)
        if (layout < 0 or layout > 4):
          quitWithError(fmt"invalid layout number: must be between 1 and 4")
        winCfg.layout = (layout - 1).Natural.some

      of "xpos",   "x": winCfg.x      = parseIntOpt(opt, arg).some
      of "ypos",   "y": winCfg.y      = parseIntOpt(opt, arg).some
      of "width",  "w": winCfg.width  = parseIntOpt(opt, arg).some
      of "height", "h": winCfg.height = parseIntOpt(opt, arg).some

      of "maximized", "m":
        winCfg.maximized = parseBoolOpt(opt, arg).some

      of "showTitleBar", "t":
        winCfg.showTitleBar = parseBoolOpt(opt, arg).some

      of "configFile", "c": configFile = arg.some

      of "help":
        printHelp()
        quit()

      of "version", "v":
        printVersion()
        quit()

      else:
        quitWithError(fmt"invalid option: {opt}")

    of cmdEnd:
      assert false  # cannot happen

  result = (configFile, mapFile, winCfg)

# }}}

# {{{ Test
when isMainModule:
  let (configFile, mapFile, winCfg) = parseCommandLineParams()

  echo fmt"configFile: {configFile}"
  echo fmt"mapFile: {mapFile}"
  echo fmt"winCfg: {winCfg}"
# }}}

# vim: et:ts=2:sw=2:fdm=marker
