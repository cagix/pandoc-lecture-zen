--[[
crawl.lua (Pandoc 3.9+)

Link-based crawler for local .md files:
- crawls only Markdown inline links `[]()` (Pandoc AST: Link)
- de-duplicates and is cycle-safe (only the first occurrence counts)
- builds a directory tree preserving insertion order per level
- file titles are taken from the YAML field `title`
- directory titles are taken from the YAML field `title` of the README.md
  in that directory (otherwise "" + warning)
- produces:
    - _sidebar.md (similar to mdBook; per level: files first, then directories;
                directory entries link to their README if present)
    - crawl-order.txt (optional, BFS/crawl order)
    - returns, as a “document”, a list of the files (like deps.mk,
    but directly usable in pipeline operations)

Usage:
  pandoc  -L crawl.lua  -s -f markdown -t markdown --wrap=none  -M book     readme.md
  pandoc  -L crawl.lua  -s -f markdown -t markdown --wrap=none  -M sidebar  readme.md
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local path   = require 'pandoc.path'
local log    = require 'pandoc.log'



-- ==========================
-- Configuration
-- ==========================
local README_CANDIDATES = { "readme.md", "README.md", "Readme.md" }

-- output artifacts (nil to deactivate)
local OUT_ORDER_TXT  = "crawl-order.txt"

-- summary.md, first bullet point:
-- - nil      : "- [<root-title>](<startfile>)"
-- - otherwise: "- [<ROOT_README_LABEL>](<startfile>)"
local ROOT_README_LABEL = "Syllabus"



-- ==========================
-- Utilities
-- ==========================
local function _is_local_link (t)
    return t ~= ""
        and not t:lower():match('https?://.*') -- is not http(s)
end

local function _is_markdown_file (t)
    return t ~= ""
        and t:lower():match('.*%.md')  -- is markdown
end

local function _is_local_markdown_file_link (t)
    return _is_local_link(t) and _is_markdown_file(t)
end

local function _strip_fragment_and_query (t)
    return t:gsub("#.*$", ""):gsub("%?.*$", "")
end

-- replace ".." if possible
local function _normalize_relpath (p)
    if p == "" then return p end

    -- Pandoc: remove "./", replace "" by ".", use platform dependent separator
    p = path.normalize(p)

    -- try to resolve "..":
    -- "a/b/../../foo.md" should become "foo.md"
    -- "../foo.md" would reference file outside the project dir - this would be an error
    local parts = {}
    for _, part in ipairs(path.split(p)) do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            else
                error("path contains too many '..': " .. p .. " ... aborting")
            end
        else
            table.insert(parts, part)
        end
    end

    return path.normalize(path.join(parts))
end

-- normalize local (markdown) link target:
-- - ignore remote targets
-- - ignore non-.md targets
-- - resolve relative targets against basefile directory
local function _normalize_local_target (basefile, target)
    if not _is_local_link(target) then return nil end

    basefile = _normalize_relpath(basefile)
    local basedir = path.directory(basefile)
    local joined  = (basedir == "." or basedir == "") and target or path.join({ basedir, target })

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



-- ==========================
-- Pandoc helper
-- ==========================

-- parse file into doc
local function _read_doc (filepath)
    local content = system.read_file(filepath)
    local doc = pandoc.read(content, FORMAT, PANDOC_READER_OPTIONS)
    return doc
end

-- get metadata title or ""
local function _get_title_from_doc (doc)
    return (doc and doc.meta and doc.meta.title) and
        utils.stringify(doc.meta.title) or ""
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
local function _new_dir_node (name, p)
    return {
        kind = "dir",
        name = name,
        path = _normalize_relpath(p),
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
        path = _normalize_relpath(p),
        title = nil,
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
        local candidate = path.join({ p, rn })
        if path.exists(candidate) then
            found = candidate
            break
        end
    end

    if not found then
        log.warn("folder w/o README.md: " .. p)
        return { title = "", readme_path = nil }
    end

    -- parse README and fetch title
    local doc = _read_doc(found)
    local t = _get_title_from_doc(doc)

    return { title = t, readme_path = found }
end

-- add new leaf node
local function _add_file_leaf (parent, filename, filepath)
    local k = _file_key(filename)

    -- do we know filename already?
    local idx = parent.child_index[k]
    if idx then return parent.children[idx] end

    -- create a new entry/leaf for filename
    local n = _new_file_node(filename, filepath)
    table.insert(parent.children, n)
    parent.child_index[k] = #parent.children
    return n
end

-- add new dir node, if not yet existing
local function _get_or_add_child_dir (parent, dir_name, dir_path)
    local k = _dir_key(dir_name)

    -- do we know dir_name already, i.e. do we have a child node?
    local idx = parent.child_index[k]
    if idx then return parent.children[idx] end

    -- create a new childnode for dir_name
    local n = _new_dir_node(dir_name, dir_path)
    table.insert(parent.children, n)
    parent.child_index[k] = #parent.children
    return n
end

-- ensure that all directory nodes along filepath exist
-- returns: parent_dirnode, leafname, dirchain (list of dirnodes on path)
local function _ensure_dir_chain (root, filepath)
    local parts = path.split(filepath) -- last part is filename

    -- just filename
    if #parts == 1 then
        return root, parts[1], {}
    end

    -- path plus filename
    local dir = root
    local chain = {}
    local accum = ""

    -- for each part: get child node or create a new node
    for i = 1, (#parts - 1) do
        local name = parts[i]
        accum = (accum == "") and name or path.join({accum, name})
        dir = _get_or_add_child_dir(dir, name, accum)
        table.insert(chain, dir)
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

-- tree -> flat file list (topic/directory grouping)
-- rule per directory: "files first, then subdirs"
local function _flatten_tree_files (startnode)
    local out = {}

    _walk_tree_files_then_dirs(startnode, function (node, depth)
        if node.kind == "dir" and node.readme_path then
            table.insert(out, node.readme_path)
        end
        if node.kind == "file" then
            table.insert(out, node.path)
        end
    end)

    return out
end



-- ==========================
-- _crawl (BFS)
-- Returns:
--   root: tree
--   _crawl_order: local markdown files in BFS _crawl order (deduplicated)
-- ==========================
local function _crawl (startfile)
    -- results: root node of new tree and list of files in _crawl order
    local root = _new_dir_node("", "")
    local _crawl_order = {}

    -- simulate a simple queue
    local queue, qh, qt = {}, 1, 0
    local seen = {}       -- discovered/enqueued

    local function _enqueue (p)
        if not p or p == "" then return end
        p = _normalize_relpath(p)
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
        -- parse current exactly once
        local doc = _read_doc(current)
        local title = _get_title_from_doc(doc)

        -- insert into tree (insertion by first-seen)
        local parent, fname, dirchain = _ensure_dir_chain(root, current)
        local leaf = _add_file_leaf(parent, fname, current)
        if leaf.title == nil then leaf.title = title end

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
        table.insert(_crawl_order, current)
        doc:walk({
            Link = function(el)
                local p = _normalize_md_target(current, el.target)
                _enqueue(p)
            end
        })

        current = _dequeue() -- next path
    end

    return root, _crawl_order
end



-- ==========================
-- Emitter
-- ==========================
-- BFS crawl order
local function _emit_order_txt (order)
    if not OUT_ORDER_TXT then return end
    system.write_file(OUT_ORDER_TXT, table.concat(order, "\n") .. "\n")
end

-- _sidebar.md (for docsify, like mdBook)
-- - per level: files first, then dirs (stable within each)
-- - directory entries link to README if present
local function _emit_sidebar_md (root)
    local lines = {}

    _walk_tree_files_then_dirs(root, function (node, depth)
        -- root.readme is depth == 0, we need to treat level 0 and 1 almost equally
        local eff_depth = math.max(depth, 1) - 1
        local indent = string.rep("  ", eff_depth) .. "- "

        if node.kind == "dir" then
            local label = (depth == 0) and ROOT_README_LABEL or _label_for_node(node)
            local entry = node.readme_path and _create_md_link(indent, label, node.readme_path)
                                         or (indent .. label)
            table.insert(lines, entry)
        end

        if node.kind == "file" then
            local label = _label_for_node(node)
            table.insert(lines, _create_md_link(indent, label, node.path))
        end
    end)

    return pandoc.read(table.concat(lines, "\n") .. "\n", "markdown")
end

-- list of dependencies for Makefile
--[[
MARKDOWN_SRC := $(shell               \
  $(PANDOC_MIN)                       \
    -L crawl.lua                      \
    -f markdown -t plain --wrap=none  \
    $(ROOT_MD)                        \
  )
]]
local function _emit_deps_doc_from_tree (root, meta)
    local order = _flatten_tree_files(root)

    local inlines = {}
    for _, p in ipairs(order) do
        table.insert(inlines, pandoc.Str(p))
        table.insert(inlines, pandoc.Space())
    end

    return pandoc.Pandoc(pandoc.Plain(inlines))
end

local function _emit_book_md (root)
    local blocks = pandoc.List()
    local meta = pandoc.List()

    local function _anchor (path)
        return "id-" .. utils.sha1(path)
    end

    _walk_tree_files_then_dirs(root, function (node, depth)
        -- root.readme is depth == 0, we need to treat level 0 and 1 almost equally
        local eff_depth = math.min(math.max(depth, 1), 6)

        -- get header (or ROOT_README_LABEL at depth == 0)
        local label = depth == 0 and ROOT_README_LABEL or _label_for_node(node)
        local id = _anchor(node.path)
--        local h = pandoc.Header(eff_depth, label, pandoc.Attr(id)) -- this does not work in docsify :/
        local h = pandoc.Header(eff_depth, label)
        local a = pandoc.RawBlock("html", '<a id="' .. id .. '"></a>') -- workaround for docsify: use extra invisible anchors above the header
        blocks:insert(a)
        blocks:insert(h)

        -- get title (only at depth == 0)
        if depth == 0 then
            meta.title = pandoc.MetaInlines(_label_for_node(node))
        end

        local path = (node.kind == "dir" and node.readme_path) and node.readme_path or nil -- test dir first (readme)
        path = (node.kind == "file" and node.path) and node.path or path                   -- if not dir, test file
        if path then
            local doc = _read_doc(path).blocks
            blocks:extend(doc:walk {
                Header = function(h)
                    if h.level + eff_depth > 6 then warn("level too deep, will vanish " .. h.level .. " => " .. utils.stringify(h.content)) end
                    h.level = math.min(h.level + eff_depth, 6)
                    return h
                end,
                Image = function(el)
                    local t = _normalize_local_target(path, el.src)
                    if t then
                        el.src = t
                        return el
                    end
                end,
                Link = function(el)
                    local t = _normalize_local_target(path, el.target)
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



-- ==========================
-- Filter Entry Point
-- ==========================
function Pandoc (doc)
    local inputs = PANDOC_STATE and PANDOC_STATE.input_files or nil
    local startfile = (inputs and #inputs >= 1) and inputs[1] or README_CANDIDATES[1]
    startfile = _normalize_relpath(startfile)

    local tree, _crawl_order = _crawl(startfile)

--    _emit_order_txt(_crawl_order)
--    _emit_deps_doc_from_tree(tree, doc.meta)

    if doc.meta and doc.meta.sidebar then return _emit_sidebar_md(tree) end
    if doc.meta and doc.meta.book then return _emit_book_md(tree) end
end
