--[[
book.lua (Pandoc 3.9+)

Generate a combined "book" document from:
- manifest.json (structure, titles, beamer/images info)
- the referenced Markdown files (content is re-read & parsed)

Behavior:
- traverse the tree in dfs order and concatenate all documents
- demote header levels based on depth (files & dirs)
- rewrite local links and image sources:
    * images: normalise relative paths and rewrite to per-file anchors
    * links to other markdown files: normalise relative paths and rewrite to per-file anchors
- per-file anchor IDs are derived from path via sha1, prefixed with "id-"
- top-level header uses ROOT_README_LABEL as title
- returns a full Pandoc document (book)

Usage:
  pandoc  -L book.lua  --wrap=none -t markdown  -M manifest=manifest.json  readme.md  >  book.md
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local path   = require 'pandoc.path'
local json   = require 'pandoc.json'
local log    = require 'pandoc.log'



-- cache frequently used path & utils functions locally for performance
local path_normalize   = path.normalize
local path_split       = path.split
local path_join        = path.join
local path_is_relative = path.is_relative
local path_directory   = path.directory
local utils_sha1       = utils.sha1
local utils_stringify  = utils.stringify



-- ==========================
-- Configuration
-- ==========================
local ROOT_README_LABEL = "Syllabus"

local cfg = {
    manifest_file = "manifest.json",
}



-- ==========================
-- Manifest helpers
-- ==========================
local function _read_manifest (filename)
    local content = system.read_file(filename)
    local manifest = json.decode(content)
    return manifest.root
end

local function _is_readme_child_manifest (parent, child)
    return parent.kind == "dir"
        and parent.readme_path
        and child.kind == "file"
        and child.path == parent.readme_path
end

local function _for_children_files_then_dirs_manifest (node, fn)
    if node.kind == "file" then return end

    for _, ch in ipairs(node.children or {}) do
        if ch.kind == "file" then fn(ch) end
    end

    for _, ch in ipairs(node.children or {}) do
        if ch.kind == "dir" then fn(ch) end
    end
end

local function _walk_tree_files_then_dirs_manifest (root, fn)
    local function _rec (node, depth)
        fn(node, depth)

        _for_children_files_then_dirs_manifest(node, function (ch)
            if _is_readme_child_manifest(node, ch) then return end
            _rec(ch, depth + 1)
        end)
    end

    _rec(root, 0)
end



-- ==========================
-- Path & link helpers (copied from original filter)
-- ==========================
local function _is_local_link (t)
    return t ~= ""
        and path_is_relative(t)
        and not t:lower():match('https?://.*') -- is not http(s)
end

local function _strip_fragment_and_query (t)
    return t:gsub("#.*$", ""):gsub("%?.*$", "")
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

-- normalize local (relative) link target:
-- - ignore remote targets
-- - resolve relative targets against basefile directory
local function _normalize_local_target (basefile, target)
    if not _is_local_link(target) then return nil end

    local basedir = path_directory(basefile)
    local joined  = (basedir == "." or basedir == "") and target or path_join({ basedir, target })

    return _normalize_relpath(joined)
end



-- ==========================
-- Pandoc helper
-- ==========================
local doc_cache = {}

local function _read_doc (filepath)
    local cached = doc_cache[filepath]
    if cached then return cached end

    local content = system.read_file(filepath)
    local doc = pandoc.read(content, FORMAT, PANDOC_READER_OPTIONS)
    doc_cache[filepath] = doc

    return doc
end

local function _label_for_node (n)
    return (n.title and n.title ~= "") and n.title or n.name
end



-- ==========================
-- Book emitter
-- ==========================
local function _emit_book_from_manifest (root)
    local blocks = pandoc.List()
    local meta = pandoc.List()

    -- cache per-path anchors to avoid repeated sha1 computation
    local anchor_cache = {}

    local function _anchor (path)
        local id = anchor_cache[path]
        if id then return id end
        id = "id-" .. utils_sha1(path)
        anchor_cache[path] = id
        return id
    end

    _walk_tree_files_then_dirs_manifest(root, function (node, depth)
        -- root.readme is depth == 0, we need to treat level 0 and 1 almost equally
        local eff_depth = math.min(math.max(depth, 1), 6)

        -- get header (or ROOT_README_LABEL at depth == 0)
        local label = depth == 0 and ROOT_README_LABEL or _label_for_node(node)
        local id = _anchor(node.path)
        -- local h = pandoc.Header(eff_depth, label, pandoc.Attr(id)) -- this does not work in docsify :/
        local h = pandoc.Header(eff_depth, label)
        local a = pandoc.RawBlock("html", '<a id="' .. id .. '"></a>') -- workaround for docsify: use extra invisible anchors above the header
        blocks:insert(a)
        blocks:insert(h)

        -- get title (only at depth == 0)
        if depth == 0 then
            meta.title = pandoc.MetaInlines(_label_for_node(node))
        end

        -- determine the actual file to include (dir -> readme, file -> itself)
        local path_to_file = (node.kind == "dir" and node.readme_path) and node.readme_path or nil -- test dir first (readme)
        path_to_file = (node.kind == "file" and node.path) and node.path or path_to_file           -- if not dir, test file
        if path_to_file then
            -- _read_doc uses a global cache, so each file is parsed at most once
            local doc_blocks = _read_doc(path_to_file).blocks
            blocks:extend(doc_blocks:walk {
                Header = function(h)
                    if h.level + eff_depth > 6 then
                        log.warn("level too deep, will vanish " .. h.level .. " => " .. utils_stringify(h.content))
                    end
                    h.level = math.min(h.level + eff_depth, 6)
                    return h
                end,
                Image = function(el)
                    -- normalise relative to the original file's directory
                    local t = _normalize_local_target(path_to_file, el.src)
                    if t then
                        el.src = t
                        return el
                    end
                end,
                Link = function(el)
                    -- rewrite links to other markdown files to point to the per-file anchor
                    local t = _normalize_local_target(path_to_file, el.target)
                    if t and t:lower():match('%.md$') then
                        el.target = "#" .. _anchor(t)
                        return el
                    end
                end
            })
        end
    end)

    return pandoc.Pandoc(blocks, meta)
end



-- ==========================
-- Filter Entry Points
-- ==========================
function Meta (meta)
    -- -M manifest=manifest.json
    if meta["manifest"] ~= nil then
        cfg.manifest_file = utils_stringify(meta["manifest"])
    end
end

function Pandoc (doc)
    local root = _read_manifest(cfg.manifest_file)
    return _emit_book_from_manifest(root)
end
