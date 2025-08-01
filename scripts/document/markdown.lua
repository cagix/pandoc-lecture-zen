-- "Template" for GFM and Docsify

function Div(el)
    -- remove columns, but keep content
    if el.classes[1] == "columns" then
        io.stderr:write("[WARNING]  [markdown.lua]  columns are not really supported in docsify/gfm\n")
        return el.content
    end
    if el.classes[1] == "column" then
        io.stderr:write("[WARNING]  [markdown.lua]  columns are not really supported in docsify/gfm\n")
        return el.content
    end
end


function DefinitionList(el)
    io.stderr:write("[WARNING]  [markdown.lua]  definition lists are not really supported in docsify/gfm\n")
end


-- Remove TeX commands - won't be automatically removed for markdown target format
function RawInline(el)
    if el.format == "tex" or el.format == "latex" then
        return {}
    end
end

function RawBlock(el)
    if el.format == "tex" or el.format == "latex" then
        return {}
    end
end


if FORMAT:match 'markdown' then
    -- Handle table captions for Docsify
    function Table(el)
        local cap = el.caption.short or el.caption.long or {}
        if #cap > 0 then
            -- reset original caption
            el.caption.short = {}
            el.caption.long = {}
            -- put caption as paragraph after table
            return {
                el,
                pandoc.Para(pandoc.utils.stringify(cap))
            }
        end
    end
end


--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- Title
    if doc.meta.title then
        -- insert manually as `pandoc.Header(1, doc.meta.title)` will be shifted like all other headings
        blocks:insert(pandoc.RawBlock("markdown", '# ' .. pandoc.utils.stringify(doc.meta.title)))
    end

    -- TL;DR and Videos
    if doc.meta.tldr or doc.meta.youtube or doc.meta.attachments then
        local quote = pandoc.List()

        quote:insert(pandoc.RawBlock("markdown", '[!NOTE]'))

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

    -- Main Doc
    blocks:extend(doc.blocks)

    -- Literature
    if doc.meta.readings then
        -- insert manually as `pandoc.Header(2, "📖 Zum Nachlesen")` will be shifted like all other headings
        -- assuming top-level heading: h1, shifting: +1
        blocks:insert(pandoc.RawBlock("markdown", '## 📖 Zum Nachlesen'))
        blocks:insert(pandoc.BulletList(
            doc.meta.readings:map(function(e) return pandoc.Span(e) end)
        ))
    end

    -- Outcomes, Quizzes, and Challenges
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

    -- References
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

    -- License (and exceptions)
    if doc.meta.license_footer and (not doc.meta.has_license) then
        blocks:insert(pandoc.HorizontalRule())
        blocks:extend(doc.meta.license_footer)
        blocks:insert(pandoc.Div('EXCEPTIONS', {class = 'exceptions'}))  -- marker for origin-filter
    end

    -- Last modified
    if doc.meta.lastmod then
        blocks:insert(pandoc.Plain({
            pandoc.RawInline('markdown', '<blockquote><p><sup><sub><strong>Last modified:</strong> '),
            pandoc.RawInline('markdown', doc.meta.lastmod),
            pandoc.RawInline('markdown', '<br></sub></sup></p></blockquote>')
        }))
    end


    -- Finé
    return pandoc.Pandoc(blocks, doc.meta)
end
