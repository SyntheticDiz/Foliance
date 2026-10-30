"""Validate an externally supplied profile without saving credentials in source."""
import datetime,plistlib,subprocess,sys
from pathlib import Path
profile,team,destination=sys.argv[1:]
p=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',profile]))
e=p.get('Entitlements',{})
assert team in p.get('TeamIdentifier',[]),'Profile team does not match FOLIANCE_TEAM_ID'
assert p.get('ExpirationDate',datetime.datetime.min)>datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),'Provisioning profile has expired'
assert not p.get('ProvisionedDevices') and not p.get('ProvisionsAllDevices'),'Use an App Store distribution profile'
app_id=e.get('com.apple.application-identifier','')
assert app_id.endswith('.app.foliance.mac'),'Profile must target app.foliance.mac'
assert not e.get('get-task-allow',False) and not e.get('com.apple.security.get-task-allow',False),'Distribution profile must not enable debugging'
with open('Config/Foliance.entitlements','rb') as f: result=plistlib.load(f)
result.update({'com.apple.application-identifier':app_id,'com.apple.developer.team-identifier':team})
Path(destination).write_bytes(plistlib.dumps(result))
print('Distribution profile matches the Foliance app and team.')
