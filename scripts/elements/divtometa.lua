-- Fetch custom divs and move content to meta data

-- Divs to be handled
local divs = pandoc.List:new {'tldr', 'youtube', 'attachments', 'readings', 'outcomes', 'quizzes', 'challenges'}

function Pandoc(doc)
    local meta = doc.meta
    local blocks = doc.blocks:walk({
        Div = function(el)
            local env = el.classes[1]
            if divs:includes(env) then
                if meta[env] then
                    io.stderr:write("[WARNING]  [divtometa.lua]  meta data key '" .. env .. "' will be overwritten w/ content from document\n")
                end
                meta[env] = el.content
                return {}
            end
        end
    })
    return pandoc.Pandoc(blocks, meta)
end
