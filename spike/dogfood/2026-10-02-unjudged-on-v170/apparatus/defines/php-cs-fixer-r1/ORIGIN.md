# php-cs-fixer-r1

Revision 1 of `php-cs-fixer`, written after that define's first explore PASSed 5/5 and strace
showed why: with no `.php-cs-fixer.php` in the project, PHP CS Fixer 3.95.27 asks whether to
create one, writes `.php-cs-fixer.dist.php` and `.gitignore`, and never opens `a.php` for
writing — a PASS over a run that did not write the file. Pint
carries its own default rule set, which is why the morning's pint define never asked.

Same seed. The operation adds `--rules=@PSR12 --no-interaction`; with those, strace shows the
same `openat(... O_WRONLY|O_CREAT|O_TRUNC)` then `write` on `a.php` that the pint-bundled
v3.95.25 performs. Not a version measured by any earlier run; this is the latest release's
own phar.
