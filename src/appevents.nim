import std/exitprocs
import std/httpclient
import std/math
import std/monotimes
import std/options
import std/os
import std/strformat
import std/strutils
import std/times
import std/typedthreads

import semver

import common

when defined(windows):
  import platform/windows/ipc

# {{{ macFileOpener()
when defined(macosx):
  import glfw

  var g_macFileOpenerThr: Thread[void]

  proc macFileOpener() {.thread.} =
    while true:
      let filenames = glfw.getCocoaOpenedFilenames()
      if filenames.len > 0:
        sendAppEvent(AppEvent(kind: aeOpenFile, path: filenames[0]))

      sleep(100)

# }}}

# {{{ Auto-saver
type
  AutoSaverMsgKind = enum
    askMapSaved, askSetTimeout

  AutoSaverMsg* = object
    case kind*: AutoSaverMsgKind
    of askMapSaved:   discard
    of askSetTimeout: timeout*: Duration

var
  g_autoSaverCh:  Channel[AutoSaverMsg]
  g_autoSaverThr: Thread[void]

# {{{ autoSaver()
proc autoSaver() {.thread.} =
  var
    t0 = getMonoTime()
    timeout = initDuration(minutes = 2)

  while true:
    let (dataAvailable, msg) = g_autoSaverCh.tryRecv
    if dataAvailable:
      case msg.kind
      of askMapSaved: t0 = getMonoTime()
      of askSetTimeout:
        timeout = msg.timeout
        t0 = getMonoTime()

    if timeout != DurationZero:
      if getMonoTime() - t0 > timeout:
        sendAppEvent(AppEvent(kind: aeAutoSave))
        t0 = getMonoTime()

    sleep(100)

# }}}

# {{{ updateLastSavedTime*()
proc updateLastSavedTime*() =
  g_autoSaverCh.send(AutoSaverMsg(kind: askMapSaved))

# }}}
# {{{ setAutoSaveTimeout*()
proc setAutoSaveTimeout*(timeout: Duration) =
  g_autoSaverCh.send(AutoSaverMsg(kind: askSetTimeout, timeout: timeout))

# }}}
# {{{ disableAutoSave*()
proc disableAutoSave*() =
  g_autoSaverCh.send(AutoSaverMsg(kind: askSetTimeout, timeout: DurationZero))

# }}}

# }}}
# {{{ Version fetcher
type
  VersionFetcherMsg = enum
    vfkFetch

var
  g_versionFetcherCh:  Channel[VersionFetcherMsg]
  g_versionFetcherThr: Thread[void]

# {{{ versionFetcher()
proc versionFetcher() {.thread.} =
  const
    LatestVersionUrl = fmt"{ProjectHomeUrl}latest_version"
    NumTries         = 5
    RetryIntervalMs  = 2000

  while true:
    let msg = g_versionFetcherCh.recv
    case msg
    of vfkFetch:
      var
        event     = AppEvent(kind: aeVersionUpdate)
        response  = ""
        triesLeft = NumTries

      while triesLeft > 0:
        var client = newHttpClient()
        try:
          response = client.getContent(LatestVersionUrl)
          break
        except CatchableError as e:
          event.error = cast[CatchableError](e[]).some
        finally:
          client.close

        sleep(RetryIntervalMs)
        dec(triesLeft)

      if response != "":
        try:
          let parts = response.split("|")
          event.versionInfo = VersionInfo(
            version: parseVersion(parts[0]),
            message: parts[1]
          ).some
        except: discard

      sendAppEvent(event)

# }}}

# {{{ fetchLatestVersion*()
proc fetchLatestVersion*() =
  g_versionFetcherCh.send(vfkFetch)

# }}}

# }}}

# {{{ shutdown()
proc shutdown() =
  when defined(windows):
    ipc.shutdownServer()

  # All these background threads can be auto-killed by the OS on exit, there's
  # no need to shut them down cleanly. All they do is send events to the main
  # thread that then performs some action, so they can be safely interrupted.
  #
  # Moreover, not waiting for the version fetcher thread fixes weird edge
  # cases when the thread hangs indefinitely on exit due to network timeouts.

# }}}

# {{{ initOrQuit*()
proc initOrQuit*() =
  g_appEventCh.open

  when defined(windows):
    if ipc.isAppRunning():
      discard ipc.initClient()
      quit()
    else:
      discard ipc.initServer()

  elif defined(macosx):
    createThread(g_macFileOpenerThr, macFileOpener)

  g_autoSaverCh.open
  createThread(g_autoSaverThr, autoSaver)

  g_versionFetcherCh.open
  createThread(g_versionFetcherThr, versionFetcher)

  addExitProc(shutdown)

# }}}
# {{{ tryRecv*()
proc tryRecv*(): Option[AppEvent] =
  let (dataAvailable, msg) = g_appEventCh.tryRecv
  if dataAvailable:
    result = msg.some

# }}}

# vim: et:ts=2:sw=2:fdm=marker
