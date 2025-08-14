-- GitHub Alerts: replace alert Divs with "real" GH alerts

-- GH Alerts to be handled
local alerts = {
    note = {
        tex  = "info-box",
        gfm  = "[!NOTE]",
    },
    tip = {
        tex  = "tip-box",
        gfm  = "[!TIP]",
    },
    important = {
        tex  = "important-box",
        gfm  = "[!IMPORTANT]",
    },
    warning = {
        tex  = "warning-box",
        gfm  = "[!WARNING]",
    },
    caution = {
        tex  = "error-box",
        gfm  = "[!CAUTION]",
    },
}

local function makeAlert(type, content)
    if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
        return {
                pandoc.RawBlock('latex', '\\begin{' .. type ..'}'),
                pandoc.Div(content),
                pandoc.RawBlock('latex', '\\end{' .. type .. '}')
            }
    end

    if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", type)} .. content)
    end
end


if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Div(el)
        local type = el.classes[1]

        if alerts[type] then
            return makeAlert(alerts[type].tex, el.content)
        end
    end
end


if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        local type = el.classes[1]

        -- handle these two alerts differently when generating for docsify
        -- docsify: "important" and "caution" not supported in docsify
        if FORMAT:match 'markdown' then
            if (type == "important") or (type == "caution") then
                io.stderr:write("[WARNING]  [ghalerts.lua]  GitHub alert '" .. type .. "' not supported in docsify (replacing w/ quote)\n")
                return pandoc.BlockQuote(el.content)
            end
        end

        -- default: emit proper gh alert
        if alerts[type] then
            return makeAlert(alerts[type].gfm, el.content)
        end
    end
end
