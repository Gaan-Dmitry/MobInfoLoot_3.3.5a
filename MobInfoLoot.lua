------------------------------------------------------------------
-- MobInfoLoot 2.0
------------------------------------------------------------------

-- SavedVariables
MobInfoLootDB = MobInfoLootDB or { itemCache = {}, search = "", sortBy = "chance", filterLow = false }

local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        print("|cFF00FF00[MobInfoLoot]|r загружен! Shift + ЛКМ по портрету цели, либо |cFFFFFF00/mil|r.")
        tinsert(UISpecialFrames, "MobInfoLootFrame")
        MobInfoLootFrameSearchBox:SetText(MobInfoLootDB.search or "")
    end
end)

SLASH_MOBINFOLOOT1 = "/mil"
SlashCmdList["MOBINFOLOOT"] = function()
    if MobInfoLootFrame:IsVisible() then
        MobInfoLootFrame:Hide()
    else
        MobInfoLootFrame:Show()
    end
end

------------------------------------------------------------------
-- Локальные ссылки
------------------------------------------------------------------
local F       = MobInfoLootFrame
local SChild  = MobInfoLootFrameScrollFrameScrollChild
local Search  = MobInfoLootFrameSearchBox
local BtnSortChance = MobInfoLootFrameSortChance
local BtnSortName   = MobInfoLootFrameSortName
local BtnFilterLow  = MobInfoLootFrameFilterLow

local lootButtons = {}
local currentLoot = nil    -- сырой список лута текущего моба
local currentNPC  = nil    -- id текущего моба

if not F.noLootText then
    F.noLootText = SChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    F.noLootText:SetPoint("TOPLEFT", 5, -5)
    F.noLootText:SetJustifyH("LEFT")
end

------------------------------------------------------------------
-- Источник лута -> короткая метка
------------------------------------------------------------------
local SOURCE_LABEL = {
    kill       = "|cffff5555[K]|r",
    pickpocket = "|cffffff55[P]|r",
    skinning   = "|cff55ff55[S]|r",
}
local SOURCE_NAME = {
    kill       = "Убийство",
    pickpocket = "Кража",
    skinning   = "Снятие шкуры",
}

------------------------------------------------------------------
-- Кэш имён предметов из SavedVariables (2.6)
------------------------------------------------------------------
local function GetCachedItemName(itemID)
    return MobInfoLootDB.itemCache[itemID]
end
local function SetCachedItemName(itemID, name, link, texture, quality)
    MobInfoLootDB.itemCache[itemID] = { name = name, link = link, texture = texture, quality = quality }
end

------------------------------------------------------------------
-- Обновление одной кнопки
------------------------------------------------------------------
local function RefreshButton(btn)
    if not btn or not btn.itemID then return end

    local itemName, itemLink, quality, _, _, _, _, _, _, itemTexture = GetItemInfo(btn.itemID)
    if itemName then
        SetCachedItemName(btn.itemID, itemName, itemLink, itemTexture, quality)
    else
        -- fallback в SavedVariables
        local cached = GetCachedItemName(btn.itemID)
        if cached then
            itemName, itemLink, itemTexture, quality = cached.name, cached.link, cached.texture, cached.quality
        end
    end

    local srcLabel = SOURCE_LABEL[btn.source] or ""
    local qColor = "|cffffffff"
    if quality == 0 then qColor = "|cff9d9d9d"
    elseif quality == 1 then qColor = "|cffffffff"
    elseif quality == 2 then qColor = "|cff1eff00"
    elseif quality == 3 then qColor = "|cff0070dd"
    elseif quality == 4 then qColor = "|cffa335ee"
    elseif quality == 5 then qColor = "|cffff8000"
    end

    if itemName and itemLink then
        btn.icon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.text:SetText(string.format("%s %s%.2f%%|r - %s", srcLabel, qColor, btn.chance, itemLink))
        btn.isPending = nil
    else
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.text:SetText(string.format("%s |cff808080%.2f%% - Неизвестно (клик для загрузки)|r", srcLabel, btn.chance))
        btn.isPending = true
    end
end

------------------------------------------------------------------
-- Поллинг "висящих" кнопок (гарантированное обновление)
------------------------------------------------------------------
local poller = CreateFrame("Frame")
poller.elapsed = 0
poller:SetScript("OnUpdate", function(self, dt)
    if not F:IsVisible() then return end
    self.elapsed = self.elapsed + dt
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    for i = 1, #lootButtons do
        local btn = lootButtons[i]
        if btn and btn:IsVisible() and btn.isPending then
            RefreshButton(btn)
        end
    end
end)

