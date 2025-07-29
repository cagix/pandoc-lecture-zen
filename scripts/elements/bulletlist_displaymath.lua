--[[
This filter iterates through each bullet point in a bullet list and promotes any display
math elements to top level.

The GitHub Markdown parser has a really weird bug: as soon as there's inline math in a
bullet point, any display math after that won't render properly in the whole bullet list.

This filter is intended as a quick-and-dirty workaround. If a display math element occurs
in a bullet point, it is removed from the bullet point. The bullet list obtained so far is
terminated, the display math element is inserted at the same AST level as the bullet list,
and a new bullet list is started for the remaining bullet points.

For reasons that are not entirely clear, empty pandoc.Para elements are sometimes inserted
into the bullet points. These are immediately removed again here in the filter.

Note: If a bullet point contains text followed by display math followed by text, the
resulting order after the filter is no longer correct: First, the complete bullet point is
emitted, followed by the display math.
]]--

function BulletList(el)
    -- resulting list of blocks
    local result = pandoc.List()

    -- temporary current bulletlist
    local curr_bulletlist = pandoc.List()

    -- fetch all bullet points (list of blocks)
    for _, bulletpoint in pairs(el.content) do
        local displaymath = pandoc.List()

        -- create bullet point and add to curr_bulletlist
        curr_bulletlist:insert(bulletpoint:walk {
            Math = function(el)
                if el.mathtype == "DisplayMath" then
                    displaymath:insert(pandoc.Para(el))  -- save math for later insertion
                    return {}                            -- remove from bullet point
                end
            end,
            Para = function(el)
                if #el.content == 0 then
                    return {}  -- remove empty paras in bullet points
                end
            end
        })

        -- if we've found some math elements move 'em outside the bullet list
        -- hacky workaround to resolve this weird GitHub bug
        if #displaymath > 0 then
            -- close current bulletlist
            result:insert(pandoc.BulletList(curr_bulletlist))
            curr_bulletlist = pandoc.List()

            -- add display math top level
            result:extend(displaymath)

            -- emit warning
            io.stderr:write("[WARNING]  [bulletlist_displaymath.lua]  GitHub does render display math in bullet points not correctly after inline math (moving display math outside bullet list)\n")
        end
    end

    -- close remaining bulletlist
    if #curr_bulletlist > 0 then
        result:insert(pandoc.BulletList(curr_bulletlist))
    end

    -- replace original BulletPoint with list of blocks
    return result
end
