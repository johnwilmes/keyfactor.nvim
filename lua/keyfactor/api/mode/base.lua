local module = {}

--[[

Pages:
    - organize a single tabpage using some layout
    - own a collection of modes (possibly empty)
    - draw themselves with window layout, and direct modes to draw in assigned windows
    - provide a scope or set of defaults for layers and possibly other controllers
    - if mode collection is empty, then page will not be drawn, cannot have focus

Modes:
    - must provide a layer controller
    - may provide other controllers
    - must provide a viewport (describing its desired window)
    - draws self in assigned window as directed by page

Prompts:
    - form a stack
    - must provide a layer controller
    - may provide other controllers
    - draw themselves, but may also provide a viewport to the current page

Focus:
    -- there is a focus page (as long as a valid page exists), which is a page with at least one mode
    -- if prompt stack is nonempty, the top prompt is treated is focus mode
    -- otherwise, the focus mode is the first (index 1) mode of the focus page
    -- keys are dispatched according to the layer controller of the focus

--]]


local modes = {} -- maps mode object to page

local pages = {} -- maps either tabpage handle or page object to page record
    -- {page=page, tab=tab, modes=<list of modes>}
local focus_page = nil -- record of focus page

local prompts = {} -- stack of active prompts

local lock = false

--[[ Internal functions ]]

local function tabnr_to_tabid(nr)
    local winid = vim.fn.win_getid(1, nr)
    if winid~=0 then
        return vim.api.nvim_win_get_tabpage(winid)
    end
end

local function get_page_record(handle)
    if handle==nil or handle==0 then
        return focus_page
    else
        return pages[handle]
    end
end

local function get_prompt_index(prompt)
    for i,p in ipairs(prompts) do
        if p==prompt then
            return i
        end
    end
end

--[[ API ]]

local function with_lock(func)
    assert(utils.is_callable(func), "invalid function")
    return function(...)
        if lock then
            error("mode lock is active")
        end
        lock = true
        local success, msg = pcall(func, ...)
        lock = false
        if not success then
            error(msg)
        end
        return msg
    end
end

local function is_locked()
    return lock
end

local function is_valid_page(page)
    return type(page)=="table"
end

local function is_valid_mode(mode)
    return not not (type(mode)=="table" and mode.layers and mode.view)
end

local function is_valid_prompt(prompt)
    return not not (type(prompt)=="table" and prompt.layers)
end

-- handle is tabpage handle or page object or mode object (or nil or 0 for focus page)
-- returns corresponding page object if exists, or nil
local function get_page(handle)
    local record = get_page_record(handle)
    if record then
        return record.page
    end
    return modes[handle]
end

local function get_mode()
    return focus_page and focus_page.modes[1]
end

