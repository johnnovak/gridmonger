REM 64-bit
nim -f release
nim packageWinInstaller
nim packageWinPortable
nim publishPackageWin

REM 32-bit
nim -f --cpu:i386 release
nim --cpu:i386 packageWinInstaller
nim --cpu:i386 packageWinPortable
nim --cpu:i386 publishPackageWin
