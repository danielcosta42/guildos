----------------------------------------------------------------------
-- Guild OS - SelfTest
-- In-client assertion harness for pure/deterministic logic. Cases are
-- registered by modules at Initialize; nothing runs until /gos selftest.
-- Ships tiny; matches the existing /gos debug diagnostic pattern.
----------------------------------------------------------------------
local SelfTest = {}
BRutus.SelfTest = SelfTest

SelfTest.cases = {}

-- fn() must return (okBool, msg). msg is shown only on failure.
function SelfTest:Register(name, fn)
    self.cases[#self.cases + 1] = { name = name, fn = fn }
end

function SelfTest:Run()
    local pass, fail = 0, 0
    for _, c in ipairs(self.cases) do
        local ranOk, ok, msg = pcall(c.fn)
        if not ranOk then
            fail = fail + 1
            BRutus:Print("|cffFF4444ERROR|r " .. c.name .. " — " .. tostring(ok))
        elseif ok then
            pass = pass + 1
        else
            fail = fail + 1
            BRutus:Print("|cffFF4444FAIL|r " .. c.name .. (msg and (" — " .. msg) or ""))
        end
    end
    BRutus:Print(string.format(
        "SelfTest: |cff4CFF4C%d passed|r, %s%d failed|r (%d total)",
        pass, fail > 0 and "|cffFF4444" or "|cff888888", fail, #self.cases))
    return fail == 0
end
