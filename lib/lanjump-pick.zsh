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

if [[ ! -t 0 || ! -t 1 ]]; then
  print "需要交互式终端。"
  exit 1
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
w_name=4 w_status=6 w_time=11 w_summary=4 w_path=4
show_summary=1
show_path=1

tmuxx() {
  [[ -n $TMUX_BIN ]] || return 1
  command "$TMUX_BIN" "$@" </dev/null
}

tmux_tty() {
  command "$TMUX_BIN" "$@"
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
  local keep="" line when title cmd wname
  local -a raw sorted f
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

draw() {
  local -i cols rows i n session_end=0
  local mark line header sep
  cols=$(term_cols)
  rows=$(term_lines)
  n=${#items_kind}
  compute_layout $(( cols - 10 ))

  for i in {1..$n}; do
    [[ ${items_kind[$i]} == session ]] && session_end=$i
  done

  print -n $'\e[H\e[J'
  print "${c_bold}  $(hostname -s)  选择 tmux session${c_reset}"
  print "${c_dim}  ↑↓/jk 选择   Enter 进入   n 新建   d 删除   h 换机器   r 刷新   q 退出${c_reset}"
  print

  if [[ $HAS_TMUX -ne 1 ]]; then
    print "  ${c_dim}（这台机器上没有 tmux，可以直接进普通 shell；exit 或 Ctrl+D 返回）${c_reset}"
    print
  elif (( session_end == 0 )); then
    print "  ${c_dim}（当前没有 session）${c_reset}"
    print
  else
    header=$(fmt_header)
    print "  ${c_dim}    #  ${header}${c_reset}"
    sep=$(printf '%*s' $(( cols - 4 )) '')
    sep=${sep// /─}
    print "  ${c_dim}${sep}${c_reset}"
  fi

  for i in {1..$n}; do
    if (( i == session_end + 1 && session_end > 0 )); then
      print
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
    printf '  %s %2d  %s\n' "$mark" "$i" "$line"
  done

  if [[ ${items_kind[$cursor]} == session ]]; then
    local -i printed preview_n
    printed=3
    (( printed += 2 ))
    (( printed += n ))
    (( session_end > 0 )) && (( printed += 1 ))
    (( printed += 3 ))
    preview_n=$(( rows - printed ))
    (( preview_n < 1 )) && preview_n=1
    print
    print "  ${c_cyan}预览${c_reset}  ${c_bold}${items_name[$cursor]}${c_reset}  ${c_dim}${items_summary[$cursor]}${c_reset}"
    print "  ${c_dim}${items_path[$cursor]}  ·  ${items_cmd[$cursor]}${c_reset}"
    session_preview_lines "${items_id[$cursor]}" $preview_n $(( cols - 4 )) "${items_cmd[$cursor]}" | while IFS= read -r line; do
      print "  ${c_dim}${line}${c_reset}"
    done
  fi
}

read_key() {
  local k k2 k3
  IFS= read -rsk1 k || return 1
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
      /bin/zsh -l
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
      n=${REPLY#num}
      if (( n >= 1 && n <= ${#items_kind} )); then
        cursor=$n
        activate $cursor
      fi
      ;;
  esac
done