-- Быстрое обновление, если ответ пришёл вовремя
F:RegisterEvent("ITEM_QUERY_SINGLE_RESPONSE")
F:SetScript("OnEvent", function(self, event, itemID)
    if event ~= "ITEM_QUERY_SINGLE_RESPONSE" then return end
    if not F:IsVisible() then return end
    for i = 1, #lootButtons do
        local btn = lootButtons[i]
        if btn and btn:IsVisible() and btn.itemID == itemID then
            RefreshButton(btn)
        end
    end
end)

------------------------------------------------------------------
-- Очистка списка
------------------------------------------------------------------
local function ClearLootButtons()
    for i = 1, #lootButtons do
        lootButtons[i]:Hide()
        lootButtons[i].isPending = nil
    end
    F.noLootText:Hide()
    SChild:SetHeight(10)
end

------------------------------------------------------------------
-- Сортировка и фильтрация (2.3)
------------------------------------------------------------------
local function ApplySortAndFilter(data)
    local out = {}
    for _, entry in ipairs(data) do
        local itemID, chance, source = entry[1], entry[2], entry[3]
        if not MobInfoLootDB.filterLow or chance >= 1 then
            out[#out+1] = { itemID, chance, source }
        end
    end

    if MobInfoLootDB.sortBy == "chance" then
        table.sort(out, function(a, b) return a[2] > b[2] end)
    elseif MobInfoLootDB.sortBy == "name" then
        table.sort(out, function(a, b)
            local an = (GetItemInfo(a[1]) or GetCachedItemName(a[1]) and GetCachedItemName(a[1]).name) or ""
            local bn = (GetItemInfo(b[1]) or GetCachedItemName(b[1]) and GetCachedItemName(b[1]).name) or ""
            return an < bn
        end)
    end
    return out
end

------------------------------------------------------------------
-- Основная функция отрисовки списка лута
------------------------------------------------------------------
local function RenderLoot(npcID)
    ClearLootButtons()

    local lootData = AtlasLoot_Data and AtlasLoot_Data["NPC_"..tostring(npcID)]
    if not lootData then
        F.noLootText:SetText("Лут не найден (ID: " .. tostring(npcID) .. ")")
        F.noLootText:Show()
        SChild:SetHeight(30)
        return
    end

    local items = ApplySortAndFilter(lootData)
    if #items == 0 then
        F.noLootText:SetText("Нет предметов по текущему фильтру.")
        F.noLootText:Show()
        SChild:SetHeight(30)
        return
    end

    local totalHeight = 0
    for i, item in ipairs(items) do
        local itemID, chance, source = item[1], item[2], item[3]

        local btn = lootButtons[i]
        if not btn then
            btn = CreateFrame("Button", "MobInfoLootBtn"..i, SChild)
            btn:SetSize(350, 20)
            btn:SetPoint("TOPLEFT", 5, -5 - ((i - 1) * 22))

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            hl:SetBlendMode("ADD")

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", 0, 0)
            btn.icon = icon

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            text:SetJustifyH("LEFT")
            btn.text = text

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. self.itemID .. ":0:0:0:0:0:0:0")
                if self.source then
                    GameTooltip:AddLine("Источник: " .. (SOURCE_NAME[self.source] or self.source), 0.7, 0.7, 1)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            btn:SetScript("OnClick", function(self)
                local _, link = GetItemInfo(self.itemID)
                if link then
                    HandleModifiedItemClick(link)
                else
                    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                    GameTooltip:SetHyperlink("item:" .. self.itemID .. ":0:0:0:0:0:0:0")
                    GameTooltip:Hide()
                    self.isPending = true
                end
            end)

            lootButtons[i] = btn
        end

        btn.itemID  = itemID
        btn.chance  = chance
        btn.source  = source
        btn:Show()
        RefreshButton(btn)
        totalHeight = totalHeight + 22
    end

    SChild:SetHeight(totalHeight + 10)
end

------------------------------------------------------------------
-- Открытие окна по таргету
------------------------------------------------------------------
local function ShowLootForTarget()
    local unit = "target"
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end

    local npc_name = UnitName(unit)
    local guid = UnitGUID(unit)
    if not npc_name or not guid then return end

    local npc_id = tonumber(guid:sub(9, 12), 16)
    if not npc_id then return end

    F:Show()
    MobInfoLootFrameTitle:SetText("Лут: " .. npc_name .. " (ID " .. npc_id .. ")")
    currentNPC = npc_id
    currentLoot = AtlasLoot_Data and AtlasLoot_Data["NPC_"..npc_id]
    RenderLoot(npc_id)
end

TargetFrame:HookScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        ShowLootForTarget()
    end
end)

