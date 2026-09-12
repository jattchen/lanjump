#!/bin/zsh
# Run from repo: zsh lib/lanjump-cli-selftest.zsh
# Sourced by lanjump.zsh --cli-selftest after CLI functions exist.
emulate -L zsh
setopt no_unset

fails=0

expect_contains() {
  local label=$1 needle=$2 hay=$3
  if [[ $hay != *"$needle"* ]]; then
    print -u2 "FAIL $label missing $(printf %q "$needle")"
    (( fails++ ))
  fi
}

expect_absent() {
  local label=$1 needle=$2 hay=$3
  if [[ $hay == *"$needle"* ]]; then
    print -u2 "FAIL $label has $(printf %q "$needle") got=$(printf %q "$hay")"
    (( fails++ ))
  fi
}

if ! (( ${+functions[cli_dispatch]} )); then
  MAIN=${0:A:h}/lanjump.zsh

  out=$(/bin/zsh "$MAIN" help)
  expect_contains help/title '用法：lanjump' "$out"
  expect_contains help/list 'list [机器]' "$out"
  expect_contains help/last 'last [机器]' "$out"
  expect_contains help/go 'go [机器:]名字' "$out"
  expect_contains help/grok '--grok' "$out"
  expect_contains help/last-menu '最近 5 个' "$out"
  expect_absent help/no-new '  new ' "$out"
  expect_contains help/work 'work [机器]' "$out"
  expect_contains help/pins 'pins [机器]' "$out"
  expect_contains help/settings ', 设置' "$out"
  expect_contains help/enter-current 'Enter 当前窗口' "$out"
  expect_contains help/t-window 't 新窗口' "$out"
  expect_absent help/no-current-default '当前窗口）。' "$out"

  out=$(/bin/zsh "$MAIN" --help)
  expect_contains help/long-opt '用法：lanjump' "$out"

  out=$(/bin/zsh "$MAIN" -h)
  expect_contains help/short-opt '用法：lanjump' "$out"

  for cmd in go list work pins last; do
    st=0
    out=$(/bin/zsh "$MAIN" "$cmd" --help) || st=$?
    if (( st != 0 )); then
      print -u2 "FAIL $cmd-help/exit got $st want 0"
      (( fails++ ))
    fi
    expect_contains $cmd-help/title '用法：lanjump' "$out"
    expect_contains $cmd-help/work 'work [机器]' "$out"
    expect_contains $cmd-help/pins 'pins [机器]' "$out"
    expect_absent $cmd-help/session "没有 session「--help」" "$out"
    expect_absent $cmd-help/host "没有保存的机器「--help」" "$out"
  done

  st=0
  out=$(/bin/zsh "$MAIN" go -h) || st=$?
  if (( st != 0 )); then
    print -u2 "FAIL go-h/exit got $st want 0"
    (( fails++ ))
  fi
  expect_contains go-h/title '用法：lanjump' "$out"
  expect_absent go-h/session "没有 session「-h」" "$out"

  st=0
  out=$(/bin/zsh "$MAIN" list -h) || st=$?
  if (( st != 0 )); then
    print -u2 "FAIL list-h/exit got $st want 0"
    (( fails++ ))
  fi
  expect_contains list-h/title '用法：lanjump' "$out"
  expect_absent list-h/host "没有保存的机器「-h」" "$out"

  st=0
  err=$(/bin/zsh "$MAIN" nosuch 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL help/unknown-exit got 0 want nonzero"
    (( fails++ ))
  fi
  expect_contains help/unknown-msg '未知命令：nosuch' "$err"
  expect_contains help/unknown-usage '用法：lanjump' "$err"

  if (( fails )); then
    print -u2 "cli-selftest: $fails failed"
    exit 1
  fi
  exec /bin/zsh "$MAIN" --cli-selftest
fi

# Drive shipped cli_open_tabs / go / work / pins. Stub SSH and the local
# picker so a remote open cannot attach or resume a local same-name session.
tmpdir=$(mktemp -d) || exit 1
log=$tmpdir/log
fake_picker=$tmpdir/pick
export LANJUMP_CLI_TEST_LOG=$log
trap 'rm -rf "$tmpdir"; restore_tty 2>/dev/null || true' EXIT

cat >"$fake_picker" <<'EOF'
emulate -L zsh
log=${LANJUMP_CLI_TEST_LOG:?}
print -r -- "LOCAL_PICK host=${LANJUMP_ATTACH_HOST:-} argv=${(j: :)${(q)@}}" >>"$log"
case ${1:-} in
  --print-workspace)
    print -r -- lanjump
    print -r -- other
    ;;
  --print-pinned|--print-last)
    print -r -- lanjump
    ;;
  --has-session)
    ;;
  --open-tabs|--attach)
    print -r -- "LOCAL_RESUME ${(j: :)${@[2,-1]}}" >>"$log"
    print -r -- "LOCAL_ATTACH ${(j: :)${@[2,-1]}}" >>"$log"
    ;;
