-- TODO figure out a way to override the thing shown by showcmd
-- TODO appropriately handle local mappings (e.g. buffer-local mappings, but possibly also
-- window/tabpage-local)

local module = {}

local utils = require('keyfactor.utils')
local Trie = require('keyfactor.trie')
local active_mappings = Trie:new()

local OPTIONS = {'remap', 'silent', 'expr', 'wait'}
local MODES = {"c", "i", "n", "o", "s", "t", "x"}
module.defaults = {
    mode={'n'},
    remap=false,
    silent=true,
    expr=false,
    wait=false,
}

local function is_action(object)
    return type(object) == "string" or utils.is_callable(object)
end

local callables = {}

function module._callable(id)
    callables[id]()
end

local function get_rhs(raw)
    if type(raw) == 'string' then
        return raw
    end
    if not utils.is_callable(raw) then
        error("Actions must be strings or callable")
    end
    table.insert(callables, raw)
    return (":lua require('keyfactor')._callable(%u)<CR>"):format(#callables)
end

--[[
External map table format:

keypress = "keypress"|keys={"key1", "key2", ...}
action = "action"|callable

map_table = {
    (keypress action?)
    {map_table}*
    [mode="modestr"]?
    [silent=...]?
    [remap=...]?
}
--]]

function module.parse(map_table)
    local result = Trie:new()

    local function recurse(map_table, context)
        -- First, build the new context(s)
        local new_contexts = {}

        -- Overwrite the mode in the new context, if necessary
        if map_table.mode ~= nil then
            local mode_str = map_table.mode
            local mode = {}
            if type(mode_str) == 'string' then
                for i=1,#mode_str do
                    local m = mode_str:sub(i,i)
                    if vim.tbl_contains(MODES, m) then
                        table.insert(mode, m)
                    else
                        error("Unrecognized mode "..m.." for prefix "..context.prefix)
                    end
                end
                context.mode = mode
            else
                error("Mode is not a string for prefix "..context.prefix)
            end
        end

        -- Overwrite remaining options in new context, if necessary
        for _, option in ipairs(OPTIONS) do
            if map_table[option] ~= nil then
                context[option] = map_table[option]
            end
        end

        -- Get extension(s) of prefix
        local keys = map_table.keys
        local index = 1 -- keep track of whether we consumed an entry of map_table
        if not keys and type(map_table[1]) == 'string' then
            keys = {map_table[1]}
            index = 2
        end

        -- If there is nothing to do, quit with an error
        if #map_table < index then
            error("No mapping specified for prefix "..context.prefix)
        end

        -- Combine everything into new contexts
        if keys then
            for _, sequence in ipairs(keys) do
                local c = vim.deepcopy(context)
                c.prefix = c.prefix..sequence
                table.insert(new_contexts, c)
            end
        else
            table.insert(new_contexts, context)
        end

        -- Process the action, if there is any
        if keys then
            local action = nil
            if map_table.action ~= nil then
                action = map_table.action
            elseif is_action(map_table[index]) then
                action = map_table[index]
                index = index + 1
            end
            if action ~= nil then
                for _, c in ipairs(new_contexts) do
                    local keycodes = utils.string.split_keycodes(c.prefix)
                    for _, m in ipairs(c.mode) do
                        -- Store it in the result trie so we can apply it later
                        local trie = result:get({m}):get(keycodes)
                        local keymap_opts = {
                            nowait = not c.wait,
                            noremap = not c.remap,
                            silent = c.silent,
                            expr = c.expr,
                        }
                        local rhs = get_rhs(action)
                        if rhs:lower():sub(1, #'<plug>') == '<plug>' then
                            keymap_opts.noremap = false
                        end
                        trie.value = {rhs=rhs, opts=keymap_opts}
                    end
                end
            end
        end

        -- Finally, proceed recursively
        for i=index,#map_table do
            if type(map_table[i]) ~= 'table' then
                if is_action(map_table[i]) then
                    error("Wrong location to specify action for prefix"..context.prefix)
                else
                    vim.api.nvim_err_writeln(vim.inspect({i, map_table, context}))
                    error("Unrecognized map table entry for "..context.prefix)
                end
            else
                for _, context in pairs(new_contexts) do
                    recurse(map_table[i], vim.deepcopy(context))
                end
            end
        end
    end

    local context = vim.deepcopy(module.defaults)
    context.prefix = ''
    recurse(map_table, context)

    return result
end

function module.apply(map_table)
    local map_trie = module.parse(map_table)

    local function has_value(trie) return (trie.value ~= nil) end
    for prefix, new_map in map_trie:filter(has_value) do
        mode = prefix[1]
        local trie = active_mappings:get(mode)
        local lhs = ''
        for i=2,(#prefix-1) do
            lhs = lhs..prefix[i]
            trie = trie:get(prefix[i])
            if not has_value(trie) then
                trie.value = {rhs='<NOP>', opts={noremap=true, silent=true}}
                vim.api.nvim_set_keymap(mode, lhs, trie.value.rhs, trie.value.opts)
            end
        end
        lhs = lhs..prefix[#prefix]
        trie:get(prefix[#prefix]).value = new_map.value
        vim.api.nvim_set_keymap(mode, lhs, new_map.value.rhs, new_map.value.opts)
    end
end

function module.initialize(keyboard)
    local map_table = require("keyfactor.mappings").get_mappings(keyboard)
    module.apply(map_table)
end

return module
