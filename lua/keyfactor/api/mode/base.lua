local module = {}

module.events = {
    start = {},
    stop = {},
    yield = {},
    resume = {},
    focus = {},
    unfocus = {}
}

--[[

Pages:
    - organize a single tabpage using some layout
    - own a collection of local modes (and their children)
    - are able to draw themselves (and attached local modes)
    - provide a scope or set of defaults for layers and possibly other controllers

All modes:
    - must provide a layer controller

Global modes:
    - like pages, draw themselves rather than being drawn by a page
    - unlike pages, can't attach local modes to them, don't provide scope/defaults to local modes
    - can only have at most one active at a time; always has focus
    - is allowed but not required to use a page to help draw

Local modes:
    - must provide at least one viewport

Focus:
    -- there is a focus page (as long as a valid page exists) which is a page with at least one local mode
    -- if there is no global mode, then the focus mode is the first (index 1) mode of the focus page
    -- keys are dispatched according to the layer controller of the leaf of the focus mode

--]]


local modes = {}
    -- {[1]=mode, ([2]=child, [3]=grandchild, ..., if local/global)
    --  page=page (if local/child of local)
    --  root=<root record> (if child)
    --  index=index in root (if child)
    --  }

local pages = {} -- maps either tabpage handle or page object to page record
    -- {page=page, tab=tab, modes=<list of local modes>}
local focus_page = nil -- record of focus page
local global_mode = nil -- record of global mode, if one is active
local null_buffer -- buffer to use in empty tabs

--[[ Internal functions ]]

local function tabnr_to_tabid(nr)
    local winid = vim.fn.win_getid(1, nr)
    if winid~=0 then
        return vim.api.nvim_win_get_tabpage(winid)
    end
end

local function stop_children(record, i)
    for j=#record,i,-1 do
        local child = record[j]
        modes[child] = nil
        record[j]=nil
        kf.events.broadcast(child, kf.events.mode.stop)
    end
end

local function stop_local_mode(record, no_page)
    local mode = record[1]
    stop_children(record, 2)
    modes[mode]=nil
    local page_record = pages[record.page]
    local index=nil
    if not no_page then
        for i=1,#page_record.modes do
            local m = record.modes[i]
            if index then
                record[i-1]=m
            elseif m==mode then
                index=i
            end
        end
    end
    kf.events.broadcast(mode, kf.events.mode.stop)
    return index
end

local function stop_global_mode()
    local mode = global_mode[1]
    stop_children(global_mode, 2)
    modes[mode]=nil
    global_mode=nil
    kf.events.broadcast(mode, kf.events.mode.stop)
end

local function get_page_record(handle)
    if handle==nil or handle==0 then
        return focus_page
    else
        return pages[handle]
    end
end

--[[ API ]]

-- handle is tabpage handle or page object (or nil or 0 for focus page)
-- returns page object if exists, or nil
local function get_page(handle)
    local record = get_page_record(handle)
    if record then
        return record.page
    end
end

-- handle is tabpage handle or page object (or nil or 0 for focus page)
-- returns tabpage handle if exists, or nil
local function get_tab(handle)
    local record = get_page_record(handle)
    if record then
        return record.tab
    end
end

local function get_page_modes(handle)
    local record = get_page_record(handle)
    if record then
        return {unpack(record.modes)}
    end
end