esac
exit 0
EOF

: >"$log"
h_alias=(studio)
h_user=(mac)
h_hostname=(studio.local)
h_ip=(10.0.0.2)
h_mac=('')
h_last=('0')

picker_path() {
  print -r -- "$fake_picker"
}

# go/last attach via cli_pick_exec; do not exec so later cases can run.
cli_pick_exec() {
  local picker
  picker=$(picker_path)
  /bin/zsh "$picker" "$@"
}

setup_access() {
  return 0
}

sync_picker() {
  return 0
}

ssh_tty() {
  print -r -- "REMOTE_SSH ${(j: :)${(q)@}}" >>"$LANJUMP_CLI_TEST_LOG"
  print -r -- "REMOTE_CMD ${@[-1]}" >>"$LANJUMP_CLI_TEST_LOG"
  return 0
}

ssh() {
  print -r -- "SSH ${(j: :)${(q)@}}" >>"$LANJUMP_CLI_TEST_LOG"
  if [[ $* == *--print-workspace* ]]; then
    print -r -- lanjump
    print -r -- other
  elif [[ $* == *--print-pinned* || $* == *--print-last* ]]; then
    print -r -- lanjump
  fi
  return 0
}

read_log() {
  [[ -f $LANJUMP_CLI_TEST_LOG ]] || return
  print -r -- "$(<"$LANJUMP_CLI_TEST_LOG")"
}

assert_remote_open() {
  local label=$1 hay=$2 session=$3
  expect_contains "$label/ssh" REMOTE_SSH "$hay"
  expect_contains "$label/pick" lanjump-pick "$hay"
  expect_contains "$label/session" "$session" "$hay"
  if [[ $hay != *--open-tabs* && $hay != *--attach* ]]; then
    print -u2 "FAIL $label/flag missing --open-tabs or --attach got=$(printf %q "$hay")"
    (( fails++ ))
  fi
  expect_absent "$label/no-local-pick" LOCAL_PICK "$hay"
  expect_absent "$label/no-local-attach" LOCAL_ATTACH "$hay"
  expect_absent "$label/no-local-resume" LOCAL_RESUME "$hay"
}

assert_local_open() {
  local label=$1 hay=$2 session=$3
  expect_contains "$label/pick" LOCAL_PICK "$hay"
  expect_contains "$label/tabs" --open-tabs "$hay"
  expect_contains "$label/session" "$session" "$hay"
  expect_absent "$label/no-attach-host" 'host=studio' "$hay"
  expect_absent "$label/no-ssh" REMOTE_SSH "$hay"
}

assert_local_attach() {
  local label=$1 hay=$2 session=$3
  expect_contains "$label/pick" LOCAL_PICK "$hay"
  expect_contains "$label/attach" --attach "$hay"
  expect_contains "$label/session" "$session" "$hay"
  expect_absent "$label/no-tabs" --open-tabs "$hay"
  expect_absent "$label/no-attach-host" 'host=studio' "$hay"
  expect_absent "$label/no-ssh" REMOTE_SSH "$hay"
}

# #84: remote names open on this Mac via local --open-tabs + LANJUMP_ATTACH_HOST.
assert_remote_local_tabs() {
  local label=$1 hay=$2
  shift 2
  expect_contains "$label/pick" LOCAL_PICK "$hay"
  expect_contains "$label/host" 'host=studio' "$hay"
  expect_contains "$label/tabs" --open-tabs "$hay"
  local n
  for n in "$@"; do
    expect_contains "$label/name-$n" "$n" "$hay"
  done
  expect_absent "$label/no-ssh" REMOTE_SSH "$hay"
  expect_absent "$label/no-remote-open" 'REMOTE_CMD' "$hay"
}

expect_eq() {
  local label=$1 want=$2 got=$3
  if [[ $got != "$want" ]]; then
    print -u2 "FAIL $label got=$(printf %q "$got") want=$(printf %q "$want")"
    (( fails++ ))
  fi
}

# Phone SSH / no local Ghostty or Terminal: keep remote --open-tabs (first only).
ghostty_restore_available() { return 1 }
terminal_restore_available() { return 1 }

