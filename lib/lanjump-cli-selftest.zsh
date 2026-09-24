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
  expect_contains help/list 'lanjump list' "$out"
  expect_contains help/last 'lanjump last 20' "$out"
  expect_contains help/go 'lanjump go' "$out"
  expect_contains help/go-host 'lanjump <机器> go' "$out"
  expect_contains help/go-g 'lanjump go demo -g' "$out"
  expect_contains help/go-G 'lanjump <机器> go -G' "$out"
  expect_contains help/on 'lanjump <机器> on' "$out"
  expect_contains help/omit-local '不写就是本机' "$out"
  expect_contains help/alias-enter '<机器>' "$out"
  expect_absent help/no-last-omit '机器省略时用上次进入的那台' "$out"
  expect_contains help/grok '--grok' "$out"
  expect_absent help/no-old-go 'go [机器 名字 | 机器:名字]' "$out"
  expect_absent help/no-t-create 't=新窗口' "$out"
  expect_absent help/no-new '  new ' "$out"
  expect_contains help/pin 'lanjump pin' "$out"
  expect_absent help/no-work 'work [机器]' "$out"
  expect_absent help/no-pins 'pins [机器]' "$out"
  expect_contains help/rename '按 e' "$out"

  out=$(/bin/zsh "$MAIN" --help)
  expect_contains help/long-opt '用法：lanjump' "$out"

  out=$(/bin/zsh "$MAIN" -h)
  expect_contains help/short-opt '用法：lanjump' "$out"

  for cmd in go list pin last; do
    st=0
    out=$(/bin/zsh "$MAIN" "$cmd" --help) || st=$?
    if (( st != 0 )); then
      print -u2 "FAIL $cmd-help/exit got $st want 0"
      (( fails++ ))
    fi
    expect_contains $cmd-help/title '用法：lanjump' "$out"
    expect_contains $cmd-help/pin 'lanjump pin' "$out"
    expect_contains $cmd-help/last 'lanjump last 20' "$out"
    expect_absent $cmd-help/no-work 'work [机器]' "$out"
    expect_absent $cmd-help/no-pins 'pins [机器]' "$out"
    expect_absent $cmd-help/no-old-go 'go [机器 名字 | 机器:名字]' "$out"
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
  # ensure_setup runs before the unknown-command rejection and creates
  # ~/.ssh plus Application Support/lanjump. Keep that off the real home.
  _lj_home=$(mktemp -d) || exit 1
  _lj_bin=$(mktemp -d) || exit 1
  print '#!/bin/zsh\nexit 0' >"$_lj_bin/ssh-add"
  chmod 755 "$_lj_bin/ssh-add"
  err=$(HOME=$_lj_home PATH="$_lj_bin:$PATH" /bin/zsh "$MAIN" nosuch 2>&1) || st=$?
  rm -rf "$_lj_home" "$_lj_bin"
  unset _lj_home _lj_bin
  if (( st == 0 )); then
    print -u2 "FAIL help/unknown-exit got 0 want nonzero"
    (( fails++ ))
  fi
  expect_contains help/unknown-msg '没有这台机器，也没有这个命令：nosuch' "$err"
  expect_absent help/unknown-not-old '未知命令：nosuch' "$err"

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
# cli_remote_pick records the host before SSH. Do that in this temp dir,
# or the first remote call creates a real Application Support/lanjump.
LAST_FILE=$tmpdir/last_target
trap 'rm -rf "$tmpdir"; restore_tty 2>/dev/null || true' EXIT

# #153: WINCH at file load must not host-draw. last/help/list/confirm
# share this process; resize used to paint an empty 「局域网 SSH」 table.
# zsh has no `trap -p SIGNAL`; that form *sets* WINCH to -p.
# `$(trap)` is a subshell and hides the parent's traps; write in-shell.
trap >"$tmpdir/traps"
_lj_traps=$(<"$tmpdir/traps")
expect_absent last-winch/load-trap "draw' WINCH" "$_lj_traps"
_lj_head=$(sed -n '1,90p' "${0:A:h}/lanjump.zsh")
if [[ $_lj_head == *WINCH* && $_lj_head == *draw* ]]; then
  print -u2 "FAIL last-winch/source-load-trap WINCH host draw at load"
  (( fails++ ))
fi
unset _lj_traps _lj_head

if ! (( ${+functions[draw_on_winch]} )); then
  print -u2 "FAIL last-winch/draw_on_winch missing"
  (( fails++ ))
else
  _lj_save_draw=$functions[draw]
  _lj_winch_draws=0
  draw() { ((_lj_winch_draws++)) }
  host_list_active=0
  loading=0
  items_kind=()
  draw_on_winch
  if (( _lj_winch_draws )); then
    print -u2 "FAIL last-winch/last-menu host draw called"
    (( fails++ ))
  fi
  host_list_active=1
  draw_on_winch
  if (( _lj_winch_draws != 1 )); then
    print -u2 "FAIL last-winch/host-list skipped draw got=$_lj_winch_draws"
    (( fails++ ))
  fi
  _lj_winch_draws=0
  loading=1
  draw_on_winch
  if (( _lj_winch_draws )); then
    print -u2 "FAIL last-winch/loading host draw called"
    (( fails++ ))
  fi
  functions[draw]=$_lj_save_draw
  host_list_active=0
  loading=0
  unset _lj_save_draw _lj_winch_draws
fi

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
  --print-sessions)
    print -r -- "${LANJUMP_ATTACH_HOST:-}"
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

