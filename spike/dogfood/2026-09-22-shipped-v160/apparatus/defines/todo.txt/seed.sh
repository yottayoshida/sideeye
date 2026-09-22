set -eu
rm -rf /s/todo && mkdir -p /s/todo/data
cat > /s/todo/todo.cfg <<'EOF'
export TODO_DIR=/s/todo/data
export TODO_FILE="$TODO_DIR/todo.txt"
export DONE_FILE="$TODO_DIR/done.txt"
export REPORT_FILE="$TODO_DIR/report.txt"
EOF
printf "(A) call mom\nbuy milk\n" > /s/todo/data/todo.txt
: > /s/todo/data/done.txt
