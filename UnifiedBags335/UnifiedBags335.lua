local ADDON = "UnifiedBags335"
local UB = CreateFrame("Frame")
_G.UnifiedBags335 = UB

local BANK = BANK_CONTAINER or -1
local BAG_COUNT = NUM_BAG_SLOTS or 4
local BANK_BAG_COUNT = NUM_BANKBAGSLOTS or 7
local BUTTON_SIZE = 36
local BUTTON_GAP = 5
local GRID_LEFT = 18

UB.bankOpen = false
UB.guildBankOpen = false
UB.reagentAPI = nil
UB.refreshPending = false
UB.bankShowPending = false
UB.hooksInstalled = false
UB.displays = {}
UB.searchText = { bags = "", bank = "", guild = "" }

local DEFAULTS = {
    bagColumns = 10,
    bankColumns = 11,
    guildColumns = 14,
    visibleRows = 9,
    scale = 1.0,
    showBagSlots = true,
    showBankBagSlots = true,
}

local function CharacterKey()
    return UnitName("player") or "Unknown"
end

local function RealmKey()
    return GetRealmName() or "Unknown"
end

local function EnsureDB()
    if type(UnifiedBags335DB) ~= "table" then UnifiedBags335DB = {} end
    if type(UnifiedBags335DB.realms) ~= "table" then UnifiedBags335DB.realms = {} end
    if type(UnifiedBags335DB.settings) ~= "table" then UnifiedBags335DB.settings = {} end

    local s = UnifiedBags335DB.settings
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end

    local realm = RealmKey()
    if type(UnifiedBags335DB.realms[realm]) ~= "table" then UnifiedBags335DB.realms[realm] = {} end
    local name = CharacterKey()
    if type(UnifiedBags335DB.realms[realm][name]) ~= "table" then
        UnifiedBags335DB.realms[realm][name] = { bags = {}, bank = {}, reagents = {}, bankSeen = false }
    end
    return UnifiedBags335DB.realms[realm][name]
end

local function Settings()
    EnsureDB()
    return UnifiedBags335DB.settings
end

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

local function AddCount(tbl, itemID, amount)
    if not itemID or not amount or amount <= 0 then return end
    tbl[itemID] = (tbl[itemID] or 0) + amount
end

local function ScanContainers(containerIDs)
    local out = {}
    for _, bag in ipairs(containerIDs) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemID = ItemIDFromLink(link)
                local _, count = GetContainerItemInfo(bag, slot)
                AddCount(out, itemID, count or 1)
            end
        end
    end
    return out
end

function UB:GetBagIDs()
    local ids = { BACKPACK_CONTAINER or 0 }
    for bag = 1, BAG_COUNT do table.insert(ids, bag) end
    return ids
end

function UB:GetBankIDs()
    local ids = { BANK }
    for i = 1, BANK_BAG_COUNT do table.insert(ids, BAG_COUNT + i) end
    return ids
end

function UB:CacheBags()
    EnsureDB().bags = ScanContainers(self:GetBagIDs())
end

function UB:CacheBank()
    if not self.bankOpen then return end
    local char = EnsureDB()
    char.bank = ScanContainers(self:GetBankIDs())
    char.bankSeen = true
end

function UB:CacheReagents()
    local char = EnsureDB()
    char.reagents = {}
    if self.reagentAPI and self.reagentAPI.GetVirtualItems then
        for itemID, amount in pairs(self.reagentAPI:GetVirtualItems() or {}) do
            AddCount(char.reagents, tonumber(itemID), tonumber(amount))
        end
    end
end

