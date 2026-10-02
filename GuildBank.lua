-- Wick's Bags
-- GuildBank.lua: guild bank panel. Shows when GUILDBANKFRAME_OPENED fires,
-- in the same chrome as the bank. One tab at a time, laid out the way the
-- guild arranged it: shared tabs are organised by people, so nothing here
-- re-sorts or categorises them.

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WB = WicksBags
local UI = WB.UI

WB.GuildBank = {}
local GB = WB.GuildBank

local SLOTS_PER_TAB = 98
local SLOTS_PER_COL = 14    -- Blizzard numbers a tab in columns of 14...
local GRID_COLS     = 14    -- ...drawn as two side-by-side stacks of 7
local GRID_ROWS     = 7
local MAX_TABS      = 8
local SLOT_SIZE     = 32
local SLOT_GAP      = 2
local HEADER_H      = 28
local TABS_H        = 28
local BAR_H         = 32
local PADDING       = 6
local TAB_SIZE      = 22

local function gridW() return GRID_COLS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP end
local function gridH() return GRID_ROWS * (SLOT_SIZE + SLOT_GAP) - SLOT_GAP end

-- Slot i of a tab sits in column ceil(i/14) of Blizzard's frame; within a
-- column, 1..7 run down the left stack and 8..14 down the right one.
local function slotCell(i)
    local col = math.ceil(i / SLOTS_PER_COL)
    local k = (i - 1) % SLOTS_PER_COL + 1
    local x = (col - 1) * 2 + (k > 7 and 1 or 0)
    local y = (k - 1) % 7
    return x, y
end
GB.SlotCell = slotCell

local function currentTab()
    return (GetCurrentGuildBankTab and GetCurrentGuildBankTab()) or 1
end

