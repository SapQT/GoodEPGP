GoodEPGP = LibStub("AceAddon-3.0"):NewAddon("GoodEPGP", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0")

-- Add our slash commands
SLASH_GEP1, SLASH_GEP2 = "/goodepgp", "/gep"
function SlashCmdList.GEP(msg, editbox)
    if (msg == nil) then
        return true
    end
    GoodEPGP:PrivateCommands(msg)
    GoodEPGP:PublicCommands(msg)
end

-- Alert the player the add-on has started, and register our events.
function GoodEPGP:OnEnable()
    -- Default settings
    if (GoodEPGPConfig == nil) then
        GoodEPGPConfig = {
            ["trigger"] = "!gep",
            ["debugEnabled"] = false,
            ["decayPercent"] = 0.1,
            ["minGP"] = 100,
        }
    end

    -- Use our settings
    GoodEPGP.config = GoodEPGPConfig

    -- Our options menu
    GoodEPGP.configOptions = {
        {["key"] = "trigger", ["type"] = "EditBox", ["label"] = "GoodEPGP Trigger", ["default"] = "!gep"},
        {["key"] = "decayPercent", ["type"] = "EditBox", ["label"] = "Decay Percentage", ["default"] = ".1"},
        {["key"] = "minGP", ["type"] = "EditBox", ["label"] = "Minimum GP", ["default"] = "100"},
        {["type"] = "Heading", ["text"] = "Debug"},
        {["key"] = "debugEnabled", ["type"] = "CheckBox", ["label"] = "Debug Mode", ["default"] = "true"},
    }
    
    -- Notify that debug is enabled
    GoodEPGP:Debug('Debug is enabled.')

    -- Events
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("CHAT_MSG_WHISPER")
    self:RegisterEvent("GUILD_ROSTER_UPDATE")
    self:RegisterEvent("CHAT_MSG_LOOT")
    
    -- Table to track which loot buttons have atttached click events
    GoodEPGP.lootButtons = {}

    GoodEPGP:ImportStandings()
end

-- =====================
-- EVENT HANDLERS
-- =====================

-- Record and report loot message.
function GoodEPGP:CHAT_MSG_LOOT(event, text, arg1, arg2, arg3, playerName)
    if (text == nil or playerName == nil) then
        return
    end
    
    local itemLink = string.match(text, "|%x+|Hitem:.-|h.-|h|r")
    local itemId = select(2, strsplit(":", itemLink))

    -- Parse out link & rarity
    local itemName, _, itemRarity = GetItemInfo(itemId)

    local currentTime = date("%m/%d/%y %H:%M:%S")
    -- Generate string
    local lootString = currentTime .. "|" .. playerName .. "|" .. itemName .. "|" .. itemRarity
    
    if (itemRarity == nil or itemRarity < 4) then
        return
    end

    -- Save loot to the table
    if (GoodEPGPLoot == nil) then
        GoodEPGPLoot = {}
    end

    -- Save this loot to the stored table
    if (playerName ~= nil) then
        table.insert(GoodEPGPLoot, lootString)

        local msg = "[GoodEPGP]: " .. playerName .. " has looted " .. itemLink .. "."
        SendChatMessage(msg, "GUILD")
    end
end

-- Re-compile our internal EPGP table
function GoodEPGP:GUILD_ROSTER_UPDATE()
    GoodEPGP:ExportGuildRoster()
end

-- Add click event listeners for all items within a loot box
function GoodEPGP:LOOT_OPENED()
	local n = GetNumLootItems()
    for i = 1, n do
        local buttonName = "LootButton" .. tostring(i)
        
        local buttonExists = false
        for j = 0, #GoodEPGP.lootButtons do
            if (GoodEPGP.lootButtons[j] == buttonName) then
                buttonExists = true
            end
        end

        if (buttonExists == false) then
            table.insert(GoodEPGP.lootButtons, buttonName)
            local button = _G[buttonName]
            if (button ~= nil) then
                _G[buttonName]:HookScript("OnClick", function(button, data)                
                    GoodEPGP:LootClick(button, data, button.slot);
                end)    
            end
        end
	end
end

-- Close our bid window when loot window is closed
function GoodEPGP:LOOT_CLOSED()
    GoodEPGP:HideBidFrame()
end

-- Event handler for being whispered
function GoodEPGP:CHAT_MSG_WHISPER(type, whisperText, playerName)
    -- If a whisper starts with the triger, route it to a separate function
    local trigger = select(1, strsplit(" ", whisperText))
    local player = select(1, strsplit("-", playerName))
    if (trigger == GoodEPGP.config.trigger) then
        -- Check if there's a command to send to the PublicCommands meethod
        if (string.find(whisperText, " ") == nil) then
            return
        end
        
        -- Separate out the actual command and parameters, send them to PublicCommand
        local command = string.sub(whisperText, string.find(whisperText, " ") + 1)
        GoodEPGP:PublicCommands(command, player)
        return
    end

    -- Prevent further processing if it's not a bid
    if (whisperText ~= "+" and whisperText ~= "-") then 
        return
    end

    -- Handle bidding
    if (GoodEPGP.activeBid ~= true) then 
        return
    end

    local memberInfo = GoodEPGP:GetGuildMemberByName(player)
    -- Set our bid type
    memberInfo.type = whisperText
    -- Insert into bids table
    table.insert(GoodEPGP.bids, memberInfo)

    GoodEPGP:UpdateBidFrame()
end

-- =====================
-- COMMAND ROUTING
-- =====================

-- Handle private command parsing/routing
function GoodEPGP:PrivateCommands(commandMessage)
    local command = select(1, strsplit(" ", commandMessage))
    local arg1 = select(2, strsplit(" ", commandMessage))
    local arg2 = select(3, strsplit(" ", commandMessage))
    local arg3 = select(4, strsplit(" ", commandMessage))
    
    -- Add EP to a player
    if (command == "ep") then
        if (arg1 ~= "" and arg2 ~= "") then
            if (arg1:lower() == "raid") then
                GoodEPGP:AddEPToRaid(arg2)
            elseif (arg1:lower() == "list") then
                GoodEPGP:AddEPToList(arg2, arg3)
            else
                GoodEPGP:AddEPByName(arg1, arg2)
            end
        end
    end

    if (command == "options") then
        GoodEPGP:OpenOptions()
    end

    if (command == "import") then
        GoodEPGP:ImportRecords()
    end

    -- Add GP to a player
    if (command == "gp") then
        if (arg1 ~= "" and arg2 ~= "") then
            GoodEPGP:AddGPByName(arg1, arg2)
        end
    end

    -- Decay EPGP standings
    if (command == "decay") then
        GoodEPGP:Decay()
    end

    -- Round all EP & GP
    if (command == "round") then
        GoodEPGP:RoundPoints()
    end

    -- Reset EPGP standings
    if (command == "reset") then
        GoodEPGP:Reset()
    end
    
    -- Charge a player for an item
    if (command == "charge") then
        GoodEPGP:ChargeForItem(arg1, arg2, arg3)
    end
end

-- Handle public command parsing / routing
function GoodEPGP:PublicCommands(commandMessage, playerName)
    if (commandMessage == "") then
        return true
    end
    local command = select(1, strsplit(" ", commandMessage))
    local arg1 = select(2, strsplit(" ", commandMessage))
    local arg2 = select(3, strsplit(" ", commandMessage))
    local argString = nil
    local type = nil

    -- Full string after the command
    if (string.find(commandMessage, " ") ~= nil) then
        argString = string.sub(commandMessage, string.find(commandMessage, " ") + 1)
    end

    -- Set response type
    if (playerName ~= nil) then
        type = "whisper"
    end

    -- Item cost lookup
    if (command == "item") then
        GoodEPGP:ShowPrice(argString, type, playerName)
        return
    end

    -- Standings lookup by class
    if (command == "standings") then
        GoodEPGP:ShowStandingsByClass(arg1, arg2, type, playerName)
        return
    end

    -- Player standngs lookup
    if (command == "player") then
        GoodEPGP:PlayerInfo(arg1, type, playerName)
        return
    end

    -- Set spec via member note
    if (command == "setspec" and playerName ~= nil) then
        GoodEPGP:SetSpec(playerName, arg1)
        return
    end

    -- None of the if statements triggered, let's assume they want an item lookup
    GoodEPGP:ShowPrice(commandMessage, type, playerName)
    GoodEPGP:PlayerInfo(commandMessage, type, playerName)
    GoodEPGP:ShowStandingsByClass(commandMessage, 1, type, playerName)

end

-- =====================
-- PRIVATE FUNCTIONS
-- =====================

function GoodEPGP:HandleLoot(msg)
    self:Print(msg)
end

-- Event function that fires when a loot button is clicked within the loot box
function GoodEPGP:LootClick(button, data, key)
    -- If it's just currency, or the slot is empty, just return.
    local item = GetLootSlotLink(key)
    if (item == nil) then
        return
    end
    
    -- Set our object vars to remember what's being currently looted.
    local itemName = select(1, GetItemInfo(item))
    local itemLink = select(2, GetItemInfo(item))
    local itemQuality = select(3, GetItemInfo(item))
    local itemID = select(2, strsplit(":", itemLink, 3))
    GoodEPGP.activeItemIndex = key
    GoodEPGP.activeItem = item   

    -- You can only ML stuff that's uncommon +
    if (itemQuality <= 1) then
        return
    end

    -- If the alt key is being run down, run a EPGP  bid
    if (IsAltKeyDown()) then 
        -- Alt + Left Click
        if (data == "LeftButton") then
            GoodEPGP:StartBid(itemID)
            return
        end
    end

    -- Don't allow random roll / loot to self if quality >= 5 (Epic)
    if (itemQuality >= 5) then
        return
    end

    -- Check if ctrl key is being held down
    -- if (IsControlKeyDown()) then
    --     -- Ctrl + Left Click
    --     if (data == "LeftButton") then
    --         GoodEPGP:LootToSelf()
    --         return
    --     end
    -- end
end

-- Start a bid for the current item
function GoodEPGP:StartBid(itemID)
    local price = GoodEPGP:GetPrice(itemID)
    local offspecPrice = math.floor(price * .25)
    GoodEPGP.activePrice = price
    GoodEPGP.activeOffspecPrice = offspecPrice
    GoodEPGP.activeBid = true
    GoodEPGP.bids = {}

    GoodEPGP:WidestAudience("Whisper me + for main spec, - for off spec to bid on " .. GoodEPGP.activeItem .. ". (MS Cost: " .. price .. " GP)")
    GoodEPGP:UpdateBidFrame()
end

-- Loot current item to self
function GoodEPGP:LootToSelf()
    -- Get player's name
    local playerName = UnitName("player")
    
    -- Retrieve player's master loot index
    candidateIndex = GoodEPGP:MasterLootByName(playerName)
end

-- Get an item's GP price by item ID
function GoodEPGP:GetPrice(itemID)
    local price = 0
    itemID = tonumber(itemID)
    if (GoodEPGP.prices[itemID] ~= nil) then
        local priceTable = GoodEPGP.prices[itemID]
        price = priceTable[1];
    end
    return price
end

-- Retrive the price of an item, and send it back via whisper/console
function GoodEPGP:ShowPrice(item, type, playerName)
    -- Attempt to pull up item data via link
    local itemID = GoodEPGP:GetItemID(item)

    -- If we couldn't find an item id, try a wildcard check against the price list
    if (itemID == nil) then
        local itemIDs = GoodEPGP:GetWildcardItemIDs(item)
        -- Display the price info for all matching items
        for key, value in pairs(itemIDs) do
            GoodEPGP:DisplayPrice(value, type, playerName)
        end
    else
        -- Display the price info for the single matching info.
        GoodEPGP:DisplayPrice(itemID, type, playerName)
    end
end

-- Gets a list of all item IDs that match item name
function GoodEPGP:GetWildcardItemIDs(item) 
    local itemIDs = {}
    for key, value in pairs(GoodEPGP.prices) do
        if (string.find(value[2]:lower(), item:lower()) ~= nil) then
            table.insert(itemIDs, key)
        end
    end

    return itemIDs
end

-- Display the price of an item
function GoodEPGP:DisplayPrice(itemID, type, playerName)
    -- Verify we have a passed itemID
    if (itemID == nil) then
        return false
    end

    -- Verify itemID is numeric
    itemID = tonumber(itemID)

    -- Retrieve item info from the database asynchronously
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function() 
        local itemName = select(1, GetItemInfo(itemID))
        local itemLink = select(2, GetItemInfo(itemID))
        local itemPrice = GoodEPGP:GetPrice(itemID)
        local itemString = GoodEPGP:PadString(itemPrice .. "GP", 10, "_", "right") .. itemLink
        GoodEPGP:HandleOutput(itemString, type, playerName)
    end)
