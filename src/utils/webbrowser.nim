# webbrowser
#
# Browser-launch helpers. Tiny wrappers over std/browsers that centralize
# project conventions for opening external content.
# Side effects: OS exec (spawns a browser process).

import std/browsers
import std/os


proc openUserManual*(manualDir: string) =
  openDefaultBrowser(manualDir / "index.html")


# vim: et:ts=2:sw=2:fdm=marker
