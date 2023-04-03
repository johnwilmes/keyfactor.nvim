local kf = require("keyfactor.api")

--[[ params:
        mode
        branchwise <boolean>
]]
local stop_mode = kf.binding.action(function(params)
    local mode = kf.fill(params, "mode")

    if params.branchwise then
        local branch = kf.mode.get_branch(mode)
        if branch then
            kf.stop(branch[1])
        end
    else
        if kf.mode.is_started(mode) then
            kf.stop(mode)
        end
    end
end)


--[[

ways to start editing a buffer:
    - replace target of current mode, if any
    - start new Edit mode
        - standalone in NEW window
        - replacing current mode
            - probably means killing entire current branch; edit mode as child of something else
            seems weird

params:
    focus - default true; whether to focus on the resulting mode
    replace="target", "mode", false-y
        - if "target" then replace target of the mode, if any; failure if no target or if
            invalid buffer for that target
        - if "mode" then replace the entire mode: attempt to take its position in the view, and
        then kill the entire branch of that mode; failure if invalid mode
        - if false-y, then start new Edit mode
    mode = the mode to use (when replace="target" or replace="mode"; ignored for other values of replace)
            -- TODO: if replace = false-y, then allow this to be an alternative to Edit mode?
    page = integer or Page object or false-y; only when replace is false-y
        - if 0, use current Page object
        - if other integer, interpret as tabpage and use the owner Page object
        - if Page object, use it
        - if falsey, create new default Page object

    position = ...; only when replace is false-y
        {relative="viewport" or "name" or false-y
         anchor=which viewport, if relative="viewport", or which named feature if relative="name"
         direction="up" "down" "left" "right"
         postion = if relative: "cursor" or position in the displayed buffer; else: screen position
         width = hint of how wide it should be
         height = hint of how tall it should be
         }
        

]]
local function start_edit(params, buffer)
    local focus = (params.focus~=false)
    if params.replace=="target" then
        local mode = kf.fill(params, "mode")
        -- TODO
    elseif params.replace=="mode" then
        local mode = kf.fill(params, "mode")
        -- TODO
    else
        -- treat params.replace as false; start new Edit mode
        local page = params.page
        if page then
            page = kf.view.get_page(page)
            if not page then
                -- TODO log warning?
            end
        end

        if not page then
            page = kf.view.Page()
        end
        local view = {display=display, position=position}

        local mode = kf.mode.Edit{buffer=buffer, view=view}
        kf.mode.start(mode, focus)
        
    end



    -- TODO validate position?
    -- TODO: params to allow this to be done as change of current target buffer in current mode
    local position = params.position
end

--[[
    params:
        path
        prompt
        position
        display
        focus
]]
local edit_file = kf.binding.action(function(params)
    local path = params.path or nil
    local picker = params.picker

    if not path and not picker then
        picker = "find_files"
    end

    if picker then
        local result = kf.mode.await_prompt(kf.mode.Telescope{picker=picker})
        if not result.accept then
            return
        end
        path = result.value
    end

    local buffer = vim.fn.bufadd(path)
    vim.api.nvim_buf_set_option(buffer, 'buflisted', true)
    start_edit(params, buffer)
end)

--[[
    params:
        buffer
        picker
        position
        display
        focus
]]
local edit_buffer = kf.binding.action(function(params)
    local buffer, is_valid
    if params.buffer then
        buffer, is_valid = kf.get_buffer(params.buffer)
    end

    local picker
    if not is_valid then
        if params.picker then
            picker = params.picker
        else
            picker = "buffers"
        end

        local result = kf.mode.await_prompt(kf.mode.Telescope{picker=picker})
        if not result.accept then
            return
        end
        buffer = result.value
    end

    start_edit(params, buffer)
end)

local help = kf.binding.action(function(params)
    local tag = params.tag
    local picker = params.prompt

    if not tag and not picker then
        prompt = "help_tags"
    end

    if picker then
        local result = kf.mode.await_prompt(kf.mode.Telescope{picker=picker, text=tag})

        if not result.accept then
            return
        end
        tag = result.value
    end

    local page = params.page
    if page then
        page = kf.view.get_page(page)
        if not page then
            -- TODO log warning?
        end
    end
    if not page then page = kf.view.get_page(0) end

    local mode
    local focus = (params.focus~=false)
    local replace = params.replace
    if replace~="mode" and replace~=false then
        replace = "target" -- default
    end
    if replace then
        mode = kf.mode.get_help(page)
    end

    if replace~="target" then
        local view = {page=page, position=params.position}
        local new_mode = kf.mode.Help{tag=tag, view=view}

        if replace then
        else
            kf.mode.start(mode, focus)
        end
    end





    if mode then
        if replace=="mode" then

        else -- replace=="target"
            -- TODO navigate to :tag <pattern>
            -- selection = kf.selection.tag(pattern, <context>)
            mode.target:set(selection)
            if focus then
                kf.mode.set_focus(mode)
            end
        end
    else -- start new edit mode
        -- TODO validate position...?
        local position = params.position
        local view = {display=display, position=position}
        local mode = kf.mode.Help{tag=tag, view=view}
        kf.mode.start(mode, focus)
    end
end)

local module = {
    help = help,
    edit_file = edit_file,
    edit_buffer = edit_buffer,
    stop = stop_mode,
}

return module