function UB:AddAccountCounts(tooltip, itemID)
    if not itemID or not UnifiedBags335DB or not UnifiedBags335DB.realms then return end
    local realm = UnifiedBags335DB.realms[RealmKey()]
    if not realm then return end

    local rows, grandTotal = {}, 0
    for name, data in pairs(realm) do
        local bags = data.bags and (data.bags[itemID] or 0) or 0
        local bank = data.bank and (data.bank[itemID] or 0) or 0
        local reagents = data.reagents and (data.reagents[itemID] or 0) or 0
        local total = bags + bank + reagents
        if total > 0 then
            table.insert(rows, { name = name, bags = bags, bank = bank, reagents = reagents, total = total })
            grandTotal = grandTotal + total
        end
    end
    if #rows == 0 then return end

    table.sort(rows, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    tooltip:AddLine(" ")
    tooltip:AddLine("Account inventory", 0.4, 0.8, 1.0)
    for _, row in ipairs(rows) do
        local parts = {}
        if row.bags > 0 then table.insert(parts, "bags " .. row.bags) end
        if row.bank > 0 then table.insert(parts, "bank " .. row.bank) end
        if row.reagents > 0 then table.insert(parts, "reagents " .. row.reagents) end
        local detail = tostring(row.total)
        if #parts > 1 or row.bank > 0 or row.reagents > 0 then
            detail = detail .. "  (" .. table.concat(parts, ", ") .. ")"
        end
        tooltip:AddDoubleLine(row.name, detail, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if #rows > 1 then
        tooltip:AddDoubleLine("Total", tostring(grandTotal), 1, 0.82, 0, 1, 0.82, 0)
    end
    tooltip:Show()
end

local function MatchesSearch(searchText, itemID, link)
    if not searchText or searchText == "" then return true end
    local name, _, _, _, _, itemType, subType = GetItemInfo(itemID)
    local haystack = string.lower((name or "") .. " " .. (itemType or "") .. " " .. (subType or ""))
    return string.find(haystack, searchText, 1, true) ~= nil
end

function UB:BuildContainerItems(ids, searchText)
    local items = {}
    local searching = searchText ~= ""
    for _, bag in ipairs(ids) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            local itemID = ItemIDFromLink(link)
            if itemID then
                if MatchesSearch(searchText, itemID, link) then
                    table.insert(items, {
                        kind = "container", bag = bag, slot = slot, itemID = itemID,
                        link = link, texture = texture, count = count or 1,
                        locked = locked, quality = quality
                    })
                end
            elseif not searching then
                table.insert(items, { kind = "empty", bag = bag, slot = slot })
            end
        end
    end
    return items
end

function UB:BuildReagentItems(searchText)
    local items = {}
    if not self.reagentAPI or not self.reagentAPI.GetVirtualItems then return items end
    for itemID, amount in pairs(self.reagentAPI:GetVirtualItems() or {}) do
        itemID, amount = tonumber(itemID), tonumber(amount)
        if itemID and amount and amount > 0 and MatchesSearch(searchText, itemID, nil) then
            local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            table.insert(items, {
                kind = "reagent", itemID = itemID, link = link, texture = texture,
                count = amount, name = name or ("Item " .. itemID)
            })
        end
    end
    table.sort(items, function(a, b)
        local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
        if an == bn then return a.itemID < b.itemID end
        return an < bn
    end)
    return items
end


function UB:BuildGuildItems(searchText)
    local items = {}
    if not self.guildBankOpen then return items end

    local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 0
    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    if not tab or tab < 1 or tab > numTabs then return items end

    local _, _, isViewable = GetGuildBankTabInfo(tab)
    if not isViewable then return items end

    local searching = searchText ~= ""
    local maxSlots = MAX_GUILDBANK_SLOTS_PER_TAB or 98
    for slot = 1, maxSlots do
        local texture, count, locked = GetGuildBankItemInfo(tab, slot)
        local link = GetGuildBankItemLink(tab, slot)
        local itemID = ItemIDFromLink(link)
        if itemID then
            if MatchesSearch(searchText, itemID, link) then
                table.insert(items, {
                    kind = "guild", tab = tab, slot = slot, itemID = itemID,
                    link = link, texture = texture, count = count or 1, locked = locked
                })
            end
        elseif not searching then
            table.insert(items, { kind = "guildempty", tab = tab, slot = slot })
        end
    end
    return items
end

local function CursorInside(frame)
    if not frame or not frame:IsShown() then return false end
    local scale = frame:GetEffectiveScale() or 1
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    return left and right and bottom and top and x >= left and x <= right and y >= bottom and y <= top
end

function UB:CancelVirtualDrag()
    if self.dragCapture then self.dragCapture:Hide() end
    if self.dragIcon then self.dragIcon:Hide() end
    self.dragItemID = nil
    self.dragAmount = nil
end

function UB:BeginVirtualDrag(itemID, amount, texture)
    if not self.bankOpen or not self.reagentAPI then return end
    self.dragItemID = itemID
    self.dragAmount = amount
    self.dragIcon.texture:SetTexture(texture)
    self.dragIcon:Show()
    self.dragCapture:Show()
end

function UB:CompleteVirtualDrag()
    local itemID, amount = self.dragItemID, self.dragAmount
    local dropOK = self.bagDisplay and CursorInside(self.bagDisplay.frame)
    self:CancelVirtualDrag()
    if dropOK and itemID and amount and self.reagentAPI then
        self.reagentAPI:RequestWithdraw(itemID, amount)
    end
end

function UB:CreateDragLayer()
    if self.dragIcon then return end
    local dragIcon = CreateFrame("Frame", nil, UIParent)
    self.dragIcon = dragIcon
    dragIcon:SetWidth(34); dragIcon:SetHeight(34)
    dragIcon:SetFrameStrata("TOOLTIP")
    dragIcon.texture = dragIcon:CreateTexture(nil, "OVERLAY")
    dragIcon.texture:SetAllPoints(dragIcon)
    dragIcon:Hide()
    dragIcon:SetScript("OnUpdate", function(frame)
        local scale = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale - 16)
    end)

    local capture = CreateFrame("Frame", nil, UIParent)
    self.dragCapture = capture
    capture:SetAllPoints(UIParent)
    capture:SetFrameStrata("TOOLTIP")
    capture:EnableMouse(true)
    capture:Hide()
    capture:SetScript("OnMouseUp", function() UB:CompleteVirtualDrag() end)
    capture:SetScript("OnHide", function() if UB.dragIcon then UB.dragIcon:Hide() end end)
end

local function SavePosition(display)
    local point, _, relativePoint, x, y = display.frame:GetPoint(1)
    local s = Settings()
    s[display.positionKey] = { point, relativePoint, x, y }
end

function UB:GetCustomButton(display, index)
    display.customButtons = display.customButtons or {}
    local b = display.customButtons[index]
    if b then return b end

    local name = "UnifiedBags335_" .. display.key .. "CustomItem" .. index
    b = CreateFrame("Button", name, display.scrollChild, "ItemButtonTemplate")
    display.customButtons[index] = b
    b:SetWidth(BUTTON_SIZE); b:SetHeight(BUTTON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = _G[name .. "IconTexture"]

    b.empty = b:CreateTexture(nil, "BACKGROUND")
    b.empty:SetAllPoints(b)
    b.empty:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    b.empty:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.SplitStack = function(button, amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return end
        if button.kind == "reagent" then
            if UB.reagentAPI then UB.reagentAPI:RequestWithdraw(button.itemID, amount) end
        elseif button.kind == "guild" and button.tab and button.slot then
            SplitGuildBankItem(button.tab, button.slot, amount)
        elseif button.bag and button.slot then
            SplitContainerItem(button.bag, button.slot, amount)
        end
    end

    local function UpdateItemTooltip(button)
        if not button.itemID then return end

        local x = button:GetRight()
        if x and x >= (GetScreenWidth() / 2) then
            GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        else
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        end

        -- Use Blizzard's real container/guild-bank tooltip setters whenever
        -- possible.  Besides showing the item, these preserve the native
        -- comparison metadata used by the 3.3.5 shopping tooltips.
        if button.kind == "guild" and GameTooltip.SetGuildBankItem then
            GameTooltip:SetGuildBankItem(button.tab, button.slot)
        elseif button.bag == BANK and button.slot and GameTooltip.SetInventoryItem then
            -- The 28 built-in bank slots are not a real bag for tooltip
            -- purposes in Wrath.  Blizzard maps them back to inventory slot
            -- IDs before asking GameTooltip for the item.
            local inventorySlot = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(button.slot, nil)
            if inventorySlot then
                GameTooltip:SetInventoryItem("player", inventorySlot)
            elseif button.link then
                GameTooltip:SetHyperlink(button.link)
            end
        elseif button.bag ~= nil and button.slot and GameTooltip.SetBagItem then
            GameTooltip:SetBagItem(button.bag, button.slot)
        elseif button.link then
            GameTooltip:SetHyperlink(button.link)
        else
            GameTooltip:SetHyperlink("item:" .. button.itemID)
        end

        UB:AddAccountCounts(GameTooltip, button.itemID)

        -- Stock GameTooltip refreshes its owner's UpdateTooltip periodically.
        -- Re-evaluate the compare modifier here so pressing/releasing Shift
        -- while already hovering behaves like Blizzard's container buttons.
        if IsModifiedClick("COMPAREITEMS") and GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(GameTooltip, true)
        elseif GameTooltip.shoppingTooltips then
            for _, tooltip in pairs(GameTooltip.shoppingTooltips) do
                tooltip:Hide()
            end
            GameTooltip.comparing = false
        end
    end

    b.UpdateTooltip = UpdateItemTooltip
    b:SetScript("OnEnter", UpdateItemTooltip)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    b:SetScript("OnClick", function(button, mouseButton)
        -- Empty real bag/bank slots are valid drop targets.  The old early
        -- return meant an item could be picked up with left-click but could
        -- never be placed into an empty destination slot.
        if not button.itemID then
            if button.kind == "empty" and mouseButton == "LeftButton" and button.bag and button.slot then
                PickupContainerItem(button.bag, button.slot)
            elseif button.kind == "guildempty" and mouseButton == "LeftButton" and button.tab and button.slot then
                PickupGuildBankItem(button.tab, button.slot)
            end
            return
        end

        if button.kind == "guild" then
            if HandleModifiedItemClick and button.link and HandleModifiedItemClick(button.link) then
                return
            end
            if IsModifiedClick("SPLITSTACK") then
                if not button.locked and (button.count or 0) > 1 then
                    OpenStackSplitFrame(button.count, button, "BOTTOMLEFT", "TOPLEFT")
                end
                return
            end
            if mouseButton == "RightButton" then
                AutoStoreGuildBankItem(button.tab, button.slot)
            else
                PickupGuildBankItem(button.tab, button.slot)
            end
            return
        end

        if button.kind == "reagent" then
            local stored = UB.reagentAPI and UB.reagentAPI:GetStored(button.itemID) or button.count or 0
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(button.itemID)
            maxStack = tonumber(maxStack) or 1
            local stackAmount = math.max(1, math.min(stored, maxStack))
            if IsModifiedClick("SPLITSTACK") then
                if stored > 1 then
                    OpenStackSplitFrame(stored, button, "BOTTOMLEFT", "TOPLEFT")
                end
            elseif mouseButton == "RightButton" and UB.reagentAPI then
                UB.reagentAPI:RequestWithdraw(button.itemID, stackAmount)
            end
            return
        end

        if HandleModifiedItemClick and button.link and HandleModifiedItemClick(button.link) then
            return
        end
        if IsModifiedClick("SPLITSTACK") then
            if (button.count or 0) > 1 then
                OpenStackSplitFrame(button.count, button, "BOTTOMLEFT", "TOPLEFT")
            end
            return
        end

        if mouseButton == "RightButton" then
            -- In banker/guild-bank/vendor contexts we need the stock
            -- context-sensitive UseContainerItem behavior (move/sell).
            -- Ordinary world use/equip/learn actions are performed by the
            -- button's SecureActionButtonTemplate action instead, so addon
            -- Lua never directly initiates a protected recipe/spell action.
            if UB.bankOpen or UB.guildBankOpen or (MerchantFrame and MerchantFrame:IsShown()) then
                UseContainerItem(button.bag, button.slot)
            end
            return
        else
            PickupContainerItem(button.bag, button.slot)
        end
    end)

    b:SetScript("OnDragStart", function(button)
        if not button.itemID then return end
        if button.kind == "guild" then
            PickupGuildBankItem(button.tab, button.slot)
        elseif button.kind == "reagent" then
            local stored = UB.reagentAPI and UB.reagentAPI:GetStored(button.itemID) or button.count or 0
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(button.itemID)
            maxStack = tonumber(maxStack) or 1
            UB:BeginVirtualDrag(button.itemID, math.max(1, math.min(stored, maxStack)), button.texture)
        else
            PickupContainerItem(button.bag, button.slot)
        end
    end)

    b:SetScript("OnReceiveDrag", function(button)
        if (button.kind == "guild" or button.kind == "guildempty") and button.tab and button.slot then
            PickupGuildBankItem(button.tab, button.slot)
        elseif button.kind ~= "reagent" and button.bag and button.slot then
            PickupContainerItem(button.bag, button.slot)
        end
    end)

    return b
end



function UB:GetContainerParent(display, bag)
    display.containerParents = display.containerParents or {}
    local parent = display.containerParents[bag]
    if parent then return parent end

    parent = CreateFrame("Frame", nil, display.scrollChild)
    parent:SetID(bag)
    parent:SetAllPoints(display.scrollChild)
    display.containerParents[bag] = parent
    return parent
end

function UB:GetContainerButton(display, index, bag)
    display.containerButtons = display.containerButtons or {}
    local b = display.containerButtons[index]
    local parent = self:GetContainerParent(display, bag)

    if not b then
        local name = "UnifiedBags335_" .. display.key .. "ContainerItem" .. index
        b = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate")
        display.containerButtons[index] = b
        b:SetWidth(BUTTON_SIZE)
        b:SetHeight(BUTTON_SIZE)
        -- UnifiedBags' layout code expects every item button to expose the
        -- standard icon texture through b.icon.  ContainerFrameItemButtonTemplate
        -- creates the texture, but does not populate this custom field for us.
        b.icon = _G[name .. "IconTexture"]

        -- Important: do not replace the inherited Blizzard OnClick script.
        -- Bagnon keeps this exact path so the physical mouse click enters
        -- Blizzard's container handler directly without addon Lua initiating
        -- protected use/equip/learn actions.
        b.empty = b:CreateTexture(nil, "BACKGROUND")
        b.empty:SetAllPoints(b)
        b.empty:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        b.empty:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local function UpdateContainerTooltip(button)
            if not button.itemID then return end

            if button:GetRight() and button:GetRight() >= (GetScreenWidth() / 2) then
                GameTooltip:SetOwner(button, "ANCHOR_LEFT")
            else
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            end

            if button.bag == BANK and GameTooltip.SetInventoryItem then
                local inventorySlot = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(button.slot)
                if inventorySlot then
                    GameTooltip:SetInventoryItem("player", inventorySlot)
                elseif button.link then
                    GameTooltip:SetHyperlink(button.link)
                end
            elseif GameTooltip.SetBagItem then
                GameTooltip:SetBagItem(button.bag, button.slot)
            elseif button.link then
                GameTooltip:SetHyperlink(button.link)
            end

            UB:AddAccountCounts(GameTooltip, button.itemID)

            if IsModifiedClick("COMPAREITEMS") and GameTooltip_ShowCompareItem then
                GameTooltip_ShowCompareItem(GameTooltip, true)
            elseif GameTooltip.shoppingTooltips then
                for _, tooltip in pairs(GameTooltip.shoppingTooltips) do
                    tooltip:Hide()
                end
                GameTooltip.comparing = false
            end
        end

        b.UpdateTooltip = UpdateContainerTooltip
        b:SetScript("OnEnter", UpdateContainerTooltip)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if ResetCursor then ResetCursor() end
        end)
    end

    if b:GetParent() ~= parent then
        b:SetParent(parent)
    end
    return b
end


local function SetCheckText(check, text)
    local fs = _G[check:GetName() .. "Text"]
    if fs then fs:SetText(text) end
end

function UB:UpdateMoney()
    if self.bagDisplay and self.bagDisplay.money then
        local money = GetMoney() or 0
        if GetCoinTextureString then
            self.bagDisplay.money:SetText(GetCoinTextureString(money))
        else
            self.bagDisplay.money:SetText(tostring(money))
        end
    end
end

function UB:RefreshBagSlots(display)
    if not display or not display.bagSlotsFrame then return end
    local s = Settings()
    local show = ((display.key == "bags") and s.showBagSlots) or ((display.key == "bank") and s.showBankBagSlots)
    if display.key == "bank" and display.view == "reagents" then show = false end
    if not show then display.bagSlotsFrame:Hide(); return end
    display.bagSlotsFrame:Show()

    local firstBag = display.key == "bags" and 1 or (BAG_COUNT + 1)
    local count = display.key == "bags" and BAG_COUNT or BANK_BAG_COUNT
    local purchased = display.key == "bank" and (GetNumBankSlots() or 0) or count

    for i = 1, count do
        local button = display.bagSlotButtons[i]
        local bag = firstBag + i - 1
        local invSlot = ContainerIDToInventoryID and ContainerIDToInventoryID(bag) or nil
        button.bagID = bag
        button.invSlot = invSlot
        button.purchased = display.key == "bags" or i <= purchased
        local texture = invSlot and GetInventoryItemTexture("player", invSlot) or nil
        button.icon:SetTexture(texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        button.icon:SetVertexColor(button.purchased and 1 or 0.45, button.purchased and 1 or 0.45, button.purchased and 1 or 0.45)
        button:Show()
    end
end

function UB:CreateBagSlotStrip(display)
    local strip = CreateFrame("Frame", nil, display.frame)
    display.bagSlotsFrame = strip
    display.bagSlotButtons = {}
    strip:SetHeight(38)
    strip:SetPoint("BOTTOMRIGHT", -24, 14)

    local count = display.key == "bags" and BAG_COUNT or BANK_BAG_COUNT
    strip:SetWidth(count * 34)
    for i = 1, count do
        local b = CreateFrame("Button", nil, strip)
        display.bagSlotButtons[i] = b
        b:SetWidth(30); b:SetHeight(30)
        b:SetPoint("LEFT", (i - 1) * 34, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints(b)
        b.border = b:CreateTexture(nil, "OVERLAY")
        b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.border:SetPoint("TOPLEFT", -1, 1); b.border:SetPoint("BOTTOMRIGHT", 1, -1)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(button, mouseButton)
            if display.key == "bank" and not button.purchased then
                UB:ShowBankBagPurchaseDialog()
                return
            end
            if mouseButton ~= "LeftButton" or not button.invSlot then return end
            if CursorHasItem and CursorHasItem() then
                if PutItemInBag then PutItemInBag(button.invSlot) end
            elseif PickupBagFromSlot then
                PickupBagFromSlot(button.invSlot)
            end
        end)
        b:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if not button.purchased then
                GameTooltip:SetText(BANK_BAG_PURCHASE or "Bank bag slot not purchased", 1, 1, 1)
                GameTooltip:AddLine("Left- or right-click to purchase the next bank bag slot.", 0.8, 0.8, 0.8)
                if GetBankSlotCost and SetTooltipMoney then
                    SetTooltipMoney(GameTooltip, GetBankSlotCost(GetNumBankSlots() or 0))
                end
            elseif button.invSlot and GetInventoryItemLink("player", button.invSlot) then
                GameTooltip:SetInventoryItem("player", button.invSlot)
            else
                GameTooltip:SetText(display.key == "bags" and "Empty bag slot" or "Empty bank bag slot")
                GameTooltip:AddLine("Left-click with a bag on the cursor to equip it.", 0.8, 0.8, 0.8)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

function UB:ShowBankBagPurchaseDialog()
    if not self.bankOpen then return end
    if not PurchaseSlot or not GetBankSlotCost then return end
    if (GetNumBankSlots() or 0) >= BANK_BAG_COUNT then return end

    local dialogName = "CONFIRM_BUY_BANK_SLOT_UNIFIEDBAGS335"
    if not StaticPopupDialogs[dialogName] then
        StaticPopupDialogs[dialogName] = {
            text = CONFIRM_BUY_BANK_SLOT or "Purchase another bank bag slot?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                PurchaseSlot()
            end,
            OnShow = function(frame)
                if frame and frame.GetName and MoneyFrame_Update then
                    MoneyFrame_Update(frame:GetName() .. "MoneyFrame", GetBankSlotCost(GetNumBankSlots() or 0))
                end
            end,
            hasMoneyFrame = 1,
            timeout = 0,
            hideOnEscape = 1,
        }
    end
    StaticPopup_Show(dialogName)
end

function UB:UpdateAutoDepositControl()
    local check = self.optionsAutoDeposit
    if not check then return end

    local apiAvailable = self.reagentAPI and self.reagentAPI.IsServerAvailable and self.reagentAPI:IsServerAvailable()
    if self.reagentAPI and self.reagentAPI.GetAutoDepositEnabled then
        check:SetChecked(self.reagentAPI:GetAutoDepositEnabled() and 1 or nil)
    else
        check:SetChecked(nil)
    end

    if apiAvailable and self.bankOpen then
        check:Enable()
        if self.optionsAutoDepositNote then
            self.optionsAutoDepositNote:SetText("Automatically deposits eligible reagents when you use a banker.")
        end
    else
        check:Disable()
        if self.optionsAutoDepositNote then
            self.optionsAutoDepositNote:SetText("Visit a banker to change this setting.")
        end
    end
end

local function CreateSearch(display, topOffset)
    local search = CreateFrame("EditBox", nil, display.frame, "InputBoxTemplate")
    display.search = search
    search:SetAutoFocus(false)
    search:SetWidth(120)
    search:SetHeight(20)
    search:SetPoint("TOPRIGHT", -36, topOffset)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(box)
        UB.searchText[display.key] = string.lower(box:GetText() or "")
        UB:RefreshDisplay(display)
    end)
    search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)

    local label = display.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("RIGHT", search, "LEFT", -5, 0)
    label:SetText("Search")
end

function UB:CreateDisplay(key, title, positionKey, hasTabs)
    local display = { key = key, titleBase = title, positionKey = positionKey, hasTabs = hasTabs, buttons = {}, view = key }
    self.displays[key] = display

    local frameName = key == "bags" and "UnifiedBags335BagsFrame" or "UnifiedBags335BankFrame"
    local f = CreateFrame("Frame", frameName, UIParent)
    display.frame = f
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) if not UB.dragItemID then frame:StartMoving() end end)
    f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); SavePosition(display) end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 }
    })
    f:Hide()
    table.insert(UISpecialFrames, frameName)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    display.title = titleText
    titleText:SetPoint("TOPLEFT", 20, -17)
    titleText:SetText(CharacterKey() .. " - " .. title)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        if display.key == "bank" and UB.bankOpen and CloseBankFrame then
            CloseBankFrame()
        else
            display.frame:Hide()
        end
    end)

    local options = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    options:SetWidth(22); options:SetHeight(20)
    options:SetPoint("TOPRIGHT", -34, -8)
    options:SetText("+")
    options:SetScript("OnClick", function() UB:OpenOptions() end)

    local gridTop
    if hasTabs then
        local function MakeTab(text, view, x, width)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetWidth(width); b:SetHeight(22)
            b:SetPoint("TOPLEFT", x, -43)
            b:SetText(text)
            b:SetScript("OnClick", function() UB:SetBankView(view) end)
            return b
        end
        display.bankTab = MakeTab("Bank", "bank", 18, 105)
        display.reagentTab = MakeTab("Reagent Storage", "reagents", 128, 145)
        CreateSearch(display, -44)
        gridTop = -72
    else
        CreateSearch(display, -18)
        gridTop = -50
    end
    display.gridTop = gridTop

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    display.scroll = scroll
    scroll:SetPoint("TOPLEFT", GRID_LEFT, gridTop)
    scroll:SetPoint("BOTTOMRIGHT", -35, 18)

    local child = CreateFrame("Frame", nil, scroll)
    display.scrollChild = child
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local current = sf:GetVerticalScroll() or 0
        local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
        sf:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 42)))
    end)


    if key == "bags" then
        local money = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        display.money = money
        money:SetPoint("BOTTOMLEFT", 20, 21)
        money:SetJustifyH("LEFT")
    end

    self:CreateBagSlotStrip(display)

    local pos = Settings()[positionKey]
    if pos then
        f:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3] or 0, pos[4] or 0)
    elseif key == "bags" then
        f:SetPoint("CENTER", UIParent, "CENTER", -285, 20)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 285, 20)
    end

    return display
