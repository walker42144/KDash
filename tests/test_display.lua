return function(T)
    local Display = require("platform.kindle.display_fbink")

    local function fake_runner()
        local r = { calls = {} }
        function r:run(argv, note)
            self.calls[#self.calls + 1] = { argv = argv, note = note }
            return 0, ""
        end
        return r
    end

    T.test("display constructor returns a usable instance", function()
        local runner = fake_runner()
        local d = Display.new({
            runner = runner,
            fbink = "/var/tmp/kdash-bin/fbink",
            width = 1072,
            height = 1448,
            font = "/mnt/us/kdash/assets/DroidSansFallbackFull.ttf",
            log = { error = function() end, warn = function() end },
        })
        T.truthy(d, "Display.new must return self")
        T.eq(d.width, 1072)
        T.eq(d.height, 1448)
        T.eq(d.available, true)
        T.truthy(d.text)
        T.truthy(d.flush)
    end)

    T.test("display text builds FBInk OTF arguments", function()
        local runner = fake_runner()
        local d = Display.new({
            runner = runner, fbink = "/var/tmp/kdash-bin/fbink",
            width = 1072, height = 1448,
            font = "/mnt/us/kdash/assets/DroidSansFallbackFull.ttf",
            log = { error = function() end, warn = function() end },
        })
        d:begin_frame(true)
        d:text({
            x = 56, y = 100, w = 960, size = 36, text = "测试 KDash",
            color = "ink", bg = "paper", measure_w = 200, h=52, valign="center",
        })
        T.truthy(d:flush({ full = true }))
        local text_calls = 0
        local vertical_center=false
        for _, c in ipairs(runner.calls) do
            for _, a in ipairs(c.argv) do
                if a == "-t" then text_calls = text_calls + 1 end
                if a == "-M" then vertical_center=true end
                if a == "--" then
                    -- 文本必须作为最后一个参数
                    T.eq(c.argv[#c.argv], "测试 KDash")
                end
            end
        end
        T.eq(text_calls, 1)
        T.truthy(vertical_center,"button text centers within its declared rectangle")
    end)

    T.test("display marks unavailable when fbink fails", function()
        local runner = { run = function() return 1, "boom" end }
        local d = Display.new({
            runner = runner, fbink = "/var/tmp/kdash-bin/fbink",
            width = 1072, height = 1448,
            font = "/mnt/us/kdash/assets/DroidSansFallbackFull.ttf",
            log = { error = function() end, warn = function() end },
        })
        d:begin_frame(true)
        T.falsy(d:flush({ full = true }))
        T.eq(d.available, false)
    end)
    T.test("periodic full cleaning follows configured count and can be disabled",function()
        for _,period in ipairs({0,2}) do
            local runner=fake_runner();local d=Display.new({runner=runner,fbink='fbink',full_refresh_every=period})
            for i=1,4 do d:begin_frame(false);d:fill({x=0,y=0,w=100,h=100},'paper');T.truthy(d:flush({full=false})) end
            local full=0
            for _,call in ipairs(runner.calls) do if call.note=='full refresh' then full=full+1 end end
            T.eq(full,period==0 and 0 or 2)
        end
    end)

    T.test("user logo uses the supported OpenType path with deferred refresh",function()
        local runner=fake_runner();local d=Display.new({runner=runner,fbink='fbink',width=1072,height=1448})
        d:begin_frame(false);d:icon('assets/logo-user.ttf',56,36,80,80)
        T.eq(#runner.calls,0);T.truthy(d:flush({full=false}))
        local draw=runner.calls[1].argv
        T.eq(draw[3],'-b');T.eq(draw[4],'-t')
        T.truthy(draw[5]:find('regular=assets/logo%-user.ttf,px=80,top=36'))
        T.eq(draw[#draw],'A');T.eq(runner.calls[2].note,'region refresh')
    end)
end
