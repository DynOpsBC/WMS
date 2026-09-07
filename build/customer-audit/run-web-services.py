from pathlib import Path
import os,subprocess,json
root=Path(__file__).resolve().parents[2]
logs=root/'build/customer-audit'
pnpm=root/'build/customer-audit/tooling/node_modules/.bin/pnpm'
env=os.environ.copy();env['CI']='true';env['NODE_OPTIONS']='--max-old-space-size=1536';env['PATH']=str(pnpm.parent)+os.pathsep+env['PATH']
for k in list(env):
 if k.startswith(('LICENSE_', 'AZURE_', 'BC_API_TOKEN')): env.pop(k)
results=[]
def run(name,args,cwd):
 with (logs/(name+'.log')).open('w') as out:
  try: code=subprocess.run([str(pnpm),*args],cwd=root/cwd,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=480).returncode
  except subprocess.TimeoutExpired: code=124
 results.append(dict(check=name,exitCode=code));(logs/'web-services-results.json').write_text(json.dumps(results,indent=2));print(name,code,flush=True);return code==0
for component in ['web','push-relay','licensing-service','customer-portal','customer-portal/api']:
 name=component.replace('/','-')
 locked=(root/component/'pnpm-lock.yaml').exists()
 if not run(name+'-install',['install','--ignore-scripts','--frozen-lockfile' if locked else '--no-lockfile','--store-dir',str(logs/'pnpm-store')],component):continue
 if component=='web':
  run(name+'-typecheck',['typecheck'],component)
  run(name+'-build',['exec','vite','build','--outDir',str(logs/'web-controladdin')],component)
  run(name+'-unit',['exec','vitest','run','--maxWorkers=1','--minWorkers=1'],component)
 elif component=='customer-portal':
  run(name+'-typecheck',['typecheck'],component)
  run(name+'-build',['build'],component)
 else:
  run(name+'-build',['build'],component)
  run(name+'-unit',['test'],component)
