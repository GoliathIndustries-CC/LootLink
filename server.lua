local cryptoNet = require("lib.cryptoNet")
local Storage = require("storage")
local completion = require("cc.completion")

local function log(message)
    print("[LootLink] "..message)
end

local function readFile(fileName)
    local path = fs.combine(shell.dir(), fileName)
    if fs.exists(path) then
        local file = assert(fs.open(path, "r"), "Encountered a problem opening the file: "..path)
        local result = file.readAll()
        file.close()
        return result
    end
    return nil
end

local function writeFile(fileName, data)
    local path = fs.combine(shell.dir(), fileName)
    local file = assert(fs.open(path, "w+"), "Encountered a problem writing to the file: "..path)
    file.write(data)
    file.close()
end

local function getReservedInventories()
    local fileName = "reserved.tbl"
    local ids = {
        ["input"] = "Storage input",
        ["manager"] = "Inventory Manager input",
    }

    local function userInput(use)
        print(("Enter the peripheral name for the %s."):format(use))
        while true do
            local choices = peripheral.getNames()
            write("> ")
            local input = read(nil, peripheral.getNames(), function(text) return completion.choice(text, peripheral.getNames()) end)
            if input == "exit" then return nil end
            local wrapped = peripheral.wrap(input)
            if wrapped and peripheral.hasType(wrapped, "inventory") then
                return input
            end
        end
    end

    local function populateReserved()
        local serialized = readFile(fileName)
        if serialized then
            local deserialized = textutils.unserialise(serialized)
            if deserialized then -- Can be nil.
                local isValid = true
                for key, value in pairs(ids) do
                    if deserialized[key] == nil or peripheral.wrap(deserialized[key]) == nil then
                        isValid = false
                        break
                    end
                end
                if isValid then return deserialized end
            end
        end
        local reserved = {}
        for key, value in pairs(ids) do
            reserved[key] = userInput(value)
        end
        local validSides = {"top", "bottom", "left", "right", "back", "front", "north", "south", "east", "west", "up", "down"}
        print("Enter the side or cardinal direction for the storage adjacent to the inventory manager.")
        write("> ")
        reserved.managerInputSide = read(nil, peripheral.getNames(), function(text) return completion.choice(text, validSides) end)
        return reserved
    end

    term.clear()
    local reserved = populateReserved()
    writeFile(fileName, textutils.serialise(reserved))
    return reserved
end

local modemSide = peripheral.getName(assert(peripheral.find("modem", function(name, modem) return modem.isWireless() end), "Requires a wireless modem."))
local reserved = getReservedInventories()
local storageInput = peripheral.wrap(reserved.input)
local managerInput = peripheral.wrap(reserved.manager)
local managerInputSide = reserved.managerInputSide
local inventoryManager = assert(peripheral.find("inventoryManager"), "LootLink requires an inventory manager peripheral.")
-- assert(inventoryManager.getOwner(), "InventoryManager doesn't have an owner.") -- Ensure that the inventoryManager has a valid memory card.
-- Should be taken care of by the temporary forceOwn program.

-- We don't want to consider the reserved inventories in the storage.
Storage.setFindFilter(
    function(name, wrapped)
        for key, value in pairs(reserved) do
            if name == value then return false end
        end
        return true
    end
)
local storage = Storage.new()


-- Username: GoliathX211
-- Password: Development#88!

local HOSTNAME = "LootLink"
local function onStart()
    cryptoNet.host(HOSTNAME, false, false, modemSide)
    os.startThread(function()
        local timer = 0
        while true do
            if timer == 0 then
                storage:serializeList("cachedStorage.tbl")
                log("Updated storage cache.")
                timer = 60
            else timer = timer - 1 end
            os.sleep(1)
        end
    end)
end

local function getPlayerInventory()
    local result = {}
    local inventory = inventoryManager.getItems()
    for index, item in ipairs(inventory) do
        table.insert(result, {item = {count = item.count, name = item.name}, slot = item.slot})
    end
    return result
end

local function parseMessage(message, socket)
    if socket.username == nil then return end
    if message.context == "queryStorage" then
        local list = storage:deserializeList("cachedStorage.tbl") or storage:list()
        cryptoNet.send(socket, {context = "queryStorage", data = list})
        log("Served queryStorage to "..socket.username)
    end
end

local function onEvent(event)
    if event[1] == "encrypted_message" then
        parseMessage(event[2], event[3]) -- Event[2] = message, event[3] = socket
    end
end

cryptoNet.startEventLoop(onStart, onEvent)