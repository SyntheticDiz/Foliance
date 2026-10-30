"""Report remaining publisher prerequisites; never read or print private keys."""
import json,os,subprocess,sys,urllib.parse
from pathlib import Path
root=Path(__file__).resolve().parent.parent
config_path=root/'AppStore/Submission.local.json'
issues=[]
config={}
if not config_path.exists():
    issues.append('Create ignored AppStore/Submission.local.json with public supportURL and privacyURL (see example).')
else:
    config=json.loads(config_path.read_text())
    for key in ['supportURL','privacyURL']:
        u=urllib.parse.urlparse(config.get(key,''))
        if u.scheme!='https' or not u.netloc or u.netloc.endswith('.invalid') or u.netloc=='example.com': issues.append(f'Set a real public HTTPS {key}.')
for key in ['FOLIANCE_APP_SIGN_IDENTITY','FOLIANCE_INSTALLER_SIGN_IDENTITY','FOLIANCE_TEAM_ID','FOLIANCE_PROVISION_PROFILE']:
    value=os.environ.get(key) or (config.get('teamID') if key=='FOLIANCE_TEAM_ID' else None)
    if not value: issues.append(f'Set {key} in the local environment.')
profile=os.environ.get('FOLIANCE_PROVISION_PROFILE')
if profile and not Path(profile).is_file(): issues.append('Provisioning profile path does not exist.')
identities=subprocess.run(['security','find-identity','-v'],capture_output=True,text=True)
if '0 valid identities found' in identities.stdout: issues.append('No valid signing identities are installed.')
shots=list((root/'AppStore/Screenshots').glob('*.png')) if (root/'AppStore/Screenshots').exists() else []
if not shots: issues.append('Capture final native screenshots for App Store Connect.')
if issues:
    print('App Store publisher prerequisites still required:')
    for issue in issues: print('- '+issue)
    sys.exit(1)
print('Local publisher prerequisites present. Run ./build-app.sh store, then validate with Transporter. This check does not upload or promise review approval.')
