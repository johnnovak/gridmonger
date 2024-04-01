import std/httpclient
import std/monotimes
import std/options
import std/os
import std/strutils
import std/times
import std/typedthreads

import glfw
import semver

when defined(windows):
  import platform/windows/ipc


# {{{ Types
type
  AppEventKind* = enum
    aeFocus, aeOpenFile, aeAutoSave, aeVersionUpdate

  AppEvent* = object
    case kind*: AppEventKind
    of aeOpenFile:
      path*: string
    of aeVersionUpdate:
      versionInfo*: Option[VersionInfo]
      error*:        Option[CatchableError]
    else: discard

  VersionInfo* = object
    version*: Version
    message*: string

# }}}

var
  g_initialised = false
  g_appEventCh: Channel[AppEvent]

# {{{ sendAppEvent()
proc sendAppEvent(event: AppEvent) =
  g_appEventCh.send(event)

  # Main event loop might be stuck at waitEvents(), so wake it up
  glfw.postEmptyEvent()

# }}}

# {{{ File opener
type
  OpenFileMsg = enum
    fokShutdown

var
  g_fileOpenerCh:  Channel[OpenFileMsg]
  g_fileOpenerThr: Thread[void]

# {{{ fileOpener()
when defined(macosx):

  proc fileOpener {.thread.} =
    while true:
      let (dataAvailable, msg) = g_fileOpenerCh.tryRecv
      if dataAvailable and msg == fokShutdown:
        break

      let filenames = glfw.getCocoaOpenedFilenames()
      if filenames.len > 0:
        sendAppEvent(AppEvent(kind: aeOpenFile, path: filenames[0]))

      sleep(100)

# }}}

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
proc autoSaver {.thread.} =
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

# }}}
# {{{ Version fetcher
type
  VersionFetcherMsg = enum
    vfkFetch, vfkShutdown

var
  g_versionFetcherCh:  Channel[VersionFetcherMsg]
  g_versionFetcherThr: Thread[void]

# {{{ versionFetcher()
proc versionFetcher {.thread.} =
  const
    LatestVersionUrl = "https://gridmonger.johnnovak.net/latest_version"
    MaxTries = 5

  while true:
    let msg = g_versionFetcherCh.recv
    case msg
    of vfkShutdown: break

    of vfkFetch:
      var
        event    = AppEvent(kind: aeVersionUpdate)
        numTry   = 1
        response = ""

      while true:
        var client = newHttpClient()
        try:
          response = client.getContent(LatestVersionUrl)
          break
        except CatchableError as e:
          event.error = cast[CatchableError](e[]).some
        finally:
          client.close

        inc(numTry)
        if numTry > MaxTries: break
        sleep(2000)

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

# }}}

# {{{ initOrQuit*()
proc initOrQuit*: bool =
  g_appEventCh.open

  g_fileOpenerCh.open
  createThread(g_fileOpenerThr, fileOpener)

  g_autoSaverCh.open
  createThread(g_autoSaverThr, autoSaver)

  g_versionFetcherCh.open
  createThread(g_versionFetcherThr, versionFetcher)
  true

# }}}
# {{{ shutdown*()
proc shutdown* =
  g_fileOpenerCh.send(fokShutdown)
  g_autoSaverCh.send(AutoSaverMsg(kind: askShutdown))
  g_versionFetcherCh.send(vfkShutdown)

  joinThreads(g_fileOpenerThr, g_autoSaverThr, g_versionFetcherThr)

  g_fileOpenerCh.close
  g_autoSaverCh.close
  g_versionFetcherCh.close

  g_appEventCh.close

# }}}
# {{{ tryRecvAppEvent*()
proc tryRecv*: Option[AppEvent] =
  let (dataAvailable, msg) = g_appEventCh.tryRecv
  if dataAvailable:
    result = msg.some

# }}}

# {{{ fetchLatestVersion*()
proc fetchLatestVersion* =
  g_versionFetcherCh.send(vfkFetch)

# }}}

# {{{ updateLastSavedTime*()
proc updateLastSavedTime* =
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

# vim: et:ts=2:sw=2:fdm=marker
