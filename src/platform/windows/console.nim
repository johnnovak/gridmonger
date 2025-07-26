import std/exitprocs

import winim

# Adapted from
# https://www.tillett.info/2013/05/13/how-to-create-a-windows-program-that-works-as-both-as-a-gui-and-console-application/

proc sendReturnKeypress() =
  let h = GetConsoleWindow()
  if IsWindow(h):
    PostMessage(h, WM_KEYUP, VK_RETURN, 0)


proc attachOutputToConsole*(): bool =
  ## Allow console output for Windows GUI applications compiled with the
  ## --app:gui flag

  if AttachConsole(AttachParentProcess) != 0:
    if GetStdHandle(StdOutputHandle) != InvalidHandleValue:
      discard stdout.reopen("CONOUT$", fmWrite)
    else: return

    if GetStdHandle(StdErrorHandle) != InvalidHandleValue:
      discard stderr.reopen("CONOUT$", fmWrite)
    else: return

    setStdIoUnbuffered()

    # Windows waits for the user to press "Enter" before releasing the
    # console after exit, so we'll simulate that here
    addExitProc(sendReturnKeypress)

    result = true

