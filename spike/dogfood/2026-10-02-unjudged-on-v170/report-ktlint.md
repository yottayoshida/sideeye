Title: `ktlint -F` leaves the file empty when its write fails or the process is killed before the write

## Expected Behavior

If `ktlint -F` cannot finish rewriting a file, the file keeps its previous contents (or holds the formatted ones), and the error is reported.

## Observed Behavior

`-F` writes the formatted text with `File.writeText`, which truncates the file and then writes. If that write fails (a full disk, a quota, `ulimit -f`) or the process is killed in between, the file is left at 0 bytes and its previous contents are gone.

```console
$ ( ulimit -f 0; ktlint -F --log-level=debug Main.kt ); wc -c < Main.kt
...
11:36:18.623 [pool-1-thread-1] DEBUG com.pinterest.ktlint.rule.engine.internal.CodeFormatter -- Finished with processing file 'Main.kt'
Exception in thread "main" java.util.concurrent.ExecutionException: java.io.IOException: File too large
Caused by: java.io.IOException: File too large
0
```

(The elided debug lines are the service-loader and rule-order output.) The write is in `KtlintCommandLine.kt`, lines 532-537 at `616af93`: `code.filePath?.toFile()?.writeText(formattedFileContent, UTF_8)`.

## Steps to Reproduce

1. `printf 'fun main( ) {\n    println( "hi" )\n}\n' > Main.kt`
2. `( ulimit -f 0; ktlint -F Main.kt )`
3. `wc -c < Main.kt` prints `0` (it was 36).

`ulimit -f 0` stands in for a write that fails after the truncation. Killing the process between the truncating open and the write leaves the same empty file (reproduced twice). Kotlin sources are usually in version control, but uncommitted edits are lost with the file.

One possible direction, not tried: write to a temporary file in the same directory and move it over the original. That replaces the file, so its permissions and a symlinked path would need care.

Not tested: a real full disk (`ENOSPC`), power loss, other platforms, the Gradle and Maven integrations, 2.0.0-ALPHA-4 (the same line by reading).

Disclosure: I found this with [sideeye](https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.

## Your Environment
* Version of ktlint used: 1.8.0
* Relevant parts of the `.editorconfig` settings: none
* Name and version (or code for custom task) of integration used (Gradle plugin, Maven plugin, command line, custom Gradle task): command line (the release's `ktlint` executable jar)
* Version of Gradle used (if applicable): n/a
* Operating System and version: Debian 13 (trixie), aarch64, in a container; OpenJDK 21.0.12
