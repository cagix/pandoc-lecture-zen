-- "Template" for (re-)formatting documents properly

-- Custom divs to be handled
local divs = pandoc.List:new {'tldr', 'youtube', 'attachments', 'readings', 'outcomes', 'quizzes', 'challenges'}


-- lift all custom divs to meta data
local function liftdivs(doc)
    local meta = doc.meta

    local blocks = doc.blocks:walk({
        Div = function(el)
            local env = el.classes[1]
            if divs:includes(env) then
                if meta[env] then
                    io.stderr:write("[WARNING]  [format.lua]  meta data key '" .. env .. "' will be overwritten w/ content from document\n")
                end
                meta[env] = el.content
                return {}
            end
        end
    })

    return pandoc.Pandoc(blocks, meta)
end


-- put custom divs back into document at proper position
local function format(doc)
    local meta = doc.meta
    local blocks = pandoc.List()

    local handle = function(div)
        if meta[div] then
            blocks:insert(pandoc.Div(meta[div], {class = div}))
            meta[div] = nil
        end
    end

    handle("tldr")
    handle("youtube")
    handle("attachments")

    blocks:extend(doc.blocks)

    handle("readings")

    handle("outcomes")
    handle("quizzes")
    handle("challenges")

    return pandoc.Pandoc(blocks, meta)
end


--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    return doc:walk { Pandoc = liftdivs }:walk { Pandoc = format }
end
