<img src="extras/logo/logo-big-bw.png" width="100%" alt="Gridmonger" />

<p align="center"><em>Your trusty old-school cRPG mapping companion</em></p>

## Project homepage

[https://gridmonger.johnnovak.net](https://gridmonger.johnnovak.net)

## Build instructions

Requires [Nim](https://nim-lang.org/) 2.0.2

### Dependencies

* [koi](https://github.com/johnnovak/koi)
* [nim-glfw](https://github.com/johnnovak/nim-glfw)
* [nim-nanovg](https://github.com/johnnovak/nim-nanovg/)
* [nim-osdialog](https://github.com/johnnovak/nim-osdialog)
* [nim-riff](https://github.com/johnnovak/nim-riff)
* [winim](https://github.com/khchen/winim)

You can install the dependencies with [Nimble](https://github.com/nim-lang/nimble):

```
nimble install koi glfw nanovg osdialog riff winim
```


### Compiling

Debug build (debug logging enabled, file dialogs disabled):

```
nim debug
```

Release build (file dialogs enabled):

```
nim release
```

Run `nim help` for the full list of build tasks.


**NOTE:** Create an empty directory `Config` in the project root directory to
enable portable mode (that's what you normally want during development).


### Building the manual & website

The [website](https://gridmonger.johnnovak.net) (GitHub Pages site) and
[manual](https://gridmonger.johnnovak.net/manual/contents.html) are generated
from [Sphinx](https://www.sphinx-doc.org) sources.

The website is published from the `/docs` directory of the `master` branch.

#### Requirements

- [Sphinx](https://www.sphinx-doc.org/en/master/usage/installation.html) 7.2+
- [Sass](https://sass-lang.com/) 1.57+
- [Make](https://www.gnu.org/software/make/) 3.8+
- [GNU sed](https://www.gnu.org/software/sed/) 4.9+
- Zip 3.0+


#### Building

- To build the website, run `nim site`

- To build the manual, run `nim manual`

- To create the zipped distribution package of the manual from the generated
  files, run `nim packageManual`

- Check out the [release build instructions](https://github.com/johnnovak/gridmonger/blob/master/RELEASE.md#build-instructions) for further details.

#### Theme development

You can run `make watch_docs_css` or `make watch_frontpage_css` from the
`sphinx-doc` directory to regenerate the CSS when the SASS files are changed
during theme development.


### Packaging & release process

See [RELEASE.md](/RELEASE.md)


## License

Developed by John Novak <<john@johnnovak.net>>, 2020-2024

This work is free. You can redistribute it and/or modify it under the terms of
the [Do What The Fuck You Want To Public License, Version 2](http://www.wtfpl.net), as published
by Sam Hocevar. See the [COPYING](./COPYING) file for more details.