: >"$log"
cli_open_tabs studio lanjump
assert_remote_open remote/open-tabs "$(read_log)" lanjump

# #110: CLI SSH into the remote picker must carry the same Apple Terminal
# env as host-list connect_item. Otherwise tmux_prepare_color treats the
# remote as RGB-capable and Grok's 24-bit background becomes white.
src_connect=${functions[connect_item]}
src_remote=${functions[cli_remote_pick]}
expect_contains sync/connect-term TERM_PROGRAM "$src_connect"
expect_contains sync/connect-color COLORTERM "$src_connect"
expect_contains sync/remote-term TERM_PROGRAM "$src_remote"
expect_contains sync/remote-color COLORTERM "$src_remote"

: >"$log"
TERM_PROGRAM=Apple_Terminal TERM_PROGRAM_VERSION=440 \
  cli_remote_pick studio --attach demo
hay=$(read_log)
assert_remote_open remote/cli-term "$hay" demo
expect_contains remote/cli-term/unset 'unset GROK_APPEARANCE LC_GROK_APPEARANCE COLORTERM' "$hay"
expect_contains remote/cli-term/program 'TERM_PROGRAM=Apple_Terminal' "$hay"
expect_contains remote/cli-term/version 'TERM_PROGRAM_VERSION=440' "$hay"
expect_contains remote/cli-term/attach --attach "$hay"

: >"$log"
cli_open_tabs local lanjump
assert_local_open local/open-tabs "$(read_log)" lanjump

# #90: forgetting the last remote must not leave that alias as CLI default.
LAST_FILE=$tmpdir/last_target
print -r -- studio >"$LAST_FILE"
expect_eq default-host/present studio "$(default_cli_host)"

h_alias=()
h_user=()
h_hostname=()
h_ip=()
h_mac=()
h_last=()
expect_eq default-host/forgotten local "$(default_cli_host)"

print -r -- local >"$LAST_FILE"
expect_eq default-host/local local "$(default_cli_host)"

print -r -- host >"$LAST_FILE"
expect_eq default-host/sentinel local "$(default_cli_host)"

rm -f "$LAST_FILE"
expect_eq default-host/missing local "$(default_cli_host)"

