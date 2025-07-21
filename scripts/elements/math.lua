-- Pandoc Markdown needs `$` or `$$` around math. This is also valid for LaTeX,
-- but when using math environments like `\begin{eqnarray} ... \end{eqnarray}`,
-- this must not enclosed in `$$` in LaTeX! This filter should handle this case
-- and remove the outer math mode and return just the content.
if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Math(el)
        if el.mathtype == "DisplayMath" then
            i, j = el.text:find("begin")
            if i == 2 then  -- handle only DisplayMath with "\\begin{}" ...
                return pandoc.RawInline('latex', el.text)
            end
        end
    end
end
