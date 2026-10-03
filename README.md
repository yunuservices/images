# Java Image Notes

## Supported Vendors and Versions
- Format: `ghcr.io/yunuservices/images:{VENDOR}_{VERSION}`
- `corretto`: `17`, `21`, `25`, `26`, `27`
- `zulu`: `17`, `21`, `25`, `26`
- `liberica`: `17`, `21`, `25`, `26`, `27`
- `temurin`: `17`, `21`, `25`, `26`, `27`
- `graalvm`: `17`, `21`, `25`

## Runtime Switches
Startup switches are passed as JVM system properties. They can be combined unless noted otherwise.

| Switch | Effect |
| --- | --- |
| `-Djemalloc=true` | Loads `libjemalloc` via `LD_PRELOAD` and exports a default `MALLOC_CONF` with RSS tuning: `background_thread:true` (a background thread purges freed memory), `dirty_decay_ms:1000` (dirty pages are returned to the OS after ~1s), `muzzy_decay_ms:0` (muzzy pages are returned immediately), `tcache_max:1024` (caps the per-thread cache size). |
| `-Ddump=true` | Implies `-Djemalloc=true`. Adds profiling options to `MALLOC_CONF`: `prof:true` (enables heap profiling), `lg_prof_interval:31` (a heap dump roughly every 2 GiB of allocation), `lg_prof_sample:17` (~128 KiB sampling interval), `prof_prefix:/home/container/dumps/jeprof/jeprof-<UTC start time>` (dump files are written as `jeprof-<start>.<pid>.<seq>.i<n>.heap` in that directory, so restarts never overwrite older dumps). |
| `-Ddiff=true` | With `-Ddump=true`, also renders each heap dump against the previous dump of the same JVM run (see [Native heap profiling](#native-heap-profiling-jeprof-gifs)). |
| `-Dkeep=N` | With `-Ddump=true`, keeps only the newest `N` converted heap dumps and deletes older dumps together with their GIFs. Unset keeps everything. |
| `-Dmimalloc=true` | Loads `mimalloc` via `LD_PRELOAD`. Performance allocator; no profiling support. |
| `-Dtcmalloc=true` | Loads `tcmalloc_minimal` from gperftools via `LD_PRELOAD`. Performance allocator; no profiling support. |
| `-Dnuma=true` | Runs the startup command with `numactl --interleave=all`. |
| `-Dnmt=true` | Starts the JVM with `-XX:NativeMemoryTracking=summary` and writes periodic NMT reports (see [Native memory tracking](#native-memory-tracking)). |
| `-Dnmtinterval=N` | NMT report interval in seconds. Default `300`. |
| `-Danalyse=true` | Enables a background thread-dump watcher that reacts to the server log (see [Thread dumps](#thread-dumps)). |
| `-Danalyse=stack` | Enables the watcher in stack mode: dumps are taken every interval and kept only when they contain the keyword. |
| `-Dkeyword=X` | Trigger keyword for the watcher. In log mode the default is `Can't`, which matches Minecraft's "Can't keep up!" line; stack mode requires it. Underscores in the value become spaces, e.g. `-Dkeyword=Can't_keep_up!`. |
| `-Dinterval=N` | Watcher interval in seconds. Default `5` in log mode, `30` in stack mode. |

Notes:
- `jemalloc`, `mimalloc` and `tcmalloc` are mutually exclusive. Setting more than one is rejected with a warning; `-Ddump=true` counts as `jemalloc` for this check.
- If a custom `MALLOC_CONF` env var is set, the image defaults are written first and the user value is appended last, so user options override the image defaults.

## Default Behavior
- If neither allocator switch is enabled, the image runs with default `malloc`.
- If more than one allocator switch is set, allocator selection is rejected and a warning is printed.
- If `-Dnuma=true` is set but `numactl` is unavailable, startup continues without NUMA policy.

## Native heap profiling (jeprof GIFs)
With `-Ddump=true`, raw heap dumps are written to `/home/container/dumps/jeprof/*.heap` (each typically 50-200 KiB). A background loop converts every new dump with `jeprof --gif` into `/home/container/dumps/output/*.gif` (each roughly 200-300 KiB). `jeprof` and `graphviz` ship in the image, so no extra tooling is needed.

GIFs keep every node and edge (`--show_bytes --nodefraction=0 --edgefraction=0 --maxdegree=20`), so small, slow leaks are not pruned from the graph. Set the `JEPROF_OPTS` env var to replace these options.

Reading a GIF:
- Bigger nodes mean more retained native memory at that call path.
- The key rule: allocation paths that reach `je_malloc_default` **without** passing through `os#malloc` are strong leak candidates. They bypass the JVM's collector and can never be freed by GC.
- Compare successive GIFs to see which paths grow over time.

With `-Ddiff=true`, every dump after the first one of a JVM run also gets a `*.diff.gif` rendered with `jeprof --base=<previous dump>`. It shows only the memory that was allocated and not freed between the two dumps, which is usually the fastest way to spot a leak.

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

Thread traces pair well with the jeprof GIFs: the trace shows the JVM view (threads, locks, stacks) and the GIF shows the native view of the same moment.

## Storage warning
Heap dumps, GIFs and thread traces accumulate on disk over time. Enable `-Ddump=true` / `-Danalyse=true` only while diagnosing an issue, and clean up the `dumps` directory afterwards. For long profiling runs, `-Dkeep=N` caps the number of heap dumps and GIFs on disk.

## About musl
*I excluded musl due to permanent resolver behavior differences (SERVFAIL-on-one-family, ndots) and slow CVE release cadence (1.2.6 ships with CVE-2026-40200/6042 open).*

## License
This project is released under the MIT license. Copyright (c) yunuservices.
