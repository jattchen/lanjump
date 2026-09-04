#!/bin/zsh
emulate -L zsh
setopt no_unset extendedglob typesetsilent
zmodload zsh/datetime

APP="$HOME/Library/Application Support/lanjump"
HOSTS_FILE="$APP/hosts"
LAST_FILE="$APP/last_target"
KEY="$HOME/.ssh/id_ed25519_lanjump"
PICKER="$APP/lanjump-pick.zsh"
SSH_CONFIG="$HOME/.ssh/config"
OLD_APP="$HOME/Library/Application Support/lan-ssh"
OLD_KEY="$HOME/.ssh/id_ed25519_lan"

typeset -a h_alias h_user h_hostname h_ip h_mac h_last
typeset -a items_kind items_alias items_user items_hostname items_ip items_mac items_status items_saved
typeset -a s_alias s_host s_ip s_mac
typeset -a MYIPS
cursor=1
loading=0
stty_orig=
PENDING_KEY=""
digit_wait=0.5
notice=""
MYIP=""
PREFIX=""
IFACE=""
LANJUMP_KEYS=""

if [[ -z ${NO_COLOR:-} ]]; then
  c_reset=$'\e[0m'
  c_bold=$'\e[1m'
  c_dim=$'\e[2m'
  c_green=$'\e[32m'
  c_cyan=$'\e[36m'
  c_red=$'\e[31m'
  c_rev=$'\e[7m'
else
  c_reset= c_bold= c_dim= c_green= c_cyan= c_red= c_rev=
fi

find_lanjump_keys() {
  local c
  LANJUMP_KEYS=""
  for c in "$HOME/.local/bin/lanjump-keys" "$APP/lanjump-keys"; do
    if [[ -x $c ]]; then
      LANJUMP_KEYS=$c
      return 0
    fi
  done
  return 1
}

restore_tty() {
  print -n -u2 $'\e[?25h'
  [[ -n ${stty_orig:-} ]] && stty "$stty_orig" 2>/dev/null || stty sane 2>/dev/null
}

setup_tty() {
  stty_orig=$(stty -g)
  stty -echo -icanon min 1 time 0
  print -n -u2 $'\e[?25l'
}

on_exit() {
  restore_tty
}
trap on_exit EXIT
trap 'restore_tty; exit 130' INT
trap '[[ $loading -eq 1 ]] || draw' WINCH

term_cols() {
  local c=${COLUMNS:-0}
  if (( c < 20 )); then
    c=$(stty size 2>/dev/null | awk '{print $2}')
  fi
  (( c < 40 )) && c=40
  print -r -- $c
}

dw() {
  local s=$1 c
  local -i w=0 i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      (( w++ ))
    else
      (( w += 2 ))
    fi
  done
  print -r -- $w
}

