local addonName = ...

local PREFIX = "|cFF00FFFF[Patron Helper]|r "
local ROW_HEIGHT = 24
local CALLER_ID = "PatronHelper"

local function Print(msg)
    print(PREFIX .. msg)
end

local function EnsureDB()
    if type(PatronHelperDB) ~= "table" then
        PatronHelperDB = {}
    end
    if type(PatronHelperDB.shoppingList) ~= "table" then
        PatronHelperDB.shoppingList = {}
    end
    if type(PatronHelperDB.importedOrders) ~= "table" then
        PatronHelperDB.importedOrders = {}
    end
end

local function ExtractItemID(node, depth)
    depth = depth or 0
    if depth > 6 then
        return nil
    end
    if type(node) == "number" then
        return node
    end
    if type(node) ~= "table" then
        return nil
    end
    if type(node.itemID) == "number" then
        return node.itemID
    end
    if type(node.id) == "number" then
        return node.id
    end
    -- Midnight stores itemID at reagentInfo.reagent.itemID; older builds used reagent.itemID.
    return ExtractItemID(node.reagentInfo, depth + 1) or ExtractItemID(node.reagent, depth + 1)
end

local function ExtractQuantity(node)
    if type(node) ~= "table" then
        return 0
    end
    if type(node.quantity) == "number" then
        return node.quantity
    end
    if node.reagentInfo and type(node.reagentInfo.quantity) == "number" then
        return node.reagentInfo.quantity
    end
    if node.reagent and type(node.reagent) == "table" and type(node.reagent.quantity) == "number" then
        return node.reagent.quantity
    end
    if node.reagentInfo and node.reagentInfo.reagent and type(node.reagentInfo.reagent.quantity) == "number" then
        return node.reagentInfo.reagent.quantity
    end
    return 0
end

local function GetOrderSlotIndex(orderReagent)
    if type(orderReagent) ~= "table" then
        return nil
    end
    return orderReagent.slotIndex
        or orderReagent.reagentSlot
        or (orderReagent.reagentInfo and (orderReagent.reagentInfo.slotIndex or orderReagent.reagentInfo.reagentSlot))
end

-- order.reagents is the customer's allocation list; Blizzard does not filter it by source.
local function IsCustomerOnlySlot(slot)
    local customer = Enum.CraftingOrderReagentSource and Enum.CraftingOrderReagentSource.Customer
    return customer ~= nil and slot.orderSource == customer
end

local function GetOwnedCount(itemID)
    if not itemID then
        return 0
    end
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID, true, false, true, true) or 0
    end
    if GetItemCount then
        return GetItemCount(itemID, true, false, true, true) or 0
    end
    return 0
end

local function GetOwnedForEntry(entry)
    local total = GetOwnedCount(entry.itemID)
    if entry.altItemIDs then
        for i = 1, #entry.altItemIDs do
            total = total + GetOwnedCount(entry.altItemIDs[i])
        end
    end
    return total
end

local function GetStillNeeded(entry)
    return math.max(0, (entry.quantity or 0) - GetOwnedForEntry(entry))
end

local function RequestItem(itemID)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function GetItemNameLink(itemID)
    local name, link
    if C_Item and C_Item.GetItemInfo then
        name, link = C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        name, link = GetItemInfo(itemID)
    end
    if not name then
        RequestItem(itemID)
    end
    return name, link
end

local function GetItemIconTexture(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    local globalGetItemIcon = _G.GetItemIcon
    if globalGetItemIcon then
        return globalGetItemIcon(itemID)
    end
    return nil
end

local function MergeAltIDs(entry, altItemIDs)
    if not altItemIDs or #altItemIDs == 0 then
        return
    end
    entry.altItemIDs = entry.altItemIDs or {}
    local seen = { [entry.itemID] = true }
    for i = 1, #entry.altItemIDs do
        seen[entry.altItemIDs[i]] = true
    end
    for i = 1, #altItemIDs do
        local id = altItemIDs[i]
        if id and not seen[id] then
            seen[id] = true
            table.insert(entry.altItemIDs, id)
        end
    end
end

local function AddToList(itemID, quantity, altItemIDs)
    for _, existing in ipairs(PatronHelperDB.shoppingList) do
        if existing.itemID == itemID then
            existing.quantity = (existing.quantity or 0) + quantity
            MergeAltIDs(existing, altItemIDs)
            return
        end
    end
    local entry = {
        itemID = itemID,
        quantity = quantity,
    }
    MergeAltIDs(entry, altItemIDs)
    table.insert(PatronHelperDB.shoppingList, entry)
    RequestItem(itemID)
end

-- Main UI
local frame = CreateFrame("Frame", "PatronHelperFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(300, 400)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:SetToplevel(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:Hide()

table.insert(UISpecialFrames, "PatronHelperFrame")

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
frame.title:SetText("Patron Helper Shopping List")

local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 5, -5)
scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -25, 5)

