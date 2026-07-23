----------------------------------------------------------------------
-- Guild OS - Level Query
-- Parses an expressive level filter into a predicate. Returns nil when
-- the text isn't a level query (so normal name search still applies).
-- Supports: exact "19", range "60-70", comparisons ">=60" "<=10" ">5" "<70",
-- and comma-lists "19, 60-70, >=68" (OR).
----------------------------------------------------------------------
local LevelQuery = {}
BRutus.LevelQuery = LevelQuery

function LevelQuery:Initialize()
    self:_RegisterTests()
end

function LevelQuery:Parse(query)
    if not query then return nil end
    -- Close up whitespace only AROUND the operators, so ">= 60" and "60 - 70"
    -- still parse while "60 70" stays two tokens. Deleting whitespace outright
    -- welded "60 70" into the valid-but-hopeless exact query "6070", which
    -- returned a predicate (suppressing the text fallback) and matched nobody.
    local q = strtrim((query:gsub("%s*([<>=,%-])%s*", "%1")))
    if q == "" then return nil end
    local preds = {}
    -- Tokens split on comma OR whitespace.
    for token in q:gmatch("[^,%s]+") do
        local op, num = token:match("^([<>]=?)(%d+)$")
        local lo, hi = token:match("^(%d+)%-(%d+)$")
        local exact = token:match("^(%d+)$")
        if op and num then
            num = tonumber(num)
            if op == ">"  then preds[#preds+1] = function(l) return l >  num end
            elseif op == ">=" then preds[#preds+1] = function(l) return l >= num end
            elseif op == "<"  then preds[#preds+1] = function(l) return l <  num end
            elseif op == "<=" then preds[#preds+1] = function(l) return l <= num end end
        elseif lo and hi then
            lo, hi = tonumber(lo), tonumber(hi)
            -- "70-60" is a typo, not an empty set: read it as 60-70 instead of
            -- returning a predicate that can never be true.
            if lo > hi then lo, hi = hi, lo end
            preds[#preds+1] = function(l) return l >= lo and l <= hi end
        elseif exact then
            local n = tonumber(exact)
            preds[#preds+1] = function(l) return l == n end
        else
            return nil     -- any non-level token => not a level query
        end
    end
    if #preds == 0 then return nil end
    return function(level)
        level = level or 0
        for _, p in ipairs(preds) do if p(level) then return true end end
        return false
    end
end

function LevelQuery:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("levelq.range", function()
        local m = LevelQuery:Parse("60-70")
        if not m or not m(65) or m(59) or not m(70) or not m(60) then return false, "range" end
        return true
    end)
    S:Register("levelq.exact_and_list", function()
        local m = LevelQuery:Parse("19, 70")
        if not m or not m(19) or not m(70) or m(50) then return false, "list" end
        return true
    end)
    S:Register("levelq.comparisons", function()
        if not LevelQuery:Parse(">=60")(60) then return false, ">=" end
        if LevelQuery:Parse(">60")(60) then return false, ">" end
        if not LevelQuery:Parse("<10")(9) then return false, "<" end
        return true
    end)
    S:Register("levelq.not_a_query", function()
        if LevelQuery:Parse("Bob") ~= nil then return false, "name => nil" end
        if LevelQuery:Parse("60-x") ~= nil then return false, "mixed => nil" end
        if LevelQuery:Parse("") ~= nil then return false, "empty => nil" end
        -- Anything that is not a level query MUST stay nil so the roster search
        -- falls back to matching names/classes/zones.
        if LevelQuery:Parse("60 warrior") ~= nil then return false, "'60 warrior' => nil" end
        if LevelQuery:Parse("warrior") ~= nil then return false, "'warrior' => nil" end
        return true
    end)
    S:Register("levelq.reversed_range", function()
        local m = LevelQuery:Parse("70-60")
        if not m then return false, "reversed range must still parse" end
        if not m(60) or not m(65) or not m(70) then return false, "inside reversed range" end
        if m(59) or m(71) then return false, "outside reversed range" end
        return true
    end)
    S:Register("levelq.whitespace_tokens", function()
        local m = LevelQuery:Parse("60 70")
        if not m then return false, "'60 70' must parse" end
        if not m(60) or not m(70) or m(65) then return false, "'60 70' is a two-value list" end
        local r = LevelQuery:Parse("60 - 70")
        if not r or not r(65) or r(59) then return false, "spaced range" end
        local g = LevelQuery:Parse(">= 60")
        if not g or not g(60) or g(59) then return false, "spaced operator" end
        return true
    end)
end
