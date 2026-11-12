-- Meeus/NOAA solar equations, apparent horizon -0.833 degrees.
-- East longitude positive; results are UTC epochs and local wall-clock minutes.
local T=require('core.timeutil');local S={};local rad=math.pi/180
local function sin(x) return math.sin(x*rad) end
local function cos(x) return math.cos(x*rad) end
local function at(jd)
 local t=(jd-2451545)/36525
 local L=(280.46646+t*(36000.76983+t*.0003032))%360
 local M=357.52911+t*(35999.05029-.0001537*t)
 local e=.016708634-t*(.000042037+.0000001267*t)
 local C=sin(M)*(1.914602-t*(.004817+.000014*t))+sin(2*M)*(.019993-.000101*t)+sin(3*M)*.000289
 local omega=125.04-1934.136*t
 local apparent=L+C-.00569-.00478*sin(omega)
 local obliq=23+(26+(21.448-t*(46.815+t*(.00059-t*.001813)))/60)/60+.00256*cos(omega)
 local decl=math.asin(sin(obliq)*sin(apparent))/rad
 local y=math.tan(obliq*rad/2)^2
 local eq=4/rad*(y*sin(2*L)-2*e*sin(M)+4*e*y*sin(M)*cos(2*L)-.5*y*y*sin(4*L)-1.25*e*e*sin(2*M))
 return decl,eq
end
function S.calculate(date,lat,lon,offset)
 local y,m,d=T.parse_date(date);lat,lon=tonumber(lat),tonumber(lon);offset=tonumber(offset) or 480
 if not y or not lat or not lon or lat~=lat or lon~=lon or math.abs(lat)>90 or math.abs(lon)>180 then return nil,'SOLAR_LOCATION_INVALID' end
 local epoch=T.days_from_civil(y,m,d)*86400;local jd=epoch/86400+2440587.5
 local _,eq=at(jd+.5-lon/360);local noon=720-4*lon-eq
 local decl=at(jd+noon/1440)
 local denominator=cos(lat)*cos(decl)
 local c=(cos(90.833)-sin(lat)*sin(decl))/denominator
 if math.abs(denominator)<1e-12 then c=lat*decl>0 and -2 or 2 end
 local result={date=date,latitude=lat,longitude=lon,offset=offset}
 if c>1 then result.state='polar_night';result.daylight_minutes=0
 elseif c< -1 then result.state='polar_day';result.daylight_minutes=1440
 else
  local ha=math.acos(math.max(-1,math.min(1,c)))/rad
  local function event(sign)
   local minute=noon+sign*4*ha
   for _=1,3 do
    local dec,e=at(jd+minute/1440)
    local v=(cos(90.833)-sin(lat)*sin(dec))/(cos(lat)*cos(dec))
    minute=720-4*lon-e+sign*4*math.acos(math.max(-1,math.min(1,v)))/rad
   end
   return minute
  end
  local rise,set=event(-1),event(1)
  result.state='normal';result.sunrise=epoch+rise*60;result.sunset=epoch+set*60
  result.sunrise_minute=(rise+offset)%1440;result.sunset_minute=(set+offset)%1440
  result.daylight_minutes=math.max(0,math.min(1440,set-rise))
 end
 result.night_minutes=1440-result.daylight_minutes;result.day_fraction=result.daylight_minutes/1440
 return result
end
function S.hhmm(minute)
 if minute==nil then return '--:--' end
 minute=math.floor(minute+.5)%1440;return string.format('%02d:%02d',math.floor(minute/60),minute%60)
end
return S
