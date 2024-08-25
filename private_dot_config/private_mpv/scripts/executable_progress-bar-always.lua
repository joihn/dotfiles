
local mp = require 'mp'

local function show_progress()
    mp.command("show-progress")
end

mp.register_event("file-loaded", show_progress)
mp.add_periodic_timer(1, show_progress)

-- Force the progress bar to stay visible
mp.observe_property("osd-level", "number", function(name, value)
    if value < 1 then
        mp.set_property("osd-level", "1")
    end
end)
