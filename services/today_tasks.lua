-- Project a cached task tree onto the current local date without mutating source data.
local M={}
local function own_date(task)
 if task.date_metadata then return task.own_due_key end
 return task.own_due_key or task.due_key or (type(task.source_due)=='string' and task.source_due:match('^(%d%d%d%d%-%d%d%-%d%d)'))
end

function M.select(view,today)
 local function project(task,inherited,nested)
  local date=own_date(task) or inherited
  local is_today=date==today
  local children={}
  for _,child in ipairs(task.children or {}) do
   local selected=project(child,date,true);if selected then children[#children+1]=selected end
  end
  local included=is_today and (not task.completed or nested)
  if not included and #children==0 then return nil end
  local out={};for k,v in pairs(task) do out[k]=v end
  out.children=children;out.context_only=not included
  if not included then out.checklist={} end
  return out
 end
 local roots={}
 for _,bucket in ipairs({'today','overdue','upcoming','undated'}) do
  for _,task in ipairs(view[bucket] or {}) do local selected=project(task,nil,false);if selected then roots[#roots+1]=selected end end
 end
 table.sort(roots,function(a,b) if a.priority~=b.priority then return (a.priority or 0)>(b.priority or 0) end;return a.title<b.title end)
 return roots
end
function M.pending_count(roots)
 local function count(nodes,parent_counted)
  local total=0
  for _,node in ipairs(nodes) do
   local counted=parent_counted or (not node.context_only and not node.completed)
   if not parent_counted and not node.context_only and not node.completed then total=total+1 end
   total=total+count(node.children or {},counted)
  end
  return total
 end
 return count(roots,false)
end

return M
