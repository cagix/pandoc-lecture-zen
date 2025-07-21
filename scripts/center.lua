-- Handling "center" Div

if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Div(el)
        -- Replace "center" Div with centered <p>
        if el.classes[1] == "center" then
            return {
                pandoc.RawBlock('latex', '\\begin{center}'),
                pandoc.Div(el.content),
                pandoc.RawBlock('latex', '\\end{center}')
            }
        end
    end
end


if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        -- Replace "center" Div with centered <p>
        if el.classes[1] == "center" then
            -- GitHub preview strips "style" attribute ...
            return pandoc.Div(el.content, {align="center"})
        end
    end
end