end

function UB:GetColumns(display)
    local s = Settings()
    if display.key == "bags" then return math.floor(s.bagColumns or DEFAULTS.bagColumns) end
    if display.key == "guild" then return math.floor(s.guildColumns or DEFAULTS.guildColumns) end
    return math.floor(s.bankColumns or DEFAULTS.bankColumns)
end

function UB:ApplyDisplayGeometry(display)
    local s = Settings()
    local columns = self:GetColumns(display)
    local rows = math.floor(s.visibleRows or DEFAULTS.visibleRows)
    local contentWidth = columns * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP
    local topSpace = display.hasTabs and 82 or 60
    local showSlots = ((display.key == "bags") and s.showBagSlots) or ((display.key == "bank") and s.showBankBagSlots)
    if display.key == "bank" and display.view == "reagents" then showSlots = false end
    local bottomSpace = showSlots and 58 or 22
    local width = contentWidth + 55
    if display.hasTabs then width = math.max(width, 575) end
    local height = topSpace + rows * (BUTTON_SIZE + BUTTON_GAP) + bottomSpace
    display.frame:SetWidth(width)
    display.frame:SetHeight(height)
    display.frame:SetScale(s.scale or 1)
    display.scroll:SetPoint("BOTTOMRIGHT", -35, showSlots and 54 or 18)
    display.scrollChild:SetWidth(contentWidth)
    self:RefreshBagSlots(display)
    self:UpdateMoney()
