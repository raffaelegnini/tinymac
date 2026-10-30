#!/bin/bash
# Points the Homebrew casks at a new release: ./scripts/update-tap.sh 1.2.0
# Expects the tap checked out next to this repo (../homebrew-tinymac) and the zips built by ./build.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$1
TAP=../homebrew-tinymac

for pair in tinymac:TinyMac tinymac-plus:TinyMacPlus; do
    cask=${pair%%:*} exe=${pair##*:}
    sha=$(shasum -a 256 "dist/$exe-$VERSION-macOS.zip" | cut -d' ' -f1)
    sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$TAP/Casks/$cask.rb"
done
cd "$TAP"
brew style Casks/*.rb
git commit -am "Update TinyMac to $VERSION"
git push
