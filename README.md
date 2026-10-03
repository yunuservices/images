# Java Image Notes

## Supported Vendors and Versions
- Format: `ghcr.io/yunuservices/images:{VENDOR}_{VERSION}`
- `corretto`: `17`, `21`, `25`, `26`, `27`
- `zulu`: `17`, `21`, `25`, `26`
- `liberica`: `17`, `21`, `25`, `26`, `27`
- `temurin`: `17`, `21`, `25`, `26`, `27`
- `graalvm`: `17`, `21`, `25`

## Verifying images
Every tag is signed with keyless [cosign](https://github.com/sigstore/cosign) from GitHub Actions:

```sh
cosign verify ghcr.io/yunuservices/images:temurin_21 \
  --certificate-identity-regexp '^https://github.com/yunuservices/images/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Each build run also lists fixable HIGH and CRITICAL vulnerabilities per image in its job summary (Trivy).

## Runtime Switches
Startup switches are passed as JVM system properties. They can be combined unless noted otherwise.

| Switch | Effect |
| --- | --- |
| `-Djemalloc=true` | Loads `libjemalloc` via `LD_PRELOAD` and exports a default `MALLOC_CONF` with RSS tuning: `background_thread:true` (a background thread purges freed memory), `dirty_decay_ms:1000` (dirty pages are returned to the OS after ~1s), `muzzy_decay_ms:0` (muzzy pages are returned immediately), `tcache_max:1024` (caps the per-thread cache size). |
| `-Ddump=true` | Implies `-Djemalloc=true`. Adds profiling options to `MALLOC_CONF`: `prof:true` (enables heap profiling), `lg_prof_interval:31` (a heap dump roughly every 2 GiB of allocation), `lg_prof_sample:17` (~128 KiB sampling interval), `prof_prefix:/home/container/dumps/jeprof/jeprof-<UTC start time>` (dump files are written as `jeprof-<start>.<pid>.<seq>.i<n>.heap` in that directory, so restarts never overwrite older dumps). |
| `-Ddiff=true` | With `-Ddump=true`, also renders each heap dump against the previous dump of the same JVM run (see [Native heap profiling](#native-heap-profiling-jeprof)). |
| `-Dkeep=N` | With `-Ddump=true`, keeps only the newest `N` converted heap dumps and deletes older dumps together with their reports. Unset keeps everything. |
| `-Djeprof_format=X` | Comma-separated jeprof report formats: `svg` (default), `gif`, `txt`. |
| `-Dmimalloc=true` | Loads `mimalloc` via `LD_PRELOAD`. Performance allocator; no profiling support. |
| `-Dtcmalloc=true` | Loads `tcmalloc_minimal` from gperftools via `LD_PRELOAD`. Performance allocator; no profiling support. |
| `-Darenas=N` | Sets `MALLOC_ARENA_MAX=N` for the default glibc allocator. Ignored when another allocator is selected. |
| `-Dnuma=true` | Runs the startup command with `numactl --interleave=all`. |
| `-Dnmt=true` | Starts the JVM with `-XX:NativeMemoryTracking=summary` and writes periodic NMT reports (see [Native memory tracking](#native-memory-tracking)). |
| `-Dnmtinterval=N` | NMT report interval in seconds. Default `300`. |
| `-Dnativemem=true` | Records native allocations with async-profiler and writes leak flame graphs (see [Native memory leaks with async-profiler](#native-memory-leaks-with-async-profiler)). Cannot be combined with `-Ddump=true`. |
| `-Dnativememinterval=N` | Length of each nativemem recording in seconds. Default `3600`. |
| `-Doomdump=true` | Writes a heap dump to `/home/container/dumps/oom/heap-<UTC start time>.hprof` when the JVM throws `OutOfMemoryError`. |
| `-Drss=true` | Records the JVM's memory, thread and file descriptor counts to `/home/container/dumps/rss.csv` (see [RSS recording](#rss-recording)). |
| `-Drssinterval=N` | RSS sample interval in seconds. Default `60`. |
| `-Danalyse=true` | Enables a background thread-dump watcher that reacts to the server log (see [Thread dumps](#thread-dumps)). |
| `-Danalyse=stack` | Enables the watcher in stack mode: dumps are taken every interval and kept only when they contain the keyword. |
| `-Dkeyword=X` | Trigger keyword for the watcher. In log mode the default is `Can't`, which matches Minecraft's "Can't keep up!" line; stack mode requires it. Underscores in the value become spaces, e.g. `-Dkeyword=Can't_keep_up!`. |
| `-Dinterval=N` | Watcher interval in seconds. Default `5` in log mode, `30` in stack mode. |

Notes:
- `jemalloc`, `mimalloc` and `tcmalloc` are mutually exclusive. Setting more than one is rejected with a warning; `-Ddump=true` counts as `jemalloc` for this check.
- If a custom `MALLOC_CONF` env var is set, the image defaults are written first and the user value is appended last, so user options override the image defaults.

## glibc malloc arenas
glibc malloc creates up to 8 arenas per CPU so threads rarely share one. A JVM runs many threads, so freed memory ends up scattered across dozens of arenas and RSS stays high long after the heap shrinks. `-Darenas=2` caps that and often cuts RSS noticeably. The trade-off is more lock contention when many threads allocate native memory at once. If you can switch allocators, `-Djemalloc=true` usually reduces RSS further without that cost.

## Default Behavior
- If neither allocator switch is enabled, the image runs with default `malloc`.
- If more than one allocator switch is set, allocator selection is rejected and a warning is printed.
- If `-Dnuma=true` is set but `numactl` is unavailable, startup continues without NUMA policy.

## RSS recording
With `-Drss=true`, one row per `-Drssinterval=N` seconds is appended to `/home/container/dumps/rss.csv`:

| Column | Meaning |
| --- | --- |
| `vm_rss_kb` | Total resident memory of the JVM process. |
| `rss_anon_kb` | Anonymous memory: Java heap, metaspace and native allocations. Leaks show up here. |
| `rss_file_kb` | File-backed memory such as mapped jars and shared libraries. |
| `threads` | Thread count. Steady growth points to a thread leak. |
| `open_fds` | Open file descriptors. Steady growth points to unclosed files or sockets. |

It is the cheapest way to tell whether there is a leak at all and where to look next: if `rss_anon_kb` keeps growing while NMT stays flat, the leak is native and `-Ddump=true` will show it; if NMT grows too, the leak is inside the JVM. A day of samples at the default interval is about 100 KiB.

## Native heap profiling (jeprof)
With `-Ddump=true`, raw heap dumps are written to `/home/container/dumps/jeprof/*.heap` (each typically 50-200 KiB). A background loop converts every new dump with `jeprof` into `/home/container/dumps/output/`. The default report is an SVG graph: open it in a browser to zoom and use Ctrl+F to find a function. `-Djeprof_format=gif` restores the old GIF output, and `txt` adds a plain text list of the largest allocation paths that is easy to paste when asking for help. Each format is one extra `jeprof` run per dump on the server's CPU, so only enable the formats you read. `jeprof` and `graphviz` ship in the image, so no extra tooling is needed.

Graphs keep every node and edge (`--show_bytes --nodefraction=0 --edgefraction=0 --maxdegree=20`), so small, slow leaks are not pruned from the graph. Set the `JEPROF_OPTS` env var to replace these options.

Reading a graph:
- Bigger nodes mean more retained native memory at that call path.
- The key rule: allocation paths that reach `je_malloc_default` **without** passing through `os#malloc` are strong leak candidates. They bypass the JVM's collector and can never be freed by GC.
- Compare successive graphs to see which paths grow over time.

With `-Ddiff=true`, every dump after the first one of a JVM run also gets `*.diff.*` reports rendered with `jeprof --base=<previous dump>`. It shows only the memory that was allocated and not freed between the two dumps, which is usually the fastest way to spot a leak.

## Native memory leaks with async-profiler
`-Dnativemem=true` loads [async-profiler](https://github.com/async-profiler/async-profiler) as a JVM agent in `nativemem` mode. It samples native allocations (every 128 KiB on average) together with the full Java and native stack, so a leak shows the Java code that caused it, for example the plugin method that opened an `Inflater` and never closed it.

- A new recording starts every `-Dnativememinterval=N` seconds (default one hour) in `/home/container/dumps/nativemem/nativemem-<time>.jfr`.
- Once a recording is finished, it is converted to `nativemem-<time>-leaks.html`: a flame graph of memory that was allocated during that recording and never freed.
- jeprof and nativemem both hook native allocations, so `-Dnativemem=true` is disabled when `-Ddump=true` is set. Use nativemem to find the Java caller of a leak and jeprof when you need the allocator's own view.

## Native memory tracking
With `-Dnmt=true`, `-XX:NativeMemoryTracking=summary` is inserted right after the `java` binary of the startup command (the command has to start with `java`). Once the JVM is up, an NMT baseline is taken, and every `-Dnmtinterval=N` seconds `jcmd <pid> VM.native_memory summary.diff` is written to `/home/container/dumps/nmt/nmt-<UTC timestamp>.txt`.

NMT only sees memory the JVM itself allocates (heap, metaspace, threads, code cache, GC, internal). Use it together with `-Ddump=true`: if NMT stays flat while the process RSS grows, the leak is outside the JVM (JNI, native libraries such as zip inflaters) and the jeprof GIFs show where it is.

## Thread dumps
The watcher has two modes. Both write matches to `/home/container/dumps/traces/trace-<UTC timestamp>.txt` using `jcmd ... Thread.print`, with `jstack` as fallback.

### Log mode
With `-Danalyse=true`, the watcher scans the server log for a trigger keyword:
- The log file is read from `$LOG_FILE`; the default is `/home/container/logs/latest.log`.
- The keyword defaults to `Can't` (matches Minecraft's "Can't keep up!" line); underscores in `-Dkeyword=X` become spaces.
- Scans run every `-Dinterval=N` seconds (default `5`). Lower intervals catch short spikes more reliably.
- On a match, a JVM thread dump is written.

### Stack mode
With `-Danalyse=stack -Dkeyword=X`, a thread dump is taken every `-Dinterval=N` seconds (default `30`) and kept only when it contains the keyword. Use it to catch the Java code that calls into native memory, e.g. `-Dkeyword=java.util.zip.Inflater` for unclosed inflaters. Each dump briefly pauses the JVM at a safepoint, so avoid very low intervals on busy servers.

Thread traces pair well with the jeprof graphs: the trace shows the JVM view (threads, locks, stacks) and the graph shows the native view of the same moment.

## Storage warning
Heap dumps, reports and thread traces accumulate on disk over time. An OOM heap dump is as large as the used heap, so `-Doomdump=true` needs free disk space of at least `-Xmx`. Enable `-Ddump=true` / `-Danalyse=true` only while diagnosing an issue, and clean up the `dumps` directory afterwards. For long profiling runs, `-Dkeep=N` caps the number of heap dumps and GIFs on disk.

## About musl
*I excluded musl due to permanent resolver behavior differences (SERVFAIL-on-one-family, ndots) and slow CVE release cadence (1.2.6 ships with CVE-2026-40200/6042 open).*

## License
This project is released under the MIT license. Copyright (c) yunuservices.
