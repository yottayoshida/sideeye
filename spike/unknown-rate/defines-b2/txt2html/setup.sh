#!/bin/sh
set -eu
cat > "$TOY_STATE/in.txt" <<'EOF'
A SEEDED DOCUMENT
=================

This is a plain text file the define seeds, so that txt2html has
something to convert. It has a heading, a paragraph, and a list.

  - one bullet
  - another bullet
  - a third, with a link: https://example.org/

A second paragraph closes the document.
EOF