------------------------------------------------------------------
-- Кнопки сортировки / фильтра
------------------------------------------------------------------
local function RefreshSortButtons()
    if MobInfoLootDB.sortBy == "chance" then
        BtnSortChance:SetText("Шанс ▼")
        BtnSortName:SetText("Имя")
    else
        BtnSortChance:SetText("Шанс")
        BtnSortName:SetText("Имя ▼")
    end
    if MobInfoLootDB.filterLow then
        BtnFilterLow:SetText("Показ <1%")
    else
        BtnFilterLow:SetText("Скрыть <1%")
    end
end

BtnSortChance:SetScript("OnClick", function()
    MobInfoLootDB.sortBy = "chance"
    RefreshSortButtons()
    if currentNPC then RenderLoot(currentNPC) end
end)

BtnSortName:SetScript("OnClick", function()
    MobInfoLootDB.sortBy = "name"
    RefreshSortButtons()
    if currentNPC then RenderLoot(currentNPC) end
end)

BtnFilterLow:SetScript("OnClick", function()
    MobInfoLootDB.filterLow = not MobInfoLootDB.filterLow
    RefreshSortButtons()
    if currentNPC then RenderLoot(currentNPC) end
end)

------------------------------------------------------------------
-- Поиск по имени моба / ID (2.2) и обратный поиск по предмету (2.4)
------------------------------------------------------------------
local function SearchNPCByName(query)
    query = strlower(query)
    if query == "" then return nil end

    -- Если это число — сразу как ID
    local asNum = tonumber(query)
    if asNum and AtlasLoot_Names[asNum] then
        return asNum
    end

    -- Иначе — ищем по вхождению подстроки
    for npcID, name in pairs(AtlasLoot_Names) do
        if strfind(strlower(name), query, 1, true) then
            return npcID
        end
    end
    return nil
end

local function SearchItemByName(query)
    query = strlower(query)
    if query == "" then return nil end

    -- 2.4: проходим по кэшу предметов, ищем совпадение по имени
    for itemID, info in pairs(MobInfoLootDB.itemCache) do
        if info.name and strfind(strlower(info.name), query, 1, true) then
            return itemID
        end
    end
    return nil
end

Search:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    MobInfoLootDB.search = text
    self:ClearFocus()

    if text == "" then return end

    -- Пытаемся как ID моба
    local npcID = SearchNPCByName(text)
    if npcID then
        local name = AtlasLoot_Names[npcID] or ("ID "..npcID)
        MobInfoLootFrameTitle:SetText("Лут: " .. name .. " (ID " .. npcID .. ")")
        currentNPC = npcID
        RenderLoot(npcID)
        return
    end

    -- Пытаемся как ID предмета (обратный поиск)
    local itemID = tonumber(text)
    if itemID and GetItemInfo(itemID) then
        -- показать всех мобов, у которых он есть
        local list = {}
        for npcID, items in pairs(AtlasLoot_Data) do
            local id = tonumber(npcID:sub(5))
            for _, entry in ipairs(items) do
                if entry[1] == itemID then
                    list[#list+1] = { id, entry[2], entry[3] }
                end
            end
        end
        -- Сортируем по шансу
        table.sort(list, function(a,b) return a[2] > b[2] end)
        -- Отрисовываем как псевдо-лут
        ClearLootButtons()
        F.noLootText:SetText("Мобы, с которых падает предмет #"..itemID..":")
        F.noLootText:Show()
        local y = -25
        for i, row in ipairs(list) do
            if i > 40 then break end -- ограничение
            local btn = lootButtons[i]
            if not btn then
                btn = CreateFrame("Button", "MobInfoLootBtn"..i, SChild)
                btn:SetSize(350, 20)
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(18,18)
                btn.icon:SetPoint("LEFT", 0, 0)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
                btn:SetScript("OnClick", function(self)
                    if self.npcID then
                        local nm = AtlasLoot_Names[self.npcID] or ("ID "..self.npcID)
                        MobInfoLootFrameTitle:SetText("Лут: "..nm.." (ID "..self.npcID..")")
                        currentNPC = self.npcID
                        RenderLoot(self.npcID)
                    end
                end)
                lootButtons[i] = btn
            end
            btn:SetPoint("TOPLEFT", 5, y)
            btn.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
            btn.text:SetText(string.format("%.2f%% - %s (ID %d)", row[2], AtlasLoot_Names[row[1]] or "?", row[1]))
            btn.npcID = row[1]
            btn:Show()
            y = y - 22
        end
        SChild:SetHeight(-y + 10)
        return
    end

    -- Иначе — как имя предмета
    local foundItem = SearchItemByName(text)
    if foundItem then
        Search:SetText(tostring(foundItem))
        Search:GetScript("OnEnterPressed")(Search)
        return
    end

    F.noLootText:SetText("Ничего не найдено по запросу: "..text)
    F.noLootText:Show()
end)

------------------------------------------------------------------
-- Инициализация состояния кнопок
------------------------------------------------------------------
RefreshSortButtons()