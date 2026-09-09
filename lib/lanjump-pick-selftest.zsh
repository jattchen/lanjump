# Sourced by lanjump-pick.zsh --pick-selftest.
# Expects dw, fit_right, fit_left, padw, compute_layout, fmt_session_row, draw,
# sort_session_items, toggle_sort_mode, filter_session_items,
# toggle_session_filter, save_session_filter, load_session_filter,
# bulk_idle_unpinned_names, delete_idle_unpinned_sessions,
# session_delete_needs_pin_warning, pin_delete_warning_text,
# rename_pin_record, restore_pinned_sessions.

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

  functions -c tmuxx _selftest_tmuxx
  local mock_pane mock_log
  local -a tmux_argv tmux_calls
  local -i tmux_n
  mock_log=$(mktemp) || return 1
  load_tmux_calls() {
    tmux_calls=("${(@f)$(<"$mock_log")}")
    tmux_n=${#tmux_calls}
    if (( tmux_n )); then
      tmux_argv=("${(z)tmux_calls[-1]}")
    else
      tmux_argv=()
    fi
  }
  tmuxx() {
    print -r -- "${(j: :)@}" >> "$mock_log"
    print -r -- "$mock_pane"
  }

  mock_pane=$'old chrome\nolder row\nlatest dialogue\ninput line'
  : > "$mock_log"
  session_preview_lines grok-sess 2 grok-1.0.13-mac
  expect preview/tail-keep $'latest dialogue\ninput line' "${(F)preview_lines}"

  mock_pane=$'keep\n\n\n   \n█\n████\nreal █ line\n\nend'
  : > "$mock_log"
  session_preview_lines sh-sess 10 zsh
  expect preview/blank-collapse $'keep\n\nreal █ line\n\nend' "${(F)preview_lines}"

  mock_pane=$'hello\n────────'
  : > "$mock_log"
  session_preview_lines sh-sess 10 zsh
  expect preview/skip-status hello "${(F)preview_lines}"

  mock_pane=$(print -l line-{1..20})
  : > "$mock_log"
  session_preview_lines sh-sess 30 zsh
  if (( ${#preview_lines} != 10 )); then
    print -u2 "FAIL preview/cap got ${#preview_lines} want 10"
    (( fails++ ))
  fi
  expect preview/cap-tail $'line-11\nline-12\nline-13\nline-14\nline-15\nline-16\nline-17\nline-18\nline-19\nline-20' "${(F)preview_lines}"

  mock_pane=$'a\nb'
  : > "$mock_log"
  session_preview_lines grok-sess 5 grok
  load_tmux_calls
  if (( tmux_n != 1 )); then
    print -u2 "FAIL preview/grok-once got ${tmux_n} captures want 1"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-a]} -gt ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/grok-alt missing -a in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-J]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/grok-no-J got ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-S]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/no-hist got -S in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi

  mock_pane=$'a\nb'
  : > "$mock_log"
  session_preview_lines zsh-sess 5 zsh
  load_tmux_calls
  if (( tmux_n != 1 )); then
    print -u2 "FAIL preview/shell-once got ${tmux_n} captures want 1"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-J]} -gt ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/shell-J missing -J in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-a]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/shell-no-alt got ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-S]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/shell-no-hist got -S in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi

  tmuxx() {
    print -r -- "${(j: :)@}" >> "$mock_log"
    if [[ ${argv[(ie)-a]} -le ${#argv} ]]; then
      print -r -- $'alt dialogue\nalt input'
    else
      print -r -- ""
    fi
  }
  : > "$mock_log"
  session_preview_lines tui-sess 5 bash
  load_tmux_calls
  if (( tmux_n != 2 )); then
    print -u2 "FAIL preview/empty-retry got ${tmux_n} captures want 2"
    (( fails++ ))
  fi
  if [[ ${tmux_calls[1]:-} != *-J* || ${tmux_calls[1]:-} == *-a* ]]; then
    print -u2 "FAIL preview/empty-first got ${tmux_calls[1]:-}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-a]} -gt ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/empty-alt missing -a in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-J]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/empty-alt-no-J got ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  expect preview/empty-alt-tail $'alt dialogue\nalt input' "${(F)preview_lines}"

  rm -f "$mock_log"
  unfunction tmuxx
  unfunction load_tmux_calls
  functions -c _selftest_tmuxx tmuxx
  unfunction _selftest_tmuxx

  local -i preview_calls=0
  session_preview_lines() {
    (( preview_calls++ ))
    preview_lines=("SECRET_CAPTURE")
  }
  items_kind=() items_id=() items_name=() items_att=() items_time=()
  items_path=() items_summary=() items_cmd=()
  items_kind+=("session") items_id+=("sess-1") items_name+=("sess-1")
  items_att+=("0") items_time+=("09-04 12:00") items_path+=("~/p/1")
  items_summary+=("sum 1") items_cmd+=("zsh")
  cursor=1
  COLUMNS=120
  LINES=40
  preview_defer=1
  preview_cache=()
  preview_calls=0
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if (( preview_calls != 0 )); then
    print -u2 "FAIL draw/defer-no-capture called session_preview_lines"
    (( fails++ ))
  fi
  if [[ $plain == *SECRET_CAPTURE* ]]; then
    print -u2 "FAIL draw/defer-placeholder showed capture"
    (( fails++ ))
  fi
  if [[ $plain != *…* ]]; then
    print -u2 "FAIL draw/defer-placeholder missing ellipsis"
    (( fails++ ))
  fi
  preview_defer=0

  session_preview_lines() {
    local -i max_lines=$2 i
    preview_lines=()
    for (( i = 1; i <= max_lines; i++ )); do
      preview_lines+=("预览长行 ${longline}")
    done
  }

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
  preview_cache=()

  t0=$EPOCHREALTIME
  draw >/dev/null
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old draw was ~700ms even without tmux capture-pane.
  if (( ms > 150 )); then
    print -u2 "FAIL draw perf ${ms}ms want <=150ms"
    (( fails++ ))
  fi

  HAS_TMUX=1
  host_short=testhost
  preview_on=0
  items_kind=() items_id=() items_name=() items_att=() items_time=()
  items_path=() items_summary=() items_cmd=()
  for i in {1..32}; do
    items_kind+=("session")
    items_id+=("sess-$i")
    items_name+=("sess-$i")
    items_att+=("0")
    items_time+=("09-04 12:00")
    items_path+=("~/p/$i")
    items_summary+=("sum $i")
    items_cmd+=("zsh")
  done
  cursor=32
  COLUMNS=120
  LINES=14
  local out plain kind name
  local -a lines
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/viewport missing selected sess-32"
    (( fails++ ))
  fi
  if [[ $plain != *还有* ]]; then
    print -u2 "FAIL draw/viewport missing overflow hint"
    (( fails++ ))
  fi
  if [[ $plain == *sess-1* && $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/viewport stayed on first page"
    (( fails++ ))
  fi
  if [[ $plain != *'↑ 还有'* ]]; then
    print -u2 "FAIL draw/viewport missing above hint"
    (( fails++ ))
  fi

  LINES=8
  expect term_lines/phone 8 "$(term_lines)"
  LINES=24
  expect term_lines/normal 24 "$(term_lines)"
  LINES=14

  view_start=1
  cursor=1
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-1* ]]; then
    print -u2 "FAIL draw/viewport top missing sess-1"
    (( fails++ ))
  fi
  if [[ $plain != *'↓ 还有'* ]]; then
    print -u2 "FAIL draw/viewport top missing below hint"
    (( fails++ ))
  fi
  if [[ $plain == *sess-32* ]]; then
    print -u2 "FAIL draw/viewport top showed last row"
    (( fails++ ))
  fi

  cursor=32
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/viewport wrap-to-last missing sess-32"
    (( fails++ ))
  fi

  cursor=1
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-1* ]]; then
    print -u2 "FAIL draw/viewport wrap-to-first missing sess-1"
    (( fails++ ))
  fi

  lines=("${(@f)plain}")
  if (( ${#lines} > LINES )); then
    print -u2 "FAIL draw/viewport drew ${#lines} lines on LINES=$LINES"
    (( fails++ ))
  fi

  for kind name in new '新建 session' shell '普通 shell' hosts '换一台机器' quit '退出'; do
    items_kind+=("$kind")
    items_id+=("$kind")
    items_name+=("$name")
    items_att+=("")
    items_time+=("")
    items_path+=("")
    items_summary+=("")
    items_cmd+=("")
  done
  view_start=1
  cursor=${#items_kind}
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *退出* ]]; then
    print -u2 "FAIL draw/viewport missing last action"
    (( fails++ ))
  fi

  items_kind=() items_id=() items_name=() items_att=() items_time=()
  items_path=() items_summary=() items_cmd=()
  for i in {1..3}; do
    items_kind+=("session")
    items_id+=("sess-$i")
    items_name+=("sess-$i")
    items_att+=("0")
    items_time+=("09-04 12:00")
    items_path+=("~/p/$i")
    items_summary+=("sum $i")
    items_cmd+=("zsh")
  done
  view_start=1
  cursor=1
  LINES=40
  preview_on=1
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *预览* ]]; then
    print -u2 "FAIL draw/viewport leftover preview missing"
    (( fails++ ))
  fi
  preview_on=0

  items_kind=() items_id=() items_name=() items_att=() items_time=()
  items_path=() items_summary=() items_cmd=()
  for i in {1..32}; do
    items_kind+=("session")
    items_id+=("sess-$i")
    items_name+=("sess-$i")
    items_att+=("0")
    items_time+=("09-04 12:00")
    items_path+=("~/p/$i")
    items_summary+=("sum $i")
    items_cmd+=("zsh")
  done
  view_start=1
  cursor=32
  LINES=7
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/viewport tiny screen missing selected sess-32"
    (( fails++ ))
  fi

  HAS_TMUX=1
  host_short=testhost
  COLUMNS=120
  preview_on=1
  preview_defer=0
  preview_cache=()
  view_start=1
  cursor=32
  LINES=14
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/preview-reserve missing selected sess-32"
    (( fails++ ))
  fi
  if [[ $plain != *'预览'*sess-32* && $plain != *'预览  sess-32'* ]]; then
    if [[ $plain != *$'\n  预览'* ]]; then
      print -u2 "FAIL draw/preview-reserve missing preview block"
      (( fails++ ))
    fi
  fi
  preview_on=0
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain == *$'\n  预览'* ]]; then
    print -u2 "FAIL draw/preview-off still showed preview block"
    (( fails++ ))
  fi
  if [[ $plain != *sess-32* ]]; then
    print -u2 "FAIL draw/preview-off missing selected sess-32"
    (( fails++ ))
  fi
  preview_on=1

  local time_order occupied_order pinned_order actions
  actions='new shell hosts quit'
  time_order="idle-free idle-pin busy-free busy-pin $actions"
  occupied_order="busy-pin busy-free idle-pin idle-free $actions"
  pinned_order="busy-pin idle-pin busy-free idle-free $actions"

  sort_fixture() {
    items_kind=(session session session session new shell hosts quit)
    items_id=(busy-pin idle-free idle-pin busy-free new shell hosts quit)
    items_name=("${items_id[@]}")
    items_att=(1 0 0 1 '' '' '' '')
    items_pinned=(1 0 1 0 '' '' '' '')
    items_time=('01-01 00:01' '01-01 00:04' '01-01 00:03' '01-01 00:02' '' '' '' '')
    items_activity=(60 90 80 70 '' '' '' '')
    items_path=('~/a' '~/b' '~/c' '~/d' '' '' '' '')
    items_summary=('sa' 'sb' 'sc' 'sd' '' '' '' '')
    items_cmd=(zsh zsh zsh zsh '' '' '' '')
    all_kind=() all_id=() all_name=() all_att=() all_time=()
    all_path=() all_summary=() all_cmd=() all_activity=() all_pinned=()
    filter_include=
    filter_exclude=
    filter_on=0
    sort_mode=time
    cursor=1
  }

  sort_fixture
  sort_session_items
  expect sort/time-desc "$time_order" "${items_id[*]}"

  sort_mode=occupied
  sort_session_items
  expect sort/occupied "$occupied_order" "${items_id[*]}"

  sort_mode=pinned
  sort_session_items
  expect sort/pinned "$pinned_order" "${items_id[*]}"

  sort_mode=occupied
  toggle_sort_mode
  expect sort/toggle-to-pinned "$pinned_order" "${items_id[*]}"
  toggle_sort_mode
  expect sort/toggle-to-time "$time_order" "${items_id[*]}"

  sort_fixture
  sort_session_items
  cursor=3
  expect sort/cursor-before busy-free "${items_id[$cursor]}"
  toggle_sort_mode
  expect sort/cursor-keep busy-free "${items_id[$cursor]}"
  expect sort/cursor-keep-order "$occupied_order" "${items_id[*]}"

  HAS_TMUX=1
  host_short=testhost
  COLUMNS=120
  LINES=40
  sort_fixture
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'o 时间'* ]]; then
    print -u2 "FAIL help/time missing o 时间"
    (( fails++ ))
  fi
  sort_mode=occupied
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'o 占用'* ]]; then
    print -u2 "FAIL help/occupied missing o 占用"
    (( fails++ ))
  fi
  sort_mode=pinned
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'o 常驻'* ]]; then
    print -u2 "FAIL help/pinned missing o 常驻"
    (( fails++ ))
  fi

  local oldhome testhome
  oldhome=$HOME
  testhome=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-filter.XXXXXX")
  HOME=$testhome
  mkdir -p "$HOME/Library/Application Support/lanjump"

  filter_fixture() {
    items_kind=(session session session session session new shell hosts quit)
    items_id=(grok-new grok-old other-new other-old cmd-only new shell hosts quit)
    items_name=(Grok-new grok-old other-new other-old plain new shell hosts quit)
    items_att=(1 0 0 1 0 '' '' '' '')
    items_time=('01-01 00:05' '01-01 00:01' '01-01 00:04' '01-01 00:00' '01-01 00:02' '' '' '' '')
    items_activity=(300 100 200 50 150 '' '' '' '')
    items_path=('~/proj/grok' '~/proj/old-grok' '~/proj/other' '~/old/other' '~/plain' '' '' '' '')
    items_summary=('work grok' 'old grok notes' 'other work' 'legacy stash' 'plain' '' '' '' '')
    items_cmd=(zsh zsh zsh zsh grok-bin '' '' '' '')
    all_kind=() all_id=() all_name=() all_att=() all_time=()
    all_path=() all_summary=() all_cmd=() all_activity=()
    filter_include=
    filter_exclude=
    filter_on=0
    sort_mode=time
    cursor=1
    HAS_TMUX=1
    host_short=testhost
    COLUMNS=120
    LINES=40
  }

  local actions='new shell hosts quit'
  local all_ids='grok-new grok-old other-new other-old cmd-only new shell hosts quit'

  filter_fixture
  filter_include=grok
  filter_on=1
  filter_session_items
  expect filter/include-ids "grok-new grok-old $actions" "${items_id[*]}"
  if [[ ${items_id[*]} == *cmd-only* ]]; then
    print -u2 "FAIL filter/include matched pane command grok-bin"
    (( fails++ ))
  fi

  filter_fixture
  filter_exclude=old
  filter_on=1
  filter_session_items
  expect filter/exclude-ids "grok-new other-new cmd-only $actions" "${items_id[*]}"

  filter_fixture
  filter_include=grok
  filter_exclude=old
  filter_on=1
  filter_session_items
  expect filter/stack-ids "grok-new $actions" "${items_id[*]}"

  filter_fixture
  filter_include=GROK
  filter_on=1
  filter_session_items
  expect filter/case-ids "grok-new grok-old $actions" "${items_id[*]}"

  filter_fixture
  filter_include=legacy
  filter_on=1
  filter_session_items
  expect filter/summary-ids "other-old $actions" "${items_id[*]}"

  filter_fixture
  filter_include='proj/other'
  filter_on=1
  filter_session_items
  expect filter/path-ids "other-new $actions" "${items_id[*]}"

  filter_fixture
  session_preview_lines() { print -r -- 'preview has grok secret'; }
  filter_include=secret
  filter_on=1
  filter_session_items
  expect filter/ignore-preview "$actions" "${items_id[*]}"
  session_preview_lines() { return 0 }

  filter_fixture
  filter_include=grok
  filter_exclude=old
  save_session_filter
  filter_on=1
  filter_session_items
  expect filter/saved-apply "grok-new $actions" "${items_id[*]}"
  toggle_session_filter
  expect filter/f-off "$all_ids" "${items_id[*]}"
  expect filter/f-off-keeps-include grok "$filter_include"
  expect filter/f-off-keeps-exclude old "$filter_exclude"
  filter_include=wiped
  filter_exclude=wiped
  load_session_filter
  expect filter/saved-pair-include grok "$filter_include"
  expect filter/saved-pair-exclude old "$filter_exclude"
  toggle_session_filter
  expect filter/f-on-again "grok-new $actions" "${items_id[*]}"

  filter_fixture
  filter_exclude=plain
  filter_on=1
  sort_mode=time
  sort_session_items
  filter_session_items
  expect filter/sort-time "grok-new other-new grok-old other-old $actions" "${items_id[*]}"
  filter_fixture
  filter_exclude=plain
  filter_on=1
  sort_mode=occupied
  sort_session_items
  filter_session_items
  expect filter/sort-occupied "grok-new other-old other-new grok-old $actions" "${items_id[*]}"

  filter_fixture
  filter_include=grok
  filter_on=0
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *other-new* ]]; then
    print -u2 "FAIL filter/draw-off missing unfiltered other-new"
    (( fails++ ))
  fi
  if [[ $plain == *'含 grok'* ]]; then
    print -u2 "FAIL filter/draw-off showed inactive include"
    (( fails++ ))
  fi
  if [[ $plain != *'f 筛选'* ]]; then
    print -u2 "FAIL filter/draw-off missing f 筛选"
    (( fails++ ))
  fi

  filter_fixture
  filter_include=grok
  filter_exclude=old
  filter_on=1
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'含 grok'* ]]; then
    print -u2 "FAIL filter/draw-on missing 含 grok"
    (( fails++ ))
  fi
  if [[ $plain != *'不含 old'* ]]; then
    print -u2 "FAIL filter/draw-on missing 不含 old"
    (( fails++ ))
  fi
  if [[ $plain != *'1/5'* ]]; then
    print -u2 "FAIL filter/draw-on missing match count 1/5"
    (( fails++ ))
  fi
  if [[ $plain != *Grok-new* && $plain != *grok-new* ]]; then
    print -u2 "FAIL filter/draw-on missing matching session"
    (( fails++ ))
  fi
  if [[ $plain == *other-new* ]]; then
    print -u2 "FAIL filter/draw-on showed excluded other-new"
    (( fails++ ))
  fi
  if [[ $plain != *退出* ]]; then
    print -u2 "FAIL filter/draw-on missing action 退出"
    (( fails++ ))
  fi
  if [[ $plain != *'f 显示全部'* ]]; then
    print -u2 "FAIL filter/draw-on missing f 显示全部"
    (( fails++ ))
  fi

  HOME=$oldhome
  rm -rf "$testhome"

  items_kind=(session session)
  items_id=(keep loose)
  items_name=(keep loose)
  items_att=(0 0)
  items_time=('01-01 00:00' '01-01 00:00')
  items_path=('~/keep' '~/loose')
  items_summary=('sa' 'sb')
  items_cmd=(zsh zsh)
  items_pinned=(1 0)
  w_name=8 w_status=6 w_time=11
  show_summary=0
  show_path=0
  _fmt_session_row 1
  if [[ $REPLY != keep\** ]]; then
    print -u2 "FAIL pin/marker-on missing keep* got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi
  _fmt_session_row 2
  if [[ $REPLY == *loose\** ]]; then
    print -u2 "FAIL pin/marker-off showed * on unpinned got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi

  oldhome=$HOME
  testhome=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-pin.XXXXXX")
  HOME=$testhome
  mkdir -p "$HOME/Library/Application Support/lanjump"

  pin_fixture() {
    items_kind=(session session session session new shell hosts quit)
    items_id=(idle-pin idle-free busy-free busy-pin new shell hosts quit)
    items_name=("${items_id[@]}")
    items_att=(0 0 1 1 '' '' '' '')
    items_time=('01-01 00:00' '01-01 00:00' '01-01 00:00' '01-01 00:00' '' '' '' '')
    items_activity=(1 2 3 4 '' '' '' '')
    items_path=('~/pin' '~/free' '~/busy' '~/busypin' '' '' '' '')
    items_summary=(sa sb sc sd '' '' '' '')
    items_cmd=(zsh zsh zsh zsh '' '' '' '')
    items_pinned=(1 0 0 1 '' '' '' '')
    all_kind=() all_id=() all_name=() all_att=() all_time=()
    all_path=() all_summary=() all_cmd=() all_activity=() all_pinned=()
    filter_include=
    filter_exclude=
    filter_on=0
    sort_mode=time
    cursor=1
    HAS_TMUX=1
  }

  pin_fixture
  expect pin/bulk-targets idle-free "$(bulk_idle_unpinned_names)"

  pin_fixture
  filter_include=idle
  filter_on=1
  copy_items_to_all
  filter_session_items
  expect pin/bulk-filter-targets idle-free "$(bulk_idle_unpinned_names)"

  local tmux_log killed
  tmux_log=$testhome/tmux.log
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      kill-session) return 0 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  pin_fixture
  delete_idle_unpinned_sessions
  killed=$(grep -E 'kill-session' "$tmux_log" | tr '\n' ' ')
  if [[ $killed != *'kill-session -t =idle-free'* ]]; then
    print -u2 "FAIL pin/bulk-kill missing idle-free got=$(printf %q "$killed")"
    (( fails++ ))
  fi
  if [[ $killed == *idle-pin* || $killed == *busy-free* || $killed == *busy-pin* ]]; then
    print -u2 "FAIL pin/bulk-kill hit protected session got=$(printf %q "$killed")"
    (( fails++ ))
  fi

  pin_fixture
  cursor=1
  if ! session_delete_needs_pin_warning; then
    print -u2 "FAIL pin/delete-warn pinned session skipped warning"
    (( fails++ ))
  fi
  expect pin/delete-warn-text '该 session 为常驻状态，是否确认删除？' "$(pin_delete_warning_text)"
  cursor=2
  if session_delete_needs_pin_warning; then
    print -u2 "FAIL pin/delete-warn unpinned session still warned"
    (( fails++ ))
  fi
  cursor=5
  if session_delete_needs_pin_warning; then
    print -u2 "FAIL pin/delete-warn action row warned"
    (( fails++ ))
  fi

  print -r -- $'name keep\ncwd /tmp/keep\ngrok gid-keep\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  rename_pin_record keep keep-renamed
  load_pinned_sessions
  if ! pin_record_exists keep-renamed; then
    print -u2 "FAIL pin/rename missing new name in pin file"
    (( fails++ ))
  fi
  if pin_record_exists keep; then
    print -u2 "FAIL pin/rename left old name in pin file"
    (( fails++ ))
  fi
  if [[ ${pinned_cwd[keep-renamed]:-} != /tmp/keep ]]; then
    print -u2 "FAIL pin/rename dropped cwd got=${pinned_cwd[keep-renamed]:-}"
    (( fails++ ))
  fi
  if [[ ${pinned_grok[keep-renamed]:-} != gid-keep ]]; then
    print -u2 "FAIL pin/rename dropped grok id got=${pinned_grok[keep-renamed]:-}"
    (( fails++ ))
  fi

  : >"$tmux_log"
  print -r -- $'name missing\ncwd /tmp/missing-cwd\ngrok gid-missing\n\nname still-live\ncwd /tmp/live\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session)
        [[ $2 == -t && $3 == '=still-live' ]] && return 0
        return 1
        ;;
      new-session|set-option|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  load_pinned_sessions
  restore_pinned_sessions
  local restore_log
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s missing -c /tmp/missing-cwd'* ]]; then
    print -u2 "FAIL pin/restore missing new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'grok --resume gid-missing'* ]]; then
    print -u2 "FAIL pin/restore missing grok resume got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s still-live'* ]]; then
    print -u2 "FAIL pin/restore recreated live session"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s idle-free'* ]]; then
    print -u2 "FAIL pin/restore created unpinned session"
    (( fails++ ))
  fi

  HOME=$oldhome
  rm -rf "$testhome"
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  if (( fails )); then
    print -u2 "pick-selftest: $fails failed"
    return 1
  fi
  print "ok pick"
  return 0
}
