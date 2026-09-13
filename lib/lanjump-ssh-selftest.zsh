# Sourced by lanjump.zsh --ssh-selftest.
# Expects strip_ssh_block, remove_ssh_config, upsert_ssh_config, forget_saved,
# ssh_id_from_alias. Uses temp files only; never the real ~/.ssh/config.

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