local scrollChild = CreateFrame("Frame", "$parentScrollChild", scrollFrame)
scrollChild:SetSize(1, 1)
scrollFrame:SetScrollChild(scrollChild)

local listText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
listText:SetPoint("TOPLEFT", 5, -5)
listText:SetJustifyH("LEFT")
listText:SetJustifyV("TOP")
listText:SetText("List is empty.")

frame.InsetBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 70)

local importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
importButton:SetSize(120, 22)
importButton:SetPoint("BOTTOMLEFT", 10, 10)
importButton:SetText("Import Order")

local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
clearButton:SetSize(100, 22)
clearButton:SetPoint("BOTTOMRIGHT", -10, 10)
clearButton:SetText("Clear List")

local searchAHButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
searchAHButton:SetSize(120, 22)
searchAHButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
searchAHButton:SetText("Search in AH")

local function SaveFramePosition()
    EnsureDB()
    local point, _, relativePoint, x, y = frame:GetPoint()
    PatronHelperDB.position = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function RestoreFramePosition()
    EnsureDB()
    local pos = PatronHelperDB.position
    if not pos or not pos.point then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x or 0, pos.y or 0)
end

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveFramePosition()
end)

local function ToggleFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

SLASH_PATRONHELPER1 = "/ph"
SLASH_PATRONHELPER2 = "/patronhelper"

local AddOpenCraftingOrder
local ConfirmClearShoppingList

SlashCmdList["PATRONHELPER"] = function(msg)
    msg = msg and strtrim(msg):lower() or ""
    if msg == "clear" then
        ConfirmClearShoppingList()
    elseif msg == "import" then
        AddOpenCraftingOrder()
    else
        ToggleFrame()
    end
end

_G.PatronHelper_OnAddonCompartmentClick = function()
    ToggleFrame()
end

local listButtons = {}
local UpdateListDisplay
local refreshPending = false

local function ScheduleRefresh()
    if refreshPending then
        return
    end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        if frame:IsShown() then
            UpdateListDisplay()
        end
    end)
end

local function LayoutScrollChild(rowCount)
    local width = math.max(1, scrollFrame:GetWidth())
    local height = math.max(scrollFrame:GetHeight(), (rowCount or 0) * ROW_HEIGHT + 10)
    scrollChild:SetSize(width, height)
    listText:SetWidth(math.max(1, width - 10))
    for _, btn in ipairs(listButtons) do
        btn:SetWidth(math.max(1, width - 10))
    end
end

local function RemoveListEntry(index)
    EnsureDB()
    if not index or not PatronHelperDB.shoppingList[index] then
        return
    end
    table.remove(PatronHelperDB.shoppingList, index)
    UpdateListDisplay()
end

