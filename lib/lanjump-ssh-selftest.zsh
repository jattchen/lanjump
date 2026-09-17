# Sourced by lanjump.zsh --ssh-selftest.
# Expects strip_ssh_block, remove_ssh_config, upsert_ssh_config, forget_saved,
# persist_scan_hosts, ssh_id_from_alias, lan_pub_install_cmd. Uses temp files
# only; never the real ~/.ssh/config.

ssh_selftest() {
  local -i fails=0
  local orig_home=$HOME
  local real_ssh="$orig_home/.ssh/config"
  local real_hash="" new_hash=""
  local tmpdir ssh_got saved_ssh saved_hosts saved_key saved_home
  local -a saved_alias saved_user saved_hostname saved_ip saved_mac saved_ssh_id saved_last

  tmpdir=$(mktemp -d) || return 1
  [[ -f $real_ssh ]] && real_hash=$(shasum -a 256 "$real_ssh")

  saved_ssh=$SSH_CONFIG
  saved_hosts=$HOSTS_FILE
  saved_key=$KEY
  saved_home=$HOME
  saved_alias=("${h_alias[@]}")
  saved_user=("${h_user[@]}")
  saved_hostname=("${h_hostname[@]}")
  saved_ip=("${h_ip[@]}")
  saved_mac=("${h_mac[@]}")
  saved_ssh_id=("${h_ssh_id[@]}")
  saved_last=("${h_last[@]}")

  SSH_CONFIG="$tmpdir/config"
  HOSTS_FILE="$tmpdir/hosts"
  KEY="$tmpdir/id_ed25519_lanjump"
  HOME=$tmpdir

  if [[ $SSH_CONFIG == "$real_ssh" || $HOSTS_FILE == "$orig_home/Library/Application Support/lanjump/hosts" ]]; then
    print -u2 "FAIL ssh/refuse refusing to use real SSH/hosts paths"
    (( fails++ ))
    SSH_CONFIG=$saved_ssh
    HOSTS_FILE=$saved_hosts
    KEY=$saved_key
    HOME=$saved_home
    rm -rf "$tmpdir"
    return 1
  fi

  expect_contains() {
    local label=$1 needle=$2 hay=$3
    if [[ $hay != *"$needle"* ]]; then
      print -u2 "FAIL $label missing $(printf %q "$needle") got=$(printf %q "$hay")"
      (( fails++ ))
    fi
  }
  expect_absent() {
    local label=$1 needle=$2 hay=$3
    if [[ $hay == *"$needle"* ]]; then
      print -u2 "FAIL $label has $(printf %q "$needle") got=$(printf %q "$hay")"
      (( fails++ ))
    fi
  }
  read_ssh() {
    ssh_got=$(<"$SSH_CONFIG")
  }

  # #63: BEGIN without END, then another Host — remove must keep the later Host.
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host office
  HostName 10.0.0.8
  User mac
Host keep-me
  HostName other.local
  User other
EOF
  remove_ssh_config lanjump-office
  read_ssh
  expect_contains ssh/missing-end/keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/missing-end/keep-hostname 'HostName other.local' "$ssh_got"
  expect_contains ssh/missing-end/keep-user 'User other' "$ssh_got"

  # Same mutilated config via forget_saved (d 忘掉).
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host office
  HostName 10.0.0.8
  User mac
Host keep-me
  HostName other.local
  User other
EOF
  h_alias=(office)
  h_user=(mac)
  h_hostname=(office.local)
  h_ip=(10.0.0.8)
  h_mac=('')
  h_last=('0')
  forget_saved 1
  read_ssh
  expect_contains ssh/forget-missing-end/keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/forget-missing-end/keep-hostname 'HostName other.local' "$ssh_got"
  expect_contains ssh/forget-missing-end/keep-user 'User other' "$ssh_got"

  # Reconnect/upsert must not wipe the later Host either.
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host office
  HostName 10.0.0.8
  User mac
Host keep-me
  HostName other.local
  User other
EOF
  upsert_ssh_config lanjump-office mac 10.0.0.8
  read_ssh
  expect_contains ssh/upsert-missing-end/keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/upsert-missing-end/keep-hostname 'HostName other.local' "$ssh_got"
  expect_contains ssh/upsert-missing-end/keep-user 'User other' "$ssh_got"

  # #252: missing END + same Host id — upsert must not leave the old HostName
  # as OpenSSH's first match (append-after-failed-strip does).
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host lanjump-office
  HostName 10.0.0.8
  User mac
Host keep-me
  HostName other.local
  User other
EOF
  upsert_ssh_config lanjump-office mac 10.0.0.99
  read_ssh
  expect_contains ssh/upsert-missing-end/hostname-keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/upsert-missing-end/hostname-keep-hostname 'HostName other.local' "$ssh_got"
  expect_contains ssh/upsert-missing-end/hostname-keep-user 'User other' "$ssh_got"
  local resolved_hn
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.99 ]]; then
    print -u2 "FAIL ssh/upsert-missing-end/hostname-wins want=10.0.0.99 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi

  # #272: happy-path upsert must replace dest in one write. strip-then-append
  # leaves a window with no Host (crash / concurrent ssh).
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host lanjump-office
  HostName 10.0.0.8
  User mac
# END LANJUMP lanjump-office
Host keep-me
  HostName other.local
  User other
EOF
  local ssh272_old ssh272_mid
  local -i ssh272_hole=0
  ssh272_old=$(<"$SSH_CONFIG")
  mv() {
    command mv "$@"
    if [[ ${@[-1]} == "$SSH_CONFIG" ]]; then
      ssh272_mid=$(<"$SSH_CONFIG")
      if [[ $ssh272_mid != "$ssh272_old" && $ssh272_mid != *'Host lanjump-office'* ]]; then
        ssh272_hole=1
      fi
    fi
  }
  print() {
    builtin print "$@"
    ssh272_mid=$(<"$SSH_CONFIG")
    if [[ $ssh272_mid != "$ssh272_old" && $ssh272_mid != *'Host lanjump-office'* ]]; then
      ssh272_hole=1
    fi
  }
  upsert_ssh_config lanjump-office mac 10.0.0.99
  unfunction print mv
  if (( ssh272_hole )); then
    print -u2 "FAIL ssh/upsert-atomic dest lacked Host mid-write"
    (( fails++ ))
  fi
  read_ssh
  expect_contains ssh/upsert-atomic/keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/upsert-atomic/keep-hostname 'HostName other.local' "$ssh_got"
  expect_contains ssh/upsert-atomic/keep-user 'User other' "$ssh_got"
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.99 ]]; then
    print -u2 "FAIL ssh/upsert-atomic/hostname-wins want=10.0.0.99 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi

  # #274: dest is a symlink (dotfiles). Upsert must update Host and leave the link.
  mkdir -p "$tmpdir/dotfiles"
  cat >"$tmpdir/dotfiles/ssh_config" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host lanjump-office
  HostName 10.0.0.8
  User mac
