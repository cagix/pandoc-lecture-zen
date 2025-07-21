-- Handle image scaling

if FORMAT:match 'beamer' then
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
end


if FORMAT:match 'markdown' then
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
end


if FORMAT:match 'gfm' then
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
end
