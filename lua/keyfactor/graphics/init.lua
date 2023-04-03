--[[
Modified from edluffy/hologram.nvim under MIT License

MIT License

Copyright (c) 2022 edluffy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local CTRL_KEYS = {
    -- General
    action = 'a',
    delete_action = 'd',

    -- Transmission
    format = 'f',
    transmission_type = 't',
    data_width = 's',
    data_height = 'v',
    data_size = 'S',
    data_offset = 'O',
    image_id = 'i',
    image_number = 'I',

    -- Display
    placement_id = 'p',
    x_offset = 'x',
    y_offset = 'y',
    width = 'w',
    height = 'h',
    cell_x_offset = 'X',
    cell_y_offset = 'Y',
    cols = 'c',
    rows = 'r',
    cursor_movement = 'C',
    z_index = 'z',

    -- Unavailable keys
    -- more=m
    -- quiet=q
    -- compressed=o
}

local stdout = vim.loop.new_tty(1, false)


local function send_graphics_command(options, payload)
    local ctrl = ''
    for k, v in pairs(options) do
        if v ~= nil then
            ctrl = ctrl..CTRL_KEYS[k]..'='..v..','
        end
    end
    ctrl = ctrl..'q=2' -- suppress all responses from kitty

    if payload then
        payload = require("base64").encode(payload)
        chunks = terminal.get_chunked(payload)
        if #chunks > 1 then
            ctrl = ctrl..',m=1'
        end
        for i=1,#chunks do
            terminal.write('\x1b_G'..ctrl..';'..chunks[i]..'\x1b\\')
            if i == #chunks-1 then ctrl = 'm=0' else ctrl = 'm=1' end
        end
    else
        terminal.write('\x1b_G'..ctrl..'\x1b\\')
    end
end

-- Split into chunks of max 4096 length
local function get_chunked(str)
    local chunks = {}
    for i = 1,#str,4096 do
        local chunk = str:sub(i, i + 4096 - 1)
        table.insert(chunks, chunk)
    end
    return chunks
end

local function move_cursor(row, col)
    terminal.write('\x1b[s')
    terminal.write('\x1b['..row..':'..col..'H')
end

local function restore_cursor()
    terminal.write('\x1b[u')
end

-- glob together writes to stdout
terminal.write = vim.schedule_wrap(function(data)
    stdout:write(data)
end)

local module = {}

local placements = {}

function module.create_image(width, height, rgba)
    local id = #placements+1
    placements[id] = 0
    send_graphics_command({
        action='t',
        format=32, -- rgba
        data_width=width,
        data_height=height,
        image_id=id,
    })
    return id
end

function module.place_image(id, window, row, col, opts)
    -- TODO translate row col relative to window
    local p = placements[id]+1
    move_cursor(row, col)
    local cmd = vim.tbl_extend("force", opts, {
        action='p',
        rows=1,
        image_id=id,
        placement_id=p
    })
    send_graphics_command(cmd)
    placements[id]=p
end

function module.clear_image(id)
    placements[id]=0
    send_graphics_command({
        action='d',
        delete_action='i',
        image_id=id
    })
end

return module
