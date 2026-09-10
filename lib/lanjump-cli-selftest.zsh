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
  expect_contains help/work 'work [机器]' "$out"
  expect_contains help/pins 'pins [机器]' "$out"
  expect_contains help/new 'new' "$out"
  expect_contains help/grok '--grok' "$out"
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

cli_has_session() {
  print -r -- "HAS host=$1 session=$2" >>"$log"
  return 0
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
        print -r -- zsh
      elif [[ $* == *pane_current_path* ]]; then
        print -r -- "${TEST_PANE_CWD:-/tmp/typed-cwd}"
      fi
      ;;
    new-session)
      print -r -- auto7
      ;;
  esac
  return 0
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
TEST_LAST_HOST=office
: >"$log"
st=0
cli_dispatch new foo --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL new-foo-grok/status got $st want 0"
  (( fails++ ))
fi
expect_contains new-foo-grok/create 'PICK --new-session foo' "$hay"
expect_contains new-foo-grok/grok 'TMUX send-keys' "$hay"
expect_contains new-foo-grok/pane-target '-t =foo:.' "$hay"
expect_absent new-foo-grok/no-bare-pane '-t =foo ' "$hay"
expect_contains new-foo-grok/grok-bin 'grok -c' "$hay"
expect_absent new-foo-grok/no-resume '--resume' "$hay"
expect_contains new-foo-grok/attach 'PICK_EXEC --attach foo' "$hay"
expect_absent new-foo-grok/no-open-tabs 'OPEN ' "$hay"
expect_absent new-foo-grok/no-ghostty '--open-tabs' "$hay"

TEST_LAST_HOST=local
: >"$log"
st=0
cli_dispatch new --grok >/dev/null || st=$?
hay=$(read_log)
if (( st != 0 )); then
  print -u2 "FAIL new-auto-grok/status got $st want 0"
  (( fails++ ))
fi
expect_contains new-auto-grok/tmux-new 'TMUX new-session' "$hay"
expect_contains new-auto-grok/attach 'PICK_EXEC --attach auto7' "$hay"
expect_contains new-auto-grok/grok 'TMUX send-keys' "$hay"
expect_absent new-auto-grok/no-named 'PICK --new-session' "$hay"
expect_absent new-auto-grok/no-open-tabs 'OPEN ' "$hay"

: >"$log"
st=0
cli_dispatch new foo >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL new-without-grok/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains new-without-grok/create 'PICK --new-session foo' "$hay"
expect_contains new-without-grok/attach 'PICK_EXEC --attach foo' "$hay"
expect_absent new-without-grok/no-grok 'TMUX send-keys' "$hay"

TEST_PANE_CWD=$HOME
: >"$log"
st=0
cli_dispatch new demo --grok >/dev/null || st=$?
if (( st != 0 )); then
  print -u2 "FAIL new-home-grok/status got $st want 0"
  (( fails++ ))
fi
hay=$(read_log)
expect_contains new-home-grok/send 'TMUX send-keys' "$hay"
expect_contains new-home-grok/fresh '-- grok Enter' "$hay"
expect_absent new-home-grok/no-resume '--resume' "$hay"
expect_absent new-home-grok/no-continue 'grok -c' "$hay"
TEST_PANE_CWD=

if (( fails )); then
  print -u2 "cli-selftest: $fails failed"
  exit 1
fi
print 'ok cli'
exit 0

