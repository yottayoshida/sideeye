<!-- Filed as symfony/symfony#67446 on 2026-10-25, unchanged from this draft apart from this comment and the Title line (the issue's title). Draft for symfony/symfony. Policy: CONTRIBUTING.md, symfony.com/doc/current/contributing/code/bugs.html (no LLM rule; AI disclosed). Form 1_Bug_report.yaml: version, Description, How to reproduce required. Search: secrets:generate-keys, SodiumVault, rotate, decrypt.private — none. Owner's posts: 0. Repro: transcripts/repro-s2-php.txt -->
Title: [FrameworkBundle] `secrets:generate-keys --rotate` killed midway leaves secrets no key can decrypt

### Symfony version(s) affected
8.1.9

### Description
If `secrets:generate-keys --rotate` is killed after it writes the new key pair and before it has re-sealed every secret, the remaining secrets are still sealed to the old public key, and the old private key has been overwritten. They cannot be decrypted by anything.

`SecretsGenerateKeysCommand::execute()` decrypts all secrets into memory, then `SodiumVault::generateKeys(true)` writes `*.decrypt.private.php` in place, then `seal()` rewrites each secret one at a time.

### How to reproduce
PHP 8.4.27, Debian 13, aarch64. A prod vault with two secrets, then:

    f=$(ls config/secrets/prod/prod.DATABASE_URL.*.php)
    strace -f -P "$f" -e trace=openat -e inject=openat:signal=KILL:when=2 \
      php bin/console secrets:generate-keys --rotate --env=prod
    php bin/console secrets:list --reveal --env=prod

The second `openat` of that file is its re-seal. Afterwards: `Secret "STRIPE_SECRET" cannot be revealed as the wrong decryption key was provided`, and both values show `******`. Run through, both reveal.

### Possible Solution
Keep the old private key (e.g. write the new pair under new names and swap them in after all secrets are re-sealed).

### Additional Context
Found with [Sideeye](https://github.com/yottayoshida/sideeye), my personal open-source crash-consistency tool (no commercial interest); drafted with AI assistance and checked by me.
