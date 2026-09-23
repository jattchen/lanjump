#!/bin/zsh
emulate -L zsh
setopt no_unset extendedglob typesetsilent
zmodload zsh/datetime

export PATH="/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
TMUX_BIN="${commands[tmux]:-/usr/local/bin/tmux}"

HAS_TMUX=0
if [[ -x "$TMUX_BIN" ]]; then
  HAS_TMUX=1
else
  TMUX_BIN=""
fi

pick_needs_tty() {
  case ${1:-} in
    --digit-selftest|--pick-selftest|--print-workspace|--print-pinned|--print-last|--print-recent|--print-sessions|--open-tabs|--has-session|--new-session|--pin-session|--start-grok|--snapshot|--refresh-pin-cwd|--install-hooks) return 1 ;;
  esac
  return 0
}

if pick_needs_tty "${1:-}"; then
  if [[ ! -t 0 || ! -t 1 ]]; then
    print "需要交互式终端。"
    exit 1
  fi
fi

if [[ -z ${NO_COLOR:-} ]]; then
  c_reset=$'\e[0m'
  c_bold=$'\e[1m'
  c_dim=$'\e[2m'
  c_green=$'\e[32m'
  c_cyan=$'\e[36m'
  c_red=$'\e[31m'
  c_rev=$'\e[7m'
else
  c_reset= c_bold= c_dim= c_green= c_cyan= c_red= c_rev=
fi

typeset -a items_kind items_id items_name items_att items_time items_path items_summary items_cmd items_activity items_pinned
typeset -a all_kind all_id all_name all_att all_time all_path all_summary all_cmd all_activity all_pinned
typeset -a preview_lines
preview_heading=
typeset -A preview_cache preview_cache_heading
typeset -A session_titles
cursor=1
# time = all by last activity desc; attached = 占用中 first, idle after, each time-desc.
sort_mode=time
filter_include=
filter_exclude=
typeset -i filter_on=0 filter_match_count=0 filter_total_count=0
typeset -i _filter_have_loaded=0
_filter_loaded_include=
_filter_loaded_exclude=
typeset -a pinned_names snap_names restore_names ghostty_names open_window_names work_names
typeset -a restore_pick_kind restore_pick_name restore_pick_checked restore_pick_row
typeset -A pinned_cwd pinned_grok snap_cwd snap_occupied snap_workspace snap_cmd snap_attached restore_cwd
typeset -i restore_pick_cursor=1 restore_mouse_col=0 restore_mouse_row=0
restore_pick_action=skip
RESTORE_RECENT_SECS=172800
WORK_RECENT_SECS=86400
stamp_boot=
stamp_token=
stamp_gen=
did_restore=0
# Interactive boot only. CLI restore stays silent.
restore_show_progress=0
restore_progress_on=0
restore_progress_index=0
restore_progress_total=0
restore_progress_name=
restore_boot_notice=
typeset -a pending_restore_names restore_progress_failed restore_created_names
attach_shell_only=0
ghostty_close_others=0
open_target=auto
open_placement=window
typeset -a project_roots
typeset -i _settings_have_loaded=0
_settings_loaded_open_target=
_settings_loaded_open_placement=
typeset -a _settings_loaded_project_roots
settings_on=0
settings_cursor=1
settings_input_on=0
settings_input_buf=
settings_input_char=
loading=0
list_active=0
stty_orig=
PENDING_KEY=""
typeset -i _read_key_fails=0
digit_wait=0.5
preview_defer=0
preview_wait=0.08
preview_max_lines=12
typeset -i preview_on=1 preview_band=8
w_name=4 w_status=6 w_time=11 w_summary=4 w_path=4
show_summary=1
show_path=1
draw_remain=0
view_start=1
view_end=0
view_above=0
view_below=0
host_short=""
prepared_keys=0
prepared_color=0
typeset -i pick_interactive=0
typeset -i _grok_appearance_osc_set=0

# #463 process-local tmux census. Not written to disk.
# #467 calls tmux_state_load before taking a data-file lock, then reads
# tm_names / tm_live / tm_path / tm_cmd / tm_att / tm_activity / tm_windows /
# tm_wname / tm_title. tm_state_gen bumps on each load; tm_state_dirty is 1
# after new-session, kill-session, or rename-session until the next load.
# #464 queues terminal-features / terminal-overrides on tm_term_queue and
# flushes them with tmux_terminal_option_flush (one tmux command, not one
# fork per entry).
typeset -i tm_state_gen=0 tm_state_dirty=1 tm_server_up=0 tm_list_rows=0
typeset -i pin_cwd_refreshed_gen=-1 hooks_installed=0 tm_features_loaded=0
tm_state_src=
hooks_tmuxx_src=
tm_features=
typeset -a tm_names tm_term_queue
typeset -A tm_live tm_path tm_cmd tm_att tm_activity tm_windows tm_wname tm_title tm_hook_cmd
# #464: raw terminal-array entries for this process. A key with ':' must be a
# parameter; zsh does not treat that colon as part of a subscript.
typeset -A _tmux_arr_loaded _tmux_arr_count
typeset -a _tmux_feat_vals _tmux_over_vals
typeset -i _tmux_term_deduped=0

# Same fields load_items already asks for. #{pane_current_path} is the
# current window's current pane, matching session_pane_target (=$name:.).
TMUX_LIST_SESSIONS_FMT=$'#{session_activity}\x1f#{session_name}\x1f#{session_windows}\x1f#{?session_attached,1,0}\x1f#{pane_current_path}\x1f#{window_name}\x1f#{pane_title}\x1f#{pane_current_command}'

tmuxx() {
  [[ -n $TMUX_BIN ]] || return 1
  command "$TMUX_BIN" "$@" </dev/null
}

tmux_state_invalidate() {
  tm_state_dirty=1
}

tmux_state_clear() {
  tm_names=()
  tm_live=()
  tm_path=()
  tm_cmd=()
  tm_att=()
  tm_activity=()
  tm_windows=()
  tm_wname=()
  tm_title=()
  tm_server_up=0
  tm_list_rows=0
}

tmux_state_note() {
  local name=$1
  [[ -n $name ]] || return 0
  if (( ! ${tm_live[$name]:-0} )); then
    tm_names+=("$name")
  fi
  tm_live[$name]=1
  tm_activity[$name]=${2:-}
  tm_windows[$name]=${3:-}
  tm_att[$name]=${4:-0}
  tm_path[$name]=${5:-}
  tm_wname[$name]=${6:-}
  tm_title[$name]=${7:-}
  tm_cmd[$name]=${8:-}
}

