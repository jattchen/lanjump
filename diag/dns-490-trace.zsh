#!/bin/zsh
# One-shot recorder for the pair-address fake dns-sd used by host selftest.
# Does not change product stop conditions. Does not write the real HOME,
# SSH config, or keychain. Timing goes only to the trace file.
#
# Observable events (CLOCK_MONOTONIC ns, CLOCK_REALTIME ns, pid, name):
#   stamp product_sha|uname|result|...        identity and chosen line; not a timer
#   proc_start argv=...                       each fake dns-sd process
#   line text=...                             stdout write and this record share
#                                             one SIGTERM-blocked section
#   sleep_begin requested_ms=N                before usleep of the gap
#   sleep_end elapsed_ns=N                    usleep returned
#   sleep_skip requested_ms=0                 fixture delay was zero
#   hold                                      output finished; waiting in pause
#   sigterm during_sleep=0|1                  this child received SIGTERM
#   shell_epochrealtime begin= end= wall_ms=  shell clock around the function
#
# sigterm is not the parent run_timed decision instant.
# shell_epochrealtime is the function wall clock. It is not a 500ms verdict.
# A missing line event means that stdout write did not finish.
#
# Exit 0: the -G process logged both addresses and then received SIGTERM.
# Exit 2: the probe did not observe that shape. The trace file is still written.

emulate -L zsh
setopt no_unset pipefail