end

-- Get an item's ID based on the name (retrived from prices.lua)
function GoodEPGP:GetItemID(itemString)
    local itemID = nil
    
    -- Attempt to retrieve item info by name / item link
    local itemLink = select(2, GetItemInfo(itemString))
    if (itemLink ~= nil) then
        -- Pull itemID from itemLink
        itemID = select(2, strsplit(":", itemLink, 3))
        -- If itemID is set, return it.
        if (itemID ~= nil) then
            return itemID
        end
    end

    -- Couldn't find by a straight GetItemInfo lookup, let's try looking it up in our price list.
    for key, value in pairs(GoodEPGP.prices) do
        local itemName = value[2]
        if (itemString:lower() == itemName:lower()) then
            itemID = key;
        end
    end

    -- Return whatever we have itemID
    return itemID
end

-- Retrieve the current guild roster
function GoodEPGP:ExportGuildRoster()
    GoodEPGP.standings = {};
    for i = 1, GetNumGuildMembers() do
        -- Retrieve information about our player, remove the realm name
        local player = select(1, GetGuildRosterInfo(i))
        if (player ~= nil) then
            player = select(1, strsplit("-", player))
        end
        local officerNote  = select(8, GetGuildRosterInfo(i))
        local level = select(4, GetGuildRosterInfo(i))
        local class = select(5, GetGuildRosterInfo(i))
        local spec = select(7, GetGuildRosterInfo(i))

        -- Set initial EPGP
        if (officerNote == nil or string.find(officerNote, ",") == nil) then
            officerNote = '0,100'
            -- GoodEPGP:SetEPGPByName(player, 0, 100)
        end

        -- Retrieve the player's EPGP
        local ep = select(1, strsplit(",", officerNote))
        local gp = select(2, strsplit(",", officerNote))
        ep = tonumber(ep)
        gp = tonumber(gp)

        -- Round to 2 decimal places
        ep = GoodEPGP:Round(ep, 2)
        gp = GoodEPGP:Round(gp, 2)

        -- Just making sure ..
        if (ep == nil) then
            ep = 0
        end

        -- Make sure we're above the min GP.
        if (gp == nil or gp < GoodEPGP.config.minGP) then
            gp = GoodEPGP.config.minGP
        end

        -- Calculate our PR
        local pr = GoodEPGP:Round(ep/gp, 2)

        -- Add the player to our standings table
        GoodEPGP.standings[i] = {["player"]=player, ["ep"]=ep, ["gp"]=gp, ["pr"]=pr, ["class"]=class, ["spec"]=spec, ["level"]=level}
    end

    table.sort(GoodEPGP.standings, function(a, b)
        return a.pr > b.pr
    end)

    local raiderList = {}
    -- Filter out people with no EP, less than lvl 55
    for key, player in pairs(GoodEPGP.standings) do
        if (tonumber(player.level) > 55 and tonumber(player.ep) > 0) then
            table.insert(raiderList, player)
        end
    end

    GoodEPGPStandings = GoodEPGP:ConvertToJSON(raiderList)
