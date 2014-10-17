local _, Simulationcraft = ...


local L = LibStub("AceLocale-3.0"):GetLocale("Simulationcraft")

function Simulationcraft:CreateOptions()

    local options = {
        type = "group",
        name = "Simulationcraft",
        args = {
            opt1 = {
                order = 2,
                name = L["This checkbox does nothing."],
                desc = L["Option1desc"],
                type = "toggle",
                width = "full",
                set = function(info,val) self.db.profile.opt1 = val end,
                get = function(info) return self.db.profile.opt1 end
            }      
        }
    }

    return options
end
