local kf = require("keyfactor.api")

local stop = kf.binding.action(function(params)
    kf.view.stop_page()
    -- this emits an event, and attached modes will either stop or figure out a different way to do their view
end)

local focus = kf.binding.action(function(params)
    -- get all windows, with mode association, for page

    -- if direction is set:
    -- set focus on current focus window at cursor position
    -- repeat until window stays same, or we get window in filtered list:
    --      move window in given direction
    --
    --
    -- else if direction is not set:
    --      ChooseWindowMode:
    --      create new view on top of page
    --      the mode does the same window filtering
    --          puts an overlay over each window labeling it
    --          getkey to get the label
end)

local module = {}

return module
