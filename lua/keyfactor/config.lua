local config = {}

config.system_encode = function(key, modifiers) return nil end
config.unshifted = [[abcdefghijklmnopqrstuvwxyz,."_/!<%*$&]]
config.shifted   = [[ABCDEFGHIJKLMNOPQRSTUVWXYZ;:'?-~>#+^|]]
config.keys = {
    left='<Left>',
    right='<Right>',
    up='<Up>',
    down='<Down>',
    home='<Home>',
    end_='<End>',
    page_up='<PageUp>',
    page_down='<PageDown>',
    alternate='<F7>',
    exit='<F4>',
    open='<F1>',
    commit='<F3>',
    wrap='<BS>',

    linewise='<BS>',
    charwise='<F17>',
    capitalize='z',
    layer_operator='r',
    join='w',
    comment='f',
    surround='s',
    indent='c',
    delete='m',
    change='n',
    yank='l',
    layer_action='p',
    insert='t',
    paste='d',
    command='v',
    repeat_='g',
    undo='b',

    goto='a',
    select_='<F18>',
    list='q',
    seek='_',
    jumps='x',
    layer_motion=',',
    object='<Space>',
    scroll='u',
    -- '.' unassigned
    word='e',
    code='o',
    search='y',
    bigram='i',
    char='"',
    mark='j',
    layer_leader='h',
    register='k',

    magic='<F19>',
}

function config.set(options)
    for k,v in pairs(options) do
        if k ~= "set" then
            config[k] = v
        end
    end
end

return config
