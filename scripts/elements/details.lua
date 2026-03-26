-- Handling "details" Div

if (FORMAT:match 'latex') or (FORMAT:match 'beamer') then
    function Div(el)
        -- Replace "details" Div with plain tex and adjust fontsize
        if el.classes[1] == "details" then
            local bl = pandoc.List()

            bl:insert(pandoc.RawBlock('latex', '\\' .. (el.attributes["opt"] or "normalsize")))

            if el.attributes["title"] then
                bl:insert(pandoc.Plain(pandoc.Strong(el.attributes["title"])))
            end
            bl:extend(el.content)

            bl:insert(pandoc.RawBlock('latex', '\\normalsize'))

            return bl
        end
    end
end


if FORMAT:match 'markdown' then
    function Div(el)
        -- Replace "details" Div with <details>
        if el.classes[1] == "details" then
            local bl = pandoc.List()

            local options = el.attributes["opt"] and (" " .. el.attributes["opt"]) or ""
            bl:insert(pandoc.RawBlock("markdown", '<details' .. options .. '>'))

            if el.attributes["title"] then
                bl:insert(pandoc.RawBlock("markdown", '<summary><strong>' .. el.attributes["title"] .. '</strong></summary>'))
            end
            bl:extend(el.content)

            bl:insert(pandoc.RawBlock("markdown", '</details>'))

            return bl
        end
    end
end


