local TallLayout = utils.class()

-- TODO handle mode size requests...
-- in particular, need to respect a min size to avoid bugs when there are too many modes to fit in
-- the screen

function TallLayout:__init(opts)
    self._modes = {}
    self._order = {}

    self._width = vim.go.columns
    self._height = vim.go.lines
end

function TallLayout:resize(width, height)
    if self._width~=width or self._height~=height then
        self._width=width
        self._height=height
    end
end

function TallLayout:add_mode(mode, placement)
    assert(not self._modes[mode], "mode already added")
    local position = placement.position or {}
    local index = #self._order+1
    if placement.index==1 then
        index = 1
    else
        if self._modes[position.anchor] then
            -- we are placing relative to a particular mode
            index = utils.list.index(self._order, position.anchor) or 1
            if index==1 or position.direction~="up" then
                index = index+1
            end
        elseif position.direction=="up" then
            index=2
        end
    end
    table.insert(self._order, index, mode)
    self._modes[mode]=true
end

function TallLayout:remove_mode(mode)
    assert(self._modes[mode], "mode not added")
    index = utils.list.index(self._order, position.anchor) or #self._order
    table.remove(self._order, index)
    self._modes[mode]=nil
end

function TallLayout:get_layout()
    if #self._order == 0 then
        return {}
    elseif #self._order == 1 then
        return {self._order[1]}
    else
        local secondary = {split="horizontal"}
        for i=2,#self._order do
            secondary[i]={self._order[i]}
        end
        return {split="vertical", {self._order[1]}, secondary}
    end
end

function TallLayout:get_sizes()
    local sizes = {}
    if #self._order==1 then
        sizes[self._order[1]] = {width=self._width, height=self._height}
    elseif #self._order>1 then
        sizes[self._order[1]] = {width=math.ceil(self._width/2), height=self._height}
        local width = math.floor(self._width/2)
        local height = math.floor(self._height/(#self._order-1))
        local n_tall = self._height % (#self._order-1)
        for i=2,#self._order do
            local h = height
            if i <= n_tall then
                h = h+1
            end
            sizes[self._order[i]] = {width=width, height=h}
        end
    end
    return sizes
end
