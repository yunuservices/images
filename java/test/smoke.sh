#!/bin/sh
# Runs inside a built image:
#   docker run --rm -i --entrypoint /bin/sh <image> -s < java/test/smoke.sh
set -u

DUMP_DIR=/home/container/dumps
failed=0

pass() {
    echo "ok   $1"
}

fail() {
    echo "FAIL $1"
    failed=1
}

# Passes when the command succeeds within the given number of seconds.
check_within() {
    name=$1
    seconds=$2
    shift 2
    while [ "$seconds" -gt 0 ]; do
        if "$@" >/dev/null 2>&1; then
            pass "$name"
            return
        fi
        sleep 1
        seconds=$((seconds - 1))
    done
    fail "$name"
}

# The checks below are re-evaluated on every attempt, so patterns are passed
# quoted and expanded here.
has_files() {
    for file in $1; do
        [ -e "$file" ] && return 0
    done
    return 1
}

file_contains() {
    for file in $2; do
        grep -q -- "$1" "$file" 2>/dev/null && return 0
    done
    return 1
}

line_count_at_least() {
    [ "$(wc -l < "$1" 2>/dev/null || echo 0)" -ge "$2" ]
}

heap_dumps_at_most() {
    [ "$(ls "$DUMP_DIR"/jeprof/*.heap 2>/dev/null | wc -l)" -le "$1" ]
}

# Runs the entrypoint with a startup command and expects a clean exit, the
# given line in the output and no ld.so preload errors.
check_startup() {
    name=$1
    expected=$2
    shift 2
    output=$( (STARTUP="$*" sh /entrypoint.sh) 2>&1 )
    status=$?
    if [ "$status" -eq 0 ] \
        && printf '%s' "$output" | grep -qF -- "$expected" \
        && ! printf '%s' "$output" | grep -q 'cannot be preloaded'; then
        pass "$name"
    else
        fail "$name"
        printf '%s\n' "$output"
    fi
}

check_startup default "Using default(malloc) allocator" java -version
check_startup jemalloc "Using allocator: jemalloc" java -Djemalloc=true -version
check_startup mimalloc "Using allocator: mimalloc" java -Dmimalloc=true -version
check_startup tcmalloc "Using allocator: tcmalloc" java -Dtcmalloc=true -version
check_startup nmt "native memory tracking enabled" java -Dnmt=true -version
check_startup arenas "at most 2 arenas" java -Darenas=2 -version

# A 1 MiB dump interval and a final dump make a short-lived JVM write heap profiles.
export MALLOC_CONF=lg_prof_interval:20,prof_final:true
check_startup dump "jemalloc profiling enabled" java -Ddump=true -version
unset MALLOC_CONF

