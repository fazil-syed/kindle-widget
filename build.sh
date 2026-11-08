#!/bin/zsh
# build.sh — build the universal2 binary, assemble the release tarball,
# and print its sha256 (for the Homebrew cask).
#
#   ./build.sh            # version from latest git tag, or 0.0.0-dev
#   ./build.sh 0.1.0

set -euo pipefail
cd "$(dirname "$0")"

VER=${1:-0.0.0-dev}
SDK="macosx"

echo "==> building arm64"
MACOSX_DEPLOYMENT_TARGET=14.0 swiftc -O -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --sdk $SDK --show-sdk-path)" src/kindle-progress.swift -o /tmp/kw-arm

echo "==> building x86_64"
MACOSX_DEPLOYMENT_TARGET=14.0 swiftc -O -target x86_64-apple-macos14.0 \
  -sdk "$(xcrun --sdk $SDK --show-sdk-path)" src/kindle-progress.swift -o /tmp/kw-x64

echo "==> lipo"
lipo -create /tmp/kw-arm /tmp/kw-x64 -output /tmp/kw-universal

echo "==> assemble"
rm -rf build/pkg build/kindle-progress
mkdir -p build/pkg
cp /tmp/kw-universal build/pkg/kindle-progress
cp src/widget-data.sh src/kindle src/kindle.jsx build/pkg/
chmod +x build/pkg/widget-data.sh build/pkg/kindle build/pkg/kindle-progress

echo "==> tarball"
mkdir -p dist
TARBALL="dist/kindle-widget_${VER}_Darwin_all.tar.gz"
tar -czf "$TARBALL" -C build/pkg .

echo "==> checksums"
TARBALL_SHA=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
BINARY_SHA=$(shasum -a 256 build/pkg/kindle-progress | awk '{print $1}')
echo "tarball:  sha256 = $TARBALL_SHA"
echo "          path   = $TARBALL"
echo "binary:   sha256 = $BINARY_SHA"
