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

if [[ ${1:-} != --digit-selftest && ${1:-} != --pick-selftest ]]; then
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
typeset -A preview_cache
cursor=1
# time = all by last activity desc; attached = 占用中 first, idle after, each time-desc.
sort_mode=time
filter_include=
filter_exclude=
typeset -i filter_on=0 filter_match_count=0 filter_total_count=0
typeset -a pinned_names
typeset -A pinned_cwd pinned_grok
loading=0
stty_orig=
PENDING_KEY=""
digit_wait=0.5
preview_defer=0
preview_wait=0.08
preview_max_lines=10
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

tmuxx() {
  [[ -n $TMUX_BIN ]] || return 1
  command "$TMUX_BIN" "$@" </dev/null
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
  local keys
  if local_keyboard && keys=$(keys_bin); then
    "$keys" "$@"
  else
    "$@"
  fi
}

tmux_has_feature() {
  local all
  all=$(tmuxx show-options -g terminal-features 2>/dev/null || true)
  [[ $all == *$1* ]]
}

tmux_prepare_keys() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  (( prepared_keys )) && return 0
  tmuxx set-option -g extended-keys always 2>/dev/null || \
    tmuxx set-option -g extended-keys on 2>/dev/null || true
  tmuxx set-option -s extended-keys-format csi-u 2>/dev/null || true
  tmuxx set-option -gw allow-passthrough on 2>/dev/null || true
  tmuxx set-option -g set-clipboard on 2>/dev/null || true
  tmux_has_feature extkeys || tmuxx set-option -as terminal-features ',xterm*:extkeys' 2>/dev/null || true
  if [[ ${TERM_PROGRAM:-} != Apple_Terminal ]]; then
    tmux_has_feature RGB || tmuxx set-option -as terminal-features ',*:RGB' 2>/dev/null || true
  fi
  local len
  len=$(tmuxx show-options -gv status-left-length 2>/dev/null || true)
  [[ $len == [0-9]## ]] || len=0
  if (( len < 40 )); then
    tmuxx set-option -g status-left-length 40 2>/dev/null || true
  fi
  tmuxx bind-key -n S-Enter send-keys Escape Enter 2>/dev/null || true
  prepared_keys=1
}

tmux_tty() {
  tmux_prepare_color
  tmux_prepare_keys
  run_interactive "$TMUX_BIN" "$@"
}

# Apple Terminal (macOS 12) is 256-color. Advertising RGB makes Grok emit
# 24-bit backgrounds that Terminal.app ignores, so the TUI sits on white.
tmux_prepare_color() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  (( prepared_color )) && return 0
  local dt apple=0
  [[ ${TERM_PROGRAM:-} == Apple_Terminal ]] && apple=1

  if [[ -n ${TERM_PROGRAM:-} ]]; then
    tmuxx set-environment -g TERM_PROGRAM "$TERM_PROGRAM" 2>/dev/null || true
  fi
  if [[ -n ${TERM_PROGRAM_VERSION:-} ]]; then
    tmuxx set-environment -g TERM_PROGRAM_VERSION "$TERM_PROGRAM_VERSION" 2>/dev/null || true
  fi

  dt=$(tmuxx show-options -gv default-terminal 2>/dev/null || true)
  if (( apple )); then
    unset COLORTERM
    tmuxx set-environment -gu COLORTERM 2>/dev/null || true
    if [[ $dt != screen-256color && $dt != xterm-256color ]]; then
      if infocmp screen-256color >/dev/null 2>&1; then
        tmuxx set-option -g default-terminal screen-256color 2>/dev/null || true
      else
        tmuxx set-option -g default-terminal xterm-256color 2>/dev/null || true
      fi
    fi
    tmuxx set-option -gu terminal-features 2>/dev/null || true
    tmuxx set-option -g terminal-overrides ',*:RGB@,*:Tc@' 2>/dev/null || true
  else
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
    tmuxx set-option -as terminal-features ',*:RGB' 2>/dev/null || true
    tmuxx set-option -ag terminal-overrides ',*:Tc' 2>/dev/null || true
  fi

  # wrap stamps LC_GROK_APPEARANCE from the local OS. That is for theme=auto
  # over SSH; it must not override a configured/default GrokNight session.
  tmuxx set-environment -gu LC_GROK_APPEARANCE 2>/dev/null || true
  tmuxx set-environment -gu GROK_APPEARANCE 2>/dev/null || true
  prepared_color=1
}

