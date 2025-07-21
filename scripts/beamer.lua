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
        blocks:insert(pandoc.Div('EXCEPTIONS', {class = 'exceptions'}))  -- marker for origin-filter
    end

    -- 3. Last modified
    if doc.meta.lastmod then
        blocks:insert(pandoc.HorizontalRule())      -- triggers a new slide: we do not want to have this in our screencasts
        blocks:insert(pandoc.RawBlock('latex', '\\vskip0pt plus 1filll'))
        blocks:insert(pandoc.RawBlock('latex', '\\scriptsize'))
        blocks:insert(pandoc.BlockQuote(pandoc.Plain({pandoc.Strong('Last modified:'), pandoc.Str(" "), doc.meta.lastmod})))
        blocks:insert(pandoc.RawBlock('latex', '\\normalsize'))
    end

    -- 4. Change numbering style to eg. `slide_numbering: fraction` if present in documents YAML header (default: "none")
    -- this is hacky: for this to work all beamer settings in beamer.yaml need to be "metadata" instead of "variables"
    local slide_numbering = { "numbering=" .. (doc.meta.slide_numbering and pandoc.utils.stringify(doc.meta.slide_numbering) or "none") }
    doc.meta.themeoptions = doc.meta.themeoptions and (doc.meta.themeoptions .. slide_numbering) or slide_numbering


    -- finé
    return pandoc.Pandoc(blocks, doc.meta)
end
