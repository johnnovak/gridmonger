<img src="extras/logo/logo-big-bw.png" width="100%" alt="Gridmonger" />

<p align="center"><em>Your trusty old-school cRPG companion</em></p>

<p align="center"><b>Work in progress, not ready for public use yet!</b></p>

## Dependencies

* koi
* nim-glfw (`gridmonger` branch)
* nim-nanovg
* nim-osdialog
* nim-riff
* winim

## Compiling

Debug build (debug logging enabled, file dialogs disabled on Windows ):

```
nim debug
```

Release build:

```
nim release
```

## Packacing

Create 32/64-bit Windows installers (required `makensis.exe` in the path):

```
nim packageWin32
nim packageWin32Portable
nim packageWin64
nim packageWin64Portable
```

Create Mac OS X application bundle:

```
nim packageMac
```

## License

Developed by John Novak <<john@johnnovak.net>>, 2020-2022

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net/), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