end

function UB:ApplyGeometry()
    if self.bagDisplay then self:ApplyDisplayGeometry(self.bagDisplay) end
    if self.bankDisplay then self:ApplyDisplayGeometry(self.bankDisplay) end
    if self.guildDisplay then self:ApplyGuildGeometry() end
    self:QueueRefresh()
end

function UB:LayoutItems(display, items)
    local columns = self:GetColumns(display)
    local shown = 0
    for i, data in ipairs(items) do
        local isContainer = data.kind == "container" or data.kind == "empty"
        local b
        if isContainer then
            b = self:GetContainerButton(display, i, data.bag)
            if display.customButtons and display.customButtons[i] then
                display.customButtons[i]:Hide()
            end
        else
            b = self:GetCustomButton(display, i)
            if display.containerButtons and display.containerButtons[i] then
                display.containerButtons[i]:Hide()
            end
        end
        shown = i
        b:ClearAllPoints()
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        b:SetPoint("TOPLEFT", display.scrollChild, "TOPLEFT", col * (BUTTON_SIZE + BUTTON_GAP), -row * (BUTTON_SIZE + BUTTON_GAP))

        b.kind = data.kind
        b.bag = data.bag
        b.tab = data.tab
        b.slot = data.slot
        b.itemID = data.itemID
        b.link = data.link
        b.texture = data.texture
        b.count = data.count or 0

        if isContainer then
            local parent = self:GetContainerParent(display, data.bag)
            if b:GetParent() ~= parent then b:SetParent(parent) end
            parent:SetID(data.bag)
            b:SetID(data.slot)
        end

        if data.itemID then
            b.empty:Hide()
            b.icon:SetTexture(data.texture)
            b.icon:Show()
            SetItemButtonCount(b, data.count or 1)
            if data.locked then SetItemButtonDesaturated(b, 1, 0.5, 0.5, 0.5) else SetItemButtonDesaturated(b, nil) end
        else
            b.icon:SetTexture(nil)
            b.icon:Hide()
            SetItemButtonCount(b, 0)
            b.empty:Show()
            SetItemButtonDesaturated(b, nil)
        end
        b:Show()
    end

    if display.containerButtons then
        for i = shown + 1, #display.containerButtons do
            display.containerButtons[i]:Hide()
        end
    end
    if display.customButtons then
        for i = shown + 1, #display.customButtons do
            display.customButtons[i]:Hide()
        end
    end

    local rows = math.max(1, math.ceil(math.max(1, #items) / columns))
    display.scrollChild:SetHeight(rows * (BUTTON_SIZE + BUTTON_GAP))
    local maxScroll = math.max(0, display.scrollChild:GetHeight() - display.scroll:GetHeight())
    if display.scroll:GetVerticalScroll() > maxScroll then display.scroll:SetVerticalScroll(maxScroll) end
end

function UB:RefreshDisplay(display)
    if not display or not display.frame:IsShown() then return end
    local items
    if display.key == "bags" then
        display.title:SetText(CharacterKey() .. " - Bags")
        items = self:BuildContainerItems(self:GetBagIDs(), self.searchText.bags or "")
    else
        if display.view == "reagents" then
            display.title:SetText(CharacterKey() .. " - Reagent Storage")
            items = self:BuildReagentItems(self.searchText.bank or "")
        else
            display.title:SetText(CharacterKey() .. " - Bank")
            items = self:BuildContainerItems(self:GetBankIDs(), self.searchText.bank or "")
        end
        if display.reagentTab then
            if self.bankOpen and self.reagentAPI and self.reagentAPI.IsServerAvailable and self.reagentAPI:IsServerAvailable() then
                display.reagentTab:Enable()
            else
                display.reagentTab:Disable()
            end
        end
    end
    self:RefreshBagSlots(display)
    if display.key == "bank" then self:UpdateAutoDepositControl() end
    self:LayoutItems(display, items)
end

function UB:Refresh()
    self:RefreshDisplay(self.bagDisplay)
    self:RefreshDisplay(self.bankDisplay)
    self:RefreshGuildDisplay()
end

function UB:QueueRefresh()
    self.refreshPending = true
end

function UB:SetBankView(view)
    if not self.bankOpen or not self.bankDisplay then return end
    if view == "reagents" and not self.reagentAPI then return end
    self.bankDisplay.view = view
    self.bankDisplay.scroll:SetVerticalScroll(0)
    self:ApplyDisplayGeometry(self.bankDisplay)
    self:RefreshDisplay(self.bankDisplay)
end

function UB:ShowBags()
    self.bagDisplay.frame:Show()
    self:RefreshDisplay(self.bagDisplay)
end

function UB:ToggleBags()
    if self.bagDisplay.frame:IsShown() then self.bagDisplay.frame:Hide() else self:ShowBags() end
end

function UB:ShowBank()
    if not self.bankOpen then return end
    self.bankDisplay.frame:Show()
    self:RefreshDisplay(self.bankDisplay)
end


function UB:UpdateGuildMoney()
    local display = self.guildDisplay
    if not display then return end
    local money = GetGuildBankMoney and GetGuildBankMoney() or 0
    if display.money then
        display.money:SetText(GetCoinTextureString and GetCoinTextureString(money) or tostring(money))
    end
    if display.withdrawButton then
        if CanWithdrawGuildBankMoney and CanWithdrawGuildBankMoney() then
            display.withdrawButton:Enable()
        else
            display.withdrawButton:Disable()
        end
    end
end

function UB:RefreshGuildTabs()
    local display = self.guildDisplay
    if not display then return end

    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 0
    local maxTabs = MAX_GUILDBANK_TABS or 6
    local maxBuyTabs = MAX_BUY_GUILDBANK_TABS or maxTabs
    local buyIndex = nil
    if IsGuildLeader and IsGuildLeader() and numTabs < maxBuyTabs and GetGuildBankTabCost and GetGuildBankTabCost() then
        buyIndex = numTabs + 1
    end

    for i = 1, maxTabs do
        local b = display.guildTabs[i]
        local name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(i)

        if i <= numTabs then
            b.isBuy = false
            b.name = (name and name ~= "") and name or ("Tab " .. i)
            b.isViewable = isViewable
            b.icon:SetTexture(icon or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            b:SetChecked(i == current)
            if isViewable then
                b:Enable()
                b.icon:SetVertexColor(1, 1, 1)
            else
                b:Disable()
                b.icon:SetVertexColor(0.45, 0.45, 0.45)
            end
            if i == current and remainingWithdrawals and remainingWithdrawals > 0 then
                SetItemButtonCount(b, remainingWithdrawals)
            else
                SetItemButtonCount(b, 0)
            end
            b:Show()
        elseif i == buyIndex then
            b.isBuy = true
            b.name = BUY_GUILDBANK_TAB or "Buy Guild Bank Tab"
            b.isViewable = true
            b.icon:SetTexture("Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab")
            b.icon:SetVertexColor(1, 1, 1)
            b:SetChecked(i == current)
            b:Enable()
            SetItemButtonCount(b, 0)
            b:Show()
        else
            b:Hide()
        end
    end
end


function UB:OpenGuildTabEdit(tab)
    if not self.guildBankOpen then return end
    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    if not tab or tab < 1 or tab > numTabs then return end

    -- The stock 3.3.5 Guild Bank UI owns the icon/name picker and commits
    -- through SetGuildBankTabInfo(). Load it only for this management dialog.
    if not GuildBankFrame then
        if UIParentLoadAddOn then
            UIParentLoadAddOn("Blizzard_GuildBankUI")
        elseif LoadAddOn then
            LoadAddOn("Blizzard_GuildBankUI")
        end
    end

    local name, icon, isViewable = GetGuildBankTabInfo(tab)
    if not isViewable then return end

    -- Different 3.3.5 UI distributions expose the dialog entry point under
    -- slightly different global helpers. Prefer the stock helper when present.
    if GuildBankPopupFrame and GuildBankPopupFrame.Show then
        GuildBankPopupFrame.tab = tab
        GuildBankPopupFrame:Show()
        if GuildBankPopupFrame_Update then
            GuildBankPopupFrame_Update(tab)
        end
        return
    end

    if GuildBankFrameTab_OnClick and GuildBankFrame then
        -- Fall back to the stock tab handler with modified-click semantics.
        local button = _G["GuildBankTab" .. tab]
        if button then
            GuildBankFrameTab_OnClick(button, "RightButton")
            return
        end
    end

    -- Last-resort lightweight native-style editor if this client build does
    -- not expose the stock popup globals after loading Blizzard_GuildBankUI.
    if not self.guildTabEditFrame then
        local f = CreateFrame("Frame", "UnifiedBags335GuildTabEditFrame", UIParent)
        self.guildTabEditFrame = f
        f:SetWidth(360); f:SetHeight(300)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 10, right = 10, top = 10, bottom = 10 }
        })
        f:Hide()

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -18)
        title:SetText("Guild Bank Tab")

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", 22, -52)
        label:SetText("Tab name:")

        local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        f.nameEdit = edit
        edit:SetAutoFocus(false)
        edit:SetWidth(245); edit:SetHeight(24)
        edit:SetPoint("LEFT", label, "RIGHT", 10, 0)

        local iconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        iconLabel:SetPoint("TOPLEFT", 22, -90)
        iconLabel:SetText("Icon:")

        f.iconButtons = {}
        local iconChoices = {
            "INV_Misc_QuestionMark",
            "INV_Misc_Bag_10",
            "INV_Misc_Coin_01",
            "INV_Ingot_02",
            "INV_Fabric_Silk_02",
            "INV_Misc_Herb_19",
            "INV_Misc_Gem_01",
            "INV_Potion_54",
            "INV_Weapon_ShortBlade_05",
            "INV_Chest_Plate03",
            "INV_Helmet_08",
            "INV_Misc_Food_15",
        }

        for i, tex in ipairs(iconChoices) do
            local b = CreateFrame("CheckButton", nil, f, "ItemButtonTemplate")
            f.iconButtons[i] = b
            b:SetWidth(36); b:SetHeight(36)
            local col = (i - 1) % 6
            local row = math.floor((i - 1) / 6)
            b:SetPoint("TOPLEFT", 55 + col * 46, -110 - row * 46)
            local iconTex = _G[b:GetName() and (b:GetName() .. "IconTexture") or ""]
            if not iconTex then
                iconTex = b:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
            end
            b.iconTexture = iconTex
            iconTex:SetTexture("Interface\\Icons\\" .. tex)
            b.iconPath = "Interface\\Icons\\" .. tex
            b:SetScript("OnClick", function(btn)
                f.selectedIcon = btn.iconPath
                for _, other in ipairs(f.iconButtons) do other:SetChecked(other == btn) end
            end)
        end

        local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ok:SetWidth(90); ok:SetHeight(24)
        ok:SetPoint("BOTTOMRIGHT", -108, 18)
        ok:SetText(OKAY)
        ok:SetScript("OnClick", function()
            local tabIndex = f.tab
            if tabIndex and SetGuildBankTabInfo then
                local newName = f.nameEdit:GetText() or ""
                local iconPath = f.selectedIcon
                if newName ~= "" and iconPath then
                    SetGuildBankTabInfo(tabIndex, newName, iconPath)
                end
            end
            f:Hide()
        end)

        local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancel:SetWidth(90); cancel:SetHeight(24)
        cancel:SetPoint("BOTTOMRIGHT", -14, 18)
        cancel:SetText(CANCEL)
        cancel:SetScript("OnClick", function() f:Hide() end)
    end

    local f = self.guildTabEditFrame
    f.tab = tab
    f.nameEdit:SetText(name or ("Tab " .. tab))
    f.nameEdit:HighlightText(0, 0)
    f.selectedIcon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    for _, b in ipairs(f.iconButtons) do
        b:SetChecked(b.iconPath == f.selectedIcon)
    end
    f:Show()
