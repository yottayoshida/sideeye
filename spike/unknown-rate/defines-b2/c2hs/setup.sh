#!/bin/sh
set -eu
printf 'int add(int a, int b);\n' > "$TOY_STATE/hello.h"
cat > "$TOY_STATE/Hello.chs" <<'EOF'
module Hello where
#include "hello.h"
{# fun add as ^ { `Int', `Int' } -> `Int' #}
EOF
