# Sourced by lanjump.zsh / lanjump-pick.zsh --digit-selftest.
# Expects index_prefix_ambiguous, collect_index_digits, PENDING_KEY, digit_wait.

digit_selftest() {
  local -i fails=0
  local acc max exp got n leftover
  local saved_wait=$digit_wait
  zmodload zsh/system || return 1
  zmodload zsh/zselect || return 1
  for acc max exp in \
    1 9 0 \
    1 10 1 \
    2 10 0 \
    9 9 0 \
    9 90 1 \
    10 10 0 \
    10 99 0 \
    10 100 1 \
    1 15 1 \
    1 100 1 \
    0 15 0 \
    01 15 0
  do
    if index_prefix_ambiguous "$acc" "$max"; then
      got=1
    else
      got=0
    fi
    if [[ $got != $exp ]]; then
      print -u2 "FAIL ambiguous($acc,$max)=$got want $exp"
      (( fails++ ))
    fi
  done

  leftover=""
  n=""
  {
    collect_index_digits 2 15
    n=$REPLY
    sysread -s 1 leftover || leftover=""
  } < <(print -n '9')
  if [[ $n != 2 || $leftover != 9 ]]; then
    print -u2 "FAIL unambiguous collect got n=$n leftover=$leftover"
    (( fails++ ))
  fi

  PENDING_KEY=x
  leftover=""
  n=""
  {
    collect_index_digits 1 15
    n=$REPLY
    sysread -s 1 leftover || leftover=""
  } < <(print -n '0x')
  if [[ $n != 10 || $leftover != x || -n $PENDING_KEY ]]; then
    print -u2 "FAIL collect 10 got n=$n leftover=$leftover pending=$PENDING_KEY"
    (( fails++ ))
  fi

  PENDING_KEY=""
  n=""
  collect_index_digits 1 15 < <(print -n 'j')
  n=$REPLY
  if [[ -n $n || $PENDING_KEY != j ]]; then
    print -u2 "FAIL other-key cancel got n=$n pending=$PENDING_KEY"
    (( fails++ ))
  fi

  PENDING_KEY=x
  n=""
  collect_index_digits 1 15 < <(print -n $'\n')
  n=$REPLY
  if [[ $n != 1 || -n $PENDING_KEY ]]; then
    print -u2 "FAIL enter commit got n=$n pending=$PENDING_KEY"
    (( fails++ ))
  fi

  PENDING_KEY=x
  n=""
  collect_index_digits 1 15 < <(print -n $'\e')
  n=$REPLY
  if [[ -n $n || -n $PENDING_KEY ]]; then
    print -u2 "FAIL esc cancel got n=$n pending=$PENDING_KEY"
    (( fails++ ))
  fi

  n=""
  leftover=""
  {
    collect_index_digits 1 100
    n=$REPLY
    sysread -s 1 leftover || leftover=""
  } < <(print -n '00z')
  if [[ $n != 100 || $leftover != z ]]; then
    print -u2 "FAIL collect 100 got n=$n leftover=$leftover"
    (( fails++ ))
  fi

  digit_wait=0.4
  n=""
  collect_index_digits 1 15 < <(sleep 0.08; print -n '0')
  n=$REPLY
  digit_wait=$saved_wait
  if [[ $n != 10 ]]; then
    print -u2 "FAIL delayed digit got n=$n"
    (( fails++ ))
  fi

  if (( fails )); then
    print -u2 "digit-selftest: $fails failed"
    return 1
  fi
  print "ok digits"
  return 0
}
