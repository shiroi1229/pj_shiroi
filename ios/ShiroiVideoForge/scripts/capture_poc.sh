#!/bin/bash
# Dedicated simulator and exact operation ID: old output cannot pass this run.
set -euo pipefail
mkdir -p output/poc
xcrun simctl list devices available --json > output/poc/simulator-devices.json
read -r TYPE RUNTIME < <(python3 - <<'PY'
import json
from pathlib import Path
candidates=[]
for runtime, devices in json.loads(Path('output/poc/simulator-devices.json').read_text())['devices'].items():
    if '.iOS-' not in runtime: continue
    version=tuple(int(x) for x in runtime.split('iOS-')[-1].split('-') if x.isdigit())
    for d in devices:
        if d.get('isAvailable') and 'iPad Pro' in d['name']:
            candidates.append(((version, int('13-inch' in d['name']), d['name']),d['deviceTypeIdentifier'],runtime))
if not candidates: raise SystemExit('No available iPad Pro simulator.')
_,device,runtime=max(candidates)
print(device,runtime)
PY
)
RUN_ID=$(python3 -c 'import uuid; print(str(uuid.uuid4()).upper())')
UDID=$(xcrun simctl create "Shiroi-POC-$RUN_ID" "$TYPE" "$RUNTIME")
BUNDLE=com.shiroi1229.ShiroiVideoForge
REC_PID=""
cleanup() {
  if [ -n "$REC_PID" ]; then kill -INT "$REC_PID" 2>/dev/null || true; wait "$REC_PID" 2>/dev/null || true; fi
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" 'build-poc/Build/Products/Release-iphonesimulator/Shiroi Video Forge.app'
APP_DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
export APP_DATA RUN_ID
xcrun simctl io "$UDID" recordVideo --codec=h264 output/poc/app-screen-recording.mp4 > output/poc/recording.log 2>&1 &
REC_PID=$!
sleep 1
kill -0 "$REC_PID"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" --poc-autostart --poc-profile hd --poc-run "$RUN_ID" > output/poc/launch.log
python3 - <<'PY'
import os,time
from pathlib import Path
report=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'/os.environ['RUN_ID']/'poc-result.json'
for _ in range(300):
    if report.exists(): break
    time.sleep(1)
else: raise SystemExit('This exact render did not complete in 300s; no earlier result accepted.')
PY
sleep 3
xcrun simctl io "$UDID" screenshot output/poc/app-screen.png
sleep 6
kill -INT "$REC_PID"
set +e
wait "$REC_PID"; RECORD_EXIT=$?
set -e
REC_PID=""
if [ "$RECORD_EXIT" -ne 0 ] && [ "$RECORD_EXIT" -ne 130 ]; then echo "Recording failed ($RECORD_EXIT)"; exit 1; fi
swiftc -swift-version 5 Tests/CaptureRecordingCheck.swift -o "$RUNNER_TEMP/check-capture"
"$RUNNER_TEMP/check-capture" output/poc/app-screen-recording.mp4 output/poc/recording-check.json
# Relaunch, without rendering: the library must recover this same saved result.
xcrun simctl terminate "$UDID" "$BUNDLE"
xcrun simctl launch "$UDID" "$BUNDLE" --poc-library-check > output/poc/reopen.log
python3 - <<'PY'
import os,time,json,shutil
from pathlib import Path
folder=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'/os.environ['RUN_ID']
for _ in range(30):
    if (folder/'poc-reopened.json').exists(): break
    time.sleep(1)
else: raise SystemExit('Library did not restore this result after relaunch.')
reopen=json.loads((folder/'poc-reopened.json').read_text())
assert reopen['selected_id']==os.environ['RUN_ID'] and reopen['history_count']==1
assert reopen['render_started'] is False
for name in ['poc-result.json','poc-video.mov','poc-poster.png','poc-reopened.json']:
    shutil.copy2(folder/name, Path('output/poc')/name)
evidence=json.loads((folder/'poc-result.json').read_text())
assert evidence['status']=='passed' and evidence['decodedFrames']==144
assert (evidence['width'],evidence['height'])==(1280,720)
assert evidence['aiInference'] is False and 'Simulator' in evidence['host']
assert Path('output/poc/app-screen.png').read_bytes()[:8]==b'\x89PNG\r\n\x1a\n'
evidence.update(source_commit=os.environ['GITHUB_SHA'], capture_run_id=os.environ['RUN_ID'],
                capture='fresh dedicated simulator; real framebuffer', library_reopen='passed', signed_installation=False)
Path('output/poc/capture-evidence.json').write_text(json.dumps(evidence,indent=2))
print(json.dumps(evidence,indent=2))
PY
sleep 2
xcrun simctl io "$UDID" screenshot output/poc/app-reopened.png
xcrun simctl terminate "$UDID" "$BUNDLE"
