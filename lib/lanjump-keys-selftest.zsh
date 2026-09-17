#!/bin/zsh
# Run from repo: zsh lib/lanjump-keys-selftest.zsh
# Seam: lanjump-keys --rewrite and wrap-mode pty drain (C helper and Python fallback).
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

# Wrap-mode public seam: stdin is a tty so forkpty/openpty is used.
# Child writes more than one 512-byte read, then a tail, then exits.
# After waitpid(WNOHANG) the parent must keep reading until 0/EIO (#288).
check_pty_drain() {
  local name=$1
  shift
  local marker='LANJUMP_KEYS_DRAIN_288'
  local got
  got=$(python3 -c '
import os, pty, sys

argv = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
chunks = []
while True:
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    chunks.append(data)
os.waitpid(pid, 0)
sys.stdout.buffer.write(b"".join(chunks))
' "$@" sh -c "printf '%2000s' x; printf '%s\\n' '$marker'") || true
  if [[ $got != *"$marker"* ]]; then
    fail "$name pty-drain-after-exit: missing $marker got ${got:-<empty>}"
  fi
}

# Linux waitpid(WNOHANG) reaps after the first 512-byte read and drops the tail.
# Darwin often keeps the child waitable until the pty is drained, so host wrap
# alone can miss #288. docker -t gives the helper a tty without a new test file.
check_pty_drain_linux() {
  local marker='LANJUMP_KEYS_DRAIN_288'
  local got
  if ! command -v docker >/dev/null; then
    return
  fi
  if ! docker image inspect python:3.12-slim >/dev/null 2>&1; then
    return
  fi
  got=$(docker run --rm --pull=never -t -v "$ROOT:/src:ro" python:3.12-slim \
    python3 /src/lib/lanjump-keys.py \
    sh -c "printf '%2000s' x; printf '%s\\n' '$marker'") || true
  if [[ $got != *"$marker"* ]]; then
    fail "linux-py pty-drain-after-exit: missing $marker got ${got:-<empty>}"
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
  check_pty_drain py python3 "$py"
  check_pty_drain_linux
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if cc -O2 -framework CoreGraphics -o "$tmp/lanjump-keys" "$ROOT/src/lanjump-keys.c"; then
  REWRITE_CMD=("$tmp/lanjump-keys" --rewrite)
  run_cases c
  check_pty_drain c "$tmp/lanjump-keys"
else
  fail "C helper did not compile"
fi

if (( fails )); then
  print -u2 "keys-selftest: $fails failed"
  exit 1
fi
print 'ok keys-rewrite'
