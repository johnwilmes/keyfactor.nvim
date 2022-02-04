local module = {}

local utils = require("keyfactor.utils")
local commands = require("keyfactor.commands")
local telescope = require("telescope.builtin")

local function normal(cmd, remap, keepjumps)
    remap = (remap and ' ') or '! '
    keepjumps = (keepjumps and 'keepjumps ') or ''
    return '<Cmd>'..keepjumps..'normal'..remap..cmd..'<CR>'
end


-- TODO fix all the modes
function module.get_mappings(keyboard)
    local k = vim.tbl_map(function(x) return keyboard.get(x, {}) end, keyboard.keys)
    local shift = vim.tbl_map(function(x) return keyboard.get(x, {S=true}) end, keyboard.keys)
    local ctrl = vim.tbl_map(function(x) return keyboard.get(x, {C=true}) end, keyboard.keys)
    local alt = vim.tbl_map(function(x) return keyboard.get(x, {A=true}) end, keyboard.keys)
    local super = vim.tbl_map(function(x) return keyboard.get(x, {D=true}) end, keyboard.keys)
    local shift_ctrl = vim.tbl_map(function(x) return keyboard.get(x, {S=true, C=true}) end, keyboard.keys)
    local shift_alt = vim.tbl_map(function(x) return keyboard.get(x, {S=true, A=true}) end, keyboard.keys)
    local shift_super = vim.tbl_map(function(x) return keyboard.get(x, {S=true, D=true}) end, keyboard.keys)

    local mappings = {
        ----------------
        -- NAVIGATION --
        ----------------

        {mode="nosx", {
            {k.left, '<Left>'},
            {k.wrap..k.left, function() utils.advance_cursor(0, true) end},
            {k.right, '<Right>'},
            {k.wrap..k.right, function() utils.advance_cursor(0, false) end},
            -- go until whitespace
            {shift.left, 'B'},
            {shift.right, 'E'},
            
            {k.up, function() commands.fancy_vert(true) end},
            {k.wrap..k.up, 'gk'},
            {k.down, commands.fancy_vert},
            {k.wrap..k.down, 'gj'},
            -- doesn't quite rhyme here, but feels worse elsewhere
            {shift.up, 'H'},
            {shift.down, 'L'},

            {k.home, '^'},
            {k.wrap..k.home, 'g^'},
            {shift.home, '0'},
            {k.wrap..shift.home, 'g0'},
            {k.end_, 'g_'},
            {k.wrap..k.end_, 'g$'}, -- TODO screenwise version of g_ doesn't seem to exist
            {shift.end_, '$'},
            {k.wrap..shift.end_, 'g$'},
        }},
        {mode="i", {
            {k.left, '<C-g>U<Left>'},
            {k.right, '<C-g>U<Right>'},
            {k.up, normal('gk')},
            {k.down, normal('gj')},
            {shift.left, normal('B')},
            {shift.right, normal('E')},
            {shift.up, normal('H')},
            {shift.down, normal('L')},
            {k.home, normal('^')},
            {k.end_, normal('g_')},
            {shift.home, normal('0')},
            {shift.end_, normal('$')},
        }},
        
        {mode="ct", {
            {k.left, '<Left>'},
            {k.right, '<Right>'},
            {k.up, '<Up>'},
            {k.down, '<Down>'},

            {shift.left, '<S-Left>'},
            {shift.right, '<S-Right>'},
            {shift.up, '<S-Up>'},
            {shift.down, '<S-Down>'},

            -- Note: modifiers unmapped when mode=ct
            {k.home, '<Home>'},
            {k.end_, '<End>'},

            -- Note: shift unmapped when mode=ct
            {k.page_up, '<PageUp>'},
            {k.page_down, '<PageDown>'},
        }},

        {mode="citnosx", {
            -- Move cursor to window
            {ctrl.left, '<C-\\><C-n><C-w>h'},
            {ctrl.right, '<C-\\><C-n><C-w>l'},
            {ctrl.up, '<C-\\><C-n><C-w>k'},
            {ctrl.down, '<C-\\><C-n><C-w>j'},
            -- Split new window
            {alt.left, '<C-\\><C-n>:vertical leftabove split<CR>'},
            {alt.right, '<C-\\><C-n>:vertical rightbelow split<CR>'},
            {alt.up, '<C-\\><C-n>:leftabove split<CR>'},
            {alt.down, '<C-\\><C-n>:rightbelow split<CR>'},
            -- Move windows, and if it is already at the end make it large
            {super.left, function() commands.move_window('h') end},
            {super.up, function() commands.move_window('k') end},
            {super.down, function() commands.move_window('j') end},
            {super.right, function() commands.move_window('l') end},

            -- Move to next/prev tab
            {ctrl.page_up, '<C-\\><C-n>:-tabnext<CR>'},
            {ctrl.page_down, '<C-\\><C-n>:+tabnext<CR>'},
            -- Create new tab left/right
            {alt.page_up, '<C-\\><C-n>:-tab split<CR>'},
            {alt.page_down, '<C-\\><C-n>:tab split<CR>'},
            -- Swap tabs left/right
            {super.page_up, '<C-\\><C-n>:-tabmove<CR>'},
            {super.page_down, '<C-\\><C-n>:+tabmove<CR>'},
        }},

        -- Buffers
        {mode='n', {
            {ctrl.home, ':bp<CR>'},
            {ctrl.end_, ':bn<CR>'},
            {alt.home, '<NOP>'}, -- TODO modified buffer with lower index
            {alt.end_, ':sbm<CR>'},
        }},

        -- Open files
        {mode='n', {
            {k.open, ':enew<CR>'},
            -- telescope git_files TODO
            -- telescope live_grep
            -- telescope oldfiles
            -- file browser
        }},
        
        -- Exit
        {mode='n', {
            {k.exit, ':bw<CR>'},
        }},
        {mode='citnosx', {
            {shift.exit, '<C-\\><C-n><C-w>q'},
            {ctrl.exit, '<C-\\><C-n>:tabclose<CR>'},
            -- {alt.nav_exit, TODO :q! but with "are you sure" prompt}
            -- {super.nav_exit, TODO :qall! but with "are you sure" prompt, and also the option to do
            -- :cquit instead
        }},

        -- Git TODO

        -------------
        -- MOTIONS --
        -------------
        
        -- scroll
        -- TODO input mode
        {mode="nosx", {
            {k.scroll, normal('<C-f>M', false, true)},
            {shift.scroll, normal('<C-b>M', false, true)},
            {k.linewise..k.scroll, normal('<C-e>')},
            {k.linewise..shift.scroll, normal('<C-y>')},
            {ctrl.scroll, normal('gg')},
            {shift_ctrl.scroll, commands.go_to_neg_line},
            {alt.scroll, commands.fancy_percent},
            {shift_alt.scroll, function() commands.fancy_percent(true) end},
        }},

        -- word/WORD movement
        {mode="nosx", {
            {k.word, 'w'},
            {shift.word, 'b'},
            {ctrl.word, 'W'},
            {shift_ctrl.word, 'B'},
            {alt.word, 'e'},
            {shift_alt.word, 'ge'},
            {super.word, 'E'},
            {shift_super.word, 'gE'},
        }},

        -- Character movement
        {mode="nosx", {
            {k.char, commands.char_t}, -- TODO test
            {shift.char, commands.char_T},
            {ctrl.char, commands.char_f},
            {shift_ctrl.char, commands.char_F},
        }},

        -- Bigram
        {mode="nosx", {
            {k.bigram, commands.sneak_forward},
            {shift.bigram, commands.sneak_backward},
        }},

        -- Search
        {mode="nosx", {
            {k.search, commands.search_forward},
            {shift.search, commands.search_backward},
            {ctrl.search, '<Cmd>noh<CR>', mode='citnosx'},
            {alt.search, telescope.current_buffer_fuzzy_find},
        }},

        -- Code movement
        -- TODO replace with e.g. nvim-treesitter-textsubjects
        {mode="nosx", {
            {k.code, '}'},
            {shift.code, '{'},
            {ctrl.code, ']['},
            {shift_ctrl.code, '[]'},
            {alt.code, '%'},
        }},


        -- Seek
        {mode="nosx", {
            {k.seek, commands.seek.go},
            {shift.seek, function() commands.seek.go(true) end},
        }},

        -- Jumps
        {mode="nosx", {
            {k.jumps, '<C-o>'}, -- jumplist navigation
            {shift.jumps, '<C-i>'},
            {ctrl.jumps, '<C-t>'}, -- tag navigation TODO fix
            {alt.jumps, normal('tag')},
            {super.jumps, '<C-]>'}, -- TODO should this be goto jumps?
        }},
        
        -- Quickfix/Location Lists
        -- {k.list, ...}
        
        -- Text objects
        -- {k.object, ...}


        -- Goto
        -- TODO check with k.charwise
        -- TODO consistent shift treatmenet
        -- TODO modes
        -- TODO double check it all
        {mode="nosx", {
            {k.goto..k.insert, "`^"},
            {k.linewise..k.goto..k.insert, "'^"},

            {k.goto..k.repeat_, "`]"}, -- TODO
            {k.linewise..k.goto..k.repeat_, "']"}, -- TODO
            {keys={shift.goto..k.repeat_,
                   shift.goto..shift.repeat_,
                   k.goto..shift.repeat_
                  }, "`["},
            {keys={k.linewise..shift.goto..k.repeat_,
                   k.linewise..shift.goto..shift.repeat_,
                   k.linewise..k.goto..shift.repeat_
                  }, "'["},

            {k.goto..k.mark, "]`"},
            {k.linewise..k.goto..k.mark, "]'"},
            {shift.goto..k.mark, "[`"},
            {k.linewise..shift.goto..k.mark, "['"},

            {k.goto..k.word, commands.goto_word_forward},
            {shift.goto..k.word, commands.goto_word_backward},
            {k.goto..ctrl.word, commands.goto_WORD_forward},
            {shift.goto..ctrl.word, commands.goto_WORD_forward}, -- TODO other shift possibilities

            -- Changelist
            {k.goto..k.undo, "`."},
            {k.linewise..k.goto..k.undo, "'."},
            {k.goto..k.change, commands.goto_older_change},
            {shift.goto..k.change, commands.goto_newer_change},
        }},

        -- Marks TODO
        -- {k.mark, ...}
        
        -------------
        -- ACTIONS --
        -------------
     
        -- Insert
        {mode='n', {
            {k.insert, 'a'},
            {shift.insert, 'i'},
            {ctrl.insert, 'A'},
            {shift_ctrl.insert, 'I'},
            {k.linewise, {
                {k.insert, 'o'},
                {shift.insert, 'O'},
                -- {ctrl.insert, TODO new line at bottom of current block?}
            }},
        }},

        -- Paste
        -- TODO visual mode
        -- TODO cursor movement...
        {mode='n', {
            {k.paste, 'p'},
            {shift.paste, 'P'},
            -- {ctrl.paste, do character-wise put at end of line},
            -- {shift_ctrl.paste, do character-wise put at beginning of line (after indent)},
            {k.linewise, {
                {k.paste, function() commands.put('l', false, 0) end},
                {shift.paste, function() commands.put('l', true, 0) end },
                {alt.paste, '<Plug>unimpairedBlankDown'},
                {shift_alt.paste, '<Plug>unimpairedBlankUp'},
            }},
            {k.charwise, {
                {k.paste, function() commands.put('c', false, 0) end},
                {shift.paste, function() commands.put('c', true, 0) end},
            }},
        }},

        -- Swap
        --[[
        {mode='n', {
            {k.swap, commands.swap_char},
            {shift.swap, function() commands.swap_char(reverse) end},
            {k.linewise, {
                {k.swap, '<Plug>(unimpaired-move-down)'},
                {shift.swap, '<Plug>(unimpaired-move-up)'},
            }}
        }},
        {mode='sx', {
            {k.swap, '<Plug>(unimpaired-move-selection-down)'},
            {shift.swap, '<Plug>(unimpaired-move-selection-up)'},
            {ctrl.swap, 'gv', mode='sx'}, -- swap with previous visual selection
        }},
        ]]

        -- Delete
        {mode='n', {
            {k.delete, 'd'},
            {ctrl.delete, 'D'},
            {shift_ctrl.delete, 'd^'},
            {k.linewise..k.delete, 'dd'},
            {k.charwise..k.delete, 'x'},
        }},
        {mode='sx', k.delete, 'd'},

        -- Change
        {mode='n', {
            {k.change, 'c'},
            {ctrl.change, 'C'},
            {shift_ctrl.change, 'c^'},
            {alt.change, 'r'},
            {k.linewise..k.change, 'cc'},
            {k.charwise..k.change, 's'},
        }},
        {mode='sx', k.change, 'c'},

        -- Yank
        {mode='n', {
            {k.yank, 'y'},
            {ctrl.yank, 'y$'},
            {shift_ctrl.yank, 'y^'},
            {k.linewise..k.yank, 'yy'},
            {k.charwise..k.yank, 'yl'},
        }},
        {mode='sx', k.yank, 'y'},

        -- Surround
        {mode='n', {
            {k.surround, '<Plug>Ysurround'},
            {k.linewise..k.surround, '<Plug>Yssurround'},
            {k.delete..k.surround, '<Plug>Dsurround'},
            {k.change..k.surround, '<Plug>Csurround'},
            {alt.surround, '<Plug>YSurround'},
            {k.change..alt.surround, '<Plug>YSurround'},
            {k.linewise..alt.surround, '<Plug>YSsurround'},
        }},
        {mode='sx', {
            {k.surround, '<Plug>VSurround'},
        }},

        -- Indent
        {mode='nsx', {
            {k.indent, '>'},
            {shift.indent, '<'},
            {alt.indent, '='},
        }},
        {mode='n', {
            {k.linewise..k.indent, '>>'},
            {k.linewise..shift.indent, '<<'},
            {k.linewise..alt.indent, '=='},
        }},

        -- Comment TODO
        --[[ {mode='nsx', {
            {k.comment, comment},
            {shift.comment, uncomment},
        }},]]

        -- Caps
        -- TODO k.charwise
        {mode='nsx', {
            {k.capitalize, 'gU'},
            {shift.capitalize, 'gu'},
            -- {ctrl.capitalize, snake case}, TODO
            -- {alt.capitalize, camel case}, TODO
        }},
        {mode='n', {
            {k.linewise..k.capitalize, 'gUgU'},
            {k.linewise..shift.capitalize, 'gugu'},
            -- {k.linewise..ctrl.capitalize, ...},
        }},

        -- Join
        {mode='nsx', {
            {k.join, commands.join},
            {shift.join, 'gq'},
        }},
        {mode='n', {
            {k.linewise..k.join, 'J'},
            {k.linewise..shift.join, 'gqgq'},
        }},

        -- Lint TODO

        -------------------
        -- MISCELLANEOUS --
        -------------------

        -- Visual
        -- k.linewise = k.visual
        -- k.charwise = shift(k.visual)
        -- TODO blockwise
        {mode='n', {
            {k.charwise..k.charwise, 'v'},
            {k.linewise..k.linewise, 'V'},
        }},
        {mode='osx', {
            {k.charwise, function() commands.do_visual('c') end},
            {k.linewise, function() commands.do_visual('l') end},
        }},

        -- Repeat
        {k.repeat_, '.'},
        {silent=false, {
            {ctrl.repeat_, 'q'}, -- TODO use default register;
            -- but if register set, then use it
            -- in either case, update default register for @
            {alt.repeat_, '@'}, -- TODO, except use default register, or ordinary set register
        }},
        -- {shift.repeat_, ':@:<CR>', silent=false}, -- TODO

        -- Undo
        {mode='n', {
            {k.undo, 'u'},
            {shift.undo, '<C-r>'},
        }},

        -- Register
        {mode='nsx', {
            {k.register, '"'},
        }},

        -- Command
        {k.command, ':', mode='n', silent=false},
        -- {alt.command, TODO do vim standard mapping}, 

        -- Fold
        -- TODO set foldmethod to indent?
        --{k.operator..k.fold, 'zf'}, -- create a fold when foldmethod is manual/marker
        --{k.linewise..k.operator..k.fold, 'zF'},
        --
        --[[
        {k.fold, {
            {k.left, 'zc'},
            {shift.left, 'zx'},
            {ctrl.left, 'zC'},
            {k.right, 'zo'},
            {shift.right, 'zv'},
            {shift.right, 'zO'},
            {k.up, 'zm'},
            {shift.up, 'zM'},
            {ctrl.up, 'zX'},
            {k.down, 'zr'},
            {shift.down, 'zR'},
            {ctrl.down, 'zX'},
        }},
        {shift.fold, 'zn'}
        {ctrl.fold, 'zx'}
        --]]


        -- Spell
        --[[
        {mode='n', {
            {k.spell, ':setlocal spell<CR>'},
            {shift.spell, ':setlocal nospell<CR>'},
            {ctrl.spell, telescope.spell_suggest}, -- suggestions?
            -- {alt.spell, '<NOP>', mode='n'}, -- mark words as good/bad/rare, and unmark. ?
        }},
        --]]

        -- Select
        --[[
        {k.select_, {
            {k.select_, telescope.builtin},
            {k.command, telescope.command_history},
            {k.register, telescope.registers},
            {k.mark, telescope.marks},
            {k.jumps, telescope.jumplist},
            {k.list, telescope.quickfix},
            {ctrl.list, telescope.loclist},
            {k.repeat_, telescope.resume},
            {k.search, telescope.search_history},
            --{k.spell, telescope.spell_suggest},
            {k.code, telescope.treesitter},
            {k.buffer, telescope.buffers},

            -- {k.word, hop word},
            -- {k.WORD, hop WORD},
            -- {k.bigram, hop bigram},
            -- {k.char, hop char},
        }},
        --]]

        -- Fix
        --[[
        {k.fix, {

            -- Open register (or yankring?) telescope, and replace previous put with selected register
            -- ( also fix changelist/etc. )
            --{k.put, }
        }},
        ]]
    }
    return mappings
end

-- TODO set telescope picker window keymaps
return module
