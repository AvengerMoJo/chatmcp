#!/usr/bin/env bash
set -euo pipefail

PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
pkg_file="$(find "$PUB_CACHE_DIR/hosted/pub.dev" -path "*/speech_to_text-*/darwin/speech_to_text/Package.swift" | head -n 1)"

if [ -z "${pkg_file:-}" ]; then
  echo "speech_to_text Package.swift not found in pub cache: $PUB_CACHE_DIR" >&2
  exit 1
fi

echo "Patching speech_to_text package: $pkg_file"

if grep -q '\.macOS("10\.14")' "$pkg_file"; then
  if sed --version >/dev/null 2>&1; then
    sed -i 's/\.macOS("10\.14")/.macOS("10.15")/g' "$pkg_file"
  else
    sed -i '' 's/\.macOS("10\.14")/.macOS("10.15")/g' "$pkg_file"
  fi
fi

grep -n '\.macOS' "$pkg_file"
echo "speech_to_text macOS SwiftPM target patch completed."
