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
    sleep(1)
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
    if type(text) == "string" then
        local logFile = fs.open("logs/crafting.csv", "a")
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. "," .. text)
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
        sleep(1)
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
    tab["recipe"] = recipe
    tab["recipeType"] = "shaped"
    if type(recipe[1][1]) == "table" then
        tab["recipeInput"] = "variable"
    else
        tab["recipeInput"] = "static"
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
    tab["recipe"] = recipe
    tab["recipeType"] = "shapeless"
    local isVar = false
    for i = 1, #recipe, 1 do
        if type(recipe[i]) == "table" then
            isVar = true
        end
    end
    if isVar then
        tab["recipeInput"] = "variable"
        tab["recipe"] = tab["recipe"][1]

        for i = 1, #tab["recipe"], 1 do
            if type(tab["recipe"][i]) ~= "table" then
                tab["recipe"][i] = { tab["recipe"][i] }
            end
        end
    else
        tab["recipeInput"] = "static"
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
            item["details"] = wrap(name).getItemDetail(slot)
            addTag(item)
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

local function getItems()
    rednet.send(server, "getItems")
    local id, message = rednet.receive(nil, 1)
    if type(message) == "table" then
        local filteredTable = {}
        for k, v in pairs(message) do
            table.insert(filteredTable, v)
        end
        local outputTable = removeDuplicates(filteredTable)
        return outputTable
    else
        sleep(0.2)
        return getItems()
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

local function search(searchTerm, InputTable, count)
    local stringSearch = string.match(searchTerm, 'item:(.+)')
    local find = string.find
    local lower = string.lower
    --print("need " .. tostring(count) .. " of " .. stringSearch)
    for k, v in pairs(InputTable) do
        if lower(v["name"]) == lower(stringSearch) and v.count >= count then
            --print("Found: " .. tostring(v.count) .. " of " .. v.name)
            return v
        end
    end
    return nil
end

local function searchForTag(string, InputTable, count)
    local find = string.find
    local match = string.match
    local stringTag = match(string, 'tag:%w+:(.+)')

    for k, v in pairs(InputTable) do
        if v.details then
            if v.details.tags then
                --print(stringTag .. " == " .. tostring(find(dump(v.details.tags),stringTag)))
                if v.details.tags[stringTag] and v.count >= count then
                    return v
                end

            end
        end
    end
    return nil
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

local function isTagCraftable(searchTerm, inputTable)
    local stringSearch = string.match(searchTerm, 'tag:%w+:(.+)')
    local items = {}
    print("searchTerm: " .. searchTerm)
    if type(tags[stringSearch]) ~= "nil" then
        --check tags database
        print("Checking tags database")
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
        return tab
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
        return tab
    end
end

local function patchStorageDatabase(itemName, count)
    local stringSearch = string.match(itemName, 'item:(.+)')
    if type(stringSearch) == "nil" then
        stringSearch = itemName
    end
    local find = string.find
    local lower = string.lower
    for k, v in pairs(items) do
        if find(lower(v["name"]), lower(stringSearch)) then
            items[k]["count"] = items[k]["count"] + count
            return 1
        end
    end
    return 0
end

local function dumpAll()
    for i = 1, 16, 1 do
        turtle.select(i)
        local item = turtle.getItemDetail(i)
        if type(item) ~= "nil" then
            patchStorageDatabase(item.name, item.count)
        end
        turtle.dropDown()
    end
end

--Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    write("Reloading database..")
    storage = getStorage()
    write("..")
    items, storageUsed = getList(storage)
    write("done\n")
    write("Writing Tags Database....")

    if fs.exists("tags.db") then
        fs.delete("tags.db")
    end
    local tagsFile = fs.open("tags.db", "w")
    tagsFile.write(textutils.serialise(tags))
    tagsFile.close()
    write("done\n")
    print("Items loaded: " .. tostring(storageUsed))
    print("Tags loaded: " .. tostring(tags.count))
    print("Tagged Items loaded: " .. tostring(tags.countItems))