local function numTabs()
    return (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
end

local function tabInfo(i)
    if not GetGuildBankTabInfo then return nil end
    local name, icon, isViewable, canDeposit, numWithdrawals, remaining = GetGuildBankTabInfo(i)
    if not name or name == "" then name = ("Tab %d"):format(i) end
    return name, icon, isViewable, canDeposit, numWithdrawals, remaining
end

local function selectTab(i)
    if not SetCurrentGuildBankTab then return end
    SetCurrentGuildBankTab(i)
    if QueryGuildBankTab then QueryGuildBankTab(i) end
    GB:Refresh()
end

-- The first viewable tab, for when the remembered one is not (rank change,
-- or a fresh visit where Blizzard left tab 1 selected and it is locked).
local function firstViewableTab()
    for i = 1, numTabs() do
        local _, _, viewable = tabInfo(i)
        if viewable then return i end
    end
    return nil
end

-- ============================================================
-- Slots
-- ============================================================
local function setQuality(b, quality)
    local qc = (quality and UI.C_QUALITY[quality]) or nil
    if not qc then b._setQualityBorder({ 0.20, 0.18, 0.34, 1 }) return end
    local intensity = (WB.db.options and WB.db.options.borderIntensity) or 1.0
    b._setQualityBorder({ qc[1], qc[2], qc[3], (qc[4] or 1) * math.min(intensity, 1) })
end

local function buildSlot(parent, i)
    local b = CreateFrame("Button", "WicksGuildBankSlot" .. i, parent)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b:SetID(i)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    UI:NewTexture(b, "BACKGROUND", { 0, 0, 0, 0.35 }):SetAllPoints(b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b._iconTex = icon

    local count = b:CreateFontString(nil, "OVERLAY")
    count:SetFont("Fonts\\ARIALN.TTF", 12, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", -1, 2)
    b._countText = count

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.12)

    -- Square quality edges, or the modern style's ring, as the bank draws them.
    local edges = {}
    local function edge(p1, p2, w, h)
        local t = b:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    b._setQualityBorder = function(c)
        for _, t in ipairs(edges) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    local ring = WickCore.Chrome.ModernSlot and WickCore.Chrome:ModernSlot(b, icon)
    if ring then
        for _, t in ipairs(edges) do t:Hide() end
        b._setQualityBorder = ring
    end
    setQuality(b, nil)

    -- The stack-split frame calls this with the amount chosen.
    b.SplitStack = function(self, split)
        if SplitGuildBankItem then SplitGuildBankItem(currentTab(), self:GetID(), split) end
    end

    -- Click handling follows Blizzard's GuildBankItemButtonMixin.
    b:SetScript("OnClick", function(self, button)
        local tab, slot = currentTab(), self:GetID()
        local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
        if link and HandleModifiedItemClick and HandleModifiedItemClick(link) then return end
        if IsModifiedClick and IsModifiedClick("SPLITSTACK") then
            if not (CursorHasItem and CursorHasItem()) and GetGuildBankItemInfo then
                local _, n, locked = GetGuildBankItemInfo(tab, slot)
                if not locked and n and n > 1 and StackSplitFrame then
                    StackSplitFrame:OpenStackSplitFrame(n, self, "BOTTOMLEFT", "TOPLEFT")
                end
            end
            return
        end
        -- Split, not `GetCursorInfo and GetCursorInfo()`: `and` keeps
        -- only the first return, and the amount is the second.
        local kind, money
        if GetCursorInfo then kind, money = GetCursorInfo() end
        if kind == "money" then
            if DepositGuildBankMoney then DepositGuildBankMoney(money) end
            ClearCursor()
        elseif kind == "guildbankmoney" then
            if DropCursorMoney then DropCursorMoney() end
            ClearCursor()
        elseif button == "RightButton" then
            if AutoStoreGuildBankItem then AutoStoreGuildBankItem(tab, slot) end
            GameTooltip:Hide()
        else
            if PickupGuildBankItem then PickupGuildBankItem(tab, slot) end
        end
    end)
    b:SetScript("OnDragStart", function(self)
        if PickupGuildBankItem then PickupGuildBankItem(currentTab(), self:GetID()) end
    end)
    b:SetScript("OnReceiveDrag", function(self)
        if PickupGuildBankItem then PickupGuildBankItem(currentTab(), self:GetID()) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetGuildBankItem then GameTooltip:SetGuildBankItem(currentTab(), self:GetID()) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function dressSlot(b, tab, i, term)
    local texture, n, locked, _, quality
    if GetGuildBankItemInfo then texture, n, locked, _, quality = GetGuildBankItemInfo(tab, i) end
    local link = texture and GetGuildBankItemLink and GetGuildBankItemLink(tab, i)
    b._link = link
    b._iconTex:SetTexture(texture)
    b._iconTex:SetDesaturated(locked and true or false)
    b._countText:SetText((n and n > 1) and tostring(n) or "")
    setQuality(b, texture and quality or nil)
    -- Search dims what does not match rather than hiding it, so the slot
    -- grid keeps the guild's layout.
    local match = true
    if term and term ~= "" then
        local name = link and link:match("%[(.-)%]")
        match = name and name:lower():find(term, 1, true) and true or false
    end
    b:SetAlpha(match and 1 or 0.25)
end

-- ============================================================
-- Panel
-- ============================================================
local function button(parent, w, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, 18)
    UI:NewTexture(btn, "BACKGROUND", { 0, 0, 0, 0.6 }):SetAllPoints(btn)
    UI:AddBorder(btn, UI.C_BORDER)
    local txt = UI:NewText(btn, 10, UI.C_TEXT_NORMAL)
    txt:SetPoint("CENTER")
    txt:SetText(label)
    btn._text = txt
    btn:SetScript("OnClick", onClick)
    btn:HookScript("OnEnter", function() txt:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    btn:HookScript("OnLeave", function()
        txt:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
        GameTooltip:Hide()
    end)
    return btn
end

local function tip(btn, title, line)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 1)
        if line then GameTooltip:AddLine(line, UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], true) end
        GameTooltip:Show()
    end)
end

local function buildPanel()
    local pos = WB.db.gbankPos
    local panel = CreateFrame("Frame", "WicksGuildBankPanel", UIParent)
    -- Not in UISpecialFrames, for the reason the bank panel gives: Blizzard's
    -- GuildBankFrame stays shown behind ours, so Escape reaches it, ends the
    -- session, and GUILDBANKFRAME_CLOSED brings this panel down with it.
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetSize(gridW() + PADDING * 2, HEADER_H + TABS_H + gridH() + BAR_H + PADDING * 3)
    if pos.posPoint and pos.posPoint ~= false then
        panel:SetPoint(pos.posPoint, UIParent, pos.posRel, pos.posX or 0, pos.posY or 0)
    else
        panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -120)
    end

    UI:NewTexture(panel, "BACKGROUND", UI.C_BG):SetAllPoints(panel)
    UI:AddBorder(panel)
    UI:AddCornerAccents(panel)

    local function snapPosition()
        local p, _, rp, x, y = panel:GetPoint()
        if not p then return end
        local t = WB.db.gbankPos
        t.posPoint = p; t.posRel = rp or p; t.posX = x or 0; t.posY = y or 0
    end
    panel._snapPosition = snapPosition
    panel:SetScript("OnMouseDown", function(self) self:Raise() end)
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); snapPosition() end)

    -- Header
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_H)
    UI:NewTexture(header, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(header)
    local modern = WickCore.Chrome.Modern and WickCore.Chrome:Modern()
    local divider = UI:NewTexture(header, "BORDER", modern and UI.C_GREEN or UI.C_BORDER)
    if modern then
        divider:SetPoint("BOTTOMLEFT", 6, 0); divider:SetPoint("BOTTOMRIGHT", -6, 0)
        divider:SetAlpha(0.5)
    else
        divider:SetPoint("BOTTOMLEFT"); divider:SetPoint("BOTTOMRIGHT")
    end
    divider:SetHeight(1)
    UI:AddTitleText(header, "Guild Bank", "LEFT", 8, 0)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -6, 0)
    local x = UI:NewText(close, 14, UI.C_TEXT_DIM)
    x:SetPoint("CENTER")
    x:SetText("\195\151")
    -- Ending the session, not just hiding: CloseGuildBankFrame fires
    -- GUILDBANKFRAME_CLOSED, which hides this panel.
    close:SetScript("OnClick", function()
        if CloseGuildBankFrame then CloseGuildBankFrame() end
        GB:Hide()
    end)
    close:SetScript("OnEnter", function() x:SetTextColor(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 1) end)
    close:SetScript("OnLeave", function() x:SetTextColor(UI.C_TEXT_DIM[1], UI.C_TEXT_DIM[2], UI.C_TEXT_DIM[3], 1) end)

    local search = CreateFrame("EditBox", nil, header)
    search:SetSize(110, 16)
    search:SetPoint("RIGHT", close, "LEFT", -8, 0)
    search:SetAutoFocus(false)
    search:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    search:SetTextColor(UI.C_TEXT_NORMAL[1], UI.C_TEXT_NORMAL[2], UI.C_TEXT_NORMAL[3], 1)
    search:SetMaxLetters(40)
    UI:AddBorder(search)
    UI:NewTexture(search, "BACKGROUND", UI.C_BG):SetAllPoints(search)
    search:SetTextInsets(4, 4, 0, 0)
    local placeholder = UI:NewText(search, 10, UI.C_TEXT_DIM)
    placeholder:SetPoint("LEFT", 4, 0)
    placeholder:SetText("search tab")
    search:SetScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
        GB:Refresh()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText("") end)
    panel._search = search

    -- Tab strip
    local tabs = CreateFrame("Frame", nil, panel)
    tabs:SetPoint("TOPLEFT", PADDING, -(HEADER_H + 3))
    tabs:SetPoint("TOPRIGHT", -PADDING, -(HEADER_H + 3))
    tabs:SetHeight(TABS_H - 4)
    panel._tabs = {}
    for i = 1, MAX_TABS do
        local t = CreateFrame("Button", nil, tabs)
        t:SetSize(TAB_SIZE, TAB_SIZE)
        t:SetPoint("LEFT", (i - 1) * (TAB_SIZE + 6), 0)
        t:RegisterForClicks("LeftButtonUp")
        local ic = t:CreateTexture(nil, "ARTWORK")
        ic:SetAllPoints(t)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        UI:AddBorder(t)
        local sel = t:CreateTexture(nil, "OVERLAY")
        sel:SetColorTexture(UI.C_GREEN[1], UI.C_GREEN[2], UI.C_GREEN[3], 0.30)
        sel:SetPoint("TOPLEFT", -1, 1)
        sel:SetPoint("BOTTOMRIGHT", 1, -1)
        sel:Hide()
        t._icon, t._sel, t._index = ic, sel, i
        t:SetScript("OnClick", function(self)
            local _, _, viewable = tabInfo(self._index)
            if viewable then selectTab(self._index) end
        end)
        t:SetScript("OnEnter", function(self)
            local name, _, viewable, canDeposit, _, remaining = tabInfo(self._index)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(name or ("Tab " .. self._index), 1, 1, 1)
            local d = UI.C_TEXT_DIM
            if not viewable then
                GameTooltip:AddLine("Your rank cannot view this tab.", d[1], d[2], d[3])
            else
                if remaining and remaining >= 0 then
                    GameTooltip:AddLine(("Withdrawals left today: %d"):format(remaining), d[1], d[2], d[3])
                elseif remaining then
                    GameTooltip:AddLine("Withdrawals: unlimited", d[1], d[2], d[3])
                end
                if canDeposit == false then GameTooltip:AddLine("Deposits not allowed", d[1], d[2], d[3]) end
            end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel._tabs[i] = t
    end
    local tabLabel = UI:NewText(tabs, 11, UI.C_TEXT_NORMAL)
    tabLabel:SetPoint("RIGHT", tabs, "RIGHT", -2, 0)
    tabLabel:SetJustifyH("RIGHT")
    panel._tabLabel = tabLabel

    -- Slot grid
    local grid = CreateFrame("Frame", nil, panel)
    grid:SetPoint("TOPLEFT", PADDING, -(HEADER_H + TABS_H + PADDING))
    grid:SetSize(gridW(), gridH())
    panel._grid = grid
    panel._slots = {}
    for i = 1, SLOTS_PER_TAB do
        local b = buildSlot(grid, i)
        local cx, cy = slotCell(i)
        b:SetPoint("TOPLEFT", cx * (SLOT_SIZE + SLOT_GAP), -cy * (SLOT_SIZE + SLOT_GAP))
        panel._slots[i] = b
    end
    local empty = UI:NewText(grid, 12, UI.C_TEXT_DIM)
    empty:SetPoint("CENTER")
    empty:Hide()
    panel._empty = empty

    -- Bottom bar
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(BAR_H - 4)
    bar:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    bar:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    UI:NewTexture(bar, "BACKGROUND", UI.C_HEADER_BG):SetAllPoints(bar)
    local rule = UI:NewTexture(bar, "BORDER", UI.C_BORDER)
    rule:SetPoint("TOPLEFT"); rule:SetPoint("TOPRIGHT"); rule:SetHeight(1)

    local deposit = button(bar, 60, "Deposit", function()
        if StaticPopup_Hide then StaticPopup_Hide("GUILDBANK_WITHDRAW") end
        if StaticPopup_Show then StaticPopup_Show("GUILDBANK_DEPOSIT") end
    end)
    deposit:SetPoint("LEFT", 4, 0)
    tip(deposit, "Deposit gold", "Puts gold from your bags into the guild bank.")
    local withdraw = button(bar, 64, "Withdraw", function()
        if StaticPopup_Hide then StaticPopup_Hide("GUILDBANK_DEPOSIT") end
        if StaticPopup_Show then StaticPopup_Show("GUILDBANK_WITHDRAW") end
    end)
    withdraw:SetPoint("LEFT", deposit, "RIGHT", 6, 0)
    withdraw:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Withdraw gold", 1, 1, 1)
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
        local d = UI.C_TEXT_DIM
        if limit and limit >= 0 then
            GameTooltip:AddLine("You can take " .. UI:FormatMoney(limit) .. " today.", d[1], d[2], d[3])
        elseif limit then
            GameTooltip:AddLine("No daily limit.", d[1], d[2], d[3])
        end
        GameTooltip:Show()
    end)
    panel._deposit, panel._withdraw = deposit, withdraw

    -- The log, tab names and permissions, and buying tabs all live in
    -- Blizzard's window; this steps aside for it.
    local blizz = button(bar, 70, "Log & tabs", function() GB:RevealDefault() end)
    blizz:SetPoint("LEFT", withdraw, "RIGHT", 6, 0)
    tip(blizz, "Blizzard's guild bank window", "For the log, tab names and permissions, and buying tabs. Close it to come back here.")
    panel._blizzBtn = blizz

    local gold = UI:NewText(bar, 11, UI.C_TEXT_NORMAL)
    gold:SetPoint("RIGHT", -8, 0)
    panel._gold = gold

    return panel
