local clients = {}

--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("exportChest", { description = "The peripheral name of the export chest", default = "", type = "string" })
settings.define(
    "importChests",
    { description = "The peripheral name of the import chests", default = { "minecraft:chest_2" }, type = "table" }
)

--Settings failes to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    settings.set("debug", false)
    settings.set("exportChest", "minecraft:chest")
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
        table.insert(peripherals, modem.getNamesRemote())
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

local function inImportChests(search)
    importChests = settings.get("importChests")
    for i, chest in pairs(importChests) do
        if chest == search then
            return true
        end
    end
    return false
end

local function getStorage()
    local storage = {}
    local peripherals = {}
    for _, modem in pairs(modems) do
        table.insert(peripherals, modem.getNamesRemote())
        local remote = modem.getNamesRemote()
        for i in pairs(remote) do
            if modem.hasTypeRemote(remote[i], "inventory") then
                if remote[i] ~= settings.get("exportChest") and inImportChests(remote[i]) == false then
                    storage[#storage + 1] = peripheral.wrap(remote[i])
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
            item["details"] = peripheral.wrap(peripheral.getName(chest)).getItemDetail(slot)
            itemCount = itemCount + item.count
            table.insert(list, item)
            --print(("%d x %s in slot %d"):format(item.count, item.name, slot))
        end
    end
    table.sort(
        list,
        function(a, b)
            return a.count > b.count
        end
    )

    return list, itemCount
end

local function getStorageSize(storage)
    local slots = 0
    local total = 0
    for _, chest in pairs(storage) do
        slots = slots + chest.size()
        for i = 1, chest.size() do
            total = total + chest.getItemLimit(i)
        end
    end
    return slots, total
end

local function reloadStorageDatabase()
    print("getting storage...")
    storage = getStorage()
    print("getting list of all items from storage...")
    items, storageUsed = getList(storage)
    print("done")
end

local function getItemLimit(search, storage, slot)
    local number = 0
    for _, chest in pairs(storage) do
        if chest["chestName"] == search then
            number = peripheral.wrap(chest["chestName"]).getItemLimit(slot)
        end
    end
    if number == 0 then
        return nil
    else
        return number
    end
end

local function search(string, InputTable)
    local filteredTable = {}
    for k, v in pairs(InputTable) do
        if string.find(string.lower(v["name"]), string.lower(string)) then
            table.insert(filteredTable, v)
        end
    end
    if filteredTable == {} then
        return nil
    else
        return filteredTable
    end
end

local function searchForItem(item, InputTable)
    local filteredTable = {}
    for k, v in pairs(InputTable) do
        --print(item["name"] .. " == " .. v["name"])
        if (item["name"] == v["name"]) then
            if (item["nbt"] ~= nil) and (v["nbt"] ~= nil) then
                if item["nbt"] == v["nbt"] then
                    table.insert(filteredTable, v)
                end
            else
                table.insert(filteredTable, v)
            end
        end
    end
    if not next(filteredTable) then
        return nil
    else
        return filteredTable
    end
end

local function findFreeSpace(item)
    local filteredTable = searchForItem(item, items)
    if filteredTable == nil then
        for k, chest in pairs(storage) do
            local size = chest.size()
            for i = 1, size, 1 do
                if chest.getItemDetail(i) == nil then
                    return peripheral.getName(chest), i
                end
            end
        end
    else
        for k, v in pairs(filteredTable) do
            --text = v["name"] .. " #" .. v["count"]
            local limit = peripheral.wrap(v["chestName"]).getItemLimit(v["slot"])
            if v["count"] ~= limit then
                return v["chestName"], v["slot"]
            end
        end
        for k, chest in pairs(storage) do
            local size = chest.size()
            for i = 1, size, 1 do
                if chest.getItemDetail(i) == nil then
                    return peripheral.getName(chest), i
                end
            end
        end
    end
end

local function getItem(requestItem)
    local amount = requestItem.count
    local filteredTable = search(requestItem.name, items)
    for i, item in pairs(filteredTable) do
        if requestItem.nbt == nil then
            if item.count >= amount then
                peripheral.wrap(settings.get("exportChest")).pullItems(item["chestName"], item["slot"], amount)
                return
            else
                peripheral.wrap(settings.get("exportChest")).pullItems(item["chestName"], item["slot"])
                amount = amount - item.count
            end
        else
            if item.nbt == requestItem.nbt then
                if item.count >= amount then
                    peripheral.wrap(settings.get("exportChest")).pullItems(item["chestName"], item["slot"], amount)
                    return
                else
                    peripheral.wrap(settings.get("exportChest")).pullItems(item["chestName"], item["slot"])
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
    --local exportChest = peripheral.wrap("right")
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
            getItem(true)
        elseif input == "send" then
            --sendItem(true)
        elseif input == "exit" then
            os.queueEvent("terminate")
        end
        sleep(1)
    end
end

local function importHandeler()
    while true do
        local inputStorage = getInputStorage()
        local list = getList(inputStorage)
        if next(list) then
            --print("list of inputStorage: " .. dump(list))
            for i, item in pairs(list) do
                --print("items found in input chest")
                local chest, slot = findFreeSpace(item)
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    sleep(5)
                else
                    --send to found slot
                    --print("chest: " .. chest .. ", slot: " .. tostring(slot))
                    --print("send " .. tostring( peripheral.wrap(item.chestName).pushItems(chest, item["slot"]) ) .. " items")
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
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
            local inputStorage = { peripheral.wrap(settings.get("exportChest")) }
            local list = getList(inputStorage)
            local filteredTable = search(message2, list)
            for i, item in pairs(filteredTable) do
                local chest, slot = findFreeSpace(item)
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    sleep(5)
                else
                    --send to found slot
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
        elseif message == "importAll" then
            local inputStorage = { peripheral.wrap(settings.get("exportChest")) }
            local list = getList(inputStorage)
            for i, item in pairs(list) do
                local chest, slot = findFreeSpace(item)
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    sleep(5)
                else
                    --send to found slot
                    peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                end
            end
            reloadStorageDatabase()
        elseif message == "export" then
            local id2, message2
            repeat
                id2, message2 = rednet.receive()
            until id == id2

            print("Exporting Item(s): " .. dump(message2))
            getItem(message2)
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

print("debug mode: " .. tostring(settings.get("debug")))
print("exportChest is set to : " .. tostring(settings.get("exportChest")))
print("importChests are set to: " .. dump(settings.get("importChests")))
print("Server is loading, please wait....")
print("Getting storage...")
storage = getStorage()
print("Getting list of all items from storage...")
items, storageUsed = getList(storage)
print("Getting storage size...")
storageSize, storageMaxSize = getStorageSize(storage)
print("Storage size is: " .. tostring(storageSize) .. " slots")
print("Items in the system: " .. tostring(storageUsed) .. "/" .. tostring(storageMaxSize) .. " " .. tostring(("%.3g"):format(storageUsed/storageMaxSize)) .."% items")
print("Server Ready")

while true do
    if settings.get("debug") then
        parallel.waitForAll(debugMenu, storageHandler, importHandeler)
    else
        parallel.waitForAll(storageHandler, importHandeler)
    end
    sleep(1)
end
