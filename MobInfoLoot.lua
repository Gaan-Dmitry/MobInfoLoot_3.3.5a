-- Стартовое сообщение при входе в мир
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("PLAYER_LOGIN")
EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        print("|cFF00FF00[MobInfoLoot]|r загружен! Выделите цель и нажмите |cFFFFFF00Shift + ЛКМ|r по ее портрету.")
    end
end)

local lootButtons = {}
local scrollChild = MobInfoLootFrameScrollFrameScrollChild -- Ссылка на контейнер прокрутки

if not MobInfoLootFrame.noLootText then
    MobInfoLootFrame.noLootText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    MobInfoLootFrame.noLootText:SetPoint("TOPLEFT", 5, -5)
end

local function ClearLootButtons()
    for i = 1, #lootButtons do
        lootButtons[i]:Hide()
    end
    MobInfoLootFrame.noLootText:Hide()
    scrollChild:SetHeight(10)
end

local function RefreshButton(btn)
    if not btn.itemID then return end
    
    local itemName, itemLink, _, _, _, _, _, _, _, itemTexture = GetItemInfo(btn.itemID)
    
    if itemName then
        btn.icon:SetTexture(itemTexture)
        btn.text:SetText(btn.chance .. "% - " .. itemLink)
    else
        btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        btn.text:SetText(btn.chance .. "% - Неизвестно (Нажми для загрузки)")
    end
end

MobInfoLootFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
MobInfoLootFrame:SetScript("OnEvent", function(self, event, itemID)
    for i = 1, #lootButtons do
        if lootButtons[i]:IsVisible() and lootButtons[i].itemID == itemID then
            RefreshButton(lootButtons[i])
        end
    end
end)

TargetFrame:HookScript("OnMouseDown", function(self, button)
    -- Изменено на Shift + ЛКМ
    if button == "LeftButton" and IsShiftKeyDown() then
        local unit = self.unit
        local npc_name = UnitName(unit)
        
        if npc_name and not UnitIsPlayer(unit) then
            MobInfoLootFrame:Show()
            MobInfoLootFrameTitle:SetText("Лут: " .. npc_name)
            ClearLootButtons()
            
            local guid = UnitGUID(unit)
            if not guid then return end
            local npc_id = tonumber(guid:sub(9, 12), 16)
            
            local lootData = AtlasLoot_Data and AtlasLoot_Data["NPC_"..tostring(npc_id)]
            
            if lootData then
                local totalHeight = 0
                
                for i, item in ipairs(lootData) do
                    local btn = lootButtons[i]
                    if not btn then
                        -- Создаем кнопку внутри scrollChild
                        btn = CreateFrame("Button", "MobInfoLootBtn"..i, scrollChild)
                        btn:SetSize(320, 20)
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
                            GameTooltip:Show()
                        end)
                        
                        btn:SetScript("OnLeave", function(self)
                            GameTooltip:Hide()
                        end)
                        
                        btn:SetScript("OnClick", function(self)
                            local _, link = GetItemInfo(self.itemID)
                            if link then
                                -- Стандартная функция WoW для отправки в чат и примерочную
                                HandleModifiedItemClick(link)
                            else
                                -- Если предмета нет в кэше, клик принудительно запрашивает его
                                GameTooltip:SetHyperlink("item:" .. self.itemID .. ":0:0:0:0:0:0:0")
                                RefreshButton(self)
                            end
                        end)
                        
                        lootButtons[i] = btn
                    end
                    
                    btn.itemID = item[1]
                    btn.chance = item[2]
                    btn:Show()
                    
                    RefreshButton(btn)
                    
                    -- Увеличиваем общую высоту контейнера прокрутки
                    totalHeight = totalHeight + 22
                end
                
                -- Задаем итоговую высоту внутреннего фрейма, чтобы ползунок понял, сколько нужно скроллить
                scrollChild:SetHeight(totalHeight + 10)
            else
                MobInfoLootFrame.noLootText:SetText("Лут не найден (ID: " .. tostring(npc_id) .. ")")
                MobInfoLootFrame.noLootText:Show()
                scrollChild:SetHeight(30)
            end
        end
    end
end)