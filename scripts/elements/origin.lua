-- Collect all 'origin' spans - this is foreign material, i.e. should be listed as exceptions to our license
credits = {}


--- Fetch all exceptions from our license and replace the custom marker
exceptions = {
    Span = function(el)
        -- Collect all 'origin' spans
        if el.classes[1] == "origin" then
            -- use map to avoid duplicates
            -- (when used in images, this would end up in alt text _and_ in caption)
            credits[pandoc.utils.stringify(el.content)] = el.content

            -- add "Quelle: " in front of content
            if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
                return {
                    pandoc.RawInline('latex', '\\origin{Quelle: '),
                    pandoc.Span(el.content),
                    pandoc.RawInline('latex', '}')
                }
            end
            if FORMAT:match ('gfm') or (FORMAT:match 'markdown') then
                return { pandoc.Str("Quelle: ") } .. el.content
            end
            io.stderr:write("\t (origin) unexpected format: '" .. FORMAT .. "' ... \n")
        end
    end,

    Div = function(el)
        if el.classes[1] == "exceptions" then
            local bullets = pandoc.List()

            -- fetch all exceptions into bullet points
            for _, v in pairs(credits) do
                bullets:insert(pandoc.Plain(v))
            end

            if #bullets > 0 then
                -- we do have some exceptions
                if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
                    return {
                        pandoc.RawBlock('latex', '\\bigskip'),
                        pandoc.Plain(pandoc.Strong('Exceptions:')),
                        pandoc.BulletList(bullets)
                    }
                end
                if FORMAT:match ('gfm') or (FORMAT:match 'markdown') then
                    return {
                        pandoc.Plain(pandoc.Strong('Exceptions:')),
                        pandoc.BulletList(bullets)
                    }
                end
                io.stderr:write("\t (origin) unexpected format: '" .. FORMAT .. "' ... \n")
            else
                -- nope, nothing ...
                return {}  -- remove marker anyway
            end
        end
    end
}

-- just analyse the (final) document structure to avoid including unused meta data
function Pandoc(doc)
    return pandoc.Pandoc(doc.blocks:walk(exceptions), doc.meta)
end
