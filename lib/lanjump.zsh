#!/bin/zsh
emulate -L zsh
setopt no_unset extendedglob typesetsilent
zmodload zsh/datetime

APP="$HOME/Library/Application Support/lanjump"

if [[ ${1:-} == upgrade || ${1:-} == update ]]; then
  if [[ ! -f $APP/install.zsh ]]; then
    print -u2 '找不到安装脚本。请重新安装：zsh install.zsh'
    exit 1
  fi
  exec /bin/zsh "$APP/install.zsh" --upgrade
fi

HOSTS_FILE="$APP/hosts"
LAST_FILE="$APP/last_target"
KEY="$HOME/.ssh/id_ed25519_lanjump"
PICKER="$APP/lanjump-pick.zsh"
SSH_CONFIG="$HOME/.ssh/config"

typeset -a h_alias h_user h_hostname h_ip h_mac h_port h_ssh_id h_last
typeset -a items_kind items_alias items_user items_hostname items_ip items_mac items_port items_status items_saved
typeset -a cli_recent_names
typeset -a s_alias s_host s_ip s_mac s_port
typeset -a MYIPS
cursor=1
cli_recent_cur=1
loading=0
host_list_active=0
draw_remain=0
view_start=1
view_end=0
view_above=0
view_below=0
stty_orig=
PENDING_KEY=""
typeset -i _read_key_fails=0
digit_wait=0.5
notice=""
MYIP=""
PREFIX=""
MASK=""
IFACE=""
LANJUMP_KEYS=""
IME_PY="${0:A:h}/lanjump-ime.py"
ime_switched=0

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
  host_list_active=0
  print -n -u2 $'\e[?25h'
  [[ -n ${stty_orig:-} ]] && stty "$stty_orig" 2>/dev/null || stty sane 2>/dev/null
}

setup_tty() {
  stty_orig=$(stty -g)
  stty -echo -icanon min 1 time 0
  print -n -u2 $'\e[?25l'
  host_list_active=1
}

on_exit() {
  restore_tty
}
trap on_exit EXIT
trap 'restore_tty; exit 130' INT

term_cols() {
  local c=${COLUMNS:-0}
  if (( c < 20 )); then
    c=$(stty size 2>/dev/null | awk '{print $2}')
  fi
  (( c < 40 )) && c=40
  print -r -- $c
}

