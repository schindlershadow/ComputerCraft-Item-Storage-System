math.randomseed(os.time() + (7 * os.getComputerID()))
local cryptoNetURL = "https://raw.githubusercontent.com/SiliconSloth/CryptoNet/master/cryptoNet.lua"
local clients = {}
local serverLAN, serverWireless
local items = {}
local detailDB = {}
local storageUsed = 0
local storageMaxSize = 0
local storageSize = 0
local storages

--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("exportChests",
    { description = "The peripheral name of the export chest", { "minecraft:chest_0" }, type = "table" })
settings.define(
    "importChests",
    { description = "The peripheral name of the import chests", default = { "minecraft:chest_2" }, type = "table" }
)
settings.define("craftingChest",
    { description = "The peripheral name of the crafting chest", "minecraft:chest_3", type = "string" })
settings.define("serverName",
    { description = "The hostname of this server", "StorageServer" .. tostring(os.getComputerID()), type = "string" })
settings.define("requireLogin", { description = "require a login for LAN clients", default = "false", type = "boolean" })


--Settings fails to load
if settings.load() == false then
    print("No settings have been found! Default values will be used!")
    settings.set("serverName", "StorageServer" .. tostring(os.getComputerID()))
    settings.set("debug", false)
    settings.set("requireLogin", false)
    settings.set("exportChests", { "minecraft:chest_0" })
    settings.set("importChests", { "minecraft:chest_2" })
    settings.set("craftingChest", "minecraft:chest_3")
    print("Stop the server and edit .settings file with correct settings")
    settings.save()
    sleep(5)
end

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

local function log(text)
    local logFile = fs.open("logs/server.log", "a")
    if type(text) == "string" then
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. text)
    else
        logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. textutils.serialise(text))
    end
    logFile.close()
end

