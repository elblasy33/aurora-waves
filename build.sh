#!/usr/bin/env bash
# Build an installable .plasmoid (what the KDE Store and "Install from file" expect).
#   ./build.sh            -> dist/aurora-waves-<version>.plasmoid
set -e
cd "$(dirname "$0")"
version=$(python3 -c 'import json;print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')
mkdir -p dist
out="dist/aurora-waves-${version}.plasmoid"
rm -f "$out"
(cd package && zip -qr -X "../$out" . -x '*/__pycache__/*' '*.pyc')
echo "$out"
