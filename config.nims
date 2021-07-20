import os
import strformat
import strutils


proc setCommonCompileParams() =
  --gc:arc
  --deepcopy:on
  --D:nvgGL3
  --D:glfwStaticLib
  hint "Performance", false 
  switch "out", "gridmonger".toExe
  setCommand "c", "src/main"

task debug, "debug build":
  --d:debug
  setCommonCompileParams()

task release, "release build":
  --d:release
  --app:gui
  setCommonCompileParams()

task releaseStacktrace, "release build with stacktrace":
  --stacktrace:on
  --linetrace:on
  releaseTask()


task packageMac, "create Mac app bundle":
  let contentsDir = "dist/Gridmonger.app/Contents/"
  let macOsDir = contentsDir / "MacOS"
  let resourcesDir = contentsDir / "Resources"

  let exeName = "Gridmonger"
  let distExePath = macOsDir / exeName
  let distName = "gridmonger-macosx"
  let version = "1.0"

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
  cpFile "gridmonger.icns", resourcesDir / "gridmonger.icns"

  # Clean executable
  exec "chmod +x " & distExePath
  exec "strip -S " & distExePath
  exec "xattr -cr " & distExePath

  #codesign --verbose --sign "Developer ID Application: John Novak (VRF26934X5)" --options runtime --entitlements Entitlements.plist --deep dist/Gridmonger.app
  #codesign --verify --deep --strict --verbose=2 dist/Gridmonger.app

  # Make distribution ZIP file
#  cd dist && zip -q -9 -r $DIST_NAME.zip Gridmonger.app
