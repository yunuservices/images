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
    gif_found=false
    for _ in 1 2 3 4 5 6; do
        if ls "$DUMP_DIR"/output/*.gif >/dev/null 2>&1; then
            gif_found=true
            break
        fi
        sleep 5
    done
    if [ "$gif_found" = true ]; then
        pass "heap dump converted to gif"
    else
        fail "heap dump converted to gif"
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

exit "$failed"
