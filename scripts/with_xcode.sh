#!/bin/sh
# Keep the selected Xcode visible to native-asset hooks, which filter environment
# variables but retain PATH. This changes only this command's environment.
set -eu
MUKAI_XCODE_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ ! -d "$MUKAI_XCODE_DIR" ]; then
  echo 'Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi
export DEVELOPER_DIR="$MUKAI_XCODE_DIR"
MUKAI_BUILD_BIN=$(mktemp -d)
trap 'rm -rf "$MUKAI_BUILD_BIN"' EXIT HUP INT TERM
# Embed the selected path as a quoted shell literal; paths containing a quote
# are rejected rather than interpreted as code.
case "$MUKAI_XCODE_DIR" in *\'*) echo 'Unsupported quote in Xcode path.' >&2; exit 1;; esac
printf '#!/bin/sh\nexport DEVELOPER_DIR=\047%s\047\nexec /usr/bin/xcrun "$@"\n' "$MUKAI_XCODE_DIR" > "$MUKAI_BUILD_BIN/xcrun"
chmod +x "$MUKAI_BUILD_BIN/xcrun"
export PATH="$MUKAI_BUILD_BIN:$PATH"
"$@"
