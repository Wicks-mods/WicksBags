-- Wick's Bags
-- Core.lua: WickCore addon object, saved variables, event dispatch, slash command.
--
-- Forever port. Every client call routes through WickCore's dialect shim, so
-- the same module code runs on Forever (C_Item / C_Container / C_UnitAuras)
-- and on TBC Anniversary (legacy globals). Modules destructure tuples, so the
-- shim's tables are unwrapped here once and exposed on ns.* exactly as before.

local ADDON, ns = ...

local Core = WickCore
if not Core then
    -- WickCore is missing or switched off.
    --
    -- The TOC asks for it with OptionalDeps rather than Dependencies on
    -- purpose. A hard dependency makes the client refuse to load this addon
    -- at all, so nothing of ours runs and the player is told nothing beyond
    -- a greyed line in the AddOns list. Loading anyway lets us say what is
    -- wrong and where to get it.
    --
    -- One line for the lot of them, not one per addon: with the whole suite
    -- installed and WickCore switched off, a line each would be a wall.
    local need = _G.WicksNeedCore
    if not need then
        need = {}
        _G.WicksNeedCore = need
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", function()
            table.sort(need)
            print(("|cff4FC778Wick's Mods|r: %s %s WickCore, which is not installed or not switched on. It is in the same download as the rest of the suite: |cffD4C8A1wicksmods.com|r")
                :format(table.concat(need, ", "), #need == 1 and "needs" or "need"))
        end)
    end
    need[#need + 1] = "Wick's Bags"
    return
end
local D = Core.Dialect

-- ============================================================
-- Client API, resolved once through the dialect shim
-- ============================================================
ns.GetNumAddOns     = (C_AddOns and C_AddOns.GetNumAddOns)     or GetNumAddOns
ns.GetAddOnInfo     = (C_AddOns and C_AddOns.GetAddOnInfo)     or GetAddOnInfo
ns.IsAddOnLoaded    = (C_AddOns and C_AddOns.IsAddOnLoaded)    or IsAddOnLoaded
ns.LoadAddOn        = (C_AddOns and C_AddOns.LoadAddOn)        or LoadAddOn
ns.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

ns.GetItemCooldown = (C_Item and C_Item.GetItemCooldown)
    or (C_Container and C_Container.GetItemCooldown)
    or GetItemCooldown

ns.GetContainerNumSlots     = D.GetContainerNumSlots
ns.GetContainerItemLink     = D.GetContainerItemLink
ns.GetContainerItemID       = D.GetContainerItemID
ns.PickupContainerItem      = D.PickupContainerItem
ns.UseContainerItem         = D.UseContainerItem
ns.ContainerIDToInventoryID = (C_Container and C_Container.ContainerIDToInventoryID) or ContainerIDToInventoryID
ns.GetItemCount             = D.GetItemCount
ns.GetItemQualityColor      = D.GetItemQualityColor

-- Tuple form of the container slot query, matching the legacy return order.
function ns.GetContainerItemInfo(bag, slot)
    local t = D.GetContainerItemInfo(bag, slot)
    if not t then return nil end
    return t.iconFileID, t.stackCount, t.isLocked, t.quality, t.isReadable, t.hasLoot,
           t.hyperlink, t.isFiltered, t.hasNoValue, t.itemID, t.isBound
end

-- Tuple form of GetItemInfo, legacy return order (bindType is the 14th).
function ns.GetItemInfo(item)
    local t = D.GetItemInfo(item)
    if not t then return nil end
    return t.name, t.link, t.quality, t.itemLevel, t.minLevel, t.itemType, t.itemSubType,
           t.stackCount, t.equipLoc, t.icon, t.sellPrice, t.classID, t.subclassID,
           t.bindType, t.expansionID, t.setID, t.isCraftingReagent
end

-- Tuple form of GetItemInfoInstant: itemID, type, subType, equipLoc, icon, classID, subclassID.
function ns.GetItemInfoInstant(item)
    local t = D.GetItemInfoInstant(item)
    if not t then return nil end
    return t.itemID, t.itemType, t.itemSubType, t.equipLoc, t.icon, t.classID, t.subclassID
end

-- Forever carries the currency API and none of the TBC currency globals.
-- Bag.lua and Options.lua key the watched-currency strip and its toggles
-- off this one flag.
ns.MODERN_CURRENCY = (C_CurrencyInfo and C_CurrencyInfo.GetBackpackCurrencyInfo and not GetHonorCurrency) and true or false

-- ============================================================
-- Item button template
-- ============================================================
-- Retail's ContainerFrameItemButtonTemplate is built on the intrinsic
-- ItemButton frame type. Creating it as a plain "Button" silently drops the
-- intrinsic's own regions (icon, Count, IconBorder, NormalTexture), which is
-- how the first Forever login crashed on a nil icon texture. Ask the client
-- what type the template wants; TBC has no intrinsics and keeps "Button".
local function slotFrameType()
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, "ContainerFrameItemButtonTemplate")
        if ok and type(info) == "table" and type(info.type) == "string" and info.type ~= "" then
            return info.type
        end
    end
    -- No template introspection: probe for the intrinsic directly.
    local ok, f = pcall(CreateFrame, "ItemButton")
    if ok and f then
        f:Hide()
        return "ItemButton"
    end
    return "Button"
end
ns.SLOT_FRAME_TYPE = slotFrameType()

-- The icon texture and stack count of a slot button, whichever way the
-- client keys them (retail parentKey, TBC global name), or our own regions
-- when the template supplied neither.
function ns.SlotIconTexture(b)
    local name = b.GetName and b:GetName()
    local tex = b.icon or b.IconTexture or (name and _G[name .. "IconTexture"])
    if not tex then
        tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", -1, 1)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = tex
    end
    return tex
end

function ns.SlotCountText(b)
    local name = b.GetName and b:GetName()
    local fs = b.Count or (name and _G[name .. "Count"])
    if not fs then
        fs = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        fs:SetPoint("BOTTOMRIGHT", -3, 2)
        fs:SetJustifyH("RIGHT")
        fs:Hide()
        b.Count = fs
    end
    return fs
end

-- ============================================================
-- Saved variables
-- ============================================================
-- Everything a player configures lives in the profile so WickCore can key it
-- by character, spec or game mode and export it as a string. Alt snapshots
-- are account-wide and live in global.
local PROFILE_DEFAULTS = {
    ui = { hidden = true },
    bagPos  = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    bankPos = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    avPos   = { posPoint = false, posRel = false, posX = 0, posY = 0, panelW = 0 },
    gbankPos = { posPoint = false, posRel = false, posX = 0, posY = 0 },
    options = {
        showJunk         = true,
        showHighlights   = true,
        sortMode         = "quality",   -- "quality" | "name" | "quantity"
        qualityMin       = 0,
        showSearch       = true,
        showBagBar       = true,
        showCurrencies   = true,        -- Forever: the player's watched currencies
        altTooltips      = true,        -- alt bag/bank counts in item tooltips
        -- TBC-only currency groups; ignored on Forever where currencies are watched tokens.
        showHonor        = true,
        showArena        = true,
        showMarks        = true,
        showBadges       = true,
        showShards       = true,
        showRep          = true,
        borderIntensity  = 1.0,
        showItemLevel    = true,
        slotScale        = 1.0,
        useItemRack      = true,
        hideDefaultBank  = true,
        hideDefaultGuildBank = true,
        suppressAutoBags = true,
        autoOpenBags     = true,
        hideKeyring      = false,
        activeSourceId   = "auto",
    },
    customRules = {
        byItemId = {},
        byClass  = {},
        patterns = {},
    },
    userCats = {},
}

local A = Core:NewAddon("WicksBags", {
    title    = "Wick's Bags",
    version  = "0.9.0",
    savedVar = "WicksBagsDB",
    defaults = {
        profile = PROFILE_DEFAULTS,
        global  = { alts = {} },
    },
    -- The alt inventory snapshot is a cache: it regrows the moment that
    -- alt logs in. It was forty-eight of the macro store's fifty-four
    -- macros, and left in it would grow with every alt until it pushed
    -- the real settings out of the budget.
    storeExclude = { "global.alts" },
})

-- ============================================================
-- Namespace (module bus is unchanged from the TBC build)
-- ============================================================
WicksBags = WicksBags or {}
local WB = WicksBags
ns.WB = WB
WB.ADDON = ADDON
WB.A = A
-- Rebound in OnInitialize once WickCore has the saved variables ready.
WB.db     = {}
WB.altDB  = {}
WB.charDB = {}

WB._listeners = {}
function WB:On(event, fn)
    self._listeners[event] = self._listeners[event] or {}
    table.insert(self._listeners[event], fn)
end
function WB:Emit(event, ...)
    local list = self._listeners[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then A:Print(("error in %s: %s"):format(event, tostring(err))) end
    end
end

-- ============================================================
-- Lifecycle
-- ============================================================
function A:OnInitialize()
    local sv = WicksBagsDB

    -- Migrate the pre-WickCore layout: ui/options/... sat at the top level of
    -- WicksBagsDB. Move them into the profile once.
    if type(sv.options) == "table" and not sv._migratedToProfile then
        for _, k in ipairs({ "ui", "bagPos", "bankPos", "avPos", "options", "customRules", "userCats" }) do
            if type(sv[k]) == "table" then
                self.db.profile[k] = sv[k]
                sv[k] = nil
            end
        end
        Core.applyDefaults(self.db.profile, PROFILE_DEFAULTS)
        sv._migratedToProfile = true
    end

    -- Alt snapshots used to live in their own WicksBagsAlts file.
    if type(WicksBagsAlts) == "table" and next(WicksBagsAlts) then
        for key, snap in pairs(WicksBagsAlts) do
            if not self.db.global.alts[key] then self.db.global.alts[key] = snap end
        end
        WicksBagsAlts = {}
    end

    WB.db     = self.db.profile
    WB.altDB  = self.db.global.alts
    WB.charDB = self.db.char

    self.db:On("OnProfileChanged", function()
        WB.db = self.db.profile
        WB:Emit("BAGS_DIRTY")
        WB:Emit("BANK_DIRTY")
        if WB.Bag and WB.Bag.ApplyOptionsUI then WB.Bag:ApplyOptionsUI() end
    end)
end

function A:OnEnable()
    WB:Emit("LOGIN")
    self:Print("loaded. /wbags to toggle.")

    self:RegisterLauncher({
        onClick = function(_, button)
            if button == "RightButton" then
                if WB.Options then WB.Options:Toggle() end
            elseif WB.Bag then
                WB.Bag:Toggle()
            end
        end,
        tooltip = function(tt)
            tt:AddLine(Core.Chrome:TitleMarkup("Wick's Bags"))
            tt:AddLine("Left-click: toggle bags   Right-click: options", 0.5, 0.5, 0.5)
        end,
    })

    self:RegisterOptions(function(page, addon)
        local O = Core.Options
        local y = O:Heading(page, "Wick's Bags", 0)
        y = O:Note(page, "Bag options live in the panel's own window: the cog icon, or /wbags options.", y)
        y = O:Button(page, "Open bag options", function()
            if WB.Options then WB.Options:Toggle() end
        end, y, 140)
        y = O:ProfileSection(page, addon, y - 8)
    end)
end

-- ============================================================
-- Game events
-- ============================================================
local f = CreateFrame("Frame")
WB.eventFrame = f
local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE",
    "BAG_UPDATE_DELAYED",
    "ITEM_LOCK_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
    "PLAYER_MONEY",
    "BAG_UPDATE_COOLDOWN",
    "PLAYER_EQUIPMENT_CHANGED",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED",
    "PLAYERBANKBAGSLOTS_CHANGED",
    "BANK_TABS_CHANGED",          -- Forever: tab purchased or renamed
    "GUILDBANKFRAME_OPENED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",   -- how retail and Forever open the vault
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "GUILDBANKFRAME_CLOSED",
    "GUILDBANKBAGSLOTS_CHANGED",
    "GUILDBANK_ITEM_LOCK_CHANGED",
    "GUILDBANK_UPDATE_TABS",
    "GUILDBANK_UPDATE_MONEY",
    "GUILDBANK_UPDATE_WITHDRAWMONEY",
    "CURRENCY_DISPLAY_UPDATE",    -- Forever: watched currencies changed
    "MERCHANT_SHOW",
    "MERCHANT_CLOSED",
    "MAIL_SHOW",
    "MAIL_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "TRADE_SKILL_SHOW",
    "TRADE_SKILL_CLOSE",
    "PLAYER_REGEN_ENABLED",       -- a held-over return of the game's bags
    "PLAYER_LOGOUT",
    "INPUT_DEVICE_INTERFACE_TRANSITION", -- Forever: a controller picked up or put down
}
for _, e in ipairs(EVENTS) do
    pcall(f.RegisterEvent, f, e)
end

local autoOpenedBag = false

-- Blizzard's own bags open themselves at a vendor, the mailbox, the bank
-- and the like (OpenAllBags, passed the window that opened them). Ours
-- stand in for them there, so theirs are kept out of sight: each of their
-- bag windows goes under a hidden frame of ours while they are open, and
-- back under its own parent once Blizzard has closed them, or as soon as
-- the player opens them on purpose (Shift+B).
--
-- They used to be shut with CloseAllBags. Called from here, that wrote
-- Blizzard's record of which window opened the bags as Wick's Bags. The
-- next bank visit read it while opening, chose its tab as Wick's Bags,
-- and from then on every bag item clicked (a hearthstone) was refused as
-- a blocked action until a reload (taint.log 2026-10-04). Moving a frame
-- writes nothing of Blizzard's.
local parkedBags = {}            -- Blizzard bag frame -> its own parent
local bagPark = CreateFrame("Frame")
bagPark:Hide()
local releasePending = false

-- On Forever's controller interface the game's bags are the ones made for
-- it: its navigation, its item panel, its radial opens them. Ours keep to
-- the keyboard. So with a controller in hand the game's bags are left in
-- their place, and ours are not opened for it at a vendor or the bank.
local function padActive()
    local S = rawget(_G, "C_InputInterfaceStyle")
    local E = rawget(_G, "Enum") and Enum.InputDeviceInterfaceType
    if not (S and S.GetCurrentStyle and E and E.Gamepad) then return false end
    local ok, style = pcall(S.GetCurrentStyle)
    return (ok and style == E.Gamepad) and true or false
end
WB.PadActive = padActive

local function blizzBagFrames()
    local out = {}
    local combined = rawget(_G, "ContainerFrameCombinedBags")
    if combined then out[#out + 1] = combined end
    for i = 1, (rawget(_G, "NUM_CONTAINER_FRAMES") or 13) do
        local fr = rawget(_G, "ContainerFrame" .. i)
        if fr then out[#out + 1] = fr end
    end
    return out
end

local function parkBlizzBags()
    if WB.db.options and WB.db.options.suppressAutoBags == false then return end
    if padActive() then return end
    if InCombatLockdown() then return end
    for _, fr in ipairs(blizzBagFrames()) do
        if not parkedBags[fr] then
            parkedBags[fr] = fr:GetParent() or UIParent
            fr:SetParent(bagPark)
        end
    end
end

local function releaseBlizzBags()
    if not next(parkedBags) then return end
    if InCombatLockdown() then releasePending = true return end
    releasePending = false
    for fr, parent in pairs(parkedBags) do
        fr:SetParent(parent)
        parkedBags[fr] = nil
    end
end

-- Back once Blizzard has shut its bags; at once when the player opens
-- them. The hooks are post-hooks, which run after Blizzard's own call and
-- leave it as it was.
local function anyBlizzBagShown()
    for _, fr in ipairs(blizzBagFrames()) do
        if fr:IsShown() then return true end
    end
    return false
end
local function releaseWhenShut()
    C_Timer.After(0, function()
        if not anyBlizzBagShown() then releaseBlizzBags() end
    end)
end
if hooksecurefunc then
    if rawget(_G, "OpenAllBags") then
        hooksecurefunc("OpenAllBags", function(frame)
            -- A window opening the bags for itself: keep them out of
            -- sight. The player's own Open All Bags: show them.
            if frame then parkBlizzBags() else releaseBlizzBags() end
        end)
    end
    if rawget(_G, "CloseAllBags") then hooksecurefunc("CloseAllBags", releaseWhenShut) end
    for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
        if rawget(_G, name) then hooksecurefunc(name, releaseBlizzBags) end
    end
end

local function suppressBlizzBags()
    parkBlizzBags()
end
WB.ParkedBlizzBags = parkedBags

local function autoOpenBag()
    if not WB.db.options or WB.db.options.autoOpenBags == false then return end
    if padActive() then return end
    if not WB.Bag then return end
    if not WB.db.ui.hidden then return end
    autoOpenedBag = true
    WB.Bag:Show()
end

local function autoCloseBag()
    if not autoOpenedBag then return end
    autoOpenedBag = false
    if WB.Bag and WB.Bag.Hide then WB.Bag:Hide() end
end

-- BAG_UPDATE fires per bag, many times in a row. Coalesce, and hold the
-- layout while the cursor carries an item so slots do not shuffle mid-drag.
local refreshDirty = false
local function scheduleRefresh()
    if refreshDirty then return end
    refreshDirty = true
    local function tryEmit()
        if CursorHasItem and CursorHasItem() then
            C_Timer.After(0.1, tryEmit)
        else
            refreshDirty = false
            WB:Emit("BAGS_DIRTY")
        end
    end
    C_Timer.After(0.05, tryEmit)
end

local bankDirty = false
local function scheduleBankRefresh()
    if bankDirty then return end
    bankDirty = true
    C_Timer.After(0.05, function()
        bankDirty = false
        WB:Emit("BANK_DIRTY")
    end)
end

local guildDirty = false
local function scheduleGuildRefresh()
    if guildDirty then return end
    guildDirty = true
    C_Timer.After(0.05, function()
        guildDirty = false
        WB:Emit("GUILDBANK_DIRTY")
    end)
end

-- The vault can announce itself two ways: GUILDBANKFRAME_OPENED, which the
-- TBC client sends, and the interaction manager's show with the guild
-- banker type, which is all Blizzard's modern guild bank code listens to.
-- Either opens ours once; counts are kept for /wbags guildbank.
local GUILD_BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
local guildOpen = false
WB.guildEvents = {}
local function guildBankOpened(how)
    WB.guildEvents[how] = (WB.guildEvents[how] or 0) + 1
    if guildOpen then return end
    guildOpen = true
    WB:Emit("GUILDBANK_OPENED")
    suppressBlizzBags()
    autoOpenBag()
end
local function guildBankClosed(how)
    WB.guildEvents[how] = (WB.guildEvents[how] or 0) + 1
    if not guildOpen then return end
    guildOpen = false
    WB:Emit("GUILDBANK_CLOSED")
    autoCloseBag()
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if releasePending then releaseWhenShut() end
        return
    end
    if event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ITEM_LOCK_CHANGED" then
        scheduleRefresh()
        if event == "ITEM_LOCK_CHANGED" then scheduleBankRefresh() end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        scheduleRefresh()
        scheduleBankRefresh()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        scheduleRefresh()
        scheduleBankRefresh()
    elseif event == "PLAYER_MONEY" or event == "CURRENCY_DISPLAY_UPDATE" then
        WB:Emit("MONEY_CHANGED")
    elseif event == "BAG_UPDATE_COOLDOWN" then
        WB:Emit("COOLDOWN_CHANGED")
    elseif event == "BANKFRAME_OPENED" then
        WB:Emit("BANK_OPENED")
        suppressBlizzBags()
        autoOpenBag()
    elseif event == "BANKFRAME_CLOSED" then
        WB:Emit("BANK_CLOSED")
        autoCloseBag()
    elseif event == "GUILDBANKFRAME_OPENED" then
        guildBankOpened(event)
    elseif event == "GUILDBANKFRAME_CLOSED" then
        guildBankClosed(event)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if GUILD_BANKER and ... == GUILD_BANKER then guildBankOpened(event) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if GUILD_BANKER and ... == GUILD_BANKER then guildBankClosed(event) end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" or event == "GUILDBANK_ITEM_LOCK_CHANGED"
        or event == "GUILDBANK_UPDATE_TABS" or event == "GUILDBANK_UPDATE_MONEY"
        or event == "GUILDBANK_UPDATE_WITHDRAWMONEY" then
        scheduleGuildRefresh()
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" or event == "BANK_TABS_CHANGED" then
        scheduleBankRefresh()
        if event == "BANK_TABS_CHANGED" then WB:Emit("BANK_TABS_CHANGED") end
    elseif event == "MERCHANT_SHOW" or event == "MAIL_SHOW"
        or event == "AUCTION_HOUSE_SHOW" or event == "TRADE_SKILL_SHOW" then
        suppressBlizzBags()
        autoOpenBag()
    elseif event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED"
        or event == "AUCTION_HOUSE_CLOSED" or event == "TRADE_SKILL_CLOSE" then
        autoCloseBag()
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- A controller in hand: the game's bags back in their place.
        if padActive() then releaseBlizzBags() end
    elseif event == "PLAYER_LOGOUT" then
        for _, mod in ipairs({ WB.Bag, WB.Bank, WB.GuildBank, WB.AltViewer }) do
            if mod and mod.panel and mod.panel._snapPosition then mod.panel._snapPosition() end
        end
    end
    WB:Emit(event, ...)
end)

-- ============================================================
-- Slash command
-- ============================================================
A:RegisterSlash(function(_, input)
    input = (input or ""):lower()
    if input == "" or input == "toggle" then
        if WB.Bag and WB.Bag.Toggle then WB.Bag:Toggle() end
        return
    end
    if input == "show" and WB.Bag then WB.Bag:Show() return end
    if input == "hide" and WB.Bag then WB.Bag:Hide() return end
    if input == "reset" and WB.Bag then WB.Bag:ResetPosition() return end
    if input == "options" or input == "config" then
        if WB.Options then WB.Options:Toggle() end
        return
    end
    if input == "alts" and WB.AltViewer then WB.AltViewer:Toggle() return end
    if input == "bank" then
        -- Written after three attempts at the bank were each a guess,
        -- and never wired to anything until someone needed it.
        if WB.Bank and WB.Bank.Diagnose then
            WB.Bank:Diagnose(function(line) A:Print(line) end)
        else A:Print("no bank diagnostic on this build.") end
        return
    end
    if input == "defaultbank" then
        -- Suppressing Blizzard's bank window means writing to their
        -- BankFrame: alpha, mouse, anchors. That write taints the frame,
        -- and their own ContainerFrameItemButton_OnClick reads it through
        -- BankFrame:GetActiveBankType, which is why right-clicking an
        -- item throws "blocked from an action" most often at the bank.
        -- Turning this off leaves their frame alone, at the cost of
        -- seeing it. It is the one way to tell whether that write is the
        -- cause, so it is reachable from here.
        local o = WB.db.options
        o.hideDefaultBank = (o.hideDefaultBank == false) and true or false
        A:Print(("Blizzard's bank window is now %s. Reload for it to take effect."):format(
            o.hideDefaultBank == false and "left alone (shown)" or "hidden by us"))
        return
    end
    if input == "guildbank" then
        local o = WB.db.options
        local bits = {}
        for k, v in pairs(WB.guildEvents or {}) do bits[#bits + 1] = k .. "=" .. v end
        A:Print("vault events seen: " .. (#bits > 0 and table.concat(bits, " ") or "none"))
        local gb = WB.GuildBank
        local st = gb and gb.State and gb:State() or {}
        local bf = rawget(_G, "GuildBankFrame")
        A:Print(("our panel: %s, shown %s   option hideDefaultGuildBank: %s")
            :format(gb and gb.panel and "built" or "not built",
                    tostring(gb and gb.panel and gb.panel:IsShown() or false),
                    tostring(o.hideDefaultGuildBank)))
        A:Print(("Blizzard's GuildBankFrame: %s, shown %s, alpha %s   hooked %s, revealed %s")
            :format(bf and "loaded" or "not loaded", tostring(bf and bf:IsShown() or false),
                    tostring(bf and bf:GetAlpha()), tostring(st.hooked), tostring(st.revealed)))
        return
    end
    if input == "defaultguildbank" then
        local o = WB.db.options
        o.hideDefaultGuildBank = (o.hideDefaultGuildBank == false) and true or false
        A:Print(("Blizzard's guild bank window is now %s. It applies from the next visit."):format(
            o.hideDefaultGuildBank == false and "left alone (shown)" or "replaced by ours"))
        return
    end
    if input == "clicks" then
        WB.clickDebug = not WB.clickDebug
        A:Print(("click reporting %s. Right-click an item: a line means the click reached the button, silence means something is sitting on top of it."):format(
            WB.clickDebug and "on" or "off"))
        return
    end
    if input == "bank" then
        if WB.Bank and WB.Bank.Diagnose then WB.Bank:Diagnose(function(l) A:Print(l) end) end
        return
    end
    if input == "sort" then
        if C_Container and C_Container.SortBags and not InCombatLockdown() then C_Container.SortBags() end
        return
    end
    if input == "help" or input == "?" then
        A:Print("commands")
        print("  /wbags                 toggle the panel")
        print("  /wbags clicks          report whether a click reaches an item button")
        print("  /wbags defaultbank     show or hide Blizzard's own bank window")
        print("  /wbags defaultguildbank use Blizzard's guild bank window instead of ours")
        print("  /wbags show | hide     show or hide")
        print("  /wbags options         open options")
        print("  /wbags alts            open the alt inventory viewer")
        print("  /wbags sort            one-click sort")
        print("  /wbags reset           reset position")
        print("  /wbags autoopen on|off auto-open at mailbox, vendor, bank")
        return
    end
    if input:match("^autoopen") then
        local arg = input:match("^autoopen%s+(%S+)")
        if arg == "off" or arg == "false" or arg == "0" then
            WB.db.options.autoOpenBags = false
            A:Print("auto-open disabled.")
        elseif arg == "on" or arg == "true" or arg == "1" then
            WB.db.options.autoOpenBags = true
            A:Print("auto-open enabled.")
        else
            A:Print(("auto-open is %s. Use /wbags autoopen on|off."):format(
                WB.db.options.autoOpenBags == false and "off" or "on"))
        end
        return
    end
    A:Print("unknown command. Try /wbags help")
end, "/wbags", "/wicksbags", "/wb")
