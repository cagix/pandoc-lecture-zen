-- "Template" for (re-)formatting documents properly
-- custom divs are expected to be found in meta data (divtometa.lua)

--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List

    local handle = function(div)
        if doc.meta[div] then
            blocks:insert(pandoc.Div(doc.meta[div], {class = div}))
            doc.meta[div] = nil
        end
    end

    -- TL;DR and Videos and Files
    handle("tldr")
    handle("youtube")
    handle("attachments")

    -- Main Doc
    blocks:extend(doc.blocks)

    -- Literature
    handle("readings")

    -- Outcomes, Quizzes, and Challenges
    handle("outcomes")
    handle("quizzes")
    handle("challenges")


    -- Finé
    return pandoc.Pandoc(blocks, doc.meta)
end
