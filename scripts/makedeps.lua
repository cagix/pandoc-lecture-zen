--[[
We want to analyse the layout of a Markdown project like

    |____ readme.md
    |____ img/
    | |____ a.png
    |____ subdir/
    | |____ readme.md
    | |____ img/
    | | |____ b.png
    | | |____ c.png
    | |____ file-a.md

and to generate a dependency Makefile containing all Markdown files linked
in the readme.md (or in the Markdown files linked there, recursively) and
containing all references to local images. Additionally, a prefix can be
specified as to where the in a following step converted files should be saved.

This filter should build a dependency Makefile like this:

```makefile
## (1) all referenced files

## not referenced anywhere, but must exist as root entry
PREFIX/readme.md: readme.md
PREFIX/readme.md: PREFIX/img/a.png
GFM_MARKDOWN_TARGETS += PREFIX/readme.md

## referenced in 'readme.md': "`[see File A](subdir/file-a.md)`"
PREFIX/subdir/file-a.md: subdir/file-a.md
PREFIX/subdir/file-a.md: PREFIX/subdir/img/b.png PREFIX/subdir/img/c.png
GFM_MARKDOWN_TARGETS += PREFIX/subdir/file-a.md


## (2) all folders containing referenced files

## not referenced anywhere, but entry necessary because of 'subdir/file-a.md'
PREFIX/subdir/readme.md: subdir/readme.md
GFM_MARKDOWN_TARGETS += PREFIX/subdir/readme.md


## (3) all referenced local images

PREFIX/img/a.png: img/a.png
GFM_IMAGE_TARGETS += PREFIX/img/a.png

PREFIX/subdir/img/b.png: subdir/img/b.png
GFM_IMAGE_TARGETS += PREFIX/subdir/img/b.png

PREFIX/subdir/img/c.png: subdir/img/c.png
GFM_IMAGE_TARGETS += PREFIX/subdir/img/c.png
```

The filter needs to look at the root Markdown file (readme.md) and to extract
all local images and local links to Markdown files. For each such link, this
process will be repeated (recursively, via breadth-first search).

This will be accomplished using a Makefile like

```makefile
GFM_MARKDOWN_TARGETS =
GFM_IMAGE_TARGETS    =

all: make.deps $$(GFM_MARKDOWN_TARGETS)

make.deps: readme.md
	$(PANDOC) -L makedeps.lua -M prefix=$(TEMP_DIR) -M indexMD=$(INDEX_MD) -t markdown $< -o $@
-include make.deps

$(GFM_MARKDOWN_TARGETS):
	mkdir -p $(dir $@)
	$(PANDOC) $(PANDOC_ARGS) $< -o $@

$(GFM_IMAGE_TARGETS):
	mkdir -p $(dir $@)
	cp $< $@
```


Usage: This filter is intended to be used with individual files that are placed
either directly in the working directory or in a subdirectory.
Examples:
    pandoc -L makedeps.lua -t markdown -M prefix=FOO readme.md
    pandoc -L makedeps.lua -t markdown -M prefix=FOO subdir/leaf/readme.md


Credits: Work on this filter was partially inspired by some ideas shared in "include-files"
(https://github.com/pandoc/lua-filters/blob/master/include-files/include-files.lua, by Albert
Krewinkel (@tarleb), license: MIT). The 'makedeps.lua' filter has been developed by us
from scratch and is neither based on nor contains any third-party code.
]]--


-- vars
local img = {}                  -- list of collected images (new_image) to ensure deterministic order in generated list (for testing)
local images = {}               -- set of collected images (new_image:old_image) to avoid processing the same file/image several times
local link_img = {}             -- dependencies for *.md: all referenced images (old_target:new_image)

local link = {}                 -- list of collected links (new_target) to ensure deterministic order in generated list (for testing)
local links = {}                -- set of collected links (old_target:new_target) to avoid processing the same file/link several times

local frontier = {}             -- queue to implement breadth-first search for visiting links
local frontier_first = 0        -- first element in queue
local frontier_last = -1        -- last element in queue
local frontier_mem = {}         -- remember all enqueued links to reduce processing time

