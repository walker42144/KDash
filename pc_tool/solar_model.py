"""Offline Meeus/NOAA sunrise/sunset, shared conventions with services/solar.lua."""
import math,datetime as dt
R=math.pi/180
sin=lambda x:math.sin(x*R)
cos=lambda x:math.cos(x*R)
def _at(jd):
 t=(jd-2451545)/36525
 L=(280.46646+t*(36000.76983+t*.0003032))%360
 M=357.52911+t*(35999.05029-.0001537*t)
 e=.016708634-t*(.000042037+.0000001267*t)
 C=sin(M)*(1.914602-t*(.004817+.000014*t))+sin(2*M)*(.019993-.000101*t)+sin(3*M)*.000289
 omega=125.04-1934.136*t
 apparent=L+C-.00569-.00478*sin(omega)
 obliq=23+(26+(21.448-t*(46.815+t*(.00059-t*.001813)))/60)/60+.00256*cos(omega)
 decl=math.asin(sin(obliq)*sin(apparent))/R
 y=math.tan(obliq*R/2)**2
 eq=4/R*(y*sin(2*L)-2*e*sin(M)+4*e*y*sin(M)*cos(2*L)-.5*y*y*sin(4*L)-1.25*e*e*sin(2*M))
 return decl,eq
def calculate(date,latitude,longitude,offset=480):
 if isinstance(date,str):date=dt.date.fromisoformat(date)
 lat,lon=float(latitude),float(longitude)
 if not math.isfinite(lat) or not math.isfinite(lon) or abs(lat)>90 or abs(lon)>180:raise ValueError('经纬度无效')
 epoch=dt.datetime.combine(date,dt.time(),dt.timezone.utc).timestamp();jd=epoch/86400+2440587.5
 _,eq=_at(jd+.5-lon/360);noon=720-4*lon-eq;decl,_=_at(jd+noon/1440)
 den=cos(lat)*cos(decl)
 c=(cos(90.833)-sin(lat)*sin(decl))/den if abs(den)>1e-12 else (-2 if lat*decl>0 else 2)
 result={'date':date.isoformat()}
 if c>1:result.update(state='polar_night',daylight_minutes=0)
 elif c< -1:result.update(state='polar_day',daylight_minutes=1440)
 else:
  ha=math.acos(max(-1,min(1,c)))/R
  def event(sign):
   minute=noon+sign*4*ha
   for _ in range(3):
    dec,e=_at(jd+minute/1440);v=(cos(90.833)-sin(lat)*sin(dec))/(cos(lat)*cos(dec))
    minute=720-4*lon-e+sign*4*math.acos(max(-1,min(1,v)))/R
   return minute
  rise,setting=event(-1),event(1)
  result.update(state='normal',sunrise=epoch+rise*60,sunset=epoch+setting*60,sunrise_minute=(rise+offset)%1440,sunset_minute=(setting+offset)%1440,daylight_minutes=max(0,min(1440,setting-rise)))
 result['day_fraction']=result['daylight_minutes']/1440
 return result
def hhmm(minute):
 n=int(minute+.5)%1440
 return f'{n//60:02d}:{n%60:02d}'
