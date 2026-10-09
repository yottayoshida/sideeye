export EASYRSA_BATCH=1 EASYRSA_PKI=/s/easyrsa/pki EASYRSA_REQ_CN=TestCA
# The clock pin docs/apparatus.md gives (libfaketime through /etc/ld.so.preload, the time frozen), added
# after the first explore: `openssl ca -revoke`, which easyrsa runs, writes the revocation time into
# index.txt, so the re-run from the restored state differed from the recorded one and the explore ended
# baseline_violates_invariant (transcripts/explore/easyrsa/syscalls.txt). The first explore is kept.
echo /usr/lib/aarch64-linux-gnu/faketime/libfaketime.so.1 > /etc/ld.so.preload
export FAKETIME='2026-10-01 00:00:00'