end

function UB:SelectGuildTab(tab)
    if not self.guildBankOpen then return end
    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local maxBuyTabs = MAX_BUY_GUILDBANK_TABS or (MAX_GUILDBANK_TABS or 6)

    if tab == numTabs + 1 and IsGuildLeader and IsGuildLeader() and numTabs < maxBuyTabs then
        if GetGuildBankTabCost and GetGuildBankTabCost() then
            SetCurrentGuildBankTab(tab)
            self:RefreshGuildTabs()
            StaticPopup_Show("CONFIRM_BUY_GUILDBANK_TAB")
        end
        return
    end

    if tab < 1 or tab > numTabs then return end
    local _, _, isViewable = GetGuildBankTabInfo(tab)
    if not isViewable then return end
    SetCurrentGuildBankTab(tab)
    QueryGuildBankTab(tab)
    self.guildDisplay.scroll:SetVerticalScroll(0)
    self:QueueRefresh()
end

function UB:CreateGuildDisplay()
    if self.guildDisplay then return end

    local display = { key = "guild", positionKey = "guildPoint", buttons = {}, guildTabs = {} }
    self.guildDisplay = display
    self.displays.guild = display

    local f = CreateFrame("Frame", "UnifiedBags335GuildBankFrame", UIParent)
    display.frame = f
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
    f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing(); SavePosition(display) end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 }
    })
    f:Hide()
    table.insert(UISpecialFrames, "UnifiedBags335GuildBankFrame")

    display.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    display.title:SetPoint("TOPLEFT", 20, -17)
    display.title:SetText("Guild Bank")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        if UB.guildBankOpen and CloseGuildBankFrame then CloseGuildBankFrame() else f:Hide() end
    end)

    local options = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    options:SetWidth(22); options:SetHeight(20)
    options:SetPoint("TOPRIGHT", -34, -8)
    options:SetText("+")
    options:SetScript("OnClick", function() UB:OpenOptions() end)

    CreateSearch(display, -18)

    local tabStrip = CreateFrame("Frame", nil, f)
    display.tabStrip = tabStrip
    tabStrip:SetPoint("TOPLEFT", 18, -48)
    tabStrip:SetWidth((MAX_GUILDBANK_TABS or 6) * 39)
    tabStrip:SetHeight(38)

    for i = 1, (MAX_GUILDBANK_TABS or 6) do
        local name = "UnifiedBags335GuildTab" .. i
        local b = CreateFrame("CheckButton", name, tabStrip, "ItemButtonTemplate")
        display.guildTabs[i] = b
        b:SetID(i)
        b:SetWidth(34); b:SetHeight(34)
        b:SetPoint("LEFT", (i - 1) * 39, 0)
        b.icon = _G[name .. "IconTexture"]
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(button, mouseButton)
            local tab = button:GetID()
            if mouseButton == "RightButton" and not button.isBuy then
                UB:OpenGuildTabEdit(tab)
            else
                UB:SelectGuildTab(tab)
            end
        end)
        b:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            if button.isBuy then
                GameTooltip:SetText(BUY_GUILDBANK_TAB or "Buy Guild Bank Tab", 1, 1, 1)
                if GetGuildBankTabCost and SetTooltipMoney and GetGuildBankTabCost() then
                    SetTooltipMoney(GameTooltip, GetGuildBankTabCost())
                end
            else
                local tab = button:GetID()
                local nameText, _, isViewable, canDeposit, numWithdrawals, remainingWithdrawals = GetGuildBankTabInfo(tab)
                GameTooltip:SetText((nameText and nameText ~= "") and nameText or ("Tab " .. tab), 1, 1, 1)
                if not isViewable then
                    GameTooltip:AddLine(GUILDBANK_TAB_LOCKED or "Locked", 1, 0.2, 0.2)
                else
                    GameTooltip:AddLine(canDeposit and "Deposit: Allowed" or "Deposit: Not allowed",
                        canDeposit and 0.2 or 1, canDeposit and 1 or 0.2, 0.2)
                    if remainingWithdrawals and remainingWithdrawals >= 0 then
                        GameTooltip:AddLine("Withdrawals remaining: " .. remainingWithdrawals, 0.8, 0.8, 0.8)
                    end
                    GameTooltip:AddLine("Right-click to rename/change icon", 0.6, 0.8, 1.0)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    display.scroll = scroll
    scroll:SetPoint("TOPLEFT", GRID_LEFT, -92)
    scroll:SetPoint("BOTTOMRIGHT", -35, 55)

    local child = CreateFrame("Frame", nil, scroll)
    display.scrollChild = child
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local current = sf:GetVerticalScroll() or 0
        local maxScroll = math.max(0, child:GetHeight() - sf:GetHeight())
        sf:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 42)))
    end)

    display.money = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    display.money:SetPoint("BOTTOMLEFT", 20, 22)

    display.depositButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    display.depositButton:SetWidth(82); display.depositButton:SetHeight(22)
    display.depositButton:SetPoint("BOTTOMRIGHT", -115, 16)
    display.depositButton:SetText("Deposit")
    display.depositButton:SetScript("OnClick", function()
        StaticPopup_Hide("GUILDBANK_WITHDRAW")
        StaticPopup_Show("GUILDBANK_DEPOSIT")
    end)

    display.withdrawButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    display.withdrawButton:SetWidth(82); display.withdrawButton:SetHeight(22)
    display.withdrawButton:SetPoint("BOTTOMRIGHT", -28, 16)
    display.withdrawButton:SetText("Withdraw")
    display.withdrawButton:SetScript("OnClick", function()
        if CanWithdrawGuildBankMoney and CanWithdrawGuildBankMoney() then
            StaticPopup_Hide("GUILDBANK_DEPOSIT")
            StaticPopup_Show("GUILDBANK_WITHDRAW")
        end
    end)

    local pos = Settings().guildPoint
    if pos then
        f:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3] or 0, pos[4] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