# END LANJUMP lanjump-office
EOF
  rm -f "$SSH_CONFIG"
  ln -s "$tmpdir/dotfiles/ssh_config" "$SSH_CONFIG"
  upsert_ssh_config lanjump-office mac 10.0.0.99
  if [[ ! -L $SSH_CONFIG ]]; then
    print -u2 "FAIL ssh/upsert-symlink dest is no longer a symlink"
    (( fails++ ))
  fi
  local symlink_want="$tmpdir/dotfiles/ssh_config"
  if [[ ${SSH_CONFIG:A} != "${symlink_want:A}" ]]; then
    print -u2 "FAIL ssh/upsert-symlink target changed want=$(printf %q "${symlink_want:A}") got=$(printf %q "${SSH_CONFIG:A}")"
    (( fails++ ))
  fi
  read_ssh
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.99 ]]; then
    print -u2 "FAIL ssh/upsert-symlink/hostname-wins want=10.0.0.99 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi
  rm -f "$SSH_CONFIG"

  # #340: first-write LANJUMP block must win over a preceding Host *
  # (OpenSSH first-match). Appending after Host * User/Port leaves
  # ssh -G showing the global values.
  cat >"$SSH_CONFIG" <<'EOF'
Host *
  User global
  Port 2222
EOF
  upsert_ssh_config lanjump-office mac 10.0.0.8 2200
  read_ssh
  expect_contains ssh/host-star-order/keep-star 'Host *' "$ssh_got"
  expect_contains ssh/host-star-order/keep-global 'User global' "$ssh_got"
  local resolved_user resolved_port
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  resolved_user=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="user"{print $2; exit}')
  resolved_port=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="port"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.8 ]]; then
    print -u2 "FAIL ssh/host-star-order/hostname want=10.0.0.8 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi
  if [[ $resolved_user != mac ]]; then
    print -u2 "FAIL ssh/host-star-order/user want=mac got=$(printf %q "$resolved_user")"
    (( fails++ ))
  fi
  if [[ $resolved_port != 2200 ]]; then
    print -u2 "FAIL ssh/host-star-order/port want=2200 got=$(printf %q "$resolved_port")"
    (( fails++ ))
  fi

  # #340: complete-block reconnect must also beat a preceding Host *.
  # In-place rewrite / END{emit()} would keep the LANJUMP Host at the
  # end; ssh -G would still show global/2222 after save.
  cat >"$SSH_CONFIG" <<'EOF'
Host *
  User global
  Port 2222
# BEGIN LANJUMP lanjump-office
Host lanjump-office
  HostName 10.0.0.8
  Port 2200
  User old
  IdentityFile /tmp/id_ed25519_lanjump
  IdentitiesOnly yes
# END LANJUMP lanjump-office
EOF
  upsert_ssh_config lanjump-office mac 10.0.0.8 2200
  read_ssh
  expect_contains ssh/host-star-complete/keep-star 'Host *' "$ssh_got"
  expect_contains ssh/host-star-complete/keep-global 'User global' "$ssh_got"
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  resolved_user=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="user"{print $2; exit}')
  resolved_port=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="port"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.8 ]]; then
    print -u2 "FAIL ssh/host-star-complete/hostname want=10.0.0.8 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi
  if [[ $resolved_user != mac ]]; then
    print -u2 "FAIL ssh/host-star-complete/user want=mac got=$(printf %q "$resolved_user")"
    (( fails++ ))
  fi
  if [[ $resolved_port != 2200 ]]; then
    print -u2 "FAIL ssh/host-star-complete/port want=2200 got=$(printf %q "$resolved_port")"
    (( fails++ ))
  fi
  if [[ $ssh_got != $'# BEGIN LANJUMP lanjump-office'*'Host *'* ]]; then
    print -u2 "FAIL ssh/host-star-complete/prepend LANJUMP must precede Host * got=$(printf %q "$ssh_got")"
    (( fails++ ))
  fi

  # Happy path: a complete block is still removed; later Host stays.
  cat >"$SSH_CONFIG" <<'EOF'
# BEGIN LANJUMP lanjump-office
Host office
  HostName 10.0.0.8
  User mac
# END LANJUMP lanjump-office
Host keep-me
  HostName other.local
  User other
