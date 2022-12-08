local go = require("keyfactor.action")

local bind, wring, redo, set, get, on, outer, clear

local keys = {
    seek="_",
    go="<Space>", motion="<Space>", -- both labels describe the key <Space>
    left={"<Left>", "<kLeft>"}, --both keys are described by the label left
}

local mods = {"choose", "multiple"}
local layers = {"universal", "normal", "motions", "actions", "settings", "insert", "raw", "prompt"}
local conflicts = {normal = {"insert", "raw"}, insert = {"raw"}, settings = {"insert", "raw"}}
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

local reversible = {reverse=on.shift}

local operator = {
    unset.orientation,
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
    register__name=on.choose(register.prompt_name),
    register__shape=on.multiple(toggle{"larger", "smaller", value=get_shape})
}

local selection = go.select_textobject{
    reversible,
    augment=on.control,
    choose=on.choose,
    partial=on.alt,
    multiple=on.multiple(on.shift("split"):_else("select")),
    textobject=outer.textobject,
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
        control=on.control,
        choose=on.choose,
        multiple=on.multiple,
    },
    one_shot.layer{
        motions=on{layer="motions"},
        actions=on{layer="actions"},
        settings=on{layer="settings"},
    },
    one_shot.params{
        count=get.params.count,
    },
}

local bindings = {}

bindings.universal = {
    -- TODO window navigation
    -- save, quit
}

bindings.normal = {
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
    char=redo.capture{namespace="seek"; selection{textobject=textobjects.char}, go.set.highlight{search=true}},
    search=redo.capture{namespace="seek"; selection{textobject=textobjects.search}, go.set.highlight{search=true}},
    seek=go.redo{namespace="seek"},


    -- TODO on control, remove nearby blank lines?
    -- TODO on shift, undo the trimming?
    delete=go.trim{point_operator},
    backspace=go.trim{point_operator, reverse=true},

    -- TODO shift should determine location of the resulting empty range (or range-part) in the
    -- case of linewise deletion, with the effect that following with insert while holding mods
    -- places a line with effect identical to line-wise "change" action
    --
    -- But it would also be nice to have shift set the register to the same one used by yank, with
    -- the default a "garbage" register
    cut=go.cut{operator, register, autochange=true},
    copy=go.copy{operator, register},

    paste=redo.capture{go.paste{point_operator, register}},
    insert=redo.capture{insert.start{point_operator, append=true, autochange=true}},
    wring=redo.capture{go.wring{reversible, register}},

    undo=go.undo{reversible, choose=on.choose},
    --[[ TODO
    surround={},
    comment={},
    indent={},
    ]]

    tab=go.rotate{reversible, contents=on.control("wring"), jump=on.alt},

    -- enter= command prompt?
    esc=on(prompt.is_active)._then(prompt.cancel)._else(clear.mods),
}

bindings.insert = {
    on._not(bind{
        delete=insert.delete{
            on.control{
                boundary="outer",
                textobject=textobjects.line,
            }._elseon.alt{
                boundary="inner",
                textobject=textobjects.line,
            }._elseon.shift{
                textobject=textobjects.word,
            },
        },
        backspace=insert.delete{
            reverse=true,
            on.control{
                boundary="outer",
                textobject=textobjects.line,
            }._elseon.alt{
                boundary="inner",
                textobject=textobjects.line,
            }._elseon.shift{
                textobject=textobjects.word,
            },
        },
        tab=insert.indent,
        enter=insert.linebreak,

        --[[ if completing, just cancel it;
        --   otherwise, exit insert mode
        --   if (non-completing) prompt is active, cancel on control
        --   otherwise (no non-completing prompt is active), set redo to reinsert
        --]]
        esc=on(completion.is_active)._then(prompt.cancel)._else{
            insert.stop,
            on._not(prompt.is_active)._then(redo.set_only{insert.reinsert})
        }
        esc={insert.stop, on.control(prompt.cancel)},

        choose=on(prompt.is_active)._then(
            prompt.accept
        )._else(
            completion.prompt{orientation__boundary=get.insert.orientation.boundary}
        )

        -- multiple= TODO treesitter-based auto-close; alternatively moves cursor forward in cases
        -- where next "closing" is already present
        -- (or should this shadow a normal-mode key that does "go to matching close"?)
    })._then(
        -- TODO if focus is not visible, then make it visible
        -- TODO literal mode to insert literally
        on(context.printable)._then(insert{text=context.printable})
    ),
}

bindings.prompt = {
    --tab= rotate focus?
    enter=prompt.accept, -- TODO multiselect prompt should instead just select focus?
    esc=prompt.cancel,
}

bindings.motions = {
    do=go.truncate_selection{
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
    },
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
}

bindings.actions = {
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
}

local lock = set{lock=true, scope=on.control{"buffer", "window"}}

go.set_local.register{name=prompt.register}

local set_register=lock.register{name=prompt.register}
local set_highlight=lock.highlight{search=toggle{true,false,value=get.highlight.search}}
bindings.settings = {
    mark=set.local{default_mark=prompt.mark},
    paste=set_register,
    wring=set_register,
    do=lock.orientation{
        side=on.shift("left"):_else("right"),
        boundary=on.alt("inner"):_else("outer"),
    },
    search=set_highlight,
    char=set_highlight,
}
