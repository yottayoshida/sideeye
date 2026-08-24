/* An FSEvents observer that records what it is given, not what it expects (#286).
 *
 * Route B asks whether FSEvents can corroborate the shim's account without
 * root. Answering that needs the raw material: the flag word as delivered,
 * the event id, and which callback delivery each entry arrived in. A
 * higher-level watcher (fswatch and friends) normalises those away, and a
 * normalisation in front of a check erases the very thing the check looks
 * for, so this talks to FSEventStreamCreate directly.
 *
 * Output is JSON Lines on stdout, one object per line, so a path holding a
 * comma or a quote cannot shift a field the way it would in CSV:
 *
 *   {"type":"config",...}   once, before anything is watched
 *   {"type":"ready",...}    after FSEventStreamStart returned true
 *   {"type":"event",...}    one per event, per callback delivery
 *   {"type":"done",...}     after the final flush
 *   {"type":"broken",...}   the harness could not measure; exit 2
 *
 * The READY/FLUSH protocol exists because FSEvents is asynchronous. A survey
 * that backgrounds a watcher and immediately runs its probe can have the
 * probe finish before the stream is started, and the resulting empty capture
 * is indistinguishable from "the observer saw nothing". So: the watcher says
 * READY only after Start returned true, and it keeps running until its stdin
 * delivers a line (or closes), at which point it calls FSEventStreamFlushSync
 * before exiting. Nothing here sleeps.
 *
 * FSEventStreamScheduleWithRunLoop is deprecated as of macOS 13, so the
 * stream is serviced by a dispatch queue. The callback therefore runs on that
 * queue while main() blocks on stdin, and both write lines, so a mutex owns
 * stdout. The alternative — a run loop plus a signalling thread — buys
 * nothing here and carries a deprecation warning.
 */
#include <CoreServices/CoreServices.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static pthread_mutex_t out_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned long batches = 0;
static unsigned long events = 0;

static uint64_t mono_ns(void) {
    struct timespec ts;
    /* CLOCK_MONOTONIC_RAW: not slewed by adjtime, which matters when the
     * question is the ordering of events milliseconds apart. */
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

/* JSON string literal, escaping what RFC 8259 requires. Bytes >= 0x20 other
 * than " and \ pass through, so UTF-8 paths stay readable in the transcript. */
static void json_str(const char *s) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
        switch (*p) {
        case '"':  fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 0x20) printf("\\u%04x", *p);
            else putchar((char)*p);
        }
    }
    putchar('"');
}

/* Every flag the SDK header defines, in header order. Decoding is a lookup,
 * not a judgement: an unknown bit is reported as leftover rather than dropped,
 * because a bit this table does not know about is exactly the kind of thing
 * that must not vanish before the analysis sees it. */
static const struct { FSEventStreamEventFlags bit; const char *name; } FLAGS[] = {
    { kFSEventStreamEventFlagMustScanSubDirs,   "MustScanSubDirs" },
    { kFSEventStreamEventFlagUserDropped,       "UserDropped" },
    { kFSEventStreamEventFlagKernelDropped,     "KernelDropped" },
    { kFSEventStreamEventFlagEventIdsWrapped,   "EventIdsWrapped" },
    { kFSEventStreamEventFlagHistoryDone,       "HistoryDone" },
    { kFSEventStreamEventFlagRootChanged,       "RootChanged" },
    { kFSEventStreamEventFlagMount,             "Mount" },
    { kFSEventStreamEventFlagUnmount,           "Unmount" },
    { kFSEventStreamEventFlagItemCreated,       "ItemCreated" },
    { kFSEventStreamEventFlagItemRemoved,       "ItemRemoved" },
    { kFSEventStreamEventFlagItemInodeMetaMod,  "ItemInodeMetaMod" },
    { kFSEventStreamEventFlagItemRenamed,       "ItemRenamed" },
    { kFSEventStreamEventFlagItemModified,      "ItemModified" },
    { kFSEventStreamEventFlagItemFinderInfoMod, "ItemFinderInfoMod" },
    { kFSEventStreamEventFlagItemChangeOwner,   "ItemChangeOwner" },
    { kFSEventStreamEventFlagItemXattrMod,      "ItemXattrMod" },
    { kFSEventStreamEventFlagItemIsFile,        "ItemIsFile" },
    { kFSEventStreamEventFlagItemIsDir,         "ItemIsDir" },
    { kFSEventStreamEventFlagItemIsSymlink,     "ItemIsSymlink" },
    { kFSEventStreamEventFlagOwnEvent,          "OwnEvent" },
    { kFSEventStreamEventFlagItemIsHardlink,    "ItemIsHardlink" },
    { kFSEventStreamEventFlagItemIsLastHardlink,"ItemIsLastHardlink" },
    { kFSEventStreamEventFlagItemCloned,        "ItemCloned" },
};

