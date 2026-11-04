#!/bin/sh
# Run Flutter with the selected Xcode available to native asset hooks.
set -eu
exec "$(dirname "$0")/with_xcode.sh" flutter "$@"
