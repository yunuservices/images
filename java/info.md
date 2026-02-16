# Java Image Notes

## Supported Vendors and Versions
- Format: `ghcr.io/yunuservices/images:{VENDOR}_{VERSION}`
- `corretto`: `21`, `25`
- `zulu`: `21`, `25`
- `liberica`: `21`, `25`
- `microsoft`: `21`, `25`
- `temurin`: `21`, `25`
- `graalvm`: `21`, `25`

## Runtime Switches
- `-Djemalloc=true`
  - Enables `jemalloc` via `LD_PRELOAD`.
- `-Dmimalloc=true`
  - Enables `mimalloc` via `LD_PRELOAD`.
- `-Dnuma=true`
  - Runs startup command with `numactl --interleave=all`.

## Default Behavior
- If neither allocator switch is enabled, the image runs with default `malloc`.
- If both `-Djemalloc=true` and `-Dmimalloc=true` are set, allocator selection is rejected and a warning is printed.
- If `-Dnuma=true` is set but `numactl` is unavailable, startup continues without NUMA policy.

## Profiling Notes
- `jemalloc` is strong for heap profiling workflows.
  - It supports build-time profiling (`--enable-prof`) and runtime profiling controls via `MALLOC_CONF`.
  - `jeprof` tooling is part of common jemalloc profiling workflows.
- `mimalloc` is strong for performance and diagnostics, but not equivalent to jemalloc + jeprof profiling flow.
  - Official docs emphasize performance, stats, and tooling integration (for example ETW/diagnostics), not a direct jeprof-style heap profiling pipeline.