!include x64.nsh
!include MUI2.nsh
!include LogicLib.nsh
!include WinCore.nsh
!include Integration.nsh

!define NAME          "Gridmonger"
!define VERSION       "0.9"

!define APP_EXE       "gridmonger.exe"
!define UNINSTALL_EXE "uninstall.exe"

!define ASSOC_EXT     ".gmm"
!define ASSOC_PROGID  "${NAME}"
!define ASSOC_VERB    "Open with ${NAME}"

!define REGPATH_UNINSTSUBKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${NAME}"

!ifdef ARCH32
  !define ARCH "32"
!else
  !define ARCH "64"
!endif

Unicode True
RequestExecutionLevel admin

Function .onInit
  ${If} ${RunningX64}
    !ifdef ARCH32
      MessageBox MB_YESNO "This will install the 32-bit version of Gridmonger.$\r$\n$\r$\nYou are running 64-bit Windows, therefore installing the 64-bit version is recommended.$\r$\n$\r$\nDo you still wish to continue?" IDYES go
        Abort
      go:
    !endif
    SetRegView 64
  ${EndIf}
FunctionEnd

Name "${NAME}"
Caption "${NAME} ${VERSION} Setup - ${ARCH}-bit"
OutFile "gridmonger-${VERSION}-win${ARCH}-setup.exe"

!ifdef ARCH32
  InstallDir "$PROGRAMFILES32\${NAME}"
!else
  InstallDir "$PROGRAMFILES64\${NAME}"
!endif

VIAddVersionKey "ProductName" "${NAME}"
VIAddVersionKey "ProductVersion" "0.9.0.0"
VIAddVersionKey "LegalCopyright" "(c) John Novak 2019-2021"
VIAddVersionKey "FileDescription" "${NAME} installer"
VIAddVersionKey "FileVersion" "0.9.0.0"

VIProductVersion 0.9.0.0

VIFileVersion 0.9.0.0


;--------------------------------
;Interface Settings

!define MUI_ABORTWARNING
!define MUI_UNABORTWARNING

!define MUI_ICON   extras\appicons\windows\gridmonger.ico
!define MUI_UNICON extras\appicons\windows\gridmonger.ico

!define MUI_WELCOMEFINISHPAGE_BITMAP   extras\installer-images\welcome-finish.bmp
!define MUI_UNWELCOMEFINISHPAGE_BITMAP extras\installer-images\welcome-finish.bmp

;--------------------------------
;Pages

; Installer

!define MUI_WELCOMEPAGE_TITLE "Welcome to Gridmonger setup"
!define welcome1 "This wizard will guide you through the installation of Gridmonger.$\r$\n$\r$\n"
!define welcome2 "Please close all running instances of Gridmonger before proceeding.$\r$\n$\r$\n"
!define welcome3 "Click Next to continue."
!define MUI_WELCOMEPAGE_TEXT "${welcome1}${welcome2}${welcome3}"

!insertmacro MUI_PAGE_WELCOME

!define MUI_COMPONENTSPAGE_NODESC
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; Uninstaller

!define MUI_WELCOMEPAGE_TITLE "Welcome to Gridmonger uninstall"
!define unwelcome1 "This wizard will guide you through the uninstallation of Gridmonger.$\r$\n$\r$\n"
!define unwelcome2 "No data will be removed from your Gridmonger user folder (user themes, configuration, etc.)$\r$\n$\r$\n"
!define unwelcome3 "Please close all running instances of the program before proceeding.$\r$\n$\r$\n"
!define unwelcome4 "Click Next to continue."
!define MUI_WELCOMEPAGE_TEXT "${unwelcome1}${unwelcome2}${unwelcome3}${unwelcome4}"

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------
;Languages

!insertmacro MUI_LANGUAGE "English"

;--------------------------------


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


