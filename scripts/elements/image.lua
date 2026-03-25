--[[
crawl.lua (Pandoc 3.9+)

Image-centric Pandoc Lua filter for Markdown-to-Markdown transformations:
- processes only local images, converting `![caption](path){width=...}` into HTML `<img>` (or `<picture>`)
- if a caption exists, wraps in a lightweight figure-compatible structure (GitHub Preview / Docsify friendly)
- when metadata `base_url` is set, converts relative local paths to URLs in `<img>` (or `<picture>`)
- when metadata `image_dark_suffix` is set, checks for `path/image_suffix.png` beside a local image
  and, if present, emits a `<picture>` instead of `<img>` with a dark-mode source; non-local images are not checked
- centers all images and figures (Docsify, Beamer, PDF/LaTeX)
- to be invoked with implicit_figures disabled for markdown: `from: markdown-implicit_figures`
]]

local utils  = require 'pandoc.utils'
local path   = require 'pandoc.path'

-- cache frequently used path & utils functions locally for performance
local path_normalize       = path.normalize
local path_split           = path.split
local path_join            = path.join
local path_exists          = path.exists
local path_is_relative     = path.is_relative
local path_directory       = path.directory
local path_filename        = path.filename
local path_split_extension = path.split_extension
local utils_stringify      = utils.stringify



-- ==========================
-- Configuration
-- ==========================
local image_dark_suffix = ""
local base_url = ""
local current_file = ""



-- ==========================
-- Utilities
-- ==========================

-- simple in-memory cache of checked dark images; avoids re-testing the same image
-- {el.src: {path: path to dark version, checked: true|false}}
local dark_cache = {}

-- resolve relative targets against basefile directory
local function _resolve_target (basefile, target)
    if basefile == "" or basefile == nil then return target end

    local basedir = path_directory(basefile)
    return (basedir == "." or basedir == "") and target or path_join({ basedir, target })
end

-- see if file exists locally
local function _file_exists (name)
    if name == "" or name == nil then return name end

    -- name will be relative to path of current input file
    local relname = _resolve_target(current_file, name)
    return path_exists(relname)
end

-- helper function to check for local file
local function _is_local_file (t)
    return t ~= nil
        and t ~= ""
        and path_is_relative(t)
        and not t:lower():match('https?://.*')
end

-- replace ".." if possible
-- we assume path 'p' to be a relative path
local function _normalize_relpath (p)
    if p == "" or p == nil then return p end

    -- Pandoc: remove "./", replace "" by ".", use platform dependent separator
    p = path_normalize(p)

    -- try to resolve "..":
    -- "a/b/../../foo.md" should become "foo.md"
    -- "../foo.md" would reference file outside the project dir - this would be an error
    local parts = {}
    local n = 0

    -- explicit stack index avoids repeated length calls and table.remove
    for _, part in ipairs(path_split(p)) do
        if part == ".." then
            if n > 0 and parts[n] ~= ".." then
                parts[n] = nil
                n = n - 1
            else
                error("path contains too many '..': " .. p .. " ... aborting")
            end
        elseif part ~= "." and part ~= "" then
            n = n + 1
            parts[n] = part
        end
    end

    if n == 0 then return "." end

    return path_join(parts)
end

-- normalize local (relative) link target
local function _normalize_target (basefile, target)
    local joined = _resolve_target(basefile, target)
    return _normalize_relpath(joined)
end

-- calculate filename for "dark" version based on src and image_dark_suffix
-- returns nil if image_dark_suffix does not exist
local function _calc_dark_image_name (src)
    if image_dark_suffix ~= "" then
        local path, extension = path_split_extension(src)
        return path .. image_dark_suffix  .. extension
    end
    return nil
end

-- calculate url if base_url is set
local function _calc_web_path (path_light, path_dark)
    if base_url ~= "" then
        -- normalize paths using path to current file (just once, use normalized path for dark version too)
        path_light = _normalize_target(current_file, path_light)
        path_dark  = path_dark and path_join({ path_directory(path_light), path_filename(path_dark) }) or nil

        -- add base_url
        path_light = path_join({ base_url, path_light })
        path_dark  = path_dark and path_join({ base_url, path_dark }) or nil
    end
    return path_light, path_dark
end

