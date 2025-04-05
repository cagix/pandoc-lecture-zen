-- Collect all 'origin' spans - this is foreign material, i.e. should be listed as exceptions to our licence
credits = {}

function Span(el)
    -- Collect all 'origin' spans - this is foreign material, i.e. should be listed as exceptions to our licence
    if el.classes[1] == "origin" then
        -- use map to avoid duplicates
        -- (when used in images, this would end up in alt text _and_ in caption)
        credits[pandoc.utils.stringify(el.content)] = el.content

        -- add "Quelle: " in front of content
        return {
            pandoc.RawInline('latex', '\\origin{Quelle: '),
            pandoc.Span(el.content),
            pandoc.RawInline('latex', '}')
        }
    end

    -- Handle "ex" span
    if el.classes[1] == "ex" then
        if el.attributes["href"] then
            el.content:insert(" (" .. el.attributes["href"] ..")")
        end
        return {
            pandoc.RawInline('latex', '\\ex{'),
            pandoc.Span(el.content),
            pandoc.RawInline('latex', '}')
        }
    end
end


-- Pandoc Markdown needs `$` or `$$` around math. This is also valid for LaTeX,
-- but when using math environments like `\begin{eqnarray} ... \end{eqnarray}`,
-- this must not enclosed in `$$` in LaTeX! This filter should handle this case
-- and remove the outer math mode and return just the content.
function Math(el)
    if el.mathtype == "DisplayMath" then
        i, j = el.text:find("begin")
        if i == 2 then  -- handle only DisplayMath with "\\begin{}" ...
            return pandoc.RawInline('latex', el.text)
        end
    end
end


function Div(el)
    -- GitHub Alerts: replace alert Divs with "real" GH alerts
    if el.classes[1] == "note" then
        return {
            pandoc.RawBlock('latex', '\\begin{info-box}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{info-box}')
        }
    end
    if el.classes[1] == "tip" then
        return {
            pandoc.RawBlock('latex', '\\begin{tip-box}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{tip-box}')
        }
    end
    if el.classes[1] == "important" then
        return {
            pandoc.RawBlock('latex', '\\begin{important-box}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{important-box}')
        }
    end
    if el.classes[1] == "warning" then
        return {
            pandoc.RawBlock('latex', '\\begin{warning-box}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{warning-box}')
        }
    end
    if el.classes[1] == "caution" then
        return {
            pandoc.RawBlock('latex', '\\begin{error-box}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{error-box}')
        }
    end

    -- Replace "details" Div with <details>
    if el.classes[1] == "details" then
        local bl = pandoc.List()

        if el.attributes["title"] then
            bl:insert(pandoc.Plain(pandoc.Strong(el.attributes["title"])))
        end
        bl:extend(el.content)

        return bl
    end

    -- Replace "center" Div with centered <p>
    if el.classes[1] == "center" then
        return {
            pandoc.RawBlock('latex', '\\begin{center}'),
            pandoc.Div(el.content),
            pandoc.RawBlock('latex', '\\end{center}')
        }
    end
end


--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- 1. Title
    if doc.meta.title then
        blocks:insert(pandoc.Header(1, doc.meta.title))
    end

    -- 2. TL;DR and Videos
    if doc.meta.tldr or doc.meta.youtube or doc.meta.attachments then
        local quote = pandoc.List()

--        quote:insert(pandoc.RawBlock('latex', '\\begin{important-box}'))
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

--        quote:insert(pandoc.RawBlock('latex', '\\end{important-box}'))
        quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

        blocks:extend(quote)
        blocks:insert(pandoc.HorizontalRule())
    end

    -- 3. Main Doc (shift headings if necessary)
    blocks:extend(doc.blocks:walk {
        Header = function(el)
            if doc.meta.shift_headings then
                el.level = el.level + 1
            end
            return el
        end
    })

    -- 4. Literature
    if doc.meta.readings then
        blocks:insert(pandoc.Header(2, "Zum Nachlesen"))
        blocks:insert(pandoc.BulletList(doc.meta.readings))
    end

    -- 5. Outcomes, Quizzes, and Challenges
    if doc.meta.outcomes or doc.meta.quizzes or doc.meta.challenges then
        local quote = pandoc.List()

--        quote:insert(pandoc.RawBlock('latex', '\\begin{tip-box}'))
        quote:insert(pandoc.RawBlock('latex', '\\small'))

        if doc.meta.outcomes then
            local bullets = pandoc.List()
            for _, e in ipairs(doc.meta.outcomes) do
                for k, v in pairs(e) do
                    bullets:insert(pandoc.Str(k .. ": " .. pandoc.utils.stringify(v)))
                end
            end
            quote:insert(pandoc.Plain(pandoc.Strong("Lernziele")))
            quote:insert(pandoc.BulletList(bullets))
        end

        if doc.meta.quizzes then
            local bullets = pandoc.List()
            for _, v in ipairs(doc.meta.quizzes) do
                local str_link = pandoc.utils.stringify(v.link)
                bullets:insert(pandoc.Link(v.name or str_link, str_link))
            end
            quote:insert(pandoc.Plain(pandoc.Strong("Quizzes")))
            quote:insert(pandoc.BulletList(bullets))
        end

        if doc.meta.challenges then
            quote:insert(pandoc.Plain(pandoc.Strong("Challenges")))
            quote:extend(doc.meta.challenges)
        end

--        quote:insert(pandoc.RawBlock('latex', '\\end{tip-box}'))
        quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

        blocks:insert(pandoc.HorizontalRule())
        blocks:extend(quote)
    end

    -- 6. References
    local refs = pandoc.utils.references(doc)
    if refs and #refs > 0 then
        local quote = pandoc.List()

--        quote:insert(pandoc.RawBlock('latex', '\\begin{info-box}'))
        quote:insert(pandoc.RawBlock('latex', '\\small'))

        quote:insert(pandoc.Plain(pandoc.Strong("Quellen")))
        quote:extend(doc.meta.refs)

--        quote:insert(pandoc.RawBlock('latex', '\\end{info-box}'))
        quote:insert(pandoc.RawBlock('latex', '\\normalsize'))

        blocks:insert(pandoc.HorizontalRule())
        blocks:extend(quote)
    end

    -- 7. License
    if doc.meta.license_footer and (not doc.meta.has_license) then
        blocks:insert(pandoc.RawBlock('latex', '\\vfill'))
        blocks:insert(pandoc.HorizontalRule())
        blocks:extend(doc.meta.license_footer)

        local bullets = pandoc.List()
        for _, v in pairs(credits) do
            bullets:insert(pandoc.Plain(v))
        end
        if #bullets > 0 then
            blocks:insert(pandoc.Strong('Exceptions:'))
            blocks:insert(pandoc.BulletList(bullets))
        end
    end


    -- finé
    return pandoc.Pandoc(blocks, doc.meta)
end
