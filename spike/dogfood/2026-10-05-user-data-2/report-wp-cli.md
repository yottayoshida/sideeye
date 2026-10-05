Title: `wp config set` leaves wp-config.php empty when the write fails

## Summary

`wp config set` saves through `WPConfigTransformer::save()` (wp-cli/wp-config-transformer, `src/WPConfigTransformer.php`, unchanged on `main` at 28896ee):

```php
$result = file_put_contents( $this->wp_config_path, $contents, LOCK_EX );
```

With `LOCK_EX`, PHP opens the file without truncating it, takes the lock, truncates it to zero and then writes. If the write fails (a full disk) or the process is killed in between, `wp-config.php` is left empty: the database credentials, the salts and the table prefix are gone, and the site stops. The error is reported, but by then the file it was about to change is already empty.

## Steps to reproduce

1. A `wp-config.php` of 369 bytes (`DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `AUTH_KEY`, `$table_prefix`).
2. Make writes fail, standing in for a full disk: `ulimit -f 0`.
3. `wp config set DB_PASSWORD new-secret --path=. --allow-root`

## Results

```
PHP Notice:  file_put_contents(): Write of 369 bytes failed with errno=27 File too large in phar:///opt/bin/wp/vendor/wp-cli/wp-config-transformer/src/WPConfigTransformer.php on line 366
Error: Could not process the 'wp-config.php' transformation.
Reason: Failed to update the config file.
```

Exit status 1; `wp-config.php` is 0 bytes. `strace` of step 3 without the limit:

```
openat(AT_FDCWD, "/s/wp/wp-config.php", O_WRONLY|O_CREAT, 0666) = 4
ftruncate(4, 0)                   = 0
write(4, "<?php\ndefine( 'DB_NAME', 'househ"..., 369) = 369
```

Killing the process after the `ftruncate` and before the `write` leaves the same 0 bytes (replayed twice).

## Impact

Getting the site back needs the database credentials from somewhere else and new salts, which signs every user out. Nothing keeps the previous contents.

## Environment

WP-CLI 2.12.0 (phar), PHP 8.4.26, Debian 13 (trixie), Linux aarch64.

## Workarounds

Copy `wp-config.php` aside before `wp config set`.

## Directions

Two, and I have no stake in which: write a temporary file in the same directory and rename it over `wp-config.php`, keeping its mode; or keep a copy of the previous file before truncating it (may not be worth it). The write itself is in wp-config-transformer; I filed here because `wp config set` is where users meet it, and I am happy for it to move.

## Disclosure

Found with [Sideeye](https://github.com/yottayoshida/sideeye), which kills a command at each file operation and checks every file is either its old or its new content. It is a personal open-source project with no commercial interest; if you would rather not have tool-assisted reports here, say so and I will stop.

Not claimed: power loss, torn writes, Windows and macOS, and the other `wp config` subcommands that go through the same `save()`.
