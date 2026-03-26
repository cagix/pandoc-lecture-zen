
-- Custom divs to be handled
local divs = {
    tldr = {
        quote    = "important",
        details  = "open",
        fontsize = "small",
        icon     = "🎯",
        summary  = "TL;DR",
    },
    youtube = {
        quote    = "tip",
        details  = "open",
        fontsize = "small",
        icon     = "🎦",
        summary  = "Videos",
    },
    attachments = {
        quote    = "tip",
        details  = "open",
        fontsize = "small",
        icon     = "🖇",
        summary  = "Weitere Unterlagen",
    },
    outcomes = {
        quote    = "note",
        details  = "",
        fontsize = "small",
        icon     = "✅",
        summary  = "Lernziele",
    },
    quizzes = {
        quote    = "tip",
        details  = "",
        fontsize = "small",
        icon     = "🧩",
        summary  = "Quizzes",
    },
    challenges = {
        quote    = "important",
        details  = "open",
        fontsize = "small",
        icon     = "🏅",
        summary  = "Challenges",
    },
    bibliography = {
        quote    = "note",
        details  = "",
        fontsize = "small",
        icon     = "👀",
        summary  = "Quellen",
    },
    readings = {
        quote    = "tip",
        details  = "open",
        fontsize = "small",
        icon     = "📖",
        summary  = "Zum Nachlesen",
    },
}


if FORMAT:match 'latex' then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs: wrap content in ghalert div
        if divs[env] then
            local defs = divs[env]
            return pandoc.Div(
                el.content, {class = defs.quote, title = defs.summary, opt = defs.fontsize}
            )
        end
    end
end


if FORMAT:match 'beamer' then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs: remove custom divs entirely
        if divs[env] then
            return {}
        end
    end
end


if FORMAT:match 'markdown' then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs: use ghalert and wrap content in "details" div, use "details" ("open" vs. "") as option for GitHub/Docsify
        if divs[env] then
            local defs = divs[env]
            return pandoc.Div(
                pandoc.Div(
                    el.content, {class = "details", title = defs.icon .. " " .. defs.summary, opt = defs.details}
                ), {class = defs.quote}
            )
        end
    end
end
