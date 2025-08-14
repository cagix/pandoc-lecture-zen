
-- Custom divs to be handled ('readings' is different)
local divs = {
    tldr = {
        quote    = "important",
        details  = " open",
        fontsize = "small",
        icon     = "🎯",
        summary  = "TL;DR",
    },
    youtube = {
        quote    = "tip",
        details  = "",
        fontsize = "small",
        icon     = "🎦",
        summary  = "Videos",
    },
    attachments = {
        quote    = "note",
        details  = "",
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

        -- handle custom divs
        if divs[env] then
            -- wrap content in "details" div
            local defs = divs[env]
            return makeQuote(defs.quote, defs.fontsize, defs.summary, el.content)
        end

        -- handle 'readings' separately
        if env == "readings" then
            -- assuming top-level heading: h1, shifting: +1
            return { pandoc.Header(1, 'Zum Nachlesen') } .. el.content
        end
    end
end

if FORMAT:match 'beamer' then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs
        if divs[env] then
            return {}
        end

        -- handle 'readings' separately
        if env == "readings" then
            return {}
        end
    end
end

if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        local env = el.classes[1]

        -- handle custom divs
        if divs[env] then
            -- wrap content in "details" div
            local defs = divs[env]
            return makeQuote(defs.quote, defs.details, defs.icon .. " " .. defs.summary, el.content)
        end

        -- handle 'readings' separately
        if env == "readings" then
            -- assuming top-level heading: h1, shifting: +1
            return { pandoc.Header(1, '📖 Zum Nachlesen') } .. el.content
        end
    end
end
