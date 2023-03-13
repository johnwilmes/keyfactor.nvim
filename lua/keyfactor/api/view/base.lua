local is_scheduled = false

local displays = {}
local current_display

local function release_schedule()
    is_scheduled=false
end

local function draw()
    local focus = kf.mode.get_focus()
    if focus then
        local new_display = displays[focus]
        if new_display then
            if current_display ~= new_display then
                current_display:clear()
                current_display = new_display
            end
            new_display:draw()
            -- wait to release schedule until after processing any events triggered by the drawing
            -- itself
            vim.schedule(release_schedule)
            return
        end
    end
    release_schedule()
end

local function schedule_draw()
    if not is_scheduled then
        is_scheduled = true
        vim.schedule(draw)
    end
end

local function attach_mode(mode, display, position)
    if not display then
        display = current_display
        if not display then
            return
        end
    end
    local previous = displays[mode]
    if previous and display~=previous then
        displays[mode] = display
        if not pcall(previous.remove, previous, mode) then
            -- TODO log error
        end
    end
    display:add(mode, position)
end

local function detach_mode(mode)
    local display = displays[mode]
    if display then
        displays[mode]=nil
        display:remove(mode)
    end
end

local module = {
    update = schedule_draw,
    show = attach_mode,
    hide = detach_mode,
}

return module
