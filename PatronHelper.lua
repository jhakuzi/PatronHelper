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
local function UpdateListDisplay()
    if not PatronHelperDB or not PatronHelperDB.shoppingList or #PatronHelperDB.shoppingList == 0 then
        listText:SetText("List is empty.")
        return
    end

    local text = ""
    for i, item in ipairs(PatronHelperDB.shoppingList) do
        local itemName = item.name
        if not itemName or itemName:find("^Item ") then
            if C_Item and C_Item.GetItemInfo then
                local infoName = C_Item.GetItemInfo(item.itemID)
                if infoName then
                    itemName = infoName
                    item.name = itemName
                end
            elseif GetItemInfo then
                local infoName = GetItemInfo(item.itemID)
                if infoName then
                    itemName = infoName
                    item.name = itemName
                end
            end
        end
        text = text .. "- " .. item.quantity .. "x " .. (itemName or "Unknown Item") .. "\n\n"
    end
    listText:SetText(text)
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
                if r.itemID then
                    validItemIDs[r.itemID] = true
                    if i == 1 then baseItemID = r.itemID end -- First one is usually Tier 1
                end
            end

            -- Calculate how many the patron provided. Anything attached to the order is provided by them.
            local provided = 0
            if order.reagents and type(order.reagents) == "table" then
                for _, orderReagent in ipairs(order.reagents) do
                    local itemID = orderReagent.reagent and orderReagent.reagent.itemID
                    if itemID and validItemIDs[itemID] then
                        provided = provided + (orderReagent.quantity or 0)
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

-- Event Handling for DB Initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if not PatronHelperDB then
            PatronHelperDB = {
                shoppingList = {}
            }
        end
        if not PatronHelperDB.shoppingList then
            PatronHelperDB.shoppingList = {}
        end

        frame:SetScript("OnShow", UpdateListDisplay)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
