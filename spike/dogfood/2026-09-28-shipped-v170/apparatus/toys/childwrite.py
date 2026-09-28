# A child writes the state while the parent does too, and the parent does not wait: two
# processes whose writes interleave, which the engine refuses by design. The wall leg's red.
import os, sys, time
d = sys.argv[1]
open(d + "/a.txt", "w").write("parent before\n")
if os.fork() == 0:
    open(d + "/b.txt", "w").write("child\n")
    os._exit(0)
open(d + "/a.txt", "w").write("parent after\n")
time.sleep(0.2)