# Accept the load_items census, the shorter snapshot census, and the
# tab-separated list / recent shapes selftests already return.
tmux_state_ingest_line() {
  local line=$1
  local -a f
  local att
  [[ -n $line ]] || return 0
  if [[ $line == *$'\x1f'* ]]; then
    f=("${(@ps:\x1f:)line}")
    if (( ${#f} >= 8 )); then
      tmux_state_note "${f[2]}" "${f[1]}" "${f[3]}" "${f[4]}" "${f[5]}" "${f[6]}" "${f[7]}" "${f[8]}"
    elif (( ${#f} >= 4 )); then
      tmux_state_note "${f[1]}" "" "" "${f[3]}" "${f[2]}" "" "" "${f[4]}"
    fi
    return 0
  fi
  [[ $line == *$'\t'* ]] || return 0
  f=("${(@ps:\t:)line}")
  if (( ${#f} >= 4 )); then
    att=0
    [[ ${f[2]} == 占用中 || ${f[2]} == 1 ]] && att=1
    tmux_state_note "${f[1]}" "" "" "$att" "${f[4]}" "" "" "${f[3]}"
  elif (( ${#f} >= 2 )); then
    tmux_state_note "${f[2]}" "${f[1]}" "" "0" "" "" "" ""
  fi
}

tmux_state_load() {
  local src out line
  local -a raw
  local -i st
  src=${functions[tmuxx]:-}
  if (( ! tm_state_dirty && tm_state_gen > 0 )) && [[ $src == "$tm_state_src" ]]; then
    return 0
  fi
  tmux_state_clear
  tm_state_src=$src
  tm_state_dirty=0
  (( ++tm_state_gen ))
  [[ $HAS_TMUX -eq 1 ]] || return 0
  out=$(tmuxx list-sessions -F "$TMUX_LIST_SESSIONS_FMT" 2>/dev/null)
  st=$?
  if (( st == 0 )); then
    tm_server_up=1
  fi
  if (( tm_server_up )) && [[ -n $out ]]; then
    raw=("${(@f)out}")
    for line in "${raw[@]}"; do
      tmux_state_ingest_line "$line"
    done
  fi
  tm_list_rows=${#tm_names}
  return 0
}

tmux_server_running() {
  tmux_state_load || return 1
  (( tm_server_up ))
}

# Existence from the census. A list that named sessions is authoritative.
# The real binary exiting non-zero means there is no session to find.
# A selftest stub may still answer has-session without printing rows.
tmux_session_live() {
  local name=$1
  [[ -n $name ]] || return 1
  tmux_state_load || return 1
  if (( ${tm_live[$name]:-0} )); then
    return 0
  fi
  if (( tm_list_rows > 0 )); then
    return 1
  fi
  [[ ${functions[tmuxx]} == *'command "$TMUX_BIN"'* ]] && return 1
  tmuxx has-session -t "=$name" 2>/dev/null
}

tmux_session_path() {
  tmux_state_load || return 1
  REPLY=${tm_path[${1}]:-}
  [[ -n $REPLY ]]
}

tmux_session_cmd() {
  tmux_state_load || return 1
  REPLY=${tm_cmd[${1}]:-}
  [[ -n $REPLY ]]
}

# lanjump writes these shapes and no others. A longer or different entry stays.
tmux_entry_is_lanjump_shape() {
  local e=$1
  [[ $e == 'xterm*:extkeys' ]] && return 0
  [[ $e == [^:]##:(RGB|Tc|RGB@|256|Tc@) ]]
}

# -gv is the raw entry, one per line. show-options without -v escapes the
# value, so an exact compare cannot use that text.
tmux_array_load() {
  local opt=$1 line key
  local -a vals
  [[ ${_tmux_arr_loaded[$opt]:-} == 1 ]] && return 0
  vals=("${(@f)$(tmuxx show-options -gv "$opt" 2>/dev/null || true)}")
  if (( ${#vals} == 1 )) && [[ -z ${vals[1]:-} ]]; then
    vals=()
  fi
  case $opt in
    terminal-features)
      _tmux_feat_vals=()
      if (( ${#vals} )); then
        _tmux_feat_vals=("${vals[@]}")
      fi
      ;;
    terminal-overrides)
      _tmux_over_vals=()
      if (( ${#vals} )); then
        _tmux_over_vals=("${vals[@]}")
      fi
      ;;
  esac
  for line in "${vals[@]}"; do
    [[ -n $line ]] || continue
    key=${opt}$'\034'${line}
    _tmux_arr_count[$key]=$(( ${_tmux_arr_count[$key]:-0} + 1 ))
  done
  _tmux_arr_loaded[$opt]=1
}

# Later copies of a lanjump shape go away, highest index first, in one
# tmux command. A short index list is not paired: that would drop a user entry.
tmux_array_dedupe_option() {
  local opt=$1 line i val key
  local -a vals idx lines drop kept args
  local -A seen
  local -i n dup=0 first=1
  vals=()
  case $opt in
    terminal-features)
      if (( ${#_tmux_feat_vals} )); then
        vals=("${_tmux_feat_vals[@]}")
      fi
      ;;
    terminal-overrides)
      if (( ${#_tmux_over_vals} )); then
        vals=("${_tmux_over_vals[@]}")
      fi
      ;;
    *) return 0 ;;
  esac
  (( ${#vals} )) || return 0
  for val in "${vals[@]}"; do
    tmux_entry_is_lanjump_shape "$val" || continue
    key=${opt}$'\034'${val}
    if (( ${_tmux_arr_count[$key]:-0} > 1 )); then
      dup=1
      break
    fi
  done
  (( dup )) || return 0
  lines=("${(@f)$(tmuxx show-options -g "$opt" 2>/dev/null || true)}")
  if (( ${#lines} == 1 )) && [[ -z ${lines[1]:-} ]]; then
    lines=()
  fi
  for line in "${lines[@]}"; do
    [[ $line == ${opt}\[* ]] || continue
    i=${line#"${opt}["}
    i=${i%%]*}
    [[ $i == [0-9]## ]] || continue
    idx+=("$i")
  done
  if (( ${#idx} != ${#vals} )); then
    return 0
  fi
  for (( n = 1; n <= ${#vals}; n++ )); do
    val=${vals[$n]}
    tmux_entry_is_lanjump_shape "$val" || continue
    if (( ${seen[$val]:-0} )); then
      drop+=("${idx[$n]}")
    else
      seen[$val]=1
    fi
  done
  (( ${#drop} )) || return 0
  drop=(${(On)drop})
  for i in "${drop[@]}"; do
    if (( first )); then
      args=(set-option -gu "${opt}[$i]")
      first=0
    else
      args+=(\; set-option -gu "${opt}[$i]")
    fi
  done
  tmuxx "${args[@]}" 2>/dev/null || true
  seen=()
  for val in "${vals[@]}"; do
    if tmux_entry_is_lanjump_shape "$val" && (( ${seen[$val]:-0} )); then
      key=${opt}$'\034'${val}
      _tmux_arr_count[$key]=1
      continue
    fi
    seen[$val]=1
    kept+=("$val")
  done
  case $opt in
    terminal-features)
      _tmux_feat_vals=()
      if (( ${#kept} )); then
        _tmux_feat_vals=("${kept[@]}")
      fi
      ;;
    terminal-overrides)
      _tmux_over_vals=()
      if (( ${#kept} )); then
        _tmux_over_vals=("${kept[@]}")
      fi
      ;;
  esac
}

tmux_terminal_arrays_dedupe() {
  (( _tmux_term_deduped )) && return 0
  tmux_array_load terminal-features
  tmux_array_load terminal-overrides
  tmux_array_dedupe_option terminal-features
  tmux_array_dedupe_option terminal-overrides
  _tmux_term_deduped=1
}

# #464: queue one missing entry. tmux_terminal_option_flush sends the batch.
# Do not fold these into the safe set-option chain. The exact read stays in
# front of the writes, and a comma would become another array element.
tmux_array_add_once() {
  local opt=$1 entry=$2 key
  [[ -n $opt && -n $entry ]] || return 0
  [[ $entry != *,* ]] || return 0
  case $opt in
    terminal-features|terminal-overrides) ;;
    *) return 1 ;;
  esac
  tmux_terminal_arrays_dedupe
  key=${opt}$'\034'${entry}
  (( ${_tmux_arr_count[$key]:-0} > 0 )) && return 0
  tm_term_queue+=("${opt}"$'\x1f'"${entry}")
  _tmux_arr_count[$key]=$(( ${_tmux_arr_count[$key]:-0} + 1 ))
  case $opt in
    terminal-features) _tmux_feat_vals+=("$entry") ;;
    terminal-overrides) _tmux_over_vals+=("$entry") ;;
  esac
}

tmux_terminal_option_flush() {
  (( ${#tm_term_queue} )) || return 0
  local item opt entry flag
  local -a args
  local -i first=1
  for item in "${tm_term_queue[@]}"; do
    opt=${item%%$'\x1f'*}
    entry=${item#*$'\x1f'}
    case $opt in
      terminal-features) flag=-as ;;
      terminal-overrides) flag=-ag ;;
      *) continue ;;
    esac
    if (( first )); then
      args=(set-option "$flag" "$opt" ",${entry}")
      first=0
    else
      args+=(\; set-option "$flag" "$opt" ",${entry}")
    fi
  done
  tm_term_queue=()
  (( ${#args} )) || return 0
  tmuxx "${args[@]}" 2>/dev/null || true
}

keys_bin() {
  local c
  for c in "$HOME/.local/bin/lanjump-keys" \
           "$HOME/Library/Application Support/lanjump/lanjump-keys"; do
    if [[ -x $c ]]; then
      print -r -- $c
      return 0
    fi
  done
  return 1
}

local_keyboard() {
  [[ -z ${SSH_CONNECTION:-} && -z ${SSH_CLIENT:-} && -z ${SSH_TTY:-} ]]
}

run_interactive() {
  local keys st
  # #212: ignore SIGINT while the child owns the tty. zsh otherwise
  # defers the picker's `exit 130` INT trap until the child returns.
  trap '' INT
  if local_keyboard && keys=$(keys_bin); then
    "$keys" "$@"
  else
    "$@"
  fi
  st=$?
  trap 'restore_tty; exit 130' INT
  return $st
}

terminfo_available() {
  local term=${1:-}
  [[ -n $term ]] || return 1
  infocmp "$term" >/dev/null 2>&1
}

# tmux attach opens the client TERM. Ghostty's xterm-ghostty is often missing
# on remotes without Ghostty.app. Keep the picker TERM for #190; only the
# tmux client falls back.
tmux_client_term() {
  local term=${TERM:-} cand
  if [[ -n $term ]] && terminfo_available "$term"; then
    print -r -- "$term"
    return 0
  fi
  for cand in xterm-256color screen-256color; do
    if terminfo_available "$cand"; then
      print -r -- "$cand"
      return 0
    fi
  done
  print -r -- "$term"
}

tmux_apply_client_term() {
  local client_term=$1
  [[ -n $client_term ]] || return 0
  [[ $client_term == ${TERM:-} ]] && return 0
  [[ ${TERM_PROGRAM:-} == Apple_Terminal ]] && return 0
  tmux_array_add_once terminal-features "${client_term}:RGB"
  tmux_array_add_once terminal-overrides "${client_term}:Tc"
  tmux_terminal_option_flush
}

tmux_prepare_keys() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  tmux_install_snapshot_hooks
  (( prepared_keys )) && return 0
  # `always` falls back to `on`. A failed command aborts the rest of a \;
  # chain, so this stays its own call. extended-keys-format and
  # allow-passthrough are newer and can fail on older tmux; same reason.
  tmuxx set-option -g extended-keys always 2>/dev/null || \
    tmuxx set-option -g extended-keys on 2>/dev/null || true
  tmuxx set-option -s extended-keys-format csi-u 2>/dev/null || true
  tmuxx set-option -gw allow-passthrough on 2>/dev/null || true
  local len
  len=$(tmuxx show-options -gv status-left-length 2>/dev/null || true)
  [[ $len == [0-9]## ]] || len=0
  # Long-standing options. bind-key is last so a miss cannot skip the sets.
  if (( len < 40 )); then
    tmuxx set-option -g set-clipboard on \; \
      set-option -g set-titles on \; \
      set-option -g set-titles-string '#S' \; \
      set-option -g status-left-length 40 \; \
      bind-key -n S-Enter send-keys Escape Enter 2>/dev/null || true
  else
    tmuxx set-option -g set-clipboard on \; \
      set-option -g set-titles on \; \
      set-option -g set-titles-string '#S' \; \
      bind-key -n S-Enter send-keys Escape Enter 2>/dev/null || true
  fi
  tmux_array_add_once terminal-features 'xterm*:extkeys'
  if [[ ${TERM_PROGRAM:-} != Apple_Terminal && -n ${TERM:-} ]]; then
    tmux_array_add_once terminal-features "${TERM}:RGB"
  fi
  tmux_terminal_option_flush
  prepared_keys=1
}

snapshot_pick_bin() {
  if [[ -n ${LANJUMP_PICK_BIN:-} ]]; then
    print -r -- "$LANJUMP_PICK_BIN"
  elif [[ -f "$HOME/Library/Application Support/lanjump/lanjump-pick.zsh" ]]; then
    # #286: a local install beats a synced ~/.local/bin copy that an
    # older machine may have overwritten on connect.
    print -r -- "$HOME/Library/Application Support/lanjump/lanjump-pick.zsh"
  elif [[ -f $HOME/.local/bin/lanjump-pick ]]; then
    print -r -- "$HOME/.local/bin/lanjump-pick"
  else
    print -r -- "$HOME/Library/Application Support/lanjump/lanjump-pick.zsh"
  fi
}

snapshot_hook_shell() {
  local pick
  pick=$(snapshot_pick_bin)
  print -r -- "zsh=\$(command -v zsh) || { echo \"lanjump: 找不到 zsh。\" >&2; exit 127; }; \"\$zsh\" $(printf %q "$pick") --snapshot >/dev/null 2>&1"
}

pin_cwd_hook_shell() {
  local pick
  pick=$(snapshot_pick_bin)
  print -r -- "zsh=\$(command -v zsh) || { echo \"lanjump: 找不到 zsh。\" >&2; exit 127; }; \"\$zsh\" $(printf %q "$pick") --refresh-pin-cwd >/dev/null 2>&1"
}

# Drop a status-bar command that runs lanjump --snapshot. Leave the rest.
strip_snapshot_status_tick() {
  local sr=$1 pat
  pat='(#b)(*)\#\(/bin/zsh*lanjump-pick*--snapshot;\)(*)'
  while [[ $sr == $~pat ]]; do
    sr="${match[1]}${match[2]}"
  done
  pat='(#b)(*)\#\(zsh=*lanjump-pick*--snapshot;\)(*)'
  while [[ $sr == $~pat ]]; do
    sr="${match[1]}${match[2]}"
  done
  pat='(#b)(*)\#\(*lanjump-pick*--snapshot*\)(*)'
  while [[ $sr == $~pat ]]; do
    sr="${match[1]}${match[2]}"
  done
  print -r -- "$sr"
}

tmux_hook_cmd_from_show() {
  local raw line name
  local -a lines
  tm_hook_cmd=()
  raw=$(tmuxx show-hooks -g 2>/dev/null || true)
  lines=("${(@f)raw}")
  for line in "${lines[@]}"; do
    [[ -n $line ]] || continue
    if [[ $line == *' '* ]]; then
      name=${line%% *}
      tm_hook_cmd[$name]=${line#* }
    else
      tm_hook_cmd[$line]=
    fi
  done
}

tmux_install_snapshot_hooks() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  local src
  src=${functions[tmuxx]:-}
  if (( hooks_installed )) && [[ $src == "$hooks_tmuxx_src" ]]; then
    return 0
  fi
  local inner sr iv hook tick cmd
  inner=$(pin_cwd_hook_shell)
  # One show-hooks -g for the five snapshot slots and client-detached[91].
  tmux_hook_cmd_from_show
  for hook in \
    'client-attached[91]' \
    'session-created[91]' \
    'after-select-pane[91]' \
    'after-select-window[91]' \
    'after-refresh-client[91]'
  do
    # #277: only unset a slot 91 hook we wrote. Foreign plugins keep theirs.
    cmd=${tm_hook_cmd[$hook]:-}
    if [[ -n $cmd && $cmd == *lanjump-pick* && $cmd == *--snapshot* ]]; then
      tmuxx set-hook -gu "$hook" 2>/dev/null || true
    fi
  done
  # #308: only write client-detached[91] if empty or already ours.
  hook='client-detached[91]'
  cmd=${tm_hook_cmd[$hook]:-}
  if [[ -z $cmd || ( $cmd == *lanjump-pick* && ( $cmd == *--snapshot* || $cmd == *--refresh-pin-cwd* ) ) ]]; then
    tmuxx set-hook -g "$hook" "run-shell -b $(printf %q "$inner")" 2>/dev/null || true
  fi
  sr=$(tmuxx show-options -gv status-right 2>/dev/null || true)
  if [[ $sr == *lanjump-pick* && $sr == *--snapshot* ]]; then
    tick=$(strip_snapshot_status_tick "$sr")
    tmuxx set-option -g status-right "$tick" 2>/dev/null || true
    iv=$(tmuxx show-options -gv status-interval 2>/dev/null || true)
    if [[ $iv == 5 ]]; then
      tmuxx set-option -g status-interval 15 2>/dev/null || true
    fi
  fi
  hooks_installed=1
  hooks_tmuxx_src=$src
}

snapshot_recently_written() {
  local file m now min
  session_snapshot_file
  file=$REPLY
  [[ -f $file ]] || return 1
  min=${LANJUMP_SNAPSHOT_MIN:-2}
  (( min <= 0 )) && return 1
  # GNU: -c %Y; BSD: -f %m. GNU -f %m is a mount point, not mtime.
  m=$(stat -c %Y "$file" 2>/dev/null) || m=$(stat -f %m "$file" 2>/dev/null) || return 1
  [[ $m == [0-9]## ]] || return 1
  now=$EPOCHSECONDS
  (( now - m < min ))
}

run_session_snapshot() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  tmux_server_running || return 0
  snapshot_recently_written && return 0
  load_settings
  load_pinned_sessions
  snapshot_live_sessions
}

tmux_tty() {
  local client_term saved_term st=0
  client_term=$(tmux_client_term)
  tmux_prepare_color
  tmux_prepare_keys
  emit_host_grok_appearance_osc
  tmux_apply_client_term "$client_term"
  saved_term=${TERM:-}
  TERM=$client_term
  run_interactive "$TMUX_BIN" "$@"
  st=$?
  if [[ -n $saved_term ]]; then
    TERM=$saved_term
  else
    unset TERM
  fi
  return $st
}

# wrap stamps LC_GROK_APPEARANCE from the client OS for theme=auto over
# SSH. Unset is not enough: Grok then OSC 11-queries Ghostty's canvas,
# which follows the Mac light/dark mode, so the TUI goes gray-white or
# washed gray-black (#445). Pin the *host* appearance instead.
host_grok_appearance() {
  case ${LANJUMP_GROK_APPEARANCE:-} in
    dark|light) print -r -- "$LANJUMP_GROK_APPEARANCE"; return ;;
  esac
  local style
  if [[ $(uname -s) == Darwin ]]; then
    style=$(defaults read -g AppleInterfaceStyle 2>/dev/null) || style=
    if [[ $style == Dark ]]; then
      print -r -- dark
    else
      print -r -- light
    fi
    return
  fi
  print -r -- dark
}

host_grok_appearance_osc() {
  # #1a1a1a is GrokNight's bg. rgb:1a1a/1a1a/1a1a is the form Apple Terminal
  # documents for OSC 11; #rrggbb is what Ghostty accepts.
  case $(host_grok_appearance) in
    light) print -n $'\e]11;#f4f4f4\a\e]11;rgb:f4f4/f4f4/f4f4\a\e]10;#1c1c1c\a' ;;
    *) print -n $'\e]11;#1a1a1a\a\e]11;rgb:1a1a/1a1a/1a1a\a\e]10;#e6e6e6\a' ;;
  esac
}

apply_host_grok_appearance() {
  local app
  app=$(host_grok_appearance)
  export LC_GROK_APPEARANCE=$app GROK_APPEARANCE=$app
  REPLY=$app
  # prepare_color folds these four into its client-env chain.
  [[ ${1:-} == --export-only ]] && return 0
  [[ $HAS_TMUX -eq 1 ]] || return 0
  tmuxx set-environment -g LC_GROK_APPEARANCE "$app" \; \
    set-environment -g GROK_APPEARANCE "$app" \; \
    set-environment LC_GROK_APPEARANCE "$app" \; \
    set-environment GROK_APPEARANCE "$app" 2>/dev/null || true
}

emit_host_grok_appearance_osc() {
  (( pick_interactive )) || return 0
  print -n "$(host_grok_appearance_osc)" >/dev/tty 2>/dev/null || true
  _grok_appearance_osc_set=1
}

reset_host_grok_appearance_osc() {
  (( _grok_appearance_osc_set )) || return 0
  print -n $'\e]110\a\e]111\a' >/dev/tty 2>/dev/null || true
  _grok_appearance_osc_set=0
}

tmux_disable_truecolor_for() {
  local t=$1
  [[ -n $t ]] || return 0
  # Queued; tmux_prepare_color flushes once. A comma is a second entry.
  tmux_array_add_once terminal-features "${t}:RGB@"
  tmux_array_add_once terminal-features "${t}:256"
  tmux_array_add_once terminal-overrides "${t}:RGB@"
  tmux_array_add_once terminal-overrides "${t}:Tc@"
}

# PATH on this Mac puts ~/.grok/bin before ~/.local/bin, so a shim only at
# ~/.local/bin/grok is never executed (#451). ~/.grok/bin/grok is a symlink
# to the real binary; replace that symlink (and the local one) with a shim.
grok_colorterm_resolve_real() {
  local link real line
  if [[ -n ${LANJUMP_GROK_BIN:-} ]]; then
    print -r -- "$LANJUMP_GROK_BIN"
    return
  fi
  link=$HOME/.grok/bin/grok
  if [[ -L $link ]]; then
    real=$(readlink "$link")
    [[ $real == /* ]] || real=${link:h}/$real
    print -r -- "$real"
    return
  fi
  if [[ -f $link ]] && grep -q lanjump-grok-colorterm-shim "$link"; then
    line=$(grep -m1 '^real=' "$link")
    eval "$line"
    print -r -- "$real"
    return
  fi
  if [[ -L $HOME/.local/bin/grok ]]; then
    real=$(readlink "$HOME/.local/bin/grok")
    [[ $real == /* ]] || real=$HOME/.local/bin/$real
    print -r -- "$real"
  fi
}

write_grok_colorterm_shim() {
  local dest=$1 real=$2 dir tmp
  [[ -n $dest && -n $real && $real != "$dest" ]] || return 0
  dir=${dest:h}
  mkdir -p "$dir" 2>/dev/null || return 0
  if [[ -e $dest && ! -L $dest ]]; then
    grep -q lanjump-grok-colorterm-shim "$dest" 2>/dev/null || return 0
  fi
  tmp=$(mktemp "$dir/.grok.XXXXXX") || return 0
  print -r -- '#!/bin/zsh' >"$tmp"
  print -r -- '# lanjump-grok-colorterm-shim' >>"$tmp"
  print -r -- "real=$(printf %q "$real")" >>"$tmp"
  print -r -- 'if [[ -n ${TMUX:-} ]]; then' >>"$tmp"
  print -r -- '  client=$(command tmux show-environment -g LANJUMP_CLIENT 2>/dev/null) || client=' >>"$tmp"
  print -r -- '  if [[ $client == LANJUMP_CLIENT=Apple_Terminal ]]; then' >>"$tmp"
  print -r -- '    exec env -u COLORTERM "$real" "$@"' >>"$tmp"
  print -r -- '  fi' >>"$tmp"
  print -r -- 'fi' >>"$tmp"
  print -r -- 'exec "$real" "$@"' >>"$tmp"
  chmod 755 "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0 }
  mv -f "$tmp" "$dest" 2>/dev/null || rm -f "$tmp"
}

install_grok_colorterm_shim() {
  (( pick_interactive )) || [[ -n ${LANJUMP_GROK_SHIM_DIR:-} ]] || return 0
  local real front localbin
  real=$(grok_colorterm_resolve_real) || return 0
  [[ -n $real ]] || return 0
  front=${LANJUMP_GROK_FRONT_DIR:-}
  localbin=${LANJUMP_GROK_SHIM_DIR:-}
  if (( pick_interactive )); then
    [[ -n $front ]] || front=$HOME/.grok/bin
    [[ -n $localbin ]] || localbin=$HOME/.local/bin
  fi
  [[ -n $front ]] && write_grok_colorterm_shim "$front/grok" "$real"
  [[ -n $localbin ]] && write_grok_colorterm_shim "$localbin/grok" "$real"
}

# Apple Terminal (macOS 12) is 256-color. Advertising RGB makes Grok emit
# 24-bit backgrounds that Terminal.app ignores, so the TUI sits on white
# (Basic profile). Disable truecolor for both the client TERM and the
# inner default-terminal so Grok paints 256-color cells like a local
# session (#447). Ghostty keeps RGB (#173).
tmux_prepare_color() {
  (( prepared_color )) && return 0
  local app dt apple=0 term=${TERM:-}
  apply_host_grok_appearance --export-only
  app=$REPLY
  [[ $HAS_TMUX -eq 1 ]] || { prepared_color=1; return 0 }
  [[ ${TERM_PROGRAM:-} == Apple_Terminal ]] && apple=1

  dt=$(tmuxx show-options -gv default-terminal 2>/dev/null || true)
  install_grok_colorterm_shim
  if (( apple )); then
    unset COLORTERM
    # Appearance and the Apple client env are independent; one chain.
    tmuxx set-environment -g LC_GROK_APPEARANCE "$app" \; \
      set-environment -g GROK_APPEARANCE "$app" \; \
      set-environment LC_GROK_APPEARANCE "$app" \; \
      set-environment GROK_APPEARANCE "$app" \; \
      set-environment -g LANJUMP_CLIENT Apple_Terminal \; \
      set-environment -gu COLORTERM \; \
      set-environment -u COLORTERM 2>/dev/null || true
    if [[ $dt != *256color* && $dt != *direct* ]]; then
      if infocmp screen-256color >/dev/null 2>&1; then
        dt=screen-256color
      else
        dt=xterm-256color
      fi
      tmuxx set-option -g default-terminal "$dt" 2>/dev/null || true
    fi
    tmux_disable_truecolor_for "$term"
    tmux_disable_truecolor_for "$dt"
    # Empty cells / ignored 24-bit show this, not Terminal.app Basic white.
    tmuxx set-option -g window-style 'bg=colour234,fg=colour252' \; \
      set-option -g window-active-style 'bg=colour234,fg=colour252' 2>/dev/null || true
  else
    tmuxx set-environment -g LC_GROK_APPEARANCE "$app" \; \
      set-environment -g GROK_APPEARANCE "$app" \; \
      set-environment LC_GROK_APPEARANCE "$app" \; \
      set-environment GROK_APPEARANCE "$app" \; \
      set-environment -g LANJUMP_CLIENT "${TERM_PROGRAM:-other}" \; \
      set-environment -g COLORTERM truecolor 2>/dev/null || true
    if [[ -z $dt || $dt == screen || $dt == xterm || $dt == dumb ]]; then
      if infocmp tmux-256color >/dev/null 2>&1; then
        dt=tmux-256color
      elif infocmp screen-256color >/dev/null 2>&1; then
        dt=screen-256color
      else
        dt=xterm-256color
      fi
      tmuxx set-option -g default-terminal "$dt" 2>/dev/null || true
    fi
    if [[ -n $term ]]; then
      tmux_array_add_once terminal-features "${term}:RGB"
      tmux_array_add_once terminal-overrides "${term}:Tc"
    fi
  fi
  # Same flush as the color entries, so a cold server does not write extkeys later.
  tmux_array_add_once terminal-features 'xterm*:extkeys'
  tmux_terminal_option_flush
  prepared_color=1
}

restore_tty() {
  list_active=0
  print -n $'\e[?25h\e[?1000l\e[?1006l'
  [[ -n ${stty_orig:-} ]] && stty "$stty_orig" 2>/dev/null || stty sane 2>/dev/null
}

setup_tty() {
  stty_orig=$(stty -g)
  stty -echo -icanon min 1 time 0
  print -n '\e[?25l'
  list_active=1
  emit_host_grok_appearance_osc
}

on_exit() {
  restore_tty
  reset_host_grok_appearance_osc
}

# WINCH: session list draw only while the list is on screen.
# During pin restore, redraw the progress screen instead of the empty list.
draw_on_winch() {
  (( list_active )) || return 0
  [[ $loading -eq 1 ]] && return 0
  if (( restore_progress_on )); then
    draw_restore_progress
    return 0
  fi
  draw
}

if pick_needs_tty "${1:-}"; then
  pick_interactive=1
fi
if (( pick_interactive )) && [[ ${1:-} != --attach ]]; then
  trap on_exit EXIT
  trap 'restore_tty; exit 130' INT
  trap draw_on_winch WINCH
fi

term_cols() {
  local c=${COLUMNS:-0}
  if (( c < 20 )); then
    c=$(stty size 2>/dev/null | awk '{print $2}')
  fi
  (( c < 40 )) && c=40
  print -r -- $c
}

term_lines() {
  local r=${LINES:-0}
  if (( r < 1 )); then
    r=$(stty size 2>/dev/null | awk '{print $1}')
  fi
  (( r < 1 )) && r=1
  print -r -- $r
}

# ASCII 0x00-0x7e → width 1; anything else → width 2.
# Do not call this per character via $(dw): that is a subshell each time
# and made the session list hitch on Grok's long CJK titles and previews.
display_width() {
  local stripped=${1//[$'\x00'-$'\x7e']/}
  REPLY=$(( ${#1} + ${#stripped} ))
}

dw() {
  display_width "$1"
  print -r -- $REPLY
}

# Truncate/pad helpers set REPLY so the list renderer can avoid $(...) subshells.
fit_right() {
  _fit_right "$1" $2
  print -r -- "$REPLY"
}

_fit_right() {
  local s=$1
  local -i max=$2 w=0 i cw lim
  local c out= stripped
  REPLY=
  (( max <= 0 )) && return
  stripped=${s//[$'\x00'-$'\x7e']/}
  if (( ${#s} + ${#stripped} <= max )); then
    REPLY=$s
    return
  fi
  if (( max <= 1 )); then
    REPLY='…'
    return
  fi
  lim=${#s}
  (( lim > max )) && lim=max
  for (( i = 1; i <= lim; i++ )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( w + cw > max - 1 )); then
      break
    fi
    out+="$c"
    (( w += cw ))
  done
  REPLY="${out}…"
}

fit_left() {
  _fit_left "$1" $2
  print -r -- "$REPLY"
}

_fit_left() {
  local s=$1
  local -i max=$2 w=0 i cw start
  local c out= stripped
  REPLY=
  (( max <= 0 )) && return
  stripped=${s//[$'\x00'-$'\x7e']/}
  if (( ${#s} + ${#stripped} <= max )); then
    REPLY=$s
    return
  fi
  if (( max <= 1 )); then
    REPLY='…'
    return
  fi
  start=1
  (( ${#s} > max )) && start=$(( ${#s} - max + 1 ))
  for (( i = ${#s}; i >= start; i-- )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( w + cw > max - 1 )); then
      break
    fi
    out="$c$out"
    (( w += cw ))
  done
  REPLY="…${out}"
}

# Keep head and tail; paths and Grok titles often live at the ends.
# Ellipsis counts as width 1, same as fit_right/fit_left.
fit_head_tail() {
  _fit_head_tail "$1" $2
  print -r -- "$REPLY"
}

_fit_head_tail() {
  local s=$1
  local -i max=$2 i j cw left_w=0 right_w=0 budget left_budget right_budget leftover
  local c stripped left= right=
  REPLY=
  (( max <= 0 )) && return
  stripped=${s//[$'\x00'-$'\x7e']/}
  if (( ${#s} + ${#stripped} <= max )); then
    REPLY=$s
    return
  fi
  if (( max <= 1 )); then
    REPLY='…'
    return
  fi
  budget=$(( max - 1 ))
  left_budget=$(( budget / 2 ))
  right_budget=$(( budget - left_budget ))
  i=1
  j=${#s}
  while (( i <= j )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( left_w + cw > left_budget )); then
      break
    fi
    left+="$c"
    (( left_w += cw, i++ ))
  done
  while (( j >= i )); do
    c=$s[j]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( right_w + cw > right_budget )); then
      break
    fi
    right="$c$right"
    (( right_w += cw, j-- ))
  done
  leftover=$(( budget - left_w - right_w ))
  while (( leftover > 0 && i <= j )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( cw > leftover )); then
      break
    fi
    left+="$c"
    (( leftover -= cw, i++ ))
  done
  while (( leftover > 0 && j >= i )); do
    c=$s[j]
    if [[ $c < $'\x7f' ]]; then
      cw=1
    else
      cw=2
    fi
    if (( cw > leftover )); then
      break
    fi
    right="$c$right"
    (( leftover -= cw, j-- ))
  done
  REPLY="${left}…${right}"
}

padw() {
  _padw "$1" $2
  print -r -- "$REPLY"
}

_padw() {
  local s=$1
  local -i width=$2 d
  local stripped=${s//[$'\x00'-$'\x7e']/}
  REPLY=
  d=$(( ${#s} + ${#stripped} ))
  (( width <= 0 )) && return
  if (( d > width )); then
    _fit_right "$s" $width
    return
  fi
  printf -v REPLY '%s%*s' "$s" $(( width - d )) ''
}

short_path() {
  local p=$1
  if [[ $p == "$HOME" ]]; then
    print -r -- '~'
  elif [[ $p == "$HOME/"* ]]; then
    print -r -- "~${p#$HOME}"
  else
    print -r -- "$p"
  fi
}

short_command_name() {
  local cmd=${1:-}
  cmd=${cmd##*/}
  [[ -n $cmd ]] || { print -r -- ''; return }
  if [[ $cmd == grok-* || $cmd == grok ]]; then
    print -r -- grok
    return
  fi
  if [[ $cmd == codex-* ]]; then
    print -r -- codex
    return
  fi
  print -r -- "$cmd"
}

pane_is_shell() {
  local cmd
  cmd=$(short_command_name "$1")
  [[ -z $cmd || $cmd == zsh || $cmd == bash || $cmd == sh || $cmd == fish || $cmd == dash || $cmd == login ]]
}

# Unreadable pane command is not an idle shell.
pane_is_idle_shell() {
  [[ -n ${1:-} ]] || return 1
  pane_is_shell "$1"
}

# tmux 3.7c: session-only -t '=$name' leaves pane formats empty.
session_pane_target() {
  print -r -- "=${1}:."
}

cwd_is_home() {
  local p=$1
  [[ -z $p || $p == '~' || $p == "$HOME" || $p == "$HOME/" ]]
}

expand_project_root() {
  local p=$1
  case "$p" in
    '~') REPLY=$HOME ;;
    '~/'*) REPLY="$HOME/${p#"~/"}" ;;
    *) REPLY=$p ;;
  esac
}

session_project_dir() {
  local n=$1 root d
  [[ -n $n ]] || return 1
  for root in "${project_roots[@]}"; do
    expand_project_root "$root"
    root=$REPLY
    [[ -n $root ]] || continue
    d="$root/$n"
    [[ -d "$d" ]] || continue
    print -r -- "$d"
    return 0
  done
  return 1
}

resolve_session_cwd() {
  local name=$1 live=${2:-}
  local pin=${pinned_cwd[$name]:-}
  local snap=${snap_cwd[$name]:-}
  local proj c
  proj=$(session_project_dir "$name") || proj=
  # Pin record wins over a leftover snapshot. Snapshot only fills a gap.
  for c in "$live" "$pin" "$snap"; do
    [[ -n $c ]] || continue
    cwd_is_home "$c" && continue
    print -r -- "$c"
    return 0
  done
  [[ -n $proj ]] && { print -r -- "$proj"; return 0 }
  for c in "$live" "$pin" "$snap"; do
    [[ -n $c ]] && { print -r -- "$c"; return 0 }
  done
}

grok_bin() {
  local c
  if [[ -n ${LANJUMP_GROK_BIN:-} ]]; then
    print -r -- "$LANJUMP_GROK_BIN"
    return 0
  fi
  for c in "$HOME/.grok/bin/grok" "$HOME/.local/bin/grok"; do
    [[ -x $c ]] && { print -r -- "$c"; return 0 }
  done
  (( $+commands[grok] )) && { print -r -- "${commands[grok]}"; return 0 }
  print -r -- grok
}

cwd_has_grok_session() {
  local cwd=$1 enc dir
  [[ -n $cwd ]] || return 1
  enc=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$cwd" 2>/dev/null) || return 1
  dir="$HOME/.grok/sessions/$enc"
  [[ -d $dir ]]
}

# If any pane in the session is grok, select that window/pane.
select_live_grok_pane() {
  local session=$1 pane_line pane_id pane_cmd
  local -a panes
  [[ -n $session ]] || return 1
  panes=("${(@f)$(tmuxx list-panes -s -t "=$session" -F $'#{pane_id}\t#{pane_current_command}' 2>/dev/null)}")
  for pane_line in "${panes[@]}"; do
    [[ -n $pane_line ]] || continue
    pane_id=${pane_line%%$'\t'*}
    pane_cmd=${pane_line#*$'\t'}
    pane_cmd=${pane_cmd##*/}
    if [[ $pane_cmd == grok || $pane_cmd == grok-* ]]; then
      tmuxx select-window -t "$pane_id" 2>/dev/null || true
      tmuxx select-pane -t "$pane_id" 2>/dev/null || true
      return 0
    fi
  done
  return 1
}

# go --grok: jump to an already-open grok pane, else type grok into an idle shell.
start_grok_session() {
  local session=$1
  local live pane_cwd bin line target
  [[ -n $session ]] || return 1
  [[ $HAS_TMUX -eq 1 ]] || return 1
  target=$(session_pane_target "$session")
  live=$(tmuxx display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || true)
  live=${live##*/}
  if [[ $live == grok || $live == grok-* ]]; then
    return 0
  fi
  select_live_grok_pane "$session" && return 0
  # Unreadable command is not an idle shell; do not send-keys into a live grok.
  [[ -n $live ]] || return 0
  case $live in
    zsh|bash|sh|fish|dash|login) ;;
    *) return 0 ;;
  esac
  pane_cwd=$(tmuxx display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null || true)
  bin=$(grok_bin)
  if cwd_has_grok_session "$pane_cwd"; then
    line="$bin -c"
  else
    line="$bin"
  fi
  tmuxx send-keys -t "$target" -- "$line" Enter
}

useful_summary() {
  local title=$1 cmd=$2 wname=$3
  local short
  short=$(short_command_name "$cmd")
  if [[ -n $short ]]; then
    print -r -- "$short"
  elif [[ -n $wname && $wname != zsh && $wname != bash ]]; then
    print -r -- "$wname"
  else
    print -r -- '-'
  fi
}

max_dw() {
  local -i best=$1
  local item
  shift
  for item in "$@"; do
    display_width "$item"
    (( REPLY > best )) && best=REPLY
  done
  print -r -- $best
}

compute_layout() {
  local -i avail=$1 i n_sess=0
  local -a names summaries paths
  names=() summaries=() paths=()
  show_summary=1
  show_path=1
  w_status=6
  w_time=11

  for i in {1..${#items_kind}}; do
    if [[ ${items_kind[$i]} == session ]]; then
      (( n_sess++ ))
      if [[ ${items_pinned[$i]:-0} == 1 ]]; then
        names+=("${items_name[$i]}*")
      else
        names+=("${items_name[$i]}")
      fi
      summaries+=("${items_summary[$i]}")
      paths+=("${items_path[$i]}")
    fi
  done

  if (( n_sess == 0 )); then
    w_name=4 w_summary=0 w_path=0
    show_summary=0
    show_path=0
    return
  fi

  w_name=$(max_dw 4 名称 "${names[@]}")
  w_summary=$(max_dw 4 程序 "${summaries[@]}")
  w_path=$(max_dw 4 路径 "${paths[@]}")

  local -i gaps=8 needed extra shrink
  needed=$(( w_name + w_status + w_time + w_summary + w_path + gaps ))

  if (( needed <= avail )); then
    return
  fi

  extra=$(( needed - avail ))

  shrink=$(( w_path - 12 ))
  (( shrink < 0 )) && shrink=0
  (( shrink > extra )) && shrink=extra
  (( w_path -= shrink, extra -= shrink ))

  if (( extra > 0 )); then
    shrink=$(( w_summary - 12 ))
    (( shrink < 0 )) && shrink=0
    (( shrink > extra )) && shrink=extra
    (( w_summary -= shrink, extra -= shrink ))
  fi

  if (( extra > 0 && w_path > 0 )); then
    extra=$(( extra - w_path - 2 ))
    w_path=0
    show_path=0
    (( extra < 0 )) && extra=0
    gaps=6
  fi

  if (( extra > 0 )); then
    shrink=$(( w_summary - 8 ))
    (( shrink < 0 )) && shrink=0
    (( shrink > extra )) && shrink=extra
    (( w_summary -= shrink, extra -= shrink ))
  fi

  if (( extra > 0 && w_summary > 0 )); then
    w_summary=0
    show_summary=0
  fi
}

fmt_session_row() {
  _fmt_session_row $1
  print -r -- "$REPLY"
}

_fmt_session_row() {
  local i=$1
  local att_txt att_col extra shown
  if [[ ${items_att[$i]} == 1 ]]; then
    att_txt="占用中"
    att_col=$c_green
  else
    att_txt="空闲"
    att_col=$c_dim
  fi
  shown=${items_name[$i]}
  if [[ ${items_pinned[$i]:-0} == 1 ]]; then
    shown="${shown}*"
  fi
  _padw "$shown" $w_name
  extra=$REPLY
  _padw "$att_txt" $w_status
  extra+="  ${att_col}${REPLY}${c_reset}"
  _padw "${items_time[$i]}" $w_time
  extra+="  $REPLY"
  if (( show_summary )); then
    _padw "${items_summary[$i]}" $w_summary
    extra+="  $REPLY"
  fi
  if (( show_path )); then
    display_width "${items_path[$i]}"
    if (( REPLY > w_path )); then
      _fit_left "${items_path[$i]}" $w_path
    else
      _padw "${items_path[$i]}" $w_path
    fi
    extra+="  $REPLY"
  fi
  REPLY=$extra
}

fmt_header() {
  _fmt_header
  print -r -- "$REPLY"
}

_fmt_header() {
  local extra
  _padw 名称 $w_name
  extra=$REPLY
  _padw 状态 $w_status
  extra+="  $REPLY"
  _padw 最近活动 $w_time
  extra+="  $REPLY"
  if (( show_summary )); then
    _padw 程序 $w_summary
    extra+="  $REPLY"
  fi
  if (( show_path )); then
    _padw 路径 $w_path
    extra+="  $REPLY"
  fi
  REPLY=$extra
}

sort_session_items() {
  local keep="${1-}" line
  local -i i idx
  local -a skind sid sname satt stime spath ssummary scmd sact spinned
  local -a akind aid aname aatt atime apath asummary acmd aact apinned
  local -a decorated lines

  if [[ -z $keep ]] && (( cursor >= 1 && cursor <= ${#items_id} )); then
    keep=${items_id[$cursor]}
  fi

  for (( i = 1; i <= ${#items_kind}; i++ )); do
    if [[ ${items_kind[$i]} == session ]]; then
      skind+=("${items_kind[$i]}")
      sid+=("${items_id[$i]}")
      sname+=("${items_name[$i]}")
      satt+=("${items_att[$i]}")
      stime+=("${items_time[$i]}")
      spath+=("${items_path[$i]}")
      ssummary+=("${items_summary[$i]}")
      scmd+=("${items_cmd[$i]}")
      sact+=("${items_activity[$i]}")
      spinned+=("${items_pinned[$i]:-}")
    else
      akind+=("${items_kind[$i]}")
      aid+=("${items_id[$i]}")
      aname+=("${items_name[$i]}")
      aatt+=("${items_att[$i]}")
      atime+=("${items_time[$i]}")
      apath+=("${items_path[$i]}")
      asummary+=("${items_summary[$i]}")
      acmd+=("${items_cmd[$i]}")
      aact+=("${items_activity[$i]}")
      apinned+=("${items_pinned[$i]:-}")
    fi
  done

  items_kind=()
  items_id=()
  items_name=()
  items_att=()
  items_time=()
  items_path=()
  items_summary=()
  items_cmd=()
  items_activity=()
  items_pinned=()

  if (( ${#skind} )); then
    local att pin
    decorated=()
    for (( i = 1; i <= ${#skind}; i++ )); do
      att=${satt[$i]:-0}
      pin=${spinned[$i]:-0}
      [[ $att == 1 ]] || att=0
      [[ $pin == 1 ]] || pin=0
      case ${sort_mode:-time} in
        occupied)
          decorated+=("${att}"$'\x1f'"${pin}"$'\x1f'"${sact[$i]}"$'\x1f'"$i")
          ;;
        pinned)
          decorated+=("${pin}"$'\x1f'"${att}"$'\x1f'"${sact[$i]}"$'\x1f'"$i")
          ;;
        *)
          decorated+=("${sact[$i]}"$'\x1f'"$i")
          ;;
      esac
    done
    if [[ ${sort_mode:-time} == occupied || ${sort_mode:-time} == pinned ]]; then
      lines=("${(@f)$(printf '%s\n' "${decorated[@]}" | sort -t $'\x1f' -k1,1nr -k2,2nr -k3,3nr)}")
    else
      lines=("${(@f)$(printf '%s\n' "${decorated[@]}" | sort -t $'\x1f' -k1,1nr)}")
    fi
    for line in "${lines[@]}"; do
      [[ -z $line ]] && continue
      idx=${line##*$'\x1f'}
      items_kind+=("${skind[$idx]}")
      items_id+=("${sid[$idx]}")
      items_name+=("${sname[$idx]}")
      items_att+=("${satt[$idx]}")
      items_time+=("${stime[$idx]}")
      items_path+=("${spath[$idx]}")
      items_summary+=("${ssummary[$idx]}")
      items_cmd+=("${scmd[$idx]}")
      items_activity+=("${sact[$idx]}")
      items_pinned+=("${spinned[$idx]:-}")
    done
  fi

  for (( i = 1; i <= ${#akind}; i++ )); do
    items_kind+=("${akind[$i]}")
    items_id+=("${aid[$i]}")
    items_name+=("${aname[$i]}")
    items_att+=("${aatt[$i]}")
    items_time+=("${atime[$i]}")
    items_path+=("${apath[$i]}")
    items_summary+=("${asummary[$i]}")
    items_cmd+=("${acmd[$i]}")
    items_activity+=("${aact[$i]}")
    items_pinned+=("${apinned[$i]:-}")
  done

  cursor=1
  if [[ -n $keep ]]; then
    for (( i = 1; i <= ${#items_id}; i++ )); do
      if [[ ${items_id[$i]} == "$keep" ]]; then
        cursor=$i
        break
      fi
    done
  fi
}

toggle_sort_mode() {
  case ${sort_mode:-time} in
    time) sort_mode=occupied ;;
    occupied) sort_mode=pinned ;;
    *) sort_mode=time ;;
  esac
  if (( ${#all_kind} )); then
    copy_all_to_items
  fi
  sort_session_items
  copy_items_to_all
  filter_session_items
}

copy_items_to_all() {
  all_kind=("${items_kind[@]}")
  all_id=("${items_id[@]}")
  all_name=("${items_name[@]}")
  all_att=("${items_att[@]}")
  all_time=("${items_time[@]}")
  all_path=("${items_path[@]}")
  all_summary=("${items_summary[@]}")
  all_cmd=("${items_cmd[@]}")
  all_activity=("${items_activity[@]}")
  all_pinned=("${items_pinned[@]}")
}

copy_all_to_items() {
  items_kind=("${all_kind[@]}")
  items_id=("${all_id[@]}")
  items_name=("${all_name[@]}")
  items_att=("${all_att[@]}")
  items_time=("${all_time[@]}")
  items_path=("${all_path[@]}")
  items_summary=("${all_summary[@]}")
  items_cmd=("${all_cmd[@]}")
  items_activity=("${all_activity[@]}")
  items_pinned=("${all_pinned[@]}")
}

lanjump_data_dir() {
  if [[ ${OSTYPE:-} == darwin* ]]; then
    REPLY="$HOME/Library/Application Support/lanjump"
  else
    REPLY="${XDG_STATE_HOME:-$HOME/.local/state}/lanjump"
  fi
}

session_filter_file() {
  lanjump_data_dir
  REPLY="$REPLY/session-filter"
}

sanitize_filter_keyword() {
  local s=$1
  s=${s##[[:space:]]#}
  s=${s%%[[:space:]]#}
  s=${s//[$'\x00'-$'\x1f'$'\x7f']/}
  if (( ${#s} > 80 )); then
    s=$s[1,80]
  fi
  REPLY=$s
}

_remember_loaded_filter() {
  _filter_have_loaded=1
  _filter_loaded_include=$filter_include
  _filter_loaded_exclude=$filter_exclude
}

save_session_filter() {
  local file st=0 my_include my_exclude
  local -i dirty_include=1 dirty_exclude=1
  session_filter_file
  file=$REPLY
  if [[ -z ${_LANJUMP_FILTER_LOCKED:-} ]]; then
    _LANJUMP_FILTER_LOCKED=1
    with_data_file_lock "$file" save_session_filter
    st=$?
    unset _LANJUMP_FILTER_LOCKED
    return $st
  fi
  sanitize_filter_keyword "$filter_include"
  filter_include=$REPLY
  sanitize_filter_keyword "$filter_exclude"
  filter_exclude=$REPLY
  my_include=$filter_include
  my_exclude=$filter_exclude
  if (( _filter_have_loaded )); then
    dirty_include=0
    dirty_exclude=0
    [[ $my_include == "$_filter_loaded_include" ]] || dirty_include=1
    [[ $my_exclude == "$_filter_loaded_exclude" ]] || dirty_exclude=1
  fi
  load_session_filter
  (( dirty_include )) && filter_include=$my_include
  (( dirty_exclude )) && filter_exclude=$my_exclude
  {
    print -r -- "include ${filter_include}"
    print -r -- "exclude ${filter_exclude}"
  } | replace_file_atomic "$file"
  _remember_loaded_filter
}

load_session_filter() {
  local file line key val
  session_filter_file
  file=$REPLY
  filter_include=
  filter_exclude=
  if [[ -f $file ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -z $line ]] && continue
      key=${line%% *}
      if [[ $line == *' '* ]]; then
        val=${line#* }
      else
        val=
      fi
      sanitize_filter_keyword "$val"
      val=$REPLY
      case $key in
        include) filter_include=$val ;;
        exclude) filter_exclude=$val ;;
      esac
    done <"$file"
  fi
  _remember_loaded_filter
}

session_src_matches() {
  local i=$1
  local hay needle
  hay="${all_name[$i]}"$'\x1f'"${all_summary[$i]}"$'\x1f'"${all_path[$i]}"
  hay=${hay:l}
  if [[ -n $filter_include ]]; then
    needle=${filter_include:l}
    [[ $hay == *${(b)needle}* ]] || return 1
  fi
  if [[ -n $filter_exclude ]]; then
    needle=${filter_exclude:l}
    [[ $hay == *${(b)needle}* ]] && return 1
  fi
  return 0
}

filter_session_items() {
  local -i i n_sess=0 n_match=0
  local keep
  if (( ${#all_kind} == 0 )); then
    copy_items_to_all
  fi
  if (( cursor >= 1 && cursor <= ${#items_id} )); then
    keep=${items_id[$cursor]}
  fi
  items_kind=()
  items_id=()
  items_name=()
  items_att=()
  items_time=()
  items_path=()
  items_summary=()
  items_cmd=()
  items_activity=()
  items_pinned=()
  for (( i = 1; i <= ${#all_kind}; i++ )); do
    if [[ ${all_kind[$i]} == session ]]; then
      (( n_sess++ ))
      if (( filter_on )) && ! session_src_matches $i; then
        continue
      fi
      (( n_match++ ))
    fi
    items_kind+=("${all_kind[$i]}")
    items_id+=("${all_id[$i]}")
    items_name+=("${all_name[$i]}")
    items_att+=("${all_att[$i]}")
    items_time+=("${all_time[$i]}")
    items_path+=("${all_path[$i]}")
    items_summary+=("${all_summary[$i]}")
    items_cmd+=("${all_cmd[$i]}")
    items_activity+=("${all_activity[$i]}")
    items_pinned+=("${all_pinned[$i]:-}")
  done
  filter_total_count=$n_sess
  filter_match_count=$n_match
  cursor=1
  if [[ -n ${keep:-} ]]; then
    for (( i = 1; i <= ${#items_id}; i++ )); do
      if [[ ${items_id[$i]} == "$keep" ]]; then
        cursor=$i
        break
      fi
    done
  fi
}

toggle_session_filter() {
  if (( filter_on )); then
    filter_on=0
  else
    load_session_filter
    filter_on=1
  fi
  filter_session_items
}

prompt_filter() {
  local which=$1 label kw
  if [[ $which == include ]]; then
    label='包含关键字（空或 Esc 清除）: '
  else
    label='排除关键字（空或 Esc 清除）: '
  fi
  restore_tty
  print
  print -n "$label"
  read -r kw || kw=
  if [[ $kw == $'\e' ]]; then
    kw=
  fi
  sanitize_filter_keyword "$kw"
  kw=$REPLY
  if [[ $which == include ]]; then
    filter_include=$kw
  else
    filter_exclude=$kw
  fi
  save_session_filter
  filter_on=1
  setup_tty
  filter_session_items
  draw
}

pinned_sessions_file() {
  lanjump_data_dir
  REPLY="$REPLY/pinned-sessions"
}

sanitize_pin_field() {
  local s=$1
  s=${s##[[:space:]]#}
  s=${s%%[[:space:]]#}
  s=${s//[$'\x00'-$'\x1f'$'\x7f']/}
  REPLY=$s
}

pin_record_exists() {
  local n=$1
  [[ -n $n ]] || return 1
  (( ${#pinned_names} )) || return 1
  (( ${pinned_names[(Ie)$n]} ))
}

load_pinned_sessions() {
  local file line key val name cwd grok
  pinned_sessions_file
  file=$REPLY
  pinned_names=()
  pinned_cwd=()
  pinned_grok=()
  [[ -f $file ]] || return 0
  name= cwd= grok=
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -z $line || $line == '#'* ]]; then
      if [[ -z $line && -n $name ]]; then
        pinned_names+=("$name")
        pinned_cwd[$name]=$cwd
        pinned_grok[$name]=$grok
        name= cwd= grok=
      fi
      continue
    fi
    key=${line%% *}
    if [[ $line == *' '* ]]; then
      val=${line#* }
    else
      val=
    fi
    sanitize_pin_field "$val"
    val=$REPLY
    case $key in
      name)
        if [[ -n $name ]]; then
          pinned_names+=("$name")
          pinned_cwd[$name]=$cwd
          pinned_grok[$name]=$grok
          cwd= grok=
        fi
        name=$val
        ;;
      cwd) cwd=$val ;;
      grok) grok=$val ;;
    esac
  done <"$file"
  if [[ -n $name ]]; then
    pinned_names+=("$name")
    pinned_cwd[$name]=$cwd
    pinned_grok[$name]=$grok
  fi
}

# Same-dir temp + rename so concurrent readers never see a torn dest (#213).
# Follow a dest symlink so the directory entry stays a link (#309).
replace_file_atomic() {
  local dest=$1 dir tmp
  [[ -L $dest ]] && dest=${dest:A}
  dir=${dest:h}
  mkdir -p "$dir"
  tmp=$(mktemp "${dir}/.${dest:t}.XXXXXX") || return 1
  cat >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$dest" || {
    rm -f "$tmp"
    return 1
  }
}

# Sidecar lock: dest is renamed by replace_file_atomic, so flock(dest) would
# not serialize writers. Same-file load+replace must hold this (#276).
with_data_file_lock() {
  local dest=$1
  shift
  local lock dir
  local -i fd=-1 st=0 n=0
  dir=${dest:h}
  lock=${dest}.lock
  mkdir -p "$dir"
  [[ -e $lock ]] || : >"$lock"
  if zmodload zsh/system 2>/dev/null && zsystem supports flock; then
    zsystem flock -f fd "$lock" || return 1
    "$@"
    st=$?
    zsystem flock -u fd
    return $st
  fi
  while ! mkdir "${lock}.d" 2>/dev/null; do
    sleep 0.05
    (( ++n > 200 )) && return 1
  done
  "$@"
  st=$?
  rmdir "${lock}.d" 2>/dev/null
  return $st
}

save_pinned_sessions() {
  local file n
  pinned_sessions_file
  file=$REPLY
  {
    for n in "${pinned_names[@]}"; do
      [[ -n $n ]] || continue
      print -r -- "name $n"
      print -r -- "cwd ${pinned_cwd[$n]:-}"
      print -r -- "grok ${pinned_grok[$n]:-}"
      print -r -- ""
    done
  } | replace_file_atomic "$file"
}

add_pin_record() {
  local name=$1 cwd=${2:-} grok=${3:-} st=0
  if [[ -z ${_LANJUMP_PIN_LOCKED:-} ]]; then
    pinned_sessions_file
    _LANJUMP_PIN_LOCKED=1
    with_data_file_lock "$REPLY" add_pin_record "$name" "$cwd" "$grok"
    st=$?
    unset _LANJUMP_PIN_LOCKED
    return $st
  fi
  sanitize_pin_field "$name"
  name=$REPLY
  [[ -n $name ]] || return 1
  sanitize_pin_field "$cwd"
  cwd=$REPLY
  sanitize_pin_field "$grok"
  grok=$REPLY
  [[ $grok == [A-Za-z0-9._-]## ]] || grok=
  load_pinned_sessions
  if pin_record_exists "$name"; then
    pinned_cwd[$name]=$cwd
    pinned_grok[$name]=$grok
  else
    pinned_names+=("$name")
    pinned_cwd[$name]=$cwd
    pinned_grok[$name]=$grok
  fi
  save_pinned_sessions
}

remove_pin_record() {
  local name=$1 st=0
  local -i i
  if [[ -z ${_LANJUMP_PIN_LOCKED:-} ]]; then
    pinned_sessions_file
    _LANJUMP_PIN_LOCKED=1
    with_data_file_lock "$REPLY" remove_pin_record "$name"
    st=$?
    unset _LANJUMP_PIN_LOCKED
    return $st
  fi
  sanitize_pin_field "$name"
  name=$REPLY
  [[ -n $name ]] || return 0
  load_pinned_sessions
  pin_record_exists "$name" || return 0
  for (( i = 1; i <= ${#pinned_names}; i++ )); do
    if [[ ${pinned_names[$i]} == "$name" ]]; then
      pinned_names[$i]=()
      break
    fi
  done
  unset "pinned_cwd[$name]"
  unset "pinned_grok[$name]"
  save_pinned_sessions
}

rename_pin_record() {
  local old=$1 new=$2 st=0
  local -i i
  if [[ -z ${_LANJUMP_PIN_LOCKED:-} ]]; then
    pinned_sessions_file
    _LANJUMP_PIN_LOCKED=1
    with_data_file_lock "$REPLY" rename_pin_record "$old" "$new"
    st=$?
    unset _LANJUMP_PIN_LOCKED
    return $st
  fi
  sanitize_pin_field "$old"
  old=$REPLY
  sanitize_pin_field "$new"
  new=$REPLY
  [[ -n $old && -n $new && $old != "$new" ]] || return 0
  load_pinned_sessions
  pin_record_exists "$old" || return 0
  for (( i = 1; i <= ${#pinned_names}; i++ )); do
    if [[ ${pinned_names[$i]} == "$old" ]]; then
      pinned_names[$i]=$new
      pinned_cwd[$new]=${pinned_cwd[$old]:-}
      pinned_grok[$new]=${pinned_grok[$old]:-}
      unset "pinned_cwd[$old]"
      unset "pinned_grok[$old]"
      save_pinned_sessions || return 1
      return 0
    fi
  done
}

grok_id_for_pid() {
  local pid=$1
  local file="$HOME/.grok/active_sessions.json" sid
  REPLY=
  [[ -n $pid && -f $file ]] || return 0
  (( ${+commands[python3]} )) || return 0
  sid=$(python3 -c '
import json, sys
pid = sys.argv[1]
path = sys.argv[2]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
best = None
best_ts = ""
for row in data:
    if str(row.get("pid", "")) != pid:
        continue
    ts = str(row.get("opened_at") or "")
    if best is None or ts >= best_ts:
        best = row
        best_ts = ts
sid = (best or {}).get("session_id") or ""
if sid:
    print(sid)
' "$pid" "$file" 2>/dev/null) || sid=
  REPLY=$sid
  print -r -- "$sid"
}

# Write a pin's directory only when the live path changed.
# Once per tmux_state_gen. The census is loaded before the pin lock;
# #467 keeps the locked body as re-read, merge, atomic write.
refresh_pin_cwds() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  tmux_state_load
  (( tm_server_up )) || return 0
  (( pin_cwd_refreshed_gen == tm_state_gen )) && return 0
  local st=0
  if [[ -z ${_LANJUMP_PIN_LOCKED:-} ]]; then
    pinned_sessions_file
    _LANJUMP_PIN_LOCKED=1
    with_data_file_lock "$REPLY" refresh_pin_cwds
    st=$?
    unset _LANJUMP_PIN_LOCKED
    return $st
  fi
  load_pinned_sessions
  local name live
  local -i changed=0
  for name in "${pinned_names[@]}"; do
    [[ -n $name ]] || continue
    (( ${tm_live[$name]:-0} )) || continue
    live=${tm_path[$name]:-}
    [[ -n $live ]] || continue
    # A pane sitting in $HOME is the default, not a move off the project.
    cwd_is_home "$live" && [[ -n ${pinned_cwd[$name]:-} ]] && continue
    [[ $live == ${pinned_cwd[$name]:-} ]] && continue
    pinned_cwd[$name]=$live
    changed=1
  done
  if (( changed )); then
    save_pinned_sessions || return 1
  fi
  pin_cwd_refreshed_gen=$tm_state_gen
}

# Settings, live cwd, and the detach hook before any restore decision.
prepare_pin_state() {
  load_settings
  load_pinned_sessions
  tmux_server_running || return 0
  tmux_install_snapshot_hooks
  refresh_pin_cwds
}

# Create one missing pin. Existing sessions are only marked. Progress text
# is drawn when restore_show_progress is set (interactive boot).
restore_one_missing_session() {
  local name=$1 cwd=$2
  local -i ok=0
  if tmux_session_live "$name"; then
    return 0
  fi
  if (( restore_show_progress )); then
    restore_progress_index=$(( restore_progress_index + 1 ))
    restore_progress_name=$name
    draw_restore_progress
  fi
  if [[ -n $cwd ]]; then
    tmuxx new-session -d -s "$name" -c "$cwd" 2>/dev/null && ok=1
  fi
  if (( ! ok )); then
    tmuxx new-session -d -s "$name" 2>/dev/null && ok=1
  fi
  if (( ok )); then
    tmux_state_invalidate
    (( restore_show_progress )) && restore_created_names+=("$name")
    return 0
  fi
  if (( restore_show_progress )); then
    restore_progress_failed+=("$name")
    draw_restore_progress
  fi
  return 1
}

restore_pinned_sessions() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  prepare_pin_state
  load_pinned_sessions
  local name cwd
  for name in "${pinned_names[@]}"; do
    [[ -n $name ]] || continue
    numeric_session_name "$name" && continue
    lanjump_foreign_session "$name" && continue
    cwd=$(resolve_session_cwd "$name")
    restore_one_missing_session "$name" "$cwd" || continue
  done
  tmux_server_running && tmux_install_snapshot_hooks
}

numeric_session_name() {
  [[ -n ${1:-} && $1 == [0-9]## ]]
}

# Unique non-numeric name so a pinned leftover 0/1 can restore (#145).
unique_non_numeric_session_name() {
  local base candidate
  local -i n=0
  base="s-${EPOCHSECONDS}"
  candidate=$base
  while (( n < 32 )); do
    if ! pin_record_exists "$candidate" && ! tmux_session_live "$candidate"; then
      REPLY=$candidate
      return 0
    fi
    (( ++n ))
    candidate="${base}-${n}"
  done
  REPLY="${base}-$$"
}

# Restore skips 0/1; rename first, then pin the new name (#145).
ensure_pinnable_session_name() {
  local name=$1 new
  REPLY=$name
  [[ -n $name ]] || return 1
  numeric_session_name "$name" || return 0
  load_pinned_sessions
  unique_non_numeric_session_name
  new=$REPLY
  tmuxx rename-session -t "=$name" "$new" 2>/dev/null || {
    REPLY=$name
    return 1
  }
  tmux_state_invalidate
  if ! rename_snap_record "$name" "$new"; then
    tmuxx rename-session -t "=$new" "$name" 2>/dev/null || true
    tmux_state_invalidate
    REPLY=$name
    return 1
  fi
  REPLY=$new
}

# CLI --pin-session: rename leftover 0/1, pin the new name, print it (#149).
pin_named_session() {
  local name=$1 cwd
  REPLY=
  [[ -n $name ]] || return 1
  load_settings
  load_pinned_sessions
  load_session_snapshot
  ensure_pinnable_session_name "$name" || return 1
  name=$REPLY
  cwd=$(resolve_session_cwd "$name")
  add_pin_record "$name" "${cwd:-$PWD}" "" || return
  REPLY=$name
  print -r -- "$name"
}

lanjump_foreign_session() {
  [[ -n ${1:-} && $1 == bmx-* ]]
}

session_snapshot_file() {
  lanjump_data_dir
  REPLY="$REPLY/session-snapshot"
}

_commit_snap_record() {
  local name=$1 cwd=$2 occ=$3 ws=$4 cmd=$5 att=$6
  [[ -n $name ]] || return
  snap_names+=("$name")
  snap_cwd[$name]=$cwd
  snap_occupied[$name]=${occ:-0}
  snap_cmd[$name]=$cmd
  snap_attached[$name]=${att:-0}
  if [[ -n $ws ]]; then
    snap_workspace[$name]=$ws
  else
    snap_workspace[$name]=${occ:-0}
  fi
}

load_session_snapshot() {
  local file line key val name cwd occ ws cmd att
  session_snapshot_file
  file=$REPLY
  snap_names=()
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  [[ -f $file ]] || return 0
  name= cwd= occ= ws= cmd= att=
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -z $line || $line == '#'* ]]; then
      if [[ -z $line && -n $name ]]; then
        _commit_snap_record "$name" "$cwd" "$occ" "$ws" "$cmd" "$att"
        name= cwd= occ= ws= cmd= att=
      fi
      continue
    fi
    key=${line%% *}
    if [[ $line == *' '* ]]; then
      val=${line#* }
    else
      val=
    fi
    sanitize_pin_field "$val"
    val=$REPLY
    case $key in
      name)
        if [[ -n $name ]]; then
          _commit_snap_record "$name" "$cwd" "$occ" "$ws" "$cmd" "$att"
          cwd= occ= ws= cmd= att=
        fi
        name=$val
        ;;
      cwd) cwd=$val ;;
      occupied) occ=$val ;;
      workspace) ws=$val ;;
      cmd) cmd=$val ;;
      attached) att=$val ;;
    esac
  done <"$file"
  if [[ -n $name ]]; then
    _commit_snap_record "$name" "$cwd" "$occ" "$ws" "$cmd" "$att"
  fi
}

drop_snap_record() {
  local name=$1
  local -i i
  [[ -n $name ]] || return 0
  for (( i = 1; i <= ${#snap_names}; i++ )); do
    if [[ ${snap_names[$i]} == "$name" ]]; then
      snap_names[$i]=()
      break
    fi
  done
  unset "snap_cwd[$name]"
  unset "snap_occupied[$name]"
  unset "snap_workspace[$name]"
  unset "snap_cmd[$name]"
  unset "snap_attached[$name]"
}

rename_snap_record() {
  local old=$1 new=$2 st=0
  local -i i
  if [[ -z ${_LANJUMP_SNAP_LOCKED:-} ]]; then
    session_snapshot_file
    _LANJUMP_SNAP_LOCKED=1
    with_data_file_lock "$REPLY" rename_snap_record "$old" "$new"
    st=$?
    unset _LANJUMP_SNAP_LOCKED
    return $st
  fi
  sanitize_pin_field "$old"
  old=$REPLY
  sanitize_pin_field "$new"
  new=$REPLY
  [[ -n $old && -n $new && $old != "$new" ]] || return 0
  load_session_snapshot
  for (( i = 1; i <= ${#snap_names}; i++ )); do
    if [[ ${snap_names[$i]} == "$old" ]]; then
      snap_names[$i]=$new
      snap_cwd[$new]=${snap_cwd[$old]:-}
      snap_cmd[$new]=${snap_cmd[$old]:-}
      snap_occupied[$new]=${snap_occupied[$old]:-}
      snap_workspace[$new]=${snap_workspace[$old]:-}
      snap_attached[$new]=${snap_attached[$old]:-}
      unset "snap_cwd[$old]"
      unset "snap_cmd[$old]"
      unset "snap_occupied[$old]"
      unset "snap_workspace[$old]"
      unset "snap_attached[$old]"
      if ! save_session_snapshot; then
        load_session_snapshot
        return 1
      fi
      return 0
    fi
  done
}

forget_killed_session() {
  local name=$1 st=0
  # Pin then snapshot, matching upgrade (#386). Nested remove_pin_record
  # must not take pin after this path already holds snapshot (#405).
  if [[ -z ${_LANJUMP_PIN_LOCKED:-} ]]; then
    pinned_sessions_file
    _LANJUMP_PIN_LOCKED=1
    with_data_file_lock "$REPLY" forget_killed_session "$name"
    st=$?
    unset _LANJUMP_PIN_LOCKED
    return $st
  fi
  if [[ -z ${_LANJUMP_SNAP_LOCKED:-} ]]; then
    session_snapshot_file
    _LANJUMP_SNAP_LOCKED=1
    with_data_file_lock "$REPLY" forget_killed_session "$name"
    st=$?
    unset _LANJUMP_SNAP_LOCKED
    return $st
  fi
  sanitize_pin_field "$name"
  name=$REPLY
  [[ -n $name ]] || return 0
  load_session_snapshot
  drop_snap_record "$name"
  if ! save_session_snapshot; then
    load_session_snapshot
    return 1
  fi
  remove_pin_record "$name" || return 1
}

save_session_snapshot() {
  local file n
  session_snapshot_file
  file=$REPLY
  {
    for n in "${snap_names[@]}"; do
      [[ -n $n ]] || continue
      print -r -- "name $n"
      print -r -- "cwd ${snap_cwd[$n]:-}"
      print -r -- "cmd ${snap_cmd[$n]:-}"
      print -r -- "occupied ${snap_occupied[$n]:-0}"
      print -r -- "workspace ${snap_workspace[$n]:-${snap_occupied[$n]:-0}}"
      print -r -- "attached ${snap_attached[$n]:-0}"
      print -r -- ""
    done
  } | replace_file_atomic "$file"
}

session_in_workspace() {
  local n=$1
  [[ ${snap_workspace[$n]:-${snap_occupied[$n]:-0}} == 1 ]]
}

snapshot_live_sessions() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  tmux_server_running || return 0
  local st=0
  if [[ -z ${_LANJUMP_SNAP_LOCKED:-} ]]; then
    session_snapshot_file
    _LANJUMP_SNAP_LOCKED=1
    with_data_file_lock "$REPLY" snapshot_live_sessions
    st=$?
    unset _LANJUMP_SNAP_LOCKED
    return $st
  fi
  local line name cwd att cmd
  local -a raw f names prev_names
  typeset -A prev_ws prev_cmd prev_cwd prev_att prev_seen live_seen
  local n keep_missing=0
  for n in "${snap_names[@]}"; do
    [[ -n $n ]] || continue
    prev_ws[$n]=${snap_workspace[$n]:-${snap_occupied[$n]:-0}}
    prev_cmd[$n]=${snap_cmd[$n]:-}
    prev_cwd[$n]=${snap_cwd[$n]:-}
    prev_att[$n]=${snap_attached[$n]:-0}
    if (( ! ${prev_seen[$n]:-0} )); then
      prev_names+=("$n")
    fi
    prev_seen[$n]=1
  done
  load_session_snapshot
  for n in "${snap_names[@]}"; do
    [[ -n $n ]] || continue
    prev_ws[$n]=${snap_workspace[$n]:-${snap_occupied[$n]:-0}}
    prev_cmd[$n]=${snap_cmd[$n]:-}
    prev_cwd[$n]=${snap_cwd[$n]:-}
    prev_att[$n]=${snap_attached[$n]:-0}
    if (( ! ${prev_seen[$n]:-0} )); then
      prev_names+=("$n")
    fi
    prev_seen[$n]=1
  done
  # First paint can snapshot leftover tmux before restore; keep missing names (#141).
  if should_restore_sessions; then
    keep_missing=1
  fi
  snap_names=()
  snap_cwd=()
  snap_occupied=()
  snap_workspace=()
  snap_cmd=()
  snap_attached=()
  # Census already loaded by tmux_server_running above. #467 reads it
  # outside this lock; do not list-sessions again while holding it.
  for name in "${tm_names[@]}"; do
    cwd=${tm_path[$name]:-}
    att=${tm_att[$name]:-0}
    cmd=${tm_cmd[$name]:-}
    [[ -n $name ]] || continue
    snap_names+=("$name")
    # resolve skips $HOME; keep the previous recorded cwd across that skip.
    snap_cwd[$name]=${prev_cwd[$name]:-}
    snap_cwd[$name]=$(resolve_session_cwd "$name" "${cwd:-${prev_cwd[$name]:-}}")
    snap_occupied[$name]=$att
    snap_cmd[$name]=$cmd
    if lanjump_foreign_session "$name"; then
      snap_workspace[$name]=${prev_ws[$name]:-0}
      snap_attached[$name]=${prev_att[$name]:-0}
    elif [[ $att == 1 ]]; then
      snap_workspace[$name]=1
      snap_attached[$name]=$EPOCHSECONDS
    elif (( ! ${prev_seen[$name]:-0} )) && ! numeric_session_name "$name"; then
      snap_workspace[$name]=1
      snap_attached[$name]=$EPOCHSECONDS
    else
      snap_workspace[$name]=${prev_ws[$name]:-0}
      snap_attached[$name]=${prev_att[$name]:-0}
    fi
  done
  if (( keep_missing )); then
    for n in "${snap_names[@]}"; do
      live_seen[$n]=1
    done
    for n in "${prev_names[@]}"; do
      [[ -n $n ]] || continue
      (( ${live_seen[$n]:-0} )) && continue
      snap_names+=("$n")
      snap_cwd[$n]=${prev_cwd[$n]:-}
      snap_cmd[$n]=${prev_cmd[$n]:-}
      snap_occupied[$n]=0
      snap_workspace[$n]=${prev_ws[$n]:-0}
      snap_attached[$n]=${prev_att[$n]:-0}
    done
  fi
  save_session_snapshot
}

mark_snapshot_occupied() {
  local name=$1 cwd cmd target st=0
  [[ -n $name ]] || return 0
  if [[ -z ${_LANJUMP_SNAP_LOCKED:-} ]]; then
    session_snapshot_file
    _LANJUMP_SNAP_LOCKED=1
    with_data_file_lock "$REPLY" mark_snapshot_occupied "$name"
    st=$?
    unset _LANJUMP_SNAP_LOCKED
    return $st
  fi
  load_session_snapshot
  # #467: these two reads still run under the snap lock. tmux_session_path
  # and tmux_session_cmd already hold the census; move the reads out with
  # the lock split.
  target=$(session_pane_target "$name")
  cwd=$(tmuxx display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null || true)
  cmd=$(tmuxx display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || true)
  if (( ${snap_names[(Ie)$name]} == 0 )); then
    snap_names+=("$name")
  fi
  [[ -n $cwd ]] && snap_cwd[$name]=$(resolve_session_cwd "$name" "$cwd")
  [[ -n $cmd ]] && snap_cmd[$name]=$cmd
  snap_occupied[$name]=1
  snap_workspace[$name]=1
  snap_attached[$name]=$EPOCHSECONDS
  save_session_snapshot
  pin_record_exists "$name" && refresh_pin_cwds
}

collect_restore_names() {
  restore_names=()
  restore_cwd=()
  local n
  typeset -A seen
  for n in "${pinned_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    (( ${seen[$n]:-0} )) && continue
    seen[$n]=1
    restore_names+=("$n")
    restore_cwd[$n]=$(resolve_session_cwd "$n")
  done
}

session_is_recent() {
  local n=$1 ts
  local -i window=${2:-$RESTORE_RECENT_SECS}
  ts=${snap_attached[$n]:-0}
  [[ $ts == [0-9]## ]] || return 1
  (( ts > 0 && EPOCHSECONDS - ts < window ))
}

collect_work_session_names() {
  work_names=()
  local n
  typeset -A seen
  for n in "${snap_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    pin_record_exists "$n" && continue
    session_is_recent "$n" "$WORK_RECENT_SECS" || continue
    (( ${seen[$n]:-0} )) && continue
    seen[$n]=1
    work_names+=("$n")
  done
}

collect_open_window_names() {
  open_window_names=()
  ghostty_names=()
  local n
  typeset -A seen
  for n in "${pinned_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    (( ${seen[$n]:-0} )) && continue
    seen[$n]=1
    open_window_names+=("$n")
  done
  for n in "${snap_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    session_is_recent "$n" || continue
    (( ${seen[$n]:-0} )) && continue
    seen[$n]=1
    open_window_names+=("$n")
  done
  ghostty_names=("${open_window_names[@]}")
}

collect_ghostty_session_names() {
  collect_open_window_names
}

build_restore_pick() {
  restore_pick_kind=()
  restore_pick_name=()
  restore_pick_checked=()
  local n
  typeset -A is_pin
  local -a pins recents
  pins=()
  recents=()
  for n in "${pinned_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    is_pin[$n]=1
    pins+=("$n")
  done
  for n in "${open_window_names[@]}"; do
    (( ${is_pin[$n]:-0} )) && continue
    recents+=("$n")
  done
  if (( ${#pins} )); then
    restore_pick_kind+=("header")
    restore_pick_name+=("常驻")
    restore_pick_checked+=(0)
    for n in "${pins[@]}"; do
      restore_pick_kind+=("item")
      restore_pick_name+=("$n")
      restore_pick_checked+=(1)
    done
  fi
  if (( ${#recents} )); then
    restore_pick_kind+=("header")
    restore_pick_name+=("最近")
    restore_pick_checked+=(0)
    for n in "${recents[@]}"; do
      restore_pick_kind+=("item")
      restore_pick_name+=("$n")
      restore_pick_checked+=(1)
    done
  fi
  restore_pick_cursor=1
  restore_pick_advance 1
}

restore_pick_advance() {
  local dir=${1:-1}
  local -i i=$restore_pick_cursor n=${#restore_pick_kind}
  (( n )) || return
  local -i guard=0
  while (( guard < n )); do
    if [[ ${restore_pick_kind[$i]} == item ]]; then
      restore_pick_cursor=$i
      return
    fi
    (( i += dir ))
    (( i < 1 )) && i=$n
    (( i > n )) && i=1
    (( guard++ ))
  done
}

draw_restore_pick() {
  local -i i row=1
  local mark box line
  restore_pick_row=()
  print -n $'\e[H\e[J\e[?25l'
  print -r -- "${c_bold}恢复后要打开哪些窗口？${c_reset}"
  print -r -- "${c_dim}空格/鼠标勾选    Enter 进入    t 新窗口    2 只要空 shell    q 不打开${c_reset}"
  print
  (( row += 3 ))
  for (( i = 1; i <= ${#restore_pick_kind}; i++ )); do
    restore_pick_row[$i]=$row
    if [[ ${restore_pick_kind[$i]} == header ]]; then
      print -r -- "${c_cyan}${restore_pick_name[$i]}${c_reset}"
    else
      if (( restore_pick_checked[i] )); then
        box='[x]'
      else
        box='[ ]'
      fi
      line="${box} ${restore_pick_name[$i]}"
      if (( i == restore_pick_cursor )); then
        print -r -- "${c_rev} ${line} ${c_reset}"
      else
        print -r -- " ${line}"
      fi
    fi
    (( row++ ))
  done
}

# CSI/SS3 third byte after ESC [ or ESC O. Left/right and PageDown-like
# leftovers are ignored; only a true Esc aborts the restore overlay.
restore_csi_key() {
  case ${1:-} in
    A) REPLY=up ;;
    B) REPLY=down ;;
    C|D) REPLY=other ;;
    *) REPLY=other ;;
  esac
}

# Match host/session lists: j up, k down. Arrows come from restore_csi_key
# (CSI ESC [ A/B and tmux application-cursor SS3 ESC O A/B).
restore_plain_key() {
  case ${1:-} in
    $'\n'|$'\r') REPLY=enter ;;
    ' ') REPLY=space ;;
    2) REPLY=two ;;
    t|T) REPLY=t ;;
    q|Q) REPLY=q ;;
    j|J) REPLY=up ;;
    k|K) REPLY=down ;;
    *) REPLY=other ;;
  esac
}

restore_read_key() {
  local k k2 k3 c buf
  read_byte || return 1
  k=$REPLY
  if [[ $k == $'\e' ]]; then
    read_byte 0.2 || { REPLY=esc; return 0 }
    k2=$REPLY
    # lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR).
    if [[ $k2 == $'\r' || $k2 == $'\n' ]]; then
      REPLY=other
      return 0
    fi
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      read_byte 0.2 || { REPLY=esc; return 0 }
      k3=$REPLY
      if [[ $k3 == '<' ]]; then
        buf=
        while read_byte 0.2; do
          c=$REPLY
          buf+=$c
          [[ $c == M || $c == m ]] && break
        done
        if [[ $buf == 0\;[0-9]##\;[0-9]##M ]]; then
          restore_mouse_col=${${buf#*;}%%;*}
          restore_mouse_row=${buf##*;}
          restore_mouse_row=${restore_mouse_row%M}
          REPLY=click
          return 0
        fi
        REPLY=other
        return 0
      fi
      restore_csi_key "$k3"
      if [[ $k3 == [0-9] ]]; then
        while read_byte 0.2; do
          c=$REPLY
          [[ $c == [A-Za-z~] ]] && break
        done
      fi
      return 0
    fi
    REPLY=esc
    return 0
  fi
  restore_plain_key "$k"
}

# Blocking read. After consecutive EOF/hangup failures, restore tty and
# exit so the restore-window loop cannot spin at 100% CPU (#270).
restore_read_key_or_exit() {
  if restore_read_key; then
    _read_key_fails=0
    return 0
  fi
  (( ++_read_key_fails >= 8 )) || return 1
  restore_tty
  exit 1
}

restore_pick_toggle() {
  local i=$1
  [[ ${restore_pick_kind[$i]:-} == item ]] || return
  if (( restore_pick_checked[i] )); then
    restore_pick_checked[i]=0
  else
    restore_pick_checked[i]=1
  fi
}

restore_pick_checked_names() {
  ghostty_names=()
  local -i i
  for (( i = 1; i <= ${#restore_pick_kind}; i++ )); do
    [[ ${restore_pick_kind[$i]} == item ]] || continue
    (( restore_pick_checked[i] )) || continue
    ghostty_names+=("${restore_pick_name[$i]}")
  done
}

# enter: one session attaches here; several (and t) open new windows.
restore_pick_finish() {
  local key=${1:-enter}
  restore_pick_checked_names
  if (( ! ${#ghostty_names} )); then
    restore_pick_action=skip
    return
  fi
  case $key in
    two)
      restore_pick_action=shell
      ;;
    t)
      restore_pick_action=resume
      ;;
    *)
      if (( ${#ghostty_names} > 1 )); then
        restore_pick_action=resume
      else
        restore_pick_action=attach
      fi
      ;;
  esac
}

prompt_restore_windows() {
  restore_pick_action=skip
  ghostty_names=()
  collect_open_window_names
  (( ${#open_window_names} )) || return 0
  build_restore_pick
  (( ${#restore_pick_kind} )) || return 0
  setup_tty
  print -n $'\e[?1000h\e[?1006h'
  trap draw_restore_pick WINCH
  while true; do
    draw_restore_pick
    restore_read_key_or_exit || continue
    case $REPLY in
      up)
        (( restore_pick_cursor-- ))
        (( restore_pick_cursor < 1 )) && restore_pick_cursor=${#restore_pick_kind}
        restore_pick_advance -1
        ;;
      down)
        (( restore_pick_cursor++ ))
        (( restore_pick_cursor > ${#restore_pick_kind} )) && restore_pick_cursor=1
        restore_pick_advance 1
        ;;
      space)
        restore_pick_toggle $restore_pick_cursor
        ;;
      click)
        local -i i
        for (( i = 1; i <= ${#restore_pick_kind}; i++ )); do
          if [[ ${restore_pick_kind[$i]} == item && ${restore_pick_row[$i]} == "$restore_mouse_row" ]]; then
            restore_pick_cursor=$i
            restore_pick_toggle $i
            break
          fi
        done
        ;;
      enter|t|two)
        restore_pick_finish "$REPLY"
        break
        ;;
      q|esc)
        restore_pick_action=skip
        ghostty_names=()
        break
        ;;
    esac
  done
  print -n $'\e[?1000l\e[?1006l'
  trap draw_on_winch WINCH
  restore_tty
  setup_tty
  print -n $'\e[H\e[J'
}

ensure_session_cwd() {
  local name=$1 want live target
  [[ -n $name ]] || return 0
  target=$(session_pane_target "$name")
  live=$(tmuxx display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null || true)
  [[ -n $live ]] || return 0
  want=$(resolve_session_cwd "$name" "$live")
  [[ -n $want ]] || return 0
  [[ $live == "$want" ]] && return 0
  tmuxx send-keys -t "$target" -- "cd ${(q)want}" Enter 2>/dev/null || true
}

maybe_resume_last_command() {
  local name=$1 live target
  [[ -n $name ]] || return 0
  target=$(session_pane_target "$name")
  live=$(tmuxx display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null || true)
  pane_is_idle_shell "$live" || return 0
  (( attach_shell_only )) && return 0
  # Idle pane: jump to a grok still running in another pane. Never respawn.
  select_live_grok_pane "$name" || true
}

last_session_file() {
  lanjump_data_dir
  REPLY="$REPLY/last-session"
}

remember_last_session() {
  local name=$1 file st=0
  [[ -n $name ]] || return 0
  last_session_file
  file=$REPLY
  mkdir -p "${file:h}"
  if [[ -z ${_LANJUMP_LAST_SESSION_LOCKED:-} ]]; then
    _LANJUMP_LAST_SESSION_LOCKED=1
    with_data_file_lock "$file" remember_last_session "$name"
    st=$?
    unset _LANJUMP_LAST_SESSION_LOCKED
    return $st
  fi
  print -r -- "$name" | replace_file_atomic "$file"
}

read_last_session_name() {
  local file s
  last_session_file
  file=$REPLY
  [[ -f $file ]] || return 1
  s=$(<"$file")
  s=${s%%$'\n'*}
  [[ -n $s ]] || return 1
  print -r -- "$s"
}

attach_named_session() {
  local name=$1 ask=${2:-0} want_new=${3:-0}
  [[ -n $name ]] || return 1
  load_session_snapshot
  if (( ask )); then
    restore_tty
    print
  fi
  mark_snapshot_occupied "$name"
  remember_last_session "$name"
  maybe_resume_last_command "$name"
  if [[ $(effective_open_target 1 $want_new) != current ]]; then
    restore_tty
    if open_workspace_tabs "$name"; then
      trap - EXIT
      exit 0
    fi
  fi
  tmux_tty attach-session -t "=$name"
  tmux_state_invalidate
  snapshot_live_sessions
  attach_shell_only=0
}

restore_saved_sessions() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  prepare_pin_state
  collect_restore_names
  local name cwd
  for name in "${restore_names[@]}"; do
    cwd=${restore_cwd[$name]:-}
    restore_one_missing_session "$name" "$cwd" || continue
  done
  tmux_server_running && tmux_install_snapshot_hooks
}

session_has_live_client() {
  local name=$1 clients
  [[ -n $name ]] || return 1
  clients=$(tmuxx list-clients -t "=$name" -F '#{client_tty}' 2>/dev/null) || return 1
  [[ -n $clients ]]
}

any_restore_session_live() {
  local n
  collect_restore_names
  (( ${#restore_names} )) || return 1
  for n in "${restore_names[@]}"; do
    tmux_session_live "$n" && return 0
  done
  return 1
}

should_restore_sessions() {
  collect_restore_names
  (( ${#restore_names} )) || return 1
  tmux_server_running || return 0
  any_restore_session_live && return 1
  return 0
}

settings_file() {
  lanjump_data_dir
  REPLY="$REPLY/settings"
}

default_project_roots() {
  project_roots=()
  [[ -d $HOME/Documents/projects ]] && project_roots=("$HOME/Documents/projects")
}

_remember_loaded_settings() {
  _settings_have_loaded=1
  _settings_loaded_open_target=$open_target
  _settings_loaded_open_placement=$open_placement
  _settings_loaded_project_roots=("${project_roots[@]}")
}

_settings_roots_match_loaded() {
  local -i i
  (( $# == ${#_settings_loaded_project_roots} )) || return 1
  for (( i = 1; i <= $#; i++ )); do
    [[ $argv[i] == "${_settings_loaded_project_roots[i]}" ]] || return 1
  done
  return 0
}

load_settings() {
  local file line key val
  local -i saw_project_root=0
  open_target=auto
  open_placement=window
  project_roots=()
  settings_file
  file=$REPLY
  if [[ -f $file ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ -z $line || $line == '#'* ]] && continue
      key=${line%% *}
      if [[ $line == *' '* ]]; then
        val=${line#* }
      else
        val=
      fi
      case $key in
        open_target)
          case $val in
            auto|ghostty|terminal) open_target=$val ;;
          esac
          ;;
        open_placement)
          case $val in
            window|tab) open_placement=$val ;;
          esac
          ;;
        project_root)
          val=${val##[[:space:]]#}
          val=${val%%[[:space:]]#}
          saw_project_root=1
          [[ -n $val ]] || continue
          project_roots+=("$val")
          ;;
      esac
    done <"$file"
  fi
  (( saw_project_root )) || default_project_roots
  _remember_loaded_settings
}

save_settings() {
  local file root st=0 my_target my_placement
  local -a my_roots
  local -i dirty_target=1 dirty_placement=1 dirty_roots=1
  settings_file
  file=$REPLY
  if [[ -z ${_LANJUMP_SETTINGS_LOCKED:-} ]]; then
    _LANJUMP_SETTINGS_LOCKED=1
    with_data_file_lock "$file" save_settings
    st=$?
    unset _LANJUMP_SETTINGS_LOCKED
    return $st
  fi
  my_target=$open_target
  my_placement=$open_placement
  my_roots=("${project_roots[@]}")
  if (( _settings_have_loaded )); then
    dirty_target=0
    dirty_placement=0
    dirty_roots=0
    [[ $my_target == "$_settings_loaded_open_target" ]] || dirty_target=1
    [[ $my_placement == "$_settings_loaded_open_placement" ]] || dirty_placement=1
    _settings_roots_match_loaded "${my_roots[@]}" || dirty_roots=1
  fi
  load_settings
  (( dirty_target )) && open_target=$my_target
  (( dirty_placement )) && open_placement=$my_placement
  if (( dirty_roots )); then
    project_roots=("${my_roots[@]}")
  fi
  {
    print -r -- "open_target ${open_target}"
    print -r -- "open_placement ${open_placement}"
    if (( ${#project_roots} )); then
      for root in "${project_roots[@]}"; do
        print -r -- "project_root ${root}"
      done
    else
      print -r -- "project_root"
    fi
  } | replace_file_atomic "$file"
  _remember_loaded_settings
}

settings_value_label() {
  case $1 in
    target)
      case $open_target in
        ghostty) print -r -- Ghostty ;;
        terminal) print -r -- 系统终端 ;;
        *) print -r -- '自动（Ghostty 优先）' ;;
      esac
      ;;
    placement)
      case $open_placement in
        tab) print -r -- 已有窗口加标签 ;;
        *) print -r -- 新开窗口 ;;
      esac
      ;;
  esac
}

cycle_setting() {
  case $settings_cursor in
    1)
      case $open_target in
        auto) open_target=ghostty ;;
        ghostty) open_target=terminal ;;
        *) open_target=auto ;;
      esac
      ;;
    2)
      if [[ $open_placement == window ]]; then
        open_placement=tab
      else
        open_placement=window
      fi
      ;;
  esac
  save_settings
}

settings_n_rows() {
  REPLY=$(( 3 + ${#project_roots} ))
}

settings_move() {
  local -i delta=$1 n
  settings_n_rows
  n=$REPLY
  (( n < 1 )) && return
  (( settings_cursor += delta ))
  if (( settings_cursor < 1 )); then
    settings_cursor=$n
  elif (( settings_cursor > n )); then
    settings_cursor=1
  fi
}

settings_remove_root() {
  local -i idx=$1 n
  (( idx >= 1 && idx <= ${#project_roots} )) || return 1
  project_roots[idx]=()
  project_roots=("${project_roots[@]}")
  save_settings
  settings_n_rows
  n=$REPLY
  (( settings_cursor > n )) && settings_cursor=$n
}

# d removes the selected root. Enter cycles 新窗口/窗口 or starts overlay input on ＋.
settings_enter() {
  local -i n=${#project_roots}
  case $settings_cursor in
    1|2) cycle_setting ;;
    *)
      if (( settings_cursor == 3 + n )); then
        settings_input_on=1
        settings_input_buf=
      fi
      ;;
  esac
}

settings_delete_key() {
  local -i n=${#project_roots}
  if (( settings_cursor >= 3 && settings_cursor < 3 + n )); then
    settings_remove_root $(( settings_cursor - 2 ))
  fi
}

settings_commit_input() {
  local root=$settings_input_buf
  settings_input_on=0
  settings_input_buf=
  root=${root##[[:space:]]#}
  root=${root%%[[:space:]]#}
  [[ -n $root ]] || return 0
  if [[ "$root" != /* && "$root" != '~' && "$root" != '~/'* ]]; then
    root="$PWD/$root"
  fi
  project_roots+=("$root")
  save_settings
  settings_cursor=$(( 2 + ${#project_roots} ))
}

# Raw-mode line editor for the settings overlay.
# REPLY=enter|esc|other|backspace|char. Lone Esc cancels; CSI/SS3 and ESC CR/LF are other.
settings_input_read() {
  local k k2 c
  read_byte || return 1
  k=$REPLY
  if [[ $k == $'\e' ]]; then
    read_byte 0.2 || { REPLY=esc; return 0 }
    k2=$REPLY
    # lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR).
    if [[ $k2 == $'\r' || $k2 == $'\n' ]]; then
      REPLY=other
      return 0
    fi
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      while read_byte 0.2; do
        c=$REPLY
        [[ $c == [A-Za-z~] ]] && break
      done
      REPLY=other
      return 0
    fi
    REPLY=esc
    return 0
  fi
  case $k in
    $'\n'|$'\r') REPLY=enter ;;
    $'\x7f'|$'\b') REPLY=backspace ;;
    *)
      REPLY=char
      settings_input_char=$k
      ;;
  esac
}

# Blocking read. After consecutive EOF/hangup failures, restore tty and
# exit so the settings input loop cannot spin at 100% CPU (#270).
settings_input_read_or_exit() {
  if settings_input_read; then
    _read_key_fails=0
    return 0
  fi
  (( ++_read_key_fails >= 8 )) || return 1
  restore_tty
  exit 1
}

# n sessions, want_new=1 means t (or CLI --open-tabs). n>1 always wants a
# new window. Missing Ghostty/Terminal (SSH, no local keyboard) → current.
effective_open_target() {
  local n=${1:-1}
  local want_new=${2:-0}
  local want=$open_target
  (( n > 1 )) && want_new=1
  if (( ! want_new )); then
    print -r -- current
    return
  fi
  case $want in
    ghostty)
      if ghostty_restore_available; then
        print -r -- ghostty
      else
        print -r -- current
      fi
      ;;
    terminal)
      if terminal_restore_available; then
        print -r -- terminal
      else
        print -r -- current
      fi
      ;;
    *)
      if ghostty_restore_available; then
        print -r -- ghostty
      elif terminal_restore_available; then
        print -r -- terminal
      else
        print -r -- current
      fi
      ;;
  esac
}

# List/restore key → current vs new-window target. Only t requests a new
# window for a single session; Shift+Enter is Grok newline, not a key here.
picker_open_mode() {
  local n=${1:-1} key=${2:-enter}
  local want_new=0
  [[ $key == t ]] && want_new=1
  effective_open_target "$n" "$want_new"
}

ghostty_restore_available() {
  local_keyboard || return 1
  [[ -d ${LANJUMP_GHOSTTY_APP:-/Applications/Ghostty.app} ]]
}

terminal_restore_available() {
  local_keyboard || return 1
  [[ -d /System/Applications/Utilities/Terminal.app || -d /Applications/Utilities/Terminal.app ]]
}

ghostty_attach_bin() {
  print -r -- "${LANJUMP_ATTACH_BIN:-$HOME/.local/bin/lanjump}"
}

ghostty_attach_helper() {
  local bin helper app
  if [[ -n ${LANJUMP_GHOSTTY_ATTACH:-} ]]; then
    print -r -- "$LANJUMP_GHOSTTY_ATTACH"
    return
  fi
  bin=$(ghostty_attach_bin)
  helper=${bin:h}/lanjump-ghostty-attach
  if [[ -x $helper ]]; then
    print -r -- "$helper"
    return
  fi
  # Ghostty login/bash -c needs a space-free command; restore ~/.local/bin (#32).
  app="$HOME/Library/Application Support/lanjump/lanjump-ghostty-attach"
  if [[ -x $app ]]; then
    mkdir -p "${helper:h}" 2>/dev/null || true
    if cp -f "$app" "$helper" 2>/dev/null; then
      chmod 755 "$helper" 2>/dev/null || true
      if [[ -x $helper ]]; then
        print -r -- "$helper"
        return
      fi
    fi
    print -r -- "$app"
    return
  fi
  print -r -- "$helper"
}

# AppleScript "..." treats \ as escape. osascript accepts \" for quotes, not "".
ghostty_applescript_string() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  print -r -- "\"$s\""
}

attaching_remote_host() {
  [[ -n ${LANJUMP_ATTACH_HOST:-} && ${LANJUMP_ATTACH_HOST} != local ]]
}

attach_spec_for() {
  local name=$1 host=${LANJUMP_ATTACH_HOST:-}
  if attaching_remote_host; then
    print -r -- "${host}:${name}"
  else
    print -r -- "$name"
  fi
}

attach_command_for() {
  local name=$1 spec
  spec=$(attach_spec_for "$name")
  if (( attach_shell_only )); then
    print -r -- "$(ghostty_attach_bin) attach --shell ${(q)spec}"
  else
    print -r -- "$(ghostty_attach_bin) attach ${(q)spec}"
  fi
}

# Terminal tab chips show argv0. exec -a so the pill is the session name (#127).
terminal_attach_command_for() {
  local name=$1 spec bin
  spec=$(attach_spec_for "$name")
  bin=$(ghostty_attach_bin)
  if (( attach_shell_only )); then
    print -r -- "exec -a ${(q)name} -- ${(q)bin} attach --shell ${(q)spec}"
  else
    print -r -- "exec -a ${(q)name} -- ${(q)bin} attach ${(q)spec}"
  fi
}

workspace_restore_prompt_text() {
  print -r -- "工作区：${(j:、:)@}"
  print -r -- "1  打开窗口"
  print -r -- "2  打开窗口，全部只要空 shell"
  print -r -- "回车  先不打开"
}

ghostty_restore_prompt_text() {
  workspace_restore_prompt_text "$@"
}

ghostty_cfg_lines() {
  local name=$1 helper spec env_list cwd
  # Ghostty on macOS runs command via `login … bash -c 'exec -l <command>'`.
  # Outer single quotes eat zsh quoting, so command must have no spaces or
  # quotes. Helper lives in ~/.local/bin; spec is surface env (#136).
  helper=$(ghostty_attach_helper)
  spec=$(attach_spec_for "$name")
  cwd=$(resolve_session_cwd "$name")
  print -r -- '  set cfg to new surface configuration'
  print -r -- "  set command of cfg to $(ghostty_applescript_string "$helper")"
  env_list=$(ghostty_applescript_string "LANJUMP_ATTACH_SPEC=${spec}")
  if (( attach_shell_only )); then
    env_list+=", $(ghostty_applescript_string LANJUMP_ATTACH_SHELL=1)"
  fi
  print -r -- "  set environment variables of cfg to {${env_list}}"
  if [[ -n $cwd ]]; then
    print -r -- "  set initial working directory of cfg to $(ghostty_applescript_string "$cwd")"
  fi
  print -r -- '  set wait after command of cfg to true'
}

ghostty_osascript_for_sessions() {
  local first n
  (( $# )) || return 1
  first=$1
  shift
  if (( ghostty_close_others )); then
    # #170: welcome and home-cwd sessions both title ~; snapshot SE ids first.
    print -r -- 'tell application "Ghostty"'
    print -r -- '  activate'
    print -r -- 'end tell'
    print -r -- 'delay 0.3'
    print -r -- 'tell application "System Events"'
    print -r -- '  tell process "Ghostty"'
    print -r -- '    set preexistingSE to {}'
    print -r -- '    try'
    print -r -- '      if (count of windows) > 0 then set preexistingSE to (id of every window) as list'
    print -r -- '    end try'
    print -r -- '  end tell'
    print -r -- 'end tell'
  fi
  print -r -- 'tell application "Ghostty"'
  print -r -- '  activate'
  print -r -- 'end tell'
  print -r -- 'delay 0.15'
  print -r -- 'tell application "Ghostty"'
  if (( ghostty_close_others )); then
    print -r -- '  set preexisting to {}'
    print -r -- '  try'
    print -r -- '    if (count of windows) > 0 then set preexisting to (id of every window) as list'
    print -r -- '  end try'
  fi
  ghostty_cfg_lines "$first"
  if [[ $open_placement == tab ]] && (( ! ghostty_close_others )); then
    print -r -- '  set win to missing value'
    print -r -- '  try'
    print -r -- '    if (count of windows) > 0 then set win to front window'
    print -r -- '  end try'
    print -r -- '  if win is missing value then'
    print -r -- '    set win to new window with configuration cfg'
    print -r -- '  else'
    print -r -- '    new tab in win with configuration cfg'
    print -r -- '  end if'
  else
    print -r -- '  set win to new window with configuration cfg'
  fi
  for n in "$@"; do
    ghostty_cfg_lines "$n"
    print -r -- '  new tab in win with configuration cfg'
  done
  if (( ghostty_close_others )); then
    print -r -- '  delay 0.3'
    print -r -- '  repeat with i in preexisting'
    print -r -- '    try'
    print -r -- '      close (first window whose id is i)'
    print -r -- '    end try'
    print -r -- '  end repeat'
  fi
  print -r -- '  activate'
  print -r -- 'end tell'
  if (( ghostty_close_others )); then
    print -r -- 'tell application "System Events"'
    print -r -- '  tell process "Ghostty"'
    print -r -- '    repeat with i in preexistingSE'
    print -r -- '      try'
    print -r -- '        perform action "AXPress" of (first button of (first window whose id is i) whose subrole is "AXCloseButton")'
    print -r -- '      end try'
    print -r -- '    end repeat'
    print -r -- '  end tell'
    print -r -- 'end tell'
  fi
}

terminal_apply_tab_title() {
  # Tab chips otherwise show `tmux attach-session -t =name`. Force the session name.
  print -r -- "  set custom title of t to $(ghostty_applescript_string "$1")"
  print -r -- '  set title displays custom title of t to true'
  print -r -- '  try'
  print -r -- '    set title displays file name of t to false'
  print -r -- '    set title displays window size of t to false'
  print -r -- '    set title displays settings name of t to false'
  print -r -- '    set title displays device name of t to false'
  print -r -- '    set title displays shell path of t to false'
  print -r -- '  end try'
}

terminal_tab_do_script() {
  # Extra sessions: Cmd+T in the window we just opened, never the picker tty.
  print -r -- 'tell application "System Events"'
  print -r -- '  tell process "Terminal"'
  print -r -- '    set frontmost to true'
  print -r -- '    keystroke "t" using command down'
  print -r -- '  end tell'
  print -r -- 'end tell'
  print -r -- 'delay 0.4'
  print -r -- 'tell application "Terminal"'
  print -r -- "  set t to do script $(ghostty_applescript_string "$1") in selected tab of front window"
  terminal_apply_tab_title "$2"
  print -r -- 'end tell'
}

terminal_osascript_for_sessions() {
  local first n cmd
  (( $# )) || return 1
  first=$1
  shift
  cmd=$(terminal_attach_command_for "$first")
  print -r -- 'tell application "Terminal" to activate'
  print -r -- 'delay 0.15'
  # Ghostty work: new window, then tabs in that window. Match that (#127).
  print -r -- 'tell application "Terminal"'
  print -r -- "  set t to do script $(ghostty_applescript_string "$cmd")"
  terminal_apply_tab_title "$first"
  print -r -- 'end tell'
  if [[ $open_placement == tab ]]; then
    for n in "$@"; do
      cmd=$(terminal_attach_command_for "$n")
      terminal_tab_do_script "$cmd" "$n"
    done
  else
    print -r -- 'tell application "Terminal"'
    for n in "$@"; do
      cmd=$(terminal_attach_command_for "$n")
      print -r -- "  set t to do script $(ghostty_applescript_string "$cmd")"
      terminal_apply_tab_title "$n"
    done
    print -r -- 'end tell'
  fi
}

ghostty_tab_titles() {
  osascript <<'APPLESCRIPT' 2>/dev/null
tell application "Ghostty"
  set out to ""
  repeat with w in windows
    repeat with t in tabs of w
      set out to out & name of t & linefeed
    end repeat
  end repeat
  return out
end tell
APPLESCRIPT
}

ghostty_focus_session() {
  local name=$1
  [[ -n $name ]] || return 1
  /usr/bin/osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Ghostty"
  repeat with w in windows
    repeat with t in tabs of w
      if name of t is $(ghostty_applescript_string "$name") or name of w is $(ghostty_applescript_string "$name") then
        try
          set selected of t to true
        end try
        activate
        return true
      end if
    end repeat
  end repeat
  return false
end tell
APPLESCRIPT
}

open_ghostty_session_tabs() {
  local n titles err
  local -a todo
  (( $# )) || return 0
  ghostty_close_others=0
  if ! pgrep -f '/Ghostty.app/Contents/MacOS/ghostty' >/dev/null 2>&1; then
    ghostty_close_others=1
  fi
  titles=
  if (( ! ghostty_close_others )); then
    titles=$(ghostty_tab_titles) || titles=
  fi
  todo=()
  for n in "$@"; do
    if ! attaching_remote_host && session_has_live_client "$n" && [[ -n $titles && ( $titles == *$'\n'"$n"$'\n'* || $titles == "$n"$'\n'* || $titles == *$'\n'"$n" || $titles == "$n" ) ]]; then
      ghostty_focus_session "$n" || true
      continue
    fi
    todo+=("$n")
  done
  (( ${#todo} )) || return 0
  err=$(ghostty_osascript_for_sessions "${todo[@]}" | /usr/bin/osascript 2>&1) || {
    print -u2 "无法打开 Ghostty${err:+：${err}}"
    return 1
  }
}

open_terminal_session_tabs() {
  (( $# )) || return 0
  # do script returns a tab; hide that so it does not land in the picker tty.
  terminal_osascript_for_sessions "$@" | osascript >/dev/null
}

open_workspace_tabs() {
  (( $# )) || return 0
  case $open_target in
    terminal)
      if terminal_restore_available; then
        open_terminal_session_tabs "$@" || {
          print -u2 "无法打开终端标签。"
          return 1
        }
        return 0
      fi
      print -u2 "没有可用的本机终端来打开窗口。"
      return 1
      ;;
  esac
  if ghostty_restore_available; then
    open_ghostty_session_tabs "$@" || {
      print -u2 "无法打开 Ghostty 标签。"
      return 1
    }
    return 0
  fi
  if terminal_restore_available; then
    open_terminal_session_tabs "$@" || {
      print -u2 "无法打开终端标签。"
      return 1
    }
    return 0
  fi
  print -u2 "没有可用的本机终端来打开窗口。"
  return 1
}

# CLI --open-tabs. Remote host:name never attaches a local tmux session here.
# Current-window (SSH / no local keyboard) can attach only one name: print
# the rest and resume only the session we actually enter.
open_named_tabs() {
  local n name keys client_term
  local -a rest
  (( $# )) || {
    print -u2 "没有可打开的 session。"
    return 1
  }
  if attaching_remote_host || [[ $(effective_open_target $# 1) != current ]]; then
    if (( ! attach_shell_only )) && ! attaching_remote_host; then
      for n in "$@"; do
        maybe_resume_last_command "$n"
      done
    fi
    open_workspace_tabs "$@"
    return $?
  fi
  if (( $# > 1 )); then
    rest=("${@:2}")
    print -u2 "当前窗口只能进入「$1」，未打开：${(j: :)rest}"
  fi
  name=$1
  if (( ! attach_shell_only )); then
    maybe_resume_last_command "$name"
  fi
  mark_snapshot_occupied "$name"
  remember_last_session "$name"
  tmux_prepare_color
  tmux_prepare_keys
  client_term=$(tmux_client_term)
  tmux_apply_client_term "$client_term"
  keys=
  if local_keyboard && keys=$(keys_bin); then
    TERM=$client_term exec "$keys" "$TMUX_BIN" attach-session -t "=$name"
  else
    TERM=$client_term exec "$TMUX_BIN" attach-session -t "=$name"
  fi
}

maybe_restore_sessions() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  load_pinned_sessions
  load_session_snapshot
  did_restore=0
  if should_restore_sessions; then
    restore_saved_sessions
    did_restore=1
  else
    restore_pinned_sessions
  fi
  if tmux_server_running; then
    tmux_install_snapshot_hooks
    refresh_pin_cwds
  fi
}

# No pending pins: settings/filter + load_items + setup_tty + the session list.
# Pending pins: same prefix, then a progress screen instead of the empty list.
# Restore runs after that first paint. The step array is the no-pending path;
# draw is last and is swapped when pins are missing.
typeset -a picker_boot_before_first_draw_steps picker_boot_after_first_draw_steps
picker_boot_before_first_draw_steps=(load_settings load_session_filter load_items setup_tty draw)
picker_boot_after_first_draw_steps=(maybe_restore_sessions tmux_prepare_color tmux_prepare_keys)

picker_run_named_steps() {
  local step
  for step in "$@"; do
    "$step"
  done
}

# Pins that still need a tmux session. Skips numeric names and bmx-*.
restore_boot_pending() {
  local n
  pending_restore_names=()
  [[ $HAS_TMUX -eq 1 ]] || return 1
  load_pinned_sessions
  load_session_snapshot
  collect_restore_names
  for n in "${restore_names[@]}"; do
    tmux_session_live "$n" && continue
    pending_restore_names+=("$n")
  done
  (( ${#pending_restore_names} ))
}

draw_restore_progress() {
  local fail
  print -n $'\e[H\e[J'
  print -r -- "  ${c_bold}正在恢复常驻 session${c_reset}"
  print -r -- ""
  if (( restore_progress_index > 0 )); then
    print -r -- "  ${restore_progress_index}/${restore_progress_total}  ${restore_progress_name}"
  else
    print -r -- "  0/${restore_progress_total}"
  fi
  for fail in "${restore_progress_failed[@]}"; do
    print -r -- "  失败  ${fail}"
  done
}

# Drop keypresses typed while the progress screen was up, so a buffered
# Enter cannot create a session the moment the list appears.
drain_pending_keys() {
  local junk
  [[ -t 0 ]] || return 0
  while IFS= read -rsk 1 -t 0 junk; do
    :
  done
  return 0
}

# Prefer the last session the user entered, when this boot recreated it.
place_restored_cursor() {
  local last n
  local -i i
  (( ${#restore_created_names} )) || return 0
  last=$(read_last_session_name 2>/dev/null) || last=
  if [[ -n $last ]]; then
    for n in "${restore_created_names[@]}"; do
      [[ $n == $last ]] || continue
      for (( i = 1; i <= ${#items_id}; i++ )); do
        if [[ ${items_id[$i]} == $last ]]; then
          cursor=$i
          return 0
        fi
      done
    done
  fi
  for (( i = 1; i <= ${#items_id}; i++ )); do
    for n in "${restore_created_names[@]}"; do
      if [[ ${items_id[$i]} == $n ]]; then
        cursor=$i
        return 0
      fi
    done
  done
}

picker_boot_before_first_draw() {
  filter_on=0
  picker_run_named_steps "${(@)picker_boot_before_first_draw_steps[1,-2]}"
  if restore_boot_pending; then
    restore_show_progress=1
    restore_progress_on=1
    restore_progress_total=${#pending_restore_names}
    restore_progress_index=0
    restore_progress_name=
    restore_progress_failed=()
    restore_created_names=()
    restore_boot_notice=
    draw_restore_progress
  else
    restore_show_progress=0
    restore_progress_on=0
    restore_boot_notice=
    draw
  fi
}

picker_boot_after_first_draw() {
  local saved_stty=${stty_orig:-} before
  local -i showed=$restore_show_progress
  before=${(j:\0:)items_id}
  restore_created_names=()
  picker_run_named_steps "${picker_boot_after_first_draw_steps[@]}"
  [[ -n $saved_stty ]] && stty_orig=$saved_stty
  # First paint already loaded items. Read again only when this boot
  # created sessions or a mutating tmux command marked the census dirty.
  if (( ${#restore_created_names} || tm_state_dirty )); then
    load_items
  fi
  if (( showed )); then
    drain_pending_keys
    restore_show_progress=0
    restore_progress_on=0
    if (( ${#restore_progress_failed} )); then
      restore_boot_notice="已恢复 ${#restore_created_names} 个，失败 ${#restore_progress_failed} 个"
    else
      restore_boot_notice="已恢复 ${#restore_created_names} 个"
    fi
    place_restored_cursor
    draw
  elif [[ ${(j:\0:)items_id} != "$before" ]]; then
    draw
  fi
}

bulk_idle_unpinned_names() {
  local -i i
  local -a names
  local name
  names=()
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    [[ ${items_kind[$i]} == session ]] || continue
    [[ ${items_att[$i]} == 1 ]] && continue
    [[ ${items_pinned[$i]:-0} == 1 ]] && continue
    name=${items_id[$i]}
    lanjump_foreign_session "$name" && continue
    names+=("$name")
  done
  print -r -- "${names[*]}"
}

delete_idle_unpinned_sessions() {
  local -i i st=0
  local name
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    [[ ${items_kind[$i]} == session ]] || continue
    [[ ${items_att[$i]} == 1 ]] && continue
    [[ ${items_pinned[$i]:-0} == 1 ]] && continue
    name=${items_id[$i]}
    lanjump_foreign_session "$name" && continue
    if tmuxx kill-session -t "=$name" 2>/dev/null; then
      tmux_state_invalidate
      forget_killed_session "$name" || st=1
    fi
  done
  return $st
}

session_delete_needs_pin_warning() {
  [[ ${items_kind[$cursor]:-} == session && ${items_pinned[$cursor]:-0} == 1 ]]
}

pin_delete_warning_text() {
  print -r -- '该 session 为常驻状态，是否确认删除？'
}

toggle_session_pin() {
  [[ $HAS_TMUX -eq 1 ]] || return
  if [[ ${items_kind[$cursor]:-} != session ]]; then
    return
  fi
  local name=${items_id[$cursor]} old cwd pid grok
  local -i i on=0
  old=$name
  if [[ ${items_pinned[$cursor]:-0} == 1 ]]; then
    remove_pin_record "$name" || return
    on=0
  else
    lanjump_foreign_session "$name" && return
    ensure_pinnable_session_name "$name" || return
    name=$REPLY
    cwd=$(tmuxx display-message -p -t "$(session_pane_target "$name")" '#{pane_current_path}' 2>/dev/null || true)
    pid=$(tmuxx display-message -p -t "$(session_pane_target "$name")" '#{pane_pid}' 2>/dev/null || true)
    grok=$(grok_id_for_pid "$pid")
    add_pin_record "$name" "$cwd" "$grok" || return
    on=1
    items_id[$cursor]=$name
    items_name[$cursor]=$name
  fi
  items_pinned[$cursor]=$on
  for (( i = 1; i <= ${#all_id}; i++ )); do
    if [[ ${all_id[$i]} == "$old" ]]; then
      all_id[$i]=$name
      all_name[$i]=$name
      all_pinned[$i]=$on
      break
    fi
  done
}

# r, and the return from a normal shell, must see sessions another
# terminal created or killed. Those paths do not run new-session,
# kill-session, or rename-session, so the census stays warm until dropped.
refresh_external_sessions() {
  tmux_state_invalidate
  load_items "$@"
}

load_items() {
  loading=1
  local keep="${1-}" line when title cmd wname pin
  local -a raw f
  if [[ -z $keep ]] && (( cursor >= 1 && cursor <= ${#items_id} )); then
    keep=${items_id[$cursor]}
  fi

  load_pinned_sessions
  local n act
  items_kind=()
  items_id=()
  items_name=()
  items_att=()
  items_time=()
  items_path=()
  items_summary=()
  items_cmd=()
  items_activity=()
  items_pinned=()  preview_cache=() preview_cache_heading=()
  session_titles=()
  raw=()

  tmux_state_load
  if (( tm_server_up && ${#tm_names} )); then
    for n in "${tm_names[@]}"; do
      act=${tm_activity[$n]:-}
      [[ $act == [0-9]## ]] || act=$EPOCHSECONDS
      strftime -s when '%m-%d %H:%M' "$act"
      wname=${tm_wname[$n]:-}
      title=${tm_title[$n]:-}
      cmd=${tm_cmd[$n]:-}
      pin=0
      pin_record_exists "$n" && pin=1
      items_kind+=("session")
      items_id+=("$n")
      items_name+=("$n")
      items_att+=("${tm_att[$n]:-0}")
      items_time+=("$when")
      items_path+=("$(short_path "${tm_path[$n]:-}")")
      items_summary+=("$(useful_summary "$title" "$cmd" "$wname")")
      session_titles[$n]=$title
      items_cmd+=("$cmd")
      items_activity+=("$act")
      items_pinned+=("$pin")
    done
    snapshot_live_sessions
    refresh_pin_cwds
  fi

  if [[ $HAS_TMUX -eq 1 ]]; then
    items_kind+=("new")
    items_id+=("new")
    items_name+=("新建 session")
    items_att+=("")
    items_time+=("")
    items_path+=("")
    items_summary+=("")
    items_cmd+=("")
    items_activity+=("")
    items_pinned+=("")
  fi

  items_kind+=("shell")
  items_id+=("shell")
  items_name+=("普通 shell（不进 tmux，exit 返回）")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")
  items_activity+=("")
  items_pinned+=("")

  items_kind+=("hosts")
  items_id+=("hosts")
  items_name+=("换一台机器")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")
  items_activity+=("")
  items_pinned+=("")

  items_kind+=("quit")
  items_id+=("quit")
  items_name+=("退出")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")
  items_activity+=("")
  items_pinned+=("")

  sort_session_items "$keep"
  copy_items_to_all
  filter_session_items
  loading=0
}

preview_is_product_title() {
  local s=$1 stripped
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  [[ -n $s ]] || return 1
  stripped=${s//[[:space:]]/}
  [[ $stripped == (#i)(tomax|grok) ]] && return 0
  [[ $stripped == (#i)(tomax|grok)[-0-9.]* ]] && return 0
  return 1
}

preview_is_grok() {
  [[ ${1:-} == (#i)*grok* ]]
}

preview_line_is_bare_prompt() {
  local line=$1 stripped
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  stripped=${line//[[:space:]]/}
  [[ $stripped == '>' || $stripped == '❯' || $stripped == '%' || $stripped == '$' || $stripped == '#' ]]
}

preview_line_is_prompt() {
  local line=$1
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n $line ]] || return 1
  preview_line_is_bare_prompt "$line" && return 0
  [[ $line == ('% '|'$ '|'> '|'# '|$'❯ ')* ]] && return 0
  return 1
}

preview_line_is_status() {
  local line=$1
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n $line ]] || return 1
  [[ $line == [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]* ]] && return 0
  [[ $line == (#i)*[[:space:]]-[[:space:]]responding[[:space:]]-* ]] && return 0
  [[ $line == (#i)*[[:space:]]-[[:space:]]thinking[[:space:]]-* ]] && return 0
  [[ $line == (#i)*waiting[[:space:]]for[[:space:]]response* ]] && return 0
  [[ $line == (#i)worked[[:space:]]for[[:space:]][0-9]* ]] && return 0
  [[ $line == (#i)*compactions[[:space:]]remaining* ]] && return 0
  return 1
}

preview_line_is_shortcut_bar() {
  local line=$1
  [[ $line == (#i)*space:prompt* ]] && return 0
  [[ $line == *Ctrl+* && $line == *│* ]] && return 0
  [[ $line == (#i)*:dashboard* && $line == (#i)*:shortcuts* ]] && return 0
  return 1
}

preview_line_is_model() {
  local s=$1 stripped
  preview_is_product_title "$s" && return 0
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  stripped=${s//[[:space:]]/}
  [[ $stripped == (#i)grok[0-9.]* ]] && return 0
  if [[ $s == *[█░▒▓─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋═║╔╗╚╝╠╣╦╩╬╭╮╯╰]* ]]; then
    [[ $s == (#i)*grok[[:space:]]#[0-9.]* ]] && return 0
    [[ $s == (#i)*always-approve* ]] && return 0
    [[ $s == (#i)*'(xhigh)'* || $s == (#i)*xhigh* ]] && return 0
  fi
  return 1
}

preview_line_is_tool() {
  local line=$1
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -n $line ]] || return 1
  [[ $line == (#i)calling[[:space:]]* ]] && return 0
  [[ $line == (#i)(function|tool)[[:space:]]#(result|call)* ]] && return 0
  [[ $line == \{* || $line == \[* || $line == \}* ]] && return 0
  [[ $line == [[:alnum:]_-]##__[[:alnum:]_-]##* ]] && return 0
  [[ $line == ◆* || $line == ◈* ]] && return 0
  return 1
}

preview_line_is_chrome() {
  local line=$1 stripped rest arrows
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#"${line%%[![:space:]]*}"}"
  stripped=${line//[[:space:]]/}
  [[ -z $stripped ]] && return 0
  [[ $stripped == █## ]] && return 0
  arrows=${line//[▲▼[:space:]]/}
  [[ -z $arrows && $line == *[▲▼]* ]] && return 0
  rest=$stripped
  rest=${rest//[█░▒▓─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋═║╔╗╚╝╠╣╦╩╬╭╮╯╰▶▷▸•·▲▼]/}
  rest=${rest//[❯>]/}
  rest=${rest//[[:punct:]]/}
  [[ -z $rest ]] && return 0
  [[ $line == *⎇* ]] && return 0
  [[ $line == *[0-9]K[[:space:]]/[[:space:]][0-9]#K* ]] && return 0
  preview_line_is_bare_prompt "$line" && return 0
  preview_is_product_title "$line" && return 0
  preview_line_is_model "$line" && return 0
  preview_line_is_status "$line" && return 0
  preview_line_is_shortcut_bar "$line" && return 0
  return 1
}

preview_strip_grok_line() {
  local line=$1
  line="${line%"${line##*[![:space:]]}"}"
  line="${line#"${line%%[![:space:]]*}"}"
  while [[ $line == *█ ]]; do
    line=${line%█}
  done
  line="${line%"${line##*[![:space:]]}"}"
  if [[ $line =~ '^(.*)[[:space:]]+[0-9]{1,2}:[0-9]{2}[[:space:]]*(AM|PM|am|pm)[[:space:]]*$' ]]; then
    line=$match[1]
    line="${line%"${line##*[![:space:]]}"}"
  fi
  if [[ $line == *'[Dashboard]'* ]]; then
    line=${line%%[[:space:]]#\[Dashboard\]*}
    line="${line%"${line##*[![:space:]]}"}"
  fi
  print -r -- "$line"
}

preview_clean_title() {
  local t=$1
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  [[ -n $t ]] || return 1
  t=${t##[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏[:space:]]#}
  t="${t#"${t%%[![:space:]]*}"}"
  [[ $t == '- '* ]] && t=${t#- }
  t="${t#"${t%%[![:space:]]*}"}"
  if [[ $t == (#i)waiting[[:space:]]for[[:space:]]response* || $t == (#i)responding* || $t == (#i)thinking* ]]; then
    if [[ $t == *' - '* ]]; then
      t=${t#* - }
    else
      return 1
    fi
  fi
  if [[ $t == (#i)*' - grok-'* ]]; then
    t=${t% - grok-*}
  elif [[ $t == (#i)*' - grok' ]]; then
    t=${t%[ ]-[ ][Gg]rok}
  fi
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  [[ -n $t ]] || return 1
  preview_is_product_title "$t" && return 1
  preview_line_is_status "$t" && return 1
  print -r -- "$t"
}

preview_useful_title() {
  local title=$1 name=$2 cmd=$3 wname=${4:-} short cleaned
  cleaned=$(preview_clean_title "$title") || return 1
  short=$(short_command_name "$cmd")
  [[ $cleaned != "$name" && $cleaned != "$cmd" && $cleaned != "$short" ]] || return 1
  [[ -n $wname && $cleaned == "$wname" ]] && preview_is_product_title "$wname" && return 1
  print -r -- "$cleaned"
}

preview_conversation_heading() {
  local line
  for line in "$@"; do
    preview_line_is_chrome "$line" && continue
    preview_line_is_prompt "$line" && continue
    print -r -- "$line"
    return 0
  done
  return 1
}

preview_keep_useful_from_cap() {
  local cap=$1 line stripped
  local -i drop_grok_noise=${2:-0} saw_blank=0
  kept=()
  for line in "${(@f)cap}"; do
    line="${line%"${line##*[![:space:]]}"}"
    stripped=${line//[[:space:]]/}
    if [[ -z $stripped ]]; then
      (( saw_blank )) && continue
      kept+=("")
      saw_blank=1
      continue
    fi
    if preview_line_is_chrome "$line"; then
      continue
    fi
    if (( drop_grok_noise )); then
      preview_line_is_tool "$line" && continue
      preview_line_is_model "$line" && continue
      if [[ $line == '❯ '* ]]; then
        line=${line#'❯ '}
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -n $line ]] || continue
      fi
    fi
    saw_blank=0
    kept+=("$line")
  done
  while (( ${#kept} )) && [[ -z "${kept[1]}" ]]; do
    kept=("${(@)kept[2,-1]}")
  done
  while (( ${#kept} )) && [[ -z "${kept[-1]}" ]]; do
    kept=("${(@)kept[1,-2]}")
  done
}

_preview_grok_lines() {
  local -i max_body=$1 i n u=0 a=0 take
  local line kind
  local -a lines tags after
  shift
  picked=()
  (( max_body < 1 )) && return
  for line in "$@"; do
    line=$(preview_strip_grok_line "$line")
    [[ -n ${line//[[:space:]]/} ]] || continue
    preview_line_is_chrome "$line" && continue
    preview_line_is_bare_prompt "$line" && continue
    preview_line_is_tool "$line" && continue
    preview_line_is_model "$line" && continue
    preview_line_is_status "$line" && continue
    kind=asst
    if [[ $line == '❯ '* ]]; then
      line=${line#'❯ '}
      kind=user
    elif [[ $line == '> '* ]]; then
      line=${line#'> '}
      kind=user
    fi
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -n $line ]] || continue
    lines+=("$line")
    tags+=("$kind")
  done
  n=${#lines}
  (( n == 0 )) && return
  for (( i = n; i >= 1; i-- )); do
    [[ ${tags[i]} == user && u -eq 0 ]] && u=$i
    [[ ${tags[i]} == asst && a -eq 0 ]] && a=$i
    (( u && a )) && break
  done
  if (( u )); then
    picked+=("${lines[u]}")
    after=()
    for (( i = u + 1; i <= n; i++ )); do
      [[ ${tags[i]} == asst ]] && after+=("${lines[i]}")
    done
    if (( ${#after} == 0 )); then
      for (( i = 1; i < u; i++ )); do
        [[ ${tags[i]} == asst ]] && after+=("${lines[i]}")
      done
    fi
    take=$(( max_body - 1 ))
    (( take < 1 )) && take=1
    if (( ${#after} > take )); then
      after=("${(@)after[-take,-1]}")
    fi
    picked+=("${after[@]}")
    if (( ${#picked} > max_body )); then
      picked=("${(@)picked[-max_body,-1]}")
    fi
  else
    if (( n > max_body )); then
      picked=("${(@)lines[-max_body,-1]}")
    else
      picked=("${lines[@]}")
    fi
  fi
}

preview_grok_lines() {
  local -a picked
  _preview_grok_lines "$@"
  (( ${#picked} )) && print -l -- "${picked[@]}"
}

_preview_generic_lines() {
  local -i max_body=$1 i last_cmd=0 nout
  local line low
  local -a all rest
  shift
  picked=()
  (( max_body < 1 )) && return
  for line in "$@"; do
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n ${line//[[:space:]]/} ]] || continue
    preview_line_is_chrome "$line" && continue
    preview_line_is_bare_prompt "$line" && continue
    low=${line:l}
    [[ $low == (zsh|bash|sh|fish|dash|login) ]] && continue
    all+=("$line")
  done
  for (( i = 1; i <= ${#all}; i++ )); do
    if preview_line_is_prompt "${all[i]}" && ! preview_line_is_bare_prompt "${all[i]}"; then
      last_cmd=$i
    fi
  done
  if (( last_cmd )); then
    picked+=("${all[last_cmd]}")
    for (( i = last_cmd + 1; i <= ${#all}; i++ )); do
      preview_line_is_prompt "${all[i]}" && continue
      picked+=("${all[i]}")
    done
  else
    picked=("${all[@]}")
  fi
  if (( ${#picked} > max_body )); then
    if (( last_cmd )) && preview_line_is_prompt "${picked[1]}"; then
      rest=("${(@)picked[2,-1]}")
      if (( max_body == 1 )); then
        (( ${#rest} )) && picked=("${rest[-1]}")
      else
        nout=$(( max_body - 1 ))
        (( ${#rest} > nout )) && rest=("${(@)rest[-nout,-1]}")
        picked=("${picked[1]}" "${rest[@]}")
      fi
    else
      picked=("${(@)picked[-max_body,-1]}")
    fi
  fi
}

preview_generic_lines() {
  local -a picked
  _preview_generic_lines "$@"
  (( ${#picked} )) && print -l -- "${picked[@]}"
}

preview_select_lines() {
  local cmd=$1
  local -i max_body=$2
  local -a picked
  shift 2
  if preview_is_grok "$cmd"; then
    _preview_grok_lines $max_body "$@"
  else
    _preview_generic_lines $max_body "$@"
  fi
  (( ${#picked} )) && print -l -- "${picked[@]}"
}

session_preview_lines() {
  local name=$1 cmd=$3
  local title=${4:-${session_titles[$name]:-}}
  local -i max_lines=$2 grok=0 room
  local cap title_line heading
  local -a kept picked
  preview_lines=()
  preview_heading=
  (( max_lines > preview_max_lines )) && max_lines=$preview_max_lines
  (( max_lines < 1 )) && return
  preview_is_grok "$cmd" && grok=1

  cap=$(tmuxx capture-pane -t "=$name:." -p -J 2>/dev/null) || cap=""
  preview_keep_useful_from_cap "$cap" $grok
  if (( ${#kept} == 0 )); then
    cap=$(tmuxx capture-pane -t "=$name:." -a -p 2>/dev/null) || cap=""
    preview_keep_useful_from_cap "$cap" $grok
  fi

  title_line=$(preview_useful_title "$title" "$name" "$cmd") || title_line=
  if (( grok )) && [[ -z $title_line ]]; then
    heading=$(preview_conversation_heading "${kept[@]}") || heading=
    title_line=$(preview_useful_title "$heading" "$name" "$cmd") || title_line=
  fi
  if (( grok )); then
    preview_heading=$title_line
    room=$max_lines
    (( room > 6 )) && room=6
    (( room < 1 )) && room=1
    _preview_grok_lines $room "${kept[@]}"
    preview_lines=("${picked[@]}")
    return
  fi
  if [[ -n $title_line && ${#kept} -gt 0 && ${kept[1]} == "$title_line" ]]; then
    if (( ${#kept} == 1 )); then
      kept=()
    else
      kept=("${(@)kept[2,-1]}")
    fi
  fi
  room=$max_lines
  [[ -n $title_line ]] && (( room-- ))
  (( room < 1 )) && room=1
  (( room > 3 )) && room=3
  _preview_generic_lines $room "${kept[@]}"
  if [[ -n $title_line && ${#picked} -gt 0 && ${picked[1]} == "$title_line" ]]; then
    if (( ${#picked} == 1 )); then
      picked=()
    else
      picked=("${(@)picked[2,-1]}")
    fi
  fi
  if (( ${#picked} == 0 )); then
    [[ -n $title_line ]] || return
    preview_lines=("$title_line")
    return
  fi
  if [[ -n $title_line ]]; then
    preview_lines=("$title_line" "${picked[@]}")
  else
    preview_lines=("${picked[@]}")
  fi
}

preview_render_grok() {
  local name=$1 pane_title=$2 cmd=$3 dump=$4
  local -a kept picked
  local heading
  preview_keep_useful_from_cap "$dump" 1
  heading=$(preview_useful_title "$pane_title" "$name" "$cmd") || heading=
  if [[ -z $heading ]]; then
    heading=$(preview_conversation_heading "${kept[@]}") || heading=
    heading=$(preview_useful_title "$heading" "$name" "$cmd") || heading=
  fi
  _preview_grok_lines 6 "${kept[@]}"
  print -r -- "预览  ${name}  grok"
  [[ -n $heading ]] && print -r -- "标题：${heading}"
  (( ${#picked} )) && print -l -- "${picked[@]}"
}

# Sticky window of `vis` item rows that keeps `cur` on screen.
# Sets view_start view_end view_above view_below (1-based inclusive).
list_window() {
  local -i n=$1 vis=$2 cur=$3
  view_end=0
  view_above=0
  view_below=0
  (( n < 1 )) && { view_start=1; return }
  (( vis < 1 )) && vis=1
  (( vis > n )) && vis=n
  (( cur < 1 )) && cur=1
  (( cur > n )) && cur=n
  (( view_start < 1 )) && view_start=1
  if (( cur < view_start )); then
    view_start=$cur
  fi
  if (( cur > view_start + vis - 1 )); then
    view_start=$(( cur - vis + 1 ))
  fi
  if (( view_start + vis - 1 > n )); then
    view_start=$(( n - vis + 1 ))
  fi
  (( view_start < 1 )) && view_start=1
  view_end=$(( view_start + vis - 1 ))
  (( view_end > n )) && view_end=n
  view_above=$(( view_start - 1 ))
  view_below=$(( n - view_end ))
}

# Fit list + overflow hints + optional section gap into `body` rows.
# gap_after: emit a blank after this index when the window spans it (0 = none).
plan_list_view() {
  local -i body=$1 n=$2 cur=$3 gap_after=${4:-0}
  local -i hints vis need max_hints
  (( n < 1 || body < 1 )) && {
    view_start=1
    view_end=0
    view_above=0
    view_below=0
    return
  }
  # Keep at least one row for the selected item; hints use leftovers only.
  max_hints=2
  (( max_hints > body - 1 )) && max_hints=$(( body - 1 ))
  (( max_hints < 0 )) && max_hints=0
  for (( hints = 0; hints <= max_hints; hints++ )); do
    vis=$(( body - hints ))
    (( vis < 1 )) && vis=1
    list_window $n $vis $cur
    if (( gap_after > 0 && view_start <= gap_after && view_end > gap_after )); then
      vis=$(( body - hints - 1 ))
      (( vis < 1 )) && vis=1
      list_window $n $vis $cur
    fi
    need=0
    (( view_above > 0 )) && (( need++ ))
    (( view_below > 0 )) && (( need++ ))
    (( need == hints )) && break
  done
  (( hints > max_hints )) && hints=$max_hints
  # Drop hints that did not get a row so they cannot steal the selected item.
  if (( view_above > 0 )); then
    if (( hints > 0 )); then
      (( hints-- ))
    else
      view_above=0
    fi
  fi
  if (( view_below > 0 )); then
    if (( hints > 0 )); then
      (( hints-- ))
    else
      view_below=0
    fi
  fi
}

draw_emit() {
  (( draw_remain > 0 )) || return 1
  print -r -- "$1"
  (( draw_remain-- ))
  return 0
}

draw_help() {
  local -i max=$1
  local -a keys
  local buf piece sort_key filter_key
  case ${sort_mode:-time} in
    occupied) sort_key='o 占用' ;;
    pinned) sort_key='o 常驻' ;;
    *) sort_key='o 时间' ;;
  esac
  if (( filter_on )); then
    filter_key='f 显示全部'
  else
    filter_key='f 筛选'
  fi
  if (( preview_on )); then
    preview_key='v 关预览'
  else
    preview_key='v 预览'
  fi
  keys=("↑↓/jk 选择" "Enter 进入" "t 新窗口" "n 新建" "e 重命名" "d 删除" "p 常驻" "X 删空闲" "h 换机器" "r 刷新" "$sort_key" "$filter_key" "$preview_key" "/ 包含" "! 排除" ", 设置" "q 退出")
  buf=""
  for piece in "${keys[@]}"; do
    if [[ -z $buf ]]; then
      buf="  $piece"
      continue
    fi
    display_width "$buf  $piece"
    if (( REPLY > max )); then
      # Keep header + selected row visible on short terminals.
      (( draw_remain < 6 )) && break
      draw_emit "${c_dim}${buf}${c_reset}" || return 1
      buf="  $piece"
    else
      buf+="  $piece"
    fi
  done
  [[ -n $buf ]] && draw_emit "${c_dim}${buf}${c_reset}"
}

draw() {
  local -i cols rows i n session_end=0 list_body preview_keep
  local mark line header sep title
  cols=$(term_cols)
  rows=$(term_lines)
  n=${#items_kind}
  compute_layout $(( cols - 10 ))
  draw_remain=$(( rows > 1 ? rows - 1 : 1 ))

  for i in {1..$n}; do
    [[ ${items_kind[$i]} == session ]] && session_end=$i
  done

  print -n $'\e[H\e[J'
  [[ -n $host_short ]] || host_short=$(hostname -s)
  title="$host_short  选择 tmux session"
  _fit_right "$title" $(( cols - 2 ))
  title="  ${c_bold}${REPLY}${c_reset}"
  if (( filter_on )); then
    if [[ -n $filter_include ]]; then
      _fit_right "含 ${filter_include}" 24
      title+="  ${c_cyan}${REPLY}${c_reset}"
    fi
    if [[ -n $filter_exclude ]]; then
      _fit_right "不含 ${filter_exclude}" 24
      title+="  ${c_red}${REPLY}${c_reset}"
    fi
    title+="  ${c_dim}${filter_match_count}/${filter_total_count}${c_reset}"
  fi
  draw_emit "$title" || return
  if [[ -n $restore_boot_notice ]]; then
    draw_emit "  ${c_dim}${restore_boot_notice}${c_reset}" || return
  fi
  draw_help $cols || return
  draw_emit "" || return

  if [[ $HAS_TMUX -ne 1 ]]; then
    draw_emit "  ${c_dim}（这台机器上没有 tmux，可以直接进普通 shell；exit 或 Ctrl+D 返回）${c_reset}" || return
    draw_emit "" || return
  elif (( session_end == 0 )); then
    if (( filter_on )); then
      draw_emit "  ${c_dim}（没有匹配的 session）${c_reset}" || return
    else
      draw_emit "  ${c_dim}（当前没有 session）${c_reset}" || return
    fi
    draw_emit "" || return
  else
    _fmt_header
    header=$REPLY
    draw_emit "  ${c_dim}    #  ${header}${c_reset}" || return
    printf -v sep '%*s' $(( cols - 4 )) ''
    sep=${sep// /─}
    draw_emit "  ${c_dim}${sep}${c_reset}" || return
  fi

  list_body=$draw_remain
  preview_keep=0
  if (( preview_on )) && [[ ${items_kind[$cursor]} == session ]]; then
    # chrome already drawn; keep ≥1 list row, rest can be the preview band.
    preview_keep=$(( 3 + preview_band ))
    (( preview_keep > draw_remain - 1 )) && preview_keep=$(( draw_remain - 1 ))
    (( preview_keep < 3 )) && preview_keep=3
    (( preview_keep > draw_remain - 1 )) && preview_keep=$(( draw_remain > 1 ? draw_remain - 1 : 0 ))
    list_body=$(( draw_remain - preview_keep ))
    (( list_body < 1 )) && list_body=1
  fi
  plan_list_view $list_body $n $cursor $session_end
  (( view_above > 0 )) && draw_emit "  ${c_dim}↑ 还有 ${view_above}${c_reset}"
  for (( i = view_start; i <= view_end; i++ )); do
    if (( i == session_end + 1 && session_end > 0 )); then
      draw_emit "" || break
    fi
    if [[ ${items_kind[$i]} == session ]]; then
      _fmt_session_row $i
      line=$REPLY
    else
      line=${items_name[$i]}
    fi
    if (( i == cursor )); then
      mark="${c_cyan}>${c_reset}"
      line="${c_rev} ${line} ${c_reset}"
    else
      mark=" "
      line=" ${line}"
    fi
    printf -v line '  %s %2d  %s' "$mark" "$i" "$line"
    draw_emit "$line" || break
  done
  (( view_below > 0 )) && draw_emit "  ${c_dim}↓ 还有 ${view_below}${c_reset}"

  if (( preview_on )) && [[ ${items_kind[$cursor]} == session ]] && (( draw_remain >= 3 )); then
    local pname psum pmeta pl cache_key
    local -i pname_w cap_lines grok_prev=0
    draw_emit "" || return
    preview_is_grok "${items_cmd[$cursor]}" && grok_prev=1
    _fit_right "${items_name[$cursor]}" 20
    pname=$REPLY
    if (( grok_prev )); then
      draw_emit "  ${c_cyan}预览${c_reset}  ${c_bold}${pname}${c_reset}  ${c_dim}grok${c_reset}" || return
    else
      display_width "$pname"
      pname_w=REPLY
      _fit_right "${items_summary[$cursor]}" $(( cols - 10 - pname_w ))
      psum=$REPLY
      draw_emit "  ${c_cyan}预览${c_reset}  ${c_bold}${pname}${c_reset}  ${c_dim}${psum}${c_reset}" || return
      _fit_right "${items_path[$cursor]}  ·  ${items_cmd[$cursor]}" $(( cols - 4 ))
      pmeta=$REPLY
      draw_emit "  ${c_dim}${pmeta}${c_reset}" || return
    fi
    cap_lines=$draw_remain
    (( cap_lines > preview_max_lines )) && cap_lines=$preview_max_lines
    cache_key="${items_id[$cursor]}"$'\x1f'"${items_activity[$cursor]:-}"
    if [[ -n ${preview_cache[$cache_key]+x} ]]; then
      if [[ -n ${preview_cache[$cache_key]} ]]; then
        preview_lines=("${(@ps:\x1e:)preview_cache[$cache_key]}")
        preview_heading=${preview_cache_heading[$cache_key]:-}
      else
        preview_lines=()
        preview_heading=
      fi
    elif (( preview_defer )); then
      draw_emit "  ${c_dim}…${c_reset}" || return
      return
    else
      session_preview_lines "${items_id[$cursor]}" $cap_lines "${items_cmd[$cursor]}"
      preview_cache[$cache_key]="${(pj:\x1e:)preview_lines}"
      preview_cache_heading[$cache_key]=$preview_heading
    fi
    if (( grok_prev )) && [[ -n $preview_heading ]]; then
      _fit_head_tail "标题：${preview_heading}" $(( cols - 4 ))
      draw_emit "  ${c_bold}${REPLY}${c_reset}" || return
    fi
    for pl in "${preview_lines[@]}"; do
      _fit_head_tail "$pl" $(( cols - 4 ))
      draw_emit "  ${c_dim}${REPLY}${c_reset}" || break
    done
  fi
  if (( settings_on )); then
    draw_settings_overlay
  fi
}

draw_settings_overlay() {
  local -i cols rows w h r c i
  local -a lines
  local line hl root
  cols=$(term_cols)
  rows=$(term_lines)
  lines=(
    "设置"
    ""
    "  新窗口    $(settings_value_label target)"
    "  窗口      $(settings_value_label placement)"
  )
  for root in "${project_roots[@]}"; do
    lines+=("  项目根    $root")
  done
  lines+=("  ＋ 添加项目根")
  if (( settings_input_on )); then
    lines+=("  路径  ${settings_input_buf}█")
    lines+=("  Enter 确定  Esc 取消")
  fi
  lines+=("")
  if (( settings_input_on )); then
    lines+=("  在浮层里输入，能看见自己打的字")
  else
    lines+=("  j/k 选择  Enter 切换/添加  d 删除根  q 关闭")
  fi
  w=44
  for line in "${lines[@]}"; do
    display_width "$line"
    (( REPLY + 4 > w )) && w=$(( REPLY + 4 ))
  done
  h=$(( ${#lines} + 2 ))
  (( w > cols - 2 )) && w=$(( cols - 2 ))
  (( w < 16 )) && w=16
  r=$(( (rows - h) / 2 + 1 ))
  c=$(( (cols - w) / 2 + 1 ))
  (( r < 1 )) && r=1
  (( c < 1 )) && c=1
  printf '\e[%d;%dH┌' $r $c
  printf '─%.0s' {1..$(( w - 2 ))}
  printf '┐'
  for (( i = 1; i <= ${#lines}; i++ )); do
    printf '\e[%d;%dH│' $(( r + i )) $c
    line=${lines[$i]}
    _padw "$line" $(( w - 2 ))
    hl=0
    if (( settings_input_on )); then
      (( i == 6 + ${#project_roots} )) && hl=1
    elif (( i == settings_cursor + 2 )); then
      hl=1
    fi
    if (( hl )); then
      printf '%s%s%s│' "$c_rev" "$REPLY" "$c_reset"
    else
      printf '%s│' "$REPLY"
    fi
  done
  printf '\e[%d;%dH└' $(( r + h - 1 )) $c
  printf '─%.0s' {1..$(( w - 2 ))}
  printf '┘'
}

# True if another digit could still name a list index.
index_prefix_ambiguous() {
  local acc=$1
  local -i max=$2 val
  case $acc in
    ''|0*|*[!0-9]*) return 1 ;;
  esac
  val=$((10#$acc))
  (( val * 10 <= max ))
}

# Read one byte from stdin into REPLY. timeout is seconds.
# Returns 1 on timeout or EOF. Tty uses read -k; pipes use zselect.
read_byte_timeout() {
  local timeout=$1
  local buf=""
  local -i hundredths
  if [[ -t 0 ]]; then
    IFS= read -rsk1 -t $timeout buf || return 1
    REPLY=$buf
    return 0
  fi
  zmodload zsh/system 2>/dev/null || return 1
  zmodload zsh/zselect 2>/dev/null || return 1
  hundredths=$(( timeout * 100 ))
  (( hundredths < 1 )) && hundredths=1
  if ! zselect -t $hundredths -r 0; then
    return 1
  fi
  sysread -s 1 buf || return 1
  REPLY=$buf
  return 0
}

# Read one byte into REPLY. Optional timeout in seconds.
# No timeout: block. Tty uses read -k; pipes use sysread.
read_byte() {
  local timeout=${1-}
  local buf=""
  if [[ -n $timeout ]]; then
    read_byte_timeout $timeout
    return $?
  fi
  if [[ -t 0 ]]; then
    IFS= read -rsk1 buf || return 1
    REPLY=$buf
    return 0
  fi
  zmodload zsh/system 2>/dev/null || return 1
  sysread -s 1 buf || return 1
  REPLY=$buf
  return 0
}

# Read extra digits while the value is still a prefix of a larger index.
# Timeout / Enter keep the current value. Esc or any other key cancel
# (other key is replayed via PENDING_KEY).
collect_index_digits() {
  local acc=$1
  local -i max=$2
  local k k2
  PENDING_KEY=""
  while index_prefix_ambiguous "$acc" $max; do
    read_byte_timeout $digit_wait || break
    k=$REPLY
    case $k in
      [0-9]) acc="${acc}${k}" ;;
      $'\n'|$'\r'|' ') break ;;
      $'\e')
        # #262: drain CSI/SGR like read_key so PageUp ESC [ 5 ~ cannot
        # leave 5 as the next num key. Do not replay the tail.
        if read_byte 0.2; then
          k2=$REPLY
          if [[ $k2 == '[' || $k2 == 'O' ]]; then
            if read_byte 0.2; then
              k2=$REPLY
              if [[ $k2 == [0-9] ]]; then
                while read_byte 0.2; do
                  [[ $REPLY == [A-Za-z~] ]] && break
                done
              elif [[ $k2 == '<' ]]; then
                while read_byte 0.2; do
                  [[ $REPLY == M || $REPLY == m ]] && break
                done
              fi
            fi
          fi
        fi
        REPLY=""
        return 0
        ;;
      *) PENDING_KEY=$k; REPLY=""; return 0 ;;
    esac
  done
  REPLY=$acc
}

read_key() {
  local timeout=${1-}
  local k k2 k3 c key
  if [[ -n $PENDING_KEY ]]; then
    k=$PENDING_KEY
    PENDING_KEY=""
  else
    read_byte $timeout || return 1
    k=$REPLY
  fi
  if [[ $k == $'\e' ]]; then
    read_byte 0.2 || { REPLY=esc; return 0 }
    k2=$REPLY
    # lanjump-keys rewrites Ghostty Shift+Enter to Alt+Enter (ESC CR).
    if [[ $k2 == $'\r' || $k2 == $'\n' ]]; then
      REPLY=other
      return 0
    fi
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      read_byte 0.2 || { REPLY=esc; return 0 }
      k3=$REPLY
      case $k3 in
        A) REPLY=up ;;
        B) REPLY=down ;;
        C) REPLY=right ;;
        D) REPLY=left ;;
        *) REPLY=other ;;
      esac
      # Drain CSI params so leftover bytes are not a new Esc/q.
      if [[ $k3 == [0-9] ]]; then
        key=$REPLY
        while read_byte 0.2; do
          c=$REPLY
          [[ $c == [A-Za-z~] ]] && break
        done
        REPLY=$key
      elif [[ $k3 == '<' ]]; then
        # #260: SGR mouse ESC [ < … M/m. Picker treats the click as other.
        while read_byte 0.2; do
          c=$REPLY
          [[ $c == M || $c == m ]] && break
        done
        REPLY=other
      fi
      return 0
    fi
    REPLY=esc
    return 0
  fi
  case $k in
    $'\n'|$'\r'|' ') REPLY=enter ;;
    j|J) REPLY=up ;;
    k|K) REPLY=down ;;
    q|Q) REPLY=q ;;
    n|N) REPLY=n ;;
    t|T) REPLY=t ;;
    s|S) REPLY=s ;;
    r|R) REPLY=r ;;
    d|D) REPLY=d ;;
    e|E) REPLY=e ;;
    h|H) REPLY=h ;;
    o|O) REPLY=o ;;
    v|V) REPLY=v ;;
    p|P) REPLY=p ;;
    X) REPLY=X ;;
    f|F) REPLY=f ;;
    /) REPLY=/ ;;
    !) REPLY=! ;;
    ,) REPLY=settings ;;
    g) REPLY=top ;;
    G) REPLY=bottom ;;
    [0-9]) REPLY="num$k" ;;
    *) REPLY=other ;;
  esac
}

# Blocking read. After consecutive EOF/hangup failures, restore tty and
# exit so the main loop cannot spin at 100% CPU (#227).
read_key_or_exit() {
  if read_key; then
    _read_key_fails=0
    return 0
  fi
  (( ++_read_key_fails >= 8 )) || return 1
  restore_tty
  exit 1
}

activate() {
  local i=$1 want_new=${2:-0}
  case ${items_kind[$i]} in
    session)
      [[ $HAS_TMUX -eq 1 ]] || return
      attach_named_session "${items_id[$i]}" 1 $want_new
      setup_tty
      load_items
      draw
      ;;
    new)
      prompt_new $want_new
      ;;
    shell)
      restore_tty
      print
      print "${c_bold}普通 shell（不进 tmux）${c_reset}"
      print "${c_dim}输入 exit 或按 Ctrl+D 回到选择界面。${c_reset}"
      print
      run_interactive /bin/zsh -l
      setup_tty
      # The shell is outside tmux. Another terminal may have created or
      # killed a session while it was up.
      refresh_external_sessions
      draw
      ;;
    hosts)
      restore_tty
      trap - EXIT
      exit 10
      ;;
    quit)
      restore_tty
      trap - EXIT
      exit 0
      ;;
  esac
}

# Colon/dot collide with CLI host:session. Empty is allowed (new auto-name).
session_name_invalid() {
  [[ -n ${1:-} && ( $1 == *:* || $1 == *.* ) ]] || return 1
  print -r -- "名称不能包含冒号或点。"
  return 0
}

# CLI --new-session: empty is invalid here (unlike TUI n auto-name).
new_session_flag_invalid() {
  local name=${1:-}
  if [[ -z $name ]]; then
    print -r -- "用法：lanjump go <session>"
    return 0
  fi
  session_name_invalid "$name"
}

# Named create: pin/snap then project dir, same cwd as CLI --new-session.
create_named_session() {
  local name=$1 cwd
  local -i ok=0
  [[ -n $name ]] || return 1
  load_settings
  load_pinned_sessions
  load_session_snapshot
  cwd=$(resolve_session_cwd "$name")
  if [[ -n $cwd ]]; then
    if tmuxx new-session -d -s "$name" -c "$cwd" 2>/dev/null || \
       tmuxx new-session -d -s "$name" 2>/dev/null; then
      ok=1
    fi
  else
    tmuxx new-session -d -s "$name" 2>/dev/null && ok=1
  fi
  (( ok )) && tmux_state_invalidate
  (( ok ))
}

# List n pin cwd: live pane then project, never picker $PWD (#130).
prompt_new_pin_cwd() {
  local name=$1 pane=
  [[ -n $name ]] || return 0
  pane=$(tmuxx display-message -p -t "$(session_pane_target "$name")" '#{pane_current_path}' 2>/dev/null || true)
  resolve_session_cwd "$name" "${pane:-}"
}

# Existing-name pin prompt lives here so create (#136) does not ask 常驻.
prompt_new_ask_pin() {
  local pinans
  print -n "常驻（y=是，回车=否）: "
  read -r pinans || pinans=
  [[ $pinans == y || $pinans == Y ]]
}

# Rename leftover 0/1 and write the pin only after enter is confirmed (#208).
prompt_new_commit_pin() {
  local name=$1 cwd
  REPLY=$name
  [[ -n $name ]] || return 1
  ensure_pinnable_session_name "$name" || return 1
  name=$REPLY
  cwd=$(prompt_new_pin_cwd "$name")
  add_pin_record "$name" "${cwd:-}" "" || return
  REPLY=$name
}

prompt_new() {
  local want_new=${1:-0}
  [[ $HAS_TMUX -eq 1 ]] || return
  restore_tty
  print
  print -n "新 session 名称（回车=自动命名）: "
  local name openans created cwd
  local -i pin=0 existing=0
  read -r name
  name=${name##[[:space:]]#}
  name=${name%%[[:space:]]#}
  if session_name_invalid "$name"; then
    print -n "按回车继续…"
    read -r
    setup_tty
    load_items
    draw
    return
  fi
  if [[ -n $name ]] && tmux_session_live "$name"; then
    existing=1
    prompt_new_ask_pin && pin=1
  fi
  if (( ! want_new )); then
    print -n "新窗口？（回车=当前窗口，t=新窗口，q=取消）: "
    read -r openans || openans=
    case $openans in
      t|T) want_new=1 ;;
      q|Q)
        setup_tty
        load_items
        draw
        return
        ;;
    esac
  fi
  tmux_prepare_color
  tmux_prepare_keys
  if (( existing )); then
    load_session_snapshot
    print "session「${name}」已存在，直接进入。"
    if (( pin )); then
      prompt_new_commit_pin "$name" || {
        setup_tty
        load_items
        draw
        return
      }
      name=$REPLY
    fi
    attach_named_session "$name" 1 $want_new
  else
    if [[ -z $name ]]; then
      created=$(tmuxx new-session -d -P -F '#{session_name}' 2>/dev/null) || created=
      created=${created%%$'\n'*}
      if [[ -z $created ]]; then
        tmux_tty new-session
        tmux_state_invalidate
        setup_tty
        load_items
        draw
        return
      fi
      tmux_state_invalidate
    else
      if ! create_named_session "$name"; then
        print "创建失败。"
        print -n "按回车继续…"
        read -r
        setup_tty
        load_items
        draw
        return
      fi
      created=$name
    fi
    mark_snapshot_occupied "$created"
    attach_named_session "$created" 0 $want_new
  fi
  setup_tty
  load_items
  draw
}

prompt_delete() {
  [[ $HAS_TMUX -eq 1 ]] || return
  if [[ ${items_kind[$cursor]} != session ]]; then
    return
  fi
  local name=${items_id[$cursor]} ans
  restore_tty
  print
  if session_delete_needs_pin_warning; then
    print "${c_red}$(pin_delete_warning_text)${c_reset}"
  fi
  if [[ ${items_att[$cursor]} == 1 ]]; then
    print "${c_red}session「${name}」正在占用中，删除会断开里面正在跑的程序。${c_reset}"
  else
    print "删除 session「${name}」。这个操作不能恢复。"
  fi
  print -n "确认删除请输入 y，其他键取消: "
  read -r ans
  if [[ $ans == y || $ans == Y ]]; then
    if ! tmuxx kill-session -t "=$name" || ! { tmux_state_invalidate; forget_killed_session "$name"; }; then
      print "删除失败。"
      print -n "按回车继续…"
      read -r
    fi
  fi
  setup_tty
  load_items
  draw
}

prompt_bulk_idle_delete() {
  [[ $HAS_TMUX -eq 1 ]] || return
  local names ans
  names=$(bulk_idle_unpinned_names)
  restore_tty
  print
  if [[ -z $names ]]; then
    print "没有可删除的空闲 session。"
    print -n "按回车继续…"
    read -r
    setup_tty
    draw
    return
  fi
  print "${c_red}高风险：将删除下列空闲且非常驻的 session，不能恢复。${c_reset}"
  print "  ${c_red}${names}${c_reset}"
  print -n "${c_red}确认删除请输入 y，其他键取消: ${c_reset}"
  read -r ans
  if [[ $ans == y || $ans == Y ]]; then
    if ! delete_idle_unpinned_sessions; then
      print "删除失败。"
      print -n "按回车继续…"
      read -r
    fi
  fi
  setup_tty
  load_items
  draw
}

prompt_rename() {
  [[ $HAS_TMUX -eq 1 ]] || return
  if [[ ${items_kind[$cursor]} != session ]]; then
    return
  fi
  local old=${items_id[$cursor]} name err
  restore_tty
  print
  print -n "将 session「${old}」重命名为（回车取消）: "
  read -r name
  name=${name##[[:space:]]#}
  name=${name%%[[:space:]]#}
  if [[ -z $name || $name == "$old" ]]; then
    setup_tty
    draw
    return
  fi
  if session_name_invalid "$name"; then
    print -n "按回车继续…"
    read -r
    setup_tty
    load_items "$old"
    draw
    return
  fi
  if tmux_session_live "$name"; then
    print "session「${name}」已存在。"
    print -n "按回车继续…"
    read -r
    setup_tty
    load_items "$old"
    draw
    return
  fi
  err=$(tmuxx rename-session -t "=$old" "$name" 2>&1) || {
    print "重命名失败${err:+：${err}}。"
    print -n "按回车继续…"
    read -r
    setup_tty
    load_items "$old"
    draw
    return
  }
  tmux_state_invalidate
  if ! rename_pin_record "$old" "$name"; then
    tmuxx rename-session -t "=$name" "$old" 2>/dev/null || true
    tmux_state_invalidate
    setup_tty
    load_items "$old"
    draw
    return
  fi
  if ! rename_snap_record "$old" "$name"; then
    rename_pin_record "$name" "$old" || true
    tmuxx rename-session -t "=$name" "$old" 2>/dev/null || true
    tmux_state_invalidate
    setup_tty
    load_items "$old"
    draw
    return
  fi
  setup_tty
  load_items "$name"
  draw
}

if [[ ${1:-} == --digit-selftest ]]; then
  . "${0:A:h}/lanjump-digit-selftest.zsh"
  digit_selftest
  exit $?
fi

print_workspace_names() {
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  collect_restore_names
  collect_work_session_names
  local n
  for n in "${work_names[@]}"; do
    tmux_session_live "$n" || continue
    print -r -- "$n"
  done
}

# Restore before has-session so go name matches work/print (#80 / #120).
has_named_session() {
  local name=${1:-}
  [[ -n $name ]] || return 1
  [[ $HAS_TMUX -eq 1 ]] || return 1
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  tmux_session_live "$name"
}

# Restore before attach so list t / Ghostty matches go (#80 / #124).
ensure_named_session_for_attach() {
  local name=${1:-}
  [[ -n $name ]] || return 1
  has_named_session "$name" && return 0
  print -u2 "没有 session「${name}」。"
  return 1
}

# Restore before listing so pins matches work/list (#137).
print_pinned_names() {
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  local n
  for n in "${pinned_names[@]}"; do
    [[ -n $n ]] || continue
    numeric_session_name "$n" && continue
    lanjump_foreign_session "$n" && continue
    print -r -- "$n"
  done
}

print_last_name() {
  local n
  n=$(read_last_session_name) && { print -r -- "$n"; return 0 }
  load_session_snapshot
  (( ${#snap_names} )) || return 1
  print -r -- "${snap_names[-1]}"
}

# Restore before listing so last matches work/go (#122).
# Newest-activity first, up to $1 names (default 5).
print_recent_names() {
  local -i max=${1:-5} n=0
  local line name act
  local -a raw
  [[ $HAS_TMUX -eq 1 ]] || return 1
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  tmux_state_load
  (( tm_server_up && ${#tm_names} )) || return 1
  raw=()
  for name in "${tm_names[@]}"; do
    act=${tm_activity[$name]:-0}
    [[ $act == [0-9]## ]] || act=0
    raw+=("${act}"$'\t'"$name")
  done
  for line in "${(@f)$(print -r -- "${(F)raw}" | sort -t $'\t' -k1,1nr)}"; do
    [[ -n $line ]] || continue
    name=${line#*$'\t'}
    [[ -n $name ]] || continue
    print -r -- "$name"
    (( ++n >= max )) && break
  done
  (( n ))
}

# Restore before listing so list matches last/work (#134).
print_session_list() {
  local n att
  [[ $HAS_TMUX -eq 1 ]] || return 0
  load_pinned_sessions
  load_session_snapshot
  if should_restore_sessions; then
    restore_saved_sessions
  else
    restore_pinned_sessions
  fi
  tmux_state_load
  (( tm_server_up && ${#tm_names} )) || return 0
  for n in "${tm_names[@]}"; do
    if [[ ${tm_att[$n]:-0} == 1 ]]; then
      att=占用中
    else
      att=空闲
    fi
    print -r -- "${n}"$'\t'"${att}"$'\t'"${tm_cmd[$n]:-}"$'\t'"${tm_path[$n]:-}"
  done
}

if [[ ${1:-} == --pick-selftest ]]; then
  . "${0:A:h}/lanjump-pick-selftest.zsh"
  pick_selftest
  exit $?
fi

if [[ ${1:-} == --snapshot ]]; then
  run_session_snapshot
  exit 0
fi
if [[ ${1:-} == --refresh-pin-cwd ]]; then
  refresh_pin_cwds
  exit 0
fi
if [[ ${1:-} == --install-hooks ]]; then
  tmux_install_snapshot_hooks
  exit 0
fi

if [[ ${1:-} == --print-workspace ]]; then
  print_workspace_names
  exit 0
fi
if [[ ${1:-} == --print-pinned ]]; then
  print_pinned_names
  exit 0
fi
if [[ ${1:-} == --print-last ]]; then
  print_last_name || exit 1
  exit 0
fi
if [[ ${1:-} == --print-recent ]]; then
  print_recent_names 5 || exit 1
  exit 0
fi
if [[ ${1:-} == --print-sessions ]]; then
  print_session_list
  exit 0
fi

if [[ ${1:-} == --has-session ]]; then
  has_named_session "${2:-}"
  exit $?
fi

if [[ ${1:-} == --start-grok ]]; then
  name=${2:-}
  [[ -n $name ]] || exit 1
  start_grok_session "$name"
  exit $?
fi

if [[ ${1:-} == --pin-session ]]; then
  pin_named_session "${2:-}" || exit 1
  exit 0
fi

if [[ ${1:-} == --new-session ]]; then
  name=${2:-}
  if msg=$(new_session_flag_invalid "$name"); then
    print -u2 "$msg"
    exit 1
  fi
  if [[ $HAS_TMUX -ne 1 ]]; then
    print -u2 "这台机器上没有 tmux。"
    exit 1
  fi
  if tmux_session_live "$name"; then
    exit 0
  fi
  create_named_session "$name" || exit 1
  mark_snapshot_occupied "$name"
  exit 0
fi

if [[ ${1:-} == --open-tabs ]]; then
  shift
  attach_shell_only=0
  names=()
  while (( $# )); do
    case $1 in
      --shell) attach_shell_only=1 ;;
      *) names+=("$1") ;;
    esac
    shift
  done
  load_settings
  load_pinned_sessions
  load_session_snapshot
  open_named_tabs "${names[@]}"
  exit $?
fi

if [[ ${1:-} == --attach ]]; then
  shift
  attach_shell_only=0
  name=
  while (( $# )); do
    case $1 in
      --shell) attach_shell_only=1 ;;
      *) name=$1 ;;
    esac
    shift
  done
  if [[ -z $name ]]; then
    print -u2 "用法：lanjump attach [--shell] <session>"
    exit 1
  fi
  if [[ $HAS_TMUX -ne 1 ]]; then
    print -u2 "这台机器上没有 tmux。"
    exit 1
  fi
  ensure_named_session_for_attach "$name" || exit 1
  load_settings
  load_session_snapshot
  mark_snapshot_occupied "$name"
  remember_last_session "$name"
  maybe_resume_last_command "$name"
  tmux_prepare_color
  tmux_prepare_keys
  emit_host_grok_appearance_osc
  keys=
  if local_keyboard && keys=$(keys_bin); then
    exec "$keys" "$TMUX_BIN" attach-session -t "=$name"
  else
    exec "$TMUX_BIN" attach-session -t "=$name"
  fi
fi

picker_boot_before_first_draw
picker_boot_after_first_draw

while true; do
  if (( settings_on && settings_input_on )); then
    preview_defer=0
    settings_input_read_or_exit || continue
    case $REPLY in
      enter)
        settings_commit_input
        draw
        ;;
      esc)
        settings_input_on=0
        settings_input_buf=
        draw
        ;;
      other)
        ;;
      backspace)
        (( ${#settings_input_buf} )) && settings_input_buf=${settings_input_buf[1,-2]}
        draw
        ;;
      char)
        settings_input_buf+=$settings_input_char
        draw
        ;;
    esac
    continue
  fi
  if (( preview_defer )); then
    if ! read_key $preview_wait; then
      preview_defer=0
      draw
      continue
    fi
  else
    read_key_or_exit || continue
  fi
  if (( settings_on )); then
    preview_defer=0
    case $REPLY in
      up)
        settings_move -1
        draw
        ;;
      down)
        settings_move 1
        draw
        ;;
      enter)
        settings_enter
        draw
        ;;
      d)
        settings_delete_key
        draw
        ;;
      q|esc|settings)
        settings_on=0
        save_settings
        draw
        ;;
    esac
    continue
  fi
  if [[ $REPLY != up && $REPLY != down ]]; then
    preview_defer=0
  fi
  case $REPLY in
    up)
      (( cursor-- ))
      (( cursor < 1 )) && cursor=${#items_kind}
      preview_defer=1
      draw
      ;;
    down)
      (( cursor++ ))
      (( cursor > ${#items_kind} )) && cursor=1
      preview_defer=1
      draw
      ;;
    top)
      cursor=1
      draw
      ;;
    bottom)
      cursor=${#items_kind}
      draw
      ;;
    enter)
      activate $cursor
      ;;
    t)
      activate $cursor 1
      ;;
    n)
      prompt_new
      ;;
    s)
      activate ${items_kind[(i)shell]}
      ;;
    d)
      prompt_delete
      ;;
    p)
      toggle_session_pin
      draw
      ;;
    X)
      prompt_bulk_idle_delete
      ;;
    e)
      prompt_rename
      ;;
    h)
      activate ${items_kind[(i)hosts]}
      ;;
    q|esc)
      restore_tty
      trap - EXIT
      exit 0
      ;;
    r)
      refresh_external_sessions
      draw
      ;;
    o)
      toggle_sort_mode
      draw
      ;;
    v)
      preview_on=$(( 1 - preview_on ))
      preview_defer=0
      draw
      ;;
    settings)
      settings_on=1
      settings_cursor=1
      load_settings
      draw
      ;;
    f)
      toggle_session_filter
      draw
      ;;
    /)
      prompt_filter include
      ;;
    !)
      prompt_filter exclude
      ;;
    num*)
      collect_index_digits "${REPLY#num}" ${#items_kind}
      n=$REPLY
      if [[ $n == [1-9]* && $n != *[!0-9]* ]] && (( 10#$n <= ${#items_kind} )); then
        cursor=$((10#$n))
        activate $cursor
      fi
      ;;
  esac
done