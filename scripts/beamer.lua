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
        local content = pandoc.utils.stringify(el.content)
        return {
            pandoc.RawInline('latex', '\\ex{'),
            pandoc.Span((el.attributes["href"] and pandoc.Link(content, el.attributes["href"]) or content)),
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


-- center images without captions too (like "real" images w/ caption aka figures)
-- remove as a precaution any parameter `web_width`, which should only be respected in the web version.
-- note: images w/ caption will be parsed (implicitly) as figures instead - no need to check for empty caption here
function Image(el)
    el.attributes["web_width"] = nil
    return {
        pandoc.RawInline('latex', '\\begin{center}'),
        el,
        pandoc.RawInline('latex', '\\end{center}')
    }
end


-- wrap inline code in `inlinecode` LaTeX command
function Code(el)
    return {
        pandoc.RawInline("latex", "\\inlinecode{"),
        el,
        pandoc.RawInline("latex", "}")
    }
end


-- wrap listings (code block) in `codeblock` LaTeX environment
-- set font size to "small" (default) or use attribute "size"
function CodeBlock(el)
    local size = el.attributes.size or "small"
    return {
        pandoc.RawBlock("latex", "\\" .. size),
        pandoc.RawBlock("latex", "\\begin{codeblock}"),
        el,
        pandoc.RawBlock("latex", "\\end{codeblock}"),
        pandoc.RawBlock("latex", "\\normalsize")
    }
end


-- do not remove "`el`{=markdown}", convert it to raw "LaTeX" instead
function RawInline(el)
    if el.format:match 'markdown' then
        return pandoc.RawInline('latex', el.text)
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

    -- 1. Main Doc (do not shift headings level - take this document as is)
    blocks:extend(doc.blocks)

    -- 2. License (and exceptions)
    if doc.meta.license_footer and (not doc.meta.has_license) then
        blocks:insert(pandoc.HorizontalRule())      -- triggers a new slide
        blocks:insert(pandoc.RawBlock('latex', '\\newpage'))
        blocks:insert(pandoc.RawBlock('latex', '\\vspace*{\\fill}'))
        blocks:extend(doc.meta.license_footer)

        local bullets = pandoc.List()
        for _, v in pairs(credits) do
            bullets:insert(pandoc.Plain(v))
        end
        if #bullets > 0 then
            blocks:insert(pandoc.RawBlock('latex', '\\bigskip'))
            blocks:insert(pandoc.Strong('Exceptions:'))
            blocks:insert(pandoc.BulletList(bullets))
        end
    end

    -- 3. Last modified
    if doc.meta.lastmod then
        blocks:insert(pandoc.HorizontalRule())      -- triggers a new slide: we do not want to have this in our screencasts
        blocks:insert(pandoc.RawBlock('latex', '\\vskip0pt plus 1filll'))
        blocks:insert(pandoc.RawBlock('latex', '\\scriptsize'))
        blocks:insert(pandoc.BlockQuote(pandoc.Plain({pandoc.Strong('Last modified:'), pandoc.Str(" "), doc.meta.lastmod})))
        blocks:insert(pandoc.RawBlock('latex', '\\normalsize'))
    end

    -- 4. Activate special numbering iff `numbering: true` is present in documents YAML header
    -- this is hacky: for this to work the beamer settings in beamer.yaml need to be "metadata" instead of "variables"
    if doc.meta.numbering then
        if doc.meta.themeoptions then
            doc.meta.themeoptions[#doc.meta.themeoptions+1] = "numbering=fraction"
        else
            doc.meta.themeoptions = {"numbering=fraction"}
        end
    end


    -- finé
    return pandoc.Pandoc(blocks, doc.meta)
end
