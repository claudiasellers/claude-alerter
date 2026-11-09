#!/bin/bash
# Build Claude Alerter.  ./build.sh          -> build/ClaudeAlerter.app
#                        ./build.sh install  -> also copy to ~/Applications and (re)launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/ClaudeAlerter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeAlerter "$APP/Contents/MacOS/ClaudeAlerter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  DEST="$HOME/Applications/ClaudeAlerter.app"
  mkdir -p "$HOME/Applications"
  pkill -x ClaudeAlerter 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
