"""Check the app bundle for identity, sandboxing, private paths and old branding."""
import plistlib,re,subprocess,sys
from pathlib import Path
app=Path(sys.argv[1]); failures=[]
with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
for key,value in {'CFBundleIdentifier':'app.foliance.mac','CFBundleExecutable':'Foliance','CFBundleShortVersionString':'1.0.0','CFBundleVersion':'2','LSMinimumSystemVersion':'26.0'}.items():
    if info.get(key)!=value: failures.append(f'Incorrect {key}')
with (app/'Contents/Resources/PrivacyInfo.xcprivacy').open('rb') as f: privacy=plistlib.load(f)
if privacy.get('NSPrivacyTracking'): failures.append('Unexpected tracking declaration')
content_types=privacy.get('NSPrivacyCollectedDataTypes',[])
if not any(x.get('NSPrivacyCollectedDataType')=='NSPrivacyCollectedDataTypeOtherUserContent' and x.get('NSPrivacyCollectedDataTypeTracking') is False for x in content_types): failures.append('Optional OpenAI user-content disclosure missing')
raw=subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL)
ent=plistlib.loads(raw)
if ent.get('com.apple.security.app-sandbox') is not True: failures.append('Sandbox missing')
if ent.get('com.apple.security.network.client') is not True: failures.append('OpenAI client-network entitlement missing')
if ent.get('com.apple.security.network.server') is not True: failures.append('Loopback OAuth callback entitlement missing')
for key in ['com.apple.security.get-task-allow']:
    if ent.get(key): failures.append(f'Unexpected entitlement: {key}')
forbidden=[bytes.fromhex('53504446').lower(),bytes.fromhex('6e697373657761617264'),b'/Users/',b'/Volumes/External']
for p in app.rglob('*'):
    if not p.is_file() or p.name in ['embedded.provisionprofile','CodeResources']: continue
    data=p.read_bytes()
    if any(token.lower() in data.lower() for token in forbidden): failures.append('Old branding or private path in '+str(p.relative_to(app)))
    if re.search(rb'sk-[A-Za-z0-9_-]{24,}',data): failures.append('Possible API credential in '+str(p.relative_to(app)))
if failures:
    print('\n'.join(failures),file=sys.stderr);sys.exit(1)
print('Release audit passed: identity, sandbox, outbound networking and loopback OAuth callback, privacy manifest, no old branding/private paths/API keys.')
