"""KDash configuration model and read-only service clients; no automatic USB writes."""
from pathlib import Path
import math
import copy,datetime as dt,hashlib,json,os,re,secrets,shutil,time,urllib.request,urllib.parse,urllib.error
import http.server,threading,webbrowser
VERSION='0.1.1-candidate1'
DIDA_AUTH='https://dida365.com/oauth/authorize'
DIDA_TOKEN='https://dida365.com/oauth/token'
DIDA_API='https://api.dida365.com/open/v1'
def digest(path):
 p=Path(path);return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None
def load(path):
 p=Path(path)
 if not p.exists():return {},None
 value=json.loads(p.read_text('utf-8-sig'))
 if not isinstance(value,dict):raise ValueError('配置根节点必须是 JSON 对象')
 return value,digest(p)
def validate_date(value):
 if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',value):raise ValueError('目标日期格式应为 YYYY-MM-DD')
 return dt.date.fromisoformat(value)
def refresh_plan(values,original=None):
 c=original or {};modules=c.get('modules',{})
 try:
  base=int(values.get('refresh_minutes',c.get('ui',{}).get('refresh_minutes',1)))
  dida=int(values.get('dida_interval',modules.get('dida',{}).get('sync_interval_minutes',15)))
  weather=int(values.get('weather_interval',modules.get('weather',{}).get('sync_interval_minutes',45)))
 except (ValueError,TypeError):raise ValueError('刷新间隔请填写整数分钟')
 if not 1<=base<=60:raise ValueError('刷新基准间隔应为 1～60 分钟')
 for name,interval in [('滴答',dida),('天气',weather)]:
  if not 5<=interval<=1440:raise ValueError(name+'同步间隔应为 5～1440 分钟')
  if interval%base:raise ValueError(name+'同步间隔必须是基准间隔的整数倍（当前基准 '+str(base)+' 分钟）')
 return base,dida,weather,math.lcm(base,dida,weather)

def apply_config(original,values):
 c=copy.deepcopy(original)
 name=values['event'].strip()
 if not name or len(name)>24:raise ValueError('事件名请填写 1～24 个字')
 validate_date(values['target'])
 modules=c.setdefault('modules',{});countdown=modules.setdefault('countdown',{})
 events=countdown.setdefault('events',[])
 event=events[0] if events else {'id':'exam','pinned':True}
 event.update(name=name,name_en=name,date=values['target'],time='');countdown['events']=[event]+events[1:];countdown['enabled']=True
 c.setdefault('ui',{}).update(direct_exit=True,hide_settings=True)
 try:
  refresh=int(values.get('refresh_minutes',c['ui'].get('refresh_minutes',1)))
  full=int(values.get('full_refresh_every',c.get('power',{}).get('full_refresh_every',24)))
 except (ValueError,TypeError):raise ValueError('刷新设置请填写整数')
 if not 1<=refresh<=60:raise ValueError('屏幕自动刷新间隔应为 1～60 分钟')
 if not 0<=full<=1000:raise ValueError('全屏清理间隔应为 0～1000 次；0 表示关闭周期清理')
 refresh_plan(values,c)
 c['ui']['refresh_minutes']=refresh
 c['ui']['refresh_alignment']='first_10min'
 c.setdefault('power',{})['full_refresh_every']=full
 c.setdefault('input',{}).update(swap_xy=bool(values.get('swap_xy')),invert_x=bool(values.get('invert_x')),invert_y=bool(values.get('invert_y')))
 device=values.get('touch_device','').strip()
 if device:c['input']['device']=device
 else:c['input'].pop('device',None)
 if device and not re.fullmatch(r'/dev/input/event\d+',device):raise ValueError('触控设备应为 /dev/input/event数字，或留空自动识别')
 c['utc_offset_minutes']=int(values.get('utc_offset',480))
 if not -720<=c['utc_offset_minutes']<=840:raise ValueError('时区偏移应为 -720～840 分钟')
 c.setdefault('modules',{}).setdefault('clock',{})['format']=values.get('clock_format','24h')
 for service in ['dida','weather']:
  cfg=modules.setdefault(service,{});cfg['enabled']=bool(values.get(service+'_enabled'))
  interval=int(values.get(service+'_interval',15 if service=='dida' else 45))
  if not 5<=interval<=1440:raise ValueError('同步间隔应为 5～1440 分钟')
  cfg['sync_interval_minutes']=interval
 modules['dida']['date_filter']='today'
 modules['dida']['allow_complete']=bool(values.get('dida_allow_complete',modules['dida'].get('allow_complete',True)))
 w=modules['weather'];w.update(provider=values.get('provider','amap'),city=values.get('city','').strip(),city_en=values.get('city','').strip(),adcode=values.get('adcode','').strip())
 if w['provider'] not in ['amap','open-meteo']:raise ValueError('未知天气来源')
 if w['enabled'] and w['provider']=='amap' and not re.fullmatch(r'\d{6}',w['adcode']):raise ValueError('高德天气需要六位城市 adcode')
 for field,limit in [('latitude',90),('longitude',180)]:
  value=float(values.get(field,w.get(field,0)))
  if not -limit<=value<=limit:raise ValueError('经纬度超出范围')
  w[field]=value
 w['timezone']=values.get('timezone','Asia/Shanghai').strip() or 'Asia/Shanghai'
 w['solar_location']={'latitude':w['latitude'],'longitude':w['longitude']}
 ids=[s.strip() for s in values.get('project_ids','').replace('，',',').split(',') if s.strip()]
 modules['dida']['project_ids']=ids
 c['pages']=[{'id': 'home', 'title': 'KDASH', 'kind': 'dashboard', 'overview': True, 'layout': [{'modules': ['clock', 'countdown'], 'weight': 24}, {'modules': ['dida'], 'weight': 39}, {'modules': ['weather'], 'weight': 37}]}]
 c['pages'] += [copy.deepcopy(p) for p in original.get('pages',[]) if p.get('id') not in ['home','tasks','weather','settings']]
 c['ui']['minimal']=True
 c['last_page']='home'
 return c
