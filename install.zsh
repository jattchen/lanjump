#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}

if [[ ${1:-} == --tar ]]; then
  tar -C "$ROOT" -czf - install.zsh bin lib src
  exit 0
fi

APP="$HOME/Library/Application Support/lanjump"
OLD_APP="$HOME/Library/Application Support/lan-ssh"
DESKTOP="$HOME/Desktop/Lanjump.command"
BIN_DIR="$HOME/.local/bin"
KEY="$HOME/.ssh/id_ed25519_lanjump"
OLD_KEY="$HOME/.ssh/id_ed25519_lan"

mkdir -p "$APP" "$BIN_DIR" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -d $OLD_APP ]]; then
  if [[ ! -s $APP/hosts && -f $OLD_APP/hosts ]]; then
    cp -p "$OLD_APP/hosts" "$APP/hosts"
  fi
  if [[ ! -f $APP/last_target && -f $OLD_APP/last_target ]]; then
    cp -p "$OLD_APP/last_target" "$APP/last_target"
  fi
fi

if [[ ! -f $KEY && -f $OLD_KEY ]]; then
  mv "$OLD_KEY" "$KEY"
  [[ -f $OLD_KEY.pub ]] && mv "$OLD_KEY.pub" "$KEY.pub"
  chmod 600 "$KEY"
  [[ -f $KEY.pub ]] && chmod 644 "$KEY.pub"
  ssh-keygen -c -C "lanjump@$(hostname -s)" -f "$KEY" >/dev/null 2>&1 || true
fi

cp -f "$ROOT/lib/lanjump.zsh" "$APP/lanjump.zsh"
cp -f "$ROOT/lib/lanjump-pick.zsh" "$APP/lanjump-pick.zsh"
chmod 755 "$APP/lanjump.zsh" "$APP/lanjump-pick.zsh"

cp -f "$ROOT/lib/lanjump-keys.py" "$APP/lanjump-keys.py"
chmod 755 "$APP/lanjump-keys.py"

keys_err=$(mktemp)
if cc -O2 -framework CoreGraphics -o "$APP/lanjump-keys" "$ROOT/src/lanjump-keys.c" 2>"$keys_err"; then
  cp -f "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
  chmod 755 "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
  xattr -d com.apple.quarantine "$BIN_DIR/lanjump-keys" 2>/dev/null || true
  keys_kind=c
else
  cp -f "$APP/lanjump-keys.py" "$APP/lanjump-keys"
  cp -f "$APP/lanjump-keys.py" "$BIN_DIR/lanjump-keys"
  chmod 755 "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
  keys_kind=py
fi
rm -f "$keys_err"

cp -f "$ROOT/bin/lanjump.command" "$DESKTOP"
chmod 755 "$DESKTOP"
xattr -d com.apple.quarantine "$DESKTOP" 2>/dev/null || true

cp -f "$ROOT/bin/lanjump" "$BIN_DIR/lanjump"
chmod 755 "$BIN_DIR/lanjump"
xattr -d com.apple.quarantine "$BIN_DIR/lanjump" 2>/dev/null || true

for old in \
  "$HOME/Desktop/LAN-SSH.command" \
  "$HOME/Desktop/SSH 局域网.command" \
  "$BIN_DIR/lan-tmux-pick"
do
  [[ -e $old ]] && rm -f "$old"
done

if [[ -d $OLD_APP ]]; then
  rm -rf "$OLD_APP"
fi

print "Installed:"
print "  $APP/lanjump.zsh"
print "  $APP/lanjump-pick.zsh"
print "  $DESKTOP"
print "  $BIN_DIR/lanjump"
if [[ $keys_kind == c ]]; then
  print "  $BIN_DIR/lanjump-keys  (Shift+Enter 换行)"
else
  print "  $BIN_DIR/lanjump-keys  (Python 备用，Shift+Enter 换行)"
fi
print
print "In a terminal, run:  lanjump"
print "Or double-click Lanjump.command on the Desktop."
print "Shift+Enter 换行要装在你敲键盘的那台 Mac 上。"
if [[ :$PATH: != *:$BIN_DIR:* ]]; then
  print
  print "Note: $BIN_DIR is not on PATH. Add this to ~/.zshrc:"
  print '  export PATH="$HOME/.local/bin:$PATH"'
fi
