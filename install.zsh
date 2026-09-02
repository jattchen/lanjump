#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
APP="$HOME/Library/Application Support/lan-ssh"
DESKTOP="$HOME/Desktop/LAN-SSH.command"
OLD_DESKTOP="$HOME/Desktop/SSH 局域网.command"

mkdir -p "$APP"
cp -f "$ROOT/lib/lan-ssh.zsh" "$APP/lan-ssh.zsh"
cp -f "$ROOT/lib/tmux-pick.zsh" "$APP/tmux-pick.zsh"
chmod 755 "$APP/lan-ssh.zsh" "$APP/tmux-pick.zsh"

cp -f "$ROOT/bin/lan-ssh.command" "$DESKTOP"
chmod 755 "$DESKTOP"
xattr -d com.apple.quarantine "$DESKTOP" 2>/dev/null || true
if [[ -e $OLD_DESKTOP ]]; then
  rm -f "$OLD_DESKTOP"
fi

print "Installed:"
print "  $APP/lan-ssh.zsh"
print "  $APP/tmux-pick.zsh"
print "  $DESKTOP"
print "Double-click LAN-SSH.command on the Desktop to run."
