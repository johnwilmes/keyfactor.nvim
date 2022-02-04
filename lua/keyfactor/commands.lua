local commands = {}
local utils = require("keyfactor.utils")

local CTRL_V = "\22"

-- Would be nice if NVIM api exposed a nicer way to do this. (Or if &opfunc could be a function
-- instead of a string!)
-- TODO when script-local stuff works better, use s: instead of Keyfactor prefix
-- KeyfactorSetCallback is a hack to work around the difficulty of directly assigning lua functions
--      to vimscript variables in the current version
-- KeyfactorDoCallback is a hack to work around fact that script-local variables don't work well in
--      current version of vim.cmd
-- KeyfactorOperator is needed because vim operatorfunc must be a string function name
vim.cmd([[
let s:callbacks = {}

function! KeyfactorSetCallback(name, callback)
    let s:callbacks[a:name] = a:callback
endfunction

function! KeyfactorDoCallback(name)
    return s:callbacks[a:name]()
endfunction

function! KeyfactorOperator(motion_type)
    return s:callbacks["operator"](a:motion_type)
endfunction

nnoremap <Plug>KeyfactorRepeat :<C-U>call KeyfactorDoCallback("repeat")<CR>
]])

--[[Produce a vim text operator from the Lua function `text_operator`. The Lua function should expect a
single string argument which is either 'line', 'char', or 'block', describing what kind of motion
followed the operator. Use the [ and ] marks to find the start and end of the selected text.
]]
function commands.operator(opfunc)
    return function()
        vim.fn.KeyfactorSetCallback("operator", opfunc)
        vim.opt.operatorfunc = "KeyfactorOperator"
        vim.api.nvim_feedkeys('g@', 'ni', false)
    end
end

--[[
Wrap a lua function so that it works well with tpope's vim-repeat.

TODO do we need to supress errors if vim-repeat isn't installed?
]]
local repeat_seq = vim.api.nvim_replace_termcodes("<Plug>KeyfactorRepeat", true, false, true)
function commands.repeatable(map, count, register)
    if register == nil then register = true end
    if count == nil then count = true end

    local function wrapped(...)
        local c = vim.v.count
        local args = {...}
        if register == true then
                vim.fn['repeat#setreg'](repeat_seq, vim.v.register)
        elseif register then
            vim.fn['repeat#setreg'](repeat_seq, register)
        end

        local result = map(...)

        if count == true then
            vim.fn['repeat#set'](repeat_seq, c)
        elseif count == false then
            vim.fn['repeat#set'](repeat_seq, -1)
        else
            vim.fn['repeat#set'](repeat_seq, count)
        end
        vim.fn.KeyfactorSetCallback("repeat", function() wrapped(unpack(args)) end)

        return result
    end

    return wrapped
end