end

-- Converts a our Lua table to json string for processing
function GoodEPGP:ConvertToJSON(table) 
    local jsonString = ""
    jsonString = jsonString .. "["
    for key, playerTable in pairs(table) do
        jsonString = jsonString .. "{"
        for infoKey, infoValue in pairs(playerTable) do
            jsonString = jsonString .. "\"" .. infoKey .. "\": \"" .. infoValue .. "\", "  
        end
        jsonString = jsonString:sub(1, -3) .. "},"
    end
    jsonString = jsonString:sub(1, -2) .. "]"

    return jsonString
end

-- Award master loot by name
function GoodEPGP:MasterLootByName(playerName)
    playerName = GoodEPGP:UCFirst(playerName)
    for i = 1, 40 do
        local candidate = GetMasterLootCandidate(GoodEPGP.activeItemIndex, i)
        if (candidate == playerName) then
            -- Award the item
            GiveMasterLoot(GoodEPGP.activeItemIndex, i)
        end
    end
end

-- Add EP to a player by their name
function GoodEPGP:AddEPByName(name, amount)
    name = GoodEPGP:UCFirst(name)
    message = "Adding " .. amount .. " EP to " .. name .. ".";
    if (amount == nil) then
        amount = 0
    end
    GoodEPGP:Debug(message)
    SendChatMessage(message, "GUILD")
    GoodEPGP:SetEPGPByName(name, nil, nil, amount, nil)
