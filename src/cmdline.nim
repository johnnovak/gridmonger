import std/options
import std/parseopt
import std/strformat
import std/strutils

import common
import utils/hocon


proc printHelp() =
  echo """
Usage:
  gridmonger [OPTIONS] [FILE]

Options:
  -c, --configFile:PATH       Use this config file

  -x, --xpos:INT              Override window X position
  -y, --ypos:INT              Override window Y position
  -W, --width:INT             Override window width
  -H, --height:INT            Override window height
  -m, --maximized:on|off      Override window maximized state
  -t, --showTitleBar:on|off   Override show window title bar state

  -h, --help                  Print help
  -v, --version               Print version information"""

proc printVersion() =
  echo fmt"""
{FullVersionString}
{CompiledAt}
{DevelopedBy}
{ProjectHomeUrl}"""


proc quitWithError(msg: string) {.noReturn.} =
  when defined(windows):
    echo ""
  quit(fmt"Error: {msg}", QuitFailure)


proc checkOptArgumentProvided(opt, arg: string) =
  if arg == "":
    quitWithError(fmt"missing argument for option '{opt}'")


proc parseNaturalOpt(opt, arg: string): Natural =
  checkOptArgumentProvided(opt, arg)
  try:
    let i = parseInt(arg)
    if i < 0:
      quitWithError(fmt"argument for option '{opt}' must be positive: {arg}")
    i.Natural
  except CatchableError:
    quitWithError(fmt"invalid integer argument for option '{opt}': {arg}")


proc parseBoolOpt(opt, arg: string): bool =
  checkOptArgumentProvided(opt, arg)
  try:
    parseBool(arg)
  except CatchableError:
    quitWithError(fmt"invalid boolean argument for option '{opt}': {arg}")


proc parseCommandLineParams*(): tuple[configFile, mapFile: Option[string],
                                      winCfg: HoconNode] =
  var
    configFile, mapFile: Option[string]
    numArgs = 0
    winCfg = newHoconObject()

  for kind, opt, arg in getopt():
    case kind
    of cmdArgument:
      if numArgs == 1:
        quitWithError("cannot provide more than file argument")
      mapFile = opt.some
      inc(numArgs)

    of cmdLongOption, cmdShortOption:
      case opt
      of "xpos", "x":   winCfg.set("x-position", parseNaturalOpt(opt, arg))
      of "ypos", "y":   winCfg.set("y-postion",  parseNaturalOpt(opt, arg))
      of "width", "W":  winCfg.set("width",      parseNaturalOpt(opt, arg))
      of "height", "H": winCfg.set("height",     parseNaturalOpt(opt, arg))
 
      of "maximized", "m":
        winCfg.set("maximized", parseBoolOpt(opt, arg))

      of "showTitleBar", "t":
        winCfg.set("show-title-bar", parseBoolOpt(opt, arg))

      of "configFile", "c": configFile = arg.some

      of "help", "h":
        printHelp()
        quit()

      of "version", "v":
        printVersion()
        quit()

      else:
        quitWithError(fmt"invalid option: {opt}")

    of cmdEnd:
      assert(false) # cannot happen

  result = (configFile, mapFile, winCfg)


when isMainModule:
  let (configFile, mapFile, winCfg) = parseCommandLineParams()

  echo fmt"configFile: {configFile}"
  echo fmt"mapFile: {mapFile}"
  echo fmt"winCfg: {winCfg}"

