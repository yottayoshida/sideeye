set -eu
rm -rf /s/vim && mkdir -p /s/vim/state
mkdir -p "/s/vim/state"
cat > "/s/vim/state/a.txt" <<'EOT'
MARKER line one old
line two old
line three stays
EOT