fit_right() {
  local s=$1
  local -i max=$2 w=0 i cw
  local c out=
  if (( max <= 0 )); then
    return
  fi
  if (( $(dw "$s") <= max )); then
    print -r -- "$s"
    return
  fi
  if (( max <= 1 )); then
    print -r -- '…'
    return
  fi
  for (( i = 1; i <= ${#s}; i++ )); do
    c=$s[i]
    cw=$(dw "$c")
    if (( w + cw > max - 1 )); then
      break
    fi
    out+="$c"
    (( w += cw ))
  done
  print -r -- "${out}…"
}

padw() {
  local s=$1
  local -i width=$2 d
  d=$(dw "$s")
  if (( width <= 0 )); then
    return
  fi
  if (( d > width )); then
    fit_right "$s" $width
    return
  fi
  printf '%s%*s' "$s" $(( width - d )) ''
}

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  print -r -- "$s"
}

mark_last() {
  print -r -- "$1" >"$LAST_FILE"
}

read_last() {
  local last=""
  [[ -f $LAST_FILE ]] || return
  last=$(<"$LAST_FILE")
  last=${last%%$'\n'*}
  last=$(trim "$last")
  [[ -n $last ]] && print -r -- "$last"
}

apply_last_cursor() {
  local last j n=${#items_kind}
  last=$(read_last)
  if [[ $last == local ]]; then
    for (( j = 1; j <= n; j++ )); do
      if [[ ${items_kind[$j]} == local ]]; then
        cursor=$j
        return
      fi
    done
  fi
  cursor=1
}

picker_path() {
  if [[ -f $PICKER ]]; then
    print -r -- "$PICKER"
    return
  fi
  local sibling="${0:A:h}/lanjump-pick.zsh"
  if [[ -f $sibling ]]; then
    print -r -- "$sibling"
  fi
}

migrate_legacy() {
  mkdir -p "$APP"
  if [[ -d $OLD_APP ]]; then
    if [[ ! -s $HOSTS_FILE && -f $OLD_APP/hosts ]]; then
      cp -p "$OLD_APP/hosts" "$HOSTS_FILE"
    fi
    if [[ ! -f $LAST_FILE && -f $OLD_APP/last_target ]]; then
      cp -p "$OLD_APP/last_target" "$LAST_FILE"
    fi
  fi
  if [[ ! -f $KEY && -f $OLD_KEY ]]; then
    mv "$OLD_KEY" "$KEY"
    [[ -f $OLD_KEY.pub ]] && mv "$OLD_KEY.pub" "$KEY.pub"
    chmod 600 "$KEY"
    [[ -f $KEY.pub ]] && chmod 644 "$KEY.pub"
    ssh-keygen -c -C "lanjump@$(hostname -s)" -f "$KEY" >/dev/null 2>&1 || true
  fi
  [[ -f $SSH_CONFIG ]] || return
  grep -qE '# BEGIN LAN-SSH |# END LAN-SSH |id_ed25519_lan$' "$SSH_CONFIG" 2>/dev/null || return
  local tmp
  tmp=$(mktemp)
  awk '
    {
      gsub(/# BEGIN LAN-SSH /, "# BEGIN LANJUMP ")
      gsub(/# END LAN-SSH /, "# END LANJUMP ")
    }
    /^# BEGIN LANJUMP / {
      sub(/ LANJUMP lan-/, " LANJUMP lanjump-")
      inblock=1
    }
    /^# END LANJUMP / {
      sub(/ LANJUMP lan-/, " LANJUMP lanjump-")
      inblock=0
    }
    inblock && /^Host lan-/ { sub(/^Host lan-/, "Host lanjump-") }
    /IdentityFile / && /id_ed25519_lan$/ { sub(/id_ed25519_lan$/, "id_ed25519_lanjump") }
    { print }
  ' "$SSH_CONFIG" >"$tmp"
  mv "$tmp" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
}

ensure_setup() {
  mkdir -p "$APP" "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  migrate_legacy
  [[ -f $HOSTS_FILE ]] || : >"$HOSTS_FILE"
  if [[ ! -f $KEY ]]; then
    ssh-keygen -t ed25519 -f "$KEY" -N "" -C "lanjump@$(hostname -s)"
    chmod 600 "$KEY"
    chmod 644 "$KEY.pub"
  fi
  ssh-add --apple-use-keychain "$KEY" >/dev/null 2>&1 || true
  find_lanjump_keys || true
}

iface_ipv4() {
  local iface=$1 ip
  ip=$(ipconfig getifaddr "$iface" 2>/dev/null) || true
  if [[ -z $ip ]]; then
    ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet / { print $2; exit }') || true
  fi
  print -r -- "$ip"
}

is_rfc1918() {
  local ip=$1 a b
  [[ $ip == [0-9]##.[0-9]##.[0-9]##.[0-9]## ]] || return 1
  a=${ip%%.*}
  b=${ip#*.}
  b=${b%%.*}
  [[ $a == 10 ]] && return 0
  [[ $a == 192 && $b == 168 ]] && return 0
  [[ $a == 172 && $b -ge 16 && $b -le 31 ]] && return 0
  return 1
}

is_ignored_iface() {
  local i=$1
  [[ $i == utun* || $i == lo* || $i == awdl* || $i == llw* || $i == bridge* || $i == ap* || $i == gif* || $i == stf* || $i == anpi* || $i == vmnet* || $i == vmenet* ]]
}

collect_self_ips() {
  MYIPS=(127.0.0.1)
  local i ip
  for i in $(ifconfig -l); do
    ip=$(iface_ipv4 "$i")
    [[ -n $ip ]] && MYIPS+=("$ip")
  done
}

detect_lan() {
  IFACE=""
  MYIP=""
  PREFIX=""
  collect_self_ips
  local def cand ip already s
  local -a cands seen
  cands=()
  seen=()
  def=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  [[ -n $def ]] && cands+=("$def")
  for cand in $(ifconfig -l); do
    [[ $cand == en[0-9]## ]] && cands+=("$cand")
  done
  for cand in "${cands[@]}"; do
    [[ -n $cand ]] || continue
    already=0
    for s in "${seen[@]}"; do
      [[ $s == "$cand" ]] && already=1 && break
    done
    (( already )) && continue
    seen+=("$cand")
    is_ignored_iface "$cand" && continue
    ip=$(iface_ipv4 "$cand")
    is_rfc1918 "$ip" || continue
    IFACE=$cand
    MYIP=$ip
    PREFIX=${ip%.*}
    return
  done
}

is_self_ip() {
  local ip=$1 x
  [[ -z $ip ]] && return 1
  for x in "${MYIPS[@]}"; do
    [[ $ip == "$x" ]] && return 0
  done
  [[ $ip == 127.0.0.1 ]] && return 0
  [[ -n $MYIP && $ip == "$MYIP" ]] && return 0
  return 1
}

norm_mac() {
  print -r -- "${1:l}"
}

get_mac() {
  local ip=$1 line mac
  line=$(arp -n "$ip" 2>/dev/null) || return
  [[ $line == *incomplete* ]] && return
  mac=$(print -r -- "$line" | awk '{for (i = 1; i <= NF; i++) if ($i == "at") { print $(i + 1); exit }}')
  [[ -n $mac && $mac != *ff:ff:ff:ff:ff:ff* ]] || return
  norm_mac "$mac"
}

ssh_id_from_alias() {
  local s=${1:l}
  s=${s// /-}
  s=${s//[^a-z0-9._-]/-}
  s=${s##-}
  s=${s%%-}
  [[ -n $s ]] || s="host"
  print -r -- "lanjump-${s}"
}

load_hosts() {
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_last=()
  [[ -f $HOSTS_FILE ]] || return
  local line
  local -a f
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    f=("${(@s:|:)line}")
    (( ${#f} >= 6 )) || continue
    h_alias+=("${f[1]}")
    h_user+=("${f[2]}")
    h_hostname+=("${f[3]}")
    h_ip+=("${f[4]}")
    h_mac+=("${f[5]}")
    h_last+=("${f[6]}")
  done <"$HOSTS_FILE"
}

save_hosts() {
  local i n=${#h_alias}
  {
    print -r -- "# alias|user|hostname|ip|mac|last"
    for (( i = 1; i <= n; i++ )); do
      print -r -- "${h_alias[$i]}|${h_user[$i]}|${h_hostname[$i]}|${h_ip[$i]}|${h_mac[$i]}|${h_last[$i]}"
    done
  } >"$HOSTS_FILE"
}

find_saved() {
  local mac=$1 hostname=$2 ip=$3
  local i n=${#h_alias}
  if [[ -n $mac ]]; then
    for (( i = 1; i <= n; i++ )); do
      if [[ -n ${h_mac[$i]} && ${h_mac[$i]} == "$mac" ]]; then
        print -r -- $i
        return
      fi
    done
  fi
  if [[ -n $hostname ]]; then
    for (( i = 1; i <= n; i++ )); do
      if [[ -n ${h_hostname[$i]} && ${h_hostname[$i]} == "$hostname" ]]; then
        print -r -- $i
        return
      fi
    done
  fi
  if [[ -n $ip ]]; then
    for (( i = 1; i <= n; i++ )); do
      if [[ ${h_ip[$i]} == "$ip" ]]; then
        print -r -- $i
        return
      fi
    done
  fi
}

upsert_host() {
  local alias=$1 user=$2 hostname=$3 ip=$4 mac=$5
  local idx
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    h_alias[$idx]=$alias
    h_user[$idx]=$user
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
    h_last[$idx]=$EPOCHSECONDS
  else
    h_alias+=("$alias")
    h_user+=("$user")
    h_hostname+=("$hostname")
    h_ip+=("$ip")
    h_mac+=("$mac")
    h_last+=("$EPOCHSECONDS")
  fi
  save_hosts
  upsert_ssh_config "$(ssh_id_from_alias "$alias")" "$user" "${hostname:-$ip}"
}

forget_saved() {
  local idx=$1
  local n=${#h_alias}
  (( idx >= 1 && idx <= n )) || return
  local id
  id=$(ssh_id_from_alias "${h_alias[$idx]}")
  remove_ssh_config "$id"
  local -a na nu nh ni nm nl
  local i
  na=() nu=() nh=() ni=() nm=() nl=()
  for (( i = 1; i <= n; i++ )); do
    (( i == idx )) && continue
    na+=("${h_alias[$i]}")
    nu+=("${h_user[$i]}")
    nh+=("${h_hostname[$i]}")
    ni+=("${h_ip[$i]}")
    nm+=("${h_mac[$i]}")
    nl+=("${h_last[$i]}")
  done
  h_alias=("${na[@]}")
  h_user=("${nu[@]}")
  h_hostname=("${nh[@]}")
  h_ip=("${ni[@]}")
  h_mac=("${nm[@]}")
  h_last=("${nl[@]}")
  save_hosts
}

strip_ssh_block() {
  local begin=$1 end=$2
  [[ -f $SSH_CONFIG ]] || return
  grep -qF "$begin" "$SSH_CONFIG" 2>/dev/null || return
  local tmp
  tmp=$(mktemp)
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$SSH_CONFIG" >"$tmp"
  mv "$tmp" "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
}

remove_ssh_config() {
  local id=$1
  local old_id=${id/#lanjump-/lan-}
  strip_ssh_block "# BEGIN LANJUMP ${id}" "# END LANJUMP ${id}"
  strip_ssh_block "# BEGIN LAN-SSH ${id}" "# END LAN-SSH ${id}"
  if [[ $old_id != "$id" ]]; then
    strip_ssh_block "# BEGIN LAN-SSH ${old_id}" "# END LAN-SSH ${old_id}"
    strip_ssh_block "# BEGIN LANJUMP ${old_id}" "# END LANJUMP ${old_id}"
  fi
}

upsert_ssh_config() {
  local id=$1 user=$2 hostname=$3
  mkdir -p "$HOME/.ssh"
  [[ -f $SSH_CONFIG ]] || : >"$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  remove_ssh_config "$id"
  {
    print
    print "# BEGIN LANJUMP ${id}"
    print "Host ${id}"
    print "  HostName ${hostname}"
    print "  User ${user}"
    print "  IdentityFile ${KEY}"
    print "  IdentitiesOnly yes"
    print "  AddKeysToAgent yes"
    print "  UseKeychain yes"
    print "  AddressFamily inet"
    print "  StrictHostKeyChecking accept-new"
    print "  ConnectTimeout 8"
    print "# END LANJUMP ${id}"
  } >>"$SSH_CONFIG"
}

run_timed() {
  local -i secs=$1
  local out=$2
  shift 2
  "$@" >"$out" 2>&1 &
  local pid=$!
  local -i i
  for (( i = 0; i < secs * 10; i++ )); do
    if ! kill -0 $pid 2>/dev/null; then
      wait $pid 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
}

scan_bonjour() {
  local tmp inst_file inst resolve_tmp line host port ip
  tmp=$(mktemp)
  inst_file=$(mktemp)
  run_timed 2 "$tmp" dns-sd -B _ssh._tcp local.
  awk '
    /Add/ && /_ssh\._tcp\./ {
      sub(/.*_ssh\._tcp\.[[:space:]]+/, "")
      gsub(/[[:space:]]+$/, "")
      if ($0 != "") print
    }
  ' "$tmp" | sort -u >"$inst_file"
  while IFS= read -r inst; do
    [[ -n $inst ]] || continue
    resolve_tmp=$(mktemp)
    run_timed 1 "$resolve_tmp" dns-sd -L "$inst" _ssh._tcp local.
    host=""
    port="22"
    line=$(grep -F "can be reached at" "$resolve_tmp" | tail -1)
    if [[ -n $line ]]; then
      host=${line##*can be reached at }
      host=${host%% *}
      port=${host##*:}
      host=${host%:*}
      host=${host%.}
      port=${port%%[^0-9]*}
    fi
    rm -f "$resolve_tmp"
    [[ -n $host ]] || continue
    ip=""
    resolve_tmp=$(mktemp)
    run_timed 1 "$resolve_tmp" dns-sd -G v4 "$host"
    ip=$(awk '/Add/ && /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i
    }' "$resolve_tmp" | tail -1)
    rm -f "$resolve_tmp"
    is_self_ip "$ip" && continue
    print -r -- "${inst}"$'\t'"${host}"$'\t'"${ip}"$'\t'"$(get_mac "$ip")"
  done <"$inst_file"
  rm -f "$tmp" "$inst_file"
}

scan_port22() {
  local prefix=$1
  [[ -n $prefix ]] || return
  local i ip
  for i in {1..254}; do
    ip="${prefix}.${i}"
    is_self_ip "$ip" && continue
    (
      if nc -z -G 1 "$ip" 22 >/dev/null 2>&1; then
        print -r -- "$ip"
      fi
    ) &
    if (( i % 40 == 0 )); then
      wait
    fi
  done
  wait
}

build_items() {
  items_kind=() items_alias=() items_user=() items_hostname=() items_ip=() items_mac=() items_status=() items_saved=()
  local i n=${#h_alias} idx last
  last=$(read_last)
  if (( n )); then
    local -a idx_order
    idx_order=()
    for (( i = 1; i <= n; i++ )); do
      idx_order+=("${h_last[$i]}/${i}")
    done
    idx_order=("${(@nO)idx_order}")
    local first=${idx_order[1]##*/}
    for i in "${idx_order[@]}"; do
      idx=${i##*/}
      items_kind+=("host")
      items_alias+=("${h_alias[$idx]}")
      items_user+=("${h_user[$idx]}")
      items_hostname+=("${h_hostname[$idx]}")
      items_ip+=("${h_ip[$idx]}")
      items_mac+=("${h_mac[$idx]}")
      if [[ $idx == "$first" && $last != local ]]; then
        items_status+=("已保存 · 上次")
      else
        items_status+=("已保存")
      fi
      items_saved+=("$idx")
    done
  fi
  items_kind+=("local")
  items_alias+=("进入本机")
  items_user+=("")
  items_hostname+=("")
  items_ip+=("")
  items_mac+=("")
  items_status+=("")
  items_saved+=("")

  items_kind+=("scan")
  items_alias+=("扫描局域网…")
  items_user+=("")
  items_hostname+=("")
  items_ip+=("")
  items_mac+=("")
  items_status+=("")
  items_saved+=("")

  items_kind+=("quit")
  items_alias+=("退出")
  items_user+=("")
  items_hostname+=("")
  items_ip+=("")
  items_mac+=("")
  items_status+=("")
  items_saved+=("")

  if (( cursor < 1 )); then
    cursor=1
  fi
  if (( cursor > ${#items_kind} )); then
    cursor=${#items_kind}
  fi
}

add_discovered() {
  local alias=$1 hostname=$2 ip=$3 mac=$4
  local idx
  is_self_ip "$ip" && return
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
    return
  fi
  local i n=${#items_kind}
  for (( i = 1; i <= n; i++ )); do
    if [[ ${items_kind[$i]} == host ]]; then
      if [[ -n $ip && ${items_ip[$i]} == "$ip" ]]; then
        return
      fi
      if [[ -n $mac && -n ${items_mac[$i]} && ${items_mac[$i]} == "$mac" ]]; then
        return
      fi
    fi
  done
  # insert before the first action row (本机 / 扫描 / 退出)
  local insert_at=0
  for (( i = 1; i <= n; i++ )); do
    if [[ ${items_kind[$i]} != host ]]; then
      insert_at=$i
      break
    fi
  done
  (( insert_at > 0 )) || return
  items_kind=("${(@)items_kind[1,insert_at-1]}" host "${(@)items_kind[insert_at,-1]}")
  items_alias=("${(@)items_alias[1,insert_at-1]}" "$alias" "${(@)items_alias[insert_at,-1]}")
  items_user=("${(@)items_user[1,insert_at-1]}" "" "${(@)items_user[insert_at,-1]}")
  items_hostname=("${(@)items_hostname[1,insert_at-1]}" "$hostname" "${(@)items_hostname[insert_at,-1]}")
  items_ip=("${(@)items_ip[1,insert_at-1]}" "$ip" "${(@)items_ip[insert_at,-1]}")
  items_mac=("${(@)items_mac[1,insert_at-1]}" "$mac" "${(@)items_mac[insert_at,-1]}")
  items_status=("${(@)items_status[1,insert_at-1]}" "新发现" "${(@)items_status[insert_at,-1]}")
  items_saved=("${(@)items_saved[1,insert_at-1]}" "" "${(@)items_saved[insert_at,-1]}")
}

mark_online() {
  local ip=$1 mac=$2 hostname=$3
  local i n=${#items_kind}
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host ]] || continue
    if [[ -n $ip && ${items_ip[$i]} == "$ip" ]] || \
       [[ -n $mac && -n ${items_mac[$i]} && ${items_mac[$i]} == "$mac" ]] || \
       [[ -n $hostname && -n ${items_hostname[$i]} && ${items_hostname[$i]} == "$hostname" ]]; then
      if [[ ${items_status[$i]} == 已保存* ]]; then
        if [[ ${items_status[$i]} == *上次* ]]; then
          items_status[$i]="在线 · 上次"
        else
          items_status[$i]="在线"
        fi
      fi
      [[ -n $hostname ]] && items_hostname[$i]=$hostname
      [[ -n $ip ]] && items_ip[$i]=$ip
      [[ -n $mac ]] && items_mac[$i]=$mac
    fi
  done
}

record_seen() {
  local alias=$1 hostname=$2 ip=$3 mac=$4
  local idx
  is_self_ip "$ip" && return
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
  fi
  local i n=${#s_ip}
  for (( i = 1; i <= n; i++ )); do
    if [[ -n $ip && ${s_ip[$i]} == "$ip" ]]; then
      [[ -n $hostname && -z ${s_host[$i]} ]] && s_host[$i]=$hostname
      [[ -n $mac && -z ${s_mac[$i]} ]] && s_mac[$i]=$mac
      [[ -n $alias && ${s_alias[$i]} == "$ip" ]] && s_alias[$i]=$alias
      return
    fi
  done
  s_alias+=("$alias")
  s_host+=("$hostname")
  s_ip+=("$ip")
  s_mac+=("$mac")
}

ssh_fp() {
  ssh-keyscan -4 -t ed25519 -T 3 "$1" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}'
}

is_numeric_alias() {
  [[ $1 == [0-9]##[.][0-9]##[.][0-9]##[.][0-9]## ]]
}

merge_seen_by_hostkey() {
  local i j n=${#s_ip}
  local -a fp
  local known="$HOME/.ssh/known_hosts"
  (( n )) || return
  fp=()
  for (( i = 1; i <= n; i++ )); do
    fp[i]=$(ssh_fp "${s_ip[$i]}")
  done
  for (( i = 1; i <= n; i++ )); do
    [[ -n ${s_ip[$i]} && -n ${fp[$i]} ]] || continue
    for (( j = i + 1; j <= n; j++ )); do
      [[ -n ${s_ip[$j]} && -n ${fp[$j]} ]] || continue
      [[ ${fp[$i]} == "${fp[$j]}" ]] || continue
      if is_numeric_alias "${s_alias[$i]}" && ! is_numeric_alias "${s_alias[$j]}"; then
        s_alias[$i]=${s_alias[$j]}
      fi
      if [[ -z ${s_host[$i]} && -n ${s_host[$j]} ]]; then
        s_host[$i]=${s_host[$j]}
      fi
      if [[ -f $known ]] && grep -qF "${s_ip[$j]} " "$known" && ! grep -qF "${s_ip[$i]} " "$known"; then
        s_ip[$i]=${s_ip[$j]}
        s_mac[$i]=${s_mac[$j]}
        [[ -n ${s_host[$j]} ]] && s_host[$i]=${s_host[$j]}
        if ! is_numeric_alias "${s_alias[$j]}"; then
          s_alias[$i]=${s_alias[$j]}
        fi
      fi
      s_ip[$j]=""
    done
  done
  local -a na nh ni nm
  na=() nh=() ni=() nm=()
  for (( i = 1; i <= n; i++ )); do
    [[ -n ${s_ip[$i]} ]] || continue
    na+=("${s_alias[$i]}")
    nh+=("${s_host[$i]}")
    ni+=("${s_ip[$i]}")
    nm+=("${s_mac[$i]}")
  done
  s_alias=("${na[@]}")
  s_host=("${nh[@]}")
  s_ip=("${ni[@]}")
  s_mac=("${nm[@]}")
}

do_scan() {
  loading=1
  restore_tty
  print
  detect_lan
  if [[ -z $PREFIX ]]; then
    notice="没找到家里的网（默认路由可能是 VPN）。仍可进入本机。"
    loading=0
    setup_tty
    return
  fi
  print "正在扫描 Bonjour SSH 和 ${PREFIX}.0/24 的 22 端口…"
  s_alias=() s_host=() s_ip=() s_mac=()
  local alias hostname ip mac
  while IFS=$'\t' read -r alias hostname ip mac; do
    [[ -n $alias || -n $ip ]] || continue
    [[ -z $alias ]] && alias=${hostname:-$ip}
    record_seen "$alias" "$hostname" "$ip" "$mac"
  done < <(scan_bonjour)
  while IFS= read -r ip; do
    [[ -n $ip ]] || continue
    mac=$(get_mac "$ip")
    record_seen "$ip" "" "$ip" "$mac"
  done < <(scan_port22 "$PREFIX")
  merge_seen_by_hostkey
  save_hosts
  load_hosts
  build_items
  local i n=${#s_alias}
  local -i extra=0
  for (( i = 1; i <= n; i++ )); do
    add_discovered "${s_alias[$i]}" "${s_host[$i]}" "${s_ip[$i]}" "${s_mac[$i]}"
    mark_online "${s_ip[$i]}" "${s_mac[$i]}" "${s_host[$i]}"
  done
  n=${#items_kind}
  extra=0
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host && ${items_status[$i]} == 新发现 ]] && (( extra++ ))
  done
  notice="扫描完成。新发现 ${extra} 台开了 SSH 的设备。"
  loading=0
  setup_tty
}

draw() {
  local -i cols i n w_name=4 w_addr=8 w_user=4 w_stat=4
  local mark line sep addr
  cols=$(term_cols)
  n=${#items_kind}
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host ]] || continue
    (( $(dw "${items_alias[$i]}") > w_name )) && w_name=$(dw "${items_alias[$i]}")
    addr=${items_ip[$i]:-${items_hostname[$i]}}
    (( $(dw "$addr") > w_addr )) && w_addr=$(dw "$addr")
    (( $(dw "${items_user[$i]}") > w_user )) && w_user=$(dw "${items_user[$i]}")
    (( $(dw "${items_status[$i]}") > w_stat )) && w_stat=$(dw "${items_status[$i]}")
  done
  (( w_name < 4 )) && w_name=4
  (( w_user < 4 )) && w_user=4
  local -i avail needed extra
  avail=$(( cols - 10 ))
  needed=$(( w_name + w_addr + w_user + w_stat + 6 ))
  if (( needed > avail )); then
    extra=$(( needed - avail ))
    if (( w_addr - extra >= 12 )); then
      (( w_addr -= extra ))
    else
      extra=$(( extra - (w_addr - 12) ))
      w_addr=12
      (( w_name - extra >= 8 )) && (( w_name -= extra )) || w_name=8
    fi
  fi

  print -n $'\e[H\e[J'
  print "${c_bold}  局域网 SSH${c_reset}"
  print "${c_dim}  ↑↓/jk 选择   Enter 进入   r 扫描   d 忘掉   q 退出${c_reset}"
  if [[ -n $notice ]]; then
    print "  ${c_cyan}${notice}${c_reset}"
  else
    print
  fi

  print "  ${c_dim}    #  $(padw 名称 $w_name)  $(padw 地址 $w_addr)  $(padw 用户 $w_user)  $(padw 状态 $w_stat)${c_reset}"
  sep=$(printf '%*s' $(( cols - 4 )) '')
  sep=${sep// /─}
  print "  ${c_dim}${sep}${c_reset}"

  local host_end=0
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host ]] && host_end=$i
  done

  for (( i = 1; i <= n; i++ )); do
    if (( i == host_end + 1 && host_end > 0 )); then
      print
    fi
    if [[ ${items_kind[$i]} == host ]]; then
      addr=${items_ip[$i]:-${items_hostname[$i]}}
      line="$(padw "${items_alias[$i]}" $w_name)  $(padw "$addr" $w_addr)  $(padw "${items_user[$i]:--}" $w_user)  $(padw "${items_status[$i]}" $w_stat)"
    else
      line=${items_alias[$i]}
    fi
    if (( i == cursor )); then
      mark="${c_cyan}>${c_reset}"
      line="${c_rev} ${line} ${c_reset}"
    else
      mark=" "
      line=" ${line}"
    fi
    printf '  %s %2d  %s\n' "$mark" "$i" "$line"
  done
}

# True if another digit could still name a list index.
index_prefix_ambiguous() {
  local acc=$1
  local -i max=$2 val
  case $acc in
    ''|0*|*[!0-9]*) return 1 ;;
  esac
  val=$((10#$acc))
  (( val * 10 <= max ))
}

# Read one byte from stdin into REPLY. timeout is seconds.
# Returns 1 on timeout or EOF. Tty uses read -k; pipes use zselect.
read_byte_timeout() {
  local timeout=$1
  local buf=""
  local -i hundredths
  if [[ -t 0 ]]; then
    IFS= read -rsk1 -t $timeout buf || return 1
    REPLY=$buf
    return 0
  fi
  zmodload zsh/system 2>/dev/null || return 1
  zmodload zsh/zselect 2>/dev/null || return 1
  hundredths=$(( timeout * 100 ))
  (( hundredths < 1 )) && hundredths=1
  if ! zselect -t $hundredths -r 0; then
    return 1
  fi
  sysread -s 1 buf || return 1
  REPLY=$buf
  return 0
}

# Read extra digits while the value is still a prefix of a larger index.
# Timeout / Enter keep the current value. Esc or any other key cancel
# (other key is replayed via PENDING_KEY).
collect_index_digits() {
  local acc=$1
  local -i max=$2
  local k
  PENDING_KEY=""
  while index_prefix_ambiguous "$acc" $max; do
    read_byte_timeout $digit_wait || break
    k=$REPLY
    case $k in
      [0-9]) acc="${acc}${k}" ;;
      $'\n'|$'\r'|' ') break ;;
      $'\e') REPLY=""; return 0 ;;
      *) PENDING_KEY=$k; REPLY=""; return 0 ;;
    esac
  done
  REPLY=$acc
}

read_key() {
  local k k2 k3
  if [[ -n $PENDING_KEY ]]; then
    k=$PENDING_KEY
    PENDING_KEY=""
  else
    IFS= read -rsk1 k || return 1
  fi
  if [[ $k == $'\e' ]]; then
    IFS= read -rsk1 -t 0.2 k2 || { REPLY=esc; return 0 }
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      IFS= read -rsk1 -t 0.2 k3 || { REPLY=esc; return 0 }
      case $k3 in
        A) REPLY=up ;;
        B) REPLY=down ;;
        C) REPLY=right ;;
        D) REPLY=left ;;
        *) REPLY=esc ;;
      esac
      return 0
    fi
    REPLY=esc
    return 0
  fi
  case $k in
    $'\n'|$'\r'|' ') REPLY=enter ;;
    k|K) REPLY=up ;;
    j|J) REPLY=down ;;
    q|Q) REPLY=q ;;
    r|R) REPLY=r ;;
    d|D) REPLY=d ;;
    g) REPLY=top ;;
    G) REPLY=bottom ;;
    [0-9]) REPLY="num$k" ;;
    *) REPLY=other ;;
  esac
}

prompt_username() {
  local user=""
  restore_tty
  print -u2
  while true; do
    print -u2 -n "这台机器的 SSH 用户名（必填）: "
    read -r user </dev/tty
    user=$(trim "$user")
    user=${user//$'\r'/}
    if [[ -n $user ]]; then
      REPLY=$user
      return 0
    fi
    print -u2 "用户名不能为空。"
  done
}

target_for() {
  local hostname=$1 ip=$2
  if [[ -n $ip ]]; then
    print -r -- "$ip"
    return
  fi
  print -r -- "$hostname"
}

typeset -a SSH_OPTS
SSH_OPTS=(-o AddressFamily=inet -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8)

# Interactive SSH only. Batch/key-install calls stay plain ssh.
# grok wrap intercepts OSC 52 on this Mac (needed by Apple Terminal) and
# writes them to pbcopy. Ghostty/iTerm2 already handle OSC 52; wrap is a no-op there.
# Set LANJUMP_NO_GROK_WRAP=1 to force plain ssh.
grok_wrap_bin() {
  [[ -n ${LANJUMP_NO_GROK_WRAP:-} ]] && return 1
  local -a cands=()
  local c seen=""
  (( $+commands[grok] )) && cands+=("${commands[grok]}")
  cands+=("$HOME/.grok/bin/grok" "$HOME/.local/bin/grok" /opt/homebrew/bin/grok /usr/local/bin/grok)
  for c in $cands; do
    [[ -n $c && -x $c ]] || continue
    [[ $seen == *"|$c|"* ]] && continue
    seen+="|$c|"
    if "$c" wrap --help >/dev/null 2>&1; then
      print -r -- "$c"
      return 0
    fi
  done
  return 1
}

ssh_tty() {
  local grok=""
  grok=$(grok_wrap_bin) || grok=""
  # Apple Terminal is 256-color. A non-256 TERM through wrap/ssh/tmux makes
  # Grok skip its background, so the TUI sits on a white terminal.
  if [[ ${TERM:-} != *256color* && ${TERM:-} != *direct* && ${TERM:-} != *-kitty ]]; then
    export TERM=xterm-256color
  fi
  if [[ ${TERM_PROGRAM:-} == Apple_Terminal ]]; then
    unset COLORTERM
  fi
  # grok wrap must own the real tty. Put lanjump-keys *inside* wrap so
  # Shift+Enter rewrite does not steal /dev/tty (that nesting hung).
  if [[ -n $grok ]]; then
    print -u2 "剪贴板转发已开（grok wrap）。"
    if [[ -n ${LANJUMP_KEYS:-} ]]; then
      "$grok" wrap "$LANJUMP_KEYS" ssh "$@"
    else
      "$grok" wrap ssh "$@"
    fi
  elif [[ -n ${LANJUMP_KEYS:-} ]]; then
    "$LANJUMP_KEYS" ssh "$@"
  else
    command ssh "$@"
  fi
}

lan_pub_install_cmd() {
  local pub
  pub=$(cat "$KEY.pub")
  print -r -- "umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; grep -Fqx '$pub' ~/.ssh/authorized_keys 2>/dev/null || printf '%s\n' '$pub' >> ~/.ssh/authorized_keys"
}

try_ssh() {
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$@" /usr/bin/true >/dev/null 2>&1
}

install_lan_pub() {
  local user=$1 target=$2
  shift 2
  ssh "${SSH_OPTS[@]}" "$@" "${user}@${target}" "$(lan_pub_install_cmd)"
}

setup_access() {
  local user=$1 target=$2
  local id
  local -a ids
  if try_ssh -o IdentitiesOnly=yes -i "$KEY" "${user}@${target}"; then
    return 0
  fi
  ids=($HOME/.ssh/id_*(N.))
  for id in "${ids[@]}"; do
    [[ $id == *.pub ]] && continue
    [[ $id == "$KEY" ]] && continue
    if try_ssh -o IdentitiesOnly=yes -i "$id" "${user}@${target}"; then
      print "发现已有密钥，正在安装局域网公钥…"
      install_lan_pub "$user" "$target" -o IdentitiesOnly=yes -i "$id"
      return $?
    fi
  done
  print
  print "请输入 ${user}@${target} 的登录密码（只此一次，用来安装公钥，密码不会保存）。"
  ssh -tt "${SSH_OPTS[@]}" \
    -o PreferredAuthentications=keyboard-interactive,password \
    -o PubkeyAuthentication=no \
    -o PasswordAuthentication=yes \
    -o KbdInteractiveAuthentication=yes \
    -o NumberOfPasswordPrompts=3 \
    "${user}@${target}" "$(lan_pub_install_cmd)"
}

sync_picker() {
  local target=$1 user=$2
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" \
    'mkdir -p "$HOME/.local/bin" && cat > "$HOME/.local/bin/lanjump-pick" && chmod 755 "$HOME/.local/bin/lanjump-pick"' \
    <"$PICKER"
}

connect_item() {
  local i=$1
  local alias=${items_alias[$i]}
  local user=${items_user[$i]}
  local hostname=${items_hostname[$i]}
  local ip=${items_ip[$i]}
  local mac=${items_mac[$i]}
  local target

  restore_tty
  if [[ -z $user ]]; then
    prompt_username
    user=$REPLY
  fi
  if [[ -z $ip && -z $hostname ]]; then
    notice="没有可用地址。"
    setup_tty
    return
  fi
  target=$(target_for "$hostname" "$ip")
  print
  print "正在连接 ${user}@${target} …"
  if ! setup_access "$user" "$target"; then
    print
    print "公钥安装失败。请确认用户名、密码，以及对方已打开远程登录。"
    print -n "按回车回到列表…"
    read -r
    setup_tty
    return
  fi
  if ! ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" true; then
    print "密钥登录仍失败。"
    print -n "按回车回到列表…"
    read -r
    setup_tty
    return
  fi
  [[ -z $mac ]] && mac=$(get_mac "$ip")
  upsert_host "$alias" "$user" "$hostname" "$ip" "$mac"
  mark_last host
  if ! sync_picker "$target" "$user"; then
    print "无法把 tmux 选择界面同步到对方。"
    print -n "按回车回到列表…"
    read -r
    setup_tty
    return
  fi
  local remote_cmd
  remote_cmd="export PATH=\"\$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:\$PATH\""
  remote_cmd+="; unset GROK_APPEARANCE LC_GROK_APPEARANCE COLORTERM"
  remote_cmd+="; export TERM_PROGRAM=$(printf %q "${TERM_PROGRAM:-}") TERM_PROGRAM_VERSION=$(printf %q "${TERM_PROGRAM_VERSION:-}")"
  remote_cmd+="; exec /bin/zsh \"\$HOME/.local/bin/lanjump-pick\""
  ssh_tty -t -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" \
    "$remote_cmd"
  local st=$?
  if [[ $st -eq 0 ]]; then
    restore_tty
    trap - EXIT
    exit 0
  fi
  load_hosts
  build_items
  if [[ $st -eq 10 ]]; then
    notice="已回到机器列表。"
  else
    notice="连接已断开（退出码 ${st}）。"
  fi
  # keep cursor on this alias if possible
  local j n=${#items_kind}
  for (( j = 1; j <= n; j++ )); do
    if [[ ${items_kind[$j]} == host && ${items_alias[$j]} == "$alias" ]]; then
      cursor=$j
      break
    fi
  done
  setup_tty
}

connect_local() {
  local picker st j n
  restore_tty
  picker=$(picker_path)
  if [[ -z $picker ]]; then
    notice="本机 tmux 选择界面不存在。请重新安装：zsh install.zsh，或运行 lanjump"
    setup_tty
    return
  fi
  mark_last local
  print
  /bin/zsh "$picker"
  st=$?
  if [[ $st -eq 0 ]]; then
    restore_tty
    trap - EXIT
    exit 0
  fi
  load_hosts
  build_items
  if [[ $st -eq 10 ]]; then
    notice="已回到机器列表。"
  else
    notice="已离开本机界面（退出码 ${st}）。"
  fi
  n=${#items_kind}
  for (( j = 1; j <= n; j++ )); do
    if [[ ${items_kind[$j]} == local ]]; then
      cursor=$j
      break
    fi
  done
  setup_tty
}

forget_item() {
  local i=$1
  if [[ ${items_kind[$i]} == local ]]; then
    notice="本机不用忘掉。"
    return
  fi
  [[ ${items_kind[$i]} == host ]] || return
  [[ -n ${items_saved[$i]} ]] || {
    notice="这台还没保存，不用忘掉。"
    return
  }
  local name=${items_alias[$i]}
  restore_tty
  print
  print "忘掉「${name}」？只删本机记录，不动对方。"
  print -n "确认请输入 y，其他键取消: "
  local ans
  read -r ans </dev/tty
  setup_tty
  if [[ $ans == y || $ans == Y ]]; then
    forget_saved "${items_saved[$i]}"
    load_hosts
    build_items
    notice="已忘掉 ${name}。"
  fi
}

activate() {
  local i=$1
  case ${items_kind[$i]} in
    host) connect_item $i ;;
    local) connect_local ;;
    scan)
      do_scan
      ;;
    quit)
      restore_tty
      trap - EXIT
      exit 0
      ;;
  esac
}

if [[ ${1:-} == --digit-selftest ]]; then
  . "${0:A:h}/lanjump-digit-selftest.zsh"
  digit_selftest
  exit $?
fi

if [[ ${1:-} == --print-lan ]]; then
  detect_lan
  print -r -- "${IFACE:-}|${MYIP:-}|${PREFIX:-}"
  exit 0
fi

ensure_setup
detect_lan
load_hosts
build_items
apply_last_cursor

if [[ ! -t 0 || ! -t 1 ]]; then
  print "需要交互式终端。请运行 lanjump，或双击桌面上的 Lanjump.command。"
  exit 1
fi

setup_tty
# No saved remotes: auto-scan unless last used this Mac.
if (( ${#h_alias} == 0 )) && [[ $(read_last) != local ]]; then
  do_scan
  apply_last_cursor
fi
draw

while true; do
  read_key || continue
  case $REPLY in
    up)
      (( cursor-- ))
      (( cursor < 1 )) && cursor=${#items_kind}
      draw
      ;;
    down)
      (( cursor++ ))
      (( cursor > ${#items_kind} )) && cursor=1
      draw
      ;;
    top)
      cursor=1
      draw
      ;;
    bottom)
      cursor=${#items_kind}
      draw
      ;;
    enter)
      activate $cursor
      draw
      ;;
    r)
      do_scan
      draw
      ;;
    d)
      forget_item $cursor
      draw
      ;;
    q|esc)
      restore_tty
      trap - EXIT
      exit 0
      ;;
    num*)
      collect_index_digits "${REPLY#num}" ${#items_kind}
      n=$REPLY
      if [[ $n == [1-9]* && $n != *[!0-9]* ]] && (( 10#$n <= ${#items_kind} )); then
        cursor=$((10#$n))
        activate $cursor
        draw
      fi
      ;;
  esac
done
