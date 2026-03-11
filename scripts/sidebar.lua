--[[
sidebar.lua (Pandoc 3.9+)

Generate a Docsify-style _sidebar.md (or similar summary) from a manifest.json
produced by crawl.lua.

- per level: files first, then dirs
- directory entries link to README if present
- root entry uses ROOT_README_LABEL at depth 0

Usage:
  pandoc  -L sidebar.lua  --wrap=none -t markdown  -M manifest=manifest.json  readme.md  >  _sidebar.md
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local json   = require 'pandoc.json'



-- cache frequently used utils locally
local utils_stringify = utils.stringify



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

local function _label_for_node (n)
    return (n.title and n.title ~= "") and n.title or n.name
end

local function _create_md_link (prefix, label, target)
    return prefix .. "[" .. label .. "](" .. target .. ")"
end



-- ==========================
-- Emitter
-- ==========================
local function _emit_sidebar_from_manifest (root)
    local lines = {}

    _walk_tree_files_then_dirs_manifest(root, function (node, depth)
        -- root.readme is depth == 0, we need to treat level 0 and 1 almost equally
        local eff_depth = math.max(depth, 1) - 1
        local indent = string.rep("  ", eff_depth) .. "- "

        if node.kind == "dir" then
            local label = (depth == 0) and ROOT_README_LABEL or _label_for_node(node)
            local entry = node.readme_path and _create_md_link(indent, label, node.readme_path)
                                         or (indent .. label)
            lines[#lines + 1] = entry
        end

        if node.kind == "file" then
            local label = _label_for_node(node)
            lines[#lines + 1] = _create_md_link(indent, label, node.path)
        end
    end)

    return table.concat(lines, "\n") .. "\n"
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
    local sidebar_md = _emit_sidebar_from_manifest(root)

    return pandoc.read(sidebar_md, "markdown")
end
