return function(T)
    local Theme = require("ui.theme")
    local Layout = require("ui.layout")

    local function fake_registry(manifests, enabled)
        return {
            get = function(_, id) return manifests[id] and { manifest = manifests[id], id = id } or nil end,
            is_enabled = function(_, id) return enabled[id] ~= false end,
        }
    end

    T.test("layout computes weighted rows", function()
        local theme = Theme.new({ width = 1072, height = 1448 })
        local manifests = {
            a = { id = "a", layout = { min_height = 100 } },
            b = { id = "b", layout = { min_height = 100 } },
            c = { id = "c", layout = { min_height = 80 } },
        }
        local layout = Layout.new({ theme = theme, registry = fake_registry(manifests, {}) })
        local page = {
            layout = {
                { modules = { "a" }, weight = 50 },
                { modules = { "b" }, weight = 30 },
                { modules = { "c" }, weight = 20 },
            },
        }
        local rows = layout:compute(page, { x = 56, y = 200, w = 960, h = 1000 })
        T.eq(#rows, 3)
        T.eq(rows[1].rect.y, 200)
        T.truthy(rows[1].rect.h > rows[2].rect.h)
        T.truthy(rows[3].rect.y > rows[2].rect.y)
    end)

    T.test("layout filters disabled modules and empty rows", function()
        local theme = Theme.new({ width = 1072, height = 1448 })
        local manifests = {
            a = { id = "a", layout = { min_height = 100 } },
            b = { id = "b", layout = { min_height = 100 } },
        }
        local layout = Layout.new({
            theme = theme,
            registry = fake_registry(manifests, { b = false }),
        })
        local rows = layout:compute({
            layout = {
                { modules = { "a" }, weight = 50 },
                { modules = { "b" }, weight = 50 },
            },
        }, { x = 0, y = 0, w = 1000, h = 800 })
        T.eq(#rows, 1)
        T.eq(rows[1].modules[1], "a")
        T.eq(rows[1].rect.h, 800)
    end)

    T.test("layout splits two modules into columns", function()
        local theme = Theme.new({ width = 1072, height = 1448 })
        local manifests = {
            a = { id = "a", layout = { min_height = 100 } },
            b = { id = "b", layout = { min_height = 100 } },
        }
        local layout = Layout.new({ theme = theme, registry = fake_registry(manifests, {}) })
        local rows = layout:compute({
            layout = { { modules = { "a", "b" }, weight = 100 } },
        }, { x = 10, y = 20, w = 1000, h = 600 })
        T.eq(#rows, 1)
        T.eq(rows[1].cells[1].w + rows[1].cells[2].w + theme.space.lg, 1000)
    end)
    T.test("overview keeps disabled services visible without overlapping rows",function()
        local theme=Theme.new({width=1072,height=1448})
        local layout=Layout.new({theme=theme,registry=fake_registry({},{dida=false,weather=false})})
        local rows=layout:compute(require("ui.dashboard").page(),{x=56,y=176,w=960,h=1100})
        T.eq(#rows,3);T.eq(#rows[1].cells,2)
        T.eq(rows[2].modules[1],"dida");T.eq(rows[3].modules[1],"weather")
        for i,row in ipairs(rows) do
            T.truthy(row.rect.y+row.rect.h<=1276)
            if i>1 then T.truthy(row.rect.y>=rows[i-1].rect.y+rows[i-1].rect.h+theme.space.md) end
        end
    end)
    T.test("overview migration preserves API settings and custom pages",function()
        local data={ui={},pages={{id="home"},{id="tasks"},{id="custom"}},modules={dida={enabled=true,project_ids={"keep"}}}}
        require("ui.dashboard").apply(data)
        T.eq(#data.pages,2);T.eq(data.pages[2].id,"custom")
        T.eq(data.modules.dida.project_ids[1],"keep");T.truthy(data.modules.dida.enabled)
    end)

end
