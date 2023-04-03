local module = {}

local redraw_triggers = {"WinEnter", "WinLeave", "WinScrolled", "WinClosed", "TabEnter", "TabLeave"}

local style = {
    KFSelectionPrimaryFocusInner={bg="#ff0000"},
    KFSelectionPrimaryFocusOuter={bg="#ff7f7f"},
    KFSelectionPrimaryFocusEmpty={sp="#ff000", underline=true, strikethrough=true},
    KFSelectionPrimaryBaseInner={bg="#a50000"},
    KFSelectionPrimaryBaseOuter={bg="#a55252"},
    KFSelectionPrimaryBaseEmpty={sp="#a50000", underline=true, strikethrough=true},

    KFSelectionSecondaryFocusInner={bg="#7f7f7f"},
    KFSelectionSecondaryFocusOuter={bg="#bfbfbf"},
    KFSelectionSecondaryFocusEmpty={sp="#7f7f7f", underline=true, strikethrough=true},
    KFSelectionSecondaryBaseInner={bg="#7f7f7f"},
    KFSelectionSecondaryBaseOuter={bg="#bfbfbf"},
    KFSelectionSecondaryBaseEmpty={bg="#7f7f7f", underline=true, strikethrough=true},
}

--[[


suggested options:
winheight, winwidth, winminheight, winminwidth = 1
equalalways = false/off


--]]

function module.setup()
    --[[ Selection highlight styles ]]
    -- TODO configuration

    for group,val in pairs(style) do
        vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", style, {default=true}))
    end


    --[[ Initialize displays and modes ]]
    --
    -- iterate over all existing tabpages
    --      create new tabpage display for each
    --      iterate over existing windows
    --          create new Edit mode for each
    --          pass to Display with position set to the existing window
    --

    --[[ Page trigger events ]]
    -- TODO set up event listener for tabpage close
    vim.api.nvim_create_autocmd("TabClosed", {
        callback = function(params)
            local tabnr = tonumber(params.file)
            if tabnr then
                local tab = utils.vim.get_tabid(tabnr)
                local page = kf.get_page(tab)
                if page then
                    kf.page.stop_page(page)
                end
            end
        end
    })

    --[[ Redraw trigger events ]]
    vim.api.nvim_create_autocmd(redraw_triggers, {
        callback=kf.view.update,
    })

    -- TODO attach mode to display, if not already attached?
    -- kf.events.attach{listener=, object=self, event=kf.events.mode.start}
    -- TODO remove mode from display?
    -- kf.events.attach{listener=, object=self, event=kf.events.mode.stop}

    -- TODO shouldn't we check if we are already listening for this buffer?
    vim.api.nvim_create_autocmd("BufWinEnter", {
        callback = function(params)
            kf.view.schedule_redraw()
            vim.api.nvim_buf_attach(params.buf, false, {
                on_lines=kf.view.schedule_redraw,
                on_reload=kf.view.schedule_redraw,
                on_changed_tick=kf.view.schedule_redraw
            })
        end
    })
end

return module
