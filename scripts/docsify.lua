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
        if el.attributes["href"] then
            el.content:insert(" (" .. el.attributes["href"] ..")")
        end
        return {
            pandoc.RawInline('markdown', '<p align="right">'),
            pandoc.Span(el.content),
            pandoc.RawInline('markdown', '</p>')
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
        -- "important" not supported in docsify
        io.stderr:write("\t[WARNING] GitHub alert 'important' not supported in docsify (replacing w/ quote)\n")
        return pandoc.BlockQuote(el.content)
    end
    if el.classes[1] == "warning" then
        return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!WARNING]')} .. el.content)
    end
    if el.classes[1] == "caution" then
        -- "caution" not supported in docsify
        io.stderr:write("\t[WARNING] GitHub alert 'caution' not supported in docsify (replacing w/ quote)\n")
        return pandoc.BlockQuote(el.content)
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


function DefinitionList(el)
    io.stderr:write("\t[WARNING] definition lists not really supported in docsify\n")
end


-- Remove TeX commands
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


-- Handle table captions
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

-- Handle code block captions
function CodeBlock(el)
    if el.attributes and el.attributes["caption"] then
        -- remove all attributes from code (just keep the class)
        -- put caption as paragraph after code block
        return {
            pandoc.CodeBlock(el.text, {class = pandoc.utils.stringify(el.classes)}),
            pandoc.Para(el.attributes["caption"])
        }
    end
end


-- Handle image scaling
-- If "width" or "web_width" parameters are present, wrap image in raw `<div style="width: ...;"> ... </div>`.
-- If both "width" and "web_width" parameters are present, "web_width" takes precedence
-- Caveat: We now also need to handle ‘figures’ ourselves - thus deactivating the `implicit_figures` option!
function Image(el)
    local width = el.attributes["web_width"]  or  el.attributes["width"]  or  ""
    local caption = pandoc.utils.stringify(el.caption)

    if caption == "" then
        -- Empty caption ("image")
        -- Markdown image needs to be separated with blank lines from context for Docsify to recognise
        local w = width == "" and "" or (' style="width:' .. width .. ';"')
        return {
            pandoc.RawInline('markdown', '<div' .. w .. '>'),
            pandoc.Str('\n\n'),
            pandoc.RawInline('markdown', '![](' .. el.src ..')'),
            pandoc.Str('\n\n'),
            pandoc.RawInline('markdown', '</div>')
        }
    else
        -- Non-empty caption ("figure")
        -- Markdown image needs to be separated with blank lines from context for Docsify to recognise
        local w = width == "" and "" or (' style="width:' .. width .. '; margin: 0 auto;"')
        return {
            pandoc.RawInline('markdown', '<div style="text-align: center;">'),
            pandoc.RawInline('markdown', '<div' .. w .. '>'),
            pandoc.Str('\n\n'),
            pandoc.RawInline('markdown', '![](' .. el.src ..')'),
            pandoc.Str('\n\n'),
            pandoc.RawInline('markdown', '</div><p>'),
            pandoc.Span(caption),
            pandoc.RawInline('markdown', '</p></div>'),
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

    -- 3. Main Doc (shift headings level if necessary)
    if doc.meta.shift_headings then
        doc.blocks = doc.blocks:walk {
            Header = function(el)
                el.level = el.level + 1
                return el
            end
        }
    end
    blocks:extend(doc.blocks)

    -- 4. Literature
    if doc.meta.readings then
        blocks:insert(pandoc.Header(2, "📖 Zum Nachlesen"))
        blocks:insert(pandoc.BulletList(doc.meta.readings))
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

    -- 7. License
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
        blocks:insert(pandoc.Plain({
            pandoc.RawInline('markdown', '<blockquote><p><sup><sub><strong>Last modified:</strong> '),
            doc.meta.lastmod,
            pandoc.RawInline('markdown', '<br></sub></sup></p></blockquote>')
        }))
    end


    -- finé
    return pandoc.Pandoc(blocks, doc.meta)
end
