# logging
#
# File-based logger init, log-file rotation, and a small wrapper for
# logging an exception with a stack trace.
# Side effects: file I/O (creates and rolls log files).

import std/logging as log except Level
import std/os

import main/appcontext
import utils/misc


using a: var AppContext


# {{{ rollLogFile(a)
proc rollLogFile*(a) =
  alias(p, a.paths)

  let fileNames = @[
    p.logFile & ".bak3",
    p.logFile & ".bak2",
    p.logFile & ".bak1",
    p.logFile
  ]

  for i, fname in fileNames:
    if fileExists(fname):
      if i == 0:
        discard tryRemoveFile(fname)
      else:
        try:
          moveFile(fname, fileNames[i-1])
        except CatchableError:
          discard

# }}}
# {{{ initLogger(a)
proc initLogger*(a) =
  rollLogFile(a)
  a.logFile = open(a.paths.logFile, fmWrite)

  var fileLog = newFileLogger(
    a.logFile,
    fmtStr = "[$levelname] $date $time - ",
    levelThreshold = if defined(DEBUG): lvlDebug else: lvlInfo
  )

  addHandler(fileLog)

# }}}
# {{{ logError()
proc logError*(e: ref Exception, msgPrefix: string = "") =
  var msg = "Error message: " & e.msg & "\n\nStack trace:\n" & getStackTrace(e)
  if msgPrefix != "":
    msg = msgPrefix & "\n" & msg

  log.error(msg)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
