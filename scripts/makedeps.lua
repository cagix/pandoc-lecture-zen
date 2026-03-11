--[[
makedeps.lua (Pandoc 3.9+)

Generate Makefile dependency lists from a manifest.json produced by crawl.lua.

- reads manifest.json (or a file given in metadata: manifest=...)
- reuses tree structure (files & dirs, insertion order)
- produces on stdout:
    DEPS_MD := ...
    DEPS_BEAMER := ...
    DEPS_IMAGE := ...

Usage:
  pandoc  -L makedeps.lua  --wrap=none -t plain  -M manifest=manifest.json  readme.md  >  deps.mk
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local json   = require 'pandoc.json'



-- cache frequently used utils locally
local utils_stringify = utils.stringify



-- ==========================
-- Configuration
-- ==========================
local cfg = {
    manifest_file = "manifest.json",
    make = {
        vars = {
            md     = "DEPS_MD",
            beamer = "DEPS_BEAMER",
            images = "DEPS_IMAGE",
        },
    },
}



-- ==========================
-- Manifest helpers
-- ==========================
local function _read_manifest (filename)
    local content = system.read_file(filename)
    local manifest = json.decode(content)
    return manifest.root
end

-- README-child helper on manifest nodes
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
-- Emitter
-- ==========================
local function _emit_deps_from_manifest (root)
    local lines = {}

    -- list of Markdown dependencies
    do
        local deps1 = {}
        _walk_tree_files_then_dirs_manifest(root, function (node, depth)
            if node.kind == "dir" and node.readme_path then
                deps1[#deps1 + 1] = node.readme_path
            end
            if node.kind == "file" then
                deps1[#deps1 + 1] = node.path
            end
        end)
        lines[#lines + 1] = cfg.make.vars.md .. " := " .. table.concat(deps1, " ")
    end

    -- list of Beamer related Markdown dependencies for Makefile
    -- this will ignore any directory readme.md files and any markdown files with `no_beamer: true`
    do
        local deps2 = {}
        _walk_tree_files_then_dirs_manifest(root, function (node, depth)
            if node.kind == "file" and node.beamer then
                deps2[#deps2 + 1] = node.path
            end
        end)
        lines[#lines + 1] = cfg.make.vars.beamer .. " := " .. table.concat(deps2, " ")
    end

    -- list of local image dependencies for Makefile, no duplicates
    do
        local deps3 = {}
        local seen = {}

        local function _enqueue_images (images)
            for _, p in ipairs(images or {}) do
                if p and not seen[p] then
                    seen[p] = true
                    deps3[#deps3 + 1] = p
                end
            end
        end

        -- we need a path->file-node index for readme images
        local files_by_path = {}
        _walk_tree_files_then_dirs_manifest(root, function (node, depth)
            if node.kind == "file" then
                files_by_path[node.path] = node
            end
        end)

        _walk_tree_files_then_dirs_manifest(root, function (node, depth)
            -- get images for directory readme.md
            if node.kind == "dir" and node.readme_path then
                local f = files_by_path[node.readme_path]
                if f and f.images then
                    _enqueue_images(f.images)
                end
            end
            -- get images for normal files
            if node.kind == "file" and node.images then
                _enqueue_images(node.images)
            end
        end)
        lines[#lines + 1] = cfg.make.vars.images .. " := " .. table.concat(deps3, " ")
    end

    return table.concat(lines, "\n\n") .. "\n"
end



-- ==========================
-- Filter Entry Points
-- ==========================
function Meta (meta)
    -- -M manifest=manifest.json
    if meta["manifest"] ~= nil then
        cfg.manifest_file = utils_stringify(meta["manifest"])
    end

    -- optional: override make variable names
    if meta["make.md"] ~= nil then
        cfg.make.vars.md = utils_stringify(meta["make.md"])
    end
    if meta["make.beamer"] ~= nil then
        cfg.make.vars.beamer = utils_stringify(meta["make.beamer"])
    end
    if meta["make.images"] ~= nil then
        cfg.make.vars.images = utils_stringify(meta["make.images"])
    end
end

function Pandoc (doc)
    local root = _read_manifest(cfg.manifest_file)
    local content = _emit_deps_from_manifest(root)

    local blocks = { pandoc.Plain{ pandoc.Str(content) } }
    return pandoc.Pandoc(blocks)
end
