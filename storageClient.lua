local modem = peripheral.find("modem", rednet.open)
local width, height = term.getSize()
local server = 0
local craftingServer = 0
local search = ""
local items = {}
local recipes = {}
local displayedRecipes = {}
local menu = false
local menuSel = "storage"

-- Settings
--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("crafting", { description = "Enables crafting support", default = "false", type = "boolean" })
settings.define("exportChestName", { description = "Name of the export chest for this client", default = "minecraft:chest", type = "string" })

local logging = true
local debug = false

--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    settings.set("debug", false)
    settings.set("crafting", false)
    settings.set("exportChestName", "minecraft:chest")
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
    if type(text) == "string" and logging then
        local logFile = fs.open("logs/RSclient.csv", "a")
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. "," .. text)
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

local function broadcastStorageServer()
    print("Searching for storageServer server")
    rednet.broadcast("storageServer")
    local id, message = rednet.receive(nil, 5)
    if type(tonumber(message)) == "number" and id == tonumber(message) then
        print("Server set to: " .. tostring(message))
        server = tonumber(message)
        return tonumber(message)
    else
        sleep(1)
        return broadcastStorageServer()
    end
end

local function getRecipes()
    rednet.send(craftingServer, "getRecipes")
    local id, message = rednet.receive(nil, 1)
    if type(message) == "table" and id == craftingServer then
        table.sort(message, function(a, b)
            return a.name < b.name
        end)

        return message



    else
        sleep(0.2)
        return getRecipes()
    end
end

local function broadcastCraftingServer()
    if settings.get("crafting") then
        print("Searching for storageCraftingServer server")
        rednet.broadcast("storageCraftingServer")
        local id, message = rednet.receive(nil, 5)
        if type(tonumber(message)) == "number" and id == tonumber(message) then
            print("Server set to: " .. tostring(message))
            craftingServer = tonumber(message)
            recipes = getRecipes()
            return tonumber(message)
        else
            sleep(1)
            return broadcastCraftingServer()
        end
    else
        return 0
    end
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

local function getItems()
    rednet.send(server, "getItems")
    local id, message = rednet.receive(nil, 1)
    if type(message) == "table" and id == server then
        if search == "" then
            return removeDuplicates(message)
        end
        local filteredTable = {}
        for k, v in pairs(message) do
            if v["details"] == nil then
                if string.find(string.lower(v["name"]), string.lower(search)) or string.find(string.lower(v["name"]), string.lower(search:gsub(" ", "_"))) then
                    table.insert(filteredTable, v)
                end
            elseif string.find(string.lower(v["details"]["displayName"]), string.lower(search)) or string.find(string.lower(v["details"]["displayName"]), string.lower(search:gsub(" ", "_"))) then
                table.insert(filteredTable, v)
            end
        end
        local outputTable = removeDuplicates(filteredTable)
        return outputTable
    else
        sleep(0.2)
        return getItems()
    end
end

local function import(item)
    rednet.send(server, "import")
    rednet.send(server, item:getTable())
end

local function importAll()
    rednet.send(server, "importAll")
end

local function export(item)
    rednet.send(server, "export")
    rednet.send(server, { item = item:getTable(), chest = settings.get("exportChestName") })
end

