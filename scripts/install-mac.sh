#!/usr/bin/env bash

ROOT=$(git rev-parse --show-toplevel)

VERSION=$($ROOT/scripts/get-version.sh version)

ZIP_FILE=gridmonger-v$VERSION-macos.zip

cd dist/macos && \
	unzip -q $ZIP_FILE && \
	rm -rf /Applications/Gridmonger.app && \
	mv Gridmonger.app /Applications
