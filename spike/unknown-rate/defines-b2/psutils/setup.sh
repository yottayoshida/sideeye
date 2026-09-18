#!/bin/sh
set -eu
cat > "$TOY_STATE/in.ps" <<'EOF'
%!PS-Adobe-3.0
%%Pages: 2
%%BoundingBox: 0 0 595 842
%%EndComments
%%Page: 1 1
/Helvetica findfont 24 scalefont setfont 100 700 moveto (Page one) show showpage
%%Page: 2 2
/Helvetica findfont 24 scalefont setfont 100 700 moveto (Page two) show showpage
%%EOF
EOF
