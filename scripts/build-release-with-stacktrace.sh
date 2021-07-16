#!/bin/bash

nim c -d:release --stacktrace:on --linetrace:on --app:gui \
    --out:gridmonger.exe "$@" src/main
