-- "Template" for Beamer and PDF

-- Custom divs to be handled ('readings' is different)
local divs = {
    tldr = {
        quote   = "important",
        details = "small",
        summary = "TL;DR"
    },
    youtube = {
        quote   = "tip",
        details = "small",
        summary = "Videos"
    },
    attachments = {
        quote   = "note",
        details = "small",
        summary = "Weitere Unterlagen"
    },
    outcomes = {
        quote   = "note",
        details = "small",
        summary = "Lernziele"
    },
    quizzes = {
        quote   = "tip",
        details = "small",
        summary = "Quizzes"
    },
    challenges = {
        quote   = "tip",
        details = "small",
        summary = "Challenges"
    }
}

local function makeQuote(quote, details, summary, content)
    return pandoc.Div(
        pandoc.Div(
            content, {class = "details", title = summary, fontsize = details}
        ), {class = quote}
    )
end


function Div(el)
    local env = el.classes[1]

    -- handle custom divs
    if divs[env] then
        if FORMAT:match 'latex' then
            -- wrap content in "details" div
            local defs = divs[env]
            return makeQuote(defs.quote, defs.details, defs.summary, el.content)
        end
        if FORMAT:match 'beamer' then
            return {}
        end
    end

    -- handle 'readings' separately
    if env == "readings" then
        if FORMAT:match 'latex' then
            -- assuming top-level heading: h1, shifting: +1
            return { pandoc.Header(1, 'Zum Nachlesen') } .. el.content
        end
        if FORMAT:match 'beamer' then
            return {}
        end
    end
end


--- Rework the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- Main Doc
    blocks:extend(doc.blocks)

    -- References (PDF)
    if FORMAT:match 'latex' then
        local refs = pandoc.utils.references(doc)
        if refs and #refs > 0 then
            blocks:insert(pandoc.HorizontalRule())
            blocks:insert(makeQuote("note", "small", "Quellen", doc.meta.refs))
        end
    end

    -- License (and exceptions)
    if doc.meta.license_footer and (not doc.meta.has_license) then
        if FORMAT:match 'beamer' then
            blocks:insert(pandoc.HorizontalRule())      -- triggers a new slide
        end

        blocks:insert(pandoc.RawBlock('latex', '\\newpage'))
        blocks:insert(pandoc.RawBlock('latex', '\\vspace*{\\fill}'))
        blocks:extend(doc.meta.license_footer)
        blocks:insert(pandoc.Div('EXCEPTIONS', {class = 'exceptions'}))  -- marker for origin-filter
    end

    -- Last modified (`git log -n 1 --pretty=reference -- $<`)
    if doc.meta.lastmod then
        if FORMAT:match 'beamer' then
            blocks:insert(pandoc.HorizontalRule())      -- triggers a new slide: we do not want to have this in our screencasts
            blocks:insert(pandoc.RawBlock('latex', '\\vskip0pt plus 1filll'))
        end
        if FORMAT:match 'latex' then
            blocks:insert(pandoc.RawBlock('latex', '\\bigskip'))
        end

        blocks:insert(pandoc.RawBlock('latex', '\\scriptsize'))
        blocks:insert(pandoc.BlockQuote(pandoc.Plain({pandoc.Strong('Last modified:'), pandoc.Str(" "), doc.meta.lastmod})))
        blocks:insert(pandoc.RawBlock('latex', '\\normalsize'))

        if FORMAT:match 'latex' then
            -- add commit sha in footer
            -- lastmod: "0de6bd3 (commit message, 2025-04-23)"
            local _, _, commit = string.find(doc.meta.lastmod, "(%w+)%s%(.+%)")
            doc.meta["footer-left"] = commit
        end
    end

    -- Change numbering style to eg. `slide_numbering: fraction` if present in documents YAML header (default: "none")
    -- this is hacky: for this to work all beamer settings in beamer.yaml need to be "metadata" instead of "variables"
    if FORMAT:match 'beamer' then
        local slide_numbering = { "numbering=" .. (doc.meta.slide_numbering and pandoc.utils.stringify(doc.meta.slide_numbering) or "none") }
        doc.meta.themeoptions = doc.meta.themeoptions and (doc.meta.themeoptions .. slide_numbering) or slide_numbering
    end


    -- Finé
    return pandoc.Pandoc(blocks, doc.meta)
end
