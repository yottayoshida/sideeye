/*
 * Does dyld interposition reach a call the target resolved at runtime?  (#299)
 *
 * `shim/src/macos.zig` states the mechanism it relies on: dyld "rewrites calls that
 * cross image boundaries". Two of the three edges that follow from that sentence were
 * already measured — a target calling libc directly is reached (every shipped CI leg
 * assumes it), and libSystem calling its own exports internally is not (ADR 0005, and
 * spike/fsusage/phase0/RESULTS-mkstemp.md for mkstemp on macOS). The third edge, a
 * target that looks a symbol up at runtime and calls through the pointer, had no
 * measurement anywhere in this repository.
 *
 * Five modes, differing ONLY in how the two state-changing calls are resolved:
 *
 *   direct   this image's own bindings, which dyld rewrites when the shim loads.
 *   default  dlsym(RTLD_DEFAULT, …)  — the ordinary "find me this symbol".
 *   next     dlsym(RTLD_NEXT, …)     — measured because the sentences this feeds do
 *                                       not say which form, and a form nobody measured
 *                                       is a form nobody should be quoted about.
 *   handle   dlsym(dlopen("/usr/lib/libSystem.B.dylib"), …) — the scoped lookup a
 *                                       program actually writes. The umbrella does not
 *                                       define these symbols; it re-exports them.
 *   defining dlsym(dlopen("/usr/lib/system/libsystem_kernel.dylib"), …) — the handle
 *                                       that names the image the symbol really comes
 *                                       from, which is the form that could plausibly
 *                                       differ. Measured because "a scoped lookup"
 *                                       covers two different things and only one of
 *                                       them was being run.
 *
 * The write and the close are issued directly in EVERY mode. They are the positive
 * control: a run that records nothing at all is a broken apparatus, not a finding, and
 * without something recorded the modes cannot be told apart from a dead run.
 *
 * `open` is variadic, so its pointer is declared variadic too. On arm64 the two
 * conventions place arguments differently, and calling one through the other's type is
 * undefined — which would make a difference in the counts an artefact of this file
 * rather than a fact about dyld. `mkdir` is not variadic and is measured beside it for
 * the same reason: an effect in only one of them is about calling conventions, an
 * effect in both is about interposition. The file's permission bits are the readable
 * consequence of that marshalling going right, which is why a caller can check them.
 *
 * `resolved_via:` is a label, and a reader should not take it for more. Review broke an
 * earlier version of this file with a one-line mutant that forced the direct path while
 * still being invoked as `dlsym`, and no assertion could tell — because under
 * interposition every form above returns the SAME pointer, which is the result this
 * file exists to record. The modes are observationally identical by construction once
 * the answer is yes; that is not a weakness of the instrument, it is the finding. What
 * can still be asserted, and is, is that the two calls resolve into the shim while a
 * symbol the shim does not wrap does not — the pair below.
 *
 * `image_of` reports which file a pointer lives in rather than the pointer itself:
 * two addresses being equal says they are the same function, not which one, and ASLR
 * makes the number unquotable. The lines print to stderr because `sideeye preflight`
 * relays the operation's stderr into its own output and does not relay its stdout —
 * measured by moving them from one stream to the other and watching them disappear.
 *
 *   cc -o toy-reach spike/toys/toy_reach.c
 *   toy-reach direct|default|next|handle|defining <path-prefix>
 */
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef int (*open_fn)(const char *, int, ...);
typedef int (*mkdir_fn)(const char *, mode_t);

/* The basename of the image a pointer lives in, or a reason it could not be named.
 * dladdr's dli_fname is the whole path and the interesting part is the last
 * component; the rest is a property of where the run happened. */
static const char *image_of(void *p) {
    Dl_info info;
    if (!p) return "(null)";
    if (!dladdr(p, &info) || !info.dli_fname) return "(unnamed)";
    const char *slash = strrchr(info.dli_fname, '/');
    return slash ? slash + 1 : info.dli_fname;
}

/* No column padding: the caller greps these lines, and a format that pads to a width
 * makes the assertion depend on how long the longest symbol name happens to be. */
static void report(const char *name, void *used) {
    fprintf(stderr, "symbol=%s used_in=%s\n", name, image_of(used));
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: toy-reach direct|default|next|handle|defining <path-prefix>\n");
        return 2;
    }

    open_fn open_p;
    mkdir_fn mkdir_p;
    const char *resolved_via;

    if (!strcmp(argv[1], "direct")) {
        open_p = open;
        mkdir_p = mkdir;
        resolved_via = "bound";
    } else if (!strcmp(argv[1], "default")) {
        open_p = (open_fn)dlsym(RTLD_DEFAULT, "open");
        mkdir_p = (mkdir_fn)dlsym(RTLD_DEFAULT, "mkdir");
        resolved_via = "RTLD_DEFAULT";
    } else if (!strcmp(argv[1], "next")) {
        open_p = (open_fn)dlsym(RTLD_NEXT, "open");
        mkdir_p = (mkdir_fn)dlsym(RTLD_NEXT, "mkdir");
        resolved_via = "RTLD_NEXT";
    } else if (!strcmp(argv[1], "handle") || !strcmp(argv[1], "defining")) {
        /* Both are already loaded, so this bumps a reference rather than opening
         * anything — which matters, because a dlopen that read a file would add
         * operations to these modes and the counts would stop being comparable. */
        int umbrella = !strcmp(argv[1], "handle");
        const char *path = umbrella ? "/usr/lib/libSystem.B.dylib"
                                    : "/usr/lib/system/libsystem_kernel.dylib";
        void *h = dlopen(path, RTLD_LAZY);
        if (!h) { fprintf(stderr, "dlopen %s failed: %s\n", path, dlerror()); return 1; }
        open_p = (open_fn)dlsym(h, "open");
        mkdir_p = (mkdir_fn)dlsym(h, "mkdir");
        resolved_via = umbrella ? "handle" : "defining";
    } else {
        fprintf(stderr, "unknown mode: %s\n", argv[1]);
        return 2;
    }

    if (!open_p || !mkdir_p) {
        fprintf(stderr, "%s: could not resolve open/mkdir: %s\n", argv[1], dlerror());
        return 1;
    }

    char dir[1024], file[1024];
    snprintf(dir, sizeof(dir), "%s-dir", argv[2]);
    snprintf(file, sizeof(file), "%s-file", argv[2]);

    if (mkdir_p(dir, 0700) != 0) { perror("mkdir"); return 1; }

    int fd = open_p(file, O_CREAT | O_RDWR | O_EXCL, 0600);
    if (fd < 0) { perror("open"); return 1; }

    /* Always direct, in every mode. */
    if (write(fd, "hello, world\n", 13) != 13) { perror("write"); return 1; }
    if (close(fd) != 0) { perror("close"); return 1; }

    fprintf(stderr, "mode: %s\n", argv[1]);
    fprintf(stderr, "resolved_via: %s\n", resolved_via);
    fprintf(stderr, "created: %s and %s\n", dir, file);
    report("open", (void *)open_p);
    report("mkdir", (void *)mkdir_p);

    /* A negative control for the reporter itself, and only for that. `getpid` is not
     * in the shim's interpose table, so a run in which every line names the shim is a
     * run whose `image_of` has stopped reading anything.
     *
     * It is NOT a matched control for the mode: this lookup is always RTLD_DEFAULT,
     * whatever form the two calls above used. Matching it would prove less, not more —
     * what it has to hold fixed is the reporter, and the reporter does not know how the
     * pointer it was handed came to be. Resolved and reported, never called. */
    report("getpid", dlsym(RTLD_DEFAULT, "getpid"));
    return 0;
}
