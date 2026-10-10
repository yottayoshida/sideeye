# How the runs were made

Linux, from this directory, after `sh build.sh` (the box mounts read-only at `/box`, results land in `out/`):

    mkdir -p out
    docker run --rm --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-py-rs.sh
    docker run --rm --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-go.sh default
    docker run --rm --privileged --cgroupns=private --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-go.sh priv
    docker run --rm --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-xdg.sh
    docker run --rm --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-home.sh
    docker run --rm --network none -v "$PWD:/box:ro" -v "$PWD/out:/out" sideeye-faq sh /box/run-fix.sh

`run-fix.sh` came last and re-ran the cargo recipe after it stopped matching the report's whitespace; its `rs-*.txt` and `xdg-missing.txt` replace the earlier ones.

macOS, in a copy of `py/`, `rs/` and `go/` whose recipes swap `--oracle /usr/bin/strace` for `--allow-unverified` and check the verdict alone (and, for Go, drop `--observe supervised`):

    (cd py && pytest -q -p no:cacheprovider test_crash_consistency.py)   # then again with keytool.py's BUGGY = True
    (cd rs && cargo test -q && cargo test -q --features buggy)
    (cd go && go test -count=1 .)    # then again with clean.go's constant set to true

and, by hand, each command at the top of `transcripts/macos/py-interpreter-*.txt`, `rs-no-witness.txt` and `rs-fs-usage-no-sudo.txt`. The `s2.toml` those name is `py/sideeye-macos-interpreter.toml`: the same define with Homebrew's framework interpreter as the first word, the path the refusal in `py-framework-launcher.txt` names.

`transcripts/linux/go-file.txt` is `file` on the Go binary `run-go.sh` builds, in the same image.
