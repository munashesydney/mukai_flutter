#!/usr/bin/env python3
"""Install APNs entitlements; Apple App ID/signing setup is still required once."""
import plistlib
import re
import shutil
from pathlib import Path
root = Path(__file__).resolve().parent.parent
plist = root / 'ios/Runner/Info.plist'
value = plistlib.loads(plist.read_bytes())
value['MukaiAPNSEnvironment'] = '$(MUKAI_APNS_ENVIRONMENT)'
value['UIBackgroundModes'] = sorted(set(value.get('UIBackgroundModes', []) + ['remote-notification']))
plist.write_bytes(plistlib.dumps(value))
project = root / 'ios/Runner.xcodeproj/project.pbxproj'
def configure(match):
    body, mode = match.group(1), match.group(2)
    if 'PRODUCT_BUNDLE_IDENTIFIER = com.mukai.mukaiFlutter;' not in body:
        return match.group(0)
    body = re.sub(r'\n\s*(?:CODE_SIGN_ENTITLEMENTS|MUKAI_APNS_ENVIRONMENT) = [^;]*;', '', body)
    environment = 'development' if mode == 'Debug' else 'production'
    body += f'\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\tMUKAI_APNS_ENVIRONMENT = {environment};'
    return 'buildSettings = {' + body + '\n\t\t\t};\n\t\t\tname = ' + mode + ';'
text = re.sub(r'buildSettings = \{([\s\S]*?)\n\t\t\t\};\n\t\t\tname = (Debug|Release|Profile);', configure, project.read_text())
project.write_text(text)
shutil.copyfile(root / 'native/ios/Runner.entitlements', root / 'ios/Runner/Runner.entitlements')
shutil.copyfile(root / 'native/ios/AppDelegate.swift', root / 'ios/Runner/AppDelegate.swift')