restore_tty() {
  print -n '\e[?25h'
  [[ -n ${stty_orig:-} ]] && stty "$stty_orig" 2>/dev/null || stty sane 2>/dev/null
}

setup_tty() {
  stty_orig=$(stty -g)
  stty -echo -icanon min 1 time 0
  print -n '\e[?25l'
}

on_exit() {
  restore_tty
}
if [[ ${1:-} != --digit-selftest && ${1:-} != --pick-selftest ]]; then
  trap on_exit EXIT
  trap 'restore_tty; exit 130' INT
  trap '[[ $loading -eq 1 ]] || draw' WINCH
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

useful_summary() {
  local title=$1 cmd=$2 wname=$3
  if [[ -n $title && $title != *.local && $title != zsh && $title != grok && $title != bash ]]; then
    print -r -- "$title"
  elif [[ -n $cmd && $cmd != zsh && $cmd != bash && $cmd != sh ]]; then
    print -r -- "$cmd"
  elif [[ -n $wname && $wname != zsh && $wname != bash ]]; then
    print -r -- "$wname"
  elif [[ -n $cmd ]]; then
    print -r -- "$cmd"
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
  w_summary=$(max_dw 4 摘要 "${summaries[@]}")
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
    _padw 摘要 $w_summary
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

session_filter_file() {
  REPLY="$HOME/Library/Application Support/lanjump/session-filter"
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

save_session_filter() {
  local file dir
  session_filter_file
  file=$REPLY
  dir=${file:h}
  mkdir -p "$dir"
  sanitize_filter_keyword "$filter_include"
  filter_include=$REPLY
  sanitize_filter_keyword "$filter_exclude"
  filter_exclude=$REPLY
  print -r -- "include ${filter_include}" >"$file"
  print -r -- "exclude ${filter_exclude}" >>"$file"
}

load_session_filter() {
  local file line key val
  session_filter_file
  file=$REPLY
  filter_include=
  filter_exclude=
  [[ -f $file ]] || return 0
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
  REPLY="$HOME/Library/Application Support/lanjump/pinned-sessions"
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

save_pinned_sessions() {
  local file dir n
  pinned_sessions_file
  file=$REPLY
  dir=${file:h}
  mkdir -p "$dir"
  : >"$file"
  for n in "${pinned_names[@]}"; do
    [[ -n $n ]] || continue
    print -r -- "name $n" >>"$file"
    print -r -- "cwd ${pinned_cwd[$n]:-}" >>"$file"
    print -r -- "grok ${pinned_grok[$n]:-}" >>"$file"
    print -r -- "" >>"$file"
  done
}

add_pin_record() {
  local name=$1 cwd=${2:-} grok=${3:-}
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
  local name=$1
  local -i i
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
  local old=$1 new=$2
  local -i i
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
      save_pinned_sessions
      return 0
    fi
  done
}

tmux_set_pinned() {
  local name=$1 on=$2
  [[ $HAS_TMUX -eq 1 ]] || return 0
  if [[ $on == 1 ]]; then
    tmuxx set-option -t "=$name" @lanjump_pinned 1 2>/dev/null || true
  else
    tmuxx set-option -u -t "=$name" @lanjump_pinned 2>/dev/null || true
  fi
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

restore_pinned_sessions() {
  [[ $HAS_TMUX -eq 1 ]] || return 0
  local name cwd grok
  load_pinned_sessions
  for name in "${pinned_names[@]}"; do
    [[ -n $name ]] || continue
    cwd=${pinned_cwd[$name]:-}
    grok=${pinned_grok[$name]:-}
    if tmuxx has-session -t "=$name" 2>/dev/null; then
      tmux_set_pinned "$name" 1
      continue
    fi
    if [[ -n $cwd ]]; then
      tmuxx new-session -d -s "$name" -c "$cwd" 2>/dev/null || \
        tmuxx new-session -d -s "$name" 2>/dev/null || continue
    else
      tmuxx new-session -d -s "$name" 2>/dev/null || continue
    fi
    if [[ -n $grok && $grok == [A-Za-z0-9._-]## ]]; then
      tmuxx send-keys -t "=$name" "grok --resume ${grok}" Enter 2>/dev/null || true
    fi
    tmux_set_pinned "$name" 1
  done
}

bulk_idle_unpinned_names() {
  local -i i
  local -a names
  names=()
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    [[ ${items_kind[$i]} == session ]] || continue
    [[ ${items_att[$i]} == 1 ]] && continue
    [[ ${items_pinned[$i]:-0} == 1 ]] && continue
    names+=("${items_id[$i]}")
  done
  print -r -- "${names[*]}"
}

delete_idle_unpinned_sessions() {
  local -i i
  for (( i = 1; i <= ${#items_kind}; i++ )); do
    [[ ${items_kind[$i]} == session ]] || continue
    [[ ${items_att[$i]} == 1 ]] && continue
    [[ ${items_pinned[$i]:-0} == 1 ]] && continue
    tmuxx kill-session -t "=${items_id[$i]}" 2>/dev/null || true
  done
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
  local name=${items_id[$cursor]} cwd pid grok
  local -i i on=0
  if [[ ${items_pinned[$cursor]:-0} == 1 ]]; then
    remove_pin_record "$name"
    tmux_set_pinned "$name" 0
    on=0
  else
    cwd=$(tmuxx display-message -p -t "=$name" '#{pane_current_path}' 2>/dev/null || true)
    pid=$(tmuxx display-message -p -t "=$name" '#{pane_pid}' 2>/dev/null || true)
    grok=$(grok_id_for_pid "$pid")
    add_pin_record "$name" "$cwd" "$grok"
    tmux_set_pinned "$name" 1
    on=1
  fi
  items_pinned[$cursor]=$on
  for (( i = 1; i <= ${#all_id}; i++ )); do
    if [[ ${all_id[$i]} == "$name" ]]; then
      all_pinned[$i]=$on
      break
    fi
  done
}

load_items() {
  loading=1
  local keep="${1-}" line when title cmd wname pin
  local -a raw f
  if [[ -z $keep ]] && (( cursor >= 1 && cursor <= ${#items_id} )); then
    keep=${items_id[$cursor]}
  fi

  load_pinned_sessions
  items_kind=()
  items_id=()
  items_name=()
  items_att=()
  items_time=()
  items_path=()
  items_summary=()
  items_cmd=()
  items_activity=()
  items_pinned=()  preview_cache=()
  raw=()

  if [[ $HAS_TMUX -eq 1 ]] && tmuxx list-sessions >/dev/null 2>&1; then
    raw=("${(@f)$(tmuxx list-sessions -F $'#{session_activity}\x1f#{session_name}\x1f#{session_windows}\x1f#{?session_attached,1,0}\x1f#{pane_current_path}\x1f#{window_name}\x1f#{pane_title}\x1f#{pane_current_command}')}")
  fi

  if (( ${#raw} )); then
    for line in "${raw[@]}"; do
      [[ -z $line ]] && continue
      f=("${(@ps:\x1f:)line}")
      (( ${#f} < 8 )) && continue
      strftime -s when '%m-%d %H:%M' "${f[1]}"
      wname=${f[6]}
      title=${f[7]}
      cmd=${f[8]}
      pin=0
      pin_record_exists "${f[2]}" && pin=1
      items_kind+=("session")
      items_id+=("${f[2]}")
      items_name+=("${f[2]}")
      items_att+=("${f[4]}")
      items_time+=("$when")
      items_path+=("$(short_path "${f[5]}")")
      items_summary+=("$(useful_summary "$title" "$cmd" "$wname")")
      items_cmd+=("$cmd")
      items_activity+=("${f[1]}")
      items_pinned+=("$pin")    done
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

session_preview_lines() {
  local name=$1 cmd=$3
  local -i max_lines=$2 start grok=0 saw_blank=0
  local cap line stripped
  local -a kept raw_lines
  preview_lines=()
  (( max_lines > preview_max_lines )) && max_lines=$preview_max_lines
  (( max_lines < 1 )) && return
  [[ $cmd == (#i)*grok* ]] && grok=1

  if (( grok )); then
    cap=$(tmuxx capture-pane -t "=$name:." -a -p 2>/dev/null) || cap=""
  else
    cap=$(tmuxx capture-pane -t "=$name:." -p -J 2>/dev/null) || cap=""
    if [[ -z ${cap//[$' \t\n']/} ]]; then
      cap=$(tmuxx capture-pane -t "=$name:." -a -p 2>/dev/null) || cap=""
    fi
  fi

  raw_lines=("${(@f)cap}")
  kept=()
  for line in "${raw_lines[@]}"; do
    line="${line%"${line##*[![:space:]]}"}"
    stripped=${line//[[:space:]]/}
    if [[ -z $stripped ]]; then
      (( saw_blank )) && continue
      kept+=("")
      saw_blank=1
      continue
    fi
    if [[ $stripped == █## ]]; then
      continue
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
  if (( ${#kept} )); then
    stripped=${kept[-1]//[[:space:]]/}
    if [[ $stripped != *[[:alnum:]]* ]]; then
      kept=("${(@)kept[1,-2]}")
    fi
  fi
  (( ${#kept} == 0 )) && return
  if (( ${#kept} > max_lines )); then
    start=$(( ${#kept} - max_lines + 1 ))
    kept=("${(@)kept[start,-1]}")
  fi
  preview_lines=("${kept[@]}")
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
  keys=("↑↓/jk 选择" "Enter 进入" "n 新建" "e 重命名" "d 删除" "p 常驻" "X 删空闲" "h 换机器" "r 刷新" "$sort_key" "$filter_key" "/ 包含" "! 排除" "q 退出")
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
  local -i cols rows i n session_end=0
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

  plan_list_view $draw_remain $n $cursor $session_end
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

  if [[ ${items_kind[$cursor]} == session ]] && (( draw_remain >= 3 )); then
    local pname psum pmeta pl cache_key
    local -i pname_w cap_lines
    draw_emit "" || return
    _fit_right "${items_name[$cursor]}" 20
    pname=$REPLY
    display_width "$pname"
    pname_w=REPLY
    _fit_right "${items_summary[$cursor]}" $(( cols - 10 - pname_w ))
    psum=$REPLY
    draw_emit "  ${c_cyan}预览${c_reset}  ${c_bold}${pname}${c_reset}  ${c_dim}${psum}${c_reset}" || return
    _fit_right "${items_path[$cursor]}  ·  ${items_cmd[$cursor]}" $(( cols - 4 ))
    pmeta=$REPLY
    draw_emit "  ${c_dim}${pmeta}${c_reset}" || return
    cap_lines=$draw_remain
    (( cap_lines > preview_max_lines )) && cap_lines=$preview_max_lines
    cache_key="${items_id[$cursor]}"$'\x1f'"${items_activity[$cursor]:-}"
    if [[ -n ${preview_cache[$cache_key]+x} ]]; then
      if [[ -n ${preview_cache[$cache_key]} ]]; then
        preview_lines=("${(@ps:\x1e:)preview_cache[$cache_key]}")
      else
        preview_lines=()
      fi
    elif (( preview_defer )); then
      draw_emit "  ${c_dim}…${c_reset}" || return
      return
    else
      session_preview_lines "${items_id[$cursor]}" $cap_lines "${items_cmd[$cursor]}"
      preview_cache[$cache_key]="${(pj:\x1e:)preview_lines}"
    fi
    for pl in "${preview_lines[@]}"; do
      _fit_right "$pl" $(( cols - 4 ))
      draw_emit "  ${c_dim}${REPLY}${c_reset}" || break
    done
  fi
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

# Read extra digits while the value is still a prefix of a larger index.
# Timeout / Enter keep the current value. Esc or any other key cancel
# (other key is replayed via PENDING_KEY).
collect_index_digits() {
  local acc=$1
  local -i max=$2
  local k
  PENDING_KEY=""
  while index_prefix_ambiguous "$acc" $max; do
    read_byte_timeout $digit_wait || break
    k=$REPLY
    case $k in
      [0-9]) acc="${acc}${k}" ;;
      $'\n'|$'\r'|' ') break ;;
      $'\e') REPLY=""; return 0 ;;
      *) PENDING_KEY=$k; REPLY=""; return 0 ;;
    esac
  done
  REPLY=$acc
}

read_key() {
  local timeout=${1-}
  local k k2 k3
  if [[ -n $PENDING_KEY ]]; then
    k=$PENDING_KEY
    PENDING_KEY=""
  elif [[ -n $timeout ]]; then
    read_byte_timeout $timeout || return 1
    k=$REPLY
  else
    IFS= read -rsk1 k || return 1
  fi
  if [[ $k == $'\e' ]]; then
    IFS= read -rsk1 -t 0.2 k2 || { REPLY=esc; return 0 }
    if [[ $k2 == '[' || $k2 == 'O' ]]; then
      IFS= read -rsk1 -t 0.2 k3 || { REPLY=esc; return 0 }
      case $k3 in
        A) REPLY=up ;;
        B) REPLY=down ;;
        C) REPLY=right ;;
        D) REPLY=left ;;
        *) REPLY=esc ;;
      esac
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
    s|S) REPLY=s ;;
    r|R) REPLY=r ;;
    d|D) REPLY=d ;;
    e|E) REPLY=e ;;
    h|H) REPLY=h ;;
    o|O) REPLY=o ;;
    p|P) REPLY=p ;;
    X) REPLY=X ;;
    f|F) REPLY=f ;;
    /) REPLY=/ ;;
    !) REPLY=! ;;
    g) REPLY=top ;;
    G) REPLY=bottom ;;
    [0-9]) REPLY="num$k" ;;
    *) REPLY=other ;;
  esac
}

activate() {
  local i=$1
  case ${items_kind[$i]} in
    session)
      [[ $HAS_TMUX -eq 1 ]] || return
      restore_tty
      print
      tmux_tty attach-session -t "=${items_id[$i]}"
      setup_tty
      load_items
      draw
      ;;
    new)
      prompt_new
      ;;
    shell)
      restore_tty
      print
      print "${c_bold}普通 shell（不进 tmux）${c_reset}"
      print "${c_dim}输入 exit 或按 Ctrl+D 回到选择界面。${c_reset}"
      print
      run_interactive /bin/zsh -l
      setup_tty
      load_items
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

prompt_new() {
  [[ $HAS_TMUX -eq 1 ]] || return
  restore_tty
  print
  print -n "新 session 名称（回车=自动命名）: "
  local name pinans created
  local -i pin=0
  read -r name
  name=${name##[[:space:]]#}
  name=${name%%[[:space:]]#}
  print -n "常驻（y=是，回车=否）: "
  read -r pinans || pinans=
  if [[ $pinans == y || $pinans == Y ]]; then
    pin=1
  fi
  tmux_prepare_color
  tmux_prepare_keys
  if [[ -n $name ]] && tmuxx has-session -t "=$name" 2>/dev/null; then
    print "session「${name}」已存在，直接进入。"
    if (( pin )); then
      add_pin_record "$name" "$PWD" ""
      tmux_set_pinned "$name" 1
    fi
    tmux_tty attach-session -t "=$name"
  else
    if [[ -z $name ]]; then
      created=$(tmuxx new-session -d -P -F '#{session_name}' 2>/dev/null) || created=
      created=${created%%$'\n'*}
      if [[ -z $created ]]; then
        tmux_tty new-session
        setup_tty
        load_items
        draw
        return
      fi
    else
      if ! tmuxx new-session -d -s "$name" 2>/dev/null; then
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
    if (( pin )); then
      add_pin_record "$created" "$PWD" ""
      tmux_set_pinned "$created" 1
    fi
    tmux_tty attach-session -t "=$created"
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
  local -i was_pinned=0
  [[ ${items_pinned[$cursor]:-0} == 1 ]] && was_pinned=1
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
    if ! tmuxx kill-session -t "=$name"; then
      print "删除失败。"
      print -n "按回车继续…"
      read -r
    elif (( was_pinned )); then
      remove_pin_record "$name"
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
    delete_idle_unpinned_sessions
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
  if [[ $name == *:* || $name == *.* ]]; then
    print "名称不能包含冒号或点。"
    print -n "按回车继续…"
    read -r
    setup_tty
    load_items "$old"
    draw
    return
  fi
  if tmuxx has-session -t "=$name" 2>/dev/null; then
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
  rename_pin_record "$old" "$name"
  setup_tty
  load_items "$name"
  draw
}

if [[ ${1:-} == --digit-selftest ]]; then
  . "${0:A:h}/lanjump-digit-selftest.zsh"
  digit_selftest
  exit $?
fi

if [[ ${1:-} == --pick-selftest ]]; then
  . "${0:A:h}/lanjump-pick-selftest.zsh"
  pick_selftest
  exit $?
fi

load_pinned_sessions
restore_pinned_sessions
tmux_prepare_color
tmux_prepare_keys
load_session_filter
filter_on=0
load_items
setup_tty
draw

while true; do
  if (( preview_defer )); then
    if ! read_key $preview_wait; then
      preview_defer=0
      draw
      continue
    fi
  else
    read_key || continue
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
      load_items
      draw
      ;;
    o)
      toggle_sort_mode
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