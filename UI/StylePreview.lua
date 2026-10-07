----------------------------------------------------------------------
-- Guild OS - /gos style preview (issue #122; spec §4.6)
-- Every piece of the Forever style's art side by side, each labelled with its role and atlas name,
-- and the ones this client lacks marked: the pieces are chosen from a beta screenshot of it.
----------------------------------------------------------------------
local Style = GuildOS.Style
local L = GuildOS.L

local ROLES = { "window", "titlebar", "panel", "well", "popup", "input",
                "button", "tab", "checkbox", "close", "minimise", "scroll" }

local function has(atlas)
    local get = C_Texture and C_Texture.GetAtlasInfo
    if not get then return false end
    local ok, info = pcall(get, atlas)
    return ok and info ~= nil
end

function Style:PreviewRows()
    local rows = {}
    for _, role in ipairs(ROLES) do
        for _, atlas in ipairs(Style.AtlasNames(self.FOREVER[role])) do
            rows[#rows + 1] = { role = role, atlas = atlas, has = has(atlas) }
        end
    end
    return rows
end

function Style:ShowPreview()
    local UI, C = GuildOS.UI, GuildOS.Colors
    local f = self.previewFrame
    if not f then
        f = UI:CreatePanel(UIParent, "GuildOSStylePreview")
        f:SetSize(720, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        f:SetScript("OnDragStop", function(frame) frame:StopMovingOrSizing() end)
        local title = UI:CreateText(f, L["Style preview"], 13, C.gold.r, C.gold.g, C.gold.b)
        title:SetPoint("TOPLEFT", 12, -10)
        local close = UI:CreateCloseButton(f)
        close:SetPoint("TOPRIGHT", -6, -6)
        close:SetScript("OnClick", function() f:Hide() end)
        local scroll, child = UI:CreateScrollFrame(f, "GuildOSStylePreviewScroll")
        scroll:SetPoint("TOPLEFT", 10, -34)
        scroll:SetPoint("BOTTOMRIGHT", -14, 10)
        child:SetWidth(680)
        local y = 0
        for i, r in ipairs(self:PreviewRows()) do
            local col = (i - 1) % 2
            if col == 0 and i > 1 then y = y + 70 end
            local x = col * 340
            local tex = child:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("TOPLEFT", x, -y)
            tex:SetSize(96, 60)
            if r.has then tex:SetAtlas(r.atlas) else tex:SetColorTexture(0.4, 0, 0, 0.6) end
            local label = UI:CreateText(child, r.role .. "\n" .. r.atlas
                .. (r.has and "" or ("\n|cffFF4444" .. L["missing"] .. "|r")), 9, C.text.r, C.text.g, C.text.b)
            label:SetPoint("TOPLEFT", x + 104, -y)
            label:SetWidth(230)
            label:SetJustifyH("LEFT")
        end
        child:SetHeight(y + 70)
        self.previewFrame = f
    end
    f:Show()
end

-- The Settings rows (issue #122): one per style this client draws, each with its description and an
-- Apply button, or no section at all where there is only one to have. Returns the next y offset.
function Style:BuildPicker(parent, yOff)
    local UI, C = GuildOS.UI, GuildOS.Colors
    local styles = self:Available()
    if #styles < 2 then return yOff end
    local head = UI:CreateText(parent, L["Interface style"], 11, C.gold.r, C.gold.g, C.gold.b)
    head:SetPoint("TOPLEFT", 8, -yOff)
    yOff = yOff + 20
    for _, id in ipairs(styles) do
        local inUse = self:Current() == id
        local name = UI:CreateText(parent, self:Name(id), 12, C.text.r, C.text.g, C.text.b)
        name:SetPoint("TOPLEFT", 16, -yOff)
        local desc = UI:CreateText(parent, self:Description(id), 10, C.label.r, C.label.g, C.label.b)
        desc:SetPoint("TOPLEFT", 16, -(yOff + 16))
        desc:SetWidth(350)   -- wraps short of the button at x = 380
        desc:SetJustifyH("LEFT")
        local apply = UI:CreateButton(parent, inUse and L["In use"] or L["Apply"], 90, 22)
        apply:SetPoint("TOPLEFT", 380, -(yOff + 4))
        if inUse then
            apply:Disable()
        else
            apply:SetScript("OnClick", function() self:Apply(id) end)
        end
        yOff = yOff + 16 + math.max(24, (desc:GetStringHeight() or 12) + 8)
    end
    return yOff + 8
end
