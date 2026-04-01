local addonName, addonTable = ...

-- Register Slash Commands
SLASH_PATRONHELPER1 = "/ph"
SLASH_PATRONHELPER2 = "/patronhelper"

SlashCmdList["PATRONHELPER"] = function(msg)
    if PatronHelperFrame:IsShown() then
        PatronHelperFrame:Hide()
    else
        PatronHelperFrame:Show()
    end
end

-- Addon Compartment Function
_G.PatronHelper_OnAddonCompartmentClick = function(addonName, buttonName)
    if PatronHelperFrame:IsShown() then
        PatronHelperFrame:Hide()
    else
        PatronHelperFrame:Show()
    end
end

-- Create the main UI Frame
local frame = CreateFrame("Frame", "PatronHelperFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(300, 400)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

-- Title
frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
frame.title:SetText("Patron Helper Shopping List")

-- Scroll Frame for the list
local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 5, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -25, 5)

local scrollChild = CreateFrame("Frame", "$parentScrollChild", scrollFrame)
scrollChild:SetSize(scrollFrame:GetWidth(), scrollFrame:GetHeight())
scrollFrame:SetScrollChild(scrollChild)

local listText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listText:SetPoint("TOPLEFT", 5, -5)
listText:SetJustifyH("LEFT")
listText:SetJustifyV("TOP")
listText:SetWidth(scrollChild:GetWidth() - 10)
listText:SetText("List is empty.")

-- Buttons
local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
importButton:SetSize(120, 22)
importButton:SetPoint("BOTTOMLEFT", 10, 10)
importButton:SetText("Import Order")

local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
clearButton:SetSize(100, 22)
clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
clearButton:SetText("Clear List")

-- Adjust inset bottom so text/scrollframe doesn't overlap the buttons
frame.InsetBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 40)

-- Functions
local listButtons = {}
local UpdateListDisplay

local function GetOrCreateListButton(index)
    if not listButtons[index] then
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetSize(scrollChild:GetWidth() - 10, 20)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", 0, 0)
        text:SetPoint("RIGHT", -25, 0)
        text:SetJustifyH("LEFT")
        btn.text = text
        
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self, button)
            -- Support shift-clicking to paste into Chat or Auction House
            local _, itemLink = GetItemInfo(self.itemID)
            if itemLink and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(itemLink)
            end
        end)

        local removeBtn = CreateFrame("Button", nil, btn, "UIPanelCloseButton")
        removeBtn:SetSize(20, 20)
        removeBtn:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        removeBtn:SetScript("OnClick", function(self)
            if btn.listIndex then
                table.remove(PatronHelperDB.shoppingList, btn.listIndex)
                UpdateListDisplay()
            end
        end)
        btn.removeBtn = removeBtn

        listButtons[index] = btn
    end
    return listButtons[index]
end

UpdateListDisplay = function()
    -- Hide all existing buttons
    for _, btn in ipairs(listButtons) do
        btn:Hide()
    end

    if not PatronHelperDB or not PatronHelperDB.shoppingList or #PatronHelperDB.shoppingList == 0 then
        listText:SetText("List is empty.")
        listText:Show()
        return
    end

    listText:Hide()
    local yOffset = -5

    for i, item in ipairs(PatronHelperDB.shoppingList) do
        local itemName = item.name
        local itemLink = nil
        
        if GetItemInfo then
            local infoName, link = GetItemInfo(item.itemID)
            if infoName then
                itemName = infoName
                item.name = itemName
                itemLink = link
            end
        end

        local btn = GetOrCreateListButton(i)
        btn.itemID = item.itemID
        btn.listIndex = i
        
        -- Default to bracketed name if link isn't cached yet
        local displayText = itemLink or ("[" .. (itemName or "Unknown Item") .. "]")
        
        btn.text:SetText("- " .. item.quantity .. "x " .. displayText)
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
        btn:Show()
        
        yOffset = yOffset - 25
    end
end

local function ClearShoppingList()
    if not PatronHelperDB then PatronHelperDB = {} end
    PatronHelperDB.shoppingList = {}
    UpdateListDisplay()
    print("|cff00ff00PatronHelper|r: Shopping list cleared.")
end
clearButton:SetScript("OnClick", ClearShoppingList)

