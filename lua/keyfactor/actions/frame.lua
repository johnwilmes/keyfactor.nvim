local module = {}
local kf = require("keyfactor.api")
local binding = require("keyfactor.binding")

--[[
    params
        direction = up/down/left/right

--]]
module.split = binding.action(function(params)
    local frame = kf.get_frame()
    -- TODO validate params.direction

    frame = frame:split(params.direction)

    kf.set_frame(frame)
end)

--[[
    params
        direction = up/down/left/right


TODO
module.move = binding.action(function(params)
    local frame = kf.get_frame()

    --vim.fn.winlayout
    --  -- might be polluted by popups, non-focusable!
    --vim.fn.win_splitmove



end)
--]]

--[[
    params
        direction = up/down/left/right
]]
local dir_to_vim = {
    up="k",
    down="j",
    left="h",
    right="l",
}
module.focus = binding.action(function(params)
    local frame = kf.get_frame()

    vim.cmd("wincmd "..dir_to_vim[params.direction])

    -- TODO if focus exists and is visible, take its position
    -- otherwise, take position of midpoint of window
    -- get window 
end)

--[[
    params
        reverse
        partial
        linewise

    TODO count
--]]
module.scroll = binding.action(function(params)
    local mode = kf.get_mode()
    local viewport = mode:get_preview_window()
    if viewport then
        vim.api.nvim_win_call(viewport, function()
            local cmd
            if params.linewise then
                cmd = ((params.reverse) and "<C-y>") or "<C-e>"
            elseif params.partial then
                cmd = ((params.reverse) and "<C-u>") or "<C-d>"
            else
                cmd = ((params.reverse) and "<C-b>") or "<C-f>"
            end
            cmd = vim.api.nvim_replace_termcodes(cmd, true, true, true)
            vim.cmd("normal! "..cmd)
        end)
    end
end)

return module
