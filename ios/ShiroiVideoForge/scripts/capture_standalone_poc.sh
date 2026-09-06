#!/bin/bash
# Real standalone app, dedicated simulator, exact operation and output.
set -euo pipefail
mkdir -p output/poc
xcrun simctl list devices available --json > output/poc/simulators.json
read -r TYPE RUNTIME < <(python3 - <<'PY'
import json
from pathlib import Path
candidates=[]
for runtime,devices in json.loads(Path('output/poc/simulators.json').read_text())['devices'].items():
    if '.iOS-' not in runtime: continue
    version=tuple(int(x) for x in runtime.split('iOS-')[-1].split('-') if x.isdigit())
    for d in devices:
        if d.get('isAvailable') and 'iPad Pro' in d['name']:
            candidates.append(((version,int('13-inch' in d['name']),d['name']),d['deviceTypeIdentifier'],runtime))
if not candidates: raise SystemExit('No available iPad Pro simulator')
_,device,runtime=max(candidates)
print(device,runtime)
PY
)
RUN_ID=$(python3 -c 'import uuid; print(str(uuid.uuid4()).upper())')
UDID=$(xcrun simctl create "Shiroi-Standalone-$RUN_ID" "$TYPE" "$RUNTIME")
BUNDLE=com.shiroi1229.ShiroiVideoForge
export RUN_ID
APP_DATA=""
cleanup() {
  status=$?
  if [ -n "$APP_DATA" ]; then
    export APP_DATA
    python3 - <<'KEEP' || true
import os,shutil
from pathlib import Path
root=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'
for folder in [root/os.environ['RUN_ID'],root/'.pending'/os.environ['RUN_ID']]:
    if folder.is_dir():
        for file in folder.iterdir():
            if file.is_file() and file.suffix in ['.json','.mov','.png']:
                shutil.copy2(file,Path('output/poc')/file.name)
KEEP
    xcrun simctl io "$UDID" screenshot output/poc/final-screen.png >/dev/null 2>&1 || true
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" 'build-standalone/Build/Products/Release-iphonesimulator/Shiroi Video Forge.app'
APP_DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
export APP_DATA
# First launch uses no POC launch flag. This is the normal app entry screen.
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" > output/poc/normal-launch.log
sleep 5
xcrun simctl io "$UDID" screenshot output/poc/normal-launch.png
xcrun simctl terminate "$UDID" "$BUNDLE"
xcrun simctl launch --console --terminate-running-process "$UDID" "$BUNDLE" --poc-autostart --poc-profile preview --poc-run "$RUN_ID" > output/poc/render-console.log 2>&1 &
CONSOLE_PID=$!
python3 - <<'PY'
import os,time,json
from pathlib import Path
folder=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'/os.environ['RUN_ID']
for _ in range(180):
    report=folder/'poc-result.json'
    if report.exists():
        result=json.loads(report.read_text())
        assert result['status']=='passed' and result['decodedFrames']==144
        assert (result['width'],result['height'])==(960,540)
        assert result['aiInference'] is False and 'Simulator' in result['host']
        result.update(source_commit=os.environ['GITHUB_SHA'],standalone_app=True,
                      external_packages=0,signed_installation=False)
        Path('output/poc/standalone-evidence.json').write_text(json.dumps(result,indent=2))
        break
    time.sleep(1)
else: raise SystemExit('Standalone app did not produce a validated movie within 180s; see final screenshot and console.')
PY
sleep 3
xcrun simctl io "$UDID" screenshot output/poc/generated.png
xcrun simctl terminate "$UDID" "$BUNDLE"
wait "$CONSOLE_PID" || true
xcrun simctl launch "$UDID" "$BUNDLE" --poc-library-check > output/poc/reopen.log
python3 - <<'PY'
import os,time,json
from pathlib import Path
marker=Path(os.environ['APP_DATA'])/'Documents/VisiblePOC'/os.environ['RUN_ID']/'poc-reopened.json'
for _ in range(30):
    if marker.exists():
        result=json.loads(marker.read_text())
        assert result['selected_id']==os.environ['RUN_ID'] and result['history_count']==1
        assert result['render_started'] is False
        print('PASS real native app generated, saved and restored its own movie')
        break
    time.sleep(1)
else: raise SystemExit('Saved result was not restored after app relaunch')
PY
