local basalt = require("lib.basalt")
local cryptoNet = require("lib.cryptoNet")

local pretty = require("cc.pretty")

local itemList = {}
local FRAMES = {}

basalt.LOGGER.setEnabled(true)
basalt.LOGGER.setLogToFile(true)

local HOSTNAME = "LootLink"

local function filterItems(filter)
    local results = {}
    if string.sub(filter, 1, 1) == "@" then
        -- Filter by namespace
        local modFilter = string.sub(filter, 2)
        for resourceLocation, data in pairs(itemList) do
            local namespace = string.match(resourceLocation, "^(.-):") or ""
            if string.find(namespace, modFilter) then
                table.insert(results, {[1] = data.total, [2] = data.displayName, [3] = resourceLocation})
            end
        end
    else
        -- Filter by item name
        for resourceLocation, data in pairs(itemList) do
            if string.find(string.lower(data.displayName), string.lower(filter)) then
                table.insert(results, {[1] = data.total, [2] = data.displayName, [3] = resourceLocation})
            end
        end
    end
    return results
end

local function formatCount(n)
    if n >= 1e12 then
        return ("%.1ft"):format(n/1e12)
    elseif n >= 1e9 then
        return ("%.1fb"):format(n/1e9)
    elseif n >= 1e6 then
        return ("%.1fm"):format(n/1e6)
    elseif n >= 1e3 then
        return ("%.1fk"):format(n/1e3)
    else return tostring(n) end
end

