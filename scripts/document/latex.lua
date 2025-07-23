-- "Template" for Beamer and PDF

--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- TL;DR and Videos (PDF)
    if FORMAT:match 'latex' then
        if doc.meta.tldr or doc.meta.youtube or doc.meta.attachments then
            local quote = pandoc.List()

            quote:insert(pandoc.RawBlock('latex', '\\begin{important-box}'))
            quote:insert(pandoc.RawBlock('latex', '\\small'))

            if doc.meta.tldr then
                quote:insert(pandoc.Plain(pandoc.Strong("TL;DR")))
                quote:extend(doc.meta.tldr)
            end

            if doc.meta.youtube then
                local bullets = pandoc.List()
                for _, v in ipairs(doc.meta.youtube) do
                    local str_link = pandoc.utils.stringify(v.link)
                    bullets:insert(pandoc.Link(v.name or str_link, str_link))
                end
                quote:insert(pandoc.Plain(pandoc.Strong("Videos")))
                quote:insert(pandoc.BulletList(bullets))
            end

            if doc.meta.attachments then
                local bullets = pandoc.List()
                for _, v in ipairs(doc.meta.attachments) do
                    local str_link = pandoc.utils.stringify(v.link)
                    bullets:insert(pandoc.Link(v.name or str_link, str_link))
                end
                quote:insert(pandoc.Plain(pandoc.Strong("Unterlagen")))
                quote:insert(pandoc.BulletList(bullets))
            end

            quote:insert(pandoc.RawBlock('latex', '\\end{important-box}'))
            quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

            blocks:extend(quote)
            blocks:insert(pandoc.HorizontalRule())
        end
    end

    -- Main Doc (do not shift headings level - take this document as is)
    blocks:extend(doc.blocks)

    -- Literature (PDF)
    if FORMAT:match 'latex' then
        if doc.meta.readings then
            -- assuming top-level heading: h1, shifting: none
            blocks:insert(pandoc.Header(1, "Zum Nachlesen"))
            blocks:insert(pandoc.BulletList(
                doc.meta.readings:map(function(e) return pandoc.Span(e) end)
            ))
        end
    end

    -- Outcomes, Quizzes, and Challenges (PDF)
    if FORMAT:match 'latex' then
        if doc.meta.outcomes or doc.meta.quizzes or doc.meta.challenges then
            local quote = pandoc.List()

            quote:insert(pandoc.RawBlock('latex', '\\small'))

            if doc.meta.outcomes then
                local bullets = pandoc.List()
                for _, e in ipairs(doc.meta.outcomes) do
                    for k, v in pairs(e) do
                        bullets:insert(pandoc.Str(k .. ": " .. pandoc.utils.stringify(v)))
                    end
                end
                quote:insert(pandoc.RawBlock('latex', '\\begin{tip-box}'))
                quote:insert(pandoc.Plain(pandoc.Strong("Lernziele")))
                quote:insert(pandoc.BulletList(bullets))
                quote:insert(pandoc.RawBlock('latex', '\\end{tip-box}'))
            end

            if doc.meta.quizzes then
                local bullets = pandoc.List()
                for _, v in ipairs(doc.meta.quizzes) do
                    local str_link = pandoc.utils.stringify(v.link)
                    bullets:insert(pandoc.Link(v.name or str_link, str_link))
                end
                quote:insert(pandoc.RawBlock('latex', '\\begin{tip-box}'))
                quote:insert(pandoc.Plain(pandoc.Strong("Quizzes")))
                quote:insert(pandoc.BulletList(bullets))
                quote:insert(pandoc.RawBlock('latex', '\\end{tip-box}'))
            end

            if doc.meta.challenges then
                quote:insert(pandoc.RawBlock('latex', '\\begin{tip-box}'))
                quote:insert(pandoc.Plain(pandoc.Strong("Challenges")))
                quote:extend(doc.meta.challenges)
                quote:insert(pandoc.RawBlock('latex', '\\end{tip-box}'))
            end

            quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

            blocks:insert(pandoc.HorizontalRule())
            blocks:extend(quote)
        end
    end

    -- References (PDF)
    if FORMAT:match 'latex' then
        local refs = pandoc.utils.references(doc)
        if refs and #refs > 0 then
            local quote = pandoc.List()

            quote:insert(pandoc.RawBlock('latex', '\\small'))
            quote:insert(pandoc.RawBlock('latex', '\\begin{info-box}'))

            quote:insert(pandoc.Plain(pandoc.Strong("Quellen")))
            quote:extend(doc.meta.refs)

            quote:insert(pandoc.RawBlock('latex', '\\end{info-box}'))
            quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

            blocks:insert(pandoc.HorizontalRule())
            blocks:extend(quote)
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