!macro RemoveShellIntegration un
  Function ${un}RemoveShellIntegration
    # Unregister file type
    ClearErrors
    DeleteRegKey ShCtx "Software\Classes\${ASSOC_PROGID}\shell\${ASSOC_VERB}"
    DeleteRegKey /IfEmpty ShCtx "Software\Classes\${ASSOC_PROGID}\shell"
    ${IfNot} ${Errors}
      DeleteRegKey ShCtx "Software\Classes\${ASSOC_PROGID}\DefaultIcon"
    ${EndIf}
    ReadRegStr $0 ShCtx "Software\Classes\${ASSOC_EXT}" ""
    DeleteRegKey /IfEmpty ShCtx "Software\Classes\${ASSOC_PROGID}"
    ${IfNot} ${Errors}
    ${AndIf} $0 == "${ASSOC_PROGID}"
      DeleteRegValue ShCtx "Software\Classes\${ASSOC_EXT}" ""
      DeleteRegKey /IfEmpty ShCtx "Software\Classes\${ASSOC_EXT}"
    ${EndIf}

    # Unregister "Default Programs"
    !ifdef REGISTER_DEFAULTPROGRAMS
    DeleteRegValue ShCtx "Software\RegisteredApplications" "${NAME}"
    DeleteRegKey ShCtx "Software\Classes\Applications\${APP_EXE}\Capabilities"
    DeleteRegKey /IfEmpty ShCtx "Software\Classes\Applications\${APP_EXE}"
    !endif

    # Attempt to clean up junk left behind by the Windows shell
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Search\JumplistData" "$INSTDIR\${APP_EXE}"
    DeleteRegValue HKCU "Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache" "$INSTDIR\${APP_EXE}.FriendlyAppName"
    DeleteRegValue HKCU "Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache" "$INSTDIR\${APP_EXE}.ApplicationCompany"
    DeleteRegValue HKCU "Software\Microsoft\Windows\ShellNoRoam\MUICache" "$INSTDIR\${APP_EXE}" ; WinXP
    DeleteRegValue HKCU "Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store" "$INSTDIR\${APP_EXE}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" "${ASSOC_PROGID}_${ASSOC_EXT}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\ApplicationAssociationToasts" "Applications\${APP_EXE}_${ASSOC_EXT}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\${ASSOC_EXT}\OpenWithProgids" "${ASSOC_PROGID}"
    DeleteRegKey /IfEmpty HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\${ASSOC_EXT}\OpenWithProgids"
    DeleteRegKey /IfEmpty HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\${ASSOC_EXT}\OpenWithList"
    DeleteRegKey /IfEmpty HKCU "Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\${ASSOC_EXT}"

    ${NotifyShell_AssocChanged}
  FunctionEnd
!macroend

!insertmacro RemoveShellIntegration ""
!insertmacro RemoveShellIntegration "un."


;=============================================================================
; Sections
;=============================================================================
Section "Gridmonger (required)" Gridmonger

  SectionIn RO

  SetOutPath $INSTDIR

  Call RemoveInstalledFiles
  Call RemoveShortcuts
  Call RemoveShellIntegration

  File /r Data
  File /r Manual
  File /r Themes
  File ${APP_EXE}

  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\${NAME} "InstallDir" "$INSTDIR"

  ; Write the uninstall keys for Windows
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "DisplayName"      "${NAME}"
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "DisplayIcon"      "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "InstallLocation"  $INSTDIR
  WriteRegStr HKLM ${REGPATH_UNINSTSUBKEY} "UninstallString"  '"$INSTDIR\${UNINSTALL_EXE}"'

  WriteRegDWORD HKLM ${REGPATH_UNINSTSUBKEY} "NoModify" 1
  WriteRegDWORD HKLM ${REGPATH_UNINSTSUBKEY} "NoRepair" 1

  WriteUninstaller "$INSTDIR\${UNINSTALL_EXE}"

SectionEnd

;-----------------------------------------------------------------------------
;
Section "Desktop icon" Shortcuts_Desktop
  CreateShortcut "$DESKTOP\${NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

Section "Start Menu icon" Shortcuts_StartMenu
  CreateShortcut "$SMPROGRAMS\${NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

;-----------------------------------------------------------------------------

Section "Associate with GMM (Gridmonger Map) files" Shell_FileAssoc
  # Register file type
  WriteRegStr ShCtx "Software\Classes\${ASSOC_PROGID}\DefaultIcon" "" "$INSTDIR\${APP_EXE},0"
  WriteRegStr ShCtx "Software\Classes\${ASSOC_PROGID}\shell\${ASSOC_VERB}\command" "" '"$INSTDIR\${APP_EXE}" "%1"'
  WriteRegStr ShCtx "Software\Classes\${ASSOC_EXT}" "" "${ASSOC_PROGID}"

  # Register "Default Programs"
  WriteRegStr ShCtx "Software\Classes\Applications\${APP_EXE}\Capabilities" "ApplicationDescription" "${NAME}"
  WriteRegStr ShCtx "Software\Classes\Applications\${APP_EXE}\Capabilities\FileAssociations" "${ASSOC_EXT}" "${ASSOC_PROGID}"
  WriteRegStr ShCtx "Software\RegisteredApplications" "${NAME}" "Software\Classes\Applications\${APP_EXE}\Capabilities"

  ${NotifyShell_AssocChanged}
SectionEnd

;-----------------------------------------------------------------------------

SectionGroup /e "Optional features" Optional

  Section "Example maps" Optional_ExampleMaps
    SetOutPath $INSTDIR
    File /r "Example Maps"
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
  Call un.RemoveShellIntegration

  ; Remove directories
  RMDir /r "$INSTDIR"
  RMDir "$INSTDIR\.."

SectionEnd

