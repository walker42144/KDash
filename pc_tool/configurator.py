"""Windows USB configuration app. Opens read-only; explicit Save is the only USB write."""
from pathlib import Path
import argparse,datetime as dt,json,queue,sys,threading,tkinter as tk
from tkinter import ttk,filedialog,messagebox
import config_model as model
import solar_model
RESOURCE=Path(getattr(sys,'_MEIPASS',Path(__file__).resolve().parents[1]))
HOME=Path(sys.executable).parent if getattr(sys,'frozen',False) else Path(__file__).resolve().parents[2]
def default_config():
 f=RESOURCE/'default-config.json'
 if not f.exists():f=RESOURCE/'config/default.json'
 return json.loads(f.read_text('utf-8'))
class ConfigApp:
 def __init__(self,root,config_path=None):
  self.root=root;root.title('KDash 配置工具');root.geometry('820x800');root.minsize(760,780)
  root.configure(bg='#f5f5f2');self.path=None;self.config=default_config();self.private={};self.config_hash=None;self.secret_hash=None;self.expires_at=None;self.queue=queue.Queue();self.fields={};self.busy=False;self.projects=[]
  style=ttk.Style();style.theme_use('clam');style.configure('.',font=('Microsoft YaHei UI',10));style.configure('TFrame',background='#f5f5f2');style.configure('TLabel',background='#f5f5f2');style.configure('TNotebook',background='#f5f5f2');style.configure('TNotebook.Tab',padding=(22,10));style.configure('TButton',padding=(14,7));style.configure('Title.TLabel',font=('Microsoft YaHei UI',20,'bold'));style.configure('Muted.TLabel',foreground='#666660');style.configure('Hero.TLabel',font=('Microsoft YaHei UI',26));style.configure('Primary.TButton',foreground='white',background='#242823');style.map('Primary.TButton',background=[('active','#424a40')]);
  head=ttk.Frame(root,padding=(28,22,28,12));head.pack(fill='x')
  try:
   logo=RESOURCE/'logo.png'
   if not logo.exists():logo=RESOURCE/'assets/logo.png'
   self.icon=tk.PhotoImage(file=str(logo)).subsample(8);ttk.Label(head,image=self.icon).pack(side='left',padx=(0,16));root.iconphoto(True,self.icon)
  except tk.TclError:pass
  title=ttk.Frame(head);title.pack(side='left');ttk.Label(title,text='KDash 配置工具',style='Title.TLabel').pack(anchor='w');ttk.Label(title,text='连接 Kindle，设置桌面上的信息。',style='Muted.TLabel').pack(anchor='w')
  box=ttk.Frame(root,padding=(28,4,28,12));box.pack(fill='x');ttk.Button(box,text='识别 Kindle',command=self.detect).pack(side='left');ttk.Button(box,text='打开配置文件…',command=self.open_file).pack(side='left',padx=8)
  self.location=tk.StringVar(value='未选择配置文件');ttk.Label(root,textvariable=self.location,style='Muted.TLabel',wraplength=750).pack(anchor='w',padx=30,pady=(0,12))
  tabs=ttk.Notebook(root);tabs.pack(fill='both',expand=True,padx=28)
  frames={}
  for key,title in [('event','事件倒计时'),('dida','滴答清单'),('weather','天气'),('refresh','刷新与省电'),('display','显示与触控')]:
   shell=ttk.Frame(tabs);tabs.add(shell,text=title)
   canvas=tk.Canvas(shell,bg='#f5f5f2',highlightthickness=0);scroll=ttk.Scrollbar(shell,orient='vertical',command=canvas.yview)
   canvas.configure(yscrollcommand=scroll.set);scroll.pack(side='right',fill='y');canvas.pack(side='left',fill='both',expand=True)
   f=ttk.Frame(canvas,padding=20);item=canvas.create_window((0,0),window=f,anchor='nw')
   f.bind('<Configure>',lambda e,c=canvas:c.configure(scrollregion=c.bbox('all')))
   canvas.bind('<Configure>',lambda e,c=canvas,i=item:c.itemconfigure(i,width=e.width))
   frames[key]=f;f.columnconfigure(1,weight=1)
  self.entry(frames['event'],0,'event','事件名称');self.entry(frames['event'],1,'target','目标日期','YYYY-MM-DD')
  self.preview=tk.StringVar();ttk.Label(frames['event'],textvariable=self.preview,style='Hero.TLabel',wraplength=650).grid(row=3,column=0,columnspan=3,sticky='w',pady=(35,14))
  ttk.Label(frames['event'],text='按目标日期计算剩余天数。当天显示“今天”。',style='Muted.TLabel').grid(row=4,column=0,columnspan=3,sticky='w')
  d=frames['dida'];self.visibility(d,0,'dida_enabled','Kindle 上的滴答清单')
  self.entry(d,1,'dida_access_token','API 口令 / Access Token',secret=True)
  ttk.Label(d,text='展示范围：仅今天，不含逾期、未来和无日期任务。保留今日任务的清单子项，独立子任务按日期筛选。\n显示顺序：任务 → 时间圆角框 → 标签胶囊；右侧保留重要程度。底部“上/下”本地翻页。\n已有可用令牌时，只需填写这一项。点击下方按钮验证连接并选择清单。\n“显示”启用同步并显示数据；“隐藏”停止同步，首页保留该分区的配置提示。',style='Muted.TLabel',wraplength=650).grid(row=2,column=0,columnspan=3,sticky='w',pady=12)
  ttk.Button(d,text='测试连接并选择清单',command=self.fetch_projects).grid(row=3,column=1,sticky='w',pady=10)
  self.project_summary=tk.StringVar()
  ttk.Label(d,textvariable=self.project_summary,style='Muted.TLabel',wraplength=650).grid(row=4,column=0,columnspan=3,sticky='w',pady=8)
  self.visibility(d,5,'dida_allow_complete','任务操作','允许勾选完成','仅查看')
  ttk.Label(d,text='勾选完成需要写入权限；只读令牌仍可显示任务。连接测试只验证读取。',style='Muted.TLabel',wraplength=650).grid(row=6,column=0,columnspan=3,sticky='w',pady=8)
  ttk.Button(d,text='高级授权设置（没有可用口令时）',command=self.toggle_dida_advanced).grid(row=7,column=0,columnspan=3,sticky='w',pady=18)
  advanced=ttk.Frame(d);advanced.grid(row=8,column=0,columnspan=3,sticky='ew');advanced.columnconfigure(1,weight=1)
  self.dida_advanced=advanced
  self.entry(advanced,0,'dida_client_id','Client ID');self.entry(advanced,1,'dida_client_secret','Client Secret',secret=True)
  self.entry(advanced,2,'redirect','回调地址');self.entry(advanced,3,'dida_refresh_token','Refresh Token',secret=True)
  self.entry(advanced,4,'project_ids','清单 ID（可选）','留空为所有可访问清单，通常用上方按钮选择')
  ttk.Button(advanced,text='浏览器授权获取令牌',command=self.authorize).grid(row=5,column=1,sticky='w',pady=12)
  ttk.Label(advanced,text='这些字段用于 OAuth 授权获取令牌；已有令牌时不需要填写。',style='Muted.TLabel',wraplength=650).grid(row=6,column=0,columnspan=3,sticky='w')
  advanced.grid_remove()
  self.fields['dida_access_token'].trace_add('write',lambda *_:self.on_dida_token_edit())
  self.fields['project_ids'].trace_add('write',lambda *_:self.update_project_summary())
  self.entry(frames['refresh'],3,'dida_interval','滴答同步（分钟）','5～1440 分钟')
  w=frames['weather'];self.visibility(w,0,'weather_enabled','Kindle 上的天气')
  self.combo(w,1,'provider','天气来源',['amap','open-meteo']);self.entry(w,2,'city','显示城市名');self.entry(w,3,'adcode','高德城市 adcode','六位行政区划代码');self.entry(w,4,'amap_key','高德 Web 服务 Key',secret=True)
  self.entry(w,5,'latitude','位置：纬度','北纬为正，用于日出日落');self.entry(w,6,'longitude','位置：经度','东经为正，用于日出日落');self.entry(w,7,'timezone','天气时区');self.entry(frames['refresh'],4,'weather_interval','天气同步（分钟）','5～1440 分钟')
  self.solar_preview=tk.StringVar()
  ttk.Label(w,textvariable=self.solar_preview,style='Muted.TLabel',wraplength=650).grid(row=8,column=0,columnspan=3,sticky='w',pady=10)
  for key in ['latitude','longitude','utc_offset']:
   if key in self.fields:self.fields[key].trace_add('write',lambda *_:self.update_solar_preview())
  ttk.Button(w,text='测试天气连接',command=self.weather_test).grid(row=9,column=1,sticky='w',pady=12)
  ttk.Label(w,text='高德使用 Web 服务类型 Key 和 adcode；Open-Meteo 使用经纬度，无需 Key。\n“显示”启用同步并显示数据；“隐藏”停止同步，首页保留该分区的配置提示。',style='Muted.TLabel',wraplength=690).grid(row=10,column=0,columnspan=3,sticky='w')
  f=frames['refresh']
  self.combo(f,0,'refresh_minutes','刷新基准间隔（分钟）',['1','2','5','10','15','30','60'])
  self.entry(f,1,'full_refresh_every','全屏清理间隔（次）','每 N 次刷新做一次全屏清理；0 关闭周期清理')
  ttk.Label(f,text='启动后先按整分钟刷新，到下一个 00、10、20…分校准一次。\n之后按设置间隔运行，不再每10分钟重置。同步间隔须为基准间隔的整数倍。\n日照和日期倒计时跨日一起更新；底部刷新图标立即同步，不改变自动基准。',style='Muted.TLabel',wraplength=650).grid(row=2,column=0,columnspan=3,sticky='w',pady=16)
  ttk.Label(f,text='电源键短按：显示屏保并停止自动更新；再按返回仪表盘。\n刷新图标立即更新画面、同步已启用服务；重复点击不会重复请求。\n日出日落本地计算，不依赖天气联网；减少刷新不等于深度休眠。\n保存后安全弹出 USB，重新打开 KDash 生效。',style='Muted.TLabel',wraplength=650).grid(row=5,column=0,columnspan=3,sticky='w',pady=20)
  self.refresh_preview=tk.StringVar()
  ttk.Label(f,textvariable=self.refresh_preview,style='Muted.TLabel',wraplength=650).grid(row=6,column=0,columnspan=3,sticky='w',pady=10)
  for key in ['refresh_minutes','dida_interval','weather_interval']:
   self.fields[key].trace_add('write',lambda *_:self.update_refresh_preview())
  presets=ttk.Frame(f);presets.grid(row=7,column=0,columnspan=3,sticky='w',pady=8)
  for label,periods in [('1 / 15 / 45 分钟',(1,15,45)),('5 / 15 / 30 分钟',(5,15,30)),('10 / 30 / 60 分钟',(10,30,60))]:
   ttk.Button(presets,text=label,command=lambda p=periods:self.set_refresh_preset(*p)).pack(side='left',padx=(0,6))
  f=frames['display'];self.combo(f,0,'clock_format','时间格式',['24h','12h']);self.entry(f,1,'utc_offset','UTC 偏移（分钟）','上海时间 Asia/Shanghai（东八区）为 480');self.entry(f,2,'touch_device','触控设备','留空自动识别，确认方向有误后再调整以下选项')
  self.check(f,3,'swap_xy','交换触控 X / Y');self.check(f,4,'invert_x','反转触控 X');self.check(f,5,'invert_y','反转触控 Y')
  self.fields['utc_offset'].trace_add('write',lambda *_:self.update_solar_preview())
  ttk.Label(f,text='修改配置后，安全弹出 USB，再重新打开 Kindle Dashboard。\n时间、倒计时、待办与天气同屏显示；未启用的服务保留配置提示。',style='Muted.TLabel',wraplength=670).grid(row=7,column=0,columnspan=3,sticky='w',pady=24)
  bottom=ttk.Frame(root,padding=(28,16,28,20));bottom.pack(side='bottom',fill='x',before=tabs)
  self.status=tk.StringVar(value='只读取配置，不会自动写入 Kindle。');ttk.Label(bottom,textvariable=self.status,style='Muted.TLabel',wraplength=520).pack(side='left',fill='x',expand=True)
  self.save_button=ttk.Button(bottom,text='保存配置',style='Primary.TButton',command=self.save);self.save_button.pack(side='right')
  self.populate();root.after(150,self.drain)
  if config_path:self.load_path(Path(config_path))
  else:self.detect()
 def entry(self,f,row,key,label,hint=None,secret=False):
  ttk.Label(f,text=label).grid(row=row,column=0,sticky='w',padx=(0,20),pady=6)
  v=tk.StringVar();self.fields[key]=v;e=ttk.Entry(f,textvariable=v,show='•' if secret else '',width=44);e.grid(row=row,column=1,sticky='ew',pady=6)
  if hint:ttk.Label(f,text=hint,style='Muted.TLabel',wraplength=190).grid(row=row,column=2,sticky='w',padx=(12,0))
  if key in ['event','target']:v.trace_add('write',lambda *_:self.update_preview())
 def visibility(self,f,row,key,label,yes='显示',no='隐藏'):
  ttk.Label(f,text=label).grid(row=row,column=0,sticky='w',padx=(0,20),pady=12)
  group=ttk.Frame(f);group.grid(row=row,column=1,columnspan=2,sticky='w')
  v=tk.BooleanVar();self.fields[key]=v
  ttk.Radiobutton(group,text=yes,variable=v,value=True).pack(side='left',padx=(0,18))
  ttk.Radiobutton(group,text=no,variable=v,value=False).pack(side='left',padx=(0,18))
  status=tk.StringVar()
  def update(*_):status.set('当前：'+(yes if v.get() else no))
  v.trace_add('write',update);update()
  ttk.Label(group,textvariable=status,style='Muted.TLabel').pack(side='left')
 def check(self,f,row,key,label):
  v=tk.BooleanVar();self.fields[key]=v;ttk.Checkbutton(f,text=label,variable=v).grid(row=row,column=0,columnspan=3,sticky='w',pady=8)
 def combo(self,f,row,key,label,values):
  ttk.Label(f,text=label).grid(row=row,column=0,sticky='w',padx=(0,20),pady=8);v=tk.StringVar();self.fields[key]=v;ttk.Combobox(f,textvariable=v,values=values,state='readonly').grid(row=row,column=1,sticky='ew')
 def values(self):return {k:v.get() for k,v in self.fields.items()}
 def populate(self):
  self.populating=True
  c=self.config;m=c.get('modules',{});ev=(m.get('countdown',{}).get('events') or [{}])[0];d=m.get('dida',{});w=m.get('weather',{});i=c.get('input',{})
  values={'refresh_minutes':c.get('ui',{}).get('refresh_minutes',1),'full_refresh_every':c.get('power',{}).get('full_refresh_every',24),'event':ev.get('name','示例事件'),'target':ev.get('date','2030-01-01'),'redirect':'http://127.0.0.1:8080/callback','dida_enabled':d.get('enabled',False),'dida_allow_complete':d.get('allow_complete',True),'weather_enabled':w.get('enabled',False),'dida_interval':d.get('sync_interval_minutes',15),'weather_interval':w.get('sync_interval_minutes',45),'project_ids':','.join(d.get('project_ids',[])),'provider':w.get('provider','amap'),'city':w.get('city',''),'adcode':w.get('adcode',''),'latitude':w.get('solar_location',{}).get('latitude',w.get('latitude',34.2)),'longitude':w.get('solar_location',{}).get('longitude',w.get('longitude',118.8)),'timezone':w.get('timezone','Asia/Shanghai'),'clock_format':m.get('clock',{}).get('format','24h'),'utc_offset':c.get('utc_offset_minutes',480),'touch_device':i.get('device') or '',**{k:i.get(k,False) for k in ['swap_xy','invert_x','invert_y']}}
  for group,fields in [('dida',['client_id','client_secret','access_token','refresh_token']),('amap',['key'])]:
   for key in fields:values[group+'_'+key]=self.private.get(group,{}).get(key) or ''
  self.update_solar_preview()
  self.expires_at=self.private.get('dida',{}).get('expires_at')
  for k,v in values.items():self.fields[k].set(v)
  self.update_solar_preview()
  self.populating=False
  self.update_preview();self.update_project_summary()
 def update_solar_preview(self):
  if not hasattr(self,'solar_preview'):return
  try:
   offset=int(self.fields.get('utc_offset',tk.StringVar(value='480')).get())
   date=dt.datetime.now(dt.timezone(dt.timedelta(minutes=offset))).date()
   v=solar_model.calculate(date,float(self.fields['latitude'].get()),float(self.fields['longitude'].get()),offset)
   if v['state']=='normal':
    mins=int(v['daylight_minutes']+.5)
    self.solar_preview.set(f"今天日出 {solar_model.hhmm(v['sunrise_minute'])}，日落 {solar_model.hhmm(v['sunset_minute'])}；白昼 {mins//60}小时{mins%60:02d}分。离线计算，每天随倒计时更新。")
   else:self.solar_preview.set('当前日期：'+('极昼' if v['state']=='polar_day' else '极夜'))
  except (ValueError,KeyError):self.solar_preview.set('请输入有效经纬度以预览日出日落。')
 def update_preview(self):
  if not hasattr(self,'preview'):return
  try:
   date=model.validate_date(self.fields['target'].get());now=dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).date();days=(date-now).days
   text='今天' if days==0 else (f'还有 {days} 天' if days>0 else f'已过去 {-days} 天')
   self.preview.set(self.fields['event'].get()+' · '+text)
  except ValueError:self.preview.set('请填写有效的目标日期')
 def toggle_dida_advanced(self):
  if self.dida_advanced.winfo_manager():self.dida_advanced.grid_remove()
  else:self.dida_advanced.grid()
 def on_dida_token_edit(self):
  if getattr(self,'populating',False):return
  self.expires_at=0
  self.fields['dida_refresh_token'].set('')
 def update_project_summary(self):
  if not hasattr(self,'project_summary'):return
  ids=[s.strip() for s in self.fields['project_ids'].get().split(',') if s.strip()]
  self.project_summary.set(f'已选择 {len(ids)} 个清单。' if ids else '显示所有可访问清单；也可点击按钮只选需要的清单。')
 def set_refresh_preset(self,base,dida,weather):
  for key,value in [('refresh_minutes',base),('dida_interval',dida),('weather_interval',weather)]:self.fields[key].set(str(value))
 def update_refresh_preview(self):
  try:
   base,dida,weather,cycle=model.refresh_plan(self.values(),self.config)
   next10=(dt.datetime.now(dt.timezone(dt.timedelta(hours=8)))+dt.timedelta(minutes=10)).replace(second=0,microsecond=0)
   next10=next10.replace(minute=(next10.minute//10)*10)
   self.refresh_preview.set(f'若现在重启，首次校准约 {next10:%H:%M}。共同刷新点：每 {base} 分钟。滴答每 {dida} 分钟，天气每 {weather} 分钟。\n配置周期的最小公倍数：{cycle} 分钟（未启用的服务不联网）。')
  except (ValueError,TypeError) as e:self.refresh_preview.set(str(e))
 def load_path(self,path):
  try:
   c,ch=model.load(path)
   if not c or 'modules' not in c:raise ValueError('这不是 KDash 配置文件')
   s,sh=model.load(path.with_name('secrets.json'));self.path=path;self.config=c;self.private=s;self.config_hash=ch;self.secret_hash=sh;self.populate();self.location.set(str(path));self.status.set('已读取。保存时先备份，并保留其他配置。')
  except (OSError,ValueError) as e:messagebox.showerror('读取失败',str(e),parent=self.root)
 def detect(self):
  roots=model.detect_kindles();candidates=[r/'kdash-candidate/config.json' for r in roots if (r/'kdash-candidate/config.json').is_file()]
  if len(candidates)==1:self.load_path(candidates[0])
  elif len(candidates)>1:self.status.set('检测到多个 Kindle，请用“打开配置文件”选择目标。')
  else:
   self.status.set(('已连接 '+', '.join(str(r) for r in roots)+'，尚未安装候选版。' if roots else '未发现 USB 模式的 Kindle。')+' 可先编辑，再另存为本地配置。')
 def open_file(self):
  p=filedialog.askopenfilename(title='选择 KDash config.json',filetypes=[('KDash 配置','*.json')]);
  if p:self.load_path(Path(p))
 def save(self):
  if self.busy:return
  try:
   v=self.values();v['dida_access_token']=model.normalize_access_token(v['dida_access_token']);c=model.apply_config(self.config,v);v['expires_at']=self.expires_at;s=model.apply_secrets(self.private,v)
   if v['dida_enabled'] and not v['dida_access_token']:raise ValueError('请填写 API 口令 / Access Token，或关闭滴答显示')
   if v['weather_enabled'] and v['provider']=='amap' and not v['amap_key']:raise ValueError('请先填写高德 Web 服务 Key，或关闭天气显示')
   if self.path is None:
    name=filedialog.asksaveasfilename(title='保存本地 config.json',initialfile='config.json',defaultextension='.json',filetypes=[('JSON','*.json')])
    if not name:return
    path=Path(name);ch=model.digest(path);sh=model.digest(path.with_name('secrets.json'))
    if path.exists() or path.with_name('secrets.json').exists():raise ValueError('请打开现有配置后再保存，或选择新的目录，避免覆盖未读取的配置与密钥')
   else:path=self.path;ch=self.config_hash;sh=self.secret_hash
   backup,ch,sh=model.save_bundle(path,c,s,ch,sh,HOME/'config-backups')
   self.path=path;self.config,self.private=c,s;self.config_hash,self.secret_hash=ch,sh;self.location.set(str(path));self.status.set('保存成功。备份：'+str(backup));messagebox.showinfo('保存成功','config.json 和 secrets.json 已保存。\n安全弹出 USB 后重新打开 KDash 生效。\n备份位于：'+str(backup),parent=self.root)
  except (ValueError,OSError) as e:messagebox.showerror('保存失败',str(e),parent=self.root)
 def worker(self,fn,success):
  if self.busy:return
  self.busy=True;self.save_button.state(['disabled']);self.status.set('正在连接，请稍候…')
  def run():
   try:self.queue.put((success,fn(),None))
   except Exception as e:self.queue.put((None,None,str(e) if isinstance(e,ValueError) else '操作失败，请检查配置与网络'))
  threading.Thread(target=run,daemon=True).start()
 def drain(self):
  try:
   while True:
    cb,value,error=self.queue.get_nowait();self.busy=False;self.save_button.state(['!disabled'])
    if error:self.status.set(error);messagebox.showerror('连接未完成',error,parent=self.root)
    else:
     try:cb(value)
     except Exception:self.status.set('返回数据处理失败，请检查配置后重试')
  except queue.Empty:pass
  self.root.after(150,self.drain)
 def authorize(self):
  v=self.values()
  def success(token):
   for k in ['access_token','refresh_token']:self.fields['dida_'+k].set(token.get(k) or '')
   self.expires_at=token.get('expires_at',0);self.status.set('已获得授权，点击“保存配置”后才写入 Kindle。')
  self.worker(lambda:model.oauth_authorize(v['dida_client_id'],v['dida_client_secret'],v['redirect'],write_access=v['dida_allow_complete']),success)
 def fetch_projects(self):
  token=self.fields['dida_access_token'].get()
  def success(projects):
   self.status.set(f'连接成功，读取到 {len(projects)} 个清单。');dialog=tk.Toplevel(self.root);dialog.title('选择显示的清单');dialog.geometry('500x380');dialog.transient(self.root)
   ttk.Label(dialog,text='选择需要显示的清单；不选择表示所有清单。',padding=16).pack(anchor='w');items=tk.Listbox(dialog,selectmode='multiple',font=('Microsoft YaHei UI',10),exportselection=False);items.pack(fill='both',expand=True,padx=16)
   selected=set(self.fields['project_ids'].get().split(','))
   for i,p in enumerate(projects):items.insert('end',p['name']);
   for i,p in enumerate(projects):
    if p['id'] in selected:items.selection_set(i)
   def choose():self.fields['project_ids'].set(','.join(projects[i]['id'] for i in items.curselection()));dialog.destroy()
   ttk.Button(dialog,text='使用所选清单',command=choose).pack(pady=14)
  self.worker(lambda:model.get_projects(token),success)
 def weather_test(self):
  v=self.values();self.worker(lambda:model.test_weather(v),lambda text:(self.status.set('连接成功：'+text),messagebox.showinfo('天气连接成功',text,parent=self.root)))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--config');args=ap.parse_args();root=tk.Tk();ConfigApp(root,args.config);root.mainloop()
if __name__=='__main__':main()
