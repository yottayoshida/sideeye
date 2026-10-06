/*
 * A stand-in for CPython's Mac/Tools/pythonw.c, the launcher a framework build installs as
 * bin/python3.x (#703). macOS only.
 *
 * It does what that launcher does to an observer: it finds the interpreter at
 * ../Resources/Python.app/Contents/MacOS/Python beside its own bin directory and replaces
 * itself with it through posix_spawn with POSIX_SPAWN_SETEXEC, passing its arguments on.
 * The shim's posix_spawn records a spawn only when the call returns, which this one never
 * does, so the new image announces itself with no exec record and the chain of observation
 * breaks — the refusal spike/check-framework-launcher-macos.sh holds.
 *
 * What it does not do: set __PYVENV_LAUNCHER__, or find the interpreter through the
 * framework library's dladdr the way pythonw.c does. Neither is what the engine reads.
 */
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

extern char **environ;

int main(int argc, char **argv) {
    (void)argc;
    char self[PATH_MAX];
    uint32_t size = sizeof self;
    if (_NSGetExecutablePath(self, &size) != 0) return 120;
    char real[PATH_MAX];
    if (realpath(self, real) == NULL) return 121;
    char interp[PATH_MAX];
    if (snprintf(interp, sizeof interp, "%s/../Resources/Python.app/Contents/MacOS/Python", dirname(real)) >= (int)sizeof interp) return 122;

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) return 123;
    if (posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) return 124;
    argv[0] = interp;
    int rc = posix_spawn(NULL, interp, NULL, &attr, argv, environ);
    fprintf(stderr, "pythonw-launcher: posix_spawn of %s failed: %d\n", interp, rc);
    return 125;
}