local function do_normal(cmd, remap)
    remap = (remap and ' ') or '! '
    if cmd:lower():sub(1, #'<plug>') == '<plug>' then
        remap = true
    end
    vim.cmd('normal'..remap..cmd)
end

local function as_function(cmd)
    if type(cmd) == "string" then
        return function() do_normal(cmd) end
    else
        return cmd
    end
end

--[[
    [count]fancy_percent jumps to the line that is a (count*10^{-#digits(count)}) fraction of
    the way from the top (or from the bottom, if neg is truthy)

    E.g., if count=4, does the same as "normal 40%"; if count is 432, instead goes 43.2% from
    the top

    If no count is provided, this is treated as 100%

    Note that since we can't give leading zeros, this doesn't provide a way to access lines between
    0 and 10% (except by setting neg=true). But usually count will be a single digit
--]]
function commands.fancy_percent(neg)
    local count = vim.v.count
    local digits = math.ceil(math.log(count+1, 10))
    local percent = count * math.pow(10,-digits)
    if count == 0 then percent = 1 end
    if neg then
        percent = 1 - percent
    end
    local line = math.floor(0.5+(percent*vim.api.nvim_buf_line_count(0)))
    do_normal(tostring(line).."gg") -- TODO is this the best way to do it?
end

--[[ Like gg, but count from the bottom instead of the top ]]
commands.go_to_neg_line = function()
    local count = vim.v.count
    line = vim.api.nvim_buf_line_count(0)-count
    if count == 0 then line = '' end
    do_normal(tostring(line).."gg")
end

--[[ If no count is given, acts like gj (moves lines in display). Otherwise acts like j (moves
     lines in buffer)
  
     If up is truthy, replace j with k
--]]
 -- TODO does this work as expected in visual mode
 commands.fancy_vert = function(up)
    local count = vim.v.count
    local dir = 'j'
    if up then dir = 'k' end
    if count == 0 then
        do_normal('g'..dir)
    else
        do_normal(tostring(count)..dir)
    end
end

--[[ Like p/P/:put[!], except:
    - can force charwise or linewise instead of guessing based on register
    - specify register the usual vim way (unlike :put)
    - repeatable (unlike :put[!])
    - strip some leading and trailing whitespace in charwise mode

    Valid modes: 'c', 'v', 'l', 'V' (see :help nvim_put). '' is also supported as long as it
    resolves to one of the previous modes. Blockwise not supported
    
    If before is true, paste before (like p/:put!)

    If cursor is nil, then we use the default and inconsisent vim-like following behavior
        - in particular, when mode='c', where the cursor ends up will depend in part on whether the
        text to be put spans more than one line (if not more than one line, the cursor will always
        move to the end of the put text)
    If cursor is 0, the cursor will remain on the same character as it starts on
    If cursor is 1, it moves to the first character of the pasted text
    If cursor is -1, it moves to the last character of the pasted text

    Only designed for normal mode! Use builtin p for visual/terminal/etc
--]]
commands.put = commands.repeatable(function(mode, before, cursor)
    local count = vim.v.count1
    local register = vim.fn.getreg(vim.v.register, 1, true)
    local charwise = false
    local space = "" -- set to " " if we end up stripping whitespace

    if #register == 0 then
        return
    end

    if mode == "" then
        mode = vim.fn.getregtype(register)
    end

    if mode == "v" or mode == "c" then
        charwise = true
        --[[ Strip white space fron start of first line and end of last line.
             (These may be the same line.)
             Keep track of whether any white space was actually stripped, since if count>1 we
             will need to add some back in later
        --]]
        local stripped = register[1]:match("^%s+(.*)")
        if stripped then
            space = " "
        else
            stripped = register[1]
        end
        register[1] = stripped

        stripped = register[#register]:match("(.-)%s+$")
        if stripped then
            space = " "
        else
            stripped = register[#register]
        end
        register[#register] = stripped
    elseif mode ~= 'V' and mode ~= 'l' then
        vim.api.nvim_err_writeln("keyfactor put: mode not supported")
        return
    end

    local lines = register
    if count > 1 then
        lines = vim.deepcopy(register)
        local head = ''
        if charwise then
            -- Need to handle concatenation of first and last lines, possibly with whitespace
            head = space..register[1]
            register = vim.list_slice(register, 2)
        end
        for i = 2,count do
            if charwise then
                lines[#lines] = lines[#lines]..head
            end
            for _,line in ipairs(register) do
                table.insert(lines, line)
            end
        end
    end

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_put(lines, mode, not before, false)

    -- simplify node labels to have following statements less verbose
    if mode == 'v' then mode = 'c' end
    if mode == 'V' then mode = 'l' end

    if cursor then
        if cursor == 1 or
           (mode == 'c' and cursor == 0 and not before) then
            cursor_pos = vim.api.nvim_buf_get_mark(0, "[")
        elseif cursor == -1 or
               (mode == 'c' and cursor == 0 and before) then
            cursor_pos = vim.api.nvim_buf_get_mark(0, "]")
        elseif mode == 'l' and before then
            -- Note: cursor == 0
            cursor_pos = {cursor_pos[1] + #lines, cursor_pos[2]}
        end
        vim.api.nvim_win_set_cursor(0, cursor_pos)
        if cursor == 0 and mode == 'c' then
            utils.advance_cursor(0, not before)
        end
    end
end)

--[[
Like 'J', but as an operator
--]]
commands.join = commands.operator(function(motion_type)
    local top, _ = unpack(vim.api.nvim_buf_get_mark(0, '['))
    local bottom, _ = unpack(vim.api.nvim_buf_get_mark(0, ']'))
    local lines = vim.api.nvim_buf_get_lines(0, top-1, bottom-1, true)
    count = bottom - top + 1
    vim.cmd(tostring(top)..'join'..tostring(count))
end)

commands.swap_char = commands.repeatable(function(reverse)
    local count = vim.v.count1
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = unpack(vim.api.nvim_buf_get_lines(0, cursor[1]-1, cursor[1], true))
    local utf_index = vim.str_utfindex(line, cursor[2])
    local a,b,c,d = 0,0,0,0
    if reverse then
        if utf_index+1-count <= 0 then return end
        a = vim.str_byteindex(line, utf_index-count)
        b = vim.str_byteindex(line, utf_index-count+1)
        c = cursor[2] -- vim.str_byteindex(line, utf_index)
        d = vim.str_byteindex(line, utf_index+1)
        cursor[2] = a
    else
        if utf_index+1+count >= vim.str_utfindex(line) then return end
        a = cursor[2] -- vim.str_byteindex(line, utf_index)
        b = vim.str_byteindex(line, utf_index+1)
        c = vim.str_byteindex(line, utf_index+count)
        d = vim.str_byteindex(line, utf_index+count+1)
        cursor[2] = d - (b-a)
    end
    local replacement = string.sub(line,c+1,d)..string.sub(line,b+1,c)..string.sub(line,a+1,b)
    vim.api.nvim_buf_set_text(0, cursor[1]-1, a, cursor[1]-1, d, {replacement})
    vim.api.nvim_win_set_cursor(0, cursor)
end)

commands.seek = (function()
    local state = {}

    local go = function(reverse)
        if vim.tbl_isempty(state) then
            return
        elseif reverse then
            backward()
        else
            forward()
        end
    end

    local motion = function(command, forward, backward)
        do_command = as_function(command)

        return function()
            state = {forward=as_function(forward), backward=as_function(backward)}
            do_command()
        end
    end

    return {go=go, motion=motion}
end)()

commands.sneak_forward = commands.seek.motion('<Plug>Sneak_s', '<Plug>Sneak_;', '<Plug>Sneak_,')
commands.sneak_backward = commands.seek.motion('<Plug>Sneak_S', '<Plug>Sneak_,', '<Plug>Sneak_;')
commands.char_f = commands.seek.motion('<Plug>Sneak_f', '<Plug>Sneak_;', '<Plug>Sneak_,')
commands.char_F = commands.seek.motion('<Plug>Sneak_F', '<Plug>Sneak_,', '<Plug>Sneak_;')
commands.char_t = commands.seek.motion('<Plug>Sneak_t', '<Plug>Sneak_;', '<Plug>Sneak_,')
commands.char_T = commands.seek.motion('<Plug>Sneak_T', '<Plug>Sneak_,', '<Plug>Sneak_;')
commands.search_forward = commands.seek.motion('/', 'n', 'N')
commands.search_backward = commands.seek.motion('?', 'N', 'n')
commands.goto_WORD_forward = commands.seek.motion('g*', 'n', 'N')
commands.goto_WORD_backward = commands.seek.motion('g#', 'N', 'n')
commands.goto_word_forward = commands.seek.motion('*', 'n', 'N')
commands.goto_word_backward = commands.seek.motion('#', 'N', 'n')
commands.goto_older_change = commands.seek.motion('g;', 'g;', 'g,')
commands.goto_newer_change = commands.seek.motion('g,', 'g;', 'g,')

function commands.do_visual(mode)
    if mode == 'c' then
        mode = 'v'
    elseif mode == 'l' then
        mode = 'V'
    elseif mode == 'b' then
        mode = CTRL_V
    end

    current_mode, _ = vim.api.nvim_get_mode()
    if (current_mode:sub(1,1) == 'n') or
       (current_mode:sub(1,1) == 'v' and mode ~= 'v') or
       (current_mode:sub(1,1) == 'V' and mode ~= 'V') or
       (current_mode:sub(1,1) == CTRL_V and mode ~= CTRL_V) then
        vim.api.nvim_feedkeys(mode, 'ni')
    end
end

local _shift = {h='H', j='J', k='K', l='L'}
function commands.move_window(direction)
    current = vim.fn.winnr()
    target = vim.fn.winner(direction)
    if current == target then
        do_normal('<C-w>'.._shift[direction])
    else
        do_normal(target..'<C-w>x')
    end
end

-- TODO commands.shift_selection ??? (swap char for visual mode. probably would never be used)

--[[
This swap operator is overly complicated and doesn't work all that well, but it was a cute idea.

-- TODO: skip ahead using count
-- TODO: make indenting work?
-- TODO: preserve extmarks?
commands.swap = function(reverse)
    -- The operator needs to repeat itself, and uses this flag to keep track of whether it is
    -- already active
    local operator_active = false
    local count = 0
    local cursor = {} -- initial cursor position
    local source_start = {} -- position of the start of the first text block
    local source_end = {} -- position of the end of the first text block

    local fail = function(message)
        vim.api.nvim_win_set_cursor(0, cursor)
        vim.api.nvim_echo({{"Swap failed: "..message}}, true, {})
    end

    local operator = commands.operator(function(motion_type)

        if motion_type == "block" then
            return fail("Blockwise motions not supported")
        end

        if not operator_active then
            -- This is the first pass through, we are getting the source block
            operator_active = true
            -- Get the bounds of the source block
            source_start = vim.api.nvim_buf_get_mark(0, "[")
            source_end = vim.api.nvim_buf_get_mark(0, "]")
            -- To infer the target block, move past the end of the source block and repeat the
            -- operator
            local next_start = {}
            if motion_type == "line" then
                if reverse then
                    if source_start[1] == 1 then
                        fail("Invalid swap pair (no line for target)")
                    else
                        next_start = {source_start[1]-1, 0}
                    end
                else
                    if source_end[1] == vim.api.nvim_buf_line_count(0) then
                        fail("Invalid swap pair (no line for target)")
                    else
                        next_start = {source_end[1]+1, 0}
                    end
                end
            else -- motion_type == "char"
                if reverse then
                    next_start = source_start
                else
                    next_start = source_end
                end
                next_start = utils.get_next_position(0, next_start, reverse)
            end
            vim.api.nvim_win_set_cursor(0, next_start)

            vim.api.nvim_feedkeys(".", "ni", false) -- repeat operator
        else
            -- This is the second pass through, we are getting the target block and doing the swap
            operator_active = false
            target_start = vim.api.nvim_buf_get_mark(0, "[")
            target_end = vim.api.nvim_buf_get_mark(0, "]")

            --vim.api.nvim_echo({{vim.inspect(source_start)..vim.inspect(target_start)}}, true, {})
            
            -- For simplicity, we arrange that source comes before target in buffer
            if reverse then
                target_start, source_start = source_start, target_start
                target_end, source_end = source_end, target_end
            end

            if (not utils.buffer_less(source_start, target_start)) or
               (not utils.buffer_less(source_end, target_end)) then
                return fail("Invalid swap pair (source doesn't precede target)")
            end

            if not utils.buffer_less(source_end, target_start) then
                -- Overlapping source and target:
                -- Leave the overlap in place and swap outside of the overlapping portion
                local tmp = utils.get_next_position(0, source_end)
                source_end = utils.get_next_position(0, target_start, true)
                target_start = tmp
            end

            local target_lines = vim.api.nvim_buf_get_lines(0, target_start[1]-1, target_end[1], true)
            local source_lines = vim.api.nvim_buf_get_lines(0, source_start[1]-1, source_end[1], true)

            -- Set cursor before swapping the text, because swapping might change positioning
            if reverse then
                vim.api.nvim_win_set_cursor(0, source_start)
            else
                vim.api.nvim_win_set_cursor(0, target_start)
            end

            if motion_type == "line" then
                vim.api.nvim_buf_set_lines(0, source_start[1]-1, source_end[1], true, target_lines)
                vim.api.nvim_buf_set_lines(0, target_start[1]-1, target_end[1], true, source_lines)
                vim.cmd([[normal! ] ].."^") -- fix cursor column
            else -- motion_type == "char"
                local lens, lent = #source_lines, #target_lines

                if lens == 1 then
                    source_lines[1] = string.sub(source_lines[1], source_start[2]+1, source_end[2]+1)
                else
                    source_lines[1] = string.sub(source_lines[1], source_start[2]+1)
                    source_lines[lens] = string.sub(source_lines[lent], 1, source_end[2]+1)
                end

                if lent == 1 then
                    target_lines[1] = string.sub(target_lines[1], target_start[2]+1, target_end[2]+1)
                else
                    target_lines[1] = string.sub(target_lines[1], target_start[2]+1)
                    target_lines[lent] = string.sub(target_lines[lent], 1, target_end[2]+1)
                end

                vim.api.nvim_buf_set_text(0, target_start[1]-1, target_start[2], 
                                             target_end[1]-1, target_end[2]+1, source_lines)
                vim.api.nvim_buf_set_text(0, source_start[1]-1, source_start[2],
                                             source_end[1]-1, source_end[2]+1, target_lines)
            end
        end
    end)

    return function()
        count = vim.v.count
        cursor = vim.api.nvim_win_get_cursor(0)
        operator()
    end
end
]]

return commands
