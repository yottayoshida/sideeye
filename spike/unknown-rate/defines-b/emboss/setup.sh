#!/bin/sh
set -eu
cat > "$TOY_STATE/in.fasta" <<'EOF'
>seq1 a small test sequence
ACGTACGTACGTACGTACGTACGTACGTACGT
EOF
