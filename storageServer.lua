math.randomseed(os.time() + (7 * os.getComputerID()))
local cryptoNetURL = "https://raw.githubusercontent.com/SiliconSloth/CryptoNet/master/cryptoNet.lua"
local clients = {}
local serverLAN, serverWireless
local items = {}
local detailDB = {}
local storageUsed = 0
local storageMaxSize = 0
local storageSize = 0
local storageFreeSlots = 0
local storageTotalSlots = 0
local storages
local monitors = {}
local mainCraftingServer
local craftingEnabled = false
local currentlyCrafting = {}
local craftingQueue = {}
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

--Suppress IDE warnings
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

--Settings
settings.define("debug", { description = "Enables debug options", default = "false", type = "boolean" })
settings.define("exportChests",
    { description = "The peripheral name of the export chest", { "minecraft:chest_0" }, type = "table" })
settings.define(
    "importChests",
    { description = "The peripheral name of the import chests", default = { "minecraft:chest_2" }, type = "table" }
)
settings.define("craftingChests",
    {
        description = "The peripheral name of the crafting chests that are above the turtle(s)",
        { "minecraft:chest_3" },
        type = "table"
    })
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
    settings.set("craftingChests", { "minecraft:chest_3" })
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

local function dumpItems()
    for k, v in pairs(items) do
        debugLog("k: " .. tostring(k) .. " v: " .. textutils.serialize(v))
    end
end

