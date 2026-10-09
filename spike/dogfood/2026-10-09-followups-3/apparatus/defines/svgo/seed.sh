set -eu
rm -rf /s/svgo && mkdir -p /s/svgo/state
cat > /s/svgo/state/a.svg <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- Generator: an editor -->
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <metadata>probe</metadata>
  <g>
    <rect x="0.000" y="0.000" width="64.000" height="64.000" fill="#ffffff"/>
    <circle cx="32.000" cy="32.000" r="16.000" fill="#ff0000" stroke="none"/>
  </g>
</svg>
EOF
