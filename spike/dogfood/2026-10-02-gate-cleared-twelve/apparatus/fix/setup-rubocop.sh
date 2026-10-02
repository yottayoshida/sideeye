#!/bin/sh
# The 2026-09-16 userview-3 rubocop seed (`run-r1.sh` there), unchanged in content.
set -eu
mkdir -p "$SD"
cat > "$SD/a.rb" <<'EOT'
# MARKER-A
def greet( name )
  puts( "hello #{name}" )
end
greet( "world" )
EOT
cat > "$SD/b.rb" <<'EOT'
# MARKER-B
def add( a, b )
  a + b
end
puts( add( 1, 2 ) )
EOT
