local type
term.clear()
term.setCursorPos(1, 1)
print("ComputerCraft Item Storage System by SchindlerShadow")
print("")
local download
if turtle then
    type = "craftingServer"
    print("Turtle Detected")
    print("Installing Crafting Server file: storageCraftingServer.lua as startup program")
    download = http.get(
        "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/storageCraftingServer.lua")
    sleep(1)
else
    local input = -1
    while tonumber(input) ~= 1 and tonumber(input) ~= 2 do
        print("Please select a role for this computer")
        print("1 Server")
        print("2 Client")
        print("3 Exit")
        print("")
        input = io.read()

        if tonumber(input) == nil or (tonumber(input) ~= 1 and tonumber(input) ~= 2 and tonumber(input) ~= 3) then
            print("Invaid input")
            input = -1
            sleep(1)
            term.clear()
            term.setCursorPos(1, 1)
        end
        if tonumber(input) == 3 then
            print("")
            print("Goodbye")
            sleep(1)
            term.clear()
            term.setCursorPos(1, 1)
            return
        end
    end
    print("")
    if tonumber(input) == 1 then
        type = "storageServer"
        print("Installing Server file: storageServer.lua as startup program")
        download = http.get(
            "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/storageServer.lua")
    else
        type = "storageClient"
        print("Installing Client file: storageClient.lua as startup program")
        download = http.get(
            "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/storageClient.lua")
    end
end


local handle = download.readAll()
download.close()
local file = fs.open("startup", "w")
file.write(handle)
file.close()

print("")
print("Startup file Install Complete")
sleep(2)
term.clear()
term.setCursorPos(1, 1)
print("Would you like to run the settings configurator?")
print("This will wipe any currently set settings")
print("")
print("1 Help me setup settings")
print("2 I dont need help")
print("")
local input = io.read()
term.clear()
term.setCursorPos(1, 1)

if tonumber(input) ~= nil and tonumber(input) == 1 then
    --settings configurator
    local crafting = false
    local recipeURL =
    "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/vanillaRecipes.txt"
    local craftingChest = "minecraft:chest_3"
    local exportChestName = "minecraft:chest_0"
    local exportChests = { "minecraft:chest_0" }
    local importChests = { "minecraft:chest_2" }

    settings.clear()

    if type == "craftingServer" or type == "storageServer" then
        term.clear()
        term.setCursorPos(1, 1)
        print("Set the network name of the chest to be used for crafting")
        print("Example: minecraft:chest_3")
        print("Type 0 if your not using autocrafting")
        print("")
        local craftingChestInput = io.read()
        if craftingChestInput ~= "0" then
            craftingChest = craftingChestInput
        end
    end

    if type == "craftingServer" then
        term.clear()
        term.setCursorPos(1, 1)
        print("Would you like to use a custom recipe URL?")
        print("The default recipe URL contains vanilla Minecraft recipes")
        print("Look on the github page to learn how to dump recipes for modpacks")
        print("")
        print("1 Vanilla Minecraft recipes")
        print("2 Custom recipe URL")
        print("")
        local customRecipe = io.read()
        if tonumber(customRecipe) ~= nil and tonumber(customRecipe) == 2 then
            term.clear()
            term.setCursorPos(1, 1)
            print("Enter Recipe URL:")
            print("")
            local recipeURLinput = io.read()
            print("")
            local success, message = http.checkURL(recipeURLinput)
            if not success then
                error("Invalid URL: " .. message)
            else
                local canReachURL = false
                http.request(recipeURLinput)
                while true do
                    event, url = os.pullEvent()
                    if event == "http_failure" then
                        error("Cannot contact the server: " .. recipeURLinput)
                        break
                    elseif event == "http_success" then
                        print("URL is reachable")
                        recipeURL = recipeURLinput
                        break
                    end
                end
            end
        end
        settings.set("debug", false)
        settings.set("recipeURL", recipeURL)
        settings.set("recipeFile", "recipes")
        settings.set("craftingChest", craftingChest)
    elseif type == "storageServer" then
        term.clear()
        term.setCursorPos(1, 1)
        print("Set the number of export chests")
        print("Type 0 to set default")
        print("")
        local numOfExportChests = tonumber(io.read())
        if numOfExportChests ~= 0 then
            for i = 1, numOfExportChests do
                term.clear()
                term.setCursorPos(1, 1)
                print("Set the network name of export chest #" .. tostring(i))
                print("")
                exportChests[i] = io.read()
            end
        end

        term.clear()
        term.setCursorPos(1, 1)
        print("Set the number of import chests")
        print("Type 0 to set default")
        print("")
        local numOfImportChests = tonumber(io.read())
        if numOfImportChests ~= 0 then
            for i = 1, numOfImportChests do
                term.clear()
                term.setCursorPos(1, 1)
                print("Set the network name of import chest #" .. tostring(i))
                print("")
                importChests[i] = io.read()
            end
        end

        settings.set("debug", false)
        settings.set("exportChests", exportChests)
        settings.set("importChests", importChests)
        settings.set("craftingChest", craftingChest)
    else
        term.clear()
        term.setCursorPos(1, 1)
        print("Set the network name of the export chest")
        print("Example: minecraft:chest_0")
        print("Type 0 to set default")
        print("")
        local exportChestInput = io.read()
        if exportChestInput ~= "0" then
            exportChestName = exportChestInput
        end

        term.clear()
        term.setCursorPos(1, 1)
        print("Enable autocrafting support?")
        print("(If set you MUST have a crafting server setup on a crafty turtle)")
        print("")
        print("1 Yes")
        print("2 No")
        print("")
        local enableCraftingInput = io.read()
        if enableCraftingInput == "1" then
            crafting = true
        end

        settings.set("debug", false)
        settings.set("crafting", crafting)
        settings.set("exportChestName", exportChestName)
    end
    settings.save()
end
print("")
print("Setup complete, Rebooting...")
sleep(2)
os.reboot()
