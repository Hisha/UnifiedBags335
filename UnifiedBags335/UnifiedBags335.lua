local ADDON = "UnifiedBags335"
local UB = CreateFrame("Frame")
_G.UnifiedBags335 = UB

local BANK = BANK_CONTAINER or -1
local BAG_COUNT = NUM_BAG_SLOTS or 4
local BANK_BAG_COUNT = NUM_BANKBAGSLOTS or 7
local BUTTON_SIZE = 36
local BUTTON_GAP = 5
local COLUMNS = 11
local GRID_LEFT = 18
local GRID_TOP = -82
local SCROLL_WIDTH = COLUMNS * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP

UB.bankOpen = false
UB.view = "bags"
UB.buttons = {}
UB.visibleItems = {}
UB.searchText = ""
UB.hooksInstalled = false
UB.reagentAPI = nil
UB.refreshPending = false
UB.bankShowPending = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffUnifiedBags335:|r " .. tostring(msg))
end

local function ItemIDFromLink(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

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

    local realm = RealmKey()
    if type(UnifiedBags335DB.realms[realm]) ~= "table" then UnifiedBags335DB.realms[realm] = {} end
    local name = CharacterKey()
    if type(UnifiedBags335DB.realms[realm][name]) ~= "table" then
        UnifiedBags335DB.realms[realm][name] = { bags = {}, bank = {}, reagents = {}, bankSeen = false }
    end
    return UnifiedBags335DB.realms[realm][name]
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
    local char = EnsureDB()
    char.bags = ScanContainers(self:GetBagIDs())
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

    local rows = {}
    local grandTotal = 0
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
        local detail = tostring(row.total)
        if row.bank > 0 or row.reagents > 0 then
            local parts = {}
            if row.bags > 0 then table.insert(parts, "bags " .. row.bags) end
            if row.bank > 0 then table.insert(parts, "bank " .. row.bank) end
            if row.reagents > 0 then table.insert(parts, "reagents " .. row.reagents) end
            detail = detail .. "  (" .. table.concat(parts, ", ") .. ")"
        end
        tooltip:AddDoubleLine(row.name, detail, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    if #rows > 1 then
        tooltip:AddDoubleLine("Total", tostring(grandTotal), 1, 0.82, 0, 1, 0.82, 0)
    end
    tooltip:Show()
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
    local dropOK = self.view == "bags" and CursorInside(self.frame)
    self:CancelVirtualDrag()
    if dropOK and itemID and amount and self.reagentAPI then
        self.reagentAPI:RequestWithdraw(itemID, amount)
    end
end

function UB:CreateFrame()
    if self.frame then return end

    local f = CreateFrame("Frame", "UnifiedBags335Frame", UIParent)
    self.frame = f
    f:SetWidth(535)
    f:SetHeight(485)
    f:SetPoint("CENTER", UIParent, "CENTER", 150, 20)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(frame)
        if not UB.dragItemID then frame:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        UnifiedBags335DB.settings.point = { point, relativePoint, x, y }
    end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 10, right = 10, top = 10, bottom = 10 }
    })
    f:Hide()
    table.insert(UISpecialFrames, "UnifiedBags335Frame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.title = title
    title:SetPoint("TOPLEFT", 20, -17)
    title:SetText("Bags")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function()
        if UB.bankOpen and CloseBankFrame then
            CloseBankFrame()
        else
            UB:Hide()
        end
    end)

    local function MakeTab(text, view, x)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetWidth(112)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", x, -45)
        b:SetText(text)
        b:SetScript("OnClick", function() UB:SetView(view) end)
        return b
    end
    self.bagTab = MakeTab("Bags", "bags", 18)
    self.bankTab = MakeTab("Bank", "bank", 134)
    self.reagentTab = MakeTab("Reagent Storage", "reagents", 250)
    self.reagentTab:SetWidth(145)

    local search = CreateFrame("EditBox", "UnifiedBags335SearchBox", f, "InputBoxTemplate")
    self.search = search
    search:SetAutoFocus(false)
    search:SetWidth(112)
    search:SetHeight(20)
    search:SetPoint("TOPRIGHT", -34, -46)
    search:SetMaxLetters(40)
    search:SetScript("OnTextChanged", function(box)
        UB.searchText = string.lower(box:GetText() or "")
        UB:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)

    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    searchLabel:SetPoint("RIGHT", search, "LEFT", -5, 0)
    searchLabel:SetText("Search")

    local scroll = CreateFrame("ScrollFrame", "UnifiedBags335ScrollFrame", f, "UIPanelScrollFrameTemplate")
    self.scroll = scroll
    scroll:SetPoint("TOPLEFT", GRID_LEFT, GRID_TOP)
    scroll:SetPoint("BOTTOMRIGHT", -35, 20)

    local child = CreateFrame("Frame", "UnifiedBags335ScrollChild", scroll)
    self.scrollChild = child
    child:SetWidth(SCROLL_WIDTH)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(frame, delta)
        local current = frame:GetVerticalScroll() or 0
        local maxScroll = math.max(0, child:GetHeight() - frame:GetHeight())
        frame:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 42)))
    end)

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

    if UnifiedBags335DB.settings.point then
        local p = UnifiedBags335DB.settings.point
        f:ClearAllPoints()
        f:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
    end
