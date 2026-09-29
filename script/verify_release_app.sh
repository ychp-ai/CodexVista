#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <CodexVista.app>" >&2
  exit 2
fi

APP_PATH="$1"
BUNDLE_ID="com.ychp.CodexVista"
test -d "$APP_PATH"
ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
if [[ "$ACTUAL_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
  echo "error: unexpected app bundle identifier: $ACTUAL_BUNDLE_ID" >&2
  exit 1
fi

ARCHITECTURES="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/CodexVista")"
[[ " $ARCHITECTURES " == *" arm64 "* ]]
[[ " $ARCHITECTURES " == *" x86_64 "* ]]

# A linker's ad-hoc Mach-O signature is not a signature of the app bundle.
# TCC needs a valid bundle identity and sealed Info.plist/resources to match
# a previously granted permission. Verify every slice and nested code too.
# This accepts Xcode's ad-hoc signature; it does not imply Developer ID trust.
/usr/bin/codesign --verify --deep --strict --all-architectures \
  -R="identifier \"$BUNDLE_ID\"" "$APP_PATH"

echo "Verified Universal app bundle signature: $APP_PATH"
