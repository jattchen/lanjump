#!/bin/zsh
# Run from repo: zsh lib/lanjump-cli-selftest.zsh
emulate -L zsh
setopt no_unset

fails=0
MAIN=${0:A:h}/lanjump.zsh

expect_contains() {
  local label=$1 needle=$2 hay=$3
  if [[ $hay != *"$needle"* ]]; then
    print -u2 "FAIL $label missing $(printf %q "$needle")"
    (( fails++ ))
  fi
}

out=$(/bin/zsh "$MAIN" help)
expect_contains help/title '用法：lanjump' "$out"
expect_contains help/list 'list [机器]' "$out"
expect_contains help/last 'last [机器]' "$out"
expect_contains help/go 'go [机器:]名字' "$out"
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
print 'ok cli'
exit 0
