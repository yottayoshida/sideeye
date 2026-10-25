<!--
Draft for saltstack/salt, 2026-10-25. Not filed.
Policy read: CONTRIBUTING.rst and CODE_OF_CONDUCT.md (no rule on AI-written text); .github/ISSUE_TEMPLATE/bug.yml (required: What happened?, Type of salt install, Major version, OS, salt --versions-report; all filled).
Freshness: tracker searched one word at a time (grains.setval, setval, truncated, "grains file", "grains lost"): #58411 is two writers racing (closed not planned 2026-10-15). Owner's prior filings here: 0.
Latest release v3008.4 (measured, onedir). Source at v3008.4: salt/modules/grains.py setvals.
Reproduced without Sideeye: transcripts/plain-repro-s3.txt; versions-report: transcripts/salt-versions-report.txt.
Title: [Bug]: grains.setval killed mid-write empties the grains file, and every grain set before it is lost
-->

### What happened?

If `salt-call --local grains.setval` is killed while it saves the grains file, every grain set before is lost, and Salt reads the empty file as no grains, with no error.

`setvals` in `salt/modules/grains.py` opens the file with `fopen(gfn, "w+")`, which truncates it, and then dumps the YAML. If the process is killed between the two, the file is 0 bytes. The next read turns it into `{}`, so `grains.item` returns empty values and the next `setval` writes only its own key. #58411 was two writers at once; this is one process.

Reproduced with the 3008.4 onedir on Debian 13 (aarch64). Start from a grains file with 7 grains (148 bytes), then run `strace -f -P <config dir>/grains -e inject=write:signal=KILL salt-call -c <config dir> --local grains.setval maintainer ops-oncall`. The file is left at 0 bytes, and `grains.item datacenter roles` returns both empty. The next `setval` leaves only `maintainer: ops-oncall` (23 bytes). Without the kill, the file holds 8 grains (171 bytes).

A possible fix: write a temporary file in the same directory and rename it over the grains file.

Found with Sideeye (https://github.com/yottayoshida/sideeye), my personal open-source crash-consistency tool, with no commercial interest; drafted with AI assistance and checked by me.

### Type of salt install

other (please specify in bug details): the 3008.4 onedir tarball from the GitHub release.

### Major version

3008.x

### What supported OS are you seeing the problem on?

debian-13

### salt --versions-report output

```yaml
Salt Version:
          Salt: 3008.4
 
Python Version:
        Python: 3.14.7 (main, Sep 30 2026, 03:32:40) [GCC 11.2.0]
 
Dependency Versions:
          cffi: 2.0.0
      cherrypy: 18.10.0
  cryptography: 50.0.1
      dateutil: 2.9.0.post0
     docker-py: Not Installed
         gitdb: 4.0.12
     gitpython: 3.2.0
        Jinja2: 3.1.6
       libgit2: Not Installed
  looseversion: 1.3.0
      M2Crypto: Not Installed
          Mako: Not Installed
       msgpack: 1.2.1
  msgpack-pure: Not Installed
  mysql-python: Not Installed
     packaging: 24.0
     pycparser: 3.00
      pycrypto: Not Installed
  pycryptodome: 3.23.0
        pygit2: Not Installed
  python-gnupg: 0.5.6
        PyYAML: 6.0.3
         PyZMQ: 27.1.0
        relenv: 0.22.27
         smmap: 5.0.2
       timelib: 0.3.0
       Tornado: 6.5.10
           ZMQ: 4.3.5
 
Salt Package Information:
  Package Type: onedir
 
System Versions:
          dist: debian 13.7 trixie
        locale: utf-8
       machine: aarch64
       release: 7.0.14-linuxkit
        system: Linux
       version: Debian GNU/Linux 13.7 trixie
```
