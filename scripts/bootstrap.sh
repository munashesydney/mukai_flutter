#!/usr/bin/env bash
#
# Prepares this Flutter client for a real iOS build.
#
# The repository deliberately carries Dart, assets, tests and config — but not
# the Xcode/Gradle host app, which is generated per machine. This script
# generates the iOS project, restores anything the generator wanted to rewrite,
# then fetches dependencies and runs the checks.
#
#   scripts/bootstrap.sh
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# ---------------------------------------------------------------------------
# 1. Toolchain
# ---------------------------------------------------------------------------
if ! command -v flutter >/dev/null 2>&1; then
  cat <<'EOF'
Flutter isn't on your PATH.

  brew install --cask flutter

…or follow https://docs.flutter.dev/get-started/install/macos, then re-run
this script (you may need to add Flutter to PATH first — the installer prints
the line, it's usually):

  export PATH="$PATH:/opt/homebrew/bin"

Xcode is also required for an iOS build (it's already installed, but if
`flutter doctor` complains, run:

  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -runfirstlaunch
EOF
  exit 1
fi

flutter --version
echo

# ---------------------------------------------------------------------------
# 2. Protect the hand-written files
# ---------------------------------------------------------------------------
# `flutter create .` is friendly but it does touch files it considers
# scaffolding, and pubspec.yaml is the one we care about: the package name in
# it is what every `package:mukai_flutter/...` import resolves to.
BACKUP="$(mktemp -d)"
trap 'rm -rf "$BACKUP"' EXIT

for file in pubspec.yaml .gitignore analysis_options.yaml README.md; do
  if [ -f "$file" ]; then
    cp "$file" "$BACKUP/$file"
  fi
done

# ---------------------------------------------------------------------------
# 3. Generate the iOS host app
# ---------------------------------------------------------------------------
flutter create . \
  --platforms=ios \
  --org com.mukai \
  --project-name mukai_flutter
echo

for file in pubspec.yaml .gitignore analysis_options.yaml README.md; do
  if [ -f "$BACKUP/$file" ] && ! cmp -s "$BACKUP/$file" "$file"; then
    cp "$BACKUP/$file" "$file"
    echo "restored $file"
  fi
done

# Its starter test contradicts the real suite in test/.
if [ -f test/widget_test.dart ]; then
  rm test/widget_test.dart
  echo "removed test/widget_test.dart (generated stub)"
fi

# ---------------------------------------------------------------------------
# 4. Dependencies and checks
# ---------------------------------------------------------------------------
python3 - <<'PYPLIST'
import plistlib
import shutil
from pathlib import Path
path = Path('ios/Runner/Info.plist')
with path.open('rb') as stream:
    value = plistlib.load(stream)
value['CFBundleDisplayName'] = 'Mukai'
value['CFBundleURLTypes'] = [item for item in value.get('CFBundleURLTypes', []) if item.get('CFBundleURLName') != 'com.mukai.mobile.oauth'] + [{'CFBundleURLName': 'com.mukai.mobile.oauth', 'CFBundleURLSchemes': ['com.mukai.mobile']}]
value['NSLocalNetworkUsageDescription'] = 'Connect to the Mukai server you host on your local network.'
value.setdefault('NSAppTransportSecurity', {})['NSAllowsLocalNetworking'] = True
with path.open('wb') as stream:
    plistlib.dump(value, stream)

# Flutter's native asset hooks retain PATH but filter DEVELOPER_DIR. Apply the
# same SDK lookup wrapper to builds launched directly from Xcode.
project = Path('ios/Runner.xcodeproj/project.pbxproj')
text = project.read_text()
original = r'/bin/sh \"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\"'
wrapped = r'/bin/sh \"$SRCROOT/../scripts/with_xcode.sh\" ' + original
if wrapped not in text:
    text = text.replace(original, wrapped)
project.write_text(text)

# Keep the native Quick Look bridge reproducible when regenerating the host.
Path('ios/Runner/AppDelegate.swift').write_text(Path('native/ios/AppDelegate.swift').read_text())

# Keep the opaque Mukai app icons when regenerating the iOS host.
shutil.copytree(
    'native/ios/AppIcon.appiconset',
    'ios/Runner/Assets.xcassets/AppIcon.appiconset',
    dirs_exist_ok=True,
)
PYPLIST

python3 scripts/configure_push.py

flutter pub get
flutter analyze
flutter test

cat <<'EOF'

Ready.

  open -a Simulator && scripts/ios.sh run        # iPhone simulator, hot reload on
  flutter devices                         # see your own iPhone when plugged in
  scripts/ios.sh run -d <id>                     # …and run on it

Open ios/Runner.xcworkspace in Xcode if you need signing, capabilities or a
device build without the CLI.
EOF
