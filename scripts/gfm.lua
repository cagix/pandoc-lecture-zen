-- Collect all 'origin' spans - this is foreign material, i.e. should be listed as exceptions to our licence
credits = {}

function Span(el)
    -- Collect all 'origin' spans - this is foreign material, i.e. should be listed as exceptions to our licence
    if el.classes[1] == "origin" then
        -- use map to avoid duplicates
        -- (when used in images, this would end up in alt text _and_ in caption)
        credits[pandoc.utils.stringify(el.content)] = el.content

        -- add "Quelle: " in front of content
        el.content = { pandoc.Str("Quelle: ") } .. el.content
        return el
    end

    -- Handle "ex" span
    -- Use key/value pair "href=..." in span as href parameter in shortcode
    -- In GitHub preview <span ...> would not work properly, using <p ...> instead
    -- Links do not work in <p ...> either ...
    if el.classes[1] == "ex" then
        local content = pandoc.utils.stringify(el.content)
        return {
            pandoc.RawInline('markdown', '<p align="right">'),
            pandoc.RawInline('markdown', (el.attributes["href"] and ('<a href="' .. el.attributes["href"] .. '">' .. content .. '</a>') or content)),
            pandoc.RawInline('markdown', '</p>')
        }
    end
end


-- Handle image scaling
-- If "width" or "web_width" parameters are present, emit raw `<img src=... width=...>` instead of pandoc.Imgage,
-- because this would result in `<img src=... style="width:...">` - and GitHub unfortunately would filter all
-- "style" parameters. This way GitHub preview will respect the given width parameter (for now).
-- If both "width" and "web_width" parameters are present, "web_width" takes precedence
-- Caveat: We now also need to handle ‘figures’ ourselves - thus deactivating the `implicit_figures` option!
function Image(el)
    local width = el.attributes["web_width"]  or  el.attributes["width"]  or  ""
    local caption = pandoc.utils.stringify(el.caption)

    local w = width == "" and "" or ('" width="' .. width)

    if caption == "" then
        -- Empty caption ("image")
        return pandoc.RawInline('markdown', '<img src="' .. el.src .. w .. '">')
    else
        -- Non-empty caption ("figure")
        return {
            pandoc.RawInline('markdown', '<p align="center">'),
            pandoc.RawInline('markdown', '<img src="' .. el.src .. w .. '">'),
            pandoc.RawInline('markdown', '</p><p align="center">'),
            pandoc.Span(caption),
            pandoc.RawInline('markdown', '</p>'),
        }
    end
end


function Div(el)
    -- GitHub Alerts: replace alert Divs with "real" GH alerts
    if el.classes[1] == "note" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!NOTE]')} .. el.content)
    end
    if el.classes[1] == "tip" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!TIP]')} .. el.content)
    end
    if el.classes[1] == "important" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!IMPORTANT]')} .. el.content)
    end
    if el.classes[1] == "warning" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!WARNING]')} .. el.content)
    end
    if el.classes[1] == "caution" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!CAUTION]')} .. el.content)
    end

    -- Replace "details" Div with <details>
    if el.classes[1] == "details" then
        local bl = pandoc.List()

        bl:insert(pandoc.RawBlock("markdown", '<details>'))
        if el.attributes["title"] then
            bl:insert(pandoc.RawBlock("markdown", '<summary><strong>' .. el.attributes["title"] .. '</strong></summary>'))
        end
        bl:extend(el.content)
        bl:insert(pandoc.RawBlock("markdown", '</details>'))

        return bl
    end

    -- Replace "center" Div with centered <p>
    if el.classes[1] == "center" then
        -- GitHub preview strips "style" attribute ...
        return pandoc.Div(el.content, {align="center"})
    end
end