if [[ $# -ne 1 || ${1:-} == -* ]]; then
  print -u2 "usage: zsh diag/dns-490-trace.zsh TRACE_FILE"
  exit 2
fi

trace=$1
root=${0:A:h:h}
product=${LJ_PRODUCT_ZSH:-$root/lib/lanjump.zsh}
src=$root/diag/dns-sd-trace.c
marker='if [[ ${1:-} == --digit-selftest ]]; then'
work=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-490.XXXXXX") || exit 2
bin=$work/dns-sd
typeset -gi diag_cleaned=0

diag_cleanup() {
  local pid
  local -a own_pids
  (( diag_cleaned )) && return
  typeset -g diag_cleaned=1
  # Background jobs this shell started. The product kill/wait covers the
  # normal path; this only reaps leftovers, and does not use pgrep.
  own_pids=(${(f)"$(jobs -p 2>/dev/null)"})
  for pid in "${own_pids[@]}"; do
    [[ $pid == <-> ]] || continue
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${own_pids[@]}"; do
    [[ $pid == <-> ]] || continue
    wait "$pid" 2>/dev/null || true
  done
  if [[ -n $work && -d $work ]]; then
    rm -rf "$work"
  fi
}

export HOME=$work/home
export TMPDIR=$work/tmp
mkdir -p "$HOME" "$TMPDIR" || exit 2
: >"$trace" || exit 2

if [[ ! -f $product || ! -f $src ]]; then
  print -u2 "diag: missing product or tracer source"
  exit 2
fi
if ! grep -F -qx -- "$marker" "$product"; then
  print -u2 "diag: refuse to source product; cut marker missing"
  exit 2
fi

awk -v marker="$marker" '$0 == marker { exit } { print }' "$product" >"$work/product-funcs.zsh"
if grep -F -q -- "$marker" "$work/product-funcs.zsh" || grep -F -q -- '需要交互式终端' "$work/product-funcs.zsh"; then
  print -u2 "diag: product truncate failed"
  exit 2
fi

source "$work/product-funcs.zsh"
# Product top-level traps replace anything installed earlier, and
# restore_tty runs stty against the real terminal.
restore_tty() { : }
on_exit() { : }
trap diag_cleanup EXIT
trap 'diag_cleanup; exit 130' INT
trap 'diag_cleanup; exit 143' TERM
if [[ ${functions[restore_tty]} == *stty* ]]; then
  print -u2 "diag: restore_tty still touches the tty"
  exit 2
fi
trap >"$work/trap-list"
if ! grep -F -q 'diag_cleanup EXIT' "$work/trap-list" \
  || ! grep -F -q 'diag_cleanup' "$work/trap-list" \
  || ! grep -F -q ' INT' "$work/trap-list" \
  || ! grep -F -q ' TERM' "$work/trap-list"; then
  print -u2 "diag: cleanup traps were not installed after source"
  exit 2
fi
if [[ ${functions[_bonjour_resolve_one]:-} != *'dns-sd -G'* || ${functions[run_timed]:-} != *'zselect -t 5'* ]]; then
  print -u2 "diag: product functions were not loaded"
  exit 2
fi
if [[ ${functions[run_timed]} == *'LJ_DNS_SD_TRACE'* ]]; then
  print -u2 "diag: product run_timed already contains tracer hooks"
  exit 2
fi

ensure_setup() { print -u2 "diag: refused ensure_setup"; exit 3; }
detect_lan() { print -u2 "diag: refused detect_lan"; exit 3; }
collect_self_ips() { print -u2 "diag: refused collect_self_ips"; exit 3; }

cc -O2 -o "$bin" "$src" || exit 2
if [[ $("$bin" --self-check) != lanjump-490-trace ]]; then
  print -u2 "diag: tracer self-check failed"
  exit 2
fi

PATH=$work:$PATH
hash -r
if [[ $(command -v dns-sd) != $bin ]]; then
  print -u2 "diag: refused to run system dns-sd"
  exit 2
fi

# Warm the dyld cache outside the recorded call. No fixture, so -L exits.
"$bin" -L __warmup >/dev/null 2>&1 || true

print -r -- $'pair\t0\t pair._ssh._tcp.local. can be reached at pair.local.:22' >"$work/resolve"
print -r -- $'pair.local\t0\t10.1.1.1|80|192.168.1.77' >"$work/addr"
export LJ_DNS_SD_RESOLVE=$work/resolve
export LJ_DNS_SD_ADDR=$work/addr
export LJ_DNS_SD_TRACE=$trace
MYIP=192.168.1.10
MASK=255.255.255.0
PREFIX=192.168.1
MYIPS=(127.0.0.1 192.168.1.10)

product_sha=$(shasum -a 256 "$product" | awk 'NR==1 { print $1 }')
run_sha=$(print -r -- "${functions[run_timed]}" | shasum -a 256 | awk 'NR==1 { print $1 }')
one_sha=$(print -r -- "${functions[_bonjour_resolve_one]}" | shasum -a 256 | awk 'NR==1 { print $1 }')
"$bin" --stamp "product_sha $product_sha"
"$bin" --stamp "run_timed_sha $run_sha"
"$bin" --stamp "resolve_one_sha $one_sha"
"$bin" --stamp "uname $(uname -sm)"
"$bin" --stamp "sw_vers $(sw_vers -productVersion)"

dest=$work/result
zmodload zsh/datetime
shell_begin=$EPOCHREALTIME
_bonjour_resolve_one pair "$dest"
shell_end=$EPOCHREALTIME
shell_wall_ms=$(( (shell_end - shell_begin) * 1000 ))
print -r -- "shell_epochrealtime begin=$shell_begin end=$shell_end wall_ms=$shell_wall_ms" >>"$trace"
if [[ -f $dest ]]; then
  result_line=$(<"$dest")
  result_line=${result_line//$'\t'/|}
  "$bin" --stamp "result $result_line"
else
  "$bin" --stamp "result missing"
fi

python3 - "$trace" <<'PY'
import sys
path = sys.argv[1]
rows = []
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        if not raw[0].isdigit():
            continue
        parts = raw.split(" ", 4)
        if len(parts) < 4:
            continue
        extra = parts[4] if len(parts) > 4 else ""
        rows.append({
            "mono": int(parts[0]),
            "real": int(parts[1]),
            "pid": int(parts[2]),
            "event": parts[3],
            "extra": extra,
        })

def stamp(prefix):
    for row in rows:
        if row["event"] == "stamp" and row["extra"].startswith(prefix):
            return row
    return None

g_pid = None
for row in rows:
    if row["event"] == "proc_start" and " -G " in row["extra"]:
        g_pid = row["pid"]
lines = [row for row in rows if row["pid"] == g_pid and row["event"] == "line"]
signals = [row for row in rows if row["pid"] == g_pid and row["event"] == "sigterm"]
first = next((row for row in lines if "10.1.1.1" in row["extra"]), None)
second = next((row for row in lines if "192.168.1.77" in row["extra"]), None)
child_sigterm = signals[-1] if signals else None

def ms(a, b):
    if a is None or b is None:
        return "absent"
    return f"{(b['mono'] - a['mono']) / 1e6:.3f}"

if first and second and child_sigterm and child_sigterm["mono"] >= second["mono"] and "during_sleep=0" in child_sigterm["extra"]:
    kind = "both_lines_then_child_sigterm"
    code = 0
elif first and child_sigterm and second is None and "during_sleep=1" in child_sigterm["extra"]:
    kind = "child_sigterm_during_second_wait"
    code = 2
elif first and child_sigterm and second is None:
    kind = "child_sigterm_without_second_line"
    code = 2
else:
    kind = "incomplete"
    code = 2

shell_wall = "absent"
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        raw = raw.rstrip("\n")
        if raw.startswith("shell_epochrealtime "):
            shell_wall = raw
result = stamp("result ")
print(f"classification={kind}")
print(f"g_pid={g_pid if g_pid is not None else 'absent'}")
print(f"line_count={len(lines)}")
print(f"line1_mono_ns={first['mono'] if first else 'absent'}")
print(f"line2_mono_ns={second['mono'] if second else 'absent'}")
print(f"child_sigterm_mono_ns={child_sigterm['mono'] if child_sigterm else 'absent'}")
print(f"child_sigterm_extra={child_sigterm['extra'] if child_sigterm else 'absent'}")
print(f"line_gap_ms={ms(first, second)}")
print(f"sigterm_after_line1_ms={ms(first, child_sigterm)}")
print(f"sigterm_after_line2_ms={ms(second, child_sigterm)}")
print(f"shell_epochrealtime={shell_wall}")
print("shell_epochrealtime_note=not_a_500ms_verdict")
print(f"result={result['extra'] if result else 'absent'}")
print(f"trace={path}")
sys.exit(code)
PY
