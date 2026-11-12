from pathlib import Path
import http.server,threading,tempfile,subprocess,json,shutil,time
ROOT=Path(__file__).resolve().parents[1]
SH=shutil.which('sh') or r'C:\Program Files\Git\usr\bin\sh.exe'
def posix(p):
 s=str(p.resolve()).replace('\\','/');return '/'+s[0].lower()+s[2:] if s[1]==':' else s
class Handler(http.server.BaseHTTPRequestHandler):
 count=0
 def do_GET(self):
  Handler.count+=1;body=b'x'*4096 if self.path=='/large' else b'{}';code=204 if self.path=='/empty' else 200
  if code==204:body=b''
  self.send_response(code);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
 def log_message(self,*a):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with tempfile.TemporaryDirectory(prefix='kdash-http-') as tmp:
  for case in ['success','empty','large','cancelled','wrapped','wrapped-cancelled']:
   folder=Path(tmp)/(case+" space's");folder.mkdir();paths={k:(folder/('request.'+ext)).resolve().as_posix() for k,ext in {'script':'sh','out':'out','err':'err','rc':'rc','status':'status','done':'done','pid':'pid','cancel':'cancel'}.items()}
   paths['worker']=(folder/'request.worker.pid').resolve().as_posix()
   descriptor=folder/'input.json';data={'opts':{'url':f'http://127.0.0.1:{server.server_port}/'+case,'max_bytes':512,'timeout':5},'paths':paths,'output':str(folder/'request.sh')}
   if case.startswith('wrapped'):data['spawn_output']=str(folder/'spawn.txt')
   descriptor.write_text(json.dumps(data),encoding='utf-8')
   subprocess.run(['luajit',str(ROOT/'tests/http_builder.lua'),str(descriptor),str(ROOT)],check=True,capture_output=True)
   subprocess.run([SH,'-n',posix(folder/'request.sh')],check=True,capture_output=True)
   before=Handler.count
   cancelled=case.endswith('cancelled')
   if cancelled:(folder/'request.cancel').write_text('cancel')
   command=(folder/'spawn.txt').read_text() if case.startswith('wrapped') else '/bin/sh "'+posix(folder/'request.sh')+'"'
   r=subprocess.run([SH,'-c',"export PATH=/usr/bin:/bin:$PATH; "+command],capture_output=True,text=True,timeout=10)
   if case.startswith('wrapped'):
    deadline=time.monotonic()+10
    # rm -f removes several files in sequence. Script disappearance alone is
    # not worker completion; wait for every artifact before checking cleanup.
    while time.monotonic()<deadline and not ((folder/'request.done').exists() or (cancelled and not any(Path(p).exists() for p in paths.values()))):time.sleep(.05)
   assert r.returncode==0,(case,r.stderr)
   if cancelled:assert Handler.count==before and not (folder/'request.sh').exists() and not (folder/'request.worker.pid').exists()
   else:
    assert (folder/'request.done').exists();rc=int((folder/'request.rc').read_text())
    if case=='large':assert rc!=0
    else:assert rc==0,(case,rc,r.stderr,(folder/'request.err').read_text())
   print('PASS generated HTTP script:',case)
finally:server.shutdown();server.server_close()
print('PASS 6 real shell/curl/owned-worker scenarios against a local fake HTTP server; no account access')
