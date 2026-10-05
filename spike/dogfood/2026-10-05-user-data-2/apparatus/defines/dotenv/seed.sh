set -eu
rm -rf /s/env && mkdir -p /s/env
printf '# production secrets\nDATABASE_URL=postgres://app:pw@db/app\nSTRIPE_KEY=sk_live_aaaa\nDEBUG=false\n' > /s/env/.env
