#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x "build/Lemmings Mac.app/Contents/MacOS/LemmingsMac" ]; then
    ./build.sh
fi
open "$PWD/build/Lemmings Mac.app"
