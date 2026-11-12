-- A single overview, including reserved sections for unconfigured services.
local M = {}
function M.page()
 return {id="home",title="KDASH",kind="dashboard",overview=true,layout={
  {modules={"clock","countdown"},weight=24},
  {modules={"dida"},weight=39}, {modules={"weather"},weight=37}}}
end
function M.apply(data)
 local pages={M.page()}
 for _,p in ipairs(data.pages or {}) do
  if p.id~="home" and p.id~="tasks" and p.id~="weather" and p.id~="settings" then pages[#pages+1]=p end
 end
 data.pages=pages;data.last_page="home";data.ui.minimal=true
end
return M
