math.randomseed(os.time() + (6 * os.getComputerID()))
local storage, items
local serverLAN, serverWireless
local tags = {}
local clients = {}
local slaves = {}
local recipes = {}
local storageServerSocket, masterCraftingServerSocket
local cryptoNetURL = "https://raw.githubusercontent.com/SiliconSloth/CryptoNet/master/cryptoNet.lua"
local detailDB
local currentlyCrafting = {}
local craftingUpdateClients = {}
local speakers = {}
local serverBootTime = os.epoch("utc") / 1000

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
os.loadAPI("cryptoNet")

-- Suppress IDE warnings
os.getComputerID = os.getComputerID
os.epoch = os.epoch
os.loadAPI = os.loadAPI
os.queueEvent = os.queueEvent
os.startThread = os.startThread
os.pullEvent = os.pullEvent
os.startTimer = os.startTimer
os.reboot = os.reboot
os.setComputerLabel = os.setComputerLabel
utf8 = utf8
cryptoNet = cryptoNet

-- Settings
settings.define("debug", {
    description = "Enables debug options",
    default = "false",
    type = "boolean"
})
-- Oneliner bash to extract recipes from craft tweaker output:
-- grep craftingTable crafttweaker.log > recipes
settings.define("recipeURL", {
    description = "The URL containing all recipes",
    "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/vanillaRecipes.txt",
    type = "string"
})
settings.define("recipeFile", {
    description = "The temp file used for loading recipes",
    "recipes",
    type = "string"
})
settings.define("craftingChest", {
    description = "The peripheral name of the crafting chest that is above the turtle",
    "minecraft:chest_3",
    type = "string"
})
settings.define("serverName", {
    description = "The hostname of this server",
    "CraftingServer" .. tostring(os.getComputerID()),
    type = "string"
})
settings.define("StorageServer", {
    description = "storage server hostname",
    default = "StorageServer",
    type = "string"
})
settings.define("requireLogin", {
    description = "require a login for LAN clients",
    default = "false",
    type = "boolean"
})
settings.define("isMasterCraftingServer", {
    description = "Defines master server vs slave server",
    default = "true",
    type = "boolean"
})
settings.define("masterCraftingServer", {
    description = "The hostname of the master crafting server",
    "CraftingServer",
    type = "string"
})

-- Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    print("Only vanilla recipes will be loaded, change the recipeURL in .settings for modded Minecraft")
    settings.set("serverName", "CraftingServer" .. tostring(os.getComputerID()))
    settings.set("StorageServer", "StorageServer")
    settings.set("debug", false)
    settings.set("isMasterCraftingServer", true)
    settings.set("masterCraftingServer", "CraftingServer")
    settings.set("requireLogin", false)
    settings.set("recipeURL",
        "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/vanillaRecipes.txt")
    settings.set("recipeFile", "recipes")
    settings.set("craftingChest", "minecraft:chest_3")
    print("Stop the server and edit .settings file with correct settings")
    settings.save()
    sleep(5)
end

-- Dumps a table to string
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

-- Logs text to log file
local function log(text)
    local logFile = fs.open("logs/craftingServer.log", "a")
    if type(text) == "string" then
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. text)
    else
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. textutils.serialise(text))
    end

    logFile.close()
end

-- Logs text only if debug mode is enabled
local function debugLog(text)
    if settings.get("debug") then
        local logFile = fs.open("logs/craftingServerDebug.log", "a")
        if type(text) == "string" then
            logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. text)
        else
            logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. textutils.serialise(text))
        end

        logFile.close()
    end
end

