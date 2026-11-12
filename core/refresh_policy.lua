-- One baseline and one display grid for all automatic updates.
local M={}
function M.minutes(config)
 local n=tonumber((config.ui or {}).refresh_minutes) or 1
 return math.max(1,math.min(60,math.floor(n)))
end
function M.next_slot(config,anchor,now)
 local step=M.minutes(config)*60
 return anchor+(math.floor((now-anchor)/step)+1)*step
end
function M.initial(config,now)
 if (config.ui or {}).refresh_alignment~="first_10min" then return now,nil end
 local off=(config.utc_offset_minutes or 480)*60
 local target=math.ceil((now+off)/600)*600-off
 if target==now then return target,nil end
 return now-now%60,target
end
return M
