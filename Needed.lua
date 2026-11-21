-- Wick's Bags
-- Needed.lua: is this item still needed?
--
-- Two things can want an item: a quest in the log that counts it, and a
-- recipe a character of yours knows. An item either of them wants gets a
-- small mark on its slot and a line in its tooltip saying who wants it, so
-- a bag clean-out does not sell tomorrow's quest turn-in or the cloth a
-- recipe uses.
--
-- Quests are read from the log whenever it changes. Recipes are read when
-- a profession window is open (the client does not hand them over
-- otherwise) and kept per character, so an alt's recipes count too.
-- Nothing here runs per frame, and nothing is read in combat.

local ADDON, ns = ...
if not WickCore then return end   -- said once in Core.lua
local WB = WicksBags

WB.Needed = {}
local N = WB.Needed

local secret = rawget(_G, "issecretvalue")
local function plain(v) if secret and secret(v) then return nil end return v end

local function on() return WB.db and WB.db.options and WB.db.options.showNeeded ~= false end
local function me() return (UnitName and plain(UnitName("player"))) or "Unknown" end

-- ============================================================
-- Quests
-- ============================================================
-- item name, lower case -> { title, have, need }
local quests = {}
local questSig = ""
local questsDirty = true

-- "Linen Cloth: 3/10" on one client, "3/10 Linen Cloth" on the other.
local function objectiveName(text)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("%d+%s*/%s*%d+", ""):gsub(":", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s:lower()
end

local function readQuests()
    local out, sig = {}, {}
    local CQ = rawget(_G, "C_QuestLog")
    local count = 0
    if CQ and CQ.GetNumQuestLogEntries then
        count = CQ.GetNumQuestLogEntries() or 0
    elseif rawget(_G, "GetNumQuestLogEntries") then
        count = GetNumQuestLogEntries() or 0
    end
    for i = 1, count do
        local title, isHeader, questID
        if CQ and CQ.GetInfo then
            local info = CQ.GetInfo(i)
            if info then title, isHeader, questID = info.title, info.isHeader, info.questID end
        elseif rawget(_G, "GetQuestLogTitle") then
            local t = { GetQuestLogTitle(i) }
            title, isHeader, questID = t[1], t[4], t[8]
        end
        title = plain(title)
        if not isHeader and questID and CQ and CQ.GetQuestObjectives then
            local objectives = CQ.GetQuestObjectives(questID)
            for _, o in ipairs(type(objectives) == "table" and objectives or {}) do
                if o.type == "item" and not o.finished then
                    local name = objectiveName(plain(o.text))
                    if name then
                        out[name] = { title = title or "a quest", have = o.numFulfilled, need = o.numRequired }
                        sig[#sig + 1] = name .. (o.numFulfilled or 0)
                    end
                end
            end
        end
    end
    table.sort(sig)
    return out, table.concat(sig, "|")
end

-- True when what the log wants has changed since the last read.
local function refreshQuests()
    if not questsDirty then return false end
    questsDirty = false
    local ok, out, sig = pcall(readQuests)
    if not ok then return false end
    local changed = sig ~= questSig
    quests, questSig = out, sig
    return changed
end

-- ============================================================
-- Recipes
-- ============================================================
-- WicksBagsDB.recipes[character][profession] = { [itemID] = recipes using it }
local function recipeDB()
    if not WB.db then return nil end
    WB.db.recipes = type(WB.db.recipes) == "table" and WB.db.recipes or {}
    return WB.db.recipes
end

local function idOf(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- What the open profession window lists, as { [itemID] = count } and the
-- profession's name. Nothing when the window shows somebody else's.
local function readOpenProfession()
    local used = {}
    local TS = rawget(_G, "C_TradeSkillUI")
    if TS and TS.GetAllRecipeIDs and TS.GetRecipeSchematic then
        if TS.IsTradeSkillLinked and TS.IsTradeSkillLinked() then return nil end
        if TS.IsTradeSkillGuild and TS.IsTradeSkillGuild() then return nil end
        local base = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
        local prof = base and plain(base.professionName)
        for _, id in ipairs(TS.GetAllRecipeIDs() or {}) do
            local info = TS.GetRecipeInfo and TS.GetRecipeInfo(id)
            if info and info.learned then
                local sch = TS.GetRecipeSchematic(id, false)
                for _, slot in ipairs(sch and sch.reagentSlotSchematics or {}) do
                    if slot.required ~= false then
                        for _, r in ipairs(slot.reagents or {}) do
                            if r.itemID then used[r.itemID] = (used[r.itemID] or 0) + 1 end
                        end
                    end
                end
            end
        end
        return prof, used
    end
    if rawget(_G, "GetNumTradeSkills") and rawget(_G, "GetTradeSkillReagentItemLink") then
        if rawget(_G, "IsTradeSkillLinked") and IsTradeSkillLinked() then return nil end
        local prof = plain((GetTradeSkillLine()))
        for i = 1, GetNumTradeSkills() or 0 do
            local _, kind = GetTradeSkillInfo(i)
            if kind ~= "header" then
                for r = 1, (GetTradeSkillNumReagents(i) or 0) do
                    local id = idOf(GetTradeSkillReagentItemLink(i, r))
                    if id then used[id] = (used[id] or 0) + 1 end
                end
            end
        end
        return prof, used
    end
    return nil
end

-- Enchanting on the older client has a window and calls of its own.
local function readOpenCraft()
    if not (rawget(_G, "GetNumCrafts") and rawget(_G, "GetCraftReagentItemLink")) then return nil end
    local used = {}
    local prof = rawget(_G, "GetCraftDisplaySkillLine") and plain((GetCraftDisplaySkillLine())) or nil
    for i = 1, GetNumCrafts() or 0 do
        local _, _, kind = GetCraftInfo(i)
        if kind ~= "header" then
            for r = 1, (GetCraftNumReagents(i) or 0) do
                local id = idOf(GetCraftReagentItemLink(i, r))
                if id then used[id] = (used[id] or 0) + 1 end
            end
        end
    end
    return prof, used
end

local function keep(reader)
    if InCombatLockdown and InCombatLockdown() then return false end
    local ok, prof, used = pcall(reader)
    if not ok or type(prof) ~= "string" or prof == "" or type(used) ~= "table" or next(used) == nil then return false end
    local db = recipeDB()
    if not db then return false end
    local mine = me()
    db[mine] = type(db[mine]) == "table" and db[mine] or {}
    db[mine][prof] = used
    return true
end

-- ============================================================
-- The answer
-- ============================================================
local function itemName(itemID)
    local CI = rawget(_G, "C_Item")
    local name = (CI and CI.GetItemNameByID and CI.GetItemNameByID(itemID))
        or (rawget(_G, "GetItemInfo") and (GetItemInfo(itemID)))
    name = plain(name)
    return type(name) == "string" and name:lower() or nil
end

-- Who wants this item: a list of lines, empty when nobody does.
function N:Reasons(itemID)
    local out = {}
    if not itemID then return out end
    refreshQuests()
    local name = itemName(itemID)
    local q = name and quests[name]
    if q then
        if q.have and q.need then
            out[#out + 1] = ("Quest: %s (%d/%d)"):format(q.title, q.have, q.need)
        else
            out[#out + 1] = ("Quest: %s"):format(q.title)
        end
    end
    local mine = me()
    local alts = {}
    for who, profs in pairs(recipeDB() or {}) do
        if type(profs) == "table" then
            for prof, used in pairs(profs) do
                local n = type(used) == "table" and used[itemID]
                if n then
                    if who == mine then
                        out[#out + 1] = ("%s: %d of your recipes"):format(prof, n)
                    else
                        alts[#alts + 1] = ("%s's %s"):format(who, prof)
                    end
                end
            end
        end
    end
    table.sort(alts)
    for _, line in ipairs(alts) do out[#out + 1] = line end
    return out
end

-- Asked for every slot on every refresh, so it does no formatting.
function N:IsNeeded(itemID)
    if not itemID or not on() then return false end
    refreshQuests()
    local name = itemName(itemID)
    if name and quests[name] then return true end
    for _, profs in pairs(recipeDB() or {}) do
        if type(profs) == "table" then
            for _, used in pairs(profs) do
                if type(used) == "table" and used[itemID] then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- The mark on a slot
-- ============================================================
-- A small square in the slot's top left corner, in the look's accent.
function N:Mark(slot, itemID)
    if not slot then return end
    local want = itemID and self:IsNeeded(itemID) or false
    if not want then
        if slot._needMark then slot._needMark:Hide() end
        return
    end
    if not slot._needMark then
        local t = slot:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetSize(6, 6)
        t:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
        slot._needMark = t
    end
    local c = WickCore.Chrome.Colors.fel
    slot._needMark:SetColorTexture(c[1], c[2], c[3], 1)
    slot._needMark:Show()
end

-- ============================================================
-- The tooltip
-- ============================================================
local function decorate(tooltip, itemID)
    if not itemID or not on() then return end
    local ok, reasons = pcall(N.Reasons, N, itemID)
    if not ok or #reasons == 0 then return end
    local c = WickCore.Chrome.Colors.fel
    tooltip:AddLine(" ")
    tooltip:AddLine("Still needed", c[1], c[2], c[3])
    for _, line in ipairs(reasons) do
        tooltip:AddLine(line, 0.83, 0.78, 0.63)
    end
end
N.Decorate = decorate

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        decorate(tooltip, data and plain(data.id))
    end)
elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tt)
        local _, link = tt:GetItem()
        decorate(tt, idOf(link))
    end)
end

-- ============================================================
-- Events
-- ============================================================
local function redraw()
    if WB.Emit then WB:Emit("BAGS_DIRTY") end
end

local pending = {}
local function later(kind, fn)
    if pending[kind] or not C_Timer then return end
    pending[kind] = true
    C_Timer.After(0.5, function() pending[kind] = nil; fn() end)
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "TRADE_SKILL_SHOW",
                      "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "CRAFT_SHOW", "CRAFT_UPDATE" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event)
    if event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        questsDirty = true
        -- The log fires in bursts; one read after it settles, and the bags
        -- are only redrawn when what it wants has changed.
        later("quests", function() if refreshQuests() and on() then redraw() end end)
    elseif event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
        later("craft", function() if keep(readOpenCraft) and on() then redraw() end end)
    else
        later("trade", function() if keep(readOpenProfession) and on() then redraw() end end)
    end
end)
