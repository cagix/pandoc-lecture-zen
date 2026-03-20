--[[
crawl.lua (Pandoc 3.9+)

Link-based crawler for local .md files:
- crawls only Markdown inline links `[]()` (Pandoc AST: Link)
- de-duplicates and is cycle-safe (only the first occurrence counts)
- builds a directory tree preserving insertion order per level
- file titles are taken from the YAML field `title`
- directory titles are taken from the YAML field `title` of the README.md
  in that directory (for the root node: ROOT_README_LABEL (if present))
- produces:
    - book.md (traverse the tree in dfs order and concatenate all documents,
                demote header, rewrite local links and image sources)
    - _sidebar.md (to be used in docsify, like mdBook but w/o title/header;
                per level: files first, then directories; directory entries
                link to their README if present)
    - deps.mk (list of files to be used in Makefile as dependencies)
- returns book.md as a "document", writes _sidebar.md and/or deps.mk directly as file

Usage:
  pandoc  -L crawl.lua  -s --wrap=none  -f markdown -t markdown  -M book=true            readme.md -o book.md
  pandoc  -L crawl.lua  -s --wrap=none  -f markdown -t markdown  -M sidebar=_sidebar.md  readme.md > /dev/null
  pandoc  -L crawl.lua  -s --wrap=none  -f markdown -t markdown  -M make.file=deps.mk    readme.md > /dev/null

  pandoc  -L crawl.lua  -s --wrap=none  -M input-format=markdown+lists_without_preceding_blankline -t markdown+smart+four_space_rule-grid_tables-multiline_tables-simple_tables  -M book=true -M sidebar=_sidebar.md -M make.file=deps.mk  readme.md -o book.md
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local path   = require 'pandoc.path'



-- cache frequently used path & utils functions locally for performance
local path_normalize   = path.normalize
local path_split       = path.split
local path_join        = path.join
local path_exists      = path.exists
local path_is_relative = path.is_relative
local path_directory   = path.directory
local path_filename    = path.filename
local path_separator   = path.separator
local utils_sha1       = utils.sha1
local utils_stringify  = utils.stringify
local system_read_file = system.read_file



-- ==========================
-- Configuration
-- ==========================
local README_CANDIDATES = { "readme.md", "README.md", "Readme.md" }

-- _sidebar.md, first bullet point:
-- - nil      : "- [<root-title>](<startfile>)"
-- - otherwise: "- [<ROOT_README_LABEL>](<startfile>)"
local ROOT_README_LABEL = "Syllabus"

local cfg = {
    book = { enabled = nil, },  -- default: book disabled
    sidebar = { file = nil, },  -- default: sidebar disabled
    make = {
        file = nil,             -- default: make disabled
        vars = {
            md     = "DEPS_MD",
            beamer = "DEPS_BEAMER",
            images = "DEPS_IMAGE",
        },
    },
    input_format = "markdown",  -- to be used for recursive parsing of markdown files
}

local startfile = ""



-- ==========================
-- Utilities
-- ==========================
local function _is_local_link (t)
    return t ~= nil
        and t ~= ""
        and path_is_relative(t)
        and not t:lower():match('https?://.*') -- is not http(s)
end

local function _is_markdown_file (t)
    return t:lower():match('%.md$') ~= nil -- is markdown
end

local function _is_local_markdown_file_link (t)
    return _is_local_link(t) and _is_markdown_file(t)
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

local function _normalize_md_target (basefile, target)
    target = _strip_fragment_and_query(target) -- remove queries and fragments from target
    if not _is_local_markdown_file_link(target) then return nil end

    return _normalize_local_target(basefile, target)
end

local function _create_md_link (prefix, label, target)
    return prefix .. "[" .. label .. "](" .. target .. ")"
end

local function _write_string_to_file (filename, strcontent)
    local f = io.open(filename, 'w')
    f:write(strcontent)
    f:close()
end



-- ==========================
-- Pandoc helper
-- ==========================

-- simple in-memory cache of parsed documents; avoids reparsing the same file
local doc_cache = {}

-- parse file into doc
-- 'filepath' needs to be relative and normalized
local function _read_doc (filepath)
    local cached = doc_cache[filepath]
    if cached then return cached end

    local content = system_read_file(filepath)
    local doc = pandoc.read(content, cfg.input_format, PANDOC_READER_OPTIONS)
    doc_cache[filepath] = doc

    return doc
end

-- get metadata title or ""
local function _get_title_from_doc (doc)
    return (doc and doc.meta and doc.meta.title) and
        utils_stringify(doc.meta.title) or ""
end

-- should this be included for beamer or not
local function _is_for_beamer (doc)
    return (doc and doc.meta and not doc.meta.no_beamer)
end

-- collect local images in document using normalized paths
-- allow duplicates (for now) since we need to filter duplicates between path/files later anyway
local function _collect_images (doc, path)
    local list = {}

    doc:walk({
        Image = function(el)
            list[#list+1] = _normalize_local_target(path, el.src)
        end
    })

    return list
end



-- ==========================
-- Tree structure
-- ==========================

-- dir node:
-- { kind="dir", name="topA", path="lecture/topA",
--   title=nil|"...", readme_path=nil|"../README.md",
--   meta_done=false,
--   children={}, child_index={} }
--
-- file node:
-- { kind="file", name="l01.md", path="lecture/topA/l01.md", title=nil|"..."}
--
-- 'p' needs to be relative and normalized
local function _new_dir_node (name, p)
    return {
        kind = "dir",
        name = name,
        path = p,
        title = nil,
        readme_path = nil,
        meta_done = false,
        children = {},
        child_index = {},
    }
end

local function _new_file_node (name, p)
    return {
        kind = "file",
        name = name,
        path = p,
        title = nil,
        beamer = nil,
        images = nil,
    }
end

-- helper: typed keys to avoid collisions between file and dir nodes with same name
local function _dir_key (name)  return "dir:" .. name end
local function _file_key (name) return "file:" .. name end

-- helper: is child the same readme.md file as the readme.md in the parent (folder)
local function _is_readme_child (parent, child)
    return parent.kind == "dir"
        and parent.readme_path
        and child.kind == "file"
        and child.path == parent.readme_path
end

-- helper: get label for node
local function _label_for_node (n)
    return (n.title and n.title ~= "") and n.title or n.name
end

-- helper: get meta data (title) for dir node
local function _compute_dir_meta (dirnode)
    local p = dirnode.path

    -- search for readme.md
    local found = nil
    for _, rn in ipairs(README_CANDIDATES) do
        local candidate = path_join({ p, rn })
        if path_exists(candidate) then
            found = candidate
            break
        end
    end

    if not found then
        io.stderr:write("[WARNING]  [crawl.lua]  folder w/o README.md: " .. p .. "\n")
        return { title = "", readme_path = nil }
    end

    -- parse README and fetch title
    local doc = _read_doc(found)
    local t = _get_title_from_doc(doc)

    return { title = t, readme_path = found }
end

-- add new leaf node
-- 'filepath' needs to be relative and normalized
local function _add_file_leaf (parent, filename, filepath)
    local k = _file_key(filename)

    -- do we know filename already?
    local idx = parent.child_index[k]
    if idx then return parent.children[idx] end

    -- create a new entry/leaf for filename
    local n = _new_file_node(filename, filepath)
    local children = parent.children
    local new_idx = #children + 1
    children[new_idx] = n
    parent.child_index[k] = new_idx
    return n
end

-- add new dir node, if not yet existing
-- 'dir_path' needs to be relative and normalized
local function _get_or_add_child_dir (parent, dir_name, dir_path)
    local k = _dir_key(dir_name)

    -- do we know dir_name already, i.e. do we have a child node?
    local idx = parent.child_index[k]
    if idx then return parent.children[idx] end

    -- create a new childnode for dir_name
    local n = _new_dir_node(dir_name, dir_path)
    local children = parent.children
    local new_idx = #children + 1
    children[new_idx] = n
    parent.child_index[k] = new_idx
    return n
end

-- ensure that all directory nodes along filepath exist
-- returns: parent_dirnode, leafname, dirchain (list of dirnodes on path)
-- 'filepath' needs to be relative and normalized
local function _ensure_dir_chain (root, filepath)
    local parts = path_split(filepath) -- last part is filename

    -- just filename
    if #parts == 1 then
        return root, parts[1], {}
    end

    -- path plus filename
    local dir = root
    local chain = {}
    local accum = ""

    -- for each part: get child node or create a new node
    -- use direct concatenation with path_separator to avoid repeated path.join
    for i = 1, (#parts - 1) do
        local name = parts[i]
        accum = (accum == "") and name or (accum .. path_separator .. name)
        dir = _get_or_add_child_dir(dir, name, accum)
        chain[#chain + 1] = dir
    end

    return dir, parts[#parts], chain
end

-- ensure that the readme path for dirnode is set
local function _ensure_dir_meta (dirnode)
    if dirnode.meta_done then return end

    local m = _compute_dir_meta(dirnode)

    dirnode.title = m.title
    dirnode.readme_path = m.readme_path
    dirnode.meta_done = true
end

-- iterate "files first, then dirs", within each group
local function _for_children_files_then_dirs (node, fn)
    if node.kind == "file" then return end

    for _, ch in ipairs(node.children) do
        if ch.kind == "file" then fn(ch) end
    end

    for _, ch in ipairs(node.children) do
        if ch.kind == "dir" then fn(ch) end
    end
end

-- generic tree traversal: files first, then dirs; skip readme children
local function _walk_tree_files_then_dirs (root, fn)
    local function _rec (node, depth)
        fn(node, depth)

        _for_children_files_then_dirs(node, function (ch)
            if _is_readme_child(node, ch) then return end -- do not emit readme.md twice
            _rec(ch, depth + 1)
        end)
    end

    _rec(root, 0)
end



-- ==========================
-- _crawl (BFS)
-- Returns:
--   root: tree
-- ==========================
local function _crawl (startfile)
    -- results: root node of new tree
    local root = _new_dir_node("", "")

    -- simulate a simple queue
    local queue, qh, qt = {}, 1, 0
    local seen = {}       -- discovered/enqueued

    -- expects already normalised paths; keeps 'seen' in normalised form
    -- 'p' needs to be relative and normalized
    local function _enqueue (p)
        if not p or p == "" then return end
        if seen[p] then return end

        seen[p] = true
        qt = qt + 1
        queue[qt] = p
    end

    local function _dequeue ()
        local p = nil
        if qh <= qt then
            p = queue[qh]
            qh = qh + 1
        end
        return p
    end

    -- initialize root from startfile + enqueue startfile
    _ensure_dir_meta(root)
    _enqueue(_normalize_relpath(startfile))

    -- main loop: read next file & extract + enqueue all local markdown links
    local current = _dequeue()
    while current do
        -- parse current exactly once (cacheing parsed documents)
        local doc = _read_doc(current)
        local title = _get_title_from_doc(doc)
        local beamer = _is_for_beamer(doc)
        local images = _collect_images(doc, current)

        -- insert into tree (insertion by first-seen)
        local parent, fname, dirchain = _ensure_dir_chain(root, current)
        local leaf = _add_file_leaf(parent, fname, current)
        if leaf.title == nil then leaf.title = title end
        if leaf.beamer == nil then leaf.beamer = beamer end
        if leaf.images == nil then leaf.images = images end

        -- ensure directory metadata along the path (lazy)
        for _, d in ipairs(dirchain) do
            _ensure_dir_meta(d)
        end

        -- also _crawl readme.md along the path
        for _, d in ipairs(dirchain) do
            if d.readme_path then
                _enqueue(_normalize_relpath(d.readme_path))
            end
        end

        -- collect links and enqueue in document order
        doc:walk({
            Link = function(el)
                _enqueue(_normalize_md_target(current, el.target))
            end
        })

        current = _dequeue() -- next path
    end

    return root
end



-- ==========================
-- Emitter
-- ==========================

-- list of dependencies for Makefile
local function _emit_depsmk (root)
    local lines = {}

    -- list of Markdown dependencies
    local deps1 = {}
    _walk_tree_files_then_dirs(root, function (node, depth)
        if node.kind == "dir" and node.readme_path then
            deps1[#deps1 + 1] = node.readme_path
        end
        if node.kind == "file" then
            deps1[#deps1 + 1] = node.path
        end
    end)
    lines[#lines + 1] = cfg.make.vars.md .. " := " .. table.concat(deps1, " ")

    -- list of Beamer related Markdown dependencies for Makefile
    -- this will ignore any directory readme.md files and any markdown files with `no_beamer: true`
    local deps2 = {}
    _walk_tree_files_then_dirs(root, function (node, depth)
        if node.kind == "file" and node.beamer then
            deps2[#deps2 + 1] = node.path
        end
    end)
    lines[#lines + 1] = cfg.make.vars.beamer .. " := " .. table.concat(deps2, " ")

    -- list of local image dependencies for Makefile, no duplicates
    local deps3 = {}
    local seen = {}
    local function _enqueue (images)
        for _, p in ipairs(images) do
            if not seen[p] then
                seen[p] = true
                deps3[#deps3 + 1] = p
            end
        end
    end
    _walk_tree_files_then_dirs(root, function (node, depth)
        -- get images for directory readme.md
        if node.kind == "dir" and node.readme_path then
            local k = _file_key(path_filename(node.readme_path))
            local idx = node.child_index[k]
            if idx and node.children[idx].images then
                _enqueue(node.children[idx].images)
            end
        end
        -- get images for normal files
        if node.kind == "file" and node.images then
            _enqueue(node.images)
        end
    end)
    lines[#lines + 1] = cfg.make.vars.images .. " := " .. table.concat(deps3, " ")

    -- write to Makefile
    local content = table.concat(lines, "\n\n") .. "\n"
    _write_string_to_file(cfg.make.file, content)
end

-- _sidebar.md (for docsify, like mdBook)
-- - per level: files first, then dirs (stable within each)
-- - directory entries link to README if present
local function _emit_sidebar (root)
    local lines = {}

    _walk_tree_files_then_dirs(root, function (node, depth)
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

    _write_string_to_file(cfg.sidebar.file, table.concat(lines, "\n") .. "\n")
end

-- book.md
local function _emit_book (root)
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

    _walk_tree_files_then_dirs(root, function (node, depth)
        -- root.readme is depth == 0, we need to treat level 0 and 1 almost equally
        local eff_depth = math.min(math.max(depth, 1), 6)

        -- get header (or ROOT_README_LABEL at depth == 0)
        local label = depth == 0 and ROOT_README_LABEL or _label_for_node(node)
        local id = _anchor(node.path)
--        local h = pandoc.Header(eff_depth, label, pandoc.Attr(id)) -- this does not work in docsify :/
        local h = pandoc.Header(eff_depth, label)
        local a = pandoc.RawBlock("html", '`<a id="' .. id .. '"></a>`{=markdown}') -- workaround for docsify: use extra invisible anchors above the header
        blocks:insert(a)
        blocks:insert(h)

        -- get title (only at depth == 0)
        if depth == 0 then
            meta.title = pandoc.MetaInlines(_label_for_node(node))
        end

        -- determine the actual file to include (dir -> readme, file -> itself)
        local path = (node.kind == "dir" and node.readme_path) and node.readme_path or nil -- test dir first (readme)
        path = (node.kind == "file" and node.path) and node.path or path                   -- if not dir, test file
        if path then
            -- _read_doc uses a global cache, so each file is parsed at most once
            local doc_blocks = _read_doc(path).blocks
            blocks:extend(doc_blocks:walk {
                Header = function(h)
                    local curr_level = h.level
                    local wannabe_new_level = curr_level + eff_depth
                    local new_level  = math.min(wannabe_new_level, 6)
                    if wannabe_new_level == 6 then
                        -- level 6 headings will vanish with "--shift-heading-level-by=1" in the next step
                        io.stderr:write("[WARNING]  [crawl.lua]  heading will vanish with --shift-heading-level-by=1: h" .. curr_level .. " => h" .. wannabe_new_level .. " (" .. utils_stringify(h.content) .. ")\n")
                    end
                    if wannabe_new_level > 6 then
                        -- markdown allows level 6 headings max
                        io.stderr:write("[WARNING]  [crawl.lua]  heading exceeds max level, cut back to h6: h" .. curr_level .. " => h" .. wannabe_new_level .. " (" .. utils_stringify(h.content) .. ")\n")
                    end
                    h.level = new_level
                    return h
                end,
                Image = function(el)
                    -- normalise relative to the original file's directory
                    local t = _normalize_local_target(path, el.src)
                    if t then
                        el.src = t
                        return el
                    end
                end,
                Link = function(el)
                    -- rewrite links to other markdown files to point to the per-file anchor
                    local t = _normalize_md_target(path, el.target)
                    if t then
                        el.target = "#" .. _anchor(t)
                        return el
                    end
                end
            })
        end
    end)

    return pandoc.Pandoc(blocks, meta)
end

local function _meta (meta)
    -- -M book=false  -> disable book output
    -- -M book=true   -> enable book output
    if meta["book"] ~= nil then
        cfg.book.enabled = meta.book
    end

    -- -M sidebar=_sidebar.md
    if meta["sidebar"] ~= nil then
        cfg.sidebar.file = utils_stringify(meta.sidebar)
    end

    -- -M make.file=deps.mk
    -- -M make.md=DEPS1
    -- -M make.beamer=DEPS2
    -- -M make.images=DEPS3
    if meta["make.file"] ~= nil then
        cfg.make.file = utils_stringify(meta["make.file"])

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

    -- -M input-format=markdown+alerts+lists_without_preceding_blankline
    if meta["input-format"] ~= nil then
        cfg.input_format = utils_stringify(meta["input-format"])
    end

    -- get filename (input file)
    if not meta.root_doc then
        error("please set your start document as 'root_doc' metadata")
    end
    startfile = utils_stringify(meta.root_doc)
end



-- ==========================
-- Filter Entry Points
-- ==========================

function Pandoc (doc)
    -- read config
    _meta(doc.meta)

    -- do the deed ...
    local tree = _crawl(startfile)

    -- emit to files when configured
    if cfg.make.file    then _emit_depsmk(tree)  end
    if cfg.sidebar.file then _emit_sidebar(tree) end

    -- return book as Pandoc document
    if cfg.book.enabled then return _emit_book(tree) end
end
