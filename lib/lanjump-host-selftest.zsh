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

  # #258: SGR mouse CSI must drain so leftover 0;10;20M is not num0.
  k1=EOF
  k2=EOF
  PENDING_KEY=""
  {
    read_key && k1=$REPLY
    read_key && k2=$REPLY
  } < <(print -n $'\e[<0;10;20Mq')
  expect host/key/sgr-mouse-then-q-1 other "$k1"
  expect host/key/sgr-mouse-then-q-2 q "$k2"

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

  # #211: DHCP reuse of a saved IP must not steal that alias's MAC/hostname.
  h_alias=(office)
  h_user=(mac)
  h_hostname=(office.local)
  h_ip=(192.168.1.5)
  h_mac=('aa:bb:cc:dd:ee:01')
  h_last=(100)
  items_kind=(host local scan quit)
  items_alias=(office 进入本机 '扫描局域网…' 退出)
  items_user=(mac '' '' '')
  items_hostname=(office.local '' '' '')
  items_ip=(192.168.1.5 '' '' '')
  items_mac=('aa:bb:cc:dd:ee:01' '' '' '')
  items_status=('已保存' '' '' '')
  items_saved=(1 '' '' '')
  s_alias=() s_host=() s_ip=() s_mac=()
  MYIPS=(127.0.0.1)
  MYIP=""
  record_seen pi pi.local 192.168.1.5 'ff:ee:dd:cc:bb:aa'
  add_discovered pi pi.local 192.168.1.5 'ff:ee:dd:cc:bb:aa'
  expect host/scan/ip-fallback-keeps-alias office "${h_alias[1]}"
  expect host/scan/ip-fallback-keeps-hostname office.local "${h_hostname[1]}"
  expect host/scan/ip-fallback-keeps-mac 'aa:bb:cc:dd:ee:01' "${h_mac[1]}"

  # #217: /23 is the interface prefix; 192.168.3.10/23 must include 192.168.2.x.
  if ! (( ${+functions[scan_lan_prefixes]} )); then
    print -u2 "FAIL host/scan/netmask-23 missing scan_lan_prefixes"
    (( fails++ ))
  else
    expect host/scan/netmask-23 $'192.168.2\n192.168.3' "$(scan_lan_prefixes 192.168.3.10 255.255.254.0)"
  fi
  if [[ ${functions[scan_port22]} != *scan_lan_prefixes* ]]; then
    print -u2 "FAIL host/scan/netmask-23 scan_port22 still scans one /24"
    (( fails++ ))
  fi

  # #225: N open hosts must not wait 3N seconds for serial ssh-keyscan.
  # Inspect bodies (no real -T 3). Parallel like scan_port22, or a helper.
  if [[ ${functions[merge_seen_by_hostkey]} == *'$(ssh_fp'* ]]; then
    print -u2 "FAIL host/scan/keyscan merge_seen_by_hostkey still serial ssh_fp"
    (( fails++ ))
  elif (( ${+functions[fill_seen_hostkeys]} )); then
    if [[ ${functions[fill_seen_hostkeys]} != *') &'* || ${functions[fill_seen_hostkeys]} != *wait* ]]; then
      print -u2 "FAIL host/scan/keyscan fill_seen_hostkeys missing batched &/wait"
      (( fails++ ))
    fi
  elif [[ ${functions[merge_seen_by_hostkey]} != *') &'* || ${functions[merge_seen_by_hostkey]} != *wait* ]]; then
    print -u2 "FAIL host/scan/keyscan merge_seen_by_hostkey missing batched &/wait"
    (( fails++ ))
  fi

  # Same host key still collapses two IPs; a third key stays. Mock ssh_fp.
  local _lj_save_ssh_fp=$functions[ssh_fp]
  ssh_fp() {
    case $1 in
      203.0.113.10|203.0.113.11) print -r -- SHA256:same-host ;;
      203.0.113.12) print -r -- SHA256:other-host ;;
    esac
  }
  s_alias=(nas 203.0.113.11 pi)
  s_host=(nas.local '' pi.local)
  s_ip=(203.0.113.10 203.0.113.11 203.0.113.12)
  s_mac=('aa:bb:cc:dd:ee:10' '' 'aa:bb:cc:dd:ee:12')
  merge_seen_by_hostkey
  expect host/scan/keyscan-merge-count 2 "${#s_ip}"
  expect host/scan/keyscan-merge-keep-ip 203.0.113.10 "${s_ip[1]}"
  expect host/scan/keyscan-merge-keep-alias nas "${s_alias[1]}"
  expect host/scan/keyscan-merge-other-ip 203.0.113.12 "${s_ip[2]}"
  functions[ssh_fp]=$_lj_save_ssh_fp

  # #186: 「已保存 · 上次」 follows LAST_FILE (read_last), not max h_last.
  local saved_last_file=$LAST_FILE
  local last_tmp office_status studio_status
  last_tmp=$(mktemp) || return 1
  LAST_FILE=$last_tmp
  print -r -- office >"$LAST_FILE"
  h_alias=(office studio)
  h_user=(mac mac)
  h_hostname=(office.local studio.local)
  h_ip=(10.0.0.1 10.0.0.2)
  h_mac=('' '')
  h_last=(100 200)
  build_items
  office_status=
  studio_status=
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    if [[ ${items_kind[$i]} == host && ${items_alias[$i]} == office ]]; then
      office_status=${items_status[$i]}
    elif [[ ${items_kind[$i]} == host && ${items_alias[$i]} == studio ]]; then
      studio_status=${items_status[$i]}
    fi
  done
  expect host/last-badge/office '已保存 · 上次' "$office_status"
  expect host/last-badge/studio '已保存' "$studio_status"
  LAST_FILE=$saved_last_file
  rm -f "$last_tmp"

  # #219: Bonjour aliases may contain |; load must not shift the other fields.
  local saved_hosts_file=$HOSTS_FILE
  local hosts_tmp pipe_idx
  hosts_tmp=$(mktemp) || return 1
  HOSTS_FILE=$hosts_tmp
  print -r -- 'Kitchen|Mac|user|kitchen.local|192.168.1.20|aa:bb:cc:dd:ee:ff|123' >"$HOSTS_FILE"
  load_hosts
  expect host/pipe-alias/count 1 "${#h_alias}"
  expect host/pipe-alias/alias 'Kitchen|Mac' "${h_alias[1]}"
  expect host/pipe-alias/user user "${h_user[1]}"
  expect host/pipe-alias/hostname kitchen.local "${h_hostname[1]}"
  expect host/pipe-alias/ip 192.168.1.20 "${h_ip[1]}"
  expect host/pipe-alias/mac aa:bb:cc:dd:ee:ff "${h_mac[1]}"
  expect host/pipe-alias/last 123 "${h_last[1]}"
  pipe_idx=
  for (( i = 1; i <= ${#h_alias}; i++ )); do
    if [[ ${h_alias[$i]} == 'Kitchen|Mac' ]]; then
      pipe_idx=$i
      break
    fi
  done
  expect host/pipe-alias/lookup 1 "$pipe_idx"
  HOSTS_FILE=$saved_hosts_file
  rm -f "$hosts_tmp"

  # #264: } >"$HOSTS_FILE" truncates dest before the new rows exist.
  # Mirror pick-selftest filter/atomic-write + snap/atomic-write.
  if [[ ${functions[save_hosts]} != *replace_file_atomic* ]]; then
    print -u2 "FAIL hosts/atomic-write missing replace_file_atomic"
    (( fails++ ))
  fi
  local hosts264 hosts264_old hosts264_mid
  local -i hosts264_torn=0 hosts264_rows
  hosts264=$(mktemp) || return 1
  saved_hosts_file=$HOSTS_FILE
  HOSTS_FILE=$hosts264
  print -r -- $'# alias|user|hostname|ip|mac|last\nold|mac|old.local|10.0.0.9||1' >"$HOSTS_FILE"
  hosts264_old=$(<"$HOSTS_FILE")
  h_alias=(office studio nas)
  h_user=(mac mac mac)
  h_hostname=(office.local studio.local nas.local)
  h_ip=(10.0.0.1 10.0.0.2 10.0.0.3)
  h_mac=('aa:bb:cc:dd:ee:01' 'aa:bb:cc:dd:ee:02' 'aa:bb:cc:dd:ee:03')
  h_last=(100 200 300)
  print() {
    builtin print "$@"
    hosts264_mid=$(<"$HOSTS_FILE")
    if [[ $hosts264_mid == "$hosts264_old" ]]; then
      return 0
    fi
    if [[ -z $hosts264_mid ]]; then
      hosts264_torn=1
      return 0
    fi
    hosts264_rows=0
    local line
    local -a f
    for line in "${(@f)hosts264_mid}"; do
      [[ $line == \#* || -z $line ]] && continue
      f=("${(@s:|:)line}")
      if (( ${#f} >= 6 )); then
        (( hosts264_rows++ ))
      else
        hosts264_torn=1
      fi
    done
    if (( hosts264_rows != 3 )); then
      hosts264_torn=1
    fi
  }
  save_hosts
  unfunction print
  if (( hosts264_torn )); then
    print -u2 "FAIL hosts/atomic-write dest was torn mid-save"
    (( fails++ ))
  fi
  load_hosts
  expect hosts/atomic-write-count 3 "${#h_alias}"
  expect hosts/atomic-write-alias office "${h_alias[1]}"
  HOSTS_FILE=$saved_hosts_file
  rm -f "$hosts264"

  # #266: print >"$LAST_FILE" truncates dest before the new alias exists.
  # Mirror hosts/atomic-write. Source-check the real mark_last (host-selftest
  # never stubs it; cli-selftest #168 does).
  if [[ ${functions[mark_last]} != *replace_file_atomic* ]]; then
    print -u2 "FAIL last/atomic-write missing replace_file_atomic"
    (( fails++ ))
  fi
  local last266 last266_mid
  local -i last266_torn=0
  last266=$(mktemp) || return 1
  saved_last_file=$LAST_FILE
  LAST_FILE=$last266
  print -r -- office >"$LAST_FILE"
  print() {
    last266_mid=$(<"$LAST_FILE")
    if [[ -z $last266_mid ]]; then
      last266_torn=1
    fi
    builtin print "$@"
  }
  mark_last studio
  unfunction print
  if (( last266_torn )); then
    print -u2 "FAIL last/atomic-write dest was torn mid-save"
    (( fails++ ))
  fi
  expect last/atomic-write-alias studio "$(read_last)"
  LAST_FILE=$saved_last_file
  rm -f "$last266"

  if (( fails )); then
    print -u2 "host-selftest: $fails failed"
    return 1
  fi
  print "ok host"
  return 0
}
