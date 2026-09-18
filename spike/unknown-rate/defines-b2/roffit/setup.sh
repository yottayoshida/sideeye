#!/bin/sh
set -eu
cat > "$TOY_STATE/in.1" <<'EOF'
.TH SEEDED 1 "2026-09-18" "seeded 1.0" "User Commands"
.SH NAME
seeded \- a page the define seeds
.SH SYNOPSIS
.B seeded
.RI [ options ]
.SH DESCRIPTION
.B seeded
does nothing but exist, so that
.BR roffit (1)
has a page to convert.
.SH OPTIONS
.TP
.B \-v
Say so.
.SH SEE ALSO
.BR roffit (1)
EOF
