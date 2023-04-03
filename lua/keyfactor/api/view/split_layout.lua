local SplitLayout = utils.class()

function SplitLayout:__init(opts)
    self._modes = {}
    self._order = {}
    self._splits = {}
    self._width = vim.go.columns
    self._height = vim.go.lines
end

function SplitLayout:_fix_sizes(width, height)
    -- for now, just do naive sizing ignoring requested sizes from modes
    -- TODO modes requesting max/min sizes:
    --      respect max sizes that don't add up to enough by using filler splits
    --      if min sizes add up to too much, then don't display the lowest-priority modes (highest
    --      indices)
    --          cap min sizes at half screen width/height?
    local cur_width, cur_height
    local self._sizes = {}
    for _,mode in ipairs(self._order) do
        -- for each mode, in descending priority order
        -- compute what screen size would be if mode was allowed its min width/height
        local record = self._modes[mode]
        self._sizes[mode] = {width=record.min_width, height=record.min_height}
        cur_width, cur_height = compute_size(self._splits, self._sizes)
        -- if resulting size exceeds actual screen size, decrease allotted size
        self._sizes.width = record.min_width - math.max(cur_width-width, 0)
        self._sizes.height = record.min_height - math.max(cur_height-height, 0)
        -- continue to next mode, even if new_width >= width (m.m. height), since split structure
        -- may still allow it to be displayed
    end
    cur_width = math.min(width, cur_width)
    cur_height = math.min(height, cur_height)

end

function SplitLayout:resize(width, height)
    if self._width~=width or self._height~=height then
        self._width=width
        self._height=height
    end
end

function SplitLayout:add_mode(mode, placement)
    assert(not self._modes[mode], "mode already added")
end

function SplitLayout:remove_mode(mode)
    assert(self._modes[mode], "mode not added")
end

function SplitLayout:get_layout()
    return self._splits
end

function SplitLayout:get_sizes()
    return self._sizes
end
