# shellcheck shell=sh

# Writes a heap dump when the JVM runs out of heap memory. The file name holds
# the start time because the JVM usually runs as PID 1.
enable_oom_heap_dump() {
    mkdir -p "$DUMP_DIR/oom"
    if ! add_jvm_options -XX:+HeapDumpOnOutOfMemoryError "-XX:HeapDumpPath=$DUMP_DIR/oom/heap-$(date -u +%Y%m%d-%H%M%S).hprof"; then
        log_error "-Doomdump=true needs the startup command to start with java, OOM heap dumps disabled."
        return
    fi
    log_info "heap dump on OutOfMemoryError enabled (→ $DUMP_DIR/oom)"
}
