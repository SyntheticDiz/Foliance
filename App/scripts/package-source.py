"""Make a reviewable source archive from an explicit credential-free allowlist."""
from pathlib import Path
import zipfile
root=Path(__file__).resolve().parent.parent
output=root/'dist/Foliance-1.0.0-source.zip'
roots=['Sources','Tests','Config','Assets','ThirdPartyLicenses','AppStore','SupportSite','scripts']
files=[root/name for name in ['LICENSE','Package.swift','build-app.sh','README.md','HANDOFF.md','AGENTS.md','.gitignore']]
for name in roots: files.extend(p for p in (root/name).rglob('*') if p.is_file())
blocked_suffixes={'.p12','.p8','.provisionprofile','.mobileprovision','.pyc','.key','.pem','.cer','.der'}
files=[p for p in files if p.suffix not in blocked_suffixes and '.local.' not in p.name and p.name!='.DS_Store' and not p.name.startswith('.env') and '__pycache__' not in p.parts and '.git' not in p.parts]
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
    for p in sorted(set(files)):
        archive.write(p,'Foliance/'+str(p.relative_to(root)))
print(f'Packaged {len(set(files))} source/metadata files: {output}')
