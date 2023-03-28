# ComputerCraft Item Storage System
 A wireless/wired server-client item storage system using only ComputerCraft

 Required mods: ComputerCraft

 Installation:
  `pastebin run 9ghzwfjw`
 
  It is reccomended to label your import, export and crafting chest before running the install
 
 The network name of the chest will be displayed in chat when you rightclick the modem its connected to, click on the name to copy to clipboard. You can now paste this during install using (Ctrl + V)
 
  Import chests are chests where if any item is entered, it will automatically be pulled into the system
  
  Export chests are chests where a client can request items be sent to. This must be configured on both the server and client side
 
  Crafting chest is the chest the system puts items into for the crafty turtle to grab. This is only needed if autocrafting is enabled. This chest should be located on the block above your crafty turtle. An import chest must also be set under the turtle
  
  Any chest on the network not set to be a crafting, import or export chest will be used for item storage
 
 Supports just about any type of storage block

Basic Server setup

![Basic server setup](https://user-images.githubusercontent.com/7072789/163578699-88fae8f4-cc99-4a9c-a802-a3b1547a5215.png)

Basic Client setup

![Basic Client setup](https://user-images.githubusercontent.com/7072789/163578734-a6088531-5736-46bd-b54a-7070c89872ac.png)

Production setup

![Production setup](https://user-images.githubusercontent.com/7072789/163578859-f478dd1f-b95c-45ff-8126-7a688373bc47.png)

Client main menu

![Client main menu](https://user-images.githubusercontent.com/7072789/169100557-be2069fc-7148-4c4b-8881-e661e7f87516.png)

Client search

![Client search](https://user-images.githubusercontent.com/7072789/169100641-91e9e3dc-2774-4622-99be-3ec9ed3acb04.png)


Client item menu

![Client item menu](https://user-images.githubusercontent.com/7072789/169100658-a97d762b-f7dd-4930-857b-2e951a8ffc20.png)


Client crafting search

![craftinglist](https://user-images.githubusercontent.com/7072789/169099908-1498e88b-c062-485d-9121-2df91752a363.png)

Client crafting menu

![craftingmenu](https://user-images.githubusercontent.com/7072789/169099960-7d4ec2a1-6251-4ecf-90d2-8ea3239763a1.png)

Server Startup

![server startup](https://user-images.githubusercontent.com/7072789/169101034-f1c15ce4-d1f1-4794-9d49-67d5d6f81cdf.png)


Server interface

![server interface](https://user-images.githubusercontent.com/7072789/169101058-5fdf8f29-a8a7-4706-bd63-d95453363df6.png)

Dumping recipes:
- Add crafttweaker to your mods folder: https://www.curseforge.com/minecraft/mc-mods/crafttweaker
- Start a single player world and run `/ct recipes`
- Find the text file in logs/crafttweaker.log
- Use grep or other text filtering program to filter the text `grep craftingTable crafttweaker.log > recipes`
- Host the text file somewhere on the internet like pastebin
- Paste the URL during install (Ctrl + V)
