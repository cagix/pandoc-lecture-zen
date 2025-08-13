-- "Template" for (re-)formatting documents properly

--- Structure of the document (should be done w/ template, but quotes won't work)
function Pandoc(doc)
    local blocks = pandoc.List()

    -- TL;DR and Videos
    if doc.meta.tldr then
        blocks:insert(pandoc.Div(doc.meta.tldr, {class = 'tldr'}))
        doc.meta.tldr = nil
    end

    if doc.meta.youtube then
        blocks:insert(pandoc.Div(doc.meta.youtube, {class = 'youtube'}))
        doc.meta.youtube = nil
    end

    if doc.meta.attachments then
        blocks:insert(pandoc.Div(doc.meta.attachments, {class = 'attachments'}))
        doc.meta.attachments = nil
    end

    -- Main Doc
    blocks:extend(doc.blocks)

    -- Literature
    if doc.meta.readings then
        blocks:insert(pandoc.Div(doc.meta.readings, {class = 'readings'}))
        doc.meta.readings = nil
    end

    -- Outcomes, Quizzes, and Challenges
    if doc.meta.outcomes then
        blocks:insert(pandoc.Div(doc.meta.outcomes, {class = 'outcomes'}))
        doc.meta.outcomes = nil
    end

    if doc.meta.quizzes then
        blocks:insert(pandoc.Div(doc.meta.quizzes, {class = 'quizzes'}))
        doc.meta.quizzes = nil
    end

    if doc.meta.challenges then
        blocks:insert(pandoc.Div(doc.meta.challenges, {class = 'challenges'}))
        doc.meta.challenges = nil
    end


    -- Finé
    return pandoc.Pandoc(blocks, doc.meta)
end
