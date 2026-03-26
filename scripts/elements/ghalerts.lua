-- GitHub Alerts: replace alert Divs with "real" GH alerts

-- GH Alerts to be handled
local alerts = {
    note = {
        tex = "info-box",
        md  = "Note",
    },
    tip = {
        tex = "tip-box",
        md  = "Tip",
    },
    important = {
        tex = "important-box",
        md  = "Important",
    },
    warning = {
        tex = "warning-box",
        md  = "Warning",
    },
    caution = {
        tex = "error-box",
        md  = "Caution",
    },
}


local function _is_genuine_ghalert(c)
    -- TODO fix me: recognition of genuine GH alerts is quite hacky: the first div in content would be a title div
    return c and #c > 1 and c[1].t == "Div" and c[1].classes and c[1].classes[1] == "title"
end


function Div(el)
    local type = el.classes[1]

    if alerts[type] then
        local c = el.content

        if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
            if _is_genuine_ghalert(c) then
                c:remove(1) -- remove title div from original ghalert
            end
            local title = el.attributes["title"] and ("[" .. el.attributes["title"] .. "]") or ""
            local box = alerts[type].tex
            return {
                pandoc.RawBlock('latex', '\\begin{' .. box ..'}' .. title),
                pandoc.Div(c),
                pandoc.RawBlock('latex', '\\end{' .. box .. '}')
            }
        end

        if FORMAT:match 'markdown' then
            -- do not touch genuine GH alerts
            if not _is_genuine_ghalert(c) then
                -- emit proper gh alert
                -- TODO workaround: the markdown writer would not recognize the gh-alert properly if there isn't plain text at the beginning (see https://github.com/jgm/pandoc/issues/11533)
                el.content = { pandoc.Div(alerts[type].md, {class='title'}), pandoc.Para(pandoc.Str("")) } .. c
                return el
            end
        end
        
    end
end
