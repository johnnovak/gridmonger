!define NAME          "Gridmonger"
!define VERSION       "0.9"

!define APP_EXE       "gridmonger.exe"
!define UNINSTALL_EXE "uninstall.exe"

!define REGPATH_UNINSTSUBKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${NAME}"


Name "${NAME} ${VERSION}"
OutFile "gridmonger-${VERSION}-win64-setup.exe"

Unicode True
RequestExecutionLevel admin

; The default installation directory
InstallDir $PROGRAMFILES64\${NAME}

; Registry key to check for directory (so if you install again, it will
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\${NAME}" "InstallDir"


VIAddVersionKey "ProductName" "Gridmonger"
VIAddVersionKey "ProductVersion" "0.9.0.0"
VIAddVersionKey "LegalCopyright" "(c) John Novak 2019-2021"
VIAddVersionKey "FileDescription" "Gridmonger installer"
VIAddVersionKey "FileVersion" "0.9.0.0"

VIProductVersion 0.9.0.0

VIFileVersion 0.9.0.0



!macro RemoveInstalledFiles un
  Function ${un}RemoveInstalledFiles
    RMDir /r $INSTDIR\Data
    RMDir /r "$INSTDIR\Example Maps"
    RMDir /r $INSTDIR\Manual
    RMDir /r $INSTDIR\Themes
    Delete $INSTDIR\${APP_EXE}
    Delete $INSTDIR\${UNINSTALL_EXE}
  FunctionEnd
!macroend
 
!insertmacro RemoveInstalledFiles ""
!insertmacro RemoveInstalledFiles "un."


!macro RemoveShortcuts un
  Function ${un}RemoveShortcuts
    Delete "$SMPROGRAMS\${NAME}.lnk"
    Delete "$DESKTOP\${NAME}.lnk"
  FunctionEnd
!macroend
 
!insertmacro RemoveShortcuts ""
!insertmacro RemoveShortcuts "un."


;=============================================================================
; Pages
;=============================================================================

Page components
Page directory
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

;=============================================================================
; Sections
;=============================================================================
Section "Gridmonger (required)"

  SectionIn RO

  SetOutPath $INSTDIR

  Call RemoveInstalledFiles
  Call RemoveShortcuts

  File /r Data
  File /r Manual
  File /r Themes
  File ${APP_EXE}

  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\${NAME} "InstallDir" "$INSTDIR"

  ; Write the uninstall keys for Windows
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "DisplayName"      "Gridmonger"
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "DisplayIcon"      "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "InstallLocation"  $INSTDIR
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "UninstallString"  '"$INSTDIR\${UNINSTALL_EXE}"'

  WriteRegDWORD HKLM ${REGPATH_UNINSTSUBKEY} "NoModify" 1
  WriteRegDWORD HKLM ${REGPATH_UNINSTSUBKEY} "NoRepair" 1

  WriteUninstaller "$INSTDIR\${UNINSTALL_EXE}"
  
SectionEnd

;-----------------------------------------------------------------------------

SectionGroup /e "Optional features"

  Section "Example maps (recommended)"
    SetOutPath $INSTDIR
    File /r "Example Maps"
  SectionEnd

SectionGroupEnd

;-----------------------------------------------------------------------------

SectionGroup /e "Shortcut icons"

  Section "Start Menu icon"
    CreateShortcut "$SMPROGRAMS\${NAME}.lnk" "$INSTDIR\${APP_EXE}"
  SectionEnd

  Section "Desktop icon"
    CreateShortcut "$DESKTOP\${NAME}.lnk" "$INSTDIR\${APP_EXE}"
  SectionEnd

SectionGroupEnd


;=============================================================================
; Uninstaller
;=============================================================================

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM ${REGPATH_UNINSTSUBKEY}
  DeleteRegKey HKLM SOFTWARE\${NAME}

  Call un.RemoveInstalledFiles
  Call un.RemoveShortcuts

  ; Remove directories
  RMDir "$INSTDIR"

SectionEnd

