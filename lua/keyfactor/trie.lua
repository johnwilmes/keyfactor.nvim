local Trie = {}

function Trie:new()
    object = {children = {}}
    setmetatable(object, self)
    self.__index = self
    return object
end

--[[ return node if present, else nil ]]
function Trie:find(sequence)
    if type(sequence) ~= 'table' then
        sequence = {sequence}
    end
    local trie = self

    for _, k in ipairs(sequence) do
        trie = trie.children[k]
        if trie == nil then
            return nil
        end
    end
    return trie
end

--[[ Return node if present, else create it and its prefixes, and return it ]]
function Trie:get(sequence)
    if type(sequence) ~= 'table' then
        sequence = {sequence}
    end
    local trie = self

    for _, k in ipairs(sequence) do
        child = trie.children[k]
        if child == nil then
            child = Trie:new()
            trie.children[k] = child
        end
        trie = child
    end
    return trie
end

function Trie:nodes()
    local parents = {self}
    local path = {}

    local function get_pairs()
        local trie = table.remove(parents)
        if trie == nil then
            return nil
        end

        local node = trie
        local prefix = vim.list_slice(path, 1, #path)

        local key, child = next(trie.children)
        while key == nil do
            trie = table.remove(parents)
            if trie == nil then
                break
            else
                key, child = next(trie.children, table.remove(path))
            end
        end
        table.insert(parents, trie)
        table.insert(parents, child)
        table.insert(path, key)

        return prefix, node
    end

    return get_pairs
end

function Trie:filter(predicate)
    local iter = self:nodes()

    local function get_pairs()
        local prefix, trie = iter()
        while (trie ~= nil) and not predicate(trie) do
            prefix, trie = iter()
        end
        return prefix, trie
    end

    return get_pairs
end

function Trie:leaves()
    return self:filter(function(trie) return vim.tbl_isempty(trie.children) end)
end

--[[ Return node if present, else nil ]]

return Trie
