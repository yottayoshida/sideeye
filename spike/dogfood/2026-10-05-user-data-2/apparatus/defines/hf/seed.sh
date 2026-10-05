set -eu
rm -rf /s/hf /s/hf-in && mkdir -p /s/hf /s/hf-in
printf '[hf_a]\nhf_token = hf_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n\n[hf_b]\nhf_token = hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > /s/hf/stored_tokens
printf 'hf_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' > /s/hf/token
