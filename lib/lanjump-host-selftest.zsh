# Sourced by lanjump.zsh --host-selftest.
# Expects draw.

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

  if (( fails )); then
    print -u2 "host-selftest: $fails failed"
    return 1
  fi
  print "ok host"
  return 0
}