local function AddOpenCraftingOrder()
    if not ProfessionsFrame or not ProfessionsFrame.OrdersPage or not ProfessionsFrame.OrdersPage:IsVisible() then
        print("|cff00ff00PatronHelper|r: No crafting order page is currently open.")
        return
    end

    local order = ProfessionsFrame.OrdersPage.OrderView.order
    if not order then
        print("|cff00ff00PatronHelper|r: No crafting order selected.")
        return
    end

    local spellID = order.spellID
    if not spellID then
        print("|cff00ff00PatronHelper|r: Could not determine order spell ID.")
        return
    end

    local schematic = C_TradeSkillUI.GetRecipeSchematic(spellID, false)
    if not schematic or not schematic.reagentSlotSchematics then
        print("|cff00ff00PatronHelper|r: Could not get recipe schematic.")
        return
    end

    local addedItems = 0
    if not PatronHelperDB.shoppingList then
        PatronHelperDB.shoppingList = {}
    end

    local customerSourceEnum = Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Customer or 0
    local basicReagentEnum = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 0

    -- Iterate through the actual recipe requirements
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- We only care about basic materials (not finishing/optional, which patron might provide but we don't buy)
        if slot.reagentType == basicReagentEnum then
            local required = slot.quantityRequired

            -- Map all valid itemIDs for this slot (e.g. all 3 quality levels of Bismuth)
            local validItemIDs = {}
            local baseItemID = nil
            for i, r in ipairs(slot.reagents) do
                local rItemID = nil
                local rCurrent = r
                for _ = 1, 4 do
                    if type(rCurrent) ~= "table" then
                        if type(rCurrent) == "number" then rItemID = rCurrent end
                        break
                    end
                    if rCurrent.itemID then rItemID = rCurrent.itemID; break end
                    if rCurrent.id then rItemID = rCurrent.id; break end
                    rCurrent = rCurrent.reagentInfo or rCurrent.reagent
                end

                if rItemID then
                    validItemIDs[rItemID] = true
                    if i == 1 then baseItemID = rItemID end -- First one is usually Tier 1
                end
            end

            -- Calculate how many the patron provided. Anything attached to the order is provided by them.
            local provided = 0
            local crafterEnum = Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Crafter or 1
            if order.reagents and type(order.reagents) == "table" then
                for _, orderReagent in ipairs(order.reagents) do
                    -- Identify the source dynamically
                    local source = orderReagent.source or (orderReagent.reagentInfo and orderReagent.reagentInfo.source)
                    
                    -- Assume provided by patron if it's explicitly not the crafter
                    if source ~= crafterEnum then
                        local itemID = nil
                        local current = orderReagent
                        
                        -- WoW API deeply nests itemID depending on the expansion (DF, TWW 11.0, Midnight 12.0+)
                        for _ = 1, 4 do
                            if type(current) ~= "table" then
                                if type(current) == "number" then itemID = current end
                                break
                            end
                            if current.itemID then itemID = current.itemID; break end
                            if current.id then itemID = current.id; break end
                            current = current.reagentInfo or current.reagent
                        end
                        
                        if itemID and validItemIDs[itemID] then
                            -- Check every possible known location for the quantity
                            local quantity = orderReagent.quantity
                                          or (orderReagent.reagentInfo and orderReagent.reagentInfo.quantity)
                                          or (orderReagent.reagentInfo and orderReagent.reagentInfo.reagent and orderReagent.reagentInfo.reagent.quantity)
                                          or (orderReagent.reagent and type(orderReagent.reagent) == "table" and orderReagent.reagent.quantity)
                                          or 0
                            provided = provided + quantity
                        end
                    end
                end
            end

            -- Calculate how many you ALREADY have in your bags, bank, reagent bank, and warbank!
            local inBags = 0
            for vItemID, _ in pairs(validItemIDs) do
                -- GetItemCount(itemID, includeBank, includeCharges, includeReagentBank, includeAccountBank)
                local count = GetItemCount and GetItemCount(vItemID, true, false, true, true) or 0
                if count == 0 and C_Item and C_Item.GetItemCount then
                    count = C_Item.GetItemCount(vItemID, true, false, true, true) or 0
                end
                inBags = inBags + count
            end

            local remainingNeeded = required - provided - inBags
            if remainingNeeded > 0 and baseItemID then
                local found = false
                for _, existing in ipairs(PatronHelperDB.shoppingList) do
                    if existing.itemID == baseItemID then
                        existing.quantity = existing.quantity + remainingNeeded
                        found = true
                        break
                    end
                end

                if not found then
                    table.insert(PatronHelperDB.shoppingList, {
                        itemID = baseItemID,
                        name = "Item " .. tostring(baseItemID),
                        quantity = remainingNeeded
                    })
                end
                addedItems = addedItems + remainingNeeded
            end
        end
    end

    if addedItems > 0 then
        print("|cff00ff00PatronHelper|r: Added " .. addedItems .. " missing reagents to your shopping list.")
        UpdateListDisplay()
    else
        print("|cff00ff00PatronHelper|r: Order requires no basic reagents from you.")
    end
end
importButton:SetScript("OnClick", AddOpenCraftingOrder)

-- Integration with Professions Frame
local function SetupProfessionButton()
    if PatronHelperProfessionButton then return end
    if not ProfessionsFrame then return end

    local btn = CreateFrame("Button", "PatronHelperProfessionButton", ProfessionsFrame, "UIPanelButtonTemplate")
    btn:SetSize(120, 22)
    -- Position it at the bottom to the left of the "Create All" button area
    btn:SetPoint("BOTTOMRIGHT", ProfessionsFrame, "BOTTOMRIGHT", -320, 8)
    btn:SetText("Patron Helper")

    btn:SetScript("OnClick", function()
        if PatronHelperFrame:IsShown() then
            PatronHelperFrame:Hide()
        else
            PatronHelperFrame:Show()
            PatronHelperFrame:ClearAllPoints()
            PatronHelperFrame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
        end
    end)
end

-- Event Handling for DB Initialization and Addon Loading
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            if not PatronHelperDB then
                PatronHelperDB = {
                    shoppingList = {}
                }
            end
            if not PatronHelperDB.shoppingList then
                PatronHelperDB.shoppingList = {}
            end

            frame:SetScript("OnShow", UpdateListDisplay)
            
            local isLoaded = false
            if C_AddOns and C_AddOns.IsAddOnLoaded then
                isLoaded = C_AddOns.IsAddOnLoaded("Blizzard_Professions")
            elseif IsAddOnLoaded then
                isLoaded = IsAddOnLoaded("Blizzard_Professions")
            end
            
            if isLoaded then
                SetupProfessionButton()
            end
        elseif arg1 == "Blizzard_Professions" then
            SetupProfessionButton()
        end
    end
end)
