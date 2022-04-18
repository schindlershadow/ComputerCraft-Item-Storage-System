local modem = peripheral.find("modem", rednet.open)
local width, height = term.getSize()
local server = 0
local search = ""
local items = {}
local menu = false

-- Settings
--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("exportChestName", { description = "Name of the export chest for this client", default = "minecraft:chest", type = "string" })

local logging = true
local debug = false

--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    settings.set("debug", false)
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
    --print("got " .. tostring(message) .. " type " .. type(message))
    if type(message) == "table" then
        if search == "" then
            return removeDuplicates(message)
        end
        local filteredTable = {}
        for k, v in pairs(message) do
            if v["details"] == nil then
                if string.find(string.lower(v["name"]), string.lower(search)) then
                    table.insert(filteredTable, v)
                end
            elseif string.find(string.lower(v["details"]["displayName"]), string.lower(search)) then
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
        --import
        term.setCursorPos(width - 5, height - 1)
        term.setBackgroundColor(colors.red)
        term.write("Import")
        term.setBackgroundColor(colors.blue)
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
            elseif key == keys.enter then
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
    if y == height - 1 and x > width - 6 then

        importAll()

    elseif items[y] ~= nil and y ~= height then
        menu = true
        drawMenu(y)
        menu = false
        term.clear()
        term.setCursorPos(1, 1)
        centerText("Requesting...")
        sleep(0.1)
        drawList()
        -- export(result)
    end
end

broadcast()
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
    sleep(1)
end
