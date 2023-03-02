local textobjects = require("keyfactor.textobjects")

local map, map_first, on, outer -- TODO

local settings = {}

settings.keys = {
    seek="_",
    go="<Space>", motion="<Space>", -- both labels describe the key <Space>
    left={"<Left>", "<kLeft>"}, --both keys are described by the label left
}

settings.layers = {
    "universal", "normal", "insert", "prompt", "getkey",
    groups = {
        normal={base="normal", "universal"},
        insert={base="insert", "universal"},
        prompt={base="prompt", "universal", "getkey"},
    }
}

settings.orientation = {boundary="inner", side="after"}

-- DEFINE COMMON ACTION/MODIFIER FAMILIES
local reversible = {reverse=on.shift}

local operator = {
    linewise=on.control,
    orientation__boundary=on.alt:bind("inner"):else_bind("outer"),
}

local point_operator = {
    operator,
    orientation__side=on.shift:bind("before"):else_bind("after"),
}

local selection = go.select.textobject:bind{
    reversible,
    augment=on.control,
    partial=on.alt,
    textobject=outer.textobject,
}

local direction = go.select.direction:bind{
    augment=on.shift,
    direction=outer.direction,
}

local nav = map(on.control:bind(
    on.alt:bind(
        go.layout.split_window
    ):else_on{shift=true}:bind(
        go.layout.move_window
    ):else_bind(
        go.layout.focus
    )
))

-- UNIVERSAL LAYER
settings.maps = {}
settings.maps.universal = map{
    up=nav:bind{direction="up"},
    down=nav:bind{direction="down"},
    left=nav:bind{direction="left"},
    right=nav:bind{direction="right"},
    esc=go.mode.stop,
}

-- NORMAL LAYER
settings.maps.normal = map{
    scroll=go.scroll:bind{reversible, partial=on.alt, linewise=on.control},

    up=direction:bind{direction="up"},
    down=direction:bind{direction="down"},
    left=direction:bind{direction="left"},
    right=direction:bind{direction="right"},

    line=selection:bind{textobject=textobjects.line},
    word=selection:bind{textobject=textobjects.word},
    -- individual ranges from current mark:
    --mark=selection{textobject=textobjects.mark:bind{name=get.local("default_mark")}},

    -- textobjects.char - by default, get pattern from (outer) params.prompt.value; either
    -- prompt.char or textobjects.char can default with case where prompt is empty accept
    char=go.prompt.char:pass{accept=selection:bind{textobject=textobjects.char}},
    search=go.prompt.search:pass{accept=selection:bind{textobject=textobjects.search}},

    delete=go.trim:bind{point_operator},
    backspace=go.trim:bind{point_operator, reverse=true},

    cut=go.cut:bind{operator},
    copy=go.copy:bind{operator},

    paste=go.paste:bind{point_operator},
    insert=go.insert.start:bind{point_operator, append=true},

    undo=go.undo:bind{reversible},
}

-- INSERT LAYER

local insert_delete = {
    partial=true,
    on.control:bind{
        boundary="outer",
        textobject=textobjects.line,
    }:else_on{alt=true}:bind{
        boundary="inner",
        textobject=textobjects.line,
    }.else_on{shift=true}:bind{
        textobject=textobjects.word,
    },
}

settings.maps.insert = map_first{
    {
        delete=go.insert.delete:bind{insert_delete},
        backspace=go.insert.delete:bind{reverse=true, insert_delete},
        tab=go.insert.indent,
        enter=go.insert.linebreak,
    },
    on(outer.key.is_printable):bind(go.insert.text)
}

-- PROMPT LAYERS
settings.maps.prompt = map{
    enter=go.prompt.accept,
}

settings.maps.getkey = map_first{
    {
        enter=go.prompt.accept, -- use prompt will use default value
        esc=go.mode.stop,
    },
    go.prompt.getkey
}

return settings
