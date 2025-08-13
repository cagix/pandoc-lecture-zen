
###############################################################################
## Setup (public)
###############################################################################


## Working directory and User
## In case this doesn't work, set the path manually (use absolute paths).
WORKDIR                ?= .
USRID                  ?= $(shell id -u)
GRPID                  ?= $(shell id -g)


## Pandoc
CONTAINER_MIN           = pandoc/minimal:latest-ubuntu
CONTAINER_EXT           = pandoc/extra:latest-ubuntu

PANDOC_MIN             ?= docker run --rm --volume "$(WORKDIR):/data" --workdir /data --user $(USRID):$(GRPID) $(CONTAINER_MIN)
PANDOC_EXT             ?= docker run --rm --volume "$(WORKDIR):/data" --workdir /data --user $(USRID):$(GRPID) $(CONTAINER_EXT)

## Folder containing the Pandoc-Lecture-Zen project
PANDOC_DATA            ?= .pandoc


## Source files of your project
## (Adjust to your needs.)
METADATA               ?= lecture.yaml
OUTPUT_DIR             ?= _gfm





###############################################################################
## Internal setup (do not change)
###############################################################################


## Auxiliary files
ROOT_DEPS               = make.deps


## Markdown sources and GFM target files (to be filled via make.deps target)
MARKDOWN_SRC           ?=
GFM_MARKDOWN_TARGETS   ?=
GFM_IMAGE_TARGETS      ?=
NO_PDF                 ?=
NO_BEAMER              ?=





###############################################################################
## Main targets (do not change)
###############################################################################


## Common options
OPTIONS                 = --metadata-file=$(METADATA)


## Build docker image ("pandoc-thesis") containing pandoc and TeX-Live
docker:
	docker pull pandoc/extra:latest-ubuntu


## Clean-up: Remove temporary (generated) files
clean:
	rm -rf $(ROOT_DEPS)

## Clean-up: Remove also generated gfm-markdown files
distclean: clean
	rm -rf $(OUTPUT_DIR)





###############################################################################
## Auxiliary targets (do not change)
###############################################################################


$(ROOT_DEPS): $(METADATA)
	$(PANDOC_MIN)  -L $(PANDOC_DATA)/scripts/makedeps.lua  -M prefix=$(OUTPUT_DIR)  -f markdown -t markdown  $<  -o $@

## this needs docker/pandoc, so do only include (and build) when required
ifeq ($(MAKECMDGOALS), $(filter $(MAKECMDGOALS),gfm docsify pdf beamer format))
-include $(ROOT_DEPS)
PDF_BEAMER_TARGETS      = $(patsubst %.md,$(OUTPUT_DIR)/%.pdf,$(MARKDOWN_SRC))
PDF_TARGETS             = $(patsubst %.md,$(OUTPUT_DIR)/%.pdf,$(filter-out $(NO_PDF),$(MARKDOWN_SRC)))
BEAMER_TARGETS          = $(patsubst %.md,$(OUTPUT_DIR)/%.pdf,$(filter-out $(NO_BEAMER),$(MARKDOWN_SRC)))
endif


## Enable secondary expansion for subsequent targets. This allows the use
## of automatic variables like '@' in the prerequisite definitions by
## expanding twice (e.g. $$(VAR)). For normal variable references (e.g.
## $(VAR)) the expansion behaviour is unchanged as the second expansion
## has no effect on an already fully expanded reference.

.SECONDEXPANSION:

.DEFAULT_GOAL:=help


## GFM: Process markdown with pandoc
gfm: $(ROOT_DEPS) $$(GFM_MARKDOWN_TARGETS) $$(GFM_IMAGE_TARGETS)
gfm: OPTIONS           += -d $(PANDOC_DATA)/scripts/gfm.yaml

## DOCSIFY: Process markdown with pandoc
docsify: $(ROOT_DEPS) $$(GFM_MARKDOWN_TARGETS) $$(GFM_IMAGE_TARGETS)
docsify: OPTIONS       += -d $(PANDOC_DATA)/scripts/docsify.yaml

## PDF: Process markdown with pandoc and latex
pdf: $(ROOT_DEPS) $$(PDF_TARGETS)
pdf: OPTIONS           += -d $(PANDOC_DATA)/scripts/pdf.yaml

## Beamer: Process markdown with pandoc and latex
beamer: $(ROOT_DEPS) $$(BEAMER_TARGETS)
beamer: OPTIONS        += -d $(PANDOC_DATA)/scripts/beamer.yaml

## Format: move (most of the) YAML headers into the document
format: OPTIONS         = -d $(PANDOC_DATA)/scripts/format.yaml
format: $(ROOT_DEPS)
	for file in $(MARKDOWN_SRC); do \
		$(PANDOC_MIN) $(OPTIONS) $$file -o $$file; \
	done
#	find . -type f -name "*.md" -print0 | xargs -0 -I{} $(PANDOC_MIN) $(OPTIONS) "{}" -o "{}"

$(GFM_MARKDOWN_TARGETS):
	$(create-folder)
	$(PANDOC_MIN) $(OPTIONS)  -M lastmod="$(shell git log -n 1 --pretty=reference -- $<)"  $<  -o $@

$(GFM_IMAGE_TARGETS):
	$(create-dir-and-copy)

## will cover PDF_TARGETS as well as BEAMER_TARGETS
$(PDF_BEAMER_TARGETS): $$(patsubst $(OUTPUT_DIR)/%.pdf,%.md,$$@)
	$(create-folder)
	$(PANDOC_EXT) $(OPTIONS)  -M lastmod="$(shell git log -n 1 --pretty=reference -- $<)"  $<  -o $@


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


.PHONY: all docker gfm docsify pdf beamer format clean distclean
