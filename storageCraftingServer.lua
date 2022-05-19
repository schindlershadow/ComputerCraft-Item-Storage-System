local tags = {}
local clients = {}
local recipes = {}
local server = 0
local modem = peripheral.find("modem")


--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
--Oneliner bash to extract recipes from craft tweaker output:
--grep craftingTable crafttweaker.log > recipes
settings.define("recipeURL", { description = "The URL containing all recipes", "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/vanillaRecipes.txt", type = "string" })
settings.define("recipeFile", { description = "The temp file used for loading recipes", "recipes", type = "string" })
settings.define("craftingChest", { description = "The peripheral name of the crafting chest", "minecraft:chest_3", type = "string" })


--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    print("Only vanilla recipes will be loaded, change the recipeURL in .settings for modded Minecraft")
    settings.set("debug", false)
    settings.set("recipeURL", "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/vanillaRecipes.txt")
    settings.set("recipeFile", "recipes")
    settings.set("craftingChest", "minecraft:chest_3")
    print("Stop the server and edit .settings file with correct settings")
    settings.save()
    sleep(5)
end

--Open all modems to rednet
peripheral.find("modem", rednet.open)

--Dumps a table to string
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

local function log(text)
    if settings.get("debug") then
        local logFile = fs.open("logs/craftingServerDebug.log", "a")
        if type(text) == "string" then

            logFile.writeLine(text)

        else
            logFile.writeLine(textutils.serialise(text))
        end

        logFile.close()
    end
end

local function broadcast()
    print("Searching for storageServer server")
    rednet.broadcast("storageServer")
    local id, message = rednet.receive(nil, 5)
    if type(tonumber(message)) == "number" and id == tonumber(message) then
        print("Server set to: " .. tostring(message))
        server = tonumber(message)
        return tonumber(message)
    else
        sleep(0.5)
        return broadcast()
    end
end

