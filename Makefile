
###############################################################################
## Setup (public)
###############################################################################


## Working directory and User
## In case this doesn't work, set the path manually (use absolute paths).
WORKDIR                ?= .
USRID                  ?= $(shell id -u)
GRPID                  ?= $(shell id -g)


## Pandoc
## (Defaults to docker. To use pandoc and TeX-Live directly, create an
## environment variable `PANDOC` pointing to the location of your
## pandoc installation.)
PANDOC                 ?= docker run --rm --volume "$(WORKDIR):/data" --workdir /data --user $(USRID):$(GRPID) pandoc/extra:latest-ubuntu

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
	$(PANDOC)  -L $(PANDOC_DATA)/scripts/makedeps.lua  -M prefix=$(OUTPUT_DIR)  -f markdown -t markdown  $<  -o $@

## this needs docker/pandoc, so do only include (and build) when required
ifeq ($(MAKECMDGOALS), $(filter $(MAKECMDGOALS),gfm pdf))
-include $(ROOT_DEPS)
PDF_MARKDOWN_TARGETS    = $(addprefix $(OUTPUT_DIR)/,$(subst /,_, $(patsubst %.md,%.pdf, $(MARKDOWN_SRC))))
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

$(GFM_MARKDOWN_TARGETS):
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -d $(PANDOC_DATA)/scripts/gfm.yaml  $<  -o $@

$(GFM_IMAGE_TARGETS):
	$(create-dir-and-copy)


## PDF: Process markdown with pandoc and latex
pdf: $(ROOT_DEPS) $$(PDF_MARKDOWN_TARGETS)

$(PDF_MARKDOWN_TARGETS): $$(subst _,/,$$(patsubst $(OUTPUT_DIR)/%.pdf,%.md,$$@))
	$(create-folder)
	$(PANDOC) $(OPTIONS)  -d $(PANDOC_DATA)/scripts/pdf.yaml  $<  -o $@


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


.PHONY: all docker gfm pdf clean distclean
