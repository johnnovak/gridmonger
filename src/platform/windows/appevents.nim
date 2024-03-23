import std/cmdline
import std/options

import ipc

# {{{ isAppRunning()
proc isAppRunning(): bool =
  discard CreateMutex(nil, true, "Global\\Gridmonger")
  result = GetLastError() == ErrorAlreadyExists

# }}}

# {{{ initOrQuit*()
proc initOrQuit*(): bool =
  if isAppRunning():
    if ipc.initClient():
      if paramCount() == 0:
        ipc.sendFocusMessage()
      else:
        ipc.sendOpenFileMessage(paramStr(1))
    quit()
  else:
    ipc.initServer()

# }}}
# {{{ tryReceiveEvent*()
proc tryReceiveEvent*(): Option[AppEvent] =
  ipc.tryReceiveMessage()

# }}}
# {{{ shutdown*()
proc shutdown*() =
  ipc.shutdown()

# }}}

# {{{ Test
when isMainModule:
  import std/os

  echo "Starting..."
  if isAppRunning():
    echo "*** CLIENT ***"
    if initClient():
      sendOpenFileMessage("quixotic")
      ipc.shutdown()

  else:
    if initServer():
      echo "*** SERVER ***"
      while true:
        let msg = tryReceiveMessage()
        if msg.isSome:
          echo msg.get
        sleep(100)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