function addShaped(recipeName, name, arg3, arg4)
    --print("name: " .. name)
    --print("itemOutput: " .. itemOutput)
    local tab = {}
    local outputNumber = 1
    local recipe
    if arg4 then
        --print("number of output: " .. tostring(arg3))
        --print("recipe: " .. dump(arg4))

        outputNumber = arg3
        recipe = arg4
    else
        --print("recipe: " .. dump(arg3))
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
        --Convert to variable recipe format
        for i = 1, #recipe, 1 do
            for j = 1, #recipe[i], 1 do
                recipe[i][j] = { recipe[i][j] }
            end
        end
        tab["recipe"] = recipe
    end

    recipes[#recipes + 1] = tab

end

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
    --tab["recipe"] = recipe
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

        --Put every item into a table to have a uniform recipe
        for i = 1, #recipe, 1 do
            if type(recipe[i]) ~= "table" then
                recipe[i] = { recipe[i] }
            end
        end

    else
        tab["recipeInput"] = "static"
    end

    --Convert to universal shaped variable recipe format

    local convertedRecipe = { {}, {}, {} }
    for row = 1, 3, 1 do
        for slot = 1, 3, 1 do
            if type(recipe[((row - 1) * 3) + slot]) == "nil" then
                convertedRecipe[row][slot] = { "none" }
            elseif isVar then
                convertedRecipe[row][slot] = recipe[((row - 1) * 3) + slot]
            else
                convertedRecipe[row][slot] = { recipe[((row - 1) * 3) + slot] }
            end
        end
    end
    tab["recipe"] = convertedRecipe

    if recipeName == "byg:fire_charge_from_byg_coals" then
        log(textutils.serialise(tab))
    end

    recipes[#recipes + 1] = tab
end

craftingTable = { addShaped = addShaped, addShapeless = addShapeless }

function getInstance()
    return "none"
end

IIngredientEmpty = { getInstance = getInstance }

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
    local newArray = {} -- new array that will be arr, but without duplicates
    for _, element in pairs(arr) do
        if not inTable(newArray, element) then -- making sure we had not added it yet to prevent duplicates
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

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

--Creates a tab table using the tabs db, use this to avoid costly peripheral lookups
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

--Check if item name is in tag db
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

--Mantain tags lookup
local function addTag(item)
    --print("addTag for: " .. item.name)

    --Maintain tags count
    local countTags
    if type(tags.count) ~= "number" then
        countTags = 0
    else
        countTags = tags.count
    end

    --Maintain item count
    local countItems
    if type(tags.countItems) ~= "number" then
        countItems = 0
    else
        countItems = tags.countItems
    end

    --Get the tags which are keys in table item.details.tags
    local keyset = {}
    local n = 0
    if type(item.details) == "nil" then
        item.details = peripheral.wrap(item.chestName).getItemDetail(item.slot)
    end
    for k, v in pairs(item.details.tags) do
        n = n + 1
        keyset[n] = k
    end
    --print(dump(keyset))


    --Add them to tags table if they dont exist, if they exist add the item name to the list
    for i = 1, #keyset, 1 do
        if type(tags[keyset[i]]) == "nil" then
            print("Found new tag: " .. keyset[i])
            print("Found new item: " .. item.name)
            tags[keyset[i]] = { item.name }
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

--gets the contents of a table of chests
local function getList(storage)
    local list = {}
    local itemCount = 0
    local getName = peripheral.getName
    local wrap = peripheral.wrap
    for _, chest in pairs(storage) do
        local tmpList = {}
        local name = getName(chest)
        for slot, item in pairs(chest.list()) do
            item["slot"] = slot
            item["chestName"] = name
            if not (inTags(item.name)) then
                item["details"] = wrap(name).getItemDetail(slot)
                addTag(item)
            else
                item["details"] = reconstructTags(item.name)
            end

            itemCount = itemCount + item.count
            --table.insert(list, item)
            list[#list + 1] = item
            --print(("%d x %s in slot %d"):format(item.count, item.name, slot))
        end
    end

    return list, itemCount
end

--Returns list of storage peripherals excluding import and export chests
local function getStorage()
    local storage = {}
    local wrap = peripheral.wrap
    local remote = modem.getNamesRemote()
    for i in pairs(remote) do
        if modem.hasTypeRemote(remote[i], "inventory") then
            if remote[i] ~= settings.get("craftingChest") then
                storage[#storage + 1] = wrap(remote[i])
            end
        end
    end
    return storage
end

local function getDatabaseFromServer()
    rednet.send(server, "getItems")
    local id, message = rednet.receive(nil, 1)
    if type(message) == "table" and id == server then
        for k, v in pairs(message) do
            if not (inTags(v.name)) then
                if type(message[k]["details"]) == "nil" then
                    message[k]["details"] = peripheral.wrap(v.chestName).getItemDetail(v.slot)
                end
                addTag(message[k])
            else
                message[k]["details"] = reconstructTags(v.name)
            end
        end
        return message
    else
        sleep(0.2)
        return getDatabaseFromServer()
    end
end

local function pingServer()
    rednet.send(server, "ping")
    local id, message = rednet.receive(nil, 1)
    if type(message) == "string" and id == server and message == "ack" then
        return message
    else
        sleep(0.2)
        return pingServer()
    end
end

function Split(s, delimiter)
    result = {};
    for match in (s .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match);
    end
    return result;
end

--Grab recipe file from an http source in crafttweaker output format and covert it to lua code
local function getRecipes()
    print("Loading recipes...")
    print("Recipe URL set to: " .. settings.get("recipeURL"))
    local contents = http.get(settings.get("recipeURL"))



    local fileName = settings.get("recipeFile")
    --local file = fs.open(fileName, "r")
    local lines = {}
    while true do
        --local line = file.readLine()
        local line = contents.readLine()
        -- If line is nil then we've reached the end of the file and should stop
        if not line then break end

        lines[#lines + 1] = line
    end

    --file.close()

    --deal with the recipes that have multiple possible item inputs
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

            --Convert the string recipe into an array
            for k = 1, #row, 1 do
                --cut out the first char which is [
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

            --Rebuild the crafttweaker string with the new format
            local newLine = firstHalf .. '['
            for row = 1, #newRecipes, 1 do
                newLine = newLine .. '['
                for slot = 1, #newRecipes[row], 1 do

                    if #newRecipes[row][slot] == 1 then
                        if string.find(newRecipes[row][slot][1], '%[') then
                            newRecipes[row][slot][1] = '{' .. string.gsub(newRecipes[row][slot][1], '%[', '') .. '}'
                        end
                        newLine = newLine .. newRecipes[row][slot][1]
                    else
                        newLine = newLine .. '{'
                        for j = 1, #newRecipes[row][slot] do
                            if string.find(newRecipes[row][slot][j], '%[') then
                                newRecipes[row][slot][j] = string.gsub(newRecipes[row][slot][j], '%[', '')
                            end
                            newLine = newLine .. newRecipes[row][slot][j]
                            if j ~= #newRecipes[row][slot] then
                                newLine = newLine .. ','
                            end
                        end
                        newLine = newLine .. '}'
                    end
                    if slot ~= #newRecipes[row] then
                        newLine = newLine .. ','
                    end
                end
                if row == #newRecipes then
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


    --Do a bunch of replacements to convert to lua code
    for i = 1, #lines, 1 do
        local line = lines[i]
        if string.find(line, '|') or string.find(line, 'withTag') then
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


    --The file might be larger than the filesystem, so do it in small chunks
    local count = #lines
    local fileNumber = 1
    print("Number of lines " .. tostring(count))
    while count > 0 do
        local outFile = fs.open(tostring(fileNumber) .. fileName, "w")
        for i = 1, 500, 1 do
            if count > 0 then
                outFile.writeLine(lines[count])
                count = count - 1
            end
        end
        outFile.close()
        --print(tostring(count))
        require(tostring(fileNumber) .. fileName)
        fs.delete(tostring(fileNumber) .. fileName)
        fileNumber = fileNumber + 1
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
                --print(stringTag .. " == " .. tostring(find(dump(v.details.tags),stringTag)))
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

local function search(searchTerm, InputTable, count)
    if string.find(searchTerm, "tag:") then
        return searchForTag(searchTerm, InputTable, count)
    else
        local stringSearch = string.match(searchTerm, 'item:(.+)')
        local find = string.find
        local number = 0
        local returnV = nil
        local returnK
        --print("need " .. tostring(count) .. " of " .. stringSearch)
        for k, v in pairs(InputTable) do
            if (v["name"]) == (stringSearch) then
                number = number + v.count
            end
            if (v["name"]) == (stringSearch) and v.count >= count then
                --print("Found: " .. tostring(v.count) .. " of " .. v.name)
                returnV = v
                returnK = k
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
        return nil
    else
        return filteredTable
    end
end

local function updateClient(id, message, messageToSend)
    local table = {}
    table.type = "craftingUpdate"

    table.message = message
    if message == "slotUpdate" then
        table[1] = messageToSend[1]
        table[2] = messageToSend[2]
        table[3] = messageToSend[3]
    elseif message == "itemUpdate" or message == "logUpdate" then
        table[1] = messageToSend
    end
    rednet.send(id, table)

end

--Calculate number of each item needed.
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
                    --print(dump(recipeName))
                    if type(numNeeded[recipeItemName]) == "nil" then
                        numNeeded[recipeItemName] = amount
                    else
                        numNeeded[recipeItemName] = numNeeded[recipeItemName] + amount
                    end
                end
            end
        end
    end




    return numNeeded
end

--Checks if crafting materials are in system
local function haveCraftingMaterials(tableOfRecipes, amount, id)
    if type(id) == "nil" then
        id = os.getComputerID()
    end
    log("haveCraftingMaterials")
    log(tableOfRecipes)
    log("amount:" .. tostring(amount) .. " id:" .. tostring(id))
    if type(amount) == "nil" then
        amount = 1
    end
    --log(tableOfRecipes)
    local recipeIsCraftable = {}
    --print("Found " .. tostring(#tableOfRecipes) .. " recipes")
    --print(dump(tableOfRecipes))

    local num = 1
    for _, tab in pairs(tableOfRecipes) do
        local recipe = tab.recipe
        --print(textutils.serialise(recipe))
        --log(textutils.serialise(recipe))
        --sleep(5)
        local craftable = true

        log("haveCraftingMaterials: numNeeded")
        local numNeeded = calculateNumberOfItems(recipe, amount)
        log(textutils.serialise(numNeeded))
        --print(textutils.serialise(numNeeded))


        craftable = true
        for i = 1, #recipe, 1 do --row
            local row = recipe[i]
            for k = 1, #row, 1 do --slot
                local slot = row[k]
                local craftable2 = false
                for j = 1, #slot, 1 do --item
                    local item = slot[j]

                    log("item: " .. item)
                    log("numNeeded[item]: " .. tostring(numNeeded[item]))
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
                        log("found " .. tostring(number) .. " need " .. tostring(numNeeded[item]))

                        --If item with exact amount is found, or there is more than what we need
                        if number >= numNeeded[item] then
                            --if "number" is >0 that means the item was found in the system
                            craftable2 = true
                        else
                            print(tostring(item:match(".+:(.+)")) .. ": Need: " .. tostring(numNeeded[item]) .. " Found: " .. tostring(number))
                            updateClient(id, "logUpdate", tostring(item:match(".+:(.+)")) .. ": Need: " .. tostring(numNeeded[item]) .. " Found: " .. tostring(number))
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

    --print(tostring(#recipeIsCraftable) .. " recipes are craftable")
    return recipeIsCraftable
end

local function isTagCraftable(searchTerm, inputTable)
    local stringSearch = string.match(searchTerm, 'tag:%w+:(.+)')
    local items = {}
    --print("searchTerm: " .. searchTerm)
    if type(tags[stringSearch]) ~= "nil" then
        --check tags database
        --print("Checking tags database")
        for i, k in pairs(tags[stringSearch]) do
            items[#items + 1] = {}
            items[#items]["name"] = k
        end
    else
        items = searchForItemWithTag(searchTerm, inputTable)
    end

    if type(items) == nil then
        return false
    end
    --print(dump(items))
    --sleep(5)

    --check if tag has crafting recipe
    local tab = {}
    for i = 1, #recipes, 1 do
        for k = 1, #items, 1 do
            if (recipes[i].name == items[k].name) then
                --return recipes[i].name
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
    rednet.send(server, "reloadStorageDatabase")
    pingServer()
end

local function patchStorageDatabase(itemName, count)
    print("patching db item:" .. itemName .. " #" .. tostring(count))
    log("patching db item:" .. itemName .. " #" .. tostring(count))
    local stringSearch
    if string.find(itemName, 'item:(.+)') then
        stringSearch = string.match(itemName, 'item:(.+)')
    else
        stringSearch = itemName
    end
    if type(stringSearch) == "nil" then
        stringSearch = itemName
    end
    local find = string.find
    local lower = string.lower
    for k, v in pairs(items) do
        if v["name"] == stringSearch then
            items[k]["count"] = items[k]["count"] + count
            return 1
        end
    end
    items[#items + 1] = {}

    return 0
end

--Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    --write("Reloading database..")
    --storage = getStorage()
    --write("..")

    --items, storageUsed = getList(storage)

    pingServer()
    rednet.send(server, "forceImport")
    items = getDatabaseFromServer()
    --write("done\n")
    --write("Writing Tags Database....")

    if fs.exists("tags.db") then
        fs.delete("tags.db")
    end
    local tagsFile = fs.open("tags.db", "w")
    tagsFile.write(textutils.serialise(tags))
    tagsFile.close()
    --write("done\n")
    --print("Items loaded: " .. tostring(storageUsed))
    --print("Tags loaded: " .. tostring(tags.count))
    --print("Tagged Items loaded: " .. tostring(tags.countItems))
end

--Returns the totals number of an item in turtle inventory
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

local function dumpAll()
    local reload = false
    for i = 1, 16, 1 do
        local item = turtle.getItemDetail(i)
        if type(item) ~= "nil" then
            turtle.select(i)
            turtle.dropDown()
            reload = true
        end
    end
    if reload then
        reloadStorageDatabase()
        pingServer()
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
    local items = {}
    --print("searchTerm: " .. searchTerm)
    if type(tags[stringSearch]) ~= "nil" then
        --check tags database
        --print("Checking tags database")
        for i, k in pairs(tags[stringSearch]) do
            items[#items + 1] = {}
            items[#items]["name"] = k
        end
    else
        items = searchForItemWithTag(searchTerm, recipes)
    end

    if type(items) == nil then
        return {}
    end

    --check if tag has crafting recipe
    local tab = {}
    for i = 1, #recipes, 1 do
        for k = 1, #items, 1 do
            if (recipes[i].name == items[k].name) then
                --return recipes[i].name
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
    log("recipeContains itemName: " .. itemName)
    --log(textutils.serialise(recipe))
    for i = 1, #recipe.recipe, 1 do --row
        local row = recipe.recipe[i]
        for j = 1, #row, 1 do --slot
            local slot = row[j]
            for k = 1, #slot, 1 do --item
                local item = slot[k]
                --log("recipeContains: " .. item .. ", " .. itemName)
                if item == itemName then
                    log("recipeContains: true")
                    return true
                end
                if string.find(item, 'tag:(.+)') then
                    item = string.match(item, 'tag:(.+)')
                    if tags[itemName] == item then
                        log("recipeContains: true")
                        return true
                    end
                end
                if string.find(item, 'item:(.+)') then
                    item = string.match(item, 'item:(.+)')
                end
                if item == itemName then
                    log("recipeContains: true")
                    return true
                end
            end
        end
    end
    log("recipeContains: false")
    return false
end

--returns score, input recipe, name of recipe item output, time-to-live, amount of item output recipe creates
local function scoreBranch(recipe, itemName, ttl, amount, id)
    local score = 0

    if type(amount) == "nil" then
        amount = 1
    end

    log("scoreBranch: " .. textutils.serialise(itemName))
    --print("scoreBranch: " .. textutils.serialise(itemName))
    log("ttl is " .. tostring(ttl))
    --log(textutils.serialise(recipe))

    if ttl < 1 then
        --print("ttl is 0")
        log("ttl is 0")
        --log(recipe)
        return 0
    end


    for i = 1, #recipe, 1 do --row
        local row = recipe[i]
        for j = 1, #row, 1 do --slot
            local slot = row[j]
            local skip = false
            for k = 1, #slot, 1 do --item
                local item = slot[k]
                if item ~= "none" and item ~= "item:minecraft:air" and not skip then
                    log("searching for: " .. textutils.serialise(item))
                    --if item is in the system, increase score
                    local searchResult
                    if string.find(item, "tag:") then
                        searchResult = searchForTag(item, items, 1)
                    elseif string.find(item, "item:(.+)") then
                        searchResult = search(item, items, 1)
                    else
                        searchResult = search(item, items, 1)
                    end

                    if type(searchResult) ~= "nil" then
                        --print(item .. " found in system")
                        log(item .. " found in system")
                        score = score + ((1 + ttl) * amount)
                        log("score: " .. tostring(score))
                        --no need to check the other possible items
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
                            log(item .. " is unknown to the system")
                            return 0
                        elseif #allRecipes < 1 then
                            print("no recipes found for: " .. item)
                            log(("no recipes found for: " .. item))
                            updateClient(id, "logUpdate", "no recipes found for: " .. tostring(item))
                            return 0
                        end
                        local craftableRecipes = haveCraftingMaterials(allRecipes, 1)

                        --If recipe needs orginal item then skip recipe
                        for counting = 1, #craftableRecipes, 1 do
                            if recipeContains(craftableRecipes[counting], itemName) then
                                --table.remove(craftableRecipes, craftableRecipes[counting])
                                craftableRecipes[counting] = nil
                            end
                        end

                        if #craftableRecipes > 0 then


                            --if it has a currently craftable recipe increase score
                            --print(item .. " is currently craftable")
                            log(item .. " is currently craftable")
                            score = score + ((1 + ttl) * amount)
                            log("score: " .. tostring(score))
                            skip = true
                            break
                        else
                            --if it has no currently craftable recipe, check all recipes
                            --log("no currently craftable recipe, check all recipes for " .. item)
                            --log(allRecipes)

                            local failed = true
                            for m = 1, #allRecipes, 1 do

                                if recipeContains(allRecipes[m], itemName) == false and recipeContains(allRecipes[m], item) == false then
                                    log("checking recipe: " .. allRecipes[m].name .. " from: " .. allRecipes[m].recipeName)
                                    ttl = ttl - 1
                                    local scoreTab = scoreBranch(allRecipes[m].recipe, allRecipes[m].name, ttl - 1, allRecipes[m].count, id)
                                    if scoreTab > 0 then
                                        score = score + scoreTab
                                        log("score: " .. tostring(score))
                                        skip = true
                                        failed = false
                                        break
                                    end
                                end
                            end
                            if failed then
                                print("No recipe found for " .. item)
                                log("No recipe found for " .. item)
                                return score
                            end
                        end
                    end
                end
            end
        end
    end

    ttl = ttl - 1
    --score = score + ttl
    log("return score: " .. tostring(score))
    return score
end

local function getBestRecipe(allRecipes, id)
    local bestRecipe
    local bestScore = 0
    local bestCount = 1
    for i = 1, #allRecipes, 1 do
        local score = scoreBranch(allRecipes[i].recipe, allRecipes[i].name, 20, allRecipes[i].count, id)
        log("recipe: " .. allRecipes[i].recipeName .. " score: " .. score)
        if score > bestScore then
            bestRecipe = allRecipes[i]
            bestScore = score
            bestCount = allRecipes[i].count
        end
    end

    if bestScore == 0 then
        log("uncraftable")
        return nil
    end
    print("Recipe score: " .. tostring(bestScore))
    log("Recipe score: " .. tostring(bestScore))

    return bestRecipe, bestCount

end

--Get items and craft
local function craftRecipe(recipeObj, timesToCraft, id)
    local recipe = recipeObj.recipe
    log("craftRecipe")
    log(recipeObj)
    log("timesToCraft:" .. tostring(timesToCraft) .. " id:" .. tostring(id))

    --amount and id is optional
    if type(timesToCraft) == "nil" then
        timesToCraft = 1
    end
    if type(id) == "nil" then
        id = os.getComputerID()
    end

    local outputAmount = timesToCraft * recipeObj.count

    --Check if any materials are stack limited
    local stackLimited = false
    local stackLimit = 64
    for row = 1, #recipe do
        for slot = 1, #recipe[row], 1 do
            --ignore empty slots
            if recipe[row][slot][1] ~= "none" and recipe[row][slot][1] ~= "item:minecraft:air" then
                local searchResult = {}
                for k = 1, #recipe[row][slot], 1 do
                    --Find a sample of the item in system
                    searchResult[k] = search(recipe[row][slot][k], items, 1)
                    if type(searchResult[k]) ~= "nil" then
                        local maxCount = peripheral.wrap(searchResult[k].chestName).getItemDetail(searchResult[k].slot).maxCount
                        if maxCount < 64 then
                            stackLimited = true
                            --Update new stack limit
                            if maxCount < stackLimit then
                                --stack limit will always be the stack limit of the smallest stack limited item
                                stackLimit = maxCount
                            end
                        end
                    end
                end
            end
        end
    end

    log("stackLimited: " .. tostring(stackLimited) .. " stackLimit:" .. tostring(stackLimit))

    --calculate number of items to be moved at once
    local moveCount = timesToCraft
    if stackLimited then
        moveCount = stackLimit
    elseif moveCount > 64 then
        moveCount = 64
    end
    log("moveCount:" .. tostring(moveCount))

    --In case of garbage in the turtle's inventory
    dumpAll()

    --Moving materials to crafting grid
    local crafted = 0
    while outputAmount > crafted do
        --Makes sure not to overcraft
        if (outputAmount - crafted) < moveCount then
            moveCount = (outputAmount - crafted)
        end
        --tracks if the crafting cannot continue and should bail
        local failed = false
        for row = 1, #recipe do
            for slot = 1, #recipe[row], 1 do
                if recipe[row][slot][1] ~= "none" and recipe[row][slot][1] ~= "item:minecraft:air" then
                    if not failed then
                        --Select the slot in the turtle, the turtle is 4x4 but crafting grid is 3x3
                        turtle.select(((row - 1) * 4) + slot)

                        --table of items in the system that matched the requirements
                        local searchResults = {}
                        --table of total items in the system
                        local insystem = {}
                        --table of indexes of global "items" that match searchResult
                        local indexs = {}
                        --keeps track of if at least one required item was found
                        local found = false
                        --keeps track of if a substitution was found
                        local foundIndexs = {}
                        local lastGoodIndex = 0

                        --This handles recipes that can have substitutions
                        for k = 1, #recipe[row][slot], 1 do
                            searchResults[k], insystem[k], indexs[k] = search(recipe[row][slot][k], items, moveCount)
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
                            log("insystem[k]:" .. tostring(insystem[k]) .. " moveCount:" .. tostring(moveCount))
                        end




                        if found == false then
                            --no sutiable item found in system
                            for j = 1, #foundIndexs, 1 do
                                if not foundIndexs[j] then
                                    print("craftRecipe: Cannot find enough " .. recipe[row][slot][j] .. " in system")
                                    log(("craftRecipe: Cannot find enough " .. recipe[row][slot][j] .. " in system"))
                                    updateClient(id, "logUpdate", "craftRecipe: Cannot find enough " .. recipe[row][slot][j] .. " in system")
                                end
                            end
                            dumpAll()
                            failed = true
                        else
                            --item was found in system
                            local searchResult, index, foundIndex

                            for k = 1, #searchResults, 1 do
                                --Get the first good result
                                if type(searchResults[k]) ~= "nil" then
                                    searchResult = searchResults[k]
                                    index = indexs[k]
                                    foundIndex = k
                                    break
                                end
                            end

                            --If there is enough in the system but not in one slot then searchResult will be nil here
                            if type(searchResult) == "nil" then
                                searchResult = search(recipe[row][slot][lastGoodIndex], items, 1)
                            end

                            --Move the items from the system to crafting chest
                            print("Getting: " .. searchResult.name:match(".+:(.+)"))
                            log("Getting: " .. searchResult.name)
                            updateClient(id, "logUpdate", "Getting: " .. searchResult.name:match(".+:(.+)"))
                            local itemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], moveCount)
                            --Ask the server to reload database now that something has been changed
                            reloadServerDatabase()
                            log("itemsMoved: " .. tostring(itemsMoved))
                            while itemsMoved < moveCount do
                                --try again
                                local itemsLeft = moveCount - itemsMoved
                                log("try again: itemsMoved:" .. tostring(itemsMoved) .. " < moveCount:" .. tostring(moveCount) .. " Items left:" .. tostring(itemsLeft))
                                reloadStorageDatabase()
                                --use same item as searchResult to avoid stacking issues
                                local newSearchResult = search("item:" .. searchResult.name, items, itemsLeft)
                                if type(newSearchResult) == "nil" then
                                    --try to find just 1
                                    newSearchResult = search("item:" .. searchResult.name, items, 1)
                                    if type(newSearchResult) == "nil" then
                                        print("failed to move item: " .. searchResult.name)
                                        log("failed to move item: " .. searchResult.name)
                                        updateClient(id, "logUpdate", "failed to move item: " .. searchResult.name)
                                        failed = true
                                        break
                                    else
                                        itemsLeft = 1
                                    end
                                end
                                local newItemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(newSearchResult["chestName"], newSearchResult["slot"], itemsLeft)
                                --Ask the server to reload database now that something has been changed
                                reloadServerDatabase()
                                itemsMoved = itemsMoved + newItemsMoved
                            end
                            --Move items from crafting chest to turtle inventory
                            turtle.suckUp()
                            --Check the items just moved
                            local slotDetail = turtle.getItemDetail()
                            if type(slotDetail) == "nil" then
                                print("failed to get item: " .. searchResult.name)
                                updateClient(id, "logUpdate", "failed to get item: " .. searchResult.name)
                                dumpAll()
                                failed = true
                                log(searchResult)
                                break
                            else
                                log("slotDetail:" .. textutils.serialise(slotDetail))
                                --Send crafting status update to client
                                local table = {}
                                table[1] = row
                                table[2] = slot
                                table[3] = slotDetail.count
                                updateClient(id, "slotUpdate", table)
                            end
                        end
                    end
                end
            end
        end

        if failed then
            dumpAll()
            return false
        else
            turtle.craft()
            local craftedItem = turtle.getItemDetail()


            if type(craftedItem) == "nil" then
                return false
            else
                --crafted = crafted + craftedItem.count
                log("recipeObj.name: " .. recipeObj.name .. " numInTurtle(recipeObj.name): " .. tostring(numInTurtle(recipeObj.name)))
                crafted = crafted + numInTurtle(recipeObj.name)
                --Wait on storage system to be ready
                pingServer()
            end
            dumpAll()
        end

        log("crafted:" .. tostring(crafted))
    end
    return true
end

local function getCountFromRecipe(recipe)
    for _, v in pairs(recipes) do
        if v.recipe == recipe then
            return v.count
        end
    end
    return nil
end

--Brute-force recersive crafting
local function craftBranch(recipeObj, ttl, amount, id)
    local recipe = recipeObj.recipe
    local itemName = recipeObj.name

    if type(amount) == "nil" then
        amount = 1
    end
    if type(id) == "nil" then
        id = os.computerID()
    end


    --Send item status update to client
    updateClient(id, "craftingUpdate", itemName)
    log("craftBranch: " .. textutils.serialise(itemName) .. " id:" .. tostring(id))
    --print("craftBranch: " .. textutils.serialise(itemName))
    --log(textutils.serialise(recipe))
    --print(textutils.serialise(recipe))

    if ttl < 1 then
        --print("ttl is 0")
        log("ttl is 0")
        --log(recipe)
        return false
    end
    log(tostring(ttl))

    local numNeeded = calculateNumberOfItems(recipe, amount)

    for k, v in pairs(numNeeded) do
        --print("Need: " .. k .. " #" .. v)
        log("numNeeded: " .. k .. " #" .. v)
    end

    local craftedAnything = false
    for i = 1, #recipe, 1 do --row
        local row = recipe[i]
        for j = 1, #row, 1 do --slot
            local slot = row[j]
            local skip = false
            for k = 1, #slot, 1 do --item
                local item = slot[k]
                if item ~= "none" and item ~= "item:minecraft:air" and skip == false then
                    log("processing: " .. tostring(numNeeded[item]) .. " " .. item)
                    --if item is in the system
                    local searchResult
                    local have = 0
                    if string.find(item, "tag:") then
                        searchResult, have = searchForTag(item, items, numNeeded[item])
                    elseif string.find(item, "item:(.+)") then
                        searchResult, have = search(item, items, numNeeded[item])
                    else
                        searchResult, have = search(item, items, numNeeded[item])
                    end
                    log(tostring(have) .. " found in system")

                    if type(searchResult) ~= "nil" or have >= numNeeded[item] then
                        --Item was found in the system
                        --print(item .. " found in system")
                        log(item .. " found in system")
                        --no need to check the other possible items
                        skip = true
                        break
                    else
                        log("have: " .. tostring(have) .. " Need: " .. tostring(numNeeded[item]) .. " of " .. item)

                        local allRecipes
                        ---need to check for tags
                        if string.find(item, 'tag:%w+:(.+)') then
                            allRecipes = getAllTagRecipes(item)
                        elseif string.find(item, "item:(.+)") then
                            allRecipes = getAllRecipes(string.match(item, 'item:(.+)'))
                        else
                            allRecipes = getAllRecipes(item)
                        end


                        if #allRecipes < 1 then
                            print("Cannot craft " .. itemName .. ": no recipes found for: " .. item)
                            updateClient(id, "logUpdate", "Cannot craft " .. itemName .. ": no recipes found for: " .. item)
                            log(("no recipes found for: " .. item))
                            return false
                        end
                        --Remove existing amount
                        if have < numNeeded[item] then
                            numNeeded[item] = numNeeded[item] - have
                        else
                            --We have enough
                            break
                        end
                        --if numNeeded[item] > 64 then
                        --    numNeeded[item] = 64
                        --end
                        local craftableRecipes = haveCraftingMaterials(allRecipes, numNeeded[item], id)
                        if #craftableRecipes > 0 then
                            --Get best recipe then craft it
                            --print(item .. " is currently craftable")
                            log(item .. " is currently craftable")

                            local recipeToCraft
                            local outputAmount = 1
                            --get the best recipe
                            if #craftableRecipes > 1 then
                                --print("More than one craftable recipe, Searching for best recipe")
                                log("More than one craftable recipe, Searching for best recipe")
                                recipeToCraft, outputAmount = getBestRecipe(craftableRecipes, id)
                            else
                                recipeToCraft = craftableRecipes[1]
                                outputAmount = craftableRecipes[1].count
                            end
                            --log(recipeToCraft)
                            log("numNeeded[item]: " .. tostring(numNeeded[item]))
                            log("outputAmount: " .. tostring(outputAmount))
                            --Send status update to client
                            updateClient(id, "itemUpdate", item)
                            local status = craftRecipe(recipeToCraft, numNeeded[item], id)
                            if status == false then
                                print("crafting failed")
                                log("crafting failed")
                                updateClient(id, "logUpdate", "crafting failed")
                                return false
                            else
                                log("breaking")
                                craftedAnything = true
                                skip = true
                                break
                            end
                        else
                            --if it has no currently craftable recipe, check all recipes
                            local failed = true
                            for m = 1, #allRecipes, 1 do
                                ttl = ttl - 1
                                if recipeContains(allRecipes[m], itemName) == false and recipeContains(allRecipes[m], item) == false then
                                    --local result = craftBranch(allRecipes[m], ttl, numNeeded[item], id)
                                    local result = craftBranch(allRecipes[m], ttl, math.ceil(numNeeded[item] / allRecipes[m].count), id)
                                    if result then
                                        failed = false
                                        craftedAnything = true
                                        break
                                    end
                                end
                            end
                            if failed then
                                --print("got nothing for " .. item)
                                log("got nothing for " .. item)
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

    log("craftedAnything: " .. tostring(craftedAnything))
    local craft = false
    --This is to ensure the materials needed to craft parent were not used in child recipe
    if craftedAnything then
        local tab = {}
        tab.recipe = recipe
        local craftable = haveCraftingMaterials({ tab }, amount, id)
        if #craftable < 1 then
            local status = craftBranch(recipeObj, ttl - 1, amount, id)
            if status == false then
                print("failed")
                log("failed")
                updateClient(id, "logUpdate", "failed")
            end
            log("This is to ensure the materials needed to craft parent were not used in child recipe: " .. tostring(status))
            return status
        else
            craft = true
        end
    else
        craft = true
    end

    --Craft parent item
    if craft then
        log("Crafting Parent recipe: " .. itemName)
        --Send status update to client
        updateClient(id, "itemUpdate", itemName)
        local status
        status = craftRecipe(recipeObj, amount, id)
        --status = craftRecipe(recipeObj, math.ceil(amount / recipeObj.count), id)
        if status == false then
            print("crafting failed")
            log("crafting failed")
            updateClient(id, "logUpdate", "crafting failed")
            return false
        end
        log("Craft parent item: " .. tostring(status))
        return status
    end
end

local function craft(item, amount, id)
    if type(id) == "nil" then
        id = os.computerID()
    end

    local ttl = 20
    if type(amount) == "nil" then
        amount = 1
    end

    local allRecipes
    if type(item) == "string" then
        --tag check
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
        allRecipes = { item }
    end

    --If one of the recipes are craftable, craft it
    local craftableRecipes = haveCraftingMaterials(allRecipes, 1, id)
    local recipeToCraft

    --print(tostring(#craftableRecipes))

    --Otherwise get the best recipe
    local outputAmount = 1
    if #craftableRecipes == 0 then
        --print("No currently craftable recipes, Searching for best recipe")
        recipeToCraft, outputAmount = getBestRecipe(allRecipes, id)
    elseif #craftableRecipes > 1 then
        --print("More than one craftable recipe, Searching for best recipe")
        recipeToCraft, outputAmount = getBestRecipe(craftableRecipes, id)
    else
        recipeToCraft = craftableRecipes[1]
        outputAmount = craftableRecipes[1].count
    end

    if type(recipeToCraft) == "nil" then
        if type(item) == "table" then
            print("No recipe found for: " .. tostring(item.name))
            updateClient(id, "logUpdate", "No recipe found for: " .. tostring(item.name:match(".+:(.+)")))
        else
            print("No recipe found for: " .. tostring(item))
            updateClient(id, "logUpdate", "No recipe found for: " .. tostring(item:match(".+:(.+)")))
        end
        return false
    end

    local failed = false
    print("Crafting: #" .. tostring(amount) .. " " .. tostring(item))
    --print(dump(recipes[i].recipe))
    --log(recipeToCraft)


    --print(recipeToCraftInput .. " " .. recipeToCraftType .. " crafting recipe")

    log("Craft: " .. tostring(item) .. ", " .. tostring(ttl) .. ", " .. tostring(amount))
    return craftBranch(recipeToCraft, ttl, math.ceil(amount / outputAmount), id)
    --return craftBranch(recipeToCraft, ttl, amount, id)
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
                --print("Crafting: " .. (input2))
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
                        --print("Crafting: " .. (recipes[i].name))
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
                    --log(dump(recipes[i]))
                end
            end
        elseif input == "exit" then
            os.queueEvent("terminate")
        end
        sleep(1)
    end
end

local function serverHandler()
    while true do
        local id, message = rednet.receive()
        if id ~= server then
            print(("Computer %d sent message %s"):format(id, message))
        end
        if message == "storageCraftingServer" then
            rednet.send(id, tostring(os.computerID()))
            local uniq = true
            for i in pairs(clients) do
                if clients[i] == id then
                    uniq = false
                end
            end
            if uniq then
                clients[#clients + 1] = id
            end
            print("")
            print("clients: ")
            for i in pairs(clients) do
                print(tostring(clients[i]))
            end
            print("")
        elseif message == "databaseReload" then
            reloadStorageDatabase()
        elseif message == "getRecipes" then
            rednet.send(id, recipes)
        elseif message == "craft" then
            turtle.craft()
        elseif message == "craftItem" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id2 == id
            print("Request to craft #" .. tostring(message2.amount) .. " " .. message2.name)
            log("Request to craft #" .. tostring(message2.amount) .. " " .. message2.name)
            reloadStorageDatabase()
            local ableToCraft = craftRecipe(message2, math.ceil(message2.amount / message2.count), id)
            if ableToCraft then
                print("Crafting Successful")
                rednet.send(id, true)
            else
                print("Crafting Failed!")
                rednet.send(id, false)
            end
        elseif message == "autoCraftItem" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id2 == id
            print("Request to autocraft #" .. tostring(message2.amount) .. " " .. message2.name)
            log("Request to autocraft #" .. tostring(message2.amount) .. " " .. message2.name)
            reloadStorageDatabase()
            local ableToCraft = craft(message2, message2.amount, id)
            if ableToCraft then
                print("Crafting Successful")
                rednet.send(id, true)
            else
                print("Crafting Failed!")
                rednet.send(id, false)
            end
        elseif message == "getAmount" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id2 == id
            local _, number = search(message2, items, 1)
            rednet.send(id, number)
        elseif message == "numNeeded" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id2 == id
            local amount = math.ceil(message2.amount / message2.count)
            rednet.send(id, calculateNumberOfItems(message2.recipe, amount))
        elseif message == "craftable" then
            local id2, message2
            local ttl = 5
            repeat
                id2, message2 = rednet.receive(nil, 0.5)
                if ttl < 1 then
                    break
                end
                ttl = ttl - 1
            until id2 == id
            local item = message2

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
                rednet.send(id, false)
            elseif #allRecipes < 1 then
                print("no recipes found for: " .. item)
                rednet.send(id, false)
            else
                local craftableRecipes = haveCraftingMaterials(allRecipes, 1)

                if #craftableRecipes > 0 then
                    rednet.send(id, craftableRecipes)
                else
                    print("0 craftable recipes")
                    log(textutils.serialise(allRecipes))
                    rednet.send(id, allRecipes)
                end
            end

        end
    end
end

log("~~Boot~~")

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

getRecipes()
broadcast()
reloadStorageDatabase()
local storage, items, storageUsed

print("")
print("Crafting Server Ready")
print("")

while true do
    if settings.get("debug") then
        --print(dump(recipes))
        parallel.waitForAny(debugMenu, serverHandler)
    else
        parallel.waitForAny(debugMenu, serverHandler)
        --serverHandler()
    end
    sleep(0.2)
end
