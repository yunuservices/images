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

# Dump names start with jeprof-<start>.<pid>, so one value means only the JVM
# wrote dumps and none of the background helpers did.
heap_dumps_from_one_process() {
    [ "$(ls "$DUMP_DIR"/jeprof/*.heap 2>/dev/null | sed 's#.*/##' | cut -d. -f1-2 | sort -u | wc -l)" -eq 1 ]
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

# A Sectigo cross-sign of one of the compromised eMudhra intermediates
# (CVE-2026-91403) must be rejected even by the root that issued it.
cat > /tmp/Blocked.java <<'EOF_JAVA'
import java.io.ByteArrayInputStream;
import java.security.cert.CertPathValidator;
import java.security.cert.CertPathValidatorException;
import java.security.cert.CertificateFactory;
import java.security.cert.PKIXParameters;
import java.security.cert.TrustAnchor;
import java.security.cert.X509Certificate;
import java.util.List;
import java.util.Set;

class Blocked {
    // EM DV TLS CA - G3B, one of the compromised intermediates.
    static final String INTERMEDIATE = """
        -----BEGIN CERTIFICATE-----
        MIIDaDCCAu6gAwIBAgIQAKSu5njyM2K0wORgt3LyFDAKBggqhkjOPQQDAzBWMQsw
        CQYDVQQGEwJJTjElMCMGA1UECgwcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRl
        ZDEgMB4GA1UEAwwXZW1TaWduIFJvb3QgVExTIENBIC0gRzMwHhcNMjUwNDMwMTU1
        NDA4WhcNNDAwNDI4MTgzMDAwWjA/MQswCQYDVQQGEwJOTDETMBEGA1UECgwKZU11
        ZGhyYSBCVjEbMBkGA1UEAwwSRU0gRFYgVExTIENBIC0gRzNCMHYwEAYHKoZIzj0C
        AQYFK4EEACIDYgAE557ZwEqXc8RzXlERHahawr1eZKs3S4DhLLwgOOweTw47gS/J
        hZ4eZ6+wTi+LyX90hbplqpEe6KTkW2LVzAPVa+Z4s8OMtNyTfKJGDiOEU8iSk10p
        1E+R4VYGtjzO2rRoo4IBljCCAZIwHwYDVR0jBBgwFoAU4TqrIXzx401UrtRyt/2L
        WUIgkFQwHQYDVR0OBBYEFOIeL+ccGTkOVUtiwSAkVzUkiiUUMB0GA1UdJQQWMBQG
        CCsGAQUFBwMBBggrBgEFBQcDAjBdBgNVHSAEVjBUMDkGCysGAQQBg44hAQABMCow
        KAYIKwYBBQUHAgEWHGh0dHA6Ly9yZXBvc2l0b3J5LmVtc2lnbi5jb20wDQYLKwYB
        BAGDjiEBAmQwCAYGZ4EMAQIBMHUGCCsGAQUFBwEBBGkwZzAkBggrBgEFBQcwAYYY
        aHR0cDovL29jc3AtYi5lbXNpZ24uY29tMD8GCCsGAQUFBzAChjNodHRwOi8vcmVw
        b3NpdG9yeS5lbXNpZ24uY29tL2NlcnRzL0VNRFZUTFNDQUczQi5wN2MwNwYDVR0f
        BDAwLjAsoCqgKIYmaHR0cDovL2NybC5lbXNpZ24uY29tLz9yb290dGxzY2FnMy5j
        cmwwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQAwCgYIKoZIzj0E
        AwMDaAAwZQIwLmsGXi6oFMJ2klkcEMXMug6gvxQWZWkewiDWVzQyl2L6z6DuQfPO
        Ibh1grvdULDCAjEAxZvLlxUavG69J6wnSjC8XBbqNIQsJ6CE2QdNOe84Ptxb6VG8
        gt2TlfJbHii+KNvK
        -----END CERTIFICATE-----
        """;

    // emSign Root TLS CA - G3, the root that issued it.
    static final String ROOT = """
        -----BEGIN CERTIFICATE-----
        MIICKTCCAa+gAwIBAgIQDnYGcvFDRZ/I/gqwvAXjlDAKBggqhkjOPQQDAzBWMQsw
        CQYDVQQGEwJJTjElMCMGA1UECgwcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRl
        ZDEgMB4GA1UEAwwXZW1TaWduIFJvb3QgVExTIENBIC0gRzMwHhcNMjQwMjA4MDgx
        OTMyWhcNNDkwMjA3MDgxOTMyWjBWMQswCQYDVQQGEwJJTjElMCMGA1UECgwcZU11
        ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAwwXZW1TaWduIFJvb3Qg
        VExTIENBIC0gRzMwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAARfD9w/q1cWxL6D9bMG
        H6CQ4u+gAV6GN9s+PwQx9Bl4hC+0iU8QOk8mWO/RwXQy10DCSxT8vSIJClHKp+Ao
        4qJKdYeV0SwZ7LMQziyLfxIUOY6Grja/sQFwLKYf8EdDXAyjQjBAMB0GA1UdDgQW
        BBThOqshfPHjTVSu1HK3/YtZQiCQVDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/
        BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjBhCFTkly7Yl7+s4hiw+k6ZJTXT2AiI
        rvmsmfqPr5E7ecwXb6kXA5LTFd6rjwTuV3sCMQC9w6ZSbVq1mveMO6dKFziOzClT
        KCT2RFT6yXtq6nzgRICgBmiXbJAXsmZ8yAwjyWc=
        -----END CERTIFICATE-----
        """;

    public static void main(String[] args) throws Exception {
        var factory = CertificateFactory.getInstance("X.509");
        var intermediate = (X509Certificate) factory.generateCertificate(new ByteArrayInputStream(INTERMEDIATE.getBytes()));
        var root = (X509Certificate) factory.generateCertificate(new ByteArrayInputStream(ROOT.getBytes()));
        var params = new PKIXParameters(Set.of(new TrustAnchor(root, null)));
        params.setRevocationEnabled(false);
        try {
            CertPathValidator.getInstance("PKIX").validate(factory.generateCertPath(List.of(intermediate)), params);
        } catch (CertPathValidatorException e) {
            if (String.valueOf(e.getMessage()).startsWith("Untrusted certificate")) {
                return;
            }
            throw e;
        }
        throw new IllegalStateException("the compromised intermediate still validates");
    }
}
EOF_JAVA
if output=$(java /tmp/Blocked.java 2>&1); then
    pass "compromised eMudhra intermediates blocked"
else
    fail "compromised eMudhra intermediates blocked"
    printf '%s\n' "$output"
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
(STARTUP="java -Ddump=true -Ddiff=true -Djeprof_format=svg,txt -Danalyse=stack -Dkeyword=smokeMarker -Dinterval=2 -Dnmt=true -Dnmtinterval=2 -Drss=true -Drssinterval=1 /tmp/Smoke.java 20" sh /entrypoint.sh) >/dev/null 2>&1
unset MALLOC_CONF

check_within "stack watcher keeps matching dumps" 1 file_contains smokeMarker "$DUMP_DIR/traces/trace-*.txt"
check_within "nmt report written" 1 file_contains "Native Memory Tracking" "$DUMP_DIR/nmt/nmt-*.txt"
check_within "rss samples recorded" 1 line_count_at_least "$DUMP_DIR/rss.csv" 3
check_within "diff report written" 60 has_files "$DUMP_DIR/output/*.diff.svg"
check_within "txt report written" 60 has_files "$DUMP_DIR/output/*.heap.txt"
check_within "only the jvm writes heap dumps" 1 heap_dumps_from_one_process

# Retention runs after the profiler loop has converted every dump, so it is
# checked with already converted dumps of an older run to stay independent of
# conversion time.
stop_background_loops
rm -rf "$DUMP_DIR"/jeprof/* "$DUMP_DIR"/output/.done/*
for seq in 0 1 2 3; do
    name="jeprof-20000101-000000.1.$seq.i$seq.heap"
    : > "$DUMP_DIR/jeprof/$name"
    : > "$DUMP_DIR/output/.done/$name"
done
(STARTUP="java -Ddump=true -Dkeep=2 -version" sh /entrypoint.sh) >/dev/null 2>&1
check_within "retention keeps two dumps" 15 heap_dumps_at_most 2
if ! heap_dumps_at_most 2; then
    ls -l "$DUMP_DIR"/jeprof
    tail -n 20 "$DUMP_DIR/loop.log" 2>/dev/null
fi

stop_background_loops
rm -rf "$DUMP_DIR"/traces/*
: > /home/container/logs/latest.log
(STARTUP="java -Danalyse=true -Dinterval=1 /tmp/Smoke.java 6" sh /entrypoint.sh) >/dev/null 2>&1
check_within "log watcher dumps on keyword" 1 has_files "$DUMP_DIR/traces/trace-*.txt"

exit "$failed"
