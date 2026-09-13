# Sourced by lanjump-pick.zsh --pick-selftest.
# Expects dw, fit_right, fit_left, fit_head_tail, padw, compute_layout, fmt_session_row, draw,
# sort_session_items, toggle_sort_mode, filter_session_items,
# toggle_session_filter, save_session_filter, load_session_filter,
# bulk_idle_unpinned_names, delete_idle_unpinned_sessions,
# forget_killed_session, drop_snap_record, rename_snap_record,
# session_delete_needs_pin_warning, pin_delete_warning_text,
# rename_pin_record, restore_pinned_sessions, numeric_session_name,
# collect_restore_names, should_restore_sessions, restore_saved_sessions,
# maybe_restore_sessions, print_pinned_names, print_workspace_names,
# has_named_session, ensure_named_session_for_attach, print_recent_names,
# print_session_list,
# ghostty_restore_available, ghostty_osascript_for_sessions,
# terminal_osascript_for_sessions,
# attaching_remote_host, attach_spec_for, attach_command_for, open_named_tabs,
# workspace_restore_prompt_text, short_command_name, useful_summary,
# load_settings, save_settings, cycle_setting, effective_open_target,
# picker_open_mode, restore_pick_finish,
# resolve_session_cwd, picker_boot_before_first_draw, picker_boot_after_first_draw,
# preview_is_grok, preview_line_is_tool, preview_line_is_model,
# preview_grok_lines, preview_generic_lines, preview_select_lines,
# session_name_invalid, restore_csi_key, restore_plain_key, restore_read_key, restore_tty,
# draw_on_winch,
# resume_prompt_choice, attach_command_for, new_session_flag_invalid, prompt_new,
# prompt_new_pin_cwd, create_named_session, unique_non_numeric_session_name,
# ensure_pinnable_session_name, pin_named_session, toggle_session_pin, read_key, settings_input_read,
# PENDING_KEY.

