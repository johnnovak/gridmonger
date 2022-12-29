#!/bin/bash

nim -f releaseMacX64
nim -f releaseMacArm64
nim releaseMacUniversal
nim packageMac
nim publishPackageMac

