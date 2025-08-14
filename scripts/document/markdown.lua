-- "Template" for GFM and Docsify

function Div(el)
    local env = el.classes[1]

    -- remove columns, but keep content
    if env == "columns" then
        io.stderr:write("[WARNING]  [markdown.lua]  columns are not really supported in docsify/gfm\n")
        return el.content
    end
    if env == "column" then
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


--- Rework the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- Title
    if doc.meta.title then
        -- assuming top-level heading: h1, shifting: +1
        blocks:insert(pandoc.Header(0, doc.meta.title))
        doc.meta.title = nil
    end

    -- Main Doc
    blocks:extend(doc.blocks)

    -- References
    local refs = pandoc.utils.references(doc)
    if refs and #refs > 0 then
        blocks:insert(pandoc.HorizontalRule())
        blocks:insert(pandoc.Div(doc.meta.refs, {class = 'bibliography'}))
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