def normalize_access_token(token):
 token=str(token or '').strip()
 if token.lower().startswith('bearer '):token=token[7:].strip()
 if any(c.isspace() for c in token):raise ValueError('API 口令内含空白，请复制完整令牌，不要复制整段请求头或 Cookie')
 return token

def apply_secrets(original,values):
 s=copy.deepcopy(original)
 for group,fields in [('dida',['client_id','client_secret','access_token','refresh_token']),('amap',['key'])]:
  dest=s.setdefault(group,{})
  for field in fields:
   key=group+'_'+field
   if key in values:dest[field]=normalize_access_token(values[key]) if key=='dida_access_token' else values[key].strip()
 changed=s.get('dida',{}).get('access_token')!=original.get('dida',{}).get('access_token')
 if changed:
  s['dida']['expires_at']=values.get('expires_at') or 0
  if s['dida'].get('refresh_token')==original.get('dida',{}).get('refresh_token'):s['dida']['refresh_token']=''
 elif values.get('expires_at') is not None:s['dida']['expires_at']=values['expires_at']
 return s
def save_bundle(config_path,config,private,expected_config,expected_secrets,backup_root):
 """Validate both snapshots, back up first, then replace; restore originals on partial failure."""
 path=Path(config_path); secret_path=path.with_name('secrets.json')
 if path.is_symlink() or secret_path.is_symlink():raise ValueError('不覆盖符号链接配置')
 if digest(path)!=expected_config or digest(secret_path)!=expected_secrets:raise ValueError('配置已被其他程序修改，请重新读取后再保存')
 if not path.parent.is_dir():raise ValueError('目标目录不存在；请先部署候选版')
 backup=Path(backup_root)/(dt.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+secrets.token_hex(3));backup.mkdir(parents=True)
 originals={p:p.read_bytes() if p.exists() else None for p in [path,secret_path]}
 for p,b in originals.items():
  if b is not None:(backup/p.name).write_bytes(b)
 payloads={path:json.dumps(config,ensure_ascii=False,indent=2)+'\n',secret_path:json.dumps(private,ensure_ascii=False,indent=2)+'\n'}
 temps=[]
 try:
  for p,text in payloads.items():
   tmp=p.with_name(p.name+'.kdash-'+secrets.token_hex(4)+'.tmp');tmp.write_bytes(text.encode('utf-8'));temps.append((p,tmp))
  for p,tmp in temps:os.replace(tmp,p)
  for p in payloads:json.loads(p.read_text('utf-8'))
 except Exception:
  for p,b in originals.items():
   if b is None:p.unlink(missing_ok=True)
   else:p.write_bytes(b)
  raise
 finally:
  for _,tmp in temps:tmp.unlink(missing_ok=True)
 return backup,digest(path),digest(secret_path)
def detect_kindles():
 found=[]
 for letter in 'DEFGHIJKLMNOPQRSTUVWXYZ':
  root=Path(letter+':/')
  try:
   if (root/'system/version.txt').is_file() and (root/'documents').is_dir():found.append(root)
  except OSError:pass
 return found
