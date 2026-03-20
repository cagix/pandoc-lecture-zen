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


-- Handle raw inline/blocks:
-- - remove raw LaTeX (i.e., commands) - won't be automatically removed for markdown target format
-- - rebrand raw HTML to raw Markdown when emitting markdown for docsify: from `...`{=html} to `...`{=markdown} and eventually just ...
function RawInline(el)
    if el.format == "tex" or el.format == "latex" then
        return {}
    end
    if el.format == "html" then
        return pandoc.RawInline("markdown", el.text)
    end
end

function RawBlock(el)
    if el.format == "tex" or el.format == "latex" then
        return {}
    end
    if el.format == "html" then
        return pandoc.RawBlock("markdown", el.text)
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


-- TODO: links using relative paths need some extra care for docsify (see https://github.com/hibbitts-design/docsify-this/issues/759)
-- (a) relative links to files on same folder level need an extra `./` prefix
-- (b) add an extra `&relative-paths=true` to the generated docify-this url
-- (perhaps this will be fixed in docsify v5.)
function Link(el)
    local function _is_local_link (t)
        return pandoc.path.is_relative(t)
            and not t:lower():match('^https?://') -- is not http(s)
            and not t:lower():match('^#')         -- is not internal link (anchor)
            and t:lower():match('%.md$') ~= nil   -- is markdown file
    end

    local src = el.target
    if src == nil or src == "" or src == "." then
        el.target = "."
        io.stderr:write("[WARNING]  [markdown.lua]  detected relative link to file on same folder level: '" .. el.target .. "' => add extra '&relative-paths=true' to generated docify-this url\n")
    else
        local path_components = pandoc.path.split(src)
        if #path_components == 1 and _is_local_link(src) then
            el.target = pandoc.path.join({ ".", src})
            io.stderr:write("[WARNING]  [markdown.lua]  detected relative link to file on same folder level: '" .. el.target .. "' => add extra '&relative-paths=true' to generated docify-this url\n")
        end
    end

    return el
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
        blocks:insert(pandoc.Div('EXCEPTIONS', {class = 'exceptions'}))  -- marker for credits-filter
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
