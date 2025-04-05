# Note to self

Normally, you would split the artefacts for Pandoc into subfolders: `filters/`, `defaults/`,
`resources/`,...

However, you'd then either have to specify the path to these subfolders using the `--data-dir`
option, or you'd have to work with relative paths in the defaults files (which is kinda
awkward). Also, if you use the Eisvogel template within the Docker container "pandoc/extra",
you cannot use `--data-dir` as the template will not be found in the container...

To avoid using local relative paths like `${.}/../resources/pdf.tex` in the defaults files,
all filters, defaults and resources for this GitHub action were simply placed in a shared
folder.
