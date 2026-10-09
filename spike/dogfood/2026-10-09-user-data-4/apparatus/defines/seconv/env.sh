# The entry gate refused seconv on `mknodat` (unsupported_syscall_observed,
# transcripts/entry-candidates.txt): the .NET runtime creates its diagnostics FIFOs
# (clr-debug-pipe-*) under TMPDIR at startup (lab 1's strace shows them being unlinked at exit).
# DOTNET_EnableDiagnostics=0 turns that startup off; it is a documented runtime knob a user can
# set, not a change to the tool.
export DOTNET_EnableDiagnostics=0