end

function UB:GetButton(index)
    local b = self.buttons[index]
    if b then return b end

    local name = "UnifiedBags335Item" .. index
    b = CreateFrame("Button", name, self.scrollChild, "ItemButtonTemplate")
    self.buttons[index] = b
    b:SetWidth(BUTTON_SIZE); b:SetHeight(BUTTON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = _G[name .. "IconTexture"]
    b.countText = _G[name .. "Count"]

    b.empty = b:CreateTexture(nil, "BACKGROUND")
    b.empty:SetAllPoints(b)
    b.empty:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    b.empty:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.SplitStack = function(button, amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return end
        if button.kind == "reagent" then
            if UB.reagentAPI then UB.reagentAPI:RequestWithdraw(button.itemID, amount) end
        elseif button.bag and button.slot then
            SplitContainerItem(button.bag, button.slot, amount)
        end
    end

    b:SetScript("OnEnter", function(button)
        if not button.itemID then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        if button.link then GameTooltip:SetHyperlink(button.link) else GameTooltip:SetHyperlink("item:" .. button.itemID) end
        UB:AddAccountCounts(GameTooltip, button.itemID)
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnClick", function(button, mouseButton)
        if not button.itemID then return end

        if button.kind == "reagent" then
            local stored = UB.reagentAPI and UB.reagentAPI:GetStored(button.itemID) or button.count or 0
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(button.itemID)
            maxStack = tonumber(maxStack) or 1
            local stackAmount = math.max(1, math.min(stored, maxStack))
            if IsShiftKeyDown() then
                if stored > 1 then StackSplitFrame_OpenStackSplitFrame(stackAmount, button, "TOPLEFT", "BOTTOMLEFT") end
            elseif mouseButton == "RightButton" and UB.reagentAPI then
                UB.reagentAPI:RequestWithdraw(button.itemID, stackAmount)
            end
            return
        end

        if IsShiftKeyDown() then
            if ChatFrameEditBox and ChatFrameEditBox:IsVisible() and button.link then
                ChatEdit_InsertLink(button.link)
            elseif (button.count or 0) > 1 then
                StackSplitFrame_OpenStackSplitFrame(button.count, button, "TOPLEFT", "BOTTOMLEFT")
            end
            return
        end

        if mouseButton == "RightButton" then
            UseContainerItem(button.bag, button.slot)
        else
            PickupContainerItem(button.bag, button.slot)
        end
    end)

    b:SetScript("OnDragStart", function(button)
        if not button.itemID then return end
        if button.kind == "reagent" then
            local stored = UB.reagentAPI and UB.reagentAPI:GetStored(button.itemID) or button.count or 0
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(button.itemID)
            maxStack = tonumber(maxStack) or 1
            UB:BeginVirtualDrag(button.itemID, math.max(1, math.min(stored, maxStack)), button.texture)
        else
            PickupContainerItem(button.bag, button.slot)
        end
    end)

    b:SetScript("OnReceiveDrag", function(button)
        if button.kind ~= "reagent" and button.bag and button.slot then PickupContainerItem(button.bag, button.slot) end
    end)

    return b
end

local function MatchesSearch(searchText, itemID, link)
    if not searchText or searchText == "" then return true end
    if link and string.find(string.lower(link), searchText, 1, true) then return true end
    local name, _, _, _, _, itemType, subType = GetItemInfo(itemID)
    local haystack = string.lower((name or "") .. " " .. (itemType or "") .. " " .. (subType or ""))
    return string.find(haystack, searchText, 1, true) ~= nil
end

function UB:BuildContainerItems(ids)
    local items = {}
    local searching = self.searchText ~= ""
    for _, bag in ipairs(ids) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
            local link = GetContainerItemLink(bag, slot)
            local itemID = ItemIDFromLink(link)
            if itemID then
                if MatchesSearch(self.searchText, itemID, link) then
                    table.insert(items, { kind = "container", bag = bag, slot = slot, itemID = itemID, link = link, texture = texture, count = count or 1, locked = locked, quality = quality })
                end
            elseif not searching then
                table.insert(items, { kind = "empty", bag = bag, slot = slot })
            end
        end
    end
    return items
end

function UB:BuildReagentItems()
    local items = {}
    if not self.reagentAPI or not self.reagentAPI.GetVirtualItems then return items end
    for itemID, amount in pairs(self.reagentAPI:GetVirtualItems() or {}) do
        itemID, amount = tonumber(itemID), tonumber(amount)
        if itemID and amount and amount > 0 and MatchesSearch(self.searchText, itemID, nil) then
            local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(itemID)
            table.insert(items, { kind = "reagent", itemID = itemID, link = link, texture = texture, count = amount, name = name or ("Item " .. itemID) })
        end
    end
    table.sort(items, function(a, b)
        local an, bn = string.lower(a.name or ""), string.lower(b.name or "")
        if an == bn then return a.itemID < b.itemID end
        return an < bn
    end)
    return items
end

function UB:LayoutItems(items)
    local shown = 0
    for i, data in ipairs(items) do
        local b = self:GetButton(i)
        shown = i
        b:ClearAllPoints()
        local col = math.mod(i - 1, COLUMNS)
        local row = math.floor((i - 1) / COLUMNS)
        b:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", col * (BUTTON_SIZE + BUTTON_GAP), -row * (BUTTON_SIZE + BUTTON_GAP))

        b.kind = data.kind
        b.bag = data.bag
        b.slot = data.slot
        b.itemID = data.itemID
        b.link = data.link
        b.texture = data.texture
        b.count = data.count or 0

        if data.itemID then
            b.empty:Hide()
            b.icon:SetTexture(data.texture)
            b.icon:Show()
            if data.count and data.count > 1 then b.countText:SetText(data.count) else b.countText:SetText("") end
            if data.locked then SetItemButtonDesaturated(b, 1, 0.5, 0.5, 0.5) else SetItemButtonDesaturated(b, nil) end
        else
            b.icon:SetTexture(nil)
            b.icon:Hide()
            b.countText:SetText("")
            b.empty:Show()
            SetItemButtonDesaturated(b, nil)
        end
        b:Show()
    end

    for i = shown + 1, #self.buttons do self.buttons[i]:Hide() end

    local rows = math.max(1, math.ceil(math.max(1, #items) / COLUMNS))
    self.scrollChild:SetHeight(rows * (BUTTON_SIZE + BUTTON_GAP))
    local maxScroll = math.max(0, self.scrollChild:GetHeight() - self.scroll:GetHeight())
    if self.scroll:GetVerticalScroll() > maxScroll then self.scroll:SetVerticalScroll(maxScroll) end
end

function UB:UpdateTabs()
    if self.bankOpen then self.bankTab:Enable() else self.bankTab:Disable() end
    if self.bankOpen and self.reagentAPI and self.reagentAPI.IsServerAvailable and self.reagentAPI:IsServerAvailable() then
        self.reagentTab:Enable()
    else
        self.reagentTab:Disable()
    end
end

function UB:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    self:UpdateTabs()

    local items
    if self.view == "bank" then
        if not self.bankOpen then self.view = "bags" end
    elseif self.view == "reagents" then
        if not self.bankOpen or not self.reagentAPI then self.view = "bags" end
    end

    if self.view == "bank" then
        self.title:SetText(CharacterKey() .. " - Bank")
        items = self:BuildContainerItems(self:GetBankIDs())
    elseif self.view == "reagents" then
        self.title:SetText(CharacterKey() .. " - Reagent Storage")
        items = self:BuildReagentItems()
    else
        self.title:SetText(CharacterKey() .. " - Bags")
        items = self:BuildContainerItems(self:GetBagIDs())
    end
    self:LayoutItems(items)
end

function UB:QueueRefresh()
    self.refreshPending = true
end

function UB:SetView(view)
    if view == "bank" and not self.bankOpen then return end
    if view == "reagents" and (not self.bankOpen or not self.reagentAPI) then return end
    self.view = view
    self.scroll:SetVerticalScroll(0)
    self:Refresh()
end

function UB:Show(view)
    self:CreateFrame()
    if view then self.view = view end
    self.frame:Show()
    self:Refresh()
end

function UB:Hide()
    self:CancelVirtualDrag()
    if self.frame then self.frame:Hide() end
end

function UB:ToggleBags()
    self:CreateFrame()
    if self.frame:IsShown() and self.view == "bags" and not self.bankOpen then
        self:Hide()
    else
        self:Show("bags")
    end
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
    self:CacheReagents()
end

function UB:InstallHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true

    self.originalToggleBackpack = ToggleBackpack
    self.originalOpenBackpack = OpenBackpack
    self.originalCloseBackpack = CloseBackpack
    self.originalToggleBag = ToggleBag
    self.originalOpenAllBags = OpenAllBags
    self.originalCloseAllBags = CloseAllBags

    ToggleBackpack = function() UB:ToggleBags() end
    OpenBackpack = function() UB:Show("bags") end
    CloseBackpack = function()
        if not UB.bankOpen then UB:Hide() end
    end
    ToggleBag = function(bagSlot)
        if bagSlot and bagSlot > BAG_COUNT and UB.bankOpen then UB:Show("bank") else UB:ToggleBags() end
    end
    OpenAllBags = function(force)
        if UB.bankOpen then
            UB:Show(UB.view == "reagents" and "reagents" or "bank")
        elseif force then UB:Show("bags") else UB:ToggleBags() end
    end
    CloseAllBags = function()
        if not UB.bankOpen then UB:Hide() end
    end

    -- We replace Blizzard's bank frame, but the normal client/server banker
    -- session is untouched.  BANKFRAME_OPENED/CLOSED still drive our UI.
    if BankFrame then
        BankFrame:UnregisterEvent("BANKFRAME_OPENED")
        BankFrame:UnregisterEvent("BANKFRAME_CLOSED")
        BankFrame:Hide()
    end
end

UB:RegisterEvent("PLAYER_LOGIN")
UB:RegisterEvent("PLAYER_LOGOUT")
UB:RegisterEvent("BAG_UPDATE")
UB:RegisterEvent("BANKFRAME_OPENED")
UB:RegisterEvent("BANKFRAME_CLOSED")
UB:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
UB:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
UB:RegisterEvent("GET_ITEM_INFO_RECEIVED")
UB:RegisterEvent("ADDON_LOADED")
UB:SetScript("OnUpdate", function(self)
    -- One-frame scheduler shared by ordinary inventory refreshes and banker
    -- opening.  Keeping one scheduler prevents simultaneous BRG sync/BAG_UPDATE
    -- events from replacing each other's OnUpdate handlers.
    if self.bankShowPending then
        self.bankShowPending = false
        self:Show("bank")
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
        EnsureDB()
        self:CreateFrame()
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
        -- Defer one frame so any stock OpenAllBags call generated by the bank
        -- interaction cannot switch the initial view away from Bank.
        self.bankShowPending = true
        return
    end

    if event == "BANKFRAME_CLOSED" then
        self:CacheBank()
        self.bankOpen = false
        if self.view == "bank" or self.view == "reagents" then self:Hide() end
        self:UpdateTabs()
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
