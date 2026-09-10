# Sourced by lanjump-pick.zsh --pick-selftest.
# Expects dw, fit_right, fit_left, fit_head_tail, padw, compute_layout, fmt_session_row, draw,
# sort_session_items, toggle_sort_mode, filter_session_items,
# toggle_session_filter, save_session_filter, load_session_filter,
# bulk_idle_unpinned_names, delete_idle_unpinned_sessions,
# session_delete_needs_pin_warning, pin_delete_warning_text,
# rename_pin_record, restore_pinned_sessions, numeric_session_name,
# collect_restore_names, should_restore_sessions, restore_saved_sessions,
# ghostty_restore_available, ghostty_osascript_for_sessions,
# workspace_restore_prompt_text, short_command_name, useful_summary,
# load_settings, save_settings, cycle_setting, effective_open_target,
# resolve_session_cwd, picker_boot_before_first_draw, picker_boot_after_first_draw,
# preview_is_grok, preview_line_is_tool, preview_line_is_model,
# preview_grok_lines, preview_generic_lines, preview_select_lines,
# session_name_invalid.

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
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach lanjump'* ]]; then
    print -u2 "FAIL ghostty/script missing attach lanjump got=$(printf %q "$script")"
    (( fails++ ))
  fi
  if [[ $script != *'/Users/mac/.local/bin/lanjump attach sysmtn'* ]]; then
    print -u2 "FAIL ghostty/script missing attach sysmtn got=$(printf %q "$script")"
    (( fails++ ))
  fi

  if pane_is_shell ''; then
    :
  else
    print -u2 "FAIL shell/empty should count as idle shell"
    (( fails++ ))
  fi
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
  expect enter/prompt $'上次在跑 grok。\nEnter  续上    s  只要 shell' "$(enter_resume_prompt_text grok-1.0.24-mac)"

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
  if [[ $restore_log != *'respawn-pane -t %1 -k'* ]]; then
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
  print -r -- "$script" >"$testhome/ghostty.applescript"
  if ! /usr/bin/osacompile -o "$testhome/ghostty.scpt" "$testhome/ghostty.applescript" 2>"$testhome/osacompile.err"; then
    print -u2 "FAIL ghostty/script-compile $(<"$testhome/osacompile.err") got=$(printf %q "$script")"
    (( fails++ ))
  fi
  ghostty_close_others=0

  attach_shell_only=1
  script=$(ghostty_osascript_for_sessions lanjump)
  if [[ $script != *'attach --shell lanjump'* ]]; then
    print -u2 "FAIL ghostty/script-shell missing --shell got=$(printf %q "$script")"
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

  open_target=current
  open_placement=tab
  save_settings
  open_target=auto
  open_placement=window
  load_settings
  expect settings/roundtrip-target current "$open_target"
  expect settings/roundtrip-placement tab "$open_placement"

  print -r -- $'open_target nope\nopen_placement sideways\n' >"$HOME/Library/Application Support/lanjump/settings"
  load_settings
  expect settings/bad-target auto "$open_target"
  expect settings/bad-placement window "$open_placement"

  expect settings/label-auto '自动（Ghostty 优先）' "$(settings_value_label target)"
  open_target=current
  expect settings/label-current 当前窗口 "$(settings_value_label target)"
  open_placement=tab
  expect settings/label-tab 已有窗口加标签 "$(settings_value_label placement)"

  settings_cursor=1
  open_target=auto
  cycle_setting
  expect settings/cycle-target ghostty "$open_target"
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
  settings_on=0
  project_roots=()
  open_target=auto
  open_placement=window

  open_target=auto
  unset SSH_CONNECTION SSH_CLIENT SSH_TTY
  LANJUMP_GHOSTTY_APP="$testhome/Ghostty.app"
  mkdir -p "$LANJUMP_GHOSTTY_APP"
  expect open/auto-ghostty ghostty "$(effective_open_target 1)"
  open_target=current
  expect open/force-current current "$(effective_open_target 1)"
  open_target=ghostty
  LANJUMP_GHOSTTY_APP="$testhome/missing-Ghostty.app"
  expect open/ghostty-missing current "$(effective_open_target 1)"
  open_target=auto
  expect open/auto-one-no-ghostty current "$(effective_open_target 1)"

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

  if session_name_invalid ''; then
    print -u2 "FAIL name/empty auto-name rejected"
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

  if (( fails )); then
    print -u2 "pick-selftest: $fails failed"
    return 1
  fi
  print "ok pick"
  return 0
}
