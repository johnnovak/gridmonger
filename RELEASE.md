# Release process

## Release checklist

Before releasing anything, make sure that:

- [ ] Everything works as expected on all platforms
- [ ] The manual has been updated
- [ ] The CHANGELOG has been updated
- [ ] Theme files have been updated (if needed)
- [ ] Example maps have been updated (if needed)
- [ ] All commits have been pushed up to the repo


## Windows specific requirements

Use the 64-bit Nim compiler and install the 32 and 64-bit MinGW compiler
dependencies from the [official Nim downloads
page](https://nim-lang.org/install_windows.html). Adjust the value of
`mingW32Dir` in `config.nims` so it points to your MinGW32 installation.

The installer executable is generated by [NSIS](https://nsis.sourceforge.io)
(Nullsoft Scriptable Install System). Install NSIS first, then make sure
`makensis.exe` is available on the path.

The documentation related tasks must be executed under WSL on Windows.


## Build instructions

All commands below must be executed from the project root directory.


### 1. Update current version

Bump up the version in `CURRENT_VERSION` and `docs/latest_version`, then
commit and push the changes.


### 2. Build the manual

*NOTE: It is important to build the manual before the release packages as
they include the manual.*

```
nim manual
```


### 3. Build, package and publish the release packages

*NOTE: Every package must be built on their respective OSes.*

#### Windows

**64-bit**

```
nim -f release
nim packageWinInstaller
nim packageWinPortable
nim publishPackageWin
```

**32-bit**

```
nim -f --cpu:i386 release
nim --cpu:i386 packageWinInstaller
nim --cpu:i386 packageWinPortable
nim --cpu:i386 publishPackageWin
```

(Or execute `scripts/build-win.bat`)

Commit and push the changes in `docs/`.


#### macOS

```
nim -f releaseMacX64
nim -f releaseMacArm64
nim mergeMacUniversal
nim packageMac
nim publishPackageMac
```

(Or execute `scripts/build-mac.sh`)

Commit and push the changes in `docs/`.


### 4. Package and publish extras

```
nim packageManual
nim packageExampleMaps
nim publishExtras
```

(Or execute `scripts/build-extras.sh` or `scripts/build-extras.bat`)

Commit and push the changes in `docs/`.


### 5. Build and publish the website

```
nim website
```

Commit and push the changes in `docs/`.


### 6. Tag the release

```
git tag vX.Y.Z && git push --tags
```


### 7. Create release branch

```
git checkout -b release-vX.Y.Z
git push --set-upstream origin release-vX.Y.Z
```

