import std/asyncdispatch
import std/httpclient
import std/monotimes
import std/options
import std/strutils
import std/times

import semver


const
  LatestVersionUrl = "https://gridmonger.johnnovak.net/latest_version"
  RetryInterval = initDuration(seconds = 2)
  MaxTries = 5

type
  VersionChecker* = object
    f:       Future[string]
    nextTry: MonoTime
    retries: Natural

  VersionInfo* = object
    version*: Version
    message*: string


proc initVersionChecker*(v: var VersionChecker) =
  v.f       = nil
  v.nextTry = getMonoTime()
  v.retries = 0

proc fetchLatestVersion(): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  try:
    return await client.getContent(LatestVersionUrl)
  finally:
    client.close


proc tryFetchLatestVersion*(v: var VersionChecker): Option[VersionInfo] =
  try:
    if v.f == nil and getMonoTime() > v.nextTry:
      v.f = fetchLatestVersion()

    else:
      asyncdispatch.poll(0)

      if v.f != nil and v.f.finished:
        if v.f.failed:
          let ex = v.f.readError
          raise ex
        else:
          let s = v.f.read
          let parts = s.split("|")
          v.f = nil

          result = VersionInfo(
            version: parseVersion(parts[0]),
            message: parts[1]
          ).some

  except ValueError as e:
    # asyncdispatch.poll() can throw ValueError in some circumstances, then
    # a bit later we the HttpRequestError.
    discard
  except HttpRequestError as e:
    inc(v.retries)
    if v.retries < MaxTries:
      echo "retry"
      v.nextTry = getMonoTime() + RetryInterval
      v.f = nil
    else:
      raise e

