-- 运行时路径与字体探测。
local util = require("core.util")

local Paths = {}
Paths.__index = Paths

function Paths.new(opts)
    local self = setmetatable({}, Paths)
    self.app_dir = opts.app_dir
    self.data_dir = opts.data_dir or "/mnt/us/kdash"
    self.cache_dir = self.data_dir .. "/cache"
    self.log_dir = self.data_dir .. "/logs"
    self.state_dir = self.data_dir .. "/state"
    self.config_path = self.data_dir .. "/config.json"
    self.secrets_path = self.data_dir .. "/secrets.json"
    self.default_config = self.app_dir .. "/config/default.json"
    return self
end

function Paths:font_candidates()
    return {
        self.app_dir .. "/assets/fonts/NotoSansSC-Regular.otf",
        self.data_dir .. "/assets/DroidSansFallbackFull.ttf",
        self.app_dir .. "/assets/fonts/DroidSansFallbackFull.ttf",
        self.data_dir .. "/assets/DroidSansFallback.ttf",
        self.app_dir .. "/assets/fonts/DroidSansFallback.ttf",
        "/usr/java/lib/fonts/DroidSansFallbackFull.ttf",
        "/usr/java/lib/fonts/DroidSansFallback.ttf",
        "/usr/java/lib/fonts/STHeiti_Light.ttf",
        "/usr/java/lib/fonts/NotoSansCJKsc-Regular.otf",
    }
end

function Paths:find_font(configured)
    if configured and configured ~= "" then
        if util.path_exists(configured) then return configured end
    end
    for _, p in ipairs(self:font_candidates()) do
        if util.path_exists(p) then return p end
    end
    return nil
end

function Paths:screen_size()
    local data = util.read_file("/sys/class/graphics/fb0/virtual_size")
    if data then
        local w, h = data:match("(%d+),(%d+)")
        if w and h then return tonumber(w), tonumber(h) end
    end
    return 1072, 1448
end

return Paths
