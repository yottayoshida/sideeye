# Two threads that write one after the other, each joined before the next starts: the engine
# judges this (a join orders the two writers, contract v18), and two thread ids write inside
# the state root — the threads question's red, which is a preference and not a refusal.
import sys, threading
d = sys.argv[1]
for n in (1, 2):
    t = threading.Thread(target=lambda n=n: open(f"{d}/t{n}.txt", "w").write(f"{n}\n"))
    t.start(); t.join()
