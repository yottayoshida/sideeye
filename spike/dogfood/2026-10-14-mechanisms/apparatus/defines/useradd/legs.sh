# One broken state per leg of CANDIDATES.md 1.1, each breaking that leg alone, applied to the
# completed state.
LEGS="a b c d"
E=/s/useradd/root/etc
break_a() { echo 'ghost:*:20000:0:99999:7:::' >> $E/shadow; }
break_b() { echo 'ghostgrp:!::' >> $E/gshadow; }
break_c() { sed -i 's/^staff:x:50:carol,alice$/staff:x:50:carol/' $E/group; sed -i 's/^staff:!::carol,alice$/staff:!::carol/' $E/gshadow; }
break_d() { sed -i 's#^carol:x:1001:1001::/:/bin/sh$#carol:x:1001:1001::/:/bin/bash#' $E/passwd; }