_pick_src_file=${0:A:h}/lanjump-pick.zsh

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
  _fmt_header
  if [[ $REPLY != *程序* ]]; then
    print -u2 "FAIL header/program missing 程序 got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi
  if [[ $REPLY == *摘要* ]]; then
    print -u2 "FAIL header/program still 摘要 got=$(printf %q "$REPLY")"
    (( fails++ ))
  fi
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
  expect snap/rename-live-keeps-grok grok-1.0.24-mac "${snap_cmd[new]:-}"
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
  expect restore/collect-names 'missing still-live lanjump sysmtn' "${restore_names[*]}"
  expect restore/collect-cwd-occupied /proj/lanjump "${restore_cwd[lanjump]}"
  expect restore/collect-cwd-pinned /tmp/missing-cwd "${restore_cwd[missing]}"
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
  if [[ $restore_log != *'new-session -d -s lanjump -c /proj/lanjump'* ]]; then
    print -u2 "FAIL restore/occupied missing lanjump got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s sysmtn -c /proj/sysmtn'* ]]; then
    print -u2 "FAIL restore/occupied missing sysmtn got=$(printf %q "$restore_log")"
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
  if ! should_restore_sessions; then
    print -u2 "FAIL snap/leftover-gate should restore demo"
    (( fails++ ))
  fi
  snapshot_live_sessions
  load_session_snapshot
  if [[ ${snap_names[(Ie)demo]} -eq 0 ]]; then
    print -u2 "FAIL snap/leftover-keep dropped demo got=${snap_names[*]}"
    (( fails++ ))
  fi
  expect snap/leftover-keep-cwd /tmp/demo "${snap_cwd[demo]:-}"
  expect snap/leftover-keep-cmd zsh "${snap_cmd[demo]:-}"
  if [[ ${snap_names[(Ie)leftover]} -eq 0 ]]; then
    print -u2 "FAIL snap/leftover-keep missing leftover got=${snap_names[*]}"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL snap/leftover-restore missing demo got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  setup_leftover_live
  load_items
  load_session_snapshot
  if [[ ${snap_names[(Ie)demo]} -eq 0 ]]; then
    print -u2 "FAIL load/leftover-keep dropped demo got=${snap_names[*]}"
    (( fails++ ))
  fi
  if [[ ${items_id[(Ie)leftover]} -eq 0 ]]; then
    print -u2 "FAIL load/leftover-paint missing leftover got=${items_id[*]}"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_saved_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL load/leftover-restore missing demo got=$(printf %q "$restore_log")"
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

  # #137: pins/--print-pinned must restore like work/list before listing pins.
  if [[ ${functions[print_pinned_names]:-} != *should_restore_sessions* ]]; then
    print -u2 "FAIL pin/print missing should_restore_sessions got=$(printf %q "${functions[print_pinned_names]:-}")"
    (( fails++ ))
  fi
  if [[ ${functions[print_pinned_names]:-} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL pin/print missing restore_saved_sessions got=$(printf %q "${functions[print_pinned_names]:-}")"
    (( fails++ ))
  fi

  setup_partial_pins
  got=$(print_pinned_names)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-pins missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s lj-pin-keep'* ]]; then
    print -u2 "FAIL pin/restore-partial-pins recreated live pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL pin/restore-partial-pins restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect pin/restore-partial-pins-names $'lj-pin-keep\nlj-pin-gone' "$got"

  # #137: kill-server / empty tmux restores pin keep and unpinned demo, prints only keep.
  : >"$tmux_log"
  mock_live=()
  did_restore=0
  snap_names=(keep demo)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  snap_cwd[keep]=/tmp/keep
  snap_cwd[demo]=/tmp/demo
  snap_occupied[keep]=1
  snap_occupied[demo]=1
  snap_workspace[keep]=1
  snap_workspace[demo]=1
  snap_attached[keep]=$EPOCHSECONDS
  snap_attached[demo]=$EPOCHSECONDS
  save_session_snapshot
  print -r -- $'name keep\ncwd /tmp/keep\n' >"$HOME/Library/Application Support/lanjump/pinned-sessions"
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
  got=$(print_pinned_names)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s keep -c /tmp/keep'* ]]; then
    print -u2 "FAIL pin/print-empty missing keep new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL pin/print-empty missing demo new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $got != *keep* ]]; then
    print -u2 "FAIL pin/print-empty missing keep got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got == *demo* ]]; then
    print -u2 "FAIL pin/print-empty listed unpinned workspace got=$(printf %q "$got")"
    (( fails++ ))
  fi
  expect pin/print-empty-names keep "$got"

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
  got=$(print_pinned_names)
  if [[ $got == *bmx-demo* ]]; then
    print -u2 "FAIL pin/print-skip-foreign listed bmx-demo got=$(printf %q "$got")"
    (( fails++ ))
  fi
  expect pin/print-skip-foreign-names keep "$got"
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
  if [[ $got != *lj-pin-keep* ]]; then
    print -u2 "FAIL pin/restore-partial-work missing live pin got=$(printf %q "$got")"
    (( fails++ ))
  fi
  if [[ $got != *lj-pin-gone* ]]; then
    print -u2 "FAIL pin/restore-partial-work missing restored pin got=$(printf %q "$got")"
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
  if [[ $restore_log != *'new-session -d -s ws-empty -c /tmp/ws-empty'* ]]; then
    print -u2 "FAIL work/print-empty missing ws-empty new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect work/print-empty-names ws-empty "$got"

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
  if (( st != 0 )); then
    print -u2 "FAIL has-session/empty-demo status got=$st want 0"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL has-session/empty-demo missing demo new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s other -c /tmp/other'* ]]; then
    print -u2 "FAIL has-session/empty-demo skipped other new-session got=$(printf %q "$restore_log")"
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
  if (( st != 0 )); then
    print -u2 "FAIL attach/empty-demo status got=$st want 0 err=$(printf %q "$err")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL attach/empty-demo missing demo new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s other -c /tmp/other'* ]]; then
    print -u2 "FAIL attach/empty-demo skipped other new-session got=$(printf %q "$restore_log")"
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

  # #122: last/--print-recent must restore like work/go before listing.
  if [[ ${functions[print_recent_names]:-} != *should_restore_sessions* ]]; then
    print -u2 "FAIL recent/print missing should_restore_sessions got=$(printf %q "${functions[print_recent_names]:-}")"
    (( fails++ ))
  fi
  if [[ ${functions[print_recent_names]:-} != *restore_saved_sessions* ]]; then
    print -u2 "FAIL recent/print missing restore_saved_sessions got=$(printf %q "${functions[print_recent_names]:-}")"
    (( fails++ ))
  fi

  local -A mock_activity
  recent_list_tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      list-sessions)
        (( ${#mock_live} )) || return 1
        if [[ $* == *session_activity* ]]; then
          local k
          for k in ${(k)mock_live}; do
            print -r -- "${mock_activity[$k]:-1}"$'\t'"$k"
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
  mock_activity=()
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
  mock_activity[demo]=200
  mock_activity[other]=100
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() { recent_list_tmuxx "$@" }
  got=$(print_recent_names 5)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL recent/print-empty missing demo new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'new-session -d -s other -c /tmp/other'* ]]; then
    print -u2 "FAIL recent/print-empty missing other new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect recent/print-empty-names $'demo\nother' "$got"

  # Newest-activity first, up to 5, after restore.
  : >"$tmux_log"
  mock_live=()
  mock_activity=()
  did_restore=0
  snap_names=(r1 r2 r3 r4 r5 r6)
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  local rn
  for rn in r1 r2 r3 r4 r5 r6; do
    snap_cwd[$rn]=/tmp/$rn
    snap_occupied[$rn]=1
    snap_workspace[$rn]=1
    snap_attached[$rn]=$EPOCHSECONDS
  done
  mock_activity[r1]=100
  mock_activity[r2]=200
  mock_activity[r3]=300
  mock_activity[r4]=400
  mock_activity[r5]=500
  mock_activity[r6]=600
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() { recent_list_tmuxx "$@" }
  got=$(print_recent_names 5)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s r6 -c /tmp/r6'* ]]; then
    print -u2 "FAIL recent/print-limit missing r6 new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect recent/print-limit-names $'r6\nr5\nr4\nr3\nr2' "$got"

  # #80/#122: anything restoreable already live skips full restore.
  : >"$tmux_log"
  mock_live=()
  mock_activity=()
  mock_live[lj-pin-keep]=1
  mock_live[ws-live]=1
  mock_activity[lj-pin-keep]=300
  mock_activity[lj-pin-gone]=200
  mock_activity[ws-live]=100
  mock_activity[ws-gone]=50
  did_restore=0
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
  tmuxx() { recent_list_tmuxx "$@" }
  got=$(print_recent_names 5)
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s lj-pin-gone -c /tmp/lj-pin-gone'* ]]; then
    print -u2 "FAIL recent/print-partial missing lj-pin-gone got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s ws-gone'* ]]; then
    print -u2 "FAIL recent/print-partial restored unpinned workspace got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'new-session -d -s lj-pin-keep'* ]]; then
    print -u2 "FAIL recent/print-partial recreated live pin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  expect recent/print-partial-names $'lj-pin-keep\nlj-pin-gone\nws-live' "$got"

  # Nothing restoreable and no live sessions: still empty.
  : >"$tmux_log"
  mock_live=()
  mock_activity=()
  snap_names=()
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  save_session_snapshot
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  tmuxx() { recent_list_tmuxx "$@" }
  if print_recent_names 5 >/dev/null; then
    print -u2 "FAIL recent/print-none listed names"
    (( fails++ ))
  fi
  restore_log=$(<"$tmux_log")
  if [[ $restore_log == *'new-session -d -s '* ]]; then
    print -u2 "FAIL recent/print-none restored sessions got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  # #134: list/--print-sessions must restore like last/work before listing.
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
  if [[ $restore_log != *'new-session -d -s demo -c /tmp/demo'* ]]; then
    print -u2 "FAIL list/print-empty missing demo new-session got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $got != *demo* ]]; then
    print -u2 "FAIL list/print-empty missing demo got=$(printf %q "$got")"
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
  expect ghostty/prompt $'工作区：lanjump、sysmtn\n1  打开窗口；能续的续上，其余进空 shell\n2  打开窗口，全部只要空 shell\n回车  先不打开' "$(workspace_restore_prompt_text lanjump sysmtn)"
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
  # #127: Terminal `do script` returns a tab; later sessions must target that tab's window.
  script=$(terminal_osascript_for_sessions a b)
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach a'* ]]; then
    print -u2 "FAIL terminal/script missing attach a got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach b'* ]]; then
    print -u2 "FAIL terminal/script missing attach b got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *'set win to do script'* && $script == *'do script'*' in win'* ]]; then
    print -u2 "FAIL terminal/script later do script targets the first tab got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'window of'* ]]; then
    print -u2 "FAIL terminal/script missing window of for later tabs got=$(printf %q "$script")"
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
  # #132: Terminal open_placement=tab uses front window; window stays a new window.
  open_placement=tab
  script=$(terminal_osascript_for_sessions a b)
  if [[ $script != *'front window'* && $script != *'count of windows'* ]]; then
    print -u2 "FAIL terminal/tab-placement missing front window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'do script'*' in '* ]]; then
    print -u2 "FAIL terminal/tab-placement missing do script in window got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script == *$'\n  set t to do script '* && $script != *'front window'* && $script != *'count of windows'* ]]; then
    print -u2 "FAIL terminal/tab-placement only untargeted do script got=$(printf %q "$script")"
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
  if [[ $script != *'set t to do script'* ]]; then
    print -u2 "FAIL terminal/window-placement missing new do script got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'window of'* ]]; then
    print -u2 "FAIL terminal/window-placement missing window of for extras got=$(printf %q "$script")"
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
  functions[open_workspace_tabs]=$_save_open_tabs
  functions[effective_open_target]=$_save_eot
  functions[maybe_resume_last_command]=$_save_resume
  unset _save_open_tabs _save_eot _save_resume
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
  if last_command_resumable grok-1.0.24-mac; then
    :
  else
    print -u2 "FAIL resume/grok should be resumable"
    (( fails++ ))
  fi
  if last_command_resumable zsh; then
    print -u2 "FAIL resume/zsh should not be resumable"
    (( fails++ ))
  fi
  if last_command_resumable codex; then
    print -u2 "FAIL resume/codex v1 should not be resumable"
    (( fails++ ))
  fi
  LANJUMP_GROK_BIN=grok
  expect resume/line-project 'grok -c' "$(resume_line_for grok-1.0.24-mac /proj/lanjump)"
  expect resume/line-home 'grok --resume' "$(resume_line_for grok-1.0.24-mac "$HOME")"
  expect resume/line-tilde 'grok --resume' "$(resume_line_for grok '~')"
  expect resume/path-keep '/opt/x/bin:/bin' "$(PATH='/opt/x/bin:/bin' resume_pane_path)"
  expect resume/path-fill '/opt/lanjump-nopath:/usr/bin:/bin:/usr/sbin:/sbin' "$(PATH='/opt/lanjump-nopath' resume_pane_path)"
  expect resume/path-empty '/usr/bin:/bin:/usr/sbin:/sbin' "$(PATH='' resume_pane_path)"
  mkdir -p "$HOME/Documents/projects/inferme"
  snap_cwd[inferme]=$HOME
  pinned_cwd[inferme]=$HOME
  load_settings
  expect resolve/named-project "$HOME/Documents/projects/inferme" "$(resolve_session_cwd inferme "$HOME")"
  expect resolve/keep-explicit /proj/keep "$(resolve_session_cwd nosuch /proj/keep)"
  expect enter/prompt $'上次在跑 grok。\nEnter/y  续上    s  只要 shell    q  取消' "$(enter_resume_prompt_text grok-1.0.24-mac)"

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
  if ! /usr/bin/osacompile -o "$testhome/ghostty-space.scpt" "$testhome/ghostty-space.applescript" 2>"$testhome/osacompile-space.err"; then
    print -u2 "FAIL ghostty/space-compile $(<"$testhome/osacompile-space.err") got=$(printf %q "$script")"
    (( fails++ ))
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
  script=$(terminal_osascript_for_sessions 'my app')
  if [[ $script != *"$(printf %q 'my app')"* ]]; then
    print -u2 "FAIL terminal/space-name missing quoted my app got=$(printf %q "$script")"
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
  expect snap/cmd-keep-grok grok-1.0.24-mac "${snap_cmd[keep]}"
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
  if [[ $hook_log != *'--snapshot'* ]]; then
    print -u2 "FAIL snap/hook missing --snapshot got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if [[ $hook_log != *'status-right'* ]]; then
    print -u2 "FAIL snap/hook missing status-right tick got=$(printf %q "$hook_log")"
    (( fails++ ))
  fi
  if pick_needs_tty --snapshot; then
    print -u2 "FAIL snap/tty --snapshot should not need a tty"
    (( fails++ ))
  fi
  # #162: remote pick is ~/.local/bin/lanjump-pick; hooks must not keep
  # pointing at the Mac-only Application Support path.
  got=$(LANJUMP_PICK_BIN=/tmp/lanjump-pick snapshot_hook_shell)
  expect snap/hook-env-bin "/bin/zsh /tmp/lanjump-pick --snapshot >/dev/null 2>&1" "$got"
  local hook_home hook_pick app_home app_pick stale_sr
  hook_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook-local.XXXXXX")
  mkdir -p "$hook_home/.local/bin"
  hook_pick=$hook_home/.local/bin/lanjump-pick
  : >"$hook_pick"
  got=$(unset LANJUMP_PICK_BIN; HOME=$hook_home snapshot_hook_shell)
  expect snap/hook-local-bin "/bin/zsh $(printf %q "$hook_pick") --snapshot >/dev/null 2>&1" "$got"
  if [[ $got == *'Application Support'* ]]; then
    print -u2 "FAIL snap/hook-local-bin leaked Application Support got=$(printf %q "$got")"
    (( fails++ ))
  fi
  app_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-hook-app.XXXXXX")
  mkdir -p "$app_home/Library/Application Support/lanjump"
  app_pick="$app_home/Library/Application Support/lanjump/lanjump-pick.zsh"
  : >"$app_pick"
  got=$(unset LANJUMP_PICK_BIN; HOME=$app_home snapshot_hook_shell)
  expect snap/hook-app-default "/bin/zsh $(printf %q "$app_pick") --snapshot >/dev/null 2>&1" "$got"
  if [[ $got == *'.local/bin/lanjump-pick'* ]]; then
    print -u2 "FAIL snap/hook-app-default used local/bin got=$(printf %q "$got")"
    (( fails++ ))
  fi
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
  if [[ ${restore_names[(Ie)test]} -eq 0 ]]; then
    print -u2 "FAIL snap/new-named should be restored got=${restore_names[*]}"
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
  expect snap/home-cd-restore-cwd /proj/keep "${restore_cwd[home-cd]:-}"
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
  if [[ $restore_log != *'respawn-pane -t =idle-grok:. -k'* ]]; then
    print -u2 "FAIL resume/send missing respawn-pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'grok -c'* ]]; then
    print -u2 "FAIL resume/send missing grok -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'-e PATH='* ]]; then
    print -u2 "FAIL resume/path missing -e PATH got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'/bin'* ]]; then
    print -u2 "FAIL resume/path missing /bin got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$tmux_log"
  PATH=/opt/lanjump-nopath maybe_resume_last_command idle-grok
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'-e PATH=/opt/lanjump-nopath:/usr/bin:/bin:/usr/sbin:/sbin '* ]]; then
    print -u2 "FAIL resume/path-fill-argv got=$(printf %q "$restore_log")"
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
  if [[ $restore_log != *'grok --resume'* ]]; then
    print -u2 "FAIL resume/home missing grok --resume got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log == *'grok -c'* ]]; then
    print -u2 "FAIL resume/home used grok -c got=$(printf %q "$restore_log")"
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
  if [[ $restore_log != *"-c $HOME/Documents/projects/inferme"* ]]; then
    print -u2 "FAIL resume/named-project missing respawn -c got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'grok -c'* ]]; then
    print -u2 "FAIL resume/named-project missing grok -c after cd got=$(printf %q "$restore_log")"
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
  if [[ $restore_log != *'-c /proj/keep'* ]]; then
    print -u2 "FAIL resume/cd missing respawn -c to project got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'grok -c'* ]]; then
    print -u2 "FAIL resume/cd-project missing grok -c got=$(printf %q "$restore_log")"
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
  if [[ $restore_log == *'respawn-pane -t %1 '* ]]; then
    print -u2 "FAIL resume/split-idle killed first pane got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'respawn-pane -t =split-idle:. -k'* ]]; then
    print -u2 "FAIL resume/split-idle missing current-pane respawn got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  if [[ $restore_log != *'grok -c'* ]]; then
    print -u2 "FAIL resume/split-idle missing grok -c got=$(printf %q "$restore_log")"
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

  # #194: resume prompt q must not occupy the snapshot; y/enter still must.
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
  print -r -- q | attach_named_session idle-grok 1 0 >/dev/null
  load_session_snapshot
  expect resume/cancel-q-ws 0 "${snap_workspace[idle-grok]:-}"
  expect resume/cancel-q-att 123 "${snap_attached[idle-grok]:-}"
  expect resume/cancel-q-occ 0 "${snap_occupied[idle-grok]:-}"
  snap_workspace[idle-grok]=0
  snap_occupied[idle-grok]=0
  snap_attached[idle-grok]=123
  save_session_snapshot
  print -r -- y | attach_named_session idle-grok 1 0 >/dev/null
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
  if ! /usr/bin/osacompile -o "$testhome/ghostty.scpt" "$testhome/ghostty.applescript" 2>"$testhome/osacompile.err"; then
    print -u2 "FAIL ghostty/script-compile $(<"$testhome/osacompile.err") got=$(printf %q "$script")"
    (( fails++ ))
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

  snap_cwd[dup]=/opt/recorded
  expect resolve/snap-over-root /opt/recorded "$(resolve_session_cwd dup)"
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

  project_roots=('/tmp/only')
  save_settings
  project_roots=()
  save_settings
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
  if ! /usr/bin/osacompile -o "$testhome/ghostty-tab.scpt" "$testhome/ghostty-tab.applescript" 2>"$testhome/osacompile-tab.err"; then
    print -u2 "FAIL ghostty/tab-compile $(<"$testhome/osacompile-tab.err") got=$(printf %q "$script")"
    (( fails++ ))
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
  load_items() { boot_calls+=(load_items); items_id=(keep restored) }
  picker_boot_after_first_draw
  expect boot/after-runs-changed 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys load_items draw' "${boot_calls[*]}"

  boot_calls=()
  items_id=(keep)
  load_items() { boot_calls+=(load_items) }
  picker_boot_after_first_draw
  expect boot/after-runs-unchanged 'maybe_restore_sessions tmux_prepare_color tmux_prepare_keys load_items' "${boot_calls[*]}"

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
  boot_calls=()
  HAS_TMUX=1
  items_id=()
  tmuxx() { return 1 }
  picker_boot_before_first_draw
  expect boot/first-paint-empty 'new shell hosts quit' "${items_id[*]}"
  expect boot/first-paint-empty-steps 'load_settings load_session_filter load_items setup_tty draw' "${boot_calls[*]}"

  boot_restore

  HOME=$oldhome
  rm -rf "$testhome"
  unset -f tmuxx
  tmuxx() {
    [[ -n $TMUX_BIN ]] || return 1
    command "$TMUX_BIN" "$@" </dev/null
  }

  recent_home=$(mktemp -d "${TMPDIR:-/tmp}/lanjump-recent.XXXXXX")
  HOME=$recent_home
  mkdir -p "$HOME/Library/Application Support/lanjump"
  tmuxx() {
    if [[ $1 == list-sessions ]]; then
      print -r -- $'100\toldest'
      print -r -- $'300\tnewest'
      print -r -- $'200\tmiddle'
      return 0
    fi
    return 1
  }
  HAS_TMUX=1
  got=$(print_recent_names 5)
  expect recent/order $'newest\nmiddle\noldest' "$got"
  got=$(print_recent_names 2)
  expect recent/limit $'newest\nmiddle' "$got"
  tmuxx() { return 1 }
  if print_recent_names 5 >/dev/null; then
    print -u2 "FAIL recent/empty listed names"
    (( fails++ ))
  fi
  HOME=$oldhome
  rm -rf "$recent_home"

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

  # #130: n + pin from picker cwd must store project dir, not $PWD.
  pinned_names=()
  pinned_cwd=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  oldpwd=$PWD
  cd "$testhome"
  : >"$tmux_log"
  print -l -- inferme y | prompt_new >/dev/null
  load_pinned_sessions
  expect prompt_new/n-pin-named-cwd "$HOME/Documents/projects/inferme" "${pinned_cwd[inferme]:-}"
  : >"$tmux_log"
  restore_pinned_sessions
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'new-session -d -s inferme -c '"$HOME/Documents/projects/inferme"* ]]; then
    print -u2 "FAIL prompt_new/n-pin-restore-cwd got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 0 ;;
      display-message)
        print -r -- /opt/live-pane
        return 0
        ;;
      *) return 0 ;;
    esac
  }
  pinned_names=()
  pinned_cwd=()
  : >"$HOME/Library/Application Support/lanjump/pinned-sessions"
  print -l -- inferme y | prompt_new >/dev/null
  load_pinned_sessions
  expect prompt_new/n-pin-existing-cwd /opt/live-pane "${pinned_cwd[inferme]:-}"

  tmuxx() {
    print -r -- "$*" >>"$tmux_log"
    case $1 in
      has-session) return 1 ;;
      new-session)
        [[ $* == *-P* ]] && print -r -- 0
        return 0
        ;;
      display-message)
        print -r -- /tmp/picker-pane
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
  print -l -- '' y | prompt_new >/dev/null
  load_pinned_sessions
  created=${pinned_names[1]:-}
  if [[ -z $created ]]; then
    print -u2 "FAIL prompt_new/n-pin-empty missing pin record"
    (( fails++ ))
  fi
  if numeric_session_name "$created"; then
    print -u2 "FAIL prompt_new/n-pin-empty still numeric got=$(printf %q "$created")"
    (( fails++ ))
  fi
  if [[ $created == *:* || $created == *.* || $created == *' '* ]]; then
    print -u2 "FAIL prompt_new/n-pin-empty invalid name got=$(printf %q "$created")"
    (( fails++ ))
  fi
  expect prompt_new/n-pin-empty-cwd /tmp/picker-pane "${pinned_cwd[$created]:-}"
  restore_log=$(<"$tmux_log")
  if [[ $restore_log != *'rename-session -t =0 '* ]]; then
    print -u2 "FAIL prompt_new/n-pin-empty-rename got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi
  : >"$tmux_log"
  restore_pinned_sessions
  restore_log=$(<"$tmux_log")
  if [[ -n $created && $restore_log != *'new-session -d -s '"$created"' -c /tmp/picker-pane'* ]]; then
    print -u2 "FAIL prompt_new/n-pin-empty-restore got=$(printf %q "$restore_log")"
    (( fails++ ))
  fi

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

  attach_shell_only=1
  if resume_prompt_choice y; then
    expect resume/choice-y 0 "$attach_shell_only"
  else
    print -u2 "FAIL resume/choice-y cancelled"
    (( fails++ ))
  fi
  attach_shell_only=1
  if resume_prompt_choice Y; then
    expect resume/choice-Y 0 "$attach_shell_only"
  else
    print -u2 "FAIL resume/choice-Y cancelled"
    (( fails++ ))
  fi
  attach_shell_only=1
  if resume_prompt_choice ''; then
    expect resume/choice-empty 0 "$attach_shell_only"
  else
    print -u2 "FAIL resume/choice-empty cancelled"
    (( fails++ ))
  fi
  attach_shell_only=0
  if resume_prompt_choice s; then
    expect resume/choice-s 1 "$attach_shell_only"
  else
    print -u2 "FAIL resume/choice-s cancelled"
    (( fails++ ))
  fi
  attach_shell_only=0
  if resume_prompt_choice S; then
    expect resume/choice-S 1 "$attach_shell_only"
  else
    print -u2 "FAIL resume/choice-S cancelled"
    (( fails++ ))
  fi
  attach_shell_only=0
  if resume_prompt_choice q; then
    print -u2 "FAIL resume/choice-q should cancel"
    (( fails++ ))
  fi
  if resume_prompt_choice Q; then
    print -u2 "FAIL resume/choice-Q should cancel"
    (( fails++ ))
  fi
  if resume_prompt_choice n; then
    print -u2 "FAIL resume/choice-n should cancel"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *resume_prompt_choice* ]]; then
    print -u2 "FAIL resume/attach missing resume_prompt_choice got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *pane_is_idle_shell* ]]; then
    print -u2 "FAIL resume/attach missing pane_is_idle_shell got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *'! select_live_grok_pane'* ]]; then
    print -u2 "FAIL resume/attach prompt not gated on live grok pane got=$(printf %q "${functions[attach_named_session]}")"
    (( fails++ ))
  fi
  if [[ ${functions[attach_named_session]} != *session_pane_target* ]]; then
    print -u2 "FAIL resume/attach missing session_pane_target got=$(printf %q "${functions[attach_named_session]}")"
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

  if [[ ${functions[tmux_prepare_color]} == *'*:RGB@'* ]]; then
    print -u2 "FAIL color/src-no-star-rgb tmux_prepare_color still has *:RGB@"
    (( fails++ ))
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
