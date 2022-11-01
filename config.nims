import os
import strformat
import strutils


proc setCommonCompileParams() =
  --gc:orc
  --deepcopy:on
  --d:nimPreviewFloatRoundtrip
  --d:nvgGL3
  --d:glfwStaticLib
  switch "out", "gridmonger".toExe
  setCommand "c", "src/main"

task debug, "debug build":
  --d:debug
  setCommonCompileParams()


task releaseFull, "release build (no stacktrace)":
  --d:release
  --app:gui
  setCommonCompileParams()


task release, "release build (with stacktrace)":
  --stacktrace:on
  --linetrace:on
  releaseFullTask()


task strip, "strip executable":
  when defined(windows):
    exec "strip gridmonger.exe"
  else:
    exec "strip gridmonger"


task packageWin32, "create Windows 32-bit installer":
  stripTask()
  exec "makensis /DARCH32 gridmonger.nsi"


task packageWin64, "create Windows 64-bit installer":
  stripTask()
  exec "makensis /DARCH64 gridmonger.nsi"


task buildDocs, "build documentation package":
  # TODO make this more flexible, or merge the two repos
  cd "../gridmonger-site/"
  exec "make gen_html"
  exec "make dist_html"


task packageWinPortable, "create Windows portable package":
  stripTask()

  let outputDir = "dist/win-portable/Gridmonger"
  rmDir outputDir
  mkDir outputDir

  # Create config dir
  mkDir outputDir / "Config"

  # Copy main executable
  cpFile "gridmonger.exe", outputDir / "gridmonger.exe"

  # Copy resources
  cpDir "Data", outputDir / "Data"
  cpDir "Example Maps", outputDir / "Example Maps"
  cpDir "Manual", outputDir / "Manual"
  cpDir "Themes", outputDir / "Themes"


task packageMac, "create Mac app bundle":
  stripTask()

  let appBundleDir = "dist/Gridmonger.app"
  let contentsDir = appBundleDir / "Contents"
  let macOsDir = contentsDir / "MacOS"
  let resourcesDir = contentsDir / "Resources"

  let exeName = "Gridmonger"
  let distExePath = macOsDir / exeName
  let distName = "gridmonger-mac"
  let version = "0.91.0"

  rmDir appBundleDir
  mkDir contentsDir

  # Copy plist file & set version
#  sed "s/{VERSION}/$VERSION/g" Info.plist >$contentsDir/Info.plist
  cpFile "Info.plist", contentsDir / "Info.plist"

  # Copy main executable
  mkDir macOsDir
  cpFile exeName, distExePath

  # Copy resources
  mkDir resourcesDir
  cpDir "Data", resourcesDir / "Data"
  cpDir "Example Maps", resourcesDir / "Example Maps"
  cpDir "Manual", resourcesDir / "Manual"
  cpDir "Themes", resourcesDir / "Themes"
  cpFile "extras/appicons/mac/gridmonger.icns", resourcesDir / "gridmonger.icns"

  # Clean executable
  exec "chmod +x " & distExePath
  exec "strip -S " & distExePath
  exec "xattr -cr " & distExePath

  #codesign --verbose --sign "Developer ID Application: John Novak (VRF26934X5)" --options runtime --entitlements Entitlements.plist --deep dist/Gridmonger.app
  #codesign --verify --deep --strict --verbose=2 dist/Gridmonger.app

  # Make distribution ZIP file
  cd "dist"
  exec fmt"zip -q -9 -r {distName}.zip Gridmonger.app"