end

-- Add GP to a player by their name
function GoodEPGP:AddGPByName(name, amount)
    name = GoodEPGP:UCFirst(name)
    message = "Adding " .. amount .. " GP to " .. name .. "."
    GoodEPGP:Debug(message)
    SendChatMessage(message, "GUILD")
    GoodEPGP:SetEPGPByName(name, nil, nil, nil, amount)
end

-- Set a player's EPGP by name (used on mass updates)
function GoodEPGP:SetEPGPByName(player, ep, gp, addEp, addGp)
    -- If our addEp or addGp params are set, add the amount before setting.
    if (addEp ~= nil or addGp ~= nil) then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, class, _, note, officerNote, _, _ = GetGuildRosterInfo(i)
            if (player == select(1, strsplit("-", name))) then
                ep = select(1, strsplit(",", officerNote))
                gp = select(2, strsplit(",", officerNote))
                if (ep == nil or ep == "") then
                    ep = 0
                end
                if (gp == nil or gp == "") then
                    gp = GoodEPGP.config.minGP
                end

                if (addEp ~= nil) then
                    ep = tonumber(ep) + tonumber(addEp)
                end
                if (addGp ~= nil) then
                    gp = tonumber(gp) + tonumber(addGp)
                end                
            end
        end
    end 

    -- Round our EP & GP
    ep = GoodEPGP:Round(ep, 2)
    gp = GoodEPGP:Round(gp, 2)
    
    -- Set the EPGP record
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
        if (player == select(1, strsplit("-", name))) then
            -- Format our officer note
            local epgpString = tostring(ep) .. "," .. tostring(gp)

            -- Inform to console
            GoodEPGP:Debug('Updated ' .. player .. ' to ' .. epgpString);

            -- Update the officer note
            GuildRosterSetOfficerNote(i, epgpString)
        end
    end
end