term_lines() {
  local r=${LINES:-0}
  if (( r < 1 )); then
    r=$(stty size 2>/dev/null | awk '{print $1}')
  fi
  (( r < 1 )) && r=1
  print -r -- $r
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

# Same idea as pick.zsh local_keyboard: this Mac is typing, not a phone SSH session.
local_keyboard() {
  [[ -z ${SSH_CONNECTION:-} && -z ${SSH_CLIENT:-} && -z ${SSH_TTY:-} ]]
}

ime_file() {
  print -r -- "$APP/ime"
}

ime_enabled() {
  local f v
  f=$(ime_file)
  [[ -f $f ]] || return 0
  v=$(<"$f")
  v=${v%%$'\n'*}
  v=$(trim "$v")
  v=${v:l}
  [[ $v != off ]]
}

should_switch_ime() {
  ime_enabled || return 1
  local_keyboard
}

ime_switch_command() {
  local py=${IME_PY:-}
  [[ -n $py && -f $py ]] || return 1
  print -r -- "python3 ${(q)py}"
}

maybe_switch_ime() {
  should_switch_ime || return 0
  (( ime_switched )) && return 0
  ime_switched=1
  local py=${IME_PY:-}
  [[ -n $py && -f $py ]] || return 0
  command python3 "$py" >/dev/null 2>&1 || true
}

toggle_ime() {
  local f dir
  f=$(ime_file)
  dir=${f:h}
  mkdir -p "$dir"
  if ime_enabled; then
    print -r -- off >"$f"
    ime_switched=0
    notice="已关闭打开时切英文输入法。"
  else
    print -r -- on >"$f"
    notice="已打开打开时切英文输入法。"
    maybe_switch_ime
  fi
}

mark_last() {
  print -r -- "$1" | replace_file_atomic "$LAST_FILE"
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
  elif [[ -n $last && $last != host ]]; then
    for (( j = 1; j <= n; j++ )); do
      if [[ ${items_kind[$j]} == host && ${items_alias[$j]} == "$last" ]]; then
        cursor=$j
        return
      fi
    done
  fi
  cursor=1
}

# Host alias, or local/scan/quit. Scan inserts must reselect this, not a row number.
list_item_key() {
  local i=$1
  (( i >= 1 && i <= ${#items_kind} )) || return 1
  case ${items_kind[$i]} in
    host) print -r -- "host:${items_alias[$i]}" ;;
    local|scan|quit) print -r -- "${items_kind[$i]}" ;;
    *) return 1 ;;
  esac
}

restore_list_cursor() {
  local want=$1 j n=${#items_kind} key
  [[ -n $want ]] || return
  for (( j = 1; j <= n; j++ )); do
    key=$(list_item_key $j) || continue
    if [[ $key == "$want" ]]; then
      cursor=$j
      return
    fi
  done
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

ensure_setup() {
  mkdir -p "$APP" "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
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

iface_netmask() {
  local iface=$1 mask
  mask=$(ifconfig "$iface" 2>/dev/null | awk '/inet / {
    for (i = 1; i <= NF; i++) if ($i == "netmask") { print $(i+1); exit }
  }') || true
  print -r -- "$mask"
}

netmask_prefixlen() {
  local mask=$1 val=0 a b c d
  if [[ -z $mask ]]; then
    print -r -- 24
    return
  fi
  if [[ $mask == 0x[0-9a-fA-F]## ]]; then
    val=$((16#${mask#0x}))
  elif [[ $mask == [0-9]##.[0-9]##.[0-9]##.[0-9]## ]]; then
    a=${mask%%.*}
    mask=${mask#*.}
    b=${mask%%.*}
    mask=${mask#*.}
    c=${mask%%.*}
    d=${mask#*.}
    val=$(( (a << 24) + (b << 16) + (c << 8) + d ))
  else
    print -r -- 24
    return
  fi
  local n=0
  while (( val )); do
    (( n += val & 1 ))
    (( val >>= 1 ))
  done
  print -r -- $n
}

ipv4_int() {
  local ip=$1 a b c d
  a=${ip%%.*}
  ip=${ip#*.}
  b=${ip%%.*}
  ip=${ip#*.}
  c=${ip%%.*}
  d=${ip#*.}
  print -r -- $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

ipv4_prefix24() {
  local n=$1
  print -r -- "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 ))"
}

ipv4_network() {
  local ip=$1 plen=$2
  local start
  start=$(( $(ipv4_int "$ip") & (0xffffffff ^ ((1 << (32 - plen)) - 1)) ))
  print -r -- "$(( (start >> 24) & 255 )).$(( (start >> 16) & 255 )).$(( (start >> 8) & 255 )).$(( start & 255 ))"
}

# /22-/24: every /24 in the interface prefix. Larger nets stay this host's /24.
scan_lan_prefixes() {
  local ip=$1 mask=$2
  local raw plen start i count
  [[ $ip == [0-9]##.[0-9]##.[0-9]##.[0-9]## ]] || return
  raw=$(netmask_prefixlen "$mask")
  plen=$raw
  if (( plen < 22 || plen > 24 )); then
    plen=24
  fi
  start=$(( $(ipv4_int "$ip") & (0xffffffff ^ ((1 << (32 - plen)) - 1)) ))
  count=$(( 1 << (24 - plen) ))
  for (( i = 0; i < count; i++ )); do
    print -r -- "$(ipv4_prefix24 $(( start + (i << 8) )))"
  done
}

scan_lan_label() {
  local ip=$1 mask=$2
  local raw
  [[ $ip == [0-9]##.[0-9]##.[0-9]##.[0-9]## ]] || return
  raw=$(netmask_prefixlen "$mask")
  if (( raw >= 22 && raw <= 24 )); then
    print -r -- "$(ipv4_network "$ip" "$raw")/${raw}"
  elif (( raw > 0 && raw < 22 )); then
    print -r -- "${ip%.*}.0/24（网段更大，只扫本 /24）"
  else
    print -r -- "${ip%.*}.0/24"
  fi
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
  MASK=""
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
    MASK=$(iface_netmask "$cand")
    return
  done
}

is_self_ip() {
  local ip=$1 x
  [[ -z $ip ]] && return 1
  (( ${#MYIPS} )) || collect_self_ips
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

ssh_id_tag() {
  local tag=${1:l}
  tag=${tag//:/-}
  tag=${tag//[^a-z0-9._-]/-}
  tag=${tag##-}
  tag=${tag%%-}
  [[ -n $tag ]] || return 1
  print -r -- "$tag"
}

# ASCII aliases stay slug-only until another host already owns that
# id (#313). CJK (or any lossy slug) is not unique after non-ASCII is
# stripped (#285), so suffix MAC, else IP, or refuse.
ssh_id_from_alias() {
  local alias=$1 mac=${2:-} ip=${3:-}
  local s=${alias:l}
  local -i lossy=0
  [[ $alias != *[^A-Za-z0-9._\ -]* ]] || lossy=1
  s=${s// /-}
  s=${s//[^a-z0-9._-]/-}
  s=${s##-}
  s=${s%%-}
  [[ -n $s ]] || s="host"
  if (( lossy )); then
    local tag
    tag=$(ssh_id_tag "$mac") || tag=$(ssh_id_tag "$ip") || return 1
    print -r -- "lanjump-${s}-${tag}"
    return
  fi
  print -r -- "lanjump-${s}"
}

# Written id wins; otherwise the natural id. exclude is the row being
# updated so a rename does not collide with itself.
ssh_id_taken() {
  local want=$1 exclude=${2:-0}
  local i n=${#h_alias} id
  for (( i = 1; i <= n; i++ )); do
    (( i == exclude )) && continue
    id=${h_ssh_id[$i]:-}
    if [[ -z $id ]]; then
      id=$(ssh_id_from_alias "${h_alias[$i]}" "${h_mac[$i]}" "${h_ip[$i]}") || continue
    fi
    [[ $id == "$want" ]] && return 0
  done
  return 1
}

# Natural id, or MAC/IP suffix when that slug is already live. Refuse
# rather than write a second host into the same SSH block.
alloc_ssh_id() {
  local alias=$1 mac=$2 ip=$3 exclude=${4:-0}
  local id tag candidate
  id=$(ssh_id_from_alias "$alias" "$mac" "$ip") || return 1
  if ssh_id_taken "$id" "$exclude"; then
    tag=$(ssh_id_tag "$mac") || tag=$(ssh_id_tag "$ip") || return 1
    candidate="lanjump-${id#lanjump-}-${tag}"
    [[ $candidate != "$id" ]] || return 1
    ssh_id_taken "$candidate" "$exclude" && return 1
    id=$candidate
  fi
  print -r -- "$id"
}

load_hosts() {
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  [[ -f $HOSTS_FILE ]] || return
  local line
  local -a f
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    f=("${(@s:|:)line}")
    (( ${#f} >= 6 )) || continue
    # #313: optional ssh_id sits before last when it is a written Host id.
    # #280: optional port sits before last. A 1–65535 field there is
    # the advertised SSH port; otherwise the row is the pre-port format.
    # #219: extra | belongs to the alias (Bonjour names).
    if (( ${#f} >= 8 )) && [[ ${f[-2]} == lanjump-* ]]; then
      h_alias+=("${(j:|:)f[1,-8]}")
      h_user+=("${f[-7]}")
      h_hostname+=("${f[-6]}")
      h_ip+=("${f[-5]}")
      h_mac+=("${f[-4]}")
      h_port+=("${f[-3]}")
      h_ssh_id+=("${f[-2]}")
      h_last+=("${f[-1]}")
    elif (( ${#f} >= 7 )) && [[ ${f[-2]} == [1-9][0-9](#c0,4) ]] && (( f[-2] <= 65535 )); then
      h_alias+=("${(j:|:)f[1,-7]}")
      h_user+=("${f[-6]}")
      h_hostname+=("${f[-5]}")
      h_ip+=("${f[-4]}")
      h_mac+=("${f[-3]}")
      h_port+=("${f[-2]}")
      h_ssh_id+=("")
      h_last+=("${f[-1]}")
    else
      h_alias+=("${(j:|:)f[1,-6]}")
      h_user+=("${f[-5]}")
      h_hostname+=("${f[-4]}")
      h_ip+=("${f[-3]}")
      h_mac+=("${f[-2]}")
      h_port+=("22")
      h_ssh_id+=("")
      h_last+=("${f[-1]}")
    fi
  done <"$HOSTS_FILE"
}

# Same-dir temp + rename so concurrent readers never see a torn dest (#213/#264).
# Follow a dest symlink so the directory entry stays a link (#274).
replace_file_atomic() {
  local dest=$1 dir tmp
  [[ -L $dest ]] && dest=${dest:A}
  dir=${dest:h}
  mkdir -p "$dir"
  tmp=$(mktemp "${dir}/.${dest:t}.XXXXXX") || return 1
  cat >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$dest" || {
    rm -f "$tmp"
    return 1
  }
}

# Sidecar lock: dest is renamed by replace_file_atomic, so flock(dest) would
# not serialize writers. Same-file load+replace must hold this (#276/#314).
with_data_file_lock() {
  local dest=$1
  shift
  local lock dir
  local -i fd=-1 st=0 n=0
  dir=${dest:h}
  lock=${dest}.lock
  mkdir -p "$dir"
  [[ -e $lock ]] || : >"$lock"
  if zmodload zsh/system 2>/dev/null && zsystem supports flock; then
    zsystem flock -f fd "$lock" || return 1
    "$@"
    st=$?
    zsystem flock -u fd
    return $st
  fi
  while ! mkdir "${lock}.d" 2>/dev/null; do
    sleep 0.05
    (( ++n > 200 )) && return 1
  done
  "$@"
  st=$?
  rmdir "${lock}.d" 2>/dev/null
  return $st
}

save_hosts() {
  local i n=${#h_alias} st=0
  if [[ -z ${_LANJUMP_HOSTS_LOCKED:-} ]]; then
    _LANJUMP_HOSTS_LOCKED=1
    with_data_file_lock "$HOSTS_FILE" save_hosts
    st=$?
    unset _LANJUMP_HOSTS_LOCKED
    return $st
  fi
  {
    print -r -- "# alias|user|hostname|ip|mac|port|ssh_id|last"
    for (( i = 1; i <= n; i++ )); do
      if [[ -n ${h_ssh_id[$i]:-} ]]; then
        print -r -- "${h_alias[$i]}|${h_user[$i]//|/-}|${h_hostname[$i]//|/-}|${h_ip[$i]}|${h_mac[$i]}|${h_port[$i]:-22}|${h_ssh_id[$i]}|${h_last[$i]}"
      else
        print -r -- "${h_alias[$i]}|${h_user[$i]//|/-}|${h_hostname[$i]//|/-}|${h_ip[$i]}|${h_mac[$i]}|${h_port[$i]:-22}|${h_last[$i]}"
      fi
    done
  } | replace_file_atomic "$HOSTS_FILE"
}

# Scan persist: same protocol as upsert_host (#314). Reload under the
# hosts lock, apply s_* onto that table, then write so a stale list
# window cannot drop a concurrent upsert (#333).
persist_scan_hosts() {
  local st=0 i n idx
  if [[ -z ${_LANJUMP_HOSTS_LOCKED:-} ]]; then
    _LANJUMP_HOSTS_LOCKED=1
    with_data_file_lock "$HOSTS_FILE" persist_scan_hosts
    st=$?
    unset _LANJUMP_HOSTS_LOCKED
    return $st
  fi
  load_hosts
  n=${#s_ip}
  for (( i = 1; i <= n; i++ )); do
    idx=$(find_saved "${s_mac[$i]}" "${s_host[$i]}" "${s_ip[$i]}")
    if [[ -n $idx ]]; then
      [[ -n ${s_host[$i]} ]] && h_hostname[$idx]=${s_host[$i]}
      [[ -n ${s_ip[$i]} ]] && h_ip[$idx]=${s_ip[$i]}
      [[ -n ${s_mac[$i]} ]] && h_mac[$idx]=${s_mac[$i]}
      [[ -n ${s_port[$i]} ]] && h_port[$idx]=${s_port[$i]}
    fi
  done
  save_hosts
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
        # Hostname is only a merge key when the saved row has no MAC.
        # Otherwise an unauthenticated mDNS name can overwrite a known
        # machine's IP and MAC (#304).
        [[ -n ${h_mac[$i]} ]] && continue
        print -r -- $i
        return
      fi
    done
  fi
  if [[ -n $ip ]]; then
    for (( i = 1; i <= n; i++ )); do
      if [[ ${h_ip[$i]} != "$ip" ]]; then
        continue
      fi
      # IP is only a merge key when the saved row has no MAC and the
      # hostname is the same or unknown. Otherwise DHCP reuse would
      # overwrite a known machine's identity (#211).
      [[ -n ${h_mac[$i]} ]] && continue
      if [[ -n ${h_hostname[$i]} && -n $hostname && ${h_hostname[$i]} != "$hostname" ]]; then
        continue
      fi
      print -r -- $i
      return
    done
  fi
}

upsert_host() {
  local alias=$1 user=$2 hostname=$3 ip=$4 mac=$5 port=${6:-22}
  local idx old_id id st=0
  if [[ -z ${_LANJUMP_HOSTS_LOCKED:-} ]]; then
    _LANJUMP_HOSTS_LOCKED=1
    with_data_file_lock "$HOSTS_FILE" upsert_host "$alias" "$user" "$hostname" "$ip" "$mac" "$port"
    st=$?
    unset _LANJUMP_HOSTS_LOCKED
    return $st
  fi
  load_hosts
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    old_id=${h_ssh_id[$idx]:-}
    if [[ -z $old_id ]]; then
      old_id=$(ssh_id_from_alias "${h_alias[$idx]}" "${h_mac[$idx]}" "${h_ip[$idx]}") || old_id=""
    fi
    h_alias[$idx]=$alias
    h_user[$idx]=$user
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
    [[ -n $port ]] && h_port[$idx]=$port
    h_last[$idx]=$EPOCHSECONDS
  else
    h_alias+=("$alias")
    h_user+=("$user")
    h_hostname+=("$hostname")
    h_ip+=("$ip")
    h_mac+=("$mac")
    h_port+=("${port:-22}")
    h_ssh_id+=("")
    h_last+=("$EPOCHSECONDS")
    idx=${#h_alias}
    old_id=""
  fi
  if id=$(alloc_ssh_id "$alias" "$mac" "$ip" "$idx"); then
    if [[ -n $old_id && $old_id != "$id" ]]; then
      remove_ssh_config "$old_id"
    fi
    upsert_ssh_config "$id" "$user" "${hostname:-$ip}" "$port"
    h_ssh_id[$idx]=$id
  fi
  save_hosts
}

forget_saved() {
  local idx=$1
  local n=${#h_alias}
  (( idx >= 1 && idx <= n )) || return
  local id mac hostname ip st=0
  local -a na nu nh ni nm np ns nl
  local i
  id=${h_ssh_id[$idx]:-}
  if [[ -z $id ]]; then
    id=$(ssh_id_from_alias "${h_alias[$idx]}" "${h_mac[$idx]}" "${h_ip[$idx]}") || id=""
  fi
  mac=${h_mac[$idx]}
  hostname=${h_hostname[$idx]}
  ip=${h_ip[$idx]}
  if [[ -z ${_LANJUMP_HOSTS_LOCKED:-} ]]; then
    _LANJUMP_HOSTS_LOCKED=1
    with_data_file_lock "$HOSTS_FILE" forget_saved "$idx"
    st=$?
    unset _LANJUMP_HOSTS_LOCKED
    return $st
  fi
  load_hosts
  idx=$(find_saved "$mac" "$hostname" "$ip")
  n=${#h_alias}
  if [[ -n $idx ]]; then
    na=() nu=() nh=() ni=() nm=() np=() ns=() nl=()
    for (( i = 1; i <= n; i++ )); do
      (( i == idx )) && continue
      na+=("${h_alias[$i]}")
      nu+=("${h_user[$i]}")
      nh+=("${h_hostname[$i]}")
      ni+=("${h_ip[$i]}")
      nm+=("${h_mac[$i]}")
      np+=("${h_port[$i]:-22}")
      ns+=("${h_ssh_id[$i]:-}")
      nl+=("${h_last[$i]}")
    done
    h_alias=("${na[@]}")
    h_user=("${nu[@]}")
    h_hostname=("${nh[@]}")
    h_ip=("${ni[@]}")
    h_mac=("${nm[@]}")
    h_port=("${np[@]}")
    h_ssh_id=("${ns[@]}")
    h_last=("${nl[@]}")
  fi
  [[ -n $id ]] && remove_ssh_config "$id"
  save_hosts
}

strip_ssh_block() {
  local begin=$1 end=$2
  [[ -f $SSH_CONFIG ]] || return
  grep -qF "$begin" "$SSH_CONFIG" 2>/dev/null || return
  # Missing END must not delete through EOF.
  awk -v b="$begin" -v e="$end" '
    $0 == b {
      if (open) exit 1
      open = 1
      next
    }
    $0 == e {
      if (open) open = 0
    }
    END { if (open) exit 1 }
  ' "$SSH_CONFIG" || return 1
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$SSH_CONFIG" | replace_file_atomic "$SSH_CONFIG" || return 1
  chmod 600 "$SSH_CONFIG"
}

remove_ssh_config() {
  local id=$1 st=0
  if [[ -z ${_LANJUMP_SSH_LOCKED:-} ]]; then
    _LANJUMP_SSH_LOCKED=1
    with_data_file_lock "$SSH_CONFIG" remove_ssh_config "$id"
    st=$?
    unset _LANJUMP_SSH_LOCKED
    return $st
  fi
  strip_ssh_block "# BEGIN LANJUMP ${id}" "# END LANJUMP ${id}"
}

replace_ssh_config() {
  cat "$1" | replace_file_atomic "$SSH_CONFIG" || {
    rm -f "$1"
    return 1
  }
  rm -f "$1"
  chmod 600 "$SSH_CONFIG"
}

upsert_ssh_config() {
  local id=$1 user=$2 hostname=$3 port=${4:-22} st=0
  local begin="# BEGIN LANJUMP ${id}"
  local end="# END LANJUMP ${id}"
  local tmp
  if [[ -z ${_LANJUMP_SSH_LOCKED:-} ]]; then
    _LANJUMP_SSH_LOCKED=1
    with_data_file_lock "$SSH_CONFIG" upsert_ssh_config "$id" "$user" "$hostname" "$port"
    st=$?
    unset _LANJUMP_SSH_LOCKED
    return $st
  fi
  mkdir -p "$HOME/.ssh"
  [[ -f $SSH_CONFIG ]] || : >"$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  # Missing END: do not append (OpenSSH first-match would keep the old HostName).
  # Replace the damaged LANJUMP Host in place; stop before a later user Host (#63).
  # Probe only — do not strip dest (that hole is #272).
  if grep -qF "$begin" "$SSH_CONFIG" 2>/dev/null &&
     ! awk -v b="$begin" -v e="$end" '
       $0 == b {
         if (open) exit 1
         open = 1
         next
       }
       $0 == e {
         if (open) open = 0
       }
       END { if (open) exit 1 }
     ' "$SSH_CONFIG"; then
    tmp=$(mktemp)
    awk -v begin="$begin" -v end="$end" -v id="$id" -v user="$user" -v hn="$hostname" -v key="$KEY" -v port="$port" '
      function emit() {
        if (emitted) return
        print ""
        print begin
        print "Host " id
        print "  HostName " hn
        if (port != "" && port != "22") print "  Port " port
        print "  User " user
        print "  IdentityFile " key
        print "  IdentitiesOnly yes"
        print "  AddKeysToAgent yes"
        print "  UseKeychain yes"
        print "  AddressFamily inet"
        print "  StrictHostKeyChecking accept-new"
        print "  ConnectTimeout 8"
        print end
        emitted = 1
      }
      $0 == begin && !emitted { skip = 1; next }
      skip && $1 == "Host" && $2 == id { ours = 1; next }
      skip && ours && /^[ \t]/ { next }
      skip && ours && $0 == end { next }
      skip { emit(); skip = 0; ours = 0; if ($0 != end) print; next }
      { print }
      END { emit() }
    ' "$SSH_CONFIG" >"$tmp"
    replace_ssh_config "$tmp"
    return
  fi
  tmp=$(mktemp)
  {
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip { print }
    ' "$SSH_CONFIG"
    print
    print "$begin"
    print "Host ${id}"
    print "  HostName ${hostname}"
    if [[ -n $port && $port != 22 ]]; then
      print "  Port ${port}"
    fi
    print "  User ${user}"
    print "  IdentityFile ${KEY}"
    print "  IdentitiesOnly yes"
    print "  AddKeysToAgent yes"
    print "  UseKeychain yes"
    print "  AddressFamily inet"
    print "  StrictHostKeyChecking accept-new"
    print "  ConnectTimeout 8"
    print "$end"
  } >"$tmp"
  replace_ssh_config "$tmp"
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
    print -r -- "${inst}"$'\t'"${host}"$'\t'"${ip}"$'\t'"$(get_mac "$ip")"$'\t'"${port:-22}"
  done <"$inst_file"
  rm -f "$tmp" "$inst_file"
}

scan_port22() {
  local prefix i ip
  local -a prefixes
  prefixes=("${(@f)$(scan_lan_prefixes "$1" "${2:-}")}")
  (( ${#prefixes} )) || return
  for prefix in "${prefixes[@]}"; do
    [[ -n $prefix ]] || continue
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
  done
  wait
}

build_items() {
  items_kind=() items_alias=() items_user=() items_hostname=() items_ip=() items_mac=() items_port=() items_status=() items_saved=()
  local i n=${#h_alias} idx last
  last=$(read_last)
  if (( n )); then
    local -a idx_order
    idx_order=()
    for (( i = 1; i <= n; i++ )); do
      idx_order+=("${h_last[$i]}/${i}")
    done
    idx_order=("${(@nO)idx_order}")
    for i in "${idx_order[@]}"; do
      idx=${i##*/}
      items_kind+=("host")
      items_alias+=("${h_alias[$idx]}")
      items_user+=("${h_user[$idx]}")
      items_hostname+=("${h_hostname[$idx]}")
      items_ip+=("${h_ip[$idx]}")
      items_mac+=("${h_mac[$idx]}")
      items_port+=("${h_port[$idx]:-22}")
      if [[ ${h_alias[$idx]} == "$last" && $last != local ]]; then
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
  items_port+=("")
  items_status+=("")
  items_saved+=("")

  items_kind+=("scan")
  items_alias+=("扫描局域网…")
  items_user+=("")
  items_hostname+=("")
  items_ip+=("")
  items_mac+=("")
  items_port+=("")
  items_status+=("")
  items_saved+=("")

  items_kind+=("quit")
  items_alias+=("退出")
  items_user+=("")
  items_hostname+=("")
  items_ip+=("")
  items_mac+=("")
  items_port+=("")
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
  # $5 empty/omitted: unspecified. A Bonjour-announced 22 must write (#312).
  local alias=$1 hostname=$2 ip=$3 mac=$4 port=${5-}
  local idx
  is_self_ip "$ip" && return
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
    [[ -n $port ]] && h_port[$idx]=$port
    return
  fi
  local i n=${#items_kind}
  for (( i = 1; i <= n; i++ )); do
    if [[ ${items_kind[$i]} == host ]]; then
      if [[ -n $ip && ${items_ip[$i]} == "$ip" ]]; then
        [[ -n $port ]] && items_port[$i]=$port
        return
      fi
      if [[ -n $mac && -n ${items_mac[$i]} && ${items_mac[$i]} == "$mac" ]]; then
        [[ -n $port ]] && items_port[$i]=$port
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
  while (( ${#items_port} < n )); do
    items_port+=("22")
  done
  items_kind=("${(@)items_kind[1,insert_at-1]}" host "${(@)items_kind[insert_at,-1]}")
  items_alias=("${(@)items_alias[1,insert_at-1]}" "$alias" "${(@)items_alias[insert_at,-1]}")
  items_user=("${(@)items_user[1,insert_at-1]}" "" "${(@)items_user[insert_at,-1]}")
  items_hostname=("${(@)items_hostname[1,insert_at-1]}" "$hostname" "${(@)items_hostname[insert_at,-1]}")
  items_ip=("${(@)items_ip[1,insert_at-1]}" "$ip" "${(@)items_ip[insert_at,-1]}")
  items_mac=("${(@)items_mac[1,insert_at-1]}" "$mac" "${(@)items_mac[insert_at,-1]}")
  items_port=("${(@)items_port[1,insert_at-1]}" "${port:-22}" "${(@)items_port[insert_at,-1]}")
  items_status=("${(@)items_status[1,insert_at-1]}" "新发现" "${(@)items_status[insert_at,-1]}")
  items_saved=("${(@)items_saved[1,insert_at-1]}" "" "${(@)items_saved[insert_at,-1]}")
}

mark_online() {
  local ip=$1 mac=$2 hostname=$3
  local i n=${#items_kind}
  local matched
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host ]] || continue
    # Same merge keys as find_saved: a row that already has a MAC is
    # only the same machine on MAC match. Hostname/IP-only must not
    # rewrite its identity (#332 / #304 / #211).
    matched=0
    if [[ -n $mac && -n ${items_mac[$i]} && ${items_mac[$i]} == "$mac" ]]; then
      matched=1
    elif [[ -n ${items_mac[$i]} ]]; then
      matched=0
    elif [[ -n $hostname && -n ${items_hostname[$i]} && ${items_hostname[$i]} == "$hostname" ]]; then
      matched=1
    elif [[ -n $ip && ${items_ip[$i]} == "$ip" ]]; then
      if [[ -z ${items_hostname[$i]} || -z $hostname || ${items_hostname[$i]} == "$hostname" ]]; then
        matched=1
      fi
    fi
    (( matched )) || continue
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
  done
}

record_seen() {
  # $5 empty/omitted: unspecified. A Bonjour-announced 22 must write (#312).
  local alias=$1 hostname=$2 ip=$3 mac=$4 port=${5-}
  local idx
  is_self_ip "$ip" && return
  idx=$(find_saved "$mac" "$hostname" "$ip")
  if [[ -n $idx ]]; then
    [[ -n $hostname ]] && h_hostname[$idx]=$hostname
    [[ -n $ip ]] && h_ip[$idx]=$ip
    [[ -n $mac ]] && h_mac[$idx]=$mac
    [[ -n $port ]] && h_port[$idx]=$port
  fi
  local i n=${#s_ip}
  for (( i = 1; i <= n; i++ )); do
    if [[ -n $ip && ${s_ip[$i]} == "$ip" ]]; then
      [[ -n $hostname && -z ${s_host[$i]} ]] && s_host[$i]=$hostname
      [[ -n $mac && -z ${s_mac[$i]} ]] && s_mac[$i]=$mac
      [[ -n $alias && ${s_alias[$i]} == "$ip" ]] && s_alias[$i]=$alias
      [[ -n $port ]] && s_port[$i]=$port
      return
    fi
  done
  s_alias+=("$alias")
  s_host+=("$hostname")
  s_ip+=("$ip")
  s_mac+=("$mac")
  s_port+=("$port")
}

ssh_fp() {
  ssh-keyscan -4 -t ed25519 -T 3 "$1" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}'
}

# Fill caller `fp` from `s_ip`, batched like scan_port22 so N hosts wait ~3s not 3N.
fill_seen_hostkeys() {
  local i n=${#s_ip} dir
  fp=()
  (( n )) || return
  dir=$(mktemp -d) || return
  for (( i = 1; i <= n; i++ )); do
    (
      ssh_fp "${s_ip[$i]}" >"$dir/$i"
    ) &
    if (( i % 40 == 0 )); then
      wait
    fi
  done
  wait
  for (( i = 1; i <= n; i++ )); do
    [[ -f $dir/$i ]] && fp[i]=$(<"$dir/$i")
  done
  rm -rf "$dir"
}

is_numeric_alias() {
  [[ $1 == [0-9]##[.][0-9]##[.][0-9]##[.][0-9]## ]]
}

merge_seen_by_hostkey() {
  local i j n=${#s_ip}
  local -a fp
  local known="$HOME/.ssh/known_hosts"
  (( n )) || return
  fill_seen_hostkeys
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
      if [[ ${s_port[$i]:-22} == 22 && ${s_port[$j]:-22} != 22 ]]; then
        s_port[$i]=${s_port[$j]}
      fi
      if [[ -f $known ]] && grep -qF "${s_ip[$j]} " "$known" && ! grep -qF "${s_ip[$i]} " "$known"; then
        s_ip[$i]=${s_ip[$j]}
        s_mac[$i]=${s_mac[$j]}
        [[ -n ${s_host[$j]} ]] && s_host[$i]=${s_host[$j]}
        if [[ ${s_port[$j]:-22} != 22 ]]; then
          s_port[$i]=${s_port[$j]}
        fi
        if ! is_numeric_alias "${s_alias[$j]}"; then
          s_alias[$i]=${s_alias[$j]}
        fi
      fi
      s_ip[$j]=""
    done
  done
  local -a na nh ni nm np
  na=() nh=() ni=() nm=() np=()
  for (( i = 1; i <= n; i++ )); do
    [[ -n ${s_ip[$i]} ]] || continue
    na+=("${s_alias[$i]}")
    nh+=("${s_host[$i]}")
    ni+=("${s_ip[$i]}")
    nm+=("${s_mac[$i]}")
    np+=("${s_port[$i]:-}")
  done
  s_alias=("${na[@]}")
  s_host=("${nh[@]}")
  s_ip=("${ni[@]}")
  s_mac=("${nm[@]}")
  s_port=("${np[@]}")
}

do_scan() {
  local keep alias hostname ip mac
  local i n
  local -i extra=0
  keep=$(list_item_key $cursor) || keep=
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
  print "正在扫描 Bonjour SSH 和 $(scan_lan_label "$MYIP" "$MASK") 的 22 端口…"
  s_alias=() s_host=() s_ip=() s_mac=() s_port=()
  while IFS=$'\t' read -r alias hostname ip mac port; do
    [[ -n $alias || -n $ip ]] || continue
    [[ -z $alias ]] && alias=${hostname:-$ip}
    record_seen "$alias" "$hostname" "$ip" "$mac" "$port"
  done < <(scan_bonjour)
  while IFS= read -r ip; do
    [[ -n $ip ]] || continue
    mac=$(get_mac "$ip")
    record_seen "$ip" "" "$ip" "$mac"
  done < <(scan_port22 "$MYIP" "$MASK")
  merge_seen_by_hostkey
  persist_scan_hosts
  load_hosts
  build_items
  n=${#s_alias}
  for (( i = 1; i <= n; i++ )); do
    add_discovered "${s_alias[$i]}" "${s_host[$i]}" "${s_ip[$i]}" "${s_mac[$i]}" "${s_port[$i]:-}"
    mark_online "${s_ip[$i]}" "${s_mac[$i]}" "${s_host[$i]}"
  done
  restore_list_cursor "$keep"
  n=${#items_kind}
  extra=0
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host && ${items_status[$i]} == 新发现 ]] && (( extra++ ))
  done
  notice="扫描完成。新发现 ${extra} 台开了 SSH 的设备。"
  loading=0
  setup_tty
}

# Sticky window of `vis` item rows that keeps `cur` on screen.
# Sets view_start view_end view_above view_below (1-based inclusive).
list_window() {
  local -i n=$1 vis=$2 cur=$3
  view_end=0
  view_above=0
  view_below=0
  (( n < 1 )) && { view_start=1; return }
  (( vis < 1 )) && vis=1
  (( vis > n )) && vis=n
  (( cur < 1 )) && cur=1
  (( cur > n )) && cur=n
  (( view_start < 1 )) && view_start=1
  if (( cur < view_start )); then
    view_start=$cur
  fi
  if (( cur > view_start + vis - 1 )); then
    view_start=$(( cur - vis + 1 ))
  fi
  if (( view_start + vis - 1 > n )); then
    view_start=$(( n - vis + 1 ))
  fi
  (( view_start < 1 )) && view_start=1
  view_end=$(( view_start + vis - 1 ))
  (( view_end > n )) && view_end=n
  view_above=$(( view_start - 1 ))
  view_below=$(( n - view_end ))
}

# Fit list + overflow hints + optional section gap into `body` rows.
# gap_after: emit a blank after this index when the window spans it (0 = none).
plan_list_view() {
  local -i body=$1 n=$2 cur=$3 gap_after=${4:-0}
  local -i hints vis need max_hints
  (( n < 1 || body < 1 )) && {
    view_start=1
    view_end=0
    view_above=0
    view_below=0
    return
  }
  # Keep at least one row for the selected item; hints use leftovers only.
  max_hints=2
  (( max_hints > body - 1 )) && max_hints=$(( body - 1 ))
  (( max_hints < 0 )) && max_hints=0
  for (( hints = 0; hints <= max_hints; hints++ )); do
    vis=$(( body - hints ))
    (( vis < 1 )) && vis=1
    list_window $n $vis $cur
    if (( gap_after > 0 && view_start <= gap_after && view_end > gap_after )); then
      vis=$(( body - hints - 1 ))
      (( vis < 1 )) && vis=1
      list_window $n $vis $cur
    fi
    need=0
    (( view_above > 0 )) && (( need++ ))
    (( view_below > 0 )) && (( need++ ))
    (( need == hints )) && break
  done
  (( hints > max_hints )) && hints=$max_hints
  # Drop hints that did not get a row so they cannot steal the selected item.
  if (( view_above > 0 )); then
    if (( hints > 0 )); then
      (( hints-- ))
    else
      view_above=0
    fi
  fi
  if (( view_below > 0 )); then
    if (( hints > 0 )); then
      (( hints-- ))
    else
      view_below=0
    fi
  fi
}

draw_emit() {
  (( draw_remain > 0 )) || return 1
  print -r -- "$1"
  (( draw_remain-- ))
  return 0
}

draw() {
  local -i cols rows i n w_name=4 w_addr=8 w_user=4 w_stat=4
  local mark line sep addr ime_key
  cols=$(term_cols)
  rows=$(term_lines)
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

  draw_remain=$(( rows > 1 ? rows - 1 : 1 ))
  print -n $'\e[H\e[J'
  ime_key='i 英文'
  ime_enabled || ime_key='i 英文关'
  draw_emit "${c_bold}  局域网 SSH${c_reset}" || return
  draw_emit "${c_dim}  ↑↓/jk 选择   Enter 进入   r 扫描   d 忘掉   ${ime_key}   q 退出${c_reset}" || return
  if [[ -n $notice ]]; then
    draw_emit "  ${c_cyan}${notice}${c_reset}" || return
  else
    draw_emit "" || return
  fi

  draw_emit "  ${c_dim}    #  $(padw 名称 $w_name)  $(padw 地址 $w_addr)  $(padw 用户 $w_user)  $(padw 状态 $w_stat)${c_reset}" || return
  sep=$(printf '%*s' $(( cols - 4 )) '')
  sep=${sep// /─}
  draw_emit "  ${c_dim}${sep}${c_reset}" || return

  local host_end=0
  for (( i = 1; i <= n; i++ )); do
    [[ ${items_kind[$i]} == host ]] && host_end=$i
  done

  plan_list_view $draw_remain $n $cursor $host_end
  (( view_above > 0 )) && draw_emit "  ${c_dim}↑ 还有 ${view_above}${c_reset}"
  for (( i = view_start; i <= view_end; i++ )); do
    if (( i == host_end + 1 && host_end > 0 )); then
      draw_emit "" || break
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
    printf -v line '  %s %2d  %s' "$mark" "$i" "$line"
    draw_emit "$line" || break
  done
  (( view_below > 0 )) && draw_emit "  ${c_dim}↓ 还有 ${view_below}${c_reset}"
}

# WINCH: host draw only while the host picker is on screen.
draw_on_winch() {
  (( host_list_active )) || return 0
  [[ $loading -eq 1 ]] && return 0
  draw
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

# Read one byte into REPLY. Optional timeout in seconds.
# No timeout: block. Tty uses read -k; pipes use sysread.
read_byte() {
  local timeout=${1-}
  local buf=""
  if [[ -n $timeout ]]; then
    read_byte_timeout $timeout
    return $?
  fi
  if [[ -t 0 ]]; then
    IFS= read -rsk1 buf || return 1
    REPLY=$buf
    return 0
  fi
  zmodload zsh/system 2>/dev/null || return 1
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
  local k k2
  PENDING_KEY=""
  while index_prefix_ambiguous "$acc" $max; do
    read_byte_timeout $digit_wait || break
    k=$REPLY
    case $k in
      [0-9]) acc="${acc}${k}" ;;
      $'\n'|$'\r'|' ') break ;;
      $'\e')
        # #262: drain CSI/SGR like read_key so PageUp ESC [ 5 ~ cannot
        # leave 5 as the next num key. Do not replay the tail.
        if read_byte 0.2; then
          k2=$REPLY
          if [[ $k2 == '[' || $k2 == 'O' ]]; then
            if read_byte 0.2; then
              k2=$REPLY
              if [[ $k2 == [0-9] ]]; then
                while read_byte 0.2; do
                  [[ $REPLY == [A-Za-z~] ]] && break
                done
              elif [[ $k2 == '<' ]]; then
                while read_byte 0.2; do
                  [[ $REPLY == M || $REPLY == m ]] && break
                done
              fi
            fi
          fi
        fi
        REPLY=""
        return 0
        ;;
      *) PENDING_KEY=$k; REPLY=""; return 0 ;;
    esac
  done
  REPLY=$acc
}

read_key() {
  local k k2 k3 c key
  if [[ -n $PENDING_KEY ]]; then
    k=$PENDING_KEY
    PENDING_KEY=""
  else
    read_byte || return 1
    k=$REPLY
  fi
  if [[ $k == $'\e' ]]; then
    read_byte 0.2 || { REPLY=esc; return 0 }
    k2=$REPLY
    # lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR).
    if [[ $k2 == $'\r' || $k2 == $'\n' ]]; then
      REPLY=other
      return 0
    fi
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      read_byte 0.2 || { REPLY=esc; return 0 }
      k3=$REPLY
      case $k3 in
        A) REPLY=up ;;
        B) REPLY=down ;;
        C) REPLY=right ;;
        D) REPLY=left ;;
        *) REPLY=other ;;
      esac
      # Drain CSI params so leftover bytes are not a new Esc/q.
      if [[ $k3 == [0-9] ]]; then
        key=$REPLY
        while read_byte 0.2; do
          c=$REPLY
          [[ $c == [A-Za-z~] ]] && break
        done
        REPLY=$key
      elif [[ $k3 == '<' ]]; then
        # #258: SGR mouse ESC [ < … M/m. Host list treats the click as other.
        while read_byte 0.2; do
          c=$REPLY
          [[ $c == M || $c == m ]] && break
        done
        REPLY=other
      fi
      return 0
    fi
    REPLY=esc
    return 0
  fi
  case $k in
    $'\n'|$'\r'|' ') REPLY=enter ;;
    j|J) REPLY=up ;;
    k|K) REPLY=down ;;
    q|Q) REPLY=q ;;
    r|R) REPLY=r ;;
    d|D) REPLY=d ;;
    i|I) REPLY=ime ;;
    g) REPLY=top ;;
    G) REPLY=bottom ;;
    [0-9]) REPLY="num$k" ;;
    *) REPLY=other ;;
  esac
}

# Blocking read. After consecutive EOF/hangup failures, restore tty and
# exit so the main loop cannot spin at 100% CPU (#227).
read_key_or_exit() {
  if read_key; then
    _read_key_fails=0
    return 0
  fi
  (( ++_read_key_fails >= 8 )) || return 1
  restore_tty
  exit 1
}

prompt_username() {
  local user=""
  restore_tty
  print -u2
  while true; do
    print -u2 -n "这台机器的 SSH 用户名（必填）: "
    read -r user </dev/tty || return 1
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

# #280: advertised _ssh._tcp port must reach later ssh (default 22 is a no-op).
apply_ssh_port() {
  local port=${1:-22}
  local -a keep
  local i
  keep=()
  for (( i = 1; i <= ${#SSH_OPTS}; i++ )); do
    if [[ ${SSH_OPTS[$i]} == -o && ${SSH_OPTS[i+1]:-} == Port=* ]]; then
      (( i++ ))
      continue
    fi
    if [[ ${SSH_OPTS[$i]} == -oPort=* ]]; then
      continue
    fi
    keep+=("${SSH_OPTS[$i]}")
  done
  SSH_OPTS=("${keep[@]}")
  if [[ $port == [1-9][0-9](#c0,4) && $port != 22 ]] && (( port <= 65535 )); then
    SSH_OPTS+=(-o "Port=${port}")
  fi
}

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
  local grok="" child_term=${TERM:-}
  grok=$(grok_wrap_bin) || grok=""
  # Apple Terminal is 256-color. A non-256 TERM through wrap/ssh/tmux makes
  # Grok skip its background, so the TUI sits on a white terminal.
  # Ghostty/kitty already advertise color; keep their TERM (#190). Prefix the
  # child only — export would rewrite this lanjump process after SSH returns.
  if [[ $child_term != *256color* && $child_term != *direct* && $child_term != *-kitty && $child_term != *ghostty* && ${TERM_PROGRAM:-} != ghostty ]]; then
    child_term=xterm-256color
  fi
  if [[ ${TERM_PROGRAM:-} == Apple_Terminal ]]; then
    unset COLORTERM
  fi
  # grok wrap must own the real tty. Put lanjump-keys *inside* wrap so
  # Shift+Enter rewrite does not steal /dev/tty (that nesting hung).
  if [[ -n $grok ]]; then
    print -u2 "剪贴板转发已开（grok wrap）。"
    if [[ -n ${LANJUMP_KEYS:-} ]]; then
      TERM=$child_term "$grok" wrap "$LANJUMP_KEYS" ssh "$@"
    else
      TERM=$child_term "$grok" wrap ssh "$@"
    fi
  elif [[ -n ${LANJUMP_KEYS:-} ]]; then
    TERM=$child_term "$LANJUMP_KEYS" ssh "$@"
  else
    TERM=$child_term command ssh "$@"
  fi
}

lan_pub_install_cmd() {
  local pub b64
  pub=$(cat "$KEY.pub")
  # #256: comment may contain '; base64 stays single-quote-safe.
  # #305: if authorized_keys has no trailing newline, >> would glue keys
  # and grep -Fqx would miss an already-installed last line.
  b64=$(print -rn -- "$pub" | base64 | tr -d '\n')
  print -r -- "umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys; pub=\$(printf '%s' '$b64' | base64 -d 2>/dev/null || printf '%s' '$b64' | base64 -D); [ -s ~/.ssh/authorized_keys ] && [ \"\$(tail -c 1 ~/.ssh/authorized_keys | wc -l)\" -eq 0 ] && printf '\\n' >> ~/.ssh/authorized_keys; grep -Fqx \"\$pub\" ~/.ssh/authorized_keys 2>/dev/null || printf '%s\n' \"\$pub\" >> ~/.ssh/authorized_keys"
}

try_ssh() {
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$@" true >/dev/null 2>&1
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

# Stock names exist on every macOS. Ghostty/kitty do not; tmux attach then
# dies with: missing or unsuitable terminal: xterm-ghostty.
terminfo_is_stock() {
  case ${1:-} in
    xterm|xterm-256color|screen|screen-256color|tmux|tmux-256color|vt100|vt102|dumb|ansi|linux)
      return 0
      ;;
  esac
  return 1
}

terminfo_source() {
  local term=${1:-} dir src
  [[ -n $term ]] || return 1
  if src=$(infocmp -x "$term" 2>/dev/null); then
    print -r -- "$src"
    return 0
  fi
  if src=$(infocmp "$term" 2>/dev/null); then
    print -r -- "$src"
    return 0
  fi
  for dir in \
    "${LANJUMP_GHOSTTY_APP:-/Applications/Ghostty.app}/Contents/Resources/terminfo" \
    "$HOME/Applications/Ghostty.app/Contents/Resources/terminfo"
  do
    [[ -d $dir ]] || continue
    if src=$(TERMINFO=$dir infocmp -x "$term" 2>/dev/null); then
      print -r -- "$src"
      return 0
    fi
    if src=$(TERMINFO=$dir infocmp "$term" 2>/dev/null); then
      print -r -- "$src"
      return 0
    fi
  done
  return 1
}

sync_terminfo() {
  local target=$1 user=$2
  local term=${TERM:-} src
  [[ -n $term ]] || return 0
  terminfo_is_stock "$term" && return 0
  src=$(terminfo_source "$term") || return 0
  [[ -n $src ]] || return 0
  print -r -- "$src" | ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" \
    "${user}@${target}" \
    'tmp=$(mktemp "${TMPDIR:-/tmp}/lanjump-terminfo.XXXXXX") && cat >"$tmp" && { tic -x "$tmp" 2>/dev/null || tic "$tmp" 2>/dev/null || true; }; rm -f "$tmp"' \
    || true
}

sync_picker() {
  local target=$1 user=$2
  local incoming_mtime
  # #286: only replace the remote copy when this picker is newer.
  # #310: prefer the picker header stamp over two machines' file mtimes.
  incoming_mtime=$(stat -c %Y "$PICKER" 2>/dev/null) || incoming_mtime=$(stat -f %m "$PICKER" 2>/dev/null) || incoming_mtime=0
  [[ $incoming_mtime == [0-9]## ]] || incoming_mtime=0
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" \
    'dest="$HOME/.local/bin/lanjump-pick"; mkdir -p "$HOME/.local/bin" || exit 1; tmp=$(mktemp "$HOME/.local/bin/.lanjump-pick.XXXXXX") || exit 1; cat >"$tmp" || { rm -f "$tmp"; exit 1; }; keep=0; if [ -f "$dest" ]; then dest_ver=$(awk "/^# lanjump-pick-version / { print \$3; exit }" "$dest"); incoming_ver=$(awk "/^# lanjump-pick-version / { print \$3; exit }" "$tmp"); case $dest_ver in *[!0-9]*) dest_ver= ;; esac; case $incoming_ver in *[!0-9]*) incoming_ver= ;; esac; if [ -n "$dest_ver" ] || [ -n "$incoming_ver" ]; then [ -n "$dest_ver" ] || dest_ver=0; [ -n "$incoming_ver" ] || incoming_ver=0; [ "$dest_ver" -gt "$incoming_ver" ] && keep=1; else dest_mtime=$(stat -c %Y "$dest" 2>/dev/null || stat -f %m "$dest" 2>/dev/null || echo 0); incoming_mtime='"$incoming_mtime"'; case $dest_mtime in *[!0-9]*) dest_mtime=0 ;; esac; [ "$dest_mtime" -gt "$incoming_mtime" ] && keep=1; fi; fi; if [ "$keep" -eq 1 ]; then rm -f "$tmp"; else chmod 755 "$tmp" && mv -f "$tmp" "$dest" || { rm -f "$tmp"; exit 1; }; fi' \
    <"$PICKER" || return $?
  sync_terminfo "$target" "$user"
  return 0
}

connect_item() {
  local i=$1
  local alias=${items_alias[$i]}
  local user=${items_user[$i]}
  local hostname=${items_hostname[$i]}
  local ip=${items_ip[$i]}
  local mac=${items_mac[$i]}
  local port=${items_port[$i]:-22}
  local target

  apply_ssh_port "$port"
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
  upsert_host "$alias" "$user" "$hostname" "$ip" "$mac" "$port"
  mark_last "$alias"
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
  remote_cmd+="; export LANJUMP_PICK_BIN=\$HOME/.local/bin/lanjump-pick"
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
    notice="本机 tmux 选择界面不存在。请重新安装：lanjump upgrade"
    setup_tty
    return
  fi
  mark_last local
  print
  # #212: picker and this host list share a process group. Ctrl+C inside
  # a child shell must not become a deferred host-list `exit 130`.
  trap '' INT
  /bin/zsh "$picker"
  st=$?
  trap 'restore_tty; exit 130' INT
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
  cli_tty_read ans
  setup_tty
  if [[ $ans == y || $ans == Y ]]; then
    forget_saved "${items_saved[$i]}"
    load_hosts
    build_items
    if [[ $(read_last) == "$name" ]]; then
      mark_last local
    fi
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

if [[ ${1:-} == --host-selftest ]]; then
  . "${0:A:h}/lanjump-host-selftest.zsh"
  host_selftest
  exit $?
fi

if [[ ${1:-} == --ssh-selftest ]]; then
  . "${0:A:h}/lanjump-ssh-selftest.zsh"
  ssh_selftest
  exit $?
fi

if [[ ${1:-} == --ime-selftest ]]; then
  . "${0:A:h}/lanjump-ime-selftest.zsh"
  ime_selftest
  exit $?
fi

if [[ ${1:-} == --print-lan ]]; then
  detect_lan
  print -r -- "${IFACE:-}|${MYIP:-}|${PREFIX:-}"
  exit 0
fi

find_host_index() {
  local want=$1 i n=${#h_alias}
  for (( i = 1; i <= n; i++ )); do
    if [[ ${h_alias[$i]} == "$want" ]]; then
      print -r -- $i
      return 0
    fi
  done
  return 1
}

default_cli_host() {
  local last
  last=$(read_last) || last=local
  if [[ -z $last || $last == host ]]; then
    print -r -- local
    return
  fi
  if [[ $last != local ]] && ! find_host_index "$last" >/dev/null; then
    print -r -- local
    return
  fi
  print -r -- "$last"
}

cli_remote_pick() {
  local alias=$1
  shift
  local idx user hostname ip target
  idx=$(find_host_index "$alias") || {
    print -u2 "没有保存的机器「${alias}」。"
    return 1
  }
  user=${h_user[$idx]}
  hostname=${h_hostname[$idx]}
  ip=${h_ip[$idx]}
  apply_ssh_port "${h_port[$idx]:-22}"
  target=$(target_for "$hostname" "$ip")
  if ! setup_access "$user" "$target"; then
    print -u2 "无法登录 ${user}@${target}。"
    return 1
  fi
  if ! sync_picker "$target" "$user"; then
    print -u2 "无法把 tmux 选择界面同步到对方。"
    return 1
  fi
  local remote_cmd
  remote_cmd="export PATH=\"\$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:\$PATH\""
  remote_cmd+="; unset GROK_APPEARANCE LC_GROK_APPEARANCE COLORTERM"
  remote_cmd+="; export TERM_PROGRAM=$(printf %q "${TERM_PROGRAM:-}") TERM_PROGRAM_VERSION=$(printf %q "${TERM_PROGRAM_VERSION:-}")"
  remote_cmd+="; export LANJUMP_PICK_BIN=\$HOME/.local/bin/lanjump-pick"
  remote_cmd+="; exec /bin/zsh \"\$HOME/.local/bin/lanjump-pick\""
  local a
  for a in "$@"; do
    remote_cmd+=" $(printf %q "$a")"
  done
  ssh_tty -t -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" \
    "$remote_cmd"
}

cli_remote_print() {
  local alias=$1
  shift
  local idx user hostname ip target
  idx=$(find_host_index "$alias") || {
    print -u2 "没有保存的机器「${alias}」。"
    return 2
  }
  user=${h_user[$idx]}
  hostname=${h_hostname[$idx]}
  ip=${h_ip[$idx]}
  apply_ssh_port "${h_port[$idx]:-22}"
  target=$(target_for "$hostname" "$ip")
  if ! setup_access "$user" "$target"; then
    print -u2 "无法登录 ${user}@${target}。"
    return 2
  fi
  if ! sync_picker "$target" "$user"; then
    print -u2 "无法把 tmux 选择界面同步到对方。"
    return 2
  fi
  local remote_cmd
  remote_cmd="export PATH=\"\$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:\$PATH\""
  remote_cmd+="; exec /bin/zsh \"\$HOME/.local/bin/lanjump-pick\""
  local a
  for a in "$@"; do
    remote_cmd+=" $(printf %q "$a")"
  done
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "${SSH_OPTS[@]}" "${user}@${target}" \
    "$remote_cmd"
}

cli_pick() {
  local picker
  picker=$(picker_path)
  if [[ -z $picker ]]; then
    print -u2 "本机 tmux 选择界面不存在。请重新安装：lanjump upgrade"
    return 1
  fi
  # Function-level VAR=val is not exported to this child on all zsh.
  LANJUMP_ATTACH_HOST=${LANJUMP_ATTACH_HOST:-} /bin/zsh "$picker" "$@"
}

cli_pick_exec() {
  local picker
  picker=$(picker_path)
  if [[ -z $picker ]]; then
    print -u2 "本机 tmux 选择界面不存在。请重新安装：lanjump upgrade"
    return 1
  fi
  exec /bin/zsh "$picker" "$@"
}

# Same checks as pick.zsh: this Mac can open Ghostty/Terminal windows.
ghostty_restore_available() {
  local_keyboard || return 1
  [[ -d ${LANJUMP_GHOSTTY_APP:-/Applications/Ghostty.app} ]]
}

terminal_restore_available() {
  local_keyboard || return 1
  [[ -d /System/Applications/Utilities/Terminal.app || -d /Applications/Utilities/Terminal.app ]]
}

cli_open_tabs() {
  local host=$1 x
  shift
  local -a ns
  ns=()
  for x in "$@"; do
    [[ -n $x ]] && ns+=("$x")
  done
  (( ${#ns} )) || {
    print -u2 "没有可打开的 session。"
    return 1
  }
  local -a args
  args=(--open-tabs)
  args+=("${ns[@]}")
  if [[ $host == local ]]; then
    cli_pick "${args[@]}"
  elif ghostty_restore_available || terminal_restore_available; then
    # Local Ghostty/Terminal: one window per name, each attach host:name.
    LANJUMP_ATTACH_HOST=$host cli_pick "${args[@]}"
  else
    cli_remote_pick "$host" "${args[@]}"
  fi
}

cli_tmux() {
  local bin
  bin="${commands[tmux]:-/usr/local/bin/tmux}"
  "$bin" "$@"
}

cli_grok_bin() {
  local c
  if [[ -n ${LANJUMP_GROK_BIN:-} ]]; then
    print -r -- "$LANJUMP_GROK_BIN"
    return 0
  fi
  for c in "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok"; do
    [[ -x $c ]] && { print -r -- "$c"; return 0 }
  done
  (( $+commands[grok] )) && { print -r -- "${commands[grok]}"; return 0 }
  print -r -- grok
}

cli_cwd_has_grok_session() {
  local cwd=$1 enc dir
  [[ -n $cwd ]] || return 1
  enc=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$cwd" 2>/dev/null) || return 1
  dir="$HOME/.grok/sessions/$enc"
  [[ -d $dir ]]
}

cli_auto_new_session() {
  local created
  created=$(cli_tmux new-session -d -P -F '#{session_name}' -c "$PWD" 2>/dev/null) || created=
  created=${created%%$'\n'*}
  [[ -n $created ]] || {
    print -u2 "无法新建 session。"
    return 1
  }
  print -r -- "$created"
}

cli_start_grok() {
  local host=$1 session=$2
  local live pane_cwd bin line target grok_pane pane_line pane_id pane_cmd
  local -a panes
  [[ -n $session ]] || return 1
  if [[ $host != local ]]; then
    cli_remote_print "$host" --start-grok "$session"
    return $?
  fi
  target="=${session}:."
  live=$(cli_tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || true)
  live=${live##*/}
  if [[ $live == grok || $live == grok-* ]]; then
    return 0
  fi
  grok_pane=
  panes=("${(@f)$(cli_tmux list-panes -s -t "=$session" -F $'#{pane_id}\t#{pane_current_command}' 2>/dev/null)}")
  for pane_line in "${panes[@]}"; do
    [[ -n $pane_line ]] || continue
    pane_id=${pane_line%%$'\t'*}
    pane_cmd=${pane_line#*$'\t'}
    pane_cmd=${pane_cmd##*/}
    if [[ $pane_cmd == grok || $pane_cmd == grok-* ]]; then
      grok_pane=$pane_id
      break
    fi
  done
  if [[ -n $grok_pane ]]; then
    cli_tmux select-window -t "$grok_pane" 2>/dev/null || true
    cli_tmux select-pane -t "$grok_pane" 2>/dev/null || true
    return 0
  fi
  # Unreadable command is not an idle shell; do not send-keys into a live grok.
  [[ -n $live ]] || return 0
  case $live in
    zsh|bash|sh|fish|dash|login) ;;
    *) return 0 ;;
  esac
  pane_cwd=$(cli_tmux display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null || true)
  bin=$(cli_grok_bin)
  if cli_cwd_has_grok_session "$pane_cwd"; then
    line="$bin -c"
  else
    line="$bin"
  fi
  cli_tmux send-keys -t "$target" -- "$line" Enter
}

cli_ask_create() {
  local ans
  print "没有 session「${1}」。"
  print -n "要新建并打开吗？（回车=是，其他键=否） "
  read -r ans </dev/tty || ans=
  [[ -z $ans ]]
}

cli_ask_pin() {
  local pinans
  print -n "常驻（y=是，回车=否）: "
  read -r pinans </dev/tty || pinans=
  [[ $pinans == y || $pinans == Y ]]
}

cli_pin_session() {
  local host=$1 session=$2 out
  local -a lines
  REPLY=$session
  if [[ $host == local ]]; then
    out=$(cli_pick --pin-session "$session") || return $?
  else
    out=$(cli_remote_print "$host" --pin-session "$session") || return $?
  fi
  lines=("${(@f)out}")
  [[ -n ${lines[-1]:-} ]] && REPLY=${lines[-1]}
}

cli_recent_draw() {
  local -i i n=${#cli_recent_names}
  print -n $'\e[H\e[J'
  print -r -- "最近 session"
  print
  for (( i = 1; i <= n; i++ )); do
    if (( i == cli_recent_cur )); then
      print -r -- "> ${cli_recent_names[i]}"
    else
      print -r -- "  ${cli_recent_names[i]}"
    fi
  done
  print
  print -r -- "j/k 选择  Enter 进入  q 取消"
}

cli_recent_select() {
  local -i n
  local chosen=
  cli_recent_names=("$@")
  cli_recent_cur=1
  n=${#cli_recent_names}
  (( n )) || return 1
  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    print -u2 "需要交互式终端。"
    return 1
  fi
  {
    stty_orig=$(stty -g </dev/tty 2>/dev/null) || stty_orig=
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
    print -n $'\e[?25l'
    trap cli_recent_draw WINCH
    while true; do
      cli_recent_draw
      read_key_or_exit || continue
      case $REPLY in
        up)
          (( cli_recent_cur-- ))
          (( cli_recent_cur < 1 )) && cli_recent_cur=$n
          ;;
        down)
          (( cli_recent_cur++ ))
          (( cli_recent_cur > n )) && cli_recent_cur=1
          ;;
        enter)
          chosen=${cli_recent_names[cli_recent_cur]}
          break
          ;;
        q|esc)
          chosen=
          break
          ;;
      esac
    done
  } always {
    trap - WINCH
    print -n $'\e[?25h'
    [[ -n $stty_orig ]] && stty "$stty_orig" </dev/tty 2>/dev/null
  } </dev/tty >/dev/tty
  [[ -n $chosen ]] || return 1
  print -r -- "$chosen"
}

cli_has_session() {
  local host=$1 session=$2
  if [[ $host == local ]]; then
    cli_pick --has-session "$session"
  else
    cli_remote_print "$host" --has-session "$session"
  fi
}

cli_new_session() {
  local host=$1 session=$2
  if [[ $host == local ]]; then
    cli_pick --new-session "$session"
  else
    cli_remote_print "$host" --new-session "$session"
  fi
}

# Colon/dot collide with CLI host:session. Same rule as picker n / --new-session.
session_name_invalid() {
  [[ -n ${1:-} && ( $1 == *:* || $1 == *.* ) ]] || return 1
  print -r -- "名称不能包含冒号或点。"
  return 0
}

cli_list_names() {
  local host=$1 flag=$2
  if [[ $host == local ]]; then
    cli_pick "$flag"
  else
    cli_remote_print "$host" "$flag"
  fi
}

cli_attach_one() {
  local host=$1 session=$2 shell=$3
  local want_new=${4:-0}
  local -a args
  if (( want_new )); then
    cli_open_tabs "$host" "$session"
    return
  fi
  args=(--attach)
  (( shell )) && args+=(--shell)
  args+=("$session")
  if [[ $host == local ]]; then
    cli_pick_exec "${args[@]}"
  else
    cli_remote_pick "$host" "${args[@]}"
  fi
}

cli_usage() {
  print -r -- '用法：lanjump [命令]'
  print
  print -r -- '  （无命令）        打开主机列表，再选 tmux session'
  print -r -- '  help              显示本说明'
  print -r -- '  list [机器]       列出 session'
  print -r -- '  last [机器]       最近 5 个 session，选一个进入'
  print -r -- '  go [机器:]名字 [--grok]  打开；不写名字则本机自动新建；--grok 再开 grok'
  print -r -- '  work [机器]       打开近 24 小时占用过的 session（不含常驻）'
  print -r -- '  pins [机器]       打开常驻'
  print -r -- '  upgrade           升级到最新版本'
  print -r -- '  update            同 upgrade'
  print
  print -r -- '机器省略时用上次进入的那台。'
  print -r -- '列表 Enter 当前窗口进入，t 新窗口。新窗口用 Ghostty 还是系统终端可在列表按 , 设置。'
  print -r -- '主机列表按 i 开关打开时切英文输入法（默认开；手机 SSH 进来时不切）。'
}

# Empty / y / Y / 是 = create in current window. t/T = create in a new window.
cli_confirm_create() {
  local ans=$1
  CREATE_WANT_NEW=0
  [[ $ans == t || $ans == T ]] && CREATE_WANT_NEW=1
  [[ -z $ans || $ans == y || $ans == Y || $ans == 是 || $ans == t || $ans == T ]]
}

cli_tty_read() {
  local _cli_tty_name=$1
  local _cli_tty_val=
  read -r _cli_tty_val </dev/tty || _cli_tty_val=
  printf -v $_cli_tty_name '%s' "$_cli_tty_val"
}

cli_dispatch() {
  local cmd=$1
  shift
  local host session spec ans pinans
  local -i shell=0 pin=0 want_grok=0 has_st=0
  local -a extra names
  extra=()
  while (( $# )); do
    case $1 in
      -h|--help)
        cli_usage
        return 0
        ;;
      --shell) shell=1 ;;
      --grok) want_grok=1 ;;
      *) extra+=("$1") ;;
    esac
    shift
  done
  host=$(default_cli_host)
  session=
  case $cmd in
    list|ls|last|work|pins)
      if (( ${#extra} )); then
        host=${extra[1]}
      fi
      ;;
    *)
      if (( ${#extra} )); then
        spec=${extra[1]}
        if [[ $spec == *:* ]]; then
          host=${spec%%:*}
          session=${spec#*:}
        else
          session=$spec
          # #85: unprefixed attach is local; go still follows last host.
          if [[ $cmd == attach ]]; then
            host=local
          fi
        fi
      fi
      ;;
  esac
  [[ -n $host ]] || host=local
  case $cmd in
    attach)
      if [[ -z $session ]]; then
        print -u2 "用法：lanjump attach [--shell] <session>"
        return 1
      fi
      mark_last "$host"
      cli_attach_one "$host" "$session" $shell || return 1
      mark_last "$host"
      ;;
    go)
      if [[ $spec == *:* && -z $session ]]; then
        print -u2 "用法：lanjump go [机器:]名字"
        return 1
      fi
      if [[ -z $session ]]; then
        session=$(cli_auto_new_session) || return 1
        if (( want_grok )); then
          cli_start_grok local "$session" || return 1
        fi
        # Local attach execs the picker; write last_target first.
        # --grok already started/selected grok; --shell skips maybe_resume.
        mark_last local
        cli_attach_one local "$session" $(( want_grok || shell ))
        return
      fi
      CREATE_WANT_NEW=0
      has_st=0
      cli_has_session "$host" "$session" || has_st=$?
      if (( has_st )); then
        # #175: remote connect/login/sync failure is not a missing session.
        if [[ $host != local ]] && (( has_st != 1 )); then
          return $has_st
        fi
        # #183: colon/dot names cannot be created; do not ask first.
        if session_name_invalid "$session"; then
          return 1
        fi
        print "没有 session「${session}」。"
        print -n "要新建并打开吗？（回车或 y=当前窗口，t=新窗口，其他=否） "
        cli_tty_read ans
        if ! cli_confirm_create "$ans"; then
          return 1
        fi
        cli_new_session "$host" "$session" || return 1
      fi
      if (( want_grok )); then
        cli_start_grok "$host" "$session" || return 1
      fi
      # Mark before attach: remote SSH blocks until it returns.
      # --grok already started/selected grok; --shell skips maybe_resume.
      mark_last "$host"
      cli_attach_one "$host" "$session" $(( want_grok || shell )) ${CREATE_WANT_NEW:-0} || return 1
      mark_last "$host"
      ;;
    work)
      names=("${(@f)$(cli_list_names "$host" --print-workspace)}") || return 1
      # Mark before open: current-window exec-attach never returns.
      mark_last "$host"
      cli_open_tabs "$host" "${names[@]}" || return 1
      mark_last "$host"
      ;;
    pins)
      names=("${(@f)$(cli_list_names "$host" --print-pinned)}") || return 1
      # Mark before open: current-window exec-attach never returns.
      mark_last "$host"
      cli_open_tabs "$host" "${names[@]}" || return 1
      mark_last "$host"
      ;;
    list|ls)
      cli_list_names "$host" --print-sessions || return 1
      ;;
    last)
      has_st=0
      names=("${(@f)$(cli_list_names "$host" --print-recent)}") || has_st=$?
      # #178: connect/login/sync/unknown is 2. #182: picker empty list is 1.
      (( has_st && has_st != 1 )) && return $has_st
      names=("${(@)names:#}")
      if (( ! ${#names} )); then
        print -u2 "没有最近的 session。"
        return 1
      fi
      session=$(cli_recent_select "${names[@]}") || return 1
      # Mark before attach: remote SSH blocks until it returns.
      # --shell skips maybe_resume, same as go/attach.
      mark_last "$host"
      cli_attach_one "$host" "$session" $shell || return 1
      mark_last "$host"
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ ${1:-} == --cli-selftest ]]; then
  . "${0:A:h}/lanjump-cli-selftest.zsh"
  exit $?
fi

if [[ ${1:-} == help || ${1:-} == -h || ${1:-} == --help ]]; then
  cli_usage
  exit 0
fi

if [[ ${1:-} == attach || ${1:-} == go || ${1:-} == work || ${1:-} == pins || ${1:-} == list || ${1:-} == ls || ${1:-} == last ]]; then
  if [[ ${2:-} == --help || ${2:-} == -h ]]; then
    cli_usage
    exit 0
  fi
  ensure_setup
  load_hosts
  find_lanjump_keys || true
  cli_dispatch "$@"
  exit $?
fi

if [[ -n ${1:-} ]]; then
  print -u2 "未知命令：${1}"
  cli_usage >&2
  exit 1
fi

ensure_setup
detect_lan
load_hosts
build_items
apply_last_cursor

if [[ ! -t 0 || ! -t 1 ]]; then
  print "需要交互式终端。请运行 lanjump，或双击桌面上的 启动 lanjump。"
  exit 1
fi

setup_tty
maybe_switch_ime
# No saved remotes: auto-scan unless last used this Mac.
if (( ${#h_alias} == 0 )) && [[ $(read_last) != local ]]; then
  do_scan
  apply_last_cursor
fi
trap draw_on_winch WINCH
draw

while true; do
  read_key_or_exit || continue
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
    ime)
      toggle_ime
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
