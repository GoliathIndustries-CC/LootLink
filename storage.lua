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

-- Create sort functions

function Storage:search(query)
    local function aggregate(results)
        local aggregated = {}
        for _, entry in ipairs(results) do
            local itemName = entry.item.name
            if aggregated[itemName] ~= nil then
                local reference = {
                    count = entry.item.count,
                    inventoryIndex = entry.inventoryIndex,
                    slot = entry.slot,
                    nbt = entry.item.nbt
                }
                aggregated[itemName].total = aggregated[itemName].total + reference.count
                table.insert(aggregated[itemName].references, reference)
            else
                aggregated[itemName] = {
                    displayName = self.inventories[entry.inventoryIndex].getItemDetail(entry.slot).displayName,
                    total = entry.item.count,
                    references = {
                        {
                            count = entry.item.count,
                            inventoryIndex = entry.inventoryIndex,
                            slot = entry.slot,
                            nbt = entry.item.nbt
                        }
                    }
                }
            end
        end
        return aggregated
    end

    local function modSearch(modQuery)
        local results = {}
        for index, inventory in ipairs(self.inventories) do
            for slot, item in pairs(inventory.list()) do
                local namespace = string.match(item.name, "^(.-):") or ""
                if string.find(namespace, modQuery) then
                    table.insert(results, {item = item, slot = slot, inventoryIndex = index})
                end
            end
        end
        return results
    end

    local function nameSearch(nameQuery)
        local results = {}
        for index, inventory in ipairs(self.inventories) do
            for slot, item in pairs(inventory.list()) do
                local itemDisplayName = inventory.getItemDetail(slot).displayName
                if string.find(itemDisplayName, nameQuery) then
                    table.insert(results, {item = item, slot = slot, inventoryIndex = index})
                end
            end
        end
        return results
    end
    if string.sub(query, 1, 2) == "@" then return aggregate(modSearch(string.sub(query, 2))) else return aggregate(nameSearch(query)) end
end

function Storage:push(wrappedPeripheral, inventoryIndex, slot, count)
    count = count or 1
    local fromInventory = self.inventories[inventoryIndex]
    if fromInventory and (peripheral.hasType(wrappedPeripheral, "inventory")) then
        fromInventory.pushItems(wrappedPeripheral.getName(wrappedPeripheral), slot, count)
    end
end

return Storage