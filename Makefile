###############################################################################
## Setup (public)
###############################################################################


## Working directory and User
## In case this doesn't work, set the path manually (use absolute paths).
WORKDIR                ?= .
USRID                  ?= $(shell id -u)
GRPID                  ?= $(shell id -g)


## Pandoc
CONTAINER_MIN           = pandoc/minimal:latest-debian
#CONTAINER_EXT           = pandoc/extra:latest-debian  ## TODO broken (see https://github.com/pandoc/dockerfiles/issues/272)
CONTAINER_EXT           = pandoc/extra:latest-ubuntu

PANDOC_MIN             ?= docker run --rm --volume "$(WORKDIR):/data" --workdir /data --user $(USRID):$(GRPID) $(CONTAINER_MIN)
PANDOC_EXT             ?= docker run --rm --volume "$(WORKDIR):/data" --workdir /data --user $(USRID):$(GRPID) $(CONTAINER_EXT)

PANDOC                 ?= $(PANDOC_MIN)
LATEX_GOALS            := beamer pdf handout
ifneq ($(filter $(LATEX_GOALS),$(MAKECMDGOALS)),)
PANDOC                 := $(PANDOC_EXT)
endif

## Folder containing the Pandoc-Lecture-Zen project
PANDOC_DATA            ?= .pandoc


## Source files of your project
## (Adjust to your needs.)
METADATA               ?= lecture.yaml
BOOK_SRC               ?= book.md
BUILD_DIR              ?= build
IMAGE_DARK_SUFFIX      ?= _inv





###############################################################################
## Internal setup (do not change)
###############################################################################


## Auxiliary files
ROOT_DEPS               = deps.mk
SIDEBAR_SRC             = _sidebar.md
NAVBAR_SRC              = _navbar.md


## Markdown sources and referenced local images (to be filled via deps.mk target)
DEPS_MD                ?=
DEPS_IMAGE             ?=
DEPS_BEAMER            ?=





###############################################################################
## Git / Lastmod helpers
###############################################################################

## Last commit in repo
LAST_REPO_COMMIT       := $(shell git log -n 1 --pretty=format:%h\ %ad\ %s 2>/dev/null  ||  echo "unversioned")

## Make-"function": last commit for an individual file, fallback to last commit in repo
## call in receipes: $(call lastmod_file,$<)
lastmod_file            = $$( git log -n 1 --pretty=format:%h\ %ad\ %s -- '$(1)' 2>/dev/null  ||  echo '$(LAST_REPO_COMMIT)' )





###############################################################################
## Main targets (do not change)
###############################################################################


## Common options
OPTIONS                 = --metadata-file=$(METADATA)


## Fetch docker images
docker:
	docker pull $(CONTAINER_MIN)
	docker pull $(CONTAINER_EXT)


## Clean-up: Remove temporary (generated) files in root dir
clean:
	rm -rf $(ROOT_DEPS) $(BOOK_SRC) $(SIDEBAR_SRC)

## Clean-up: Remove also generated markdown and pdf files (build dir)
distclean: clean
	rm -rf $(BUILD_DIR)





###############################################################################
## Auxiliary targets (do not change)
###############################################################################


## CRAWL
## crawl.lua needs docker/pandoc, so do only include (and build) when required
GOALS_NO_DEPS          := clean distclean update_tooling
ifneq ($(filter-out $(GOALS_NO_DEPS),$(MAKECMDGOALS)),)

## crawl and find dependencies
$(ROOT_DEPS): $(METADATA)
	$(PANDOC)  $(OPTIONS)  -L $(PANDOC_DATA)/scripts/crawl.lua  -d $(PANDOC_DATA)/scripts/book.yaml  -M book=true -M sidebar=$(SIDEBAR_SRC) -M make.file=$(ROOT_DEPS)  $<  -o $(BOOK_SRC)

## include information from crawling
-include $(ROOT_DEPS)

