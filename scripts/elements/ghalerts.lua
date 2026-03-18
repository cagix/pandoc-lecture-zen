-- GitHub Alerts: replace alert Divs with "real" GH alerts

-- GH Alerts to be handled
local alerts = {
    note = {
        tex  = "info-box",
        gfm  = "Note",
    },
    tip = {
        tex  = "tip-box",
        gfm  = "Tip",
    },
    important = {
        tex  = "important-box",
        gfm  = "Important",
    },
    warning = {
        tex  = "warning-box",
        gfm  = "Warning",
    },
    caution = {
        tex  = "error-box",
        gfm  = "Caution",
    },
}

local function makeAlert(type, content)
    if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
        return {
                pandoc.RawBlock('latex', '\\begin{' .. alerts[type].tex ..'}'),
                pandoc.Div(content),
                pandoc.RawBlock('latex', '\\end{' .. alerts[type].tex .. '}')
            }
    end

    if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
        -- do not touch genuine GH alerts
        -- TODO fix me: recognition of genuine GH alerts is quite hacky
        -- TODO workaround: the markdown writer would not recognize the gh-alert properly if there isn't plain text at the beginning (see https://github.com/jgm/pandoc/issues/11533)
        if not (content and #content > 1 and content[1].t == "Div" and content[1].classes and content[1].classes[1] == "title") then
            return pandoc.Div(
                { pandoc.Div(alerts[type].gfm, {class='title'}), pandoc.Para(pandoc.Str("")) } .. content,
                {class=type}
            )
        end
    end
end


if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Div(el)
        local type = el.classes[1]

        if alerts[type] then
            return makeAlert(type, el.content)
        end
    end
end


if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        local type = el.classes[1]

        -- default: emit proper gh alert
        if alerts[type] then
            return makeAlert(type, el.content)
        end
    end
end
