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
  expect_contains help/settings ', 设置' "$out"

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

# Drive shipped cli_dispatch. Stub list/open so host selection is
# visible; do not exercise cli_open_tabs remote vs local.
tmpdir=$(mktemp -d) || exit 1
log=$tmpdir/log
: >"$log"
trap 'rm -rf "$tmpdir"; restore_tty 2>/dev/null || true' EXIT

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
  (( CLI_HAS_SESSION ))
}

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
expect_contains go-host-session/open 'OPEN host=office names=lanjump' "$hay"
expect_contains go-host-session/last 'LAST host=office' "$hay"
expect_absent go-host-session/not-local-open 'OPEN host=local' "$hay"

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
expect_contains go-local/open 'OPEN host=local names=lanjump' "$hay"
expect_contains go-local/last 'LAST host=local' "$hay"

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
expect_contains go-create-y/open 'OPEN host=local names=dummytest' "$hay"
expect_contains go-create-y/last 'LAST host=local' "$hay"

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
expect_contains go-create-empty/open 'OPEN host=local names=dummytest' "$hay"
expect_contains go-create-empty/last 'LAST host=local' "$hay"

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

if (( fails )); then
  print -u2 "cli-selftest: $fails failed"
  exit 1
fi
print 'ok cli'
exit 0

