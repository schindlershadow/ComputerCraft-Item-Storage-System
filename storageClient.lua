math.randomseed(os.time() + (5 * os.getComputerID()))
local timeoutConnect = nil
local width, height = term.getSize()
local scroll = 0
local search = ""
local items = {}
local recipes = {}
local displayedRecipes = {}
local menu = false
local menuSel = "storage"
local storageServerSocket, craftingServerSocket
local isWirelessModem = false
local cryptoNetURL = "https://raw.githubusercontent.com/SiliconSloth/CryptoNet/master/cryptoNet.lua"
local username = ""
local password = ""

-- Settings
--Settings
settings.define("StorageServer", { description = "storage server hostname", default = "StorageServer", type = "string" })
settings.define("CraftingServer",
    { description = "crafting server hostname", default = "CraftingServer", type = "string" })
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("crafting", { description = "Enables crafting support", default = "false", type = "boolean" })
settings.define("exportChestName",
    { description = "Name of the export chest for this client", default = "minecraft:chest_0", type = "string" })

local logging = true
local debug = false

--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    --settings.set("StorageServer", "StorageServer")
    --settings.set("craftingServer", "CraftingServer")
    settings.set("debug", false)
    settings.set("crafting", false)
    settings.set("exportChestName", "minecraft:chest_0")
    print("Stop the client and edit .settings file with correct settings")
    settings.save()
    sleep(5)
end

term.setBackgroundColor(colors.blue)

Item = { name = "", count = 1, nbt = "", tags = "" }
function Item:new(name, count, nbt, tags)
    obj = obj or {}
    setmetatable(obj, self)
    self.__index = self
    self.name = name or ""
    self.count = count or 1
    self.nbt = nbt or ""
    self.tags = tags or nil

    return obj
end

function Item:getTable()
    local table = {}
    if self.name ~= "" then
        table["name"] = self.name
    end
    if self.count ~= 0 then
        table["count"] = self.count
    end
    if self.nbt ~= "" then
        table["nbt"] = self.nbt
    end
    return table
end

local function log(text)
    if settings.get("debug") then
        local logFile = fs.open("logs/clientDebug.log", "a")
        if type(text) == "string" then
            logFile.writeLine(text)
        else
            logFile.writeLine(textutils.serialise(text))
        end

        logFile.close()
    end
end

local function dump(o)
    if type(o) == "table" then
        local s = ""
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = '"' .. k .. '"'
            end
            s = s .. "[" .. k .. "] = " .. dump(v) .. ","
        end
        return s
    else
        return tostring(o)
    end
end

local function getRecipes()
    cryptoNet.send(craftingServerSocket, { "getRecipes" })
    local event
    repeat
        event = os.pullEvent("gotRecipes")
    until event == "gotRecipes"
end

local function pingStorageServer()
    cryptoNet.send(storageServerSocket, { "ping" })
    local event
    repeat
        event = os.pullEvent("storageServerAck")
    until event == "storageServerAck"
end

local function getItemDetails(item)
    if type(item) ~= "nil" and type(item.chestName) ~= "nil" and type(item.slot) ~= "nil" then
        cryptoNet.send(storageServerSocket, { "getItemDetails", item })
        local event, data
        repeat
            event, data = os.pullEvent("gotItemDetails")
        until event == "gotItemDetails"

        if type(data) == "table" then
            return data
        else
            sleep(0.5 + (math.random() % 0.2))
            return getItemDetails()
        end
    end
end

