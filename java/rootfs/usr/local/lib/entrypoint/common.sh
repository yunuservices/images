# shellcheck shell=sh
DUMP_DIR=/home/container/dumps

log_info() {
    printf "\033[1m\033[33mcontainer@pterodactyl~ \033[0m%s\n" "$1"
}

log_error() {
    printf "\033[1m\033[31mcontainer@pterodactyl~ \033[0m%s\n" "$1"
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
    case "$(to_lower "$1")" in
        1|true|yes|on)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prints the value of the last -D<key>=<value> in the startup command.
extract_dprop() {
    printf '%s' "$PARSED" | sed -n "s/.*-D$1=\([^ ]*\).*/\1/p" | tail -n1
}

dprop_enabled() {
    is_true "$(extract_dprop "$1")"
}

# Background helpers (jeprof, jcmd, ...) must not inherit the allocator chosen
# for the JVM: with heap profiling on they would write their own dumps.
reset_allocator_env() {
    unset LD_PRELOAD MALLOC_CONF MALLOC_ARENA_MAX
}

# Inserts JVM options right after the java binary of the startup command.
add_jvm_options() {
    java_cmd=${PARSED%% *}
    case "$java_cmd" in
        java|*/java)
            ;;
        *)
            return 1
            ;;
    esac
    PARSED="$java_cmd $*${PARSED#"$java_cmd"}"
}

find_jvm_pid() {
    pid=$(pgrep -x java 2>/dev/null | head -n 1)
    if [ -z "$pid" ]; then
        pid=$(pgrep -f java 2>/dev/null | head -n 1)
    fi
    if [ -z "$pid" ]; then
        for proc_dir in /proc/[0-9]*; do
            cmdline=$(tr '\0' ' ' < "$proc_dir/cmdline" 2>/dev/null)
            case "${cmdline%% *}" in
                */java|java)
                    pid=${proc_dir#/proc/}
                    break
                    ;;
            esac
        done
    fi
    printf '%s' "$pid"
}
