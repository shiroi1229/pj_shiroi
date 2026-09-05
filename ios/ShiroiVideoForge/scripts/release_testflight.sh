#!/bin/bash
# Run only in the manually authorized main-branch workflow. Never print secrets or use set -x.
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?Use the dedicated macOS CI workflow}"
: "${APPLE_TEAM_ID:?Missing Apple team}"
: "${APP_STORE_CONNECT_KEY_ID:?Missing App Store Connect key ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Missing App Store Connect issuer}"
WORK=$(mktemp -d "$RUNNER_TEMP/forge-signing.XXXXXX")
export WORK
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
PROFILE_PATH=""
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  if [ -n "$PROFILE_PATH" ]; then rm -f "$PROFILE_PATH"; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

python3 - <<'PY'
import os, base64
from pathlib import Path
p=Path(os.environ['WORK'])
for key, name in [('BUILD_CERTIFICATE_BASE64','certificate.p12'),('BUILD_PROVISION_PROFILE_BASE64','profile.mobileprovision')]:
    (p/name).write_bytes(base64.b64decode(''.join(os.environ[key].split()), validate=True))
key_id=os.environ['APP_STORE_CONNECT_KEY_ID']
if not key_id.isalnum(): raise SystemExit('Invalid App Store Connect key ID format')
(p/f'AuthKey_{key_id}.p8').write_text(os.environ['APP_STORE_CONNECT_PRIVATE_KEY'])
PY
security cms -D -i "$WORK/profile.mobileprovision" > "$WORK/profile.plist"
python3 - <<'PY'
import os, plistlib, datetime
from pathlib import Path
p=Path(os.environ['WORK']); profile=plistlib.loads((p/'profile.plist').read_bytes())
team=os.environ['APPLE_TEAM_ID']; bundle='com.shiroi1229.ShiroiVideoForge'
if team not in profile.get('TeamIdentifier',[]): raise SystemExit('Provisioning profile team mismatch')
ent=profile.get('Entitlements',{})
if ent.get('application-identifier','').split('.',1)[-1] != bundle: raise SystemExit('Provisioning profile bundle ID mismatch')
if profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices') or ent.get('get-task-allow'):
    raise SystemExit('An App Store distribution profile, not development/ad-hoc/enterprise, is required')
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile expired')
(p/'uuid.txt').write_text(profile['UUID'])
options={'method':'app-store-connect','destination':'export','signingStyle':'manual',
         'teamID':team,'signingCertificate':'Apple Distribution','provisioningProfiles':{bundle:profile['UUID']},
         'manageAppVersionAndBuildNumber':False,'uploadSymbols':True}
(p/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
UUID=$(cat "$WORK/uuid.txt")
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/certificate.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
mkdir -p "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROFILE_PATH="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$UUID.mobileprovision"
cp "$WORK/profile.mobileprovision" "$PROFILE_PATH"
# Unique dotted build version also distinguishes repeated workflow attempts.
BUILD_NUMBER="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
xcodebuild -project ShiroiVideoForge.xcodeproj -scheme ShiroiVideoForge \
  -configuration Release -destination 'generic/platform=iOS' -archivePath "$WORK/app.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution' \
  PROVISIONING_PROFILE_SPECIFIER="$UUID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
xcodebuild -exportArchive -archivePath "$WORK/app.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export"
IPA=$(find "$WORK/export" -maxdepth 1 -name '*.ipa' -print -quit)
[ -n "$IPA" ] || { echo '::error::No signed IPA was exported'; exit 1; }
export API_PRIVATE_KEYS_DIR="$WORK"
xcrun altool --upload-app --type ios -f "$IPA" \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
echo 'Beta uploaded to Apple. Processing, tester assignment, compliance and any beta review are still separate gates.' >> "$GITHUB_STEP_SUMMARY"
