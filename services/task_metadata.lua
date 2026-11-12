local time=require('core.timeutil');local M={}
function M.time_label(task,offset)
 if task.is_all_day==true or task.isAllDay==true then return nil end
 local explicit=task.is_all_day==false or task.isAllDay==false
 local function stamp(raw)
  if type(raw)~='string' or not raw:match('T%d%d:%d%d') then return nil end
  if not explicit and raw:match('T00:00:00') then return nil end
  return time.parse_iso8601(raw)
 end
 local start=stamp(task.source_start or task.startDate);local finish=stamp(task.source_due or task.dueDate)
 local function label(ts) return time.format_time(ts,offset or 480,true) end
 if start and finish and finish>start then return label(start)..'-'..label(finish) end
 return (start or finish) and label(start or finish) or nil
end
function M.badges(task,offset)
 local out={};local stamp=M.time_label(task,offset)
 if stamp then out[#out+1]={text=stamp,kind='time'} end
 local seen={}
 for _,tag in ipairs(type(task.tags)=='table' and task.tags or {}) do
  if type(tag)=='string' and tag~='' and not seen[tag] then out[#out+1]={text=tag,kind='tag'};seen[tag]=true end
 end
 return out
end
return M
