#!/bin/bash
#
# Build whisper.xcframework for the OpenSuperWhisperiOS target.
#
# The iOS target links libwhisper/whisper.cpp/build-apple/whisper.xcframework, which is a build
# product (ignored by the submodule) and must exist before the target builds. This runs
# whisper.cpp's own build-xcframework.sh unchanged: iOS 16.4+ device and simulator slices
# (plus the other Apple platforms it always builds), Metal embedded, OpenMP off.
#
# Usage:  ./Scripts/build-ios-whisper.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER="$ROOT/libwhisper/whisper.cpp"

if [ ! -f "$WHISPER/build-xcframework.sh" ]; then
	echo "whisper.cpp submodule missing: run git submodule update --init --recursive" >&2
	exit 1
fi
command -v cmake > /dev/null || { echo "cmake not found (brew install cmake)" >&2; exit 1; }

cd "$WHISPER"
./build-xcframework.sh
# CMake's configure step rewrites this tracked file's version; put it back so the submodule stays clean.
git checkout -- bindings/javascript/package.json 2> /dev/null || true
echo "Built $WHISPER/build-apple/whisper.xcframework"
