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

if [[ ${1:-} != --digit-selftest ]]; then
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

typeset -a items_kind items_id items_name items_att items_time items_path items_summary items_cmd
cursor=1
loading=0
stty_orig=
PENDING_KEY=""
digit_wait=0.5
w_name=4 w_status=6 w_time=11 w_summary=4 w_path=4
show_summary=1
show_path=1
draw_remain=0

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
  tmuxx set-option -g extended-keys always 2>/dev/null || \
    tmuxx set-option -g extended-keys on 2>/dev/null || true
  tmuxx set-option -s extended-keys-format csi-u 2>/dev/null || true
  tmuxx set-option -gw allow-passthrough on 2>/dev/null || true
  tmuxx set-option -g set-clipboard on 2>/dev/null || true
  tmux_has_feature extkeys || tmuxx set-option -as terminal-features ',xterm*:extkeys' 2>/dev/null || true
  if [[ ${TERM_PROGRAM:-} != Apple_Terminal ]]; then
    tmux_has_feature RGB || tmuxx set-option -as terminal-features ',*:RGB' 2>/dev/null || true
  fi
  local s w len keys
  len=$(tmuxx show-options -gv status-left-length 2>/dev/null || true)
  [[ $len == [0-9]## ]] || len=0
  if (( len < 40 )); then
    tmuxx set-option -g status-left-length 40 2>/dev/null || true
  fi
  keys=$(tmuxx list-keys -T root 2>/dev/null || true)
  if [[ $keys != *S-Enter* ]]; then
    tmuxx bind-key -n S-Enter send-keys Escape Enter 2>/dev/null || true
  fi
  for s in "${(@f)$(tmuxx list-sessions -F '#{session_name}' 2>/dev/null)}"; do
    [[ -n $s ]] || continue
    tmuxx set-option -t "$s" extended-keys always 2>/dev/null || true
  done
  for w in "${(@f)$(tmuxx list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)}"; do
    [[ -n $w ]] || continue
    tmuxx set-option -w -t "$w" allow-passthrough on 2>/dev/null || true
  done
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
trap on_exit EXIT
trap 'restore_tty; exit 130' INT
trap '[[ $loading -eq 1 ]] || draw' WINCH

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
  if (( r < 8 )); then
    r=$(stty size 2>/dev/null | awk '{print $1}')
  fi
  (( r < 12 )) && r=12
  print -r -- $r
}

dw() {
  local s=$1 c
  local -i w=0 i
  for (( i = 1; i <= ${#s}; i++ )); do
    c=$s[i]
    if [[ $c < $'\x7f' ]]; then
      (( w++ ))
    else
      (( w += 2 ))
    fi
  done
  print -r -- $w
}

fit_right() {
  local s=$1
  local -i max=$2 w=0 i cw
  local c out=
  if (( max <= 0 )); then
    return
  fi
  if (( $(dw "$s") <= max )); then
    print -r -- "$s"
    return
  fi
  if (( max <= 1 )); then
    print -r -- '…'
    return
  fi
  for (( i = 1; i <= ${#s}; i++ )); do
    c=$s[i]
    cw=$(dw "$c")
    if (( w + cw > max - 1 )); then
      break
    fi
    out+="$c"
    (( w += cw ))
  done
  print -r -- "${out}…"
}

fit_left() {
  local s=$1
  local -i max=$2 w=0 i cw
  local c out=
  if (( max <= 0 )); then
    return
  fi
  if (( $(dw "$s") <= max )); then
    print -r -- "$s"
    return
  fi
  if (( max <= 1 )); then
    print -r -- '…'
    return
  fi
  for (( i = ${#s}; i >= 1; i-- )); do
    c=$s[i]
    cw=$(dw "$c")
    if (( w + cw > max - 1 )); then
      break
    fi
    out="$c$out"
    (( w += cw ))
  done
  print -r -- "…${out}"
}

padw() {
  local s=$1
  local -i width=$2 d
  d=$(dw "$s")
  if (( width <= 0 )); then
    return
  fi
  if (( d > width )); then
    fit_right "$s" $width
    return
  fi
  printf '%s%*s' "$s" $(( width - d )) ''
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
  local best=$1 item
  shift
  for item in "$@"; do
    (( $(dw "$item") > best )) && best=$(dw "$item")
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
      names+=("${items_name[$i]}")
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
  local i=$1
  local att_txt att_col name_cell status_cell time_cell extra=""
  if [[ ${items_att[$i]} == 1 ]]; then
    att_txt="占用中"
    att_col=$c_green
  else
    att_txt="空闲"
    att_col=$c_dim
  fi
  name_cell=$(padw "${items_name[$i]}" $w_name)
  status_cell="${att_col}$(padw "$att_txt" $w_status)${c_reset}"
  time_cell=$(padw "${items_time[$i]}" $w_time)
  extra="$name_cell  $status_cell  $time_cell"
  if (( show_summary )); then
    extra+="  $(padw "${items_summary[$i]}" $w_summary)"
  fi
  if (( show_path )); then
    if (( $(dw "${items_path[$i]}") > w_path )); then
      extra+="  $(fit_left "${items_path[$i]}" $w_path)"
    else
      extra+="  $(padw "${items_path[$i]}" $w_path)"
    fi
  fi
  print -r -- "$extra"
}

fmt_header() {
  local extra
  extra="$(padw 名称 $w_name)  $(padw 状态 $w_status)  $(padw 最近活动 $w_time)"
  if (( show_summary )); then
    extra+="  $(padw 摘要 $w_summary)"
  fi
  if (( show_path )); then
    extra+="  $(padw 路径 $w_path)"
  fi
  print -r -- "$extra"
}

load_items() {
  loading=1
  local keep="${1-}" line when title cmd wname
  local -a raw sorted f
  if [[ -z $keep ]] && (( cursor >= 1 && cursor <= ${#items_id} )); then
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
  raw=()

  if [[ $HAS_TMUX -eq 1 ]] && tmuxx list-sessions >/dev/null 2>&1; then
    raw=("${(@f)$(tmuxx list-sessions -F $'#{session_activity}\x1f#{session_name}\x1f#{session_windows}\x1f#{?session_attached,1,0}\x1f#{pane_current_path}\x1f#{window_name}\x1f#{pane_title}\x1f#{pane_current_command}')}")
  fi

  if (( ${#raw} )); then
    sorted=("${(@f)$(printf '%s\n' "${raw[@]}" | sort -t $'\x1f' -k1,1nr)}")
    for line in "${sorted[@]}"; do
      [[ -z $line ]] && continue
      f=("${(@ps:\x1f:)line}")
      (( ${#f} < 8 )) && continue
      strftime -s when '%m-%d %H:%M' "${f[1]}"
      wname=${f[6]}
      title=${f[7]}
      cmd=${f[8]}
      items_kind+=("session")
      items_id+=("${f[2]}")
      items_name+=("${f[2]}")
      items_att+=("${f[4]}")
      items_time+=("$when")
      items_path+=("$(short_path "${f[5]}")")
      items_summary+=("$(useful_summary "$title" "$cmd" "$wname")")
      items_cmd+=("$cmd")
    done
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
  fi

  items_kind+=("shell")
  items_id+=("shell")
  items_name+=("普通 shell（不进 tmux，exit 返回）")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")

  items_kind+=("hosts")
  items_id+=("hosts")
  items_name+=("换一台机器")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")

  items_kind+=("quit")
  items_id+=("quit")
  items_name+=("退出")
  items_att+=("")
  items_time+=("")
  items_path+=("")
  items_summary+=("")
  items_cmd+=("")

  cursor=1
  if [[ -n $keep ]]; then
    local i
    for i in {1..${#items_id}}; do
      if [[ ${items_id[$i]} == "$keep" ]]; then
        cursor=$i
        break
      fi
    done
  fi
  loading=0
}

session_preview_lines() {
  local name=$1 cmd=$4
  local -i max_lines=$2 cols=$3 hist start i
  local cap line stripped
  local -a kept raw_lines
  kept=()
  (( max_lines < 1 )) && return
  hist=$(( max_lines + 120 ))
  (( hist < 160 )) && hist=160
  (( hist > 400 )) && hist=400
  cap=$(tmuxx capture-pane -t "=$name:." -p -J -S -$hist 2>/dev/null) || cap=""
  if [[ -z ${cap//[$' \t\n']/} ]]; then
    cap=$(tmuxx capture-pane -t "=$name:." -a -p -J -S -$hist 2>/dev/null) || cap=""
  fi
  raw_lines=("${(@f)cap}")
  for line in "${raw_lines[@]}"; do
    line="${line%"${line##*[![:space:]]}"}"
    stripped=${line//[[:space:]]/}
    [[ -z $stripped || $stripped == █ ]] && continue
    kept+=("$line")
  done
  (( ${#kept} == 0 )) && return
  if (( ${#kept} > max_lines )); then
    if [[ $cmd == *grok* ]]; then
      kept=("${(@)kept[1,max_lines]}")
    else
      start=$(( ${#kept} - max_lines + 1 ))
      kept=("${(@)kept[start,-1]}")
    fi
  fi
  for line in "${kept[@]}"; do
    print -r -- "$(fit_right "$line" $cols)"
  done
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
  local buf piece
  keys=("↑↓/jk 选择" "Enter 进入" "n 新建" "e 重命名" "d 删除" "h 换机器" "r 刷新" "q 退出")
  buf=""
  for piece in "${keys[@]}"; do
    if [[ -z $buf ]]; then
      buf="  $piece"
      continue
    fi
    if (( $(dw "$buf  $piece") > max )); then
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
  local mark line header sep
  cols=$(term_cols)
  rows=$(term_lines)
  n=${#items_kind}
  compute_layout $(( cols - 10 ))
  draw_remain=$(( rows > 1 ? rows - 1 : 1 ))

  for i in {1..$n}; do
    [[ ${items_kind[$i]} == session ]] && session_end=$i
  done

  print -n $'\e[H\e[J'
  draw_emit "${c_bold}  $(fit_right "$(hostname -s)  选择 tmux session" $(( cols - 2 )))${c_reset}" || return
  draw_help $cols || return
  draw_emit "" || return

  if [[ $HAS_TMUX -ne 1 ]]; then
    draw_emit "  ${c_dim}（这台机器上没有 tmux，可以直接进普通 shell；exit 或 Ctrl+D 返回）${c_reset}" || return
    draw_emit "" || return
  elif (( session_end == 0 )); then
    draw_emit "  ${c_dim}（当前没有 session）${c_reset}" || return
    draw_emit "" || return
  else
    header=$(fmt_header)
    draw_emit "  ${c_dim}    #  ${header}${c_reset}" || return
    sep=$(printf '%*s' $(( cols - 4 )) '')
    sep=${sep// /─}
    draw_emit "  ${c_dim}${sep}${c_reset}" || return
  fi

  for i in {1..$n}; do
    if (( i == session_end + 1 && session_end > 0 )); then
      draw_emit "" || break
    fi
    if [[ ${items_kind[$i]} == session ]]; then
      line=$(fmt_session_row $i)
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
    draw_emit "$(printf '  %s %2d  %s' "$mark" "$i" "$line")" || break
  done

  if [[ ${items_kind[$cursor]} == session ]] && (( draw_remain >= 3 )); then
    local pname psum pmeta pl
    local -a plines
    draw_emit "" || return
    pname=$(fit_right "${items_name[$cursor]}" 20)
    psum=$(fit_right "${items_summary[$cursor]}" $(( cols - 10 - $(dw "$pname") )))
    draw_emit "  ${c_cyan}预览${c_reset}  ${c_bold}${pname}${c_reset}  ${c_dim}${psum}${c_reset}" || return
    pmeta=$(fit_right "${items_path[$cursor]}  ·  ${items_cmd[$cursor]}" $(( cols - 4 )))
    draw_emit "  ${c_dim}${pmeta}${c_reset}" || return
    if (( draw_remain > 0 )); then
      plines=("${(@f)$(session_preview_lines "${items_id[$cursor]}" $draw_remain $(( cols - 4 )) "${items_cmd[$cursor]}")}")
      for pl in "${plines[@]}"; do
        draw_emit "  ${c_dim}${pl}${c_reset}" || break
      done
    fi
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
  local k k2 k3
  if [[ -n $PENDING_KEY ]]; then
    k=$PENDING_KEY
    PENDING_KEY=""
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
    k|K) REPLY=up ;;
    j|J) REPLY=down ;;
    q|Q) REPLY=q ;;
    n|N) REPLY=n ;;
    s|S) REPLY=s ;;
    r|R) REPLY=r ;;
    d|D) REPLY=d ;;
    e|E) REPLY=e ;;
    h|H) REPLY=h ;;
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
  local name
  read -r name
  name=${name##[[:space:]]#}
  name=${name%%[[:space:]]#}
  if [[ -z $name ]]; then
    tmux_tty new-session
  elif tmuxx has-session -t "=$name" 2>/dev/null; then
    print "session「${name}」已存在，直接进入。"
    tmux_tty attach-session -t "=$name"
  else
    tmux_tty new-session -s "$name"
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
  setup_tty
  load_items "$name"
  draw
}

if [[ ${1:-} == --digit-selftest ]]; then
  . "${0:A:h}/lanjump-digit-selftest.zsh"
  digit_selftest
  exit $?
fi

tmux_prepare_color
tmux_prepare_keys
load_items
setup_tty
draw

while true; do
  read_key || continue
  case $REPLY in
    up)
      (( cursor-- ))
      (( cursor < 1 )) && cursor=${#items_kind}
      draw
      ;;
    down)
      (( cursor++ ))
      (( cursor > ${#items_kind} )) && cursor=1
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