#!/bin/sh
# #556 R1 C3: in each exec'd image, which signal-state set-calls run BEFORE the shim's own
# rt_sigaction(SIGSYS, handler)? Tracked per pid (the first version's awk was not, and its
# execve pattern missed `<... execve resumed>`).
set -u
SHIM=/se/libsideeye_shim.so
echo "libc: $(ldd --version 2>&1 | head -1)   arch: $(uname -m)   openssl: $(openssl version 2>&1)"
probe() {
  tag=$1; shift
  LD_PRELOAD=$SHIM strace -f -qq -e trace=execve,rt_sigaction,rt_sigprocmask -o /tmp/st.txt "$@" > /dev/null 2>&1
  echo "==== $tag"
  awk '
    { pid = $1 }
    /execve\(/ && / = 0$/ { st[pid] = "img"; n[pid] = 0; next }
    /<\.\.\. execve resumed>/ && / = 0$/ { st[pid] = "img"; n[pid] = 0; next }
    st[pid] == "img" && /rt_sigaction\(SIGSYS, \{sa_handler=0x/ { print "   pid " pid ": shim handler installed after " n[pid] " set-call(s)"; st[pid] = "done"; next }
    st[pid] == "img" && /rt_sigaction\([A-Z0-9_+]+, \{/ { n[pid]++; print "   pid " pid " BEFORE: " $0; next }
    st[pid] == "img" && /rt_sigprocmask\(SIG_(BLOCK|SETMASK), \[/ { n[pid]++; print "   pid " pid " BEFORE: " $0; next }
    END { for (p in st) if (st[p] == "img") print "   pid " p ": image ended with NO shim install line (" n[p] " set-calls seen)" }
  ' /tmp/st.txt
}
probe "/bin/true" /bin/true
probe "sh -c '/bin/true; :' (two images)" sh -c '/bin/true; :'
probe "openssl version" openssl version