def request_json(url,form=None,headers=None):
 data=urllib.parse.urlencode(form).encode() if form is not None else None
 hs={'Accept':'application/json','User-Agent':'KDash-Config/0.1.1'};hs.update(headers or {})
 if data is not None:hs['Content-Type']='application/x-www-form-urlencoded'
 req=urllib.request.Request(url,data=data,headers=hs)
 try:
  with urllib.request.urlopen(req,timeout=25) as response:raw=response.read(5*1024*1024+1)
  if len(raw)>5*1024*1024:raise ValueError('服务返回内容过大')
  return json.loads(raw)
 except urllib.error.HTTPError as err:raise ValueError('服务返回 HTTP '+str(err.code)) from None
 except (urllib.error.URLError,TimeoutError,OSError):raise ValueError('连接失败，请检查网络与服务地址') from None
 except json.JSONDecodeError:raise ValueError('服务未返回有效 JSON') from None
def get_projects(token):
 token=normalize_access_token(token)
 if not token:raise ValueError('请先授权或填写 Access Token')
 data=request_json(DIDA_API+'/project',headers={'Authorization':'Bearer '+token})
 if not isinstance(data,list):raise ValueError('清单接口返回格式不符')
 projects=[{'id':str(p['id']),'name':str(p.get('name',''))} for p in data if isinstance(p,dict) and 'id' in p]
 if not any(p['id'].startswith('inbox') for p in projects):projects.insert(0,{'id':'inbox','name':'收集箱'})
 return projects
def test_weather(values):
 if values['provider']=='amap':
  if not re.fullmatch(r'\d{6}',values['adcode']):raise ValueError('请填写六位城市 adcode')
  if not values['amap_key']:raise ValueError('请填写高德 Web 服务 Key')
  url='https://restapi.amap.com/v3/weather/weatherInfo?'+urllib.parse.urlencode({'city':values['adcode'],'key':values['amap_key'],'extensions':'base','output':'JSON'})
  d=request_json(url)
  if str(d.get('status'))!='1':raise ValueError('高德返回错误码 '+str(d.get('infocode','未知')))
  lives=d.get('lives',[])
  if not lives:raise ValueError('高德未返回该城市的实况天气')
  return str(lives[0].get('city',''))+'：'+str(lives[0].get('weather',''))+' '+str(lives[0].get('temperature',''))+'℃'
 url='https://api.open-meteo.com/v1/forecast?'+urllib.parse.urlencode({'latitude':float(values['latitude']),'longitude':float(values['longitude']),'current':'temperature_2m','timezone':values['timezone']})
 d=request_json(url)
 if 'current' not in d:raise ValueError('天气接口返回格式不符')
 return 'Open-Meteo：'+str(d['current']['temperature_2m'])+'℃'
def oauth_authorize(client_id,client_secret,redirect,write_access=False):
 scope="tasks:read tasks:write" if write_access else "tasks:read"
 if not client_id or not client_secret:raise ValueError('请填写 Client ID 和 Client Secret')
 uri=urllib.parse.urlparse(redirect)
 if uri.scheme!='http' or uri.hostname!='127.0.0.1' or not uri.port or uri.query or uri.fragment:raise ValueError('回调地址应为 http://127.0.0.1:端口/callback，并在开发者后台注册')
 state=secrets.token_urlsafe(32);result={};done=threading.Event()
 class Handler(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
   parsed=urllib.parse.urlparse(self.path);qs=urllib.parse.parse_qs(parsed.query)
   valid=parsed.path==(uri.path or '/') and secrets.compare_digest((qs.get('state') or [''])[0],state)
   self.send_response(200 if valid else 400);self.send_header('Content-Type','text/plain; charset=utf-8');self.end_headers()
   self.wfile.write(('已收到授权回调，请返回 KDash 配置工具。' if valid else '无效回调。').encode())
   if valid:
    result['code']=(qs.get('code') or [''])[0];result['error']=bool(qs.get('error'));done.set()
  def log_message(self,*args):pass
 with http.server.HTTPServer(('127.0.0.1',uri.port),Handler) as server:
  server.timeout=.5
  url=DIDA_AUTH+'?'+urllib.parse.urlencode({'client_id':client_id,'redirect_uri':redirect,'response_type':'code','scope':scope,'state':state})
  webbrowser.open(url);deadline=time.monotonic()+300
  while not done.is_set() and time.monotonic()<deadline:server.handle_request()
 if not done.is_set():raise ValueError('授权等待超时，请重试')
 if result.get('error') or not result.get('code'):raise ValueError('授权被取消或没有授权码')
 token=request_json(DIDA_TOKEN,form={'client_id':client_id,'client_secret':client_secret,'code':result['code'],'grant_type':'authorization_code','redirect_uri':redirect,'scope':scope})
 if not token.get('access_token'):raise ValueError('未获得 Access Token；请核对应用凭据与回调地址')
 token['expires_at']=int(time.time())+int(token['expires_in'])-60 if token.get('expires_in') else 0
 return token
