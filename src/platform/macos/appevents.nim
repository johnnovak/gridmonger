import std/options
import std/os
import std/typedthreads

import glfw

import ../../common
import ../../utils


type ThreadData = object
  running:   bool
  filenames: seq[string]
  hasData:   bool

var
  g_thread:     Thread[void]
  g_threadData: ptr ThreadData

# {{{ pollOpenedFilenamesFunc()
proc pollOpenedFilenamesFunc() {.thread.} =
  alias(t, g_threadData)

  while t.running:
    if not t.hasData:
      let filenames = getCocoaOpenedFilenames()
      if filenames.len > 0:
        t.filenames = filenames
        t.hasData = true

        # Main event loop might be stuck at waitEvents(), so wake it up
        postEmptyEvent()

    sleep(100)

# }}}

# {{{ initOrQuit*()
proc initOrQuit*(): bool =
  g_threadData = cast[ptr ThreadData](alloc0(sizeof(ThreadData)))
  g_threadData.running = true

  createThread(g_thread, pollOpenedFilenamesFunc)
  true

# }}}
# {{{ tryReceiveEvent*()
proc tryReceiveEvent*(): Option[AppEvent] =
  alias(t, g_threadData)

  if t.hasData:
    let filenames = t.filenames
    if filenames.len > 0:
      result = AppEvent(kind: aeOpenFile, path: filenames[0]).some
      t.hasData = false

# }}}
# {{{ shutdown*()
proc shutdown*() =
  g_threadData.running = false
  joinThread(g_thread)

# }}}

# vim: et:ts=2:sw=2:fdm=marker