EOF
  remove_ssh_config lanjump-office
  read_ssh
  expect_absent ssh/complete/begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_absent ssh/complete/end '# END LANJUMP lanjump-office' "$ssh_got"
  expect_absent ssh/complete/old-host $'Host office\n  HostName 10.0.0.8' "$ssh_got"
  expect_contains ssh/complete/keep-host 'Host keep-me' "$ssh_got"
  expect_contains ssh/complete/keep-hostname 'HostName other.local' "$ssh_got"

  # #285: CJK aliases must not share one SSH Host id. 书房/客厅 both
  # sanitized to lanjump-host; later connect overwrote HostName and
  # forgetting either deleted the shared block.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host '书房' mac study.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  upsert_host '客厅' mac living.local 10.0.0.9 'aa:bb:cc:dd:ee:02'
  read_ssh
  expect_contains ssh/cjk-id/study-hn 'HostName study.local' "$ssh_got"
  expect_contains ssh/cjk-id/living-hn 'HostName living.local' "$ssh_got"
  forget_saved 1
  read_ssh
  expect_absent ssh/cjk-id/forget-study 'HostName study.local' "$ssh_got"
  expect_contains ssh/cjk-id/forget-living 'HostName living.local' "$ssh_got"

  # #313: ASCII near-names that slug to the same id must not share one
  # live SSH Host block. office mac / office-mac both became
  # lanjump-office-mac and the later HostName won.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host 'office mac' mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  upsert_host 'office-mac' mac studio.local 10.0.0.9 'aa:bb:cc:dd:ee:02'
  read_ssh
  expect_contains ssh/ascii-id/office-hn 'HostName office.local' "$ssh_got"
  expect_contains ssh/ascii-id/studio-hn 'HostName studio.local' "$ssh_got"
  forget_saved 1
  read_ssh
  expect_absent ssh/ascii-id/forget-office 'HostName office.local' "$ssh_got"
  expect_contains ssh/ascii-id/forget-studio 'HostName studio.local' "$ssh_got"

  # #313: rename / id change must drop the previous BEGIN/END pair.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  read_ssh
  expect_contains ssh/rename-id/old-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  upsert_host work mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  read_ssh
  expect_absent ssh/rename-id/stale-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_absent ssh/rename-id/stale-end '# END LANJUMP lanjump-office' "$ssh_got"
  expect_contains ssh/rename-id/new-begin '# BEGIN LANJUMP lanjump-work' "$ssh_got"
  expect_contains ssh/rename-id/new-hn 'HostName office.local' "$ssh_got"

  # #336: another window renamed the alias (new ssh id on disk). Forget
  # with the stale in-memory index/id must still drop the current block.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  if [[ ${h_alias[1]} != office ]]; then
    print -u2 "FAIL ssh/forget-renamed/memory-office want=office got=$(printf %q "${h_alias[1]}")"
    (( fails++ ))
  fi
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$tmpdir")"
    print -r -- "HOSTS_FILE=$(printf %q "$HOSTS_FILE")"
    print -r -- "SSH_CONFIG=$(printf %q "$SSH_CONFIG")"
    print -r -- "KEY=$(printf %q "$KEY")"
    print -r -- 'typeset -a h_alias h_user h_hostname h_ip h_mac h_port h_ssh_id h_last'
    local ssh336_fn
    for ssh336_fn in ssh_id_tag ssh_id_from_alias ssh_id_taken alloc_ssh_id \
      load_hosts replace_file_atomic save_hosts find_saved upsert_host \
      strip_ssh_block remove_ssh_config replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$ssh336_fn]} )) && functions "$ssh336_fn"
    done
    print -r -- "upsert_host work mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'"
  } >"$tmpdir/child-336.zsh"
  /bin/zsh "$tmpdir/child-336.zsh"
  if [[ ${h_alias[1]} != office ]]; then
    print -u2 "FAIL ssh/forget-renamed/stale-memory want=office got=$(printf %q "${h_alias[1]}")"
    (( fails++ ))
  fi
  if [[ ${h_ssh_id[1]} != lanjump-office ]]; then
    print -u2 "FAIL ssh/forget-renamed/stale-id want=lanjump-office got=$(printf %q "${h_ssh_id[1]}")"
    (( fails++ ))
  fi
  read_ssh
  expect_contains ssh/forget-renamed/disk-new-begin '# BEGIN LANJUMP lanjump-work' "$ssh_got"
  expect_absent ssh/forget-renamed/disk-old-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  forget_saved 1
  load_hosts
  if (( ${#h_alias} )); then
    print -u2 "FAIL ssh/forget-renamed leftover hosts aliases=$(printf %q "${h_alias[*]}")"
    (( fails++ ))
  fi
  read_ssh
  expect_absent ssh/forget-renamed/leftover-begin '# BEGIN LANJUMP lanjump-work' "$ssh_got"
  expect_absent ssh/forget-renamed/leftover-end '# END LANJUMP lanjump-work' "$ssh_got"
  expect_absent ssh/forget-renamed/leftover-host 'Host lanjump-work' "$ssh_got"

  # #337: SSH write failure must not commit a hosts row / ssh_id as saved.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  functions -c upsert_ssh_config _ssh337_upsert
  upsert_ssh_config() { return 1 }
  if upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'; then
    print -u2 "FAIL ssh/write-fail-hosts upsert_host returned 0 after SSH write failure"
    (( fails++ ))
  fi
  functions -c _ssh337_upsert upsert_ssh_config
  unfunction _ssh337_upsert
  local ssh337_disk
  ssh337_disk=$(<"$HOSTS_FILE")
  if [[ $ssh337_disk == *office.local* || $ssh337_disk == *lanjump-office* ]]; then
    print -u2 "FAIL ssh/write-fail-hosts persisted hosts row got=$(printf %q "$ssh337_disk")"
    (( fails++ ))
  fi
  load_hosts
  if (( ${#h_alias} )); then
    print -u2 "FAIL ssh/write-fail-hosts leftover hosts aliases=$(printf %q "${h_alias[*]}") ssh_id=$(printf %q "${h_ssh_id[*]}")"
    (( fails++ ))
  fi

  # #359: hosts write failure after SSH upsert must roll back the new
  # SSH block, fail upsert_host, and stop connect from entering a session.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  functions -c save_hosts _ssh359_save
  save_hosts() { return 1 }
  if upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'; then
    print -u2 "FAIL ssh/hosts-write-fail upsert_host returned 0 after hosts write failure"
    (( fails++ ))
  fi
  functions -c _ssh359_save save_hosts
  unfunction _ssh359_save
  local ssh359_disk
  ssh359_disk=$(<"$HOSTS_FILE")
  if [[ $ssh359_disk == *office.local* || $ssh359_disk == *lanjump-office* ]]; then
    print -u2 "FAIL ssh/hosts-write-fail persisted hosts row got=$(printf %q "$ssh359_disk")"
    (( fails++ ))
  fi
  read_ssh
  expect_absent ssh/hosts-write-fail/ssh-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_absent ssh/hosts-write-fail/ssh-host 'Host lanjump-office' "$ssh_got"
  expect_absent ssh/hosts-write-fail/ssh-hn 'HostName office.local' "$ssh_got"
  load_hosts
  if (( ${#h_alias} )); then
    print -u2 "FAIL ssh/hosts-write-fail leftover hosts aliases=$(printf %q "${h_alias[*]}") ssh_id=$(printf %q "${h_ssh_id[*]}")"
    (( fails++ ))
  fi

  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  rm -f "$tmpdir/ssh359_session" "$tmpdir/ssh359_sync" "$tmpdir/ssh359_last"
  local ssh359_notice=$notice
  local -a ssh359_saved_opts ssh359_kind ssh359_alias ssh359_user ssh359_hn ssh359_ip ssh359_mac ssh359_port
  ssh359_saved_opts=("${SSH_OPTS[@]}")
  ssh359_kind=("${items_kind[@]}")
  ssh359_alias=("${items_alias[@]}")
  ssh359_user=("${items_user[@]}")
  ssh359_hn=("${items_hostname[@]}")
  ssh359_ip=("${items_ip[@]}")
  ssh359_mac=("${items_mac[@]}")
  ssh359_port=("${items_port[@]}")
  items_kind=(host)
  items_alias=(office)
  items_user=(mac)
  items_hostname=(office.local)
  items_ip=(10.0.0.8)
  items_mac=('aa:bb:cc:dd:ee:01')
  items_port=(22)
  functions -c apply_ssh_port _ssh359_port
  functions -c restore_tty _ssh359_restore
  functions -c setup_tty _ssh359_setup
  functions -c setup_access _ssh359_access
  functions -c ssh_tty _ssh359_tty
  functions -c sync_picker _ssh359_sync
  functions -c mark_last _ssh359_mark
  functions -c save_hosts _ssh359_save2
  apply_ssh_port() { : }
  restore_tty() { : }
  setup_tty() { : }
  setup_access() { return 0 }
  ssh() { return 0 }
  ssh_tty() {
    print -r -- connected >"$tmpdir/ssh359_session"
    return 10
  }
  sync_picker() {
    print -r -- synced >"$tmpdir/ssh359_sync"
    return 0
  }
  mark_last() { print -r -- "$1" >"$tmpdir/ssh359_last" }
  save_hosts() { return 1 }
  connect_item 1
  unfunction ssh
  functions -c _ssh359_port apply_ssh_port
  functions -c _ssh359_restore restore_tty
  functions -c _ssh359_setup setup_tty
  functions -c _ssh359_access setup_access
  functions -c _ssh359_tty ssh_tty
  functions -c _ssh359_sync sync_picker
  functions -c _ssh359_mark mark_last
  functions -c _ssh359_save2 save_hosts
  unfunction _ssh359_port _ssh359_restore _ssh359_setup _ssh359_access \
    _ssh359_tty _ssh359_sync _ssh359_mark _ssh359_save2
  SSH_OPTS=("${ssh359_saved_opts[@]}")
  items_kind=("${ssh359_kind[@]}")
  items_alias=("${ssh359_alias[@]}")
  items_user=("${ssh359_user[@]}")
  items_hostname=("${ssh359_hn[@]}")
  items_ip=("${ssh359_ip[@]}")
  items_mac=("${ssh359_mac[@]}")
  items_port=("${ssh359_port[@]}")
  notice=$ssh359_notice
  if [[ -f $tmpdir/ssh359_session || -f $tmpdir/ssh359_sync || -f $tmpdir/ssh359_last ]]; then
    print -u2 "FAIL ssh/hosts-write-fail/connect treated upsert failure as a successful session"
    (( fails++ ))
  fi
  read_ssh
  expect_absent ssh/hosts-write-fail/connect-ssh-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_absent ssh/hosts-write-fail/connect-ssh-hn 'HostName office.local' "$ssh_got"

  # #359: forget_saved must keep the hosts row when SSH remove fails.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  functions -c remove_ssh_config _ssh359_rm
  remove_ssh_config() { return 1 }
  if forget_saved 1; then
    print -u2 "FAIL ssh/forget-ssh-fail forget_saved returned 0 after SSH remove failure"
    (( fails++ ))
  fi
  functions -c _ssh359_rm remove_ssh_config
  unfunction _ssh359_rm
  load_hosts
  if [[ ${h_alias[1]:-} != office ]]; then
    print -u2 "FAIL ssh/forget-ssh-fail dropped hosts row aliases=$(printf %q "${h_alias[*]}")"
    (( fails++ ))
  fi
  ssh359_disk=$(<"$HOSTS_FILE")
  if [[ $ssh359_disk != *office.local* ]]; then
    print -u2 "FAIL ssh/forget-ssh-fail hosts file lost office.local got=$(printf %q "$ssh359_disk")"
    (( fails++ ))
  fi
  read_ssh
  expect_contains ssh/forget-ssh-fail/keep-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_contains ssh/forget-ssh-fail/keep-hn 'HostName office.local' "$ssh_got"

  # #360: hosts row exists but the LANJUMP block was hand-deleted (or
  # .ssh restored). Reconnect same MAC with a new alias/IP must succeed
  # and write the new block — missing old block is not a remove failure.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host office mac office.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  : >"$SSH_CONFIG"
  if ! upsert_host work mac studio.local 10.0.0.9 'aa:bb:cc:dd:ee:01'; then
    print -u2 "FAIL ssh/missing-block-upsert upsert_host returned 1 after old block was gone"
    (( fails++ ))
  fi
  load_hosts
  if [[ ${h_alias[1]:-} != work ]]; then
    print -u2 "FAIL ssh/missing-block-upsert/alias want=work got=$(printf %q "${h_alias[1]:-}")"
    (( fails++ ))
  fi
  if [[ ${h_ip[1]:-} != 10.0.0.9 ]]; then
    print -u2 "FAIL ssh/missing-block-upsert/ip want=10.0.0.9 got=$(printf %q "${h_ip[1]:-}")"
    (( fails++ ))
  fi
  read_ssh
  expect_contains ssh/missing-block-upsert/new-begin '# BEGIN LANJUMP lanjump-work' "$ssh_got"
  expect_contains ssh/missing-block-upsert/new-hn 'HostName studio.local' "$ssh_got"
  expect_absent ssh/missing-block-upsert/old-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"

  # #361: persist_scan_hosts must refresh HostName/Port in the LANJUMP
  # block. DHCP IP change or 2222→22 left ssh lanjump-xxx on the old
  # address until the next connect/upsert_host.
  : >"$SSH_CONFIG"
  : >"$HOSTS_FILE"
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_ssh_id=() h_last=()
  upsert_host office mac '' 10.0.0.8 'aa:bb:cc:dd:ee:01' 2222
  read_ssh
  expect_contains ssh/scan-sync/old-hn 'HostName 10.0.0.8' "$ssh_got"
  expect_contains ssh/scan-sync/old-port 'Port 2222' "$ssh_got"
  s_alias=() s_host=() s_ip=() s_mac=() s_port=()
  s_host=('')
  s_ip=(10.0.0.99)
  s_mac=('aa:bb:cc:dd:ee:01')
  s_port=(22)
  persist_scan_hosts
  load_hosts
  if [[ ${h_ip[1]:-} != 10.0.0.99 ]]; then
    print -u2 "FAIL ssh/scan-sync/hosts-ip want=10.0.0.99 got=$(printf %q "${h_ip[1]:-}")"
    (( fails++ ))
  fi
  if [[ ${h_port[1]:-} != 22 ]]; then
    print -u2 "FAIL ssh/scan-sync/hosts-port want=22 got=$(printf %q "${h_port[1]:-}")"
    (( fails++ ))
  fi
  read_ssh
  expect_contains ssh/scan-sync/new-hn 'HostName 10.0.0.99' "$ssh_got"
  expect_absent ssh/scan-sync/stale-hn 'HostName 10.0.0.8' "$ssh_got"
  expect_absent ssh/scan-sync/stale-port 'Port 2222' "$ssh_got"
  resolved_hn=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="hostname"{print $2; exit}')
  local resolved_port
  resolved_port=$(ssh -G -F "$SSH_CONFIG" lanjump-office 2>/dev/null | awk '$1=="port"{print $2; exit}')
  if [[ $resolved_hn != 10.0.0.99 ]]; then
    print -u2 "FAIL ssh/scan-sync/hostname-wins want=10.0.0.99 got=$(printf %q "$resolved_hn")"
    (( fails++ ))
  fi
  if [[ $resolved_port != 22 ]]; then
    print -u2 "FAIL ssh/scan-sync/port-wins want=22 got=$(printf %q "$resolved_port")"
    (( fails++ ))
  fi

  # #314: two upsert_ssh_config writers read then replace the whole SSH file.
  # A reads, yields, then writes; B writes in the gap. Both Host blocks must remain.
  local ssh314_home ssh314_fn
  local -i ssh314_a=0 ssh314_b=0
  ssh314_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-314-ssh.XXXXXX") || return 1
  mkdir -p "$ssh314_home/.ssh"
  : >"$ssh314_home/.ssh/config"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$ssh314_home")"
    print -r -- "SSH_CONFIG=$(printf %q "$ssh314_home/.ssh/config")"
    print -r -- "KEY=$(printf %q "$ssh314_home/.ssh/id_ed25519_lanjump")"
    for ssh314_fn in replace_file_atomic replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$ssh314_fn]} )) && functions "$ssh314_fn"
    done
    print -r -- 'functions -c replace_ssh_config _ssh314_replace'
    print -r -- 'replace_ssh_config() {'
    print -r -- '  print -r -- loaded >"$HOME/loaded"'
    print -r -- '  sleep 0.35'
    print -r -- '  _ssh314_replace "$@"'
    print -r -- '}'
    print -r -- 'upsert_ssh_config lanjump-office mac office.local'
  } >"$ssh314_home/child-a.zsh"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$ssh314_home")"
    print -r -- "SSH_CONFIG=$(printf %q "$ssh314_home/.ssh/config")"
    print -r -- "KEY=$(printf %q "$ssh314_home/.ssh/id_ed25519_lanjump")"
    for ssh314_fn in replace_file_atomic replace_ssh_config upsert_ssh_config \
      with_data_file_lock; do
      (( ${+functions[$ssh314_fn]} )) && functions "$ssh314_fn"
    done
    print -r -- 'while [[ ! -f $HOME/loaded ]]; do'
    print -r -- '  sleep 0.01'
    print -r -- 'done'
    print -r -- 'upsert_ssh_config lanjump-studio mac studio.local'
  } >"$ssh314_home/child-b.zsh"
  /bin/zsh "$ssh314_home/child-a.zsh" &
  ssh314_a=$!
  /bin/zsh "$ssh314_home/child-b.zsh" &
  ssh314_b=$!
  wait $ssh314_a
  wait $ssh314_b
  ssh_got=$(<"$ssh314_home/.ssh/config")
  expect_contains ssh/concurrent-write/office-begin '# BEGIN LANJUMP lanjump-office' "$ssh_got"
  expect_contains ssh/concurrent-write/office-hn 'HostName office.local' "$ssh_got"
  expect_contains ssh/concurrent-write/studio-begin '# BEGIN LANJUMP lanjump-studio' "$ssh_got"
  expect_contains ssh/concurrent-write/studio-hn 'HostName studio.local' "$ssh_got"
  rm -rf "$ssh314_home"

  # #256: KEY.pub comment with ' must still be a valid remote install script
  # that writes the full line. Callers pass this string as the ssh command.
  local pub_line install_cmd remote_home remote_keys
  pub_line="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForQuoteTest lanjump@J's-Mac"
  print -r -- "$pub_line" >"$KEY.pub"
  install_cmd=$(lan_pub_install_cmd)
  if ! zsh -n -c -- "$install_cmd"; then
    print -u2 "FAIL ssh/pub-install-quote/syntax remote command is not valid shell got=$(printf %q "$install_cmd")"
    (( fails++ ))
  else
    remote_home=$tmpdir/quote-remote
    mkdir -p "$remote_home"
    if ! HOME=$remote_home zsh -c -- "$install_cmd"; then
      print -u2 "FAIL ssh/pub-install-quote/run install command failed"
      (( fails++ ))
    else
      remote_keys=$(<"$remote_home/.ssh/authorized_keys")
      if [[ $remote_keys != "$pub_line" ]]; then
        print -u2 "FAIL ssh/pub-install-quote/key want=$(printf %q "$pub_line") got=$(printf %q "$remote_keys")"
        (( fails++ ))
      fi
    fi
  fi

  # #305: existing authorized_keys without a trailing newline must not
  # glue the new pubkey onto that last line. Callers pass this string
  # as the ssh command.
  local existing_line
  existing_line="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExistingKeyNoNewline existing@host"
  pub_line="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForNewlineTest lanjump@newline"
  print -r -- "$pub_line" >"$KEY.pub"
  install_cmd=$(lan_pub_install_cmd)
  remote_home=$tmpdir/newline-remote
  mkdir -p "$remote_home/.ssh"
  printf '%s' "$existing_line" >"$remote_home/.ssh/authorized_keys"
  if ! HOME=$remote_home zsh -c -- "$install_cmd"; then
    print -u2 "FAIL ssh/pub-install-newline/run install command failed"
    (( fails++ ))
  else
    remote_keys=$(<"$remote_home/.ssh/authorized_keys")
    if [[ $remote_keys != "$existing_line"$'\n'"$pub_line" ]]; then
      print -u2 "FAIL ssh/pub-install-newline/key want=$(printf %q "$existing_line"$'\n'"$pub_line") got=$(printf %q "$remote_keys")"
      (( fails++ ))
    fi
  fi

  # #190: Ghostty TERM stays; Apple Terminal 256-color rewrite is ssh-child only.
  local saved_path=$PATH
  local saved_term=${TERM-}
  local saved_term_program=${TERM_PROGRAM-}
  local saved_no_wrap=${LANJUMP_NO_GROK_WRAP-}
  local saved_keys=$LANJUMP_KEYS
  local fake_bin=$tmpdir/bin
  local child_term
  mkdir -p "$fake_bin"
  cat >"$fake_bin/ssh" <<EOF
#!/bin/zsh
print -r -- "\${TERM:-}" >"$tmpdir/child_term"
exit 0
EOF
  chmod +x "$fake_bin/ssh"
  PATH="$fake_bin:$PATH"
  rehash
  LANJUMP_NO_GROK_WRAP=1
  LANJUMP_KEYS=""

  TERM=xterm-ghostty
  unset TERM_PROGRAM
  : >"$tmpdir/child_term"
  ssh_tty -o BatchMode=yes user@host
  if [[ $TERM != xterm-ghostty ]]; then
    print -u2 "FAIL ssh/ghostty-term parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi
  child_term=$(<"$tmpdir/child_term")
  if [[ $child_term != xterm-ghostty ]]; then
    print -u2 "FAIL ssh/ghostty-term child rewritten got=$(printf %q "$child_term")"
    (( fails++ ))
  fi

  TERM=xterm
  TERM_PROGRAM=ghostty
  : >"$tmpdir/child_term"
  ssh_tty -o BatchMode=yes user@host
  if [[ $TERM != xterm ]]; then
    print -u2 "FAIL ssh/ghostty-program parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi
  child_term=$(<"$tmpdir/child_term")
  if [[ $child_term != xterm ]]; then
    print -u2 "FAIL ssh/ghostty-program child rewritten got=$(printf %q "$child_term")"
    (( fails++ ))
  fi

  TERM=xterm-kitty
  unset TERM_PROGRAM
  : >"$tmpdir/child_term"
  ssh_tty -o BatchMode=yes user@host
  if [[ $TERM != xterm-kitty ]]; then
    print -u2 "FAIL ssh/kitty-term parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi
  child_term=$(<"$tmpdir/child_term")
  if [[ $child_term != xterm-kitty ]]; then
    print -u2 "FAIL ssh/kitty-term child rewritten got=$(printf %q "$child_term")"
    (( fails++ ))
  fi

  TERM=xterm
  unset TERM_PROGRAM
  : >"$tmpdir/child_term"
  ssh_tty -o BatchMode=yes user@host
  if [[ $TERM != xterm ]]; then
    print -u2 "FAIL ssh/xterm-parent parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi
  child_term=$(<"$tmpdir/child_term")
  if [[ $child_term != xterm-256color ]]; then
    print -u2 "FAIL ssh/xterm-child want xterm-256color got=$(printf %q "$child_term")"
    (( fails++ ))
  fi

  # Ghostty TERM stays on the SSH child (#190), but tmux attach on a host
  # without that terminfo fails: missing or unsuitable terminal: xterm-ghostty.
  # Connecting copies the entry with tic; stock names skip the extra SSH.
  print -r -- 0 >"$tmpdir/ssh_n"
  cat >"$fake_bin/ssh" <<EOF
#!/bin/zsh
n=\$(( \$(<"$tmpdir/ssh_n") + 1 ))
print -r -- \$n >"$tmpdir/ssh_n"
print -r -- "\$*" >"$tmpdir/ssh_args_\$n"
cat >"$tmpdir/ssh_stdin_\$n"
exit 0
EOF
  chmod +x "$fake_bin/ssh"
  rehash

  local saved_picker=$PICKER
  PICKER=$tmpdir/fake-pick
  print -r -- 'picker-src' >"$PICKER"
  terminfo_source() { print -r -- "terminfo-src-$1" }

  print -r -- 0 >"$tmpdir/ssh_n"
  TERM=xterm-ghostty
  unset TERM_PROGRAM
  sync_terminfo host.local mac
  if [[ $(<"$tmpdir/ssh_n") != 1 ]]; then
    print -u2 "FAIL ssh/terminfo-ghostty/count got=$(<"$tmpdir/ssh_n") want=1"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_args_1") != *mac@host.local* ]]; then
    print -u2 "FAIL ssh/terminfo-ghostty/target got=$(printf %q "$(<"$tmpdir/ssh_args_1")")"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_args_1") != *tic* ]]; then
    print -u2 "FAIL ssh/terminfo-ghostty/tic got=$(printf %q "$(<"$tmpdir/ssh_args_1")")"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_stdin_1") != terminfo-src-xterm-ghostty ]]; then
    print -u2 "FAIL ssh/terminfo-ghostty/src got=$(printf %q "$(<"$tmpdir/ssh_stdin_1")")"
    (( fails++ ))
  fi

  print -r -- 0 >"$tmpdir/ssh_n"
  TERM=xterm-256color
  sync_terminfo host.local mac
  if [[ $(<"$tmpdir/ssh_n") != 0 ]]; then
    print -u2 "FAIL ssh/terminfo-stock extra ssh got=$(<"$tmpdir/ssh_n") args=$(printf %q "$(<"$tmpdir/ssh_args_1" 2>/dev/null || true)")"
    (( fails++ ))
  fi

  print -r -- 0 >"$tmpdir/ssh_n"
  TERM=xterm-ghostty
  sync_picker host.local mac
  if [[ $(<"$tmpdir/ssh_n") != 2 ]]; then
    print -u2 "FAIL ssh/sync-picker-terminfo/count got=$(<"$tmpdir/ssh_n") want=2"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_stdin_1") != picker-src ]]; then
    print -u2 "FAIL ssh/sync-picker-terminfo/picker got=$(printf %q "$(<"$tmpdir/ssh_stdin_1")")"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_args_2") != *tic* ]]; then
    print -u2 "FAIL ssh/sync-picker-terminfo/tic got=$(printf %q "$(<"$tmpdir/ssh_args_2")")"
    (( fails++ ))
  fi
  if [[ $(<"$tmpdir/ssh_stdin_2") != terminfo-src-xterm-ghostty ]]; then
    print -u2 "FAIL ssh/sync-picker-terminfo/src got=$(printf %q "$(<"$tmpdir/ssh_stdin_2")")"
    (( fails++ ))
  fi

  # #286: older incoming picker must not replace a newer remote copy.
  # Fake ssh runs the remote command against a throwaway HOME.
  local remote_home=$tmpdir/remote-286
  mkdir -p "$remote_home/.local/bin"
  print -r -- 'remote-newer' >"$remote_home/.local/bin/lanjump-pick"
  chmod 755 "$remote_home/.local/bin/lanjump-pick"
  print -r -- 'incoming-old' >"$PICKER"
  touch -t 202001010000 "$PICKER"
  touch -t 202601010000 "$remote_home/.local/bin/lanjump-pick"
  print -r -- 0 >"$tmpdir/ssh_n"
  cat >"$fake_bin/ssh" <<EOF
#!/bin/zsh
n=\$(( \$(<"$tmpdir/ssh_n") + 1 ))
print -r -- \$n >"$tmpdir/ssh_n"
print -r -- "\$*" >"$tmpdir/ssh_args_\$n"
cmd=\${@[-1]}
if [[ \$cmd == *tic* ]]; then
  cat >/dev/null
  exit 0
fi
HOME=$(printf %q "$remote_home") /bin/zsh -c "\$cmd"
EOF
  chmod +x "$fake_bin/ssh"
  rehash
  TERM=xterm-256color
  sync_picker host.local mac
  if [[ $(<"$remote_home/.local/bin/lanjump-pick") != remote-newer ]]; then
    print -u2 "FAIL ssh/sync-picker-keep-newer dest overwritten got=$(printf %q "$(<"$remote_home/.local/bin/lanjump-pick")")"
    (( fails++ ))
  fi
  print -r -- 'incoming-newer' >"$PICKER"
  touch -t 202701010000 "$PICKER"
  print -r -- 0 >"$tmpdir/ssh_n"
  sync_picker host.local mac
  if [[ $(<"$remote_home/.local/bin/lanjump-pick") != incoming-newer ]]; then
    print -u2 "FAIL ssh/sync-picker-take-newer dest kept stale got=$(printf %q "$(<"$remote_home/.local/bin/lanjump-pick")")"
    (( fails++ ))
  fi

  # #310: keep-newer must use a version stamp, not two machines' mtimes.
  # Dest mtime is last sync write on a possibly-fast remote clock, so a
  # newer local picker can look older and never replace the stale copy.
  print -r -- $'# lanjump-pick-version 100 oldsha\nremote-old-stamp' >"$remote_home/.local/bin/lanjump-pick"
  chmod 755 "$remote_home/.local/bin/lanjump-pick"
  print -r -- $'# lanjump-pick-version 200 newsha\nincoming-new-stamp' >"$PICKER"
  touch -t 202001010000 "$PICKER"
  touch -t 202601010000 "$remote_home/.local/bin/lanjump-pick"
  print -r -- 0 >"$tmpdir/ssh_n"
  sync_picker host.local mac
  if [[ $(<"$remote_home/.local/bin/lanjump-pick") != *incoming-new-stamp* ]]; then
    print -u2 "FAIL ssh/sync-picker-version-stamp dest kept clock-newer old version got=$(printf %q "$(<"$remote_home/.local/bin/lanjump-pick")")"
    (( fails++ ))
  fi

  # #287: probe must use the same remote command as later verify (`true`).
  # NixOS often has `true` on PATH but no /usr/bin/true; exit 127 there
  # is not a key failure and must not drop the user onto the password path.
  print -r -- 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyFor287Test lanjump@test' >"$KEY.pub"
  rm -f "$tmpdir/try_ssh_287_args" "$tmpdir/try_ssh_287_path"
  cat >"$fake_bin/ssh" <<EOF
#!/bin/zsh
print -r -- "\$*" >>"$tmpdir/try_ssh_287_args"
cmd=\${@[-1]}
if [[ \$* == *PreferredAuthentications=keyboard-interactive* ]]; then
  print -r -- password-install >"$tmpdir/try_ssh_287_path"
  exit 1
fi
if [[ \$cmd == /usr/bin/true ]]; then
  exit 127
fi
if [[ \$cmd == true ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "$fake_bin/ssh"
  rehash
  if ! setup_access mac nixos.local; then
    print -u2 "FAIL ssh/try-ssh-true/access key probe failed when only PATH true exists"
    (( fails++ ))
  fi
  if [[ -f $tmpdir/try_ssh_287_path ]]; then
    print -u2 "FAIL ssh/try-ssh-true/password-path missing /usr/bin/true was treated as a key failure"
    (( fails++ ))
  fi
  if [[ -f $tmpdir/try_ssh_287_args ]]; then
    if [[ $(<"$tmpdir/try_ssh_287_args") != *' true'* ]]; then
      print -u2 "FAIL ssh/try-ssh-true/cmd probe remote command is not true got=$(printf %q "$(<"$tmpdir/try_ssh_287_args")")"
      (( fails++ ))
    fi
    if [[ $(<"$tmpdir/try_ssh_287_args") == *'/usr/bin/true'* ]]; then
      print -u2 "FAIL ssh/try-ssh-true/abs-cmd probe still uses /usr/bin/true got=$(printf %q "$(<"$tmpdir/try_ssh_287_args")")"
      (( fails++ ))
    fi
  else
    print -u2 "FAIL ssh/try-ssh-true/cmd probe did not invoke ssh"
    (( fails++ ))
  fi

  # #341: after the key works, remote pick and snapshot hook/tick must
  # find zsh on PATH. Hard /bin/zsh is 127 on NixOS.
  # cli_remote_* are defined after --ssh-selftest; connect_item is here.
  _lj341_remote=${functions[connect_item]}
  if (( ${+functions[remote_pick_exec]} )); then
    _lj341_remote+=${functions[remote_pick_exec]}
  fi
  if [[ $_lj341_remote == *'exec /bin/zsh'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/hard-bin-zsh still execs /bin/zsh for lanjump-pick"
    (( fails++ ))
  fi
  if [[ $_lj341_remote != *'command -v zsh'* && $_lj341_remote != *'/usr/bin/env zsh'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/find-zsh missing command -v zsh or /usr/bin/env zsh"
    (( fails++ ))
  fi
  unset _lj341_remote

  eval "$(awk '
    /^snapshot_pick_bin\(\)/ {p=1}
    /^snapshot_hook_shell\(\)/ {p=1}
    p {print}
    p && /^}/ {p=0}
  ' "${${(%):-%x}:A:h}/lanjump-pick.zsh")"
  _lj341_hook=$(LANJUMP_PICK_BIN=/tmp/lanjump-pick snapshot_hook_shell)
  if [[ $_lj341_hook == /bin/zsh\ *lanjump-pick* || $_lj341_hook == *'/bin/zsh /tmp/lanjump-pick'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/hook-hard-bin-zsh got=$(printf %q "$_lj341_hook")"
    (( fails++ ))
  fi
  if [[ $_lj341_hook != *'command -v zsh'* && $_lj341_hook != *'/usr/bin/env zsh'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/hook-find-zsh missing command -v zsh or /usr/bin/env zsh got=$(printf %q "$_lj341_hook")"
    (( fails++ ))
  fi
  unset _lj341_hook
  _lj341_tick=$(awk '
    /^tmux_install_snapshot_hooks\(\)/ {p=1}
    p && /tick=/ {print; exit}
  ' "${${(%):-%x}:A:h}/lanjump-pick.zsh")
  if [[ $_lj341_tick == *'/bin/zsh'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/tick-hard-bin-zsh got=$(printf %q "$_lj341_tick")"
    (( fails++ ))
  fi
  if [[ $_lj341_tick != *'command -v zsh'* && $_lj341_tick != *'/usr/bin/env zsh'* ]]; then
    print -u2 "FAIL ssh/remote-zsh/tick-find-zsh missing command -v zsh or /usr/bin/env zsh got=$(printf %q "$_lj341_tick")"
    (( fails++ ))
  fi
  unset _lj341_tick

  PICKER=$saved_picker
  unfunction terminfo_source 2>/dev/null || true

  PATH=$saved_path
  rehash
  if [[ -n $saved_term ]]; then
    TERM=$saved_term
  else
    unset TERM
  fi
  if [[ -n $saved_term_program ]]; then
    TERM_PROGRAM=$saved_term_program
  else
    unset TERM_PROGRAM
  fi
  if [[ -n $saved_no_wrap ]]; then
    LANJUMP_NO_GROK_WRAP=$saved_no_wrap
  else
    unset LANJUMP_NO_GROK_WRAP
  fi
  LANJUMP_KEYS=$saved_keys

  SSH_CONFIG=$saved_ssh
  HOSTS_FILE=$saved_hosts
  KEY=$saved_key
  HOME=$saved_home
  h_alias=("${saved_alias[@]}")
  h_user=("${saved_user[@]}")
  h_hostname=("${saved_hostname[@]}")
  h_ip=("${saved_ip[@]}")
  h_mac=("${saved_mac[@]}")
  h_ssh_id=("${saved_ssh_id[@]}")
  h_last=("${saved_last[@]}")
  rm -rf "$tmpdir"

  if [[ -f $real_ssh ]]; then
    new_hash=$(shasum -a 256 "$real_ssh")
  else
    new_hash=""
  fi
  if [[ $real_hash != "$new_hash" ]]; then
    print -u2 "FAIL ssh/real-config-untouched real ~/.ssh/config changed during selftest"
    (( fails++ ))
  fi

  # #307: tty hangup must not treat a failed read as an empty username.
  if ! (( ${+functions[prompt_username]} )); then
    print -u2 "FAIL username/tty-eof missing prompt_username"
    (( fails++ ))
  elif ! command -v python3 >/dev/null; then
    print -u2 "FAIL username/tty-eof missing python3"
    (( fails++ ))
  else
    local eof_dir eof_st=0
    eof_dir=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-307.XXXXXX") || return 1
    {
      typeset -f trim
      typeset -f prompt_username
      print -r -- 'restore_tty() { : }'
      print -r -- 'prompt_username'
    } >"$eof_dir/run.zsh"
    python3 - "$eof_dir" <<'PY'
import os, subprocess, sys
d = sys.argv[1]
try:
    r = subprocess.run(
        ["/bin/zsh", os.path.join(d, "run.zsh")],
        preexec_fn=os.setsid,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=open(os.path.join(d, "err"), "wb"),
        timeout=1.5,
    )
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    sys.exit(99)
PY
    eof_st=$?
    if (( eof_st == 99 )); then
      print -u2 "FAIL username/tty-eof spun (treated read fail as empty name)"
      (( fails++ ))
    elif [[ -f $eof_dir/err ]] && grep -q '用户名不能为空' "$eof_dir/err"; then
      print -u2 "FAIL username/tty-eof treated read fail as empty name"
      (( fails++ ))
    elif (( eof_st == 0 )); then
      print -u2 "FAIL username/tty-eof accepted empty name on read fail"
      (( fails++ ))
    fi
    rm -rf "$eof_dir"
  fi

  if (( fails )); then
    print -u2 "ssh-selftest: $fails failed"
    return 1
  fi
  print "ok ssh"
  return 0
}