-- Set a player's spec
function GoodEPGP:SetSpec(player, spec)
    player = select(1, strsplit("-", player))

    local playerClass = nil
    -- Loop through and grab the player's current class
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
        if (player == select(1, strsplit("-", name))) then
            playerClass = class;
            GoodEPGP:Debug(playerClass)
        end
    end
    
    -- Loop through and check if this is a valid spec
    local validSpec = false
    for key, value in pairs(GoodEPGP.specs) do
        if (value[1]:lower() == playerClass:lower() and value[2]:lower() == spec:lower()) then
            validSpec = true
        end
    end

    -- Reply based on whether it's a valid spec, then set the member note
    if (validSpec) then
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
            if (player == select(1, strsplit("-", name))) then
                GuildRosterSetPublicNote(i, GoodEPGP:UCFirst(spec))
            end
        end
        GoodEPGP:SendWhisper("Your specialization has been set.", player)
    else
        GoodEPGP:SendWhisper("Please choose a valid spec for your class.", player)
    end

    return
end

-- Get a player's index within the guild roster
function GoodEPGP:GetGuildMemberByName(name)
    local playerInfo
    if (name == nil) then
        GoodEPGP:Debug("Empty name for guild member lookup.")
    else 
        for i = 1, GetNumGuildMembers() do
            local guildName, _, _, _, class, _, note, officerNote, _, _ = GetGuildRosterInfo(i)
            -- Strip the server name
            guildName = select(1, strsplit("-", guildName))
            if (guildName:lower() == name:lower()) then
                local ep = select(1, strsplit(",", officerNote))
                local gp = select(2, strsplit(",", officerNote))
                if (ep == nil or gp == nil) then
                    ep = 0
                    gp = 100
                end
                local pr = GoodEPGP:Round(tonumber(ep) / tonumber(gp), 2)
                playerInfo = {
                    ["name"] = GoodEPGP:UCFirst(guildName),
                    ["spec"] = GoodEPGP:UCFirst(note),
                    ["class"] = GoodEPGP:UCFirst(class),
                    ["ep"] = ep,
                    ["gp"] = gp,
                    ["pr"] = pr,
                };
            end
        end
    end
    return playerInfo
end

-- Reset EPGP of all members
function GoodEPGP:Reset()
    -- Loop through guild roster, decay all members
    for i = 1, GetNumGuildMembers() do
        local guildName, _, _, _, class, _, note, officerNote, _, _ = GetGuildRosterInfo(i)
        local ep = 0
        local gp = 100
        playerName = select(1, strsplit("-", guildName))
        GoodEPGP:SetEPGPByName(playerName, ep, gp)
    end
end

-- Decay EPGP of all members
function GoodEPGP:Decay()
    -- Loop through guild roster, decay all members
    for i = 1, GetNumGuildMembers() do
        local guildName, _, _, _, class, _, note, officerNote, _, _ = GetGuildRosterInfo(i)
        if (string.find(officerNote, ",") == nil) then
            officerNote = '0,100'
        end
        
        local ep = select(1, strsplit(",", officerNote))
        local gp = select(2, strsplit(",", officerNote))
        ep = tonumber(ep)
        gp = tonumber(gp)

        if (ep > 0) then
            ep = ep * (1 - tonumber(GoodEPGP.config.decayPercent))
            gp = gp * (1 - tonumber(GoodEPGP.config.decayPercent))
            if (gp < GoodEPGP.config.minGP) then
                gp = GoodEPGP.config.minGP
            end
            playerName = select(1, strsplit("-", guildName))
            GoodEPGP:SetEPGPByName(playerName, ep, gp)
        end
    end

    local decayPercent = GoodEPGP:Round(GoodEPGP.config.decayPercent * 100, 0) .. '%.'
    GoodEPGP:Debug("EP & GP have been decayed by " .. decayPercent)
end

-- Round all player's EP & GP to 2 decimal places
function GoodEPGP:RoundPoints()
    -- Loop through guild roster, decay all members
    for i = 1, GetNumGuildMembers() do
        local guildName, _, _, _, class, _, note, officerNote, _, _ = GetGuildRosterInfo(i)
        if (string.find(officerNote, ",") == nil) then
            officerNote = '0,100'
        end
        
        local ep = select(1, strsplit(",", officerNote))
        local gp = select(2, strsplit(",", officerNote))
        ep = tonumber(ep)
        gp = tonumber(gp)
        local ep = GoodEPGP:Round(ep, 2)
        local gp = GoodEPGP:Round(gp, 2)

        if (ep > 0) then
            playerName = select(1, strsplit("-", guildName))
            GoodEPGP:SetEPGPByName(playerName, ep, gp)
        end
    end
end

-- Get a player's current EP/GP standing. Name = player to lookup, type = (whisper|console), playerName = player to whisper back with information
function GoodEPGP:PlayerInfo(name, type, playerName)
    local memberInfo = GoodEPGP:GetGuildMemberByName(name)
    GoodEPGP:ShowPlayerInfo(memberInfo, type, playerName)
end

