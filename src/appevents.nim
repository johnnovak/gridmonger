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

import glfw
import semver

import common


# {{{ macFileOpener()
when defined(macosx):
  type
    OpenFileMsg = enum
      ofmShutdown

  var
    g_macFileOpenerCh:  Channel[OpenFileMsg]
    g_macFileOpenerThr: Thread[void]

  proc macFileOpener() {.thread.} =
    while true:
      let (dataAvailable, msg) = g_macFileOpenerCh.tryRecv
      if dataAvailable and msg == ofmShutdown:
        break

      let filenames = glfw.getCocoaOpenedFilenames()
      if filenames.len > 0:
        sendAppEvent(AppEvent(kind: aeOpenFile, path: filenames[0]))

      sleep(100)

# }}}

# {{{ Auto-saver
type
  AutoSaverMsgKind = enum
    askMapSaved, askSetTimeout, askShutdown

  AutoSaverMsg* = object
    case kind*: AutoSaverMsgKind
    of askMapSaved:   discard
    of askSetTimeout: timeout*: Duration
    of askShutdown:   discard

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
      of askShutdown: break
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
    vfkFetch, vfkShutdown

var
  g_versionFetcherCh:  Channel[VersionFetcherMsg]
  g_versionFetcherThr: Thread[void]

# {{{ versionFetcher()
proc versionFetcher() {.thread.} =
  const
    LatestVersionUrl   = fmt"{ProjectHomeUrl}latest_version"
    NumTries           = 5
    TickDurationMs     = 100
    RetryIntervalMs    = 2000
    RetryIntervalTicks = ceil(RetryIntervalMs / TickDurationMs).int

  block topLoop:
    while true:
      let msg = g_versionFetcherCh.recv
      case msg
      of vfkShutdown:
        break topLoop

      of vfkFetch:
        var
          event    = AppEvent(kind: aeVersionUpdate)
          response = ""

          numTry    = 1
          triesLeft = NumTries
          ticksLeft = RetryIntervalTicks

        while triesLeft > 0:
          while ticksLeft > 0:
            # We drain messages at the tick interval to avoid the process
            # potentially hanging for the retry sleep duration at exit.
            let (dataAvailable, msg) = g_versionFetcherCh.tryRecv
            if dataAvailable:
              case msg
              of vfkShutdown: break topLoop
              of vfkFetch:    discard # fetch already in progress

            var client = newHttpClient()
            try:
              response = client.getContent(LatestVersionUrl)
              break
            except CatchableError as e:
              event.error = cast[CatchableError](e[]).some
            finally:
              client.close

            sleep(TickDurationMs)
            dec(ticksLeft)

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

  elif defined(macosx):
    g_macFileOpenerCh.send(ofmShutdown)
    joinThread(g_macFileOpenerThr)
    g_macFileOpenerCh.close

  g_autoSaverCh.send(AutoSaverMsg(kind: askShutdown))
  g_versionFetcherCh.send(vfkShutdown)

  joinThreads(g_autoSaverThr, g_versionFetcherThr)

  g_autoSaverCh.close
  g_versionFetcherCh.close

  g_appEventCh.close

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
    g_macFileOpenerCh.open
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
