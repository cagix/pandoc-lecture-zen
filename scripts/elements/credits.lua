-- Collect all 'credits' spans - this is alien material, i.e. should be listed as exceptions to our license
credits = {}

exceptions = {
    -- Format all 'credits' spans and collect all w/o "nolist" attribute
    Span = function(el)
        -- Simple usage (credits only): `[AC-3 Algorithmus: Eigener Code basierend auf einer Idee nach [@Russell2020, p. 171, fig. 5.3]]{.credits nolist=true}`
        -- Exception to license:        `[MapGermanyGraph.svg](https://commons.wikimedia.org/wiki/File:MapGermanyGraph.svg) by [Regnaron](https://de.wikipedia.org/wiki/Benutzer:Regnaron) and [Jahobr](https://commons.wikimedia.org/wiki/User:Jahobr) on Wikimedia Commons ([Public Domain](https://en.wikipedia.org/wiki/en:public_domain))]{.credits}`
        if el.classes[1] == "credits" then
            -- collect all w/o "nolist" attribute
            -- use map to avoid duplicates (images: this would end up in alt text _and_ in caption)
            if not el.attributes["nolist"] then
                credits[pandoc.utils.stringify(el.content)] = el.content
            end

            -- add "Quelle: " in front of content
            if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
                return {
                    pandoc.RawInline('latex', '\\credits{Quelle: '),
                    pandoc.Span(el.content),
                    pandoc.RawInline('latex', '}')
                }
            end
            if FORMAT:match ('gfm') or (FORMAT:match 'markdown') then
                return { pandoc.Str("Quelle: ") } .. el.content
            end
            io.stderr:write("\t (credits) unexpected format: '" .. FORMAT .. "' ... \n")
        end
    end,

    -- Fetch all exceptions from our license and replace the custom marker "exceptions"
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
                io.stderr:write("\t (credits) unexpected format: '" .. FORMAT .. "' ... \n")
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