local function centerText(text)
    local x, y = term.getSize()
    local x1, y1 = term.getCursorPos()
    term.setCursorPos((math.floor(x / 2) - (math.floor(#text / 2))), y1)
    term.write(text)
end

local function loadingScreen(text)
    if type(text) == nil then
        text = ""
    end
    term.setBackgroundColor(colors.red)
    term.clear()
    term.setCursorPos(1, 2)
    centerText(text)
    term.setCursorPos(1, 4)
    centerText("Loading...")
    term.setCursorPos(1, 6)
end

local function findInTable(arr, element)
    for i, value in pairs(arr) do
        if value.name == element.name and value.nbt == element.nbt then
            return i
        end
    end
    return nil
end

local function inTable(arr, element) -- function to check if something is in an table
    for _, value in pairs(arr) do
        if value.name == element.name and value.nbt == element.nbt then
            return true
        end
    end
    return false -- if no element was found, return false
end

local function removeDuplicates(arr)
    local newArray = {}                        -- new array that will be arr, but without duplicates
    for _, element in pairs(arr) do
        if not inTable(newArray, element) then -- making sure we had not added it yet to prevent duplicates
            --if element.details == nil then
            --element.details = peripheral.wrap(element.chestName).getItemDetail(element.slot)
            --end
            table.insert(newArray, element)
        else
            local index = findInTable(newArray, element)
            if index ~= nil then
                newArray[index]["count"] = newArray[index].count + element.count
            end
        end
    end
    return newArray -- returning the new, duplicate removed array
end

--Filters items by search term
local function filterItems()
    local filteredTable = {}
    for k, v in pairs(items) do
        if v["details"] == nil then
            if string.find(string.lower(v["name"]), string.lower(search)) or string.find(string.lower(v["name"]), string.lower(search:gsub(" ", "_"))) then
                local tab = v
                --tab.details = peripheral.wrap(v.chestName).getItemDetail(v.slot)
                table.insert(filteredTable, tab)
            end
        elseif string.find(string.lower(v["details"]["displayName"]), string.lower(search)) or string.find(string.lower(v["details"]["displayName"]), string.lower(search:gsub(" ", "_"))) or string.find(string.lower(v["name"]), string.lower(search)) or string.find(string.lower(v["name"]), string.lower(search:gsub(" ", "_"))) then
            table.insert(filteredTable, v)
        end
    end
    local outputTable = removeDuplicates(filteredTable)
    return outputTable
end

local function getItems()
    --pingStorageServer()
    cryptoNet.send(storageServerSocket, { "getItems" })
    local event
    repeat
        event = os.pullEvent("itemsUpdated")
    until event == "itemsUpdated"
end

local function import(item)
    --pingStorageServer()
    cryptoNet.send(storageServerSocket, { "import", item:getTable() })
end

local function importAll()
    loadingScreen("Importing from Export chests")
    --print("Waiting for server to be ready")
    --pingStorageServer()
    --print("Importing")
    cryptoNet.send(storageServerSocket, { "importAll" })
    local event
    repeat
        event = os.pullEvent("importAllComplete")
    until event == "importAllComplete"
    --pingStorageServer()
    print("Import Complete")
    print("Reloading Database")
    getItems()
end

local function export(item)
    cryptoNet.send(storageServerSocket, { "export", { item = item:getTable(), chest = settings.get("exportChestName") } })
end

local function drawDetailsmenu(sel)
    local filteredItems = filterItems()
    local amount = 1
    local done = false
    while done == false do
        term.setBackgroundColor(colors.green)
        for k = 3, height - 1, 1 do
            for i = 1, width, 1 do
                term.setCursorPos(i, k)
                term.write(" ")
            end
        end
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.black)
        for i = 1, width, 1 do
            term.setCursorPos(i, 1)
            term.write(" ")
        end
        centerText("Details Menu")
        term.setCursorPos(1, 2)
        term.setBackgroundColor(colors.blue)
        for i = 1, width, 1 do
            term.setCursorPos(i, 2)
            term.write(" ")
        end
        centerText(filteredItems[sel].name .. " #" .. tostring(filteredItems[sel].count))
        term.setBackgroundColor(colors.green)
        term.setCursorPos(1, 3)
        if filteredItems[sel].details ~= nil then
            write(dump(filteredItems[sel].details))
        end
        term.setCursorPos(width, 1)
        term.setBackgroundColor(colors.red)
        term.write("x")
        term.setBackgroundColor(colors.green)

        local event, button, x, y
        repeat
            event, button, x, y = os.pullEvent()
        until event == "mouse_click" or event == "key"

        if event == "key" then
            local key = button
            if key == keys.backspace then
                done = true
            end
        end

        if event == "mouse_click" then
            if y < 2 and x > width - 1 then
                done = true
            end
        end

        --sleep(5)
    end
end

local function craftRecipe(recipe, amount, canCraft)
    local table = {}
    local logs = {}
    for row = 1, 3, 1 do
        table[row] = {}
        for slot = 1, 3, 1 do
            table[row][slot] = 0
        end
    end


    --sleep(0.1)
    recipe.amount = amount
    if canCraft == true then
        cryptoNet.send(craftingServerSocket, { "craftItem", recipe })
    else
        cryptoNet.send(craftingServerSocket, { "autoCraftItem", recipe })
    end
    term.clear()
    local id, message
    local nowCrafting = recipe.name
    local ttl = 5
    repeat
        local timeoutTimer = os.startTimer(15)
        if type(message) == "table" and message.type == "craftingUpdate" then
            log(textutils.serialise(message))
            if message.message == "slotUpdate" then
                table[message[1]][message[2]] = message[3]
            elseif message.message == "itemUpdate" then
                nowCrafting = message[1]
                for row = 1, 3, 1 do
                    table[row] = {}
                    for slot = 1, 3, 1 do
                        table[row][slot] = 0
                    end
                end
            elseif message.message == "logUpdate" then
                if logs[#logs] ~= message[1] then
                    logs[#logs + 1] = message[1]
                end
            end
            ttl = 5
        end

        if type(message) == "nil" then
            ttl = ttl - 1
        end

        term.clear()
        term.setCursorPos(1, 1)
        centerText("Crafting:" .. nowCrafting:match(".+:(.+)"))

        --Draw crafting table
        term.setCursorPos(1, 2)
        term.setBackgroundColor(colors.gray)
        print("        ")
        --term.setCursorPos(1, 2 + 1)
        term.setCursorPos(1, 1)
        local pos = 1
        for row = 1, 3, 1 do
            term.setCursorPos(1, 2 + row)
            term.setBackgroundColor(colors.gray)
            term.write(" ")
            if type(recipe.recipe[row]) == "nil" then
                term.setBackgroundColor(colors.black)
                term.write("     ")
            else
                for slot = 1, 3, 1 do
                    --log(textutils.serialise(recipe.recipe[row][slot][1]))
                    if table[row][slot] == 0 then
                        term.setBackgroundColor(colors.black)
                        term.write("  ")
                    else
                        term.setBackgroundColor(colors.green)
                        term.write(string.format("%02d",table[row][slot]))
                    end
                    if slot ~= 3 then
                        --term.setBackgroundColor(colors.gray)
                        --term.write(" ")
                    end
                end
            end
            term.setCursorPos(8, 2 + row)
            term.setBackgroundColor(colors.gray)
            term.write(" ")
        end
        term.setBackgroundColor(colors.gray)
        term.setCursorPos(1, 6)
        print("        ")

        --Draw logs
        term.setBackgroundColor(colors.black)
        local count = 0
        if pocket then
            for i = 8, (height - 2), 1 do
                term.setCursorPos(1, i)
                if #logs - count > 0 and type(logs[#logs - count]) ~= "nil" then
                    term.write(logs[#logs - count])
                    count = count + 1
                end
            end
        else
            for i = 5, (height - 2), 1 do
                term.setCursorPos(7, i)
                if #logs - count > 0 and type(logs[#logs - count]) ~= "nil" then
                    term.write(logs[#logs - count])
                    count = count + 1
                end
            end
        end

        local event, data
        repeat
            event, data = os.pullEvent()
        until event == "craftingUpdate" or data == timeoutTimer
        if data == timeoutTimer then
            ttl = 0
        else
            message = data
        end
        --log("data: " .. dump(data))

        if type(message) == "table" and type(message.message) == "boolean" then
            message = message.message
            break
        end

    until (type(message) == "boolean") or ttl < 1
    if ttl < 1 then
        message = false
        term.setBackgroundColor(colors.red)
        centerText(" Connection Timeout! ")
        print()
    end
    term.setCursorPos(1, height - 1)
    if message == true then
        term.setBackgroundColor(colors.green)
        centerText(" Crafting Complete! ")
    elseif message == false then
        term.setBackgroundColor(colors.red)
        centerText(" Crafting Failed! ")
    end
    term.setBackgroundColor(colors.black)
    print()
    term.setBackgroundColor(colors.blue)
    centerText(" Press any button ")

    local event, button, x, y
    repeat
        event, button, x, y = os.pullEvent()
    until event == "mouse_click" or event == "key" or event == "mouse_scroll"
    --loadingScreen("Loading request from Storage Server...")
    getItems()
    --sleep(10)

    return message
end

local function getAmount(itemName)
    cryptoNet.send(craftingServerSocket, { "getAmount", itemName })

    local event, data
    repeat
        event, data = os.pullEvent("gotAmount")
    until event == "gotAmount"

    return data
end

local function getCraftingServerCert()
    --Download the cert from the crafting server if it doesnt exist already
    local filePath = settings.get("CraftingServer") .. ".crt"
    if not fs.exists(filePath) then
        log("Download the cert from the CraftingServer")
        cryptoNet.send(craftingServerSocket, { "getCertificate" })
        --wait for reply from server
        log("wait for reply from CraftingServer")
        local event, data
        repeat
            event, data = os.pullEvent("gotCertificate")
        until event == "gotCertificate"

        log("write the cert file")
        --write the file
        local file = fs.open(filePath, "w")
        file.write(data)
        file.close()
    end
end

local function getStorageServerCert()
    --Download the cert from the storageserver if it doesnt exist already
    local filePath = settings.get("StorageServer") .. ".crt"
    if not fs.exists(filePath) then
        log("Download the cert from the storageserver")
        cryptoNet.send(storageServerSocket, { "getCertificate" })
        --wait for reply from server
        log("wait for reply from server")
        local event, data
        repeat
            event, data = os.pullEvent("gotCertificate")
        until event == "gotCertificate"

        log("write the cert file")
        --write the file
        local file = fs.open(filePath, "w")
        file.write(data)
        file.close()
    end
end

local function isCraftable(itemName)
    cryptoNet.send(craftingServerSocket, { "craftable", itemName })
    local event, data
    repeat
        event, data = os.pullEvent("gotCraftable")
    until event == "gotCraftable"
    --log("craftable" .. dump(data))
    return data
end

local function drawCraftingMenu(sel, inputTable)
    menu = true
    if type(inputTable) == "nil" then
        log("type(inputTable) == nil")
        inputTable = displayedRecipes
    end
    --log(inputTable)
    local amount = 1
    local done = false
    while done == false do
        --loadingScreen("Loading request from Crafting Server...")

        inputTable[sel].amount = amount
        log(inputTable[sel])
        cryptoNet.send(craftingServerSocket, { "getNumNeeded", inputTable[sel] })

        local event, data
        repeat
            event, data = os.pullEvent("gotNumNeeded")
        until event == "gotNumNeeded"

        local numNeeded = data
        local legend = {}
        local legendKeys = {}
        local canCraft = true
        local count = 0
        for i, v in pairs(numNeeded) do
            count = count + 1
            legend[count] = {}
            legend[count].item = i
            legend[count].count = v
            legend[count].have = getAmount(i)
            legendKeys[i] = count

            if legend[count].have < legend[count].count then
                canCraft = false
            end
        end

        term.setBackgroundColor(colors.green)
        term.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.black)
        local tmpText = ""
        for i = 1, width, 1 do
            tmpText = tmpText .. " "
        end
        term.write(tmpText)
        centerText("Crafting Menu")
        term.setCursorPos(1, 2)
        term.setBackgroundColor(colors.brown)
        tmpText = ""
        for i = 1, width, 1 do
            tmpText = tmpText .. " "
        end
        term.write(tmpText)
        term.setCursorPos(1, 2)
        term.write("<")
        centerText(inputTable[sel].name .. " #" .. tostring(inputTable[sel].count))
        term.setCursorPos(width, 2)
        term.write(">")
        term.setCursorPos(1, 3)
        term.setBackgroundColor(colors.gray)
        print("     ")
        term.setCursorPos(1, 3 + 1)
        term.setCursorPos(1, 1)
        --print(textutils.serialise(inputTable[sel].recipe))
        --sleep(10)

        --Draw crafting table
        local pos = 1
        for row = 1, 3, 1 do
            term.setCursorPos(1, 3 + row)
            term.setBackgroundColor(colors.gray)
            term.write(" ")
            if type(inputTable[sel].recipe[row]) == "nil" then
                term.setBackgroundColor(colors.black)
                term.write("   ")
                term.setBackgroundColor(colors.gray)
                term.write(" ")
            else
                for slot = 1, 3, 1 do
                    term.setBackgroundColor(colors.black)
                    if type(inputTable[sel].recipe[row][slot]) == "nil" then
                        term.write(" ")
                    else
                        --log(textutils.serialise(inputTable[sel].recipe[row][slot][1]))
                        if inputTable[sel].recipe[row][slot][1] == "none" or inputTable[sel].recipe[row][slot][1] == "item:minecraft:air" then
                            term.write(" ")
                        else
                            term.write(utf8.char(legendKeys[inputTable[sel].recipe[row][slot][1]] + 64))
                        end
                    end
                    if slot ~= 3 then
                        --term.setBackgroundColor(colors.gray)
                        --term.write(" ")
                    end
                end
            end
            term.setCursorPos(5, 3 + row)
            term.setBackgroundColor(colors.gray)
            term.write(" ")
        end
        term.setBackgroundColor(colors.gray)
        term.setCursorPos(1, 7)
        print("     ")


        --Draw legend
        if pocket then
            for i = 1, #legend, 1 do
                term.setCursorPos(1, 8 + (i - 1))
                --log(tostring(getAmount(legend[i].item)))
                if legend[i].count <= legend[i].have then
                    term.setBackgroundColor(colors.green)
                else
                    term.setBackgroundColor(colors.red)
                end
                term.write(utf8.char(i + 64) ..
                    ":" ..
                    legend[i].item:match(":([%w,_,/]*)$") ..
                    ":" .. tostring(legend[i].have) .. "/" .. tostring(legend[i].count))
                --term.write(utf8.char(i + 64) .. ": #" .. legend[i].count .. " " .. legend[i].item)
            end
        else
            for i = 1, #legend, 1 do
                term.setCursorPos(7, 4 + (i - 1))
                --log(tostring(getAmount(legend[i].item)))
                if legend[i].count <= legend[i].have then
                    term.setBackgroundColor(colors.green)
                else
                    term.setBackgroundColor(colors.red)
                end
                term.write(utf8.char(i + 64) ..
                    ": " ..
                    legend[i].item:match(":([%w,_,/]*)$") ..
                    ": " .. tostring(legend[i].have) .. "/" .. tostring(legend[i].count))
                --term.write(utf8.char(i + 64) .. ": #" .. legend[i].count .. " " .. legend[i].item)
            end
        end


        term.setBackgroundColor(colors.green)


        term.setCursorPos(1, height - (height * .25) + 1)
        centerText("Amount to request")
        term.setCursorPos(width, 1)
        term.setBackgroundColor(colors.red)
        term.write("x")
        term.setBackgroundColor(colors.green)
        term.setCursorPos((width * .25), height - (height * .25) + 2)
        term.write("<")
        term.setCursorPos((width * .50), height - (height * .25) + 2)
        centerText(tostring(amount))
        term.setCursorPos(width - (width * .25), height - (height * .25) + 2)
        term.write(">")
        term.setCursorPos((width * .25), height - (height * .25) + 3)
        term.write("+64")
        term.setCursorPos((width * .25) * 2 - 1, height - (height * .25) + 3)
        term.write("-64")
        term.setCursorPos((width * .25) * 3, height - (height * .25) + 3)
        term.write("1")

        term.setBackgroundColor(colors.red)
        term.setCursorPos(1, height - (height * .25) + 4)
        if canCraft == true then
            centerText(" Craft ")
        else
            centerText(" Attempt to AutoCraft ")
        end


        local event, button, x, y
        repeat
            event, button, x, y = os.pullEvent()
        until event == "mouse_click" or event == "key" or event == "mouse_scroll"

        if event == "key" then
            local key = button
            if key == keys.right then
                amount = amount + 1
            elseif key == keys.left then
                if amount > 1 then
                    amount = amount - 1
                end
            elseif key == keys.home then
                amount = 1
            elseif key == keys.comma then
                if type(inputTable[sel - 1]) ~= "nil" then
                    done = true
                    drawCraftingMenu(sel - 1, inputTable)
                end
            elseif key == keys.period then
                if type(inputTable[sel + 1]) ~= "nil" then
                    done = true
                    drawCraftingMenu(sel + 1, inputTable)
                end
            elseif key == keys.backspace then
                done = true
            elseif key == keys.enter or key == keys.numPadEnter then
                loadingScreen("Communication with Crafting Server")
                done = true
                craftRecipe(inputTable[sel], amount, canCraft)
            elseif key == keys.one and type(legend[1]) ~= "nil" then
                local craftable = isCraftable(legend[1].item)
                if craftable ~= false then
                    log("craftable: " .. dump(craftable))
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.two and type(legend[2]) ~= "nil" then
                local craftable = isCraftable(legend[2].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.three and type(legend[3]) ~= "nil" then
                local craftable = isCraftable(legend[3].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.four and type(legend[4]) ~= "nil" then
                local craftable = isCraftable(legend[4].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.five and type(legend[5]) ~= "nil" then
                local craftable = isCraftable(legend[5].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.six and type(legend[6]) ~= "nil" then
                local craftable = isCraftable(legend[6].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.seven and type(legend[7]) ~= "nil" then
                local craftable = isCraftable(legend[7].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.eight and type(legend[8]) ~= "nil" then
                local craftable = isCraftable(legend[8].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.nine and type(legend[9]) ~= "nil" then
                local craftable = isCraftable(legend[9].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad1 and type(legend[1]) ~= "nil" then
                local craftable = isCraftable(legend[1].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad2 and type(legend[2]) ~= "nil" then
                local craftable = isCraftable(legend[2].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad3 and type(legend[3]) ~= "nil" then
                local craftable = isCraftable(legend[3].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad4 and type(legend[4]) ~= "nil" then
                local craftable = isCraftable(legend[4].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad5 and type(legend[5]) ~= "nil" then
                local craftable = isCraftable(legend[5].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad6 and type(legend[6]) ~= "nil" then
                local craftable = isCraftable(legend[6].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad7 and type(legend[7]) ~= "nil" then
                local craftable = isCraftable(legend[7].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad8 and type(legend[8]) ~= "nil" then
                local craftable = isCraftable(legend[8].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            elseif key == keys.numPad9 and type(legend[9]) ~= "nil" then
                local craftable = isCraftable(legend[9].item)
                if craftable ~= false then
                    drawCraftingMenu(1, craftable)
                end
            end
        elseif event == "mouse_scroll" then
            if button == -1 then
                amount = amount + 1
            elseif button == 1 then
                if amount > 1 then
                    amount = amount - 1
                end
            end
        elseif event == "mouse_click" then
            if x > 8 and y >= 4 and y <= 4 + 8 and type(legend[y - 3]) ~= "nil" then
                --Item on legend is clicked, open subMenu

                local craftable = isCraftable(legend[y - 3].item)
                log(textutils.serialise(craftable))

                if craftable ~= false and craftable ~= nil then
                    log("craftable: " .. tostring(craftable))
                    drawCraftingMenu(1, craftable)
                end
            elseif (x == math.floor(width * .25) and y == math.floor(height - (height * .25) + 2))
            then
                if amount > 1 then
                    amount = amount - 1
                end
            elseif (x == math.floor(width - (width * .25)) and y == math.floor((height - (height * .25) + 2)))
            then
                amount = amount + 1
            elseif (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and (y == math.floor(height - (height * .25) + 3)))
            then
                amount = amount + 64
            elseif (((x < ((width * .25) * 2) + 3) and (x > ((width * .25) * 2) - 3)) and
                (y == math.floor(height - (height * .25) + 3)))
            then
                if amount > 1 + 64 then
                    amount = amount - 64
                else
                    amount = 1
                end
            elseif (x == math.floor((width * .25) * 3) and y == math.floor(height - (height * .25) + 3))
            then
                amount = 1
            elseif y == (height - 1) then
                loadingScreen("Communication with Crafting Server")
                done = true
                craftRecipe(inputTable[sel], amount, canCraft)
            elseif y == 2 and x == 1 then
                if type(inputTable[sel - 1]) ~= "nil" then
                    loadingScreen("Communication with Crafting Server")
                    done = true
                    drawCraftingMenu(sel - 1, inputTable)
                end
            elseif y == 2 and x == width then
                if type(inputTable[sel + 1]) ~= "nil" then
                    loadingScreen("Communication with Crafting Server")
                    done = true
                    drawCraftingMenu(sel + 1, inputTable)
                end
            elseif y < 2 and x > width - 1 then
                done = true
            end
        end

        --sleep(5)
    end
    menu = false
end

local function drawMenu(sel, list)
    menu = true
    local filteredItems = list
    if filteredItems == nil then
        filteredItems = filterItems()
    end
    local amount = 1
    local done = false
    while done == false do
        term.setBackgroundColor(colors.green)
        term.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(colors.black)
        local tmpText = ""
        for i = 1, width, 1 do
            tmpText = tmpText .. " "
        end
        term.write(tmpText)

        if filteredItems[sel].details ~= nil and filteredItems[sel].details.displayName ~= nil then
            centerText(filteredItems[sel].details.displayName .. " Item Menu")
        else
            centerText("Item Menu")
        end
        term.setCursorPos(1, 2)
        term.setBackgroundColor(colors.blue)
        tmpText = ""
        for i = 1, width, 1 do
            tmpText = tmpText .. " "
        end
        term.write(tmpText)
        centerText(filteredItems[sel].name .. " #" .. tostring(filteredItems[sel].count))
        term.setBackgroundColor(colors.green)
        term.setCursorPos(1, 3)
        if filteredItems[sel].details ~= nil then
            term.setBackgroundColor(colors.red)
            centerText(" Show Item details ")
            term.setBackgroundColor(colors.green)
        end
        term.setCursorPos(1, (height * .25) + 4)
        centerText("Amount to request")
        term.setCursorPos(width, 1)
        term.setBackgroundColor(colors.red)
        term.write("x")
        term.setBackgroundColor(colors.green)
        term.setCursorPos((width * .25), (height * .25) + 5)
        term.write("<")
        term.setCursorPos((width * .50), (height * .25) + 5)
        centerText(tostring(amount))
        term.setCursorPos(width - (width * .25), (height * .25) + 5)
        term.write(">")
        term.setCursorPos((width * .25), (height * .25) + 7)
        term.write("+64")
        term.setCursorPos((width * .25) * 2 - 1, (height * .25) + 7)
        term.write("-64")
        term.setCursorPos((width * .25) * 3, (height * .25) + 7)
        term.write("1")
        term.setCursorPos(1, (height * .25) + 11)
        centerText("All")

        term.setBackgroundColor(colors.red)
        term.setCursorPos(1, height - (height * .25) + 4)
        centerText(" Request ")

        local event, button, x, y

        repeat
            event, button, x, y = os.pullEvent()
        until event == "mouse_click" or event == "key" or event == "mouse_scroll"

        if event == "key" then
            local key = button
            if key == keys.right then
                if amount < filteredItems[sel].count then
                    amount = amount + 1
                end
            elseif key == keys.left then
                if amount > 1 then
                    amount = amount - 1
                end
            elseif key == keys['end'] then
                amount = filteredItems[sel].count
            elseif key == keys.home then
                amount = 1
            elseif key == keys.comma then
                if type(filteredItems[sel - 1]) ~= "nil" then
                    done = true
                    drawMenu(sel - 1, filteredItems)
                end
            elseif key == keys.period then
                if type(filteredItems[sel + 1]) ~= "nil" then
                    done = true
                    drawMenu(sel + 1, filteredItems)
                end
            elseif key == keys.s then
                if filteredItems[sel].details ~= nil then
                    drawDetailsmenu(sel)
                end
            elseif key == keys.backspace then
                done = true
            elseif key == keys.enter or key == keys.numPadEnter then
                loadingScreen("Exporting Items")
                done = true
                local result
                if filteredItems[sel].nbt == nil then
                    result = Item:new(filteredItems[sel].name, amount, "", filteredItems[sel].tags)
                else
                    result = Item:new(filteredItems[sel].name, amount, filteredItems[sel].nbt, filteredItems[sel].tags)
                end
                export(result)
                print("Export Complete")
                print("Reloading Database")
                getItems()
            end
        elseif event == "mouse_scroll" then
            if button == -1 then
                if amount < filteredItems[sel].count then
                    amount = amount + 1
                end
            elseif button == 1 then
                if amount > 1 then
                    amount = amount - 1
                end
            end
        elseif event == "mouse_click" then
            if (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and
                ((y > (height * .25) + 4) and (y < (height * .25) + 6)))
            then
                if amount > 1 then
                    amount = amount - 1
                end
            elseif (((x < (width - (width * .25)) + 2) and (x > (width - (width * .25)) - 2)) and
                ((y > (height * .25) + 4) and (y < (height * .25) + 6)))
            then
                if amount < filteredItems[sel].count then
                    amount = amount + 1
                end
            elseif (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and
                ((y > (height * .25) + 6) and (y < (height * .25) + 10)))
            then
                if amount + 64 < filteredItems[sel].count then
                    amount = amount + 64
                else
                    amount = filteredItems[sel].count
                end
            elseif (((x < ((width * .25) * 2) + 3) and (x > ((width * .25) * 2) - 3)) and
                ((y > (height * .25) + 6) and (y < (height * .25) + 10)))
            then
                if amount > 1 + 64 then
                    amount = amount - 64
                else
                    amount = 1
                end
            elseif (((x < ((width * .25) * 3) + 3) and (x > ((width * .25) * 3) - 3)) and
                ((y > (height * .25) + 6) and (y < (height * .25) + 10)))
            then
                amount = 1
            elseif (y < ((height * .25) + 13)) and (y > ((height * .25) + 10)) then
                amount = filteredItems[sel].count
            elseif y == (height - 1) then
                loadingScreen("Exporting Items")
                done = true
                local result
                if filteredItems[sel].nbt == nil then
                    result = Item:new(filteredItems[sel].name, amount, "", filteredItems[sel].tags)
                else
                    result = Item:new(filteredItems[sel].name, amount, filteredItems[sel].nbt, filteredItems[sel].tags)
                end
                export(result)
                print("Export Complete")
                print("Reloading Database")
                getItems()
            elseif y < 2 and x > width - 1 then
                loadingScreen("Communication with Storage Server")
                done = true
            elseif y == 3 then
                if filteredItems[sel].details ~= nil then
                    drawDetailsmenu(sel)
                end
            end
        end

        --sleep(5)
    end
    menu = false
end

local function drawList(list)
    if menu == false then
        if menuSel == "storage" then
            local filteredItems = list
            if filteredItems == nil then
                filteredItems = filterItems()
            end
            --log(filteredItems)
            term.setBackgroundColor(colors.blue)

            for k, v in pairs(filteredItems) do
                if k > scroll then
                    if k < (height + scroll) then
                        local text = ""
                        --if v["details"] == nil and not pocket and not isWirelessModem then
                        if v["details"] == nil then
                            if type(peripheral.wrap(v.chestName)) == "nil" then
                                v.details = getItemDetails(v)
                            else
                                v.details = peripheral.wrap(v.chestName).getItemDetail(v.slot)
                            end
                            filteredItems[k].details = v.details
                        end
                        if v["details"] == nil then
                            text = v["name"]:match(".+:(.+)") .. " - #" .. v["count"]
                        else
                            text = v["details"]["displayName"] .. " - #" .. v["count"]
                            if v["details"]["damage"] ~= nil then
                                text = text ..
                                    " Durability:" ..
                                    tostring(math.floor(100 *
                                            ((v["details"]["maxDamage"] - v["details"]["damage"]) / v["details"]["maxDamage"])) ..
                                        "%")
                            end
                            if v["details"]["enchantments"] ~= nil then
                                text = text .. " Enchanted"
                            end
                            if v["nbt"] ~= nil and settings.get("debug") then
                                text = text .. " NBT:" .. dump(v["nbt"])
                            end
                        end

                        for i = 1, width, 1 do
                            term.setCursorPos(i, k - scroll)
                            term.write(" ")
                        end
                        term.setCursorPos(1, k - scroll)
                        term.write(text)
                        term.setCursorPos(1, height)
                    end
                end
            end
            for k = 1, height - 1, 1 do
                if type(filteredItems[k + scroll]) == "nil" then
                    for i = 1, width, 1 do
                        term.setCursorPos(i, k)
                        term.write(" ")
                    end
                end
            end
        elseif menuSel == "crafting" then
            local filteredRecipes = {}
            for k, v in pairs(recipes) do
                if string.find(string.lower(v["name"]), string.lower(search)) or string.find(string.lower(v["name"]), string.lower(search:gsub(" ", "_"))) then
                    filteredRecipes[#filteredRecipes + 1] = v
                end
            end
            term.setBackgroundColor(colors.brown)
            for k, recipe in pairs(filteredRecipes) do
                if k > scroll then
                    if k < (height + scroll) then
                        for i = 1, width, 1 do
                            term.setCursorPos(i, k - scroll)
                            term.write(" ")
                        end
                        term.setCursorPos(1, k - scroll)
                        term.write(recipe.name ..
                            " #" .. tostring(recipe.count) .. " - " .. recipe.recipeName:match("(.*):"))
                        term.setCursorPos(1, height)
                    end
                end
            end
            for k = 1, height - 1, 1 do
                if type(filteredRecipes[k + scroll]) == "nil" then
                    for i = 1, width, 1 do
                        term.setCursorPos(i, k)
                        term.write(" ")
                    end
                end
            end

            displayedRecipes = filteredRecipes
        end

        --import
        term.setCursorPos(width - 8, height - 1)
        term.setBackgroundColor(colors.red)
        term.write(" Import  ")
        term.setBackgroundColor(colors.blue)

        if settings.get("crafting") == true then
            term.setCursorPos(width - 8, height - 3)
            if menuSel == "crafting" then
                term.setBackgroundColor(colors.green)
            else
                term.setBackgroundColor(colors.red)
            end
            term.write(" Crafting ")
            term.setBackgroundColor(colors.blue)

            term.setCursorPos(width - 8, height - 2)
            if menuSel == "storage" then
                term.setBackgroundColor(colors.green)
            else
                term.setBackgroundColor(colors.red)
            end
            term.write(" Storage ")
            term.setBackgroundColor(colors.blue)
        end
    end
end

local function openMenu(sel)
    if menuSel == "crafting" then
        if displayedRecipes[sel + scroll] ~= nil then
            drawCraftingMenu(sel + scroll, displayedRecipes)
            local filteredItems = filterItems()
            drawList(filteredItems)
        end
    else
        local filteredItems = filterItems()
        if filteredItems[sel + scroll] ~= nil then
            drawMenu(sel + scroll)
            filteredItems = filterItems()
            drawList(filteredItems)
        end
    end
end

local function inputHandler()
    while true do
        local event, key, x, y
        repeat
            event, key, x, y = os.pullEvent()
        until event == "char" or event == "key" or event == "mouse_scroll" or event == "mouse_click" or event == "databaseReloaded"
        log(event)
        if (event == "char" or event == "key" or event == "mouse_scroll" or event == "mouse_click") and menu == false then
            --term.setCursorPos(1,height)
            if event == "databaseReloaded" then
                getItems()
                drawList()
            elseif event == "mouse_click" then
                if y == height - 1 and x > width - 8 then
                    --Import button pressed
                    importAll()
                    drawList()
                elseif settings.get("crafting") == true and y == height - 2 and x > width - 8 then
                    --Storage menu button pressed
                    menuSel = "storage"
                    drawList()
                elseif settings.get("crafting") == true and y == height - 3 and x > width - 8 then
                    --Crafting menu button pressed
                    menuSel = "crafting"
                    drawList()
                elseif (items[y + scroll] ~= nil or displayedRecipes[y + scroll] ~= nil) and y ~= height then
                    openMenu(y)
                end
            elseif key == keys.one then
                openMenu(1)
            elseif key == keys.two then
                openMenu(2)
            elseif key == keys.three then
                openMenu(3)
            elseif key == keys.four then
                openMenu(4)
            elseif key == keys.five then
                openMenu(5)
            elseif key == keys.six then
                openMenu(6)
            elseif key == keys.seven then
                openMenu(7)
            elseif key == keys.eight then
                openMenu(8)
            elseif key == keys.nine then
                openMenu(9)
            elseif event == "char" then
                search = search .. key
            elseif event == "mouse_scroll" then
                if key == 1 then
                    scroll = scroll + 1
                    drawList()
                elseif key == -1 then
                    if scroll > 0 then
                        scroll = scroll - 1
                        drawList()
                    end
                end
            elseif event == "char" or event == "key" then
                if key == keys.pageUp then
                    if scroll >= (height - 1) then
                        scroll = scroll - (height - 1)
                        drawList()
                    elseif scroll > 0 then
                        scroll = 0
                        drawList()
                    end
                elseif key == keys.pageDown then
                    scroll = scroll + (height - 1)
                    drawList()
                elseif key == keys.home then
                    scroll = 0
                    drawList()
                elseif key == keys.up then
                    if scroll > 0 then
                        scroll = scroll - 1
                        drawList()
                    end
                elseif key == keys.down then
                    scroll = scroll + 1
                    drawList()
                elseif key == keys.f5 then
                    loadingScreen("Reloading Database")
                    getItems()
                    drawList()
                elseif key == keys.backspace then
                    search = search:sub(1, -2)
                elseif key == keys.enter or key == keys.numPadEnter then
                    scroll = 0
                    drawList()
                elseif key == keys.tab then
                    scroll = 0
                    if menuSel == "storage" then
                        menuSel = "crafting"
                    elseif menuSel == "crafting" then
                        menuSel = "storage"
                    end
                    drawList()
                elseif key == keys.delete then
                    search = ""
                    scroll = 0
                    drawList()
                elseif key == keys.insert then
                    --Import button pressed
                    importAll()
                    drawList()
                elseif key == keys.numPad1 then
                    openMenu(1)
                elseif key == keys.numPad2 then
                    openMenu(2)
                elseif key == keys.numPad3 then
                    openMenu(3)
                elseif key == keys.numPad4 then
                    openMenu(4)
                elseif key == keys.numPad5 then
                    openMenu(5)
                elseif key == keys.numPad6 then
                    openMenu(6)
                elseif key == keys.numPad7 then
                    openMenu(7)
                elseif key == keys.numPad8 then
                    openMenu(8)
                elseif key == keys.numPad9 then
                    openMenu(9)
                end
            end
        end

        term.setBackgroundColor(colors.black)
        for i = 1, width, 1 do
            term.setCursorPos(i, height)
            term.write(" ")
        end

        term.setCursorPos(1, height)
        term.write(search)
    end
end

function discoverServers(serverType)
    local serverList = {}
    --while next(serverList) == nil do
    print("Looking for servers")
    serverList = cryptoNet.discover()
    --end

    local done = false
    local scrollDiscovery = 0
    while done == false do
        term.setBackgroundColor(colors.gray)
        term.clear()
        term.setCursorPos(1, 1)
        --log(dump(serverList))
        for k, v in pairs(serverList) do
            if k > scrollDiscovery then
                if k < (height + scrollDiscovery) then
                    local text = v.name
                    for i = 1, width, 1 do
                        term.setCursorPos(i, k - scrollDiscovery)
                        term.write(" ")
                    end
                    term.setCursorPos(1, k - scrollDiscovery)
                    term.write(text)
                    term.setCursorPos(1, height)
                end
            end
        end
        for k = 1, height - 1, 1 do
            if type(serverList[k + scrollDiscovery]) == "nil" then
                for i = 1, width, 1 do
                    term.setCursorPos(i, k)
                    term.write(" ")
                end
            end
        end

        --refresh button
        term.setCursorPos(width - 12, height - 1)
        term.setBackgroundColor(colors.red)
        term.write(" Refresh (F5) ")

        term.setBackgroundColor(colors.black)
        for i = 1, width, 1 do
            term.setCursorPos(i, height)
            term.write(" ")
        end
        term.setCursorPos(1, height)
        term.write("Discovered " .. serverType .. " Servers")
        term.setBackgroundColor(colors.gray)

        local event, button, x, y
        repeat
            event, button, x, y = os.pullEvent()
        until event == "mouse_click" or event == "key" or event == "mouse_scroll"

        if event == "key" then
            local key = button
            if key == keys.backspace then
                done = true
            elseif key == keys.f5 then
                done = true
                discoverServers(serverType)
            elseif key == keys.one then
                if serverList[1] ~= nil then
                    settings.set(serverType, serverList[1].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.two then
                if serverList[2] ~= nil then
                    settings.set(serverType, serverList[2].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.three then
                if serverList[3] ~= nil then
                    settings.set(serverType, serverList[3].name)
                    settings.save()
                end
            elseif key == keys.four then
                if serverList[4] ~= nil then
                    settings.set(serverType, serverList[4].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.five then
                if serverList[5] ~= nil then
                    settings.set(serverType, serverList[5].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.six then
                if serverList[6] ~= nil then
                    settings.set(serverType, serverList[6].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.seven then
                if serverList[7] ~= nil then
                    settings.set(serverType, serverList[7].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.eight then
                if serverList[8] ~= nil then
                    settings.set(serverType, serverList[8].name)
                    settings.save()
                    done = true
                end
            elseif key == keys.nine then
                if serverList[9] ~= nil then
                    settings.set(serverType, serverList[9].name)
                    settings.save()
                    done = true
                end
            end
        elseif event == "mouse_scroll" then
            if button == -1 then
                if scrollDiscovery > 0 then
                    scrollDiscovery = scrollDiscovery - 1
                end
            elseif button == 1 then
                scrollDiscovery = scrollDiscovery + 1
            end
        elseif event == "mouse_click" then
            --log("mouse_click x" .. tostring(x) .. " y" .. tostring(y) .. " scroll: " .. tostring(scroll))
            if y == height - 1 and x > width - 12 then
                --refresh button pressed
                done = true
                discoverServers(serverType)
            elseif (serverList[y + scrollDiscovery] ~= nil) and y ~= height then
                settings.set(serverType, serverList[y + scrollDiscovery].name)
                settings.save()
                done = true
            end
        end
    end
end

function loginScreen()
    local done = false
    local user = ""
    local pass = ""
    local text = ""
    local selectedField = "user"
    while done == false do
        term.setBackgroundColor(colors.gray)
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.white)

        --calc the width needed to fit the server name in login box
        local border
        border = math.ceil((width - string.len(settings.get("StorageServer")) - 2) / 2)
        local widthBlanks = ""
        for i = 1, width, 1 do
            widthBlanks = widthBlanks .. " "
        end

        --print computer information
        if (settings.get("debug")) then
            term.setCursorPos(1, 1)
            term.write("DEBUG MODE")
        end
        term.setCursorPos(1, height)
        term.write("ID:" .. tostring(os.getComputerID()))


        --print(tostring(border))
        local forth = math.floor(height / 4)
        for k = forth, height - forth, 1 do
            if k == forth then
                term.setBackgroundColor(colors.black)
            else
                term.setBackgroundColor(colors.lightGray)
            end
            term.setCursorPos(1, k)
            term.write(widthBlanks)
        end

        term.setBackgroundColor(colors.black)
        term.setCursorPos(1, forth)
        centerText("Storage Login")

        term.setTextColor(colors.black)
        term.setBackgroundColor(colors.lightGray)
        term.setCursorPos(1, forth + 2)
        for i = border, width - border, 1 do
            term.setCursorPos(i, forth + 2)
            term.write("~")
        end
        term.setCursorPos(1, forth + 3)
        centerText(settings.get("StorageServer"))
        term.setCursorPos(1, forth + 4)
        for i = border, width - border, 1 do
            term.setCursorPos(i, forth + 4)
            term.write("~")
        end

        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
        for i = border + 6, width - border - 1, 1 do
            term.setCursorPos(i, forth + 6)
            term.write(" ")
        end
        term.setCursorPos(border + 6, forth + 6)
        term.write(user)
        term.setCursorPos(border + 1, forth + 6)
        term.setBackgroundColor(colors.lightGray)
        print("User:")

        term.setBackgroundColor(colors.white)
        for i = border + 6, width - border - 1, 1 do
            term.setCursorPos(i, forth + 8)
            term.write(" ")
        end
        term.setCursorPos(border + 6, forth + 8)
        --write password sub text
        for i = 1, string.len(pass), 1 do
            term.write("*")
        end
        term.setCursorPos(border + 1, forth + 8)
        term.setBackgroundColor(colors.lightGray)
        print("Pass:")

        term.setCursorPos(border + 1, forth + 10)
        term.setBackgroundColor(colors.red)
        term.write(" Change Server ")
        term.setCursorPos(width - border - 7, forth + 10)
        term.setBackgroundColor(colors.green)
        term.write(" Login ")

        local event, button, x, y
        repeat
            event, button, x, y = os.pullEvent()
        until event == "mouse_click" or event == "key" or event == "char"

        if event == "char" then
            local key = button
            --search = search .. key
            if selectedField == "user" then
                user = user .. key
            else
                pass = pass .. key
            end
        elseif event == "key" then
            local key = button
            if key == keys.backspace then
                --remove from text entry
                if selectedField == "user" then
                    user = user:sub(1, -2)
                else
                    pass = pass:sub(1, -2)
                end
            elseif key == keys.enter or key == keys.numPadEnter then
                --set creds
                username = user
                password = pass
                user = ""
                pass = ""
                done = true
            elseif key == keys.tab then
                --toggle user/pass text entry
                if selectedField == "user" then
                    selectedField = "pass"
                else
                    selectedField = "user"
                end
            end
        elseif event == "mouse_click" then
            --log("mouse_click x" .. tostring(x) .. " y" .. tostring(y) .. " scroll: " .. tostring(scroll))
            if y == math.floor(height / 4) + 10 then
                if (x > width - border - 7 and x < width - border - 7 + 15) then
                    --login
                    username = user
                    password = pass
                    user = ""
                    pass = ""
                    done = true
                elseif (x > border + 1 and x < border + 1 + 7) then
                    --change server
                    discoverServers("StorageServer")
                    if settings.get("crafting") then
                        discoverServers("CraftingServer")
                    end
                end
            end
        end
    end
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
end

function onStart()
    --clear out old log
    if fs.exists("logs/clientDebug.log") then
        fs.delete("logs/clientDebug.log")
    end
    --Close any old connections
    cryptoNet.closeAll()

    local wirelessModem = nil
    local wiredModem = nil

    print("Looking for connected modems...")

    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            local modem = peripheral.wrap(side)
            if modem.isWireless() then
                wirelessModem = modem
                wirelessModem.side = side
                print("Wireless modem found on " .. side .. " side")
                log("Wireless modem found on " .. side .. " side")
            else
                wiredModem = modem
                wiredModem.side = side
                print("Wired modem found on " .. side .. " side")
                log("Wired modem found on " .. side .. " side")
            end
        end
    end

    if wirelessModem then
        isWirelessModem = true
    end

    -- Connect to the server
    print("Connecting to server: " .. settings.get("StorageServer"))
    log("Connecting to server: " .. settings.get("StorageServer"))

    timeoutConnect = os.startTimer(15)
    storageServerSocket = cryptoNet.connect(settings.get("StorageServer"))

    --check if server requires a login
    cryptoNet.send(storageServerSocket, { "requireLogin" })
    local event, loginRequired
    repeat
        event, loginRequired = os.pullEvent("requireLogin")
    until event == "requireLogin"

    if isWirelessModem or loginRequired == true then
        timeoutConnect = nil
        --hosts must auth
        --Log in with a username and password
        loginScreen()
        timeoutConnect = os.startTimer(15)
        print("Logging into server:" .. settings.get("StorageServer"))
        log("Logging into server:" .. settings.get("StorageServer"))
        cryptoNet.login(storageServerSocket, username, password)
    else
        getStorageServerCert()
        cryptoNet.send(storageServerSocket, { "storageServer" })
        if settings.get("crafting") then
            print("Connecting to server: " .. settings.get("CraftingServer"))
            log("Connecting to server: " .. settings.get("CraftingServer"))
            craftingServerSocket = cryptoNet.connect(settings.get("CraftingServer"))
            getCraftingServerCert()
            --timeout no longer needed
            timeoutConnect = nil
            cryptoNet.send(craftingServerSocket, { "craftingServer" })
            print("Loading Database")
            getItems()
            print("Loading Recipes")
            getRecipes()
            drawList()

            term.setBackgroundColor(colors.black)
            for i = 1, width, 1 do
                term.setCursorPos(i, height)
                term.write(" ")
            end

            while true do
                inputHandler()
                sleep(0.1)
            end
        else
            print("Loading Database")
            getItems()
            drawList()

            term.setBackgroundColor(colors.black)
            for i = 1, width, 1 do
                term.setCursorPos(i, height)
                term.write(" ")
            end

            while true do
                inputHandler()
                sleep(0.1)
            end
        end
    end
end

function onCryptoNetEvent(event)
    if event[1] == "login" then
        -- Logged in successfully
        -- The username logged in
        local username = event[2]
        -- The socket that was logged in
        local socket = event[3]
        print("Logged in as " .. username .. " to " .. socket.target)
        log("Logged in as " .. username .. " to " .. socket.target)
        log("socket.target: " .. socket.target)
        cryptoNet.send(socket, { "getServerType" })
        local event, data
        repeat
            event, data = os.pullEvent("gotServerType")
        until event == "gotServerType"
        log("serverType: " .. tostring(data))
        --cryptoNet.send(socket, "Hello server!")
        if data == "StorageServer" then
            getStorageServerCert()
            cryptoNet.send(socket, { "storageServer" })
            if settings.get("crafting") then
                print("Connecting to server: " .. settings.get("CraftingServer"))
                log("Connecting to server: " .. settings.get("CraftingServer"))
                craftingServerSocket = cryptoNet.connect(settings.get("CraftingServer"))
                -- Log in with a username and password
                print("Logging into server:" .. settings.get("CraftingServer"))
                log("Logging into server:" .. settings.get("CraftingServer"))
                print("password: " .. password)
                cryptoNet.login(craftingServerSocket, username, password)
                --clear password from memory
                password = ""
            else
                --clear password from memory
                password = ""
                print("Loading Database")
                getItems()
                drawList()

                term.setBackgroundColor(colors.black)
                for i = 1, width, 1 do
                    term.setCursorPos(i, height)
                    term.write(" ")
                end

                while true do
                    inputHandler()
                    sleep(0.1)
                end
            end
        elseif data == "CraftingServer" then
            getCraftingServerCert()
            cryptoNet.send(socket, { "craftingServer" })
            print("Loading Database")
            getItems()
            print("Loading Recipes")
            getRecipes()
            drawList()

            term.setBackgroundColor(colors.black)
            for i = 1, width, 1 do
                term.setCursorPos(i, height)
                term.write(" ")
            end

            while true do
                inputHandler()
                sleep(0.1)
            end
        end
    elseif event[1] == "login_failed" then
        -- Login failed (wrong username or password)
        print("Login Failed")
    elseif event[1] == "plain_message" then
        local messageType = event[2][1]
        local message = event[2][2]
        if messageType == "getRecipes" then
            if type(message) == "table" then
                table.sort(message, function(a, b)
                    return a.name < b.name
                end)
                recipes = message
                os.queueEvent("gotRecipes")
            else
                sleep(0.2)
                getRecipes()
            end
        elseif messageType == "getItems" then
            if type(message) == "table" then
                local tab = removeDuplicates(message)
                table.sort(
                    tab,
                    function(a, b)
                        return a.count > b.count
                    end
                )
                items = tab
                os.queueEvent("itemsUpdated")
            else
                sleep(0.5 + (math.random() % 0.2))
                getItems()
            end
        end
    elseif event[1] == "connection_closed" then
        --print(dump(event))
        --log(dump(event))
    elseif event[1] == "encrypted_message" then
        --log("Server said: " .. dump(event[2]))
        local messageType = event[2][1]
        local message = event[2][2]
        if messageType == "getItems" then
            if type(message) == "table" then
                local tab = removeDuplicates(message)
                table.sort(
                    tab,
                    function(a, b)
                        return a.count > b.count
                    end
                )
                items = tab
                os.queueEvent("itemsUpdated")
            else
                sleep(0.5 + (math.random() % 0.2))
                getItems()
            end
        elseif messageType == "import" then
            getItems()
        elseif messageType == "ping" then
            if type(message) == "string" and message == "ack" then
                os.queueEvent("storageServerAck")
            else
                sleep(0.5 + (math.random() % 0.2))
                pingStorageServer()
            end
        elseif messageType == "requireLogin" then
            --timeout no longer needed
            --timeoutConnect = nil
            --loginScreen()
            --print("Logging into server:" .. settings.get("StorageServer"))
            --log("Logging into server:" .. settings.get("StorageServer"))
            --cryptoNet.login(storageServerSocket, username, password)
            os.queueEvent("requireLogin", message)
        elseif messageType == "craftingUpdate" then
            os.queueEvent("craftingUpdate", message)
        elseif messageType == "getCertificate" then
            --log("gotCertificate from: " .. socket.sender .. " target:"  )
            os.queueEvent("gotCertificate", message)
        elseif messageType == "getItemDetails" then
            os.queueEvent("gotItemDetails", message)
        elseif messageType == "getServerType" then
            os.queueEvent("gotServerType", message)
        elseif messageType == "getAmount" then
            os.queueEvent("gotAmount", message)
        elseif messageType == "craftable" then
            os.queueEvent("gotCraftable", message)
        elseif messageType == "getNumNeeded" then
            os.queueEvent("gotNumNeeded", message)
        elseif messageType == "importAll" then
            os.queueEvent("importAllComplete")
        elseif messageType == "databaseReload" then
            os.queueEvent("databaseReloaded")
            getItems()
        end
    elseif event[1] == "timer" then
        if event[2] == timeoutConnect and (type(storageServerSocket) == "nil" or type(storageServerSocket.username) == "nil") then
            --Reboot after failing to connect
            cryptoNet.closeAll()
            os.reboot()
        end
    end
end

loadingScreen("Storage Client")

if not fs.exists("cryptoNet") then
    print("")
    print("cryptoNet API not found on disk, downloading...")
    local response = http.get(cryptoNetURL)
    if response then
        local file = fs.open("cryptoNet", "w")
        file.write(response.readAll())
        file.close()
        response.close()
        print("File downloaded as '" .. "cryptoNet" .. "'.")
    else
        print("Failed to download file from " .. cryptoNetURL)
    end
end

--sleep(0.5 + (math.random() % 1))
--broadcastStorageServer()
--sleep(0.5 + (math.random() % 1))
--broadcastCraftingServer()
--sleep(0.5 + (math.random() % 1))
os.loadAPI("cryptoNet")

if settings.get("StorageServer") == "StorageServer" or settings.get("StorageServer") == nil then
    discoverServers("StorageServer")
end

if settings.get("CraftingServer") == "CraftingServer" or settings.get("CraftingServer") == nil then
    discoverServers("CraftingServer")
end

cryptoNet.startEventLoop(onStart, onCryptoNetEvent)
cryptoNet.closeAll()
