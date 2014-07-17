local _, Simulationcraft = ...
LibStub("AceAddon-3.0"):NewAddon(Simulationcraft, "Simulationcraft", "AceEvent-3.0",  "AceConsole-3.0")

function Simulationcraft:CreateDefaults()

    local defaults = {
        profile = {
            newStyle = true,
        }
    }

    return defaults 
end