local is_scheduled = false

local drawn

local function release_schedule()
    is_scheduled=false
end

local function draw()
    local focus = kf.mode.get_focus()
    if focus then
        if focus~=drawn then
            drawn.view:clear()
            drawn = focus
        end
        if focus.view:draw() then
            -- wait to release schedule until after processing any events triggered by the drawing
            -- itself
            kf.schedule(release_schedule)
        else
            kf.schedule(draw)
        end
        return
    end
    release_schedule()
end

local function schedule_draw()
    if not is_scheduled then
        is_scheduled = true
        kf.schedule(draw)
    end
end

local pages = {} -- {<tabpage-id> = {page=Page, next=next record, prev=prev record}}
local first_page = nil
local last_page = nil

-- page has .tabpage attribute
local function start_page(page)
end

local function stop_page(page)
end

local function get_page(tabpage or page)
end

local function set_focus(tabpage or page)
end

local module = {
    draw = schedule_draw,
    show = attach_mode,
    hide = detach_mode,

    start_page = start_page,
    stop_page = stop_page,
    get_page = get_page,
    set_focus = set_focus,
}

return module
