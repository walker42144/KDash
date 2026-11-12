-- 主机侧单元测试入口：luajit tests/run.lua
package.path = "./?.lua;./?/init.lua;./tests/?.lua;" .. package.path

local T = require("tests.lib")
local files = {
    "test_candidate",
    "test_refresh",
    "test_today_pause",
    "test_power_sleep",
    "test_r12",
    "test_r13",
    "test_geometry",
    "test_device",
    "test_amap",
    "test_json",
    "test_timeutil",
    "test_scheduler",
    "test_config",
    "test_layout",
    "test_dida",
    "test_dida_write",
    "test_task_controls",
    "test_weather",
    "test_touch",
    "test_registry",
    "test_http",
    "test_display",
    "test_app_boot",
}

for _, name in ipairs(files) do
    local ok, mod = pcall(require, name)
    if not ok then
        T.fail = T.fail + 1
        print("FAIL load " .. name .. ": " .. tostring(mod))
    else
        mod(T)
    end
end

print(string.format("\n%d passed, %d failed", T.pass, T.fail))
os.exit(T.fail == 0 and 0 or 1)