function UB:ApplyGuildGeometry()
    local display = self.guildDisplay
    if not display then return end
    local s = Settings()
    local columns = math.floor(s.guildColumns or DEFAULTS.guildColumns)
    local rows = math.floor(s.visibleRows or DEFAULTS.visibleRows)
    local contentWidth = columns * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP
    local width = math.max(contentWidth + 55, 575)
    local height = 122 + rows * (BUTTON_SIZE + BUTTON_GAP) + 55
    display.frame:SetWidth(width)
    display.frame:SetHeight(height)
    display.frame:SetScale(s.scale or 1)
    display.scrollChild:SetWidth(contentWidth)
end

function UB:RefreshGuildDisplay()
    local display = self.guildDisplay
    if not display or not display.frame:IsShown() then return end
    local guildName = GetGuildInfo and GetGuildInfo("player") or nil
    local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 0
    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local tabName = nil
    if tab >= 1 and tab <= numTabs then tabName = GetGuildBankTabInfo(tab) end
    display.title:SetText((guildName and guildName ~= "") and
        (guildName .. " - " .. ((tabName and tabName ~= "") and tabName or "Guild Bank")) or "Guild Bank")
    self:RefreshGuildTabs()
    self:UpdateGuildMoney()
    self:LayoutItems(display, self:BuildGuildItems(self.searchText.guild or ""))
