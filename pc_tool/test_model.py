import copy,importlib.util,json,sys,tempfile,threading,time,unittest,urllib.parse,urllib.request
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent));import config_model as m
DEFAULT=json.loads((Path(__file__).resolve().parents[1]/'config/default.json').read_text('utf-8'))
def values():return {'event':'示例事件','target':'2030-01-01','provider':'amap','adcode':'110101','amap_key':'fake-key','city':'测试城市','latitude':'30','longitude':'110','weather_enabled':False,'dida_enabled':False,'project_ids':'a,b'}
class ConfigTests(unittest.TestCase):
 def test_solar_location_and_one_time_alignment_are_saved_without_losing_credentials(self):
  v={**values(),'latitude':'34.2','longitude':'118.8'}
  c=m.apply_config(DEFAULT,v)
  self.assertEqual(c['modules']['weather']['solar_location'],{'latitude':34.2,'longitude':118.8})
  self.assertEqual(c['ui']['refresh_alignment'],'first_10min')
 def test_solar_cross_midnight_and_polar_states(self):
  import solar_model as s
  a=s.calculate('2024-01-01',34.2,118.8)
  self.assertLess(a['sunrise_minute'],480)
  self.assertGreater(a['daylight_minutes'],500)
  self.assertEqual(s.calculate('2026-06-21',89,0)['state'],'polar_day')
  self.assertEqual(s.calculate('2026-12-21',89,0)['state'],'polar_night')
  with self.assertRaises(ValueError):s.calculate('2026-01-01',float('nan'),118)

 def test_refresh_lcm_and_roundtrip(self):
  v={**values(),'refresh_minutes':'5','dida_interval':'15','weather_interval':'30','full_refresh_every':'48'}
  self.assertEqual(m.refresh_plan(v),(5,15,30,30))
  c=m.apply_config(DEFAULT,v);self.assertEqual(c['ui']['refresh_minutes'],5);self.assertEqual(c['power']['full_refresh_every'],48)
  self.assertEqual(c['modules']['dida']['sync_interval_minutes'],15)
 def test_refresh_rejects_off_grid_and_invalid_values(self):
  for update in [{'refresh_minutes':'5','dida_interval':'7'},{'refresh_minutes':'0'},{'refresh_minutes':'1.5'},{'full_refresh_every':'-1'}]:
   with self.assertRaises(ValueError):m.apply_config(DEFAULT,{**values(),**update})
 def test_refresh_preserves_existing_settings(self):
  original=copy.deepcopy(DEFAULT);original['ui']['refresh_minutes']=5;original['power']['full_refresh_every']=48
  c=m.apply_config(original,values());self.assertEqual(c['ui']['refresh_minutes'],5);self.assertEqual(c['power']['full_refresh_every'],48)
 def test_token_only_configuration_needs_no_developer_fields(self):
  cfg=m.apply_config(DEFAULT,{**values(),'dida_enabled':True})
  private=m.apply_secrets({}, {'dida_access_token':'Bearer example-token'})
  self.assertTrue(cfg['modules']['dida']['enabled']);self.assertEqual(private['dida']['access_token'],'example-token')
  self.assertNotIn('client_id',private['dida']);self.assertEqual(private['dida']['expires_at'],0)
 def test_replacing_token_drops_stale_expiry_and_refresh_token(self):
  old={'dida':{'access_token':'old','refresh_token':'stale','expires_at':1,'client_id':'keep'}}
  new=m.apply_secrets(old,{'dida_access_token':'new','dida_refresh_token':'stale'})
  self.assertEqual(new['dida']['expires_at'],0);self.assertEqual(new['dida']['refresh_token'],'');self.assertEqual(new['dida']['client_id'],'keep')
  oauth=m.apply_secrets(old,{'dida_access_token':'new','dida_refresh_token':'fresh','expires_at':999})
  self.assertEqual(oauth['dida']['refresh_token'],'fresh');self.assertEqual(oauth['dida']['expires_at'],999)
 def test_token_rejects_multiple_header_lines(self):
  with self.assertRaises(ValueError):m.normalize_access_token('abc\nX-Header: test')
 def test_visibility_and_completion_are_explicit_boolean_settings(self):
  for shown in [True,False]:
   c=m.apply_config(DEFAULT,{**values(),'dida_enabled':shown,'weather_enabled':shown,'dida_allow_complete':False})
   self.assertIs(c['modules']['dida']['enabled'],shown);self.assertIs(c['modules']['weather']['enabled'],shown)
   self.assertIs(c['modules']['dida']['allow_complete'],False)
 def test_today_only_and_pause_choice_survive_configuration_save(self):
  original=copy.deepcopy(DEFAULT);original['ui']['auto_update']=False;original['modules']['dida']['date_filter']='all'
  c=m.apply_config(original,values());self.assertEqual(c['modules']['dida']['date_filter'],'today');self.assertIs(c['ui']['auto_update'],False)
 def test_date(self):
  with self.assertRaises(ValueError):m.apply_config(DEFAULT,{**values(),'target':'2026-02-30'})
 def test_preserves_unknown_and_other_events(self):
  c=copy.deepcopy(DEFAULT);c['custom']={'keep':123};c['modules']['countdown']['events'].append({'id':'other','date':'2027-01-01'})
  result=m.apply_config(c,values());self.assertEqual(result['custom'],c['custom']);self.assertEqual(len(result['modules']['countdown']['events']),2);self.assertEqual(c['modules']['countdown']['events'][0]['name'],'示例事件')
 def test_service_switches_keep_single_overview(self):
  c=m.apply_config(DEFAULT,{**values(),'dida_enabled':True,'weather_enabled':True});self.assertEqual([p['id'] for p in c['pages']],['home']);self.assertTrue(c['ui']['minimal']);self.assertTrue(c['pages'][0]['overview'])
 def test_amap_requires_adcode(self):
  with self.assertRaises(ValueError):m.apply_config(DEFAULT,{**values(),'adcode':'','weather_enabled':True})
 def test_save_backup_and_conflict(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';p.write_text(json.dumps(DEFAULT));s=p.with_name('secrets.json');s.write_text('{"keep":true}')
   backup,ch,sh=m.save_bundle(p,m.apply_config(DEFAULT,values()),{'amap':{'key':'fake'}},m.digest(p),m.digest(s),Path(tmp)/'backup')
   self.assertTrue((backup/'secrets.json').exists());self.assertEqual(s.read_text('utf-8'),'{\n  "amap": {\n    "key": "fake"\n  }\n}\n')
   p.write_text('{}')
   with self.assertRaises(ValueError):m.save_bundle(p,{}, {},ch,sh,Path(tmp)/'backup')
 def test_partial_save_rolls_back(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'config.json';p.write_bytes(b'{"old":1}');s=p.with_name('secrets.json');s.write_bytes(b'{"old":2}')
   real=m.os.replace;calls=[]
   def replace(a,b):
    calls.append(a)
    if len(calls)==2:raise OSError('simulated disconnected storage')
    return real(a,b)
   with patch.object(m.os,'replace',replace):
    with self.assertRaises(OSError):m.save_bundle(p,{}, {},m.digest(p),m.digest(s),Path(tmp)/'backups')
   self.assertEqual(p.read_bytes(),b'{"old":1}');self.assertEqual(s.read_bytes(),b'{"old":2}');self.assertFalse(list(Path(tmp).glob('*.tmp')))
 def test_secret_separation(self):
  c=m.apply_config(DEFAULT,values());s=m.apply_secrets({'other':{'keep':1}},{'amap_key':'fake','dida_access_token':'fake-token'})
  self.assertNotIn('fake-token',json.dumps(c));self.assertEqual(s['other']['keep'],1)
 def test_project_client_uses_bearer(self):
  with patch.object(m,'request_json',return_value=[{'id':'a','name':'Test'}]) as request:
   self.assertEqual([p['id'] for p in m.get_projects('fake')],['inbox','a']);self.assertEqual(request.call_args.kwargs['headers']['Authorization'],'Bearer fake')
 def test_project_client_does_not_duplicate_inbox(self):
  with patch.object(m,'request_json',return_value=[{'id':'inbox','name':'收集箱'}]):
   self.assertEqual(len(m.get_projects('fake')),1)
 def test_amap_http_error_code_no_key(self):
  with patch.object(m,'request_json',return_value={'status':'0','infocode':'10001'}):
   with self.assertRaisesRegex(ValueError,'10001'):m.test_weather(values())
 def test_oauth_loopback_and_state(self):
  with self.assertRaises(ValueError):m.oauth_authorize('id','secret','http://example.com/callback')
  import socket
  with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
  statuses=[]
  def open_browser(url):
   query=urllib.parse.parse_qs(urllib.parse.urlparse(url).query);self.assertEqual(query['scope'],['tasks:read'])
   def callback():
    for state in ['wrong',query['state'][0]]:
     target=query['redirect_uri'][0]+'?'+urllib.parse.urlencode({'state':state,'code':'fake-code'})
     try:
      with urllib.request.urlopen(target,timeout=3) as r:statuses.append(r.status)
     except urllib.error.HTTPError as e:statuses.append(e.code);e.close()
   threading.Thread(target=callback,daemon=True).start()
  with patch.object(m.webbrowser,'open',open_browser),patch.object(m,'request_json',return_value={'access_token':'fake','expires_in':3600}) as token_request:
   result=m.oauth_authorize('id','secret',f'http://127.0.0.1:{port}/callback')
   self.assertEqual(result['access_token'],'fake');self.assertEqual(statuses,[400,200]);self.assertEqual(token_request.call_args.kwargs['form']['code'],'fake-code')
 def test_oauth_completion_requests_write_scope(self):
  with self.assertRaises(ValueError):m.oauth_authorize('id','secret','http://example.com/callback')
  import socket
  with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
  statuses=[]
  def open_browser(url):
   query=urllib.parse.parse_qs(urllib.parse.urlparse(url).query);self.assertEqual(query['scope'],['tasks:read tasks:write'])
   def callback():
    for state in ['wrong',query['state'][0]]:
     target=query['redirect_uri'][0]+'?'+urllib.parse.urlencode({'state':state,'code':'fake-code'})
     try:
      with urllib.request.urlopen(target,timeout=3) as r:statuses.append(r.status)
     except urllib.error.HTTPError as e:statuses.append(e.code);e.close()
   threading.Thread(target=callback,daemon=True).start()
  with patch.object(m.webbrowser,'open',open_browser),patch.object(m,'request_json',return_value={'access_token':'fake','expires_in':3600}) as token_request:
   result=m.oauth_authorize('id','secret',f'http://127.0.0.1:{port}/callback',write_access=True)
   self.assertEqual(result['access_token'],'fake');self.assertEqual(statuses,[400,200]);self.assertEqual(token_request.call_args.kwargs['form']['code'],'fake-code')
if __name__=='__main__':unittest.main(verbosity=2)