--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- 1. Title
    if doc.meta.title then
        -- insert manually as `pandoc.Header(1, doc.meta.title)` will be shifted like all other headings
        blocks:insert(pandoc.RawBlock("markdown", '# ' .. pandoc.utils.stringify(doc.meta.title)))
    end

    -- 2. TL;DR and Videos
    if doc.meta.tldr or doc.meta.youtube or doc.meta.attachments then
        local quote = pandoc.List()

        quote:insert(pandoc.RawBlock("markdown", '[!IMPORTANT]'))

        if doc.meta.tldr then
            quote:insert(pandoc.RawBlock("markdown", '<details open>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>🎯 TL;DR</strong></summary>'))
            quote:extend(doc.meta.tldr)
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        if doc.meta.youtube then
            local bullets = pandoc.List()
            for _, v in ipairs(doc.meta.youtube) do
                local str_link = pandoc.utils.stringify(v.link)
                bullets:insert(pandoc.Link(v.name or str_link, str_link))
            end
            quote:insert(pandoc.RawBlock("markdown", '<details>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>🎦 Videos</strong></summary>'))
            quote:insert(pandoc.BulletList(bullets))
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        if doc.meta.attachments then
            local bullets = pandoc.List()
            for _, v in ipairs(doc.meta.attachments) do
                local str_link = pandoc.utils.stringify(v.link)
                bullets:insert(pandoc.Link(v.name or str_link, str_link))
            end
            quote:insert(pandoc.RawBlock("markdown", '<details>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>🖇 Unterlagen</strong></summary>'))
            quote:insert(pandoc.BulletList(bullets))
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        blocks:insert(pandoc.BlockQuote(quote))
    end

    -- 3. Main Doc
    blocks:extend(doc.blocks)

    -- 4. Literature
    if doc.meta.readings then
        -- insert manually as `pandoc.Header(2, "📖 Zum Nachlesen")` will be shifted like all other headings
        -- assuming top-level heading: h1, shifting: +1
        blocks:insert(pandoc.RawBlock("markdown", '## 📖 Zum Nachlesen'))
        blocks:insert(pandoc.BulletList(
            doc.meta.readings:map(function(e) return pandoc.Span(e) end)
        ))
    end

    -- 5. Outcomes, Quizzes, and Challenges
    if doc.meta.outcomes or doc.meta.quizzes or doc.meta.challenges then
        local quote = pandoc.List()

        quote:insert(pandoc.RawBlock("markdown", '[!TIP]'))

        if doc.meta.outcomes then
            local bullets = pandoc.List()
            for _, e in ipairs(doc.meta.outcomes) do
                for k, v in pairs(e) do
                    bullets:insert(pandoc.Str(k .. ": " .. pandoc.utils.stringify(v)))
                end
            end
            quote:insert(pandoc.RawBlock("markdown", '<details>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>✅ Lernziele</strong></summary>'))
            quote:insert(pandoc.BulletList(bullets))
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        if doc.meta.quizzes then
            local bullets = pandoc.List()
            for _, v in ipairs(doc.meta.quizzes) do
                local str_link = pandoc.utils.stringify(v.link)
                bullets:insert(pandoc.Link(v.name or str_link, str_link))
            end
            quote:insert(pandoc.RawBlock("markdown", '<details>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>🧩 Quizzes</strong></summary>'))
            quote:insert(pandoc.BulletList(bullets))
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        if doc.meta.challenges then
            quote:insert(pandoc.RawBlock("markdown", '<details>'))
            quote:insert(pandoc.RawBlock("markdown", '<summary><strong>🏅 Challenges</strong></summary>'))
            quote:extend(doc.meta.challenges)
            quote:insert(pandoc.RawBlock("markdown", '</details>'))
        end

        blocks:insert(pandoc.HorizontalRule())
        blocks:insert(pandoc.BlockQuote(quote))
    end

    -- 6. References
    local refs = pandoc.utils.references(doc)
    if refs and #refs > 0 then
        local quote = pandoc.List()

        quote:insert(pandoc.RawBlock("markdown", '[!NOTE]'))
        quote:insert(pandoc.RawBlock("markdown", '<details>'))
        quote:insert(pandoc.RawBlock("markdown", '<summary><strong>👀 Quellen</strong></summary>'))
        quote:extend(doc.meta.refs)
        quote:insert(pandoc.RawBlock("markdown", '</details>'))

        blocks:insert(pandoc.HorizontalRule())
        blocks:insert(pandoc.BlockQuote(quote))
    end

    -- 7. License (and exceptions)
    if doc.meta.license_footer and (not doc.meta.has_license) then
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

    -- 8. Last modified
    if doc.meta.lastmod then
        blocks:insert(pandoc.BlockQuote(pandoc.Plain({
            pandoc.RawInline('markdown', '<sup><sub>'),
            pandoc.Strong('Last modified:'),
            pandoc.Str(" "),
            pandoc.RawInline('markdown', doc.meta.lastmod),
            pandoc.RawInline('markdown', '</sub></sup>')
        })))
    end


    -- finé
    return pandoc.Pandoc(blocks, doc.meta)
end
