-- Project a cached task tree onto the current local date without mutating source data.
local M={}
local metadata=require('services.task_metadata')
local function own_date(task)
 if task.date_metadata then return task.own_due_key end
 return task.own_due_key or task.due_key or (type(task.source_due)=='string' and task.source_due:match('^(%d%d%d%d%-%d%d%-%d%d)'))
end

local function sort_tasks(tasks, keys, mode)
 local order={}
 for i,task in ipairs(tasks) do order[task]=i end
 table.sort(tasks,function(a,b)
  local ka,kb=keys[a],keys[b]
  local pa=a.context_only and 0 or (a.priority or 0)
  local pb=b.context_only and 0 or (b.priority or 0)
  if mode=='priority' and pa~=pb then return pa>pb end
  if ka~=kb then return ka<kb end
  if pa~=pb then return pa>pb end
  return order[a]<order[b]
 end)
end

function M.select(view,today,offset,mode)
 local keys={}
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
  sort_tasks(children,keys,mode)
  out.children=children;out.context_only=not included
  if not included then out.checklist={} end
  local label=included and metadata.time_label(task,offset)
  if label then
   keys[out]=label:sub(1,5)
  elseif not included and children[1] then
   keys[out]=keys[children[1]]
  else
   keys[out]='~'
  end
  return out
 end
 local roots={}
 for _,bucket in ipairs({'today','overdue','upcoming','undated'}) do
  for _,task in ipairs(view[bucket] or {}) do local selected=project(task,nil,false);if selected then roots[#roots+1]=selected end end
 end
 sort_tasks(roots,keys,mode)
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