local function debugLog(text)
    if settings.get("debug") then
        local logFile = fs.open("logs/serverDebug.log", "a")
        if type(text) == "string" then
            logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. text)
        else
            logFile.writeLine(os.date("%A/%d/%B/%Y %I:%M%p") .. ", " .. textutils.serialise(text))
        end
        logFile.close()
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
    local exportChests = settings.get("exportChests")
    for i, chest in pairs(exportChests) do
        output[#output + 1] = peripheral.wrap(chest)
    end
    return output
end

local function inExportChests(search)
    local exportChests = settings.get("exportChests")
    for _, chest in pairs(exportChests) do
        if chest == search then
            return true
        end
    end
    return false
end

local function inImportChests(search)
    local importChests = settings.get("importChests")
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
                if inExportChests(remote[i]) == false and inImportChests(remote[i]) == false and remote[i] ~= settings.get("craftingChest") then
                    storage[#storage + 1] = wrap(remote[i])
                end
            end
        end
    end
    return storage
end

--Use this to avoid costly peripheral lookups
local function reconstructDetails(itemName)
    if type(detailDB[itemName]) ~= "nil" then
        return detailDB[itemName]
    end
    return nil
end

--Check if item name is in tag db
local function inDetailsDB(itemName)
    if type(detailDB) ~= "nil" then
        if type(detailDB[itemName]) ~= "nil" then
            return true
        end
    end
    return false
end

--Mantain details lookup
local function addDetailsDB(item)
    --print("addTag for: " .. item.name)

    --Maintain number of details stored
    local countDetails
    if type(detailDB.count) ~= "number" then
        countDetails = 0
    else
        countDetails = detailDB.count
    end

    --Maintain item count
    local countItems
    if type(detailDB.countItems) ~= "number" then
        countItems = 0
    else
        countItems = detailDB.countItems
    end

    --Add them to details db if they dont exist
    if type(detailDB[item.name]) == "nil" then
        --print("Found new item: " .. item.name)
        --print("Found new detail: " .. item.details.displayName)
        detailDB[item.name] = item.details
        countDetails = countDetails + 1
        countItems = countItems + 1
    end

    detailDB.count = countDetails
    detailDB.countItems = countItems
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

            if item.details == nil then
                --this is a massive time save
                if not (inDetailsDB(item.name)) or item.nbt ~= nil then
                    item["details"] = wrap(name).getItemDetail(slot)
                    if item.nbt == nil then
                        --print("addDetailsDB")
                        addDetailsDB(item)
                    end
                elseif item.nbt == nil then
                    --try to generate the details from db
                    item["details"] = reconstructDetails(item.name)
                end
                --if we still dont have details, we must reach out to the chest
                if item.details == nil then
                    item["details"] = wrap(name).getItemDetail(slot)
                end
            end
            itemCount = itemCount + item.count
            --table.insert(list, item)
            list[#list + 1] = item
            --print(("%d x %s in slot %d"):format(item.count, item.name, slot))
        end
    end
    return list, itemCount
end

local function average(t)
    local sum = 0
    for _, v in pairs(t) do -- Get the sum of all numbers in t
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


    for i = 1, #workingStorage, 1 do
        local size = workingStorage[i].size()
        slots = slots + size
    end

    --If the number of chests slots is unchanged from last db refresh, skip max storage calc
    if slots == storageSize then
        return storageSize, storageMaxSize
    end
    if storageSize ~= 0 then
        print("")
        print("Storage change detected")
        print("")
    end

    slots = 0

    print("")
    print("")
    local x, y = term.getSize()
    setCursorPos(1, y - 1)
    write("Progress:      of " .. tostring(#storage) .. " storages processed")

    local time = epoch("utc") / 1000
    local speedHistory = {}
    --for _, chest in pairs(workingStorage) do
    for i = 1, #workingStorage, 1 do
        setCursorPos(11, y - 1)
        write(tostring(i))
        setCursorPos(1, y)
        local size = workingStorage[i].size()
        slots = slots + size
        local getItemLimit = workingStorage[i].getItemLimit
        local getItemDetail = workingStorage[i].getItemDetail
        for k = 1, size do
            --getItemLimit is broken on cc-restitched
            --total = total + getItemLimit(k)
            local slotItem = getItemDetail(k)
            if type(slotItem) ~= "nil" then
                total = total + slotItem.maxCount
            end
        end
        local speed = (epoch("utc") / 1000) - time
        speedHistory[#speedHistory + 1] = speed
        term.write(floor(speed * 1000) / 1000 ..
            " seconds per storage   ETA: " ..
            (floor((#storage - i) * average(speedHistory))) .. " seconds left                                        ")
        time = epoch("utc") / 1000
    end
    return slots, total
end

local function printClients()
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
    local count = 0
    for _ in pairs(clients) do count = count + 1 end
    print("Clients: " .. tostring(count))
    for i in pairs(clients) do
        print(tostring(clients[i].username) ..
            ":" .. string.sub(tostring(clients[i].target), 1, 5) .. ":" .. tostring(clients[i].sender))
    end
    print("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
end

local function pingClients(message)
    --log(textutils.serialise(clients))
    for k, v in pairs(clients) do
        cryptoNet.send(v, { message })
    end
end

--Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    print("Reloading database..")
    storages = getStorage()
    --This part is slow
    items, storageUsed = getList(storages)
    print("Writing storage database....")

    if fs.exists("storage.db") then
        fs.delete("storage.db")
    end

    local decoded = {}
    decoded.detailDB = detailDB
    decoded.storageMaxSize = storageMaxSize
    decoded.storageSize = storageSize

    local storageFile = fs.open("storage.db", "w")
    storageFile.write(textutils.serialise(decoded))
    storageFile.close()
    pingClients("databaseReload")
    os.queueEvent("databaseReloaded")
    print("Database reload complete")
end

local function threadedStorageDatabaseReload()
    --os.startThread(reloadStorageDatabase)
    reloadStorageDatabase()
    --local event
    --repeat
    --    event = os.pullEvent("databaseReloaded")
    --until event == "databaseReloaded"
end

local function search(string, InputTable)
    local filteredTable = {}
    local find = string.find
    local lower = string.lower
    for k, v in pairs(InputTable) do
        if lower(v["name"]) == lower(string) then
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
    local find = string.find
    if filteredTable == nil then
        --Item not found in system
        --Find first chest with a free slot
        for k, chest in pairs(localStorage) do
            local list = chest.list()
            local size = chest.size()
            local chestName = getName(chest)
            --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))

            local index
            --workaround for storage drawers mod. slot 1 has the size of each slot but only slots 2..n can hold items so loop should start at 2
            if find(chestName, "storagedrawers:") then
                --print("applying storage drawers mod workaround")
                index = 2
            else --otherwise slots should start at 1
                index = 1
            end
            for i = index, size, 1 do
                if list[i] == nil then
                    --print("Found free slot at chest: " .. getName(chest) .. " Slot: " .. tostring(i))
                    return chestName, i
                end
            end
        end
    else
        --Item was found in the system
        --print("Item was found in the system")
        for k, v in pairs(filteredTable) do
            --text = v["name"] .. " #" .. v["count"]
            --print(v["name"] .. " #" .. v["count"] .. " " .. v["chestName"] .. " " .. v["slot"])
            local limit
            --workaround for storage drawers mod. slot 1 reports the true item limit, slots 2..n report 0
            if find(v["chestName"], "storagedrawers:") then
                --getItemLimit is broken on cc-restitched
                --limit = wrap(v["chestName"]).getItemLimit(1)
                local slotItem = wrap(v["chestName"]).getItemDetail(1)
                if type(slotItem) ~= "nil" then
                    limit = slotItem.maxCount
                else
                    limit = 64
                end
            else
                --limit = wrap(v["chestName"]).getItemLimit(v["slot"])

                --workaround for getItemLimit being broken on cc-restitched as of ver 1.101.2
                local slotItem = wrap(v["chestName"]).getItemDetail(v["slot"])
                if type(slotItem) ~= "nil" then
                    limit = slotItem.maxCount
                else
                    limit = 64
                end
            end

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
            local chestName = getName(chest)
            --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))

            --workaround for storage drawers mod. slot 1 has the size of each slot but only slots 2..n can hold items so loop should start at 2
            local index
            if find(chestName, "storagedrawers:") then
                --print("applying storage drawers mod workaround")
                index = 2
            else --otherwise slots should start at 1
                index = 1
            end
            for i = index, size, 1 do
                if list[i] == nil then
                    --print("Found free slot at chest: " .. getName(chest) .. " Slot: " .. tostring(i))
                    return chestName, i
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
    --reloadStorageDatabase()
    threadedStorageDatabaseReload()
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

    peripheral.wrap(settings.get("exportChests")[1]).pullItems(filteredTable[1]["chestName"], filteredTable[1]["slot"])
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
        elseif input == "list" then
            for i = 1, 6, 1 do
                print(dump(items[i]))
            end
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
            local localStorage = storages
            for i, item in pairs(list) do
                --print("finding free space....")
                local chest, slot = findFreeSpace(item, storages)
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
            --threadedStorageDatabaseReload()
            sleep(5)
        end

        sleep(1)
    end
end

local function onCryptoNetEvent(event)
    -- When a client logs in
    if event[1] == "login" or event[1] == "hash_login" then
        local username = event[2]
        -- The socket of the client that just logged in
        local socket = event[3]
        -- The logged-in username is also stored in the socket
        print(socket.username .. " just logged in.")
        -- Received a message from the client
    elseif event[1] == "encrypted_message" then
        local socket = event[3]
        -- Check the username to see if the client is logged in or allow without login if wired
        if (socket.username ~= nil or (not settings.get("requireLogin") and socket.sender == settings.get("serverName"))) and event[2][1] ~= "hashLogin" then
            local message = event[2][1]
            local data = event[2][2]
            if socket.username == nil then
                socket.username = "LAN Host"
            end
            print(socket.username .. " requested: " .. tostring(message))
            log("User: " .. socket.username .. " Client: " .. socket.target .. " request: " .. tostring(message))
            if message == "storageServer" then
                cryptoNet.send(socket, { message, settings.get("serverName") })
                local uniq = true
                for i in pairs(clients) do
                    if clients[i] == socket then
                        uniq = false
                    end
                end
                if uniq then
                    clients[#clients + 1] = socket
                end
                printClients()
            elseif message == "getServerType" then
                cryptoNet.send(socket, { message, "StorageServer" })
            elseif message == "ping" then
                cryptoNet.send(socket, { "ping", "ack" })
            elseif message == "reloadStorageDatabase" then
                cryptoNet.send(socket, { message })
                reloadStorageDatabase()
                --threadedStorageDatabaseReload()
            elseif message == "getItems" then
                cryptoNet.sendUnencrypted(socket, { "getItems", items })
            elseif message == "getDetailDB" then
                cryptoNet.sendUnencrypted(socket, { "getDetailDB", detailDB })
            elseif message == "getItem" then
                if settings.get("debug") then
                    print(dump(data))
                end
                local filteredTable = search(data, items)
                cryptoNet.send(socket, { message, filteredTable[1] })
            elseif message == "getItemDetails" then
                if settings.get("debug") then
                    print(dump(data))
                end
                if type(data) == "table" then
                    local details = peripheral.wrap(data.chestName).getItemDetail(data.slot)
                    cryptoNet.send(socket, { message, details })
                end
            elseif message == "forceImport" then
                local inputStorage = getInputStorage()
                local list = getList(inputStorage)
                --check if list is not empty
                if next(list) then
                    local localStorage = storages
                    for i, item in pairs(list) do
                        local chest, slot = findFreeSpace(item, storages)
                        if chest == nil then
                            --TODO: implement space full alert
                            print("No free space found!")
                            reloadStorageDatabase()
                        else
                            --send to found slot
                            print("Import: " .. item.name .. " #" .. tostring(item.count))
                            peripheral.wrap(item.chestName).pushItems(chest, item["slot"])
                        end
                    end
                    reloadStorageDatabase()
                    cryptoNet.send(socket, { message, "forceImport" })
                end
            elseif message == "import" then
                local inputStorage = getExportChests()
                local list = getList(inputStorage)
                local filteredTable = search(data, list)
                if type(filteredTable) ~= "nil" then
                    for i, item in pairs(filteredTable) do
                        local chest, slot = findFreeSpace(item, storages)
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
                end
                --reloadStorageDatabase()
                threadedStorageDatabaseReload()
            elseif message == "importAll" then
                local inputStorage = getExportChests()
                local list = getList(inputStorage)
                for i, item in pairs(list) do
                    local chest, slot = findFreeSpace(item, storages)
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
                --reloadStorageDatabase()
                threadedStorageDatabaseReload()
                cryptoNet.send(socket, { message })
            elseif message == "export" then
                print("Exporting Item(s): " .. dump(data["item"]))
                log("Export: " .. dump(data["item"]))
                getItem(data["item"], data["chest"])
                --reloadStorageDatabase()
                threadedStorageDatabaseReload()
            elseif message == "storageUsed" then
                cryptoNet.send(socket, { message, storageUsed })
            elseif message == "storageSize" then
                cryptoNet.send(socket, { message, storageSize })
            elseif message == "storageMaxSize" then
                cryptoNet.send(socket, { message, storageMaxSize })
            elseif message == "requireLogin" then
                cryptoNet.send(socket, { message, settings.get("requireLogin") })
            elseif message == "getCertificate" then
                local fileContents = nil
                local filePath = socket.sender .. ".crt"
                if fs.exists(filePath) then
                    local file = fs.open(filePath, "r")
                    fileContents = file.readAll()
                    file.close()
                end
                cryptoNet.send(socket, { message, fileContents })
            elseif message == "getPermissionLevel" then
                cryptoNet.send(socket, { message, cryptoNet.getPermissionLevel(data, serverLAN) })
            elseif message == "setPermissionLevel" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.permissionLevel) == "number" then
                    cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverLAN)
                    cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "checkPasswordHashed" then
                local check1 = cryptoNet.checkPasswordHashed(data.username, data.passwordHash, serverLAN)
                local check2 = cryptoNet.checkPasswordHashed(data.username, data.passwordHash, serverWireless)

                if check1 or check2 then
                    local permissionLevel = 0
                    if check1 then
                        permissionLevel = cryptoNet.getPermissionLevel(data.username, serverLAN)
                    else
                        permissionLevel = cryptoNet.getPermissionLevel(data.username, serverWireless)
                    end
                    cryptoNet.send(socket, { message, true, permissionLevel })
                else
                    cryptoNet.send(socket, { message, false, 0 })
                end
            elseif message == "setPassword" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                debugLog("setPassword:" ..
                    socket.username ..
                    ":" .. data.username .. ":" .. tostring(permissionLevel) .. ":" .. tostring(userExists))
                if tonumber(permissionLevel) >= 2 and userExists and type(data.password) == "string" then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, { message, true })
                elseif userExists and data.username == socket.username then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "setPasswordHashed" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                debugLog("setPassword:" ..
                    socket.username ..
                    ":" .. data.username .. ":" .. tostring(permissionLevel) .. ":" .. tostring(userExists))
                if tonumber(permissionLevel) >= 2 and userExists and type(data.passwordHash) == "string" then
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverLAN)
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverWireless)
                    cryptoNet.send(socket, { message, true })
                elseif userExists and data.username == socket.username then
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverLAN)
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "addUser" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and not userExists and type(data.password) == "string" then
                    cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverLAN)
                    cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "addUserHashed" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and not userExists and type(data.passwordHash) == "string" then
                    cryptoNet.addUserHashed(data.username, data.passwordHash, data.permissionLevel, serverLAN)
                    cryptoNet.addUserHashed(data.username, data.passwordHash, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "deleteUser" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.password) == "string" then
                    cryptoNet.deleteUser(data.username, serverLAN)
                    cryptoNet.deleteUser(data.username, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            end
        else
            --User is not logged in
            local message = event[2][1]
            local data = event[2][2]
            if message == "hashLogin" then
                --Need to auth with storage server
                --debugLog("hashLogin")
                print("User login request for: " .. data.username)
                log("User login request for: " .. data.username)
                local loginStatus = cryptoNet.checkPasswordHashed(data.username, data.passwordHash, serverLAN)
                local permissionLevel = cryptoNet.getPermissionLevel(data.username, serverLAN)
                --debugLog("loginStatus:"..tostring(loginStatus))
                if loginStatus == true then
                    cryptoNet.send(socket, { "hashLogin", true, permissionLevel })
                    socket.username = data.username
                    socket.permissionLevel = permissionLevel

                    --Update internal sockets
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
                    cryptoNet.send(socket, { "hashLogin", false })
                end
            elseif message == "requireLogin" then
                cryptoNet.send(socket, { message, settings.get("requireLogin") })
            else
                debugLog("User is not logged in. Sender: " .. socket.sender .. " Target: " .. socket.target)
                cryptoNet.send(socket, { "requireLogin" })
                cryptoNet.send(socket, "Sorry, I only talk to logged in users")
            end
        end
    elseif event[1] == "connection_closed" then
        local socket = event[2]
        log("connection closed: " ..
            tostring(socket.username) ..
            ":" .. string.sub(tostring(socket.target), 1, 5) .. ":" .. tostring(socket.sender))

        for i in pairs(clients) do
            if clients[i].target == socket.target then
                table.remove(clients, i)
                print("Client Disconnected: " ..
                    tostring(socket.username) ..
                    ":" .. string.sub(tostring(socket.target), 1, 5) .. ":" .. tostring(socket.sender))
            end
        end
        printClients()
    end
end

local function onStart()
    --clear out old log
    if fs.exists("logs/server.log") then
        fs.delete("logs/server.log")
    end
    if fs.exists("logs/serverDebug.log") then
        fs.delete("logs/serverDebug.log")
    end
    --Close any old connections and servers
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
                debugLog("Wireless modem found on " .. side .. " side")
            else
                wiredModem = modem
                wiredModem.side = side
                print("Wired modem found on " .. side .. " side")
                debugLog("Wired modem found on " .. side .. " side")
            end
        end
    end

    -- Start the cryptoNet server
    if type(wiredModem) ~= "nil" then
        serverLAN = cryptoNet.host(settings.get("serverName", true, false, wiredModem.side))
    end

    if type(wirelessModem) ~= "nil" then
        serverWireless = cryptoNet.host(settings.get("serverName") .. "_Wireless", true, false, wirelessModem.side)
    end

    importHandler()
end

term.clear()
print("debug mode: " .. tostring(settings.get("debug")))
print("exportChests are set to : " .. dump(settings.get("exportChests")))
print("importChests are set to: " .. dump(settings.get("importChests")))
print("craftingChest is set to: " .. (settings.get("craftingChest")))

print("")
print("Server is loading, please wait....")
--list of storage peripherals
storages = getStorage()


if fs.exists("storage.db") then
    print("Reading storage database")
    local storageFile = fs.open("storage.db", "r")
    local contents = storageFile.readAll()
    storageFile.close()

    local decoded = textutils.unserialize(contents)
    if type(decoded) ~= "nil" then
        detailDB = decoded.detailDB
        storageMaxSize = decoded.storageMaxSize
        storageSize = decoded.storageSize
    end
end

items, storageUsed = getList(storages)

if settings.get("debug") == false then
    write("\nGetting storage size")
    storageSize, storageMaxSize = getStorageSize(storages)
    write("\ndone\n\n")
    print("Storage size is: " .. tostring(storageSize) .. " slots")
    print("Items in the system: " ..
        tostring(storageUsed) ..
        "/" ..
        tostring(storageMaxSize) .. " " .. tostring(("%.3g"):format((storageUsed / storageMaxSize) * 100)) .. "% items")
else
    print("Items in the system: " .. tostring(storageUsed) .. " items")
end


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


print("")
print("Server Ready")
print("")

cryptoNet.setLoggingEnabled(true)
if settings.get("debug") then
    --cryptoNet.setLoggingEnabled(true)
    --parallel.waitForAll(debugMenu, storageHandler, importHandler)
    --debugMenu()
    cryptoNet.startEventLoop(onStart, onCryptoNetEvent)
else
    --cryptoNet.setLoggingEnabled(false)
    --parallel.waitForAll(storageHandler, importHandler)
    cryptoNet.startEventLoop(onStart, onCryptoNetEvent)
end
cryptoNet.closeAll()
