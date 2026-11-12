return function(T)
    local Dida = require("services.api.dida")
    local timeutil = require("core.timeutil")

    T.test("dida view classifies today, overdue and upcoming", function()
        local now = timeutil.parse_iso8601("2026-11-11T12:00:00+0800")
        local projects = {
            { id = "p1", name = "Work" },
            { id = "p2", name = "Study" },
        }
        local project_data = {
            p1 = {
                tasks = {
                    {
                        id = "t1", projectId = "p1", title = "Today high",
                        dueDate = "2026-11-11T10:00:00+0800", isAllDay = false,
                        priority = 5, status = 0,
                    },
                    {
                        id = "t2", projectId = "p1", title = "Overdue",
                        dueDate = "2026-11-09", isAllDay = true, priority = 3, status = 0,
                    },
                },
            },
            p2 = {
                tasks = {
                    {
                        id = "t3", projectId = "p2", title = "Upcoming",
                        dueDate = "2026-11-14T00:00:00+0800", isAllDay = false,
                        priority = 1, status = 0,
                    },
                    {
                        id = "t4", projectId = "p2", title = "Done today",
                        dueDate = "2026-11-11T09:00:00+0800", isAllDay = false,
                        priority = 0, status = 2,
                        completedTime = "2026-11-11T09:30:00+0800",
                    },
                    {
                        id = "t5", projectId = "p2", title = "No due date",
                        priority = 0, status = 0,
                    },
                },
            },
        }
        local view = Dida.build_view(projects, project_data, now, 480, { upcoming_days = 7 })
        T.eq(#view.today, 1)
        T.eq(view.today[1].id, "t1")
        T.eq(view.today[1].project, "Work")
        T.eq(#view.overdue, 1)
        T.eq(view.overdue[1].id, "t2")
        T.eq(#view.upcoming, 1)
        T.eq(view.upcoming[1].id, "t3")
        T.eq(view.upcoming[1].days_left, 3)
        T.eq(view.completed_today, 1)
        T.eq(view.total_today, 2)
        T.eq(view.progress, 50)
    end)

    T.test("dida view sorts by priority then due date", function()
        local now = timeutil.parse_iso8601("2026-11-11T12:00:00+0800")
        local projects = { { id = "p", name = "P" } }
        local tasks = {}
        for i, pri in ipairs({ 1, 5, 3 }) do
            tasks[i] = {
                id = "t" .. i, projectId = "p", title = "Task " .. i,
                dueDate = "2026-11-11T0" .. i .. ":00:00+0800", isAllDay = false,
                priority = pri, status = 0,
            }
        end
        local view = Dida.build_view(projects, { p = { tasks = tasks } }, now, 480, {})
        T.eq(view.today[1].priority, 5)
        T.eq(view.today[2].priority, 3)
        T.eq(view.today[3].priority, 1)
    end)
end