static void callback(ConstFSEventStreamRef stream, void *info, size_t n,
                     void *paths, const FSEventStreamEventFlags *flags,
                     const FSEventStreamEventId *ids) {
    (void)stream; (void)info;
    const uint64_t t = mono_ns();
    char **p = (char **)paths;

    pthread_mutex_lock(&out_lock);
    const unsigned long b = batches++;
    for (size_t i = 0; i < n; i++) {
        FSEventStreamEventFlags f = flags[i];
        printf("{\"type\":\"event\",\"batch\":%lu,\"index_in_batch\":%zu,"
               "\"event_id\":%llu,\"flags_raw\":\"0x%08x\",\"flags_decoded\":[",
               b, i, (unsigned long long)ids[i], (unsigned)f);
        FSEventStreamEventFlags seen = 0;
        int first = 1;
        for (size_t k = 0; k < sizeof FLAGS / sizeof FLAGS[0]; k++) {
            if (f & FLAGS[k].bit) {
                printf("%s\"%s\"", first ? "" : ",", FLAGS[k].name);
                first = 0;
                seen |= FLAGS[k].bit;
            }
        }
        printf("],\"flags_unknown\":\"0x%08x\",\"path\":", (unsigned)(f & ~seen));
        json_str(p[i]);
        printf(",\"mono_ns\":%llu}\n", (unsigned long long)t);
        events++;
    }
    fflush(stdout);
    pthread_mutex_unlock(&out_lock);
}

static int broken(const char *reason) {
    pthread_mutex_lock(&out_lock);
    printf("{\"type\":\"broken\",\"reason\":");
    json_str(reason);
    printf("}\n");
    fflush(stdout);
    pthread_mutex_unlock(&out_lock);
    return 2;
}

static void usage(void) {
    fprintf(stderr,
        "usage: watcher --path DIR [--latency SEC] [--no-defer] [--file-events]\n"
        "               [--mark-self] [--ignore-self] [--self-write PATH]\n"
        "Writes JSON Lines to stdout. Reads one line from stdin to flush and exit.\n");
}