end

-- ============================================================
-- Refresh
-- ============================================================
function GB:Refresh()
    local panel = self.panel
    if not (panel and panel:IsShown()) then return end

    local n = numTabs()
    local tab = currentTab()
    local _, _, curViewable = tabInfo(tab)
    if n > 0 and not curViewable then
        local first = firstViewableTab()
        if first and first ~= tab and SetCurrentGuildBankTab then
            SetCurrentGuildBankTab(first)
            if QueryGuildBankTab then QueryGuildBankTab(first) end
            tab, curViewable = first, true
        end
    end

    for i = 1, MAX_TABS do
        local t = panel._tabs[i]
        if i <= n then
            local _, icon, viewable = tabInfo(i)
            t._icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            t._icon:SetDesaturated(not viewable)
            t._sel:SetShown(i == tab)
            t:SetAlpha(viewable and 1 or 0.5)
            t:Show()
        else
            t:Hide()
        end
    end

    local name, _, _, _, _, remaining = tabInfo(tab)
    local label = n > 0 and name or ""
    if n > 0 and curViewable and remaining and remaining >= 0 then
        label = ("%s  |cff6b598a%d left|r"):format(label, remaining)
    end
    panel._tabLabel:SetText(label)

    local term = panel._search:GetText()
    term = term and term:lower() or ""
    local showGrid = n > 0 and curViewable
    for i = 1, SLOTS_PER_TAB do
        local b = panel._slots[i]
        if showGrid then dressSlot(b, tab, i, term); b:Show() else b:Hide() end
    end
    if n == 0 then
        panel._empty:SetText("This guild has no bank tabs yet.")
        panel._empty:Show()
    elseif not curViewable then
        panel._empty:SetText("Your rank cannot view any tab.")
        panel._empty:Show()
    else
        panel._empty:Hide()
    end

    panel._gold:SetText(UI:FormatMoney((GetGuildBankMoney and GetGuildBankMoney()) or 0))
    local canWithdraw = CanWithdrawGuildBankMoney and CanWithdrawGuildBankMoney()
    panel._withdraw:SetShown(canWithdraw and true or false)
