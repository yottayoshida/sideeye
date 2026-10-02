Bugzilla: bugs.ghostscript.com — Product: MuPDF, Component: mupdf (or apps), Version: 1.28.5
Summary: mutool clean with the same input and output path removes the file before writing it; a kill or a failed write in between loses the document

mutool clean a.pdf a.pdf (output path equal to the input path) removes a.pdf and then creates it again. If the process is killed between the two, a.pdf no longer exists; if the write that follows fails (a full disk, a quota, ulimit -f), a.pdf is left at 0 bytes. In both cases the original document is gone and nothing else holds a copy.

Version: mutool 1.28.5, built from mupdf-1.28.5-source.tar.gz (make HAVE_X11=no HAVE_GLUT=no build=release), Debian 13, aarch64. Debian's 1.25.1 behaves the same. Any PDF reproduces it; the attached a.pdf is a minimal 537-byte one.

The write path, from strace:

  unlinkat(AT_FDCWD, "a.pdf", 0) = 0
  openat(AT_FDCWD, "a.pdf", O_RDWR|O_CREAT|O_TRUNC, 0666) = 4
  write(4, "%PDF-1.4\n%\302\265\302\266\n% Written by MuPD"..., 589) = 589

It comes from fz_new_output_with_path in source/fitz/output.c (lines 297-304 at 3a8329655): remove(filename), then fopen(filename, "wb+"). pdf_save_document calls it with the output path as given; I found no branch for an output path that is also the input.

To reproduce without a kill:

  $ wc -c < a.pdf
  537
  $ ( ulimit -f 0; mutool clean a.pdf a.pdf )
  File size limit exceeded
  $ ls -l a.pdf
  -rw-r--r-- 1 root root 0 ... a.pdf

With a kill: SIGKILL delivered between the unlinkat and the openat leaves the directory without a.pdf (strace -e inject=openat:signal=KILL on the creating openat shows it; the checker below killed the process at the same point and replayed it twice).

Expected: when the output path is the input path, the original is still there (or the complete new file is) if mutool does not finish.

Related: bug 701797 (the O_EXCL fix) discussed this code. Its reporter noted the remove() before the fopen() and wrote that the portable fix is the mkstemp family; the reply there: "Not sure we can make use of mkstemp(), given this function's API?". Bug 697649 says clean needs a seekable output, which a temporary file in the same directory followed by a rename would still be. I have not tried a patch. One smaller thing seen on the way: the comment above that code still says the "x" flag is used, and since 1.27.0 CLOBBER is "" outside Windows, so the open on Linux no longer has O_EXCL.

Not tested: a real full disk (ENOSPC), power loss, Windows, other tools that write through fz_new_output_with_path (mutool convert, merge, ...), incremental saves.

Disclosure: I found this with sideeye (https://github.com/yottayoshida/sideeye), a crash-consistency checker I maintain as a personal open-source project, and wrote this report with the help of an AI assistant (Claude), checking it against the runs. If you would rather not have tool-assisted reports here, say so and I will stop.
