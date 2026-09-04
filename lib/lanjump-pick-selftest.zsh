# Sourced by lanjump-pick.zsh --pick-selftest.
# Expects dw, fit_right, fit_left, padw, compute_layout, fmt_session_row, draw.

pick_selftest() {
  local -i fails=0
  local got
  zmodload zsh/datetime || return 1

  expect() {
    local label=$1 want=$2
    got=$3
    if [[ $got != "$want" ]]; then
      print -u2 "FAIL $label got=$(printf %q "$got") want=$(printf %q "$want")"
      (( fails++ ))
    fi
  }

  expect dw/ascii 5 "$(dw hello)"
  expect dw/cjk 4 "$(dw 中文)"
  expect dw/mixed 4 "$(dw a中b)"
  expect dw/empty 0 "$(dw '')"

  expect fit_right/short hello "$(fit_right hello 10)"
  expect fit_right/ascii hel… "$(fit_right hello 4)"
  expect fit_right/one … "$(fit_right hello 1)"
  expect fit_right/cjk5 中文… "$(fit_right 中文测试 5)"
  expect fit_right/cjk4 中… "$(fit_right 中文测试 4)"
  expect fit_left/path '…ts/projects/lanjump' "$(fit_left /Users/mac/Documents/projects/lanjump 20)"
  expect fit_left/home '…cts/lanjump' "$(fit_left ~/Documents/projects/lanjump 12)"
  expect padw/ascii 'ab   ' "$(padw ab 5)"
  expect padw/cjk '中文  ' "$(padw 中文 6)"
  expect padw/trunc hel… "$(padw hello 4)"

  local sample longline
  sample="这是一段中文预览文字 mixed with ascii and ████ blocks"
  longline=$(printf '%s' {1..40} | tr -d '\n')
  longline="${sample} ${longline} ${sample}"

  local -i n
  local -F 3 t0 t1 ms
  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    fit_right "$longline" 80 >/dev/null
  done
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old per-character $(dw) path was ~3000ms for this case.
  if (( ms > 80 )); then
    print -u2 "FAIL fit_right perf ${ms}ms want <=80ms"
    (( fails++ ))
  fi

  local i
  items_kind=() items_id=() items_name=() items_att=() items_time=()
  items_path=() items_summary=() items_cmd=()
  for i in {1..8}; do
    items_kind+=("session")
    items_id+=("sess-$i")
    items_name+=("bmx-session-$i")
    items_att+=("0")
    items_time+=("09-04 12:00")
    items_path+=("~/Documents/projects/lanjump-and-a-quite-long-path-$i")
    items_summary+=("小兜宝探路：钉死后第一版最终效果 - grok 下载 X 视频到 NAS 影视库 $i")
    items_cmd+=("grok-1.0.13-mac")
  done
  cursor=1
  COLUMNS=120
  LINES=40

  compute_layout 110
  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    for i in {1..8}; do
      _fmt_session_row $i
    done
  done
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old path was ~80ms per row, ~12s for this loop.
  if (( ms > 100 )); then
    print -u2 "FAIL fmt_session_row perf ${ms}ms want <=100ms"
    (( fails++ ))
  fi

  session_preview_lines() {
    local -i max_lines=$2 cols=$3 i
    local line="预览长行 ${longline}"
    for (( i = 1; i <= max_lines; i++ )); do
      _fit_right "$line" $cols
      print -r -- "$REPLY"
    done
  }

  t0=$EPOCHREALTIME
  draw >/dev/null
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old draw was ~700ms even without tmux capture-pane.
  if (( ms > 150 )); then
    print -u2 "FAIL draw perf ${ms}ms want <=150ms"
    (( fails++ ))
  fi

  if (( fails )); then
    print -u2 "pick-selftest: $fails failed"
    return 1
  fi
  print "ok pick"
  return 0
}
