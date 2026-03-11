--[[
crawl.lua (Pandoc 3.9+)

Link-based crawler for local .md files:
- crawls only Markdown inline links `[]()` (Pandoc AST: Link)
- de-duplicates and is cycle-safe (only the first occurrence counts)
- builds a directory tree preserving insertion order per level
- file titles are taken from the YAML field `title`
- directory titles are taken from the YAML field `title` of the README.md
  in that directory (for the root node: ROOT_README_LABEL (if present))
- produces on stdout:
    - manifest.json (written as plain text JSON to stdout)
- manifest structure (JSON/Lua):
    {
      "root": {
        "kind": "dir" | "file",
        "name": "...",
        "path": "...", -- normalized
        "title": "...",
        -- dir only:
        "readme_path": "..." | null,
        "children": [ <nodes> ],
        -- file only:
        "beamer": true|false,
        "images": [ "path/to/img", ... ] -- normalized
      }
    }

Usage:
  pandoc  -L crawl.lua  --wrap=none -t plain  readme.md  >  manifest.json
]]

local system = require 'pandoc.system'
local utils  = require 'pandoc.utils'
local path   = require 'pandoc.path'
local log    = require 'pandoc.log'
local json   = require 'pandoc.json'



-- cache frequently used path & utils functions locally for performance
local path_normalize   = path.normalize
local path_split       = path.split
local path_join        = path.join
local path_exists      = path.exists
local path_is_relative = path.is_relative
local path_directory   = path.directory
local path_separator   = path.separator
local utils_sha1       = utils.sha1
local utils_stringify  = utils.stringify



-- ==========================
-- Configuration
-- ==========================
local README_CANDIDATES = { "readme.md", "README.md", "Readme.md" }

local ROOT_README_LABEL = "Syllabus"



-- ==========================
-- Utilities
-- ==========================
local function _is_local_link (t)
    return t ~= ""
        and path_is_relative(t)
        and not t:lower():match('https?://.*') -- is not http(s)
end

local function _is_markdown_file (t)
    return t:lower():match('%.md$') -- is markdown
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

    local content = system.read_file(filepath)

    -- TODO: FORMAT ist nur das Output-Format, ohne die Extensions wie "alerts"
    --[[
pandoc -L .pandoc/scripts/crawl.lua \
  -f markdown+smart+four_space_rule-alerts+lists_without_preceding_blankline \
  -t plain --wrap=none \
  --metadata=crawl_reader_format:"markdown+smart+four_space_rule-alerts+lists_without_preceding_blankline" \
  readme.md > manifest.json

local function reader_format_from_meta(meta)
  local s = meta.crawl_reader_format and pandoc.utils.stringify(meta.crawl_reader_format)
  if not s or s == "" then
    -- Fallback: wenigstens "markdown"
    s = "markdown"
  end
  return pandoc.format.from_string(s)
end

local READ_FORMAT

function Pandoc(doc)
  READ_FORMAT = reader_format_from_meta(doc.meta)
  return doc
end

-- später beim rekursiven Einlesen:
-- local subdoc = pandoc.read(content, READ_FORMAT, PANDOC_READER_OPTIONS)
    ]]

    local doc = pandoc.read(content, "markdown", PANDOC_READER_OPTIONS)
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

-- helper: get meta data (title) for dir node
local function _compute_dir_meta (dirnode)
    local p = dirnode.path

    -- search for readme.md
    local found = nil
    for _, rn in ipairs(README_CANDIDATES) do
        local candidate = (p == "" or p == ".") and rn or path_join({ p, rn })
        if path_exists(candidate) then
            found = candidate
            break
        end
    end

    if not found then
        log.warn("folder w/o README.md: " .. (p ~= "" and p or "."))
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
-- Manifest (JSON) Emitter
-- ==========================
local function _manifest_as_json_string (root)
    local function _serialize_node (node)
        local t = {
            kind  = node.kind,
            name  = node.name,
            path  = node.path,
            title = node.title,
        }

        if node.kind == "dir" then
            t.readme_path = node.readme_path
            t.children = {}
            for _, ch in ipairs(node.children) do
                t.children[#t.children + 1] = _serialize_node(ch)
            end
        end

        if node.kind == "file" then
            t.beamer = node.beamer
            t.images = node.images
        end

        return t
    end

    local manifest = {
        root = _serialize_node(root)
    }

    return json.encode(manifest) .. "\n"
end



-- ==========================
-- Filter Entry Points
-- ==========================
function Pandoc (doc)
    local inputs = PANDOC_STATE and PANDOC_STATE.input_files or nil
    local startfile = (inputs and #inputs >= 1) and inputs[1] or README_CANDIDATES[1]

    local tree = _crawl(startfile)

    local json_str = _manifest_as_json_string(tree)
    local blocks = { pandoc.Plain{ pandoc.Str(json_str) } }

    return pandoc.Pandoc(blocks)
end