int main(int argc, char **argv) {
    const char *path = NULL;
    double latency = 0.0;
    FSEventStreamCreateFlags create_flags = kFSEventStreamCreateFlagNone;
    int want_no_defer = 0, want_file_events = 0, want_mark_self = 0, want_ignore_self = 0;
    const char *self_write = NULL;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--path") && i + 1 < argc) path = argv[++i];
        else if (!strcmp(argv[i], "--latency") && i + 1 < argc) latency = atof(argv[++i]);
        else if (!strcmp(argv[i], "--no-defer")) want_no_defer = 1;
        else if (!strcmp(argv[i], "--file-events")) want_file_events = 1;
        else if (!strcmp(argv[i], "--mark-self")) want_mark_self = 1;
        else if (!strcmp(argv[i], "--ignore-self")) want_ignore_self = 1;
        else if (!strcmp(argv[i], "--self-write") && i + 1 < argc) self_write = argv[++i];
        else { usage(); return broken("unrecognised argument"); }
    }
    if (!path) { usage(); return broken("--path is required"); }

    if (want_no_defer)     create_flags |= kFSEventStreamCreateFlagNoDefer;
    if (want_file_events)  create_flags |= kFSEventStreamCreateFlagFileEvents;
    if (want_mark_self)    create_flags |= kFSEventStreamCreateFlagMarkSelf;
    if (want_ignore_self)  create_flags |= kFSEventStreamCreateFlagIgnoreSelf;

    CFStringRef cf_path = CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8);
    if (!cf_path) return broken("path is not valid UTF-8");
    CFArrayRef watch = CFArrayCreate(NULL, (const void **)&cf_path, 1, &kCFTypeArrayCallBacks);
    if (!watch) { CFRelease(cf_path); return broken("CFArrayCreate failed"); }

    FSEventStreamContext ctx = { 0, NULL, NULL, NULL, NULL };
    /* SinceNow: history is not the subject, and the header notes HistoryDone
     * is never delivered for it, so nothing has to be filtered out later. */
    FSEventStreamRef stream = FSEventStreamCreate(NULL, callback, &ctx, watch,
                                                 kFSEventStreamEventIdSinceNow,
                                                 latency, create_flags);
    if (!stream) { CFRelease(watch); CFRelease(cf_path); return broken("FSEventStreamCreate returned NULL"); }

    dispatch_queue_t queue = dispatch_queue_create("sideeye.fsevents.watcher", DISPATCH_QUEUE_SERIAL);
    FSEventStreamSetDispatchQueue(stream, queue);

    pthread_mutex_lock(&out_lock);
    printf("{\"type\":\"config\",\"path\":");
    json_str(path);
    printf(",\"latency\":%g,\"create_flags\":\"0x%08x\",\"no_defer\":%d,"
           "\"file_events\":%d,\"mark_self\":%d,\"ignore_self\":%d,\"mono_ns\":%llu}\n",
           latency, (unsigned)create_flags, want_no_defer, want_file_events,
           want_mark_self, want_ignore_self, (unsigned long long)mono_ns());
    fflush(stdout);
    pthread_mutex_unlock(&out_lock);

    /* The return value is checked because a stream that failed to start
     * produces exactly the same empty capture as a filesystem that saw
     * nothing, and only one of those is a measurement. */
    if (!FSEventStreamStart(stream)) {
        FSEventStreamInvalidate(stream);
        FSEventStreamRelease(stream);
        CFRelease(watch); CFRelease(cf_path);
        return broken("FSEventStreamStart returned false");
    }

    pthread_mutex_lock(&out_lock);
    printf("{\"type\":\"ready\",\"mono_ns\":%llu}\n", (unsigned long long)mono_ns());
    fflush(stdout);
    pthread_mutex_unlock(&out_lock);

    /* The control for MarkSelf and IgnoreSelf. Those flags are about the
     * WATCHER's own process, not about the probe, so the only way to see
     * either take effect is for this process to perform the write itself.
     * Done after READY so the event cannot race the stream's start. */
    if (self_write) {
        int fd = open(self_write, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        int e = (fd < 0) ? errno : 0;
        if (fd >= 0) close(fd);
        pthread_mutex_lock(&out_lock);
        printf("{\"type\":\"self_write\",\"path\":");
        json_str(self_write);
        printf(",\"rc\":%d,\"errno\":%d,\"mono_ns\":%llu}\n",
               fd < 0 ? -1 : 0, e, (unsigned long long)mono_ns());
        fflush(stdout);
        pthread_mutex_unlock(&out_lock);
    }

    /* Blocks until the driver says stop, or closes the pipe. */
    char line[256];
    if (!fgets(line, sizeof line, stdin)) line[0] = '\0';

    FSEventStreamFlushSync(stream);
    FSEventStreamStop(stream);
    FSEventStreamInvalidate(stream);
    FSEventStreamRelease(stream);
    dispatch_release(queue);
    CFRelease(watch);
    CFRelease(cf_path);

    pthread_mutex_lock(&out_lock);
    printf("{\"type\":\"done\",\"batches\":%lu,\"events\":%lu,\"mono_ns\":%llu}\n",
           batches, events, (unsigned long long)mono_ns());
    fflush(stdout);
    pthread_mutex_unlock(&out_lock);
    return 0;
}
