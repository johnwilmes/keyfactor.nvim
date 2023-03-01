local go = require("keyfactor.action")
local textobjects = require("keyfactor.textobjects")

local map, on, get -- TODO

local settings = {}

settings.keys = {
    seek="_",
    go="<Space>", motion="<Space>", -- both labels describe the key <Space>
    left={"<Left>", "<kLeft>"}, --both keys are described by the label left
}

settings.layers = {"universal", "normal", "insert", "raw", "prompt"}
settings.layer_conflicts = {normal = {"insert", "raw"}, insert = {"raw"}}
settings.orientation = {boundary="inner", side="right"}
settings.bindings = {}

-- DEFINE COMMON ACTION/MODIFIER FAMILIES
local reversible = {reverse=on.shift}

local operator = {
    linewise=on.control,
    orientation__boundary=on.alt("inner")._else("outer"),
}

local point_operator = {
    operator,
    orientation__side=on.shift("left")._else("right"),
}

local selection = go.select_textobject{
    reversible,
    augment=on.control,
    partial=on.alt,
    textobject=get.outer.textobject,
}

local direction = go.select_direction{
    augment=on.shift,
    direction=get.outer.direction,
}

local frame_nav = map(on.control(
    on.alt(
        go.frame.split
    )._else(
        on.shift(go.frame.move)._else(go.frame.focus)
    )
))

-- UNIVERSAL LAYER
settings.bindings.universal = {
    up=frame_nav:with{direction="up"},
    down=frame_nav:with{direction="down"},
    left=frame_nav:with{direction="left"},
    right=frame_nav:with{direction="right"},
    command=command,
}

-- NORMAL LAYER
settings.bindings.normal = {
    scroll=go.scroll{reversible, partial=on.alt, linewise=on.control},

    up=direction:with{direction="up"},
    down=direction:with{direction="down"},
    left=direction:with{direction="left"},
    right=direction:with{direction="right"},

    line=selection:with{textobject=textobjects.line},
    word=selection:with{textobject=textobjects.word},
    -- individual ranges from current mark:
    --mark=selection{textobject=textobjects.mark:with{name=get.local("default_mark")}},
    char=selection{textobject=textobjects.char},
    search=selection{textobject=textobjects.search},

    delete=go.trim{point_operator},
    backspace=go.trim{point_operator, reverse=true},

    cut=go.cut{operator, autochange=true},
    copy=go.copy{operator},

    paste=go.paste{point_operator},
    insert=go.insert.start{point_operator, append=true, autochange=true},

    undo=go.undo{reversible},
}

-- INSERT LAYER
settings.bindings.insert = {
    on._not(map{
        delete=go.insert.delete{
            partial=true,
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
        backspace=go.insert.delete{
            reverse=true,
            partial=true,
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
        tab=go.insert.indent,
        enter=go.insert.linebreak,

        esc=go.insert.stop,
    })._then(
        on(get.context.printable)._then(insert{text=get.context.printable})
    ),
}

-- PROMPT LAYERS
settings.bindings.raw = {
    on._not(map{
        backspace=go.prompt.pop_key
    })._then(
        go.prompt.push_key
    )
}

settings.bindings.prompt = {
    enter=go.prompt.accept,
    esc=go.prompt.cancel,
}

return settings
