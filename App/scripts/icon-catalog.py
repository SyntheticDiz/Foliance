import json,sys
from pathlib import Path
p=Path(sys.argv[1])
images=[{'idiom':'mac','size':f'{s}x{s}','scale':f'{scale}x','filename':f'icon_{s}x{s}'+('@2x' if scale==2 else '')+'.png'} for s in [16,32,128,256,512] for scale in [1,2]]
(p/'Contents.json').write_text(json.dumps({'images':images,'info':{'version':1,'author':'Foliance'}},indent=2))
