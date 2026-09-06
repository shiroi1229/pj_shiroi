#!/bin/bash
# Launch the real simulator app; capture its framebuffer and exported video.
set -euo pipefail
mkdir -p output/poc
xcrun simctl list devices available --json > output/poc/simulator-devices.json
UDID=$(python3 - <<'PY'
import json
from pathlib import Path
p=json.loads(Path('output/poc/simulator-devices.json').read_text())
candidates=[]
for runtime, devices in p['devices'].items():
    if '.iOS-' not in runtime: continue
    version=tuple(int(x) for x in runtime.split('iOS-')[-1].split('-') if x.isdigit())
    for d in devices:
        if d.get('isAvailable') and 'iPad Pro' in d['name']:
            candidates.append(((version, int('13-inch' in d['name']), d['name']),d['udid']))
if not candidates: raise SystemExit('No available iPad Pro simulator. Do not fabricate a screenshot.')
print(max(candidates)[1])
PY
)
BUNDLE=com.shiroi1229.ShiroiVideoForge
REC_PID=""
cleanup() {
  if [ -n "$REC_PID" ]; then kill -INT "$REC_PID" 2>/dev/null || true; wait "$REC_PID" 2>/dev/null || true; fi
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" 'build-poc/Build/Products/Release-iphonesimulator/Shiroi Video Forge.app'
xcrun simctl io "$UDID" recordVideo --codec=h264 output/poc/app-screen-recording.mp4 > output/poc/recording.log 2>&1 &
REC_PID=$!
xcrun simctl launch --terminate-running-process --console-pty "$UDID" "$BUNDLE" --poc-autostart > output/poc/app-console.log 2>&1 &
LAUNCH_PID=$!
APP_DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
export APP_DATA
python3 - <<'PY'
import os,time
from pathlib import Path
root=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'
for _ in range(240):
    if root.exists() and (list(root.glob('*/poc-result.json')) or list(root.glob('*/poc-failure.json'))): break
    time.sleep(1)
else: raise SystemExit('App did not produce a completion/failure marker in 240 s')
PY
sleep 2
xcrun simctl io "$UDID" screenshot output/poc/app-screen.png
sleep 5
kill -INT "$REC_PID"; wait "$REC_PID" || true
REC_PID=""
python3 - <<'PY'
import os,json,shutil
from pathlib import Path
root=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'
reports=list(root.glob('*/poc-result.json'))
failed=list(root.glob('*/poc-failure.json'))
if failed: shutil.copy2(failed[-1], 'output/poc/poc-failure.json')
if not reports: raise SystemExit('POC render did not pass; see app log and failure JSON')
report=reports[-1]
for name in ['poc-result.json','poc-video.mov','poc-poster.png']:
    shutil.copy2(report.parent/name, Path('output/poc')/name)
evidence=json.loads(report.read_text())
assert evidence['status']=='passed' and evidence['decodedFrames']==144
assert evidence['aiInference'] is False
assert 'Simulator' in evidence['host']
evidence.update(source_commit=os.environ['GITHUB_SHA'], capture='real iPad simulator framebuffer, not a mockup', signed_installation=False)
Path('output/poc/capture-evidence.json').write_text(json.dumps(evidence,indent=2))
print(json.dumps(evidence,indent=2))
PY
xcrun simctl terminate "$UDID" "$BUNDLE" || true
wait "$LAUNCH_PID" || true
