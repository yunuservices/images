# Java Image Notes

## Supported Vendors and Versions
- Format: `ghcr.io/yunuservices/images:{VENDOR}_{VERSION}`
- `corretto`: `17`, `21`, `25`, `26`
- `zulu`: `17`, `21`, `25`, `26`
- `liberica`: `17`, `21`, `25`, `26`
- `temurin`: `17`, `21`, `25`, `26`
- `graalvm`: `17`, `21`, `25`

## Runtime Switches
Startup switches are passed as JVM system properties. They can be combined unless noted otherwise.

| Switch | Effect |
| --- | --- |
| `-Djemalloc=true` | Loads `libjemalloc` via `LD_PRELOAD` and exports a default `MALLOC_CONF` with RSS tuning: `background_thread:true` (a background thread purges freed memory), `dirty_decay_ms:1000` (dirty pages are returned to the OS after ~1s), `muzzy_decay_ms:0` (muzzy pages are returned immediately), `tcache_max:1024` (caps the per-thread cache size). |
| `-Ddump=true` | Implies `-Djemalloc=true`. Adds profiling options to `MALLOC_CONF`: `prof:true` (enables heap profiling), `lg_prof_interval:31` (a heap dump roughly every 2 GiB of allocation), `lg_prof_sample:17` (~128 KiB sampling interval), `prof_prefix:/home/container/dumps/jeprof` (where dump files are written). |
| `-Dmimalloc=true` | Loads `mimalloc` via `LD_PRELOAD`. Performance allocator; no profiling support. |
| `-Dnuma=true` | Runs the startup command with `numactl --interleave=all`. |
| `-Danalyse=true` | Enables a background thread-dump watcher (see [Thread dumps](#thread-dumps)). |
| `-Dkeyword=X` | Trigger keyword for the watcher. Default `Can't`, which matches Minecraft's "Can't keep up!" line. Underscores in the value become spaces, e.g. `-Dkeyword=Can't_keep_up!`. |
| `-Dinterval=N` | Watcher scan interval in seconds. Default `5`. |

Notes:
- `jemalloc` and `mimalloc` are mutually exclusive. Setting both is rejected with a warning; `-Ddump=true` counts as `jemalloc` for this check.
- If a custom `MALLOC_CONF` env var is set, the image defaults are written first and the user value is appended last, so user options override the image defaults.

## Default Behavior
- If neither allocator switch is enabled, the image runs with default `malloc`.
- If both `-Djemalloc=true` and `-Dmimalloc=true` are set, allocator selection is rejected and a warning is printed.
- If `-Dnuma=true` is set but `numactl` is unavailable, startup continues without NUMA policy.

## Native heap profiling (jeprof GIFs)
With `-Ddump=true`, raw heap dumps are written to `/home/container/dumps/jeprof/*.heap` (each typically 50-200 KiB). A background loop converts every new dump with `jeprof --gif` into `/home/container/dumps/output/*.gif` (each roughly 200-300 KiB). `jeprof` and `graphviz` ship in the image, so no extra tooling is needed.

Reading a GIF:
- Bigger nodes mean more retained native memory at that call path.
- The key rule: allocation paths that reach `je_malloc_default` **without** passing through `os#malloc` are strong leak candidates. They bypass the JVM's collector and can never be freed by GC.
- Compare successive GIFs to see which paths grow over time.

## Thread dumps
With `-Danalyse=true`, a background watcher scans the server log for a trigger keyword:
- The log file is read from `$LOG_FILE`; the default is `/home/container/logs/latest.log`.
- The keyword defaults to `Can't` (matches Minecraft's "Can't keep up!" line); underscores in `-Dkeyword=X` become spaces.
- Scans run every `-Dinterval=N` seconds (default `5`). Lower intervals catch short spikes more reliably.
- On a match, a JVM thread dump is written to `/home/container/dumps/traces/trace-<UTC timestamp>.txt` using `jcmd ... Thread.print`, with `jstack` as fallback.

Thread traces pair well with the jeprof GIFs: the trace shows the JVM view (threads, locks, stacks) and the GIF shows the native view of the same moment.

## Storage warning
Heap dumps, GIFs and thread traces accumulate on disk over time. Enable `-Ddump=true` / `-Danalyse=true` only while diagnosing an issue, and clean up the `dumps` directory afterwards.

## About musl
*I excluded musl due to permanent resolver behavior differences (SERVFAIL-on-one-family, ndots) and slow CVE release cadence (1.2.6 ships with CVE-2026-40200/6042 open).*

## License
This project is released under the MIT license. Copyright (c) yunuservices.