-- returns leaf of focus mode
local function get_mode()
    if global_mode then
        return global_mode[#global_mode]
    end
    if focus_page then
        local root = focus_page.modes[1]
        local record = modes[root]
        return record[#record]
    end
end

-- init is page constructor
local function start_page(init)
    local cleanup = false
    if not vim.tbl_isempty(pages) then
        -- else use existing tabpage
        vim.cmd("tab sb "..null_buffer)
        cleanup = true
    end
    local tabpage = vim.api.nvim_get_current_tabpage()

    local success, result = pcall(init, {tab=tabpage})
    if success and type(result)=="table" then
        local record = {page=result, tab=tabpage, modes={}}
        pages[result] = record
        pages[tab] = record
        kf.events.broadcast(result, kf.events.page.start)
    else
        if cleanup then
            local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
            vim.cmd("tabclose"..tabnr)
        end
        local message = (success and "invalid page constructor") or result
        error(message)
    end
    -- no focus events, since page doesn't have any associated modes so can't have focus
end

-- page is page object or tabpage handle
local function stop_page(handle)
    local record = get_page_record(handle)
    if not record then
        error("invalid page")
    end

    for i=#record.modes,1,-1 do
        stop_local_mode(modes[record.modes[i]], true)
        record.modes[i]=nil
    end

    local next_page
    if record==focus_page then
        next_page = get_next_page(record.page)
    end
    pages[record.page] = nil
    pages[record.tab] = nil
    kf.events.broadcast(record.page, kf.events.page.stop)
    local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
    vim.cmd("tabclose"..tabnr)
    if next_page then
        focus_page = next_page
        kf.events.broadcast(focus_page, kf.events.page.focus)
        kf.events.broadcast(focus_page.modes[1], kf.events.mode.focus)
    end

end

-- handle can be tabpage handle or page target
-- sets page to be the focus page
local function set_page(handle)
    local record = pages[handle]
    if not (page_record and page_record.modes[1]) then
        -- no such page or page has no modes
        return false
    end

    if page_record==focus_page then
        return true
    end

    local old_page = focus_page
    local old_mode = old_page.modes[1]
    focus_page = page_record
    if not global_mode then
        kf.events.broadcast(old_mode, kf.events.mode.unfocus)
    end
    kf.events.broadcast(old_page.page, kf.events.page.unfocus)
    kf.events.broadcast(page_record.page, kf.events.page.focus)
    if not global_mode then
        kf.events.broadcast(page_record.modes[1], kf.events.mode.focus)
    end
    return true
end

-- sets mode as focus w/in its page
-- (does not put focus on page)
-- mode must be local or child of local
local function set_page_focus(mode)
    local mode_record = modes[handle]
    if not mode_record.page then
        return false
    end

    mode_record = mode_record.root or mode_record
    local mode = mode_record[1]
    local page_record = pages[mode_record.page]
    if page_record.modes[1]==mode then
        return true
    end

    local found = false
    for i=#record.modes,1,-1 do
        local m = record.modes[i]
        if found then
            record[i+1]=m
        elseif m==mode then
            found=true
        end
    end
    record.modes[1]=mode

    if focus_page==page_record and not global_mode then
        kf.events.broadcast(record.modes[2], kf.events.mode.unfocus)
        kf.events.broadcast(mode, kf.events.mode.focus)
    end
    return true
end

local function get_next_page(handle, reverse)
    local record = pages[handle]
    local start = vim.api.nvim_tabpage_get_number(record.tab)
    local n_tabs = vim.fn.tabpagenr("$")
    local step = (reverse and -1) or 1
    for i=1,(n_tabs-1) do
        local tab_nr = 1+((n_tabs-1+start+(i*step)) % n_tabs)
        local tab = tabnr_to_tabid(tab_nr)
        record = pages[tab]
        if record and record.modes[1] then
            return record.page
        end
    end
end

-- focus: whether mode should be focus within page (default true)
local function start_local_mode(init, page, focus)
    local record = get_page_record(page)
    if not record then
        error("invalid page")
    end

    local mode = init{page=record.page}
    modes[mode] = {mode, page=record.page}
    if focus~=false then
        table.insert(record.modes, 1, mode)
    else
        table.insert(record.modes, mode)
    end

    -- record==focus_page implies that another mode exists in the page
    local focus_event = focus and (record==focus_page) and not global_mode

    kf.events.broadcast(mode, kf.events.mode.start)
    if focus_event then
        kf.events.broadcast(record.modes[2], kf.events.mode.unfocus)
        kf.events.broadcast(mode, kf.events.mode.focus)
    end
end

local function start_global_mode(init, force)
    if global_mode and not force then
        error("a global mode is already started")
    end

    local mode = init()

    local unfocus = true
    if global_mode then
        stop_global_mode()
        unfocus = false
    end

    global_mode = {mode}
    modes[mode] = global_mode

    kf.broadcast(mode, kf.events.mode.start)
    if unfocus then 
        kf.broadcast(focus_page.modes[1], kf.events.mode.unfocus)
    end
    kf.broadcast(mode, kf.events.mode.focus)
end

local function start_child_mode(init, parent)
    parent = parent or get_mode()
    local root = get_mode_root(parent)

    if not root then
        error("invalid parent")
    end

    local child = init{root=root}
    local record = modes[root]
    record[#record]=child
    modes[child] = {[1]=child, root=record, page=record.page, index=#record}

    kf.events.broadcast(child, kf.events.mode.start)
end

local function stop_mode(mode)
    local record = get_mode_record(mode)
    if record then -- valid mode
        if record.root then -- child mode
            stop_children(record.root, record.index)
            -- focus cannot have changed
        elseif record.page then -- local mode
            local i = stop_local_mode(record)
            local page_record = pages[record.page]
            if i==1 and focus_page==page_record then
                -- stopped mode had focus
                if page_record.modes[1] then
                    kf.events.broadcast(page_record.modes[1], kf.events.mode.focus)
                else
                    focus_page=get_next_page(page_record.page)
                    kf.events.broadcast(page_record.page, kf.events.page.unfocus)
                    if focus_page then
                        kf.events.broadcast(focus_page.page, kf.events.page.focus)
                        kf.events.broadcast(focus_page.modes[1], kf.events.mode.focus)
                    end
                end
        else
            stop_global_mode()
        end
    end
end

local function is_mode_valid(mode)
    return not not get_mode_record(mode)
end

local function is_mode_child(mode)
    local record = get_mode_record(mode)
    return not not (record and record.root)
end

local function is_mode_local(mode)
    local record = get_mode_record(mode)
    if not record then return false end
    record = record.root or record
    return not not record.page
end

local function get_children(mode)
    local record = get_mode_record(mode)
    if not record then return nil end
    local index = 2
    if record.index then
        index = record.index+1
        record = record.root
    end
    return vim.list_slice(record, index, #record)
end

local function get_mode_root(mode)
    local record = get_mode_record(mode)
    if not record then return nil end
    record = record.root or record
    return record[1]
end

local function get_mode_leaf(mode)
    local record = get_mode_record(mode)
    if not record then return nil end
    record = record.root or record
    return record[#record]
end

return module
