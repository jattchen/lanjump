#!/bin/zsh
set -euo pipefail

ROOT=${0:A:h}
ARCHIVE_URL='https://github.com/jattchen/lanjump/archive/refs/heads/main.tar.gz'

if [[ ${1:-} == --tar ]]; then
  tar -C "$ROOT" -czf - install.zsh bin lib src
  exit 0
fi

print '正在安装 lanjump …'
print

fetched=
cleanup() {
  [[ -n $fetched ]] && rm -rf "$fetched"
}
trap cleanup EXIT
trap 'print -u2 "安装失败。"' ERR

if [[ ! -f $ROOT/lib/lanjump.zsh || ! -f $ROOT/bin/lanjump || ! -f $ROOT/src/lanjump-keys.c ]]; then
  fetched=$(mktemp -d)
  curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$fetched"
  ROOT="$fetched/lanjump-main"
  if [[ ! -f $ROOT/lib/lanjump.zsh ]]; then
    extracted=($fetched/*(/))
    ROOT=${extracted[1]:-}
  fi
fi

APP="$HOME/Library/Application Support/lanjump"
OLD_APP="$HOME/Library/Application Support/lan-ssh"
DESKTOP="$HOME/Desktop/Lanjump.command"
BIN_DIR="$HOME/.local/bin"
KEY="$HOME/.ssh/id_ed25519_lanjump"
OLD_KEY="$HOME/.ssh/id_ed25519_lan"
ZSHRC="$HOME/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

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
  chmod 755 "$APP/lanjump-keys"
  # macOS 26 can SIGKILL an adhoc helper copied onto this path (invalid signature).
  rm -f "$BIN_DIR/lanjump-keys"
  cp -f "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
  chmod 755 "$BIN_DIR/lanjump-keys"
  xattr -d com.apple.quarantine "$BIN_DIR/lanjump-keys" 2>/dev/null || true
  codesign --force --sign - "$APP/lanjump-keys" 2>/dev/null || true
  codesign --force --sign - "$BIN_DIR/lanjump-keys" 2>/dev/null || true
else
  cp -f "$APP/lanjump-keys.py" "$APP/lanjump-keys"
  cp -f "$APP/lanjump-keys.py" "$BIN_DIR/lanjump-keys"
  chmod 755 "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
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

path_note=0
if [[ :$PATH: != *:$BIN_DIR:* ]]; then
  if [[ ! -f $ZSHRC ]] || ! grep -qE '(^|[[:space:]])(export[[:space:]]+)?PATH=.*(\$HOME|~)/\.local/bin' "$ZSHRC" 2>/dev/null; then
    if [[ ! -f $ZSHRC ]]; then
      print '# lanjump' > "$ZSHRC"
      print "$PATH_LINE" >> "$ZSHRC"
    else
      print >> "$ZSHRC"
      print '# lanjump' >> "$ZSHRC"
      print "$PATH_LINE" >> "$ZSHRC"
    fi
  fi
  path_note=1
fi

print '安装完成。'
print
print '打开方式'
print '  终端输入  lanjump'
print '  或双击桌面  Lanjump.command'
if (( path_note )); then
  print
  print '已把 lanjump 命令加入终端。请新开一个终端，或执行：'
  print '  source ~/.zshrc'
fi