# Mux setup must not mkdir the real ~/.ssh (#443 / #465).
functions -c ssh_prepare_mux _cli_ssh_prepare_mux
ssh_prepare_mux() {
  local saved_home=$HOME
  HOME=$tmpdir
  {
    _cli_ssh_prepare_mux
  } always {
    HOME=$saved_home
  }
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
expect_contains sync/connect-color remote_pick_color_cmd "$src_connect"
expect_contains sync/connect-pick-bin LANJUMP_PICK_BIN "$src_connect"
expect_contains sync/remote-term TERM_PROGRAM "$src_remote"
expect_contains sync/remote-color remote_pick_color_cmd "$src_remote"
expect_contains sync/remote-pick-bin LANJUMP_PICK_BIN "$src_remote"

# #445: wrap's client LC_GROK_APPEARANCE must be dropped. COLORTERM is only
# harmful on Apple Terminal; Ghostty needs it so Grok paints a truecolor
# background instead of sitting on the window canvas.
apple_color=$(TERM_PROGRAM=Apple_Terminal remote_pick_color_cmd)
expect_contains color/apple-drop-wrap 'unset GROK_APPEARANCE LC_GROK_APPEARANCE' "$apple_color"
expect_contains color/apple-no-truecolor 'unset COLORTERM' "$apple_color"
ghostty_color=$(TERM_PROGRAM=ghostty remote_pick_color_cmd)
expect_contains color/ghostty-drop-wrap 'unset GROK_APPEARANCE LC_GROK_APPEARANCE' "$ghostty_color"
expect_absent color/ghostty-keep-truecolor 'unset COLORTERM' "$ghostty_color"

: >"$log"
TERM_PROGRAM=Apple_Terminal TERM_PROGRAM_VERSION=440 \
  cli_remote_pick studio --attach demo
hay=$(read_log)
assert_remote_open remote/cli-term "$hay" demo
expect_contains remote/cli-term/unset 'unset GROK_APPEARANCE LC_GROK_APPEARANCE' "$hay"
expect_contains remote/cli-term/no-truecolor 'unset COLORTERM' "$hay"
expect_contains remote/cli-term/program 'TERM_PROGRAM=Apple_Terminal' "$hay"
expect_contains remote/cli-term/version 'TERM_PROGRAM_VERSION=440' "$hay"
expect_contains remote/cli-term/attach --attach "$hay"
expect_contains remote/cli-term/pick-bin 'LANJUMP_PICK_BIN=$HOME/.local/bin/lanjump-pick' "$hay"

: >"$log"
TERM_PROGRAM=ghostty TERM_PROGRAM_VERSION=1 \
  cli_remote_pick studio --attach demo
hay=$(read_log)
assert_remote_open remote/cli-ghostty "$hay" demo
expect_contains remote/cli-ghostty/unset 'unset GROK_APPEARANCE LC_GROK_APPEARANCE' "$hay"
expect_absent remote/cli-ghostty/keep-truecolor 'unset COLORTERM' "$hay"
expect_contains remote/cli-ghostty/program 'TERM_PROGRAM=ghostty' "$hay"

# #341: NixOS has zsh on PATH but no /bin/zsh. After the key works,
# remote pick must resolve zsh from PATH or the login dies with 127.
expect_absent remote/cli-term/no-hard-bin-zsh 'exec /bin/zsh' "$hay"
if [[ $hay != *'command -v zsh'* && $hay != *'/usr/bin/env zsh'* ]]; then
  print -u2 "FAIL remote/cli-term/find-zsh missing command -v zsh or /usr/bin/env zsh got=$(printf %q "$hay")"
  (( fails++ ))
fi
expect_contains remote/cli-term/zsh-missing-msg '远端找不到 zsh' "$hay"

: >"$log"
cli_remote_print studio
hay=$(read_log)
if [[ $hay == *'/bin/zsh'* && $hay == *lanjump-pick* ]]; then
  print -u2 "FAIL remote/cli-print/no-hard-bin-zsh still uses /bin/zsh for lanjump-pick got=$(printf %q "$hay")"
  (( fails++ ))
fi
if [[ $hay != *'command -v zsh'* && $hay != *'command\ -v\ zsh'* && $hay != *'/usr/bin/env zsh'* ]]; then
  print -u2 "FAIL remote/cli-print/find-zsh missing command -v zsh or /usr/bin/env zsh got=$(printf %q "$hay")"
  (( fails++ ))
fi

: >"$log"
cli_remote_pick studio
hay=$(read_log)
rcmd341=
while IFS= read -r _lj341_line; do
  if [[ $_lj341_line == REMOTE_CMD* ]]; then
    rcmd341=${_lj341_line#REMOTE_CMD }
  fi
done <<<"$hay"
unset _lj341_line
if [[ -z $rcmd341 ]]; then
  print -u2 "FAIL remote/path-zsh missing REMOTE_CMD got=$(printf %q "$hay")"
  (( fails++ ))
else
  remote341=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-341-remote.XXXXXX")
  mkdir -p "$remote341/home/.local/bin"
  print -r -- $'#!/bin/sh\necho PATH_ZSH >>"$LANJUMP_341_MARK"\nexec /bin/sh "$@"' >"$remote341/home/.local/bin/zsh"
  chmod +x "$remote341/home/.local/bin/zsh"
  print -r -- $'#!/bin/sh\necho PICKER >>"$LANJUMP_341_MARK"\nexit 0' >"$remote341/home/.local/bin/lanjump-pick"
  chmod +x "$remote341/home/.local/bin/lanjump-pick"
  : >"$remote341/mark"
  st=0
  LANJUMP_341_MARK=$remote341/mark HOME=$remote341/home \
    PATH=/usr/bin:/bin \
    /bin/sh -c "$rcmd341" || st=$?
  if (( st == 127 )); then
    print -u2 "FAIL remote/path-zsh exec exited 127 with zsh only on PATH"
    (( fails++ ))
  fi
  if [[ ! -f $remote341/mark || $(<"$remote341/mark") != *PATH_ZSH* ]]; then
    print -u2 "FAIL remote/path-zsh did not exec PATH zsh got=$(printf %q "$(<"$remote341/mark" 2>/dev/null || true)") cmd=$(printf %q "$rcmd341")"
    (( fails++ ))
  fi
  rm -rf "$remote341"
fi

: >"$log"
cli_open_tabs local lanjump
assert_local_open local/open-tabs "$(read_log)" lanjump

# #440: omitted CLI host is this Mac even when last_target is a remote.
LAST_FILE=$tmpdir/last_target
print -r -- studio >"$LAST_FILE"
expect_eq default-host/present local "$(default_cli_host)"

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

# #90: omitted-host list with a forgotten last alias still lists local
# (default_cli_host), not 「没有保存的机器」.
# #192: listing is not entering; do not rewrite LAST_FILE.
print -r -- studio >"$LAST_FILE"
: >"$log"
st=0
err=$(cli_dispatch list 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL list-forgotten/status got $st want 0"
  (( fails++ ))
fi
expect_absent list-forgotten/no-missing '没有保存的机器' "$err"
expect_eq list-forgotten/last studio "$(read_last)"

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
cli_dispatch studio go lanjump
assert_remote_open remote/go "$(read_log)" lanjump

# #70: real cli_remote_print path. Stub local tmux so a miss cannot
# send-keys into a same-named local session.
cli_tmux() {
  print -r -- "LOCAL_TMUX ${(j: :)@}" >>"$LANJUMP_CLI_TEST_LOG"
  return 0
}
: >"$log"
cli_dispatch studio go lanjump --grok
hay=$(read_log)
assert_remote_open remote/go-grok "$hay" lanjump
expect_contains remote/go-grok/start --start-grok "$hay"
expect_contains remote/go-grok/shell '--attach --shell' "$hay"
expect_contains remote/go-grok/ssh-print SSH "$hay"
expect_absent remote/go-grok/no-local-tmux LOCAL_TMUX "$hay"
unfunction cli_tmux

# #175: remote has-session connect/sync failure is not "missing" (status 1).
st=0
err=$(cli_has_session nosuchhost demo 2>&1) || st=$?
if (( st == 0 || st == 1 )); then
  print -u2 "FAIL has-session-unknown/status got $st want not 0 or 1"
  (( fails++ ))
fi
expect_contains has-session-unknown/msg '没有保存的机器「nosuchhost」。' "$err"

_lj_save_access=$functions[setup_access]
_lj_save_sync=$functions[sync_picker]
setup_access() { return 1 }
st=0
err=$(cli_has_session studio demo 2>&1) || st=$?
if (( st == 0 || st == 1 )); then
  print -u2 "FAIL has-session-login/status got $st want not 0 or 1"
  (( fails++ ))
fi
expect_contains has-session-login/msg '无法登录' "$err"

# #465: network failure stays exit 2 (#175/#178) and is not an auth failure.
setup_access() { return 11 }
st=0
err=$(cli_has_session studio demo 2>&1) || st=$?
if (( st != 2 )); then
  print -u2 "FAIL has-session-net/status got $st want 2"
  (( fails++ ))
fi
expect_contains has-session-net/msg '连不上 studio（可能睡眠、离线或换了网络）。' "$err"
expect_absent has-session-net/no-auth '无法登录' "$err"
st=0
out=$(cli_dispatch studio go demo 2>&1) || st=$?
if (( st != 2 )); then
  print -u2 "FAIL go-net/status got $st want 2"
  (( fails++ ))
fi
expect_contains go-net/msg '连不上 studio（可能睡眠、离线或换了网络）。' "$out"
expect_absent go-net/no-prompt '要新建并打开吗' "$out"
expect_absent go-net/no-auth '无法登录' "$out"
st=0
out=$(cli_dispatch studio last 2>&1) || st=$?
if (( st != 2 )); then
  print -u2 "FAIL last-net/status got $st want 2"
  (( fails++ ))
fi
expect_contains last-net/msg '连不上 studio（可能睡眠、离线或换了网络）。' "$out"
expect_absent last-net/no-auth '无法登录' "$out"
st=0
out=$(cli_dispatch studio list 2>&1) || st=$?
if (( st != 2 )); then
  print -u2 "FAIL list-net/status got $st want 2"
  (( fails++ ))
fi
expect_contains list-net/msg '连不上 studio（可能睡眠、离线或换了网络）。' "$out"
expect_absent list-net/no-auth '无法登录' "$out"
st=0
out=$(cli_dispatch studio ls 2>&1) || st=$?
if (( st != 2 )); then
  print -u2 "FAIL ls-net/status got $st want 2"
  (( fails++ ))
fi
expect_contains ls-net/msg '连不上 studio（可能睡眠、离线或换了网络）。' "$out"
expect_absent ls-net/no-auth '无法登录' "$out"
_lj_save_pick=$functions[cli_pick]
cli_pick() { return 1 }
st=0
out=$(cli_dispatch local list 2>&1) || st=$?
if (( st != 1 )); then
  print -u2 "FAIL list-local-fail/status got $st want 1"
  (( fails++ ))
fi
expect_absent list-local-fail/no-net '连不上' "$out"
functions[cli_pick]=$_lj_save_pick
unset _lj_save_pick
functions[setup_access]=$_lj_save_access

sync_picker() { return 1 }
st=0
err=$(cli_has_session studio demo 2>&1) || st=$?
if (( st == 0 || st == 1 )); then
  print -u2 "FAIL has-session-sync/status got $st want not 0 or 1"
  (( fails++ ))
fi
expect_contains has-session-sync/msg '无法把 tmux 选择界面同步到对方。' "$err"
functions[sync_picker]=$_lj_save_sync
unset _lj_save_access _lj_save_sync

: >"$log"
cli_dispatch studio pin
hay=$(read_log)
expect_contains remote/pin-view '--view pinned' "$hay"
expect_absent remote/pin-no-print --print-pinned "$hay"
expect_absent remote/pin-no-attach '--attach' "$hay"
if [[ $hay == *--open-tabs* ]]; then
  print -u2 "FAIL remote/pin opened every pin got=$(printf %q "$hay")"
  (( fails++ ))
fi

# #166: zsh prefix-assignment on a function is not exported to /bin/zsh
# inside cli_pick. The child picker must see LANJUMP_ATTACH_HOST.
src_pick=${functions[cli_pick]}
if [[ $src_pick != *export\ LANJUMP_ATTACH_HOST* && $src_pick != *LANJUMP_ATTACH_HOST*/bin/zsh* ]]; then
  print -u2 "FAIL attach-host/cli-pick-src missing LANJUMP_ATTACH_HOST on /bin/zsh got=$(printf %q "$src_pick")"
  (( fails++ ))
fi
got=$(LANJUMP_ATTACH_HOST=studio cli_pick --print-sessions)
expect_eq attach-host/child-pick studio "$got"

# #84: Ghostty on this Mac opens one local window per remote name.
ghostty_restore_available() { return 0 }
terminal_restore_available() { return 1 }
: >"$log"
cli_open_tabs studio a b
assert_remote_local_tabs remote-ghostty/open-tabs "$(read_log)" a b

: >"$log"
cli_dispatch studio pin
hay=$(read_log)
expect_contains remote-ghostty/pin-view '--view pinned' "$hay"
expect_absent remote-ghostty/pin-no-print --print-pinned "$hay"
expect_absent remote-ghostty/pin-no-attach '--attach' "$hay"
if [[ $hay == *--open-tabs* ]]; then
  print -u2 "FAIL remote-ghostty/pin opened every pin got=$(printf %q "$hay")"
  (( fails++ ))
fi

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
cli_dispatch pin
hay=$(read_log)
expect_contains local/pin-pick LOCAL_PICK "$hay"
expect_contains local/pin-view '--view pinned' "$hay"
expect_absent local/pin-no-print --print-pinned "$hay"
expect_absent local/pin-no-attach --attach "$hay"
expect_absent local/pin-no-tabs --open-tabs "$hay"
expect_absent local/pin-no-ssh REMOTE_SSH "$hay"

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
  print -r -- local
}

mark_last() {
  print -r -- "LAST host=$1" >>"$log"
}

cli_list_names() {
  local host=$1 flag=$2
  print -r -- "LIST host=$host flag=$flag" >>"$log"
  if [[ $host != local ]] && ! find_host_index "$host" >/dev/null; then
    print -u2 "没有保存的机器「${host}」。"
    # Match cli_remote_print: unknown/connect is 2; picker empty list is 1.
    return 2
  fi
  if [[ $host != local ]] && (( ${CLI_HAS_CONNECT:-1} == 0 )); then
    print -u2 "无法登录 ${host}."
    return 2
  fi
  case $flag in
    --print-workspace) print -r -- "${host}-work" ;;
    --print-pinned) print -r -- "${host}-pin" ;;
    --print-last) print -r -- "${host}-last" ;;
    --print-recent)
      if (( ${CLI_RECENT_EMPTY:-0} )); then
        return 1
      fi
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
  if [[ $1 != local ]] && (( ${CLI_HAS_CONNECT:-1} == 0 )); then
    print -u2 "无法登录 ${1}."
    return 2
  fi
  mark_last "$1"
  print -r -- "REMOTE_PICK host=$1 argv=${(j: :)${@[2,-1]}}" >>"$log"
}

