Storage = {}
Storage.__index = Storage

local findFilter

function Storage.new()
    local storage = setmetatable({}, Storage)
    storage:updateInventories()
    return storage
end

function Storage.setFindFilter(newFilter)
    assert(type(newFilter) == "function", "A function must be specified for the filter.")
    findFilter = newFilter
end

function Storage:updateInventories()
    self.inventories = { peripheral.find("inventory", findFilter) }
end

function Storage:serializeList(fileName)
    local path = fs.combine(shell.dir(), fileName)
    local file = assert(fs.open(path, "w+"), "Encountered a problem writing to the file: "..path)
    file.write(textutils.serialise(self:list()))
    file.close()
end

function Storage:deserializeList(fileName)
    local path = fs.combine(shell.dir(), fileName)
    if fs.exists(path) then
        local file = assert(fs.open(path, "r"), "Encountered a problem opening the file: "..path)
        local result = file.readAll()
        file.close()
        return result and textutils.unserialise(result) or nil
    end
    return nil
end

-- Create sort functions

function Storage:list()
    local aggregated = {}
    for index, inventory in ipairs(self.inventories) do
        for slot, item in pairs(inventory.list()) do
            local itemName = item.name
            if aggregated[itemName] ~= nil then
                local reference = {
                    count = item.count,
                    inventoryIndex = index,
                    slot = slot,
                    nbt = item.nbt
                }
                aggregated[itemName].total = aggregated[itemName].total + reference.count
                table.insert(aggregated[itemName].references, reference)
            else
                aggregated[itemName] = {
                    displayName = self.inventories[index].getItemDetail(slot).displayName,
                    total = item.count,
                    references = {
                        {
                            count = item.count,
                            inventoryIndex = index,
                            slot = slot,
                            nbt = item.nbt
                        }
                    }
                }
            end
        end
    end
    return aggregated
end

function Storage:push(wrappedPeripheral, inventoryIndex, slot, count)
    count = count or 1
    local fromInventory = self.inventories[inventoryIndex]
    if fromInventory and (peripheral.hasType(wrappedPeripheral, "inventory")) then
        fromInventory.pushItems(wrappedPeripheral.getName(wrappedPeripheral), slot, count)
    end
end

return Storage