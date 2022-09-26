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
        First, recursively apply bindings indexed from 1 to #bindings
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
    go.select_textobject,
    reversible,
    on.control.let{augment=true},
    -- choose is based on view port, so this lets us select into viewport
    on.choose.let{choose="auto"},
    on.multiple{
        -- control(augment): whether we subselect, or just select from everything
        on.shift.let{multiple="split"}._else.let{multiple="select"}
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
local seekable = seek:go_set{selection}

-- TODO when is binding for capture actually needed?
--      - e.g. for redo: in principle we might want to have point/range operators that are both
--      redo-able with the same key, but with mods doing the same thing as at the captured
--      action...
-- would it be more useful to somehow specify stuff that gets hidden from capture?
--
--  instead: seek:capture{selection}
--      and prompt.search{seek:capture{selection}}
--
--  redo:capture -- saves binding but also evaluates and then executes resulting action
--  redo:set -- just saves the binding (and the params it is called with) without executing underlying action
--

--[[
If wring is not set for this selection/undo node then
    - yank the selection and set orientation boundary via operator mods
    - set this selection for wringing with the replace action
    - set redo to first yank and then replace with whatever the register ends up as
    after wringing
Otherwise wring
]]
local yank_or_replace = go(wring{
    default={go.yank, wring:set{go.replace}, operator,
             redo:set{
                 go.yank, then_go.replace, operator, wring:get_register(), register,
             },
    },
})


local scroll = {go.scroll, reversible, on.alt.let{partial=true}, on.control.let{linewise=true}}

local bindings = {}
bindings.base = {
    on.insert{
        on[{edit=false}].bind{
            tab={go.complete_next, reversible},
            enter={go.complete_default},
        }
        scroll={on.control{scroll}, on.alt{scroll}},
    },
    on.normal{
        -- TODO... actions.set
        go={go.set.layer{motion=true}, passthrough},
        do={go.set.layer{action=true}, passthrough},
        settings={go.set.layer{settings=true}, passthrough},
        choose={go.set.mod{choose=true}, passthrough},
        multiple={go.set.mod{multiple=true}, passthrough},

        scroll=scroll,

        line={selection, let{textobject=textobjects.line}},
        word={selection, let{textobject=textobjects.word}},
        search={seekable, textobjects.search:prompt()}, -- TODO instead prompt.search?
        char={seekable, textobjects.char:prompt()},
        mark={selection, --[[ individual ranges from current mark]]},
        seek=go(seek),


        delete={go.delete, operator, register},
        -- TODO fix insert below: can't call into insert action from `go`...
        insert={go.insert{ redo:set{go.reinsert, point_operator} }, point_operator},
        paste={wring:go_set{go.paste}, point_operator, register,
        -- this is a bit ugly: in principle, wring could be looking at some other action when we do
        -- redo, and then we would paste the wrong register.
        -- What we actually want is that redo does whatever the last "paste" register ended up as
        -- In practice, we set redo whenever we set wring, so this doesn't matter. But it would be
        -- nice to have a more elegant solution
            redo:set{go.paste, point_operator, wring:get_register(), register},
        },

        wring={yank_or_replace, let{increment="depth"}, reversible, register}
        -- TODO "choose" mod but for undo
        undo={go.undo, reversible},
        enter={go.redo},

        surround={},
        comment={},
        indent={},

        -- TODO tab rotates focus of selection
        --      shift goes in reverse direction
        --      alt moves to top/bottom
        --      control rotates *contents* of selection, and if selection is from register it does
        --          this by changing alignment of selection (via wring)
        tab={
            on.control{
                yank_or_replace, let{increment="align"}
                on.alt{--[[TODO cycle top/bottom/focus]]}._else{reversible},
            }._else{
                go.rotate_focus,
                on.alt{--[[TODO cycle top/bottom/former focus]]}._else{reversible},
            },
    },
}

bindings.motion = {
    on.normal{
        do={go.round_selection,
            on.control{
                -- round to inner/outer/left/right
                -- TODO should linewise rounding be possible?
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
        -- TODO tab = go to focus
        -- TODO enter = "add new range to selection, immediately following focus, constructed the
        --              same way as the focus" ???!!
    },
}

bindings.action = {
    on.normal{
        char={go.capitalize, reversible, operator},
        line={go.join, reversible, operator},
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
