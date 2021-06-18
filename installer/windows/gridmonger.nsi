; The name of the installer
Name "Gridmonger v0.9"

; The file to write
OutFile "install_gridmonger.exe"

; Request application privileges for Windows Vista and higher
RequestExecutionLevel admin

; Build Unicode installer
Unicode True

; The default installation directory
InstallDir $PROGRAMFILES64\Gridmonger

; Registry key to check for directory (so if you install again, it will 
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\Gridmonger" "InstallDir"


VIAddVersionKey "ProductName" "Gridmonger"
VIAddVersionKey "ProductVersion" "0.9.0.0"
VIAddVersionKey "LegalCopyright" "(c) John Novak 2019-2021"
VIAddVersionKey "FileDescription" "Gridmonger installer"
VIAddVersionKey "FileVersion" "0.9.0.0"

VIProductVersion 0.9.0.0

VIFileVersion 0.9.0.0


;=============================================================================
; Pages
;=============================================================================

Page license
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

  File /r Data
  File /r Manual
  File /r Themes
  File gridmonger.exe

  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\Gridmonger "InstallDir" "$INSTDIR"
  
  ; Write the uninstall keys for Windows
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gridmonger" "DisplayName" "Gridmonger"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gridmonger" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gridmonger" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gridmonger" "NoRepair" 1
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
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
    CreateDirectory "$SMPROGRAMS\Gridmonger"
    CreateShortcut "$SMPROGRAMS\Gridmonger\Uninstall.lnk" "$INSTDIR\uninstall.exe"
    CreateShortcut "$SMPROGRAMS\Gridmonger\Gridmonger.lnk" "$INSTDIR\Gridmonger.nsi"
  SectionEnd

  Section "Desktop icon"
  SectionEnd

SectionGroupEnd


;=============================================================================
; Uninstaller
;=============================================================================

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Gridmonger"
  DeleteRegKey HKLM SOFTWARE\Gridmonger

  ; Remove files and uninstaller
  Delete $INSTDIR\gridmonger.nsi
  Delete $INSTDIR\uninstall.exe

  ; Remove shortcuts, if any
  Delete "$SMPROGRAMS\Gridmonger\*.lnk"

  ; Remove directories
  RMDir "$SMPROGRAMS\Gridmonger"
  RMDir "$INSTDIR"

SectionEnd

