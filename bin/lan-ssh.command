#!/bin/zsh
# Desktop launcher for lan-ssh. Install with: zsh install.zsh

set -u

APP="$HOME/Library/Application Support/lan-ssh"
MAIN="$APP/lan-ssh.zsh"

pause() {
  echo
  echo "$1"
  echo -n "Press Return to close…"
  read -r
}

if [[ ! -f $MAIN ]]; then
  pause "lan-ssh is not installed. From the repo run: zsh install.zsh"
  exit 1
fi

chmod 755 "$MAIN" "$APP/tmux-pick.zsh" 2>/dev/null || true
/bin/zsh "$MAIN"
code=$?
if (( code != 0 )); then
  pause "已退出（代码 ${code}）。"
fi
exit $code
