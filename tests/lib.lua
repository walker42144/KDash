local T = { pass = 0, fail = 0 }

function T.test(name, fn)
    local ok, err = xpcall(fn, function(e)
        return tostring(e) .. "\n" .. debug.traceback("", 2)
    end)
    if ok then
        T.pass = T.pass + 1
        io.write("ok   " .. name .. "\n")
    else
        T.fail = T.fail + 1
        io.write("FAIL " .. name .. "\n" .. tostring(err) .. "\n")
    end
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "not equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function T.truthy(value, msg)
    if not value then error(msg or "expected truthy value", 2) end
end

function T.falsy(value, msg)
    if value then error(msg or "expected falsy value", 2) end
end

function T.near(actual, expected, eps, msg)
    eps = eps or 0.0001
    if math.abs((actual or 0) - expected) > eps then
        error((msg or "not near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

return T
