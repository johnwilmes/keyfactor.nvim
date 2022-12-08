--[[

history stacks:
frame
tabpage
sub-frame window 
buffer
tag
selection


mode stack per frame - this is not history, it is state

mode: mandatory + forbidden layers, and restrictions on windows within the frame
    - focusable
    - scrollable
    - selectable
    - editable
    - change buffer

At what level of api are these restrictions enforced? User-level actions certainly - but any
lower-level also? Probably not?




--]]


local module = {}

local mode_stack = {}

function module.push_mode(frame, config)
    -- TODO validate frame (number) and config ( table)

    if frame==0 then
        frame = get current frame
    end

    local mode = {name=config.name}
    if type(mode.name)~="string" then
        -- TODO default? error?
    end

    mode.layers = {}
    if config.layers then
        local state = TODO get layer state for frame
        for name,enable in pairs(config.layers) do
            if state[name]~=nil and utils.xor(enable, state[name]) then
                -- TODO set layer state to enable (at frame scope?)
                mode.layers[name] = enable
            end
        end
    end

    local stack = utils.table.set_default(frame)
    stack[#stack+1]=mode
end

function module.pop_mode(frame, count)
    count = count or 1
    if frame==0 then
        frame = get current frame
    end
    local stack = utils.table.set_default(frame)
    if count < 1 then count = #stack end

    for _=1,count do
        local mode = table.remove(stack)
        for name,enable in pairs(mode.layers) do
            -- TODO set layer state to NOT enable (at frame scope?)
        end

    end
end






