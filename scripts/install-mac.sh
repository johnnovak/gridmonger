#!/usr/bin/env bash

set -e

ROOT=$(git rev-parse --show-toplevel)
cd $ROOT/dist/macos

VERSION=$($ROOT/scripts/get-version.sh version)
ZIP_FILE=gridmonger-v$VERSION-macos.zip
unzip -q $ZIP_FILE

rm -rf /Applications/Gridmonger.app
mv Gridmonger.app /Applications
