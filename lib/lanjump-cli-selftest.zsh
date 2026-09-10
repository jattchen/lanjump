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

setup_access() {
  return 0
}

sync_picker() {
  return 0
}

ssh_tty() {
  print -r -- "REMOTE_SSH ${(j: :)${(q)@}}" >>"$LANJUMP_CLI_TEST_LOG"
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

: >"$log"
cli_open_tabs studio lanjump
assert_remote_open remote/open-tabs "$(read_log)" lanjump

: >"$log"
cli_open_tabs local lanjump
assert_local_open local/open-tabs "$(read_log)" lanjump

default_cli_host() {
  print -r -- studio
}

: >"$log"
cli_dispatch go studio:lanjump
assert_remote_open remote/go "$(read_log)" lanjump

: >"$log"
cli_dispatch work
assert_remote_open remote/work "$(read_log)" lanjump
expect_contains remote/work-other other "$(read_log)"

: >"$log"
cli_dispatch pins
assert_remote_open remote/pins "$(read_log)" lanjump

default_cli_host() {
  print -r -- local
}

: >"$log"
cli_dispatch go lanjump
assert_local_open local/go "$(read_log)" lanjump

: >"$log"
cli_dispatch work
assert_local_open local/work "$(read_log)" lanjump
expect_contains local/work-other other "$(read_log)"

# Host routing for work/pins (issue 44): stub list/open so the chosen
# machine is visible without going through SSH.
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

if (( fails )); then
  print -u2 "cli-selftest: $fails failed"
  exit 1
fi
print 'ok cli'
exit 0