local function GetOrCreateListButton(index)
    if listButtons[index] then
        return listButtons[index]
    end

    local btn = CreateFrame("Button", nil, scrollChild)
    btn:SetSize(math.max(1, scrollChild:GetWidth() - 10), 20)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", -16, 0)
    text:SetJustifyH("LEFT")
    btn.text = text

    btn:SetScript("OnEnter", function(self)
        if not self.itemID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:AddLine(" ")
        if self.hasQualityAlts then
            GameTooltip:AddLine("Shopping list uses the lowest quality.", 0.6, 0.8, 1, true)
        end
        GameTooltip:AddLine("Shift-click to link. Right-click to remove.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            RemoveListEntry(self.listIndex)
            return
        end
        local _, itemLink = GetItemNameLink(self.itemID)
        if itemLink and HandleModifiedItemClick then
            HandleModifiedItemClick(itemLink)
        elseif itemLink and IsModifiedClick("CHATLINK") then
            ChatEdit_InsertLink(itemLink)
        end
    end)

    local removeBtn = CreateFrame("Button", nil, btn)
    removeBtn:SetSize(16, 16)
    removeBtn:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    local removeLabel = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    removeLabel:SetPoint("CENTER")
    removeLabel:SetText("x")
    removeBtn:SetFontString(removeLabel)
    removeBtn:SetNormalFontObject(GameFontNormalSmall)
    removeBtn:SetHighlightFontObject(GameFontHighlightSmall)
    removeBtn:SetScript("OnClick", function()
        RemoveListEntry(btn.listIndex)
    end)
    btn.removeBtn = removeBtn

    listButtons[index] = btn
    return btn
end

UpdateListDisplay = function()
    EnsureDB()

    for _, btn in ipairs(listButtons) do
        btn:Hide()
    end

    local list = PatronHelperDB.shoppingList
    if #list == 0 then
        listText:SetText("List is empty.")
        listText:Show()
        LayoutScrollChild(0)
        return
    end

    listText:Hide()
    LayoutScrollChild(#list)

    local yOffset = -5
    for i, item in ipairs(list) do
        local itemName, itemLink = GetItemNameLink(item.itemID)
        local displayText = itemLink or ("[" .. (itemName or ("Item " .. tostring(item.itemID))) .. "]")
        local owned = GetOwnedForEntry(item)
        local stillNeeded = math.max(0, (item.quantity or 0) - owned)

        local btn = GetOrCreateListButton(i)
        btn.itemID = item.itemID
        btn.listIndex = i
        btn.hasQualityAlts = item.altItemIDs and #item.altItemIDs > 0

        local iconTexture = GetItemIconTexture(item.itemID)
        if iconTexture then
            btn.icon:SetTexture(iconTexture)
            btn.icon:Show()
        else
            btn.icon:Hide()
        end

        if stillNeeded > 0 then
            btn.text:SetText(stillNeeded .. "x " .. displayText)
            btn.text:SetTextColor(1, 1, 1)
        else
            btn.text:SetText("Have " .. owned .. "x " .. displayText)
            btn.text:SetTextColor(0.5, 0.8, 0.5)
        end

        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
        btn:Show()
        yOffset = yOffset - ROW_HEIGHT
    end
end

scrollFrame:SetScript("OnSizeChanged", function()
    if frame:IsShown() then
        UpdateListDisplay()
    else
        EnsureDB()
        LayoutScrollChild(PatronHelperDB.shoppingList and #PatronHelperDB.shoppingList or 0)
    end
end)

frame:SetScript("OnShow", UpdateListDisplay)

local function ClearShoppingList()
    EnsureDB()
    PatronHelperDB.shoppingList = {}
    PatronHelperDB.importedOrders = {}
    UpdateListDisplay()
    Print("Shopping list cleared.")
end

ConfirmClearShoppingList = function()
    EnsureDB()
    if #PatronHelperDB.shoppingList == 0 then
        Print("Shopping list is already empty.")
        return
    end
    StaticPopup_Show("PATRONHELPER_CLEAR_LIST")
end

StaticPopupDialogs["PATRONHELPER_CLEAR_LIST"] = {
    text = "Clear the Patron Helper shopping list?",
    button1 = YES,
    button2 = NO,
    OnAccept = ClearShoppingList,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

clearButton:SetScript("OnClick", ConfirmClearShoppingList)

AddOpenCraftingOrder = function()
    EnsureDB()

    if not ProfessionsFrame or not ProfessionsFrame.OrdersPage or not ProfessionsFrame.OrdersPage:IsVisible() then
        Print("No crafting order page is currently open.")
        return
    end

    local orderView = ProfessionsFrame.OrdersPage.OrderView
    local order = orderView and orderView.order
    if not order then
        Print("No crafting order selected.")
        return
    end

    if order.orderID then
        local orderKey = tostring(order.orderID)
        if PatronHelperDB.importedOrders[orderKey] then
            Print("This order is already on your shopping list.")
            return
        end
    end

    local spellID = order.spellID
    if not spellID then
        Print("Could not determine order spell ID.")
        return
    end

    local isRecraft = order.isRecraft
    if isRecraft == nil and orderView.IsRecrafting then
        isRecraft = orderView:IsRecrafting()
    end
    isRecraft = not not isRecraft

    local schematic = C_TradeSkillUI.GetRecipeSchematic(spellID, isRecraft, order.recipeLevel)
    if not schematic or not schematic.reagentSlotSchematics then
        Print("Could not get recipe schematic.")
        return
    end

    local basicReagentEnum = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    local addedItems = 0

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagentType == basicReagentEnum and not IsCustomerOnlySlot(slot) then
            local required = slot.quantityRequired or 0
            if required > 0 then
                local validItemIDs = {}
                local altItemIDs = {}
                local baseItemID = nil

                for i, r in ipairs(slot.reagents) do
                    local rItemID = ExtractItemID(r)
                    if rItemID then
                        validItemIDs[rItemID] = true
                        if i == 1 then
                            baseItemID = rItemID
                        else
                            table.insert(altItemIDs, rItemID)
                        end
                    end
                end

                local provided = 0
                if order.reagents and type(order.reagents) == "table" then
                    for _, orderReagent in ipairs(order.reagents) do
                        local orderSlot = GetOrderSlotIndex(orderReagent)
                        local matchesSlot
                        if orderSlot and slot.slotIndex then
                            matchesSlot = orderSlot == slot.slotIndex
                        else
                            local itemID = ExtractItemID(orderReagent)
                            matchesSlot = itemID and validItemIDs[itemID]
                        end
                        if matchesSlot then
                            provided = provided + ExtractQuantity(orderReagent)
                        end
                    end
                end

                -- Store gross remaining from the order. Bags are subtracted at display/search time
                -- so importing multiple orders does not double-count inventory.
                local remainingNeeded = required - provided
                if remainingNeeded > 0 and baseItemID then
                    AddToList(baseItemID, remainingNeeded, altItemIDs)
                    addedItems = addedItems + remainingNeeded
                end
            end
        end
    end

    if order.orderID then
        PatronHelperDB.importedOrders[tostring(order.orderID)] = true
    end

    if addedItems > 0 then
        Print("Added " .. addedItems .. " reagents to your shopping list.")
        UpdateListDisplay()
    else
        Print("Order requires no basic reagents from you.")
    end
end

importButton:SetScript("OnClick", AddOpenCraftingOrder)

searchAHButton:SetScript("OnClick", function()
    EnsureDB()

    if not PatronHelperDB.shoppingList or #PatronHelperDB.shoppingList == 0 then
        Print("Your shopping list is empty.")
        return
    end

    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        Print("Open the Auction House first.")
        return
    end

    if not Auctionator or not Auctionator.API or not Auctionator.API.v1 then
        Print("Auctionator not found or incompatible API.")
        return
    end

    local advancedSearchTerms = {}
    local fallbackTerms = {}
    local missingNames = 0

    for _, item in ipairs(PatronHelperDB.shoppingList) do
        local stillNeeded = GetStillNeeded(item)
        if stillNeeded > 0 then
            local itemName = GetItemNameLink(item.itemID)
            if itemName then
                table.insert(advancedSearchTerms, {
                    searchString = itemName,
                    isExact = true,
                    quantity = stillNeeded,
                })
                table.insert(fallbackTerms, itemName)
            else
                missingNames = missingNames + 1
            end
        end
    end

    if #advancedSearchTerms == 0 then
        if missingNames > 0 then
            Print("Waiting for item names to load; try again in a moment.")
        else
            Print("You already have everything on the list.")
        end
        return
    end

    local ok, err
    if Auctionator.API.v1.MultiSearchAdvanced then
        ok, err = pcall(Auctionator.API.v1.MultiSearchAdvanced, CALLER_ID, advancedSearchTerms)
    elseif Auctionator.API.v1.MultiSearchExact then
        ok, err = pcall(Auctionator.API.v1.MultiSearchExact, CALLER_ID, fallbackTerms)
    elseif Auctionator.API.v1.MultiSearch then
        ok, err = pcall(Auctionator.API.v1.MultiSearch, CALLER_ID, fallbackTerms)
    else
        Print("Auctionator not found or incompatible API.")
        return
    end

    if not ok then
        Print("Auctionator search failed: " .. tostring(err))
    end
end)

local professionButton
local ahButton

local function IsAddOnLoadedSafe(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if IsAddOnLoaded then
        return IsAddOnLoaded(name)
    end
    return false
end

local function SetupProfessionButton()
    if professionButton or not ProfessionsFrame or not ProfessionsFrame.OrdersPage then
        return
    end

    local parent = ProfessionsFrame.OrdersPage
    professionButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    professionButton:SetSize(120, 22)
    professionButton:SetText("Patron Helper")
    -- Parent is the Orders tab so this is hidden on Crafting/Specializations.
    professionButton:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 16, 8)

    professionButton:SetScript("OnClick", ToggleFrame)
end

local function SetupAuctionHouseButton()
    if ahButton or not AuctionHouseFrame then
        return
    end

    ahButton = CreateFrame("Button", nil, AuctionHouseFrame, "UIPanelButtonTemplate")
    ahButton:SetSize(95, 22)
    ahButton:SetText("Patron Helper")

    if AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.FilterButton then
        ahButton:SetPoint("RIGHT", AuctionHouseFrame.SearchBar.FilterButton, "LEFT", -5, 0)
    else
        ahButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -36, -6)
    end

    ahButton:SetScript("OnClick", ToggleFrame)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_DATA_LOAD_RESULT")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            EnsureDB()
            RestoreFramePosition()
            if IsAddOnLoadedSafe("Blizzard_Professions") then
                SetupProfessionButton()
            end
            if IsAddOnLoadedSafe("Blizzard_AuctionHouseUI") then
                SetupAuctionHouseButton()
            end
        elseif arg1 == "Blizzard_Professions" then
            SetupProfessionButton()
        elseif arg1 == "Blizzard_AuctionHouseUI" then
            SetupAuctionHouseButton()
        end
    elseif (event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" or event == "BAG_UPDATE_DELAYED") and frame:IsShown() then
        ScheduleRefresh()
    end
end)