print -r -- studio >"$LAST_FILE"
: >"$log"
st=0
err=$(cli_dispatch list 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL list-forgotten/status got $st want 0"
  (( fails++ ))
fi
expect_absent list-forgotten/no-missing '没有保存的机器' "$err"
expect_eq list-forgotten/last local "$(read_last)"

_lj_save_restore_tty=$functions[restore_tty]
_lj_save_setup_tty=$functions[setup_tty]
_lj_save_forget_saved=$functions[forget_saved]
_lj_save_load_hosts=$functions[load_hosts]
_lj_save_build_items=$functions[build_items]
_lj_save_cli_tty_read=$functions[cli_tty_read]
restore_tty() { : }
setup_tty() { : }
forget_saved() { : }
load_hosts() { : }
build_items() { : }
items_kind=(host)
items_alias=(studio)
items_saved=(1)

print -r -- studio >"$LAST_FILE"
cli_tty_read() { printf -v $1 y }
forget_item 1 >/dev/null
expect_eq forget-last/cleared local "$(read_last)"

print -r -- office >"$LAST_FILE"
cli_tty_read() { printf -v $1 y }
forget_item 1 >/dev/null
expect_eq forget-last/other office "$(read_last)"

print -r -- studio >"$LAST_FILE"
cli_tty_read() { printf -v $1 n }
forget_item 1 >/dev/null
expect_eq forget-last/cancel studio "$(read_last)"

functions[restore_tty]=$_lj_save_restore_tty
functions[setup_tty]=$_lj_save_setup_tty
functions[forget_saved]=$_lj_save_forget_saved
functions[load_hosts]=$_lj_save_load_hosts
functions[build_items]=$_lj_save_build_items
functions[cli_tty_read]=$_lj_save_cli_tty_read
unset _lj_save_restore_tty _lj_save_setup_tty _lj_save_forget_saved
unset _lj_save_load_hosts _lj_save_build_items _lj_save_cli_tty_read

h_alias=(studio)
h_user=(mac)
h_hostname=(studio.local)
h_ip=(10.0.0.2)
h_mac=('')
h_last=('0')

default_cli_host() {
  print -r -- studio
}

: >"$log"
cli_dispatch go studio:lanjump
assert_remote_open remote/go "$(read_log)" lanjump

# #70: real cli_remote_print path. Stub local tmux so a miss cannot
# send-keys into a same-named local session.
cli_tmux() {
  print -r -- "LOCAL_TMUX ${(j: :)@}" >>"$LANJUMP_CLI_TEST_LOG"
  return 0
}
: >"$log"
cli_dispatch go studio:lanjump --grok
hay=$(read_log)
assert_remote_open remote/go-grok "$hay" lanjump
expect_contains remote/go-grok/start --start-grok "$hay"
expect_contains remote/go-grok/ssh-print SSH "$hay"
expect_absent remote/go-grok/no-local-tmux LOCAL_TMUX "$hay"
unfunction cli_tmux

: >"$log"
cli_dispatch work
assert_remote_open remote/work "$(read_log)" lanjump
expect_contains remote/work-other other "$(read_log)"

: >"$log"
cli_dispatch pins
assert_remote_open remote/pins "$(read_log)" lanjump

# #84: Ghostty on this Mac opens one local window per remote name.
ghostty_restore_available() { return 0 }
terminal_restore_available() { return 1 }
: >"$log"
cli_open_tabs studio a b
assert_remote_local_tabs remote-ghostty/open-tabs "$(read_log)" a b

: >"$log"
cli_dispatch work
hay=$(read_log)
assert_remote_local_tabs remote-ghostty/work "$hay" lanjump other
expect_contains remote-ghostty/work-print SSH "$hay"
expect_contains remote-ghostty/work-print-ws --print-workspace "$hay"

: >"$log"
cli_dispatch pins
hay=$(read_log)
assert_remote_local_tabs remote-ghostty/pins "$hay" lanjump
expect_contains remote-ghostty/pins-print SSH "$hay"
expect_contains remote-ghostty/pins-print-pin --print-pinned "$hay"

ghostty_restore_available() { return 1 }
terminal_restore_available() { return 0 }
: >"$log"
cli_open_tabs studio a b
assert_remote_local_tabs remote-terminal/open-tabs "$(read_log)" a b

ghostty_restore_available() { return 1 }
terminal_restore_available() { return 1 }

default_cli_host() {
  print -r -- local
}

: >"$log"
cli_dispatch go lanjump
assert_local_attach local/go "$(read_log)" lanjump

: >"$log"
cli_dispatch work
assert_local_open local/work "$(read_log)" lanjump
expect_contains local/work-other other "$(read_log)"

# Host routing for work/pins (issue 44): stub list/open so the chosen
# machine is visible without going through SSH.
TEST_LAST_HOST=local
CLI_HAS_SESSION=1
typeset -a CLI_TTY_REPLIES
CLI_TTY_REPLIES=()
h_alias=(office)
h_user=(mac)
h_hostname=(office.local)
h_ip=(10.0.0.1)
h_mac=('')
h_last=('0')

default_cli_host() {
  print -r -- "${TEST_LAST_HOST:-local}"
}

mark_last() {
  print -r -- "LAST host=$1" >>"$log"
}

cli_list_names() {
  local host=$1 flag=$2
  print -r -- "LIST host=$host flag=$flag" >>"$log"
  if [[ $host != local ]] && ! find_host_index "$host" >/dev/null; then
    print -u2 "没有保存的机器「${host}」。"
    return 1
  fi
  case $flag in
    --print-workspace) print -r -- "${host}-work" ;;
    --print-pinned) print -r -- "${host}-pin" ;;
    --print-last) print -r -- "${host}-last" ;;
    --print-recent)
      print -r -- "${host}-recent1"
      print -r -- "${host}-recent2"
      ;;
    *) print -r -- "${host}-sess" ;;
  esac
}

