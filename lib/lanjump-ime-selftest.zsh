# Sourced by lanjump.zsh --ime-selftest.
# Expects ime_enabled, should_switch_ime, ime_switch_command, toggle_ime,
# maybe_switch_ime, draw. Must not require a live GUI or change the real IME.
IME_SELFTEST_LIB=${0:A:h}

ime_selftest() {
  local -i fails=0
  local tmp saved_app saved_py saved_switched saved_notice out plain cmd helper src ran
  local saved_ssh_connection saved_ssh_client saved_ssh_tty

  expect_fn() {
    if ! typeset -f $1 >/dev/null; then
      print -u2 "FAIL missing $1"
      (( fails++ ))
      return 1
    fi
  }

  expect_fn ime_enabled
  expect_fn should_switch_ime
  expect_fn ime_switch_command
  expect_fn toggle_ime
  expect_fn maybe_switch_ime
  expect_fn local_keyboard

  saved_app=$APP
  saved_py=${IME_PY:-}
  saved_switched=${ime_switched:-0}
  saved_notice=${notice:-}
  saved_ssh_connection=${SSH_CONNECTION:-}
  saved_ssh_client=${SSH_CLIENT:-}
  saved_ssh_tty=${SSH_TTY:-}
  tmp=$(mktemp -d)
  APP=$tmp
  ime_switched=0
  notice=""
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY

  if typeset -f ime_enabled >/dev/null; then
    if ! ime_enabled; then
      print -u2 "FAIL ime_enabled default (missing file) should be on"
      (( fails++ ))
    fi
    print -r -- on >"$tmp/ime"
    if ! ime_enabled; then
      print -u2 "FAIL ime_enabled on"
      (( fails++ ))
    fi
    print -r -- 'ON' >"$tmp/ime"
    if ! ime_enabled; then
      print -u2 "FAIL ime_enabled ON (case)"
      (( fails++ ))
    fi
    print -r -- $'off\n' >"$tmp/ime"
    if ime_enabled; then
      print -u2 "FAIL ime_enabled off should be disabled"
      (( fails++ ))
    fi
    print -r -- ' OFF ' >"$tmp/ime"
    if ime_enabled; then
      print -u2 "FAIL ime_enabled padded OFF should be disabled"
      (( fails++ ))
    fi
    print -r -- garbage >"$tmp/ime"
    if ! ime_enabled; then
      print -u2 "FAIL ime_enabled unknown value should stay on"
      (( fails++ ))
    fi
    rm -f "$tmp/ime"
  fi

  if typeset -f should_switch_ime >/dev/null; then
    rm -f "$tmp/ime"
    unset SSH_CONNECTION SSH_CLIENT SSH_TTY
    if ! should_switch_ime; then
      print -u2 "FAIL should_switch_ime default local should switch"
      (( fails++ ))
    fi
    print -r -- off >"$tmp/ime"
    if should_switch_ime; then
      print -u2 "FAIL should_switch_ime disabled should skip"
      (( fails++ ))
    fi
    rm -f "$tmp/ime"
    SSH_CONNECTION='1.2.3.4 22 10.0.0.1 22'
    if should_switch_ime; then
      print -u2 "FAIL should_switch_ime SSH_CONNECTION should skip"
      (( fails++ ))
    fi
    unset SSH_CONNECTION
    SSH_CLIENT='1.2.3.4 22 10.0.0.1 22'
    if should_switch_ime; then
      print -u2 "FAIL should_switch_ime SSH_CLIENT should skip"
      (( fails++ ))
    fi
    unset SSH_CLIENT
    SSH_TTY=/dev/ttys001
    if should_switch_ime; then
      print -u2 "FAIL should_switch_ime SSH_TTY should skip"
      (( fails++ ))
    fi
    unset SSH_TTY
  fi

  helper=${saved_py:-$IME_SELFTEST_LIB/lanjump-ime.py}
  if [[ ! -f $helper ]]; then
    print -u2 "FAIL missing Carbon helper $helper"
    (( fails++ ))
  else
    src=$(<"$helper")
    if [[ $src != *TISSelectInputSource* ]]; then
      print -u2 "FAIL helper missing TISSelectInputSource"
      (( fails++ ))
    fi
    if [[ $src != *com.apple.keylayout.ABC* ]]; then
      print -u2 "FAIL helper missing com.apple.keylayout.ABC"
      (( fails++ ))
    fi
    if [[ $src != *com.apple.keylayout.US* ]]; then
      print -u2 "FAIL helper missing US fallback"
      (( fails++ ))
    fi
  fi

  if typeset -f ime_switch_command >/dev/null; then
    IME_PY=$helper
    cmd=$(ime_switch_command) || cmd=
    if [[ $cmd != *python3* ]]; then
      print -u2 "FAIL ime_switch_command missing python3 got=$(printf %q "$cmd")"
      (( fails++ ))
    fi
    if [[ $cmd != *lanjump-ime.py* ]]; then
      print -u2 "FAIL ime_switch_command missing helper path got=$(printf %q "$cmd")"
      (( fails++ ))
    fi
  fi

  print -r -- "open(r'''$tmp/ran''', 'a').write('x')" >"$tmp/stub.py"
  IME_PY=$tmp/stub.py

  if typeset -f toggle_ime >/dev/null; then
    rm -f "$tmp/ime"
    toggle_ime
    if [[ $(<"$tmp/ime") != off ]]; then
      print -u2 "FAIL toggle_ime default on -> off got=$(printf %q "$(<"$tmp/ime")")"
      (( fails++ ))
    fi
    if ime_enabled; then
      print -u2 "FAIL toggle_ime should disable"
      (( fails++ ))
    fi
    toggle_ime
    if [[ $(<"$tmp/ime") != on ]]; then
      print -u2 "FAIL toggle_ime off -> on got=$(printf %q "$(<"$tmp/ime")")"
      (( fails++ ))
    fi
    if ! ime_enabled; then
      print -u2 "FAIL toggle_ime should enable"
      (( fails++ ))
    fi
  fi

  if typeset -f maybe_switch_ime >/dev/null; then
    rm -f "$tmp/ime" "$tmp/ran"
    unset SSH_CONNECTION SSH_CLIENT SSH_TTY
    ime_switched=0
    maybe_switch_ime
    maybe_switch_ime
    ran=
    [[ -f $tmp/ran ]] && ran=$(<"$tmp/ran")
    if [[ $ran != x ]]; then
      print -u2 "FAIL maybe_switch_ime should run once got=$(printf %q "$ran")"
      (( fails++ ))
    fi

    rm -f "$tmp/ran"
    ime_switched=0
    SSH_CONNECTION='1.2.3.4 22'
    maybe_switch_ime
    if [[ -f $tmp/ran ]]; then
      print -u2 "FAIL maybe_switch_ime SSH should not run helper"
      (( fails++ ))
    fi
    unset SSH_CONNECTION

    rm -f "$tmp/ran"
    ime_switched=0
    print -r -- off >"$tmp/ime"
    maybe_switch_ime
    if [[ -f $tmp/ran ]]; then
      print -u2 "FAIL maybe_switch_ime disabled should not run helper"
      (( fails++ ))
    fi
    rm -f "$tmp/ime"
  fi

  items_kind=("host") items_alias=("box") items_user=("mac")
  items_hostname=("box.local") items_ip=("192.168.1.2") items_mac=("")
  items_status=("已保存") items_saved=("1")
  cursor=1
  notice=""
  COLUMNS=120
  LINES=20
  view_start=1
  rm -f "$tmp/ime"
  if typeset -f draw >/dev/null; then
    out=$(draw)
    plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
    if [[ $plain != *'i 英文'* ]]; then
      print -u2 "FAIL header missing i 英文 when enabled"
      (( fails++ ))
    fi
    print -r -- off >"$tmp/ime"
    out=$(draw)
    plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
    if [[ $plain != *'i 英文关'* ]]; then
      print -u2 "FAIL header missing i 英文关 when disabled"
      (( fails++ ))
    fi
  fi

  out=$(/bin/zsh "$IME_SELFTEST_LIB/lanjump.zsh" help)
  if [[ $out != *用法：lanjump* ]]; then
    print -u2 "FAIL help missing 用法：lanjump"
    (( fails++ ))
  fi
  if [[ $out != *'i 开关打开时切英文输入法'* ]]; then
    print -u2 "FAIL help missing i 英文 toggle"
    (( fails++ ))
  fi

  APP=$saved_app
  IME_PY=$saved_py
  ime_switched=$saved_switched
  notice=$saved_notice
  if [[ -n $saved_ssh_connection ]]; then
    SSH_CONNECTION=$saved_ssh_connection
  else
    unset SSH_CONNECTION
  fi
  if [[ -n $saved_ssh_client ]]; then
    SSH_CLIENT=$saved_ssh_client
  else
    unset SSH_CLIENT
  fi
  if [[ -n $saved_ssh_tty ]]; then
    SSH_TTY=$saved_ssh_tty
  else
    unset SSH_TTY
  fi
  rm -rf "$tmp"

  if (( fails )); then
    print -u2 "ime-selftest: $fails failed"
    return 1
  fi
  print "ok ime"
  return 0
}
