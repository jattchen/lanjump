# Sourced by lanjump-pick.zsh --pick-selftest.
# Expects dw, fit_right, fit_left, fit_head_tail, padw, compute_layout, fmt_session_row, draw,
# sort_session_items, toggle_sort_mode, filter_session_items,
# toggle_session_filter, save_session_filter, load_session_filter,
# bulk_idle_unpinned_names, delete_idle_unpinned_sessions,
# forget_killed_session, drop_snap_record, rename_snap_record,
# session_delete_needs_pin_warning, pin_delete_warning_text,
# rename_pin_record, prompt_rename, restore_pinned_sessions, numeric_session_name,
# collect_restore_names, collect_work_session_names, should_restore_sessions, restore_saved_sessions,
# maybe_restore_sessions, print_workspace_names,
# has_named_session, ensure_named_session_for_attach,
# print_session_list,
# ghostty_restore_available, ghostty_osascript_for_sessions,
# ghostty_applescript_string, ghostty_focus_session,
# terminal_osascript_for_sessions,
# attaching_remote_host, attach_spec_for, attach_command_for, open_named_tabs,
# workspace_restore_prompt_text, short_command_name, useful_summary,
# load_settings, save_settings, cycle_setting, toggle_preview, effective_open_target,
# picker_open_mode, restore_pick_finish,
# resolve_session_cwd, picker_boot_before_first_draw, picker_boot_after_first_draw,
# preview_is_grok, preview_line_is_tool, preview_line_is_model,
# preview_grok_lines, preview_generic_lines, preview_select_lines,
# session_name_invalid, restore_csi_key, restore_plain_key, restore_read_key, restore_tty,
# draw_on_winch,
# attach_command_for, new_session_flag_invalid, prompt_new,
# prompt_new_pin_cwd, prompt_new_ask_pin, prompt_new_commit_pin, create_named_session, unique_non_numeric_session_name,
# ensure_pinnable_session_name, pin_named_session, toggle_session_pin, read_key, read_key_or_exit,
# restore_read_key_or_exit, settings_input_read, settings_input_read_or_exit, PENDING_KEY.

_pick_src_file=${0:A:h}/lanjump-pick.zsh

# Relative wall-clock gate for pick selftest perf loops (#223).
# work_ms vs empty-loop baseline_ms, with typical_ms as the documented
# healthy cost. Prints 1 if acceptable, 0 if work exceeds 10x
# (baseline + typical) — the old ~12s fmt_session_row path, not 105–286ms jitter.
pick_selftest_wall_ok() {
  local -F 3 work_ms=$1 baseline_ms=$2 typical_ms=$3 limit
  if (( baseline_ms < 0 )); then
    baseline_ms=0
  fi
  if (( typical_ms < 1 )); then
    typical_ms=1
  fi
  limit=$(( 10.0 * (baseline_ms + typical_ms) ))
  if (( work_ms > limit )); then
    print -r -- 0
  else
    print -r -- 1
  fi
}