-- Output a single line of standings
function GoodEPGP:ShowPlayerInfo(memberInfo, type, playerName)
    if (memberInfo == nil) then
        return
    end
    local playerString = memberInfo.name .. ": " .. memberInfo.ep .. " EP / " .. memberInfo.gp .. " GP (" .. memberInfo.pr .. " Prio)"
    GoodEPGP:HandleOutput(playerString, type, playerName)
end

-- Add a certain amount of EP to all players in the raid
function GoodEPGP:AddEPToRaid(amount)
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup, level, class = GetRaidRosterInfo(i);
        local guildInfo = GoodEPGP:GetGuildMemberByName(name)
        if (guildInfo ~= nil) then
            GoodEPGP:AddEPByName(name, amount)
        end
    end
    GoodEPGP:WidestAudience("Added " .. amount .. " EP to entire raid.")
end

-- Add a certain amount of EP to a comma delimited list of guild members
function GoodEPGP:AddEPToList(list, amount) 
    list = GoodEPGP:SplitString(list, ",")
    for key, member in pairs(list) do
        GoodEPGP:AddEPByName(member, amount)
    end
end

-- Confirm the item should be looted to player
function GoodEPGP:ConfirmAwardItem(playerName, type)
    -- Hide our bid frame when awarding
    GoodEPGP:HideBidFrame()

    local confirmString = "Are you sure you want to loot this item to " .. playerName .. " as " .. type .. "?"
    GoodEPGP:ConfirmAction(confirmString, function() 
        GoodEPGP:AwardItem(playerName, type)
    end,
    function() 


        GoodEPGP:UpdateBidFrame() 
    end)
end

-- Award the current item up for bids to player by namne.  priceType = (ms|os)
function GoodEPGP:AwardItem(playerName, priceType)
    -- Format player's name 
    playerName = GoodEPGP:UCFirst(playerName)

    -- Retrive player's candidate index by name
    GoodEPGP:MasterLootByName(playerName)
   
    --- Award main spec or offspec GP
    GoodEPGP:ChargeForItem(playerName, GoodEPGP.activeItem, priceType)
end

-- Charge a player for an item
function GoodEPGP:ChargeForItem(member, itemString, priceType, type, playerName)
    local itemID = GoodEPGP:GetItemID(itemString)
    if (itemID == nil) then
        GoodEPGP:HandleOutput('Could not find item: ' .. itemString, type, member)
        return
    end

    local price = GoodEPGP:GetPrice(itemID)
    if (priceType == 'os') then 
        price = GoodEPGP:Round(price * .25, 2)
    end

    GoodEPGP:Debug("Adding " .. price .. "GP to " .. member .. " for " .. itemString)
    GoodEPGP:AddGPByName(member, price)
end

-- Show standings by class, with a minimum priority (1 by default)
function GoodEPGP:ShowStandingsByClass(class, minimumPrio, type, playerName)
    -- Retrieve our standings by class(es)
    local classStandings = GoodEPGP:GetStandingsByClass(class:lower())
    if (classStandings == nil or #classStandings == 0) then
        return
    end
    
    -- Check if minimum is set and numeric
    minimumPrio = tonumber(minimumPrio)
    if (minimumPrio == nil) then
        minimumPrio = .1
    end
    
    -- Loop through our classStandings table and show every line above minimum prio
    for key, memberInfo in pairs(classStandings) do
        if (tonumber(memberInfo.pr) >= tonumber(minimumPrio)) then
            GoodEPGP:ShowPlayerInfo(memberInfo, type, playerName)
        end
    end
end

-- Get EPGP standings by class/classes
function GoodEPGP:GetStandingsByClass(class)
    local classes = nil
    if (string.find(class, ",") ~= nil) then
        classes = GoodEPGP:SplitString(class, ",")
    end

    local classStandings = {}
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i)
        name = select(1, strsplit("-", name))
        local member = GoodEPGP:GetGuildMemberByName(name)
        if (member == nil) then
            return classStandings
        end
        if (classes ~= nil) then 
            for classKey, className in pairs(classes) do
                if (member.class == GoodEPGP:UCFirst(className)) then
                    table.insert(classStandings, member)
                end
            end
        else
            if (member.class == GoodEPGP:UCFirst(class)) then
                table.insert(classStandings, member)
            end
        end
    end
    table.sort(classStandings, function(a, b)
        return a.pr > b.pr
    end)
    return classStandings
end