local function centerText(text)
    local x, y = term.getSize()
    local x1, y1 = term.getCursorPos()
    term.setCursorPos((math.floor(x / 2) - (math.floor(#text / 2))), y1)
    write(text)
end

local function drawNBTmenu(sel)
    local amount = 1
    local done = false
    while done == false do
        term.setBackgroundColor(colors.green)
        for k = 1, height - 1, 1 do
            for i = 1, width, 1 do
                term.setCursorPos(i, k)
                term.write(" ")
            end
        end
        term.setCursorPos(1, 1)
        centerText("NBT Menu")
        term.setCursorPos(1, 2)
        centerText(items[sel].name .. " #" .. tostring(items[sel].count))
        term.setCursorPos(1, 3)
        if items[sel].nbt ~= nil then
            write(dump(items[sel].details))
        end
        term.setCursorPos(width, 1)
        term.setBackgroundColor(colors.red)
        term.write("x")
        term.setBackgroundColor(colors.green)


        local event, button, x, y = os.pullEvent("mouse_click")

        if y < 2 and x > width - 1 then
            done = true
        end

        --sleep(5)
    end
end

local function craftRecipe(recipe, amount)
    rednet.send(craftingServer, "craftItem")
    sleep(0.1)
    recipe.amount = amount
    rednet.send(craftingServer, recipe)
    term.clear()
    term.setCursorPos(1, 1)
    term.write("Crafting....")
    local id, message
    repeat
        id, message = rednet.receive()
        term.write(".")
    until id == craftingServer
    if message == true then
        term.write("\n\nCrafting Complete! :D")
    else
        term.write("\n\nCrafting Failed! D:")
    end
    sleep(5)

    return message
end

local function getAmount(itemName)
    rednet.send(craftingServer, "getAmount")
    sleep(0.1)
    rednet.send(craftingServer, itemName)
    local id2, message2
    repeat
        id2, message2 = rednet.receive()
    until id2 == craftingServer and type(message2) == "number"
    return message2
end

local function isCraftable(itemName)
    rednet.send(craftingServer, "craftable")
    sleep(0.1)
    rednet.send(craftingServer, itemName)
    local id2, message2
    repeat
        id2, message2 = rednet.receive()
    until id2 == craftingServer and (type(message2) == "bool" or type(message2) == "table")
    return message2
end

local function drawCraftingMenu(sel, inputTable)
    if type(inputTable) ~= "nil" then
        local displayedRecipes = inputTable
    end
    local amount = 1
    done = false
    while done == false do
        rednet.send(craftingServer, "numNeeded")
        sleep(0.1)
        displayedRecipes[sel].amount = amount
        rednet.send(craftingServer, displayedRecipes[sel])
        local id2, message2
        repeat
            id2, message2 = rednet.receive()
        until id2 == craftingServer and type(message2) == "table"
        local numNeeded = message2

        local legend = {}
        local keys = {}
        local canCraft = true
        local count = 0
        for i, v in pairs(numNeeded) do
            count = count + 1
            legend[count] = {}
            legend[count].item = i
            legend[count].count = v
            legend[count].have = getAmount(i)
            keys[i] = count

            if legend[count].have < legend[count].count then
                canCraft = false
            end
        end

        term.setBackgroundColor(colors.green)
        for k = 1, height - 1, 1 do
            for i = 1, width, 1 do
                term.setCursorPos(i, k)
                term.write(" ")
            end
        end
        term.setCursorPos(1, 1)
        centerText("Crafting Menu")
        term.setCursorPos(1, 2)
        centerText(displayedRecipes[sel].name .. " #" .. tostring(displayedRecipes[sel].count))
        term.setCursorPos(1, (height * .25))
        term.setBackgroundColor(colors.gray)
        print("       ")
        term.setCursorPos(1, (height * .25) + 1)
        term.setCursorPos(1, 1)
        --print(textutils.serialise(displayedRecipes[sel].recipe))
        --sleep(10)

        local pos = 1
        for row = 1, 3, 1 do
            if row == 1 then
                term.setCursorPos(1, (height * .25) + row)
            else
                term.setCursorPos(1, (height * .25) + row + pos)
                pos = pos + 1
            end
            term.setBackgroundColor(colors.gray)
            term.write(" ")
            if type(displayedRecipes[sel].recipe[row]) == "nil" then
                term.setBackgroundColor(colors.black)
                term.write(" ")
                term.setBackgroundColor(colors.gray)
                term.write(" ")
                term.setBackgroundColor(colors.black)
                term.write(" ")
                term.setBackgroundColor(colors.gray)
                term.write(" ")
                term.setBackgroundColor(colors.black)
                term.write(" ")
            else
                for slot = 1, 3, 1 do
                    term.setBackgroundColor(colors.black)
                    if type(displayedRecipes[sel].recipe[row][slot]) == "nil" then
                        term.write(" ")
                    else
                        --log(textutils.serialise(displayedRecipes[sel].recipe[row][slot][1]))
                        if displayedRecipes[sel].recipe[row][slot][1] == "none" then
                            term.write(" ")
                        else
                            term.write(utf8.char(keys[displayedRecipes[sel].recipe[row][slot][1]] + 64))
                        end
                    end
                    if slot ~= 3 then
                        term.setBackgroundColor(colors.gray)
                        term.write(" ")
                    end
                end
            end
            term.setBackgroundColor(colors.gray)
            term.write(" ")

            term.setCursorPos(1, (height * .25) + row + pos)
            print("       ")
        end



        for i = 1, #legend, 1 do
            term.setCursorPos(9, (height * .25) + (i - 1))
            --log(tostring(getAmount(legend[i].item)))
            if legend[i].count < legend[i].have then
                term.setBackgroundColor(colors.green)
            else
                term.setBackgroundColor(colors.red)
            end
            term.write(utf8.char(i + 64) .. ": " .. legend[i].item:match(":([%w,_]*)$") .. " - Need #" .. tostring(legend[i].count) .. " Have #" .. tostring(legend[i].have) .. " ")
            --term.write(utf8.char(i + 64) .. ": #" .. legend[i].count .. " " .. legend[i].item)
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

        if debug then
            event, button, x, y = os.pullEvent("mouse_click")
            term.setCursorPos(x, y)
            term.write("? " .. tostring(x) .. " " .. tostring(y))
            sleep(5)
        else
            event, button, x, y = os.pullEvent("mouse_click")
        end
        log(tostring(x) .. " " .. tostring(y) .. " " .. tostring((height * .25)))

        --if x > 8 and y >= (height * .25) and y < (height * .25) + 8 and type(legend[y - math.ceil((height * .25))]) ~= "nil" then
        if x > 8 and y >= 4 and y <= 4 + 8 and type(legend[y-4]) ~= "nil" then
            --log(legend[y - math.ceil((height * .25))].item)
            --local craftable = isCraftable(legend[y - math.ceil((height * .25))].item)
            local craftable = isCraftable(legend[y - 4].item)
            if craftable ~= false then
                drawCraftingMenu(1, { craftable })
            end
        elseif (x == (width * .25) and y == height - (height * .25) + 2)
        then
            if amount > 1 then
                amount = amount - 1
            end
        elseif (x == width - (width * .25) and y == height - (height * .25) + 2)
        then
            amount = amount + 1
        elseif (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and (y == height - (height * .25) + 3))
        then
            amount = amount + 64
        elseif (((x < ((width * .25) * 2) + 3) and (x > ((width * .25) * 2) - 3)) and
            (y == height - (height * .25) + 3))
        then
            if amount > 1 + 64 then
                amount = amount - 64
            else
                amount = 1
            end
        elseif (x == (width * .25) * 3 and y == height - (height * .25) + 3)
        then
            amount = 1
        elseif y == (height - 1) then
            done = true
            craftRecipe(displayedRecipes[sel], amount)
        elseif y < 2 and x > width - 1 then
            done = true
        end

        --sleep(5)
    end
end

local function drawMenu(sel)
    local amount = 1
    done = false
    while done == false do
        term.setBackgroundColor(colors.green)
        for k = 1, height - 1, 1 do
            for i = 1, width, 1 do
                term.setCursorPos(i, k)
                term.write(" ")
            end
        end
        term.setCursorPos(1, 1)
        centerText("Menu")
        term.setCursorPos(1, 2)
        centerText(items[sel].name .. " #" .. tostring(items[sel].count))
        term.setCursorPos(1, 3)
        if items[sel].nbt ~= nil then
            term.setBackgroundColor(colors.red)
            centerText("Show NBT tags")
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
        centerText("Request")

        local event, button, x, y

        if debug then
            term.setCursorPos((width * .25) + 2, (height * .25) + 4)
            term.write("X")
            term.setCursorPos((width * .25) - 2, (height * .25) + 6)
            term.write("Y")

            term.setCursorPos(width - (width * .25) + 2, ((height * .25) + 4))
            term.write("X")
            term.setCursorPos((width - (width * .25)) - 2, (height * .25) + 6)
            term.write("Y")

            event, button, x, y = os.pullEvent("mouse_click")
            term.setCursorPos(x, y)
            term.write("? " .. tostring(x) .. " " .. tostring(y))
            sleep(5)
        else
            event, button, x, y = os.pullEvent("mouse_click")
        end

        if (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and
            ((y > (height * .25) + 4) and (y < (height * .25) + 6)))
        then
            if amount > 1 then
                amount = amount - 1
            end
        elseif (((x < (width - (width * .25)) + 2) and (x > (width - (width * .25)) - 2)) and
            ((y > (height * .25) + 4) and (y < (height * .25) + 6)))
        then
            if amount < items[sel].count then
                amount = amount + 1
            end
        elseif (((x < (width * .25) + 2) and (x > (width * .25) - 2)) and
            ((y > (height * .25) + 6) and (y < (height * .25) + 10)))
        then
            if amount + 64 < items[sel].count then
                amount = amount + 64
            else
                amount = items[sel].count
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
            amount = items[sel].count
        elseif y == (height - 1) then
            done = true
            local result
            if items[sel].nbt == nil then
                result = Item:new(items[sel].name, amount, "", items[sel].tags)
            else
                result = Item:new(items[sel].name, amount, items[sel].nbt, items[sel].tags)
            end
            export(result)
        elseif y < 2 and x > width - 1 then
            done = true
        elseif y == 3 then
            drawNBTmenu(sel)
        end

        --sleep(5)
    end
end

local function drawList()
    if menu == false then
        if menuSel == "storage" then
            items = getItems()
            table.sort(
                items,
                function(a, b)
                return a.count > b.count
            end
            )
            term.setBackgroundColor(colors.blue)
            for k = 1, height - 1, 1 do
                for i = 1, width, 1 do
                    term.setCursorPos(i, k)
                    term.write(" ")
                end
            end
            for k, v in pairs(items) do
                if k < height then
                    local text = ""

                    if v["nbt"] ~= nil then
                        text = v["details"]["displayName"] .. " - #" .. v["count"] .. " " .. dump(v["details"])
                    elseif v["details"] == nil then
                        text = v["name"] .. " - #" .. v["count"]
                    else
                        if v["details"]["tags"] ~= nil then
                            text = v["details"]["displayName"] .. " - #" .. v["count"] .. " " .. dump(v["details"]["tags"])
                        else
                            text = v["details"]["displayName"] .. " - #" .. v["count"]
                        end
                    end

                    term.setCursorPos(1, k)
                    term.write(text)
                    term.setCursorPos(1, height)
                end
            end
        elseif menuSel == "crafting" then

            local filteredRecipes = {}
            for k, v in pairs(recipes) do
                if string.find(string.lower(v["name"]), string.lower(search)) or string.find(string.lower(v["name"]), string.lower(search:gsub(" ", "_"))) then
                    filteredRecipes[#filteredRecipes + 1] = v
                end
            end
            term.setBackgroundColor(colors.blue)
            for k = 1, height - 1, 1 do
                for i = 1, width, 1 do
                    term.setCursorPos(i, k)
                    term.write(" ")
                end
            end
            for k, recipe in pairs(filteredRecipes) do
                if k < height then
                    term.setCursorPos(1, k)
                    term.write(recipe.name .. " #" .. tostring(recipe.count) .. " - " .. recipe.recipeName:match("(.*):"))
                    term.setCursorPos(1, height)
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

    --sleep(5)
end

local function inputHandler()
    while true do
        local event, key
        repeat
            event, key = os.pullEvent()
        until event ~= "char" or event ~= "key"
        if event == "char" or event == "key" then
            --term.setCursorPos(1,height)
            if event == "char" then
                search = search .. key
            elseif key == keys.backspace then
                search = search:sub(1, -2)
            elseif key == keys.enter or key == keys.numPadEnter then
                drawList()
            elseif key == keys.tab then
                if menuSel == "storage" then
                    menuSel = "crafting"
                elseif menuSel == "crafting" then
                    menuSel = "storage"
                end
                drawList()
            elseif key == keys.delete then
                search = ""
                drawList()
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

local function touchHandler()
    local event, button, x, y = os.pullEvent("mouse_click")
    if y == height - 1 and x > width - 8 then
        --Import button pressed
        importAll()

    elseif settings.get("crafting") == true and y == height - 2 and x > width - 8 then
        --Storage menu button pressed
        menuSel = "storage"
        drawList()
    elseif settings.get("crafting") == true and y == height - 3 and x > width - 8 then
        --Crafting menu button pressed
        menuSel = "crafting"
        drawList()
    elseif (items[y] ~= nil or displayedRecipes[y] ~= nil) and y ~= height then
        menu = true
        if menuSel == "crafting" then
            drawCraftingMenu(y)
        else
            drawMenu(y)
        end

        menu = false
        term.clear()
        term.setCursorPos(1, 1)
        centerText("Requesting...")
        sleep(0.1)
        drawList()
        -- export(result)
    end
end

broadcastStorageServer()
broadcastCraftingServer()
term.clear()
term.setCursorPos(1, 1)
drawList()

term.setBackgroundColor(colors.black)
for i = 1, width, 1 do
    term.setCursorPos(i, height)
    term.write(" ")
end

while true do
    parallel.waitForAny(touchHandler, inputHandler)

    --inputHandler()
    sleep(0.1)
end
