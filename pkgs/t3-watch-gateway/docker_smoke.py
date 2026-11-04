import subprocess,json,time,secrets,urllib.request,urllib.error
import argparse
from pathlib import Path
parser = argparse.ArgumentParser(description="Exercise disposable gateway images. Does not publish or deploy.")
parser.add_argument("image_lock", type=Path)
args = parser.parse_args()
lock = json.loads(args.image_lock.read_text())
bridge = lock['images']['bridge']['ref']
gateway = lock['images']['gateway']['ref']
archives = [lock['images'][kind]['archive'] for kind in ('bridge', 'gateway')]
def run(args,**kwargs):return subprocess.run(args,capture_output=True,text=True,check=True,**kwargs)
for archive in archives:run(['docker','load','-i',archive])
suffix=secrets.token_hex(4);gn='t3-gateway-smoke-'+suffix;bn='t3-bridge-smoke-'+suffix;volume='t3-gateway-smoke-'+suffix;pn='t3-pod-smoke-'+suffix
run(['docker','volume','create',volume]);created=[]
try:
 run(['docker','run','-d','--name',pn,'--read-only','--entrypoint','/bin/sleep','-p','127.0.0.1::8789',bridge,'infinity']);created.append(pn)
 run(['docker','run','-d','--name',gn,'--network','container:'+pn,'--read-only','--tmpfs','/tmp:rw,noexec,nosuid,size=128m','--mount',f'type=volume,src={volume},dst=/data',gateway]);created.append(gn)
 for _ in range(160):
  r=subprocess.run(['docker','exec',gn,'/bin/t3-watch-gateway','--healthcheck'],capture_output=True)
  if r.returncode==0:break
  time.sleep(.25)
 else:raise RuntimeError('Real OCI gateway readiness deadline')
 token=secrets.token_hex(32)
 run(['docker','exec','-i',gn,'/bin/sh','-c','umask 077; cat > /data/bridge-secrets/watch-token'],input=token+'\n')
 before=run(['docker','exec',gn,'/bin/sh','-c','sha256sum /data/bridge-secrets/t3-token /data/bridge-secrets/t3-mcp-token']).stdout
 run(['docker','run','-d','--name',bn,'--read-only','--tmpfs','/tmp:rw,noexec,nosuid,size=32m','--network','container:'+pn,'--mount',f'type=volume,src={volume},dst=/run/t3-bridge,volume-subpath=bridge-secrets,readonly',bridge]);created.append(bn)
 addr=run(['docker','port',pn,'8789/tcp']).stdout.strip();url='http://'+addr+'/v1/pending?brief=1'
 for _ in range(100):
  try:
   with urllib.request.urlopen(urllib.request.Request(url,headers={'Authorization':'Bearer '+token}),timeout=5) as r:
    assert r.status==200 and json.load(r)=={'items':[]};break
  except (urllib.error.URLError, ConnectionError):time.sleep(.1)
 else:raise RuntimeError('Real OCI bridge API deadline')
 try:urllib.request.urlopen(url,timeout=5);raise RuntimeError('Unauthenticated request was allowed')
 except urllib.error.HTTPError as e:assert e.code==401
 print('PASS two real rootless OCI containers: private T3 + shared secret subdir + public bridge auth/list200',flush=True)
 for n in created:
  info=json.loads(run(['docker','inspect',n]).stdout)[0]
  assert info['Config']['User']=='65532:65532' and info['HostConfig']['ReadonlyRootfs']
  logs=run(['docker','logs',n]).stdout
  assert token not in logs
 run(['docker','restart',gn])
 for _ in range(160):
  if subprocess.run(['docker','exec',gn,'/bin/t3-watch-gateway','--healthcheck'],capture_output=True).returncode==0:break
  time.sleep(.25)
 else:raise RuntimeError('Real OCI restart readiness deadline')
 after=run(['docker','exec',gn,'/bin/sh','-c','sha256sum /data/bridge-secrets/t3-token /data/bridge-secrets/t3-mcp-token']).stdout
 assert before==after
 with urllib.request.urlopen(urllib.request.Request(url,headers={'Authorization':'Bearer '+token}),timeout=10) as response:
  assert response.status==200 and json.load(response)=={'items':[]}
 print('PASS OCI gateway restart preserves credentials and restores watch API in the shared pod network',flush=True)
 run(['docker','stop','-t','30',gn])
 inspect=json.loads(run(['docker','inspect',gn]).stdout)[0]
 assert inspect['State']['ExitCode']==0
 # Readonly verification helper uses the same disposable volume after gateway exit.
 r=run(['docker','run','--rm','--entrypoint','/bin/sh','--mount',f'type=volume,src={volume},dst=/data',gateway,'-ec','test ! -e /data/bridge-secrets/ready'])
 print('PASS OCI SIGTERM exits0 and removes readiness; no credential values enter logs',flush=True)
finally:
 for n in reversed(created):subprocess.run(['docker','rm','-f',n],capture_output=True)
 subprocess.run(['docker','volume','rm',volume],capture_output=True)
