-- Handle "ex" span

if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Span(el)
        if el.classes[1] == "ex" then
            local content = pandoc.utils.stringify(el.content)
            return {
                pandoc.RawInline('latex', '\\ex{'),
                pandoc.Span((el.attributes["href"] and pandoc.Link(content, el.attributes["href"]) or content)),
                pandoc.RawInline('latex', '}')
            }
        end
    end
end

if FORMAT:match ('gfm') or (FORMAT:match 'markdown') then
    function Span(el)
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
end
