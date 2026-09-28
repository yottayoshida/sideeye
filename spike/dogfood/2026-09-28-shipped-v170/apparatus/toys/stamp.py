# Two operations whose bytes differ run to run: the --twice leg's red.
import sys, time
open(sys.argv[1] + "/stamp.txt", "w").write(str(time.time_ns()) + "\n")