heap_file=$(ls "$DUMP_DIR"/jeprof/*.heap 2>/dev/null | head -n 1)
if [ -n "$heap_file" ]; then
    pass "heap dump written"
else
    fail "heap dump written"
fi

if [ -n "$heap_file" ]; then
    # The profiler loop converts dumps every 10 seconds.
    report_found=false
    for _ in 1 2 3 4 5 6; do
        if ls "$DUMP_DIR"/output/*.svg >/dev/null 2>&1; then
            report_found=true
            break
        fi
        sleep 5
    done
    if [ "$report_found" = true ]; then
        pass "heap dump converted to svg"
    else
        fail "heap dump converted to svg"
        cat "$DUMP_DIR/loop.log" 2>/dev/null
    fi

    report=$(jeprof --text "$(command -v java)" "$heap_file" 2>/dev/null | grep '%')
    printf '%s\n' "$report" | head -n 10
    if printf '%s\n' "$report" | awk '$NF !~ /^0x/ { found = 1 } END { exit !found }'; then
        pass "jeprof resolves symbols"
    else
        fail "jeprof resolves symbols"
    fi
fi

check_startup nativemem "native memory profiling enabled" java -Dnativemem=true -version
recording=$(ls "$DUMP_DIR"/nativemem/*.jfr 2>/dev/null | head -n 1)
if [ -n "$recording" ] && /opt/async-profiler/bin/jfrconv --nativemem --leak "$recording" /tmp/nativemem.html >/dev/null 2>&1 \
    && [ -s /tmp/nativemem.html ]; then
    pass "nativemem recording converted"
else
    fail "nativemem recording converted"
fi

# Runs a single-file program that fills the heap until it fails.
cat > /tmp/Oom.java <<'EOF_JAVA'
class Oom {
    public static void main(String[] args) {
        var blocks = new java.util.ArrayList<long[]>();
        while (true) {
            blocks.add(new long[1 << 20]);
        }
    }
}
EOF_JAVA
(STARTUP="java -Doomdump=true -Xmx64m /tmp/Oom.java" sh /entrypoint.sh) >/dev/null 2>&1
if ls "$DUMP_DIR"/oom/*.hprof >/dev/null 2>&1; then
    pass "heap dump on OutOfMemoryError"
else
    fail "heap dump on OutOfMemoryError"
fi

# A program that runs for the given seconds, waits in a marker method, leaks
# native memory through unclosed Deflaters and writes a lag line to the log.
mkdir -p /home/container/logs
cat > /tmp/Smoke.java <<'EOF_JAVA'
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.ArrayList;
import java.util.zip.Deflater;

class Smoke {
    public static void main(String[] args) throws Exception {
        long end = System.currentTimeMillis() + Long.parseLong(args[0]) * 1000;
        Path log = Path.of("/home/container/logs/latest.log");
        var leaked = new ArrayList<Deflater>();
        while (System.currentTimeMillis() < end) {
            smokeMarker();
            leaked.add(new Deflater());
            Files.writeString(log, "Can't keep up!\n", StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        }
    }

    static void smokeMarker() throws InterruptedException {
        Thread.sleep(200);
    }
}
EOF_JAVA

# Background loops of earlier runs would otherwise touch the same files.
stop_background_loops() {
    pkill -f /entrypoint.sh 2>/dev/null || true
    sleep 1
}

# One long run exercises the background features that need a live JVM.
stop_background_loops
rm -rf "$DUMP_DIR"/jeprof/* "$DUMP_DIR"/output/* "$DUMP_DIR"/output/.done/* "$DUMP_DIR"/traces/*
export MALLOC_CONF=lg_prof_interval:23
(STARTUP="java -Ddump=true -Ddiff=true -Dkeep=2 -Djeprof_format=svg,txt -Danalyse=stack -Dkeyword=smokeMarker -Dinterval=2 -Dnmt=true -Dnmtinterval=2 -Drss=true -Drssinterval=1 /tmp/Smoke.java 20" sh /entrypoint.sh) >/dev/null 2>&1
unset MALLOC_CONF

check_within "stack watcher keeps matching dumps" 1 file_contains smokeMarker "$DUMP_DIR/traces/trace-*.txt"
check_within "nmt report written" 1 file_contains "Native Memory Tracking" "$DUMP_DIR/nmt/nmt-*.txt"
check_within "rss samples recorded" 1 line_count_at_least "$DUMP_DIR/rss.csv" 3
check_within "diff report written" 60 has_files "$DUMP_DIR/output/*.diff.svg"
check_within "txt report written" 60 has_files "$DUMP_DIR/output/*.heap.txt"
check_within "retention keeps two dumps" 90 heap_dumps_at_most 2

stop_background_loops
rm -rf "$DUMP_DIR"/traces/*
: > /home/container/logs/latest.log
(STARTUP="java -Danalyse=true -Dinterval=1 /tmp/Smoke.java 6" sh /entrypoint.sh) >/dev/null 2>&1
check_within "log watcher dumps on keyword" 1 has_files "$DUMP_DIR/traces/trace-*.txt"

exit "$failed"
