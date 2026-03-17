
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
        quote    = "note",
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
        quote    = "tip",
        details  = "",
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

local function makeQuote(quote, details, summary, content)
    return pandoc.Div(
        pandoc.Div(
            content, {class = "details", title = summary, opt = details}
        ), {class = quote}
    )
end


if FORMAT:match 'latex' then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs: wrap content in "details" div, use "fontsize" as option for LaTeX
        if divs[env] then
            local defs = divs[env]
            return makeQuote(defs.quote, defs.fontsize, defs.summary, el.content)
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

if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs: wrap content in "details" div, use "details" ("open" vs. "") as option for GitHub/Docsify
        if divs[env] then
            local defs = divs[env]
            return makeQuote(defs.quote, defs.details, defs.icon .. " " .. defs.summary, el.content)
        end
    end
end