end

local function craft(item)
    for i = 1, #recipes, 1 do
        if recipes[i]["name"] == item then
            print("Crafting: " .. item)
            --print(dump(recipes[i].recipe))

            --TODO: Check if every item exists in the system
            local numNeeded = {}
            if recipes[i].recipeType == "shaped" then
                for row = 1, #recipes[i].recipe do
                    for slot = 1, #recipes[i].recipe[row], 1 do
                        if recipes[i].recipe[row][slot] ~= "none" then
                            local recipeName = recipes[i].recipe[row][slot]
                            --print(dump(recipeName))
                            if type(recipeName) == "table" then
                                recipeName = recipeName[1]
                            end
                            if type(numNeeded[recipeName]) == "nil" then
                                numNeeded[recipeName] = 1
                            else
                                numNeeded[recipeName] = numNeeded[recipeName] + 1
                            end
                        end
                    end
                end
            else
                --shapeless recipes have no rows
                for slot = 1, #recipes[i].recipe, 1 do
                    if recipes[i].recipe[slot] ~= "none" then
                        local recipeName = recipes[i].recipe[slot]
                        if type(recipeName) == "table" then
                            recipeName = recipeName[1]
                        end
                        if type(numNeeded[recipeName]) == "nil" then
                            numNeeded[recipeName] = 1
                        else
                            numNeeded[recipeName] = numNeeded[recipeName] + 1
                        end
                    end
                end
            end

            print(recipes[i].recipeInput .. " crafting recipe")

            --Get items and craft
            if recipes[i].recipeInput == "static" then
                if recipes[i].recipeType == "shaped" then
                    for row = 1, #recipes[i].recipe do
                        for slot = 1, #recipes[i].recipe[row], 1 do
                            --print("Do we have " .. recipes[i].recipe[row][slot] .. " ?")
                            --print("row " .. row .. " slot " .. slot)
                            if recipes[i].recipe[row][slot] ~= "none" then

                                turtle.select(((row - 1) * 4) + slot)
                                local searchResult
                                print("need #" .. tostring(numNeeded[recipes[i].recipe[row][slot]]) .. " " .. recipes[i].recipe[row][slot])
                                if string.find(recipes[i].recipe[row][slot], "tag:") then
                                    searchResult = searchForTag(recipes[i].recipe[row][slot], items, numNeeded[recipes[i].recipe[row][slot]])
                                else
                                    searchResult = search(recipes[i].recipe[row][slot], items, numNeeded[recipes[i].recipe[row][slot]])
                                end

                                --print(dump(searchResult))
                                log(dump(searchResult))
                                --print(tostring(type(searchResult)))
                                if type(searchResult) == "nil" then
                                    print("Cannot find enough " .. recipes[i].recipe[row][slot] .. " in system")
                                    dumpAll()

                                    local redoItem = ""
                                    if string.find(recipes[i].recipe[row][slot], "tag:") then
                                        redoItem = isTagCraftable(recipes[i].recipe[row][slot], items)
                                    else
                                        redoItem = isCraftable(recipes[i].recipe[row][slot])
                                    end

                                    if type(redoItem) ~= "boolean" then
                                        print(dump(redoItem))
                                        for redos = 1, #redoItem, 1 do
                                            print("Attempting to craft " .. redoItem[redos])
                                            local ableToCraft = craft(redoItem[redos])
                                            if ableToCraft ~= 0 then
                                                --sleep to let the storage server catch up
                                                sleep(1)
                                                print("Try to craft original item")
                                                ableToCraft = craft(item)
                                                if ableToCraft ~= 0 then
                                                    return 1
                                                else
                                                    print("Failed")
                                                end
                                            end
                                        end
                                        return 0
                                    else
                                        return 0
                                    end


                                else
                                    print("Getting: " .. searchResult.name)
                                    local itemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                    if itemsMoved < 1 then
                                        reloadStorageDatabase()
                                        peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                    end
                                    turtle.suckUp()
                                    if type(turtle.getItemDetail()) == "nil" then
                                        print("failed to get item")
                                        dumpAll()
                                        return 0
                                    end
                                    local success = patchStorageDatabase(searchResult.name, -1)
                                    if success == 0 then
                                        reloadStorageDatabase()
                                    end
                                    numNeeded[recipes[i].recipe[row][slot]] = numNeeded[recipes[i].recipe[row][slot]] - 1
                                end
                            end
                        end
                    end
                else
                    for slot = 1, #recipes[i].recipe, 1 do
                        --print("Do we have " .. recipes[i].recipe[row][slot] .. " ?")
                        --print("row " .. row .. " slot " .. slot)
                        if recipes[i].recipe[slot] ~= "none" then
                            if slot > 3 then
                                turtle.select(((math.floor(slot / 3)) * 4) + slot)
                            else
                                turtle.select(slot)
                            end

                            local searchResult
                            --print("need #" .. tostring(numNeeded[recipes[i].recipe[slot]]) .. " " .. recipes[i].recipe[slot])
                            if string.find(recipes[i].recipe[slot], "tag:") then
                                searchResult = searchForTag(recipes[i].recipe[slot], items, numNeeded[recipes[i].recipe[slot]])
                            else
                                searchResult = search(recipes[i].recipe[slot], items, numNeeded[recipes[i].recipe[slot]])
                            end

                            --print(dump(searchResult))
                            log(dump(searchResult))
                            print(tostring(type(searchResult)))
                            if type(searchResult) == "nil" then
                                print("Cannot find enough " .. recipes[i].recipe[slot] .. " in system")
                                dumpAll()
                                local redoItem = ""
                                if string.find(recipes[i].recipe[slot], "tag:") then
                                    redoItem = isTagCraftable(recipes[i].recipe[slot], items)
                                else
                                    redoItem = isCraftable(recipes[i].recipe[slot])
                                end

                                if redoItem then
                                    for redos = 1, #redoItem, 1 do
                                        print("Attempting to craft " .. redoItem[redos])
                                        local ableToCraft = craft(redoItem[redos])
                                        if ableToCraft ~= 0 then
                                            --sleep to let the storage server catch up
                                            sleep(1)
                                            ableToCraft = craft(item)
                                            if ableToCraft ~= 0 then
                                                return 1
                                            end
                                        end
                                    end
                                    return 0
                                else
                                    return 0
                                end
                            else
                                print("Getting: " .. searchResult.name)
                                local itemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                if itemsMoved < 1 then
                                    reloadStorageDatabase()
                                    peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                end
                                turtle.suckUp()
                                if type(turtle.getItemDetail()) == "nil" then
                                    print("failed to get item")
                                    dumpAll()
                                    return 0
                                end
                                local success = patchStorageDatabase(searchResult.name, -1)
                                if success == 0 then
                                    reloadStorageDatabase()
                                end
                                numNeeded[recipes[i].recipe[slot]] = numNeeded[recipes[i].recipe[slot]] - 1
                            end
                        end
                    end
                end
            else
                --Crafting type is variable meaning recipe can have different materals to make the same item
                --print(dump(recipes[i]))
                if recipes[i].recipeType == "shaped" then
                    for row = 1, #recipes[i].recipe do
                        for slot = 1, #recipes[i].recipe[row], 1 do
                            --print("Do we have " .. recipes[i].recipe[row][slot] .. " ?")
                            --print("row " .. row .. " slot " .. slot)
                            if recipes[i].recipe[row][slot][1] ~= "none" then

                                turtle.select(((row - 1) * 4) + slot)
                                local searchResult = {}
                                local found = false

                                for k = 1, #recipes[i].recipe[row][slot], 1 do
                                    --print(dump(recipes[i].recipe[row][slot]))
                                    print("need #" .. tostring(numNeeded[recipes[i].recipe[row][slot][1]]) .. " " .. tostring(recipes[i].recipe[row][slot][k]))

                                    if string.find(recipes[i].recipe[row][slot][k], "tag:") then
                                        searchResult[k] = searchForTag(recipes[i].recipe[row][slot][k], items, numNeeded[recipes[i].recipe[row][slot][1]])
                                    else
                                        searchResult[k] = search(recipes[i].recipe[row][slot][k], items, numNeeded[recipes[i].recipe[row][slot][1]])
                                    end
                                    if type(searchResult[k]) ~= "nil" then
                                        found = true
                                    end


                                end

                                --print(dump(searchResult))
                                log(dump(searchResult))
                                --print(tostring(type(searchResult)))
                                if found == false then
                                    print("Cannot find enough " .. recipes[i].recipe[row][slot][1] .. " in system")
                                    dumpAll()

                                    local redoItem = {}
                                    for k = 1, #recipes[i].recipe[row][slot], 1 do
                                        if string.find(recipes[i].recipe[row][slot][k], "tag:") then
                                            redoItem[k] = isTagCraftable(recipes[i].recipe[row][slot][k], items)
                                        else
                                            redoItem[k] = isCraftable(recipes[i].recipe[row][slot][k])
                                        end

                                        if redoItem[k] then
                                            for redos = 1, #redoItem[k], 1 do
                                                print("Attempting to craft " .. redoItem[k][redos])
                                                local ableToCraft = craft(redoItem[k][redos])
                                                if ableToCraft ~= 0 then
                                                    --sleep to let the storage server catch up
                                                    sleep(1)
                                                    ableToCraft = craft(item)
                                                    if ableToCraft ~= 0 then
                                                        return 1
                                                    end
                                                end
                                            end
                                        else

                                        end
                                    end
                                    return 0


                                else
                                    local selected = 0
                                    for k = 1, #searchResult, 1 do
                                        if searchResult[k] ~= nil then
                                            searchResult = searchResult[k]
                                            selected = k
                                        end
                                    end
                                    print("Getting: " .. searchResult.name)
                                    local itemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                    if itemsMoved < 1 then
                                        reloadStorageDatabase()
                                        peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                    end
                                    turtle.suckUp()
                                    if type(turtle.getItemDetail()) == "nil" then
                                        print("failed to get item")
                                        dumpAll()
                                        return 0
                                    end
                                    local success = patchStorageDatabase(searchResult.name, -1)
                                    if success == 0 then
                                        reloadStorageDatabase()
                                    end
                                    numNeeded[recipes[i].recipe[row][slot][1]] = numNeeded[recipes[i].recipe[row][slot][1]] - 1
                                end
                            end
                        end
                    end
                else
                    print(dump(recipes[i].recipe))
                    for slot = 1, #recipes[i].recipe, 1 do
                        --print("Do we have " .. recipes[i].recipe[row][slot] .. " ?")
                        --print("row " .. row .. " slot " .. slot)
                        if recipes[i].recipe[slot][1] ~= "none" then

                            if slot > 3 then
                                turtle.select(((math.floor(slot / 3)) * 4) + slot)
                            else
                                turtle.select(slot)
                            end
                            local searchResult = {}
                            local found = false

                            for k = 1, #recipes[i].recipe[slot], 1 do
                                --print(dump(recipes[i].recipe[row][slot]))
                                print("need #" .. tostring(numNeeded[recipes[i].recipe[slot][1]]) .. " " .. tostring(recipes[i].recipe[slot][k]))

                                if string.find(recipes[i].recipe[slot][k], "tag:") then
                                    searchResult[k] = searchForTag(recipes[i].recipe[slot][k], items, numNeeded[recipes[i].recipe[slot][1]])
                                else
                                    searchResult[k] = search(recipes[i].recipe[slot][k], items, numNeeded[recipes[i].recipe[slot][1]])
                                end
                                if type(searchResult[k]) ~= "nil" then
                                    found = true
                                end


                            end

                            --print(dump(searchResult))
                            log(dump(searchResult))
                            --print(tostring(type(searchResult)))
                            if found == false then
                                print("Cannot find enough " .. recipes[i].recipe[slot][1] .. " in system")
                                dumpAll()

                                local redoItem = {}
                                for k = 1, #recipes[i].recipe[slot], 1 do
                                    if string.find(recipes[i].recipe[slot][k], "tag:") then
                                        redoItem[k] = isTagCraftable(recipes[i].recipe[slot][k], items)
                                    else
                                        redoItem[k] = isCraftable(recipes[i].recipe[slot][k])
                                    end

                                    if redoItem[k] then
                                        for redos = 1, #redoItem[k], 1 do
                                            print("Attempting to craft " .. redoItem[k][redos])
                                            local ableToCraft = craft(redoItem[k][redos])
                                            if ableToCraft ~= 0 then
                                                --sleep to let the storage server catch up
                                                sleep(1)
                                                ableToCraft = craft(item)
                                                if ableToCraft ~= 0 then
                                                    return 1
                                                end
                                            end
                                        end

                                    else

                                    end
                                end
                                return 0


                            else
                                local selected = 0
                                for k = 1, #searchResult, 1 do
                                    if searchResult[k] ~= nil then
                                        searchResult = searchResult[k]
                                        selected = k
                                    end
                                end
                                print("Getting: " .. searchResult.name)
                                local itemsMoved = peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                if itemsMoved < 1 then
                                    reloadStorageDatabase()
                                    peripheral.wrap(settings.get("craftingChest")).pullItems(searchResult["chestName"], searchResult["slot"], 1)
                                end
                                turtle.suckUp()
                                if type(turtle.getItemDetail()) == "nil" then
                                    print("failed to get item")
                                    dumpAll()
                                    return 0
                                end
                                local success = patchStorageDatabase(searchResult.name, -1)
                                if success == 0 then
                                    reloadStorageDatabase()
                                end
                                numNeeded[recipes[i].recipe[slot][1]] = numNeeded[recipes[i].recipe[slot][1]] - 1
                            end
                        end
                    end
                end

            end
            turtle.craft()
            local craftedItem = turtle.getItemDetail()
            dumpAll()
            if type(craftedItem) == "nil" then
                return 0
            end
            local success = patchStorageDatabase(craftedItem.name, craftedItem.count)
            if success == 0 then
                reloadStorageDatabase()
            end
            return 1
        end
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
            local input2 = io.read()
            if string.find(input2, ':') then
                print("Crafting: " .. (input2))
                reloadStorageDatabase()
                local ableToCraft = craft(input2)
                if ableToCraft ~= 0 then
                    print("Crafting Successful")
                else
                    print("Crafting Failed!")
                end
            else
                for i = 1, #recipes, 1 do
                    if string.find(recipes[i].name, input2) then
                        print("Crafting: " .. (recipes[i].name))
                        reloadStorageDatabase()
                        local ableToCraft = craft(recipes[i].name)
                        if ableToCraft ~= 0 then
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
                    log(dump(recipes[i]))
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
        print(("Computer %d sent message %s"):format(id, message))
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
        elseif message == "craft" then
            turtle.craft()
        elseif message == "craftItem" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id2 == id
            reloadStorageDatabase()
            local ableToCraft = craft(message2)
            if ableToCraft ~= 0 then
                print("Crafting Successful")
            else
                print("Crafting Failed!")
            end
        end
    end
end

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
local storage, items, storageUsed

print("")
print("Crafting Server Ready")
print("")

while true do
    if settings.get("debug") then
        print(dump(recipes))
        parallel.waitForAny(debugMenu, serverHandler)
    else
        parallel.waitForAny(debugMenu, serverHandler)
        --serverHandler()
    end
    sleep(1)
end