end

function GB:Init()
    if self.panel then return end
    self.panel = buildPanel()
    self.panel:Hide()
end

function GB:Show()
    self:Init()
    self.panel:Show()
    self.panel:Raise()
    self:Refresh()
end

function GB:Hide()
    if not self.panel then return end
    if self.panel._snapPosition then self.panel._snapPosition() end
    self.panel:Hide()
    if StaticPopup_Hide then
        StaticPopup_Hide("GUILDBANK_DEPOSIT")
        StaticPopup_Hide("GUILDBANK_WITHDRAW")
    end
end

-- ============================================================
-- Blizzard's GuildBankFrame
-- ============================================================
-- Same treatment as the bank: hiding it would run its OnHide, which calls
-- CloseGuildBankFrame and ends the session. So it stays shown, invisible,
-- parked off screen, and Escape still reaches it. Deferred a frame so
-- Blizzard's own OnShow (tab select, first query) finishes untouched.
-- Nothing is written onto Blizzard's frame: its state lives here. A field
-- set on one of their frames is tainted, and their code reads that frame.
local anchor, hooked, revealed

local function parked(f)
    if not anchor then
        local point, rel, relPoint, x, y = f:GetPoint()
        anchor = { point or "CENTER", rel, relPoint or "CENTER", x or 0, y or 0 }
    end
    f:SetAlpha(0)
    f:EnableMouse(false)
    f:ClearAllPoints()
    f:SetPoint("LEFT", UIParent, "RIGHT", 100, 0)
