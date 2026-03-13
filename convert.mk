###############################################################################
## Setup
###############################################################################


## path/foo.png and path/foo_inv.png - see also Makefile and use the same suffix!
IMAGE_DARK_SUFFIX      ?= _inv


## DOT and TEX sources
DOT_SOURCES             = $(shell find . -type f -name '*.dot')
TEX_SOURCES             = $(shell find . -type f -name '*.tex')

## IMAGE sources
IMAGE_SOURCES_PNG       = $(filter-out %$(IMAGE_DARK_SUFFIX).png,  $(shell find . -type f -name '*.png'))
IMAGE_SOURCES_JPG       = $(filter-out %$(IMAGE_DARK_SUFFIX).jpg,  $(shell find . -type f -name '*.jpg'))
IMAGE_SOURCES_JPEG      = $(filter-out %$(IMAGE_DARK_SUFFIX).jpeg, $(shell find . -type f -name '*.jpeg'))
IMAGE_SOURCES           = $(IMAGE_SOURCES_PNG) $(IMAGE_SOURCES_JPG) $(IMAGE_SOURCES_JPEG)


## DOT/TEX/PNG derived targets
DOT_PNG                 = $(DOT_SOURCES:.dot=.png)
TEX_PNG                 = $(TEX_SOURCES:.tex=.png)
IMAGE_DARK              = $(foreach img,$(IMAGE_SOURCES), $(basename $(img))$(IMAGE_DARK_SUFFIX)$(suffix $(img)))


## Image Magick, Graphviz, LaTeX
IMAGEMAGICK             = magick
DOT                     = dot
LATEX                   = cd $(dir $(realpath $<)) && latex

## Options
IM_WHITE_BACKGROUND     = -background white -alpha remove -alpha off  -strip
IM_INVERT               = -background white -alpha remove -alpha off  -channel RGB -negate +channel  -strip
DOT_ARGS                = -Tpng
LATEX_ARGS              = -shell-escape -interaction=nonstopmode





###############################################################################
## Main targets (do not change)
###############################################################################


## Generate dark variants for all images in IMAGE_SOURCES
images_dark: $(IMAGE_DARK)

IMAGE_EXTS := png jpg jpeg
define DARK_RULE
%$(IMAGE_DARK_SUFFIX).$(1): %.$(1)
	$$(IMAGEMAGICK) "$$<" $$(IM_INVERT) "$$@"
endef
$(foreach e,$(IMAGE_EXTS),$(eval $(call DARK_RULE,$(e))))


## Replace background w/ for all images in IMAGE_SOURCES
images_light: $(IMAGE_SOURCES)
	for file in $(IMAGE_SOURCES);  do  $(IMAGEMAGICK) "$$file" $(IM_WHITE_BACKGROUND) "$$file";  done


## Build PNGs from all .dot sources via Graphviz
dot_figures: $(DOT_PNG)

$(DOT_PNG): %.png: %.dot
	$(DOT) $(DOT_ARGS) $< -o $@


## Build PNGs from all .tex standalone documents
tex_figures: $(TEX_PNG)

$(TEX_PNG): %.png: %.tex
	$(LATEX) $(LATEX_ARGS) $(notdir $<)





###############################################################################
## Declaration of phony targets
###############################################################################


.PHONY: images_dark images_light dot_figures tex_figures
