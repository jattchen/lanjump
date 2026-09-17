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
  local json v epoch
  if [[ -n ${LANJUMP_REMOTE_SHA:-} ]]; then
    print -r -- "$LANJUMP_REMOTE_SHA"
    return 0
  fi
  json=$(curl -fsSL -A lanjump -H 'Accept: application/vnd.github+json' "$VERSION_API") || return 1
  epoch=$(print -r -- "$json" | python3 -c 'import json,sys
from datetime import datetime
j=json.load(sys.stdin)
d=j["commit"]["committer"]["date"]
print(int(datetime.fromisoformat(d.replace("Z","+00:00")).timestamp()))' 2>/dev/null) || epoch=
  if v=$(print -r -- "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' 2>/dev/null); then
    print -r -- "$v"
    [[ $epoch =~ ^[0-9]+$ ]] && print -r -- "$epoch"
    return 0
  fi
  if [[ $json =~ '"sha": "([0-9a-f]{40})"' ]]; then
    print -r -- "$match[1]"
    [[ $epoch =~ ^[0-9]+$ ]] && print -r -- "$epoch"
    return 0
  fi
  return 1
}

# Command substitution cannot keep assignments from fetch_remote_ver.
# First line is the SHA (want_ver); optional second line is commit epoch.
take_remote_ver() {
  local out rest
  out=$(fetch_remote_ver) || return 1
  want_ver=${out%%$'\n'*}
  rest=${out#*$'\n'}
  if [[ $rest != "$out" && $rest =~ ^[0-9]+$ ]]; then
    REMOTE_COMMIT_TIME=$rest
  fi
  [[ -n $want_ver ]]
}

local_git_ver() {
  git -C "$ROOT" rev-parse HEAD 2>/dev/null || return 1
}

# #310: picker header stamp is commit time, not this machine's file mtime.
write_picker_version_stamp() {
  local picker="$APP/lanjump-pick.zsh" sha=${want_ver:-} epoch tmp first
  [[ -f $picker && -n $sha ]] || return 0
  if grep -q '^# lanjump-pick-version ' "$picker" 2>/dev/null; then
    return 0
  fi
  epoch=$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null) || epoch=${REMOTE_COMMIT_TIME:-}
  [[ $epoch =~ ^[0-9]+$ ]] || return 0
  tmp=$(mktemp "${picker}.XXXXXX") || return 0
  first=$(head -n 1 "$picker")
  if [[ $first == '#!'* ]]; then
    {
      print -r -- "$first"
      print -r -- "# lanjump-pick-version $epoch $sha"
      tail -n +2 "$picker"
    } >"$tmp"
  else
    {
      print -r -- "# lanjump-pick-version $epoch $sha"
      cat "$picker"
    } >"$tmp"
  fi
  mv -f "$tmp" "$picker"
}

have_ver=
want_ver=
REMOTE_COMMIT_TIME=
have_ver=$(read_local_ver) || have_ver=

if [[ $mode == 升级 ]]; then
  if take_remote_ver; then
    :
  else
    want_ver=
  fi
  if [[ -z ${LANJUMP_ARCHIVE_URL:-} && -n $want_ver ]]; then
    ARCHIVE_URL="https://github.com/jattchen/lanjump/archive/${want_ver}.tar.gz"
  fi
  if [[ -n $have_ver && -n $want_ver && $have_ver == "$want_ver" ]]; then
    # #355: same SHA is only a no-op when the files upgrade is asked to repair still exist.
    if [[ -f $APP/lanjump.zsh && -f $APP/lanjump-pick.zsh ]]; then
      print "没有新版本。当前已是 $(short_ver "$have_ver")。"
      exit 0
    fi
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
  # curl | zsh: $0 is /bin/zsh, so ROOT is not the repo and git rev-parse fails.
  if [[ -z $want_ver ]]; then
    take_remote_ver || want_ver=
  fi
  if [[ -z ${LANJUMP_ARCHIVE_URL:-} && -n $want_ver ]]; then
    ARCHIVE_URL="https://github.com/jattchen/lanjump/archive/${want_ver}.tar.gz"
  fi
  print '正在安装 lanjump …'
fi
print

fetched=
stage=
cleanup() {
  if [[ ! -e $APP && -d $APP.old ]]; then
    mv -f "$APP.old" "$APP"
  fi
  [[ -n $fetched ]] && rm -rf "$fetched"
  if [[ -n $stage && -d $stage && $stage != "$APP" ]]; then
    rm -rf "$stage"
  fi
}
trap cleanup EXIT
trap 'print -u2 "${mode}失败。"' ERR

# 系统若开了「显示所有文件扩展名」，.command 的「隐藏扩展名」不会在桌面上生效。
# 真正的脚本放进 Application Support，桌面放无后缀的访达替身，显示名就是「启动 lanjump」。
# 只清官方启动器文件名或与官方启动器内容完全一致的副本，不删只是提到 lanjump 目录的用户脚本。
is_official_desktop_launcher_name() {
  local name=${1:t}
  [[ $name == 'Lanjump.command' || $name == '启动 lanjump.command' ]]
}

is_official_desktop_launcher_content() {
  local f=$1
  [[ -f $f ]] || return 1
  if [[ -n ${APP_LAUNCHER:-} && -f $APP_LAUNCHER ]]; then
    cmp -s "$f" "$APP_LAUNCHER" && return 0
  fi
  [[ -f $ROOT/bin/lanjump.command ]] && cmp -s "$f" "$ROOT/bin/lanjump.command"
}

is_lanjump_desktop_script() {
  local f=$1
  [[ -f $f ]] || return 1
  is_official_desktop_launcher_name "$f" && return 0
  is_official_desktop_launcher_content "$f"
}

# HOME 指向测试假家目录时也能进 $HOME/.Trash；失败再 rm。
trash_desktop_script() {
  local f=$1 dest
  mkdir -p "$HOME/.Trash"
  dest="$HOME/.Trash/${f:t}"
  if [[ -e $dest ]]; then
    dest="$HOME/.Trash/${f:t}.${RANDOM}"
  fi
  mv -f "$f" "$dest" 2>/dev/null || rm -f "$f"
}

remove_desktop_lanjump_scripts() {
  local f
  setopt localoptions nullglob
  for f in "$HOME/Desktop/"*; do
    is_lanjump_desktop_script "$f" || continue
    trash_desktop_script "$f"
  done
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
# 若这次刚下载了 tarball，且里面的 install.zsh 也是新版安装脚本，则用它覆盖
# 已保存的副本；否则 $SELF 就是 $APP/install.zsh，-ef 恒为真，第一次安装
# 留下的脚本会永远挡住后来新增的文件。
save_self_installer() {
  local src=$SELF
  if [[ ! -f $src || $src != *.zsh ]] || ! grep -q 'write_cli_launcher' "$src" 2>/dev/null; then
    src="$ROOT/install.zsh"
  fi
  if [[ -n ${fetched:-} && -f $ROOT/install.zsh ]] && grep -q 'write_cli_launcher' "$ROOT/install.zsh" 2>/dev/null; then
    src="$ROOT/install.zsh"
  fi
  [[ -f $src ]] || return 0
  grep -q 'write_cli_launcher' "$src" 2>/dev/null || return 0
  if [[ ! -e "$APP/install.zsh" || ! "$src" -ef "$APP/install.zsh" ]]; then
    # 升级时 $APP/install.zsh 就是正在跑的脚本，原地 cp 会改正在读的 inode。
    local tmp=$APP/install.zsh.new.$$
    cp -f "$src" "$tmp"
    chmod 755 "$tmp"
    mv -f "$tmp" "$APP/install.zsh"
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

if [[ ${1:-} == upgrade || ${1:-} == update ]]; then
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
  if ! curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$fetched"; then
    if [[ $mode != 升级 && -z ${LANJUMP_ARCHIVE_URL:-} && -n ${want_ver:-} && $ARCHIVE_URL != *'/archive/refs/heads/main.tar.gz' ]]; then
      # Empty dir: "$fetched"/* NOMATCH-aborts under set -e before fallback.
      rm -rf "$fetched"
      mkdir -p "$fetched"
      ARCHIVE_URL='https://github.com/jattchen/lanjump/archive/refs/heads/main.tar.gz'
      curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$fetched"
      # Installed heads/main, not the unused API sha. Do not stamp a lie.
      want_ver=
      REMOTE_COMMIT_TIME=
    else
      exit 1
    fi
  fi
  ROOT="$fetched/lanjump-main"
  if [[ ! -f $ROOT/lib/lanjump.zsh ]]; then
    extracted=($fetched/*(/))
    ROOT=${extracted[1]:-}
  fi
fi

# SIGKILL/power-loss after APP→APP.old and before APP.new→APP leaves
# user data only in APP.old. Restore that copy before mkdir -p / rm -rf
# so the next run cannot wipe the only remaining hosts/settings/pins.
if [[ -d $APP.old && ! -f $APP/lanjump.zsh ]]; then
  rm -rf "$APP"
  mv -f "$APP.old" "$APP"
fi

mkdir -p "$APP" "$BIN_DIR" "$HOME/.ssh" "$HOME/Desktop"
chmod 700 "$HOME/.ssh"
save_self_installer

# 先写到 $APP.new，整树成功后再 mv 进 $APP，避免中途失败留下新旧混合树。
stage=$APP.new
rm -rf "$stage"
mkdir -p "$stage"

cp -f "$ROOT/lib/lanjump.zsh" "$stage/lanjump.zsh"
cp -f "$ROOT/lib/lanjump-pick.zsh" "$stage/lanjump-pick.zsh"
if [[ -f $ROOT/bin/lanjump-ghostty-attach ]]; then
  cp -f "$ROOT/bin/lanjump-ghostty-attach" "$stage/lanjump-ghostty-attach"
fi
chmod 755 "$stage/lanjump.zsh" "$stage/lanjump-pick.zsh"

cp -f "$ROOT/lib/lanjump-keys.py" "$stage/lanjump-keys.py"
chmod 755 "$stage/lanjump-keys.py"
if [[ -f $ROOT/lib/lanjump-ime.py ]]; then
  cp -f "$ROOT/lib/lanjump-ime.py" "$stage/lanjump-ime.py"
fi

keys_err=$(mktemp)
keys_compiled=0
if cc -O2 -framework CoreGraphics -o "$stage/lanjump-keys" "$ROOT/src/lanjump-keys.c" 2>"$keys_err"; then
  chmod 755 "$stage/lanjump-keys"
  keys_compiled=1
else
  if ! command python3 -c '' >/dev/null 2>&1; then
    print -u2 '无法编译按键辅助，且本机 python3 不能运行，安装中止。'
    rm -f "$keys_err"
    exit 1
  fi
  cp -f "$stage/lanjump-keys.py" "$stage/lanjump-keys"
  chmod 755 "$stage/lanjump-keys"
fi
rm -f "$keys_err"

cp -f "$ROOT/bin/lanjump.command" "$stage/lanjump.command"
chmod 755 "$stage/lanjump.command"

# Carry keepers (settings, hosts, install.zsh, …) into the staged tree, then
# switch the live dir in one rename. A crash mid-loop of per-file mv used to
# leave a mixed old/new $APP (e.g. new main, old IME).
for f in "$APP"/*(ND); do
  [[ -e $stage/${f:t} ]] && continue
  cp -a "$f" "$stage/${f:t}"
done
old=$APP.old
rm -rf "$old"
# #335: recopy keepers immediately before the switch so a write that
# landed on live $APP after the first stage copy is not left on APP.old.
for f in "$APP"/*(ND); do
  name=${f:t}
  case $name in
    lanjump.zsh|lanjump-pick.zsh|lanjump-ghostty-attach|lanjump-keys.py|lanjump-ime.py|lanjump-keys|lanjump.command)
      continue
      ;;
  esac
  rm -rf "$stage/$name"
  cp -a "$f" "$stage/$name"
done
if ! mv "$APP" "$old"; then
  exit 1
fi
if ! mv "$stage" "$APP"; then
  mv -f "$old" "$APP"
  exit 1
fi
# #334: a concurrent mkdir -p $APP between the two mvs makes BSD mv nest
# APP.new as $APP/lanjump.new/. Do not discard APP.old unless the live
# tree landed at the app root.
if [[ ! -f $APP/lanjump.zsh ]]; then
  rm -rf "$APP"
  mv -f "$old" "$APP"
  exit 1
fi
stage=
rm -rf "$old"
write_picker_version_stamp

if [[ -f $APP/lanjump-ghostty-attach ]]; then
  cp -f "$APP/lanjump-ghostty-attach" "$BIN_DIR/lanjump-ghostty-attach"
  chmod 755 "$APP/lanjump-ghostty-attach" "$BIN_DIR/lanjump-ghostty-attach"
  xattr -d com.apple.quarantine "$BIN_DIR/lanjump-ghostty-attach" 2>/dev/null || true
fi

if (( keys_compiled )); then
  # macOS 26 can SIGKILL an adhoc helper copied onto this path (invalid signature).
  rm -f "$BIN_DIR/lanjump-keys"
  cp -f "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
  chmod 755 "$BIN_DIR/lanjump-keys"
  xattr -d com.apple.quarantine "$BIN_DIR/lanjump-keys" 2>/dev/null || true
  codesign --force --sign - "$APP/lanjump-keys" 2>/dev/null || true
  codesign --force --sign - "$BIN_DIR/lanjump-keys" 2>/dev/null || true
else
  cp -f "$APP/lanjump-keys.py" "$BIN_DIR/lanjump-keys"
  chmod 755 "$APP/lanjump-keys" "$BIN_DIR/lanjump-keys"
fi

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
  if [[ ! -f $ZSHRC ]] || ! grep -vE '^[[:space:]]*#' "$ZSHRC" 2>/dev/null | grep -qE '(^|[[:space:]])(export[[:space:]]+)?PATH=.*(\$HOME|~)/\.local/bin'; then
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
