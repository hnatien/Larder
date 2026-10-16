#!/bin/bash
# Points the toolchain at Xcode.app when xcode-select still targets the Command Line Tools.
if [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
