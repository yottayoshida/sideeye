#!/bin/sh
# The 2026-09-16 userview-3 codespell seed (`run-r1.sh` there), unchanged in content.
set -eu
mkdir -p "$SD"
cat > "$SD/a.txt" <<'EOT'
MARKER-A keep this line
The reciever did not seperate the files.
Second line stays as it is.
EOT
cat > "$SD/b.txt" <<'EOT'
MARKER-B keep this line too
teh quick brown fox, occured twice.
EOT
cat > "$SD/c.txt" <<'EOT'
MARKER-C third file
adress and lenght are both wrong here.
EOT
