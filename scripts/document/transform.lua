-- "Template" for moving (most of the) YAML headers into document

--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- TL;DR and Videos
    if doc.meta.tldr then
        blocks:insert(pandoc.Div(doc.meta.tldr, {class = 'tldr'}))
        doc.meta.tldr = nil
    end

    if doc.meta.youtube then
        local bullets = pandoc.List()
        for _, v in ipairs(doc.meta.youtube) do
            local str_link = pandoc.utils.stringify(v.link)
            bullets:insert(pandoc.Link(v.name or str_link, str_link))
        end
        blocks:insert(pandoc.Div(pandoc.BulletList(bullets), {class = 'youtube'}))
        doc.meta.youtube = nil
    end

    if doc.meta.attachments then
        local bullets = pandoc.List()
        for _, v in ipairs(doc.meta.attachments) do
            local str_link = pandoc.utils.stringify(v.link)
            bullets:insert(pandoc.Link(v.name or str_link, str_link))
        end
        blocks:insert(pandoc.Div(pandoc.BulletList(bullets), {class = 'attachments'}))
        doc.meta.attachments = nil
    end

    -- Main Doc
    blocks:extend(doc.blocks)

    -- Literature
    if doc.meta.readings then
        blocks:insert(pandoc.Div(pandoc.BulletList(
                    doc.meta.readings:map(function(e) return pandoc.Span(e) end)
                ), {class = 'readings'}))
        doc.meta.readings = nil
    end

    -- Outcomes, Quizzes, and Challenges
    if doc.meta.outcomes then
        local bullets = pandoc.List()
        for _, e in ipairs(doc.meta.outcomes) do
            for k, v in pairs(e) do
                bullets:insert(pandoc.Str(k .. ": " .. pandoc.utils.stringify(v)))
            end
        end
        blocks:insert(pandoc.Div(pandoc.BulletList(bullets), {class = 'outcomes'}))
        doc.meta.outcomes = nil
    end

    if doc.meta.quizzes then
        local bullets = pandoc.List()
        for _, v in ipairs(doc.meta.quizzes) do
            local str_link = pandoc.utils.stringify(v.link)
            bullets:insert(pandoc.Link(v.name or str_link, str_link))
        end
        blocks:insert(pandoc.Div(pandoc.BulletList(bullets), {class = 'quizzes'}))
        doc.meta.quizzes = nil
    end

    if doc.meta.challenges then
        blocks:insert(pandoc.Div(doc.meta.challenges, {class = 'challenges'}))
        doc.meta.challenges = nil
    end


    -- Finé
    return pandoc.Pandoc(blocks, doc.meta)
end
