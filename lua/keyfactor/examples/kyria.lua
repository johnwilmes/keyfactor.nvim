local keyboard = require("keyfactor.keyboard")
local actions = require("keyfactor.actions")
local textobjects = require("keyfactor.textobjects")

local layers = {'motion', 'action'}
--local mods = {'shift', 'control', 'alt', 'choose', 'multiple', 'focus'}
local mods = {'shift', 'control', 'alt', 'choose', 'multiple', 'outer', side=2}
-- TODO keys, mod remapper

keyboard.initialize({layers=layers, mods=mods, --[[...]]})

local shift = {shift=true} -- usually reverse
local control = {control=true} -- augment, or outer/inner
local alt = {alt=true} -- partial/exterior, or linewise
local choose = {choose=true}
local multiple = {multiple=true}

local selection_map = {
    {
        action=actions.select_next,
        params={stretch=true,
                outer=params.mod('outer'),
                side=params.mod('side'),
                reverse=params.mod('shift'),
                augment=params.mod('control')}
    }, {
        mods=choose,
        action=actions.select_choice,
    }, {
        mods=multiple, -- TODO check that other params make sense
        action=actions.select_all,
    }
}

local alt_exterior =  {params={exterior=params.mod('alt')}}
local alt_partial =  {params={partial=params.mod('alt')}}

local function get_side()
    local mods = keyboard.get_mods()
    return (mods.shift and 1) or 2
end

local function xor_outer()
    local mods = keyboard.get_mods()
    if mods.control then return (not mods.outer) end
    return mods.outer
end

local function xor_side()
    local mods = keyboard.get_mods()
    if mods.shift then return (3 - mods.side) end
    return mods.side
end

local action_map = {
    params={side=xor_side, outer=xor_outer, linewise=params.mod('alt')}
}


keyboard.map_layer('base', {
    --keyname={bindings...}
    choose={action=actions.oneshot_mod, params={choose=true, keep_mods='all'}},
    multiple={action=actions.oneshot_mod, params={multiple=true, keep_mods='all'}},
    focus={action=actions.lock_mod, params={inner=params.mod('control'), side=get_side}, 
            {mods=alt,
             action=actions.rotate_selection,
             params={reverse=params.mod('shift'), endpoint=params.mod('control')},
            }},
    go={action=actions.oneshot_layer, params={layer='motion', keep_mods='all'}},
    do={action=actions.oneshot_layer, params={layer='action', keep_mods='all'}},

    word={params={textobject=textobjects.word}, selection_map, alt_exterior},
    WORD={params={textobject=textobjects.WORD}, selection_map, alt_exterior},
    line={params={textobject=textobjects.line}, selection_map, alt_partial},
    char={params={textobject=textobjects.char}, selection_map, alt_exterior},
    search={params={textobject=textobjects.search}, selection_map, alt_exterior},
    block={params={textobject=textobjects.block}, selection_map, alt_partial},

    delete={action=actions.delete, action_map},
    insert={action=actions.insert, action_map},
    yank={action=actions.yank, action_map},
    put={action=actions.put, action_map},
    surround={action=actions.surround, action_map,
              {mods=shift, action=actions.delete_surround}},
    comment={action=actions.comment, action_map,
             {mods=shift, action=actions.uncomment}},
    indent={action=actions.indent, reverse=params.mod('shift')}, -- control and alt?

    undo={action=actions.undo, reverse=params.mod('shift')}, -- control and alt?
})

keyboard.map_layer('motion', {
    --line = select line by number
    surround={params={textobject=textobjects.surround}, selection_map, alt_partial},
    comment={params={textobject=textobjects.comment}, selection_map, alt_exterior},
})

