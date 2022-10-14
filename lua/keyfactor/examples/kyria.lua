local go = require("keyfactor.action")

local bind, wring, redo, set, get, on, outer

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
    Execute actions
    If any returns truthy then break
(Additional default layer at index 0 comes from current mode)
(Note: can have default action that can be explicitly called if you want to skip to it from a
higher layer...)

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

local one_shot = set{lock=false}
local keep_orientation = one_shot.orientation{
    side=get.orientation.side,
    boundary=get.orientation.boundary,
}

local reversible = {reverse=on.shift}

local operator = {
    linewise=on.control,
    orientation__boundary=on.alt("inner"):_else("outer"),
}

local point_operator = {
    operator,
    orientation__side=on.shift("left"):_else("right"),
}

local get_shape = function(context)
    local reg = (context.register or {}).shape
    if reg then
        if reg=="smaller" then
            return "smaller"
        end
        return "larger"
    end
    local state = -- TODO get default/state shape
    if state=="smaller" then
        return "smaller"
    end
    return "larger"
end

local register = {
    register__name=on.choose(prompt.register),
    register__shape=on.multiple(toggle{"larger", "smaller", value=get_shape})
}

local selection = bind{
    go.select_textobject{
        reversible,
        augment=on.control,
        choose=on.choose,
        partial=on.alt,
        multiple=on.multiple(on.shift("split"):_else("select")),
        textobject=outer.textobject,
    }, keep_orientation,
}

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


local scroll = go.scroll{reversible, partial=on.alt, linewise=on.control}

local passthrough = {
    one_shot.mod{
        shift=on.shift,
        alt=on.alt,
        ctrl=on.ctrl,
        choose=on.choose,
        multiple=on.multiple,
    },
    one_shot.layer{
        motions=on{layer="motions"},
        actions=on{layer="actions"},
        settings=on{layer="settings"},
    },
    keep_orientation,
    one_shot.params{
        count=get.params.count,
    },
}

local bindings = {}
bindings.base = {
    on.insert{
        on{edit=false}:_then{
            -- TODO this stuff could be implemented instead with mode default layer
            tab=go.complete_next{reversible},
            enter=go.complete_default,
        }
        -- TODO might be nice to have non-printable scroll key (on combo?) so that we can do the
        -- same regardless of mode
        scroll={on.control(scroll), on.alt(scroll)},
    },
    on.normal{
        go={one_shot.layer{motions=true}, passthrough},
        do={one_shot.layer{actions=true}, passthrough},
        settings={one_shot.layer{settings=true}, passthrough},
        choose={one_shot.mods{choose=true}, passthrough},
        multiple={one_shot.mods{multiple=true}, passthrough},

        scroll=scroll,

        line=selection:with{textobject=textobjects.line},
        word=selection:with{textobject=textobjects.word},
        -- individual ranges from current mark:
        --mark=selection{textobject=textobjects.mark:with{name=get.local("default_mark")}},
        char=redo.set{selection,
            set{lock=true}.highlight{search=true},
            namespace="seek",
        }:with{textobject=textobjects.char}, 
        search=redo.set{selection,
            set{lock=true}.highlight{search=true},
            namespace="seek",
        }:with{textobject=textobjects.search}, 
        seek=redo{namespace="seek"},

        delete=go.delete{operator, register},
        insert=bind{
            go.insert,
            redo.set_only(go.paste{register__name="insert", outer})
        }:with{point_operator}
        paste=bind{
            wring.set(go.paste),
            redo.set_only(wring.set(go.paste):with{outer, register=wring.register})
        }:with{point_operator, register}

        wring=bind(
            on(wring.is_active):_then(
                wring{increment="depth", reversible, outer}
            ):_else(
                wring.set{on(wring.is_active):_then(go.replace):_else(go.yank)}:with{outer, operator}
            )):with{register}
        -- TODO "choose" mod but for undo
        undo=go.undo{reversible},
        enter=redo,

        surround={},
        comment={},
        indent={},

        tab=on.control(
            on(wring.is_active):_then(
                wring{increment="offset", reversible}
            ):_else(
                wring.set{on(wring.is_active):_then(go.replace):_else(go.yank)}:with{operator}
            )
        ):_else(go.rotate_focus{reversible, jump=on.alt}),
    },
}

bindings.motions = {
    on.normal{
        do={keep_orientation, go.round_selection{
            on.control(
                -- round to inner/outer/left/right
                -- TODO should linewise rounding be possible?
                on.shift(
                    on.alt{boundary="inner"}:_else{side="left"}
                ):_else(
                    on.alt{side="right"}:_else{boundary="outer"}
                ),
            ):_else(
                -- round to a specific position
                on.shift{side="left"}:_else{side="right"},
                on.alt{boundary="inner"}:_else{boundary="outer"},
            )
        }},
        --[[ TODO line: if count is given, select specific line by number
        --      (from bottom, if shift/reverse)
        --  if line not given, select via prompt
        --
        --  ctrl/augment and alt/partial should work as usual-ish?
        --
        line=go.select_line ]]

        --[[
        surround=seekable:with{textobject=textobjects.surround},
        comment=seekable:with{textobject=textobjects.comment},
        indent=seekable:with{textobject=textobjects.indent},
        mark=seekable:with{textobject=textobjects.mark}
        tab=go.view_focus{on.alt{center=false}:_else{center=true}},
        ]]

        -- TODO enter = "add new range to selection, immediately following focus, constructed the
        --              same way as the focus" ???!!
    },
}

bindings.actions = {
    on.normal{
        --[[
        char=go.capitalize{reversible, operator},
        line=go.join{reversible, operator},
        mark=go.mark_selection:with{
            -- modify existing mark vs replace existing mark
            -- take only focus of selection vs take entire selection
            --
            -- if modifying, additional choices:
            --      add ranges to mark:
            --          - on overlap: take both, replace, or keep old
            --      remove ranges from mark:
            --          - any overlaps, or only identical?
            --      or some kind of symmetric difference, I guess..

            -- shift: remove any overlap
            -- multiple: use all ranges of selection. otherwise only use focus
            -- choose: choose mark name instead of using default
            -- ctrl or alt: modify mark; otherwise, replace. also implied by shift

            on_overlap="replace", -- could be "replace", "add", or "ignore", or I guess "merge"
            on{ctrl=false,alt=false,shift=false}.let{augment=true}:_else{augment=false},
            on.shift{remove=true},
            on{multiple=false}.let{only_focus=true},
            on.choose{name=prompt.mark},
        },
        ]]
    },
}

-- TODO reset orientation (and clear lock) immediately prior to any non-motion action, effective
--          immediately
-- TODO set highlight=true when we search

local lock = set{lock=true, scope=on.ctrl{"buffer", "window"}}

local set_register=lock.register{name=prompt.register}
local set_highlight=lock.highlight{search=toggle{true,false,value=get.highlight.search}}
bindings.settings = {
    on.normal{
        mark=set.local{default_mark=prompt.mark},
        paste=set_register,
        wring=set_register,
        do=one_shot.orientation{
            on.shift{side="left"}:_else{side="right"},
            on.alt{boundary="inner"}:_else{boundary="outer"},
        },
        search=set_highlight,
        char=set_highlight,
    }
}
