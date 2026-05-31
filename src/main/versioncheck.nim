# versioncheck
#
# State reset for the background version-fetch result. The actual HTTP
# fetch is in appevents.nim; this module just clears AppContext fields.
# Side effects: none (just AppContext field mutation).

import std/options

import common         # VersionInfo
import main/appcontext


using a: var AppContext


# {{{ initVersionChecking()
proc initVersionChecking*(a) =
  a.latestVersion     = VersionInfo.none
  a.versionFetchError = CatchableError.none

# }}}

# vim: et:ts=2:sw=2:fdm=marker
