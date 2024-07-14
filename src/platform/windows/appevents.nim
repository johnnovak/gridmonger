import std/cmdline
import std/options

import winim/lean

import ../../common
import ipc

# {{{ isAppRunning()
proc isAppRunning(): bool =
  discard CreateMutex(nil, true, "Global\\Gridmonger")
  result = GetLastError() == ErrorAlreadyExists

# }}}

# {{{ winInitOrQuit*()
proc winInitOrQuit*() =
  if isAppRunning():
    if ipc.initClient():
      if paramCount() == 0:
        ipc.sendFocusMessage()
      else:
        ipc.sendOpenFileMessage(paramStr(1))
    quit()
  else:
    discard ipc.initServer()

# }}}
# {{{ winTryRecv*()
proc winTryRecv*(): Option[AppEvent] =
  ipc.tryRecv()

# }}}
# {{{ winShutdown*()
proc winShutdown*() =
  ipc.shutdown()

# }}}

# {{{ Test
when isMainModule:
  import std/os

  echo "Starting..."
  if isAppRunning():
    echo "*** CLIENT ***"
    if initClient():
      ipc.sendOpenFileMessage("quixotic")
      ipc.shutdown()

  else:
    if ipc.initServer():
      echo "*** SERVER ***"
      while true:
        let msg = tryRecv()
        if msg.isSome:
          echo msg.get
        sleep(100)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