local function createStorageFrame(parentFrame)
    local termWidth, termHeight = term.getSize()

    local storageFrame = parentFrame:addFrame({x = 1, y = 1, width = termWidth, height = termHeight})

    local interactionFrame = storageFrame:addFrame({x = 1, y = 1, width = termWidth, height = 4})
    --local selectedItemLabel = interactionFrame:addLabel({text = "", x = 1, y = 1})
    interactionFrame:addLabel({text = "Quantity", x = 10, y = 2, width = 6})
    local manualInput = interactionFrame:addInput({
        x = 10, y = 3, width = 8, background = colors.gray,
        pattern = "^%d+$",
        text = "",
    })


    local listHeight = termHeight - 5
    local listFrame = storageFrame:addFrame({x = 1, y = 5, width = termWidth, height = listHeight})
    listFrame:addLabel({text = "Search: ", x = 1, y = 1, width = 7})
    local searchInput = listFrame:addInput({text = "", x = 8, y = 1, width = termWidth - 7 - 1, background = colors.gray})
    local itemsTable = listFrame:addTable({
        x = 1, y = 2,
        width = termWidth, height = listHeight - 1,
        columns = {
            {name = "Count", width = 7},
            {name = "Name", width = termWidth - 7}
        },
        sortColumn = 1,
        sortDirection = "desc"
    })
    itemsTable:setColumnSortFunction(1, function(a, b, direction)
        local valueA, valueB = a._sortValues[1], b._sortValues[1]
        if direction == "asc" then
            return valueA < valueB
        else
            return valueA > valueB
        end
    end)

    local populateItemsTable = function()
        local scrollOffset = itemsTable.get("scrollOffset")
        local selectedRowIndex = itemsTable.get("selectedRow")
        local resourceLocation
        if selectedRowIndex then
            resourceLocation = itemsTable.get("data")[selectedRowIndex][3]
        end
        local sortColumn, sortDirection = itemsTable.get("sortColumn"), itemsTable.get("sortDirection")
        -- Table#setData resets the sortColumn and sortDirection back to nil and 'asc' respectively.
        itemsTable:setData(filterItems(searchInput.get("text")), {[1] = formatCount})
        -- Ensure that the sortColumn and sortDirection stay the same from before the update.
        itemsTable:setSortColumn(sortColumn); itemsTable:setSortDirection(sortDirection)
        itemsTable:setScrollOffset(scrollOffset)
        itemsTable:sortData(sortColumn)

        -- If the item is in the same position, the row will stay selected.
        if selectedRowIndex then
            if itemsTable.get("data")[selectedRowIndex][3] == resourceLocation then
                itemsTable:setSelectedRow(selectedRowIndex)
            end
        end
    end

    local function validateInput(input)
        return input:match("^[1-9]%d*$") and true or false
    end

    manualInput:onChange("text", function(self, newText, oldText)
        if newText == "" then return end
        if not validateInput(newText) then self:setText(oldText); return end
        local success, result = pcall(tonumber, newText)
        -- If somehow the newText does not parse into a number.
        if not success then self:setText(oldText); return end

        local row = itemsTable.get("data")[itemsTable.get("selectedRow")]
        if not row then self:setText(""); return end

        local storedQuantity = row._sortValues[1]
        basalt.LOGGER.info(("result: %s, storedQuantity: %s, #asText: %s"):format(result, storedQuantity, #tostring(storedQuantity)))

        if result > storedQuantity then
            local asText = tostring(storedQuantity)
            self:setText(asText)
        end


    end)
    -- itemsTable:onChange("selectedRow", function(self, newRowIndex)
    --     local value = manualInput.get("text")
    --     local success, result = pcall(tonumber, value)
    --     local num = success and result or 1
    --     local row = self.get("data")[newRowIndex]
    --     local totalCount = row and row._sortValues[1] or 0
    --     manualInput:setText(tostring(clamp(0, num, totalCount)))
    -- end)

    searchInput:onChange("text", populateItemsTable)
    storageFrame:registerCallback("storageUpdated", populateItemsTable)

    return storageFrame
end

local function lootLinkFrameInit(parentFrame, socket)
    local termWidth, termHeight = term.getSize()
    local lootLinkFrame = parentFrame:addFrame({visible = false, x = 1, y = 1, width = termWidth, height = termHeight})

    local storageFrame = createStorageFrame(lootLinkFrame)
    -- Pass storageFrame related events through to storageFrame
    lootLinkFrame:registerCallback("storageUpdated", function() storageFrame:fireEvent("storageUpdated") end)

    FRAMES.lootLink = lootLinkFrame

    basalt.schedule(function ()
        while true do
            os.sleep(5)
            cryptoNet.send(socket, {context = "queryStorage"})
        end
    end) -- Storage updater.
end

local function credentialsFrameInit(parentFrame, socket)
    local credentialsFrame = parentFrame:addFrame({draggable = true, width = 24, height = 9, x = 2, y = 5, background = colors.gray, foreground = colors.black})
    credentialsFrame:addLabel({text = "LootLink Login", x = 6, y = 2, foreground = colors.white})

    credentialsFrame:addLabel({text = "User: ", x = 2, y = 4})
    local usernameInput = credentialsFrame:addInput({placeholder = "    username", x = 8, y = 4, width = 16, height = 1})

    credentialsFrame:addLabel({text = "Pass: ", x = 2, y = 5})
    local passwordInput = credentialsFrame:addInput({placeholder = "    password", replaceChar = "*", x = 8, y = 5, width = 16, height = 1})

    local message1Label = credentialsFrame:addLabel({text = "", x = 3, y = 8})
    local message2Label = credentialsFrame:addLabel({text = "", x = 8, y = 9})

    local loginButton = credentialsFrame:addButton({text = "Login", x = 10, y = 7, width = 5, height = 1})
    loginButton:onClick(function()
        cryptoNet.login(socket, usernameInput:getText(), passwordInput:getText())
    end)

    credentialsFrame:registerCallback("invalidCredentials", function()
        message1Label:setText("Invalid credentials.")
        message1Label:setForeground(colors.red)

        message2Label:setText("Try again.")
        message2Label:setForeground(colors.red)

        usernameInput:setText("")
        passwordInput:setText("")
    end)

    FRAMES.credentials = credentialsFrame
end

local function onStart()
    local main = basalt.getMainFrame()
    local socket = cryptoNet.connect(HOSTNAME)
    cryptoNet.login(socket, "GoliathX211", "Development#88!")
    credentialsFrameInit(main, socket)
    lootLinkFrameInit(main, socket)
    basalt.run()
end

local function parseMessage(message, socket)
    if message.context == "queryStorage" then
        itemList = message.data
        FRAMES.lootLink:fireEvent("storageUpdated")
    end
end

local function onEvent(event)
    if event[1] == "login" then
        local username = event[2]
        local socket = event[3]
        cryptoNet.send(socket, {context = "queryStorage"})
        FRAMES.credentials:setVisible(false)
        FRAMES.lootLink:setVisible(true)
    elseif event[1] == "login_failed" then
        FRAMES.credentials:fireEvent("invalidCredentials")
        -- Tell the credentialsFrame that the username or password is incorrect.
    elseif event[1] == "logout" then
        for _, frame in ipairs(FRAMES) do
            frame:setVisible(false)
        end
        FRAMES.credentials.setVisible(true)
    elseif event[1] == "encrypted_message" then
        parseMessage(event[2], event[3])
    end
end

cryptoNet.setLoggingEnabled(false)
cryptoNet.startEventLoop(onStart, onEvent)
