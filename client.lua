local cryptoNet = require("lib.cryptoNet")
local pretty = require("cc.pretty")

local itemList = {}

local HOSTNAME = "LootLink"
local function enterCredentials(socket)
    write("Username: ")
    local username = read()
    write("Password: ")
    local password = read("*")
    cryptoNet.login(socket, username, password)
end

local function clamp(min, value, max)
    return math.max(min, math.min(max, value))
end

local function renderScreen()
    local termWidth, termHeight = term.getSize()
    local listXPos, listYPos = 1, 4
    local topLines, bottomLines = 3, 2
    local listWindow = window.create(term.current(), listXPos, listYPos, termWidth, termHeight - topLines - bottomLines) -- 3 lines on top and 3 lines on bottom
    local listWidth, listHeight = listWindow.getSize()
    local yScroll = 1
    local xScroll = 1

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

    local longestName = 0
    local function writeItems()
        local countStrWidth = 7
        listWindow.clear()
        listWindow.setCursorPos(1, 1)
        longestName = 0
        local itemCount = 0
        while itemCount <= listHeight do
            listWindow.setCursorPos(1, 1 + itemCount)
            local entry = itemList[yScroll + itemCount]
            if entry then
                if #entry.item.name > longestName then longestName = #entry.item.name end
                listWindow.write(("%-"..countStrWidth.."s%s"):format(formatCount(entry.item.count), string.sub(entry.item.name, xScroll, xScroll + listWidth - 7 - 2)))
                itemCount = itemCount + 1
            else break end
        end
    end

    local function update()
        local backgroundColor = colors.black
        local scrollbarColor = colors.white

        term.setCursorPos(termWidth, 1)
        term.blit("X", colors.toBlit(colors.red), colors.toBlit(term.getBackgroundColor()))
        local scrollbarSize = math.ceil(listHeight * listHeight / #itemList)
        local scrollbarPos = math.ceil(yScroll / (#itemList - listHeight) * (listHeight - scrollbarSize))
        for i = scrollbarPos, scrollbarPos + scrollbarSize do
            listWindow.setCursorPos(listWidth, i)
            listWindow.blit(" ", colors.toBlit(scrollbarColor), colors.toBlit(scrollbarColor))
        end
        writeItems()
    end
    update()

    local function scrollListener()
        while true do
            local event, dir, x, y = os.pullEvent("mouse_scroll") -- 1 = move down and -1 = move up
            if (x == listWidth) and ((y >= listYPos) and (y <= listHeight)) then
                yScroll = clamp(1, yScroll + dir, #itemList - listHeight + 1)
            else
                xScroll = clamp(1, xScroll + dir, longestName - listWidth + countStrWidth + 2)
            end
            listWindow.clear()
            update()
        end
    end

    local function arrowKeyListener()
        while true do
            local event, key, is_held = os.pullEvent("key")
            if key == keys.up then
                local adjusted = yScroll - 1
                if (adjusted > 0) and (adjusted < #itemList - termHeight + 3) then
                    yScroll = adjusted
                end
            elseif key == keys.down then
                local adjusted = yScroll + 1
                if (adjusted > 0) and (adjusted < #itemList - termHeight + 3) then
                    yScroll = adjusted
                end
            elseif key == keys.left then
                local adjusted = xScroll - 1
                if (adjusted > 0) and (adjusted < longestName - termWidth + 9) then
                    xScroll = adjusted
                end
            elseif key == keys.right then
                local adjusted = xScroll + 1
                if (adjusted > 0) and (adjusted < longestName - termWidth + 9) then
                    xScroll = adjusted
                end
            end
            listWindow.clear()
            update()
        end
    end

    local function clickHandler()
        while true do
            local event, button, x, y = os.pullEvent("mouse_click")
            if (x == termWidth) and (y == 1) then -- X button.
                break
            end
            if y >= listYPos and y <= listHeight - bottomLines then
                local entry = itemList[y-listYPos + yScroll]
                if entry then
                    term.setCursorPos(1, 1)
                    term.clearLine()
                    term.write(entry.item.name)
                else term.write("nil") end
            end
        end
    end
    parallel.waitForAny(scrollListener, arrowKeyListener, clickHandler)
end

local function onStart()
    local socket = cryptoNet.connect(HOSTNAME)
    term.clear()
    local termWidth, termHeight = term.getSize()
    local titleText = "LootLink Login"
    local offset = math.floor((termWidth - #titleText)/2) + 1
    term.setCursorPos(offset, 1)
    print(titleText)
    print()
    enterCredentials(socket)
    print()
    read()
    term.clear()
    os.startThread(renderScreen)
end

local function parseMessage(message, socket)
    if message.context == "queryStorage" then
        itemList = message.data
    end
end

local function onEvent(event)
    if event[1] == "login" then
        local username = event[2]
        local socket = event[3]
        print(("Welcome %s!"):format(username))
        cryptoNet.send(socket, {context = "queryStorage", data = ""})
    elseif event[1] == "failedLogin" then
        print("Incorrect username or password. Please try again.")
        enterCredentials(event[3])
    elseif event[1] == "encrypted_message" then
        parseMessage(event[2], event[3])
    end
end

cryptoNet.setLoggingEnabled(false)
cryptoNet.startEventLoop(onStart, onEvent)
