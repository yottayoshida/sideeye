Title: dotenvx decrypt drops the backslash of \$, so a value with a literal $ changes

A value keeps a literal `$` by escaping it (`PW=pa\$sword`, the workaround in #240). `get` and `run` read `pa$sword`, before and after `encrypt`. `decrypt` writes it back as `PW=pa$sword`, without the backslash, and from then on it expands: `get` and `run` read `pa`, and encrypting again keeps `pa`. Inside double quotes it is the same; single quotes are not affected.

To reproduce (2.34.2 and 2.32.4, Debian 13 arm64):

```
printf '%s\n' 'PW=pa\$sword' > .env
dotenvx get PW
dotenvx encrypt > /dev/null && dotenvx get PW
dotenvx decrypt > /dev/null && grep ^PW .env && dotenvx get PW
```

This prints `pa$sword`, `pa$sword`, then `PW=pa$sword` and `pa`.

**Expected:** `decrypt` writes the value back so that it reads the same, as #406 settled for backslashes.

Found alongside the Sideeye runs for #1012; no crash is involved, so this one is a plain script.
