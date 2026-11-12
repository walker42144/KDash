-- 设计令牌：E Ink 黑白灰、瑞士式排版、字号与间距比例。
local util = require("core.util")

local Theme = {}
Theme.__index = Theme

local BASE_W = 1072
local BASE_H = 1448

function Theme.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Theme)
    local w = opts.width or BASE_W
    local h = opts.height or BASE_H
    self.width = w
    self.height = h
    self.scale = math.min(w / BASE_W, h / BASE_H) * (opts.font_scale or 1.0)
    self.ink_mode = opts.ink_mode == true
    self.margin = opts.margin or 56
    self.colors = {
        paper = self.ink_mode and "ink" or "paper",
        ink = self.ink_mode and "paper" or "ink",
        muted = self.ink_mode and "paper" or "ink",
        faint = self.ink_mode and "gray8" or "gray2",
        rule = self.ink_mode and "paper" or "ink",
        inverse_bg = self.ink_mode and "paper" or "ink",
        inverse_fg = self.ink_mode and "ink" or "paper",
    }
    local function s(v) return util.round(v * self.scale) end
    self.type = {
        hero = s(176),
        display = s(96),
        title = s(48),
        body = s(36),
        small = s(32),
        micro = s(26),
    }
    self.space = {
        xs = s(8),
        sm = s(16),
        md = s(24),
        lg = s(36),
        xl = s(52),
    }
    self.line = math.max(2, s(2))
    self.header_h = s(104)
    self.footer_h = s(92)
    self.nav_size = s(28)
    return self
end

return Theme