end

local function restored(f)
    f:SetAlpha(1)
    f:EnableMouse(true)
    f:ClearAllPoints()
    if anchor and anchor[2] then f:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    else f:SetPoint("CENTER") end
end

local function hideDefaultWanted()
    return WB.db.options.hideDefaultGuildBank ~= false
end

local function takeOver()
    local f = rawget(_G, "GuildBankFrame")
    if not f then return end
    if not hooked then
        hooked = true
        f:HookScript("OnShow", function(self)
            if revealed or not hideDefaultWanted() then return end
            C_Timer.After(0, function()
                if self:IsShown() and not revealed and hideDefaultWanted() then parked(self) end
            end)
        end)
        f:HookScript("OnHide", function(self)
            revealed = nil
            restored(self)
        end)
    end
    if f:IsShown() and not revealed and hideDefaultWanted() then parked(f) end
end

function GB:RevealDefault()
    local f = rawget(_G, "GuildBankFrame")
    if not f then return end
    revealed = true
    restored(f)
    if self.panel then self.panel:Hide() end
end

function GB:State() return { hooked = hooked, revealed = revealed, parked = anchor ~= nil } end

-- Blizzard's window loads on demand during the first vault visit, possibly
-- after our open handler has run. Their bootstrap's ShowGuildBankFrame
-- runs every time it is shown, so a post-hook catches it whenever it turns
-- up. hooksecurefunc leaves their function untainted.
if type(rawget(_G, "ShowGuildBankFrame")) == "function" and hooksecurefunc then
    hooksecurefunc("ShowGuildBankFrame", function()
        if GB.panel and GB.panel:IsShown() then takeOver() end
    end)
end

-- ============================================================
-- Events
-- ============================================================
WB:On("GUILDBANK_OPENED", function()
    if not hideDefaultWanted() then return end
    GB:Show()
    -- Blizzard's frame loads on demand inside the open and its OnShow
    -- queries the selected tab; take over after both have happened.
    C_Timer.After(0, function()
        takeOver()
        local tab = currentTab()
        if QueryGuildBankTab then QueryGuildBankTab(tab) end
        GB:Refresh()
    end)
end)

WB:On("GUILDBANK_CLOSED", function() GB:Hide() end)

WB:On("GUILDBANK_DIRTY", function() GB:Refresh() end)