local function get_prompt()
    return prompts[#prompts]
end

local function get_prompt_stack()
    return {unpack(prompts)}
end

-- handle is tabpage handle or page object (or nil or 0 for focus page)
-- returns tabpage handle if exists, or nil
local function get_tab(handle)
    local record = get_page_record(handle)
    if record then
        return record.tab
    end
end

-- handle is page or tab
local function get_attached_modes(handle)
    local record = get_page_record(handle)
    if record then
        return {unpack(record.modes)}
    end
end

local start_page = with_lock(function(page)
    if pages[page] or not is_valid_page(page) then
        error("invalid page")
    end

    local tab = vim.api.nvim_get_current_tabpage()
    if not vim.tbl_isempty(pages) then
        local tab_restore = tab
        vim.utils.noautocmd(function()
            vim.cmd("tab new")
            local new_buf = vim.api.nvim_get_current_buf()
            vim.api.nvim_win_set_buf(base_win, kf.get_null_buffer())
            vim.api.nvim_buf_delete(new_buf, {force=true})
            tab = vim.api.nvim_get_current_tabpage()
            vim.api.nvim_set_current_tabpage(tab_restore)
        end)
    end -- else use existing tab
    assert(not pages[tab], "tabpage already in use")

    local record = {page=page, tab=tab, modes={}}
    pages[page] = record
    pages[tab] = record
    local success, msg = pcall(page._start, page, tab)
    if not success then
        pages[page]=nil
        pages[tab]=nil
        error(msg)
    end
    kf.events.enqueue(page, kf.events.page.start, {tab=tab})
    -- no focus events, since page doesn't have any associated modes so can't have focus
end)

-- page is page object or tabpage handle
local stop_page = with_lock(function(handle)
    local record = get_page_record(handle)
    if not record then
        error("invalid page")
    end

    for i=#record.modes,1,-1 do
        local mode = record.modes[i]
        modes[mode]=nil
        record.modes[i]=nil
        pcall(mode._stop, mode, record.page)
        kf.events.enqueue(mode, kf.events.mode.stop, {page=page})
    end

    local next_page
    if record==focus_page then
        next_page = get_next_page(record.page)
    end
    pages[record.page] = nil
    pages[record.tab] = nil
    if vim.fn.tabpagenr("$")>1 and vim.api.nvim_tabpage_is_valid(record.tab) then
        local tabnr = vim.api.nvim_tabpage_get_number(record.tab)
        vim.cmd("tabclose"..tabnr)
    end
    pcall(record.page._stop, record.page, record.tab)
    kf.events.enqueue(record.page, kf.events.page.stop, {tab=record.tab})
    if next_page then
        focus_page = next_page
        kf.events.enqueue(focus_page, kf.events.page.focus)
        kf.events.enqueue(focus_page.modes[1], kf.events.mode.focus, {page=record.page})
    else
        focus_page = nil
    end
end)

-- handle can be tabpage handle or page target (NOT nil or 0)
-- sets page to be the focus page
local set_page = with_lock(function(handle)
    local record = pages[handle]
    if not (page_record and page_record.modes[1]) then
        -- no such page or page has no modes
        return false
    end

    if page_record==focus_page then
        return true
    end

    local old_page = focus_page
    focus_page = page_record
    kf.events.enqueue(old_page.modes[1], kf.events.mode.unfocus, {page=old_page})
    kf.events.enqueue(old_page.page, kf.events.page.unfocus)
    kf.events.enqueue(page_record.page, kf.events.page.focus)
    kf.events.enqueue(page_record.modes[1], kf.events.mode.focus, {page=page_record})
    return true
end)

-- sets mode as focus w/in its page
-- (does not set page as focus page)
local set_mode = with_lock(function(mode)
    local page = modes[mode]
    if not page then
        return false
    end

    local record = pages[page]
    if record.modes[1]==mode then
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

    assert(found, "inconsistent page state")
    record.modes[1]=mode
    if focus_page==record then
        kf.events.enqueue(record.modes[2], kf.events.mode.unfocus, {page=page})
        kf.events.enqueue(mode, kf.events.mode.focus, {page=page})
    end
    return true
end)

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

--[[

    opts:
        page (default current page)
        focus (whether mode should get focus within its page (does not focus the page itself)
            (default true)
            can also be an integer, in which case insert in this position
        position


]]
local start_mode = with_lock(function(mode, opts)
    if modes[mode] or not is_valid_mode(mode) then
        error("invalid mode")
    end
    local record = get_page_record(opts.page)
    if not record then
        error("invalid page")
    end

    local index = 1
    if type(opts.focus)=="number" then
        index = math.max(1, math.min(math.floor(opts.focus), #record.modes+1))
        table.insert(record.modes, index, mode)
    elseif opts.focus==false then
        index = #record.modes+1
    else
        index = 1
    end

    modes[mode] = record.page
    table.insert(record.modes, index, mode)
    local success, msg = pcall(mode, mode._start, record.page)
    if not success then
        modes[mode]=nil
        table.remove(record.modes, index)
        error(msg)
    end
    success, msg = pcall(record.page, record.page._add_mode, {index=index, position=opts.position, mode=mode})
    if not success then
        modes[mode]=nil
        table.remove(record.modes, index)
        error(msg)
    end

    kf.events.enqueue(mode, kf.events.mode.start, {page=record.page})
    if (index==1) and (record.page==focus_page) then
        kf.events.enqueue(record.modes[2], kf.events.mode.unfocus, {page=record.page})
        kf.events.enqueue(mode, kf.events.mode.focus, {page=record.page})
    end
end)

local stop_mode = with_lock(function(mode)
    local page = modes[mode]
    if not page then
        return false
    end
    local record = pages[page]
    assert(record, "inconsistent page state")

    modes[mode]=nil
    local index=nil
    for i=1,#record.modes do
        local m = record.modes[i]
        if index then
            record[i-1]=m
        elseif m==mode then
            index=i
        end
    end
    pcall(page, page._remove_mode, {mode=mode, index=index})
    pcall(mode, mode._stop, page)
    kf.events.enqueue(mode, kf.events.mode.stop, {page=page})
    if index==1 and focus_page==record then
        -- stopped mode had focus
        if page_record.modes[1] then
            kf.events.enqueue(record.modes[1], kf.events.mode.focus, {page=page})
        else
            focus_page=get_next_page(page)
            kf.events.enqueue(page, kf.events.page.unfocus)
            if focus_page then
                kf.events.enqueue(focus_page.page, kf.events.page.focus)
                kf.events.enqueue(focus_page.modes[1], kf.events.mode.focus, {page=focus_page.page})
            end
        end
    end
end)

local start_prompt = with_lock(function(prompt)
    if get_prompt_index(prompt) or not is_valid_prompt(prompt) then
        error("invalid prompt")
    end

    prompts[#prompts+1]=prompt
    local success, msg = pcall(prompt, prompt._start)
    if not success then
        prompts[#prompts]=nil
        error(msg)
    end
    kf.enqueue(prompt, kf.events.prompt.start)
end)

local stop_prompt = with_lock(function(all)
    local last = (all and 1) or #prompts
    for i=#prompts,last,-1 do
        local prompt = table.remove(prompts)
        pcall(prompt, prompt._stop)
        kf.enqueue(prompt, kf.events.prompt.stop)
    end
end)

return module