cli_remote_print() {
  print -r -- "REMOTE_PRINT host=$1 argv=${(j: :)${@[2,-1]}}" >>"$log"
  if [[ ${2:-} == --new-auto ]]; then
    print -r -- auto7
  elif [[ ${2:-} == --pin-session ]]; then
    local n=${3:-}
    if [[ -n $n && $n != *[!0-9]* ]]; then
      print -r -- "s-renamed-$n"
    else
      print -r -- "$n"
    fi
  fi
}

CLI_HAS_SESSION=1
CLI_HAS_CONNECT=1
CLI_PIN=0
CLI_CREATE=1
CLI_GROK_DIR=0
TEST_PANE_CMD=zsh
TEST_PANE_CWD=/tmp/typed-cwd
TEST_PANE_LIST=

cli_has_session() {
  print -r -- "HAS host=$1 session=$2" >>"$log"
  # #175: unknown/unreachable remote is not a missing session (status 1).
  if [[ $1 != local ]]; then
    if ! find_host_index "$1" >/dev/null; then
      print -u2 "没有保存的机器「${1}」。"
      return 2
    fi
    if (( ${CLI_HAS_CONNECT:-1} == 0 )); then
      print -u2 "无法登录 ${1}."
      return 2
    fi
  fi
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

# #122/#137/#480: last/pin/on open the interactive picker. Restore is the
# same boot as lanjump <机器>, not a silent print before a small list.
open_src=${functions[cli_open_session_list]:-}
if [[ -z $open_src ]]; then
  print -u2 "FAIL view/open missing cli_open_session_list"
  (( fails++ ))
else
  expect_contains view/open-local cli_pick "$open_src"
  expect_contains view/open-remote cli_remote_pick "$open_src"
  expect_contains view/open-flag --view "$open_src"
  if [[ $open_src == *--print-recent* || $open_src == *--print-pinned* || $open_src == *--print-last* ]]; then
    print -u2 "FAIL view/open still uses a silent print list"
    (( fails++ ))
  fi
fi
dispatch_view=${functions[cli_dispatch]}
expect_contains view/last-recent 'recent:' "$dispatch_view"
expect_contains view/pin-pinned 'pinned' "$dispatch_view"
expect_contains view/on-occupied 'occupied' "$dispatch_view"
remote_pick_src=$(awk '
  /^cli_remote_pick\(\)/ {p=1}
  p {print}
  p && /^}/ {exit}
' "${0:A:h}/lanjump.zsh")
if [[ $remote_pick_src != *'cli_ensure_access'*'mark_last'*'ssh_lanjump_tty'* ]]; then
  print -u2 "FAIL view/remote-mark mark_last is not after access and before ssh got=$(printf %q "$remote_pick_src")"
  (( fails++ ))
fi
boot_src=
restore_src=
if [[ -f $pick_file ]]; then
  boot_src=$(awk '
    /^picker_boot_after_first_draw_steps=/ {print; exit}
    /^picker_boot_after_first_draw\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
  restore_src=$(awk '
    /^maybe_restore_sessions\(\)/ {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$pick_file")
fi
expect_contains view/boot-restore maybe_restore_sessions "$boot_src"
expect_contains view/restore-gate should_restore_sessions "$restore_src"
expect_contains view/restore-saved restore_saved_sessions "$restore_src"
unset open_src dispatch_view remote_pick_src boot_src restore_src

# #134: list/--print-sessions must restore like work before listing.
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
  if [[ ${1:-} == --new-auto ]]; then
    print -r -- auto7
  elif [[ ${1:-} == --pin-session ]]; then
    local n=${2:-}
    if [[ -n $n && $n != *[!0-9]* ]]; then
      print -r -- "s-renamed-$n"
    else
      print -r -- "$n"
    fi
  fi
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

cli_recent_select() {
  print -r -- "SELECT ${(j: :)@}" >>"$log"
  print -r -- "$1"
}

read_log() {
  [[ -f $log ]] || return
  print -r -- "$(<$log)"
}

: >"$log"
st=0
cli_dispatch office pin >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pin-office/status got $st want 0"
  (( fails++ ))
fi
expect_contains pin-office/pick 'REMOTE_PICK host=office argv=--view pinned' "$hay"
expect_contains pin-office/last 'LAST host=office' "$hay"
expect_contains pin-office/last-before-pick $'LAST host=office\nREMOTE_PICK' "$hay"
expect_absent pin-office/not-print --print-pinned "$hay"
expect_absent pin-office/not-open 'OPEN host=office' "$hay"
expect_absent pin-office/not-local-list 'LIST host=local' "$hay"

: >"$log"
st=0
err=$(cli_dispatch pin nosuch 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL pin-unknown/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains pin-unknown/msg '用法：lanjump [机器] pin' "$err"
expect_absent pin-unknown/no-hint '现在写' "$err"
hay=$(read_log)
expect_absent pin-unknown/no-last 'LAST ' "$hay"

: >"$log"
st=0
if [[ ${functions[cli_dispatch]} == *$'\n    work)'* || ${functions[cli_is_command]} == *'|work|'* ]]; then
  print -u2 "FAIL work-gone still dispatches work"
  (( fails++ ))
fi
if [[ ${functions[cli_dispatch]} != *'pin)'* ]]; then
  print -u2 "FAIL pin-dispatch missing pin branch"
  (( fails++ ))
fi

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch pin >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pin-omit-local/status got $st want 0"
  (( fails++ ))
fi
expect_contains pin-omit-local/pick 'PICK --view pinned' "$hay"
expect_contains pin-omit-local/last 'LAST host=local' "$hay"
expect_absent pin-omit-local/not-office 'REMOTE_PICK host=office' "$hay"
expect_absent pin-omit-local/not-print --print-pinned "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch office go lanjump >/dev/null || st=$?
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
expect_contains go-host-session/last-before-attach $'LAST host=office\nREMOTE_PICK' "$hay"
expect_absent go-host-session/no-shell '--shell' "$hay"
expect_absent go-host-session/no-tabs --open-tabs "$hay"
expect_absent go-host-session/not-local-open 'OPEN host=local' "$hay"

# #479: two-word `go 别名 session` is rejected. The host comes first.
TEST_LAST_HOST=local
: >"$log"
st=0
err=$(cli_dispatch go office lanjump 2>&1) || st=$?
hay=$(read_log)
if (( st == 0 )); then
  print -u2 "FAIL go-two-word/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-two-word/hint '现在写 lanjump office go lanjump' "$err"
expect_absent go-two-word/no-has 'HAS ' "$hay"
expect_absent go-two-word/no-attach 'REMOTE_PICK' "$hay"

LANJUMP_GROK_BIN=grok
: >"$log"
st=0
cli_dispatch office go demo --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-two-word-grok/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-two-word-grok/has 'HAS host=office session=demo' "$hay"
expect_contains go-two-word-grok/remote 'REMOTE_PRINT host=office argv=--start-grok demo' "$hay"
expect_contains go-two-word-grok/attach 'REMOTE_PICK host=office' "$hay"
expect_contains go-two-word-grok/shell '--attach --shell demo' "$hay"
expect_absent go-two-word-grok/no-local-pick 'PICK --start-grok' "$hay"

st=0
err=$(cli_dispatch go office demo extra 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-three-word/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-three-word/hint '现在写 lanjump office go demo' "$err"

# #479: `go 别名:名字` is rejected, including with --grok.
LANJUMP_GROK_BIN=grok
TEST_PANE_CMD=zsh
CLI_HAS_SESSION=1
TEST_LAST_HOST=local
: >"$log"
st=0
err=$(cli_dispatch go office:demo --grok 2>&1) || st=$?
hay=$(read_log)
if (( st == 0 )); then
  print -u2 "FAIL go-host-grok/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-host-grok/hint '现在写 lanjump office go demo' "$err"
expect_absent go-host-grok/no-remote 'REMOTE_PRINT' "$hay"
expect_absent go-host-grok/no-local-pick 'PICK --start-grok' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch local go lanjump >/dev/null || st=$?
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
cli_dispatch local go lanjump >/dev/null || st=$?
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
expect_absent go-create-y/no-prompt '要新建并打开吗' "$out"
expect_absent go-create-y/no-t 't=新窗口' "$out"
expect_absent go-create-y/no-pin '常驻（y=是，回车=否）' "$out"
hay=$(read_log)
expect_contains go-create-y/new 'NEW host=local session=dummytest' "$hay"
expect_contains go-create-y/attach 'PICK_EXEC --attach dummytest' "$hay"
expect_contains go-create-y/last 'LAST host=local' "$hay"
expect_absent go-create-y/no-open 'OPEN ' "$hay"
expect_absent go-create-y/no-pin-pick 'PICK --pin-session' "$hay"

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

# Create no longer pins; numeric go 42 stays 42.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y)
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch go 42 >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-numeric/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains go-create-numeric/new 'NEW host=local session=42' "$hay"
expect_absent go-create-numeric/no-pin 'PICK --pin-session' "$hay"
expect_contains go-create-numeric/attach 'PICK_EXEC --attach 42' "$hay"
expect_contains go-create-numeric/last 'LAST host=local' "$hay"

# Unpinned numeric go 42 stays 42 and does not pin.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y '')
: >"$log"
st=0
cli_dispatch go 42 >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-numeric-nopin/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains go-create-numeric-nopin/new 'NEW host=local session=42' "$hay"
expect_absent go-create-numeric-nopin/no-pin 'PICK --pin-session' "$hay"
expect_contains go-create-numeric-nopin/attach 'PICK_EXEC --attach 42' "$hay"

# Named create still attaches the given name and does not pin.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y)
: >"$log"
st=0
cli_dispatch go dummytest >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-named/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_absent go-create-named/no-pin 'PICK --pin-session' "$hay"
expect_contains go-create-named/attach 'PICK_EXEC --attach dummytest' "$hay"

# Missing go attaches the current window. The old t=新窗口 prompt is gone.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(t)
: >"$log"
st=0
cli_dispatch go dummytest >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-t/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains go-create-t/new 'NEW host=local session=dummytest' "$hay"
expect_absent go-create-t/no-tabs 'OPEN ' "$hay"
expect_contains go-create-t/attach 'PICK_EXEC --attach dummytest' "$hay"
expect_absent go-create-t/no-pin 'PICK --pin-session' "$hay"

# Remote go create numeric stays 42 and does not pin.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y)
: >"$log"
st=0
cli_dispatch office go 42 >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-remote-create-numeric/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains go-remote-create-numeric/new 'NEW host=office session=42' "$hay"
expect_absent go-remote-create-numeric/no-pin 'REMOTE_PRINT host=office argv=--pin-session' "$hay"
expect_contains go-remote-create-numeric/attach 'REMOTE_PICK host=office' "$hay"
expect_contains go-remote-create-numeric/attach-flag '--attach' "$hay"

# No prompt: a missing name is created even if nothing is typed.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(n)
: >"$log"
st=0
out=$(cli_dispatch go dummytest 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-create-n/status got $st want 0"
  (( fails++ ))
fi
expect_absent go-create-n/no-prompt '要新建并打开吗' "$out"
hay=$(read_log)
expect_contains go-create-n/new 'NEW host=local session=dummytest' "$hay"
expect_contains go-create-n/attach 'PICK_EXEC --attach dummytest' "$hay"

# #479: `go A:B` always hints, even when A is not a saved alias.
CLI_HAS_SESSION=0
CLI_HAS_CONNECT=1
TEST_LAST_HOST=local
: >"$log"
st=0
out=$(cli_dispatch go nosuchhost:demo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-unknown-host/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-unknown-host/hint '现在写 lanjump nosuchhost go demo' "$out"
expect_absent go-unknown-host/no-saved '没有保存的机器' "$out"
expect_absent go-unknown-host/no-prompt '要新建并打开吗' "$out"
hay=$(read_log)
expect_absent go-unknown-host/no-new 'NEW ' "$hay"
expect_absent go-unknown-host/no-last 'LAST ' "$hay"
expect_absent go-unknown-host/no-remote-new '--new-session' "$hay"

# Unknown machine in the new position never connects.
st=0
out=$(cli_dispatch nosuchhost go demo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-nosuch-machine/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-nosuch-machine/msg '没有这台机器，也没有这个命令：nosuchhost' "$out"

CLI_HAS_SESSION=0
CLI_HAS_CONNECT=0
: >"$log"
st=0
out=$(cli_dispatch office go demo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-login-fail/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-login-fail/msg '无法登录' "$out"
expect_absent go-login-fail/no-prompt '要新建并打开吗' "$out"
expect_absent go-login-fail/no-session-msg '没有 session「demo」' "$out"
hay=$(read_log)
expect_absent go-login-fail/no-new 'NEW ' "$hay"
expect_absent go-login-fail/no-last 'LAST ' "$hay"
expect_absent go-login-fail/no-remote-new '--new-session' "$hay"
CLI_HAS_CONNECT=1

# Reachable remote, session missing: create without asking.
CLI_HAS_SESSION=0
: >"$log"
st=0
out=$(cli_dispatch office go demo 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-remote-missing/status got $st want 0"
  (( fails++ ))
fi
expect_absent go-remote-missing/no-prompt '要新建并打开吗' "$out"
hay=$(read_log)
expect_contains go-remote-missing/new 'NEW host=office session=demo' "$hay"
expect_contains go-remote-missing/attach 'REMOTE_PICK host=office' "$hay"

# #183: missing dotted name must fail before the create/pin prompts.
CLI_HAS_SESSION=0
CLI_TTY_REPLIES=(y y)
TEST_LAST_HOST=local
: >"$log"
st=0
out=$(cli_dispatch go web.api 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-invalid-dot/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-invalid-dot/msg '名称不能包含冒号或点' "$out"
expect_absent go-invalid-dot/no-prompt '要新建并打开吗' "$out"
hay=$(read_log)
expect_absent go-invalid-dot/no-new 'NEW ' "$hay"
expect_absent go-invalid-dot/no-last 'LAST ' "$hay"

# Existing dotted name still attaches if has-session succeeds.
CLI_HAS_SESSION=1
CLI_TTY_REPLIES=()
: >"$log"
st=0
out=$(cli_dispatch go web.api 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL go-existing-dot/status got $st want 0"
  (( fails++ ))
fi
expect_absent go-existing-dot/no-invalid '名称不能包含冒号或点' "$out"
expect_absent go-existing-dot/no-prompt '要新建并打开吗' "$out"
hay=$(read_log)
expect_contains go-existing-dot/has 'HAS host=local session=web.api' "$hay"
expect_contains go-existing-dot/attach 'PICK_EXEC --attach web.api' "$hay"
expect_absent go-existing-dot/no-new 'NEW ' "$hay"

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
expect_contains last-menu/pick 'PICK --view recent:5' "$hay"
expect_contains last-menu/last 'LAST host=local' "$hay"
expect_absent last-menu/no-print --print-recent "$hay"
expect_absent last-menu/no-attach 'PICK_EXEC' "$hay"

# #75: last <host> enters that host; last/default host must become it, not the previous local.
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch office last >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-host/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-host/pick 'REMOTE_PICK host=office argv=--view recent:5' "$hay"
expect_contains last-host/last 'LAST host=office' "$hay"
expect_contains last-host/last-before-pick $'LAST host=office\nREMOTE_PICK' "$hay"
expect_absent last-host/not-local 'LAST host=local' "$hay"
expect_absent last-host/not-attach '--attach' "$hay"
expect_absent last-host/not-print --print-recent "$hay"
TEST_LAST_HOST=local

# #202: last --shell must skip resume, same as go name --shell.
: >"$log"
st=0
cli_dispatch last --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-shell/pick 'PICK --view recent:5 --shell' "$hay"
expect_contains last-shell/last 'LAST host=local' "$hay"
expect_absent last-shell/no-print --print-recent "$hay"
expect_absent last-shell/no-unknown '未知选项' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch office last --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-host-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-host-shell/pick 'REMOTE_PICK host=office argv=--view recent:5 --shell' "$hay"
expect_contains last-host-shell/last 'LAST host=office' "$hay"
expect_absent last-host-shell/no-print --print-recent "$hay"
expect_absent last-host-shell/no-unknown '未知选项' "$hay"
TEST_LAST_HOST=local

# #178: last must not treat connect failure as an empty recent list.
# work/list already return on cli_list_names failure; last did not.
: >"$log"
st=0
out=$(cli_dispatch last nosuchhost 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL last-unknown-host/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains last-unknown-host/msg '用法：lanjump [机器] last [N]' "$out"
expect_absent last-unknown-host/no-hint '现在写' "$out"
expect_absent last-unknown-host/no-empty '没有最近的 session。' "$out"
hay=$(read_log)
expect_absent last-unknown-host/no-last 'LAST ' "$hay"
expect_absent last-unknown-host/no-select 'SELECT ' "$hay"
expect_absent last-unknown-host/no-attach 'REMOTE_PICK ' "$hay"

CLI_HAS_CONNECT=0
: >"$log"
st=0
out=$(cli_dispatch office last 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL last-login-fail/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains last-login-fail/msg '无法登录' "$out"
expect_absent last-login-fail/no-empty '没有最近的 session。' "$out"
hay=$(read_log)
expect_absent last-login-fail/no-last 'LAST ' "$hay"
expect_absent last-login-fail/no-select 'SELECT ' "$hay"
CLI_HAS_CONNECT=1

# Empty ranges stay inside the picker. The CLI still opens the list.
: >"$log"
st=0
out=$(cli_dispatch office last 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL last-empty-recent/status got $st want 0"
  (( fails++ ))
fi
expect_absent last-empty-recent/no-msg '没有最近的 session。' "$out"
hay=$(read_log)
expect_contains last-empty-recent/pick 'REMOTE_PICK host=office argv=--view recent:5' "$hay"

: >"$log"
st=0
out=$(cli_dispatch last 2>&1) || st=$?
if (( st != 0 )); then
  print -u2 "FAIL last-empty-recent-local/status got $st want 0"
  (( fails++ ))
fi
expect_absent last-empty-recent-local/no-msg '没有最近的 session。' "$out"
hay=$(read_log)
expect_contains last-empty-recent-local/pick 'PICK --view recent:5' "$hay"

: >"$log"
st=0
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto/new 'PICK --new-auto' "$hay"
expect_contains go-auto/cwd '--cwd' "$hay"
expect_contains go-auto/attach 'PICK_EXEC --attach auto7' "$hay"
expect_contains go-auto/last 'LAST host=local' "$hay"
expect_absent go-auto/no-tabs 'OPEN ' "$hay"
expect_absent go-auto/no-tmux 'TMUX new-session' "$hay"
expect_absent go-auto/no-pin 'PICK --pin-session' "$hay"

# #164: nameless go --shell still skips resume (same attach flag as --grok).
: >"$log"
st=0
cli_dispatch go --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto-shell/attach 'PICK_EXEC --attach --shell auto7' "$hay"
expect_absent go-auto-shell/no-resume 'PICK_EXEC --attach auto7' "$hay"
expect_absent go-auto-shell/no-grok 'PICK --start-grok' "$hay"

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
expect_contains go-auto-from-remote/new 'PICK --new-auto' "$hay"
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
expect_contains go-host-empty/hint '现在写 lanjump office go' "$err"
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
expect_contains go-auto-grok/pick 'PICK --start-grok auto7' "$hay"
expect_absent go-auto-grok/no-new 'PICK --start-grok-new' "$hay"
expect_contains go-auto-grok/shell 'PICK_EXEC --attach --shell auto7' "$hay"
expect_absent go-auto-grok/no-resume 'PICK_EXEC --attach auto7' "$hay"

: >"$log"
st=0
cli_dispatch go -g >/dev/null || st=$?
hay=$(read_log)
expect_contains go-auto-short-g/pick 'PICK --start-grok auto7' "$hay"
expect_contains go-auto-short-g/shell 'PICK_EXEC --attach --shell auto7' "$hay"

CLI_HAS_SESSION=1
: >"$log"
st=0
cli_dispatch go demo --grok >/dev/null || st=$?
hay=$(read_log)
expect_contains go-exist-grok/pick 'PICK --start-grok demo' "$hay"
# #151: start-grok already typed grok; --attach must skip maybe_resume.
expect_contains go-exist-grok/shell 'PICK_EXEC --attach --shell demo' "$hay"
expect_absent go-exist-grok/no-resume 'PICK_EXEC --attach demo' "$hay"

: >"$log"
st=0
cli_dispatch go -g demo >/dev/null || st=$?
hay=$(read_log)
expect_contains go-g-before-name/pick 'PICK --start-grok demo' "$hay"
expect_contains go-g-before-name/shell 'PICK_EXEC --attach --shell demo' "$hay"

: >"$log"
st=0
cli_dispatch go demo -g >/dev/null || st=$?
hay=$(read_log)
expect_contains go-g-after-name/pick 'PICK --start-grok demo' "$hay"

: >"$log"
st=0
cli_dispatch go -G >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-auto-G/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-auto-G/pick 'PICK --start-grok-new auto7' "$hay"
expect_contains go-auto-G/shell 'PICK_EXEC --attach --shell auto7' "$hay"
expect_absent go-auto-G/no-resume 'PICK_EXEC --attach auto7' "$hay"

: >"$log"
st=0
cli_dispatch go demo -G >/dev/null || st=$?
hay=$(read_log)
expect_contains go-exist-G/pick 'PICK --start-grok-new demo' "$hay"
expect_contains go-exist-G/shell 'PICK_EXEC --attach --shell demo' "$hay"
expect_absent go-exist-G/no-resume 'PICK_EXEC --attach demo' "$hay"
expect_absent go-exist-G/no-old 'PICK --start-grok demo' "$hay"

: >"$log"
st=0
err=$(cli_dispatch go -g -G 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-both-grok/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-both-grok/usage '用法：lanjump [机器] go [名字] [-g|-G]' "$err"
hay=$(read_log)
expect_absent go-both-grok/no-pick 'PICK --start-grok' "$hay"

: >"$log"
st=0
err=$(cli_dispatch go --grok --grok-new demo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-both-long/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-both-long/usage '用法：lanjump [机器] go [名字] [-g|-G]' "$err"

: >"$log"
st=0
err=$(cli_dispatch go -x 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-unknown-opt/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains go-unknown-opt/msg '未知选项：-x' "$err"
hay=$(read_log)
expect_absent go-unknown-opt/no-new 'NEW ' "$hay"
expect_absent go-unknown-opt/no-ask '要新建并打开吗' "$err"

: >"$log"
st=0
cli_dispatch go demo >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-exist-nogrok/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-exist-nogrok/attach 'PICK_EXEC --attach demo' "$hay"
expect_absent go-exist-nogrok/no-shell 'PICK_EXEC --attach --shell demo' "$hay"

# #164: go name --shell must skip resume, same as attach --shell.
: >"$log"
st=0
cli_dispatch go demo --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-exist-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-exist-shell/attach 'PICK_EXEC --attach --shell demo' "$hay"
expect_absent go-exist-shell/no-resume 'PICK_EXEC --attach demo' "$hay"
expect_absent go-exist-shell/no-grok 'PICK --start-grok' "$hay"

# #85: unprefixed attach is always local (Ghostty / `lanjump attach name`).
# #440: unprefixed go <name> is also local. Prefixed attach host:name still honors host.
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
expect_contains attach-prefixed-remote/last-before-attach $'LAST host=office\nREMOTE_PICK' "$hay"
expect_absent attach-prefixed-remote/no-local 'PICK_EXEC' "$hay"

# #378: aliases may contain colons; session names may not. Ghostty /
# `lanjump attach 机器:session` must split on the last colon.
TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch attach 'office:2:dev' >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL attach-colon-host/status got $st want 0"
  (( fails++ ))
fi
expect_contains attach-colon-host/attach 'REMOTE_PICK host=office:2' "$hay"
expect_contains attach-colon-host/argv 'argv=--attach dev' "$hay"
expect_contains attach-colon-host/last 'LAST host=office:2' "$hay"
expect_absent attach-colon-host/no-first-split 'argv=--attach 2:dev' "$hay"
expect_absent attach-colon-host/no-local 'PICK_EXEC' "$hay"

TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch go lj85-local >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-unprefixed-from-remote/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-unprefixed-from-remote/has 'HAS host=local session=lj85-local' "$hay"
expect_contains go-unprefixed-from-remote/attach 'PICK_EXEC --attach lj85-local' "$hay"
expect_contains go-unprefixed-from-remote/session lj85-local "$hay"
expect_contains go-unprefixed-from-remote/last 'LAST host=local' "$hay"
expect_absent go-unprefixed-from-remote/no-remote 'REMOTE_PICK' "$hay"
TEST_LAST_HOST=local

# #168: remote go/attach/last must write last_target before attach blocks.
# Host-list Enter already marks before SSH; CLI used to wait until SSH returns.
dispatch_src=${functions[cli_dispatch]}
if [[ $dispatch_src == *'[[ $host == local ]] && mark_last'* ]]; then
  print -u2 "FAIL mark-last-before-attach/src first mark_last still local-only"
  (( fails++ ))
fi
unset dispatch_src

_lj_save_mark_last=$functions[mark_last]
_lj_save_cli_attach_one=$functions[cli_attach_one]
h_alias+=(studio)
h_user+=(mac)
h_hostname+=(studio.local)
h_ip+=(10.0.0.3)
h_mac+=('')
h_last+=('0')
mark_last() {
  print -r -- "$1" >"$LAST_FILE"
  print -r -- "LAST host=$1" >>"$log"
}
cli_attach_one() {
  print -r -- "ATTACH_DURING last=$(read_last) host=$1 session=$2" >>"$log"
}

CLI_HAS_SESSION=1
TEST_LAST_HOST=office
print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch studio go demo >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-remote-mark-before-attach/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-remote-mark-before-attach/during 'ATTACH_DURING last=studio host=studio session=demo' "$hay"
expect_eq go-remote-mark-before-attach/last-file studio "$(read_last)"

print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch attach studio:demo >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL attach-remote-mark-before-attach/status got $st want 0"
  (( fails++ ))
fi
expect_contains attach-remote-mark-before-attach/during 'ATTACH_DURING last=studio host=studio session=demo' "$hay"
expect_eq attach-remote-mark-before-attach/last-file studio "$(read_last)"

print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch studio last >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-remote-mark-before-attach/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-remote-mark-before-attach/pick 'REMOTE_PICK host=studio argv=--view recent:5' "$hay"
expect_contains last-remote-mark-before-attach/order $'LAST host=studio\nREMOTE_PICK' "$hay"
expect_eq last-remote-mark-before-attach/last-file studio "$(read_last)"

# pin opens the local list and marks this Mac first, same as last.
print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch local pin >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pin-local-mark-before-attach/status got $st want 0"
  (( fails++ ))
fi
expect_contains pin-local-mark-before-attach/pick 'PICK --view pinned' "$hay"
expect_contains pin-local-mark-before-attach/order $'LAST host=local\nPICK' "$hay"
expect_eq pin-local-mark-before-attach/last-file local "$(read_last)"

# #192: list/ls is not entering. LAST_FILE stays the previously entered host.
print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch local list >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL list-local-no-mark/status got $st want 0"
  (( fails++ ))
fi
expect_contains list-local-no-mark/list 'LIST host=local flag=--print-sessions' "$hay"
expect_absent list-local-no-mark/no-last 'LAST ' "$hay"
expect_eq list-local-no-mark/last office "$(read_last)"

print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch studio list >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL list-saved-no-mark/status got $st want 0"
  (( fails++ ))
fi
expect_contains list-saved-no-mark/list 'LIST host=studio flag=--print-sessions' "$hay"
expect_absent list-saved-no-mark/no-last 'LAST ' "$hay"
expect_eq list-saved-no-mark/last office "$(read_last)"

print -r -- office >"$LAST_FILE"
: >"$log"
st=0
cli_dispatch studio ls >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL ls-saved-no-mark/status got $st want 0"
  (( fails++ ))
fi
expect_contains ls-saved-no-mark/list 'LIST host=studio flag=--print-sessions' "$hay"
expect_absent ls-saved-no-mark/no-last 'LAST ' "$hay"
expect_eq ls-saved-no-mark/last office "$(read_last)"

print -r -- office >"$LAST_FILE"
: >"$log"
st=0
err=$(cli_dispatch nosuchhost list 2>&1) || st=$?
hay=$(read_log)
if (( st == 0 )); then
  print -u2 "FAIL list-unknown-no-mark/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains list-unknown-no-mark/msg '没有这台机器，也没有这个命令：nosuchhost' "$err"
expect_absent list-unknown-no-mark/no-last 'LAST ' "$hay"
expect_eq list-unknown-no-mark/last office "$(read_last)"

functions[mark_last]=$_lj_save_mark_last
functions[cli_attach_one]=$_lj_save_cli_attach_one
unset _lj_save_mark_last _lj_save_cli_attach_one
TEST_LAST_HOST=local

if ! cli_is_command go || ! cli_is_command pin || ! cli_is_command list || ! cli_is_command on; then
  print -u2 "FAIL cli-is-command/known go/pin/list/on not recognized"
  (( fails++ ))
fi
if cli_is_command office || cli_is_command o; then
  print -u2 "FAIL cli-is-command/alias treated as command"
  (( fails++ ))
fi

# #479: machine-first parsing, nameless go, -g/-G, old syntax, on, last N.
_lj479_alias=("${h_alias[@]}")
_lj479_pwd=$PWD
h_alias=(office o)
mkdir -p "$tmpdir/lanjump" "$tmpdir/foo.bar" "$tmpdir/a:b" "$tmpdir/123"

st=0
cli_route go demo >/dev/null || st=$?
if (( st != 0 )) || [[ ${CLI_ROUTE:-} != dispatch ]]; then
  print -u2 "FAIL route/command got st=$st route=${CLI_ROUTE:-}"
  (( fails++ ))
fi
st=0
cli_route office >/dev/null || st=$?
if (( st != 0 )) || [[ ${CLI_ROUTE:-} != host-list-alias ]]; then
  print -u2 "FAIL route/alias got st=$st route=${CLI_ROUTE:-}"
  (( fails++ ))
fi
st=0
cli_route local >/dev/null || st=$?
if (( st != 0 )) || [[ ${CLI_ROUTE:-} != local-list ]]; then
  print -u2 "FAIL route/local got st=$st route=${CLI_ROUTE:-}"
  (( fails++ ))
fi
st=0
cli_route local go >/dev/null || st=$?
if (( st != 0 )) || [[ ${CLI_ROUTE:-} != dispatch ]]; then
  print -u2 "FAIL route/local-go got st=$st route=${CLI_ROUTE:-}"
  (( fails++ ))
fi
st=0
err=$(cli_route zz 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL route/neither status got 0"
  (( fails++ ))
fi
expect_contains route/neither '没有这台机器，也没有这个命令：zz' "$err"
st=0
cli_route office nope >/dev/null || st=$?
if (( st != 0 )) || [[ ${CLI_ROUTE:-} != dispatch ]]; then
  print -u2 "FAIL route/alias-plus got st=$st route=${CLI_ROUTE:-}"
  (( fails++ ))
fi
st=0
err=$(cli_dispatch office nope 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL route/bad-cmd status got 0"
  (( fails++ ))
fi
expect_contains route/bad-cmd '未知命令：nope' "$err"
expect_contains route/bad-cmd-usage '用法：lanjump' "$err"

CLI_HAS_SESSION=1
: >"$log"
st=0
err=$(cli_dispatch go o 2>&1) || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-o/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-o/has 'HAS host=local session=o' "$hay"
expect_contains go-o/attach 'PICK_EXEC --attach o' "$hay"
expect_absent go-o/no-rename '改名' "$err"
expect_absent go-o/no-hint '现在写' "$err"

: >"$log"
st=0
err=$(cli_dispatch go office:demo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-colon/status got 0"
  (( fails++ ))
fi
expect_contains go-colon/hint '现在写 lanjump office go demo' "$err"
hay=$(read_log)
expect_absent go-colon/no-has 'HAS ' "$hay"

: >"$log"
st=0
err=$(cli_dispatch list office 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL list-old/status got 0"
  (( fails++ ))
fi
expect_contains list-old/hint '现在写 lanjump office list' "$err"

: >"$log"
st=0
err=$(cli_dispatch last office 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL last-old/status got 0"
  (( fails++ ))
fi
expect_contains last-old/hint '现在写 lanjump office last' "$err"

: >"$log"
st=0
err=$(cli_dispatch pin office 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL pin-old/status got 0"
  (( fails++ ))
fi
expect_contains pin-old/hint '现在写 lanjump office pin' "$err"

: >"$log"
st=0
err=$(cli_dispatch list nope 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL list-extra/status got 0"
  (( fails++ ))
fi
expect_contains list-extra/usage '用法：lanjump [机器] list' "$err"
expect_absent list-extra/no-hint '现在写' "$err"

: >"$log"
st=0
cli_dispatch last 20 >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-n/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-n/pick 'PICK --view recent:20' "$hay"
expect_absent last-n/no-print --print-recent "$hay"

: >"$log"
st=0
cli_dispatch office last 8 >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL last-n-host/status got $st want 0"
  (( fails++ ))
fi
expect_contains last-n-host/pick 'REMOTE_PICK host=office argv=--view recent:8' "$hay"

: >"$log"
st=0
cli_dispatch pin --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pin-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains pin-shell/pick 'PICK --view pinned --shell' "$hay"
expect_absent pin-shell/no-unknown '未知选项' "$hay"

: >"$log"
st=0
cli_dispatch office pin --shell >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL pin-host-shell/status got $st want 0"
  (( fails++ ))
fi
expect_contains pin-host-shell/pick 'REMOTE_PICK host=office argv=--view pinned --shell' "$hay"

for bad in 0 abc 01; do
  st=0
  err=$(cli_dispatch last "$bad" 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL last-bad/$bad status got 0"
    (( fails++ ))
  fi
  expect_contains last-bad/$bad '用法：lanjump [机器] last [N]' "$err"
done
st=0
err=$(cli_dispatch last 1 2 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL last-two/status got 0"
  (( fails++ ))
fi
expect_contains last-two/usage '用法：lanjump [机器] last [N]' "$err"

: >"$log"
st=0
out=$(cli_dispatch on 2>&1) || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL on/status got $st want 0"
  (( fails++ ))
fi
expect_contains on/pick 'PICK --view occupied' "$hay"
expect_absent on/no-print --print- "$hay"
: >"$log"
st=0
out=$(cli_dispatch office on 2>&1) || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL on-host/status got $st out=$(printf %q "$out")"
  (( fails++ ))
fi
expect_contains on-host/pick 'REMOTE_PICK host=office argv=--view occupied' "$hay"
expect_absent on-host/no-print --print- "$hay"
# h exits 10. That status is what the host list already treats as "back".
_lj_save_pick=$functions[cli_pick]
cli_pick() { return 10 }
st=0
cli_open_session_list local recent:5 0 || st=$?
functions[cli_pick]=$_lj_save_pick
if (( st != 10 )); then
  print -u2 "FAIL list-h/status got $st want 10"
  (( fails++ ))
fi
if ! cli_keep_host_list 10; then
  print -u2 "FAIL list-h/keep rejected 10"
  (( fails++ ))
fi
if cli_keep_host_list 0 || cli_keep_host_list 1; then
  print -u2 "FAIL list-h/keep accepted a non-10 status"
  (( fails++ ))
fi
st=0
err=$(cli_dispatch on foo 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL on-arg/status got 0"
  (( fails++ ))
fi
expect_contains on-arg/usage '用法：lanjump [机器] on' "$err"
st=0
err=$(cli_dispatch on -g 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL on-g/status got 0"
  (( fails++ ))
fi
expect_contains on-g/opt '未知选项：-g' "$err"
st=0
err=$(cli_dispatch list -G 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL list-G/status got 0"
  (( fails++ ))
fi
expect_contains list-G/opt '未知选项：-G' "$err"
st=0
err=$(cli_dispatch pin --grok 2>&1) || st=$?
if (( st == 0 )); then
  print -u2 "FAIL pin-grok/status got 0"
  (( fails++ ))
fi
expect_contains pin-grok/opt '未知选项：--grok' "$err"

: >"$log"
st=0
err=$(cli_dispatch office upgrade 2>&1) || st=$?
hay=$(read_log)
if (( st == 0 )); then
  print -u2 "FAIL upgrade-remote/status got 0"
  (( fails++ ))
fi
expect_contains upgrade-remote/usage '用法：lanjump upgrade' "$err"
expect_absent upgrade-remote/no-ssh 'REMOTE_' "$hay"

: >"$log"
st=0
err=$(cli_dispatch office attach demo 2>&1) || st=$?
hay=$(read_log)
if (( st == 0 )); then
  print -u2 "FAIL attach-new-form/status got 0"
  (( fails++ ))
fi
expect_contains attach-new-form/usage '用法：lanjump attach [--shell] <session>' "$err"
expect_absent attach-new-form/no-remote 'REMOTE_PICK' "$hay"

: >"$log"
st=0
cli_dispatch office go -G >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-remote-G/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-remote-G/pick 'REMOTE_PRINT host=office argv=--start-grok-new auto7' "$hay"
expect_contains go-remote-G/attach 'REMOTE_PICK host=office' "$hay"
expect_absent go-remote-G/no-local 'PICK --start-grok-new' "$hay"

: >"$log"
st=0
cli_dispatch office go demo -g >/dev/null || st=$?
hay=$(read_log)
expect_contains go-remote-g-after/pick 'REMOTE_PRINT host=office argv=--start-grok demo' "$hay"
expect_contains go-remote-g-after/shell '--attach --shell demo' "$hay"

cd "$tmpdir/lanjump"
: >"$log"
st=0
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
expect_contains go-base/name 'PICK --new-auto lanjump --cwd '"$tmpdir/lanjump" "$hay"
cd "$tmpdir/foo.bar"
: >"$log"
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
expect_contains go-base/dot 'PICK --new-auto foo-bar --cwd '"$tmpdir/foo.bar" "$hay"
cd "$tmpdir/a:b"
: >"$log"
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
expect_contains go-base/colon 'PICK --new-auto a-b --cwd '"$tmpdir/a:b" "$hay"
cd "$tmpdir/123"
: >"$log"
cli_dispatch go >/dev/null || st=$?
hay=$(read_log)
expect_contains go-base/num 'PICK --new-auto s-123 --cwd '"$tmpdir/123" "$hay"
cd "$tmpdir/lanjump"
: >"$log"
cli_dispatch office go >/dev/null || st=$?
hay=$(read_log)
expect_contains go-base/remote 'REMOTE_PRINT host=office argv=--new-auto lanjump' "$hay"
expect_absent go-base/remote-no-cwd '--cwd' "$hay"
cd "$_lj479_pwd"

expect_eq base/root s "$(cli_go_base_name /)"
expect_eq base/dots --- "$(cli_go_base_name /tmp/...)"
expect_eq base/empty s "$(cli_go_base_name '')"

h_alias=(go)
: >"$log"
st=0
err=$(cli_dispatch go demo 2>&1) || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL alias-cmd/status got $st want 0"
  (( fails++ ))
fi
expect_contains alias-cmd/warn '有台机器也叫 go，按 e 在主机列表给它改名' "$err"
expect_contains alias-cmd/has 'HAS host=local session=demo' "$hay"

h_alias=("${_lj479_alias[@]}")
unset _lj479_alias _lj479_pwd
CLI_HAS_SESSION=1

st=0
# Same ensure_setup side effect as the nosuch case above.
_lj_home=$(mktemp -d) || exit 1
_lj_bin=$(mktemp -d) || exit 1
print '#!/bin/zsh\nexit 0' >"$_lj_bin/ssh-add"
chmod 755 "$_lj_bin/ssh-add"
err=$(HOME=$_lj_home PATH="$_lj_bin:$PATH" /bin/zsh "${0:A:h}/lanjump.zsh" new 2>&1) || st=$?
rm -rf "$_lj_home" "$_lj_bin"
unset _lj_home _lj_bin
if (( st == 0 )); then
  print -u2 "FAIL new-removed/status got 0 want nonzero"
  (( fails++ ))
fi
expect_contains new-removed/msg '没有这台机器，也没有这个命令：new' "$err"
expect_absent new-removed/no-hint 'lanjump go' "$err"

# #227: host/recent loops must not `read_key || continue` forever on EOF.
if ! (( ${+functions[read_key_or_exit]} )); then
  print -u2 "FAIL key/eof-spin missing read_key_or_exit"
  (( fails++ ))
else
  st=0
  PENDING_KEY=""
  (
    restore_tty() { : }
    typeset -i _read_key_fails=0
    local -i n=0
    while true; do
      (( ++n > 40 )) && exit 99
      read_key_or_exit || continue
    done
  ) </dev/null
  st=$?
  if (( st != 1 )); then
    print -u2 "FAIL key/eof-spin exit got=$st want=1 (99=spun)"
    (( fails++ ))
  fi
fi
if grep -E -q '^cli_recent_select\(\)|^cli_recent_draw\(\)' "${0:A:h}/lanjump.zsh"; then
  print -u2 "FAIL key/eof-spin small recent list still exists"
  (( fails++ ))
fi
if grep -E -q '^[[:space:]]*read_key \|\| continue' "${0:A:h}/lanjump.zsh"; then
  print -u2 "FAIL key/eof-spin host loop still continues forever on read fail"
  (( fails++ ))
fi

# #226: go/list/last do not need the LAN prefix. CLI entry must not probe
# interfaces; is_self_ip lazy-loads collect_self_ips when MYIPS is empty.
_lj_cli=$(awk '
  index($0, "CLI entry: no LAN scan") { p=1 }
  p { print }
  p && index($0, "build_items") { exit }
' "${0:A:h}/lanjump.zsh")
if [[ -z $_lj_cli ]]; then
  print -u2 "FAIL cli-entry/no-detect-lan missing go/list/last branch"
  (( fails++ ))
elif [[ $_lj_cli == *detect_lan* ]]; then
  print -u2 "FAIL cli-entry/no-detect-lan still calls detect_lan before go/list/last"
  (( fails++ ))
fi
unset _lj_cli

_lj_save_collect=$functions[collect_self_ips]
_lj_save_myips=("${MYIPS[@]}")
collect_self_ips() {
  MYIPS=(10.9.8.7)
}
MYIPS=()
if ! is_self_ip 10.9.8.7; then
  print -u2 "FAIL is_self_ip/lazy-self-ips did not collect when MYIPS empty"
  (( fails++ ))
fi
functions[collect_self_ips]=$_lj_save_collect
MYIPS=("${_lj_save_myips[@]}")
unset _lj_save_collect _lj_save_myips

if (( fails )); then
  print -u2 "cli-selftest: $fails failed"
  exit 1
fi
print 'ok cli'
exit 0