end

function UB:ShowGuildBank()
    if not self.guildBankOpen then return end
    self:CreateGuildDisplay()
    self:ApplyGuildGeometry()
    self.guildDisplay.frame:Show()

    local numTabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 0
    if numTabs > 0 and (not current or current < 1 or current > numTabs + 1) then
        for i = 1, numTabs do
            local _, _, viewable = GetGuildBankTabInfo(i)
            if viewable then
                SetCurrentGuildBankTab(i)
                QueryGuildBankTab(i)
                break
            end
        end
    elseif current and current >= 1 and current <= numTabs then
        QueryGuildBankTab(current)
    end
    self:RefreshGuildDisplay()
end

function UB:CreateOptions()
    if self.optionsPanel then return end
    local panel = CreateFrame("Frame", "UnifiedBags335OptionsPanel", InterfaceOptionsFramePanelContainer)
    self.optionsPanel = panel
    panel.name = "UnifiedBags335"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("UnifiedBags335")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("Layout settings are applied immediately.")

    local function MakeSlider(name, label, minv, maxv, step, y, setting)
        local slider = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", 24, y)
        slider:SetWidth(260)
        slider:SetMinMaxValues(minv, maxv)
        slider:SetValueStep(step)
        slider:SetValue(Settings()[setting])
        _G[name .. "Low"]:SetText(tostring(minv))
        _G[name .. "High"]:SetText(tostring(maxv))
        _G[name .. "Text"]:SetText(label .. ": " .. tostring(Settings()[setting]))
        slider:SetScript("OnValueChanged", function(self, value)
            if step >= 1 then value = math.floor(value + 0.5) else value = math.floor(value * 100 + 0.5) / 100 end
            Settings()[setting] = value
            _G[name .. "Text"]:SetText(label .. ": " .. tostring(value))
            UB:ApplyGeometry()
        end)
        return slider
    end

    MakeSlider("UnifiedBags335BagColumnsSlider", "Bag columns", 6, 16, 1, -82, "bagColumns")
    MakeSlider("UnifiedBags335BankColumnsSlider", "Bank/Reagent columns", 6, 16, 1, -142, "bankColumns")
    MakeSlider("UnifiedBags335GuildColumnsSlider", "Guild Bank columns", 7, 18, 1, -202, "guildColumns")
    MakeSlider("UnifiedBags335RowsSlider", "Visible rows", 4, 14, 1, -262, "visibleRows")
    MakeSlider("UnifiedBags335ScaleSlider", "Window scale", 0.70, 1.30, 0.05, -322, "scale")


    local function MakeCheck(name, label, y, setting)
        local check = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 24, y)
        check:SetChecked(Settings()[setting] and 1 or nil)
        SetCheckText(check, label)
        check:SetScript("OnClick", function(self)
            Settings()[setting] = self:GetChecked() and true or false
            UB:ApplyGeometry()
        end)
        return check
    end

    MakeCheck("UnifiedBags335ShowBagSlotsCheck", "Show equipped bag slots on Bags", -375, "showBagSlots")
    MakeCheck("UnifiedBags335ShowBankBagSlotsCheck", "Show bank bag slots on Bank", -410, "showBankBagSlots")

    local auto = CreateFrame("CheckButton", "UnifiedBags335OptionsAutoDepositCheck", panel, "UICheckButtonTemplate")
    self.optionsAutoDeposit = auto
    auto:SetPoint("TOPLEFT", 24, -445)
    SetCheckText(auto, "Auto-deposit reagents")
    auto:SetScript("OnClick", function(check)
        if UB.reagentAPI and UB.reagentAPI.SetAutoDepositEnabled then
            UB.reagentAPI:SetAutoDepositEnabled(check:GetChecked() and true or false)
        end
    end)

    local autoNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.optionsAutoDepositNote = autoNote
    autoNote:SetPoint("TOPLEFT", 48, -474)
    autoNote:SetWidth(360)
    autoNote:SetJustifyH("LEFT")
    autoNote:SetText("Visit a banker to change this setting.")

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetWidth(120); reset:SetHeight(24)
    reset:SetPoint("TOPLEFT", 24, -515)
    reset:SetText("Reset Layout")
    reset:SetScript("OnClick", function()
        local s = Settings()
        for k, v in pairs(DEFAULTS) do s[k] = v end
        s.bagPoint = nil
        s.bankPoint = nil
        s.guildPoint = nil
        UB.bagDisplay.frame:ClearAllPoints()
        UB.bagDisplay.frame:SetPoint("CENTER", UIParent, "CENTER", -285, 20)
        UB.bankDisplay.frame:ClearAllPoints()
        UB.bankDisplay.frame:SetPoint("CENTER", UIParent, "CENTER", 285, 20)
        if UB.guildDisplay then
            UB.guildDisplay.frame:ClearAllPoints()
            UB.guildDisplay.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        end
        UB:ApplyGeometry()
        InterfaceOptionsFrame_OpenToCategory(panel)
    end)

    InterfaceOptions_AddCategory(panel)
    self:UpdateAutoDepositControl()