## already existing inverted images should be included as IMAGE_TARGETS
DARK_IMAGES            := $(foreach img,$(DEPS_IMAGE), $(if $(wildcard $(basename $(img))$(IMAGE_DARK_SUFFIX)$(suffix $(img))), $(basename $(img))$(IMAGE_DARK_SUFFIX)$(suffix $(img))))

## MARKDOWN derived targets
MARKDOWN_TARGETS        = $(patsubst %,$(BUILD_DIR)/%,$(DEPS_MD))
IMAGE_TARGETS           = $(patsubst %,$(BUILD_DIR)/%,$(DEPS_IMAGE))  $(patsubst %,$(BUILD_DIR)/%,$(DARK_IMAGES))
BEAMER_TARGETS          = $(patsubst %.md,$(BUILD_DIR)/%.pdf,$(DEPS_BEAMER))
BOOK_PDF_TARGET         = $(patsubst %.md,$(BUILD_DIR)/%.pdf,$(BOOK_SRC))
BOOK_MD_TARGET          = $(patsubst %,$(BUILD_DIR)/%,$(BOOK_SRC))
SIDEBAR_TARGET          = $(patsubst %,$(BUILD_DIR)/%,$(SIDEBAR_SRC))
NAVBAR_TARGET           = $(patsubst %,$(BUILD_DIR)/%,$(NAVBAR_SRC))

endif
## CRAWL


## Format: move (most of the) YAML headers into the document
format: OPTIONS         = -d $(PANDOC_DATA)/scripts/format.yaml
format: $(ROOT_DEPS) $(DEPS_MD)
	for file in $(DEPS_MD); do  $(PANDOC) $(OPTIONS) $$file -o $$file;  done
#	find . -type f -name "*.md" -print0 | xargs -0 -I{} $(PANDOC) $(OPTIONS) "{}" -o "{}"

## Student materials
handout: docsify pdf

## DOCSIFY: Process markdown with pandoc
docsify: $(ROOT_DEPS) $(MARKDOWN_TARGETS) $(IMAGE_TARGETS) $(BOOK_MD_TARGET) $(SIDEBAR_TARGET) $(NAVBAR_TARGET)
docsify: OPTIONS       += -d $(PANDOC_DATA)/scripts/docsify.yaml
docsify: OPTIONS       += -M image_dark_suffix=$(IMAGE_DARK_SUFFIX)

## Beamer: Process markdown with pandoc and latex
beamer: $(ROOT_DEPS) $(BEAMER_TARGETS)
beamer: OPTIONS        += -d $(PANDOC_DATA)/scripts/beamer.yaml

## PDF: Process markdown with pandoc and latex
pdf: $(ROOT_DEPS) $(BOOK_PDF_TARGET)
pdf: OPTIONS           += -d $(PANDOC_DATA)/scripts/pdf.yaml


## individual transformations
$(MARKDOWN_TARGETS): $(BUILD_DIR)/%: %
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -M lastmod="$(call lastmod_file,$<)"  $<  -o $@

$(BOOK_MD_TARGET): $(BUILD_DIR)/%: %
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -M lastmod="$(LAST_REPO_COMMIT)"  $<  -o $@

$(IMAGE_TARGETS) $(SIDEBAR_TARGET) $(NAVBAR_TARGET): $(BUILD_DIR)/%: %
	$(create-dir-and-copy)

$(BEAMER_TARGETS): $(BUILD_DIR)/%.pdf: %.md
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -M lastmod="$(call lastmod_file,$<)"  $<  -o $@

$(BOOK_PDF_TARGET): $(BUILD_DIR)/%.pdf: %.md
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -M lastmod="$(LAST_REPO_COMMIT)"  $<  -o $@


## Canned recipe for creating output folder
define create-folder
@mkdir -p $(dir $@)
endef

## Canned recipe for creating output folder and copy output file
define create-dir-and-copy
$(create-folder)
cp $< $@
endef





###############################################################################
## Declaration of phony targets
###############################################################################


.PHONY: all docker clean distclean format docsify beamer pdf handout
