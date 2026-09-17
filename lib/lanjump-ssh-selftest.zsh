# Sourced by lanjump.zsh --ssh-selftest.
# Expects strip_ssh_block, remove_ssh_config, upsert_ssh_config, forget_saved,
# ssh_id_from_alias, lan_pub_install_cmd. Uses temp files only; never the
# real ~/.ssh/config.

ssh_selftest() {
  local -i fails=0
  local orig_home=$HOME
  local real_ssh="$orig_home/.ssh/config"
  local real_hash="" new_hash=""
  local tmpdir ssh_got saved_ssh saved_hosts saved_key saved_home
  local -a saved_alias saved_user saved_hostname saved_ip saved_mac saved_last

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
  h_alias=() h_user=() h_hostname=() h_ip=() h_mac=() h_port=() h_last=()
  upsert_host '书房' mac study.local 10.0.0.8 'aa:bb:cc:dd:ee:01'
  upsert_host '客厅' mac living.local 10.0.0.9 'aa:bb:cc:dd:ee:02'
  read_ssh
  expect_contains ssh/cjk-id/study-hn 'HostName study.local' "$ssh_got"
  expect_contains ssh/cjk-id/living-hn 'HostName living.local' "$ssh_got"
  forget_saved 1
  read_ssh
  expect_absent ssh/cjk-id/forget-study 'HostName study.local' "$ssh_got"
  expect_contains ssh/cjk-id/forget-living 'HostName living.local' "$ssh_got"

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

  if (( fails )); then
    print -u2 "ssh-selftest: $fails failed"
    return 1
  fi
  print "ok ssh"
  return 0
}
