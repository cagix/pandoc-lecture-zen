
-- Issue a warning if users use elements that are no longer supported (spans, divs, classes, ...)

local function warning(w)
    io.stderr:write("\t" .. "[WARNING] " .. w .. "\n")
end


function Span(el)
    if el.classes[1] == "alert" then
        warning("Span `alert`: `[...]{.alert}` is no longer supported => please use Pandoc marks instead (`==FOO==`)")
    end

    if el.classes[1] == "bsp" then
        warning("Span `bsp`: `[...]{.bsp}` is no longer supported => please use Span `ex` instead (`[...]{.ex}`)")
    end

    if el.classes[1] == "cbox" then
        warning("Span `cbox`: `[...]{.cbox}` is no longer supported")
    end

    if el.classes[1] == "hinweis" then
        warning("Span `hinweis`: `[...]{.hinweis}` is no longer supported")
    end

    if el.classes[1] == "thema" then
        warning("Span `thema`: `[...]{.thema}` is no longer supported")
    end
end


function Div(el)
    if el.classes[1] == "showme" then
        warning("Div `showme`: `::: showme ... :::` is no longer supported => please use Div `details` instead (`::: details ... :::`)")
    end

    if el.classes[1] == "cbox" then
        warning("Div `cbox`: `::: cbox ... :::` is no longer supported")
    end
end
