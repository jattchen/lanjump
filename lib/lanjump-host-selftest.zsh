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

  # #90: forgetting the last remote must not leave last_target on that alias.
  local orig_home=$HOME
  local real_ssh="$orig_home/.ssh/config"
  local real_last="$orig_home/Library/Application Support/lanjump/last_target"
  local tmpdir forget_i j
  local saved_ssh saved_hosts saved_key saved_home saved_last_file
  local -a saved_alias saved_user saved_hostname saved_ip saved_mac saved_last
  tmpdir=$(mktemp -d) || return 1
  saved_ssh=$SSH_CONFIG
  saved_hosts=$HOSTS_FILE
  saved_key=$KEY
  saved_home=$HOME
  saved_last_file=$LAST_FILE
  saved_alias=("${h_alias[@]}")
  saved_user=("${h_user[@]}")
  saved_hostname=("${h_hostname[@]}")
  saved_ip=("${h_ip[@]}")
  saved_mac=("${h_mac[@]}")
  saved_last=("${h_last[@]}")
  SSH_CONFIG="$tmpdir/config"
  HOSTS_FILE="$tmpdir/hosts"
  LAST_FILE="$tmpdir/last_target"
  KEY="$tmpdir/id_ed25519_lanjump"
  HOME=$tmpdir
  restore_tty() { : }
  setup_tty() { : }
  if [[ $SSH_CONFIG == "$real_ssh" || $LAST_FILE == "$real_last" || $HOSTS_FILE == "$orig_home/Library/Application Support/lanjump/hosts" ]]; then
    print -u2 "FAIL host/forget-last refusing to use real SSH/hosts/last paths"
    (( fails++ ))
  else
    : >"$SSH_CONFIG"
    print -r -- 'office|mac|office.local|10.0.0.8||1' >"$HOSTS_FILE"
    print -r -- 'studio|mac|studio.local|10.0.0.2||2' >>"$HOSTS_FILE"
    print -r -- office >"$LAST_FILE"
    load_hosts
    build_items
    forget_i=
    for (( j = 1; j <= ${#items_kind}; j++ )); do
      if [[ ${items_kind[$j]} == host && ${items_alias[$j]} == office ]]; then
        forget_i=$j
        break
      fi
    done
    if [[ -z $forget_i ]]; then
      print -u2 "FAIL host/forget-last missing office item"
      (( fails++ ))
    else
      host_tty_read() { printf -v $1 'y' }
      forget_item $forget_i >/dev/null
      expect host/forget-last-cleared local "$(read_last)"
      if [[ $notice != *已忘掉*office* ]]; then
        print -u2 "FAIL host/forget-last-notice got=$(printf %q "$notice")"
        (( fails++ ))
      fi
    fi

    print -r -- 'office|mac|office.local|10.0.0.8||1' >"$HOSTS_FILE"
    print -r -- 'studio|mac|studio.local|10.0.0.2||2' >>"$HOSTS_FILE"
    print -r -- studio >"$LAST_FILE"
    load_hosts
    build_items
    forget_i=
    for (( j = 1; j <= ${#items_kind}; j++ )); do
      if [[ ${items_kind[$j]} == host && ${items_alias[$j]} == office ]]; then
        forget_i=$j
        break
      fi
    done
    host_tty_read() { printf -v $1 'y' }
    forget_item $forget_i >/dev/null
    expect host/forget-other-keeps-last studio "$(read_last)"

    print -r -- 'office|mac|office.local|10.0.0.8||1' >"$HOSTS_FILE"
    print -r -- office >"$LAST_FILE"
    load_hosts
    build_items
    forget_i=
    for (( j = 1; j <= ${#items_kind}; j++ )); do
      if [[ ${items_kind[$j]} == host && ${items_alias[$j]} == office ]]; then
        forget_i=$j
        break
      fi
    done
    host_tty_read() { printf -v $1 'n' }
    forget_item $forget_i >/dev/null
    expect host/forget-cancel-keeps-last office "$(read_last)"
  fi
  SSH_CONFIG=$saved_ssh
  HOSTS_FILE=$saved_hosts
  KEY=$saved_key
  HOME=$saved_home
  LAST_FILE=$saved_last_file
  h_alias=("${saved_alias[@]}")
  h_user=("${saved_user[@]}")
  h_hostname=("${saved_hostname[@]}")
  h_ip=("${saved_ip[@]}")
  h_mac=("${saved_mac[@]}")
  h_last=("${saved_last[@]}")
  rm -rf "$tmpdir"

  if (( fails )); then
    print -u2 "host-selftest: $fails failed"
    return 1
  fi
  print "ok host"
  return 0
}