cli_open_tabs() {
  local host=$1 x
  shift
  local -a ns
  ns=()
  for x in "$@"; do
    [[ -n $x ]] && ns+=("$x")
  done
  print -r -- "OPEN host=$host names=${(j:,:)ns}" >>"$log"
  (( ${#ns} )) || return 1
}

cli_remote_pick() {
  print -r -- "REMOTE_PICK host=$1 argv=${(j: :)${@[2,-1]}}" >>"$log"
}

cli_remote_print() {
  print -r -- "REMOTE_PRINT host=$1 argv=${(j: :)${@[2,-1]}}" >>"$log"
}

CLI_HAS_SESSION=1
CLI_PIN=0
CLI_CREATE=1
CLI_GROK_DIR=0
TEST_PANE_CMD=zsh
TEST_PANE_CWD=/tmp/typed-cwd
TEST_PANE_LIST=

cli_has_session() {
  print -r -- "HAS host=$1 session=$2" >>"$log"
  (( CLI_HAS_SESSION ))
}

# #120: cli_has_session is stubbed here; the picker --has-session handler
# must restore like work/print before answering.
pick_file="${0:A:h}/lanjump-pick.zsh"
has_src=
if [[ -f $pick_file ]]; then
  has_src=$(awk '
    /^has_named_session\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains has-session/restore-gate should_restore_sessions "$has_src"
expect_contains has-session/restore-saved restore_saved_sessions "$has_src"

# #122: last/--print-recent must restore like work/go before listing.
recent_src=
if [[ -f $pick_file ]]; then
  recent_src=$(awk '
    /^print_recent_names\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains last/restore-gate should_restore_sessions "$recent_src"
expect_contains last/restore-saved restore_saved_sessions "$recent_src"

# #134: list/--print-sessions must restore like last/work before listing.
list_src=
if [[ -f $pick_file ]]; then
  list_src=$(awk '
    /^print_session_list\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains list/restore-gate should_restore_sessions "$list_src"
expect_contains list/restore-saved restore_saved_sessions "$list_src"

# #137: pins/--print-pinned must restore like work/list before listing pins.
pins_src=
if [[ -f $pick_file ]]; then
  pins_src=$(awk '
    /^print_pinned_names\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains pins/restore-gate should_restore_sessions "$pins_src"
expect_contains pins/restore-saved restore_saved_sessions "$pins_src"

# #124: --attach must restore like go/--has-session before attaching.
attach_src=
ensure_src=
if [[ -f $pick_file ]]; then
  attach_src=$(awk '
    /\[\[ \$\{1:-\} == --attach \]\]/ {p=1}
    p {print}
    p && /^picker_boot_before_first_draw/ {exit}
  ' "$pick_file")
  ensure_src=$(awk '
    /^ensure_named_session_for_attach\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains attach/restore-call ensure_named_session_for_attach "$attach_src"
expect_contains attach/ensure-has has_named_session "$ensure_src"

cli_new_session() {
  print -r -- "NEW host=$1 session=$2" >>"$log"
  return 0
}

cli_tty_read() {
  local _n=$1
  local _v=
  if (( ${#CLI_TTY_REPLIES} )); then
    _v=${CLI_TTY_REPLIES[1]}
    shift CLI_TTY_REPLIES
  else
    _v=
  fi
  printf -v $_n '%s' "$_v"
}

cli_ask_create() {
  print "没有 session「${1}」。"
  print -n "要新建并打开吗？（回车=是，其他键=否） "
  (( CLI_CREATE ))
}

cli_ask_pin() {
  print -n "常驻（y=是，回车=否）: "
  (( CLI_PIN ))
}

cli_pick() {
  print -r -- "PICK ${(j: :)@}" >>"$log"
}

cli_pick_exec() {
  print -r -- "PICK_EXEC ${(j: :)@}" >>"$log"
}

cli_tmux() {
  print -r -- "TMUX ${(j: :)@}" >>"$log"
  case $1 in
    display-message)
      if [[ $* == *pane_current_command* ]]; then
        print -r -- "$TEST_PANE_CMD"
      elif [[ $* == *pane_current_path* ]]; then
        print -r -- "$TEST_PANE_CWD"
      fi
      ;;
    list-panes)
      [[ -n ${TEST_PANE_LIST:-} ]] && print -r -- "$TEST_PANE_LIST"
      ;;
    new-session)
      print -r -- auto7
      ;;
  esac
  return 0
}

cli_cwd_has_grok_session() {
  (( CLI_GROK_DIR ))
}

cli_recent_select() {
  print -r -- "SELECT ${(j: :)@}" >>"$log"
  print -r -- "$1"
}

read_log() {
  [[ -f $log ]] || return
  print -r -- "$(<$log)"
}

for ans in '' y Y 是; do
  if ! cli_confirm_create "$ans"; then
    print -u2 "FAIL confirm-create/yes $(printf %q "$ans")"
    (( fails++ ))
  fi
done
for ans in n N no yes x; do
  if cli_confirm_create "$ans"; then
    print -u2 "FAIL confirm-create/no $(printf %q "$ans") treated as yes"
    (( fails++ ))
  fi
done

: >"$log"
st=0
cli_dispatch work office >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL work-office/status got $st want 0"
  (( fails++ ))
fi
expect_contains work-office/list 'LIST host=office flag=--print-workspace' "$hay"
expect_contains work-office/open 'OPEN host=office names=office-work' "$hay"
expect_contains work-office/last 'LAST host=office' "$hay"
expect_absent work-office/not-local-list 'LIST host=local' "$hay"
expect_absent work-office/not-local-open 'OPEN host=local' "$hay"

: >"$log"
st=0
cli_dispatch pins office >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pins-office/status got $st want 0"
  (( fails++ ))
fi
expect_contains pins-office/list 'LIST host=office flag=--print-pinned' "$hay"
expect_contains pins-office/open 'OPEN host=office names=office-pin' "$hay"
expect_contains pins-office/last 'LAST host=office' "$hay"
expect_absent pins-office/not-local-list 'LIST host=local' "$hay"
expect_absent pins-office/not-local-open 'OPEN host=local' "$hay"

: >"$log"
st=0
err=$(cli_dispatch work nosuch 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL work-unknown/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains work-unknown/msg '没有保存的机器「nosuch」。' "$err"
hay=$(read_log)
expect_absent work-unknown/no-local-open 'OPEN host=local' "$hay"
expect_absent work-unknown/no-last 'LAST ' "$hay"

: >"$log"
st=0
err=$(cli_dispatch pins nosuch 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL pins-unknown/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains pins-unknown/msg '没有保存的机器「nosuch」。' "$err"
hay=$(read_log)
expect_absent pins-unknown/no-local-open 'OPEN host=local' "$hay"
expect_absent pins-unknown/no-last 'LAST ' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch work >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL work-last-local/status got $st want 0"
  (( fails++ ))
fi
expect_contains work-last-local/list 'LIST host=local flag=--print-workspace' "$hay"
expect_contains work-last-local/open 'OPEN host=local names=local-work' "$hay"
expect_contains work-last-local/last 'LAST host=local' "$hay"

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch work >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL work-last-office/status got $st want 0"
  (( fails++ ))
fi
expect_contains work-last-office/list 'LIST host=office flag=--print-workspace' "$hay"
expect_contains work-last-office/open 'OPEN host=office names=office-work' "$hay"
expect_contains work-last-office/last 'LAST host=office' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch go office:lanjump >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-host-session/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-host-session/has 'HAS host=office session=lanjump' "$hay"
expect_contains go-host-session/attach 'REMOTE_PICK host=office' "$hay"
expect_contains go-host-session/attach-flag '--attach' "$hay"
expect_contains go-host-session/session lanjump "$hay"
expect_contains go-host-session/last 'LAST host=office' "$hay"
expect_absent go-host-session/no-tabs --open-tabs "$hay"
expect_absent go-host-session/not-local-open 'OPEN host=local' "$hay"

# #70: --grok on host:session must start grok on that host, not local tmux.
LANJUMP_GROK_BIN=grok
TEST_PANE_CMD=zsh
CLI_HAS_SESSION=1
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch go office:demo --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-host-grok/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-host-grok/has 'HAS host=office session=demo' "$hay"
expect_contains go-host-grok/remote 'REMOTE_PRINT host=office argv=--start-grok demo' "$hay"
expect_contains go-host-grok/attach 'REMOTE_PICK host=office' "$hay"
expect_contains go-host-grok/attach-flag '--attach' "$hay"
expect_contains go-host-grok/last 'LAST host=office' "$hay"
expect_absent go-host-grok/no-local-tmux 'TMUX ' "$hay"
expect_absent go-host-grok/no-local-pick 'PICK --start-grok' "$hay"
expect_absent go-host-grok/not-local-open 'OPEN host=local' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch go local:lanjump >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-local/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-local/has 'HAS host=local session=lanjump' "$hay"
expect_contains go-local/attach 'PICK_EXEC --attach lanjump' "$hay"
expect_contains go-local/last 'LAST host=local' "$hay"
expect_absent go-local/no-open 'OPEN ' "$hay"

# #78: named go local:session records last host even when previous last was remote.
# Local attach execs the picker, so last_target must be written first.
TEST_LAST_HOST=office
CLI_HAS_SESSION=1
: >"$log"
st=0
cli_dispatch go local:lanjump >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-local-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-local-from-remote/has 'HAS host=local session=lanjump' "$hay"
expect_contains go-local-from-remote/attach 'PICK_EXEC --attach lanjump' "$hay"
expect_contains go-local-from-remote/last 'LAST host=local' "$hay"
expect_contains go-local-from-remote/last-before-exec $'LAST host=local\nPICK_EXEC' "$hay"
expect_absent go-local-from-remote/not-office 'LAST host=office' "$hay"
TEST_LAST_HOST=local

CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y '')
TEST_LAST_HOST=local
: >"$log"
st=0
out=$(cli_dispatch go dummytest) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-y/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-create-y/prompt '回车或 y=是' "$out"
expect_contains go-create-y/pin '常驻（y=是，回车=否）' "$out"
hay=$(read_log)
expect_contains go-create-y/new 'NEW host=local session=dummytest' "$hay"
expect_contains go-create-y/attach 'PICK_EXEC --attach dummytest' "$hay"
expect_contains go-create-y/last 'LAST host=local' "$hay"
expect_absent go-create-y/no-open 'OPEN ' "$hay"

CLI_HAS_SESSION=0
CLI_TTY_REPLIES=('' '')
: >"$log"
st=0
cli_dispatch go dummytest >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-empty/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains go-create-empty/new 'NEW host=local session=dummytest' "$hay"
expect_contains go-create-empty/attach 'PICK_EXEC --attach dummytest' "$hay"
expect_contains go-create-empty/last 'LAST host=local' "$hay"
expect_absent go-create-empty/no-open 'OPEN ' "$hay"

CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(n)
: >"$log"
st=0
out=$(cli_dispatch go dummytest) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-create-n/status got 0 want nonzero"
  (( fails++ ))
fi
hay=$(read_log)
expect_absent go-create-n/no-new 'NEW ' "$hay"
expect_absent go-create-n/no-open 'OPEN ' "$hay"
expect_absent go-create-n/no-last 'LAST ' "$hay"

CLI_HAS_SESSION=1
CLI_TTY_REPLIES=()
LANJUMP_GROK_BIN=grok
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch last >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-menu/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-menu/list 'LIST host=local flag=--print-recent' "$hay"
expect_contains last-menu/select 'SELECT local-recent1 local-recent2' "$hay"
expect_contains last-menu/attach 'PICK_EXEC --attach local-recent1' "$hay"
expect_contains last-menu/last 'LAST host=local' "$hay"

# #75: last <host> enters that host; last/default host must become it, not the previous local.
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch last office >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-host/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-host/list 'LIST host=office flag=--print-recent' "$hay"
expect_contains last-host/select 'SELECT office-recent1 office-recent2' "$hay"
expect_contains last-host/attach 'REMOTE_PICK host=office' "$hay"
expect_contains last-host/attach-flag '--attach' "$hay"
expect_contains last-host/session office-recent1 "$hay"
expect_contains last-host/last 'LAST host=office' "$hay"
expect_absent last-host/not-local 'LAST host=local' "$hay"
expect_absent last-host/not-local-list 'LIST host=local' "$hay"
TEST_LAST_HOST=local

: >"$log"
st=0
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto/tmux 'TMUX new-session' "$hay"
expect_contains go-auto/attach 'PICK_EXEC --attach auto7' "$hay"
expect_contains go-auto/last 'LAST host=local' "$hay"
expect_absent go-auto/no-tabs 'OPEN ' "$hay"
expect_absent go-auto/no-grok 'TMUX send-keys' "$hay"
expect_absent go-auto/no-pin 'PICK --pin-session' "$hay"

# #73: nameless go enters local; last host must become local, not the previous remote.
TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto-from-remote/tmux 'TMUX new-session' "$hay"
expect_contains go-auto-from-remote/attach 'PICK_EXEC --attach auto7' "$hay"
expect_contains go-auto-from-remote/last 'LAST host=local' "$hay"
expect_absent go-auto-from-remote/not-office 'LAST host=office' "$hay"
TEST_LAST_HOST=local

# #142: go host: with empty session is usage, not a local auto-new.
# Nameless go (no args) still auto-news local — covered by go-auto above.
TEST_LAST_HOST=office
: >"$log"
st=0
err=$(cli_dispatch go office: 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-host-empty/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-host-empty/usage '用法：' "$err"
hay=$(read_log)
expect_absent go-host-empty/no-local-pick 'LOCAL_PICK' "$hay"
expect_absent go-host-empty/no-tmux 'TMUX ' "$hay"
expect_absent go-host-empty/no-pick-exec 'PICK_EXEC' "$hay"
expect_absent go-host-empty/no-last 'LAST ' "$hay"
expect_absent go-host-empty/no-remote 'REMOTE_PICK' "$hay"
TEST_LAST_HOST=local

: >"$log"
st=0
cli_dispatch go --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto-grok/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto-grok/send 'TMUX send-keys' "$hay"
expect_contains go-auto-grok/fresh '-- grok Enter' "$hay"
expect_absent go-auto-grok/no-c 'grok -c' "$hay"

CLI_GROK_DIR=1
: >"$log"
st=0
cli_dispatch go --grok >/dev/null || st=$?
hay=$(read_log)
expect_contains go-auto-grok-c/c 'grok -c' "$hay"
CLI_GROK_DIR=0

TEST_PANE_CMD=
: >"$log"
st=0
cli_dispatch go --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-auto-unread/no-send 'TMUX send-keys' "$hay"
TEST_PANE_CMD=zsh

CLI_HAS_SESSION=1
TEST_PANE_CMD=zsh
CLI_GROK_DIR=0
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_contains go-exist-grok/send 'TMUX send-keys' "$hay"
expect_contains go-exist-grok/fresh '-- grok Enter' "$hay"
expect_absent go-exist-grok/no-c 'grok -c' "$hay"

TEST_PANE_CMD=grok
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-exist-already/no-send 'TMUX send-keys' "$hay"

TEST_PANE_CMD=grok-1.0.24-mac
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-exist-grok-ver/no-send 'TMUX send-keys' "$hay"

TEST_PANE_CMD=
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-exist-unread/no-send 'TMUX send-keys' "$hay"
expect_contains go-exist-unread/pane-target '-t =demo:.' "$hay"
TEST_PANE_CMD=zsh

# #82: another window already runs grok; jump there, do not start a second grok.
TEST_PANE_LIST=$'%1\tzsh\n%2\tgrok'
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-exist-other-grok/status got $st want 0"
  (( fails++ ))
fi
expect_absent go-exist-other-grok/no-send 'TMUX send-keys' "$hay"
expect_contains go-exist-other-grok/list 'list-panes -s' "$hay"
expect_contains go-exist-other-grok/select 'select-window -t %2' "$hay"
expect_contains go-exist-other-grok/attach 'PICK_EXEC --attach demo' "$hay"

TEST_PANE_LIST=$'%1\tzsh\n%2\tgrok-1.0.24-mac'
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-exist-other-ver/no-send 'TMUX send-keys' "$hay"
expect_contains go-exist-other-ver/select 'select-window -t %2' "$hay"

TEST_PANE_CMD=
TEST_PANE_LIST=$'%1\t\n%2\tgrok'
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_absent go-exist-unread-other/no-send 'TMUX send-keys' "$hay"
expect_contains go-exist-unread-other/select 'select-window -t %2' "$hay"
TEST_PANE_CMD=zsh
TEST_PANE_LIST=

# #85: unprefixed attach is always local (Ghostty / `lanjump attach name`).
# go <name> still follows last host. Prefixed attach host:name still honors host.
CLI_HAS_SESSION=1
TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch attach lj85-local >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL attach-unprefixed-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains attach-unprefixed-from-remote/attach 'PICK_EXEC --attach lj85-local' "$hay"
expect_contains attach-unprefixed-from-remote/last 'LAST host=local' "$hay"
expect_absent attach-unprefixed-from-remote/no-remote 'REMOTE_PICK' "$hay"
expect_absent attach-unprefixed-from-remote/not-office 'LAST host=office' "$hay"

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch attach --shell lj85-local >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL attach-shell-unprefixed-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains attach-shell-unprefixed-from-remote/attach 'PICK_EXEC --attach --shell lj85-local' "$hay"
expect_absent attach-shell-unprefixed-from-remote/no-remote 'REMOTE_PICK' "$hay"

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch attach office:lj85-local >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL attach-prefixed-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains attach-prefixed-remote/attach 'REMOTE_PICK host=office' "$hay"
expect_contains attach-prefixed-remote/attach-flag '--attach' "$hay"
expect_contains attach-prefixed-remote/session lj85-local "$hay"
expect_contains attach-prefixed-remote/last 'LAST host=office' "$hay"
expect_absent attach-prefixed-remote/no-local 'PICK_EXEC' "$hay"

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch go lj85-local >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-unprefixed-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-unprefixed-from-remote/has 'HAS host=office session=lj85-local' "$hay"
expect_contains go-unprefixed-from-remote/attach 'REMOTE_PICK host=office' "$hay"
expect_contains go-unprefixed-from-remote/session lj85-local "$hay"
expect_contains go-unprefixed-from-remote/last 'LAST host=office' "$hay"
expect_absent go-unprefixed-from-remote/no-local 'PICK_EXEC' "$hay"
TEST_LAST_HOST=local

st=0
err=$(/bin/zsh "${0:A:h}/lanjump.zsh" new 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL new-removed/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains new-removed/msg '未知命令：new' "$err"
expect_absent new-removed/no-hint 'lanjump go' "$err"

if (( fails )); then
  print -u2 "cli-selftest: $fails failed"
  exit 1
fi
print 'ok cli'
exit 0
