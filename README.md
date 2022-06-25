<img src="extras/logo/logo-big-bw.png" width="100%" alt="Gridmonger" />

<p align="center"><em>Your trusty old-school cRPG mapping companion</em></p>

## Dependencies

* [koi](https://github.com/johnnovak/koi)
* [nim-glfw](https://github.com/johnnovak/nim-glfw) (`gridmonger` branch)
* [nim-nanovg](https://github.com/johnnovak/nim-nanovg/)
* [nim-osdialog](https://github.com/johnnovak/nim-osdialog)
* [nim-riff](https://github.com/johnnovak/nim-riff)
* [winim](https://github.com/khchen/winim)

## Compiling

Debug build (debug logging enabled, file dialogs disabled on Windows ):

```
nim debug
```

Release build:

```
nim release
```

## Packaging

Run `nim release` first to create a release build.

To create 32/64-bit Windows installers (requires `makensis.exe` on the path):

```
nim packageWin32
nim packageWin32Portable

nim packageWin64
nim packageWin64Portable
```

To create Mac OS X application bundle:

```
nim packageMac
```

## License

Developed by John Novak <<john@johnnovak.net>>, 2020-2022

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net/), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