local function getInputStorage()
    local storage = {}
    local peripherals = {}
    local importChests = settings.get("importChests")
    for _, modem in pairs(modems) do
        --local remote = modem.getNamesRemote()
        --peripherals[#peripherals + 1] = remote

        --for i in pairs(remote) do
        for k, chest in pairs(importChests) do
            --if chest == remote[i] then
            if modem.isPresentRemote(chest) then
                --storage[#storage + 1] = peripheral.wrap(remote[i])
                storage[#storage + 1] = peripheral.wrap(chest)
            end
            --end
        end
        --end
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

local function inCraftingChests(search)
    local importChests = settings.get("craftingChests")
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
                if inExportChests(remote[i]) == false and inImportChests(remote[i]) == false and inCraftingChests(remote[i]) == false then
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

local function calcFreeSlots()
    local freeSlots = 0
    for _, chest in pairs(storages) do
        local numberOfSlots = 0
        for slot, item in pairs(chest.list()) do
            numberOfSlots = numberOfSlots + 1
        end
        freeSlots = freeSlots + ((chest.size() - numberOfSlots))
    end
    return freeSlots
end

--gets the contents of a table of chests
local function getList(storage)
    local list = {}
    local itemCount = 0
    local getName = peripheral.getName
    local wrap = peripheral.wrap
    local freeSlots = 0
    local total = 0

    for _, chest in pairs(storage) do
        --local time = os.epoch("utc") / 1000
        local tmpList = {}
        local name = getName(chest)
        local numberOfSlots = 0

        total = total + (chest.size())
        for slot, item in pairs(chest.list()) do
            item["slot"] = slot
            item["chestName"] = name
            numberOfSlots = numberOfSlots + 1

            if item.details == nil then
                --this is a massive time save
                if not (inDetailsDB(item.name)) or item.nbt ~= nil then
                    if item.nbt == nil then
                        item["details"] = wrap(name).getItemDetail(slot)
                        --print("addDetailsDB")
                        addDetailsDB(item)
                    end
                elseif item.nbt == nil then
                    --try to generate the details from db
                    item["details"] = reconstructDetails(item.name)
                end
                --if we still dont have details, we must reach out to the chest
                --This causes major slowdowns if there is a large amount of items with nbt tags in system
                --if item.details == nil then
                --    item["details"] = wrap(name).getItemDetail(slot)
                --end
            end
            --free = free + (item.details.maxCount - item.count)
            itemCount = itemCount + item.count
            --table.insert(list, item)
            list[#list + 1] = item
            --print(("%d x %s in slot %d"):format(item.count, item.name, slot))
        end
        freeSlots = freeSlots + ((chest.size() - numberOfSlots))
        --local speed = (os.epoch("utc") / 1000) - time
        --debugLog("Chest " .. name .. " took " .. tostring(speed) .. " seconds")
    end
    return list, itemCount, freeSlots, total
end

local function getUserList()
    local filename = settings.get("serverName") .. "_users.tbl"
    if fs.exists(filename) then
        local file = fs.open(filename, "r")
        local contents = file.readAll()
        file.close()

        local decoded = textutils.unserialize(contents)
        local tab = {}
        if type(decoded) ~= "nil" then
            for k, v in pairs(decoded) do
                local tmp = {}
                tmp.username = k
                tmp.permissionLevel = v[2]
                tab[#tab + 1] = tmp
            end
            return tab
        else
            return nil
        end
    end
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
    local free = 0
    local totalSlots = 0


    for i = 1, #workingStorage, 1 do
        local size = workingStorage[i].size()
        totalSlots = totalSlots + size
    end

    --If the number of chests slots is unchanged from last db refresh, skip max storage calc
    if totalSlots == storageSize then
        return storageSize, storageMaxSize, storageFreeSlots, storageTotalSlots
    end
    if storageSize ~= 0 then
        print("")
        print("Storage change detected")
        print("")
    end

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
            else
                total = total + 64
                free = free + 1
            end
        end
        local speed = (epoch("utc") / 1000) - time
        speedHistory[#speedHistory + 1] = speed
        term.write(floor(speed * 1000) / 1000 ..
            " seconds per storage   ETA: " ..
            (floor((#storage - i) * average(speedHistory))) .. " seconds left                                        ")
        time = epoch("utc") / 1000
    end
    return slots, total, free, totalSlots
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
    if mainCraftingServer ~= nil then
        cryptoNet.send(mainCraftingServer, { message })
    end
end

--Note: Large performance hit on larger systems
local function reloadStorageDatabase()
    print("Reloading database..")
    local time = os.epoch("utc") / 1000
    storages = getStorage()
    --This part is slow
    items, storageUsed, storageFreeSlots, storageTotalSlots = getList(storages)
    --log("storageFreeSlots:" .. tostring(storageFreeSlots) .. " storageTotalSlots:" .. tostring(storageTotalSlots))
    local speed = (os.epoch("utc") / 1000) - time
    --print("Getting item list took " .. tostring(speed) .. " seconds")
    debugLog("Getting item list took " .. tostring(speed) .. " seconds")
    local timeWrittingdb = os.epoch("utc") / 1000

    print("Writing storage database....")

    if fs.exists("storage.db") then
        fs.delete("storage.db")
    end

    local decoded = {}
    decoded.detailDB = detailDB
    decoded.storageMaxSize = storageMaxSize
    decoded.storageSize = storageSize
    decoded.storageFreeSlots = storageFreeSlots
    decoded.storageTotalSlots = storageTotalSlots

    local storageFile = fs.open("storage.db", "w")
    storageFile.write(textutils.serialise(decoded, { allow_repetitions = true }))
    storageFile.close()
    local speedWrittingdb = (os.epoch("utc") / 1000) - timeWrittingdb
    --print("Writting storage database took " .. tostring(speedWrittingdb) .. " seconds")
    debugLog("Writting storage database took " .. tostring(speedWrittingdb) .. " seconds")

    pingClients("databaseReload")
    os.queueEvent("databaseReloaded")
    print("Database reload complete")
    speed = (os.epoch("utc") / 1000) - time
    print("Database reload took " .. tostring(("%.3g"):format(speed) .. " seconds total"))
    debugLog("Database reload took " .. tostring(speed) .. " seconds total")
end

local function threadedStorageDatabaseReload()
    --os.startThread(reloadStorageDatabase)
    reloadStorageDatabase()
    --local event
    --repeat
    --    event = os.pullEvent("databaseReloaded")
    --until event == "databaseReloaded"
end

--Avoid costly database reload by patching database in memory
local function patchStorageDatabase(inputItem, count, chest, slot)
    if count == 0 or inputItem == nil or chest == nil or slot == nil then
        return false
    end
    local itemName = inputItem.name

    --print("Patching database item:" .. itemName .. " by #" .. tostring(count) .. " chest:" .. chest .. " slot:" .. tostring(slot))
    debugLog("Patching database item:" ..
        itemName .. " by #" .. tostring(count) .. " chest:" .. chest .. " slot:" .. tostring(slot))
    local stringSearch
    --Strip out the item: from the front of the item name
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
                    if v.nbt == inputItem.nbt then
                        --handler for techreborn storage_units
                        if (string.find(chest, "techreborn:") and string.find(chest, "storage_unit")) then
                            local slotDetails = peripheral.wrap(chest).getItemDetail(slot)
                            if slotDetails ~= nil then
                                items[k].count = slotDetails.count
                            else
                                items[k].count = 0
                            end

                            --storageUsed = storageUsed + (slotDetails.count - count)
                        else
                            items[k].count = items[k].count + count
                            storageUsed = storageUsed + count
                        end
                        if items[k].count < 1 then
                            --If there is 0 items, delete from list
                            table.remove(items, k)
                        end

                        return true
                    end
                end
            end
            if not next(savedDetails) and v.details ~= nil and v.nbt == inputItem.nbt then
                savedDetails = v.details
            end
        end
    end

    --If we managed to capture details from other slots, create new entry in list
    if next(savedDetails) then
        local tmp = {}
        tmp.count = count
        tmp.slot = slot
        tmp.details = savedDetails
        tmp.name = itemName
        tmp.chestName = chest
        tmp.nbt = savedDetails.nbt
        table.insert(items, tmp)
        storageUsed = storageUsed + count
        return true
    else
        --if all else fails, reach out to chest to get details
        if chest ~= nil and slot ~= nil and peripheral.wrap(chest) ~= nil then
            local slotDetails = peripheral.wrap(chest).getItemDetail(slot)
            if slotDetails ~= nil then
                local tmp = {}
                tmp.count = slotDetails.count
                tmp.slot = slot
                tmp.details = slotDetails
                tmp.name = itemName
                tmp.chestName = chest
                tmp.nbt = slotDetails.nbt
                table.insert(items, tmp)
                storageUsed = storageUsed + count
                return true
            end
        end
    end

    --Patching failed, fallback to full reload
    reloadStorageDatabase()
    return false
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

local function cleanTable(table)
    local arr = {}
    --print("size: " .. tostring(#table))
    for k, v in pairs(table) do
        local tab = {}
        tab.recipeType = v.recipeType
        tab.name = v.name
        tab.count = v.count
        tab.recipeName = v.recipeName
        tab.recipe = v.recipe
        tab.recipeInput = v.recipeInput
        tab.displayName = v.displayName
        tab.chestName = v.chestName
        tab.slot = v.slot
        tab.nbt = v.nbt
        --tab.tags = v.tags
        --No idea why this works
        local tag = textutils.serialize(v.tags)
        tab.tags = textutils.unserialise(tag)
        arr[#arr + 1] = tab
        --print(tostring(k))
        --debugLog("k: " .. tostring(k) .. " dump: " .. dump(tab))
        --debugLog(textutils.serialize(tab))
    end
    return arr
end

--Finds next free space in system of an item
local function findFreeSpace(item, storage)
    local localStorage = storage
    local filteredTable = searchForItem(item, items)
    local getName = peripheral.getName
    local wrap = peripheral.wrap
    local find = string.find


    if filteredTable == nil then
        --debugLog("Item not found in system")
        --Item not found in system
        --Find first chest with a free slot
        for k, chest in pairs(localStorage) do
            local list = chest.list()
            local size = chest.size()
            --skip full chests
            if list ~= nil and #list < size then
                local chestName = getName(chest)
                --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))
                --Do not use techreborn storage_units
                if not (find(chestName, "techreborn:") and find(chestName, "storage_unit")) then
                    local index
                    --workaround for storage drawers mod. slot 1 has the size of each slot but only slots 2..n can hold items so loop should start at 2
                    if find(chestName, "storagedrawers:") then
                        --print("applying storage drawers mod workaround")
                        index = 2
                    else --otherwise slots should start at 1
                        index = 1
                    end

                    --Find a slot that has nothing
                    for i = index, size, 1 do
                        if list[i] == nil then
                            --print("Found free slot at chest: " .. chestName .. " Slot: " .. tostring(i))
                            --debugLog("Found free slot at chest: " .. chestName .. " Slot: " .. tostring(i))
                            --local test = wrap(chestName).getItemDetail(i)
                            --debugLog("slot info:" ..textutils.serialize(test))
                            return chestName, i
                        end
                    end
                end
            end
        end
    else
        local clean = cleanTable(filteredTable)
        debugLog("findFreeSpace filteredTable: " .. textutils.serialize(clean))
        --debugLog("Item was found in the system")
        --Item was found in the system
        --print("Item was found in the system")
        local limit
        for k, v in pairs(filteredTable) do
            --text = v["name"] .. " #" .. v["count"]
            --print(v["name"] .. " #" .. v["count"] .. " " .. v["chestName"] .. " " .. v["slot"])
            --workaround for storage drawers mod. slot 1 reports the true item limit, slots 2..n report 0
            if limit == nil then
                if find(v["chestName"], "storagedrawers:") then
                    --getItemLimit is broken on cc-restitched
                    --limit = wrap(v["chestName"]).getItemLimit(1)
                    local slotItem = wrap(v["chestName"]).getItemDetail(1)
                    if type(slotItem) ~= "nil" then
                        limit = slotItem.maxCount - slotItem.count
                    else
                        limit = 64
                    end
                else
                    --limit = wrap(v["chestName"]).getItemLimit(v["slot"])

                    --workaround for getItemLimit being broken on cc-restitched as of ver 1.101.2
                    local slotItem = wrap(v["chestName"]).getItemDetail(v["slot"])
                    if type(slotItem) ~= "nil" then
                        limit = slotItem.maxCount - slotItem.count
                    else
                        limit = 64
                    end
                end
            end

            if (find(v.chestName, "techreborn:") and find(v.chestName, "storage_unit")) then
                debugLog("found techreborn: " .. v.chestName)
                --storage_units can only input from slot 1, if slot 1 is full then the storage unit is full

                local slotItem = wrap(v["chestName"]).getItemDetail(1)
                if slotItem == nil then
                    return v["chestName"], 1
                end
                limit = slotItem.maxCount - slotItem.count
                if v["count"] <= limit and item.nbt == v.nbt then
                    return v["chestName"], 1
                end
            else
                --if the slot is not full, then it has free space
                --print("limit: " .. tostring(limit) .. " count: " .. tostring(v["count"]))
                if v["count"] <= limit and item.nbt == v.nbt then
                    return v["chestName"], v["slot"]
                end
            end
        end

        --Find first chest with a free slot
        --print("Find first chest with a free slot")
        --debugLog("Find first chest with a free slot")
        for k, chest in pairs(localStorage) do
            local list = chest.list()
            local size = chest.size()
            --skip full chests
            if #list < size then
                local chestName = getName(chest)
                --print("checking chest #" .. tostring(k) .. " Name: " .. getName(chest) .. " slot1 is: " .. tostring(list[1]))
                --Do not use techreborn storage_units
                if not (find(chestName, "techreborn:") and find(chestName, "storage_unit")) then
                    --workaround for storage drawers mod. slot 1 has the size of each slot but only slots 2..n can hold items so loop should start at 2
                    local index
                    if find(chestName, "storagedrawers:") then
                        --print("applying storage drawers mod workaround")
                        index = 2
                    else --otherwise slots should start at 1
                        index = 1
                    end

                    --Find a slot that has nothing
                    for i = index, size, 1 do
                        if list[i] == nil then
                            --print("Found free slot at chest: " .. chestName .. " Slot: " .. tostring(i))
                            --debugLog("Found free slot at chest: " .. chestName .. " Slot: " .. tostring(i))
                            --local test = wrap(chestName).getItemDetail(i)
                            --debugLog("slot info:" ..textutils.serialize(test))
                            return chestName, i
                        end
                    end
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
    --print(tostring(inExportChests(chest)))
    local amount = requestItem.count
    local filteredTable = search(requestItem.name, items)
    local wrap = peripheral.wrap
    if filteredTable ~= nil then
        for i, item in pairs(filteredTable) do
            local chestP = wrap(chest)
            if chestP ~= nil and not (item.slot == 1 and (string.find(chest, "techreborn:") and string.find(chest, "storage_unit"))) then
                --dont export from the first slot of a techreborn storage_unit
                if requestItem.nbt == nil and item.nbt == nil then
                    if item.count >= amount then
                        --print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                        debugLog(("Export: " .. requestItem.name .. " #" .. tostring(amount) .. " chest:" .. item.chestName .. " slot:" .. item.slot))
                        local moved = chestP.pullItems(item["chestName"], item["slot"], amount)
                        local patchstatus = patchStorageDatabase(item, -1 * moved, item.chestName, item.slot)
                        return
                    else
                        --print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                        debugLog(("Export: " .. requestItem.name .. " #" .. tostring(amount) .. " chest:" .. item.chestName .. " slot:" .. item.slot))
                        local moved = chestP.pullItems(item["chestName"], item["slot"])
                        amount = amount - item.count
                        local patchstatus = patchStorageDatabase(item, -1 * moved, item.chestName, item.slot)
                    end
                else
                    if item.nbt == requestItem.nbt then
                        if item.count >= amount then
                            --print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                            debugLog(("Export: " .. requestItem.name .. " #" .. tostring(amount) .. " chest:" .. item.chestName .. " slot:" .. item.slot))
                            local moved = chestP.pullItems(item["chestName"], item["slot"], amount)
                            local patchstatus = patchStorageDatabase(item, -1 * moved, item.chestName, item.slot)
                            return
                        else
                            --print("Export: " .. requestItem.name .. " #" .. tostring(amount))
                            debugLog(("Export: " .. requestItem.name .. " #" .. tostring(amount) .. " chest:" .. item.chestName .. " slot:" .. item.slot))
                            local moved = chestP.pullItems(item["chestName"], item["slot"])
                            amount = amount - item.count
                            local patchstatus = patchStorageDatabase(item, -1 * moved, item.chestName, item.slot)
                        end
                    end
                end
            end
        end
    end
    --reloadStorageDatabase()
    --threadedStorageDatabaseReload()
end

--debug function
local function find(all)
    print("Enter search term")
    local input = io.read()
    local filteredTable = search(input, items)

    if all and filteredTable ~= nil then
        print(dump(filteredTable[1]))
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
    if filteredTable ~= nil then
        print("exporting " .. filteredTable[1]["name"])
        print(dump(filteredTable[1]))

        peripheral.wrap(settings.get("exportChests")[1]).pullItems(filteredTable[1]["chestName"],
            filteredTable[1]["slot"])
        reloadStorageDatabase()
    end
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
            pingClients("databaseReload")
            storageFreeSlots = calcFreeSlots()
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

local function centerText(monitor, text)
    if text == nil then
        text = ""
    end
    local x, y = monitor.getSize()
    local x1, y1 = monitor.getCursorPos()
    monitor.setCursorPos((math.floor(x / 2) - (math.floor(#text / 2))), y1)
    monitor.write(text)
end

local function mergeCraftingQueue()
    local event

    --merge whats crafting and crafting queue
    local queue = {}
    if next(currentlyCrafting) then
        queue = { currentlyCrafting }
    end
    for i = 1, #craftingQueue, 1 do
        table.insert(queue, craftingQueue[i].recipe)
    end
    --log("queue: " .. textutils.serialise(queue))
    return queue
end

--Main loop for monitor
local function monitorHandler()
    local name = (settings.get("serverName"))
    while true do
        local queue = {}
        if craftingEnabled then
            --request crafting queue
            queue = mergeCraftingQueue()
        end
        for monitorid = 1, #monitors, 1 do
            local monitor = peripheral.wrap(monitors[monitorid])
            if monitor ~= nil then
                local width, height = monitor.getSize()
                local bgColor, barColor
                if monitor.isColor() then
                    bgColor = colors.blue
                    barColor = colors.white
                else
                    bgColor = colors.black
                    barColor = colors.black
                end
                monitor.setTextScale(0.5)
                monitor.setBackgroundColor(bgColor)
                monitor.clear()
                monitor.setCursorPos(1, 1)
                centerText(monitor, name)
                monitor.setCursorPos(1, 3)
                monitor.write("Space:")
                local storageBar
                if storageUsed == storageMaxSize then
                    storageBar = width - 2
                else
                    storageBar = math.floor(((storageUsed / storageMaxSize)) * (width))
                end
                local bar = ""


                --generate the progress bar
                for i = 1, storageBar, 1 do
                    if monitor.isColor() then
                        bar = bar .. " "
                    else
                        bar = bar .. "-"
                    end
                end
                --write the empty part of the bar
                monitor.setBackgroundColor(barColor)
                --monitor.clearLine()
                for i = 2, width - 1, 1 do
                    monitor.setCursorPos(i, 4)
                    if monitor.isColor() then
                        monitor.write(" ")
                    else
                        monitor.write("|")
                    end
                end
                monitor.setCursorPos(2, 4)
                local percent = (storageUsed / storageMaxSize) * 100
                if percent < 50 then
                    monitor.setBackgroundColor(colors.green)
                elseif percent < 70 then
                    monitor.setBackgroundColor(colors.orange)
                else
                    monitor.setBackgroundColor(colors.red)
                end

                monitor.write(bar)
                monitor.setBackgroundColor(bgColor)

                monitor.setCursorPos(1, 5)
                centerText(monitor, tostring(storageUsed) ..
                    "/" ..
                    tostring(storageMaxSize) ..
                    " Items " .. tostring(("%.3g"):format(percent) .. "%"))

                monitor.setCursorPos(1, 6)
                monitor.write("Slots:")
                if (storageTotalSlots - storageFreeSlots) == storageTotalSlots then
                    storageBar = width - 2
                else
                    storageBar = math.floor((((storageTotalSlots - storageFreeSlots) / storageTotalSlots)) * (width))
                end
                bar = ""
                --generate the progress bar
                for i = 1, storageBar, 1 do
                    if monitor.isColor() then
                        bar = bar .. " "
                    else
                        bar = bar .. "-"
                    end
                end
                --write the empty part of the bar
                monitor.setBackgroundColor(barColor)
                --monitor.clearLine()
                for i = 2, width - 1, 1 do
                    monitor.setCursorPos(i, 7)
                    if monitor.isColor() then
                        monitor.write(" ")
                    else
                        monitor.write("|")
                    end
                end
                monitor.setCursorPos(2, 7)
                percent = ((storageTotalSlots - storageFreeSlots) / storageTotalSlots) * 100
                if percent < 50 then
                    monitor.setBackgroundColor(colors.green)
                elseif percent < 70 then
                    monitor.setBackgroundColor(colors.orange)
                else
                    monitor.setBackgroundColor(colors.red)
                end
                monitor.write(bar)
                monitor.setBackgroundColor(bgColor)
                monitor.setCursorPos(1, 8)
                centerText(monitor, tostring(storageTotalSlots - storageFreeSlots) ..
                    "/" ..
                    tostring(storageTotalSlots) ..
                    " Slots " .. tostring(("%.3g"):format(percent) .. "%"))
                monitor.setCursorPos(1, 10)
                --Print connected clients
                local clientCount = 0
                for _ in pairs(clients) do clientCount = clientCount + 1 end
                centerText(monitor, "Clients connected: " .. tostring(clientCount))

                --Draw crafting queue
                if craftingEnabled and mainCraftingServer ~= nil then
                    if monitor.isColor() then
                        monitor.setBackgroundColor(colors.gray)
                        for i = 12, height, 1 do
                            monitor.setCursorPos(1, i)
                            monitor.clearLine()
                        end
                    else
                        monitor.setBackgroundColor(colors.black)
                    end

                    monitor.setCursorPos(1, 12)
                    centerText(monitor, mainCraftingServer.serverName)
                    monitor.setCursorPos(1, 14)
                    monitor.write("Crafting Queue:")
                    for k, v in pairs(queue) do
                        if k < (height - 15) and v ~= nil then
                            local text
                            --text = v.displayName .. ": #" .. tostring(v.amount) .. " - " .. v.recipeName:match("(.+):.+")
                            text = v.displayName ..
                                ": #" .. tostring(v.amount) .. " - " .. v.recipeName

                            for i = 1, width, 1 do
                                monitor.setCursorPos(i, k + 15)
                                monitor.write(" ")
                            end
                            monitor.setCursorPos(1, k + 15)
                            monitor.write(text)
                            --term.setCursorPos(1, height)
                        end
                    end
                end
            end
            sleep(1)
        end
    end
end

--Main loop for importing items into the system via defined import chests
local function importHandler()
    local inputStorage = getInputStorage()
    while true do
        --local list = getList(inputStorage)

        --Make a minimal list of items from input storages
        local list = {}
        for k, chest in pairs(inputStorage) do
            local chestName = peripheral.getName(chest)
            local itemList = chest.list()
            if itemList ~= nil then
                for slot, item in pairs(itemList) do
                    item.chestName = chestName
                    item.slot = slot
                    list[#list + 1] = item
                end
            end
        end
        --check if list is not empty
        --print(dump(list))
        if next(list) then
            local reload = false
            local localStorage = storages
            for i, item in pairs(list) do
                --local currentItemDetail = peripheral.wrap(item.chestName).getItemDetail(item.slot)
                --if currentItemDetail ~= nil then
                --print("finding free space....")
                local chest, slot = findFreeSpace(item, storages)
                --print("chest: " .. tostring(chest) .. " slot: " .. tostring(slot))
                if chest == nil then
                    --TODO: implement space full alert
                    print("No free space found!")
                    reloadStorageDatabase()
                    reload = false
                    --sleep(5)
                    --return
                else
                    --send to found slot
                    local moved = peripheral.wrap(item.chestName).pushItems(chest, item.slot, item.count, slot)
                    if moved > 0 then
                        local patchstatus = patchStorageDatabase(item, moved, chest, slot)
                        if not patchstatus then
                            reload = true
                        end
                        print("Import: " .. item.name .. " #" .. tostring(moved))
                        debugLog("importHandler: " ..
                            item.name .. " #" .. tostring(moved) .. " chest:" .. chest .. " slot:" .. tostring(slot))
                    else
                        --local test = peripheral.wrap(chest).getItemDetail(item["slot"])
                        --debugLog("moved is 0: " .. textutils.serialize(test))
                        --reloadStorageDatabase()
                        reload = false
                    end
                end
                --end
            end
            pingClients("databaseReload")
            storageFreeSlots = calcFreeSlots()
            --threadedStorageDatabaseReload()
            --sleep(5)
        end
        sleep(0.5)
    end
end

--Cryptonet event handler
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
        if socket ~= nil and (socket.username ~= nil or (not settings.get("requireLogin") and socket.sender == settings.get("serverName"))) and event[2][1] ~= "hashLogin" then
            local message = event[2][1]
            local data = event[2][2]
            if socket.username == nil then
                socket.username = "LAN Host"
            end
            --print(socket.username .. " requested: " .. tostring(message))
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
                    cryptoNet.send(socket, { "isMainCraftingServer" })
                end
                printClients()
            elseif message == "getServerType" then
                cryptoNet.send(socket, { message, "StorageServer" })
            elseif message == "isMainCraftingServer" then
                if data then
                    cryptoNet.send(socket, { "storageCraftingServer" })
                    cryptoNet.send(socket, { "watchCrafting" })
                    mainCraftingServer = socket
                    craftingEnabled = true
                end
            elseif message == "storageCraftingServer" then
                mainCraftingServer.serverName = data
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
                if filteredTable ~= nil then
                    cryptoNet.send(socket, { message, filteredTable[1] })
                end
            elseif message == "getItemDetails" then
                if settings.get("debug") then
                    print(dump(data))
                end
                if type(data) == "table" then
                    local details = peripheral.wrap(data.chestName).getItemDetail(data.slot)
                    cryptoNet.send(socket, { message, details })
                end
            elseif message == "forceImport" then
                print(socket.username .. " requested: " .. tostring(message))
                local inputStorage = { peripheral.wrap(data) }
                local list = getList(inputStorage)
                local reload = false
                --check if list is not empty
                if next(list) then
                    local localStorage = storages
                    for i, item in pairs(list) do
                        local chest, slot = findFreeSpace(item, storages)
                        if chest == nil then
                            --TODO: implement space full alert
                            print("No free space found!")
                            reloadStorageDatabase()
                            reload = false
                        else
                            --send to found slot
                            local moved = peripheral.wrap(item.chestName).pushItems(chest, item.slot, item.count, slot)
                            if moved > 0 then
                                local patchstatus = patchStorageDatabase(item, moved, chest, item.slot)
                                if not patchstatus then
                                    reload = true
                                end
                                print("Import: " .. item.name .. " #" .. tostring(moved))
                                debugLog("forceImport: " ..
                                    item.name ..
                                    " #" .. tostring(moved) .. " chest:" .. chest .. " slot:" .. tostring(slot))
                            end
                        end
                    end
                    storageFreeSlots = calcFreeSlots()
                    pingClients("databaseReload")
                    cryptoNet.send(socket, { message, "forceImport" })
                end
            elseif message == "import" then
                print(socket.username .. " requested: " .. tostring(message))
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
                            local moved = peripheral.wrap(item.chestName).pushItems(chest, item.slot, item.count, slot)
                            print("Import: " .. item.name .. " #" .. tostring(moved))
                        end
                    end
                end
                reloadStorageDatabase()
                --threadedStorageDatabaseReload()
            elseif message == "importAll" then
                print(socket.username .. " requested: " .. tostring(message))
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
                        local moved = peripheral.wrap(item.chestName).pushItems(chest, item.slot, item.count, slot)
                        print("Import: " .. item.name .. " #" .. tostring(moved))
                    end
                end
                reloadStorageDatabase()
                --threadedStorageDatabaseReload()
                cryptoNet.send(socket, { message })
            elseif message == "export" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Export: " .. (data.item.name) .. " #" .. tostring(data.item.count))
                log("Export: " .. dump(data["item"]))
                getItem(data["item"], data["chest"])
                pingClients("databaseReload")
                storageFreeSlots = calcFreeSlots()
                --reloadStorageDatabase()
                --threadedStorageDatabaseReload()
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
            elseif message == "getUserList" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                if tonumber(permissionLevel) >= 2 then
                    cryptoNet.send(socket, { message, getUserList() })
                end
            elseif message == "getPermissionLevel" then
                cryptoNet.send(socket, { message, cryptoNet.getPermissionLevel(data, serverLAN) })
            elseif message == "setPermissionLevel" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists and type(data.permissionLevel) == "number" and data.permissionLevel < 3 then
                    cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverLAN)
                    --cryptoNet.setPermissionLevel(data.username, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "checkPasswordHashed" then
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                -- check if user has perms or if on lan when logins are not required
                if (not settings.get("requireLogin") and socket.sender == settings.get("serverName")) or tonumber(permissionLevel) >= 2 then
                    local check = cryptoNet.checkPasswordHashed(data.username, data.passwordHash, serverLAN)
                    if check then
                        permissionLevel = cryptoNet.getPermissionLevel(data.username, serverLAN)
                        cryptoNet.send(socket, { message, true, permissionLevel })
                    else
                        cryptoNet.send(socket, { message, false, 0 })
                    end
                end
            elseif message == "setPassword" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                debugLog("setPassword:" ..
                    socket.username ..
                    ":" .. data.username .. ":" .. tostring(permissionLevel) .. ":" .. tostring(userExists))
                if tonumber(permissionLevel) >= 2 and userExists and type(data.password) == "string" then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    --cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, { message, true })
                elseif userExists and data.username == socket.username then
                    cryptoNet.setPassword(data.username, data.password, serverLAN)
                    --cryptoNet.setPassword(data.username, data.password, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "setPasswordHashed" then
                print(socket.username .. " requested: " .. tostring(message))
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                debugLog("setPassword:" ..
                    socket.username ..
                    ":" .. data.username .. ":" .. tostring(permissionLevel) .. ":" .. tostring(userExists))
                if tonumber(permissionLevel) >= 2 and userExists and type(data.passwordHash) == "string" then
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverLAN)
                    --cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverWireless)
                    cryptoNet.send(socket, { message, true })
                elseif userExists and data.username == socket.username then
                    cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverLAN)
                    --cryptoNet.setPasswordHashed(data.username, data.passwordHash, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "addUser" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Request to add user: " .. data.username)
                log("Request to add user: " .. data.username)
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and not userExists and type(data.password) == "string" then
                    cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverLAN)
                    --cryptoNet.addUser(data.username, data.password, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "addUserHashed" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Request to add user: " .. data.username)
                log("Request to add user: " .. data.username)
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and not userExists and type(data.passwordHash) == "string" then
                    cryptoNet.addUserHashed(data.username, data.passwordHash, data.permissionLevel, serverLAN)
                    --cryptoNet.addUserHashed(data.username, data.passwordHash, data.permissionLevel, serverWireless)
                    cryptoNet.send(socket, { message, true })
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "deleteUser" then
                print(socket.username .. " requested: " .. tostring(message))
                print("Request to delete user: " .. data.username)
                log("Request to delete user: " .. data.username)
                local permissionLevel = cryptoNet.getPermissionLevel(socket.username, serverLAN)
                local userExists = cryptoNet.userExists(data.username, serverLAN)
                if permissionLevel >= 2 and userExists then
                    local userPermissionLevel = cryptoNet.getPermissionLevel(data.username, serverLAN)
                    if userPermissionLevel < 3 then
                        cryptoNet.deleteUser(data.username, serverLAN)
                        --cryptoNet.deleteUser(data.username, serverWireless)
                        cryptoNet.send(socket, { message, true })
                    else
                        --super admins cannot be deleted
                        cryptoNet.send(socket, { message, false })
                    end
                else
                    cryptoNet.send(socket, { message, false })
                end
            elseif message == "getCurrentlyCrafting" then
                debugLog("gotCurrentlyCrafting: " .. dump(data))
                os.queueEvent("gotCurrentlyCrafting", data)
            elseif message == "getCraftingQueue" then
                os.queueEvent("gotCraftingQueue", data)
            elseif message == "pushCurrentlyCrafting" then
                debugLog("gotCurrentlyCrafting: " .. dump(data))
                currentlyCrafting = data
            elseif message == "pushCraftingQueue" then
                craftingQueue = data
            elseif message == "getFreeSlots" then
                local tmp = {}
                tmp.freeSlots = storageFreeSlots
                tmp.totalSlots = storageTotalSlots
                cryptoNet.send(socket, { message, tmp })
            elseif message == "pullItems" then
                debugLog("pullItems:" .. dump(data))
                local itemsMoved = peripheral.wrap(data.craftingChest).pullItems(data.chestName, data.slot,
                    data.moveCount)
                cryptoNet.send(socket, { message, itemsMoved })
                local patchstatus = patchStorageDatabase(data, -1 * itemsMoved, data.chestName, data.slot)
            elseif message == "patchStorageDatabase" then
                local patchstatus = patchStorageDatabase(data, data.count, data.chestName, data.slot)
            end
        elseif event[2] ~= nil then
            --User is not logged in
            local message = event[2][1]
            local data = event[2][2]
            if message == "hashLogin" then
                --Need to auth with storage server
                --debugLog("hashLogin")
                print("User login request for: " .. data.username)
                log("User login request for: " .. data.username)
                local loginStatus = cryptoNet.checkPassword(data.username, data.password, serverLAN)
                data.password = nil
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
                    if type(serverWireless) == "table" then
                        for k, v in pairs(serverWireless.sockets) do
                            if v.target == socket.target then
                                serverWireless.sockets[k] = socket
                                break
                            end
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
                if mainCraftingServer ~= nil and clients[i].target == mainCraftingServer.target then
                    mainCraftingServer = nil
                end
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
    os.setComputerLabel(settings.get("serverName"))
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
        elseif peripheral.getType(side) == "monitor" then
            table.insert(monitors, side)
        end
    end

    -- Start the cryptoNet server
    if type(wiredModem) ~= "nil" then
        serverLAN = cryptoNet.host(settings.get("serverName", true, false, wiredModem.side))
    end

    if type(wirelessModem) ~= "nil" then
        serverWireless = cryptoNet.host(settings.get("serverName") .. "_Wireless", true, false, wirelessModem.side)
    end

    --os.startThread(importHandler)
    local speed = (os.epoch("utc") / 1000) - serverBootTime
    print("Boot time: " .. tostring(("%.3g"):format(speed) .. " seconds"))
    debugLog("Boot time: " .. tostring(("%.3g"):format(speed) .. " seconds"))
    if next(monitors) then
        os.startThread(monitorHandler)
        --monitorHandler()
    end
    importHandler()
end

term.clear()
print("debug mode: " .. tostring(settings.get("debug")))
print("exportChests are set to : " .. dump(settings.get("exportChests")))
print("importChests are set to: " .. dump(settings.get("importChests")))
print("craftingChests is set to: " .. dump(settings.get("craftingChests")))

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
        --storageFreeSlots = decoded.storageFreeSlots
        --storageTotalSlots = decoded.storageTotalSlots
    end
end

items, storageUsed, storageFreeSlots, storageTotalSlots = getList(storages)
--debugLog(dump(items))
--for k,v in pairs(items) do
--    debugLog("k: " .. tostring(k) .. " v: " .. textutils.serialize(v))
--end

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
