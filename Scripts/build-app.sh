#!/usr/bin/env bash
# Builds GitPulse.app (release, ad-hoc signed). Used by `make install` and the release workflow.
#
# Environment:
#   VERSION       CFBundleShortVersionString (default: "dev (<short sha>)", or "dev")
#   BUILD_NUMBER  CFBundleVersion (default: 0)
#   UNIVERSAL     1 = arm64 + x86_64 (needs full Xcode)
#   OUTPUT_DIR    where GitPulse.app is written (default: .build/app)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GitPulse"
OUTPUT_DIR="${OUTPUT_DIR:-.build/app}"
BUILD_NUMBER="${BUILD_NUMBER:-0}"

if [[ -z "${VERSION:-}" ]]; then
  if sha="$(git rev-parse --short HEAD 2>/dev/null)"; then
    VERSION="dev (${sha})"
  else
    VERSION="dev"
  fi
fi

build_args=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  build_args+=(--arch arm64 --arch x86_64)
fi

swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"

iconset=".build/AppIcon.iconset"
icns=".build/AppIcon.icns"
if [[ ! -f "$icns" || Support/genicon.swift -nt "$icns" ]]; then
  rm -rf "$iconset"
  mkdir -p "$iconset"
  swift Support/genicon.swift "$iconset"
  iconutil -c icns "$iconset" -o "$icns"
fi

app="${OUTPUT_DIR}/${APP_NAME}.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app/Contents/Info.plist"
cp "${bin_dir}/${APP_NAME}" "$app/Contents/MacOS/${APP_NAME}"
cp "$icns" "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"

echo "Built ${app} (version ${VERSION}, build ${BUILD_NUMBER})"
