Title: [Bug]: In-place run (`ocrmypdf myfile.pdf myfile.pdf`) leaves an empty file if it is interrupted while the output is written

### Describe the bug

The cookbook's "Modify a file in place" says the file will only be overwritten if OCRmyPDF is successful. If the run is killed while the output is being written, `myfile.pdf` is left at 0 bytes and the original PDF is gone. The final copy opens the output with `open('w+b')`, which empties it, and then copies the result in (`copy_final` in `src/ocrmypdf/_pipeline.py`; the same on `main` at 58048daf96).

### Steps to reproduce

```
strace -f -qq -P "$PWD/myfile.pdf" -e inject=write:signal=KILL \
  ocrmypdf -q --force-ocr myfile.pdf myfile.pdf
ls -l myfile.pdf
```

strace kills ocrmypdf at its first write to `myfile.pdf`, after the open that empties it. `myfile.pdf` goes from 537 bytes to 0. Without strace, the same command exits 0 and writes the OCRed PDF.

### Files

A one-page PDF I generated, with no personal data; I can attach it. Nothing about it is special to the failure.

### How did you download and install the software?

Linux package manager (apt)

### OCRmyPDF version

16.7.0 (Debian 13)

### Operating system

Debian 13 (trixie), arm64, in a container

### Relevant log output

None: the process is killed.

Found with [Sideeye](https://github.com/yottayoshida/sideeye), a personal open-source tool, no commercial interest. This report was written with AI assistance; every command above was run. Not measured: power loss.