-- fixes tags entry in recipe causing textutils.serialise to throw error
local function cleanRecipe(table)
    local arr = {}
    -- print("size: " .. tostring(#table))
    for k, v in pairs(table) do
        local tab = {}
        tab.recipeType = v.recipeType
        tab.name = v.name
        tab.count = v.count
        tab.recipeName = v.recipeName
        tab.recipe = v.recipe
        tab.recipeInput = v.recipeInput
        tab.displayName = v.displayName
        -- tab.tags = v.tags
        -- No idea why this works
        local tag = textutils.serialize(v.tags)
        tab.tags = textutils.unserialise(tag)
        arr[#arr + 1] = tab
        -- print(tostring(k))
        -- debugLog("k: " .. tostring(k) .. " dump: " .. dump(tab))
        -- debugLog(textutils.serialize(tab))
    end
    return arr
end

-- These set of global functions are used when importing recipes
-- MUST be global
function addShaped(recipeName, name, arg3, arg4)
    -- print("name: " .. name)
    -- print("itemOutput: " .. itemOutput)
    local tab = {}
    local outputNumber = 1
    local recipe
    if arg4 then
        -- print("number of output: " .. tostring(arg3))
        -- print("recipe: " .. dump(arg4))

        outputNumber = arg3
        recipe = arg4
    else
        -- print("recipe: " .. dump(arg3))
        recipe = arg3
    end

    name = string.match(name, 'item:(.+)')

    tab["name"] = name
    tab["recipeName"] = recipeName
    tab["count"] = outputNumber

    tab["recipeType"] = "shaped"
    if type(recipe[1][1]) == "table" then
        tab["recipeInput"] = "variable"
        tab["recipe"] = recipe
    else
        tab["recipeInput"] = "static"
        -- Convert to variable recipe format
        for i = 1, #recipe, 1 do
            for j = 1, #recipe[i], 1 do
                recipe[i][j] = {recipe[i][j]}
            end
        end
        tab["recipe"] = recipe
    end

    recipes[#recipes + 1] = tab
end

-- MUST be global
function addShapeless(recipeName, name, arg3, arg4)
    local tab = {}
    local outputNumber = 1
    local recipe
    if arg4 then
        outputNumber = arg3
        recipe = arg4
    else
        recipe = arg3
    end

    name = string.match(name, 'item:(.+)')

    tab["name"] = name
    tab["recipeName"] = recipeName
    tab["count"] = outputNumber
    -- tab["recipe"] = recipe
    tab["recipeType"] = "shapeless"
    local isVar = false
    for i = 1, #recipe, 1 do
        if type(recipe[i]) == "table" then
            isVar = true
        end
    end
    if isVar then
        tab["recipeInput"] = "variable"
        recipe = recipe[1]

        -- Put every item into a table to have a uniform recipe
        for i = 1, #recipe, 1 do
            if type(recipe[i]) ~= "table" then
                recipe[i] = {recipe[i]}
            end
        end
    else
        tab["recipeInput"] = "static"
    end

    -- Convert to universal shaped variable recipe format

    local convertedRecipe = {{}, {}, {}}
    for row = 1, 3, 1 do
        for slot = 1, 3, 1 do
            if type(recipe[((row - 1) * 3) + slot]) == "nil" then
                convertedRecipe[row][slot] = {"none"}
            elseif isVar then
                convertedRecipe[row][slot] = recipe[((row - 1) * 3) + slot]
            else
                convertedRecipe[row][slot] = {recipe[((row - 1) * 3) + slot]}
            end
        end
    end
    tab["recipe"] = convertedRecipe

    if recipeName == "byg:fire_charge_from_byg_coals" then
        debugLog(textutils.serialise(tab))
    end

    recipes[#recipes + 1] = tab
end

-- MUST be global
craftingTable = {
    addShaped = addShaped,
    addShapeless = addShapeless
}

-- MUST be global
function getInstance()
    return "none"
end

-- MUST be global
IIngredientEmpty = {
    getInstance = getInstance
}

local craftingQueue = {}
craftingQueue.first = 0
craftingQueue.last = -1

function craftingQueue.pushleft(value)
    local first = craftingQueue.first - 1
    craftingQueue.first = first
    craftingQueue[first] = value
end

function craftingQueue.pushright(value)
    local last = craftingQueue.last + 1
    craftingQueue.last = last
    craftingQueue[last] = value
end

function craftingQueue.popleft()
    local first = craftingQueue.first
    if first > craftingQueue.last then
        error("craftingQueue is empty")
    end
    local value = craftingQueue[first]
    craftingQueue[first] = nil -- to allow garbage collection
    craftingQueue.first = first + 1
    return value
end

function craftingQueue.popright()
    local last = craftingQueue.last
    if craftingQueue.first > last then
        error("craftingQueue is empty")
    end
    local value = craftingQueue[last]
    craftingQueue[last] = nil -- to allow garbage collection
    craftingQueue.last = last - 1
    return value
end

function craftingQueue.dumpItems()
    -- This allows us to send the queue without socket information
    local last = craftingQueue.last
    local first = craftingQueue.first
    local tab = {}
    -- debugLog("craftingQueue.dump()")
    if craftingQueue.first > last then
        return tab
    end
    for i = first, last, 1 do
        local tmp = {}
        tmp.name = craftingQueue[i].name
        tmp.displayName = craftingQueue[i].displayName
        tmp.amount = craftingQueue[i].amount
        tmp.count = craftingQueue[i].count
        tmp.recipeType = craftingQueue[i].recipeType
        tmp.recipeInput = craftingQueue[i].recipeInput
        tmp.recipe = craftingQueue[i].recipe
        tmp.recipeName = craftingQueue[i].recipeName

        table.insert(tab, tmp)
    end
    debugLog(dump(tab))
    return tab
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

-- MUST be global
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

-- Creates a tab table using the tabs db, use this to avoid costly peripheral lookups
local function reconstructTags(itemName)
    local tab = {}
    tab.tags = {}
    for tag, nameTable in pairs(tags) do
        if type(nameTable) == "table" then
            for _, name in pairs(nameTable) do
                if name == itemName then
                    tab.tags[tag] = true
                end
            end
        end
    end
    return tab
end

-- Check if item name is in tag db
local function inTags(itemName)
    for _, nameTable in pairs(tags) do
        if type(nameTable) == "table" then
            for _, name in pairs(nameTable) do
                if name == itemName then
                    return true
                end
            end
        end
    end
    return false
end

-- Mantain tags lookup
local function addTag(item)
    -- print("addTag for: " .. item.name)

    -- Maintain tags count
    local countTags
    if type(tags.count) ~= "number" then
        countTags = 0
    else
        countTags = tags.count
    end

    -- Maintain item count
    local countItems
    if type(tags.countItems) ~= "number" then
        countItems = 0
    else
        countItems = tags.countItems
    end

    -- Get the tags which are keys in table item.details.tags
    local keyset = {}
    local n = 0
    if type(item.details) == "nil" then
        item.details = peripheral.wrap(item.chestName).getItemDetail(item.slot)
    end
    if type(item.details) ~= "nil" then
        for k, v in pairs(item.details.tags) do
            n = n + 1
            keyset[n] = k
        end
    end
    -- print(dump(keyset))

    -- Add them to tags table if they dont exist, if they exist add the item name to the list
    for i = 1, #keyset, 1 do
        if type(tags[keyset[i]]) == "nil" then
            print("Found new tag: " .. keyset[i])
            print("Found new item: " .. item.name)
            tags[keyset[i]] = {item.name}
            countTags = countTags + 1
            countItems = countItems + 1
        elseif table.contains(tags[keyset[i]], item.name) == false then
            print("Found new item: " .. item.name)
            table.insert(tags[keyset[i]], item.name)
            countItems = countItems + 1
        end
    end

    tags.count = countTags
    tags.countItems = countItems
end

local function getDatabaseFromServer()
    cryptoNet.send(storageServerSocket, {"getItems"})
    local event
    repeat
        event = os.pullEvent("itemsUpdated")
    until event == "itemsUpdated"
end

local function getDetailDBFromServer()
    cryptoNet.send(storageServerSocket, {"getDetailDB"})
    local event
    repeat
        event = os.pullEvent("detailDBUpdated")
    until event == "detailDBUpdated"

    local count = 0
    for _ in pairs(detailDB) do
        count = count + 1
    end

    print("Got " .. tostring(count) .. " items metadeta from storageserver")
    -- sleep(5)
end

local function pingServer()
    cryptoNet.send(storageServerSocket, {"ping"})

    local event
    repeat
        event = os.pullEvent("storageServerAck")
    until event == "storageServerAck"
end

local function Split(s, delimiter)
    local result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match);
    end
    return result;
end

-- Grab recipe file from an http source in crafttweaker output format and covert it to lua code
local function getRecipes()
    -- This whole thing is extremely jank to workaround limited CC storage
    print("Loading recipes...")
    print("Recipe URL set to: " .. settings.get("recipeURL"))
    local contents = http.get(settings.get("recipeURL"))

    local fileName = settings.get("recipeFile")
    -- local file = fs.open(fileName, "r")
    local lines = {}
    while true do
        -- local line = file.readLine()
        local line = contents.readLine()
        -- If line is nil then we've reached the end of the file and should stop
        if not line then
            break
        end

        lines[#lines + 1] = line
    end

    -- file.close()

    -- deal with the recipes that have multiple possible item inputs
    for i = 1, #lines, 1 do
        local line = lines[i]

        if string.find(line, '|') then
            table.remove(lines, i)

            local firstHalf = string.sub(line, 1, string.find(line, '%[') - 1)
            local recipe = ""
            if string.find(line, '%[%[') then
                recipe = string.sub(line, string.find(line, '%[') + 1, string.find(line, ');') - 3)
            else
                recipe = string.sub(line, string.find(line, '%['), string.find(line, ');') - 2)
            end

            local row = Split(recipe, '],')
            local newRecipes = {}

            -- Convert the string recipe into an array
            for k = 1, #row, 1 do
                -- cut out the first char which is [
                row[k] = string.sub(row[k], 2, #row[k])
                newRecipes[k] = {}
                local slot = Split(row[k], ',')

                for m = 1, #slot, 1 do
                    local inputs = Split(slot[m], '|')
                    newRecipes[k][m] = {}
                    for j = 1, #inputs, 1 do
                        newRecipes[k][m][j] = inputs[j]:gsub(' ', '')
                    end
                end
            end

            -- Rebuild the crafttweaker string with the new format
            local newLine = firstHalf .. '['
            for row2 = 1, #newRecipes, 1 do
                newLine = newLine .. '['
                for slot = 1, #newRecipes[row2], 1 do
                    if #newRecipes[row2][slot] == 1 then
                        if string.find(newRecipes[row2][slot][1], '%[') then
                            newRecipes[row2][slot][1] = '{' .. string.gsub(newRecipes[row2][slot][1], '%[', '') .. '}'
                        end
                        newLine = newLine .. newRecipes[row2][slot][1]
                    else
                        newLine = newLine .. '{'
                        for j = 1, #newRecipes[row2][slot] do
                            if string.find(newRecipes[row2][slot][j], '%[') then
                                newRecipes[row2][slot][j] = string.gsub(newRecipes[row2][slot][j], '%[', '')
                            end
                            newLine = newLine .. newRecipes[row2][slot][j]
                            if j ~= #newRecipes[row2][slot] then
                                newLine = newLine .. ','
                            end
                        end
                        newLine = newLine .. '}'
                    end
                    if slot ~= #newRecipes[row2] then
                        newLine = newLine .. ','
                    end
                end
                if row2 == #newRecipes then
                    newLine = newLine .. ']'
                else
                    newLine = newLine .. '],'
                end
            end
            newLine = newLine .. ']);'
            --[[
            if string.find(newLine, '"minecraft:torch"') then
                print(newLine)
            end
            --]]
            lines[#lines + 1] = newLine
        end
        lines[i] = line
    end

    -- Do a bunch of replacements to convert to lua code
    for i = 1, #lines, 1 do
        local line = lines[i]
        -- ignore recipes that need a tag or damage value
        if string.find(line, '|') or string.find(line, 'withTag') or string.find(line, 'withDamage') or
            string.find(line, 'withJsonComponent') then
            line = ""
        else
            line = string.gsub(line, "<", '"')
            line = string.gsub(line, ">", '"')
            line = string.gsub(line, '%[', '{')
            line = string.gsub(line, '%]', '}')
            line = string.gsub(line, ' %* ', ' ,')
            line = string.gsub(line, ';', '\n')
        end
        lines[i] = line
    end

    -- The file might be larger than the filesystem, so do it in small chunks
    local count = #lines
    local fileNumber = 1
    print("Number of lines " .. tostring(count))
    while count > 0 do
        local outFile = fs.open(tostring(fileNumber) .. fileName, "w")
        for i = 1, 100, 1 do
            if count > 0 then
                outFile.writeLine(lines[count])
                count = count - 1
            end
        end
        outFile.close()
        -- print(tostring(count))
        -- print(fileNumber)
        require(tostring(fileNumber) .. fileName)
        fs.delete(tostring(fileNumber) .. fileName)
        fileNumber = fileNumber + 1
    end

    -- Add the display name from detailDB we got from the storage server
    if type(detailDB) ~= "nil" then
        for i = 1, #recipes, 1 do
            if detailDB[recipes[i].name] ~= nil then
                recipes[i].displayName = detailDB[recipes[i].name].displayName
                recipes[i].tags = detailDB[recipes[i].name].tags
            elseif recipes[i].displayName == nil then
                recipes[i].displayName = ""
            end
        end
    end

    print(tostring(#recipes) .. " recipes loaded!")
end

local function searchForTag(string, InputTable, count)
    local find = string.find
    local match = string.match
    local stringTag = match(string, 'tag:%w+:(.+)')
    local number = 0

    local returnV = nil
    local returnK
    for k, v in pairs(InputTable) do
        if v.details then
            if v.details.tags then
                -- print(stringTag .. " == " .. tostring(find(dump(v.details.tags),stringTag)))
                if v.details.tags[stringTag] then
                    number = number + v.count
                end
                if v.details.tags[stringTag] and v.count >= count then
                    returnV = v
                    returnK = k
                end
            end
        end
    end
    return returnV, number, returnK
end

-- Returns matched item obj, total number in list and index of matched obj
local function search(searchTerm, InputTable, count)
    if string.find(searchTerm, "tag:") then
        return searchForTag(searchTerm, InputTable, count)
    else
        local stringSearch = string.match(searchTerm, 'item:(.+)')
        local find = string.find
        local number = 0
        local returnV = nil
        local returnK
        -- print("need " .. tostring(count) .. " of " .. stringSearch)
        for k, v in pairs(InputTable) do
            if (v["name"]) == (stringSearch) then
                number = number + v.count

                if v.count >= count then
                    -- print("Found: " .. tostring(v.count) .. " of " .. v.name)
                    returnV = v
                    returnK = k
                end
            end
        end
        return returnV, number, returnK
    end
end

local function searchForItemWithTag(string, InputTable)
    local filteredTable = {}
    local find = string.find
    local match = string.match
    local stringTag = match(string, 'tag:%w+:(.+)')

    for k, v in pairs(InputTable) do
        if v.details then
            if v.details.tags then
                if v.details.tags[stringTag] then
                    filteredTable[#filteredTable + 1] = v
                end
            end
        end
    end
    if filteredTable == {} then
        return {}
    else
        return filteredTable
    end
end

local function updateClient(socket, message, messageToSend)
    local table = {}
    table.type = "craftingUpdate"

    table.message = message
    if message == "slotUpdate" then
        table[1] = messageToSend[1]
        table[2] = messageToSend[2]
        table[3] = messageToSend[3]
        currentlyCrafting.table[messageToSend[1]][messageToSend[2]] = messageToSend[3]
    elseif message == "itemUpdate" or message == "logUpdate" then
        table[1] = messageToSend
        if message == "logUpdate" and currentlyCrafting.log ~= nil then
            currentlyCrafting.log[#currentlyCrafting.log + 1] = messageToSend
        elseif message == "itemUpdate" then
            currentlyCrafting.nowCrafting = messageToSend
            for row = 1, 3, 1 do
                currentlyCrafting.table[row] = {}
                for slot = 1, 3, 1 do
                    currentlyCrafting.table[row][slot] = 0
                end
            end
        end
    elseif type(message) == "boolean" then
        currentlyCrafting = {}
    end
    cryptoNet.send(socket, {"craftingUpdate", table})
    if message == "itemUpdate" or type(message) == "boolean" then
        -- Update any clients subscribed to crafting updates
        for k, v in pairs(craftingUpdateClients) do
            cryptoNet.send(v, {"craftingUpdate", table})
            cryptoNet.send(v, {"pushCurrentlyCrafting", currentlyCrafting})
            cryptoNet.send(v, {"pushCraftingQueue", craftingQueue.dumpItems()})
        end
    end
end

-- Calculate number of each item needed.
local function calculateNumberOfItems(recipe, amount)
    if type(amount) == "nil" then
        amount = 1
    end
    if type(recipe) == "nil" then
        return {}
    end
    local numNeeded = {}
    for row = 1, #recipe do
        for slot = 1, #recipe[row], 1 do
            for itemSlot = 1, #recipe[row][slot], 1 do
                if recipe[row][slot][itemSlot] ~= "none" and recipe[row][slot][itemSlot] ~= "item:minecraft:air" then
                    local recipeItemName = recipe[row][slot][itemSlot]
                    -- print(dump(recipeName))
                    if type(recipeItemName) ~= "nil" and recipeItemName ~= "nil" then
                        if type(numNeeded[recipeItemName]) == "nil" then
                            numNeeded[recipeItemName] = amount
                        else
                            numNeeded[recipeItemName] = numNeeded[recipeItemName] + amount
                        end
                    end
                end
            end
        end
    end
    debugLog("calculateNumberOfItems: " .. dump(numNeeded))
    return numNeeded
end

-- Checks if crafting materials are in system
local function haveCraftingMaterials(tableOfRecipes, amount, socket)
    if type(socket) == "nil" then
        socket = storageServerSocket
    end
    debugLog("haveCraftingMaterials")
    -- debugLog(tableOfRecipes)
    debugLog("amount:" .. tostring(amount))
    if type(amount) == "nil" then
        amount = 1
    end
    -- log(tableOfRecipes)
    local recipeIsCraftable = {}
    -- print("Found " .. tostring(#tableOfRecipes) .. " recipes")
    -- print(dump(tableOfRecipes))

    local num = 1
    for _, tab in pairs(tableOfRecipes) do
        local recipe = tab.recipe
        -- print(textutils.serialise(recipe))
        -- log(textutils.serialise(recipe))
        -- sleep(5)
        local craftable = true

        debugLog("haveCraftingMaterials: numNeeded")
        local numNeeded = calculateNumberOfItems(recipe, amount)
        debugLog(dump(numNeeded))
        -- print(textutils.serialise(numNeeded))

        craftable = true
        for i = 1, #recipe, 1 do -- row
            local row = recipe[i]
            for k = 1, #row, 1 do -- slot
                local slot = row[k]
                local craftable2 = false
                for j = 1, #slot, 1 do -- item
                    local item = slot[j]

                    debugLog("item: " .. item)
                    debugLog("numNeeded[item]: " .. tostring(numNeeded[item]))
                    if type(numNeeded[item]) == "nil" then
                        return {}
                    end

                    if item == "none" or item == "item:minecraft:air" then
                        craftable2 = true
                    else
                        local result
                        local number = 0
                        if string.find(item, "tag:") then
                            result, number = searchForTag(item, items, numNeeded[item])
                        else
                            result, number = search(item, items, numNeeded[item])
                        end
                        debugLog("found " .. tostring(number) .. " need " .. tostring(numNeeded[item]))

                        -- If item with exact amount is found, or there is more than what we need
                        if number >= numNeeded[item] then
                            -- if "number" is >0 that means the item was found in the system
                            craftable2 = true
                        else
                            print(tostring(item:match(".+:(.+)")) .. ": Need: " .. tostring(numNeeded[item]) ..
                                      " Found: " .. tostring(number))
                            updateClient(socket, "logUpdate", tostring(item:match(".+:(.+)")) .. ": " ..
                                tostring(number) .. "/" .. tostring(numNeeded[item]))
                        end
                    end
                end
                if not craftable2 then
                    craftable = false
                end
            end
        end

        if craftable then
            recipeIsCraftable[num] = tab
            num = num + 1
        end
    end

    -- print(tostring(#recipeIsCraftable) .. " recipes are craftable")
    return recipeIsCraftable
end

-- unused, may remove
local function isTagCraftable(searchTerm, inputTable)
    local stringSearch = string.match(searchTerm, 'tag:%w+:(.+)')
    local itemsTmp = {}
    -- print("searchTerm: " .. searchTerm)
    if type(tags[stringSearch]) ~= "nil" then
        -- check tags database
        -- print("Checking tags database")
        for i, k in pairs(tags[stringSearch]) do
            itemsTmp[#itemsTmp + 1] = {}
            itemsTmp[#itemsTmp]["name"] = k
        end
    else
        itemsTmp = searchForItemWithTag(searchTerm, inputTable)
    end

    if type(itemsTmp) == nil then
        return false
    end
    -- print(dump(items))
    -- sleep(5)

    -- check if tag has crafting recipe
    local tab = {}
    for i = 1, #recipes, 1 do
        for k = 1, #itemsTmp, 1 do
            if (recipes[i].name == itemsTmp[k].name) then
                -- return recipes[i].name
                tab[#tab + 1] = recipes[i].name
            end
        end
    end
    if not next(tab) then
        return false
    else
        return true
    end
end

local function isCraftable(searchTerm)
    local tab = {}
    local stringSearch = string.match(searchTerm, 'item:(.+)')
    for i = 1, #recipes, 1 do
        if (recipes[i].name == stringSearch) then
            tab[#tab + 1] = recipes[i].name
        end
    end
    if not next(tab) then
        return false
    else
        return true
    end
end

local function reloadServerDatabase()
    cryptoNet.send(storageServerSocket, {"reloadStorageDatabase"})
end

-- Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    debugLog("Reloading database..")
    -- storage = getStorage()
    -- write("..")

    -- items, storageUsed = getList(storage)

    -- pingServer()
    reloadServerDatabase()
    -- cryptoNet.send(storageServerSocket, { "reloadStorageDatabase" })
    -- pingServer()

    -- getDatabaseFromServer()
    debugLog("wait for itemsUpdated")
    local event
    repeat
        event = os.pullEvent("itemsUpdated")
    until event == "itemsUpdated"

    -- write("done\n")
    -- write("Writing Tags Database....")

    if fs.exists("tags.db") then
        fs.delete("tags.db")
    end
    local tagsFile = fs.open("tags.db", "w")
    tagsFile.write(textutils.serialise(tags))
    tagsFile.close()
    -- write("done\n")
    -- print("Items loaded: " .. tostring(storageUsed))
    -- print("Tags loaded: " .. tostring(tags.count))
    -- print("Tagged Items loaded: " .. tostring(tags.countItems))
end

-- Returns the totals number of an item in turtle inventory
local function numInTurtle(itemName)
    local count = 0
    for i = 1, 16, 1 do
        local slotDetail = turtle.getItemDetail(i)
        if type(slotDetail) ~= "nil" then
            if slotDetail.name == itemName then
                count = count + slotDetail.count
            end
        end
    end
    return count
end

-- dumps turtle inventory to system
local function dumpAll(skipReload)
    if skipReload == nil then
        skipReload = false
    end
    local reload = false
    for i = 1, 16, 1 do
        local item = turtle.getItemDetail(i)
        if type(item) ~= "nil" then
            turtle.select(i)
            turtle.dropDown()
            reload = true
        end
    end
    if reload and storageServerSocket ~= nil and not skipReload then
        -- reloadStorageDatabase()
        -- cryptoNet.send(storageServerSocket, { "forceImport", settings.get("craftingImportChest") })

        -- local event
        -- repeat
        --    event = os.pullEvent()
        -- until event == "forceImport"

        local event
        repeat
            event = os.pullEvent("itemsUpdated")
        until event == "itemsUpdated"
    end
end

-- Play tune on speakers
local function playSounds(instrument, reversed)
    for i = 1, 3, 1 do
        local pitch
        if reversed then
            pitch = 24 - math.floor(24 / i)
        else
            pitch = math.floor(24 / i)
        end
        for speakerid = 1, #speakers, 1 do
            local speaker = peripheral.wrap(speakers[speakerid])
            speaker.playNote(instrument, 3, pitch)
        end
        -- sleep(0.2)
    end
end

local function playAudio(complete)
    local dfpwm = require("cc.audio.dfpwm")
    local audioFile
    if complete then
        audioFile = "craftingComplete.dfpwm"
    else
        audioFile = "craftingFailed.dfpwm"
    end

    local decoder = dfpwm.make_decoder()
    for chunk in io.lines(audioFile, 16 * 1024) do
        local buffer = decoder(chunk)
        for speakerid = 1, #speakers, 1 do
            local speaker = peripheral.wrap(speakers[speakerid])
            while not speaker.playAudio(buffer, 3) do
                os.pullEvent("speaker_audio_empty")
            end
        end
    end
end

local function getAllRecipes(itemName)
    local allRecipes = {}
    for i = 1, #recipes, 1 do
        if recipes[i]["name"] == itemName then
            allRecipes[#allRecipes + 1] = recipes[i]
        end
    end
    return allRecipes
end

local function getAllTagRecipes(searchTerm)
    local stringSearch = string.match(searchTerm, 'tag:%w+:(.+)')
    local itemsTmp = {}
    -- print("searchTerm: " .. searchTerm)
    if type(tags[stringSearch]) ~= "nil" then
        -- check tags database
        -- print("Checking tags database")
        for i, k in pairs(tags[stringSearch]) do
            itemsTmp[#itemsTmp + 1] = {}
            itemsTmp[#itemsTmp]["name"] = k
        end
    else
        itemsTmp = searchForItemWithTag(searchTerm, recipes)
    end

    if type(itemsTmp) == nil then
        return {}
    end

    -- check if tag has crafting recipe
    local tab = {}
    for i = 1, #recipes, 1 do
        for k = 1, #itemsTmp, 1 do
            if (recipes[i].name == itemsTmp[k].name) then
                -- return recipes[i].name
                tab[#tab + 1] = recipes[i]
            end
        end
    end
    if not next(tab) then
        return {}
    else
        return tab
    end
end

local function recipeContains(recipe, itemName)
    debugLog("recipeContains itemName: " .. itemName)
    -- log(textutils.serialise(recipe))
    for i = 1, #recipe.recipe, 1 do -- row
        local row = recipe.recipe[i]
        for j = 1, #row, 1 do -- slot
            local slot = row[j]
            for k = 1, #slot, 1 do -- item
                local item = slot[k]
                -- log("recipeContains: " .. item .. ", " .. itemName)
                if item == itemName then
                    debugLog("recipeContains: true")
                    return true
                end
                if string.find(item, 'tag:(.+)') then
                    item = string.match(item, 'tag:(.+)')
                    if tags[itemName] == item then
                        debugLog("recipeContains: true")
                        return true
                    end
                end
                if string.find(item, 'item:(.+)') then
                    item = string.match(item, 'item:(.+)')
                end
                if item == itemName then
                    debugLog("recipeContains: true")
                    return true
                end
            end
        end
    end
    debugLog("recipeContains: false")
    return false
end

-- returns score, input recipe, name of recipe item output, time-to-live, amount of item output recipe creates
local function scoreBranch(recipe, itemName, ttl, amount, socket)
    local score = 0

    if type(amount) == "nil" then
        amount = 1
    end

    debugLog("scoreBranch: " .. textutils.serialise(itemName))
    -- print("scoreBranch: " .. textutils.serialise(itemName))
    debugLog("ttl is " .. tostring(ttl))
    -- log(textutils.serialise(recipe))

    if ttl < 1 then
        -- print("ttl is 0")
        debugLog("ttl is 0")
        -- log(recipe)
        return 0
    end

    for i = 1, #recipe, 1 do -- row
        local row = recipe[i]
        for j = 1, #row, 1 do -- slot
            local slot = row[j]
            local skip = false
            for k = 1, #slot, 1 do -- item
                local item = slot[k]
                if item ~= "none" and item ~= "item:minecraft:air" and not skip then
                    debugLog("searching for: " .. textutils.serialise(item))
                    -- if item is in the system, increase score
                    local searchResult
                    if string.find(item, "tag:") then
                        searchResult = searchForTag(item, items, 1)
                    elseif string.find(item, "item:(.+)") then
                        searchResult = search(item, items, 1)
                    else
                        searchResult = search(item, items, 1)
                    end

                    if type(searchResult) ~= "nil" then
                        -- print(item .. " found in system")
                        debugLog(item .. " found in system")
                        score = score + ((1 + ttl) * amount)
                        debugLog("score: " .. tostring(score))
                        -- no need to check the other possible items
                        skip = true
                        break
                    else
                        local allRecipes
                        ---need to check for tags
                        if string.find(item, 'tag:%w+:(.+)') then
                            allRecipes = getAllTagRecipes(item)
                        elseif string.find(item, "item:(.+)") then
                            allRecipes = getAllRecipes(string.match(item, 'item:(.+)'))
                        else
                            allRecipes = getAllRecipes(item)
                        end

                        if type(allRecipes) == "nil" then
                            print(item .. " is unknown to the system")
                            debugLog(item .. " is unknown to the system")
                            return 0
                        elseif #allRecipes < 1 then
                            print("no recipes found for: " .. item)
                            debugLog(("no recipes found for: " .. item))
                            updateClient(socket, "logUpdate", "no recipes: " .. tostring(item):match(".+:(.+)"))
                            return 0
                        end
                        local craftableRecipes = haveCraftingMaterials(allRecipes, 1, socket)

                        -- If recipe needs orginal item then skip recipe
                        for counting = 1, #craftableRecipes, 1 do
                            if recipeContains(craftableRecipes[counting], itemName) then
                                -- table.remove(craftableRecipes, craftableRecipes[counting])
                                craftableRecipes[counting] = nil
                            end
                        end

                        if #craftableRecipes > 0 then
                            -- if it has a currently craftable recipe increase score
                            -- print(item .. " is currently craftable")
                            debugLog(item .. " is currently craftable")
                            score = score + ((1 + ttl) * amount)
                            debugLog("score: " .. tostring(score))
                            skip = true
                            break
                        else
                            -- if it has no currently craftable recipe, check all recipes
                            -- log("no currently craftable recipe, check all recipes for " .. item)
                            -- log(allRecipes)

                            local failed = true
                            for m = 1, #allRecipes, 1 do
                                if recipeContains(allRecipes[m], itemName) == false and
                                    recipeContains(allRecipes[m], item) == false then
                                    debugLog("checking recipe: " .. allRecipes[m].name .. " from: " ..
                                                 allRecipes[m].recipeName)
                                    ttl = ttl - 1
                                    local scoreTab = scoreBranch(allRecipes[m].recipe, allRecipes[m].name, ttl - 1,
                                        allRecipes[m].count, socket)
                                    if scoreTab > 0 then
                                        score = score + scoreTab
                                        debugLog("score: " .. tostring(score))
                                        skip = true
                                        failed = false
                                        break
                                    end
                                end
                            end
                            if failed then
                                print("No recipe found for " .. item)
                                debugLog("No recipe found for " .. item)
                                return score
                            end
                        end
                    end
                end
            end
        end
    end

    ttl = ttl - 1
    -- score = score + ttl
    debugLog("return score: " .. tostring(score))
    return score
end

-- Try to find best recipe from a list of recipes using a scoring system
local function getBestRecipe(allRecipes, id)
    local bestRecipe
    local bestScore = 0
    local bestCount = 1
    for i = 1, #allRecipes, 1 do
        local score = scoreBranch(allRecipes[i].recipe, allRecipes[i].name, 20, allRecipes[i].count, id)
        debugLog("recipe: " .. allRecipes[i].recipeName .. " score: " .. score)
        if score > bestScore then
            bestRecipe = allRecipes[i]
            bestScore = score
            bestCount = allRecipes[i].count
        end
    end

    if bestScore == 0 then
        debugLog("uncraftable")
        return 0, 0
    end
    -- print("Recipe score: " .. tostring(bestScore))
    debugLog("Recipe score: " .. tostring(bestScore))

    return bestRecipe, bestCount
end

-- Avoid costly database reload by patching database in memory
local function patchStorageDatabase(itemName, count, chest, slot)
    if count == 0 or itemName == nil or chest == nil or slot == nil then
        return false
    end
    -- print("Patching database item:" .. itemName .. " by #" .. tostring(count) .. " chest:" .. chest .. " slot:" .. tostring(slot))
    debugLog("Patching database item:" .. itemName .. " by #" .. tostring(count) .. " chest:" .. chest .. " slot:" ..
                 tostring(slot))
    local stringSearch
    -- Strip out the item: from the front of the item name
    if string.find(itemName, 'item:(.+)') then
        stringSearch = string.match(itemName, 'item:(.+)')
    else
        stringSearch = itemName
    end
    if type(stringSearch) == "nil" then
        stringSearch = itemName
    end

    local savedDetails = {}

    for k, v in pairs(items) do
        if v.name == stringSearch then
            if v.chestName == chest then
                if v.slot == slot then
                    items[k].count = items[k].count + count
                    if items[k].count < 1 then
                        -- If there is 0 items, delete from list
                        table.remove(items, k)
                    end
                    return true
                end
            end
            if not next(savedDetails) then
                savedDetails = v.details
            end
        end
    end

    -- If we managed to capture details from other slots, create new entry in list
    if next(savedDetails) then
        local tmp = {}
        tmp.count = count
        tmp.slot = slot
        tmp.details = savedDetails
        tmp.name = itemName
        tmp.chestName = chest
        table.insert(items, tmp)
        -- dumpItems()
        return true
    end

    -- Patching failed, fallback to full reload
    getDatabaseFromServer()
    return false
end

local function pullItems(craftingChest, chestName, slot, moveCount, itemName)
    tmp = {}
    tmp.craftingChest = craftingChest
    tmp.chestName = chestName
    tmp.slot = slot
    -- tmp.moveCount = moveCount
    tmp.name = itemName
    -- cryptoNet.send(storageServerSocket, { "pullItems", tmp })
    -- local event
    -- local moved = 0
    -- repeat
    --    event, moved = os.pullEvent("gotPullItems")
    -- until event == "gotPullItems"
    -- getDatabaseFromServer()
    -- cryptoNet.send(storageServerSocket, { "getItems" })

    local itemToBeMoved = peripheral.wrap(chestName).list()[slot]

    if itemToBeMoved == nil then
        print("Tried to get from empty slot")
        debugLog("Tried to get from empty slot")
        return 0
    end
    if itemToBeMoved.name ~= itemName then
        print("Tried to get wrong item: " .. itemToBeMoved.name)
        debugLog("Tried to get wrong item: " .. itemToBeMoved.name)
        -- debugLog("itemToBeMoved: " .. dump(itemToBeMoved))
        return 0
    end
    local moved = peripheral.wrap(craftingChest).pullItems(chestName, slot, moveCount)
    tmp.count = -1 * moved

    --[[
    local itemMoved = peripheral.wrap(settings.get("craftingChest")).list()[1]
    debugLog("itemMoved: " .. dump(itemMoved))
    if itemMoved.name ~= itemName then
        print("Moved wrong item! expected: " .. itemName .. " got:" .. itemMoved.name)
    end
    if itemMoved.count ~= moveCount then
        print("Moved wrong amount of item! expected: " .. tostring(moveCount) .. " got:" ..itemMoved.count )
    end
    --]]
    -- Patch db on both servers at the same time
    cryptoNet.send(storageServerSocket, {"patchStorageDatabase", tmp})
    local patchstatus = patchStorageDatabase(itemName, -1 * moved, chestName, slot)
    return moved
end

-- Get items and craft
local function craftRecipe(recipeObj, timesToCraft, socket)
    local recipe = recipeObj.recipe
    getDatabaseFromServer()
    updateClient(socket, "itemUpdate", recipeObj.name)
    -- debugLog("craftRecipe")
    -- debugLog(recipeObj)
    -- debugLog("timesToCraft:" .. tostring(timesToCraft) .. " id:" .. tostring(socket))

    -- amount and id is optional
    if type(timesToCraft) == "nil" then
        timesToCraft = 1
    end
    if type(socket) == "nil" then
        socket = os.getComputerID()
    end

    local outputAmount = timesToCraft * recipeObj.count

    -- Check if any materials are stack limited
    local stackLimited = false
    local stackLimit = 64
    for row = 1, #recipe do
        for slot = 1, #recipe[row], 1 do
            -- ignore empty slots
            if recipe[row][slot][1] ~= "none" and recipe[row][slot][1] ~= "item:minecraft:air" then
                local searchResult = {}
                for k = 1, #recipe[row][slot], 1 do
                    -- Find a sample of the item in system
                    searchResult[k] = search(recipe[row][slot][k], items, 1)
                    if type(searchResult[k]) ~= "nil" then
                        local itemDetail
                        -- Save some time if item is in detaildb
                        if detailDB[searchResult[k].name] ~= nil then
                            itemDetail = detailDB[searchResult[k]]
                        else
                            itemDetail = peripheral.wrap(searchResult[k].chestName).getItemDetail(searchResult[k].slot)
                        end
                        if type(itemDetail) ~= "nil" then
                            local maxCount = itemDetail.maxCount
                            if maxCount < 64 then
                                stackLimited = true
                                -- Update new stack limit
                                if maxCount < stackLimit then
                                    -- stack limit will always be the stack limit of the smallest stack limited item
                                    stackLimit = maxCount
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- debugLog("stackLimited: " .. tostring(stackLimited) .. " stackLimit:" .. tostring(stackLimit))

    -- calculate number of items to be moved at once
    local moveCount = timesToCraft
    if stackLimited then
        moveCount = stackLimit
    elseif moveCount > 64 then
        moveCount = 64
    end
    -- debugLog("moveCount:" .. tostring(moveCount))

    -- In case of garbage in the turtle's inventory
    dumpAll(true)

    -- Moving materials to crafting grid
    local crafted = 0
    local craftingChest = settings.get("craftingChest")
    while outputAmount > crafted do
        -- Makes sure not to overcraft
        if (outputAmount - crafted) < moveCount then
            moveCount = (outputAmount - crafted)
        end
        -- tracks if the crafting cannot continue and should bail
        local failed = false
        for row = 1, #recipe do
            for slot = 1, #recipe[row], 1 do
                if recipe[row][slot][1] ~= "none" and recipe[row][slot][1] ~= "item:minecraft:air" then
                    if not failed then
                        -- Select the slot in the turtle, the turtle is 4x4 but crafting grid is 3x3
                        turtle.select(((row - 1) * 4) + slot)

                        -- table of items in the system that matched the requirements
                        local searchResults = {}
                        -- table of total items in the system
                        local insystem = {}
                        -- table of indexes of global "items" that match searchResult
                        local indexs = {}
                        -- keeps track of if at least one required item was found
                        local found = false
                        -- keeps track of if a substitution was found
                        local foundIndexs = {}
                        local lastGoodIndex = 0

                        -- This handles recipes that can have substitutions
                        debugLog("This handles recipes that can have substitutions")
                        local debug = settings.get("debug")
                        for k = 1, #recipe[row][slot], 1 do
                            searchResults[k], insystem[k], indexs[k] = search(recipe[row][slot][k], items, moveCount)
                            if debug then
                                debugLog("searchResults[k]: " .. textutils.serialize(searchResults[k]))
                                local itemToBeMoved =
                                    peripheral.wrap(searchResults[k].chestName).list()[searchResults[k].slot]
                                debugLog("itemToBeMoved: " .. textutils.serialize(itemToBeMoved))
                            end
                            if type(searchResults[k]) ~= "nil" then
                                found = true
                                foundIndexs[k] = true
                            else
                                foundIndexs[k] = false
                            end
                            if insystem[k] > moveCount then
                                found = true
                                lastGoodIndex = k
                            end
                            -- debugLog("insystem[k]:" .. tostring(insystem[k]) .. " moveCount:" .. tostring(moveCount))
                        end

                        -- Try again
                        if found == false then
                            reloadStorageDatabase()
                            for k = 1, #recipe[row][slot], 1 do
                                searchResults[k], insystem[k], indexs[k] =
                                    search(recipe[row][slot][k], items, moveCount)
                                if type(searchResults[k]) ~= "nil" then
                                    found = true
                                    foundIndexs[k] = true
                                else
                                    foundIndexs[k] = false
                                end
                                if insystem[k] > moveCount then
                                    found = true
                                    lastGoodIndex = k
                                end
                                debugLog("insystem[k]:" .. tostring(insystem[k]) .. " moveCount:" .. tostring(moveCount))
                            end
                        end

                        if found == false then
                            -- no sutiable item found in system
                            for j = 1, #foundIndexs, 1 do
                                if not foundIndexs[j] then
                                    print("craftRecipe: Cannot find enough " .. recipe[row][slot][j] .. " in system")
                                    debugLog(
                                        ("craftRecipe: Cannot find enough " .. recipe[row][slot][j] .. " in system"))
                                    updateClient(socket, "logUpdate",
                                        "Not enough " .. recipe[row][slot][j]:match(".+:(.+)") .. " in system")
                                end
                            end
                            dumpAll(true)
                            failed = true
                        else
                            -- item was found in system
                            local searchResult, index, foundIndex

                            for k = 1, #searchResults, 1 do
                                -- Get the first good result
                                if type(searchResults[k]) ~= "nil" then
                                    searchResult = searchResults[k]
                                    index = indexs[k]
                                    foundIndex = k
                                    break
                                end
                            end

                            -- If there is enough in the system but not in one slot then searchResult will be nil here
                            if type(searchResult) == "nil" then
                                searchResult = search(recipe[row][slot][lastGoodIndex], items, 1)
                            end

                            -- Move the items from the system to crafting chest
                            debugLog("Move the items from the system to crafting chest")
                            debugLog(textutils.serialize(searchResult))
                            print("Getting: " .. searchResult.name:match(".+:(.+)"))
                            debugLog("Getting: " .. searchResult.name)
                            updateClient(socket, "logUpdate", searchResult.name:match(".+:(.+)"))
                            -- local itemsMoved = peripheral.wrap(craftingChest).pullItems(searchResult["chestName"], searchResult["slot"], moveCount)
                            local itemsMoved = pullItems(craftingChest, searchResult["chestName"], searchResult["slot"],
                                moveCount, searchResult.name)
                            -- debugLog("itemsMoved: " .. tostring(itemsMoved))
                            while itemsMoved < moveCount do
                                -- try again
                                local itemsLeft = moveCount - itemsMoved
                                debugLog("try again: itemsMoved:" .. tostring(itemsMoved) .. " < moveCount:" ..
                                             tostring(moveCount) .. " Items left:" .. tostring(itemsLeft))
                                reloadStorageDatabase()
                                -- use same item as searchResult to avoid stacking issues
                                local newSearchResult = search("item:" .. searchResult.name, items, itemsLeft)
                                if type(newSearchResult) == "nil" then
                                    -- try to find just 1
                                    newSearchResult = search("item:" .. searchResult.name, items, 1)
                                    if type(newSearchResult) == "nil" then
                                        print("Failed to move item: " .. searchResult.name)
                                        debugLog("Failed to move item: " .. searchResult.name)
                                        updateClient(socket, "logUpdate",
                                            "Failed move: " .. searchResult.name:match(".+:(.+)"))
                                        failed = true
                                        break
                                    else
                                        itemsLeft = 1
                                    end
                                end
                                -- local newItemsMoved = peripheral.wrap(craftingChest).pullItems(newSearchResult["chestName"], newSearchResult["slot"], itemsLeft)
                                local newItemsMoved = pullItems(craftingChest, newSearchResult["chestName"],
                                    newSearchResult["slot"], itemsLeft, newSearchResult.name)
                                -- Ask the server to reload database now that something has been changed
                                -- reloadServerDatabase()
                                itemsMoved = itemsMoved + newItemsMoved
                            end
                            -- Ask the server to reload database now that something has been changed
                            -- reloadServerDatabase()
                            -- Move items from crafting chest to turtle inventory
                            turtle.suckUp()
                            -- Check the items just moved
                            local slotDetail = turtle.getItemDetail()
                            if type(slotDetail) == "nil" then
                                print("failed to get item: " .. searchResult.name)
                                updateClient(socket, "logUpdate",
                                    "Failed getting: " .. searchResult.name:match(".+:(.+)"))
                                dumpAll(true)
                                failed = true
                                debugLog(searchResult)
                                break
                            else
                                -- debugLog("slotDetail:" .. textutils.serialise(slotDetail))
                                -- Send crafting status update to client
                                local table = {}
                                table[1] = row
                                table[2] = slot
                                table[3] = slotDetail.count
                                updateClient(socket, "slotUpdate", table)
                            end
                        end
                    end
                end
            end
        end

        if failed then
            dumpAll(true)
            return false
        else
            turtle.craft()
            local craftedItem = turtle.getItemDetail()

            if type(craftedItem) == "nil" then
                return false
            else
                -- crafted = crafted + craftedItem.count
                -- debugLog("recipeObj.name: " .. recipeObj.name .. " numInTurtle(recipeObj.name): " .. tostring(numInTurtle(recipeObj.name)))
                crafted = crafted + numInTurtle(recipeObj.name)
                -- Wait on storage system to be ready
                -- pingServer()
            end
            dumpAll()
        end

        debugLog("crafted:" .. tostring(crafted))
    end
    return true
end

-- Brute-force recersive crafting
local function craftBranch(recipeObj, ttl, amount, socket)
    if type(recipeObj) ~= "table" then
        return false
    end
    local recipe = recipeObj.recipe
    local itemName = recipeObj.name

    if type(amount) == "nil" then
        amount = 1
    end
    if type(socket) == "nil" then
        socket = storageServerSocket
    end

    -- Send item status update to client
    updateClient(socket, "craftingUpdate", itemName)
    debugLog("craftBranch: " .. textutils.serialise(itemName) .. " id:" .. tostring(socket))
    -- print("craftBranch: " .. textutils.serialise(itemName))
    -- log(textutils.serialise(recipe))
    -- print(textutils.serialise(recipe))

    if ttl < 1 then
        -- print("ttl is 0")
        debugLog("ttl is 0")
        -- log(recipe)
        return false
    end
    debugLog(tostring(ttl))

    local numNeeded = calculateNumberOfItems(recipe, amount)

    for k, v in pairs(numNeeded) do
        -- print("Need: " .. k .. " #" .. v)
        debugLog("numNeeded: " .. k .. " #" .. v)
    end

    local craftedAnything = false
    for i = 1, #recipe, 1 do -- row
        local row = recipe[i]
        for j = 1, #row, 1 do -- slot
            local slot = row[j]
            local skip = false
            for k = 1, #slot, 1 do -- item
                local item = slot[k]
                if item ~= "none" and item ~= "item:minecraft:air" and skip == false then
                    debugLog("processing: " .. tostring(numNeeded[item]) .. " " .. item)
                    -- if item is in the system
                    local searchResult
                    local have = 0
                    if string.find(item, "tag:") then
                        searchResult, have = searchForTag(item, items, numNeeded[item])
                    elseif string.find(item, "item:(.+)") then
                        searchResult, have = search(item, items, numNeeded[item])
                    else
                        searchResult, have = search(item, items, numNeeded[item])
                    end
                    debugLog(tostring(have) .. " found in system")

                    if type(searchResult) ~= "nil" or have >= numNeeded[item] then
                        -- Item was found in the system
                        -- print(item .. " found in system")
                        debugLog(item .. " found in system")
                        -- no need to check the other possible items
                        skip = true
                        break
                    else
                        debugLog("have: " .. tostring(have) .. " Need: " .. tostring(numNeeded[item]) .. " of " .. item)

                        local allRecipes
                        ---need to check for tags
                        if string.find(item, 'tag:%w+:(.+)') then
                            allRecipes = getAllTagRecipes(item)
                        elseif string.find(item, "item:(.+)") then
                            allRecipes = getAllRecipes(string.match(item, 'item:(.+)'))
                        else
                            allRecipes = getAllRecipes(item)
                        end

                        local missing = numNeeded[item] - have
                        if #allRecipes < 1 then
                            print("Cannot craft " .. itemName .. ": no recipes found for: " .. item)
                            updateClient(socket, "logUpdate", "Cannot craft " .. itemName:match(".+:(.+)"))
                            updateClient(socket, "logUpdate",
                                "Missing " .. tostring(missing) .. " " .. item:match(".+:(.+)"))
                            debugLog(("no recipes found for: " .. item))
                            return false
                        end
                        -- Remove existing amount
                        if have < numNeeded[item] then
                            numNeeded[item] = numNeeded[item] - have
                        else
                            -- We have enough
                            break
                        end
                        -- if numNeeded[item] > 64 then
                        --    numNeeded[item] = 64
                        -- end
                        local craftableRecipes = haveCraftingMaterials(allRecipes, numNeeded[item], socket)
                        if #craftableRecipes > 0 then
                            -- Get best recipe then craft it
                            -- print(item .. " is currently craftable")
                            debugLog(item .. " is currently craftable")

                            local recipeToCraft
                            local outputAmount = 1
                            -- get the best recipe
                            if #craftableRecipes > 1 then
                                -- print("More than one craftable recipe, Searching for best recipe")
                                debugLog("More than one craftable recipe, Searching for best recipe")
                                recipeToCraft, outputAmount = getBestRecipe(craftableRecipes, socket)
                            else
                                recipeToCraft = craftableRecipes[1]
                                outputAmount = craftableRecipes[1].count
                            end
                            -- log(recipeToCraft)
                            debugLog("numNeeded[item]: " .. tostring(numNeeded[item]))
                            debugLog("outputAmount: " .. tostring(outputAmount))
                            -- Send status update to client
                            updateClient(socket, "itemUpdate", item)
                            local status = craftRecipe(recipeToCraft, numNeeded[item], socket)
                            if status == false then
                                print("crafting failed")
                                debugLog("crafting failed")
                                updateClient(socket, "logUpdate", "crafting failed")
                                return false
                            else
                                debugLog("breaking")
                                craftedAnything = true
                                skip = true
                                break
                            end
                        else
                            -- if it has no currently craftable recipe, check all recipes
                            local failed = true
                            for m = 1, #allRecipes, 1 do
                                ttl = ttl - 1
                                if recipeContains(allRecipes[m], itemName) == false and
                                    recipeContains(allRecipes[m], item) == false then
                                    -- local result = craftBranch(allRecipes[m], ttl, numNeeded[item], id)
                                    local result = craftBranch(allRecipes[m], ttl,
                                        math.ceil(numNeeded[item] / allRecipes[m].count), socket)
                                    if result then
                                        failed = false
                                        craftedAnything = true
                                        break
                                    end
                                end
                            end
                            if failed then
                                -- print("got nothing for " .. item)
                                debugLog("got nothing for " .. item)
                                if k >= #slot then
                                    return false
                                end
                            else
                                skip = true
                            end
                        end
                    end
                end
            end
        end
    end

    debugLog("craftedAnything: " .. tostring(craftedAnything))
    local craft = false
    -- This is to ensure the materials needed to craft parent were not used in child recipe
    if craftedAnything then
        local tab = {}
        tab.recipe = recipe
        local craftable = haveCraftingMaterials({tab}, amount, socket)
        if #craftable < 1 then
            local status = craftBranch(recipeObj, ttl - 1, amount, socket)
            if status == false then
                print("failed")
                debugLog("failed")
                updateClient(socket, "logUpdate", "failed")
            end
            debugLog("This is to ensure the materials needed to craft parent were not used in child recipe: " ..
                         tostring(status))
            return status
        else
            craft = true
        end
    else
        craft = true
    end

    -- Craft parent item
    if craft then
        debugLog("Crafting Parent recipe: " .. itemName)
        -- Send status update to client
        updateClient(socket, "itemUpdate", itemName)
        local status
        status = craftRecipe(recipeObj, amount, socket)
        -- status = craftRecipe(recipeObj, math.ceil(amount / recipeObj.count), id)
        if status == false then
            print("crafting parent recipe failed")
            debugLog("crafting parent recipe failed")
            updateClient(socket, "logUpdate", "crafting parent recipe failed")
            return false
        end
        debugLog("Craft parent item: " .. tostring(status))
        return status
    end
end

-- Craft recipe assuming all materials are available
local function craft(item, amount, socket)
    getDatabaseFromServer()
    debugLog("craft")
    if type(socket) == "nil" then
        socket = storageServerSocket
    end

    local ttl = 20
    if type(amount) == "nil" then
        amount = 1
    end

    local allRecipes
    if type(item) == "string" then
        -- tag check
        debugLog("tag check")
        if string.find(item, 'tag:%w+:(.+)') then
            allRecipes = getAllTagRecipes(item)
            item = string.match(item, 'tag:%w+:(.+)')
        elseif string.find(item, "item:(.+)") then
            item = string.match(item, 'item:(.+)')
            allRecipes = getAllRecipes(item)
        else
            allRecipes = getAllRecipes(item)
        end
    elseif type(item) == "table" then
        allRecipes = {item}
    end

    -- If one of the recipes are craftable, craft it
    -- debugLog("If one of the recipes are craftable, craft it")
    local craftableRecipes = haveCraftingMaterials(allRecipes, 1, socket)
    local recipeToCraft

    -- print(tostring(#craftableRecipes))

    -- Otherwise get the best recipe
    -- debugLog("Otherwise get the best recipe")
    local outputAmount = 1
    if #craftableRecipes == 0 then
        -- print("No currently craftable recipes, Searching for best recipe")
        recipeToCraft, outputAmount = getBestRecipe(allRecipes, socket)
    elseif #craftableRecipes > 1 then
        -- print("More than one craftable recipe, Searching for best recipe")
        recipeToCraft, outputAmount = getBestRecipe(craftableRecipes, socket)
    else
        recipeToCraft = craftableRecipes[1]
        outputAmount = craftableRecipes[1].count
    end

    if type(recipeToCraft) == "nil" then
        if type(item) == "table" then
            print("No recipe found for: " .. tostring(item.name))
            updateClient(socket, "logUpdate", "No recipe: " .. tostring(item.name:match(".+:(.+)")))
        else
            print("No recipe found for: " .. tostring(item))
            updateClient(socket, "logUpdate", "No recipe: " .. tostring(item:match(".+:(.+)")))
        end
        return false
    end

    local failed = false
    print("Crafting: #" .. tostring(amount) .. " " .. tostring(item))
    -- print(dump(recipes[i].recipe))
    -- log(recipeToCraft)

    -- print(recipeToCraftInput .. " " .. recipeToCraftType .. " crafting recipe")

    debugLog("Craft: " .. tostring(item) .. ", " .. tostring(ttl) .. ", " .. tostring(amount))
    return craftBranch(recipeToCraft, ttl, math.ceil(amount / outputAmount), socket)
    -- return craftBranch(recipeToCraft, ttl, amount, id)
end

-- Consumes crafting jobs from the queue, runs on its own thread
local function craftingManager()
    while true do
        if craftingQueue.first ~= nil then
            -- check if the queue has anything in it
            if craftingQueue.first <= craftingQueue.last then
                local time = os.epoch("utc") / 1000
                local craftingRequest = craftingQueue.popleft()
                debugLog("craftingRequest.recipe: " .. textutils.serialise(craftingRequest.recipe))
                debugLog("craftingRequest.timesToCraft: " .. tostring(craftingRequest.timesToCraft))
                currentlyCrafting.name = craftingRequest.recipe.name
                currentlyCrafting.displayName = craftingRequest.recipe.displayName
                currentlyCrafting.amount = craftingRequest.recipe.amount
                currentlyCrafting.count = craftingRequest.recipe.count
                currentlyCrafting.recipeType = craftingRequest.recipe.recipeType
                currentlyCrafting.recipeInput = craftingRequest.recipe.recipeInput
                currentlyCrafting.recipe = craftingRequest.recipe.recipe
                currentlyCrafting.recipeName = craftingRequest.recipe.recipeName
                currentlyCrafting.nowCrafting = craftingRequest.recipe.recipeName
                currentlyCrafting.log = {}
                currentlyCrafting.table = {}

                for row = 1, 3, 1 do
                    currentlyCrafting.table[row] = {}
                    for slot = 1, 3, 1 do
                        currentlyCrafting.table[row][slot] = 0
                    end
                end

                -- reloadStorageDatabase()
                local ableToCraft = false
                if craftingRequest.autoCraft then
                    ableToCraft = craft(craftingRequest.recipe, craftingRequest.timesToCraft, craftingRequest.socket)
                    --[[
                    if ableToCraft == false then
                        print("Crafting Failed!")
                        --try again
                        print("Trying to craft again")
                        reloadStorageDatabase()
                        ableToCraft = craft(craftingRequest.recipe, craftingRequest.timesToCraft, craftingRequest.socket)
                    end
                    --]]
                else
                    ableToCraft = craftRecipe(craftingRequest.recipe, craftingRequest.timesToCraft,
                        craftingRequest.socket)
                end

                -- Report to client
                if ableToCraft then
                    print("Crafting Successful")
                    -- cryptoNet.send(socket, { "craftingUpdate", true })
                    updateClient(craftingRequest.socket, true)
                    -- playSounds("bell", false)
                    playAudio(true)
                else
                    print("Crafting Failed!")
                    -- cryptoNet.send(socket, { "craftingUpdate", false })
                    updateClient(craftingRequest.socket, false)
                    -- playSounds("cow_bell", true)
                    playAudio(false)
                end
                currentlyCrafting = {}
                local speed = (os.epoch("utc") / 1000) - time
                print("Craft took " .. tostring(("%.3g"):format(speed) .. " seconds total"))
                debugLog("Craft took " .. tostring(speed) .. " seconds total")
            end
        end
        sleep(0.5)
    end
end

local function debugMenu()
    while true do
        print("Main menu")

        local input = io.read()
        if input == "list" then
            for i = 1, #recipes, 1 do
                print(recipes[i].name)
            end
        elseif input == "craft" then
            print("Enter item name:")
            local input2 = io.read()
            print("Enter Amount:")
            local amount = tonumber(io.read())
            if string.find(input2, ':') then
                -- print("Crafting: " .. (input2))
                reloadStorageDatabase()
                local ableToCraft = craft(input2, amount)
                if ableToCraft then
                    print("Crafting Successful")
                else
                    print("Crafting Failed!")
                end
            else
                for i = 1, #recipes, 1 do
                    if string.find(recipes[i].name, input2) then
                        -- print("Crafting: " .. (recipes[i].name))
                        reloadStorageDatabase()
                        local ableToCraft = craft(recipes[i], amount)
                        if ableToCraft then
                            print("Crafting Successful")
                        else
                            print("Crafting Failed!")
                        end
                        return
                    end
                end
            end
        elseif input == "find" then
            local input2 = io.read()
            for i = 1, #recipes, 1 do
                if string.find(recipes[i].name, input2) then
                    print(dump(recipes[i]))
                    -- log(dump(recipes[i]))
                end
            end
        elseif input == "exit" then
            os.queueEvent("terminate")
        end
        sleep(1)
    end
end

-- Logs in using password hash
-- This allows multiple servers to use a central server as an auth server by passing the hash
local function login(socket, user, pass, servername)
    -- Check if wireless server
    local startIndex, endIndex = string.find(servername, "_Wireless")
    if startIndex then
        -- get the server name by cutting out "_Wireless"
        servername = string.sub(servername, 1, startIndex - 1)
        log("wireless server rename: " .. servername)
    else
        log("servername " .. servername)
    end

    local tmp = {}
    tmp.username = user
    tmp.password = pass
    tmp.servername = servername
    -- mark for garbage collection
    pass = nil
    -- log("hashLogin")
    cryptoNet.send(socket, {"hashLogin", tmp})
    -- mark for garbage collection
    tmp = nil
    local event
    local loginStatus = false
    local permissionLevel = 0
    repeat
        event, loginStatus, permissionLevel = os.pullEvent("hashLogin")
    until event == "hashLogin"
    log("loginStatus:" .. tostring(loginStatus))
    if loginStatus == true then
        socket.username = user
        socket.permissionLevel = permissionLevel
        os.queueEvent("login", user, socket)
        -- Register as slave crafting server
        cryptoNet.send(socket, {"registerSlaveServer"})
        debugLog("Successfully logged in")
    else
        term.setCursorPos(1, 1)
        debugLog("Failed login")
        error("Failed to login to Server")
    end

    return socket
end

-- Cryptonet event handler
local function onCryptoNetEvent(event)
    -- When a crafting server logs in to storage server
    if event[1] == "login" and not next(recipes) then
        local username = event[2]
        -- The socket of the client that just logged in
        local socket = event[3]
        -- The logged-in username is also stored in the socket
        print("Login successful using " .. socket.username)
        os.queueEvent("storageServerLogin")
        -- If this is a slave crafting server, login to master crafting server
        if not settings.get("isMasterCraftingServer") and masterCraftingServerSocket == nil then
            print("Connecting to master server: " .. settings.get("MasterCraftingServer"))
            log("Connecting to master server: " .. settings.get("MasterCraftingServer"))
            masterCraftingServerSocket = cryptoNet.connect(settings.get("MasterCraftingServer"))
            -- Log in with a username and password
            print("Logging into master server:" .. settings.get("MasterCraftingServer"))
            log("Logging into master server:" .. settings.get("MasterCraftingServer"))

            login(masterCraftingServerSocket, settings.get("username"), settings.get("password"),
                settings.get("StorageServer"))
        end
    elseif event[1] == "login" or event[1] == "hash_login" then
        local username = event[2]
        -- The socket of the client that just logged in
        local socket = event[3]
        -- The logged-in username is also stored in the socket
        print(socket.username .. " just logged in.")
    elseif event[1] == "login_failed" then
        -- Login failed (wrong username or password)
        print("Login Failed")
    elseif event[1] == "plain_message" then
        local message = event[2][1]
        local data = event[2][2]
        local socket = event[3]
        debugLog("message: " .. message)
        -- Check the username to see if the client is logged in or should have an exception
        if socket.username ~= nil or (not settings.get("requireLogin") and socket.sender == settings.get("serverName")) or
            socket.target == settings.get("StorageServer") then
            if message == "getItems" then
                if type(data) == "table" then
                    items = data
                    for k, v in pairs(data) do
                        if not (inTags(v.name)) then
                            if type(data[k]["details"]) == "nil" then
                                data[k]["details"] = peripheral.wrap(v.chestName).getItemDetail(v.slot)
                            end
                            addTag(data[k])
                        else
                            data[k]["details"] = reconstructTags(v.name)
                        end
                    end

                    os.queueEvent("itemsUpdated")
                else
                    sleep(math.random() % 0.2)
                    return getDatabaseFromServer()
                end
            elseif message == "getDetailDB" then
                detailDB = data
                os.queueEvent("detailDBUpdated")
            elseif message == "ping" then
                if type(data) == "string" and data == "ack" then
                    os.queueEvent("storageServerAck")
                else
                    sleep(0.5 + (math.random() % 0.2))
                    pingServer()
                end
            elseif message == "requireLogin" then
                cryptoNet.send(socket, {message, settings.get("requireLogin")})
            end
        else
            -- User is not logged in
            cryptoNet.send(socket, "Sorry, I only talk to logged in users.")
        end
    elseif event[1] == "encrypted_message" then
        local socket = event[3]
        debugLog("encrypted_message: " .. dump(event[2]))
        -- Check the username to see if the client is logged in or should have an exception
        if (socket.username ~= nil or (not settings.get("requireLogin") and socket.sender == settings.get("serverName")) or
            socket.target == settings.get("StorageServer")) and event[2][1] ~= "hashLogin" then
            local message = event[2][1]
            local data = event[2][2]
            if socket.username == nil then
                if socket.target == settings.get("StorageServer") then
                    socket.username = socket.target
                else
                    socket.username = "LAN Host"
                end
            end
            -- print(socket.username .. " requested: " .. tostring(message))
            log("User: " .. socket.username .. " Client: " .. socket.target .. "Sender: " .. socket.sender ..
                    " request: " .. tostring(message))
            -- log(socket.name)
            -- log(socket.channel)
            -- log("Sender: " .. socket.sender)
            -- log(socket.name)
            if message == "storageCraftingServer" then
                cryptoNet.send(socket, {message, settings.get("serverName")})
                local uniq = true
                for i in pairs(clients) do
                    if clients[i] == socket then
                        uniq = false
                    end
                end
                if uniq then
                    clients[#clients + 1] = socket
                end
                print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
                local count = 0
                for _ in pairs(clients) do
                    count = count + 1
                end
                print("Clients: " .. tostring(count))
                for i in pairs(clients) do
                    print(
                        tostring(clients[i].username) .. ":" .. string.sub(tostring(clients[i].sender), 1, 5) .. ":" ..
                            tostring(clients[i].target))
                end
                print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
            elseif message == "registerSlaveServer" then
                cryptoNet.send(socket, {message, settings.get("serverName")})
                local uniq = true
                for i in pairs(slaves) do
                    if slaves[i] == socket then
                        uniq = false
                    end
                end
                if uniq then
                    slaves[#slaves + 1] = socket
                end
                print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
                local count = 0
                for _ in pairs(slaves) do
                    count = count + 1
                end
                print("Slaves: " .. tostring(count))
                for i in pairs(slaves) do
                    print(tostring(slaves[i].username) .. ":" .. string.sub(tostring(slaves[i].sender), 1, 5) .. ":" ..
                              tostring(slaves[i].target))
                end
                print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
            elseif message == "getServerType" then
                cryptoNet.send(socket, {message, "CraftingServer"})
            elseif message == "isMainCraftingServer" then
                if settings.get("isMasterCraftingServer") then
                    cryptoNet.send(socket, {message, true})
                else
                    cryptoNet.send(socket, {message, false})
                end
            elseif message == "requireLogin" then
                -- timeout no longer needed
                timeoutConnect = nil
                print("Logging into server:" .. settings.get("StorageServer"))
                log("Logging into server:" .. settings.get("StorageServer"))
                cryptoNet.login(storageServerSocket, settings.get("username"), settings.get("password"))
            elseif message == "databaseReload" then
                -- os.startThread(getDatabaseFromServer)
                getDatabaseFromServer()
            elseif message == "forceImport" then
                os.queueEvent("forceImport")
            elseif message == "getRecipes" then
                cryptoNet.sendUnencrypted(socket, {message, recipes})
            elseif message == "getCraftingQueue" then
                -- debugLog("getCraftingQueue")
                cryptoNet.send(socket, {message, craftingQueue.dumpItems()})
            elseif message == "getCurrentlyCrafting" then
                -- debugLog("getCurrentlyCrafting")
                cryptoNet.send(socket, {message, currentlyCrafting})
            elseif message == "craft" then
                print(socket.username .. " requested: " .. tostring(message))
                turtle.craft()
            elseif message == "craftItem" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Request to craft #" .. tostring(data.amount) .. " " .. data.name)
                debugLog("Request to craft #" .. tostring(data.amount) .. " " .. data.name)
                -- reloadStorageDatabase()
                debugLog("data: " .. textutils.serialize(data))

                local craftingRequest = {}
                craftingRequest.autoCraft = false
                craftingRequest.recipe = data
                craftingRequest.name = data.name
                craftingRequest.timesToCraft = math.ceil(data.amount / data.count)
                craftingRequest.socket = socket
                craftingQueue.pushright(craftingRequest)
            elseif message == "autoCraftItem" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Request to autocraft #" .. tostring(data.amount) .. " " .. data.name)
                debugLog("Request to autocraft #" .. tostring(data.amount) .. " " .. data.name)
                -- reloadStorageDatabase()

                local craftingRequest = {}
                craftingRequest.autoCraft = true
                craftingRequest.recipe = data
                craftingRequest.name = data.name
                craftingRequest.timesToCraft = math.ceil(data.amount / data.count)
                craftingRequest.socket = socket
                craftingQueue.pushright(craftingRequest)
            elseif message == "getAmount" then
                local _, number = search(data, items, 1)
                cryptoNet.send(socket, {message, number})
            elseif message == "getNumNeeded" then
                local amount = math.ceil(data.amount / data.count)
                cryptoNet.send(socket, {message, calculateNumberOfItems(data.recipe, amount)})
            elseif message == "craftable" then
                local item = data

                print("Checking if " .. item .. " is craftable")
                local allRecipes
                ---need to check for tags
                if string.find(item, 'tag:') then
                    allRecipes = getAllTagRecipes(item)
                elseif string.find(item, "item:") then
                    allRecipes = getAllRecipes(string.match(item, 'item:(.+)'))
                else
                    allRecipes = getAllRecipes(item)
                end

                if type(allRecipes) == "nil" then
                    print(item .. " is unknown to the system")
                    updateClient(socket, "logUpdate", "unknown item: " .. tostring(item):match(".+:(.+)"))
                    cryptoNet.send(socket, {message, false})
                elseif #allRecipes < 1 then
                    print("no recipes found for: " .. item)
                    updateClient(socket, "logUpdate", "no recipes: " .. tostring(item):match(".+:(.+)"))
                    cryptoNet.send(socket, {message, false})
                else
                    local craftableRecipes = haveCraftingMaterials(allRecipes, 1, socket)

                    if #craftableRecipes > 0 then
                        cryptoNet.send(socket, {message, craftableRecipes})
                    else
                        print("0 craftable recipes")
                        debugLog("0 craftable recipes")
                        local clean = cleanRecipe(allRecipes)
                        -- debugLog(textutils.serialize(clean, {false, true}))
                        cryptoNet.send(socket, {message, clean})
                        -- cryptoNet.send(socket, { message, {allRecipes[1]} })
                    end
                end
            elseif message == "getItems" then
                if type(data) == "table" then
                    items = data
                    for k, v in pairs(data) do
                        if not (inTags(v.name)) then
                            if type(data[k]["details"]) == "nil" then
                                data[k]["details"] = peripheral.wrap(v.chestName).getItemDetail(v.slot)
                            end
                            addTag(data[k])
                        else
                            data[k]["details"] = reconstructTags(v.name)
                        end
                    end

                    os.queueEvent("itemsUpdated")
                else
                    sleep(math.random() % 0.2)
                    getDatabaseFromServer()
                end
            elseif message == "ping" then
                if type(data) == "string" and data == "ack" then
                    os.queueEvent("storageServerAck")
                else
                    sleep(0.5 + (math.random() % 0.2))
                    pingServer()
                end
            elseif message == "getItemDetails" then
                os.queueEvent("gotItemDetails", data)
            elseif message == "pullItems" then
                os.queueEvent("gotPullItems", data)
            elseif message == "getCertificate" and socket.target == settings.get("StorageServer") then
                print("Got new cert from StorageServer")
                os.queueEvent("gotCertificate", data)
            elseif message == "getCertificate" then
                print("Serving cert to client")
                local fileContents = nil
                local filePath = socket.sender .. ".crt"
                debugLog("cert filePath: " .. filePath)
                if fs.exists(filePath) then
                    -- debugLog("file exists")
                    local file = fs.open(filePath, "r")
                    fileContents = file.readAll()
                    file.close()
                end
                debugLog("sending cert: " .. filePath)
                cryptoNet.send(socket, {message, fileContents})
            elseif message == "getPermissionLevel" then
                cryptoNet.send(socket, {message, cryptoNet.getPermissionLevel(data, serverLAN)})
            elseif message == "setPermissionLevel" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.permissionLevel) == "number" then
                    cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverLAN)
                    cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, {message, true})
                else
                    cryptoNet.send(socket, {message, false})
                end
            elseif message == "setPassword" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.password) == "string" then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, {message, true})
                elseif userExists and data.username == socket.username then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, {message, true})
                else
                    cryptoNet.send(socket, {message, false})
                end
            elseif message == "addUser" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and not userExists and type(data.password) == "string" then
                    cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverLAN)
                    cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, {message, true})
                else
                    cryptoNet.send(socket, {message, false})
                end
            elseif message == "deleteUser" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.password) == "string" then
                    cryptoNet.deleteUser(data.username, serverLAN)
                    cryptoNet.deleteUser(data.username, serverWireless)
                    cryptoNet.send(socket, {message, true})
                else
                    cryptoNet.send(socket, {message, false})
                end
            elseif message == "checkPasswordHashed" then
                os.queueEvent("gotCheckPasswordHashed", data, event[2][3])
            elseif message == "watchCrafting" and not settings.get("isMasterCraftingServer") then
                local uniq = true
                for i in pairs(craftingUpdateClients) do
                    if craftingUpdateClients[i] == socket then
                        uniq = false
                    end
                end
                if uniq then
                    craftingUpdateClients[#craftingUpdateClients + 1] = socket
                end
            elseif message == "stopWatchCrafting" then
                for i in pairs(craftingUpdateClients) do
                    if craftingUpdateClients[i].target == socket.target then
                        table.remove(craftingUpdateClients, i)
                    end
                end
            end
        else
            -- User is not logged in
            local message = event[2][1]
            local data = event[2][2]
            if message == "hashLogin" then
                -- Need to auth with storage server
                -- debugLog("hashLogin")
                print("User login request for: " .. data.username)
                log("User login request for: " .. data.username)
                local tmp = {}
                tmp.username = data.username
                tmp.passwordHash = cryptoNet.hashPassword(data.username, data.password, data.servername)
                tmp.servername = data.servername
                data.password = nil
                cryptoNet.send(storageServerSocket, {"checkPasswordHashed", tmp})

                local event2
                local loginStatus = false
                local permissionLevel = 0
                repeat
                    event2, loginStatus, permissionLevel = os.pullEvent("gotCheckPasswordHashed")
                until event2 == "gotCheckPasswordHashed"
                -- debugLog("loginStatus:"..tostring(loginStatus))
                if loginStatus == true then
                    cryptoNet.send(socket, {"hashLogin", true, permissionLevel})
                    socket.username = data.username
                    socket.permissionLevel = permissionLevel

                    -- Update internal sockets
                    for k, v in pairs(serverLAN.sockets) do
                        if v.target == socket.target then
                            serverLAN.sockets[k] = socket
                            break
                        end
                    end
                    for k, v in pairs(serverWireless.sockets) do
                        if v.target == socket.target then
                            serverWireless.sockets[k] = socket
                            break
                        end
                    end
                    os.queueEvent("hash_login", socket.username, socket)
                else
                    print("User: " .. data.username .. " failed to login")
                    log("User: " .. data.username .. " failed to login")
                    cryptoNet.send(socket, {"hashLogin", false})
                end
            elseif message == "requireLogin" then
                cryptoNet.send(socket, {message, settings.get("requireLogin")})
            else
                debugLog("User is not logged in. Sender: " .. socket.sender .. " Target: " .. socket.target)
                -- debugLog("socket.username: " .. tostring(socket.username))
                cryptoNet.send(socket, {"requireLogin"})
                cryptoNet.send(socket, "Sorry, I only talk to logged in users")
            end
        end
    elseif event[1] == "connection_closed" then
        local socket = event[2]
        -- debugLog(dump(storageServerSocket))
        -- debugLog(dump(socket))
        if socket.sender == storageServerSocket.sender then
            cryptoNet.closeAll()
            os.reboot()
        end
        if not settings.get("isMasterCraftingServer") and socket.sender == masterCraftingServerSocket.sender then
            cryptoNet.closeAll()
            os.reboot()
        end
    elseif event[1] == "timer" then
        if event[2] == timeoutConnect and (type(storageServerSocket) == "nil") then
            -- Reboot after failing to connect
            cryptoNet.closeAll()
            os.reboot()
        end
    end
end

local function getMasterCraftingServerCert()
    -- Download the cert from the MasterCraftingServer if it doesnt exist already
    local filePath = settings.get("MasterCraftingServer") .. ".crt"
    if not fs.exists(filePath) then
        log("Download the cert from the MasterCraftingServer")
        cryptoNet.send(masterCraftingServerSocket, {"getCertificate"})
        -- wait for reply from server
        log("wait for reply from MasterCraftingServer")
        local event, data
        repeat
            event, data = os.pullEvent("gotCertificate")
        until event == "gotCertificate"

        log("write the cert file")
        -- write the file
        local file = fs.open(filePath, "w")
        file.write(data)
        file.close()
    end
end

local function postStart()
    -- Download the cert from the storageserver if it doesnt exist already
    local filePath = settings.get("StorageServer") .. ".crt"
    if not fs.exists(filePath) then
        debugLog("Download the cert from the storageserver")
        cryptoNet.send(storageServerSocket, {"getCertificate"})
        -- wait for reply from server
        debugLog("wait for reply from server")
        local event, data
        repeat
            event, data = os.pullEvent("gotCertificate")
        until event == "gotCertificate"

        debugLog("write the cert file")
        -- write the file
        local file = fs.open(filePath, "w")
        file.write(data)
        file.close()
    end
    cryptoNet.send(storageServerSocket, {"storageServer"})
    getDatabaseFromServer()
    getDetailDBFromServer()
    if not settings.get("isMasterCraftingServer") then
        getMasterCraftingServerCert()
    end
end

local function onStart()
    os.setComputerLabel(settings.get("serverName"))
    -- clear out old log
    if fs.exists("logs/craftingServer.log") then
        fs.delete("logs/craftingServer.log")
    end
    if fs.exists("logs/craftingServerDebug.log") then
        fs.delete("logs/craftingServerDebug.log")
    end
    -- Close any old connections and servers
    cryptoNet.closeAll()
    local wirelessModem = nil
    local wiredModem = nil

    dumpAll(true)

    print("Looking for connected modems...")

    for _, side in ipairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            local modem = peripheral.wrap(side)
            if modem.isWireless() then
                wirelessModem = modem
                wirelessModem.side = side
                print("Wireless modem found on " .. side .. " side")
                debugLog("Wireless modem found on " .. side .. " side")
            else
                wiredModem = modem
                wiredModem.side = side
                print("Wired modem found on " .. side .. " side")
                debugLog("Wired modem found on " .. side .. " side")
            end
        elseif peripheral.getType(side) == "speaker" then
            table.insert(speakers, side)
        end
    end

    -- Start the cryptoNet server
    if type(wiredModem) ~= "nil" then
        debugLog("Start the wired cryptoNet server")
        serverLAN = cryptoNet.host(settings.get("serverName", true, false, wiredModem.side))
    end

    -- Only open wireless server if master crafting server
    if type(wirelessModem) ~= "nil" and settings.get("isMasterCraftingServer") then
        debugLog("Start the wireless cryptoNet server")
        serverWireless = cryptoNet.host(settings.get("serverName") .. "_Wireless", true, false, wirelessModem.side)
    end

    timeoutConnect = os.startTimer(10)
    -- Connect to the server
    print("Connecting to server: " .. settings.get("StorageServer"))
    storageServerSocket = cryptoNet.connect(settings.get("StorageServer"), 5, 1,
        settings.get("StorageServer") .. ".crt", wiredModem.side)

    debugLog("requireLogin: " .. tostring(settings.get("requireLogin")) .. " isMasterCraftingServer: " ..
                 tostring(settings.get("isMasterCraftingServer")))
    if settings.get("requireLogin") then
        -- If we send a "ping" and server requires login, it will return "requireLogin" which will start the login process on this server
        cryptoNet.send(storageServerSocket, {"ping"})
        local event
        -- Wait until login is complete
        repeat
            event = os.pullEvent("storageServerLogin")
        until event == "storageServerLogin"
    elseif not settings.get("isMasterCraftingServer") then
        print("Connecting to master server: " .. settings.get("MasterCraftingServer"))
        log("Connecting to master server: " .. settings.get("MasterCraftingServer"))
        debugLog("Connecting to master server: " .. settings.get("MasterCraftingServer"))
        masterCraftingServerSocket = cryptoNet.connect(settings.get("MasterCraftingServer"))
    end
    -- timeout no longer needed
    timeoutConnect = nil

    postStart()

    getRecipes()
    -- os.startThread(craftingManager)
    local speed = (os.epoch("utc") / 1000) - serverBootTime
    print("Boot time: " .. tostring(("%.3g"):format(speed) .. " seconds"))
    debugLog("Boot time: " .. tostring(("%.3g"):format(speed) .. " seconds"))
    craftingManager()
end

debugLog("~~Boot~~")

print("debug mode: " .. tostring(settings.get("debug")))
print("recipeFile is set to : " .. (settings.get("recipeFile")))
print("craftingChest is set to: " .. (settings.get("craftingChest")))

if fs.exists("tags.db") then
    print("Reading Tags Database")
    local tagsFile = fs.open("tags.db", "r")
    local contents = tagsFile.readAll()
    tagsFile.close()

    tags = textutils.unserialize(contents)
    if type(tags) == "nil" then
        tags = {}
    end
    print("Tags read: " .. tostring(tags.count))
end

print("")
print("Crafting Server Ready")
print("")

cryptoNet.setLoggingEnabled(true)
if settings.get("debug") then
    -- print(dump(recipes))
    -- parallel.waitForAny(debugMenu, serverHandler)
    cryptoNet.startEventLoop(onStart, onCryptoNetEvent)
else
    cryptoNet.startEventLoop(onStart, onCryptoNetEvent)
    -- serverHandler()
end

cryptoNet.closeAll()
