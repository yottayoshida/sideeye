#!/bin/sh
# Option A feasibility: in an exec'd image, does anything set a signal disposition or mask
# BEFORE the shim's constructor installs its SIGSYS handler? A trapped call there would kill
# the image at startup. The shim's own install is the rt_sigaction(SIGSYS, {sa_handler=...}).
set -u
SHIM=/se/libsideeye_shim.so
echo "shim sha256: $(sha256sum "$SHIM" | cut -d' ' -f1)"
probe() {
  tag=$1; shift
  LD_PRELOAD=$SHIM strace -f -qq -e trace=execve,rt_sigaction,rt_sigprocmask -o /tmp/st.txt "$@" > /dev/null 2>&1
  echo "==== $tag"
  awk '
    /execve\(/ && / = 0/ { img = $0; before = 0; seen = 0; next }
    /rt_sigaction\(SIGSYS, \{sa_handler=0x/ && !seen { seen = 1; print "   shim handler installed after " before " set-call(s)"; next }
    !seen && /rt_sigaction\([A-Z0-9]+, \{/ { before++; print "   BEFORE: " $0 }
    !seen && /rt_sigprocmask\(SIG_(BLOCK|SETMASK), \[/ { before++; print "   BEFORE: " $0 }
  ' /tmp/st.txt
  echo "   total rt_sigaction set: $(grep -c 'rt_sigaction([A-Z0-9]*, {' /tmp/st.txt)  rt_sigprocmask block/setmask: $(grep -c 'rt_sigprocmask(SIG_\(BLOCK\|SETMASK\), \[' /tmp/st.txt)"
}
probe "/bin/true" /bin/true
probe "sh -c /bin/true (exec chain)" sh -c '/bin/true; :'
probe "python3 -c pass" python3 -c pass
probe "node -e 0" node -e 0
