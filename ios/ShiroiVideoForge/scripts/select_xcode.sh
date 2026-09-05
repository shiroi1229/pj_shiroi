#!/bin/bash
# Do not rely on the runner's default Xcode or XcodeGen's project metadata.
set -euo pipefail
DEVELOPER_DIR=$(python3 - <<'PY'
import glob, plistlib, re
from pathlib import Path
candidates=[]
for name in glob.glob('/Applications/Xcode*.app'):
    path=Path(name)
    if any(x in path.resolve().name.lower() for x in ('beta','rc')): continue
    try:
        info=plistlib.loads((path/'Contents/Info.plist').read_bytes())
        version=str(info.get('CFBundleShortVersionString',''))
        if not re.fullmatch(r'\d+(\.\d+){1,2}',version): continue
        parts=tuple(int(v) for v in version.split('.'))
        if parts[0] >= 26: candidates.append((parts,path/'Contents/Developer'))
    except (OSError,ValueError,plistlib.InvalidFileException): continue
if not candidates: raise SystemExit('No stable Xcode 26+ installed; use a supported macOS runner image.')
print(max(candidates,key=lambda x:x[0])[1])
PY
)
export DEVELOPER_DIR
xcodebuild -version
SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
  echo '::error::App Store Connect requires iOS/iPadOS 26 SDK or newer.'; exit 1
fi
echo "Using iOS SDK $SDK_VERSION"
if [ -n "${GITHUB_ENV:-}" ]; then echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"; fi
