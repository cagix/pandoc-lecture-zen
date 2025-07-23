-- GitHub Alerts: replace alert Divs with "real" GH alerts

if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Div(el)
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
    end
end


if (FORMAT:match 'gfm') or (FORMAT:match 'markdown') then
    function Div(el)
        if el.classes[1] == "note" then
            return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!NOTE]')} .. el.content)
        end

        if el.classes[1] == "tip" then
            return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!TIP]')} .. el.content)
        end

        if el.classes[1] == "warning" then
            return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!WARNING]')} .. el.content)
        end

        if el.classes[1] == "important" then
            if FORMAT:match 'markdown' then
                -- docsify: "important" not supported in docsify
                io.stderr:write("\t[WARNING]  [ghalerts.lua]  GitHub alert 'important' not supported in docsify (replacing w/ quote)\n")
                return pandoc.BlockQuote(el.content)
            else
                -- gfm
                return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!IMPORTANT]')} .. el.content)
            end
        end

        if el.classes[1] == "caution" then
            if FORMAT:match 'markdown' then
                -- docsify: "caution" not supported in docsify
                io.stderr:write("\t[WARNING]  [ghalerts.lua]  GitHub alert 'caution' not supported in docsify (replacing w/ quote)\n")
                return pandoc.BlockQuote(el.content)
            else
                -- gfm
                return pandoc.BlockQuote({pandoc.RawBlock("markdown", '[!CAUTION]')} .. el.content)
            end
        end
    end
end


