# Two operations, the ordinary shape: open (truncating) and write. The gate's 0 leg.
import sys
open(sys.argv[1] + "/f.txt", "w").write("one line\n")
