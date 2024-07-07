#!/usr/bin/env bash

nim -f releaseMacX64
nim -f releaseMacArm64
nim mergeMacUniversal
nim packageMacAppBundle
nim packageMacZip
nim publishPackageMac
