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

  # #304: Same mDNS hostname from another MAC must not steal that alias's IP/MAC.
  h_alias=(foo)
  h_user=(mac)
  h_hostname=(foo.local)
  h_ip=(192.168.1.10)
  h_mac=('aa:bb:cc:dd:ee:01')
  h_last=(100)
  items_kind=(host local scan quit)
  items_alias=(foo 进入本机 '扫描局域网…' 退出)
  items_user=(mac '' '' '')
  items_hostname=(foo.local '' '' '')
  items_ip=(192.168.1.10 '' '' '')
  items_mac=('aa:bb:cc:dd:ee:01' '' '' '')
  items_status=('已保存' '' '' '')
  items_saved=(1 '' '' '')
  s_alias=() s_host=() s_ip=() s_mac=()
  MYIPS=(127.0.0.1)
  MYIP=""
  record_seen foo foo.local 192.168.1.99 'ff:ee:dd:cc:bb:aa'
  add_discovered foo foo.local 192.168.1.99 'ff:ee:dd:cc:bb:aa'
  expect host/scan/hostname-keeps-alias foo "${h_alias[1]}"
  expect host/scan/hostname-keeps-hostname foo.local "${h_hostname[1]}"
  expect host/scan/hostname-keeps-ip 192.168.1.10 "${h_ip[1]}"
  expect host/scan/hostname-keeps-mac 'aa:bb:cc:dd:ee:01' "${h_mac[1]}"

  # #332: Live-list mark_online must not rewrite a MAC-bearing saved row
  # when another machine announces the same mDNS hostname.
  local office_ip office_mac
  h_alias=(office)
  h_user=(mac)
  h_hostname=(office.local)
  h_ip=(10.0.0.9)
  h_mac=('aa:bb:cc:dd:ee:01')
  h_port=(22)
  h_last=(100)
  MYIPS=(127.0.0.1)
  MYIP=""
  build_items
  add_discovered office.local office.local 10.0.0.77 'de:ad:be:ef:00:77'
  mark_online 10.0.0.77 'de:ad:be:ef:00:77' office.local
  office_ip=
  office_mac=
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    if [[ ${items_kind[$i]} == host && ${items_alias[$i]} == office && -n ${items_saved[$i]} ]]; then
      office_ip=${items_ip[$i]}
      office_mac=${items_mac[$i]}
      break
    fi
  done
  expect host/scan/live-hostname-keeps-ip 10.0.0.9 "$office_ip"
  expect host/scan/live-hostname-keeps-mac 'aa:bb:cc:dd:ee:01' "$office_mac"

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

  # #425: Bonjour off-LAN first, port22 current-LAN later, same hostkey —
  # keep the scan-LAN address (not the earlier USB/Thunderbolt 10.x).
  local saved_myip=$MYIP saved_mask=$MASK
  _lj_save_ssh_fp=$functions[ssh_fp]
  MYIP=198.51.100.1
  MASK=255.255.255.0
  ssh_fp() {
    case $1 in
      10.55.1.8|198.51.100.8) print -r -- SHA256:dual-nic ;;
    esac
  }
  s_alias=(office 198.51.100.8)
  s_host=(office.local '')
  s_ip=(10.55.1.8 198.51.100.8)
  s_mac=('aa:bb:cc:dd:ee:08' 'aa:bb:cc:dd:ee:88')
  s_port=(22 22)
  merge_seen_by_hostkey
  expect host/scan/hostkey-prefer-scan-lan/count 1 "${#s_ip}"
  expect host/scan/hostkey-prefer-scan-lan/ip 198.51.100.8 "${s_ip[1]}"
  expect host/scan/hostkey-prefer-scan-lan/alias office "${s_alias[1]}"
  functions[ssh_fp]=$_lj_save_ssh_fp
  MYIP=$saved_myip
  MASK=$saved_mask

  # #280: advertised _ssh._tcp port must stay on the discovery row
  # and later SSH (not silently become 22).
  local _lj_save_run_timed=$functions[run_timed]
  local _lj_save_get_mac=$functions[get_mac]
  local _lj_save_is_self=$functions[is_self_ip]
  local bonjour_line discovered_port
  local -a bf saved_ssh_opts
  run_timed() {
    local out=$2
    shift 2
    case "$*" in
      *'dns-sd -B'*)
        print -r -- $'Timestamp     A/R    Flags  if Domain               Service Type         Instance Name\n 9:00:00.000  Add        3  1 local.               _ssh._tcp.           pi' >"$out"
        ;;
      *'dns-sd -L'*)
        print -r -- ' pi._ssh._tcp.local. can be reached at pi.local.:2222' >"$out"
        ;;
      *'dns-sd -G'*)
        print -r -- $'Timestamp     A/R  if Hostname      Address         TTL\n 9:00:01.000  Add   1 pi.local.     192.168.1.50    120' >"$out"
        ;;
      *)
        : >"$out"
        ;;
    esac
  }
  get_mac() { print -r -- 'aa:bb:cc:dd:ee:50'; }
  is_self_ip() { return 1; }
  bonjour_line=$(scan_bonjour)
  functions[run_timed]=$_lj_save_run_timed
  functions[get_mac]=$_lj_save_get_mac
  functions[is_self_ip]=$_lj_save_is_self
  bf=("${(@s:	:)bonjour_line}")
  expect host/bonjour-port/host pi.local "${bf[2]:-}"
  expect host/bonjour-port/ip 192.168.1.50 "${bf[3]:-}"
  expect host/bonjour-port/scan 2222 "${bf[5]:-}"

  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_last=()
  items_kind=(local scan quit)
  items_alias=(进入本机 '扫描局域网…' 退出)
  items_user=('' '' '')
  items_hostname=('' '' '')
  items_ip=('' '' '')
  items_mac=('' '' '')
  items_status=('' '' '')
  items_saved=('' '' '')
  items_port=('' '' '')
  s_alias=() s_host=() s_ip=() s_mac=() s_port=()
  MYIPS=(127.0.0.1)
  MYIP=""
  while IFS=$'\t' read -r alias hostname ip mac port; do
    [[ -n $alias || -n $ip ]] || continue
    record_seen "$alias" "$hostname" "$ip" "$mac" "$port"
    add_discovered "$alias" "$hostname" "$ip" "$mac" "$port"
  done <<< "$bonjour_line"
  discovered_port=
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    if [[ ${items_kind[$i]} == host && ${items_alias[$i]} == pi ]]; then
      discovered_port=${items_port[$i]:-}
      break
    fi
  done
  expect host/bonjour-port/item 2222 "$discovered_port"
  if (( ${+functions[apply_ssh_port]} )); then
    saved_ssh_opts=("${SSH_OPTS[@]}")
    SSH_OPTS=()
    apply_ssh_port "$discovered_port"
    expect host/bonjour-port/ssh-opt '-o Port=2222' "${SSH_OPTS[*]}"
    SSH_OPTS=("${saved_ssh_opts[@]}")
  else
    print -u2 "FAIL host/bonjour-port/ssh-opt missing apply_ssh_port"
    (( fails++ ))
  fi
  if [[ ${functions[connect_item]} != *apply_ssh_port* ]]; then
    print -u2 "FAIL host/bonjour-port/connect_item never applies advertised port"
    (( fails++ ))
  fi

  # #312: a saved custom port must become 22 when Bonjour announces 22.
  local item_port
  _lj_save_run_timed=$functions[run_timed]
  _lj_save_get_mac=$functions[get_mac]
  _lj_save_is_self=$functions[is_self_ip]
  run_timed() {
    local out=$2
    shift 2
    case "$*" in
      *'dns-sd -B'*)
        print -r -- $'Timestamp     A/R    Flags  if Domain               Service Type         Instance Name\n 9:00:00.000  Add        3  1 local.               _ssh._tcp.           pi' >"$out"
        ;;
      *'dns-sd -L'*)
        print -r -- ' pi._ssh._tcp.local. can be reached at pi.local.:22' >"$out"
        ;;
      *'dns-sd -G'*)
        print -r -- $'Timestamp     A/R  if Hostname      Address         TTL\n 9:00:01.000  Add   1 pi.local.     192.168.1.50    120' >"$out"
        ;;
      *)
        : >"$out"
        ;;
    esac
  }
  get_mac() { print -r -- 'aa:bb:cc:dd:ee:50'; }
  is_self_ip() { return 1; }
  bonjour_line=$(scan_bonjour)
  functions[run_timed]=$_lj_save_run_timed
  functions[get_mac]=$_lj_save_get_mac
  functions[is_self_ip]=$_lj_save_is_self
  bf=("${(@s:	:)bonjour_line}")
  expect host/bonjour-port-to-22/scan 22 "${bf[5]:-}"

  h_alias=(pi)
  h_user=(mac)
  h_hostname=(pi.local)
  h_ip=(192.168.1.50)
  h_mac=('aa:bb:cc:dd:ee:50')
  h_port=(2222)
  h_last=(100)
  items_kind=(host local scan quit)
  items_alias=(pi 进入本机 '扫描局域网…' 退出)
  items_user=(mac '' '' '')
  items_hostname=(pi.local '' '' '')
  items_ip=(192.168.1.50 '' '' '')
  items_mac=('aa:bb:cc:dd:ee:50' '' '' '')
  items_port=(2222 '' '' '')
  items_status=('已保存' '' '' '')
  items_saved=(1 '' '' '')
  s_alias=() s_host=() s_ip=() s_mac=() s_port=()
  MYIPS=(127.0.0.1)
  MYIP=""
  while IFS=$'\t' read -r alias hostname ip mac port; do
    [[ -n $alias || -n $ip ]] || continue
    record_seen "$alias" "$hostname" "$ip" "$mac" "$port"
    add_discovered "$alias" "$hostname" "$ip" "$mac" "$port"
  done <<< "$bonjour_line"
  expect host/bonjour-port-to-22/saved 22 "${h_port[1]:-}"
  build_items
  item_port=
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    if [[ ${items_kind[$i]} == host && ${items_alias[$i]} == pi ]]; then
      item_port=${items_port[$i]:-}
      break
    fi
  done
  expect host/bonjour-port-to-22/item 22 "$item_port"

  # #362: multiple A records — prefer the scan-subnet address, not docker0 last.
  local saved_myip=$MYIP saved_mask=$MASK
  _lj_save_run_timed=$functions[run_timed]
  _lj_save_get_mac=$functions[get_mac]
  _lj_save_is_self=$functions[is_self_ip]
  MYIP=192.168.1.10
  MASK=255.255.255.0
  run_timed() {
    local out=$2
    shift 2
    case "$*" in
      *'dns-sd -B'*)
        print -r -- $'Timestamp     A/R    Flags  if Domain               Service Type         Instance Name\n 9:00:00.000  Add        3  1 local.               _ssh._tcp.           pi' >"$out"
        ;;
      *'dns-sd -L'*)
        print -r -- ' pi._ssh._tcp.local. can be reached at pi.local.:22' >"$out"
        ;;
      *'dns-sd -G'*)
        print -r -- $'Timestamp     A/R  if Hostname      Address         TTL\n 9:00:01.000  Add   1 pi.local.     192.168.1.50    120\n 9:00:01.001  Add   2 pi.local.     172.17.0.1      120' >"$out"
        ;;
      *)
        : >"$out"
        ;;
    esac
  }
  get_mac() { print -r -- 'aa:bb:cc:dd:ee:50'; }
  is_self_ip() { return 1; }
  bonjour_line=$(scan_bonjour)
  functions[run_timed]=$_lj_save_run_timed
  functions[get_mac]=$_lj_save_get_mac
  functions[is_self_ip]=$_lj_save_is_self
  MYIP=$saved_myip
  MASK=$saved_mask
  bf=("${(@s:	:)bonjour_line}")
  expect host/bonjour-prefer-scan-subnet/ip 192.168.1.50 "${bf[3]:-}"

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

  # #314: two save_hosts writers load then replace the whole hosts file.
  # A mutates, yields, then saves; B writes in the gap. Both rows must remain.
  local hosts314_home hosts314_saved_home hosts314_saved_ssh hosts314_saved_key
  local hosts314_fn hosts314_got
  local -i hosts314_a=0 hosts314_b=0
  hosts314_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-314.XXXXXX") || return 1
  hosts314_saved_home=$HOME
  hosts314_saved_ssh=$SSH_CONFIG
  hosts314_saved_key=$KEY
  saved_hosts_file=$HOSTS_FILE
  mkdir -p "$hosts314_home/Library/Application Support/lanjump" "$hosts314_home/.ssh"
  HOSTS_FILE="$hosts314_home/Library/Application Support/lanjump/hosts"
  SSH_CONFIG="$hosts314_home/.ssh/config"
  KEY="$hosts314_home/.ssh/id_ed25519_lanjump"
  HOME=$hosts314_home
  : >"$HOSTS_FILE"
  : >"$SSH_CONFIG"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$hosts314_home")"
    print -r -- "HOSTS_FILE=$(printf %q "$HOSTS_FILE")"
    print -r -- "SSH_CONFIG=$(printf %q "$SSH_CONFIG")"
    print -r -- "KEY=$(printf %q "$KEY")"
    print -r -- 'typeset -a h_alias h_user h_hostname h_ip h_mac h_port h_ssh_id h_last'
    for hosts314_fn in ssh_id_tag ssh_id_from_alias ssh_id_taken alloc_ssh_id \
      load_hosts replace_file_atomic save_hosts find_saved upsert_host \
      strip_ssh_block remove_ssh_config replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$hosts314_fn]} )) && functions "$hosts314_fn"
    done
    print -r -- 'functions -c save_hosts _hosts314_save'
    print -r -- 'save_hosts() {'
    print -r -- '  print -r -- loaded >"$HOME/loaded"'
    print -r -- '  sleep 0.35'
    print -r -- '  _hosts314_save "$@"'
    print -r -- '}'
    print -r -- "upsert_host office mac office.local 10.0.0.1 'aa:bb:cc:dd:ee:01'"
  } >"$hosts314_home/child-a.zsh"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$hosts314_home")"
    print -r -- "HOSTS_FILE=$(printf %q "$HOSTS_FILE")"
    print -r -- "SSH_CONFIG=$(printf %q "$SSH_CONFIG")"
    print -r -- "KEY=$(printf %q "$KEY")"
    print -r -- 'typeset -a h_alias h_user h_hostname h_ip h_mac h_port h_ssh_id h_last'
    for hosts314_fn in ssh_id_tag ssh_id_from_alias ssh_id_taken alloc_ssh_id \
      load_hosts replace_file_atomic save_hosts find_saved upsert_host \
      strip_ssh_block remove_ssh_config replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$hosts314_fn]} )) && functions "$hosts314_fn"
    done
    print -r -- 'while [[ ! -f $HOME/loaded ]]; do'
    print -r -- '  sleep 0.01'
    print -r -- 'done'
    print -r -- "upsert_host studio mac studio.local 10.0.0.2 'aa:bb:cc:dd:ee:02'"
  } >"$hosts314_home/child-b.zsh"
  /bin/zsh "$hosts314_home/child-a.zsh" &
  hosts314_a=$!
  /bin/zsh "$hosts314_home/child-b.zsh" &
  hosts314_b=$!
  wait $hosts314_a
  wait $hosts314_b
  load_hosts
  hosts314_got="${h_alias[*]}"
  if ! (( ${h_alias[(Ie)office]} && ${h_alias[(Ie)studio]} )); then
    print -u2 "FAIL hosts/concurrent-write lost an update aliases=$(printf %q "$hosts314_got")"
    (( fails++ ))
  fi
  HOSTS_FILE=$saved_hosts_file
  SSH_CONFIG=$hosts314_saved_ssh
  KEY=$hosts314_saved_key
  HOME=$hosts314_saved_home
  rm -rf "$hosts314_home"

  # #333: Window A list has office in memory; Window B upserts studio;
  # A presses r and the scan-save path writes its stale table. studio
  # and its SSH block must remain (same lock+reload+merge as #314).
  local hosts333_home hosts333_saved_home hosts333_saved_ssh hosts333_saved_key
  local hosts333_fn hosts333_got hosts333_id
  local _lj333_restore_tty _lj333_setup_tty _lj333_detect_lan
  local _lj333_scan_bonjour _lj333_scan_port22 _lj333_merge
  hosts333_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-333.XXXXXX") || return 1
  hosts333_saved_home=$HOME
  hosts333_saved_ssh=$SSH_CONFIG
  hosts333_saved_key=$KEY
  saved_hosts_file=$HOSTS_FILE
  mkdir -p "$hosts333_home/Library/Application Support/lanjump" "$hosts333_home/.ssh"
  HOSTS_FILE="$hosts333_home/Library/Application Support/lanjump/hosts"
  SSH_CONFIG="$hosts333_home/.ssh/config"
  KEY="$hosts333_home/.ssh/id_ed25519_lanjump"
  HOME=$hosts333_home
  : >"$HOSTS_FILE"
  : >"$SSH_CONFIG"
  MYIPS=(127.0.0.1)
  MYIP=""
  upsert_host office mac office.local 10.0.0.1 'aa:bb:cc:dd:ee:01'
  expect host/scan-save-stale/memory-office office "${h_alias[*]}"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$hosts333_home")"
    print -r -- "HOSTS_FILE=$(printf %q "$HOSTS_FILE")"
    print -r -- "SSH_CONFIG=$(printf %q "$SSH_CONFIG")"
    print -r -- "KEY=$(printf %q "$KEY")"
    print -r -- 'typeset -a h_alias h_user h_hostname h_ip h_mac h_port h_ssh_id h_last'
    for hosts333_fn in ssh_id_tag ssh_id_from_alias ssh_id_taken alloc_ssh_id \
      load_hosts replace_file_atomic save_hosts find_saved upsert_host \
      strip_ssh_block remove_ssh_config replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$hosts333_fn]} )) && functions "$hosts333_fn"
    done
    print -r -- "upsert_host studio mac studio.local 10.0.0.2 'aa:bb:cc:dd:ee:02'"
  } >"$hosts333_home/child.zsh"
  /bin/zsh "$hosts333_home/child.zsh"
  if ! grep -q '^studio|' "$HOSTS_FILE"; then
    print -u2 "FAIL host/scan-save-stale child upsert did not write studio"
    (( fails++ ))
  fi
  expect host/scan-save-stale/memory-still-office office "${h_alias[*]}"
  _lj333_restore_tty=$functions[restore_tty]
  _lj333_setup_tty=$functions[setup_tty]
  _lj333_detect_lan=$functions[detect_lan]
  _lj333_scan_bonjour=$functions[scan_bonjour]
  _lj333_scan_port22=$functions[scan_port22]
  _lj333_merge=$functions[merge_seen_by_hostkey]
  restore_tty() { :; }
  setup_tty() { :; }
  detect_lan() { PREFIX=10.0.0 MYIP=10.0.0.9 MASK=255.255.255.0; }
  scan_bonjour() { print -r -- $'office\toffice.local\t10.0.0.1\taa:bb:cc:dd:ee:01\t22'; }
  scan_port22() { :; }
  merge_seen_by_hostkey() { :; }
  cursor=1
  build_items
  do_scan >/dev/null
  functions[restore_tty]=$_lj333_restore_tty
  functions[setup_tty]=$_lj333_setup_tty
  functions[detect_lan]=$_lj333_detect_lan
  functions[scan_bonjour]=$_lj333_scan_bonjour
  functions[scan_port22]=$_lj333_scan_port22
  functions[merge_seen_by_hostkey]=$_lj333_merge
  load_hosts
  hosts333_got="${h_alias[*]}"
  if ! (( ${h_alias[(Ie)office]} && ${h_alias[(Ie)studio]} )); then
    print -u2 "FAIL host/scan-save-stale lost studio aliases=$(printf %q "$hosts333_got")"
    (( fails++ ))
  fi
  hosts333_id=
  for (( i = 1; i <= ${#h_alias}; i++ )); do
    if [[ ${h_alias[$i]} == studio ]]; then
      hosts333_id=${h_ssh_id[$i]:-}
      break
    fi
  done
  if [[ -z $hosts333_id ]]; then
    print -u2 "FAIL host/scan-save-stale studio ssh_id missing aliases=$(printf %q "$hosts333_got")"
    (( fails++ ))
  elif ! grep -qF "Host ${hosts333_id}" "$SSH_CONFIG"; then
    print -u2 "FAIL host/scan-save-stale orphaned SSH block id=$(printf %q "$hosts333_id")"
    (( fails++ ))
  fi
  HOSTS_FILE=$saved_hosts_file
  SSH_CONFIG=$hosts333_saved_ssh
  KEY=$hosts333_saved_key
  HOME=$hosts333_saved_home
  rm -rf "$hosts333_home"

  # #376: persist_scan_hosts returns 1 after a mid-loop SSH write
  # failure. do_scan must not report 扫描完成.
  local hosts376_home hosts376_saved_home hosts376_saved_ssh hosts376_saved_key
  local _lj376_restore_tty _lj376_setup_tty _lj376_detect_lan
  local _lj376_scan_bonjour _lj376_scan_port22 _lj376_merge _lj376_upsert
  hosts376_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-376.XXXXXX") || return 1
  hosts376_saved_home=$HOME
  hosts376_saved_ssh=$SSH_CONFIG
  hosts376_saved_key=$KEY
  saved_hosts_file=$HOSTS_FILE
  mkdir -p "$hosts376_home/Library/Application Support/lanjump" "$hosts376_home/.ssh"
  HOSTS_FILE="$hosts376_home/Library/Application Support/lanjump/hosts"
  SSH_CONFIG="$hosts376_home/.ssh/config"
  KEY="$hosts376_home/.ssh/id_ed25519_lanjump"
  HOME=$hosts376_home
  : >"$HOSTS_FILE"
  : >"$SSH_CONFIG"
  MYIPS=(127.0.0.1)
  MYIP=""
  upsert_host office mac office.local 10.0.0.1 'aa:bb:cc:dd:ee:01'
  _lj376_restore_tty=$functions[restore_tty]
  _lj376_setup_tty=$functions[setup_tty]
  _lj376_detect_lan=$functions[detect_lan]
  _lj376_scan_bonjour=$functions[scan_bonjour]
  _lj376_scan_port22=$functions[scan_port22]
  _lj376_merge=$functions[merge_seen_by_hostkey]
  _lj376_upsert=$functions[upsert_ssh_config]
  restore_tty() { :; }
  setup_tty() { :; }
  detect_lan() { PREFIX=10.0.0 MYIP=10.0.0.9 MASK=255.255.255.0; }
  scan_bonjour() { print -r -- $'office\toffice.local\t10.0.0.8\taa:bb:cc:dd:ee:01\t22'; }
  scan_port22() { :; }
  merge_seen_by_hostkey() { :; }
  upsert_ssh_config() { return 1 }
  cursor=1
  notice=""
  build_items
  do_scan >/dev/null
  functions[restore_tty]=$_lj376_restore_tty
  functions[setup_tty]=$_lj376_setup_tty
  functions[detect_lan]=$_lj376_detect_lan
  functions[scan_bonjour]=$_lj376_scan_bonjour
  functions[scan_port22]=$_lj376_scan_port22
  functions[merge_seen_by_hostkey]=$_lj376_merge
  functions[upsert_ssh_config]=$_lj376_upsert
  if [[ $notice == *扫描完成* ]]; then
    print -u2 "FAIL host/scan-persist-fail reported success notice=$(printf %q "$notice")"
    (( fails++ ))
  fi
  expect host/scan-persist-fail/notice '没法记下这次扫描。' "$notice"
  HOSTS_FILE=$saved_hosts_file
  SSH_CONFIG=$hosts376_saved_ssh
  KEY=$hosts376_saved_key
  HOME=$hosts376_saved_home
  rm -rf "$hosts376_home"

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

  # #354: Bonjour aliases may start with #; load must not treat the row as a comment.
  local hash_idx hosts354
  hosts354=$(mktemp) || return 1
  saved_hosts_file=$HOSTS_FILE
  HOSTS_FILE=$hosts354
  print -r -- '#2 Studio|mac|#2-studio.local|192.168.1.21|aa:bb:cc:dd:ee:02|456' >"$HOSTS_FILE"
  load_hosts
  expect host/hash-alias/count 1 "${#h_alias}"
  expect host/hash-alias/alias '#2 Studio' "${h_alias[1]}"
  expect host/hash-alias/user mac "${h_user[1]}"
  expect host/hash-alias/hostname '#2-studio.local' "${h_hostname[1]}"
  expect host/hash-alias/ip 192.168.1.21 "${h_ip[1]}"
  expect host/hash-alias/mac aa:bb:cc:dd:ee:02 "${h_mac[1]}"
  expect host/hash-alias/last 456 "${h_last[1]}"
  save_hosts
  load_hosts
  expect host/hash-alias/reload-count 1 "${#h_alias}"
  expect host/hash-alias/reload-alias '#2 Studio' "${h_alias[1]}"
  expect host/hash-alias/reload-user mac "${h_user[1]}"
  expect host/hash-alias/reload-hostname '#2-studio.local' "${h_hostname[1]}"
  hash_idx=
  for (( i = 1; i <= ${#h_alias}; i++ )); do
    if [[ ${h_alias[$i]} == '#2 Studio' ]]; then
      hash_idx=$i
      break
    fi
  done
  expect host/hash-alias/lookup 1 "$hash_idx"
  HOSTS_FILE=$saved_hosts_file
  rm -f "$hosts354"

  if (( fails )); then
    print -u2 "host-selftest: $fails failed"
    return 1
  fi
  print "ok host"
  return 0
}
