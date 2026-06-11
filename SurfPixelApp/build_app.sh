#!/bin/bash
# Build SurfPixel.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/SurfPixel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SurfPixel "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "built $APP"
