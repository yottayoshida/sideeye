/* pin-getpid.so — declared apparatus (PROTOCOL.md: apparatus policy,
 * himalaya probe plan).
 *
 * Pins the pid component of io-maildir's minted entry names
 * ({secs}.#{counter:x}M{nanos}P{pid}.{hostname}, entry.rs:48-56): the
 * target reads it through std::process::id(), which on Linux is the
 * libc getpid symbol (client.rs:239), so a preloaded definition wins.
 * Loaded via /etc/ld.so.preload for the target's runs only — the
 * libfaketime precedent: the engine owns LD_PRELOAD, so additive
 * interposition goes through the loader's file.
 *
 * The value is fixed and recognizable; a minted name carrying P4242 in
 * a transcript is the apparatus speaking, and the comparison between
 * runs is what the determinism condition judges either way.
 *
 * Falsification (PROTOCOL.md, himalaya probe plan): the probe must show
 * the two-run split WITHOUT this library before any run uses it.
 *
 * Build: cc -shared -fPIC -o pin-getpid.so pin-getpid.c
 */
#include <sys/types.h>

pid_t getpid(void) { return (pid_t)4242; }
