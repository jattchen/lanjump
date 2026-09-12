#!/bin/zsh
# Run from repo: zsh lib/lanjump-keys-selftest.zsh
# Seam: lanjump-keys --rewrite (C helper and Python fallback).
emulate -L zsh
set -euo pipefail

ROOT=${0:A:h:h}
fails=0

fail() {
  print -u2 "FAIL $1"
  fails=$((fails + 1))
}

REWRITE_CMD=()

# name expected_hex input_bytes
check_rewrite() {
  local name=$1 want=$2
  local got
  got=$(printf '%s' "$3" | "${REWRITE_CMD[@]}" | xxd -p -c 256)
  got=${got//$'\n'/}
  if [[ $got != "$want" ]]; then
    fail "$name: got ${got:-<empty>} want $want"
  fi
}

run_cases() {
  local label=$1
  # Kitty event-type (colon): Ghostty 1.3 + Grok protocol push.
  check_rewrite "$label colon-press" '1b0d' $'\x1b[13;2:1u'
  check_rewrite "$label colon-repeat" '1b0d' $'\x1b[13;2:2u'
  check_rewrite "$label colon-release" '' $'\x1b[13;2:3u'
  check_rewrite "$label colon-altkeys" '1b0d' $'\x1b[13:13;2:1u'
  # Existing CSI-u / legacy semicolon event type.
  check_rewrite "$label csi-u" '1b0d' $'\x1b[13;2u'
  check_rewrite "$label semi-press" '1b0d' $'\x1b[13;2;1u'
  check_rewrite "$label semi-repeat" '1b0d' $'\x1b[13;2;2u'
  check_rewrite "$label semi-release" '' $'\x1b[13;2;3u'
  # Already Alt+Enter; unmodified CR; unrelated CSI.
  check_rewrite "$label esc-cr" '1b0d' $'\x1b\r'
  # Lone Esc must flush at EOF; holding ST_ESC forever drops it (#118).
  check_rewrite "$label lone-esc" '1b' $'\x1b'
  check_rewrite "$label cr" '0d' $'\r'
  check_rewrite "$label up" '1b5b41' $'\x1b[A'
  # xterm modifyOtherKeys Shift+Enter.
  check_rewrite "$label mok" '1b0d' $'\x1b[27;2;13~'
}

py=$ROOT/lib/lanjump-keys.py
if [[ ! -f $py ]]; then
  fail "missing python fallback"
else
  REWRITE_CMD=(python3 "$py" --rewrite)
  run_cases py
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if cc -O2 -framework CoreGraphics -o "$tmp/lanjump-keys" "$ROOT/src/lanjump-keys.c"; then
  REWRITE_CMD=("$tmp/lanjump-keys" --rewrite)
  run_cases c
else
  fail "C helper did not compile"
fi

if (( fails )); then
  print -u2 "keys-selftest: $fails failed"
  exit 1
fi
print 'ok keys-rewrite'