function GoodEPGP:OpenOptions()
    local AceGUI = LibStub("AceGUI-3.0")
    GoodEPGP.optionFrame = AceGUI:Create("Frame")
    GoodEPGP.optionFrame:SetTitle("GoodEPGP Options")
    GoodEPGP.optionFrame:SetStatusText("Configure your GoodEPGP")
    GoodEPGP.optionFrame:SetLayout("List")
    GoodEPGP.optionFrame:SetCallback("OnClose", function(widget) 
        AceGUI:Release(widget) 
        GoodEPGP.optionFrame = nil
    end)

    for key, value in pairs(GoodEPGP.configOptions) do
        local configWidget = AceGUI:Create(value.type)
        if (value.label ~= nil) then
            configWidget:SetLabel(value.label)
        end
        if (value.description ~= nil) then
            configWidget:SetDescription(value.description)
        end
        if (value.text ~= nil) then
            configWidget:SetText(value.text)
        end
        configWidget:SetFullWidth(true)

        -- Set our initial values by type, and callback
        if (value.type == "EditBox") then
            configWidget:SetText(GoodEPGP.config[value.key])
            configWidget:SetCallback("OnEnterPressed", function(widget)
                GoodEPGP.config[value.key] = widget:GetText()
                GoodEPGPConfig = GoodEPGP.config
            end)
        end
        if (value.type == "CheckBox") then
            configWidget:SetValue(GoodEPGP.config[value.key])
            configWidget:SetCallback("OnValueChanged", function(widget)
                GoodEPGP.config[value.key] = widget:GetValue()
                GoodEPGPConfig = GoodEPGP.config
            end)
        end

        GoodEPGP.optionFrame:AddChild(configWidget)
    end

end

function GoodEPGP:CreateBidFrame()
    local AceGUI = LibStub("AceGUI-3.0")
    GoodEPGP.bidFrame = AceGUI:Create("Frame")
    GoodEPGP.bidFrame:SetTitle("GoodEPGP")
    GoodEPGP.bidFrame:SetStatusText("Current bids for " .. GoodEPGP.activeItem)
    GoodEPGP.bidFrame:SetCallback("OnClose", function(widget) 
        AceGUI:Release(widget) 
        GoodEPGP.bidFrame = nil
    end)
    GoodEPGP.bidFrame:SetLayout("Flow")
end

function GoodEPGP:HideBidFrame()
    local AceGUI = LibStub("AceGUI-3.0")
    if (GoodEPGP.bidFrame == nil) then
        return
    end
    AceGUI:Release(GoodEPGP.bidFrame) 
    GoodEPGP.bidFrame = nil
end

function GoodEPGP:UpdateBidFrame()
    local AceGUI = LibStub("AceGUI-3.0")

    -- Sort by prio
    table.sort(GoodEPGP.bids, function(a, b)
        return a.pr > b.pr
    end)

    -- Create or reset bid frame
    if (GoodEPGP.bidFrame ~= nil) then
        AceGUI:Release(GoodEPGP.bidFrame)
    end
    GoodEPGP:CreateBidFrame()

    -- Add title
    GoodEPGP:AddBidFrameTitle("Main Spec")

    -- Add Header
    GoodEPGP:AddBidFrameHeader()

    -- Main Spec
    for i=1, #GoodEPGP.bids do
        local bid = GoodEPGP.bids[i]
        if (bid.type == "+") then
            GoodEPGP:AddBidLine(bid, "ms")
        end
    end

    -- Add spacer
    GoodEPGP:AddBidFrameTitle(" ")

    -- Add title
    GoodEPGP:AddBidFrameTitle("Off Spec")
        
    -- Add Header
    GoodEPGP:AddBidFrameHeader()

    -- Off Spec
    for i=1, #GoodEPGP.bids do
        local bid = GoodEPGP.bids[i]
        if (bid.type == "-") then
           GoodEPGP:AddBidLine(bid, "os")
        end
    end
end

function GoodEPGP:AddBidFrameTitle(title)
    local AceGUI = LibStub("AceGUI-3.0")
    local titleLabel = AceGUI:Create("Label")
    titleLabel:SetText(title)
    titleLabel:SetFullWidth(true)
    titleLabel:SetJustifyH("Left")
    titleLabel:SetFont("Fonts\\FRIZQT__.TTF", 14)
    GoodEPGP.bidFrame:AddChild(titleLabel)
end

function GoodEPGP:AddBidFrameHeader()
    local AceGUI = LibStub("AceGUI-3.0")

    -- Our table of header data (width, label)
    local headers = {
        {200, "Player"},
        {150, "Level/Class"},
        {50, "EP"},
        {50, "GP"},
        {50, "Prio"},
        {150, ""}
    }

    -- Generate header labels
    for key, value in pairs(headers) do
        local headerLabel = AceGUI:Create("Label")
        headerLabel:SetText(value[2])
        headerLabel:SetWidth(value[1])
        GoodEPGP.bidFrame:AddChild(headerLabel)
    end
end


