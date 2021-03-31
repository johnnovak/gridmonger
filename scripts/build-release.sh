#!/bin/bash

nim c -d:release --app:gui --out:gridmonger.exe "$@" src/main
