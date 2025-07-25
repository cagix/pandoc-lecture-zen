-- Handling code

if FORMAT:match 'beamer' then
    -- wrap inline code in `inlinecode` LaTeX command
    function Code(el)
        return {
            pandoc.RawInline("latex", "\\inlinecode{"),
            el,
            pandoc.RawInline("latex", "}")
        }
    end
end


if FORMAT:match 'beamer' then
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
end


if FORMAT:match 'latex' then
    -- remove any extra attribute "size" when generating pdf's
    -- Eisvogel has it's own settings, don't mess with it
    function CodeBlock(el)
        el.attributes.size = nil
        return el
    end
end


if FORMAT:match 'markdown' then
    -- Handle code block captions
    function CodeBlock(el)
        if el.attributes and el.attributes["caption"] then
            -- remove all attributes from code (just keep the class)
            -- put caption as paragraph after code block
            return {
                pandoc.CodeBlock(el.text, {class = pandoc.utils.stringify(el.classes)}),
                pandoc.Para(el.attributes["caption"])
            }
        end
    end
end