function GoodEPGP:AddBidLine(bid, bidType)
    local AceGUI = LibStub("AceGUI-3.0")

    local assignButton = AceGUI:Create("Button")
    assignButton:SetText("Assign")
    assignButton:SetWidth(100)
    assignButton:SetCallback("OnClick", function() 
        GoodEPGP:ConfirmAwardItem(bid.name, bidType)
    end)

    local spacerLabel = AceGUI:Create("Label")
    spacerLabel:SetText(" ")
    spacerLabel:SetWidth(50)

    local playerLabel = AceGUI:Create("Label")
    playerLabel:SetText(bid.name)
    playerLabel:SetWidth(200)

    local classLabel = AceGUI:Create("Label")
    classLabel:SetText(bid.spec .. " " .. bid.class)
    classLabel:SetWidth(150)

    local epLabel = AceGUI:Create("Label")
    epLabel:SetText(bid.ep)
    epLabel:SetWidth(50)

    local gpLabel = AceGUI:Create("Label")
    gpLabel:SetText(bid.gp)
    gpLabel:SetWidth(50)

    local prioLabel = AceGUI:Create("Label")
    prioLabel:SetText(bid.pr)
    prioLabel:SetWidth(100)

    GoodEPGP.bidFrame:AddChild(playerLabel)
    GoodEPGP.bidFrame:AddChild(classLabel)
    GoodEPGP.bidFrame:AddChild(epLabel)
    GoodEPGP.bidFrame:AddChild(gpLabel)
    GoodEPGP.bidFrame:AddChild(prioLabel)
    GoodEPGP.bidFrame:AddChild(assignButton)
end

function GoodEPGP:ImportRecords()
    -- Don't bother unless we have records
    if (GoodEPGPImport == nil or #GoodEPGPImport == 0) then
        return
    end

    -- Loop through import data
    for key, value in pairs(GoodEPGPImport) do
        GoodEPGP:ChargeForItem(value["name"], value["item"], value["type"])
    end

    -- Clear out our import variable so we don't import twice
    GoodEPGPImport = {}
end

function GoodEPGP:ImportStandings()
    -- Don't bother unless we have records
    if (GoodEPGPStandingsImport == nil or #GoodEPGPStandingsImport == 0) then
        return
    end

    -- Inform debug that we're importing.
    GoodEPGP:Debug('Importing standings.')

    -- Loop through import data
    for key, value in pairs(GoodEPGPStandingsImport) do
        if (tonumber(value.ep) > 0) then
            GoodEPGP:Debug(value.player)
            GoodEPGP:SetEPGPByName(value.player, value.ep, value.gp)
        end
    end

    -- GoodEPGPStandingsImport = {}
end

-- =====================
-- UTILITY FUNCTIONS
-- =====================

-- Capitalize the first letter of a word, lowercase the rest.
function GoodEPGP:UCFirst(word)
    word = word:sub(1,1):upper() .. word:sub(2):lower()
    return word
end

-- Send a branded whisper to player.  message = message to send, playerName = player to whisper
function GoodEPGP:SendWhisper(message, playerName)
    SendChatMessage("GEPGP: " .. message, "WHISPER", "COMMON", playerName)
end

-- Send a branded message to guild chat
function GoodEPGP:SendGuild(message)
    SendChatMessage("GEPGP: " .. message, "GUILD")
end

-- Round a number to a certain number of places
function GoodEPGP:Round(num, places)
    local mult = 10^(places or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Determine which chat channel should be used to display a message
function GoodEPGP:WidestAudience(msg, rw)
    if (rw == nil) then
        rw = true
    end
    local channel = "GUILD"
    if UnitInRaid("player") then
        if ((UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and rw == true) then
            channel = "RAID_WARNING"
        else
            channel = "RAID"
        end
    elseif UnitExists("party1") then
        channel = "PARTY"
    end
    SendChatMessage(msg, channel)
end

-- Pad a string
function GoodEPGP:PadString(originalString, length, padCharacter, direction) 
    if (padCharacter == nil) then 
        padCharacter = ' ' 
    end
    if (direction == nil) then
        direction = "right"
    end
    originalString = tostring(originalString)
    
    local padString = ""
    if (direction == "left") then
        padString = string.rep(padCharacter, length - #originalString) .. originalString
    else
        padString = originalString .. string.rep(padCharacter, length - #originalString)
    end

    return padString
end

-- Handle output to console / whisper
function GoodEPGP:HandleOutput(string, type, playerName)
    if (type == "whisper") then
        GoodEPGP:SendWhisper(string, playerName)
    else
        self:Print('GEPGP: ' .. string)
    end
end

-- Split a string into a table
function GoodEPGP:SplitString(string, delimiter)
    result = {};
    for match in (string..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

-- Put up a confirmation modal
function GoodEPGP:ConfirmAction(confirmString, acceptCallback, cancelCalback)
    StaticPopupDialogs["CONFIRM_ACTION"] ={
        preferredIndex = 5,
        text = confirmString,
        button1 = "Yes",
        button2 = "No",
        OnAccept = acceptCallback,
        OnCancel = cancelCalback,
        timeout = 0,
        hideOnEscape = false,
        showAlert = true
    }

    StaticPopup_Show("CONFIRM_ACTION")      
end

function GoodEPGP:Debug(message)
    if (GoodEPGP.config.debugEnabled == true) then
        self:Print("DEBUG: " .. message)
    end
end