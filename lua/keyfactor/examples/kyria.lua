local keys = {
    seek="_",
    go="<Space>", motion="<Space>", -- both labels describe the key <Space>
    left={"<Left>", "<kLeft>"}, --both keys are described by the label left


}

local mods = {"choose", "multiple"}
local layers = {"base", "motions", "actions", "settings"}
local orientation = {boundary="inner", side="right"}

--[[
For each active layers, from highest to lowest index:
    Resolve bindings
    If action is not nil (and if "continue" flag is not set?) then break

Binding resolution:
        First, recursively apply bindings indexed from 1 to #layer
        Then, if any table keys match any of the names of the keypress, apply them (in an unspecified order)

base={
    on.insert{
        tab={bindings}
    },
    on.normal{
        tab={bindings}
    }

    left={bindings, on.insert
}

--]]


local reversible = on.shift.let{reverse=true}
local operator = {
    on.alt.extend{orientation={boundary="inner"}},
    on.control.let{linewise=true}
}
local point_operator = {operator, on.shift.extend{orientation={side="left"}}}
local register = {on.choose(--[[TODO prompt for register]]), on.multiple.extend{register={shape="larger"}}}

local selection = {
    only.select_textobject,
    reversible,
    on.control.let{augment=true},
    on.choose.let{choose="auto"},
    on.multiple{
        on.alt.let{multiple="split"}._else.let{multiple="select"}
    }._else{
        on.alt.let{partial=true},
    },
}

local reset = {let{reverse=false,
    partial=false,
    multiple=false,
    choose=false,
    augment=false,
    orientation={},
    linewise=false,
}}

local seek = actions.redo:new()
local seekable = {selection, seek:capture{reset}}


-- if selection is currently from a register (captured for "wringing"), then replace via "wringing"
-- otherwise, yank selection (and capture for "wringing")
-- wring(stuff that happens if we actually wring)._else(stuff that happens if we don't wring)
local yank_or_replace = only.wring._else{only.yank, operator, actions.wring:capture(only.replace)}

local scroll = {only.scroll, reversible, on.alt.let{partial=true}, on.control.let{linewise=true}}

local bindings = {}
bindings.base = {
    on.insert{
        on[{edit=false}].bind{
            tab={only.complete_next, reversible},
            enter={only.complete_default},
        }
        scroll={on.control{scroll}, on.alt{scroll}},
    },
    on.normal{
        -- TODO... actions.set
        go={only.set.layer{motion=true}, passthrough},
        do={only.set.layer{action=true}, passthrough},
        settings={only.set.layer{settings=true}, passthrough},
        choose={only.set.mod{choose=true}, passthrough},
        multiple={only.set.mod{multiple=true}, passthrough},

        scroll=scroll,

        line={selection, let{textobject=textobjects.line}},
        word={selection, let{textobject=textobjects.word}},
        search={seekable, textobjects.search:prompt()}, -- TODO instead prompt.search?
        char={seekable, textobjects.char:prompt()},
        mark={selection, --[[ individual ranges from current mark]]},
        seek={only(seek), selection},

        delete={only.delete, operator, register},
        insert={only.reinsert,
            point_operator,
            actions.redo:capture{reset, point_operator},
            actions.insert:prompt()},
        paste={only.paste,
            point_operator,
            actions.wring:capture(), -- TODO insteat capture.wring?
            actions.redo:capture{reset, point_operator}, -- TODO instead capture.redo{reset, operator}?
            register},
        wring={yank_or_replace, reversible, register},
        -- TODO choose for undo
        undo={only.undo, reversible},
        enter={only.redo, register},

        surround={},
        comment={},
        indent={},

        -- TODO tab rotates focus of selection
        --      shift goes in reverse direction
        --      alt moves to top/bottom
        --      control rotates *contents* of selection, and if selection is from register it does
        --          this by changing alignment of selection (via wring?)
        tab={only.rotate_selection, reversible}
    },
}

bindings.motion = {
    on.normal{
        do={only.round_selection,
            on.control{
                -- round to inner/outer/left/right
                on.shift{
                    on.alt.let{boundary="inner"}._else.let{side="left"}
                }._else{
                    on.alt.let{side="right"}._else.let{boundary="outer"}
                },
            }._else{
                -- round to a specific position
                on.shift.let{side="left"}._else.let{side="right"},
                on.alt.let{boundary="inner"}._else.let{boundary="outer"},
            }
        },
        surround={seekable, textobjects.surround:prompt()},
        comment={seekable, let{textobject=textobjects.comment}},
        indent={seekable, let{textobject=textobjects.indent}},
        mark={--[[TODO like base-layer mark, but prompt for mark instead of using default]]}
    },
}

bindings.action = {
    on.normal{
        char={only.capitalize, reversible, operator},
        line={only.join, reversible, operator},
        mark={--[[set/add current selection to given mark]]},
    },
}

-- TODO change orientation... oneshot vs lock... until non-motion action?
-- TODO change highlighting... until next highlighting action?
bindings.settings = {
    on.normal{
        mark={--[[TODO prompt for mark, and set that one as the default]]},
    }
}
