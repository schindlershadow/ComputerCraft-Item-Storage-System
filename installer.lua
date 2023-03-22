term.clear()
term.setCursorPos(1, 1)
print("ComputerCraft Item Storage System by SchindlerShadow")
print("")
local download
if turtle then
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
        print("")
        input = io.read()
        if tonumber(input) == nil or (tonumber(input) ~= 1 and tonumber(input) ~= 2) then
            print("Invaid input")
            input = -1
            sleep(1)
            term.clear()
            term.setCursorPos(1, 1)
        end
        print("")
    end
    if tonumber(input) == 1 then
        print("Installing Server file: storageCraftingServer.lua as startup program")
        download = http.get(
            "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/storageServer.lua")
    else
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
print("Install Complete")
sleep(1)
print("")
print("Rebooting...")
sleep(1)
os.reboot()
