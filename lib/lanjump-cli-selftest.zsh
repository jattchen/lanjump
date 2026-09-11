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

  out=$(/bin/zsh "$MAIN" --help)
  expect_contains help/long-opt '用法：lanjump' "$out"

  out=$(/bin/zsh "$MAIN" -h)
  expect_contains help/short-opt '用法：lanjump' "$out"

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

# Drive shipped cli_dispatch. Stub list/open so host selection is
# visible; do not exercise cli_open_tabs remote vs local.
tmpdir=$(mktemp -d) || exit 1
log=$tmpdir/log
: >"$log"
trap 'rm -rf "$tmpdir"; restore_tty 2>/dev/null || true' EXIT

TEST_LAST_HOST=local
h_alias=(office)
h_user=(mac)
h_hostname=(office.local)
h_ip=(10.0.0.1)
h_mac=('')
h_last=('0')

default_cli_host() {
  print -r -- "${TEST_LAST_HOST:-local}"
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

CLI_HAS_SESSION=1
CLI_PIN=0
CLI_CREATE=1
CLI_GROK_DIR=0
TEST_PANE_CMD=zsh
TEST_PANE_CWD=/tmp/typed-cwd

cli_has_session() {
  print -r -- "HAS host=$1 session=$2" >>"$log"
  (( CLI_HAS_SESSION ))
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
expect_contains go-host-session/open 'OPEN host=office names=lanjump' "$hay"
expect_absent go-host-session/not-local-open 'OPEN host=local' "$hay"

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
expect_absent go-auto/no-tabs 'OPEN ' "$hay"
expect_absent go-auto/no-grok 'TMUX send-keys' "$hay"
expect_absent go-auto/no-pin 'PICK --pin-session' "$hay"

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

CLI_HAS_SESSION=0
CLI_CREATE=1
CLI_PIN=0
: >"$log"
st=0
out=$(cli_dispatch go demo) || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL go-missing/status got $st want 0"
  (( fails++ ))
fi
expect_contains go-missing/ask '要新建并打开吗' "$out"
expect_contains go-missing/pin-prompt '常驻（y=是，回车=否）' "$out"
expect_contains go-missing/create 'PICK --new-session demo' "$hay"
expect_absent go-missing/no-pin 'PICK --pin-session' "$hay"
expect_contains go-missing/open 'OPEN host=local names=demo' "$hay"

CLI_PIN=1
: >"$log"
st=0
cli_dispatch go demo >/dev/null || st=$?
hay=$(read_log)
expect_contains go-missing-pin/pin 'PICK --pin-session demo' "$hay"
CLI_PIN=0

CLI_CREATE=0
: >"$log"
st=0
cli_dispatch go demo >/dev/null || st=$?
if (( st == 0 )); then
  print -u2 "FAIL go-missing-cancel/status got 0 want nonzero"
  (( fails++ ))
fi
CLI_CREATE=1

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
TEST_PANE_CMD=zsh

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