-- produce `<picture>` if path_dark is present, `<img>` otherwise
local function _create_image (path_light, path_dark, width)
    local w = width == "" and "" or ('width="' .. width .. '"')

    if path_dark then
        return string.format(
            '<picture><source media="(prefers-color-scheme: dark)" srcset="%s" /><img src="%s" %s /></picture>',
            path_dark,
            path_light,
            w
        )
    end

    return string.format('<img src="%s" %s />', path_light, w)
end

-- center images
local function _center_image (image)
    return string.format('<p align="center">%s</p>', image)
end

-- workaround for GH preview, will also work in Docsify
local function _wrap_in_figure_p (image, caption)
    return string.format(
        '<p align="center">%s</p><p align="center">%s</p>',
        image,
        caption
    )
end

-- this will not work in GitHub preview - use _wrap_in_figure_p() as workaround
local function _wrap_in_figure (image, caption)
    return string.format(
        '<div style="text-align: center;"><figure>%s<figcaption>%s</figcaption></figure></div>',
        image,
        caption
    )
end

-- wrap non-local images (web-resourcs) in `<img>`
-- for local images:
--     test for dark image version (use image_dark_suffix as suffix)
--     calculate url (if base_url is set)
--     if dark image exists: create in `<picture>` (`<img>` otherwise)
-- if caption is set, wrap everything in `<figure>`
local function _image_to_picture (src, width, caption)
    local path_light, path_dark = src, nil

    if _is_local_file(src) then
        cache = dark_cache[src]
        if cache and cache.checked then
            path_dark = cache.path
        else
            if image_dark_suffix ~= "" then
                path_dark = _calc_dark_image_name(src)
                path_dark = _file_exists(path_dark) and path_dark or nil
                dark_cache[src] = {path=path_dark, checked=true}
            end
        end

        if base_url ~= "" then
            path_light, path_dark = _calc_web_path(path_light, path_dark)
        end
    end

    local image = _create_image(path_light, path_dark, width)

    if caption ~= "" then
        image = _wrap_in_figure_p(image, caption)
    else
        image = _center_image(image)
    end

    return image
end



-- ==========================
-- Main Filter Functions
-- ==========================

local function _image (el)
    if FORMAT:match 'beamer' or FORMAT:match 'latex' then
        -- center images without captions too (like "real" images w/ caption aka figures)
        -- remove as a precaution any parameter `web_width`, which should only be respected in the web version.
        -- NOTE: this will also add an extra center environment for "real" images - not necessary, but not harmful either
        el.attributes["web_width"] = nil
        return {
            pandoc.RawInline('latex', '\\begin{center}'),
            el,
            pandoc.RawInline('latex', '\\end{center}')
        }
    end

    if FORMAT:match 'markdown' then
        -- If "width" or "web_width" parameters are present, emit raw `<img src=... width=...>` instead of pandoc.Image,
        -- because this would result in `<img src=... style="width:...">` - and GitHub unfortunately would filter all
        -- "style" parameters. This way GitHub preview will respect the given width parameter (for now).
        -- If both "width" and "web_width" parameters are present, "web_width" takes precedence
        -- NOTE: This conversion will also replace images wrapped in a figure with a rawinline img/picture, causing the
        --       markdown-writer to ignore the content! So we now also need to handle ‘figures’ ourselves and emit proper
        --       figures - thus deactivating the `implicit_figures` extension when reading from markdown!
        local width = el.attributes["web_width"]  or  el.attributes["width"]  or  ""
        local caption = utils_stringify(el.caption)

        return pandoc.RawInline('markdown', _image_to_picture(el.src, width, caption))
    end
end

local function _meta (meta)
    -- -M image_dark_suffix=$(IMAGE_DARK_SUFFIX)
    if meta["image_dark_suffix"] ~= nil then
        image_dark_suffix = utils_stringify(meta.image_dark_suffix)
    end

    -- -M base_url=https://raw.githubusercontent.com/USER/REPO/BRANCH/
    if meta["base_url"] ~= nil then
        base_url = utils_stringify(meta.base_url)
    end

    -- path/name.extension of current file
    local inputs = PANDOC_STATE and PANDOC_STATE.input_files or nil
    current_file = (inputs and #inputs >= 1) and inputs[1] or ""
    if current_file == "" then error("no current file set - this shouldn't happen") end
end



-- ==========================
-- Filter Entry Point
-- ==========================

function Pandoc (doc)
    -- read config
    _meta(doc.meta)

    -- transform images
    return doc:walk { Image = _image }
end
