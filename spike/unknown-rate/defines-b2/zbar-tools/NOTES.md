# zbar-tools — wall W3 (no non-interactive writer)

Debian description: "QR code / bar code scanner and decoder (utilities)";
debtags `hardware::camera`, `hardware::scanner`, `implemented-in::c`.
Installed 0.23.93-8 in the trixie image. Freshness: no tracked file outside the
selection names it (`b2-author.sh`, 2026-09-18).

Two programs. man zbarcam: "scans a video4linux video source (eg, a webcam)
for bar codes and prints any decoded data to the standard output" — a camera
device, and output to the terminal. man zbarimg: "For each specified image
file zbarimg scans the image for bar codes and prints any decoded data to
stdout" — a reader; its options select symbologies and output formats
(`--xml`, `--raw`) and none names a file it writes. Neither manual documents
a command that changes a file, so there is no state-changing operation to
declare. (roffit's define in this group carries a shell redirect because its
own SYNOPSIS is `roffit < inputfile > outputfile` and its DESCRIPTION says it
"converts the inputfile to outputfile"; zbarimg's says it prints.) W3.
