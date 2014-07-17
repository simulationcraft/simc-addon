local _, Simulationcraft = ...


local L = LibStub("AceLocale-3.0"):GetLocale("Simulationcraft")

function Simulationcraft:CreateOptions()

    local options = {
        type = "group",
        name = "Simulationcraft",
        args = {
            newStyle = {
                order = 2,
                name = L["Use Compact Output"],
                desc = L["UseCompactOutputDescription"],
                type = "toggle",
                width = "full",
                set = function(info,val) self.db.profile.newStyle = val end,
                get = function(info) return self.db.profile.newStyle end
            }      
        }
    }

    return options
end
