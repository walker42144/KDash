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
        self.app_dir .. "/assets/fonts/NotoSansSC-Medium.otf",
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

-- virtual_size describes framebuffer allocation/stride and multiple buffers, not the viewport.
function Paths.parse_fbink_state(data)
    local w = tonumber((data or ""):match("viewWidth=(%d+);"))
    local h = tonumber((data or ""):match("viewHeight=(%d+);"))
    local bpp = tonumber((data or ""):match("BPP=(%d+);"))
    if not w or not h or not bpp then return nil, nil, "missing FBInk visible geometry" end
    if w ~= 1072 or h ~= 1448 or bpp ~= 8 then
        return nil, nil, "unreviewed FBInk viewport or pixel format"
    end
    return w, h
end

function Paths:screen_size(runner, fbink)
    local code, state = runner:run({fbink, "-e"}, "read FBInk visible geometry")
    if code ~= 0 then error("cannot query FBInk visible geometry") end
    local w, h, err = Paths.parse_fbink_state(state)
    if not w then error(err) end
    return w, h
end

return Paths
