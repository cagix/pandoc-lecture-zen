-- removing internal links (pdf, beamer)

local path = require 'pandoc.path'

-- cache frequently used path & utils functions locally for performance
local path_is_relative = path.is_relative



-- ==========================
-- Utilities
-- ==========================

-- helper function to check for local file
local function _is_local_link (t)
    return t ~= nil
        and t ~= ""
        and path_is_relative(t)
        and not t:lower():match('https?://.*')
end



-- ==========================
-- Filter Entry Point
-- ==========================

function Link(el)
    if _is_local_link(el.target) then
        return el.content
    end
end
