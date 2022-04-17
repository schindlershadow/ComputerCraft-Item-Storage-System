local clients = {}

--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("exportChests", { description = "The peripheral name of the export chest", { "minecraft:chest" }, type = "table" })
settings.define(
    "importChests",
    { description = "The peripheral name of the import chests", default = { "minecraft:chest_2" }, type = "table" }
)

--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    settings.set("debug", false)
    settings.set("exportChests", { "minecraft:chest" })
    settings.set("importChests", { "minecraft:chest_2" })
    print("Stop the server and edit .settings file with correct settings")
    settings.save()
    sleep(1)
end

--Open all modems to rednet
peripheral.find("modem", rednet.open)

--Table of all wired modems
local modems = {
    peripheral.find(
        "modem",
        function(name, modem)
            if modem.isWireless() then
                return false
            else
                return true
            end
        end
    )
}

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

local function getInputStorage()
    local storage = {}
    local peripherals = {}
    for _, modem in pairs(modems) do
        peripherals[#peripherals + 1] = modem.getNamesRemote()
        local remote = modem.getNamesRemote()
        for i in pairs(remote) do
            for k, chest in pairs(settings.get("importChests")) do
                if chest == remote[i] then
                    if modem.isPresentRemote(chest) then
                        storage[#storage + 1] = peripheral.wrap(remote[i])
                    end
                end
            end
        end
    end
    --print("getInputStorage: " .. dump(storage))
    return storage
end

local function getExportChests()
    local output = {}
    exportChests = settings.get("exportChests")
    for i, chest in pairs(exportChests) do
        output[#output + 1] = peripheral.wrap(chest)
    end
    return output
end

local function inExportChests(search)
    exportChests = settings.get("exportChests")
    for _, chest in pairs(exportChests) do
        if chest == search then
            return true
        end
    end
    return false
end

local function inImportChests(search)
    importChests = settings.get("importChests")
    for _, chest in pairs(importChests) do
        if chest == search then
            return true
        end
    end
    return false
end

--Returns list of storage peripherals excluding import and export chests
local function getStorage()
    local storage = {}
    local peripherals = {}
    local wrap = peripheral.wrap
    for _, modem in pairs(modems) do
        peripherals[#peripherals + 1] = modem.getNamesRemote()
        local remote = modem.getNamesRemote()
        for i in pairs(remote) do
            if modem.hasTypeRemote(remote[i], "inventory") then
                if inExportChests(remote[i]) == false and inImportChests(remote[i]) == false then
                    storage[#storage + 1] = wrap(remote[i])
                end
            end
        end
    end
    return storage
end

--gets the contents of a table of chests
local function getList(storage)
    local list = {}
    local itemCount = 0
    for _, chest in pairs(storage) do
        local tmpList = {}
        for slot, item in pairs(chest.list()) do
            item["slot"] = slot
            item["chestName"] = peripheral.getName(chest)
            if item.nbt ~= nil then
                item["details"] = peripheral.wrap(peripheral.getName(chest)).getItemDetail(slot)
            end
            itemCount = itemCount + item.count
            table.insert(list, item)
            --print(("%d x %s in slot %d"):format(item.count, item.name, slot))
        end
    end
    --[[
    table.sort(
        list,
        function(a, b)
            return a.count > b.count
        end
    )
    --]]

    return list, itemCount
end

function average(t)
    local sum = 0
    for _,v in pairs(t) do -- Get the sum of all numbers in t
      sum = sum + v
    end
    return sum / #t
  end

--loops all chests, adding together the number of slots and storage size of each. Note: MASSIVE performance hit on larger systems
local function getStorageSize(storage)
    --use local var for performance
    local workingStorage = storage
    local floor = math.floor
    local epoch = os.epoch
    local setCursorPos = term.setCursorPos
    local slots = 0
    local total = 0
    print("")
    print("")
    x, y = term.getSize()
    setCursorPos(1,y-1)
    write("Progress:      of " .. tostring(#storage) .. " storages processed")
    
    local time = epoch("utc")/1000
    local speedHistory = {}
    --for _, chest in pairs(workingStorage) do
    for i = 1, #workingStorage, 1 do
        setCursorPos(11,y-1)
        write(tostring(i))
        setCursorPos(1,y)
        local size = workingStorage[i].size()
        slots = slots + size
        local getItemLimit = workingStorage[i].getItemLimit
        for k = 1, size do
            total = total + getItemLimit(k)
        end
        local speed =  (epoch("utc")/1000) - time
        speedHistory[#speedHistory+1] = speed
        term.write(floor(speed * 1000) / 1000 .. " seconds per storage   ETA: " .. (floor((#storage-i)*average(speedHistory))) .. " seconds left                                        ")
        time = epoch("utc")/1000
    end
    return slots, total
end

--Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    write("Reloading database..")
    storage = getStorage()
    write("..")
    items, storageUsed = getList(storage)
    write("done\n")
end

local function search(string, InputTable)
    local filteredTable = {}
    local find = string.find
    local lower = string.lower
    for k, v in pairs(InputTable) do
        if find(lower(v["name"]), lower(string)) then
            filteredTable[#filteredTable + 1] = v
        end
    end
    if filteredTable == {} then
        return nil
    else
        return filteredTable
    end
end

--Looks for an item in a given table
local function searchForItem(item, InputTable)
    local filteredTable = {}
    --for k, v in pairs(InputTable) do
    for i = 1, #InputTable, 1 do
        if (item["name"] == InputTable[i]["name"]) then
            --if the item has NBT, dont mix it with the same item that does not have an NBT
            if (item["nbt"] ~= nil) and (InputTable[i]["nbt"] ~= nil) then
                if item["nbt"] == InputTable[i]["nbt"] then
                    filteredTable[#filteredTable + 1] = InputTable[i]
                end
            else
                filteredTable[#filteredTable + 1] = InputTable[i]
            end
        end
    end
    if not next(filteredTable) then
        return nil
    else
        return filteredTable
    end
end

--Finds next free space in system of an item
local function findFreeSpace(item, storage)
    local localStorage = storage
    local filteredTable = searchForItem(item, items)
    local getName = peripheral.getName
    local wrap = peripheral.wrap
    if filteredTable == nil then
        --Item not found in system
        --Find first chest with a free slot
        for k, chest in pairs(localStorage) do
            local list = chest.list()
            local size = chest.size()
            --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))
            for i = 1, size, 1 do
                if list[i] == nil then
                    --print("Found free slot at chest: " .. getName(chest) .. " Slot: " .. tostring(i))
                    return getName(chest), i
                end
            end
        end
    else
        --Item was found in the system
        --print("Item was found in the system")
        for k, v in pairs(filteredTable) do
            --text = v["name"] .. " #" .. v["count"]
            local limit = wrap(v["chestName"]).getItemLimit(v["slot"])
            --if the slot is not full, then it has free space
            --print("limit: " .. tostring(limit) .. " count: " .. tostring(v["count"]))
            if v["count"] ~= limit then
                return v["chestName"], v["slot"]
            end
        end
        --Find first chest with a free slot
        --print("Find first chest with a free slot")
        for k, chest in pairs(localStorage) do
            local list = chest.list()
            local size = chest.size()
            --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))
            for i = 1, size, 1 do
                if list[i] == nil then
                    --print("Found free slot at chest: " .. getName(chest) .. " Slot: " .. tostring(i))
                    return getName(chest), i
                end
            end
        end
    end
end

local function getItem(requestItem, chest)
    if inExportChests(chest) == false then
        print("ERROR: invaild export chest set on client")
        return
    end
    print(tostring(inExportChests(chest)))
    local amount = requestItem.count
    local filteredTable = search(requestItem.name, items)
    local wrap = peripheral.wrap
    for i, item in pairs(filteredTable) do
        if requestItem.nbt == nil then
            if item.count >= amount then
                print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                wrap(chest).pullItems(item["chestName"], item["slot"], amount)
                return
            else
                print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                wrap(chest).pullItems(item["chestName"], item["slot"])
                amount = amount - item.count
            end
        else
            if item.nbt == requestItem.nbt then
                if item.count >= amount then
                    print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                    wrap(chest).pullItems(item["chestName"], item["slot"], amount)
                    return
                else
                    print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                    wrap(chest).pullItems(item["chestName"], item["slot"])
                    amount = amount - item.count
                end
            end
        end
    end
    reloadStorageDatabase()
end

--debug function
local function find(all)
    print("Enter search term")
    local input = io.read()
    local filteredTable = search(input, items)
    print(dump(filteredTable[1]))

    if all then
        for k, v in pairs(filteredTable) do
            local text = ""
            if v["nbt"] == nil then
                text = v["name"] .. " #" .. v["count"]
            else
                print(dump(v))
            end
            print(text)
        end
    end
end

--debug function
local function get()
    print("Enter item")
    local input = io.read()
    local filteredTable = search(input, items)
    print("exporting " .. filteredTable[1]["name"])
    print(dump(filteredTable[1]))

    peripheral.wrap(settings.get("exportChest")).pullItems(filteredTable[1]["chestName"], filteredTable[1]["slot"])
    reloadStorageDatabase()
end

local function debugMenu()
    while true do
        --parallel.waitForAny(server, draw)
        print("Main menu")

        local input = io.read()
        if input == "find" then
            find(false)
        elseif input == "get" then
            get()
        elseif input == "findAll" then
            find(true)
        elseif input == "getItem" then
            getItem(true, settings.get("exportChests")[1])
        elseif input == "send" then
            --sendItem(true)
        elseif input == "exit" then
            os.queueEvent("terminate")
        end
        sleep(1)
    end
end

--Main loop for importing items into the system via defined import chests
local function importHandler()
    while true do
        local inputStorage = getInputStorage()
        local list = getList(inputStorage)
        --check if list is not empty
        --print(dump(list))
        if next(list) then
            local localStorage = storage
            for i, item in pairs(list) do
                --print("finding free space....")
                local chest, slot = findFreeSpace(item, storage)
                --print("chest: " .. tostring(chest) .. " slot: " .. tostring(slot))
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    reloadStorageDatabase()
                    --sleep(5)
                    --return
                else
                    --send to found slot
                    print("Import: " .. item.name .. " #" .. tostring(item.count))
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
            sleep(5)
        end

        sleep(0.2)
    end
end

local function storageHandler()
    while true do
        local id, message = rednet.receive()
        print(("Computer %d sent message %s"):format(id, message))
        if message == "storageServer" then
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
        elseif message == "getItems" then
            if settings.get("debug") then
                print(dump(items))
            end
            rednet.send(id, items)
        elseif message == "getItem" then
            local id2, message2 = rednet.receive()
            if settings.get("debug") then
                print(dump(message2))
            end
            local filteredTable = search(message2, items)
            rednet.send(id, filteredTable[1])
        elseif message == "import" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id == id2
            local inputStorage = getExportChests()
            local list = getList(inputStorage)
            local filteredTable = search(message2, list)
            for i, item in pairs(filteredTable) do
                local chest, slot = findFreeSpace(item, storage)
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    reloadStorageDatabase()
                    --sleep(5)
                else
                    --send to found slot
                    print("Import: " .. item.name .. " #" .. tostring(item.count))
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
        elseif message == "importAll" then
            local inputStorage = getExportChests()
            local list = getList(inputStorage)
            for i, item in pairs(list) do
                local chest, slot = findFreeSpace(item, storage)
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    sleep(5)
                else
                    --send to found slot
                    print("Import: " .. item.name .. " #" .. tostring(item.count))
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
        elseif message == "export" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id == id2

            print("Exporting Item(s): " .. dump(message2["item"]))
            getItem(message2["item"], message2["chest"])
            reloadStorageDatabase()
        elseif message == "storageUsed" then
            rednet.send(id, storageUsed)
        elseif message == "storageSize" then
            rednet.send(id, storageSize)
        elseif message == "storageMaxSize" then
            rednet.send(id, storageMaxSize)
        end
    end
end

term.clear()
print("debug mode: " .. tostring(settings.get("debug")))
print("exportChests are set to : " .. dump(settings.get("exportChests")))
print("importChests are set to: " .. dump(settings.get("importChests")))
print("")
print("Server is loading, please wait....")
--list of storage peripherals
storage = getStorage()
items, storageUsed = getList(storage)
storageMaxSize = 0
storageSize = 0
if settings.get("debug") == false then
    write("\nGetting storage size")
    storageSize, storageMaxSize = getStorageSize(storage)
    write("\ndone\n\n")
    print("Storage size is: " .. tostring(storageSize) .. " slots")
    print("Items in the system: " .. tostring(storageUsed) .. "/" .. tostring(storageMaxSize) .. " " .. tostring(("%.3g"):format((storageUsed / storageMaxSize)*100)) .. "% items")
else
    print("Items in the system: " .. tostring(storageUsed) .. " items")
end
print("")
print("Server Ready")
print("")


while true do
    if settings.get("debug") then
        parallel.waitForAll(debugMenu, storageHandler, importHandler)
    else
        parallel.waitForAll(storageHandler, importHandler)
    end
    sleep(1)
end
