import std/os

import ../../common

import glfw

var g_macFileOpenerThr: Thread[void]

proc macFileOpener() {.thread.} =
  while true:
    let filenames = glfw.getCocoaOpenedFilenames()
    if filenames.len > 0:
      sendAppEvent(AppEvent(kind: aeOpenFile, path: filenames[0]))
    sleep(100)

proc init*() =
  createThread(g_macFileOpenerThr, macFileOpener)


# vim: et:ts=2:sw=2:fdm=marker
