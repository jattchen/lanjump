#!/bin/zsh
set -euo pipefail

SELF=${0:A}
ROOT=${SELF:h}
ARCHIVE_URL=${LANJUMP_ARCHIVE_URL:-'https://github.com/jattchen/lanjump/archive/refs/heads/main.tar.gz'}
VERSION_API=${LANJUMP_VERSION_API:-'https://api.github.com/repos/jattchen/lanjump/commits/main'}

if [[ ${1:-} == --tar ]]; then
  tar -C "$ROOT" -czf - install.zsh bin lib src
  exit 0
fi

mode=安装
if [[ ${1:-} == --upgrade ]]; then
  mode=升级
fi

APP="$HOME/Library/Application Support/lanjump"
APP_LAUNCHER="$APP/lanjump.command"
DESKTOP_NAME='启动 lanjump'
BIN_DIR="$HOME/.local/bin"
ZSHRC="$HOME/.zshrc"
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
VERSION_FILE="$APP/version"

short_ver() {
  local s=${1:-}
  [[ -n $s ]] || return
  print -r -- "${s[1,7]}"
}

read_local_ver() {
  local v
  [[ -f $VERSION_FILE ]] || return 1
  v=$(<"$VERSION_FILE")
  v=${v%%$'\n'*}
  v=${v// /}
  [[ $v =~ '^[0-9a-f]{7,}$' ]] || return 1
  print -r -- "$v"
}

fetch_remote_ver() {
  local json v
  if [[ -n ${LANJUMP_REMOTE_SHA:-} ]]; then
    print -r -- "$LANJUMP_REMOTE_SHA"
    return 0
  fi
  json=$(curl -fsSL -A lanjump -H 'Accept: application/vnd.github+json' "$VERSION_API") || return 1
  if v=$(print -r -- "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' 2>/dev/null); then
    print -r -- "$v"
    return 0
  fi
  if [[ $json =~ '"sha": "([0-9a-f]{40})"' ]]; then
    print -r -- "$match[1]"
    return 0
  fi
  return 1
}

local_git_ver() {
  git -C "$ROOT" rev-parse HEAD 2>/dev/null || return 1
}

have_ver=
want_ver=
have_ver=$(read_local_ver) || have_ver=

if [[ $mode == 升级 ]]; then
  if want_ver=$(fetch_remote_ver); then
    :
  else
    want_ver=
  fi
  if [[ -n $have_ver && -n $want_ver && $have_ver == "$want_ver" ]]; then
    print "没有新版本。当前已是 $(short_ver "$have_ver")。"
    exit 0
  fi
  if [[ -n $have_ver && -n $want_ver ]]; then
    print "正在从 $(short_ver "$have_ver") 升级到 $(short_ver "$want_ver") …"
  elif [[ -n $want_ver ]]; then
    print "正在升级到 $(short_ver "$want_ver") …"
  else
    print '无法核对本机和网上的版本，将重新安装。'
    print '正在升级 lanjump …'
  fi
else
  want_ver=$(local_git_ver) || want_ver=
  print '正在安装 lanjump …'
fi
print

fetched=
cleanup() {
  [[ -n $fetched ]] && rm -rf "$fetched"
}
trap cleanup EXIT
trap 'print -u2 "${mode}失败。"' ERR

# 系统若开了「显示所有文件扩展名」，.command 的「隐藏扩展名」不会在桌面上生效。
# 真正的脚本放进 Application Support，桌面放无后缀的访达替身，显示名就是「启动 lanjump」。
is_lanjump_desktop_script() {
  local f=$1 first
  [[ -f $f ]] || return 1
  first=$(head -n 1 "$f" 2>/dev/null) || return 1
  [[ $first == '#!/bin/zsh' ]] || return 1
  grep -qF 'Application Support/lanjump' "$f"
}

remove_desktop_lanjump_scripts() {
  local f
  setopt localoptions nullglob
  for f in "$HOME/Desktop/"*; do
    is_lanjump_desktop_script "$f" || continue
    rm -f "$f"
  done
  rm -f "$HOME/Desktop/Lanjump.command" "$HOME/Desktop/启动 lanjump.command"
}

# 已有指向本脚本的替身就改名为「启动 lanjump」，没有则新建。不进废纸篓。
# :A 解开 /var → /private/var，否则访达里的原件路径对不上，会再造一个同名替身。
ensure_desktop_alias() {
  local desk=${1:A} src=${2:A} wanted=$3
  if [[ -e "$desk/$wanted" && $(file -b "$desk/$wanted") == *Alias* ]]; then
    return 0
  fi
  osascript - "$desk" "$src" "$wanted" <<'APPLESCRIPT'
on run argv
  set deskPath to item 1 of argv
  set srcPath to item 2 of argv
  set wanted to item 3 of argv
  set desk to POSIX file deskPath as alias
  set src to POSIX file srcPath as alias
  tell application "Finder"
    set keeper to missing value
    set itemList to every item of folder desk
    repeat with f in itemList
      try
        if class of f is alias file then
          set orig to POSIX path of (original item of f as alias)
          if orig is srcPath or orig is (srcPath & "/") then
            if keeper is missing value then
              set keeper to f
            else
              do shell script "rm -f " & quoted form of (deskPath & "/" & name of f)
            end if
          end if
        end if
      end try
    end repeat
    if keeper is missing value then
      make alias file at desk to src with properties {name:wanted}
    else if name of keeper is not wanted then
      set name of keeper to wanted
    end if
  end tell
  return "ok"
end run
APPLESCRIPT
}

hide_finder_extension() {
  local f=$1
  [[ -e $f ]] || return 0
  xattr -wx com.apple.FinderInfo \
    0000000000000000001000000000000000000000000000000000000000000000 \
    "$f" 2>/dev/null || true
}

# 把当前这份安装脚本存下来。升级走它，而不是 GitHub 上可能更旧的 install.zsh。
save_self_installer() {
  local src=$SELF
  if [[ ! -f $src || $src != *.zsh ]] || ! grep -q 'write_cli_launcher' "$src" 2>/dev/null; then
    src="$ROOT/install.zsh"
  fi
  [[ -f $src ]] || return 0
  grep -q 'write_cli_launcher' "$src" 2>/dev/null || return 0
  if [[ ! -e "$APP/install.zsh" || ! "$src" -ef "$APP/install.zsh" ]]; then
    cp -f "$src" "$APP/install.zsh"
  fi
  chmod 755 "$APP/install.zsh"
}

# 启动器由安装脚本自己写出，避免网上旧包里的 bin/lanjump 把 upgrade 盖掉。
write_cli_launcher() {
  cat > "$BIN_DIR/lanjump" <<'EOF'
#!/bin/zsh
# Terminal launcher for lanjump. Install with: zsh install.zsh

set -u

APP="$HOME/Library/Application Support/lanjump"
MAIN="$APP/lanjump.zsh"
INSTALLER="$APP/install.zsh"

if [[ ${1:-} == upgrade || ${1:-} == 升级 ]]; then
  if [[ ! -f $INSTALLER ]]; then
    print -u2 '找不到安装脚本。请重新安装：zsh install.zsh'
    exit 1
  fi
  exec /bin/zsh "$INSTALLER" --upgrade
fi

if [[ ! -f $MAIN ]]; then
  print "lanjump is not installed. From the repo run: zsh install.zsh" >&2
  exit 1
fi

chmod 755 "$MAIN" "$APP/lanjump-pick.zsh" 2>/dev/null || true
exec /bin/zsh "$MAIN" "$@"
EOF
  chmod 755 "$BIN_DIR/lanjump"
  xattr -d com.apple.quarantine "$BIN_DIR/lanjump" 2>/dev/null || true
}

if [[ $mode == 升级 || ! -f $ROOT/lib/lanjump.zsh || ! -f $ROOT/bin/lanjump || ! -f $ROOT/src/lanjump-keys.c ]]; then
  fetched=$(mktemp -d)
  curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$fetched"
  ROOT="$fetched/lanjump-main"
  if [[ ! -f $ROOT/lib/lanjump.zsh ]]; then
    extracted=($fetched/*(/))
    ROOT=${extracted[1]:-}
  fi
fi

mkdir -p "$APP" "$BIN_DIR" "$HOME/.ssh" "$HOME/Desktop"
chmod 700 "$HOME/.ssh"
save_self_installer

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

cp -f "$ROOT/bin/lanjump.command" "$APP_LAUNCHER"
chmod 755 "$APP_LAUNCHER"
xattr -d com.apple.quarantine "$APP_LAUNCHER" 2>/dev/null || true
remove_desktop_lanjump_scripts
if ! ensure_desktop_alias "$HOME/Desktop" "$APP_LAUNCHER" "$DESKTOP_NAME" >/dev/null; then
  cp -f "$APP_LAUNCHER" "$HOME/Desktop/${DESKTOP_NAME}.command"
  chmod 755 "$HOME/Desktop/${DESKTOP_NAME}.command"
  xattr -d com.apple.quarantine "$HOME/Desktop/${DESKTOP_NAME}.command" 2>/dev/null || true
  hide_finder_extension "$HOME/Desktop/${DESKTOP_NAME}.command"
fi

write_cli_launcher

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

if [[ -n $want_ver ]]; then
  print -r -- "$want_ver" >"$VERSION_FILE"
fi

if [[ $mode == 升级 ]]; then
  if [[ -n $have_ver && -n $want_ver ]]; then
    print "已从 $(short_ver "$have_ver") 升级到 $(short_ver "$want_ver")。"
  elif [[ -n $want_ver ]]; then
    print "已升级到 $(short_ver "$want_ver")。"
  else
    print '升级完成。'
  fi
else
  print '安装完成。'
  if [[ -n $want_ver ]]; then
    print "版本 $(short_ver "$want_ver")。"
  fi
fi
print
print '打开方式'
print '  终端输入  lanjump'
print '  或双击桌面  启动 lanjump'
if (( path_note )); then
  print
  print '已把 lanjump 命令加入终端。请新开一个终端，或执行：'
  print '  source ~/.zshrc'
fi