local INDEX_MD = "readme"       -- name of readme.md (will be set from metadata)
local PREFIX = "."              -- string to prepend to the new locations, e.g. temporary folder (will be set from metadata)
local ROOT = "."                -- absolute path to working directory when starting
local LEVEL_STARTFILE = nil     -- remember subdir(s) of landing page/start file


-- helper
local function _is_local_path (path)
    return pandoc.path.is_relative(path) and    -- is relative path
           not path:match('https?://.*')        -- is not http(s)
end

local function _is_local_markdown_file_link (inline)
    return inline and
           inline.t and
           inline.t == "Link" and               -- is pandoc.Link
           inline.target:match('.*%.md') and    -- is markdown
           _is_local_path(inline.target)        -- is relative & not http(s)
end

local function _prepend_include_path (path)
    -- include path: current working directory, relative to project root
    local include_path = pandoc.path.make_relative(pandoc.system.get_working_directory(), ROOT)
    -- put everything together: include path and the given path
    return pandoc.path.normalize(pandoc.path.join({ include_path, path }))
end

local function _new_path (file)
    -- put everything together: PREFIX and the given file name (w/ include path)
    -- typically: 'PREFIX/include_path/file.md' for links (file being 'include_path/file.md')
    -- typically: 'PREFIX/include_path/img/image.png' for images  (file being 'include_path/img/image.png')
    return pandoc.path.normalize(pandoc.path.join({ PREFIX, file }))
end


-- queue
local function _enqueue (path)
    if not frontier_mem[path] then
        -- enqueue path
        frontier_last = frontier_last + 1
        frontier[frontier_last] = path

        -- remember this path: we don't need to enqueue this path for processing again
        frontier_mem[path] = true
    end
end

local function _dequeue ()
    local path = nil
    if frontier_first <= frontier_last then
        path = frontier[frontier_first]
        frontier[frontier_first] = nil
        frontier_first = frontier_first + 1
    end
    return path
end

-- enqueue local landing page(s) of current target for later processing ("include_path/readme.md")
local function _enqueue_landingpages (target)
    -- if target = 'a/b/c/d/foo.md' and the start file was 'a/b/readme.md', we should consider only the 'c/d/' part here
    local path = pandoc.path.directory(pandoc.path.make_relative(target, LEVEL_STARTFILE))

    -- do this for all sub-folders in path, i.e. for a path 'a/b/c' enqueue 'a/b/c/readme.md', 'a/b/readme.md',
    -- and 'a/readme.md'; do not enqueue 'readme.md' to save time: the start file has been processed already
    while path ~= "." do
        _enqueue(pandoc.path.normalize(pandoc.path.join({ LEVEL_STARTFILE, path, INDEX_MD .. ".md" })))
        path = pandoc.path.directory(path)      -- removes the last directory separator and everything after
    end
end


