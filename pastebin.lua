local download = "https://raw.githubusercontent.com/schindlershadow/ComputerCraft-Item-Storage-System/main/installer.lua"

if fs.exists("installer.lua") then
    print("Removing old installer")
    fs.delete("installer.lua")
end

print("Grabbing new installer")
local response = http.get(download)
if response then
    local file = fs.open("installer.lua", "w")
    file.write(response.readAll())
    file.close()
    response.close()
    print("File downloaded as installer.lua")
else
    print("Failed to download file from " .. download)
end
sleep(2)
if response then
    shell.run("installer.lua")
end