pick_selftest() {
  local -i fails=0
  local got
  zmodload zsh/datetime || return 1
  zmodload zsh/system || return 1

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
  # /Users/mac/Documents/projects/lanjump is 37 cols. max 20 → keep 19, head 9, tail 10.
  expect fit_head_tail/short hello "$(fit_head_tail hello 10)"
  expect fit_head_tail/one … "$(fit_head_tail hello 1)"
  expect fit_head_tail/two '…o' "$(fit_head_tail hello 2)"
  expect fit_head_tail/three 'h…o' "$(fit_head_tail hello 3)"
  expect fit_head_tail/ascii 'h…lo' "$(fit_head_tail hello 4)"
  expect fit_head_tail/path '/Users/ma…ts/lanjump' "$(fit_head_tail /Users/mac/Documents/projects/lanjump 20)"
  expect fit_head_tail/preview36 '/Users/mac/Docume…s/projects/lanjump' "$(fit_head_tail /Users/mac/Documents/projects/lanjump 36)"
  expect fit_head_tail/cjk5 中…试 "$(fit_head_tail 中文测试 5)"
  expect fit_head_tail/cjk7 中文…试 "$(fit_head_tail 中文测试 7)"
  expect padw/ascii 'ab   ' "$(padw ab 5)"
  expect padw/cjk '中文  ' "$(padw 中文 6)"
  expect padw/trunc hel… "$(padw hello 4)"

  local sample longline
  sample="这是一段中文预览文字 mixed with ascii and ████ blocks"
  longline=$(printf '%s' {1..40} | tr -d '\n')
  longline="${sample} ${longline} ${sample}"

  local -i n
  local -F 3 t0 t1 ms baseline_ms
  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    :
  done
  t1=$EPOCHREALTIME
  baseline_ms=$(( (t1 - t0) * 1000 ))
  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    fit_right "$longline" 80 >/dev/null
  done
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old per-character $(dw) path was ~3000ms for this case.
  if [[ $(pick_selftest_wall_ok $ms $baseline_ms 80) != 1 ]]; then
    print -u2 "FAIL fit_right perf ${ms}ms baseline=${baseline_ms}ms (10x typical 80ms)"
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
  _fmt_header
  if [[ $REPLY != *程序* ]]; then
    print -u2 "FAIL header/program missing 程序 got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi
  if [[ $REPLY == *摘要* ]]; then
    print -u2 "FAIL header/program still 摘要 got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi
  # #223: 105–286ms for 160 fmt_session_row calls is scheduling jitter, not a
  # user-visible picker delay. The 100ms wall is too tight; the gate must
  # accept that range and still flag the old ~12s path (10x-class).
  expect pick-selftest/fmt-row-perf-allows-issue-286ms 1 "$(pick_selftest_wall_ok 286 2 192)"
  expect pick-selftest/fmt-row-perf-flags-old-12s 0 "$(pick_selftest_wall_ok 12000 2 192)"

  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    for i in {1..8}; do
      :
    done
  done
  t1=$EPOCHREALTIME
  baseline_ms=$(( (t1 - t0) * 1000 ))
  t0=$EPOCHREALTIME
  for (( n = 0; n < 20; n++ )); do
    for i in {1..8}; do
      _fmt_session_row $i
    done
  done
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old path was ~80ms per row, ~12s for this loop. Typical 192ms is 1.2ms/row * 160.
  if [[ $(pick_selftest_wall_ok $ms $baseline_ms 192) != 1 ]]; then
    print -u2 "FAIL fmt_session_row perf ${ms}ms baseline=${baseline_ms}ms (10x typical 192ms)"
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
  expect preview/blank-collapse $'keep\nreal █ line\nend' "${(F)preview_lines}"

  mock_pane=$'hello\n────────'
  : > "$mock_log"
  session_preview_lines sh-sess 10 zsh
  expect preview/skip-status hello "${(F)preview_lines}"

  mock_pane=$(print -l line-{1..20})
  : > "$mock_log"
  session_preview_lines sh-sess 30 zsh
  if (( ${#preview_lines} != 3 )); then
    print -u2 "FAIL preview/cap got ${#preview_lines} want 3"
    (( fails++ ))
  fi
  expect preview/cap-tail $'line-18\nline-19\nline-20' "${(F)preview_lines}"

  mock_pane=$'a\nb'
  : > "$mock_log"
  session_preview_lines grok-sess 5 grok
  load_tmux_calls
  if (( tmux_n != 1 )); then
    print -u2 "FAIL preview/grok-once got ${tmux_n} captures want 1"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-J]} -gt ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/grok-J missing -J in ${(j: :)tmux_argv}"
    (( fails++ ))
  fi
  if [[ ${tmux_argv[(ie)-a]} -le ${#tmux_argv} ]]; then
    print -u2 "FAIL preview/grok-no-alt got ${(j: :)tmux_argv}"
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

  tmuxx() {
    print -r -- "${(j: :)@}" >> "$mock_log"
    print -r -- "$mock_pane"
  }
  session_titles=()

  mock_pane=$'Grok 4.6\n────────────────\n怎么改 tmux 预览\n可以先丢掉状态条\n────────────────\n>\n█'
  : > "$mock_log"
  session_preview_lines grok-sess 6 grok
  expect preview/drop-chrome $'怎么改 tmux 预览\n可以先丢掉状态条' "${(F)preview_lines}"

  mock_pane=$'zsh\n% ls\nlanjump-pick.zsh\nREADME.md\n% '
  : > "$mock_log"
  session_preview_lines sh-sess 6 zsh
  expect preview/shell-keep $'% ls\nlanjump-pick.zsh\nREADME.md' "${(F)preview_lines}"

  mock_pane=$'Grok 4.6\n────────\n可以丢掉状态条\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]='怎么改预览 - grok'
  session_preview_lines grok-sess 6 grok
  expect preview/title-heading '怎么改预览' "$preview_heading"
  expect preview/title '可以丢掉状态条' "${(F)preview_lines}"
  session_titles=()

  expect preview/useful-title '怎么改预览' "$(preview_useful_title '怎么改预览 - grok' grok-sess grok)"
  expect preview/useful-title-name '' "$(preview_useful_title grok-sess grok-sess grok)"
  expect preview/useful-title-cmd '' "$(preview_useful_title grok grok-sess grok)"
  expect preview/useful-title-tomax '' "$(preview_useful_title ToMax grok-sess grok)"
  expect preview/useful-title-grokver '' "$(preview_useful_title 'Grok 4.6' grok-sess grok)"
  expect preview/useful-title-grokstar '' "$(preview_useful_title grok-1.0.13-mac grok-sess zsh)"
  preview_line_is_chrome ToMax
  expect preview/chrome-tomax 0 "$?"
  preview_line_is_chrome 'Grok 4.6'
  expect preview/chrome-grokver 0 "$?"
  preview_line_is_chrome '怎么改 tmux 预览'
  expect preview/chrome-body 1 "$?"
  expect preview/heading-from-pane '怎么改 tmux 预览' "$(preview_conversation_heading ToMax $'────────' '怎么改 tmux 预览' '可以先丢掉状态条' '>')"
  expect preview/heading-skip-prompt '怎么改 tmux 预览' "$(preview_conversation_heading '% ls' '怎么改 tmux 预览' 'body')"

  mock_pane=$'Grok 4.6\n────────\n可以丢掉状态条\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]=grok-sess
  session_preview_lines grok-sess 6 grok
  expect preview/title-skip '可以丢掉状态条' "${(F)preview_lines}"
  session_titles=()

  mock_pane=$'Grok 4.6\n────────\nkeep-1\nkeep-2\nkeep-3\nkeep-4\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]='怎么改预览 - grok'
  session_preview_lines grok-sess 3 grok
  expect preview/title-last $'keep-2\nkeep-3\nkeep-4' "${(F)preview_lines}"
  session_titles=()

  mock_pane=$'ToMax\n────────\n怎么改 tmux 预览\n可以先丢掉状态条\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]=ToMax
  session_preview_lines grok-sess 6 grok
  expect preview/tomax-heading $'怎么改 tmux 预览\n可以先丢掉状态条' "${(F)preview_lines}"
  if [[ ${(F)preview_lines} == ToMax* || ${(F)preview_lines} == *$'ToMax\n'* ]]; then
    print -u2 "FAIL preview/tomax-not-title got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi
  if [[ ${(F)preview_lines} != *$'\n'* ]]; then
    print -u2 "FAIL preview/tomax-missing-body got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi
  session_titles=()

  mock_pane=$'Grok 4.6\n────────\n怎么改 tmux 预览\nkeep-1\nkeep-2\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]='Grok 4.6'
  session_preview_lines grok-sess 6 grok
  expect preview/shape-two-part $'怎么改 tmux 预览\nkeep-1\nkeep-2' "${(F)preview_lines}"
  session_titles=()

  mock_pane=$'Grok 4.6\n────────\n怎么改预览 - grok\n可以丢掉状态条\n────────\n>'
  : > "$mock_log"
  session_titles[grok-sess]='怎么改预览 - grok'
  session_preview_lines grok-sess 6 grok
  expect preview/shape-real-title $'怎么改预览 - grok\n可以丢掉状态条' "${(F)preview_lines}"
  session_titles=()

  tmuxx() {
    print -r -- "${(j: :)@}" >> "$mock_log"
    if [[ ${argv[(ie)-a]} -le ${#argv} ]]; then
      print -r -- $'ToMax\n────────\n>\n█'
    else
      print -r -- $'怎么改 tmux 预览\n最后有用的输出'
    fi
  }
  : > "$mock_log"
  session_titles[grok-sess]=ToMax
  session_preview_lines grok-sess 6 grok
  expect preview/grok-retry-body $'怎么改 tmux 预览\n最后有用的输出' "${(F)preview_lines}"
  session_titles=()
  tmuxx() {
    print -r -- "${(j: :)@}" >> "$mock_log"
    print -r -- "$mock_pane"
  }

  preview_is_grok grok-1.0.13-mac
  expect preview/is-grok 0 "$?"
  preview_is_grok zsh
  expect preview/is-grok-sh 1 "$?"
  preview_line_is_tool 'Calling github__issue_read'
  expect preview/tool-calling 0 "$?"
  preview_line_is_tool '{"name":"github__issue_read"}'
  expect preview/tool-json 0 "$?"
  preview_line_is_tool '预览要有标题吗'
  expect preview/tool-question 1 "$?"
  preview_line_is_model 'Grok 4.6'
  expect preview/model-ver 0 "$?"
  preview_line_is_model '要，还要最后几行'
  expect preview/model-answer 1 "$?"

  expect preview/grok-qa-fn $'预览要有标题吗\n要，还要最后几行' "$(preview_grok_lines 3 ToMax 'Grok 4.6' $'────────' '预览要有标题吗' 'Calling github__issue_read' '{"name":"github__issue_read"}' '要，还要最后几行' '>')"
  expect preview/generic-ls-fn $'% ls\nlanjump-pick.zsh\nREADME.md' "$(preview_generic_lines 3 zsh '% ls' 'lanjump-pick.zsh' 'README.md' '%')"
  expect preview/select-grok $'预览要有标题吗\n要，还要最后几行' "$(preview_select_lines grok 3 ToMax 'Grok 4.6' '预览要有标题吗' 'Calling github__issue_read' '要，还要最后几行')"
  expect preview/select-zsh $'% ls\nlanjump-pick.zsh\nREADME.md' "$(preview_select_lines zsh 3 zsh '% ls' 'lanjump-pick.zsh' 'README.md' '%')"

  mock_pane=$'ToMax\nGrok 4.6\n────────────────\n预览要有标题吗\nCalling github__issue_read\n{"name":"github__issue_read"}\n要，还要最后几行\n────────────────\n>\n█'
  : > "$mock_log"
  session_titles[grok-sess]=ToMax
  session_preview_lines grok-sess 6 grok
  expect preview/grok-qa $'预览要有标题吗\n要，还要最后几行' "${(F)preview_lines}"
  if [[ ${(F)preview_lines} == *'Grok 4.6'* ]]; then
    print -u2 "FAIL preview/grok-qa-no-model got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi
  if [[ ${(F)preview_lines} == *Calling* || ${(F)preview_lines} == *github__issue_read* ]]; then
    print -u2 "FAIL preview/grok-qa-no-tool got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi
  if [[ ${(F)preview_lines} == *ToMax* ]]; then
    print -u2 "FAIL preview/grok-qa-no-tomax got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi
  session_titles=()

  mock_pane=$'zsh\n% ls\nlanjump-pick.zsh\nREADME.md\n% '
  : > "$mock_log"
  session_preview_lines sh-sess 6 zsh
  expect preview/generic-ls $'% ls\nlanjump-pick.zsh\nREADME.md' "${(F)preview_lines}"
  if [[ ${(F)preview_lines} == $'% '* && ${(F)preview_lines} != *lanjump-pick.zsh* ]]; then
    print -u2 "FAIL preview/generic-not-only-prompt got=$(printf %q "${(F)preview_lines}")"
    (( fails++ ))
  fi

  local footer_responding footer_modelbox footer_shortcuts footer_thought footer_run footer_read footer_spin footer_box
  footer_responding='⠹ - Responding - Write LoopX coordinator Goal for remaini… - grok'
  footer_modelbox='╰────────────────…Grok 4.6 (xhigh) · always-approve ─╯'
  footer_shortcuts=$'Ctrl+\\:dashboard  │  Ctrl+[/]:prev…│  Space:prompt  │  Ctrl+.:shortcuts'
  footer_thought='◆ Thought for 22.6s'
  footer_run='◆ Run Consume LoopX turn-start quota packet once'
  footer_read='◈ Read 2 files'
  footer_spin='⠴ Save full Grok...'
  footer_box='│ ❯'
  preview_line_is_chrome "$footer_responding"
  expect preview/footer-responding 0 "$?"
  preview_line_is_chrome "$footer_modelbox"
  expect preview/footer-modelbox 0 "$?"
  preview_line_is_chrome "$footer_shortcuts"
  expect preview/footer-shortcuts 0 "$?"
  preview_line_is_tool "$footer_run"
  expect preview/tool-run 0 "$?"
  preview_line_is_tool "$footer_read"
  expect preview/tool-read 0 "$?"
  preview_line_is_tool "$footer_thought"
  expect preview/tool-thought 0 "$?"
  expect preview/footer-only '' "$(preview_grok_lines 3 "$footer_responding" "$footer_modelbox" "$footer_shortcuts")"
  expect preview/live-footer-dump $'预览要有标题吗\n要，还要最后几行' "$(preview_grok_lines 3 "$footer_responding" "$footer_modelbox" "$footer_shortcuts" "$footer_thought" "$footer_run" "$footer_read" "$footer_spin" "$footer_box" '❯ 预览要有标题吗' '要，还要最后几行')"
  expect preview/live-footer-mention $'你贴的这段预览还是 Grok 底栏：Responding、Grok 4.6 (xhigh)、快捷键，不是问题和回复。' "$(preview_grok_lines 1 "$footer_responding" "$footer_modelbox" "$footer_shortcuts" '你贴的这段预览还是 Grok 底栏：Responding、Grok 4.6 (xhigh)、快捷键，不是问题和回复。')"

  mock_pane="${footer_thought}"$'\n'"${footer_run}"$'\n'"${footer_read}"$'\n''❯ 预览要有标题吗'$'\n''要，还要最后几行'$'\n'"${footer_responding}"$'\n'"${footer_modelbox}"$'\n'"${footer_shortcuts}"$'\n'"${footer_spin}"$'\n'"${footer_box}"
  : > "$mock_log"
  session_titles[grok-sess]=ToMax
  session_preview_lines grok-sess 6 grok
  expect preview/live-footer-session $'预览要有标题吗\n要，还要最后几行' "${(F)preview_lines}"
  session_titles=()

  preview_line_is_status 'Worked for 4m11s'
  expect preview/status-worked 0 "$?"
  preview_line_is_status 'Worked for 1m29s'
  expect preview/status-worked-short 0 "$?"
  preview_line_is_status $'⠹ - Waiting for response… - 手机 Shadowrocket 分流兼进家里内网 - grok'
  expect preview/status-waiting 0 "$?"
  preview_line_is_chrome '▼'
  expect preview/chrome-arrow 0 "$?"
  expect preview/clean-title-suffix '新建 devloop 仓库并规划 LoopX 自主长跑' "$(preview_clean_title '新建 devloop 仓库并规划 LoopX 自主长跑 - grok')"
  expect preview/clean-title-waiting '手机 Shadowrocket 分流兼进家里内网' "$(preview_clean_title $'⠹ - Waiting for response… - 手机 Shadowrocket 分流兼进家里内网 - grok')"

  local panes dump out
  panes=/var/folders/hb/21sdw0893vxbvq2wpch2rpxr0000gn/T/grok-goal-2b0ef817ca46/implementer/panes
  if [[ ! -f $panes/devloop-main.txt || ! -f $panes/sysmtn-main.txt ]]; then
    print -u2 "skip preview/render-dumps missing $panes"
  else
    dump=$(<"$panes/devloop-main.txt")
    out=$(preview_render_grok devloop '新建 devloop 仓库并规划 LoopX 自主长跑 - grok' grok-1.0.25-mac "$dump")
    local scratch=/var/folders/hb/21sdw0893vxbvq2wpch2rpxr0000gn/T/grok-goal-2b0ef817ca46/implementer/preview-render-devloop-sysmtn.txt
    {
      print -r -- '=== devloop ==='
      print -r -- "$out"
    } > "$scratch"
    if [[ $out != *'标题：新建 devloop 仓库并规划 LoopX 自主长跑'* ]]; then
      print -u2 "FAIL preview/render-devloop-title got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out != *开分支改* ]]; then
      print -u2 "FAIL preview/render-devloop-ask got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'Worked for'* ]]; then
      print -u2 "FAIL preview/render-devloop-worked got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'grok-1.0.25-mac'* ]]; then
      print -u2 "FAIL preview/render-devloop-ver got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'~/Documents/projects'* ]]; then
      print -u2 "FAIL preview/render-devloop-path got=$(printf %q "$out")"
      (( fails++ ))
    fi
    dump=$(<"$panes/sysmtn-main.txt")
    out=$(preview_render_grok sysmtn $'⠹ - Waiting for response… - 手机 Shadowrocket 分流兼进家里内网 - grok' grok-1.0.25-mac "$dump")
    {
      print -r -- ''
      print -r -- '=== sysmtn ==='
      print -r -- "$out"
    } >> "$scratch"
    if [[ $out != *'标题：手机 Shadowrocket 分流兼进家里内网'* ]]; then
      print -u2 "FAIL preview/render-sysmtn-title got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out != *你改哪了* && $out != *Shadowrocket* ]]; then
      print -u2 "FAIL preview/render-sysmtn-body got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'Waiting for response'* ]]; then
      print -u2 "FAIL preview/render-sysmtn-waiting got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'11:18 PM'* ]]; then
      print -u2 "FAIL preview/render-sysmtn-clock got=$(printf %q "$out")"
      (( fails++ ))
    fi
    if [[ $out == *'grok-1.0.25-mac'* ]]; then
      print -u2 "FAIL preview/render-sysmtn-ver got=$(printf %q "$out")"
      (( fails++ ))
    fi
  fi

  HAS_TMUX=1
  host_short=testhost
  preview_on=1
  preview_defer=0
  preview_cache=()
  COLUMNS=40
  LINES=24
  cursor=1
  items_kind=(session)
  items_id=(grok-sess)
  items_name=(grok-sess)
  items_att=(0)
  items_time=('09-04 12:00')
  items_path=('~/p')
  items_summary=('sum')
  items_cmd=(grok)
  items_activity=('')
  items_pinned=('0')
  mock_pane='/Users/mac/Documents/projects/lanjump'
  : > "$mock_log"
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain == *'/Users/mac/Docume…s/projects/lanjump'* ]]; then
    got=1
  else
    got=0
  fi
  expect draw/preview-head-tail 1 "$got"
  if [[ $plain == *'/Users/mac/Documents/projects/lanju…'* ]]; then
    print -u2 "FAIL draw/preview-only-head clipped with fit_right"
    (( fails++ ))
  fi
  if [[ $plain == *'…sers/mac/Documents/projects/lanjump'* ]]; then
    print -u2 "FAIL draw/preview-only-tail clipped with fit_left"
    (( fails++ ))
  fi
  COLUMNS=120
  LINES=40

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
  :
  t1=$EPOCHREALTIME
  baseline_ms=$(( (t1 - t0) * 1000 ))
  t0=$EPOCHREALTIME
  draw >/dev/null
  t1=$EPOCHREALTIME
  ms=$(( (t1 - t0) * 1000 ))
  # Old draw was ~700ms even without tmux capture-pane. Typical 50ms keeps a 10x catch.
  if [[ $(pick_selftest_wall_ok $ms $baseline_ms 50) != 1 ]]; then
    print -u2 "FAIL draw perf ${ms}ms baseline=${baseline_ms}ms (10x typical 50ms)"
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
    view_scope=all
    view_recent_n=0
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
  if [[ $plain != *', 设置'* ]]; then
    print -u2 "FAIL help/settings missing , 设置"
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
    view_scope=all
    view_recent_n=0
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

  # #250: two print redirects can leave dest with only include.
  if [[ ${functions[save_session_filter]} != *replace_file_atomic* || ${functions[save_session_filter]} == *'>>'* ]]; then
    print -u2 "FAIL filter/atomic-write still uses > then >> (or is missing replace_file_atomic)"
    (( fails++ ))
  fi

  # #357: another picker may persist exclude while this one only changes include.
  local filt357_home filt357_saved_home filt357_file
  filt357_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-357-filter.XXXXXX") || return 1
  filt357_saved_home=$HOME
  HOME=$filt357_home
  mkdir -p "$HOME/Library/Application Support/lanjump" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/lanjump"
  session_filter_file
  filt357_file=$REPLY
  mkdir -p "${filt357_file:h}"
  print -r -- $'include foo\nexclude old\n' >"$filt357_file"
  load_session_filter
  filter_include=bar
  print -r -- $'include foo\nexclude other\n' >"$filt357_file"
  save_session_filter
  load_session_filter
  expect filter/merge-underfoot-include bar "$filter_include"
  expect filter/merge-underfoot-exclude other "$filter_exclude"
  HOME=$filt357_saved_home
  rm -rf "$filt357_home"

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

  # #480: --view narrows session rows. o reorders that set; it does not swap in others.
  view_fixture() {
    items_kind=(session session session session session new shell hosts quit)
    items_id=(alpha beta gamma delta epsilon new shell hosts quit)
    items_name=("${items_id[@]}")
    items_att=(0 1 0 0 1 '' '' '' '')
    items_time=('01-01 00:01' '01-01 00:02' '01-01 00:03' '01-01 00:04' '01-01 00:05' '' '' '' '')
    items_activity=(10 40 30 50 20 '' '' '' '')
    items_path=('~/a' '~/b' '~/c' '~/d' '~/e' '' '' '' '')
    items_summary=(keepme other keepme other other '' '' '' '')
    items_cmd=(zsh zsh zsh zsh zsh '' '' '' '')
    items_pinned=(1 0 1 0 0 '' '' '' '')
    all_kind=() all_id=() all_name=() all_att=() all_time=()
    all_path=() all_summary=() all_cmd=() all_activity=() all_pinned=()
    filter_include=
    filter_exclude=
    filter_on=0
    sort_mode=time
    cursor=1
    HAS_TMUX=1
    host_short=testhost
    COLUMNS=120
    LINES=40
    view_scope=all
    view_recent_n=0
  }
  view_session_ids() {
    local -a ids sorted
    local id
    ids=()
    for id in "${items_id[@]}"; do
      case $id in
        new|shell|hosts|quit) ;;
        *) ids+=("$id") ;;
      esac
    done
    sorted=("${(o)ids[@]}")
    print -r -- "${(j: :)sorted}"
  }

  view_fixture
  sort_session_items
  copy_items_to_all
  view_scope=recent
  view_recent_n=2
  filter_session_items
  expect view/recent-2 'beta delta' "$(view_session_ids)"
  if [[ ${items_id[*]} == *epsilon* || ${items_id[*]} == *alpha* || ${items_id[*]} == *gamma* ]]; then
    print -u2 "FAIL view/recent-2 kept a session outside the newest two got=${items_id[*]}"
    (( fails++ ))
  fi
  before=$(view_session_ids)
  toggle_sort_mode
  expect view/recent-o-set "$before" "$(view_session_ids)"
  if [[ ${items_id[*]} == *epsilon* ]]; then
    print -u2 "FAIL view/recent-o swapped in epsilon got=${items_id[*]}"
    (( fails++ ))
  fi

  view_fixture
  view_scope=pinned
  filter_session_items
  expect view/pinned 'alpha gamma' "$(view_session_ids)"

  view_fixture
  view_scope=occupied
  filter_session_items
  expect view/occupied 'beta epsilon' "$(view_session_ids)"

  view_fixture
  sort_session_items
  copy_items_to_all
  view_scope=recent
  view_recent_n=3
  filter_include=keepme
  filter_on=1
  filter_session_items
  expect view/stack gamma "$(view_session_ids)"
  expect view/stack-count 1 "$filter_match_count"
  expect view/stack-total 3 "$filter_total_count"
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  title_line=${plain%%$'\n'*}
  if [[ $title_line != *'最近 3 个'* || $title_line != *'1/3'* ]]; then
    print -u2 "FAIL view/title-stack got=$(printf %q "$title_line")"
    (( fails++ ))
  fi

  view_fixture
  view_scope=pinned
  filter_on=1
  filter_include=zzzz
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'（没有匹配的 session）'* ]]; then
    print -u2 "FAIL view/keyword-miss missing 没有匹配的 session got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain == *'（没有常驻 session）'* ]]; then
    print -u2 "FAIL view/keyword-miss used the empty-range line"
    (( fails++ ))
  fi

  view_fixture
  items_pinned=(0 0 0 0 0 '' '' '' '')
  view_scope=pinned
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'（没有常驻 session）'* ]]; then
    print -u2 "FAIL view/empty-pinned got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain != *quit* ]]; then
    print -u2 "FAIL view/empty-pinned closed the list"
    (( fails++ ))
  fi

  view_fixture
  items_att=(0 0 0 0 0 '' '' '' '')
  view_scope=occupied
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'（没有占用中的 session）'* ]]; then
    print -u2 "FAIL view/empty-occupied got=$(printf %q "$plain")"
    (( fails++ ))
  fi

  view_fixture
  items_kind=(new shell hosts quit)
  items_id=(new shell hosts quit)
  items_name=('新建 session' '普通 shell' '换一台机器' '退出')
  items_att=('' '' '' '')
  items_time=('' '' '' '')
  items_activity=('' '' '' '')
  items_path=('' '' '' '')
  items_summary=('' '' '' '')
  items_cmd=('' '' '' '')
  items_pinned=('' '' '' '')
  all_kind=() all_id=() all_name=() all_att=() all_time=()
  all_path=() all_summary=() all_cmd=() all_activity=() all_pinned=()
  view_scope=recent
  view_recent_n=5
  filter_session_items
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'（没有最近的 session）'* ]]; then
    print -u2 "FAIL view/empty-recent got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  title_line=${plain%%$'\n'*}
  if [[ $title_line != *'最近 5 个'* ]]; then
    print -u2 "FAIL view/empty-recent-title got=$(printf %q "$title_line")"
    (( fails++ ))
  fi

  view_fixture
  view_scope=pinned
  filter_session_items
  if [[ ${items_id[1]} != alpha ]]; then
    print -u2 "FAIL view/unpin-setup cursor not alpha got=${items_id[1]}"
    (( fails++ ))
  fi
  cursor=1
  toggle_session_pin
  filter_session_items
  if [[ ${items_id[*]} == *alpha* ]]; then
    print -u2 "FAIL view/unpin alpha stayed after p got=${items_id[*]}"
    (( fails++ ))
  fi
  expect view/unpin-left gamma "$(view_session_ids)"

  view_fixture
  view_scope=pinned
  filter_include=
  filter_exclude=
  filter_on=0
  session_filter_file
  print -r -- $'include \nexclude \n' >"$REPLY"
  filter_session_items
  toggle_session_filter
  if [[ $view_scope != pinned ]]; then
    print -u2 "FAIL view/f-on cleared the range got=$view_scope"
    (( fails++ ))
  fi
  expect view/f-on 'alpha gamma' "$(view_session_ids)"
  toggle_session_filter
  if [[ $view_scope != pinned ]]; then
    print -u2 "FAIL view/f-off cleared the range got=$view_scope"
    (( fails++ ))
  fi
  expect view/f-off 'alpha gamma' "$(view_session_ids)"

  view_scope=recent
  view_recent_n=4
  filter_include=aa
  filter_exclude=bb
  save_session_filter
  session_filter_file
  got=$(<"$REPLY")
  if [[ $got == *recent* || $got == *pinned* || $got == *occupied* || $got == *view_scope* ]]; then
    print -u2 "FAIL view/not-saved wrote the range got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *'include aa'* || $got != *'exclude bb'* ]]; then
    print -u2 "FAIL view/not-saved dropped keywords got=$(printf %q "$got")"
    (( fails++ ))
  fi
  load_session_filter
  if [[ $view_scope != recent || $view_recent_n != 4 ]]; then
    print -u2 "FAIL view/not-saved load changed scope=$view_scope n=$view_recent_n"
    (( fails++ ))
  fi

  view_scope=all
  view_recent_n=0
  launch_shell_only=0
  attach_shell_only=0
  parse_picker_launch_args --view recent:7 --shell
  if [[ $view_scope != recent || $view_recent_n != 7 || $launch_shell_only != 1 || $attach_shell_only != 1 ]]; then
    print -u2 "FAIL view/parse-shell scope=$view_scope n=$view_recent_n shell=$launch_shell_only attach=$attach_shell_only"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *launch_shell_only* ]]; then
    print -u2 "FAIL view/shell-sticky attach clears --shell for later enters"
    (( fails++ ))
  fi
  view_scope=all
  view_recent_n=0
  launch_shell_only=0
  attach_shell_only=0
  parse_picker_launch_args --shell --view pinned
  if [[ $view_scope != pinned || $launch_shell_only != 1 ]]; then
    print -u2 "FAIL view/parse-order scope=$view_scope shell=$launch_shell_only"
    (( fails++ ))
  fi
  st=0
  err=$(parse_picker_launch_args --view recent:0 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL view/parse-zero accepted recent:0"
    (( fails++ ))
  fi
  st=0
  err=$(parse_picker_launch_args --view recent:01 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL view/parse-pad accepted recent:01"
    (( fails++ ))
  fi
  st=0
  err=$(parse_picker_launch_args --view nope 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL view/parse-bad accepted nope"
    (( fails++ ))
  fi
  view_scope=all
  view_recent_n=0
  launch_shell_only=0
  attach_shell_only=0
  filter_include=
  filter_exclude=
  filter_on=0

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
    view_scope=all
    view_recent_n=0
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

  # #158: bulk X skips idle unpinned foreign sessions (bmx-*).
  pin_fixture
  items_kind=(session session new shell hosts quit)
  items_id=(bmx-foo demo new shell hosts quit)
  items_name=("${items_id[@]}")
  items_att=(0 0 '' '' '' '')
  items_time=('01-01 00:00' '01-01 00:00' '' '' '' '')
  items_activity=(1 2 '' '' '' '')
  items_path=('~/bmx' '~/demo' '' '' '' '')
  items_summary=(sa sb '' '' '' '')
  items_cmd=(zsh zsh '' '' '' '')
  items_pinned=(0 0 '' '' '' '')
  expect pin/bulk-skip-foreign demo "$(bulk_idle_unpinned_names)"
  : >"$tmux_log"
  delete_idle_unpinned_sessions
  killed=$(grep -E 'kill-session' "$tmux_log" | tr '\n' ' ')
  if [[ $killed == *bmx-foo* ]]; then
    print -u2 "FAIL pin/bulk-kill-foreign hit bmx-foo got=$(printf %q "$killed")"
    (( fails++ ))
  fi
  if [[ $killed != *'kill-session -t =demo'* ]]; then
    print -u2 "FAIL pin/bulk-kill-foreign missing demo got=$(printf %q "$killed")"
    (( fails++ ))
  fi

  # #93: last-session delete must persist an empty snapshot. load_items
  # skips snapshot_live_sessions when list-sessions is empty, so the
  # kill path itself has to drop the name from snap/pin.
  setup_last_snap() {
    local gone=$1
    shift
    snap_names=("$@")
    snap_cwd=()
    snap_occupied=()
    snap_workspace=()
    snap_cmd=()
    snap_attached=()
    local n
    for n in "${snap_names[@]}"; do
      snap_cwd[$n]=/tmp/$n
      snap_occupied[$n]=1
      snap_workspace[$n]=1
      snap_cmd[$n]=zsh
      snap_attached[$n]=$EPOCHSECONDS
    done
    save_session_snapshot
    pinned_names=()
    pinned_cwd=()
    pinned_grok=()
    : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    items_kind=(session new shell hosts quit)
    items_id=("$gone" new shell hosts quit)
    items_name=("${items_id[@]}")
    items_att=(0 '' '' '' '')
    items_pinned=(0 '' '' '' '')
    items_time=('01-01 00:00' '' '' '' '')
    items_activity=(1 '' '' '' '')
    items_path=('~/gone' '' '' '' '')
    items_summary=(sa '' '' '' '')
    items_cmd=(zsh '' '' '' '')
    cursor=1
    HAS_TMUX=1
  }

  setup_last_snap last-one last-one
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      kill-session) return 0 ;;
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  delete_idle_unpinned_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)last-one]} -ne 0 ]]; then
    print -u2 "FAIL delete/last-snap still has last-one got=${snap_names[*]}"
    (( fails++ ))
  fi
  session_snapshot_file
  if grep -qx 'name last-one' "$REPLY"; then
    print -u2 "FAIL delete/last-snap file still has last-one"
    (( fails++ ))
  fi
  if should_restore_sessions; then
    print -u2 "FAIL delete/last-snap should not restore after last kill"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s last-one'* ]]; then
    print -u2 "FAIL delete/last-snap restored last-one got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  setup_last_snap gone keep gone
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      kill-session) return 0 ;;
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  delete_idle_unpinned_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)gone]} -ne 0 ]]; then
    print -u2 "FAIL delete/keep-snap still has gone got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)keep]} -eq 0 ]]; then
    print -u2 "FAIL delete/keep-snap dropped keep got=${snap_names[*]}"
    (( fails++ ))
  fi

  setup_last_snap last-one last-one
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      kill-session) return 1 ;;
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  delete_idle_unpinned_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)last-one]} -eq 0 ]]; then
    print -u2 "FAIL delete/failed-kill dropped last-one from snap"
    (( fails++ ))
  fi

  # #406: bulk X must not treat a forget write failure as a clean delete.
  # Remaining picker rows used to wipe the failed status, so X looked
  # successful while disk still had the names for restore / work.
  setup_last_snap gone gone keep-idle
  items_kind=(session session new shell hosts quit)
  items_id=(gone keep-idle new shell hosts quit)
  items_name=("${items_id[@]}")
  items_att=(0 0 '' '' '' '')
  items_pinned=(0 0 '' '' '' '')
  items_time=('01-01 00:00' '01-01 00:00' '' '' '' '')
  items_activity=(1 2 '' '' '' '')
  items_path=('~/gone' '~/keep' '' '' '' '')
  items_summary=(sa sb '' '' '' '')
  items_cmd=(zsh zsh '' '' '' '')
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      kill-session) return 0 ;;
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  functions -c save_session_snapshot _save406
  save_session_snapshot() { return 1 }
  local -i del406_st=0
  delete_idle_unpinned_sessions || del406_st=$?
  functions -c _save406 save_session_snapshot
  unset -f _save406
  if (( del406_st == 0 )); then
    print -u2 "FAIL delete/bulk-forget-write-fail reported success"
    (( fails++ ))
  fi
  killed=$(grep -E 'kill-session' "$tmux_log" | tr '\n' ' ')
  if [[ $killed != *'kill-session -t =gone'* || $killed != *'kill-session -t =keep-idle'* ]]; then
    print -u2 "FAIL delete/bulk-forget-write-fail stopped early got=$(printf %q "$killed")"
    (( fails++ ))
  fi
  load_session_snapshot
  if [[ ${snap_names[(Ie)gone]} -eq 0 || ${snap_names[(Ie)keep-idle]} -eq 0 ]]; then
    print -u2 "FAIL delete/bulk-forget-write-fail dropped snap names got=${snap_names[*]}"
    (( fails++ ))
  fi
  if should_restore_sessions; then
    print -u2 "FAIL delete/bulk-forget-write-fail restored unpinned names"
    (( fails++ ))
  fi

  if [[ ${functions[prompt_delete]} != *forget_killed_session* ]]; then
    print -u2 "FAIL delete/prompt missing forget_killed_session"
    (( fails++ ))
  fi
  if [[ ${functions[delete_idle_unpinned_sessions]} != *forget_killed_session* ]]; then
    print -u2 "FAIL delete/bulk missing forget_killed_session"
    (( fails++ ))
  fi

  setup_last_snap last-one last-one
  add_pin_record last-one /tmp/last-one
  forget_killed_session last-one
  load_session_snapshot
  load_pinned_sessions
  if [[ ${snap_names[(Ie)last-one]} -ne 0 ]]; then
    print -u2 "FAIL delete/forget-snap still has last-one got=${snap_names[*]}"
    (( fails++ ))
  fi
  if pin_record_exists last-one; then
    print -u2 "FAIL delete/forget-pin still has last-one"
    (( fails++ ))
  fi
  session_snapshot_file
  if grep -qx 'name last-one' "$REPLY"; then
    print -u2 "FAIL delete/forget-snap file still has last-one"
    (( fails++ ))
  fi
  if should_restore_sessions; then
    print -u2 "FAIL delete/forget-pin should not restore"
    (( fails++ ))
  fi

  # #405: forget_killed_session must take pin then snapshot (upgrade #386).
  # Holding session-snapshot then taking pin deadlocks with upgrade.
  # The 5s flock timeout would turn that into a skipped write; order still matters.
  local -a lock405_order
  local -i lock405_pin=-1 lock405_snap=-1 lock405_i
  setup_last_snap gone gone
  add_pin_record gone /tmp/gone
  functions -c with_data_file_lock _lock405_with
  lock405_order=()
  with_data_file_lock() {
    lock405_order+=("${1:t}")
    _lock405_with "$@"
  }
  forget_killed_session gone
  functions -c _lock405_with with_data_file_lock
  unset -f _lock405_with
  for (( lock405_i = 1; lock405_i <= ${#lock405_order}; lock405_i++ )); do
    if [[ ${lock405_order[lock405_i]} == pinned-sessions && lock405_pin -lt 0 ]]; then
      lock405_pin=$lock405_i
    fi
    if [[ ${lock405_order[lock405_i]} == session-snapshot && lock405_snap -lt 0 ]]; then
      lock405_snap=$lock405_i
    fi
  done
  if (( lock405_pin < 0 || lock405_snap < 0 )); then
    print -u2 "FAIL delete/forget-lock-order missing pin or snapshot lock got=$(printf %q "${lock405_order[*]}")"
    (( fails++ ))
  elif (( lock405_snap < lock405_pin )); then
    print -u2 "FAIL delete/forget-lock-order inverted snapshot before pin got=$(printf %q "${lock405_order[*]}")"
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

  if [[ ${functions[prompt_rename]} != *rename_snap_record* ]]; then
    print -u2 "FAIL rename/prompt missing rename_snap_record"
    (( fails++ ))
  fi

  # #99: rename must migrate snapshot cmd so idle grok still resumes.
  snap_names=(old keep)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[old]=/proj/old
  snap_cwd[keep]=/proj/keep
  snap_occupied[old]=0
  snap_occupied[keep]=1
  snap_workspace[old]=1
  snap_workspace[keep]=1
  snap_cmd[old]=grok-1.0.24-mac
  snap_cmd[keep]=zsh
  snap_attached[old]=123
  snap_attached[keep]=456
  save_session_snapshot
  rename_snap_record old new
  load_session_snapshot
  if [[ ${snap_names[(Ie)old]} -ne 0 ]]; then
    print -u2 "FAIL snap/rename left old name got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)new]} -eq 0 ]]; then
    print -u2 "FAIL snap/rename missing new name got=${snap_names[*]}"
    (( fails++ ))
  fi
  expect snap/rename-cmd grok-1.0.24-mac "${snap_cmd[new]:-}"
  expect snap/rename-cwd /proj/old "${snap_cwd[new]:-}"
  expect snap/rename-ws 1 "${snap_workspace[new]:-}"
  expect snap/rename-occ 0 "${snap_occupied[new]:-}"
  expect snap/rename-att 123 "${snap_attached[new]:-}"
  if [[ -n ${snap_cmd[old]:-} ]]; then
    print -u2 "FAIL snap/rename old cmd still set got=${snap_cmd[old]}"
    (( fails++ ))
  fi
  expect snap/rename-keep-cmd zsh "${snap_cmd[keep]:-}"
  session_snapshot_file
  if grep -qx 'name old' "$REPLY"; then
    print -u2 "FAIL snap/rename file still has old"
    (( fails++ ))
  fi
  if ! grep -qx 'name new' "$REPLY"; then
    print -u2 "FAIL snap/rename file missing new"
    (( fails++ ))
  fi
  HAS_TMUX=1
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'new\x1f/proj/old\x1f0\x1fzsh'
        print -r -- $'keep\x1f/proj/keep\x1f1\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/rename-live-follows-shell zsh "${snap_cmd[new]:-}"
  if [[ ${snap_names[(Ie)old]} -ne 0 ]]; then
    print -u2 "FAIL snap/rename-live still has old got=${snap_names[*]}"
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
  if [[ $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL pin/restore still launched grok got=$(printf %q "$restore_log")"
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

  if numeric_session_name 12; then
    :
  else
    print -u2 "FAIL restore/numeric 12 not treated as numeric"
    (( fails++ ))
  fi
  if numeric_session_name lanjump; then
    print -u2 "FAIL restore/numeric lanjump treated as numeric"
    (( fails++ ))
  fi
  if numeric_session_name 1a; then
    print -u2 "FAIL restore/numeric 1a treated as numeric"
    (( fails++ ))
  fi

  pinned_names=(missing 5 still-live)
  pinned_cwd=()
  pinned_grok=()
  pinned_cwd[missing]=/tmp/missing-cwd
  pinned_cwd[5]=/tmp/five
  pinned_cwd[still-live]=/tmp/live
  snap_names=(lanjump 6 sysmtn idle-named)
  snap_cwd=()
  snap_occupied=()
  snap_cwd[lanjump]=/proj/lanjump
  snap_cwd[6]=/tmp/six
  snap_cwd[sysmtn]=/proj/sysmtn
  snap_cwd[idle-named]=/proj/idle
  snap_occupied[lanjump]=1
  snap_occupied[6]=1
  snap_occupied[sysmtn]=1
  snap_occupied[idle-named]=0
  collect_restore_names
  expect restore/collect-names 'missing still-live' "${restore_names[*]}"
  expect restore/collect-cwd-pinned /tmp/missing-cwd "${restore_cwd[missing]}"
  if [[ -n ${restore_cwd[lanjump]:-} || ${restore_names[(Ie)lanjump]} -ne 0 ]]; then
    print -u2 "FAIL restore/collect-names included unpinned lanjump got=${restore_names[*]}"
    (( fails++ ))
  fi
  snap_attached=()
  snap_attached[lanjump]=$EPOCHSECONDS
  snap_attached[sysmtn]=$((EPOCHSECONDS - 200000))
  collect_open_window_names
  expect open/window-names 'missing still-live lanjump' "${open_window_names[*]}"
  snap_names+=(bmx-ae65d23f)
  snap_attached[bmx-ae65d23f]=$EPOCHSECONDS
  snap_workspace[bmx-ae65d23f]=1
  collect_open_window_names
  if [[ ${open_window_names[(Ie)bmx-ae65d23f]} -ne 0 ]]; then
    print -u2 "FAIL open/window-names leaked botmux got=${open_window_names[*]}"
    (( fails++ ))
  fi
  build_restore_pick
  expect open/pick-first-header 常驻 "${restore_pick_name[1]}"
  expect open/pick-pin-item missing "${restore_pick_name[2]}"

  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 1 ;;
      new-session|set-option|send-keys|set-environment|show-environment|list-sessions) return 0 ;;
      *) return 0 ;;
    esac
  }
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s lanjump'* || $restore_log == *'new-session -d -s sysmtn'* ]]; then
    print -u2 "FAIL restore/occupied restored unpinned names got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s missing'* ]]; then
    print -u2 "FAIL restore/occupied missing pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s 5'* || $restore_log == *'new-session -d -s 6'* ]]; then
    print -u2 "FAIL restore/occupied restored numeric session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s idle-named'* ]]; then
    print -u2 "FAIL restore/occupied restored idle unpinned got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL restore/occupied launched grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  if ! should_restore_sessions; then
    print -u2 "FAIL restore/gate kill-server should restore"
    (( fails++ ))
  fi

  tmuxx() {
    case $1 in
      list-sessions) return 0 ;;
      has-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  if should_restore_sessions; then
    print -u2 "FAIL restore/gate sessions already live should skip"
    (( fails++ ))
  fi

  tmuxx() {
    case $1 in
      list-sessions) return 0 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  if ! should_restore_sessions; then
    print -u2 "FAIL restore/gate server up but sessions missing should restore"
    (( fails++ ))
  fi

  tmuxx() {
    case $1 in
      list-sessions) return 1 ;;
      has-session) return 1 ;;
      *) return 0 ;;
    esac
  }
  if ! should_restore_sessions; then
    print -u2 "FAIL restore/gate reboot should restore"
    (( fails++ ))
  fi

  # #221: restore-stamp is write-only dead code. Helpers must be gone, and
  # start (maybe_restore_sessions after first draw) must not write a stamp.
  # Restore stays on should_restore_sessions only — do not wire boot/tmux-gen.
  expect restore/stamp-helpers-gone 0 "$(( ${+functions[current_boot_id]} + ${+functions[current_tmux_generation]} + ${+functions[read_restore_stamp]} + ${+functions[write_restore_stamp]} + ${+functions[ensure_restore_token]} + ${+functions[restore_stamp_file]} ))"
  if [[ ${functions[maybe_restore_sessions]:-} == *ensure_restore_token* ]]; then
    print -u2 "FAIL restore/stamp-start still writes stamp got=$(printf %q "${functions[maybe_restore_sessions]:-}")"
    (( fails++ ))
  fi

  # #80: one live pin + one missing pin must recreate only the missing pin.
  # Full restore still skips when anything restoreable is live, so a killed
  # unpinned workspace session stays gone and the window prompt stays closed.
  local -A mock_live
  mock_live_from_new_session() {
    local -a args
    args=("$@")
    local idx=${args[(I)-s]}
    (( idx && idx < $#args )) && mock_live[${args[idx+1]}]=1
  }
  setup_partial_pins() {
    : >"$tmux_log"
    did_restore=0
    mock_live=()
    mock_live[lj-pin-keep]=1
    mock_live[ws-live]=1
    snap_names=(ws-live ws-gone)
    snap_cwd=()
    snap_occupied=()
    snap_workspace=()
    snap_cmd=()
    snap_attached=()
    snap_cwd[ws-live]=/tmp/ws-live
    snap_cwd[ws-gone]=/tmp/ws-gone
    snap_occupied[ws-live]=1
    snap_occupied[ws-gone]=1
    snap_workspace[ws-live]=1
    snap_workspace[ws-gone]=1
    snap_attached[ws-live]=$EPOCHSECONDS
    snap_attached[ws-gone]=$EPOCHSECONDS
    save_session_snapshot
    print -r -- $'name lj-pin-keep\ncwd /tmp/lj-pin-keep\n\nname lj-pin-gone\ncwd /tmp/lj-pin-gone\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    tmuxx() {
      print -r -- "$*" >>"$tmux_log"
      case $1 in
        has-session)
          [[ $2 == -t ]] || return 1
          (( ${mock_live[${3#=}]:-0} )) && return 0
          return 1
          ;;
        new-session)
          mock_live_from_new_session "$@"
          return 0
          ;;
        list-sessions)
          if [[ $* == *-F* ]]; then
            print -r -- $'lj-pin-keep\x1f/tmp/lj-pin-keep\x1f0\x1fzsh'
            print -r -- $'ws-live\x1f/tmp/ws-live\x1f1\x1fzsh'
          fi
          return 0
          ;;
        *) return 0 ;;
      esac
    }
  }

  setup_partial_pins
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    print -u2 "FAIL restore/gate partial pin still live should skip full restore"
    (( fails++ ))
  fi

  setup_partial_pins
  maybe_restore_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-list missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s lj-pin-keep'* ]]; then
    print -u2 "FAIL pin/restore-partial-list recreated live pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-live'* ]]; then
    print -u2 "FAIL pin/restore-partial-list recreated live workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-list restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if (( did_restore )); then
    print -u2 "FAIL pin/restore-partial-list opened restore prompt did_restore=$did_restore"
    (( fails++ ))
  fi

  # #141: leftover live session after kill-server must not wipe unpinned
  # restoreable snapshot names before maybe_restore_sessions runs.
  setup_leftover_live() {
    : >"$tmux_log"
    mock_live=()
    mock_live[leftover]=1
    did_restore=0
    snap_names=(demo)
    snap_cwd=()
    snap_occupied=()
    snap_workspace=()
    snap_cmd=()
    snap_attached=()
    snap_cwd[demo]=/tmp/demo
    snap_occupied[demo]=1
    snap_workspace[demo]=1
    snap_cmd[demo]=zsh
    snap_attached[demo]=$EPOCHSECONDS
    pinned_names=()
    pinned_cwd=()
    pinned_grok=()
    : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    save_session_snapshot
    HAS_TMUX=1
    cursor=1
    tmuxx() {
      print -r -- "$*" >>"$tmux_log"
      case $1 in
        list-sessions)
          if [[ $* == *-F* ]]; then
            if [[ $* == *session_activity* ]]; then
              print -r -- $'1\x1fleftover\x1f1\x1f0\x1f/tmp/leftover\x1fzsh\x1fzsh\x1fzsh'
            else
              print -r -- $'leftover\x1f/tmp/leftover\x1f0\x1fzsh'
            fi
          else
            print -r -- leftover
          fi
          return 0
          ;;
        has-session)
          [[ $2 == -t ]] || return 1
          (( ${mock_live[${3#=}]:-0} )) && return 0
          return 1
          ;;
        new-session)
          mock_live_from_new_session "$@"
          return 0
          ;;
        *) return 0 ;;
      esac
    }
  }

  setup_leftover_live
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    print -u2 "FAIL snap/leftover-gate restored unpinned demo"
    (( fails++ ))
  fi
  snapshot_live_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)demo]} -ne 0 ]]; then
    print -u2 "FAIL snap/leftover-keep kept unpinned demo got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)leftover]} -eq 0 ]]; then
    print -u2 "FAIL snap/leftover-keep missing leftover got=${snap_names[*]}"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s demo'* ]]; then
    print -u2 "FAIL snap/leftover-restore created unpinned demo got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  setup_leftover_live
  load_items
  load_session_snapshot
  if [[ ${snap_names[(Ie)demo]} -ne 0 ]]; then
    print -u2 "FAIL load/leftover-keep kept unpinned demo got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${items_id[(Ie)leftover]} -eq 0 ]]; then
    print -u2 "FAIL load/leftover-paint missing leftover got=${items_id[*]}"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s demo'* ]]; then
    print -u2 "FAIL load/leftover-restore created unpinned demo got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #80: a live restoreable pin still lets snapshot drop killed unpinned.
  setup_partial_pins
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    print -u2 "FAIL snap/partial-gate should skip full restore"
    (( fails++ ))
  fi
  snapshot_live_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)ws-gone]} -ne 0 ]]; then
    print -u2 "FAIL snap/partial-drop still has ws-gone got=${snap_names[*]}"
    (( fails++ ))
  fi

  # #137/#122/#480: last/pin/on use this list. Restore is the interactive
  # boot, the same path as lanjump <机器>, not a silent print.
  if [[ ${functions[maybe_restore_sessions]} != *should_restore_sessions* || ${functions[maybe_restore_sessions]} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL view/restore boot missing should_restore_sessions"
    (( fails++ ))
  fi
  if [[ ${picker_boot_after_first_draw_steps[*]} != *maybe_restore_sessions* || ${functions[picker_boot_after_first_draw]} != *picker_boot_after_first_draw_steps* ]]; then
    print -u2 "FAIL view/restore boot does not run maybe_restore_sessions"
    (( fails++ ))
  fi

  # #177: leftover bmx pin must not list or restore-pick, and restore must not recreate it.
  : >"$tmux_log"
  mock_live=()
  snap_names=()
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  : >"$HOME/Library/Application Support/lanjump/session-snapshot"
  print -r -- $'name keep\ncwd /tmp/keep\n\nname bmx-demo\ncwd /tmp/bmx\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s bmx-demo'* ]]; then
    print -u2 "FAIL pin/print-skip-foreign restored bmx-demo got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  pinned_names=(keep bmx-demo)
  open_window_names=()
  build_restore_pick
  if [[ ${restore_pick_name[(Ie)bmx-demo]} -ne 0 ]]; then
    print -u2 "FAIL pin/pick-skip-foreign listed bmx-demo got=${restore_pick_name[*]}"
    (( fails++ ))
  fi
  if [[ ${restore_pick_name[(Ie)keep]} -eq 0 ]]; then
    print -u2 "FAIL pin/pick-skip-foreign missing keep got=${restore_pick_name[*]}"
    (( fails++ ))
  fi

  if [[ ${functions[print_workspace_names]} != *should_restore_sessions* ]]; then
    print -u2 "FAIL work/print missing should_restore_sessions got=$(printf %q "${functions[print_workspace_names]}")"
    (( fails++ ))
  fi
  if [[ ${functions[print_workspace_names]} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL work/print missing restore_saved_sessions got=$(printf %q "${functions[print_workspace_names]}")"
    (( fails++ ))
  fi

  setup_partial_pins
  got=$(print_workspace_names)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-work missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s lj-pin-keep'* ]]; then
    print -u2 "FAIL pin/restore-partial-work recreated live pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-work restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $got == *lj-pin-keep* ]]; then
    print -u2 "FAIL pin/restore-partial-work listed live pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *lj-pin-gone* ]]; then
    print -u2 "FAIL pin/restore-partial-work listed restored pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *ws-live* ]]; then
    print -u2 "FAIL pin/restore-partial-work missing live workspace got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *ws-gone* ]]; then
    print -u2 "FAIL pin/restore-partial-work listed killed unpinned workspace got=$(printf %q "$got")"
    (( fails++ ))
  fi

  # #107: kill-server / empty list restores unpinned workspace names and prints them.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(ws-empty)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[ws-empty]=/tmp/ws-empty
  snap_occupied[ws-empty]=1
  snap_workspace[ws-empty]=1
  snap_attached[ws-empty]=$EPOCHSECONDS
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  got=$(print_workspace_names)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s ws-empty'* ]]; then
    print -u2 "FAIL work/print-empty restored unpinned ws-empty got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ -n $got ]]; then
    print -u2 "FAIL work/print-empty-names got=$(printf %q "$got") want empty"
    (( fails++ ))
  fi

  # Unpinned names are not restored. Only pins come back.
  # Restore-window list stays 48h and still includes pins.
  : >"$tmux_log"
  mock_live=()
  mock_live[pinlive]=1
  mock_live[ws23h]=1
  mock_live[ws30h]=1
  mock_live[ws50h]=1
  did_restore=0
  snap_names=(pinlive ws23h ws30h ws50h)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  for wn in pinlive ws23h ws30h ws50h; do
    snap_cwd[$wn]=/tmp/$wn
    snap_occupied[$wn]=1
    snap_workspace[$wn]=1
  done
  snap_attached[pinlive]=$EPOCHSECONDS
  snap_attached[ws23h]=$((EPOCHSECONDS - 82800))
  snap_attached[ws30h]=$((EPOCHSECONDS - 108000))
  snap_attached[ws50h]=$((EPOCHSECONDS - 180000))
  save_session_snapshot
  print -r -- $'name pinlive\ncwd /tmp/pinlive\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  got=$(print_workspace_names)
  expect work/print-24h-names ws23h "$got"
  if [[ $got == *pinlive* ]]; then
    print -u2 "FAIL work/print-24h listed pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *ws30h* ]]; then
    print -u2 "FAIL work/print-24h listed 30h session got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *ws50h* ]]; then
    print -u2 "FAIL work/print-24h listed 50h session got=$(printf %q "$got")"
    (( fails++ ))
  fi
  load_pinned_sessions
  load_session_snapshot
  collect_open_window_names
  expect open/window-48h-names 'pinlive ws23h ws30h' "${open_window_names[*]}"

  # kill-server: work restores a 30h workspace member but does not open it.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(ws-30h)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[ws-30h]=/tmp/ws-30h
  snap_occupied[ws-30h]=1
  snap_workspace[ws-30h]=1
  snap_attached[ws-30h]=$((EPOCHSECONDS - 108000))
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  got=$(print_workspace_names)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s ws-30h'* ]]; then
    print -u2 "FAIL work/print-30h restored unpinned ws-30h got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect work/print-30h-names '' "$got"

  # #120: go --has-session must restore like work/print before answering.
  if [[ ${functions[has_named_session]:-} != *should_restore_sessions* ]]; then
    print -u2 "FAIL has-session/print missing should_restore_sessions got=$(printf %q "${functions[has_named_session]:-}")"
    (( fails++ ))
  fi
  if [[ ${functions[has_named_session]:-} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL has-session/print missing restore_saved_sessions got=$(printf %q "${functions[has_named_session]:-}")"
    (( fails++ ))
  fi

  # kill-server / no live sessions: restore every restoreable workspace name.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(demo other)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[demo]=/tmp/demo
  snap_cwd[other]=/tmp/other
  snap_occupied[demo]=1
  snap_occupied[other]=1
  snap_workspace[demo]=1
  snap_workspace[other]=1
  snap_attached[demo]=$EPOCHSECONDS
  snap_attached[other]=$EPOCHSECONDS
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  st=0
  has_named_session demo || st=$?
  restore_log=$(<"$tmux_log")
  if (( st == 0 )); then
    print -u2 "FAIL has-session/empty-demo status got=0 want nonzero"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s demo'* || $restore_log == *'new-session -d -s other'* ]]; then
    print -u2 "FAIL has-session/empty-demo restored unpinned got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #80/#120: anything restoreable already live skips full restore.
  setup_partial_pins
  st=0
  has_named_session ws-gone || st=$?
  restore_log=$(<"$tmux_log")
  if (( st == 0 )); then
    print -u2 "FAIL has-session/partial-gone status got=0 want nonzero"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL has-session/partial-gone restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL has-session/partial-gone missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #124: --attach must restore like go/--has-session before attaching.
  attach_src=
  if [[ -f ${_pick_src_file:-} ]]; then
    attach_src=$(awk '
      /\[\[ \$\{1:-\} == --attach \]\]/ {p=1}
      p {print}
      p && /^picker_boot_before_first_draw/ {exit}
    ' "$_pick_src_file")
  fi
  if [[ $attach_src != *has_named_session* && $attach_src != *ensure_named_session_for_attach* && $attach_src != *restore_saved_sessions* ]]; then
    print -u2 "FAIL attach/handler missing restore gate got=$(printf %q "$attach_src")"
    (( fails++ ))
  fi
  if [[ ${functions[ensure_named_session_for_attach]:-} != *has_named_session* ]]; then
    print -u2 "FAIL attach/ensure missing has_named_session got=$(printf %q "${functions[ensure_named_session_for_attach]:-}")"
    (( fails++ ))
  fi

  # kill-server / no live sessions: attach restore recreates snapshot names.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(demo other)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[demo]=/tmp/demo
  snap_cwd[other]=/tmp/other
  snap_occupied[demo]=1
  snap_occupied[other]=1
  snap_workspace[demo]=1
  snap_workspace[other]=1
  snap_attached[demo]=$EPOCHSECONDS
  snap_attached[other]=$EPOCHSECONDS
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions) return 1 ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  st=0
  err=$(ensure_named_session_for_attach demo 2>&1) || st=$?
  restore_log=$(<"$tmux_log")
  if (( st == 0 )); then
    print -u2 "FAIL attach/empty-demo status got=0 want nonzero err=$(printf %q "$err")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s demo'* || $restore_log == *'new-session -d -s other'* ]]; then
    print -u2 "FAIL attach/empty-demo restored unpinned got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #80/#124: anything restoreable already live skips full restore.
  setup_partial_pins
  st=0
  err=$(ensure_named_session_for_attach ws-gone 2>&1) || st=$?
  restore_log=$(<"$tmux_log")
  if (( st == 0 )); then
    print -u2 "FAIL attach/partial-gone status got=0 want nonzero"
    (( fails++ ))
  fi
  if [[ $err != *'没有 session「ws-gone」。'* ]]; then
    print -u2 "FAIL attach/partial-gone error got=$(printf %q "$err")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL attach/partial-gone restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL attach/partial-gone missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #134: list/--print-sessions must restore like work before listing.
  if [[ ${functions[print_session_list]:-} != *should_restore_sessions* ]]; then
    print -u2 "FAIL list/print missing should_restore_sessions got=$(printf %q "${functions[print_session_list]:-}")"
    (( fails++ ))
  fi
  if [[ ${functions[print_session_list]:-} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL list/print missing restore_saved_sessions got=$(printf %q "${functions[print_session_list]:-}")"
    (( fails++ ))
  fi

  session_list_tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions)
        (( ${#mock_live} )) || return 1
        if [[ $* == *-F* ]]; then
          local k
          for k in ${(k)mock_live}; do
            print -r -- "$k"$'\t'"空闲"$'\t'"zsh"$'\t'"${snap_cwd[$k]:-/tmp/$k}"
          done
        fi
        return 0
        ;;
      has-session)
        [[ $2 == -t ]] || return 1
        (( ${mock_live[${3#=}]:-0} )) && return 0
        return 1
        ;;
      new-session)
        mock_live_from_new_session "$@"
        return 0
        ;;
      *) return 0 ;;
    esac
  }

  # kill-server / no live sessions: restore snapshot names then list them.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(demo)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[demo]=/tmp/demo
  snap_occupied[demo]=1
  snap_workspace[demo]=1
  snap_attached[demo]=$EPOCHSECONDS
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() { session_list_tmuxx "$@" }
  if (( ${+functions[print_session_list]} )); then
    got=$(print_session_list)
  else
    got=
    print -u2 "FAIL list/print-empty print_session_list missing"
    (( fails++ ))
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s demo'* ]]; then
    print -u2 "FAIL list/print-empty restored unpinned demo got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $got == *demo* ]]; then
    print -u2 "FAIL list/print-empty listed unpinned demo got=$(printf %q "$got")"
    (( fails++ ))
  fi

  # #80/#134: anything restoreable already live skips full restore.
  setup_partial_pins
  tmuxx() { session_list_tmuxx "$@" }
  if (( ${+functions[print_session_list]} )); then
    got=$(print_session_list)
  else
    got=
    print -u2 "FAIL list/print-partial print_session_list missing"
    (( fails++ ))
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL list/print-partial missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL list/print-partial restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s lj-pin-keep'* ]]; then
    print -u2 "FAIL list/print-partial recreated live pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $got != *lj-pin-keep* ]]; then
    print -u2 "FAIL list/print-partial missing live pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *lj-pin-gone* ]]; then
    print -u2 "FAIL list/print-partial missing restored pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *ws-live* ]]; then
    print -u2 "FAIL list/print-partial missing live workspace got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *ws-gone* ]]; then
    print -u2 "FAIL list/print-partial listed killed unpinned workspace got=$(printf %q "$got")"
    (( fails++ ))
  fi

  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  LANJUMP_GHOSTTY_APP="$testhome/Ghostty.app"
  mkdir -p "$LANJUMP_GHOSTTY_APP"
  if ! ghostty_restore_available; then
    print -u2 "FAIL ghostty/available local ghostty should be usable"
    (( fails++ ))
  fi
  SSH_CONNECTION='1.2.3.4 22'
  if ghostty_restore_available; then
    print -u2 "FAIL ghostty/available over ssh should skip"
    (( fails++ ))
  fi
  unset SSH_CONNECTION
  expect ghostty/prompt $'工作区：lanjump、sysmtn\n1  打开窗口\n2  打开窗口，全部只要空 shell\n回车  先不打开' "$(workspace_restore_prompt_text lanjump sysmtn)"
  LANJUMP_ATTACH_BIN=/Users/mac/.local/bin/lanjump
  local script
  script=$(ghostty_osascript_for_sessions lanjump sysmtn)
  if [[ $script != *'new window'* ]]; then
    print -u2 "FAIL ghostty/script missing new window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'new tab'* ]]; then
    print -u2 "FAIL ghostty/script missing new tab got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *direct:* ]]; then
    print -u2 "FAIL ghostty/script used direct: which macOS Ghostty passes to bash got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'set command of cfg to "/Users/mac/.local/bin/lanjump-ghostty-attach"'* ]]; then
    print -u2 "FAIL ghostty/script missing space-free helper command got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SPEC=lanjump'* ]]; then
    print -u2 "FAIL ghostty/script missing attach lanjump spec got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SPEC=sysmtn'* ]]; then
    print -u2 "FAIL ghostty/script missing attach sysmtn spec got=$(printf %q "$script")"
    (( fails++ ))
  fi
  # #127: Terminal `do script in window` reuses the current tab. Extra sessions
  # must Cmd+T (tab) or untargeted do script (window).
  open_placement=window
  script=$(terminal_osascript_for_sessions a b)
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach a'* ]]; then
    print -u2 "FAIL terminal/script missing attach a got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach b'* ]]; then
    print -u2 "FAIL terminal/script missing attach b got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *' in w'* || $script == *'window of'* ]]; then
    print -u2 "FAIL terminal/window-placement still reuses one window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *keystroke* ]]; then
    print -u2 "FAIL terminal/window-placement used Cmd+T got=$(printf %q "$script")"
    (( fails++ ))
  fi
  script=$(terminal_osascript_for_sessions a)
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach a'* ]]; then
    print -u2 "FAIL terminal/script-one missing attach a got=$(printf %q "$script")"
    (( fails++ ))
  fi
  case $script in
    *'do script'*'do script'*)
      print -u2 "FAIL terminal/script-one extra do script got=$(printf %q "$script")"
      (( fails++ ))
      ;;
  esac
  open_placement=tab
  script=$(terminal_osascript_for_sessions a b)
  if [[ $script == *'count of windows'* || $script == *haveWin* ]]; then
    print -u2 "FAIL terminal/tab-placement still joins an existing window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'keystroke "t" using command down'* ]]; then
    print -u2 "FAIL terminal/tab-placement missing Cmd+T for extra tabs got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'selected tab of front window'* ]]; then
    print -u2 "FAIL terminal/tab-placement missing selected tab got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'custom title of t to "a"'* || $script != *'custom title of t to "b"'* ]]; then
    print -u2 "FAIL terminal/tab-placement missing session tab titles got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'title displays custom title of t to true'* ]]; then
    print -u2 "FAIL terminal/tab-placement missing title displays custom title got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'exec -a a '* || $script != *'exec -a b '* ]]; then
    print -u2 "FAIL terminal/tab-placement missing exec -a session argv0 got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/terminal-tab.applescript"
  if ! /usr/bin/osacompile -o "$testhome/terminal-tab.scpt" "$testhome/terminal-tab.applescript" 2>"$testhome/osacompile-terminal-tab.err"; then
    print -u2 "FAIL terminal/tab-compile $(<"$testhome/osacompile-terminal-tab.err") got=$(printf %q "$script")"
    (( fails++ ))
  fi
  open_placement=window
  script=$(terminal_osascript_for_sessions a b)
  if [[ $script == *'front window'* ]]; then
    print -u2 "FAIL terminal/window-placement attached first session to front window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'do script'* ]]; then
    print -u2 "FAIL terminal/window-placement missing do script got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'custom title of t to "a"'* ]]; then
    print -u2 "FAIL terminal/window-placement missing tab title got=$(printf %q "$script")"
    (( fails++ ))
  fi
  expect attach/spec-local lanjump "$(attach_spec_for lanjump)"
  if attaching_remote_host; then
    print -u2 "FAIL attach/remote-host-empty should be local"
    (( fails++ ))
  fi
  LANJUMP_ATTACH_HOST=studio
  expect attach/spec-remote 'studio:lanjump' "$(attach_spec_for lanjump)"
  if ! attaching_remote_host; then
    print -u2 "FAIL attach/remote-host-studio should be remote"
    (( fails++ ))
  fi
  got=$(attach_command_for lanjump)
  if [[ $got != *'/Users/mac/.local/bin/lanjump attach studio:lanjump'* ]]; then
    print -u2 "FAIL attach/host-cmd missing studio:lanjump got=$(printf %q "$got")"
    (( fails++ ))
  fi
  script=$(ghostty_osascript_for_sessions lanjump sysmtn)
  if [[ $script != *'set command of cfg to "/Users/mac/.local/bin/lanjump-ghostty-attach"'* ]]; then
    print -u2 "FAIL ghostty/host-script missing space-free helper command got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SPEC=studio:lanjump'* ]]; then
    print -u2 "FAIL ghostty/host-script missing attach studio:lanjump spec got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SPEC=studio:sysmtn'* ]]; then
    print -u2 "FAIL ghostty/host-script missing attach studio:sysmtn spec got=$(printf %q "$script")"
    (( fails++ ))
  fi
  LANJUMP_ATTACH_HOST=local
  expect attach/spec-host-local lanjump "$(attach_spec_for lanjump)"
  if attaching_remote_host; then
    print -u2 "FAIL attach/remote-host-local should be local"
    (( fails++ ))
  fi
  unset LANJUMP_ATTACH_HOST

  # #84: remote --open-tabs must open windows even if effective_open_target is current.
  tabs_src=${functions[open_named_tabs]}
  if [[ $tabs_src != *attaching_remote_host* ]]; then
    print -u2 "FAIL open-tabs/remote-src missing attaching_remote_host"
    (( fails++ ))
  fi
  if [[ $tabs_src == *没有可用的本机终端* ]]; then
    print -u2 "FAIL open-tabs/remote-src errors instead of open_workspace_tabs"
    (( fails++ ))
  fi
  _save_open_tabs=$functions[open_workspace_tabs]
  _save_eot=$functions[effective_open_target]
  _save_resume=$functions[maybe_resume_last_command]
  open_workspace_tabs() {
    print -r -- "OPEN_TABS ${(j: :)${(q)@}}"
    return 0
  }
  effective_open_target() { print -r -- current }
  maybe_resume_last_command() {
    print -r -- "RESUME $1"
  }
  LANJUMP_ATTACH_HOST=studio
  open_target=current
  attach_shell_only=0
  got=$(open_named_tabs pin-one 2>&1)
  expect open-tabs/remote-current-one 'OPEN_TABS pin-one' "$got"
  if [[ $got == *没有可用的本机终端* ]]; then
    print -u2 "FAIL open-tabs/remote-current-one printed no-terminal got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *RESUME* ]]; then
    print -u2 "FAIL open-tabs/remote-current-one resumed local session got=$(printf %q "$got")"
    (( fails++ ))
  fi
  got=$(open_named_tabs a b 2>&1)
  expect open-tabs/remote-current-multi 'OPEN_TABS a b' "$got"
  unset LANJUMP_ATTACH_HOST

  # #197: local SSH / no keyboard: current window can attach only the first
  # name. Print the rest; do not resume sessions the user never entered.
  _save_mark=$functions[mark_snapshot_occupied]
  _save_remember=$functions[remember_last_session]
  _save_color=$functions[tmux_prepare_color]
  _save_tkeys=$functions[tmux_prepare_keys]
  _save_kb=$functions[local_keyboard]
  mark_snapshot_occupied() { : }
  remember_last_session() { : }
  tmux_prepare_color() { : }
  tmux_prepare_keys() { : }
  local_keyboard() { return 1 }
  exec() {
    print -r -- "ATTACH ${(q)@}"
  }
  got=$(open_named_tabs st197-one st197-two 2>&1)
  if [[ $got == *OPEN_TABS* ]]; then
    print -u2 "FAIL open-tabs/local-current-multi used workspace tabs got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *RESUME\ st197-one* ]]; then
    print -u2 "FAIL open-tabs/local-current-multi missing resume of first got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *RESUME\ st197-two* ]]; then
    print -u2 "FAIL open-tabs/local-current-multi resumed dropped session got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *未打开：st197-two* ]]; then
    print -u2 "FAIL open-tabs/local-current-multi silently dropped extras got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *st197-one* || $got != *ATTACH* ]]; then
    print -u2 "FAIL open-tabs/local-current-multi did not attach first got=$(printf %q "$got")"
    (( fails++ ))
  fi
  unfunction exec
  functions[mark_snapshot_occupied]=$_save_mark
  functions[remember_last_session]=$_save_remember
  functions[tmux_prepare_color]=$_save_color
  functions[tmux_prepare_keys]=$_save_tkeys
  functions[local_keyboard]=$_save_kb
  functions[open_workspace_tabs]=$_save_open_tabs
  functions[effective_open_target]=$_save_eot
  functions[maybe_resume_last_command]=$_save_resume
  unset _save_open_tabs _save_eot _save_resume _save_mark _save_remember _save_color _save_tkeys _save_kb
  open_target=auto

  if pane_is_shell ''; then
    :
  else
    print -u2 "FAIL shell/empty should count as idle shell"
    (( fails++ ))
  fi
  if pane_is_idle_shell ''; then
    print -u2 "FAIL idle/empty unread command should not count as idle shell"
    (( fails++ ))
  fi
  if pane_is_idle_shell zsh; then
    :
  else
    print -u2 "FAIL idle/zsh should count as idle shell"
    (( fails++ ))
  fi
  if pane_is_idle_shell grok-1.0.24-mac; then
    print -u2 "FAIL idle/grok should not count as idle shell"
    (( fails++ ))
  fi
  expect pane/target '=lanjump:.' "$(session_pane_target lanjump)"
  expect cmd/short-grok grok "$(short_command_name grok-1.0.24-mac)"
  expect cmd/short-path grok "$(short_command_name /Users/mac/.grok/bin/grok)"
  expect cmd/short-zsh zsh "$(short_command_name zsh)"
  expect summary/cmd grok "$(useful_summary '对话标题 - grok' grok-1.0.24-mac grok-1.0.24-mac)"
  expect summary/zsh zsh "$(useful_summary '' zsh zsh)"
  for leftover in last_command_resumable resume_line_for resume_pane_path \
      enter_resume_prompt_text resume_prompt_choice; do
    if (( ${+functions[$leftover]} )); then
      print -u2 "FAIL resume/leftover $leftover still defined"
      (( fails++ ))
    fi
  done
  mkdir -p "$HOME/Documents/projects/inferme"
  snap_cwd[inferme]=$HOME
  pinned_cwd[inferme]=$HOME
  load_settings
  expect resolve/named-project "$HOME/Documents/projects/inferme" "$(resolve_session_cwd inferme "$HOME")"
  expect resolve/keep-explicit /proj/keep "$(resolve_session_cwd nosuch /proj/keep)"
  if [[ ${functions[maybe_resume_last_command]} == *respawn-pane* ]]; then
    print -u2 "FAIL resume/no-respawn maybe_resume still respawns got=$(printf %q "${functions[maybe_resume_last_command]}")"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} == *enter_resume_prompt_text* ]]; then
    print -u2 "FAIL resume/no-ask attach_named_session still prompts got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi

  LANJUMP_ATTACH_BIN=/Users/mac/.local/bin/lanjump
  attach_shell_only=0
  got=$(attach_command_for 'web api')
  if [[ $got != *"$(printf %q 'web api')"* ]]; then
    print -u2 "FAIL attach/quote-space missing quoted web api got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *'attach web api'* ]]; then
    print -u2 "FAIL attach/quote-space has unquoted attach web api got=$(printf %q "$got")"
    (( fails++ ))
  fi
  attach_shell_only=1
  got=$(attach_command_for 'web api')
  if [[ $got != *"attach --shell $(printf %q 'web api')"* ]]; then
    print -u2 "FAIL attach/quote-shell missing quoted --shell web api got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *'attach --shell web api'* ]]; then
    print -u2 "FAIL attach/quote-shell has unquoted attach --shell web api got=$(printf %q "$got")"
    (( fails++ ))
  fi
  attach_shell_only=0

  # #136: Ghostty wraps command in bash -c 'exec -l <command>'; zsh quotes are eaten.
  LANJUMP_ATTACH_BIN=/Users/mac/.local/bin/lanjump
  LANJUMP_GHOSTTY_ATTACH=/Users/mac/.local/bin/lanjump-ghostty-attach
  ghostty_command_of_cfg() {
    local line
    while IFS= read -r line; do
      [[ $line == $'  set command of cfg to '* ]] || continue
      line=${line#  set command of cfg to }
      line=${line#\"}
      line=${line%\"}
      print -r -- "$line"
    done
  }
  assert_ghostty_command_helper() {
    local label=$1 script=$2 cmd
    cmd=$(print -r -- "$script" | ghostty_command_of_cfg)
    if [[ -z $cmd ]]; then
      print -u2 "FAIL $label missing command of cfg got=$(printf %q "$script")"
      (( fails++ ))
      return
    fi
    if [[ $cmd == *[[:space:]]* || $cmd == *\'* ]]; then
      print -u2 "FAIL $label command has space/quote got=$(printf %q "$cmd")"
      (( fails++ ))
    fi
    if [[ $cmd != /Users/mac/.local/bin/lanjump-ghostty-attach ]]; then
      print -u2 "FAIL $label command is not space-free helper got=$(printf %q "$cmd")"
      (( fails++ ))
    fi
  }
  script=$(ghostty_osascript_for_sessions 'my app')
  assert_ghostty_command_helper ghostty/space-name "$script"
  if [[ $script == *"attach 'my app'"* || $script == *'attach "my app"'* ]]; then
    print -u2 "FAIL ghostty/space-name quoted spec in command got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SPEC=my app'* ]]; then
    print -u2 "FAIL ghostty/space-name spec missing from env got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'set environment variables of cfg to'* ]]; then
    print -u2 "FAIL ghostty/space-name missing environment variables got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/ghostty-space.applescript"
  # `surface configuration` exists only in Ghostty's scripting dictionary.
  # CI has no Ghostty.app. String checks above still run; compile does not.
  if [[ -z ${_lj_ghostty_dict:-} ]]; then
    typeset -g _lj_ghostty_dict=0
    local _gdir
    _gdir=$(mktemp -d) || _gdir=
    if [[ -n $_gdir ]]; then
      print -r -- $'tell application "Ghostty"\nset cfg to new surface configuration\nend tell' >"$_gdir/probe.applescript"
      if /usr/bin/osacompile -o "$_gdir/probe.scpt" "$_gdir/probe.applescript" >/dev/null 2>&1; then
        _lj_ghostty_dict=1
      fi
      rm -rf "$_gdir"
    fi
  fi
  if (( _lj_ghostty_dict )); then
    if ! /usr/bin/osacompile -o "$testhome/ghostty-space.scpt" "$testhome/ghostty-space.applescript" 2>"$testhome/osacompile-space.err"; then
      print -u2 "FAIL ghostty/space-compile $(<"$testhome/osacompile-space.err") got=$(printf %q "$script")"
      (( fails++ ))
    fi
  fi
  script=$(ghostty_osascript_for_sessions lanjump)
  assert_ghostty_command_helper ghostty/plain-name "$script"
  if [[ $script != *'LANJUMP_ATTACH_SPEC=lanjump'* ]]; then
    print -u2 "FAIL ghostty/plain-name spec missing from env got=$(printf %q "$script")"
    (( fails++ ))
  fi
  attach_shell_only=1
  script=$(ghostty_osascript_for_sessions 'my app')
  assert_ghostty_command_helper ghostty/space-shell "$script"
  if [[ $script != *'LANJUMP_ATTACH_SPEC=my app'* ]]; then
    print -u2 "FAIL ghostty/space-shell spec missing from env got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SHELL=1'* ]]; then
    print -u2 "FAIL ghostty/space-shell missing LANJUMP_ATTACH_SHELL got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'attach --shell'* ]]; then
    print -u2 "FAIL ghostty/space-shell still puts --shell in command got=$(printf %q "$script")"
    (( fails++ ))
  fi
  attach_shell_only=0
  # #218: ghostty_focus_session interpolated $name raw; " or \ broke osascript.
  # Function-level / captured-script stand-in; no live Ghostty.
  focus_name=$'say "hi"\\end'
  focus_as=$(ghostty_applescript_string "$focus_name")
  expect ghostty/focus-escape '"say \"hi\"\\end"' "$focus_as"
  focus_fn=${functions[ghostty_focus_session]}
  if [[ $focus_fn == *'is "$name"'* ]]; then
    print -u2 "FAIL ghostty/focus-quote interpolates raw \$name into AppleScript got=$(printf %q "$focus_fn")"
    (( fails++ ))
  fi
  if [[ $focus_fn != *ghostty_applescript_string* ]]; then
    print -u2 "FAIL ghostty/focus-quote missing ghostty_applescript_string got=$(printf %q "$focus_fn")"
    (( fails++ ))
  fi
  # #279: session names may contain ". AppleScript "" doubling is -2740
  # under osascript; \" is accepted. Ghostty and Terminal share this helper.
  # Compile-only; no live Ghostty/Terminal.
  quote_as=$(ghostty_applescript_string $'say "hi"')
  print -r -- "set t to $quote_as" >"$testhome/applescript-quote.applescript"
  if ! /usr/bin/osacompile -o "$testhome/applescript-quote.scpt" "$testhome/applescript-quote.applescript" 2>"$testhome/osascript-quote.err"; then
    print -u2 "FAIL applescript/quote-escape $(<"$testhome/osascript-quote.err") got=$(printf %q "$quote_as")"
    (( fails++ ))
  fi
  # #127: Terminal do script interpolates zsh ${(q)} into AppleScript "...";
  # acc\ test is not a valid AppleScript string (osacompile -2741).
  saved_placement=$open_placement
  open_placement=tab
  script=$(terminal_osascript_for_sessions 'acc test' clipkeep)
  if [[ $script == *'acc\ test'* ]]; then
    print -u2 "FAIL terminal/space-tab raw acc\\ test inside AppleScript quotes got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'acc\\ test'* ]]; then
    print -u2 "FAIL terminal/space-tab missing AppleScript-escaped acc test got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'count of windows'* || $script == *haveWin* ]]; then
    print -u2 "FAIL terminal/space-tab still joins an existing window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'keystroke "t" using command down'* ]]; then
    print -u2 "FAIL terminal/space-tab missing Cmd+T got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'custom title of t to "acc test"'* || $script != *'custom title of t to "clipkeep"'* ]]; then
    print -u2 "FAIL terminal/space-tab missing session titles got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'title displays custom title of t to true'* ]]; then
    print -u2 "FAIL terminal/space-tab missing title displays custom title got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/terminal-space-tab.applescript"
  if ! /usr/bin/osacompile -o "$testhome/terminal-space-tab.scpt" "$testhome/terminal-space-tab.applescript" 2>"$testhome/osacompile-terminal-space-tab.err"; then
    print -u2 "FAIL terminal/space-tab-compile $(<"$testhome/osacompile-terminal-space-tab.err") got=$(printf %q "$script")"
    (( fails++ ))
  fi
  open_placement=window
  script=$(terminal_osascript_for_sessions 'acc test' clipkeep)
  if [[ $script == *'acc\ test'* ]]; then
    print -u2 "FAIL terminal/space-window raw acc\\ test inside AppleScript quotes got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'front window'* ]]; then
    print -u2 "FAIL terminal/space-window attached first session to front window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/terminal-space-window.applescript"
  if ! /usr/bin/osacompile -o "$testhome/terminal-space-window.scpt" "$testhome/terminal-space-window.applescript" 2>"$testhome/osacompile-terminal-space-window.err"; then
    print -u2 "FAIL terminal/space-window-compile $(<"$testhome/osacompile-terminal-space-window.err") got=$(printf %q "$script")"
    (( fails++ ))
  fi
  open_placement=$saved_placement
  script=$(terminal_osascript_for_sessions 'my app')
  if [[ $script == *'my\ app'* ]]; then
    print -u2 "FAIL terminal/space-name raw my\\ app inside AppleScript quotes got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'my\\ app'* ]]; then
    print -u2 "FAIL terminal/space-name missing AppleScript-escaped my app got=$(printf %q "$script")"
    (( fails++ ))
  fi
  local helper_src helper_got helper_home
  helper_src=${_pick_src_file:h:h}/bin/lanjump-ghostty-attach
  helper_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-ghostty-helper.XXXXXX")
  mkdir -p "$helper_home/Library/Application Support/lanjump"
  print -r -- 'print -r -- "ATTACH ${(j: :)${(q)@}}"' >"$helper_home/Library/Application Support/lanjump/lanjump.zsh"
  helper_got=$(HOME=$helper_home LANJUMP_ATTACH_SPEC='my app' /bin/zsh "$helper_src")
  expect ghostty/helper-space "ATTACH attach $(printf %q 'my app')" "$helper_got"
  helper_got=$(HOME=$helper_home LANJUMP_ATTACH_SPEC='my app' LANJUMP_ATTACH_SHELL=1 /bin/zsh "$helper_src")
  expect ghostty/helper-space-shell "ATTACH attach --shell $(printf %q 'my app')" "$helper_got"
  helper_got=$(HOME=$helper_home LANJUMP_ATTACH_SPEC=lanjump /bin/zsh "$helper_src")
  expect ghostty/helper-plain 'ATTACH attach lanjump' "$helper_got"
  rm -rf "$helper_home"

  # #32: ~/.local/bin helper missing; use Application Support copy and self-heal.
  local helper_app helper_bin saved_attach_bin saved_ghostty_attach
  helper_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-ghostty-missing-bin.XXXXXX")
  mkdir -p "$helper_home/Library/Application Support/lanjump"
  helper_app="$helper_home/Library/Application Support/lanjump/lanjump-ghostty-attach"
  helper_bin="$helper_home/.local/bin/lanjump-ghostty-attach"
  print -r -- $'#!/bin/zsh\nexit 0' >"$helper_app"
  chmod 755 "$helper_app"
  saved_attach_bin=${LANJUMP_ATTACH_BIN:-}
  saved_ghostty_attach=${LANJUMP_GHOSTTY_ATTACH:-}
  HOME=$helper_home
  LANJUMP_ATTACH_BIN=$HOME/.local/bin/lanjump
  unset LANJUMP_GHOSTTY_ATTACH
  helper_got=$(ghostty_attach_helper)
  expect ghostty/helper-missing-bin-path "$helper_bin" "$helper_got"
  if [[ ! -x $helper_got ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin path is not executable got=$(printf %q "$helper_got")"
    (( fails++ ))
  fi
  if [[ $helper_got == *[[:space:]]* ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin command path has spaces got=$(printf %q "$helper_got")"
    (( fails++ ))
  fi
  if [[ ! -x $helper_bin ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin did not restore ~/.local/bin copy"
    (( fails++ ))
  fi
  script=$(ghostty_osascript_for_sessions somename)
  cmd=$(print -r -- "$script" | ghostty_command_of_cfg)
  if [[ $cmd != "$helper_got" ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin script command mismatch got=$(printf %q "$cmd") helper=$(printf %q "$helper_got")"
    (( fails++ ))
  fi
  if [[ $script != *'set command of cfg to "'$helper_got'"'* ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin script missing existing helper command got=$(printf %q "$script") helper=$(printf %q "$helper_got")"
    (( fails++ ))
  fi
  if [[ $cmd == *[[:space:]]* ]]; then
    print -u2 "FAIL ghostty/helper-missing-bin script command has spaces got=$(printf %q "$cmd")"
    (( fails++ ))
  fi
  HOME=$testhome
  if [[ -n $saved_attach_bin ]]; then
    LANJUMP_ATTACH_BIN=$saved_attach_bin
  else
    unset LANJUMP_ATTACH_BIN
  fi
  if [[ -n $saved_ghostty_attach ]]; then
    LANJUMP_GHOSTTY_ATTACH=$saved_ghostty_attach
  else
    unset LANJUMP_GHOSTTY_ATTACH
  fi
  rm -rf "$helper_home"

  snap_names=(keep drop)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_cwd[keep]=/proj/keep
  snap_cwd[drop]=/proj/drop
  snap_occupied[keep]=0
  snap_occupied[drop]=0
  snap_workspace[keep]=1
  snap_workspace[drop]=0
  snap_cmd[keep]=grok-1.0.24-mac
  snap_cmd[drop]=zsh
  save_session_snapshot
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'keep\x1f/proj/keep\x1f0\x1fzsh'
        print -r -- $'drop\x1f/proj/drop\x1f0\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/ws-keep 1 "${snap_workspace[keep]}"
  expect snap/ws-drop 0 "${snap_workspace[drop]}"
  expect snap/cmd-follow-shell zsh "${snap_cmd[keep]}"
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'keep\x1f/proj/keep\x1f0\x1fcodex'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/cmd-follow-codex codex "${snap_cmd[keep]}"
  : >"$tmux_log"
  LANJUMP_PICK_BIN=/opt/lanjump/lanjump-pick.zsh
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    return 0
  }
  hooks_installed=0
  tmux_install_snapshot_hooks
  hook_log=$(<"$tmux_log")
  if [[ $hook_log != *'set-hook -g client-detached[91]'* ]]; then
    print -u2 "FAIL snap/hook missing client-detached got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log == *'set-hook -g client-attached[91]'* ]]; then
    print -u2 "FAIL snap/hook should not install client-attached got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log != *'--refresh-pin-cwd'* ]]; then
    print -u2 "FAIL snap/hook missing --refresh-pin-cwd got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log == *'set-option -ag status-right'* || $hook_log == *'--snapshot'* ]]; then
    print -u2 "FAIL snap/hook still installs snapshot tick got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if pick_needs_tty --snapshot; then
    print -u2 "FAIL snap/tty --snapshot should not need a tty"
    (( fails++ ))
  fi
  # #277: foreign hook in slot 91 must survive install. Do not -gu [91] blindly.
  local hook91_file hook91_got
  typeset -g PICK_SELFTEST_HOOK91_DIR
  PICK_SELFTEST_HOOK91_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook91.XXXXXX")
  hook91_file=$PICK_SELFTEST_HOOK91_DIR/client-attached\[91\]
  print -r -- 'run-shell -b /usr/local/bin/other-plugin' >"$hook91_file"
  LANJUMP_PICK_BIN=/opt/lanjump/lanjump-pick.zsh
  tmuxx() {
    local hook file
    case $1 in
      show-hooks)
        if [[ ${@[-1]} == -g ]]; then
          local f base
          setopt local_options nullglob
          for f in "$PICK_SELFTEST_HOOK91_DIR"/*; do
            base=${f:t}
            print -r -- "$base $(<"$f")"
          done
        else
          hook=${@[-1]}
          file="$PICK_SELFTEST_HOOK91_DIR/$hook"
          if [[ -f "$file" ]]; then
            print -r -- "$hook $(<"$file")"
          else
            print -r -- "$hook "
          fi
        fi
        ;;
      set-hook)
        hook=$3
        file="$PICK_SELFTEST_HOOK91_DIR/$hook"
        if [[ $2 == -gu ]]; then
          rm -f -- "$file"
        elif [[ $2 == -g ]]; then
          print -r -- "${@[4,-1]}" >"$file"
        fi
        ;;
    esac
    return 0
  }
  hooks_installed=0
  tmux_install_snapshot_hooks
  hook91_got=
  [[ -f "$hook91_file" ]] && hook91_got=$(<"$hook91_file")
  expect snap/hook-keep-foreign-91 'run-shell -b /usr/local/bin/other-plugin' "$hook91_got"
  rm -rf "$PICK_SELFTEST_HOOK91_DIR"
  unset PICK_SELFTEST_HOOK91_DIR
  # #308: foreign client-detached[91] must survive install. Do not set-hook -g blindly.
  local detached91_file detached91_got
  typeset -g PICK_SELFTEST_HOOK91_DIR
  PICK_SELFTEST_HOOK91_DIR=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook91-detached.XXXXXX")
  detached91_file=$PICK_SELFTEST_HOOK91_DIR/client-detached\[91\]
  print -r -- 'run-shell -b /usr/local/bin/other-plugin' >"$detached91_file"
  LANJUMP_PICK_BIN=/opt/lanjump/lanjump-pick.zsh
  tmuxx() {
    local hook file
    case $1 in
      show-hooks)
        if [[ ${@[-1]} == -g ]]; then
          local f base
          setopt local_options nullglob
          for f in "$PICK_SELFTEST_HOOK91_DIR"/*; do
            base=${f:t}
            print -r -- "$base $(<"$f")"
          done
        else
          hook=${@[-1]}
          file="$PICK_SELFTEST_HOOK91_DIR/$hook"
          if [[ -f "$file" ]]; then
            print -r -- "$hook $(<"$file")"
          else
            print -r -- "$hook "
          fi
        fi
        ;;
      set-hook)
        hook=$3
        file="$PICK_SELFTEST_HOOK91_DIR/$hook"
        if [[ $2 == -gu ]]; then
          rm -f -- "$file"
        elif [[ $2 == -g ]]; then
          print -r -- "${@[4,-1]}" >"$file"
        fi
        ;;
    esac
    return 0
  }
  hooks_installed=0
  tmux_install_snapshot_hooks
  detached91_got=
  [[ -f "$detached91_file" ]] && detached91_got=$(<"$detached91_file")
  expect snap/hook-keep-foreign-detached-91 'run-shell -b /usr/local/bin/other-plugin' "$detached91_got"
  rm -rf "$PICK_SELFTEST_HOOK91_DIR"
  unset PICK_SELFTEST_HOOK91_DIR
  # #162: remote pick is ~/.local/bin/lanjump-pick; hooks must not keep
  # pointing at the Mac-only Application Support path.
  got=$(LANJUMP_PICK_BIN=/tmp/lanjump-pick snapshot_hook_shell)
  expect snap/hook-env-bin 'zsh=$(command -v zsh) || { echo "lanjump: 找不到 zsh。" >&2; exit 127; }; "$zsh" /tmp/lanjump-pick --snapshot >/dev/null 2>&1' "$got"
  local hook_home hook_pick app_home app_pick stale_sr
  hook_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook-local.XXXXXX")
  mkdir -p "$hook_home/.local/bin"
  hook_pick=$hook_home/.local/bin/lanjump-pick
  : >"$hook_pick"
  got=$(unset LANJUMP_PICK_BIN; HOME=$hook_home snapshot_hook_shell)
  expect snap/hook-local-bin "zsh=\$(command -v zsh) || { echo \"lanjump: 找不到 zsh。\" >&2; exit 127; }; \"\$zsh\" $(printf %q "$hook_pick") --snapshot >/dev/null 2>&1" "$got"
  if [[ $got == *'Application Support'* ]]; then
    print -u2 "FAIL snap/hook-local-bin leaked Application Support got=$(printf %q "$got")"
    (( fails++ ))
  fi
  app_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook-app.XXXXXX")
  mkdir -p "$app_home/Library/Application Support/lanjump"
  app_pick="$app_home/Library/Application Support/lanjump/lanjump-pick.zsh"
  : >"$app_pick"
  got=$(unset LANJUMP_PICK_BIN; HOME=$app_home snapshot_hook_shell)
  expect snap/hook-app-default "zsh=\$(command -v zsh) || { echo \"lanjump: 找不到 zsh。\" >&2; exit 127; }; \"\$zsh\" $(printf %q "$app_pick") --snapshot >/dev/null 2>&1" "$got"
  if [[ $got == *'.local/bin/lanjump-pick'* ]]; then
    print -u2 "FAIL snap/hook-app-default used local/bin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  # #286: local install wins over a synced ~/.local/bin leftover.
  local both_home both_local both_app
  both_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook-both.XXXXXX")
  mkdir -p "$both_home/.local/bin" "$both_home/Library/Application Support/lanjump"
  both_local=$both_home/.local/bin/lanjump-pick
  both_app="$both_home/Library/Application Support/lanjump/lanjump-pick.zsh"
  : >"$both_local"
  : >"$both_app"
  got=$(unset LANJUMP_PICK_BIN; HOME=$both_home snapshot_pick_bin)
  expect snap/prefer-app-over-synced "$both_app" "$got"
  : >"$tmux_log"
  unset LANJUMP_PICK_BIN
  LANJUMP_PICK_BIN=$hook_pick
  stale_sr="#(/bin/zsh $(printf %q "$app_pick") --snapshot;)"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    if [[ $* == *show-options*-gv\ status-right* ]]; then
      print -r -- "$stale_sr"
    fi
    return 0
  }
  hooks_installed=0
  tmux_install_snapshot_hooks
  hook_log=$(<"$tmux_log")
  if [[ $hook_log != *"$hook_pick"* ]]; then
    print -u2 "FAIL snap/hook-stale missing local pick got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log != *'set-hook -g client-detached[91]'* ]]; then
    print -u2 "FAIL snap/hook-stale missing client-detached got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log != *'set-option -g status-right'* ]]; then
    print -u2 "FAIL snap/hook-stale missing status-right replace got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log == *'set-option -ag status-right'* ]]; then
    print -u2 "FAIL snap/hook-stale appended instead of replace got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log == *"$app_pick"* && $hook_log == *'set-option -g status-right'* ]]; then
    print -u2 "FAIL snap/hook-stale kept Application Support got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  unset LANJUMP_PICK_BIN
  rm -rf "$hook_home" "$app_home"
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'keep\x1f/proj/keep\x1f0\x1fzsh'
        print -r -- $'test\x1f/tmp/test\x1f0\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/new-named-ws 1 "${snap_workspace[test]}"
  if [[ ${snap_attached[test]:-0} == 0 ]]; then
    print -u2 "FAIL snap/new-named-attached should be set"
    (( fails++ ))
  fi
  collect_restore_names
  if [[ ${restore_names[(Ie)test]} -ne 0 ]]; then
    print -u2 "FAIL snap/new-named restored unpinned test got=${restore_names[*]}"
    (( fails++ ))
  fi
  collect_open_window_names
  if [[ ${open_window_names[(Ie)test]} -eq 0 ]]; then
    print -u2 "FAIL snap/new-named should be in open-window list got=${open_window_names[*]}"
    (( fails++ ))
  fi

  # #116: unpinned named session. cd $HOME must not overwrite the stored project cwd.
  snap_names=(home-cd)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[home-cd]=/proj/keep
  snap_occupied[home-cd]=0
  snap_workspace[home-cd]=1
  snap_cmd[home-cd]=zsh
  snap_attached[home-cd]=123
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  save_session_snapshot
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'home-cd\x1f'"$HOME"$'\x1f0\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/home-cd-keeps-cwd /proj/keep "${snap_cwd[home-cd]:-}"
  collect_restore_names
  if [[ -n ${restore_cwd[home-cd]:-} || ${restore_names[(Ie)home-cd]} -ne 0 ]]; then
    print -u2 "FAIL snap/home-cd-restore restored unpinned home-cd got=${restore_names[*]}"
    (( fails++ ))
  fi
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'home-cd\x1f/opt/other\x1f0\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snapshot_live_sessions
  expect snap/home-cd-follow-live /opt/other "${snap_cwd[home-cd]:-}"

  # #116: pinned cwd is the fallback when snap was already home and the live pane is home.
  snap_names=(pin-home)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[pin-home]=$HOME
  snap_occupied[pin-home]=0
  snap_workspace[pin-home]=1
  snap_cmd[pin-home]=zsh
  snap_attached[pin-home]=123
  save_session_snapshot
  print -r -- $'name pin-home\ncwd /proj/pinned\ngrok \n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  LANJUMP_SNAPSHOT_MIN=0
  tmuxx() {
    case $1 in
      list-sessions)
        print -r -- $'pin-home\x1f'"$HOME"$'\x1f0\x1fzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  run_session_snapshot
  unset LANJUMP_SNAPSHOT_MIN
  expect snap/pin-home-loaded-pin /proj/pinned "${pinned_cwd[pin-home]:-}"
  expect snap/pin-home-keeps-cwd /proj/pinned "${snap_cwd[pin-home]:-}"
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()

  # #213: truncate-then-append exposes an empty/partial dest to readers.
  # After each print during save, dest must stay a complete snapshot
  # (the old bytes, or the full new file).
  session_snapshot_file
  local snap213=$REPLY
  mkdir -p "${snap213:h}"
  snap_names=(old-a old-b)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[old-a]=/tmp/a
  snap_cwd[old-b]=/tmp/b
  snap_occupied[old-a]=0
  snap_occupied[old-b]=1
  snap_workspace[old-a]=1
  snap_workspace[old-b]=0
  snap_cmd[old-a]=zsh
  snap_cmd[old-b]=grok
  snap_attached[old-a]=1
  snap_attached[old-b]=2
  save_session_snapshot
  local snap213_old snap213_mid snap213_n snap213_line
  local -a snap213_lines
  local -i snap213_torn=0 snap213_names=0 snap213_cwd=0 snap213_cmd=0
  local -i snap213_occ=0 snap213_ws=0 snap213_att=0
  snap213_old=$(<"$snap213")
  snap_names=(new-a new-b new-c)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  for snap213_n in new-a new-b new-c; do
    snap_cwd[$snap213_n]=/tmp/$snap213_n
    snap_occupied[$snap213_n]=0
    snap_workspace[$snap213_n]=1
    snap_cmd[$snap213_n]=zsh
    snap_attached[$snap213_n]=9
  done
  print() {
    builtin print "$@"
    snap213_mid=$(<"$snap213")
    if [[ $snap213_mid == "$snap213_old" ]]; then
      return 0
    fi
    if [[ -z $snap213_mid ]]; then
      snap213_torn=1
      return 0
    fi
    snap213_names=0
    snap213_cwd=0
    snap213_cmd=0
    snap213_occ=0
    snap213_ws=0
    snap213_att=0
    snap213_lines=("${(@f)snap213_mid}")
    for snap213_line in "${snap213_lines[@]}"; do
      case $snap213_line in
        name\ *) (( snap213_names++ )) ;;
        cwd\ *) (( snap213_cwd++ )) ;;
        cmd\ *) (( snap213_cmd++ )) ;;
        occupied\ *) (( snap213_occ++ )) ;;
        workspace\ *) (( snap213_ws++ )) ;;
        attached\ *) (( snap213_att++ )) ;;
      esac
    done
    if (( snap213_names != 3 || snap213_cwd != 3 || snap213_cmd != 3 || snap213_occ != 3 || snap213_ws != 3 || snap213_att != 3 )); then
      snap213_torn=1
    fi
  }
  save_session_snapshot
  unfunction print
  if (( snap213_torn )); then
    print -u2 "FAIL snap/atomic-write dest was torn mid-save"
    (( fails++ ))
  fi
  load_session_snapshot
  expect snap/atomic-write-count 3 "${#snap_names[@]}"

  # #309: mv onto dest replaces a symlink (dotfiles) with a regular file.
  session_snapshot_file
  local snap309=$REPLY
  local snap309_dot="$testhome/dotfiles/session-snapshot"
  mkdir -p "${snap309:h}" "${snap309_dot:h}"
  print -r -- $'name old-link\ncwd /tmp/old\ncmd zsh\noccupied 0\nworkspace 0\nattached 0\n' >"$snap309_dot"
  rm -f "$snap309"
  ln -s "$snap309_dot" "$snap309"
  snap_names=(new-link)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[new-link]=/tmp/new
  snap_occupied[new-link]=0
  snap_workspace[new-link]=1
  snap_cmd[new-link]=zsh
  snap_attached[new-link]=1
  save_session_snapshot
  if [[ ! -L $snap309 ]]; then
    print -u2 "FAIL snap/atomic-write-symlink dest is no longer a symlink"
    (( fails++ ))
  fi
  if [[ ${snap309:A} != "${snap309_dot:A}" ]]; then
    print -u2 "FAIL snap/atomic-write-symlink target changed want=$(printf %q "${snap309_dot:A}") got=$(printf %q "${snap309:A}")"
    (( fails++ ))
  fi
  load_session_snapshot
  expect snap/atomic-write-symlink-count 1 "${#snap_names[@]}"
  expect snap/atomic-write-symlink-name new-link "${snap_names[1]:-}"
  expect snap/atomic-write-symlink-target new-link "$(awk '$1=="name"{print $2; exit}' "$snap309_dot")"
  rm -f "$snap309"
  : >"$snap309"

  # #222: GNU stat -f %m prints a mount point; a just-written snapshot
  # must still count as recent so status ticks do not rewrite every time.
  session_snapshot_file
  : >"$REPLY"
  stat() {
    if [[ $1 == -c && $2 == %Y && -n ${3:-} ]]; then
      print -r -- $EPOCHSECONDS
      return 0
    fi
    # GNU coreutils: -f is --file-system, %m is the mount point.
    if [[ $1 == -f && $2 == %m ]]; then
      print -r -- /
      return 0
    fi
    return 1
  }
  LANJUMP_SNAPSHOT_MIN=2
  if ! snapshot_recently_written; then
    print -u2 "FAIL snap/gnu-stat-throttle GNU-style stat -f %m skipped recent snapshot"
    (( fails++ ))
  fi
  unfunction stat
  unset LANJUMP_SNAPSHOT_MIN

  : >"$tmux_log"
  snap_cmd[idle-grok]=grok-1.0.24-mac
  snap_cwd[idle-grok]=/proj/lanjump
  attach_shell_only=0
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- "$HOME"
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes) print -r -- '%1'; return 0 ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command idle-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/idle still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message) print -r -- grok-1.0.24-mac; return 0 ;;
      send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command idle-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/running-grok still sent command got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  attach_shell_only=1
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message) print -r -- zsh; return 0 ;;
      send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command idle-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/shell-only still sent grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  attach_shell_only=0

  : >"$tmux_log"
  snap_cmd[home-grok]=grok-1.0.24-mac
  snap_cwd[home-grok]=$HOME
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- "$HOME"
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes) print -r -- '%1'; return 0 ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command home-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok --resume'* || $restore_log == *'grok -c'* ]]; then
    print -u2 "FAIL resume/home still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cmd[inferme]=grok-1.0.24-mac
  snap_cwd[inferme]=$HOME
  pinned_cwd[inferme]=$HOME
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- "$HOME"
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes) print -r -- '%1'; return 0 ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command inferme
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/named-project still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cmd[wrong-cwd]=grok-1.0.24-mac
  snap_cwd[wrong-cwd]=/proj/keep
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- "$HOME"
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes) print -r -- '%1'; return 0 ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command wrong-cwd
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/cd still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # tmux 3.7c: session-only -t '=$name' leaves pane formats empty; grok is still running.
  : >"$tmux_log"
  snap_cmd[reattach-grok]=grok-1.0.24-mac
  snap_cwd[reattach-grok]=/proj/lanjump
  attach_shell_only=0
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *'-t =reattach-grok '* ]]; then
          print -r -- ''
          return 0
        fi
        if [[ $* == *pane_current_command* ]]; then
          print -r -- grok-1.0.24-mac
        else
          print -r -- /proj/lanjump
        fi
        return 0
        ;;
      list-panes)
        if [[ $* == *pane_current_command* ]]; then
          print -r -- grok-1.0.24-mac
        elif [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- '%1'
        fi
        return 0
        ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command reattach-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL resume/session-only-empty killed running grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'-t =reattach-grok '* && $restore_log != *'-t =reattach-grok:'* ]]; then
    print -u2 "FAIL resume/session-only-empty still used session-only pane target got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cmd[unread-grok]=grok-1.0.24-mac
  snap_cwd[unread-grok]=/proj/lanjump
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message) print -r -- ''; return 0 ;;
      list-panes) print -r -- '%1'; return 0 ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command unread-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL resume/unread-command mutated pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #87: idle current pane vs first pane in a split. Resume must not respawn %1.
  : >"$tmux_log"
  snap_cmd[split-idle]=grok-1.0.24-mac
  snap_cwd[split-idle]=/proj/lanjump
  attach_shell_only=0
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- '%1'
        print -r -- '%2'
        return 0
        ;;
      respawn-pane|send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command split-idle
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/split-idle still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #105: idle current pane, grok still running in another window. Jump there; do not respawn.
  : >"$tmux_log"
  snap_cmd[jump-grok]=grok-1.0.24-mac
  snap_cwd[jump-grok]=/proj/lanjump
  attach_shell_only=0
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- $'%1\tzsh\n%2\tgrok'
        return 0
        ;;
      respawn-pane|send-keys|select-window|select-pane) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command jump-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'list-panes -s'* ]]; then
    print -u2 "FAIL resume/jump-live-grok missing session-wide list-panes got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL resume/jump-live-grok missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'respawn-pane'* ]]; then
    print -u2 "FAIL resume/jump-live-grok still respawned idle pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cmd[jump-grok-ver]=grok-1.0.24-mac
  snap_cwd[jump-grok-ver]=/proj/lanjump
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- $'%1\tzsh\n%2\tgrok-1.0.24-mac'
        return 0
        ;;
      respawn-pane|send-keys|select-window|select-pane) return 0 ;;
      *) return 0 ;;
    esac
  }
  maybe_resume_last_command jump-grok-ver
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL resume/jump-live-grok-ver missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'respawn-pane'* ]]; then
    print -u2 "FAIL resume/jump-live-grok-ver still respawned idle pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # Ordinary attach (go without --grok / list enter) must jump, not respawn.
  functions -c mark_snapshot_occupied _st105_mark
  functions -c load_session_snapshot _st105_load
  functions -c remember_last_session _st105_remember
  functions -c restore_tty _st105_restore
  functions -c tmux_tty _st105_tmux_tty
  functions -c snapshot_live_sessions _st105_snap
  functions -c effective_open_target _st105_eot
  mark_snapshot_occupied() { : }
  load_session_snapshot() { : }
  remember_last_session() { : }
  restore_tty() { : }
  tmux_tty() { print -r -- "tmux_tty $*" >>"$tmux_log"; }
  snapshot_live_sessions() { : }
  effective_open_target() { print -r -- current; }
  : >"$tmux_log"
  snap_cmd[jump-grok]=grok-1.0.24-mac
  snap_cwd[jump-grok]=/proj/lanjump
  attach_shell_only=0
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- $'%1\tzsh\n%2\tgrok'
        return 0
        ;;
      respawn-pane|send-keys|select-window|select-pane|attach-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  attach_named_session jump-grok 0 0
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL resume/attach-jump-live-grok missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'respawn-pane'* ]]; then
    print -u2 "FAIL resume/attach-jump-live-grok still respawned idle pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  functions -c _st105_mark mark_snapshot_occupied
  functions -c _st105_load load_session_snapshot
  functions -c _st105_remember remember_last_session
  functions -c _st105_restore restore_tty
  functions -c _st105_tmux_tty tmux_tty
  functions -c _st105_snap snapshot_live_sessions
  functions -c _st105_eot effective_open_target
  unset -f _st105_mark _st105_load _st105_remember _st105_restore \
    _st105_tmux_tty _st105_snap _st105_eot

  # Attach occupies the snapshot. There is no resume prompt to cancel with q.
  functions -c restore_tty _st194_restore
  functions -c tmux_tty _st194_tmux_tty
  functions -c snapshot_live_sessions _st194_snap
  functions -c effective_open_target _st194_eot
  functions -c maybe_resume_last_command _st194_resume
  restore_tty() { : }
  tmux_tty() { : }
  snapshot_live_sessions() { : }
  effective_open_target() { print -r -- current; }
  maybe_resume_last_command() { : }
  tmuxx() {
    case $1 in
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- $'%1\tzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snap_names=(idle-grok)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[idle-grok]=/proj/lanjump
  snap_occupied[idle-grok]=0
  snap_workspace[idle-grok]=0
  snap_cmd[idle-grok]=grok-1.0.24-mac
  snap_attached[idle-grok]=123
  pinned_names=()
  save_session_snapshot
  attach_named_session idle-grok 1 0 >/dev/null
  load_session_snapshot
  expect resume/enter-y-ws 1 "${snap_workspace[idle-grok]:-}"
  expect resume/enter-y-occ 1 "${snap_occupied[idle-grok]:-}"
  if [[ ${snap_attached[idle-grok]:-0} == 123 || ${snap_attached[idle-grok]:-0} == 0 ]]; then
    print -u2 "FAIL resume/enter-y-att still old got=${snap_attached[idle-grok]:-}"
    (( fails++ ))
  fi
  snap_workspace[idle-grok]=0
  snap_occupied[idle-grok]=0
  snap_attached[idle-grok]=123
  save_session_snapshot
  print -r -- '' | attach_named_session idle-grok 1 0 >/dev/null
  load_session_snapshot
  expect resume/enter-empty-ws 1 "${snap_workspace[idle-grok]:-}"
  expect resume/enter-empty-occ 1 "${snap_occupied[idle-grok]:-}"
  if [[ ${snap_attached[idle-grok]:-0} == 123 || ${snap_attached[idle-grok]:-0} == 0 ]]; then
    print -u2 "FAIL resume/enter-empty-att still old got=${snap_attached[idle-grok]:-}"
    (( fails++ ))
  fi
  drop_snap_record idle-grok
  save_session_snapshot
  functions -c _st194_restore restore_tty
  functions -c _st194_tmux_tty tmux_tty
  functions -c _st194_snap snapshot_live_sessions
  functions -c _st194_eot effective_open_target
  functions -c _st194_resume maybe_resume_last_command
  unset -f _st194_restore _st194_tmux_tty _st194_snap _st194_eot _st194_resume

  # n filling an existing name enters it; no grok-resume prompt.
  functions -c restore_tty _st204_restore
  functions -c setup_tty _st204_setup
  functions -c draw _st204_draw
  functions -c load_items _st204_load_items
  functions -c tmux_prepare_color _st204_color
  functions -c tmux_prepare_keys _st204_keys
  functions -c tmux_tty _st204_tmux_tty
  functions -c snapshot_live_sessions _st204_snap
  functions -c effective_open_target _st204_eot
  restore_tty() { : }
  setup_tty() { : }
  draw() { : }
  load_items() { : }
  tmux_prepare_color() { : }
  tmux_prepare_keys() { : }
  tmux_tty() { : }
  snapshot_live_sessions() { : }
  effective_open_target() { print -r -- current; }
  : >"$tmux_log"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 0 ;;
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /proj/lanjump
        else
          print -r -- zsh
        fi
        return 0
        ;;
      list-panes)
        print -r -- $'%1\tzsh'
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  snap_names=(demo)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[demo]=/proj/lanjump
  snap_occupied[demo]=0
  snap_workspace[demo]=0
  snap_cmd[demo]=grok-1.0.24-mac
  snap_attached[demo]=123
  pinned_names=()
  HAS_TMUX=1
  LANJUMP_GROK_BIN=grok
  attach_shell_only=0
  save_session_snapshot
  out=$(print -l -- demo '' | prompt_new)
  load_session_snapshot
  if [[ $out == *'上次在跑 grok'* ]]; then
    print -u2 "FAIL resume/n-existing still asked to resume grok got=$(printf %q "$out")"
    (( fails++ ))
  fi
  if [[ $out != *'直接进入'* ]]; then
    print -u2 "FAIL resume/n-existing missing 直接进入 got=$(printf %q "$out")"
    (( fails++ ))
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'respawn-pane'* || $restore_log == *'grok -c'* || $restore_log == *'grok --resume'* ]]; then
    print -u2 "FAIL resume/n-existing still spawned grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  drop_snap_record demo
  save_session_snapshot
  functions -c _st204_restore restore_tty
  functions -c _st204_setup setup_tty
  functions -c _st204_draw draw
  functions -c _st204_load_items load_items
  functions -c _st204_color tmux_prepare_color
  functions -c _st204_keys tmux_prepare_keys
  functions -c _st204_tmux_tty tmux_tty
  functions -c _st204_snap snapshot_live_sessions
  functions -c _st204_eot effective_open_target
  unset -f _st204_restore _st204_setup _st204_draw _st204_load_items \
    _st204_color _st204_keys _st204_tmux_tty _st204_snap _st204_eot

  : >"$tmux_log"
  snap_cwd[reattach-cwd]=/proj/lanjump
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *'-t =reattach-cwd '* ]]; then
          print -r -- ''
          return 0
        fi
        print -r -- /proj/lanjump
        return 0
        ;;
      send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  ensure_session_cwd reattach-cwd
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL cwd/session-only-empty sent cd into pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cwd[unread-cwd]=/proj/lanjump
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message) print -r -- ''; return 0 ;;
      send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  ensure_session_cwd unread-cwd
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL cwd/unread-path sent cd into pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  : >"$tmux_log"
  snap_cwd[idle-cd]=/proj/keep
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      display-message)
        if [[ $* == *'-t =idle-cd '* ]]; then
          print -r -- ''
          return 0
        fi
        print -r -- "$HOME"
        return 0
        ;;
      send-keys) return 0 ;;
      *) return 0 ;;
    esac
  }
  ensure_session_cwd idle-cd
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'send-keys'* || $restore_log != *'cd /proj/keep'* ]]; then
    print -u2 "FAIL cwd/idle-cd missing send-keys cd to project got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  ghostty_close_others=1
  script=$(ghostty_osascript_for_sessions lanjump)
  if [[ $script != *'preexisting'* || $script != *'close (first window whose id is i)'* ]]; then
    print -u2 "FAIL ghostty/close-others missing close extra windows got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'saving no'* ]]; then
    print -u2 "FAIL ghostty/close-others uses saving no which Ghostty rejects got=$(printf %q "$script")"
    (( fails++ ))
  fi
  # #170: Ghostty welcome titles ~; a home-cwd session does too. Close only
  # windows that existed before open, never every window named ~.
  if [[ $script == *'name of w is "~"'* || $script == *'if name of w is "~"'* ]]; then
    print -u2 "FAIL ghostty/close-home-title generated script closes leftover windows by title ~ got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ ${functions[open_ghostty_session_tabs]} == *'name of w is "~"'* || ${functions[open_ghostty_session_tabs]} == *'if name of w is "~"'* ]]; then
    print -u2 "FAIL ghostty/close-home-title leftover close uses window title ~"
    (( fails++ ))
  fi
  if [[ $script != *'id of every window'* ]]; then
    print -u2 "FAIL ghostty/close-home-title missing before-open window id snapshot got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'System Events'* || $script != *'preexistingSE'* || $script != *'first window whose id is i'* ]]; then
    print -u2 "FAIL ghostty/close-home-title leftover close missing System Events before-set ids got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ ${script%%new window*} != *'preexistingSE'* || ${script%%new window*} != *'id of every window'* ]]; then
    print -u2 "FAIL ghostty/close-home-title System Events id snapshot is not before new window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/ghostty.applescript"
  if (( _lj_ghostty_dict )); then
    if ! /usr/bin/osacompile -o "$testhome/ghostty.scpt" "$testhome/ghostty.applescript" 2>"$testhome/osacompile.err"; then
      print -u2 "FAIL ghostty/script-compile $(<"$testhome/osacompile.err") got=$(printf %q "$script")"
      (( fails++ ))
    fi
  fi
  ghostty_close_others=0

  attach_shell_only=1
  script=$(ghostty_osascript_for_sessions lanjump)
  if [[ $script != *'LANJUMP_ATTACH_SPEC=lanjump'* ]]; then
    print -u2 "FAIL ghostty/script-shell missing spec env got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'LANJUMP_ATTACH_SHELL=1'* ]]; then
    print -u2 "FAIL ghostty/script-shell missing LANJUMP_ATTACH_SHELL got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'attach --shell'* ]]; then
    print -u2 "FAIL ghostty/script-shell still puts --shell in command got=$(printf %q "$script")"
    (( fails++ ))
  fi
  attach_shell_only=0

  open_target=auto
  open_placement=window
  save_settings
  open_target=current
  open_placement=tab
  load_settings
  expect settings/default-target auto "$open_target"
  expect settings/default-placement window "$open_placement"

  open_target=ghostty
  open_placement=tab
  save_settings
  open_target=auto
  open_placement=window
  load_settings
  expect settings/roundtrip-target ghostty "$open_target"
  expect settings/roundtrip-placement tab "$open_placement"

  print -r -- $'open_target nope\nopen_placement sideways\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/bad-target auto "$open_target"
  expect settings/bad-placement window "$open_placement"

  # Missing preview key is off. v remembers on/off. Another picker's
  # placement change must not clobber a preview this process did not touch.
  preview_on=1
  print -r -- $'open_target auto\nopen_placement window\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/preview-missing-off 0 "$preview_on"
  preview_on=1
  save_settings
  preview_on=0
  load_settings
  expect settings/preview-roundtrip-on 1 "$preview_on"
  toggle_preview
  expect settings/preview-toggle-off 0 "$preview_on"
  preview_on=1
  load_settings
  expect settings/preview-stays-off 0 "$preview_on"
  toggle_preview
  expect settings/preview-toggle-on 1 "$preview_on"
  preview_on=0
  load_settings
  expect settings/preview-stays-on 1 "$preview_on"
  print -r -- $'preview maybe\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/preview-bad-off 0 "$preview_on"
  print -r -- $'open_target auto\nopen_placement window\npreview off\nproject_root /opt/keep\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  open_target=terminal
  print -r -- $'open_target auto\nopen_placement tab\npreview on\nproject_root /opt/keep\n' >"$HOME/Library/Application Support/lanjump/settings"
  save_settings
  load_settings
  expect settings/preview-merge-target terminal "$open_target"
  expect settings/preview-merge-placement tab "$open_placement"
  expect settings/preview-merge-kept 1 "$preview_on"
  expect settings/preview-merge-root /opt/keep "${project_roots[*]}"
  open_target=auto
  open_placement=window

  expect settings/label-auto '自动（Ghostty 优先）' "$(settings_value_label target)"
  open_target=ghostty
  expect settings/label-ghostty Ghostty "$(settings_value_label target)"
  open_target=terminal
  expect settings/label-terminal 系统终端 "$(settings_value_label target)"
  open_placement=tab
  expect settings/label-tab 已有窗口加标签 "$(settings_value_label placement)"

  settings_cursor=1
  open_target=auto
  cycle_setting
  expect settings/cycle-target ghostty "$open_target"
  cycle_setting
  expect settings/cycle-target-terminal terminal "$open_target"
  cycle_setting
  expect settings/cycle-target-auto auto "$open_target"
  if [[ $open_target == current ]]; then
    print -u2 "FAIL settings/cycle-no-current got current"
    (( fails++ ))
  fi
  print -r -- $'open_target current\nopen_placement window\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/legacy-current-is-auto auto "$open_target"
  settings_cursor=2
  open_placement=window
  cycle_setting
  expect settings/cycle-placement tab "$open_placement"

  print -r -- $'open_target auto\nopen_placement window\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/default-root "$HOME/Documents/projects" "${project_roots[*]}"
  expect resolve/default-root "$HOME/Documents/projects/inferme" "$(resolve_session_cwd inferme "$HOME")"

  local isolated
  isolated=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-noroots.XXXXXX")
  HOME=$isolated
  mkdir -p "$HOME/Library/Application Support/lanjump"
  project_roots=(leftover)
  load_settings
  expect settings/no-projects-empty '' "${project_roots[*]}"
  HOME=$testhome
  rm -rf "$isolated"

  local r1 r2
  r1=$testhome/roots/first
  r2=$testhome/roots/second
  mkdir -p "$r1/dup" "$r2/dup" "$r2/onlysecond"
  project_roots=("$r1" "$r2")
  open_target=auto
  open_placement=window
  save_settings
  project_roots=()
  snap_cwd=()
  pinned_cwd=()
  load_settings
  expect settings/two-roots "$r1 $r2" "${project_roots[*]}"
  expect resolve/earlier-root "$r1/dup" "$(resolve_session_cwd dup)"
  expect resolve/later-if-missing "$r2/onlysecond" "$(resolve_session_cwd onlysecond)"

  pinned_cwd[dup]=/opt/recorded
  expect resolve/pin-over-root /opt/recorded "$(resolve_session_cwd dup)"
  unset 'pinned_cwd[dup]'
  unset 'snap_cwd[dup]'
  expect resolve/live-over-root /opt/live "$(resolve_session_cwd dup /opt/live)"
  expect resolve/live-home-uses-root "$r1/dup" "$(resolve_session_cwd dup "$HOME")"

  project_roots=("$testhome/roots/missing" "$r2")
  save_settings
  load_settings
  expect resolve/skip-missing "$r2/dup" "$(resolve_session_cwd dup)"

  mkdir -p "$HOME/altroot/tildeme"
  print -r -- $'open_target auto\nopen_placement window\nproject_root ~/altroot\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect resolve/tilde "$HOME/altroot/tildeme" "$(resolve_session_cwd tildeme)"

  mkdir -p "$testhome/root with space/child"
  project_roots=("$testhome/root with space")
  save_settings
  project_roots=()
  load_settings
  expect settings/space-root "$testhome/root with space" "${project_roots[1]}"
  expect resolve/space-root "$testhome/root with space/child" "$(resolve_session_cwd child)"
  if (( ${+functions[prompt_add_project_root]} )); then
    print -u2 "FAIL settings/no-fullscreen-prompt prompt_add_project_root should be gone"
    (( fails++ ))
  fi
  project_roots=()
  settings_cursor=3
  settings_enter
  expect settings/input-starts "1" "$settings_input_on"
  settings_input_buf='/opt/overlay-root'
  settings_commit_input
  expect settings/input-commit '/opt/overlay-root' "${project_roots[1]}"
  expect settings/input-clears "0" "$settings_input_on"
  settings_input_on=1
  settings_input_buf='   '
  settings_commit_input
  expect settings/input-empty-cancels '/opt/overlay-root' "${project_roots[*]}"

  # #214: local path= is tied to PATH; first-time save_settings then cannot mkdir.
  local firsthome
  firsthome=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-first-settings.XXXXXX")
  HOME=$firsthome
  project_roots=()
  settings_input_on=1
  settings_input_buf='/opt/first-root'
  settings_commit_input
  project_roots=()
  load_settings
  expect settings/first-write-persists /opt/first-root "${project_roots[1]-}"
  HOME=$testhome
  rm -rf "$firsthome"

  # #357: two pickers. This one changes terminal; the other added a root underfoot.
  local set357_home set357_saved_home set357_file
  set357_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-357-settings.XXXXXX") || return 1
  set357_saved_home=$HOME
  HOME=$set357_home
  mkdir -p "$HOME/Library/Application Support/lanjump" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/lanjump"
  settings_file
  set357_file=$REPLY
  mkdir -p "${set357_file:h}"
  print -r -- $'open_target auto\nopen_placement window\nproject_root /opt/orig\n' >"$set357_file"
  load_settings
  open_target=terminal
  print -r -- $'open_target auto\nopen_placement tab\nproject_root /opt/orig\nproject_root /opt/other\n' >"$set357_file"
  save_settings
  load_settings
  expect settings/merge-underfoot-target terminal "$open_target"
  expect settings/merge-underfoot-placement tab "$open_placement"
  expect settings/merge-underfoot-roots '/opt/orig /opt/other' "${project_roots[*]}"
  HOME=$set357_saved_home
  rm -rf "$set357_home"

  # #96: settings overlay input must ignore CSI; only a true Esc cancels.
  expect_settings_input_key() {
    local label=$1 want=$2 seq=$3
    local leftover=""
    {
      if settings_input_read; then
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
  expect_settings_input_key settings/input-pagedown other $'\e[6~'
  expect_settings_input_key settings/input-pageup other $'\e[5~'
  expect_settings_input_key settings/input-home other $'\e[H'
  expect_settings_input_key settings/input-end other $'\e[F'
  expect_settings_input_key settings/input-left other $'\e[D'
  expect_settings_input_key settings/input-csi-u-s-enter other $'\e[13;2u'
  expect_settings_input_key settings/input-alt-enter-s-enter other $'\e\r'
  expect_settings_input_key settings/input-alt-enter-lf other $'\e\n'
  expect_settings_input_key settings/input-ss3-up other $'\eOA'
  expect_settings_input_key settings/input-esc esc $'\e'
  expect_settings_input_key settings/input-enter enter $'\r'
  expect_settings_input_key settings/input-backspace backspace $'\x7f'
  expect_settings_input_key settings/input-char char a
  expect settings/input-char-byte a "$settings_input_char"

  settings_input_on=1
  settings_input_buf='/tmp/typed-root'
  {
    settings_input_read
    got=$REPLY
  } < <(print -n $'\e[6~')
  case $got in
    esc)
      settings_input_on=0
      settings_input_buf=
      ;;
  esac
  expect settings/input-pagedown-keeps-on "1" "$settings_input_on"
  expect settings/input-pagedown-keeps-buf '/tmp/typed-root' "$settings_input_buf"

  local -a settings_input_keys
  local settings_input_quit=0
  settings_input_keys=()
  settings_input_on=1
  settings_input_buf='/tmp/typed-root'
  {
    while true; do
      settings_input_read || break
      settings_input_keys+=("$REPLY")
      case $REPLY in
        esc)
          settings_input_on=0
          settings_input_buf=
          settings_input_quit=1
          break
          ;;
      esac
    done
  } < <(print -n $'\e[6~\e[H\e[F\e[D\e[13;2u\e')
  expect settings/input-csi-then-esc-quit 1 "$settings_input_quit"
  expect settings/input-csi-then-esc-on "0" "$settings_input_on"
  expect settings/input-csi-then-esc-buf '' "$settings_input_buf"
  if (( ${#settings_input_keys} != 6 )); then
    print -u2 "FAIL settings/input-csi-keys got=${settings_input_keys[*]} want=5 others then esc"
    (( fails++ ))
  elif [[ ${settings_input_keys[-1]} != esc ]]; then
    print -u2 "FAIL settings/input-csi-last got=$(printf %q "${settings_input_keys[-1]}") want=esc"
    (( fails++ ))
  fi
  for k in "${settings_input_keys[1,-2]}"; do
    if [[ $k == esc ]]; then
      print -u2 "FAIL settings/input-csi treated as esc got=${settings_input_keys[*]}"
      (( fails++ ))
      break
    fi
  done

  # #114: ESC CR then Esc must not cancel on the first key.
  settings_input_keys=()
  settings_input_quit=0
  settings_input_on=1
  settings_input_buf='/tmp/typed-root'
  {
    while true; do
      settings_input_read || break
      settings_input_keys+=("$REPLY")
      case $REPLY in
        esc)
          settings_input_on=0
          settings_input_buf=
          settings_input_quit=1
          break
          ;;
      esac
    done
  } < <(print -n $'\e\r\e')
  expect settings/input-alt-enter-then-esc-quit 1 "$settings_input_quit"
  expect settings/input-alt-enter-then-esc-on "0" "$settings_input_on"
  if (( ${#settings_input_keys} != 2 )); then
    print -u2 "FAIL settings/input-alt-enter-then-esc-keys got=${settings_input_keys[*]} want=other then esc"
    (( fails++ ))
  elif [[ ${settings_input_keys[-1]} != esc ]]; then
    print -u2 "FAIL settings/input-alt-enter-then-esc-last got=$(printf %q "${settings_input_keys[-1]}") want=esc"
    (( fails++ ))
  fi
  if (( ${#settings_input_keys} >= 1 )) && [[ ${settings_input_keys[1]} == esc ]]; then
    print -u2 "FAIL settings/input-alt-enter treated as esc got=${settings_input_keys[*]}"
    (( fails++ ))
  fi

  project_roots=('/opt/a' '/opt/b' '/opt/c')
  settings_remove_root 2
  expect settings/remove-middle '/opt/a /opt/c' "${project_roots[*]}"
  project_roots=('/opt/a' '/opt/b')
  settings_cursor=3
  settings_delete_key
  expect settings/delete-key '/opt/b' "${project_roots[*]}"
  project_roots=('/opt/keep')
  settings_cursor=1
  settings_delete_key
  expect settings/delete-key-noop '/opt/keep' "${project_roots[*]}"

  # #196: deleting the first root must compact so a second d removes the rest.
  project_roots=('/opt/a' '/opt/b')
  settings_cursor=3
  settings_delete_key
  expect settings/delete-consecutive-first '/opt/b' "${project_roots[*]}"
  expect settings/delete-consecutive-first-len 1 "${#project_roots}"
  expect settings/delete-consecutive-first-idx1 '/opt/b' "${project_roots[1]-}"
  settings_n_rows
  if (( settings_cursor < 1 || settings_cursor > REPLY )); then
    print -u2 "FAIL settings/delete-consecutive-first-cursor got=$settings_cursor n=$REPLY"
    (( fails++ ))
  fi
  settings_delete_key
  expect settings/delete-consecutive-second '' "${project_roots[*]}"
  expect settings/delete-consecutive-second-len 0 "${#project_roots}"
  settings_n_rows
  if (( settings_cursor < 1 || settings_cursor > REPLY )); then
    print -u2 "FAIL settings/delete-consecutive-second-cursor got=$settings_cursor n=$REPLY"
    (( fails++ ))
  fi

  # #200: clearing every root must persist. No project_root key still defaults.
  project_roots=("$r1" "$r2")
  save_settings
  settings_cursor=3
  settings_delete_key
  settings_delete_key
  save_settings
  project_roots=()
  load_settings
  expect settings/cleared-stays-empty '' "${project_roots[*]}"
  expect settings/cleared-stays-empty-len 0 "${#project_roots}"

  print -r -- $'open_target auto\nopen_placement window\nproject_root\n' >"$HOME/Library/Application Support/lanjump/settings"
  project_roots=(leftover)
  load_settings
  expect settings/empty-sentinel '' "${project_roots[*]}"

  print -r -- $'open_target auto\nopen_placement window\n' >"$HOME/Library/Application Support/lanjump/settings"
  project_roots=()
  load_settings
  expect settings/empty-redefault "$HOME/Documents/projects" "${project_roots[*]}"

  settings_on=1
  settings_cursor=1
  project_roots=('/opt/foo' '/opt/bar')
  host_short=testhost
  COLUMNS=80
  LINES=24
  items_kind=(session)
  items_id=(sess)
  items_name=(sess)
  items_att=(0)
  items_time=('01-01 00:00')
  items_path=('~/p')
  items_summary=('sum')
  items_cmd=(zsh)
  items_activity=(1)
  items_pinned=(0)
  cursor=1
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'＋ 添加项目根'* ]]; then
    print -u2 "FAIL settings/overlay-add missing ＋ 添加项目根 got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain != *'/opt/foo'* || $plain != *'/opt/bar'* ]]; then
    print -u2 "FAIL settings/overlay-roots missing listed roots got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain != *新窗口* ]]; then
    print -u2 "FAIL settings/overlay-new-window missing 新窗口 got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain == *当前窗口* ]]; then
    print -u2 "FAIL settings/overlay-no-current still 当前窗口 got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  settings_on=0
  out=$(draw)
  plain=${out//$'\e'\[[0-9;]#[A-Za-z]/}
  if [[ $plain != *'t 新窗口'* ]]; then
    print -u2 "FAIL help/t-window missing t 新窗口 got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  if [[ $plain != *'Enter 进入'* ]]; then
    print -u2 "FAIL help/enter missing Enter 进入 got=$(printf %q "$plain")"
    (( fails++ ))
  fi
  project_roots=()
  open_target=auto
  open_placement=window

  open_target=auto
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  LANJUMP_GHOSTTY_APP="$testhome/Ghostty.app"
  mkdir -p "$LANJUMP_GHOSTTY_APP"
  expect open/enter-one current "$(picker_open_mode 1 enter)"
  expect open/enter-one-default current "$(effective_open_target 1)"
  expect open/t-one ghostty "$(picker_open_mode 1 t)"
  expect open/auto-ghostty ghostty "$(effective_open_target 1 1)"
  expect open/enter-multi ghostty "$(picker_open_mode 2 enter)"
  expect open/t-multi ghostty "$(picker_open_mode 2 t)"
  expect open/s-enter-one current "$(picker_open_mode 1 s-enter)"
  open_target=ghostty
  LANJUMP_GHOSTTY_APP="$testhome/missing-Ghostty.app"
  expect open/ghostty-missing current "$(effective_open_target 1 1)"
  open_target=auto
  expect open/auto-one-no-ghostty current "$(effective_open_target 1)"
  if terminal_restore_available; then
    expect open/t-one-no-ghostty-uses-terminal terminal "$(picker_open_mode 1 t)"
    expect open/enter-multi-no-ghostty terminal "$(picker_open_mode 2 enter)"
  else
    expect open/t-one-no-ghostty-no-terminal current "$(picker_open_mode 1 t)"
    expect open/enter-multi-no-ghostty current "$(picker_open_mode 2 enter)"
  fi
  LANJUMP_GHOSTTY_APP="$testhome/Ghostty.app"
  mkdir -p "$LANJUMP_GHOSTTY_APP"
  SSH_CONNECTION=1
  expect open/ssh-enter current "$(picker_open_mode 1 enter)"
  expect open/ssh-t current "$(picker_open_mode 1 t)"
  expect open/ssh-multi current "$(picker_open_mode 2 enter)"
  unset SSH_CONNECTION

  open_placement=tab
  ghostty_close_others=0
  LANJUMP_ATTACH_BIN=/Users/mac/.local/bin/lanjump
  script=$(ghostty_osascript_for_sessions lanjump)
  if [[ $script != *'if (count of windows) > 0 then set win to front window'* ]]; then
    print -u2 "FAIL ghostty/tab-existing missing front window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'new tab in win with configuration cfg'* ]]; then
    print -u2 "FAIL ghostty/tab-existing missing new tab got=$(printf %q "$script")"
    (( fails++ ))
  fi
  print -r -- "$script" >"$testhome/ghostty-tab.applescript"
  if (( _lj_ghostty_dict )); then
    if ! /usr/bin/osacompile -o "$testhome/ghostty-tab.scpt" "$testhome/ghostty-tab.applescript" 2>"$testhome/osacompile-tab.err"; then
      print -u2 "FAIL ghostty/tab-compile $(<"$testhome/osacompile-tab.err") got=$(printf %q "$script")"
      (( fails++ ))
    fi
  fi
  ghostty_close_others=1
  script=$(ghostty_osascript_for_sessions lanjump)
  if [[ $script != *'new window with configuration cfg'* ]]; then
    print -u2 "FAIL ghostty/tab-fresh missing new window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  ghostty_close_others=0
  open_placement=window

  tmuxx() {
    case $1 in
      list-clients)
        [[ $3 == '=alive' ]] && { print -r -- /dev/ttys001; return 0 }
        return 1
        ;;
      *) return 0 ;;
    esac
  }
  if ! session_has_live_client alive; then
    print -u2 "FAIL client/alive should count as live"
    (( fails++ ))
  fi
  if session_has_live_client dead; then
    print -u2 "FAIL client/dead should not count as live"
    (( fails++ ))
  fi

  expect boot/before-first-draw 'load_settings load_session_filter load_items setup_tty draw' "${picker_boot_before_first_draw_steps[*]-}"
  expect boot/after-first-draw 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys' "${picker_boot_after_first_draw_steps[*]-}"

  local -a boot_calls boot_saved
  boot_save() {
    local fn
    for fn in "$@"; do
      functions -c "$fn" "_boot_orig_${fn}"
      boot_saved+=("$fn")
    done
  }
  boot_restore() {
    local fn
    for fn in "${boot_saved[@]}"; do
      functions -c "_boot_orig_${fn}" "$fn"
      unset -f "_boot_orig_${fn}"
    done
    boot_saved=()
  }
  boot_save load_settings load_session_filter load_items setup_tty draw \
    maybe_restore_sessions tmux_prepare_color tmux_prepare_keys
  load_settings() { boot_calls+=(load_settings) }
  load_session_filter() { boot_calls+=(load_session_filter) }
  load_items() { boot_calls+=(load_items) }
  setup_tty() { boot_calls+=(setup_tty) }
  draw() { boot_calls+=(draw) }
  maybe_restore_sessions() { boot_calls+=(maybe_restore_sessions) }
  tmux_prepare_color() { boot_calls+=(tmux_prepare_color) }
  tmux_prepare_keys() { boot_calls+=(tmux_prepare_keys) }

  boot_calls=()
  filter_on=1
  picker_boot_before_first_draw
  expect boot/before-runs 'load_settings load_session_filter load_items setup_tty draw' "${boot_calls[*]}"
  expect boot/before-filter-off 0 "$filter_on"

  boot_calls=()
  items_id=(keep)
  tmux_state_invalidate
  load_items() { boot_calls+=(load_items); items_id=(keep restored) }
  picker_boot_after_first_draw
  expect boot/after-runs-changed 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys load_items draw' "${boot_calls[*]}"

  boot_calls=()
  items_id=(keep)
  tmux_state_invalidate
  load_items() { boot_calls+=(load_items) }
  picker_boot_after_first_draw
  expect boot/after-runs-unchanged 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys load_items' "${boot_calls[*]}"

  # #463: a clean census and no created session reuse the first paint.
  boot_calls=()
  items_id=(keep)
  tm_state_dirty=0
  (( tm_state_gen > 0 )) || tm_state_gen=1
  load_items() { boot_calls+=(load_items) }
  picker_boot_after_first_draw
  expect boot/after-skips-clean-load 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys' "${boot_calls[*]}"

  stty_orig='saved-tty'
  maybe_restore_sessions() { boot_calls+=(maybe_restore_sessions); stty_orig=clobbered }
  boot_calls=()
  items_id=(keep)
  picker_boot_after_first_draw
  expect boot/after-keeps-stty saved-tty "$stty_orig"

  functions -c _boot_orig_load_items load_items
  load_items() {
    boot_calls+=(load_items)
    _boot_orig_load_items
  }
  # No pins: tmux down still paints the empty list, cursor row is 新建.
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  boot_calls=()
  HAS_TMUX=1
  items_id=()
  tmuxx() { return 1 }
  picker_boot_before_first_draw
  expect boot/first-paint-empty 'new shell hosts quit' "${items_id[*]}"
  expect boot/first-paint-empty-steps 'load_settings load_session_filter load_items setup_tty draw' "${boot_calls[*]}"

  boot_restore

  # Missing pins: progress screen first, then the list with a count.
  # A failed create is skipped. Cursor prefers the last entered session.
  {
    typeset -A progress_live
    progress_live=()
    print -r -- $'name alpha\ncwd /tmp/alpha\n\nname beta\ncwd /tmp/beta\n\nname gamma\ncwd /tmp/gamma\n' \
      >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    print -r -- beta >"$HOME/Library/Application Support/lanjump/last-session"
    : >"$tmux_log"
    tmuxx() {
      print -r -- "$*" >>"$tmux_log"
      case $1 in
        has-session)
          [[ $2 == -t ]] || return 1
          (( ${progress_live[${3#=}]:-0} )) && return 0
          return 1
          ;;
        new-session)
          [[ $* == *' -s gamma'* ]] && return 1
          local -a args
          args=("$@")
          local idx=${args[(I)-s]}
          (( idx && idx < $#args )) && progress_live[${args[idx+1]}]=1
          return 0
          ;;
        list-sessions)
          if [[ $* == *session_activity* ]]; then
            local n
            for n in "${(@k)progress_live}"; do
              print -r -- "200"$'\x1f'"$n"$'\x1f'"1"$'\x1f'"0"$'\x1f'"/tmp/$n"$'\x1f'"zsh"$'\x1f'"$n"$'\x1f'"zsh"
            done
          fi
          (( ${#progress_live} ))
          ;;
        *) return 0 ;;
      esac
    }
    local progress_out progress_before progress_after restore_log
    # Both paints must run in one process. Separate command substitutions
    # would drop restore_show_progress before the list is drawn.
    progress_out=$(
      picker_boot_before_first_draw
      print -r -- $'\n---AFTER---'
      picker_boot_after_first_draw
      print -r -- $'\n---CURSOR---'
      print -r -- "${items_kind[$cursor]:-} ${items_id[$cursor]:-}"
    )
    progress_before=${progress_out%%$'\n---AFTER---'*}
    progress_after=${progress_out#*$'\n---AFTER---'}
    progress_after=${progress_after%%$'\n---CURSOR---'*}
    if [[ $progress_before != *'正在恢复常驻 session'* || $progress_before != *'0/3'* ]]; then
      print -u2 "FAIL progress/first-paint got=$(printf %q "$progress_before")"
      (( fails++ ))
    fi
    if [[ $progress_before == *'新建 session'* ]]; then
      print -u2 "FAIL progress/first-paint showed the empty list"
      (( fails++ ))
    fi
    if [[ $progress_after != *'1/3  alpha'* || $progress_after != *'3/3  gamma'* ]]; then
      print -u2 "FAIL progress/steps got=$(printf %q "$progress_after")"
      (( fails++ ))
    fi
    if [[ $progress_after != *'失败  gamma'* ]]; then
      print -u2 "FAIL progress/fail-line got=$(printf %q "$progress_after")"
      (( fails++ ))
    fi
    if [[ $progress_after != *'已恢复 2 个，失败 1 个'* ]]; then
      print -u2 "FAIL progress/notice got=$(printf %q "$progress_after")"
      (( fails++ ))
    fi
    if [[ ${functions[draw_restore_progress]} == *sleep* || ${functions[restore_one_missing_session]} == *sleep* || ${functions[picker_boot_after_first_draw]} == *sleep* ]]; then
      print -u2 "FAIL progress/no-extra-pause contains sleep"
      (( fails++ ))
    fi
    if [[ ${progress_out##*$'\n---CURSOR---'} != *'session beta'* ]]; then
      print -u2 "FAIL progress/cursor got=$(printf %q "${progress_out##*$'\n---CURSOR---'}")"
      (( fails++ ))
    fi
    restore_log=$(<"$tmux_log")
    if [[ $restore_log != *'new-session -d -s alpha -c /tmp/alpha'* || $restore_log != *'new-session -d -s beta -c /tmp/beta'* ]]; then
      print -u2 "FAIL progress/create got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    if [[ $restore_log == *'new-session -d -s gamma -c /tmp/gamma'* && $restore_log != *'new-session -d -s gamma'* ]]; then
      :
    fi
    if [[ $restore_log != *'new-session -d -s gamma'* ]]; then
      print -u2 "FAIL progress/gamma-attempted got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi

    # One pin already live: progress counts only the missing one, and does
    # not take the old full-restore prompt path.
    progress_live=()
    progress_live[alpha]=1
    print -r -- $'name alpha\ncwd /tmp/alpha\n\nname beta\ncwd /tmp/beta\n' \
      >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    : >"$tmux_log"
    progress_out=$(
      picker_boot_before_first_draw
      print -r -- $'\n---AFTER---'
      picker_boot_after_first_draw
      print -r -- $'\n---DID---'
      print -r -- "$did_restore"
    )
    progress_before=${progress_out%%$'\n---AFTER---'*}
    progress_after=${progress_out#*$'\n---AFTER---'}
    progress_after=${progress_after%%$'\n---DID---'*}
    if [[ $progress_before != *'0/1'* || $progress_before == *'0/2'* ]]; then
      print -u2 "FAIL progress/partial-count got=$(printf %q "$progress_before")"
      (( fails++ ))
    fi
    restore_log=$(<"$tmux_log")
    if [[ $progress_after != *'已恢复 1 个'* || $progress_after == *'失败'* ]]; then
      print -u2 "FAIL progress/partial-notice got=$(printf %q "$progress_after")"
      (( fails++ ))
    fi
    if [[ $restore_log == *'new-session -d -s alpha'* || $restore_log != *'new-session -d -s beta -c /tmp/beta'* ]]; then
      print -u2 "FAIL progress/partial-create got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    if [[ ${progress_out##*$'\n---DID---'} != *0* ]]; then
      print -u2 "FAIL progress/partial-prompt got=$(printf %q "${progress_out##*$'\n---DID---'}")"
      (( fails++ ))
    fi

    # CLI / direct restore stays silent.
    restore_show_progress=0
    restore_progress_on=0
    progress_live=()
    progress_out=$(restore_pinned_sessions 2>&1)
    if [[ $progress_out == *'正在恢复常驻 session'* ]]; then
      print -u2 "FAIL progress/silent-cli got=$(printf %q "$progress_out")"
      (( fails++ ))
    fi

    # WINCH during progress redraws the progress screen, not the list.
    local _pw_list _pw_prog
    _pw_list=0
    _pw_prog=0
    functions -c draw _progress_save_draw
    functions -c draw_restore_progress _progress_save_progress
    draw() { (( ++_pw_list )) }
    draw_restore_progress() { (( ++_pw_prog )) }
    list_active=1
    loading=0
    restore_progress_on=1
    draw_on_winch
    if (( _pw_list || _pw_prog != 1 )); then
      print -u2 "FAIL progress/winch list=$_pw_list progress=$_pw_prog"
      (( fails++ ))
    fi
    functions -c _progress_save_draw draw
    functions -c _progress_save_progress draw_restore_progress
    unset -f _progress_save_draw _progress_save_progress
    restore_progress_on=0
    list_active=0
    restore_tty >/dev/null 2>&1 || true
  }

  HOME=$oldhome
  rm -rf "$testhome"
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  if session_name_invalid ''; then
    print -u2 "FAIL name/empty auto-name rejected"
    (( fails++ ))
  fi
  if session_name_invalid 'my app'; then
    print -u2 "FAIL name/space my app rejected"
    (( fails++ ))
  fi
  if got=$(session_name_invalid web:api); then
    expect name/colon-msg "名称不能包含冒号或点。" "$got"
  else
    print -u2 "FAIL name/colon web:api accepted"
    (( fails++ ))
  fi
  if got=$(session_name_invalid web.api); then
    expect name/dot-msg "名称不能包含冒号或点。" "$got"
  else
    print -u2 "FAIL name/dot web.api accepted"
    (( fails++ ))
  fi

  if got=$(new_session_flag_invalid web.api); then
    expect name/cli-dot "名称不能包含冒号或点。" "$got"
  else
    print -u2 "FAIL name/cli-dot web.api accepted"
    (( fails++ ))
  fi
  if got=$(new_session_flag_invalid web:api); then
    expect name/cli-colon "名称不能包含冒号或点。" "$got"
  else
    print -u2 "FAIL name/cli-colon web:api accepted"
    (( fails++ ))
  fi
  if got=$(new_session_flag_invalid ''); then
    expect name/cli-empty "用法：lanjump go <session>" "$got"
  else
    print -u2 "FAIL name/cli-empty accepted"
    (( fails++ ))
  fi
  if new_session_flag_invalid web-api; then
    print -u2 "FAIL name/cli-ok web-api rejected"
    (( fails++ ))
  fi
  local pick_bin st
  pick_bin=${${(%):-%x}:A:h}/lanjump-pick.zsh
  st=0
  err=$(/bin/zsh "$pick_bin" --new-session 'web.api' 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL name/cli-flag-dot-exit got 0 want nonzero"
    (( fails++ ))
  fi
  expect name/cli-flag-dot "名称不能包含冒号或点。" "$err"
  st=0
  err=$(/bin/zsh "$pick_bin" --new-session 'web:api' 2>&1) || st=$?
  if (( st == 0 )); then
    print -u2 "FAIL name/cli-flag-colon-exit got 0 want nonzero"
    (( fails++ ))
  fi
  expect name/cli-flag-colon "名称不能包含冒号或点。" "$err"

  # #479: --new-auto names, dedups, and chooses cwd on this machine.
  if (( ! ${+functions[new_auto_session]} )); then
    print -u2 "FAIL new-auto/missing new_auto_session"
    (( fails++ ))
  else
    oldhome=$HOME
    auto_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-auto.XXXXXX")
    HOME=$auto_home
    mkdir -p "$HOME/Documents/projects/lanjump-2" "$HOME/Library/Application Support/lanjump"
    auto_log=$auto_home/tmux.log
    : >"$auto_log"
    HAS_TMUX=1
    typeset -A auto_live
    auto_live=()
    tmux_state_invalidate
    _auto_have_tmuxx=0
    if (( ${+functions[tmuxx]} )); then
      functions -c tmuxx _auto_save_tmuxx
      _auto_have_tmuxx=1
    fi
    tmuxx() {
      print -r -- "$*" >>"$auto_log"
      case $1 in
        list-sessions) return 1 ;;
        has-session)
          local n=${@[-1]#=}
          (( ${auto_live[$n]:-0} ))
          ;;
        *) return 0 ;;
      esac
    }
    st=0
    err=$(new_auto_session 'web.api' '/tmp/lj-explicit' 2>&1) || st=$?
    if (( st == 0 )); then
      print -u2 "FAIL new-auto/dot status got 0"
      (( fails++ ))
    fi
    expect new-auto/dot "名称不能包含冒号或点。" "$err"
    : >"$auto_log"
    got=$(new_auto_session lanjump /tmp/lj-explicit) || got=
    expect new-auto/name lanjump "$got"
    restore_log=$(<"$auto_log")
    if [[ $restore_log != *'new-session -d -s lanjump -c /tmp/lj-explicit'* ]]; then
      print -u2 "FAIL new-auto/cwd missing explicit dir got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    if [[ $restore_log == *'Documents/projects'* ]]; then
      print -u2 "FAIL new-auto/cwd used project dir got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    auto_live[lanjump]=1
    auto_live[lanjump-2]=1
    tmux_state_invalidate
    : >"$auto_log"
    got=$(new_auto_session lanjump /tmp/lj-explicit) || got=
    expect new-auto/dedup lanjump-3 "$got"
    restore_log=$(<"$auto_log")
    if [[ $restore_log != *'new-session -d -s lanjump-3 -c /tmp/lj-explicit'* ]]; then
      print -u2 "FAIL new-auto/dedup-cwd got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    auto_live=()
    auto_live[demo]=1
    tmux_state_invalidate
    mkdir -p "$HOME/Documents/projects/demo-2"
    : >"$auto_log"
    got=$(new_auto_session demo) || got=
    expect new-auto/remote-name demo-2 "$got"
    restore_log=$(<"$auto_log")
    if [[ $restore_log != *"-c $HOME/Documents/projects/demo-2"* ]]; then
      print -u2 "FAIL new-auto/remote-cwd got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    if [[ $restore_log == *'/tmp/lj-explicit'* ]]; then
      print -u2 "FAIL new-auto/remote used local cwd got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    HOME=$oldhome
    if (( _auto_have_tmuxx )); then
      functions -c _auto_save_tmuxx tmuxx
      unfunction _auto_save_tmuxx
    fi
    unset auto_live
    rm -rf "$auto_home"
  fi

  # #103: picker n named-create must use project dir as tmux -c.
  if [[ ${functions[prompt_new]} != *resolve_session_cwd* && ${functions[prompt_new]} != *create_named_session* ]]; then
    print -u2 "FAIL prompt_new/named-cwd missing resolve_session_cwd got=$(printf %q "${functions[prompt_new]}")"
    (( fails++ ))
  fi
  if [[ ${functions[prompt_new]} != *'new-session -d -P'* ]]; then
    print -u2 "FAIL prompt_new/empty-auto missing new-session -d -P got=$(printf %q "${functions[prompt_new]}")"
    (( fails++ ))
  fi
  # #130: n + pin must not store picker $PWD.
  if [[ ${functions[prompt_new]} == *add_pin_record*'"$PWD"'* ]]; then
    print -u2 "FAIL prompt_new/pin-cwd still pins \$PWD"
    (( fails++ ))
  fi
  if [[ ${functions[prompt_new]} == *'常驻（y=是'* ]]; then
    print -u2 "FAIL prompt_new still asks 常驻 on create got=$(printf %q "${functions[prompt_new]}")"
    (( fails++ ))
  fi
  if [[ ${functions[prompt_new]} != *'新窗口？'* ]]; then
    print -u2 "FAIL prompt_new missing 新窗口 prompt got=$(printf %q "${functions[prompt_new]}")"
    (( fails++ ))
  fi

  oldhome=$HOME
  testhome=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-prompt-new.XXXXXX")
  HOME=$testhome
  mkdir -p "$HOME/Library/Application Support/lanjump" "$HOME/Documents/projects/inferme"
  tmux_log=$testhome/tmux.log
  : >"$tmux_log"
  HAS_TMUX=1
  snap_cwd=()
  pinned_cwd=()
  pinned_names=()
  snap_names=()
  load_settings
  expect prompt_new/settings-root "$HOME/Documents/projects" "${project_roots[*]}"
  expect prompt_new/resolve-project "$HOME/Documents/projects/inferme" "$(resolve_session_cwd inferme)"
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 1 ;;
      new-session)
        [[ $* == *-P* ]] && print -r -- 0
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  if (( ! ${+functions[prompt_new_pin_cwd]} )); then
    print -u2 "FAIL prompt_new/helper missing prompt_new_pin_cwd"
    (( fails++ ))
  else
    expect prompt_new/pin-cwd-named "$HOME/Documents/projects/inferme" "$(prompt_new_pin_cwd inferme)"
  fi
  if (( ! ${+functions[ensure_pinnable_session_name]} )); then
    print -u2 "FAIL pin/helper missing ensure_pinnable_session_name"
    (( fails++ ))
  fi
  if (( ! ${+functions[unique_non_numeric_session_name]} )); then
    print -u2 "FAIL pin/helper missing unique_non_numeric_session_name"
    (( fails++ ))
  fi
  if (( ! ${+functions[create_named_session]} )); then
    print -u2 "FAIL prompt_new/helper missing create_named_session"
    (( fails++ ))
  else
    create_named_session inferme
    restore_log=$(<"$tmux_log")
    if [[ $restore_log != *'new-session -d -s inferme -c '"$HOME/Documents/projects/inferme"* ]]; then
      print -u2 "FAIL prompt_new/named-project-cwd got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
  fi

  functions -c restore_tty _pn_restore_tty
  functions -c setup_tty _pn_setup_tty
  functions -c draw _pn_draw
  functions -c load_items _pn_load_items
  functions -c tmux_prepare_color _pn_tmux_prepare_color
  functions -c tmux_prepare_keys _pn_tmux_prepare_keys
  functions -c attach_named_session _pn_attach_named_session
  functions -c mark_snapshot_occupied _pn_mark_snapshot_occupied
  restore_tty() { : }
  setup_tty() { : }
  draw() { : }
  load_items() { : }
  tmux_prepare_color() { : }
  tmux_prepare_keys() { : }
  attach_named_session() { : }
  mark_snapshot_occupied() { : }
  : >"$tmux_log"
  print -l -- inferme '' | prompt_new >/dev/null
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s inferme -c '"$HOME/Documents/projects/inferme"* ]]; then
    print -u2 "FAIL prompt_new/n-named-project-cwd got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$tmux_log"
  print -l -- '' '' | prompt_new >/dev/null
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -P'* ]]; then
    print -u2 "FAIL prompt_new/n-empty-auto missing -P got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *' -c '* ]]; then
    print -u2 "FAIL prompt_new/n-empty-auto used -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *rename-session* ]]; then
    print -u2 "FAIL prompt_new/n-empty-auto renamed unpinned got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if (( ${#pinned_names} )); then
    print -u2 "FAIL prompt_new/n-empty-auto pinned unpinned got=${pinned_names[*]}"
    (( fails++ ))
  fi

  # Create does not pin; 常驻 is list p only.
  pinned_names=()
  pinned_cwd=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  oldpwd=$PWD
  cd "$testhome"
  : >"$tmux_log"
  print -l -- inferme '' | prompt_new >/dev/null
  load_pinned_sessions
  if (( ${#pinned_names} )); then
    print -u2 "FAIL prompt_new/n-no-pin still pinned got=${pinned_names[*]}"
    (( fails++ ))
  fi

  # #136: after the name, n asks 新窗口？ Enter=current, t=new. No 常驻. t on 新建 skips the question.
  attach_log=$testhome/attach.log
  attach_named_session() {
    print -r -- "$*" >>"$attach_log"
  }
  : >"$attach_log"
  : >"$tmux_log"
  out=$(print -l -- inferme '' | prompt_new)
  if [[ $out == *常驻* ]]; then
    print -u2 "FAIL prompt_new/n-open still asks 常驻 got=$(printf %q "$out")"
    (( fails++ ))
  fi
  if [[ $out != *新窗口？* ]]; then
    print -u2 "FAIL prompt_new/n-open missing 新窗口 prompt got=$(printf %q "$out")"
    (( fails++ ))
  fi
  attach_got=$(<"$attach_log")
  if [[ $attach_got != *'inferme 0 0'* ]]; then
    print -u2 "FAIL prompt_new/n-enter-current want_new got=$(printf %q "$attach_got") want=*inferme 0 0*"
    (( fails++ ))
  fi
  : >"$attach_log"
  : >"$tmux_log"
  print -l -- inferme t | prompt_new >/dev/null
  attach_got=$(<"$attach_log")
  if [[ $attach_got != *'inferme 0 1'* ]]; then
    print -u2 "FAIL prompt_new/n-t-new-window want_new got=$(printf %q "$attach_got") want=*inferme 0 1*"
    (( fails++ ))
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s inferme'* ]]; then
    print -u2 "FAIL prompt_new/n-t-new-window missing create got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$attach_log"
  : >"$tmux_log"
  print -l -- inferme q | prompt_new >/dev/null
  attach_got=$(<"$attach_log")
  restore_log=$(<"$tmux_log")
  if [[ -n $attach_got ]]; then
    print -u2 "FAIL prompt_new/n-q still attached got=$(printf %q "$attach_got")"
    (( fails++ ))
  fi
  if [[ $restore_log == *new-session* ]]; then
    print -u2 "FAIL prompt_new/n-q still created got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$attach_log"
  print -l -- inferme | prompt_new 1 >/dev/null
  attach_got=$(<"$attach_log")
  if [[ $attach_got != *'inferme 0 1'* ]]; then
    print -u2 "FAIL prompt_new/t-on-new-row want_new got=$(printf %q "$attach_got") want=*inferme 0 1*"
    (( fails++ ))
  fi

  # #208: n + existing name + pin y + cancel must not pin or rename.
  # q here is the post-pin cancel (新窗口 / resume-grok).
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session)
        [[ $* == *'=7'* ]] && return 0
        return 1
        ;;
      display-message)
        if [[ $* == *pane_current_path* ]]; then
          print -r -- /tmp/seven
        else
          print -r -- zsh
        fi
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$attach_log"
  : >"$tmux_log"
  snap_names=(7)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[7]=/tmp/seven
  snap_occupied[7]=0
  snap_workspace[7]=0
  snap_cmd[7]=grok-1.0.24-mac
  snap_attached[7]=0
  save_session_snapshot
  out=$(print -l -- 7 y q | prompt_new)
  load_pinned_sessions
  attach_got=$(<"$attach_log")
  restore_log=$(<"$tmux_log")
  if [[ $out != *常驻* ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-q missing pin prompt got=$(printf %q "$out")"
    (( fails++ ))
  fi
  if [[ -n $attach_got ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-q still attached got=$(printf %q "$attach_got")"
    (( fails++ ))
  fi
  if (( ${#pinned_names} )); then
    print -u2 "FAIL prompt_new/n-existing-pin-q still pinned got=${pinned_names[*]}"
    (( fails++ ))
  fi
  if [[ $restore_log == *rename-session* ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-q still renamed got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # Enter after pin y is what writes the pin; numeric 7 is renamed then.
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$attach_log"
  : >"$tmux_log"
  print -l -- 7 y '' | prompt_new >/dev/null
  load_pinned_sessions
  attach_got=$(<"$attach_log")
  restore_log=$(<"$tmux_log")
  created=${pinned_names[1]:-}
  if [[ -z $created ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-enter missing pin record"
    (( fails++ ))
  fi
  if [[ -n $created ]] && numeric_session_name "$created"; then
    print -u2 "FAIL prompt_new/n-existing-pin-enter still numeric got=$(printf %q "$created")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'rename-session -t =7 '* ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-enter missing rename got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ -n $created && $attach_got != *"$created 1 0"* ]]; then
    print -u2 "FAIL prompt_new/n-existing-pin-enter attach got=$(printf %q "$attach_got") want=*$created 1 0*"
    (( fails++ ))
  fi
  drop_snap_record 7
  [[ -n $created ]] && drop_snap_record "$created"
  save_session_snapshot

  attach_named_session() { : }

  # #145: list p on numeric 0 renames then pins.
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 1 ;;
      display-message)
        print -r -- /tmp/zero-pane
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$tmux_log"
  items_kind=(session)
  items_id=(0)
  items_name=(0)
  items_pinned=(0)
  all_id=(0)
  all_name=(0)
  all_pinned=(0)
  cursor=1
  HAS_TMUX=1
  toggle_session_pin
  load_pinned_sessions
  created=${pinned_names[1]:-}
  if [[ -z $created ]]; then
    print -u2 "FAIL pin/p-numeric missing pin record"
    (( fails++ ))
  fi
  if numeric_session_name "$created"; then
    print -u2 "FAIL pin/p-numeric still numeric got=$(printf %q "$created")"
    (( fails++ ))
  fi
  if [[ $created == *:* || $created == *.* || $created == *' '* ]]; then
    print -u2 "FAIL pin/p-numeric invalid name got=$(printf %q "$created")"
    (( fails++ ))
  fi
  expect pin/p-numeric-id "$created" "${items_id[1]}"
  expect pin/p-numeric-name "$created" "${items_name[1]}"
  expect pin/p-numeric-pinned 1 "${items_pinned[1]}"
  expect pin/p-numeric-cwd /tmp/zero-pane "${pinned_cwd[$created]:-}"
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'rename-session -t =0 '* ]]; then
    print -u2 "FAIL pin/p-numeric-rename got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_pinned_sessions
  restore_log=$(<"$tmux_log")
  if [[ -n $created && $restore_log != *'new-session -d -s '"$created"' -c /tmp/zero-pane'* ]]; then
    print -u2 "FAIL pin/p-numeric-restore got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # Named pin still uses the given name.
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$tmux_log"
  items_kind=(session)
  items_id=(keep)
  items_name=(keep)
  items_pinned=(0)
  all_id=(keep)
  all_name=(keep)
  all_pinned=(0)
  cursor=1
  toggle_session_pin
  load_pinned_sessions
  expect pin/p-named keep "${pinned_names[1]:-}"
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *rename-session* ]]; then
    print -u2 "FAIL pin/p-named renamed non-numeric got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #177: p on a live bmx session must not add a pin.
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$tmux_log"
  items_kind=(session)
  items_id=(bmx-demo)
  items_name=(bmx-demo)
  items_pinned=(0)
  all_id=(bmx-demo)
  all_name=(bmx-demo)
  all_pinned=(0)
  cursor=1
  HAS_TMUX=1
  toggle_session_pin
  load_pinned_sessions
  if [[ ${pinned_names[(Ie)bmx-demo]} -ne 0 ]]; then
    print -u2 "FAIL pin/p-foreign added pin got=${pinned_names[*]}"
    (( fails++ ))
  fi
  expect pin/p-foreign-pinned 0 "${items_pinned[1]}"
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'@lanjump_pinned 1'* ]]; then
    print -u2 "FAIL pin/p-foreign marked tmux pinned got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #149: CLI --pin-session on numeric 0 renames then pins, prints the new name.
  pin_flag_src=$(awk '
    /\[\[ \$\{1:-\} == --pin-session \]\]/ {p=1}
    p {print}
    p && /^fi$/ {exit}
  ' "$_pick_src_file")
  if [[ $pin_flag_src != *pin_named_session* && $pin_flag_src != *ensure_pinnable_session_name* ]]; then
    print -u2 "FAIL pin/cli-flag missing ensure_pinnable_session_name"
    (( fails++ ))
  fi
  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 1 ;;
      display-message)
        print -r -- /tmp/cli-zero-pane
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$tmux_log"
  if (( ! ${+functions[pin_named_session]} )); then
    print -u2 "FAIL pin/cli-numeric missing pin_named_session"
    (( fails++ ))
  else
    out=$(pin_named_session 0)
    load_pinned_sessions
    created=${pinned_names[1]:-}
    if [[ -z $created ]]; then
      print -u2 "FAIL pin/cli-numeric missing pin record"
      (( fails++ ))
    fi
    if numeric_session_name "$created"; then
      print -u2 "FAIL pin/cli-numeric still numeric got=$(printf %q "$created")"
      (( fails++ ))
    fi
    if [[ $created == *:* || $created == *.* || $created == *' '* ]]; then
      print -u2 "FAIL pin/cli-numeric invalid name got=$(printf %q "$created")"
      (( fails++ ))
    fi
    expect pin/cli-numeric-stdout "$created" "$out"
    restore_log=$(<"$tmux_log")
    if [[ $restore_log != *'rename-session -t =0 '* ]]; then
      print -u2 "FAIL pin/cli-numeric-rename got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
    : >"$tmux_log"
    restore_pinned_sessions
    restore_log=$(<"$tmux_log")
    if [[ -n $created && $restore_log != *'new-session -d -s '"$created"* ]]; then
      print -u2 "FAIL pin/cli-numeric-restore got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
  fi

  # Named --pin-session still uses the given name and prints it.
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  : >"$tmux_log"
  if (( ${+functions[pin_named_session]} )); then
    out=$(pin_named_session keep)
    load_pinned_sessions
    expect pin/cli-named keep "${pinned_names[1]:-}"
    expect pin/cli-named-stdout keep "$out"
    restore_log=$(<"$tmux_log")
    if [[ $restore_log == *rename-session* ]]; then
      print -u2 "FAIL pin/cli-named renamed non-numeric got=$(printf %q "$restore_log")"
      (( fails++ ))
    fi
  fi
  cd "$oldpwd"
  functions -c _pn_restore_tty restore_tty
  functions -c _pn_setup_tty setup_tty
  functions -c _pn_draw draw
  functions -c _pn_load_items load_items
  functions -c _pn_tmux_prepare_color tmux_prepare_color
  functions -c _pn_tmux_prepare_keys tmux_prepare_keys
  functions -c _pn_attach_named_session attach_named_session
  functions -c _pn_mark_snapshot_occupied mark_snapshot_occupied
  unset -f _pn_restore_tty _pn_setup_tty _pn_draw _pn_load_items \
    _pn_tmux_prepare_color _pn_tmux_prepare_keys _pn_attach_named_session \
    _pn_mark_snapshot_occupied
  HOME=$oldhome
  rm -rf "$testhome"
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  # #41 / #64: CSI leftovers (PageDown/Home/End/Delete/CSI-u) must not be Esc/q.
  expect_key() {
    local label=$1 want=$2 seq=$3
    local leftover=""
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

  expect_key key/arrow-up up $'\e[A'
  expect_key key/arrow-down down $'\e[B'
  expect_key key/ss3-up up $'\eOA'
  expect_key key/pagedown other $'\e[6~'
  expect_key key/pageup other $'\e[5~'
  expect_key key/home other $'\e[H'
  expect_key key/end other $'\e[F'
  expect_key key/home-1 other $'\e[1~'
  expect_key key/end-4 other $'\e[4~'
  expect_key key/delete other $'\e[3~'
  expect_key key/csi-u-s-enter other $'\e[13;2u'
  # #114: lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR/LF).
  expect_key key/alt-enter-s-enter other $'\e\r'
  expect_key key/alt-enter-lf other $'\e\n'
  expect_key key/t t t
  expect_key key/T t T
  expect_key key/enter enter $'\r'
  expect_key key/q q q
  expect_key key/esc esc $'\e'

  local k1=EOF k2=EOF
  PENDING_KEY=""
  {
    read_key && k1=$REPLY
    read_key && k2=$REPLY
  } < <(print -n $'\e[6~\e[A')
  expect key/pagedown-then-up-1 other "$k1"
  expect key/pagedown-then-up-2 up "$k2"

  # #260: SGR mouse CSI must drain so leftover 0;10;20M is not num0.
  k1=EOF
  k2=EOF
  PENDING_KEY=""
  {
    read_key && k1=$REPLY
    read_key && k2=$REPLY
  } < <(print -n $'\e[<0;10;20Mq')
  expect key/sgr-mouse-then-q-1 other "$k1"
  expect key/sgr-mouse-then-q-2 q "$k2"

  local -a loop_keys
  local loop_quit=0 k
  loop_keys=()
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
  expect key/loop-quit 1 "$loop_quit"
  if (( ${#loop_keys} != 6 )); then
    print -u2 "FAIL key/loop-keys got=${loop_keys[*]} want=5 others then q"
    (( fails++ ))
  elif [[ ${loop_keys[-1]} != q ]]; then
    print -u2 "FAIL key/loop-last got=$(printf %q "${loop_keys[-1]}") want=q"
    (( fails++ ))
  fi
  for k in "${loop_keys[1,-2]}"; do
    if [[ $k == esc || $k == q ]]; then
      print -u2 "FAIL key/loop-csi treated as quit got=${loop_keys[*]}"
      (( fails++ ))
      break
    fi
  done

  # #114: ESC CR then q must not quit on the first key.
  loop_keys=()
  loop_quit=0
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
  } < <(print -n $'\e\rq')
  expect key/alt-enter-then-q-quit 1 "$loop_quit"
  if (( ${#loop_keys} != 2 )); then
    print -u2 "FAIL key/alt-enter-then-q-keys got=${loop_keys[*]} want=other then q"
    (( fails++ ))
  elif [[ ${loop_keys[-1]} != q ]]; then
    print -u2 "FAIL key/alt-enter-then-q-last got=$(printf %q "${loop_keys[-1]}") want=q"
    (( fails++ ))
  fi
  if (( ${#loop_keys} >= 1 )) && [[ ${loop_keys[1]} == esc || ${loop_keys[1]} == q ]]; then
    print -u2 "FAIL key/alt-enter-then-q treated as quit got=${loop_keys[*]}"
    (( fails++ ))
  fi

  restore_csi_key A
  expect restore/csi-up up "$REPLY"
  restore_csi_key B
  expect restore/csi-down down "$REPLY"
  restore_csi_key C
  expect restore/csi-right other "$REPLY"
  restore_csi_key D
  expect restore/csi-left other "$REPLY"
  restore_csi_key 6
  expect restore/csi-pgdn other "$REPLY"
  if [[ ${functions[restore_read_key]} != *restore_csi_key* ]]; then
    print -u2 "FAIL restore/read-key missing restore_csi_key got=$(printf %q "${functions[restore_read_key]}")"
    (( fails++ ))
  fi
  if [[ ${functions[restore_read_key]} != *"\$'\\r'"* || ${functions[restore_read_key]} != *"\$'\\n'"* ]]; then
    print -u2 "FAIL restore/read-key missing ESC CR/LF other got=$(printf %q "${functions[restore_read_key]}")"
    (( fails++ ))
  fi

  # #147: tmux application cursor keys send SS3 (ESC O A/B), not CSI.
  # Those must move, not abort the restore overlay like Esc/q.
  expect_restore_key() {
    local label=$1 want=$2 seq=$3
    local leftover=""
    {
      if restore_read_key; then
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
  expect_restore_key restore/read-csi-up up $'\e[A'
  expect_restore_key restore/read-csi-down down $'\e[B'
  expect_restore_key restore/read-ss3-up up $'\eOA'
  expect_restore_key restore/read-ss3-down down $'\eOB'
  expect_restore_key restore/read-ss3-right other $'\eOC'
  expect_restore_key restore/read-ss3-left other $'\eOD'
  expect_restore_key restore/read-esc esc $'\e'
  expect_restore_key restore/read-q q q
  k1=EOF
  k2=EOF
  {
    restore_read_key && k1=$REPLY
    restore_read_key && k2=$REPLY
  } < <(print -n $'\eOA\eOB')
  expect restore/read-ss3-up-then-down-1 up "$k1"
  expect restore/read-ss3-up-then-down-2 down "$k2"

  # #228: restore ESC [ < mouse drain must time out like sibling CSI branches.
  # Incomplete SGR (no M/m) is other. A blocking `while read_byte` eats later keys.
  {
    local c buf=
    while read_byte 0.2; do
      c=$REPLY
      buf+=$c
      [[ $c == M || $c == m ]] && break
    done
    if [[ $buf == 0\;[0-9]##\;[0-9]##M ]]; then
      got=click
    else
      got=other
    fi
  } < <(print -n -- '0;12;4')
  expect restore/mouse-seq-timeout-other other "$got"
  # zsh pretty-prints `while read_byte; do` as `while read_byte` then `do`.
  if [[ ${functions[restore_read_key]} == *$'\twhile read_byte\n'* ]]; then
    print -u2 "FAIL restore/mouse-seq-timeout blocking until M/m"
    (( fails++ ))
  fi

  # #40: restore checkbox list must match host/session lists (j up, k down).
  restore_plain_key j
  expect restore/j-up up "$REPLY"
  restore_plain_key J
  expect restore/J-up up "$REPLY"
  restore_plain_key k
  expect restore/k-down down "$REPLY"
  restore_plain_key K
  expect restore/K-down down "$REPLY"
  restore_plain_key t
  expect restore/t t "$REPLY"
  restore_plain_key T
  expect restore/T t "$REPLY"
  restore_plain_key $'\r'
  expect restore/cr-enter enter "$REPLY"
  restore_plain_key $'\n'
  expect restore/lf-enter enter "$REPLY"
  if [[ ${functions[restore_read_key]} != *restore_plain_key* ]]; then
    print -u2 "FAIL restore/read-key missing restore_plain_key got=$(printf %q "${functions[restore_read_key]}")"
    (( fails++ ))
  fi
  if [[ ${functions[restore_plain_key]} == *S-Enter* || ${functions[read_key]} == *S-Enter* ]]; then
    print -u2 "FAIL key/s-enter-not-new-window Shift+Enter must stay Grok newline"
    (( fails++ ))
  fi
  if [[ ${functions[tmux_prepare_keys]} != *'bind-key -n S-Enter send-keys Escape Enter'* ]]; then
    print -u2 "FAIL key/tmux-s-enter missing Escape Enter bind got=$(printf %q "${functions[tmux_prepare_keys]}")"
    (( fails++ ))
  fi

  # #227: closed stdin must not spin. The product loop is `read_key || continue`
  # with no exit; a helper must restore_tty and exit 1 after consecutive EOF.
  # Cap at 40 so a missing/broken path cannot hang the suite.
  if ! (( ${+functions[read_key_or_exit]} )); then
    print -u2 "FAIL key/eof-spin missing read_key_or_exit"
    (( fails++ ))
  else
    local eof_st=0
    PENDING_KEY=""
    (
      restore_tty() { : }
      typeset -i _read_key_fails=0
      local -i n=0
      while true; do
        (( ++n > 40 )) && exit 99
        read_key_or_exit || continue
      done
    ) </dev/null
    eof_st=$?
    if (( eof_st != 1 )); then
      print -u2 "FAIL key/eof-spin exit got=$eof_st want=1 (99=spun)"
      (( fails++ ))
    fi
  fi
  if grep -E -q '^[[:space:]]*read_key \|\| continue' "$_pick_src_file"; then
    print -u2 "FAIL key/eof-spin pick loop still continues forever on read fail"
    (( fails++ ))
  fi

  # #270: restore window list (and settings input) have the same
  # `|| continue` gap. Closed stdin must restore_tty and exit, not spin.
  if ! (( ${+functions[restore_read_key_or_exit]} )); then
    print -u2 "FAIL restore/eof-spin missing restore_read_key_or_exit"
    (( fails++ ))
  else
    local eof_st=0
    PENDING_KEY=""
    (
      restore_tty() { : }
      typeset -i _read_key_fails=0
      local -i n=0
      while true; do
        (( ++n > 40 )) && exit 99
        restore_read_key_or_exit || continue
      done
    ) </dev/null
    eof_st=$?
    if (( eof_st != 1 )); then
      print -u2 "FAIL restore/eof-spin exit got=$eof_st want=1 (99=spun)"
      (( fails++ ))
    fi
  fi
  if grep -E -q '^[[:space:]]*restore_read_key \|\| continue' "$_pick_src_file"; then
    print -u2 "FAIL restore/eof-spin restore loop still continues forever on read fail"
    (( fails++ ))
  fi
  if ! (( ${+functions[settings_input_read_or_exit]} )); then
    print -u2 "FAIL settings/eof-spin missing settings_input_read_or_exit"
    (( fails++ ))
  else
    local eof_st=0
    PENDING_KEY=""
    (
      restore_tty() { : }
      typeset -i _read_key_fails=0
      local -i n=0
      while true; do
        (( ++n > 40 )) && exit 99
        settings_input_read_or_exit || continue
      done
    ) </dev/null
    eof_st=$?
    if (( eof_st != 1 )); then
      print -u2 "FAIL settings/eof-spin exit got=$eof_st want=1 (99=spun)"
      (( fails++ ))
    fi
  fi
  if grep -E -q '^[[:space:]]*settings_input_read \|\| continue' "$_pick_src_file"; then
    print -u2 "FAIL settings/eof-spin settings loop still continues forever on read fail"
    (( fails++ ))
  fi

  restore_pick_kind=(item item)
  restore_pick_name=(one two)
  restore_pick_checked=(1 0)
  restore_pick_finish enter
  expect restore/finish-enter-one attach "$restore_pick_action"
  expect restore/finish-enter-one-name one "${ghostty_names[*]}"
  restore_pick_finish t
  expect restore/finish-t-one resume "$restore_pick_action"
  restore_pick_checked=(1 1)
  restore_pick_finish enter
  expect restore/finish-enter-multi resume "$restore_pick_action"
  expect restore/finish-enter-multi-names 'one two' "${ghostty_names[*]}"
  restore_pick_finish t
  expect restore/finish-t-multi resume "$restore_pick_action"
  restore_pick_finish two
  expect restore/finish-two shell "$restore_pick_action"
  restore_pick_checked=(0 0)
  restore_pick_finish enter
  expect restore/finish-none skip "$restore_pick_action"
  restore_pick_finish t
  expect restore/finish-t-none skip "$restore_pick_action"

  if [[ ${functions[restore_tty]} != *1000l* || ${functions[restore_tty]} != *1006l* ]]; then
    print -u2 "FAIL restore/tty-mouse missing 1000l/1006l got=$(printf %q "${functions[restore_tty]}")"
    (( fails++ ))
  fi

  # #155: WINCH must not redraw the session list over a cooked prompt.
  # --pick-selftest skips the load-time WINCH trap; call the handler.
  if grep -F -q "|| draw' WINCH" "$_pick_src_file"; then
    print -u2 "FAIL pick-winch/source-trap WINCH still draws list"
    (( fails++ ))
  fi
  if ! (( ${+functions[draw_on_winch]} )); then
    print -u2 "FAIL pick-winch/draw_on_winch missing"
    (( fails++ ))
  else
    _pw_save_draw=$functions[draw]
    _pw_save_stty_orig=${stty_orig:-}
    _pw_winch_draws=0
    draw() { ((_pw_winch_draws++)) }
    stty() { : }
    loading=0
    restore_tty >/dev/null
    draw_on_winch
    if (( _pw_winch_draws )); then
      print -u2 "FAIL pick-winch/prompt draw called"
      (( fails++ ))
    fi
    if (( list_active )); then
      print -u2 "FAIL pick-winch/prompt list_active on"
      (( fails++ ))
    fi
    # #160: overlay ends restore_tty then setup_tty so the list WINCH works again.
    _pw_overlay=${functions[prompt_restore_windows]}
    if [[ ${_pw_overlay##*restore_tty} != *setup_tty* ]]; then
      print -u2 "FAIL pick-winch/overlay-end setup_tty missing after restore_tty"
      (( fails++ ))
    fi
    setup_tty >/dev/null
    if (( list_active != 1 )); then
      print -u2 "FAIL pick-winch/overlay-end list_active=$list_active"
      (( fails++ ))
    fi
    draw_on_winch
    if (( _pw_winch_draws != 1 )); then
      print -u2 "FAIL pick-winch/list skipped draw got=$_pw_winch_draws"
      (( fails++ ))
    fi
    _pw_winch_draws=0
    loading=1
    draw_on_winch
    if (( _pw_winch_draws )); then
      print -u2 "FAIL pick-winch/loading draw called"
      (( fails++ ))
    fi
    functions[draw]=$_pw_save_draw
    unset -f stty
    loading=0
    list_active=0
    stty_orig=$_pw_save_stty_orig
    unset _pw_save_draw _pw_save_stty_orig _pw_winch_draws _pw_overlay
  fi

  if [[ ${functions[attach_named_session]} == *resume_prompt_choice* || ${functions[attach_named_session]} == *enter_resume_prompt_text* ]]; then
    print -u2 "FAIL resume/attach still asks to resume grok got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi
  if [[ ${functions[maybe_resume_last_command]} != *select_live_grok_pane* ]]; then
    print -u2 "FAIL resume/jump missing select_live_grok_pane got=$(printf %q "${functions[maybe_resume_last_command]}")"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} == *'改在当前窗口进入'* ]]; then
    print -u2 "FAIL open/no-fallback-prompt attach_named_session still prompts"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *want_new* ]]; then
    print -u2 "FAIL open/attach-want-new missing want_new got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi

  # #70: picker --start-grok types grok into this machine's tmux.
  local grok_log
  grok_log=$(mktemp "${TMPDIR:-/tmp}/lanjump-grok.XXXXXX") || return 1
  HAS_TMUX=1
  LANJUMP_GROK_BIN=grok
  TEST_GROK_DIR=0
  TEST_PANE_CMD=zsh
  TEST_PANE_CWD=/tmp/typed-cwd
  TEST_PANE_LIST=
  cwd_has_grok_session() { (( TEST_GROK_DIR )); }
  tmuxx() {
    print -r -- "$*" >>"$grok_log"
    case $1 in
      display-message)
        if [[ $* == *pane_current_command* ]]; then
          print -r -- "$TEST_PANE_CMD"
        elif [[ $* == *pane_current_path* ]]; then
          print -r -- "$TEST_PANE_CWD"
        fi
        ;;
      list-panes)
        [[ -n ${TEST_PANE_LIST:-} ]] && print -r -- "$TEST_PANE_LIST"
        ;;
      send-keys|select-window|select-pane) return 0 ;;
      new-window)
        print -r -- '@9'
        return 0
        ;;
      *) return 0 ;;
    esac
  }

  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log != *'send-keys -t =demo:. -- grok Enter'* ]]; then
    print -u2 "FAIL grok/start-idle missing send-keys grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'grok -c'* ]]; then
    print -u2 "FAIL grok/start-idle used grok -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_GROK_DIR=1
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log != *'send-keys -t =demo:. -- grok -c Enter'* ]]; then
    print -u2 "FAIL grok/start-c missing grok -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  TEST_GROK_DIR=0

  TEST_PANE_CMD=grok
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-already sent keys into grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_CMD=grok-1.0.24-mac
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-grok-ver sent keys into grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_CMD=
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-unread sent keys into unread pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'-t =demo:.'* ]]; then
    print -u2 "FAIL grok/start-unread missing pane target got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  TEST_PANE_CMD=zsh

  # #82: another window already runs grok; jump there, do not start a second grok.
  TEST_PANE_LIST=$'%1\tzsh\n%2\tgrok'
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-other-window sent keys into idle shell got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'list-panes -s'* ]]; then
    print -u2 "FAIL grok/start-other-window missing session-wide list-panes got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL grok/start-other-window missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_LIST=$'%1\tzsh\n%2\tgrok-1.0.24-mac'
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-other-ver sent keys into idle shell got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL grok/start-other-ver missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_CMD=
  TEST_PANE_LIST=$'%1\t\n%2\tgrok'
  : >"$grok_log"
  start_grok_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok/start-unread-other sent keys got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'select-window -t %2'* ]]; then
    print -u2 "FAIL grok/start-unread-other missing select-window grok pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  TEST_PANE_CMD=zsh
  TEST_PANE_LIST=

  if pick_needs_tty --start-grok; then
    print -u2 "FAIL grok/start-no-tty --start-grok still needs tty"
    (( fails++ ))
  fi
  if pick_needs_tty --start-grok-new || pick_needs_tty --new-auto; then
    print -u2 "FAIL grok/new-auto-tty still needs tty"
    (( fails++ ))
  fi

  # #479: -G never uses grok -c and does not steal an existing grok pane.
  TEST_GROK_DIR=1
  TEST_PANE_CMD=zsh
  TEST_PANE_LIST=
  : >"$grok_log"
  start_grok_new_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log != *'send-keys -t =demo:. -- grok Enter'* ]]; then
    print -u2 "FAIL grok-new/idle missing fresh grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'grok -c'* || $restore_log == *'new-window'* ]]; then
    print -u2 "FAIL grok-new/idle used -c or new-window got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  TEST_GROK_DIR=0

  TEST_PANE_LIST=$'%1\tzsh\n%2\tgrok'
  TEST_PANE_CMD=zsh
  TEST_PANE_CWD=/tmp/typed-cwd
  : >"$grok_log"
  start_grok_new_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* || $restore_log == *'select-window -t %2'* ]]; then
    print -u2 "FAIL grok-new/existing disturbed grok got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-window -P -F #{window_id} -t =demo -c /tmp/typed-cwd grok'* ]]; then
    print -u2 "FAIL grok-new/existing missing new-window got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'grok -c'* ]]; then
    print -u2 "FAIL grok-new/existing used grok -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'select-window -t @9'* ]]; then
    print -u2 "FAIL grok-new/existing missing select got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_LIST=
  TEST_PANE_CMD=vim
  : >"$grok_log"
  start_grok_new_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log != *'new-window'* || $restore_log == *'send-keys'* ]]; then
    print -u2 "FAIL grok-new/busy missing new-window got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  TEST_PANE_CMD=grok
  : >"$grok_log"
  start_grok_new_session demo
  restore_log=$(<"$grok_log")
  if [[ $restore_log == *'send-keys'* || $restore_log != *'new-window'* ]]; then
    print -u2 "FAIL grok-new/current-grok disturbed pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  TEST_PANE_CMD=zsh
  TEST_PANE_LIST=
  rm -f "$grok_log"

  # #173: Apple Terminal color prep must not disable RGB for other clients.
  local color_dir color_log color_got
  local color_term_program=${TERM_PROGRAM-}
  local color_term_program_version=${TERM_PROGRAM_VERSION-}
  local color_term=${TERM-}
  local color_colorterm=${COLORTERM-}
  local -i color_prepared=$prepared_color color_has_tmux=$HAS_TMUX
  color_dir=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-color.XXXXXX") || return 1
  color_log=$color_dir/tmux.log
  HAS_TMUX=1
  tmuxx() {
    print -r -- "$*" >>"$color_log"
    case $1 in
      show-options)
        print -r -- tmux-256color
        return 0
        ;;
      *) return 0 ;;
    esac
  }

  : >"$color_log"
  prepared_color=0
  TERM_PROGRAM=Apple_Terminal
  TERM_PROGRAM_VERSION=440
  TERM=xterm-256color
  unset COLORTERM
  tmux_prepare_color
  color_got=$(<"$color_log")
  if [[ $color_got == *'*:RGB@'* ]]; then
    print -u2 "FAIL color/apple-no-star-rgb got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got == *'-g TERM_PROGRAM Apple_Terminal'* ]]; then
    print -u2 "FAIL color/apple-no-global-term-program got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got == *'-gu terminal-features'* ]]; then
    print -u2 "FAIL color/apple-no-unset-features got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  # #447: inner Grok must emit 256-color. 24-bit backgrounds are ignored
  # by Terminal.app, so the Basic (white) profile shows through.
  if [[ $color_got != *'-gu COLORTERM'* ]]; then
    print -u2 "FAIL color/apple-unset-colorterm missing -gu COLORTERM got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *tmux-256color:RGB@* ]]; then
    print -u2 "FAIL color/apple-inner-no-rgb missing tmux-256color:RGB@ got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *window-style*colour234* ]]; then
    print -u2 "FAIL color/apple-window-style missing colour234 got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *'-g LANJUMP_CLIENT Apple_Terminal'* ]]; then
    print -u2 "FAIL color/apple-client missing LANJUMP_CLIENT Apple_Terminal got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *xterm-256color:256* ]]; then
    print -u2 "FAIL color/apple-256-feature missing xterm-256color:256 got=$(printf %q "$color_got")"
    (( fails++ ))
  fi

  local shim_dir front_dir shim_bin saved_shim_dir saved_front_dir saved_grok_bin
  saved_shim_dir=${LANJUMP_GROK_SHIM_DIR-}
  saved_front_dir=${LANJUMP_GROK_FRONT_DIR-}
  saved_grok_bin=${LANJUMP_GROK_BIN-}
  shim_dir=$color_dir/shim
  front_dir=$color_dir/front
  mkdir -p "$shim_dir" "$front_dir"
  LANJUMP_GROK_SHIM_DIR=$shim_dir
  LANJUMP_GROK_FRONT_DIR=$front_dir
  LANJUMP_GROK_BIN=/usr/bin/true
  : >"$color_log"
  prepared_color=0
  TERM_PROGRAM=Apple_Terminal
  TERM=xterm-256color
  tmux_prepare_color
  shim_bin=$shim_dir/grok
  if [[ ! -x $shim_bin ]]; then
    print -u2 "FAIL color/apple-shim missing executable $shim_bin"
    (( fails++ ))
  elif ! grep -q lanjump-grok-colorterm-shim "$shim_bin"; then
    print -u2 "FAIL color/apple-shim missing marker got=$(printf %q "$(<$shim_bin)")"
    (( fails++ ))
  elif ! grep -q 'env -u COLORTERM' "$shim_bin"; then
    print -u2 "FAIL color/apple-shim missing COLORTERM strip got=$(printf %q "$(<$shim_bin)")"
    (( fails++ ))
  fi
  if [[ ! -x $front_dir/grok ]] || ! grep -q lanjump-grok-colorterm-shim "$front_dir/grok"; then
    print -u2 "FAIL color/apple-front-shim missing ~/.grok/bin shim"
    (( fails++ ))
  fi
  if [[ -n $saved_shim_dir ]]; then
    LANJUMP_GROK_SHIM_DIR=$saved_shim_dir
  else
    unset LANJUMP_GROK_SHIM_DIR
  fi
  if [[ -n $saved_front_dir ]]; then
    LANJUMP_GROK_FRONT_DIR=$saved_front_dir
  else
    unset LANJUMP_GROK_FRONT_DIR
  fi
  if [[ -n $saved_grok_bin ]]; then
    LANJUMP_GROK_BIN=$saved_grok_bin
  else
    unset LANJUMP_GROK_BIN
  fi

  : >"$color_log"
  prepared_color=0
  TERM_PROGRAM=ghostty
  TERM=xterm-ghostty
  COLORTERM=truecolor
  tmux_prepare_color
  color_got=$(<"$color_log")
  if [[ $color_got != *xterm-ghostty:RGB* ]]; then
    print -u2 "FAIL color/ghostty-rgb missing xterm-ghostty:RGB got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *xterm-ghostty:Tc* ]]; then
    print -u2 "FAIL color/ghostty-tc missing xterm-ghostty:Tc got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got == *'*:RGB'* ]]; then
    print -u2 "FAIL color/ghostty-no-star-rgb got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *'-g LANJUMP_CLIENT ghostty'* ]]; then
    print -u2 "FAIL color/ghostty-client missing LANJUMP_CLIENT ghostty got=$(printf %q "$color_got")"
    (( fails++ ))
  fi

  if [[ ${functions[tmux_prepare_color]} == *'*:RGB@'* ]]; then
    print -u2 "FAIL color/src-no-star-rgb tmux_prepare_color still has *:RGB@"
    (( fails++ ))
  fi

  # #445: unset wrap's client appearance lets OSC 11 read Ghostty's
  # macOS-following canvas, so theme=auto becomes GrokDay (灰白) or a
  # washed GrokNight (灰黑). Pin host appearance in process + tmux env.
  local color_app_saved=${LANJUMP_GROK_APPEARANCE-}
  local color_lc_saved=${LC_GROK_APPEARANCE-}
  local color_g_saved=${GROK_APPEARANCE-}

  if ! (( ${+functions[host_grok_appearance]} )); then
    print -u2 "FAIL color/host-appearance missing host_grok_appearance"
    (( fails++ ))
  else
    LANJUMP_GROK_APPEARANCE=dark
    expect color/host-appearance-dark dark "$(host_grok_appearance)"
    LANJUMP_GROK_APPEARANCE=light
    expect color/host-appearance-light light "$(host_grok_appearance)"
  fi
  if ! (( ${+functions[host_grok_appearance_osc]} )); then
    print -u2 "FAIL color/host-osc missing host_grok_appearance_osc"
    (( fails++ ))
  else
    local osc
    LANJUMP_GROK_APPEARANCE=dark
    osc=$(host_grok_appearance_osc)
    if [[ $osc != *$'\e]11;#1a1a1a\a'* ]]; then
      print -u2 "FAIL color/host-osc-dark missing OSC 11 dark bg got=$(printf %q "$osc")"
      (( fails++ ))
    fi
    LANJUMP_GROK_APPEARANCE=light
    osc=$(host_grok_appearance_osc)
    if [[ $osc != *$'\e]11;#f4f4f4\a'* ]]; then
      print -u2 "FAIL color/host-osc-light missing OSC 11 light bg got=$(printf %q "$osc")"
      (( fails++ ))
    fi
  fi

  : >"$color_log"
  prepared_color=0
  LANJUMP_GROK_APPEARANCE=dark
  unset LC_GROK_APPEARANCE GROK_APPEARANCE
  tmux_prepare_color
  color_got=$(<"$color_log")
  if [[ $color_got == *'-gu LC_GROK_APPEARANCE'* || $color_got == *'-gu GROK_APPEARANCE'* ]]; then
    print -u2 "FAIL color/appearance-no-unset got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *'-g LC_GROK_APPEARANCE dark'* ]]; then
    print -u2 "FAIL color/appearance-global missing -g LC_GROK_APPEARANCE dark got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  if [[ $color_got != *'set-environment LC_GROK_APPEARANCE dark'* ]]; then
    print -u2 "FAIL color/appearance-session missing session LC_GROK_APPEARANCE dark got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  expect color/appearance-export-lc dark "${LC_GROK_APPEARANCE:-}"
  expect color/appearance-export-g dark "${GROK_APPEARANCE:-}"

  : >"$color_log"
  prepared_color=0
  LANJUMP_GROK_APPEARANCE=light
  LC_GROK_APPEARANCE=dark
  GROK_APPEARANCE=dark
  tmux_prepare_color
  color_got=$(<"$color_log")
  if [[ $color_got != *'-g LC_GROK_APPEARANCE light'* ]]; then
    print -u2 "FAIL color/appearance-overwrite missing -g LC_GROK_APPEARANCE light got=$(printf %q "$color_got")"
    (( fails++ ))
  fi
  expect color/appearance-overwrite-export light "${LC_GROK_APPEARANCE:-}"

  if [[ ${functions[setup_tty]} != *emit_host_grok_appearance_osc* ]]; then
    print -u2 "FAIL color/setup-tty-osc setup_tty does not emit host appearance OSC"
    (( fails++ ))
  fi
  if [[ ${functions[on_exit]} != *reset_host_grok_appearance_osc* ]]; then
    print -u2 "FAIL color/on-exit-osc on_exit does not reset host appearance OSC"
    (( fails++ ))
  fi

  if [[ -n $color_app_saved ]]; then
    LANJUMP_GROK_APPEARANCE=$color_app_saved
  else
    unset LANJUMP_GROK_APPEARANCE
  fi
  if [[ -n $color_lc_saved ]]; then
    LC_GROK_APPEARANCE=$color_lc_saved
  else
    unset LC_GROK_APPEARANCE
  fi
  if [[ -n $color_g_saved ]]; then
    GROK_APPEARANCE=$color_g_saved
  else
    unset GROK_APPEARANCE
  fi

  if [[ -n $color_term_program ]]; then
    TERM_PROGRAM=$color_term_program
  else
    unset TERM_PROGRAM
  fi
  if [[ -n $color_term_program_version ]]; then
    TERM_PROGRAM_VERSION=$color_term_program_version
  else
    unset TERM_PROGRAM_VERSION
  fi
  if [[ -n $color_term ]]; then
    TERM=$color_term
  else
    unset TERM
  fi
  if [[ -n $color_colorterm ]]; then
    COLORTERM=$color_colorterm
  else
    unset COLORTERM
  fi
  prepared_color=$color_prepared
  HAS_TMUX=$color_has_tmux
  rm -rf "$color_dir"
  _tmux_arr_loaded=()
  _tmux_arr_count=()
  _tmux_feat_vals=()
  _tmux_over_vals=()
  _tmux_term_deduped=0
  tm_term_queue=()
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  # #464: whole-entry dedupe in front of the one flush. The stub keeps real
  # slots. -gv is the raw text; -g is the indexed line used only to delete.
  local t464_term=${TERM-} t464_prog=${TERM_PROGRAM-} t464_ct=${COLORTERM-}
  local t464_app=${LANJUMP_GROK_APPEARANCE-} t464_lc=${LC_GROK_APPEARANCE-}
  local t464_g=${GROK_APPEARANCE-}
  local t464_shim=${LANJUMP_GROK_SHIM_DIR-} t464_front=${LANJUMP_GROK_FRONT_DIR-}
  local -i t464_color=$prepared_color t464_keys=$prepared_keys
  local -i t464_tmux=$HAS_TMUX t464_pi=$pick_interactive
  local t464_log t464_got t464_needle
  typeset -gA st464_feat st464_over
  typeset -gi st464_hide_g=0
  st464_n() {
    local which=$1 want=$2 i n=0
    local -a keys
    if [[ $which == feat ]]; then
      (( ${#st464_feat} )) || { print 0; return }
      keys=(${(kon)st464_feat})
      for i in "${keys[@]}"; do
        [[ ${st464_feat[$i]} == "$want" ]] && (( n++ ))
      done
    else
      (( ${#st464_over} )) || { print 0; return }
      keys=(${(kon)st464_over})
      for i in "${keys[@]}"; do
        [[ ${st464_over[$i]} == "$want" ]] && (( n++ ))
      done
    fi
    print -r -- "$n"
  }
  st464_reset_cache() {
    _tmux_arr_loaded=()
    _tmux_arr_count=()
    _tmux_feat_vals=()
    _tmux_over_vals=()
    _tmux_term_deduped=0
    tm_term_queue=()
    prepared_color=0
    prepared_keys=0
  }
  st464_one() {
    local flags=$2 opt=$3 spec i entry
    local -a keys parts
    case $1 in
      show-options)
        case $opt in
          default-terminal) print -r -- tmux-256color; return 0 ;;
          status-left-length) print -r -- 40; return 0 ;;
          terminal-features|terminal-overrides) ;;
          *) return 0 ;;
        esac
        if [[ $opt == terminal-features ]]; then
          (( ${#st464_feat} )) || return 0
          keys=(${(kon)st464_feat})
        else
          (( ${#st464_over} )) || return 0
          keys=(${(kon)st464_over})
        fi
        if (( st464_hide_g )) && [[ $flags == -g ]]; then
          keys=("${keys[1,-2]}")
        fi
        for i in "${keys[@]}"; do
          if [[ $flags == -gv ]]; then
            if [[ $opt == terminal-features ]]; then
              print -r -- "${st464_feat[$i]}"
            else
              print -r -- "${st464_over[$i]}"
            fi
          elif [[ $flags == -g ]]; then
            if [[ $opt == terminal-features ]]; then
              print -r -- "terminal-features[$i] ${st464_feat[$i]}"
            else
              print -r -- "terminal-overrides[$i] ${st464_over[$i]}"
            fi
          fi
        done
        return 0
        ;;
      set-option)
        if [[ $2 == -gu ]]; then
          spec=$3
          if [[ $spec == terminal-features\[* ]]; then
            i=${spec#"terminal-features["}
            i=${i%%]*}
            unset "st464_feat[$i]"
          elif [[ $spec == terminal-overrides\[* ]]; then
            i=${spec#"terminal-overrides["}
            i=${i%%]*}
            unset "st464_over[$i]"
          fi
          return 0
        fi
        if [[ $2 == -as || $2 == -ag ]]; then
          opt=$3
          entry=$4
          [[ $entry == ,* ]] && entry=${entry#,}
          parts=("${(@s:,:)entry}")
          for entry in "${parts[@]}"; do
            [[ -n $entry ]] || continue
            i=0
            if [[ $opt == terminal-features ]]; then
              while [[ -n ${st464_feat[$i]:-} ]]; do (( i++ )); done
              st464_feat[$i]=$entry
            elif [[ $opt == terminal-overrides ]]; then
              while [[ -n ${st464_over[$i]:-} ]]; do (( i++ )); done
              st464_over[$i]=$entry
            fi
          done
        fi
        return 0
        ;;
    esac
    return 0
  }
  t464_log=$(mktemp "${TMPDIR:-/tmp}/lanjump-464.XXXXXX") || return 1
  HAS_TMUX=1
  pick_interactive=0
  unset LANJUMP_GROK_SHIM_DIR LANJUMP_GROK_FRONT_DIR
  tmuxx() {
    print -r -- "$*" >>"$t464_log"
    local -a cmd
    local a
    cmd=()
    for a in "$@"; do
      if [[ $a == ';' ]]; then
        st464_one "${cmd[@]}"
        cmd=()
      else
        cmd+=("$a")
      fi
    done
    (( ${#cmd} )) && st464_one "${cmd[@]}"
    return 0
  }

  tmux_entry_is_lanjump_shape 'xterm-ghostty:RGB' && t464_got=yes || t464_got=no
  expect 464/shape-rgb yes "$t464_got"
  tmux_entry_is_lanjump_shape 'xterm-ghostty:Tc@' && t464_got=yes || t464_got=no
  expect 464/shape-tc-off yes "$t464_got"
  tmux_entry_is_lanjump_shape 'xterm*:extkeys' && t464_got=yes || t464_got=no
  expect 464/shape-extkeys yes "$t464_got"
  tmux_entry_is_lanjump_shape 'xterm-ghostty:RGB:extra' && t464_got=yes || t464_got=no
  expect 464/shape-longer no "$t464_got"
  tmux_entry_is_lanjump_shape 'other:extkeys' && t464_got=yes || t464_got=no
  expect 464/shape-other-extkeys no "$t464_got"
  tmux_entry_is_lanjump_shape 'mytheme:colors=256' && t464_got=yes || t464_got=no
  expect 464/shape-colors-256 no "$t464_got"
  if (( ${+functions[tmux_has_feature]} )); then
    print -u2 "FAIL 464/no-substring-helper tmux_has_feature still defined"
    (( fails++ ))
  fi

  st464_feat=()
  st464_over=()
  st464_hide_g=0
  st464_feat[0]='xterm*:clipboard:ccolour:cstyle:focus:title'
  st464_feat[1]='xterm-ghostty:RGB'
  st464_feat[2]='screen*:title'
  st464_feat[3]='xterm-ghostty:RGB'
  st464_feat[4]='xterm-ghostty:RGB:extra'
  st464_feat[5]='user custom:foo'
  st464_feat[6]='xterm-ghostty:RGB'
  st464_feat[7]='mytheme:colors=256'
  st464_feat[8]='mytheme:colors=256'
  st464_feat[9]='other:extkeys'
  st464_feat[10]='xterm-ghostty:RGB'
  st464_feat[12]='xterm-ghostty:RGB'
  st464_over[0]='linux*:AX@'
  st464_over[1]='xterm-ghostty:Tc'
  st464_over[2]='xterm-ghostty:Tc'
  st464_over[3]='xterm-ghostty:Tc@'
  st464_over[4]='xterm*:colors=256'
  st464_over[5]='xterm-256color:RGB@'
  st464_over[6]='xterm-256color:RGB@'
  st464_over[7]='user:colors=256'
  st464_over[8]='user:colors=256'
  : >"$t464_log"
  st464_reset_cache
  TERM=xterm-ghostty
  TERM_PROGRAM=ghostty
  COLORTERM=truecolor
  tmux_prepare_color
  tmux_prepare_keys
  t464_got=$(<"$t464_log")
  expect 464/dedupe-rgb 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/keep-rgb-extra 1 "$(st464_n feat xterm-ghostty:RGB:extra)"
  expect 464/keep-user-space 1 "$(st464_n feat 'user custom:foo')"
  expect 464/keep-clipboard 1 "$(st464_n feat 'xterm*:clipboard:ccolour:cstyle:focus:title')"
  expect 464/keep-nonshape-dup 2 "$(st464_n feat 'mytheme:colors=256')"
  expect 464/keep-other-extkeys 1 "$(st464_n feat 'other:extkeys')"
  expect 464/add-extkeys-once 1 "$(st464_n feat 'xterm*:extkeys')"
  expect 464/dedupe-tc 1 "$(st464_n over xterm-ghostty:Tc)"
  expect 464/keep-tc-off 1 "$(st464_n over xterm-ghostty:Tc@)"
  expect 464/dedupe-rgb-off 1 "$(st464_n over xterm-256color:RGB@)"
  expect 464/keep-linux 1 "$(st464_n over 'linux*:AX@')"
  expect 464/keep-nonshape-over-dup 2 "$(st464_n over 'user:colors=256')"
  t464_needle='set-option -gu terminal-features[12] ; set-option -gu terminal-features[10] ; set-option -gu terminal-features[6] ; set-option -gu terminal-features[3]'
  if [[ $t464_got != *"$t464_needle"* ]]; then
    print -u2 "FAIL 464/unset-order got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi
  t464_needle='set-option -gu terminal-overrides[6] ; set-option -gu terminal-overrides[2]'
  if [[ $t464_got != *"$t464_needle"* ]]; then
    print -u2 "FAIL 464/unset-over-order got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi
  for t464_needle in \
    'set-option -gu terminal-features[0]' \
    'set-option -gu terminal-features[1]' \
    'set-option -gu terminal-features[4]' \
    'set-option -gu terminal-features[5]' \
    'set-option -gu terminal-features[7]' \
    'set-option -gu terminal-features[9]' \
    'set-option -gu terminal-overrides[0]' \
    'set-option -gu terminal-overrides[1]' \
    'set-option -gu terminal-overrides[3]' \
    'set-option -as terminal-features ,xterm-ghostty:RGB' \
    'set-option -ag terminal-overrides ,xterm-ghostty:Tc'
  do
    if [[ $t464_got == *"$t464_needle"* ]]; then
      print -u2 "FAIL 464/kept-or-skipped touched $(printf %q "$t464_needle")"
      (( fails++ ))
    fi
  done
  t464_needle='set-option -as terminal-features ,xterm*:extkeys'
  if [[ $t464_got != *"$t464_needle"* ]]; then
    print -u2 "FAIL 464/extkeys-added missing exact xterm*:extkeys append"
    (( fails++ ))
  fi

  : >"$t464_log"
  local -i t464_round
  for (( t464_round = 0; t464_round < 10; t464_round++ )); do
    st464_reset_cache
    TERM=xterm-ghostty
    TERM_PROGRAM=ghostty
    tmux_prepare_color
    tmux_prepare_keys
  done
  t464_got=$(<"$t464_log")
  if [[ $t464_got == *'set-option -as terminal-features'* || $t464_got == *'set-option -ag terminal-overrides'* || $t464_got == *'set-option -gu terminal-'* ]]; then
    print -u2 "FAIL 464/ten-opens still wrote arrays got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi
  expect 464/ten-rgb 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/ten-extkeys 1 "$(st464_n feat 'xterm*:extkeys')"
  expect 464/ten-user-dup 2 "$(st464_n over 'user:colors=256')"

  : >"$t464_log"
  st464_reset_cache
  TERM=xterm-kitty
  TERM_PROGRAM=kitty
  tmux_prepare_color
  tmux_prepare_keys
  t464_got=$(<"$t464_log")
  expect 464/cross-kitty-rgb 1 "$(st464_n feat xterm-kitty:RGB)"
  expect 464/cross-kitty-tc 1 "$(st464_n over xterm-kitty:Tc)"
  expect 464/cross-ghostty-stays 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/cross-extkeys-stays 1 "$(st464_n feat 'xterm*:extkeys')"
  if [[ $t464_got != *',xterm-kitty:RGB'*',xterm-kitty:Tc'* ]]; then
    print -u2 "FAIL 464/cross-one-flush got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi

  st464_feat=()
  st464_over=()
  st464_feat[0]='xterm-ghostty:RGB:extra'
  st464_feat[1]='xterm-ghostty:RGB@'
  st464_feat[2]='xterm-ghostty:RGB2'
  st464_over[0]='linux*:AX@'
  st464_over[1]='xterm-ghostty:Tc@'
  : >"$t464_log"
  st464_reset_cache
  TERM=xterm-ghostty
  TERM_PROGRAM=ghostty
  tmux_prepare_color
  expect 464/similar-added-rgb 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/similar-keeps-extra 1 "$(st464_n feat xterm-ghostty:RGB:extra)"
  expect 464/similar-keeps-rgb-off 1 "$(st464_n feat xterm-ghostty:RGB@)"
  expect 464/similar-keeps-rgb2 1 "$(st464_n feat xterm-ghostty:RGB2)"
  expect 464/similar-keeps-tc-off 1 "$(st464_n over xterm-ghostty:Tc@)"
  expect 464/similar-added-tc 1 "$(st464_n over xterm-ghostty:Tc)"

  st464_feat=()
  st464_over=()
  st464_feat[0]='xterm-ghostty:RGB'
  st464_feat[1]='xterm-ghostty:RGB'
  st464_feat[2]='user custom:foo'
  st464_hide_g=1
  : >"$t464_log"
  st464_reset_cache
  TERM=xterm-ghostty
  TERM_PROGRAM=ghostty
  tmux_prepare_color
  t464_got=$(<"$t464_log")
  expect 464/mismatch-keeps-both 2 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/mismatch-keeps-user 1 "$(st464_n feat 'user custom:foo')"
  if [[ $t464_got == *'set-option -gu terminal-'* ]]; then
    print -u2 "FAIL 464/mismatch-deleted got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi
  st464_hide_g=0
  : >"$t464_log"
  st464_reset_cache
  tmux_prepare_color
  expect 464/mismatch-then-clean 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/mismatch-user-remains 1 "$(st464_n feat 'user custom:foo')"

  st464_feat=()
  st464_over=()
  st464_feat[0]='xterm-ghostty:RGB'
  st464_feat[1]='user custom:foo'
  st464_over[0]='linux*:AX@'
  : >"$t464_log"
  st464_reset_cache
  TERM=xterm-256color
  TERM_PROGRAM=Apple_Terminal
  unset COLORTERM
  tmux_prepare_color
  tmux_prepare_keys
  expect 464/apple-keeps-ghostty 1 "$(st464_n feat xterm-ghostty:RGB)"
  expect 464/apple-keeps-user 1 "$(st464_n feat 'user custom:foo')"
  expect 464/apple-term-rgb-off 1 "$(st464_n feat xterm-256color:RGB@)"
  expect 464/apple-term-256 1 "$(st464_n feat xterm-256color:256)"
  expect 464/apple-inner-rgb-off 1 "$(st464_n feat tmux-256color:RGB@)"
  expect 464/apple-inner-256 1 "$(st464_n feat tmux-256color:256)"
  expect 464/apple-over-rgb-off 1 "$(st464_n over xterm-256color:RGB@)"
  expect 464/apple-over-tc-off 1 "$(st464_n over xterm-256color:Tc@)"
  expect 464/apple-inner-over-rgb 1 "$(st464_n over tmux-256color:RGB@)"
  expect 464/apple-inner-over-tc 1 "$(st464_n over tmux-256color:Tc@)"
  expect 464/apple-keeps-linux 1 "$(st464_n over 'linux*:AX@')"
  expect 464/apple-no-truecolor-rgb 0 "$(st464_n feat xterm-256color:RGB)"
  : >"$t464_log"
  for (( t464_round = 0; t464_round < 10; t464_round++ )); do
    st464_reset_cache
    tmux_prepare_color
    tmux_prepare_keys
  done
  t464_got=$(<"$t464_log")
  if [[ $t464_got == *'set-option -as terminal-features'* || $t464_got == *'set-option -ag terminal-overrides'* || $t464_got == *'set-option -gu terminal-'* ]]; then
    print -u2 "FAIL 464/apple-ten-opens still wrote arrays got=$(printf %q "$t464_got")"
    (( fails++ ))
  fi
  expect 464/apple-ten-ghostty 1 "$(st464_n feat xterm-ghostty:RGB)"

  st464_reset_cache
  prepared_color=$t464_color
  prepared_keys=$t464_keys
  HAS_TMUX=$t464_tmux
  pick_interactive=$t464_pi
  _tmux_arr_loaded=()
  _tmux_arr_count=()
  _tmux_feat_vals=()
  _tmux_over_vals=()
  _tmux_term_deduped=0
  tm_term_queue=()
  unset st464_feat st464_over st464_hide_g
  unfunction st464_n st464_reset_cache st464_one tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }
  rm -f "$t464_log"
  if [[ -n $t464_term ]]; then TERM=$t464_term; else unset TERM; fi
  if [[ -n $t464_prog ]]; then TERM_PROGRAM=$t464_prog; else unset TERM_PROGRAM; fi
  if [[ -n $t464_ct ]]; then COLORTERM=$t464_ct; else unset COLORTERM; fi
  if [[ -n $t464_app ]]; then LANJUMP_GROK_APPEARANCE=$t464_app; else unset LANJUMP_GROK_APPEARANCE; fi
  if [[ -n $t464_lc ]]; then LC_GROK_APPEARANCE=$t464_lc; else unset LC_GROK_APPEARANCE; fi
  if [[ -n $t464_g ]]; then GROK_APPEARANCE=$t464_g; else unset GROK_APPEARANCE; fi
  if [[ -n $t464_shim ]]; then LANJUMP_GROK_SHIM_DIR=$t464_shim; else unset LANJUMP_GROK_SHIM_DIR; fi
  if [[ -n $t464_front ]]; then LANJUMP_GROK_FRONT_DIR=$t464_front; else unset LANJUMP_GROK_FRONT_DIR; fi

  # tmux attach needs a terminfo entry. Ghostty's xterm-ghostty is missing on
  # older remotes; keep the picker TERM, attach with a stock name instead.
  local client_term_saved=${TERM-} client_term_program=${TERM_PROGRAM-}
  local client_got client_log
  local -i client_has_tmux=$HAS_TMUX
  HAS_TMUX=1
  client_log=$(mktemp "${TMPDIR:-/tmp}/lanjump-client-term.XXXXXX") || return 1
  functions -c terminfo_available _st_terminfo_available 2>/dev/null || true
  functions -c tmux_prepare_color _st_tmux_prepare_color
  functions -c tmux_prepare_keys _st_tmux_prepare_keys
  functions -c run_interactive _st_run_interactive
  functions -c tmuxx _st_client_tmuxx
  terminfo_available() { [[ $1 == xterm-256color || $1 == screen-256color ]] }
  tmux_prepare_color() { : }
  tmux_prepare_keys() { : }
  tmuxx() { print -r -- "$*" >>"$client_log" }
  run_interactive() { print -r -- "TERM=${TERM:-} $*" >>"$client_log" }

  TERM=xterm-ghostty
  TERM_PROGRAM=ghostty
  client_got=$(tmux_client_term)
  if [[ $client_got != xterm-256color ]]; then
    print -u2 "FAIL client-term/missing-ghostty got=$(printf %q "$client_got") want=xterm-256color"
    (( fails++ ))
  fi
  if [[ $TERM != xterm-ghostty ]]; then
    print -u2 "FAIL client-term/missing-ghostty-parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi

  : >"$client_log"
  TMUX_BIN=tmux
  tmux_tty attach-session -t '=test'
  client_got=$(<"$client_log")
  if [[ $client_got != *'TERM=xterm-256color tmux attach-session -t =test'* ]]; then
    print -u2 "FAIL client-term/attach-fallback got=$(printf %q "$client_got")"
    (( fails++ ))
  fi
  if [[ $client_got != *xterm-256color:RGB* ]]; then
    print -u2 "FAIL client-term/attach-rgb got=$(printf %q "$client_got")"
    (( fails++ ))
  fi
  if [[ $TERM != xterm-ghostty ]]; then
    print -u2 "FAIL client-term/attach-parent mutated got=$(printf %q "$TERM")"
    (( fails++ ))
  fi

  terminfo_available() { return 0 }
  client_got=$(tmux_client_term)
  if [[ $client_got != xterm-ghostty ]]; then
    print -u2 "FAIL client-term/keep-ghostty got=$(printf %q "$client_got") want=xterm-ghostty"
    (( fails++ ))
  fi

  : >"$client_log"
  tmux_tty attach-session -t '=test'
  client_got=$(<"$client_log")
  if [[ $client_got != *'TERM=xterm-ghostty tmux attach-session -t =test'* ]]; then
    print -u2 "FAIL client-term/attach-keep got=$(printf %q "$client_got")"
    (( fails++ ))
  fi
  if [[ $client_got == *xterm-256color:RGB* ]]; then
    print -u2 "FAIL client-term/attach-keep-no-fallback-rgb got=$(printf %q "$client_got")"
    (( fails++ ))
  fi

  if [[ ${functions[open_named_tabs]} != *tmux_client_term* ]]; then
    print -u2 "FAIL client-term/open-tabs-exec missing tmux_client_term"
    (( fails++ ))
  fi

  if [[ -n ${functions[_st_terminfo_available]:-} ]]; then
    functions -c _st_terminfo_available terminfo_available
    unfunction _st_terminfo_available
  else
    unfunction terminfo_available 2>/dev/null || true
  fi
  functions -c _st_tmux_prepare_color tmux_prepare_color
  functions -c _st_tmux_prepare_keys tmux_prepare_keys
  functions -c _st_run_interactive run_interactive
  functions -c _st_client_tmuxx tmuxx
  unfunction _st_tmux_prepare_color _st_tmux_prepare_keys _st_run_interactive _st_client_tmuxx
  HAS_TMUX=$client_has_tmux
  rm -f "$client_log"
  if [[ -n $client_term_saved ]]; then
    TERM=$client_term_saved
  else
    unset TERM
  fi
  if [[ -n $client_term_program ]]; then
    TERM_PROGRAM=$client_term_program
  else
    unset TERM_PROGRAM
  fi

  # #212: picker and a child shell share a foreground group. The shell
  # ignores SIGINT; zsh defers the picker's `exit 130` INT trap until
  # the child returns. Ctrl+C then `exit` must return to the list, not
  # quit the UI. Pty stand-in: product run_interactive + product trap,
  # child ignores INT, write ^C, child exits 0.
  local _st212_dir _st212_st _st212_log _st212_err
  _st212_dir=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-212.XXXXXX") || return 1
  typeset -f run_interactive keys_bin >"$_st212_dir/fns.zsh"
  print -r -- $'#!/bin/zsh\ntrap \'\' INT\nprint -r -- CHILD_READY\nread -r _ || true\nprint -r -- CHILD_DONE\nexit 0' >"$_st212_dir/child.zsh"
  chmod +x "$_st212_dir/child.zsh"
  cat >"$_st212_dir/parent.zsh" <<EOF
emulate zsh
setopt no_unset
LOG=${(q)_st212_dir}/log
. ${(q)_st212_dir}/fns.zsh
restore_tty() { print -r -- RESTORED >>\$LOG }
local_keyboard() { return 1 }
trap 'restore_tty; print -r -- TRAP >>\$LOG; exit 130' INT
print -r -- PARENT_START >>\$LOG
run_interactive /bin/zsh ${(q)_st212_dir}/child.zsh
print -r -- PARENT_BACK >>\$LOG
exit 0
EOF
  cat >"$_st212_dir/drive.py" <<'PY'
import os, pty, select, time, sys
d = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/zsh", ["zsh", os.path.join(d, "parent.zsh")])
buf = b""
deadline = time.time() + 4
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            buf += os.read(fd, 4096)
        except OSError:
            break
        if b"CHILD_READY" in buf:
            break
os.write(fd, b"\x03")
time.sleep(0.1)
os.write(fd, b"\n")
st = None
deadline = time.time() + 4
while time.time() < deadline:
    wpid, status = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        st = status
        break
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            buf += os.read(fd, 4096)
        except OSError:
            pass
if st is None:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    sys.exit(99)
if os.WIFEXITED(st):
    sys.exit(os.WEXITSTATUS(st))
if os.WIFSIGNALED(st):
    sys.exit(128 + os.WTERMSIG(st))
sys.exit(99)
PY
  _st212_st=0
  _st212_err=$(python3 "$_st212_dir/drive.py" "$_st212_dir" 2>&1) || _st212_st=$?
  _st212_log=
  [[ -f $_st212_dir/log ]] && _st212_log=$(<$_st212_dir/log)
  rm -rf "$_st212_dir"
  if (( _st212_st == 130 )) || [[ $_st212_log == *TRAP* ]] || [[ $_st212_log != *PARENT_BACK* ]]; then
    print -u2 "FAIL shell-int/deferred-quit status=$_st212_st log=$(printf %q "$_st212_log") err=$(printf %q "$_st212_err")"
    (( fails++ ))
  fi

  # #268: print >last-session truncates dest before the new name exists.
  # Mirror last/atomic-write / snap/atomic-write. Source-check the real
  # remember_last_session (stubs above restore it).
  if [[ ${functions[remember_last_session]} != *replace_file_atomic* ]]; then
    print -u2 "FAIL last-session/atomic-write missing replace_file_atomic"
    (( fails++ ))
  fi
  local last268_home last268 last268_mid last268_saved_home
  local -i last268_torn=0
  last268_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-268.XXXXXX") || return 1
  last268_saved_home=$HOME
  HOME=$last268_home
  last_session_file
  last268=$REPLY
  mkdir -p "${last268:h}"
  print -r -- old-session >"$last268"
  print() {
    last268_mid=$(<"$last268")
    if [[ -z $last268_mid ]]; then
      last268_torn=1
    fi
    builtin print "$@"
  }
  remember_last_session new-session
  unfunction print
  if (( last268_torn )); then
    print -u2 "FAIL last-session/atomic-write dest was torn mid-save"
    (( fails++ ))
  fi
  expect last-session/atomic-write-name new-session "$(read_last_session_name)"
  HOME=$last268_saved_home
  rm -rf "$last268_home"

  # #276: two add_pin_record writers load then replace the whole pin file.
  # A loads, yields, then saves; B writes in the gap. Both names must remain.
  local pin276_home pin276_saved_home pin276_fn
  local -a pin276_names
  local -i pin276_a=0 pin276_b=0
  pin276_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-276.XXXXXX") || return 1
  pin276_saved_home=$HOME
  mkdir -p "$pin276_home/Library/Application Support/lanjump"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$pin276_home")"
    print -r -- 'typeset -a pinned_names'
    print -r -- 'typeset -A pinned_cwd pinned_grok'
    for pin276_fn in lanjump_data_dir pinned_sessions_file sanitize_pin_field \
      pin_record_exists load_pinned_sessions replace_file_atomic \
      save_pinned_sessions add_pin_record with_data_file_lock; do
      (( ${+functions[$pin276_fn]} )) && functions "$pin276_fn"
    done
  } >"$pin276_home/child-a.zsh"
  {
    print -r -- 'functions -c load_pinned_sessions _pin276_load'
    print -r -- 'load_pinned_sessions() {'
    print -r -- '  _pin276_load "$@"'
    print -r -- '  print -r -- loaded >"$HOME/loaded"'
    print -r -- '  sleep 0.35'
    print -r -- '}'
    print -r -- 'add_pin_record pin-a /tmp/a'
  } >>"$pin276_home/child-a.zsh"
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$pin276_home")"
    print -r -- 'typeset -a pinned_names'
    print -r -- 'typeset -A pinned_cwd pinned_grok'
    for pin276_fn in lanjump_data_dir pinned_sessions_file sanitize_pin_field \
      pin_record_exists load_pinned_sessions replace_file_atomic \
      save_pinned_sessions add_pin_record with_data_file_lock; do
      (( ${+functions[$pin276_fn]} )) && functions "$pin276_fn"
    done
    print -r -- 'while [[ ! -f $HOME/loaded ]]; do'
    print -r -- '  sleep 0.01'
    print -r -- 'done'
    print -r -- 'add_pin_record pin-b /tmp/b'
  } >"$pin276_home/child-b.zsh"
  /bin/zsh "$pin276_home/child-a.zsh" &
  pin276_a=$!
  /bin/zsh "$pin276_home/child-b.zsh" &
  pin276_b=$!
  wait $pin276_a
  wait $pin276_b
  HOME=$pin276_home
  load_pinned_sessions
  pin276_names=("${pinned_names[@]}")
  HOME=$pin276_saved_home
  if ! (( ${pin276_names[(Ie)pin-a]} && ${pin276_names[(Ie)pin-b]} )); then
    print -u2 "FAIL pin/concurrent-write lost an update names=$(printf %q "${pin276_names[*]}")"
    (( fails++ ))
  fi
  rm -rf "$pin276_home"

  # #315: pin file write failure must not paint list/tmux as pinned or renamed.
  local pin315_home pin315_saved_home pin315_tmux pin315_log
  local pin315_tmux_name pin315_draw_id pin315_draw_pinned
  local pin315_load_keep pin315_items_id
  local -i pin315_has_tmux=$HAS_TMUX
  pin315_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-315.XXXXXX") || return 1
  pin315_saved_home=$HOME
  HOME=$pin315_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  pin315_tmux=$pin315_home/tmux.log
  : >"$pin315_tmux"
  functions -c replace_file_atomic _pin315_replace
  functions -c tmuxx _pin315_tmuxx
  functions -c restore_tty _pin315_restore_tty
  functions -c setup_tty _pin315_setup_tty
  functions -c draw _pin315_draw
  replace_file_atomic() { return 1 }
  tmuxx() {
    print -r -- "$*" >>"$pin315_tmux"
    case $1 in
      display-message)
        print -r -- /tmp/keep
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  HAS_TMUX=1
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  items_kind=(session)
  items_id=(keep)
  items_name=(keep)
  items_pinned=(0)
  all_id=(keep)
  all_name=(keep)
  all_pinned=(0)
  cursor=1
  toggle_session_pin
  if [[ ${items_pinned[1]} == 1 ]]; then
    print -u2 "FAIL pin/write-fail-ui still marked pinned"
    (( fails++ ))
  fi
  if [[ ${all_pinned[1]} == 1 ]]; then
    print -u2 "FAIL pin/write-fail-ui all_pinned still 1"
    (( fails++ ))
  fi
  pin315_log=$(<"$pin315_tmux")
  if [[ $pin315_log == *'@lanjump_pinned 1'* ]]; then
    print -u2 "FAIL pin/write-fail-ui tmux still pinned got=$(printf %q "$pin315_log")"
    (( fails++ ))
  fi
  functions -c _pin315_replace replace_file_atomic
  load_pinned_sessions
  if pin_record_exists keep; then
    print -u2 "FAIL pin/write-fail-ui pin file has keep"
    (( fails++ ))
  fi

  print -r -- $'name keep\ncwd /tmp/keep\ngrok gid-keep\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  load_pinned_sessions
  functions -c replace_file_atomic _pin315_replace
  replace_file_atomic() { return 1 }
  pin315_tmux_name=keep
  pin315_draw_id=
  pin315_draw_pinned=
  : >"$pin315_tmux"
  tmuxx() {
    print -r -- "$*" >>"$pin315_tmux"
    case $1 in
      has-session) return 1 ;;
      rename-session)
        pin315_tmux_name=${@[-1]}
        return 0
        ;;
      list-sessions)
        if [[ $* == *-F* ]]; then
          print -r -- $'100\x1f'"$pin315_tmux_name"$'\x1f1\x1f0\x1f/tmp/keep\x1fkeep\x1fkeep\x1fzsh'
        fi
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  functions -c load_items _pin315_load_items
  restore_tty() { : }
  setup_tty() { : }
  load_items() {
    print -r -- "${1:-}" >"$pin315_home/load_keep"
    _pin315_load_items "$@"
    print -r -- "${items_id[*]}" >"$pin315_home/items_id"
    print -r -- "${items_pinned[*]}" >"$pin315_home/items_pinned"
  }
  draw() {
    pin315_draw_id=${items_id[1]:-}
    pin315_draw_pinned=${items_pinned[1]:-}
    print -r -- "${items_id[1]:-}" >"$pin315_home/draw_id"
    print -r -- "${items_pinned[1]:-}" >"$pin315_home/draw_pinned"
  }
  items_kind=(session)
  items_id=(keep)
  items_name=(keep)
  items_pinned=(1)
  cursor=1
  # Here-doc keeps prompt_rename in this shell so draw/tmux state is visible.
  prompt_rename >/dev/null <<'EOF'
keep-renamed
EOF
  pin315_draw_id=$(<"$pin315_home/draw_id" 2>/dev/null)
  pin315_draw_pinned=$(<"$pin315_home/draw_pinned" 2>/dev/null)
  pin315_load_keep=$(<"$pin315_home/load_keep" 2>/dev/null)
  pin315_items_id=$(<"$pin315_home/items_id" 2>/dev/null)
  if [[ ${pin315_load_keep:-} == keep-renamed ]]; then
    print -u2 "FAIL pin/rename-write-fail-ui load_items kept keep-renamed"
    (( fails++ ))
  fi
  if [[ ${pin315_items_id:-} == *keep-renamed* ]]; then
    print -u2 "FAIL pin/rename-write-fail-ui list has keep-renamed got=$(printf %q "$pin315_items_id")"
    (( fails++ ))
  fi
  if [[ ${pin315_draw_id:-} == keep-renamed ]]; then
    print -u2 "FAIL pin/rename-write-fail-ui redrew as keep-renamed"
    (( fails++ ))
  fi
  if [[ ${pin315_draw_id:-} == keep-renamed && ${pin315_draw_pinned:-} == 1 ]]; then
    print -u2 "FAIL pin/rename-write-fail-ui marked keep-renamed pinned"
    (( fails++ ))
  fi
  pin315_log=$(<"$pin315_tmux")
  if [[ $pin315_log == *'rename-session -t =keep keep-renamed'* && $pin315_log != *'rename-session -t =keep-renamed keep'* ]]; then
    print -u2 "FAIL pin/rename-write-fail-ui tmux left as keep-renamed got=$(printf %q "$pin315_log")"
    (( fails++ ))
  fi
  functions -c _pin315_replace replace_file_atomic
  load_pinned_sessions
  if ! pin_record_exists keep; then
    print -u2 "FAIL pin/rename-write-fail-ui pin file lost keep"
    (( fails++ ))
  fi
  if pin_record_exists keep-renamed; then
    print -u2 "FAIL pin/rename-write-fail-ui pin file has keep-renamed"
    (( fails++ ))
  fi
  functions -c _pin315_tmuxx tmuxx
  functions -c _pin315_restore_tty restore_tty
  functions -c _pin315_setup_tty setup_tty
  functions -c _pin315_draw draw
  functions -c _pin315_load_items load_items
  unset -f _pin315_replace _pin315_tmuxx _pin315_restore_tty _pin315_setup_tty \
    _pin315_draw _pin315_load_items
  HAS_TMUX=$pin315_has_tmux
  HOME=$pin315_saved_home
  rm -rf "$pin315_home"

  # #356: snapshot/pin persist failure must not look like 已删 / 已取消常驻.
  local pin356_home pin356_saved_home pin356_tmux pin356_log pin356_out
  local -i pin356_has_tmux=$HAS_TMUX pin356_forget_st=0
  pin356_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-356.XXXXXX") || return 1
  pin356_saved_home=$HOME
  HOME=$pin356_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  pin356_tmux=$pin356_home/tmux.log
  : >"$pin356_tmux"
  functions -c tmuxx _pin356_tmuxx
  functions -c remove_pin_record _pin356_remove
  tmuxx() {
    print -r -- "$*" >>"$pin356_tmux"
    return 0
  }
  remove_pin_record() { return 1 }
  HAS_TMUX=1
  items_kind=(session)
  items_id=(keep)
  items_name=(keep)
  items_pinned=(1)
  all_id=(keep)
  all_name=(keep)
  all_pinned=(1)
  cursor=1
  toggle_session_pin
  if [[ ${items_pinned[1]} != 1 ]]; then
    print -u2 "FAIL delete/unpin-write-fail-ui marked unpinned"
    (( fails++ ))
  fi
  if [[ ${all_pinned[1]} != 1 ]]; then
    print -u2 "FAIL delete/unpin-write-fail-ui all_pinned cleared"
    (( fails++ ))
  fi
  pin356_log=$(<"$pin356_tmux")
  if [[ $pin356_log == *'@lanjump_pinned'* ]]; then
    print -u2 "FAIL delete/unpin-write-fail-ui tmux unpinned got=$(printf %q "$pin356_log")"
    (( fails++ ))
  fi
  functions -c _pin356_remove remove_pin_record

  functions -c save_session_snapshot _pin356_save
  snap_names=(gone)
  snap_cwd=([gone]=/tmp/gone)
  snap_occupied=([gone]=1)
  snap_workspace=([gone]=1)
  snap_cmd=([gone]=zsh)
  snap_attached=([gone]=$EPOCHSECONDS)
  save_session_snapshot
  pinned_names=(gone)
  pinned_cwd=([gone]=/tmp/gone)
  pinned_grok=()
  save_pinned_sessions
  save_session_snapshot() { return 1 }
  pin356_forget_st=0
  forget_killed_session gone || pin356_forget_st=$?
  if (( pin356_forget_st == 0 )); then
    print -u2 "FAIL delete/snap-write-fail forget reported success"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)gone]} -eq 0 ]]; then
    print -u2 "FAIL delete/snap-write-fail cleared in-memory snap"
    (( fails++ ))
  fi
  load_session_snapshot
  if [[ ${snap_names[(Ie)gone]} -eq 0 ]]; then
    print -u2 "FAIL delete/snap-write-fail disk snap lost gone"
    (( fails++ ))
  fi
  load_pinned_sessions
  if ! pin_record_exists gone; then
    print -u2 "FAIL delete/snap-write-fail removed pin after snap save fail"
    (( fails++ ))
  fi

  functions -c restore_tty _pin356_restore_tty
  functions -c setup_tty _pin356_setup_tty
  functions -c draw _pin356_draw
  functions -c load_items _pin356_load_items
  restore_tty() { : }
  setup_tty() { : }
  draw() { : }
  load_items() { : }
  tmuxx() {
    print -r -- "$*" >>"$pin356_tmux"
    case $1 in
      kill-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  items_kind=(session)
  items_id=(gone)
  items_name=(gone)
  items_att=(0)
  items_pinned=(1)
  cursor=1
  HAS_TMUX=1
  pin356_out=$(prompt_delete <<'EOF'
y

EOF
)
  if [[ $pin356_out != *删除失败* ]]; then
    print -u2 "FAIL delete/snap-write-fail-ui did not report 删除失败 got=$(printf %q "$pin356_out")"
    (( fails++ ))
  fi
  functions -c _pin356_save save_session_snapshot
  functions -c _pin356_tmuxx tmuxx
  functions -c _pin356_restore_tty restore_tty
  functions -c _pin356_setup_tty setup_tty
  functions -c _pin356_draw draw
  functions -c _pin356_load_items load_items
  unset -f _pin356_save _pin356_tmuxx _pin356_remove _pin356_restore_tty \
    _pin356_setup_tty _pin356_draw _pin356_load_items
  HAS_TMUX=$pin356_has_tmux
  HOME=$pin356_saved_home
  rm -rf "$pin356_home"

  # #395: n / --pin-session pin write failure must fail. @lanjump_pinned is gone (#463).
  local pin395_home pin395_saved_home pin395_log
  local -i pin395_has_tmux=$HAS_TMUX pin395_st=0
  pin395_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-395.XXXXXX") || return 1
  pin395_saved_home=$HOME
  HOME=$pin395_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  pin395_log=$pin395_home/tmux.log
  : >"$pin395_log"
  functions -c add_pin_record _pin395_add
  functions -c tmuxx _pin395_tmuxx
  add_pin_record() { return 1 }
  tmuxx() { print -r -- "$*" >>"$pin395_log"; return 0 }
  HAS_TMUX=1
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"

  pin395_st=0
  : >"$pin395_log"
  prompt_new_commit_pin keep || pin395_st=$?
  if (( pin395_st == 0 )); then
    print -u2 "FAIL pin/new-write-fail commit reported success"
    (( fails++ ))
  fi
  if [[ $(<"$pin395_log") == *'@lanjump_pinned'* ]]; then
    print -u2 "FAIL pin/new-write-fail commit still set tmux pinned"
    (( fails++ ))
  fi

  pin395_st=0
  : >"$pin395_log"
  pin_named_session keep >/dev/null || pin395_st=$?
  if (( pin395_st == 0 )); then
    print -u2 "FAIL pin/cli-write-fail reported success"
    (( fails++ ))
  fi
  if [[ $(<"$pin395_log") == *'@lanjump_pinned'* ]]; then
    print -u2 "FAIL pin/cli-write-fail still set tmux pinned"
    (( fails++ ))
  fi

  functions -c _pin395_add add_pin_record
  functions -c _pin395_tmuxx tmuxx
  unset -f _pin395_add _pin395_tmuxx
  HAS_TMUX=$pin395_has_tmux
  HOME=$pin395_saved_home
  rm -rf "$pin395_home"

  # #407: rename snapshot write failure must fail-closed, not look successful.
  # tmux/pin already moved; disk snap staying old used to let restore / work
  # recreate the old name or drop workspace marks.
  local snap407_home snap407_saved_home snap407_tmux snap407_log snap407_load
  local -i snap407_has_tmux=$HAS_TMUX snap407_st=0
  snap407_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-407.XXXXXX") || return 1
  snap407_saved_home=$HOME
  HOME=$snap407_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  snap407_tmux=$snap407_home/tmux.log
  : >"$snap407_tmux"
  snap_names=(old)
  snap_cwd=([old]=/proj/old)
  snap_occupied=([old]=0)
  snap_workspace=([old]=1)
  snap_cmd=([old]=zsh)
  snap_attached=([old]=123)
  save_session_snapshot
  functions -c save_session_snapshot _snap407_save
  save_session_snapshot() { return 1 }
  snap407_st=0
  rename_snap_record old new || snap407_st=$?
  if (( snap407_st == 0 )); then
    print -u2 "FAIL snap/rename-write-fail reported success"
    (( fails++ ))
  fi
  functions -c _snap407_save save_session_snapshot
  load_session_snapshot
  if [[ ${snap_names[(Ie)old]} -eq 0 ]]; then
    print -u2 "FAIL snap/rename-write-fail disk lost old got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)new]} -ne 0 ]]; then
    print -u2 "FAIL snap/rename-write-fail disk has new got=${snap_names[*]}"
    (( fails++ ))
  fi

  print -r -- $'name old\ncwd /proj/old\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  load_pinned_sessions
  snap_names=(old)
  snap_cwd=([old]=/proj/old)
  snap_occupied=([old]=0)
  snap_workspace=([old]=1)
  snap_cmd=([old]=zsh)
  snap_attached=([old]=123)
  save_session_snapshot
  functions -c save_session_snapshot _snap407_save
  functions -c tmuxx _snap407_tmuxx
  functions -c restore_tty _snap407_restore_tty
  functions -c setup_tty _snap407_setup_tty
  functions -c draw _snap407_draw
  functions -c load_items _snap407_load_items
  save_session_snapshot() { return 1 }
  tmuxx() {
    print -r -- "$*" >>"$snap407_tmux"
    case $1 in
      has-session) return 1 ;;
      rename-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  restore_tty() { : }
  setup_tty() { : }
  draw() { : }
  load_items() {
    print -r -- "${1:-}" >"$snap407_home/load_keep"
  }
  HAS_TMUX=1
  items_kind=(session)
  items_id=(old)
  items_name=(old)
  items_pinned=(1)
  cursor=1
  prompt_rename >/dev/null <<'EOF'
new
EOF
  snap407_load=$(<"$snap407_home/load_keep" 2>/dev/null)
  snap407_log=$(<"$snap407_tmux")
  if [[ ${snap407_load:-} == new ]]; then
    print -u2 "FAIL snap/rename-write-fail-ui load_items kept new"
    (( fails++ ))
  fi
  if [[ $snap407_log == *'rename-session -t =old new'* && $snap407_log != *'rename-session -t =new old'* ]]; then
    print -u2 "FAIL snap/rename-write-fail-ui tmux left as new got=$(printf %q "$snap407_log")"
    (( fails++ ))
  fi
  functions -c _snap407_save save_session_snapshot
  load_pinned_sessions
  if ! pin_record_exists old; then
    print -u2 "FAIL snap/rename-write-fail-ui pin file lost old"
    (( fails++ ))
  fi
  if pin_record_exists new; then
    print -u2 "FAIL snap/rename-write-fail-ui pin file has new"
    (( fails++ ))
  fi
  load_session_snapshot
  if [[ ${snap_names[(Ie)old]} -eq 0 || ${snap_names[(Ie)new]} -ne 0 ]]; then
    print -u2 "FAIL snap/rename-write-fail-ui disk snap drifted got=${snap_names[*]}"
    (( fails++ ))
  fi
  functions -c _snap407_tmuxx tmuxx
  functions -c _snap407_restore_tty restore_tty
  functions -c _snap407_setup_tty setup_tty
  functions -c _snap407_draw draw
  functions -c _snap407_load_items load_items
  unset -f _snap407_save _snap407_tmuxx _snap407_restore_tty _snap407_setup_tty \
    _snap407_draw _snap407_load_items
  HAS_TMUX=$snap407_has_tmux
  HOME=$snap407_saved_home
  rm -rf "$snap407_home"

  # #463: r and the shell return re-read tmux. A warm census would keep
  # showing sessions another terminal already created or killed.
  if [[ ${functions[refresh_external_sessions]:-} != *tmux_state_invalidate* ]]; then
    print -u2 "FAIL refresh/external missing tmux_state_invalidate"
    (( fails++ ))
  fi
  if [[ ${functions[activate]:-} != *refresh_external_sessions* ]]; then
    print -u2 "FAIL refresh/shell-return activate still loads a warm census"
    (( fails++ ))
  fi
  if ! awk '
    /[^[:alnum:]_]r\)/ {p=1}
    p && /refresh_external_sessions/ {found=1; exit}
    p && /;;/ {exit}
    END {exit found ? 0 : 1}
  ' "$_pick_src_file"; then
    print -u2 "FAIL refresh/key-r main loop does not drop the census"
    (( fails++ ))
  fi
  {
    local ext_home ext_saved_home ext_row
    local -i ext_has=$HAS_TMUX
    ext_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-463-ext.XXXXXX") || return 1
    ext_saved_home=$HOME
    HOME=$ext_home
    mkdir -p "$HOME/Library/Application Support/lanjump"
    : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    ext_row=$'100\x1fext-old\x1f1\x1f0\x1f/tmp/old\x1fold\x1fold\x1fzsh'
    functions -c tmuxx _ext_tmuxx
    tmuxx() {
      case $1 in
        list-sessions)
          print -r -- "$ext_row"
          return 0
          ;;
        *) return 0 ;;
      esac
    }
    HAS_TMUX=1
    tmux_state_invalidate
    load_items
    if [[ ${items_id[(Ie)ext-old]} -eq 0 ]]; then
      print -u2 "FAIL refresh/external-old missing ext-old got=${items_id[*]}"
      (( fails++ ))
    fi
    ext_row=$'200\x1fext-fresh\x1f1\x1f0\x1f/tmp/fresh\x1ffresh\x1ffresh\x1fzsh'
    load_items
    if [[ ${items_id[(Ie)ext-old]} -eq 0 || ${items_id[(Ie)ext-fresh]} -ne 0 ]]; then
      print -u2 "FAIL refresh/external-warm still served the new census got=${items_id[*]}"
      (( fails++ ))
    fi
    refresh_external_sessions
    if [[ ${items_id[(Ie)ext-fresh]} -eq 0 || ${items_id[(Ie)ext-old]} -ne 0 ]]; then
      print -u2 "FAIL refresh/external-r got=${items_id[*]}"
      (( fails++ ))
    fi
    functions -c _ext_tmuxx tmuxx
    unset -f _ext_tmuxx
    HAS_TMUX=$ext_has
    HOME=$ext_saved_home
    tmux_state_invalidate
    rm -rf "$ext_home"
  }

  # #463: steady server, no pin left to create. Cold flags, so an earlier
  # test cannot hide calls. LINES is a normal terminal so the first paint's
  # preview counts. Boot reloads settings, so preview on is in the file.
  # Capture returns text, so the empty-pane retry does not.
  {
    local budget_home budget_log budget_saved_home budget_term budget_prog
    local budget_app budget_ct
    local -i budget_n budget_has=$HAS_TMUX
    local -i budget_pk=$prepared_keys budget_pc=$prepared_color
    local -i budget_hooks=$hooks_installed budget_feat=$tm_features_loaded
    local -i budget_lines=${LINES:-0} budget_cols=${COLUMNS:-0}
    budget_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-463-budget.XXXXXX") || return 1
    budget_saved_home=$HOME
    budget_term=${TERM-}
    budget_prog=${TERM_PROGRAM-}
    budget_app=${LANJUMP_GROK_APPEARANCE-}
    budget_ct=${COLORTERM-}
    HOME=$budget_home
    mkdir -p "$HOME/Library/Application Support/lanjump"
    : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    budget_log=$budget_home/tmux.log
    : >"$budget_log"
    prepared_keys=0
    prepared_color=0
    hooks_installed=0
    hooks_tmuxx_src=
    tm_features_loaded=0
    tm_term_queue=()
    _tmux_arr_loaded=()
    _tmux_arr_count=()
    _tmux_feat_vals=()
    _tmux_over_vals=()
    _tmux_term_deduped=0
    tmux_state_invalidate
    pin_cwd_refreshed_gen=-1
    restore_created_names=()
    restore_show_progress=0
    restore_progress_on=0
    HAS_TMUX=1
    LINES=40
    COLUMNS=100
    print -r -- $'open_target auto\nopen_placement window\npreview on\n' \
      >"$HOME/Library/Application Support/lanjump/settings"
    preview_on=1
    functions -c term_lines _budget_term_lines
    functions -c term_cols _budget_term_cols
    term_lines() { print -r -- 40 }
    term_cols() { print -r -- 100 }
    TERM=xterm-ghostty
    TERM_PROGRAM=ghostty
    COLORTERM=truecolor
    LANJUMP_GROK_APPEARANCE=dark
    tmuxx() {
      print -r -- "$*" >>"$budget_log"
      case $1 in
        list-sessions)
          print -r -- $'100\x1fkeep\x1f1\x1f0\x1f/tmp/keep\x1fkeep\x1fkeep\x1fzsh'
          return 0
          ;;
        capture-pane)
          print -r -- 'echo hello'
          return 0
          ;;
        show-options)
          case "$*" in
            *terminal-features*)
              print -r -- 'xterm*:extkeys'
              print -r -- 'xterm-ghostty:RGB'
              ;;
            *terminal-overrides*)
              print -r -- 'xterm-ghostty:Tc'
              ;;
            *status-left-length*) print -r -- 40 ;;
            *default-terminal*) print -r -- tmux-256color ;;
          esac
          return 0
          ;;
        *) return 0 ;;
      esac
    }
    items_id=()
    cursor=1
    picker_boot_before_first_draw >/dev/null
    picker_boot_after_first_draw >/dev/null
    budget_n=$(wc -l <"$budget_log" | tr -d ' ')
    if (( budget_n > 15 )); then
      print -u2 "FAIL budget/boot-tmux-calls got=$budget_n want<=15"
      print -u2 "$(<"$budget_log")"
      (( fails++ ))
    fi

    : >"$budget_log"
    prepared_keys=0
    prepared_color=0
    hooks_installed=0
    hooks_tmuxx_src=
    tm_features_loaded=0
    tm_term_queue=()
    _tmux_arr_loaded=()
    _tmux_arr_count=()
    _tmux_feat_vals=()
    _tmux_over_vals=()
    _tmux_term_deduped=0
    tmux_state_invalidate
    pin_cwd_refreshed_gen=-1
    print_session_list >/dev/null
    budget_n=$(wc -l <"$budget_log" | tr -d ' ')
    if (( budget_n > 6 )); then
      print -u2 "FAIL budget/print-sessions got=$budget_n want<=6"
      print -u2 "$(<"$budget_log")"
      (( fails++ ))
    fi

    : >"$budget_log"
    prepared_keys=0
    prepared_color=0
    hooks_installed=0
    hooks_tmuxx_src=
    tm_features_loaded=0
    tm_term_queue=()
    _tmux_arr_loaded=()
    _tmux_arr_count=()
    _tmux_feat_vals=()
    _tmux_over_vals=()
    _tmux_term_deduped=0
    tmux_state_invalidate
    pin_cwd_refreshed_gen=-1
    has_named_session keep >/dev/null
    budget_n=$(wc -l <"$budget_log" | tr -d ' ')
    if (( budget_n > 6 )); then
      print -u2 "FAIL budget/has-session got=$budget_n want<=6"
      print -u2 "$(<"$budget_log")"
      (( fails++ ))
    fi
    functions -c _budget_term_lines term_lines
    functions -c _budget_term_cols term_cols
    unset -f _budget_term_lines _budget_term_cols
    HOME=$budget_saved_home
    HAS_TMUX=$budget_has
    prepared_keys=$budget_pk
    prepared_color=$budget_pc
    hooks_installed=$budget_hooks
    tm_features_loaded=$budget_feat
    if (( budget_lines > 0 )); then LINES=$budget_lines; else unset LINES; fi
    if (( budget_cols > 0 )); then COLUMNS=$budget_cols; else unset COLUMNS; fi
    if [[ -n $budget_term ]]; then TERM=$budget_term; else unset TERM; fi
    if [[ -n $budget_prog ]]; then TERM_PROGRAM=$budget_prog; else unset TERM_PROGRAM; fi
    if [[ -n $budget_app ]]; then LANJUMP_GROK_APPEARANCE=$budget_app; else unset LANJUMP_GROK_APPEARANCE; fi
    if [[ -n $budget_ct ]]; then COLORTERM=$budget_ct; else unset COLORTERM; fi
    tmux_state_invalidate
    rm -rf "$budget_home"
  }
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  # #426: leftover 0/1 pin must roll tmux back if snapshot rename write fails.
  # Callers (p / n / --pin-session) must not keep pinning the new name.
  local snap426_home snap426_saved_home snap426_tmux snap426_log
  local -i snap426_has_tmux=$HAS_TMUX snap426_st=0
  snap426_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-426.XXXXXX") || return 1
  snap426_saved_home=$HOME
  HOME=$snap426_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  snap426_tmux=$snap426_home/tmux.log
  : >"$snap426_tmux"
  snap_names=(0)
  snap_cwd=([0]=/tmp/zero)
  snap_occupied=([0]=0)
  snap_workspace=([0]=0)
  snap_cmd=([0]=zsh)
  snap_attached=([0]=0)
  save_session_snapshot
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  functions -c save_session_snapshot _snap426_save
  functions -c tmuxx _snap426_tmuxx
  functions -c unique_non_numeric_session_name _snap426_unique
  save_session_snapshot() { return 1 }
  unique_non_numeric_session_name() { REPLY=s-426-leftover }
  tmuxx() {
    print -r -- "$*" >>"$snap426_tmux"
    case $1 in
      has-session) return 1 ;;
      rename-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  HAS_TMUX=1
  snap426_st=0
  pin_named_session 0 >/dev/null || snap426_st=$?
  if (( snap426_st == 0 )); then
    print -u2 "FAIL pin/leftover-snap-write-fail reported success"
    (( fails++ ))
  fi
  snap426_log=$(<"$snap426_tmux")
  if [[ $snap426_log == *'rename-session -t =0 s-426-leftover'* && $snap426_log != *'rename-session -t =s-426-leftover 0'* ]]; then
    print -u2 "FAIL pin/leftover-snap-write-fail tmux left as new got=$(printf %q "$snap426_log")"
    (( fails++ ))
  fi
  functions -c _snap426_save save_session_snapshot
  load_pinned_sessions
  if (( ${#pinned_names} )); then
    print -u2 "FAIL pin/leftover-snap-write-fail still pinned got=${pinned_names[*]}"
    (( fails++ ))
  fi
  load_session_snapshot
  if [[ ${snap_names[(Ie)0]} -eq 0 || ${snap_names[(Ie)s-426-leftover]} -ne 0 ]]; then
    print -u2 "FAIL pin/leftover-snap-write-fail disk snap drifted got=${snap_names[*]}"
    (( fails++ ))
  fi
  functions -c _snap426_tmuxx tmuxx
  functions -c _snap426_unique unique_non_numeric_session_name
  unset -f _snap426_save _snap426_tmuxx _snap426_unique
  HAS_TMUX=$snap426_has_tmux
  HOME=$snap426_saved_home
  rm -rf "$snap426_home"

  # #467: flock waits 5s then skips the write, hooks do not wait, and a
  # dead mkdir lock is reclaimed. Children use a temp dir and never call tmux.
  extract_lock_fn() {
    local file=$1 line
    local -i depth=0 start=0
    while IFS= read -r line; do
      if (( !start )) && [[ $line == 'with_data_file_lock() {' ]]; then
        start=1
      fi
      if (( start )); then
        print -r -- "$line"
        depth+=${#line//[^\{]/}
        depth+=-${#line//[^\}]/}
        (( depth == 0 )) && return 0
      fi
    done <"$file"
    return 1
  }
  local lock467_root lock467_z lock467_p lock467_i
  lock467_root=${_pick_src_file:h:h}
  lock467_z=$(extract_lock_fn "$lock467_root/lib/lanjump.zsh" || true)
  lock467_p=$(extract_lock_fn "$lock467_root/lib/lanjump-pick.zsh" || true)
  lock467_i=$(extract_lock_fn "$lock467_root/install.zsh" || true)
  if [[ -z $lock467_z || $lock467_z != "$lock467_p" || $lock467_p != "$lock467_i" ]]; then
    print -u2 "FAIL lock/same-body host, picker, and install locks differ"
    (( fails++ ))
  fi

  # #482: zsh 5.8 rejects flock -i. Retry without -i, then a delete drops the pin.
  local flock482_home flock482_saved_home flock482_out
  local -i flock482_has_tmux=$HAS_TMUX
  flock482_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-482.XXXXXX") || return 1
  flock482_saved_home=$HOME
  HOME=$flock482_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  unset _LANJUMP_FLOCK_NO_INTERVAL
  zsystem() {
    if [[ $1 == flock && $* == *' -i '* ]]; then
      return 1
    fi
    builtin zsystem "$@"
  }
  if ! add_pin_record stay /tmp/stay || ! add_pin_record later /tmp/later; then
    print -u2 "FAIL lock/zsh58-flock-i pin write failed"
    (( fails++ ))
  fi
  load_pinned_sessions
  if ! pin_record_exists stay || ! pin_record_exists later; then
    print -u2 "FAIL lock/zsh58-flock-i pin missing after write stay=${pinned_names[*]}"
    (( fails++ ))
  fi
  if [[ ${_LANJUMP_FLOCK_NO_INTERVAL:-0} != 1 ]]; then
    print -u2 "FAIL lock/zsh58-flock-i did not remember to skip -i"
    (( fails++ ))
  fi
  functions -c tmuxx _flock482_tmuxx
  functions -c restore_tty _flock482_restore_tty
  functions -c setup_tty _flock482_setup_tty
  functions -c draw _flock482_draw
  functions -c load_items _flock482_load_items
  tmuxx() { return 0 }
  restore_tty() { : }
  setup_tty() { : }
  draw() { : }
  load_items() { : }
  items_kind=(session)
  items_id=(stay)
  items_name=(stay)
  items_att=(0)
  items_pinned=(1)
  cursor=1
  HAS_TMUX=1
  flock482_out=$(prompt_delete <<'EOF'
y

EOF
)
  if [[ $flock482_out == *删除失败* ]]; then
    print -u2 "FAIL lock/zsh58-flock-i delete reported 删除失败 got=$(printf %q "$flock482_out")"
    (( fails++ ))
  fi
  load_pinned_sessions
  if pin_record_exists stay; then
    print -u2 "FAIL lock/zsh58-flock-i deleted pin still on disk"
    (( fails++ ))
  fi
  if ! pin_record_exists later; then
    print -u2 "FAIL lock/zsh58-flock-i dropped an unrelated pin names=${pinned_names[*]}"
    (( fails++ ))
  fi
  unfunction zsystem 2>/dev/null || true
  unset _LANJUMP_FLOCK_NO_INTERVAL
  functions -c _flock482_tmuxx tmuxx
  functions -c _flock482_restore_tty restore_tty
  functions -c _flock482_setup_tty setup_tty
  functions -c _flock482_draw draw
  functions -c _flock482_load_items load_items
  unset -f _flock482_tmuxx _flock482_restore_tty _flock482_setup_tty \
    _flock482_draw _flock482_load_items
  HAS_TMUX=$flock482_has_tmux
  HOME=$flock482_saved_home
  rm -rf "$flock482_home"
  local lock467_src
  lock467_src=$(<"$_pick_src_file")
  if [[ $lock467_src != *'LANJUMP_LOCK_QUIET=1
  run_session_snapshot
  exit 0'* ]]; then
    print -u2 "FAIL lock/snapshot-hook snapshot hook is not quiet"
    (( fails++ ))
  fi
  if [[ $lock467_src != *'LANJUMP_LOCK_QUIET=1
  LANJUMP_LOCK_NONBLOCK=1
  refresh_pin_cwds
  exit 0'* ]]; then
    print -u2 "FAIL lock/pin-hook refresh-pin-cwd is not quiet and nonblocking"
    (( fails++ ))
  fi
  local lock467_draw
  lock467_draw=$(
    COLUMNS=100
    LINES=40
    notice='另一个 lanjump 正在写 pinned-sessions，稍后再试'
    draw
  )
  if [[ $lock467_draw != *'另一个 lanjump 正在写 pinned-sessions，稍后再试'* ]]; then
    print -u2 "FAIL lock/notice-draw list did not show the lock notice"
    (( fails++ ))
  fi

  local lock467_home lock467_saved_home lock467_fn
  local -a lock467_names lock467_pids
  local -i lock467_i2 lock467_w
  lock467_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-pin.XXXXXX") || return 1
  lock467_saved_home=$HOME
  mkdir -p "$lock467_home/Library/Application Support/lanjump"
  HOME=$lock467_home
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  add_pin_record gamma /tmp/gamma
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$lock467_home")"
    print -r -- 'typeset -a pinned_names'
    print -r -- 'typeset -A pinned_cwd pinned_grok'
    for lock467_fn in lanjump_data_dir pinned_sessions_file sanitize_pin_field \
      pin_record_exists load_pinned_sessions replace_file_atomic \
      save_pinned_sessions add_pin_record with_data_file_lock; do
      (( ${+functions[$lock467_fn]} )) && functions "$lock467_fn"
    done
    print -r -- 'LANJUMP_LOCK_WAIT=30'
    print -r -- 'add_pin_record "$1" "/tmp/$1"'
  } >"$lock467_home/add.zsh"
  lock467_pids=()
  for lock467_i2 in {1..8}; do
    /bin/zsh "$lock467_home/add.zsh" "pin-$lock467_i2" &
    lock467_pids+=($!)
  done
  for lock467_w in "${lock467_pids[@]}"; do
    wait $lock467_w || {
      print -u2 "FAIL lock/concurrent-pin writer $lock467_w failed"
      (( fails++ ))
    }
  done
  load_pinned_sessions
  lock467_names=("${pinned_names[@]}")
  HOME=$lock467_saved_home
  for lock467_fn in gamma pin-1 pin-2 pin-3 pin-4 pin-5 pin-6 pin-7 pin-8; do
    if (( ${lock467_names[(Ie)$lock467_fn]} == 0 )); then
      print -u2 "FAIL lock/concurrent-pin lost $lock467_fn names=$(printf %q "${lock467_names[*]}")"
      (( fails++ ))
    fi
  done
  rm -rf "$lock467_home"

  local lock467_snap lock467_a lock467_b
  lock467_snap=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-snap.XXXXXX") || return 1
  HOME=$lock467_snap
  mkdir -p "$HOME/Library/Application Support/lanjump"
  snap_names=(alpha beta gamma)
  snap_cwd=([alpha]=/a [beta]=/b [gamma]=/g)
  snap_occupied=([alpha]=0 [beta]=0 [gamma]=0)
  snap_workspace=([alpha]=0 [beta]=0 [gamma]=0)
  snap_cmd=([alpha]=zsh [beta]=zsh [gamma]=zsh)
  snap_attached=([alpha]=0 [beta]=0 [gamma]=0)
  save_session_snapshot
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset extendedglob typesetsilent'
    print -r -- 'zmodload zsh/datetime'
    print -r -- "HOME=$(printf %q "$lock467_snap")"
    print -r -- 'typeset -a snap_names'
    print -r -- 'typeset -A snap_cwd snap_occupied snap_workspace snap_cmd snap_attached'
    for lock467_fn in lanjump_data_dir session_snapshot_file sanitize_pin_field \
      _commit_snap_record load_session_snapshot replace_file_atomic \
      save_session_snapshot rename_snap_record with_data_file_lock; do
      (( ${+functions[$lock467_fn]} )) && functions "$lock467_fn"
    done
    print -r -- 'LANJUMP_LOCK_WAIT=30'
    print -r -- 'rename_snap_record "$1" "$2"'
  } >"$lock467_snap/rename.zsh"
  /bin/zsh "$lock467_snap/rename.zsh" alpha alpha-2 &
  lock467_a=$!
  /bin/zsh "$lock467_snap/rename.zsh" beta beta-2 &
  lock467_b=$!
  wait $lock467_a || {
    print -u2 "FAIL lock/concurrent-snap alpha rename failed"
    (( fails++ ))
  }
  wait $lock467_b || {
    print -u2 "FAIL lock/concurrent-snap beta rename failed"
    (( fails++ ))
  }
  HOME=$lock467_snap
  load_session_snapshot
  if [[ ${snap_names[(Ie)alpha-2]} -eq 0 || ${snap_names[(Ie)beta-2]} -eq 0 || ${snap_names[(Ie)gamma]} -eq 0 ]]; then
    print -u2 "FAIL lock/concurrent-snap lost a record names=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${snap_names[(Ie)alpha]} -ne 0 || ${snap_names[(Ie)beta]} -ne 0 ]]; then
    print -u2 "FAIL lock/concurrent-snap left an old name names=${snap_names[*]}"
    (( fails++ ))
  fi
  HOME=$lock467_saved_home
  rm -rf "$lock467_snap"

  local lock467_dir lock467_dest lock467_holder lock467_ready
  # Product default stays 5s (LANJUMP_LOCK_WAIT:-5). The suite times the same
  # flock -t path at 0.5s so install.zsh --selftest stays under #461's minute.
  if [[ ${functions[with_data_file_lock]} != *'LANJUMP_LOCK_WAIT:-5'* ]]; then
    print -u2 "FAIL lock/default-wait product timeout is not 5s"
    (( fails++ ))
  fi
  lock467_dir=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-flock.XXXXXX") || return 1
  lock467_dest=$lock467_dir/pinned-sessions
  lock467_ready=$lock467_dir/ready
  : >"${lock467_dest}.lock"
  zsh -c "
zmodload zsh/system
zsystem flock -f fd $(printf %q "${lock467_dest}.lock") || exit 9
( builtin print -r -- HOLDER > $(printf %q "$lock467_dest") )
builtin print -r -- ready > $(printf %q "$lock467_ready")
sleep 3
zsystem flock -u fd
" &
  lock467_holder=$!
  for _ in {1..50}; do
    [[ -f $lock467_ready ]] && break
    sleep 0.05
  done
  if [[ ! -f $lock467_ready ]]; then
    print -u2 "FAIL lock/flock-holder did not acquire"
    (( fails++ ))
    kill -9 $lock467_holder 2>/dev/null || true
    wait $lock467_holder 2>/dev/null || true
  else
    {
      print -r -- 'emulate -L zsh'
      print -r -- 'setopt no_unset'
      print -r -- 'zmodload zsh/datetime'
      functions with_data_file_lock
      print -r -- "dest=$(printf %q "$lock467_dest")"
      print -r -- 'write_body() { builtin print -r -- "$1" >"$dest.try" }'
      print -r -- 'LANJUMP_LOCK_WAIT=0.5'
      print -r -- 'start=$EPOCHREALTIME'
      print -r -- 'with_data_file_lock "$dest" write_body WAITER'
      print -r -- 'st1=$?'
      print -r -- 'mid=$EPOCHREALTIME'
      print -r -- 'with_data_file_lock "$dest" write_body WAITER2'
      print -r -- 'st2=$?'
      print -r -- 'end=$EPOCHREALTIME'
      print -r -- 'print -r -- "st1=$st1"'
      print -r -- 'print -r -- "st2=$st2"'
      print -r -- 'print -r -- "first=$(( mid - start ))"'
      print -r -- 'print -r -- "second=$(( end - mid ))"'
    } >"$lock467_dir/waiter.zsh"
    {
      print -r -- 'emulate -L zsh'
      print -r -- 'setopt no_unset'
      print -r -- 'zmodload zsh/datetime'
      functions with_data_file_lock
      print -r -- "dest=$(printf %q "$lock467_dest")"
      print -r -- 'pick_interactive=1'
      print -r -- 'LANJUMP_LOCK_WAIT=0.5'
      print -r -- 'start=$EPOCHREALTIME'
      print -r -- 'with_data_file_lock "$dest" builtin print -r -- UI_BODY'
      print -r -- 'st=$?'
      print -r -- 'end=$EPOCHREALTIME'
      print -r -- 'print -r -- "st=$st"'
      print -r -- 'print -r -- "elapsed=$(( end - start ))"'
      print -r -- 'print -r -- "notice=${notice:-}"'
    } >"$lock467_dir/ui.zsh"
    {
      print -r -- 'emulate -L zsh'
      print -r -- 'setopt no_unset'
      print -r -- 'zmodload zsh/datetime'
      functions with_data_file_lock
      print -r -- "dest=$(printf %q "$lock467_dest")"
      print -r -- 'LANJUMP_LOCK_NONBLOCK=1'
      print -r -- 'LANJUMP_LOCK_QUIET=1'
      print -r -- 'start=$EPOCHREALTIME'
      print -r -- 'with_data_file_lock "$dest" builtin print -r -- NB_BODY'
      print -r -- 'st=$?'
      print -r -- 'end=$EPOCHREALTIME'
      print -r -- 'print -r -- "st=$st"'
      print -r -- 'print -r -- "elapsed=$(( end - start ))"'
      print -r -- 'print -r -- "notice=${notice:-}"'
    } >"$lock467_dir/nb.zsh"
    /bin/zsh "$lock467_dir/waiter.zsh" >"$lock467_dir/waiter.out" 2>"$lock467_dir/waiter.err" &
    lock467_a=$!
    /bin/zsh "$lock467_dir/ui.zsh" >"$lock467_dir/ui.out" 2>"$lock467_dir/ui.err" &
    lock467_b=$!
    /bin/zsh "$lock467_dir/nb.zsh" >"$lock467_dir/nb.out" 2>"$lock467_dir/nb.err" &
    lock467_w=$!
    wait $lock467_a || true
    wait $lock467_b || true
    wait $lock467_w || true
    local lock467_line lock467_st1 lock467_st2 lock467_first lock467_second
    local lock467_ust lock467_uelapsed lock467_unotice
    local lock467_nst lock467_nelapsed lock467_nnotice
    lock467_st1=0 lock467_st2=0 lock467_first=0 lock467_second=0
    while IFS= read -r lock467_line; do
      case $lock467_line in
        st1=*) lock467_st1=${lock467_line#st1=} ;;
        st2=*) lock467_st2=${lock467_line#st2=} ;;
        first=*) lock467_first=${lock467_line#first=} ;;
        second=*) lock467_second=${lock467_line#second=} ;;
      esac
    done <"$lock467_dir/waiter.out"
    if [[ $lock467_st1 != 2 || $lock467_st2 == 0 ]]; then
      print -u2 "FAIL lock/flock-timeout status st1=$lock467_st1 st2=$lock467_st2"
      (( fails++ ))
    fi
    if (( lock467_first < 0.4 || lock467_first > 1.0 )); then
      print -u2 "FAIL lock/flock-timeout first wait ${lock467_first}s"
      (( fails++ ))
    fi
    if (( lock467_second > 0.4 )); then
      print -u2 "FAIL lock/flock-timeout second wait ${lock467_second}s"
      (( fails++ ))
    fi
    if [[ $(<"$lock467_dir/waiter.err") != '另一个 lanjump 正在写 pinned-sessions，稍后再试' ]]; then
      print -u2 "FAIL lock/flock-notice stderr=$(printf %q "$(<"$lock467_dir/waiter.err")")"
      (( fails++ ))
    fi
    if [[ -f $lock467_dest.try ]]; then
      print -u2 "FAIL lock/flock-timeout wrote during the wait"
      (( fails++ ))
    fi
    if [[ $(<"$lock467_dest") != HOLDER ]]; then
      print -u2 "FAIL lock/flock-timeout disturbed holder file=$(printf %q "$(<"$lock467_dest")")"
      (( fails++ ))
    fi
    lock467_ust=0 lock467_uelapsed=0 lock467_unotice=
    while IFS= read -r lock467_line; do
      case $lock467_line in
        st=*) lock467_ust=${lock467_line#st=} ;;
        elapsed=*) lock467_uelapsed=${lock467_line#elapsed=} ;;
        notice=*) lock467_unotice=${lock467_line#notice=} ;;
      esac
    done <"$lock467_dir/ui.out"
    if [[ $lock467_ust == 0 || $lock467_unotice != '另一个 lanjump 正在写 pinned-sessions，稍后再试' ]]; then
      print -u2 "FAIL lock/interactive-notice st=$lock467_ust notice=$(printf %q "$lock467_unotice")"
      (( fails++ ))
    fi
    if (( lock467_uelapsed < 0.4 || lock467_uelapsed > 1.2 )); then
      print -u2 "FAIL lock/interactive-notice waited ${lock467_uelapsed}s"
      (( fails++ ))
    fi
    if [[ -s $lock467_dir/ui.err ]]; then
      print -u2 "FAIL lock/interactive-notice wrote stderr=$(printf %q "$(<"$lock467_dir/ui.err")")"
      (( fails++ ))
    fi
    lock467_nst=0 lock467_nelapsed=0 lock467_nnotice=x
    while IFS= read -r lock467_line; do
      case $lock467_line in
        st=*) lock467_nst=${lock467_line#st=} ;;
        elapsed=*) lock467_nelapsed=${lock467_line#elapsed=} ;;
        notice=*) lock467_nnotice=${lock467_line#notice=} ;;
      esac
    done <"$lock467_dir/nb.out"
    if [[ $lock467_nst == 0 || -n $lock467_nnotice || $lock467_nnotice == x ]]; then
      print -u2 "FAIL lock/nonblock st=$lock467_nst notice=$(printf %q "$lock467_nnotice")"
      (( fails++ ))
    fi
    if (( lock467_nelapsed > 0.5 )); then
      print -u2 "FAIL lock/nonblock waited ${lock467_nelapsed}s"
      (( fails++ ))
    fi
    if [[ -s $lock467_dir/nb.err ]]; then
      print -u2 "FAIL lock/nonblock wrote stderr=$(printf %q "$(<"$lock467_dir/nb.err")")"
      (( fails++ ))
    fi
    if [[ $(<"$lock467_dir/nb.out") == *NB_BODY* || $(<"$lock467_dir/ui.out") == *UI_BODY* ]]; then
      print -u2 "FAIL lock/held-lock ran the skipped write"
      (( fails++ ))
    fi
    kill -9 $lock467_holder 2>/dev/null || true
    wait $lock467_holder 2>/dev/null || true
  fi
  rm -rf "$lock467_dir"

  local lock467_md lock467_mpid
  lock467_md=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-mkdir.XXXXXX") || return 1
  {
    print -r -- 'emulate -L zsh'
    print -r -- 'setopt no_unset'
    print -r -- 'zmodload zsh/datetime'
    print -r -- 'zmodload zsh/system'
    print -r -- 'disable zsystem'
    print -r -- 'zsystem() { return 1 }'
    functions with_data_file_lock
    print -r -- "dest=$(printf %q "$lock467_md/target")"
    print -r -- 'mode=${1:-}'
    print -r -- 'if [[ $mode == hold ]]; then'
    print -r -- '  with_data_file_lock "$dest" sleep 30'
    print -r -- '  exit 0'
    print -r -- 'fi'
    print -r -- 'if [[ $mode == probe ]]; then'
    print -r -- '  LANJUMP_LOCK_NONBLOCK=1'
    print -r -- '  LANJUMP_LOCK_QUIET=1'
    print -r -- '  with_data_file_lock "$dest" builtin print -r -- PROBE'
    print -r -- '  print -r -- "st=$?"'
    print -r -- '  exit 0'
    print -r -- 'fi'
    print -r -- 'if [[ $mode == stale ]]; then'
    print -r -- '  mkdir -p "${dest}.lock.d"'
    print -r -- '  touch -t 202001010000 "${dest}.lock.d"'
    print -r -- 'fi'
    print -r -- 'start=$EPOCHREALTIME'
    print -r -- 'with_data_file_lock "$dest" builtin print -r -- NEXT_OK'
    print -r -- 'st=$?'
    print -r -- 'end=$EPOCHREALTIME'
    print -r -- 'print -r -- "st=$st"'
    print -r -- 'print -r -- "elapsed=$(( end - start ))"'
  } >"$lock467_md/mkdir.zsh"
  /bin/zsh "$lock467_md/mkdir.zsh" hold &
  lock467_holder=$!
  for _ in {1..50}; do
    [[ -f $lock467_md/target.lock.d/pid ]] && break
    sleep 0.02
  done
  if [[ ! -f $lock467_md/target.lock.d/pid ]]; then
    print -u2 "FAIL lock/mkdir-pid holder wrote no pid"
    (( fails++ ))
    kill -9 $lock467_holder 2>/dev/null || true
    wait $lock467_holder 2>/dev/null || true
  else
    lock467_mpid=$(<"$lock467_md/target.lock.d/pid")
    /bin/zsh "$lock467_md/mkdir.zsh" probe >"$lock467_md/probe.out" 2>"$lock467_md/probe.err"
    if [[ $(<"$lock467_md/probe.out") == *'st=0'* || ! -f $lock467_md/target.lock.d/pid ]]; then
      print -u2 "FAIL lock/mkdir-live nonblock stole a live lock out=$(printf %q "$(<"$lock467_md/probe.out")")"
      (( fails++ ))
    fi
    if kill -0 $lock467_holder 2>/dev/null; then
      :
    else
      print -u2 "FAIL lock/mkdir-live holder died during probe"
      (( fails++ ))
    fi
    kill -9 $lock467_holder 2>/dev/null || true
    wait $lock467_holder 2>/dev/null || true
    /bin/zsh "$lock467_md/mkdir.zsh" next >"$lock467_md/next.out" 2>"$lock467_md/next.err"
    lock467_nst=0 lock467_nelapsed=0
    while IFS= read -r lock467_line; do
      case $lock467_line in
        st=*) lock467_nst=${lock467_line#st=} ;;
        elapsed=*) lock467_nelapsed=${lock467_line#elapsed=} ;;
        NEXT_OK) ;;
      esac
    done <"$lock467_md/next.out"
    if [[ $lock467_nst != 0 || $(<"$lock467_md/next.out") != *NEXT_OK* ]]; then
      print -u2 "FAIL lock/mkdir-reclaim status=$lock467_nst out=$(printf %q "$(<"$lock467_md/next.out")")"
      (( fails++ ))
    fi
    if (( lock467_nelapsed > 1 )); then
      print -u2 "FAIL lock/mkdir-reclaim took ${lock467_nelapsed}s after kill -9 of $lock467_mpid"
      (( fails++ ))
    fi
    if [[ -d $lock467_md/target.lock.d ]]; then
      print -u2 "FAIL lock/mkdir-reclaim left the lock dir"
      (( fails++ ))
    fi
    /bin/zsh "$lock467_md/mkdir.zsh" stale >"$lock467_md/stale.out"
    if [[ $(<"$lock467_md/stale.out") != *'st=0'* || $(<"$lock467_md/stale.out") != *NEXT_OK* ]]; then
      print -u2 "FAIL lock/mkdir-stale out=$(printf %q "$(<"$lock467_md/stale.out")")"
      (( fails++ ))
    fi
  fi
  rm -rf "$lock467_md"

  local lock467_se
  lock467_se=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-sete.XXXXXX") || return 1
  {
    print -r -- 'set -euo pipefail'
    functions with_data_file_lock
    print -r -- "dest=$(printf %q "$lock467_se/hosts")"
    print -r -- ': >"$dest.lock"'
    print -r -- "zsh -c 'zmodload zsh/system; zsystem flock -f fd $(printf %q "$lock467_se/hosts.lock") || exit 9; sleep 3; zsystem flock -u fd' &"
    print -r -- 'hp=$!'
    print -r -- 'sleep 0.05'
    print -r -- 'LANJUMP_LOCK_WAIT=0.5'
    print -r -- 'st=0'
    print -r -- 'with_data_file_lock "$dest" builtin print -r -- RAN || st=$?'
    print -r -- 'print -r -- "continued st=$st"'
    print -r -- 'kill -9 $hp 2>/dev/null || true'
    print -r -- 'wait $hp 2>/dev/null || true'
  } >"$lock467_se/sete.zsh"
  /bin/zsh "$lock467_se/sete.zsh" >"$lock467_se/out" 2>"$lock467_se/err" || {
    print -u2 "FAIL lock/install-errexit script aborted err=$(printf %q "$(<"$lock467_se/err")")"
    (( fails++ ))
  }
  if [[ $(<"$lock467_se/out") != *'continued st=2'* ]]; then
    print -u2 "FAIL lock/install-errexit out=$(printf %q "$(<"$lock467_se/out")") err=$(printf %q "$(<"$lock467_se/err")")"
    (( fails++ ))
  fi
  if [[ $(<"$lock467_se/err") != *'另一个 lanjump 正在写 hosts，稍后再试'* ]]; then
    print -u2 "FAIL lock/install-notice err=$(printf %q "$(<"$lock467_se/err")")"
    (( fails++ ))
  fi
  rm -rf "$lock467_se"

  # Census is read before the pin and snapshot locks. tmuxx inside either lock is a failure.
  local lock467_hold_home lock467_hold_saved
  local -i lock467_hold_hits=0 lock467_hold_has=$HAS_TMUX lock467_hold_gen=$pin_cwd_refreshed_gen
  lock467_hold_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-467-hold.XXXXXX") || return 1
  lock467_hold_saved=$HOME
  functions -c tmuxx _lock467_hold_tmuxx
  tmuxx() {
    if (( ${_LANJUMP_PIN_LOCKED:-0} || ${_LANJUMP_SNAP_LOCKED:-0} )); then
      lock467_hold_hits+=1
    fi
    case $1 in
      list-sessions)
        print -r -- $'100\x1fdemo\x1f1\x1f0\x1f/tmp/demo\x1fdemo\x1ftitle\x1fzsh'
        return 0
        ;;
    esac
    return 0
  }
  HAS_TMUX=1
  HOME=$lock467_hold_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  add_pin_record demo /old
  tmux_state_invalidate
  pin_cwd_refreshed_gen=-1
  refresh_pin_cwds
  load_pinned_sessions
  if [[ ${pinned_cwd[demo]:-} != /tmp/demo ]]; then
    print -u2 "FAIL lock/no-tmux-held pin cwd=$(printf %q "${pinned_cwd[demo]:-}")"
    (( fails++ ))
  fi
  snapshot_live_sessions
  mark_snapshot_occupied demo
  load_session_snapshot
  if [[ ${snap_names[(Ie)demo]} -eq 0 || ${snap_cmd[demo]:-} != zsh || ${snap_occupied[demo]:-} != 1 ]]; then
    print -u2 "FAIL lock/no-tmux-held snap names=${snap_names[*]} cmd=${snap_cmd[demo]:-} occ=${snap_occupied[demo]:-}"
    (( fails++ ))
  fi
  if (( lock467_hold_hits != 0 )); then
    print -u2 "FAIL lock/no-tmux-held tmuxx during lock count=$lock467_hold_hits"
    (( fails++ ))
  fi
  functions -c _lock467_hold_tmuxx tmuxx
  unset -f _lock467_hold_tmuxx
  tmux_state_invalidate
  HAS_TMUX=$lock467_hold_has
  pin_cwd_refreshed_gen=$lock467_hold_gen
  HOME=$lock467_hold_saved
  rm -rf "$lock467_hold_home"
  unset -f extract_lock_fn

  # #485: $(fn) strips every trailing newline. short_path and short_command_name
  # still print those bytes. useful_summary strips the command name the way
  # $(short_command_name) did, and the list/snapshot/restore readers strip too.
  {
    local p485_home p485_saved_home p485_file p485_got p485_scope
    local -a p485_roots
    local -i p485_st p485_has=$HAS_TMUX p485_filter=$filter_on
    p485_saved_home=$HOME
    p485_roots=("${project_roots[@]}")
    p485_scope=$view_scope
    p485_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-485.XXXXXX") || return 1
    p485_file=$p485_home/out
    HOME=$p485_home
    mkdir -p "$HOME/Library/Application Support/lanjump"
    p485_capture() {
      local fn=$1
      shift
      "$fn" "$@" >"$p485_file"
      p485_st=$?
      IFS= read -r -d '' p485_got <"$p485_file" || true
    }
    REPLY=sentinel
    p485_capture short_path $'/trailing\n'
    expect fmt/path-nl-st 0 "$p485_st"
    expect fmt/path-nl-bytes $'/trailing\n\n' "$p485_got"
    expect fmt/path-nl-reply sentinel "$REPLY"
    REPLY=sentinel
    p485_capture short_command_name $'/trailing\n'
    expect fmt/cmd-nl-st 0 "$p485_st"
    expect fmt/cmd-nl-bytes $'trailing\n\n' "$p485_got"
    expect fmt/cmd-nl-reply sentinel "$REPLY"
    REPLY=sentinel
    p485_capture short_command_name
    expect fmt/cmd-none-st 0 "$p485_st"
    expect fmt/cmd-none-bytes $'\n' "$p485_got"
    expect fmt/cmd-none-reply sentinel "$REPLY"
    REPLY=sentinel
    p485_capture useful_summary 'ignored' $'/trailing\n' ''
    expect fmt/summary-nl-st 0 "$p485_st"
    expect fmt/summary-nl-bytes $'trailing\n' "$p485_got"
    expect fmt/summary-nl-reply sentinel "$REPLY"
    p485_capture useful_summary 'ignored' $'/bin/grok-1\n\n' zsh
    expect fmt/summary-grok-nl-bytes $'grok\n' "$p485_got"
    p485_capture useful_summary 'ignored' $'/\n' $'title\n'
    expect fmt/summary-wname-nl-bytes $'title\n\n' "$p485_got"
    expect fmt/summary-nl-sub trailing "$(useful_summary ignored $'/trailing\n' '')"

    pinned_names=(nl 4 bmx-bot)
    pinned_cwd=()
    snap_cwd=()
    pinned_cwd[nl]=$'/opt/pin\n\n'
    pinned_cwd[4]=/tmp/four
    collect_restore_names
    expect fmt/restore-nl-names nl "${restore_names[*]}"
    expect fmt/restore-nl-cwd /opt/pin "${restore_cwd[nl]}"
    if [[ ${restore_cwd[nl]} == *$'\n'* ]]; then
      print -u2 "FAIL fmt/restore-nl-cwd kept a newline"
      (( fails++ ))
    fi

    functions -c tmux_state_load _p485_state_load
    tmux_state_load() {
      tm_names=(nl)
      tm_live=([nl]=1)
      tm_path=([nl]=$'/trailing\n')
      tm_cmd=([nl]=$'/trailing\n')
      tm_att=([nl]=0)
      tm_activity=([nl]=100)
      tm_windows=([nl]=1)
      tm_wname=([nl]=zsh)
      tm_title=([nl]=title)
      tm_server_up=1
      tm_list_rows=1
      tm_state_dirty=0
      (( ++tm_state_gen ))
      tm_state_src=${functions[tmuxx]:-}
    }
    HAS_TMUX=1
    filter_on=0
    view_scope=all
    : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    print -r -- $'name nl\ncwd /opt/stay\n\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
    tmux_state_invalidate
    pin_cwd_refreshed_gen=-1
    load_items
    local -i p485_i p485_found=0
    for (( p485_i = 1; p485_i <= ${#items_id}; p485_i++ )); do
      [[ ${items_id[$p485_i]} == nl ]] || continue
      p485_found=1
      expect fmt/list-nl-path /trailing "${items_path[$p485_i]}"
      expect fmt/list-nl-summary trailing "${items_summary[$p485_i]}"
      if [[ ${items_path[$p485_i]} == *$'\n'* || ${items_summary[$p485_i]} == *$'\n'* ]]; then
        print -u2 "FAIL fmt/list-nl kept a newline path=$(printf %q "${items_path[$p485_i]}") summary=$(printf %q "${items_summary[$p485_i]}")"
        (( fails++ ))
      fi
    done
    if (( ! p485_found )); then
      print -u2 "FAIL fmt/list-nl missing session got=${items_id[*]}"
      (( fails++ ))
    fi
    expect fmt/snap-nl-cwd /trailing "${snap_cwd[nl]:-}"
    if [[ ${snap_cwd[nl]:-} == *$'\n'* ]]; then
      print -u2 "FAIL fmt/snap-nl-cwd kept a newline"
      (( fails++ ))
    fi

    functions -c _p485_state_load tmux_state_load
    unset -f _p485_state_load p485_capture
    HAS_TMUX=$p485_has
    filter_on=$p485_filter
    view_scope=$p485_scope
    HOME=$p485_saved_home
    project_roots=("${p485_roots[@]}")
    unset 'pinned_cwd[nl]' 'snap_cwd[nl]'
    pinned_names=()
    tmux_state_invalidate
    rm -rf "$p485_home"
  }

  if (( fails )); then
    print -u2 "pick-selftest: $fails failed"
    return 1
  fi
  print "ok pick"
  return 0
}