end

function UB:OpenOptions()
    self:CreateOptions()
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
end

function UB:CreateFrames()
    if self.bagDisplay then return end
    EnsureDB()
    self:CreateDragLayer()
    self.bagDisplay = self:CreateDisplay("bags", "Bags", "bagPoint", false)
    self.bankDisplay = self:CreateDisplay("bank", "Bank", "bankPoint", true)
    self.bankDisplay.view = "bank"
    self:CreateGuildDisplay()
    self:ApplyGeometry()
    self:CreateOptions()
end

function UB:AttachReagentAPI()
    local api = _G.BankReagentsUI
    if not api or not api.RegisterStorageCallback then return end
    if self.reagentAPI == api then return end
    self.reagentAPI = api
    api:RegisterStorageCallback(self, function(owner)
        owner:CacheReagents()
        owner:QueueRefresh()
    end)
    if api.RegisterAutoDepositCallback then
        api:RegisterAutoDepositCallback(self, function(owner)
            owner:UpdateAutoDepositControl()
            owner:CacheReagents()
            owner:QueueRefresh()
        end)
    end
    self:CacheReagents()
end

function UB:InstallHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    ToggleBackpack = function() UB:ToggleBags() end
    OpenBackpack = function() UB:ShowBags() end
    CloseBackpack = function() if not UB.bankOpen then UB.bagDisplay.frame:Hide() end end
    ToggleBag = function() UB:ToggleBags() end
    OpenAllBags = function() UB:ShowBags() end
    CloseAllBags = function() if not UB.bankOpen then UB.bagDisplay.frame:Hide() end end

    if BankFrame then
        BankFrame:UnregisterEvent("BANKFRAME_OPENED")
        BankFrame:UnregisterEvent("BANKFRAME_CLOSED")
        BankFrame:Hide()
    end

    if GuildBankFrame_LoadUI then
        GuildBankFrame_LoadUI = function() end
    end
end

SLASH_UNIFIEDBAGS3351 = "/ubags"
SlashCmdList.UNIFIEDBAGS335 = function(msg)
    msg = string.lower(msg or "")
    if msg == "options" or msg == "config" or msg == "" then
        UB:OpenOptions()
    elseif msg == "bags" then
        UB:ToggleBags()
    end
end

UB:RegisterEvent("PLAYER_LOGIN")
UB:RegisterEvent("PLAYER_LOGOUT")
UB:RegisterEvent("BAG_UPDATE")
UB:RegisterEvent("PLAYER_MONEY")
UB:RegisterEvent("UNIT_INVENTORY_CHANGED")
UB:RegisterEvent("BANKFRAME_OPENED")
UB:RegisterEvent("BANKFRAME_CLOSED")
UB:RegisterEvent("GUILDBANKFRAME_OPENED")
UB:RegisterEvent("GUILDBANKFRAME_CLOSED")
UB:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
UB:RegisterEvent("GUILDBANK_ITEM_LOCK_CHANGED")
UB:RegisterEvent("GUILDBANK_UPDATE_TABS")
UB:RegisterEvent("GUILDBANK_UPDATE_MONEY")
UB:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY")
UB:RegisterEvent("GUILD_ROSTER_UPDATE")
UB:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
UB:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
UB:RegisterEvent("GET_ITEM_INFO_RECEIVED")
UB:RegisterEvent("ADDON_LOADED")
UB:RegisterEvent("MERCHANT_SHOW")
UB:RegisterEvent("MERCHANT_CLOSED")

UB:SetScript("OnUpdate", function(self)
    if self.bankShowPending then
        self.bankShowPending = false
        self:ShowBags()
        self:ShowBank()
        self.refreshPending = false
        return
    end
    if self.refreshPending then
        self.refreshPending = false
        self:Refresh()
    end
end)

UB:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        self:CreateFrames()
        self:AttachReagentAPI()
        self:InstallHooks()
        self:CacheBags()
        self:CacheReagents()
        return
    end

    if event == "ADDON_LOADED" then
        local name = ...
        if name == "BankReagentsUI" then self:AttachReagentAPI() end
        return
    end

    if event == "PLAYER_LOGOUT" then
        self:CacheBags()
        self:CacheBank()
        self:CacheReagents()
        return
    end

    if event == "BANKFRAME_OPENED" then
        self.bankOpen = true
        self:AttachReagentAPI()
        self:CacheBags()
        self:CacheBank()
        if self.reagentAPI and self.reagentAPI.RequestSync then self.reagentAPI:RequestSync() end
        if self.reagentAPI and self.reagentAPI.RequestAutoDepositState then self.reagentAPI:RequestAutoDepositState() end
        self.bankShowPending = true
        return
    end

    if event == "BANKFRAME_CLOSED" then
        self:CacheBank()
        self.bankOpen = false
        self.bankDisplay.frame:Hide()
        self.bankDisplay.view = "bank"
        return
    end

    if event == "GUILDBANKFRAME_OPENED" then
        self.guildBankOpen = true
        self:ShowBags()
        self:ShowGuildBank()
        return
    end

    if event == "GUILDBANKFRAME_CLOSED" then
        self.guildBankOpen = false
        if self.guildDisplay then self.guildDisplay.frame:Hide() end
        StaticPopup_Hide("GUILDBANK_WITHDRAW")
        StaticPopup_Hide("GUILDBANK_DEPOSIT")
        StaticPopup_Hide("CONFIRM_BUY_GUILDBANK_TAB")
        return
    end

    if event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_ITEM_LOCK_CHANGED"
        or event == "GUILDBANK_UPDATE_TABS" or event == "GUILD_ROSTER_UPDATE" then
        if self.guildBankOpen then self:QueueRefresh() end
        return
    end

    if event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        if self.guildBankOpen then
            self:UpdateGuildMoney()
            self:RefreshGuildTabs()
        end
        return
    end

    if event == "MERCHANT_SHOW" or event == "MERCHANT_CLOSED" then
        self:QueueRefresh()
        return
    end

    if event == "PLAYER_MONEY" then
        self:UpdateMoney()
        if self.guildBankOpen then
            self:UpdateGuildMoney()
            self:RefreshGuildTabs()
        end
        return
    end

    if event == "UNIT_INVENTORY_CHANGED" then
        self:RefreshBagSlots(self.bagDisplay)
        if self.bankOpen then self:RefreshBagSlots(self.bankDisplay) end
        self:QueueRefresh()
        return
    end

    if event == "BAG_UPDATE" then
        self:CacheBags()
        if self.bankOpen then self:CacheBank() end
        self:QueueRefresh()
        return
    end

    if event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        self:CacheBank()
        self:QueueRefresh()
        return
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        self:QueueRefresh()
        return
    end
end)