-- store for each processed file the old and the new path
local function _remember_file (old_target, new_target)
    -- safe as PREFIX/include_path/target: include_path/target
    if not links[new_target] then
        link[#link + 1] = new_target        -- list: we want the same sequence for each run
        links[new_target] = old_target      -- store new target as key because due to the "remove path parts" functionality the same resulting new file name can be constructed from different markdown files - we just keep the FIRST occurrence (n old_target => 1 new_target)
    end
end

-- store for each processed file the old and new image source
local function _remember_image (image_src, old_target, new_target)
    local old_image = _prepend_include_path(image_src)  -- old src: include_path/image_src
    local new_image = _new_path(old_image)              -- new src: PREFIX/include_path/image_src

    -- safe as PREFIX/include_path/image_src: include_path/image_src
    if not images[new_image] then
        img[#img + 1] = new_image       -- list: we want the same sequence for each run
        images[new_image] = old_image   -- store new image src as key because the same image can be referenced by different markdown files and needs to be copied in all cases to the new locations (1 old_image => n new_image)

        -- create a dependency for corresponding new_target (markdown file)
        link_img[new_target] = link_img[new_target] and (link_img[new_target] .. " " .. new_image) or (new_image)
    end
end

-- process all blocks in context of target's directory
local function _filter_blocks_in_dir (blocks, target)
    -- change into directory of 'target' to resolve potential '../' in path
    pandoc.system.with_working_directory(
            pandoc.path.directory(target),    -- may still contain '../'
            function ()
                -- when processing the start file: remember the level of its subdir(s) relative to project root
                -- "a/b/readme.md" => remember "a/b" to avoid trying to include 'readme.md' files above this level (except when directly linked to)
                if LEVEL_STARTFILE == nil then
                    LEVEL_STARTFILE = _prepend_include_path(".")
                end

                -- same as 'pandoc.path.directory(target)' but w/o '../' since Pandoc cd'ed here
                local old_target = _prepend_include_path(pandoc.path.filename(target))  -- old link: include_path/target
                local new_target = _new_path(old_target)                                -- new link: PREFIX/include_path/target

                -- remember this file (path w/o '../')
                _remember_file(old_target, new_target)

                -- collect and enqueue all new images and links in current file 'include_path/target'
                blocks:walk({
                    Image = function (image)
                        if _is_local_path(image.src) then
                            _remember_image(image.src, old_target, new_target)
                        end
                    end,
                    Link = function (link)
                        if _is_local_markdown_file_link(link) then
                            local target = _prepend_include_path(link.target)
                            _enqueue_landingpages(target)
                            _enqueue(target)
                        end
                    end
                })
            end)
end

-- open file and read content (and parse recursively and return list of blocks via '_filter_blocks_in_dir')
function _handle_file (target)
    local fh = io.open(target, "r")
    if not fh then
        io.stderr:write("\t (_handle_file) WARNING: cannot open file '" .. target .. "' ... skipping ... \n")
    else
        local blocks = pandoc.read(fh:read "*all", "markdown", PANDOC_READER_OPTIONS).blocks
        fh:close()

        _filter_blocks_in_dir(blocks, target)
    end
end


-- emit structures for make.deps
local function _emit_images ()
    local inlines = pandoc.List:new()
    for _, new_image in ipairs(img) do
        local old_image = images[new_image]

        inlines:insert(pandoc.RawInline("markdown", new_image .. ": " .. old_image .. "\n"))
        inlines:insert(pandoc.RawInline("markdown", "GFM_IMAGE_TARGETS += " .. new_image .. "\n\n"))
    end
    return inlines
end

local function _emit_links ()
    local inlines = pandoc.List:new()
    for _, new_target in ipairs(link) do
        local old_target = links[new_target]

        inlines:insert(pandoc.RawInline("markdown", new_target .. ": " .. old_target .. "\n"))
        if link_img[new_target] then
            inlines:insert(pandoc.RawInline("markdown", new_target .. ": " .. link_img[new_target] .. "\n"))
        end
        inlines:insert(pandoc.RawInline("markdown", "GFM_MARKDOWN_TARGETS += " .. new_target .. "\n"))
        inlines:insert(pandoc.RawInline("markdown", "MARKDOWN_SRC += " .. old_target .. "\n\n"))
    end
    return inlines
end


-- main filter function
function Pandoc (doc)
    -- init global vars using metadata: meta.prefix and meta.indexMD
    INDEX_MD = doc.meta.indexMD or "readme"             -- we do need the name w/o extension
    PREFIX = doc.meta.prefix or "."                     -- if not set, use "." and do no harm
    ROOT = pandoc.system.get_working_directory()        -- remember our project root

    -- get filename (input file)
    local file = doc.meta.root_doc or (INDEX_MD .. ".md")

    -- enqueue landing page for processing
    _enqueue(_prepend_include_path(file))

    -- process files recursively: breadth-first search
    local target = _dequeue()
    while target do
        _handle_file(target)
        target = _dequeue()
    end

    -- emit dependency makefile
    return pandoc.Pandoc({ pandoc.Plain(_emit_images()), pandoc.Plain(_emit_links()) }, doc.meta)
end
