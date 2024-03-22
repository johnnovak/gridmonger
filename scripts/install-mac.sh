#!/usr/bin/env bash

cd dist/macos && \
	unzip -q gridmonger-*.zip && \
	rm -rf /Applications/Gridmonger.app && \
	mv Gridmonger.app /Applications

