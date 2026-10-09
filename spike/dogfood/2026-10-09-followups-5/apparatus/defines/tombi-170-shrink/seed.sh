set -eu
# Padded so that formatting makes the file shorter: the window the fix leaves open, if any, is between
# its write and the set_len that cuts the old tail.
rm -rf /s/tombi && mkdir -p /s/tombi/proj && cd /s/tombi/proj
printf '[a]\nb          =          1\nc          =          "x"\n[d]\ne          =          [1,          2,          3]\n' > a.toml
