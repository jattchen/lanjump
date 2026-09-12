# Sourced by lanjump.zsh --host-selftest.
# Expects draw, read_key, PENDING_KEY.

host_selftest() {
  local -i fails=0 i
  local out plain
  local -a lines

  items_kind=() items_alias=() items_user=() items_hostname=()
  items_ip=() items_mac=() items_status=() items_saved=()
  for i in {1..32}; do
    items_kind+=("host")
    items_alias+=("box-$i")
    items_user+=("mac")
    items_hostname+=("box-$i.local")
    items_ip+=("192.168.1.$i")
    items_mac+=("")
    items_status+=("已保存")
    items_saved+=("$i")
  done
  cursor=32
  notice=""
  COLUMNS=120
  LINES=14
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  lines=("${(@f)plain}")
  if [[ $plain != *box-32* ]]; then
    print -u2 "FAIL host/viewport missing selected box-32"
    (( fails++ ))
  fi
  if [[ $plain != *还有* ]]; then
    print -u2 "FAIL host/viewport missing overflow hint"
    (( fails++ ))
  fi
  if (( ${#lines} > LINES )); then
    print -u2 "FAIL host/viewport drew ${#lines} lines on LINES=$LINES"
    (( fails++ ))
  fi

  view_start=1
  cursor=1
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *box-1* ]]; then
    print -u2 "FAIL host/viewport top missing box-1"
    (( fails++ ))
  fi
  if [[ $plain != *'↓ 还有'* ]]; then
    print -u2 "FAIL host/viewport top missing below hint"
    (( fails++ ))
  fi

  cursor=32
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *box-32* ]]; then
    print -u2 "FAIL host/viewport wrap-to-last missing box-32"
    (( fails++ ))
  fi

  view_start=1
  LINES=7
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *box-32* ]]; then
    print -u2 "FAIL host/viewport tiny screen missing selected box-32"
    (( fails++ ))
  fi

  zmodload zsh/system || return 1
  local got leftover k1 k2 k
  local -a loop_keys
  expect() {
    local label=$1 want=$2
    got=$3
    if [[ $got != "$want" ]]; then
      print -u2 "FAIL $label got=$(printf %q "$got") want=$(printf %q "$want")"
      (( fails++ ))
    fi
  }
  expect_key() {
    local label=$1 want=$2 seq=$3
    leftover=""
    PENDING_KEY=""
    {
      if read_key; then
        got=$REPLY
      else
        got=EOF
      fi
      sysread leftover || leftover=""
    } < <(print -n -- "$seq")
    expect "$label" "$want" "$got"
    if [[ -n $leftover ]]; then
      print -u2 "FAIL $label leftover=$(printf %q "$leftover")"
      (( fails++ ))
    fi
  }

  expect_key host/key/arrow-up up $'\e[A'
  expect_key host/key/arrow-down down $'\e[B'
  expect_key host/key/pagedown other $'\e[6~'
  expect_key host/key/home other $'\e[H'
  expect_key host/key/end other $'\e[F'
  expect_key host/key/delete other $'\e[3~'
  expect_key host/key/csi-u-s-enter other $'\e[13;2u'
  # #114: lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR/LF).
  expect_key host/key/alt-enter-s-enter other $'\e\r'
  expect_key host/key/alt-enter-lf other $'\e\n'
  expect_key host/key/q q q
  expect_key host/key/esc esc $'\e'

  k1=EOF
  k2=EOF
  PENDING_KEY=""
  {
    read_key && k1=$REPLY
    read_key && k2=$REPLY
  } < <(print -n $'\e[6~\e[A')
  expect host/key/pagedown-then-up-1 other "$k1"
  expect host/key/pagedown-then-up-2 up "$k2"

  loop_keys=()
  local loop_quit=0
  PENDING_KEY=""
  {
    while true; do
      read_key || break
      loop_keys+=("$REPLY")
      case $REPLY in
        q|esc)
          loop_quit=1
          break
          ;;
      esac
    done
  } < <(print -n $'\e[6~\e[H\e[F\e[3~\e[13;2uq')
  expect host/key/loop-quit 1 "$loop_quit"
  if (( ${#loop_keys} != 6 )); then
    print -u2 "FAIL host/key/loop-keys got=${loop_keys[*]} want=5 others then q"
    (( fails++ ))
  elif [[ ${loop_keys[-1]} != q ]]; then
    print -u2 "FAIL host/key/loop-last got=$(printf %q "${loop_keys[-1]}") want=q"
    (( fails++ ))
  fi
  for k in "${loop_keys[1,-2]}"; do
    if [[ $k == esc || $k == q ]]; then
      print -u2 "FAIL host/key/loop-csi treated as quit got=${loop_keys[*]}"
      (( fails++ ))
      break
    fi
  done

  # #114: ESC CR then q must not quit on the first key.
  loop_keys=()
  loop_quit=0
  PENDING_KEY=""
  {
    while true; do
      read_key || break
      loop_keys+=("$REPLY")
      case $REPLY in
        q|esc)
          loop_quit=1
          break
          ;;
      esac
    done
  } < <(print -n $'\e\rq')
  expect host/key/alt-enter-then-q-quit 1 "$loop_quit"
  if (( ${#loop_keys} != 2 )); then
    print -u2 "FAIL host/key/alt-enter-then-q-keys got=${loop_keys[*]} want=other then q"
    (( fails++ ))
  elif [[ ${loop_keys[-1]} != q ]]; then
    print -u2 "FAIL host/key/alt-enter-then-q-last got=$(printf %q "${loop_keys[-1]}") want=q"
    (( fails++ ))
  fi
  if (( ${#loop_keys} >= 1 )) && [[ ${loop_keys[1]} == esc || ${loop_keys[1]} == q ]]; then
    print -u2 "FAIL host/key/alt-enter-then-q treated as quit got=${loop_keys[*]}"
    (( fails++ ))
  fi

  # #112: scan inserts new hosts before 本机/扫描/退出; keep the same item, not the old row.
  scan_keep_fixture() {
    items_kind=(host local scan quit)
    items_alias=(nas 进入本机 '扫描局域网…' 退出)
    items_user=(mac '' '' '')
    items_hostname=(nas.local '' '' '')
    items_ip=(192.168.1.8 '' '' '')
    items_mac=('aa:bb:cc:dd:ee:01' '' '' '')
    items_status=('已保存' '' '' '')
    items_saved=(1 '' '' '')
    h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_last=()
    MYIPS=(127.0.0.1)
    MYIP=""
  }
  scan_keep_insert() {
    local keep n_before
    keep=$(list_item_key $cursor) || keep=
    n_before=${#items_kind}
    add_discovered pi pi.local 192.168.1.50 aa:bb:cc:dd:ee:50
    restore_list_cursor "$keep"
    if (( ${#items_kind} != n_before + 1 )); then
      print -u2 "FAIL host/scan/insert-count got=${#items_kind} want=$((n_before + 1))"
      (( fails++ ))
    fi
    if [[ ${items_kind[2]} != host || ${items_alias[2]} != pi ]]; then
      print -u2 "FAIL host/scan/insert-before-actions got=${items_kind[2]}:${items_alias[2]}"
      (( fails++ ))
    fi
  }

  scan_keep_fixture
  cursor=2
  scan_keep_insert
  expect host/scan/keep-local-kind local "${items_kind[$cursor]}"
  expect host/scan/keep-local-alias 进入本机 "${items_alias[$cursor]}"

  scan_keep_fixture
  cursor=3
  scan_keep_insert
  expect host/scan/keep-scan-kind scan "${items_kind[$cursor]}"
  expect host/scan/keep-scan-alias '扫描局域网…' "${items_alias[$cursor]}"

  scan_keep_fixture
  cursor=4
  scan_keep_insert
  expect host/scan/keep-quit-kind quit "${items_kind[$cursor]}"
  expect host/scan/keep-quit-alias 退出 "${items_alias[$cursor]}"

  scan_keep_fixture
  cursor=1
  scan_keep_insert
  expect host/scan/keep-host-kind host "${items_kind[$cursor]}"
  expect host/scan/keep-host-alias nas "${items_alias[$cursor]}"

  # Rebuild drops an unsaved 新发现 row; restore must use the pre-rebuild identity.
  items_kind=(host host local scan quit)
  items_alias=(nas pi 进入本机 '扫描局域网…' 退出)
  items_user=(mac '' '' '' '')
  items_hostname=(nas.local pi.local '' '' '')
  items_ip=(192.168.1.8 192.168.1.50 '' '' '')
  items_mac=('aa:bb:cc:dd:ee:01' 'aa:bb:cc:dd:ee:50' '' '' '')
  items_status=('已保存' 新发现 '' '' '')
  items_saved=(1 '' '' '' '')
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_last=()
  MYIPS=(127.0.0.1)
  MYIP=""
  cursor=2
  keep=$(list_item_key $cursor) || keep=
  items_kind=(host local scan quit)
  items_alias=(nas 进入本机 '扫描局域网…' 退出)
  items_user=(mac '' '' '')
  items_hostname=(nas.local '' '' '')
  items_ip=(192.168.1.8 '' '' '')
  items_mac=('aa:bb:cc:dd:ee:01' '' '' '')
  items_status=('已保存' '' '' '')
  items_saved=(1 '' '' '')
  add_discovered pi pi.local 192.168.1.50 aa:bb:cc:dd:ee:50
  restore_list_cursor "$keep"
  expect host/scan/keep-discovered-kind host "${items_kind[$cursor]}"
  expect host/scan/keep-discovered-alias pi "${items_alias[$cursor]}"

  if [[ ${functions[do_scan]} != *list_item_key* || ${functions[do_scan]} != *restore_list_cursor* ]]; then
    print -u2 "FAIL host/scan/do_scan missing list_item_key/restore_list_cursor"
    (( fails++ ))
  fi

  if (( fails )); then
    print -u2 "host-selftest: $fails failed"
    return 1
  fi
  print "ok host"
  return 0
}
