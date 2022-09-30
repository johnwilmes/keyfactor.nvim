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
    on.alt.let{orientation__boundary="inner"}._else.let{orientation__boundary="outer"}
    on.control.let{linewise=true}._else.let{linewise=false},
}
local point_operator = {operator,
    on.shift.let{orientation__side="left"}._else.extend{orientation__side="right"}
},

-- TODO multiple should *toggle* register shape between larger and smaller?
--      e.g. when we have wring:watch{something, redo:set{something:with{register}}}:with{register}
--          we want redo to be able to change register shape (?), but should default to what was
--          set from register
local register = {on.choose(--[[TODO prompt for register]]),
    on.multiple.toggle{register__shape={"larger", "smaller"}},
}
--[[ or, maybe:
local register = function(...)
    return {on.choose.prompt.register(...)._else(...),
    on.multiple.extend{register={shape="large"}}}
end
]]

local selection = go.select_textobject:with{
    reversible,
    on.control.let{augment=true},
    on.choose.let{choose="auto"},
    on.alt.let{partial=true},
    on.multiple{
        -- control(augment): whether we subselect, or just select from everything
        on.shift.let{multiple="split"}._else.let{multiple="select"}
    },
}
local seek = go.redo:with_namespace()
local seekable = seek:watch{selection}

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

--[[ TODO here, we bind default params into wring.

later, we use this wring object (with defaults bound in) for our :set and :go_set bindings
finally, we use this wring object to bind for execution

but what if we used separate wring objects, with separately bound defaults, for :set and :exec?

possible solutions:
    -ignore bound defaults for set and go_set
]]


local wring_or_yank = go.wring:with{
    fallback={go{
            go.yank, 
            go.wring:set{
                go.replace,
                redo:set{go{go.yank, go.replace}:with{operator, register}},
            },
        }:with{operator, register},
    },
}

local wring_now = go.wring:with{
    fallback={go{
            go.yank
            go.wring:set{
                go.replace,
                redo:set{go.yank:with{operator, register}, go.replace:with{operator, register}},
            },
            go.wring,
        }:with{register}
    },
}

local scroll = go.scroll:with{reversible, on.alt.let{partial=true}, on.control.let{linewise=true}}
local scroll = go.scroll:with{reversible, on.alt{partial=true}, on.control{linewise=true}}

local passthrough = {
    -- TODO
}

local bindings = {}
bindings.base = {
    on.insert{
        on{edit=false}.go{
            tab=go.complete_next:with{reversible},
            enter=go.complete_default,
        }
        scroll={on.control{scroll}, on.alt{scroll}},
    },
    on.normal{
        -- TODO... actions.set
        go=go.set.layer{motion=true}:with{passthrough},
        do=go.set.layer{action=true}:with{passthrough},
        settings=go.set.layer{settings=true:with{passthrough},
        choose=go.set.mod{choose=true}:with{passthrough},
        multiple=go.set.mod{multiple=true}:with{passthrough},

        scroll=scroll,

        line=selection:with{textobject=textobjects.line},
        word=selection:with{textobject=textobjects.word},
        search=prompt.search{seekable}, -- TODO instead prompt.search?
        --[[ prompt.search(seekable) ]]
        char=prompt.char{seekable},
        -- individual ranges from current mark:
        mark=selection:with{textobject=textobjects.mark},
        seek=go(seek),


        delete=go.delete:with{operator, register},
        insert={go.insert:with{point_operator},
            -- TODO probably should be wringable-ish
            -- TODO is reinsert actually different from paste with register.name="insert"?
            redo:set{go.reinsert, point_operator},
        },
        --[[ binding from redo:set gets called everytime we wring the paste, with updated
                register params, so redoing by default does what the paste ended up as

             point_operator (and register) bindings are made available to redo and to paste, but
             not to wring.
             (although the actual wring action will again have register bindings available)
        ]]
        paste={
            wring:watch{
                go.paste, redo:set{go.paste, point_operator, register},
            }:with{
                point_operator, register,
            }
        },
        wring=wring:with{increment="depth", reversible, register}
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
        tab=on.control{
            wring_now:with{increment="align",
                on.alt{
                    on.shift.toggle{
                        register__align={"bottom", "focus", "top"}
                    }._else.toggle{
                        register__align={"top", "focus", "bottom"}
                    }
                }._else{reversible}
            },
        }._else{
            go.rotate_focus:with{
                on.alt{
                    on.shift.toggle{
                        align={"bottom", "alternate", "top"}
                    }._else.toggle{
                        align={"top", "alternate", "bottom"}
                    }
                }._else{reversible},
            },
        },
    },
}

bindings.motions = {
    on.normal{
        do=go.round_selection:with{
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
        surround=prompt.surround(seekable), -- TODO shim to transform surround prompt to textobject?
        comment=seekable:with{textobject=textobjects.comment},
        indent=seekable:with{textobject=textobjects.indent},
        mark={--[[TODO like base-layer mark, but prompt for mark instead of using default]]}
        -- TODO tab = go to focus
        -- TODO enter = "add new range to selection, immediately following focus, constructed the
        --              same way as the focus" ???!!
    },
}

bindings.actions = {
    on.normal{
        char=go.capitalize:with{reversible, operator},
        line=go.join:with{reversible, operator},
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
