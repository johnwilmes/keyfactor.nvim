local textobjects = require("keyfactor.textobjects")

local map, on, outer, key -- TODO

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

local selection = go.select_textobject:with{
    reversible,
    augment=on.control,
    partial=on.alt,
    textobject=outer.textobject,
}

local direction = go.select_direction:with{
    augment=on.shift,
    direction=outer.direction,
}

local nav = map(on.control(
    on.alt(
        go.frame.split
    )._else(
        on.shift:bind(go.frame.move):else_bind(go.frame.focus)
    )
))

-- UNIVERSAL LAYER
settings.maps = {}
settings.maps.universal = {
    up=nav:with{direction="up"},
    down=nav:with{direction="down"},
    left=nav:with{direction="left"},
    right=nav:with{direction="right"},
    esc=go.stop_mode,
}

-- NORMAL LAYER
settings.maps.normal = {
    scroll=go.scroll:with{reversible, partial=on.alt, linewise=on.control},

    up=direction:with{direction="up"},
    down=direction:with{direction="down"},
    left=direction:with{direction="left"},
    right=direction:with{direction="right"},

    line=selection:with{textobject=textobjects.line},
    word=selection:with{textobject=textobjects.word},
    -- individual ranges from current mark:
    --mark=selection{textobject=textobjects.mark:with{name=get.local("default_mark")}},
    char=selection:with{textobject=textobjects.char},
    search=selection:with{textobject=textobjects.search},

    delete=go.trim:with{point_operator},
    backspace=go.trim:with{point_operator, reverse=true},

    cut=go.cut:with{operator},
    copy=go.copy:with{operator},

    paste=go.paste:with{point_operator},
    insert=go.insert.start:with{point_operator, append=true},

    undo=go.undo:with{reversible},
}

-- INSERT LAYER

local insert_delete = {
    partial=true,
    on.control:bind{
        boundary="outer",
        textobject=textobjects.line,
    }:else_on.alt:bind{
        boundary="inner",
        textobject=textobjects.line,
    }.else_on.shift:bind{
        textobject=textobjects.word,
    },
}

settings.maps.insert = {
    on_not(map{
        delete=go.insert.delete:with{insert_delete},
        backspace=go.insert.delete:with{reverse=true, insert_delete},
        tab=go.insert.indent,
        enter=go.insert.linebreak,
    }):bind(
        on(key.is_printable):bind(go.insert.text)
    ),
}

-- PROMPT LAYERS
settings.maps.prompt = {
    enter=go.prompt.accept,
}

settings.maps.getkey = {
    on_not(map{esc=go.stop_mode}):bind(go.prompt.getkey)
}

return settings
