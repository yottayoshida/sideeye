# Two threads, each writing its own file, neither ordered after the other by a join before it
# writes: more than one thread id writes inside the state root. The threads question's red.
import sys, threading
d = sys.argv[1]
ts = [threading.Thread(target=lambda n=n: open(f"{d}/t{n}.txt", "w").write(f"{n}\n")) for n in (1, 2)]
for t in ts: t.start()
for t in ts: t.join()
