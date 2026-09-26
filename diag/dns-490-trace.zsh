#!/bin/zsh
# One recorded _bonjour_resolve_one. mode is solo or pair.
# solo matches the host selftest resolve-one fixture: one address, no delay.
# pair matches the host selftest resolve-pair fixture: 10.1.1.1, then 80ms,
# then 192.168.1.77. Product stop conditions are not changed.
#
# Does not write the real HOME, SSH config, or keychain. Timing goes only
# to the trace file. stdout of dns-sd is unchanged.
#
# Child events (CLOCK_MONOTONIC ns, CLOCK_REALTIME ns, pid, name):
#   proc_start argv=... qos_rc= qos_class= qos_rel=
#       qos_* is this dns-sd process only, not the parent shell and not
#       the effective timer policy
#   line text=...          stdout write and this record share one SIGTERM block
#   sleep_begin/sleep_end/sleep_skip/hold
#   sigterm during_sleep=  child received SIGTERM, not the parent decision
#
# Shell lines, written by this process, not by an extra timer process:
#   shell_mode solo|pair
#   shell_run_timed call=L|G begin= end= wall_ms= rc= args=...
#   shell_epochrealtime begin= end= wall_ms= note=trace_overhead_is_not_the_500ms_acceptance
#   shell_result ...
#
# shell_run_timed is one product run_timed call. shell_epochrealtime is the
# whole _bonjour_resolve_one. The difference is work outside those two calls,
# including this wrapper's bookkeeping. Neither number is the original 500ms
# acceptance; LJ466_TIME on the unmodified host selftest is that record.
#
# Exit 0: both run_timed calls and the outer wall were recorded.
# Exit 2: the trace is incomplete. This exit is not a 500ms verdict.

emulate -L zsh
setopt no_unset pipefail

if [[ $# -ne 2 || ${1:-} == -* ]]; then
  print -u2 "usage: zsh diag/dns-490-trace.zsh TRACE_FILE solo|pair"
  exit 2
fi

trace=$1
mode=$2
if [[ $mode != solo && $mode != pair ]]; then
  print -u2 "diag: mode must be solo or pair"
  exit 2
fi
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

if [[ $mode == solo ]]; then
  print -r -- $'solo\t0\t solo._ssh._tcp.local. can be reached at solo.local.:22' >"$work/resolve"
  print -r -- $'solo.local\t0\t192.168.1.40' >"$work/addr"
  inst=solo
else
  print -r -- $'pair\t0\t pair._ssh._tcp.local. can be reached at pair.local.:22' >"$work/resolve"
  print -r -- $'pair.local\t0\t10.1.1.1|80|192.168.1.77' >"$work/addr"
  inst=pair
fi
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

# Time each product run_timed in this shell. The copied function body and
# its stop conditions stay as loaded. The wrapper only records the call.
functions -c run_timed _diag_run_timed_orig
run_timed() {
  local begin end rc plain kind
  local -F wall
  begin=$EPOCHREALTIME
  _diag_run_timed_orig "$@"
  rc=$?
  end=$EPOCHREALTIME
  wall=$(( (end - begin) * 1000 ))
  plain=${(j: :)@}
  kind=other
  [[ $plain == *'dns-sd -L'* ]] && kind=L
  [[ $plain == *'dns-sd -G'* ]] && kind=G
  print -r -- "shell_run_timed call=$kind begin=$begin end=$end wall_ms=$wall rc=$rc args=${(j: :)${(q+)@}}" >>"$trace" || true
  return $rc
}

dest=$work/result
zmodload zsh/datetime
print -r -- "shell_mode $mode" >>"$trace"
shell_begin=$EPOCHREALTIME
_bonjour_resolve_one "$inst" "$dest"
shell_end=$EPOCHREALTIME
shell_wall_ms=$(( (shell_end - shell_begin) * 1000 ))
print -r -- "shell_epochrealtime begin=$shell_begin end=$shell_end wall_ms=$shell_wall_ms note=trace_overhead_is_not_the_500ms_acceptance" >>"$trace"
if [[ -f $dest ]]; then
  result_line=$(<"$dest")
  result_line=${result_line//$'\t'/|}
  print -r -- "shell_result $result_line" >>"$trace"
else
  print -r -- "shell_result missing" >>"$trace"
fi

python3 - "$trace" <<'PY'
import sys
path = sys.argv[1]
text = open(path, "r", encoding="utf-8", errors="replace").read().splitlines()
rows = []
shell_calls = []
outer = None
result = "absent"
mode = "absent"
for raw in text:
    if not raw:
        continue
    if raw.startswith("shell_run_timed "):
        fields = {}
        for part in raw.split(" ")[1:]:
            if "=" in part and part.split("=", 1)[0] in ("call", "begin", "end", "wall_ms", "rc"):
                key, val = part.split("=", 1)
                fields[key] = val
            else:
                break
        shell_calls.append(fields)
        continue
    if raw.startswith("shell_epochrealtime "):
        outer = raw
        continue
    if raw.startswith("shell_result "):
        result = raw
        continue
    if raw.startswith("shell_mode "):
        mode = raw.split(" ", 1)[1]
        continue
    if not raw[0].isdigit():
        continue
    parts = raw.split(" ", 4)
    if len(parts) < 4:
        continue
    rows.append({
        "mono": int(parts[0]),
        "pid": int(parts[2]),
        "event": parts[3],
        "extra": parts[4] if len(parts) > 4 else "",
    })

def call_wall(name):
    for fields in shell_calls:
        if fields.get("call") == name and "wall_ms" in fields:
            return fields
    return None

L = call_wall("L")
G = call_wall("G")
outer_ms = None
if outer and "wall_ms=" in outer:
    try:
        outer_ms = float(outer.split("wall_ms=", 1)[1].split(" ", 1)[0])
    except ValueError:
        outer_ms = None
outside = "absent"
if outer_ms is not None and L and G:
    outside = f"{outer_ms - float(L['wall_ms']) - float(G['wall_ms']):.3f}"

qos = [row["extra"] for row in rows if row["event"] == "proc_start" and "qos_rc=" in row["extra"]]
print(f"mode={mode}")
print(f"run_timed_L={L['wall_ms'] if L else 'absent'} rc={L.get('rc', 'absent') if L else 'absent'}")
print(f"run_timed_G={G['wall_ms'] if G else 'absent'} rc={G.get('rc', 'absent') if G else 'absent'}")
print(f"outer_wall={outer if outer else 'absent'}")
print(f"outside_run_timed_ms={outside}")
print("timing_note=trace_overhead_is_not_the_500ms_acceptance")
print(f"child_proc_start_count={len(qos)}")
for extra in qos:
    print(f"child_proc_start {extra}")
print("child_qos_note=not_parent_shell_or_effective_timer_policy")
print(f"result={result}")
print(f"trace={path}")
complete = L is not None and G is not None and outer is not None and len(qos) >= 2
sys.exit(0 if complete else 2)
PY
