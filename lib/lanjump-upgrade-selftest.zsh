#!/bin/zsh
# Run from repo: zsh lib/lanjump-upgrade-selftest.zsh
emulate -L zsh
set -euo pipefail

ROOT=${0:A:h:h}
fails=0

fail() {
  print -u2 "FAIL $1"
  fails=1
}

desktop_names() {
  local f
  for f in "$1/"*(N); do
    print -r -- "${f:t}"
  done
}

# APFS is usually case-insensitive, so -e Lanjump.command is also true for lanjump.command.
has_desktop_name() {
  local dir=$1 name=$2 f
  for f in "$dir/"*(N); do
    [[ ${f:t} == "$name" ]] && return 0
  done
  return 1
}

fakehome=$(mktemp -d)
mkdir -p "$fakehome/Desktop" "$fakehome/.ssh" "$fakehome/Library/Application Support"
cp "$ROOT/bin/lanjump.command" "$fakehome/Desktop/启动 xx.command"
chmod 755 "$fakehome/Desktop/启动 xx.command"
print old >"$fakehome/Desktop/Lanjump.command"
# #215: a user script that only mentions the app dir must survive install.
cat >"$fakehome/Desktop/my-custom-tool.command" <<'EOF'
#!/bin/zsh
# helper that mentions Application Support/lanjump but is not the launcher
print custom
EOF
chmod 755 "$fakehome/Desktop/my-custom-tool.command"
HOME=$fakehome /bin/zsh "$ROOT/install.zsh" >/dev/null

if [[ -e "$fakehome/Desktop/启动 xx.command" || -e "$fakehome/Desktop/Lanjump.command" || -e "$fakehome/Desktop/启动 lanjump.command" ]]; then
  fail "old desktop scripts still present: $(desktop_names "$fakehome/Desktop")"
fi
if [[ ! -f "$fakehome/Desktop/my-custom-tool.command" ]]; then
  fail "install deleted custom desktop script that only mentioned lanjump"
fi
if [[ ! -x "$fakehome/Library/Application Support/lanjump/install.zsh" ]]; then
  fail "installer was not saved to app dir"
fi
if [[ ! -x "$fakehome/Library/Application Support/lanjump/lanjump.command" ]]; then
  fail "missing app launcher"
fi
desk="$fakehome/Desktop/启动 lanjump"
if [[ ! -e "$desk" ]]; then
  fail "missing desktop 启动 lanjump"
fi
kind=$(file -b "$desk")
if [[ $kind != *Alias* ]]; then
  fail "desktop item is not an alias ($kind)"
fi
if ! grep -q 'INSTALLER=' "$fakehome/.local/bin/lanjump"; then
  fail "installed launcher has no local upgrade"
fi
if [[ ! -x "$fakehome/.local/bin/lanjump-ghostty-attach" ]]; then
  fail "missing ~/.local/bin/lanjump-ghostty-attach"
fi
local_sha=$(git -C "$ROOT" rev-parse HEAD)
if [[ $(<"$fakehome/Library/Application Support/lanjump/version") != "$local_sha" ]]; then
  fail "install did not record repo revision"
fi

# Same remote SHA: no download, no desktop churn.
out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$local_sha LANJUMP_ARCHIVE_URL="file:///dev/null" "$fakehome/.local/bin/lanjump" upgrade)
if [[ $out != *没有新版本* ]]; then
  fail "same version should skip: $out"
fi
if [[ $out != *$(print -r -- ${local_sha[1,7]})* ]]; then
  fail "skip message missing current version: $out"
fi

# #355: same remote SHA must still reinstall if a required file is missing.
# Official recovery is `lanjump upgrade`; a version-only skip leaves picker gone.
repairpkg=$(mktemp -d)
mkdir -p "$repairpkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$repairpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$repairpkg/lanjump-main/bin/"
cp "$ROOT/lib/"* "$repairpkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$repairpkg/lanjump-main/src/"
cp "$ROOT/install.zsh" "$repairpkg/lanjump-main/install.zsh"
print -r -- '# REPAIR-PICKER-355' >>"$repairpkg/lanjump-main/lib/lanjump-pick.zsh"
repairtar=$(mktemp)
tar -czf "$repairtar" -C "$repairpkg" lanjump-main
rm -f "$fakehome/Library/Application Support/lanjump/lanjump-pick.zsh"

st=0
out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$local_sha LANJUMP_ARCHIVE_URL="file://${repairtar}" "$fakehome/.local/bin/lanjump" upgrade) || st=$?
if [[ $out == *没有新版本* ]]; then
  fail "#355 same SHA with missing picker must not skip: $out"
fi
if (( st )); then
  fail "#355 repair upgrade failed ($st): $out"
fi
if [[ ! -f "$fakehome/Library/Application Support/lanjump/lanjump-pick.zsh" ]]; then
  fail "#355 upgrade did not restore missing picker"
fi
if ! grep -q 'REPAIR-PICKER-355' "$fakehome/Library/Application Support/lanjump/lanjump-pick.zsh"; then
  fail "#355 upgrade did not reinstall picker from archive"
fi

# After official Lanjump.command is gone, a user-copied lanjump.command with one
# extra env line must survive upgrade. Cannot coexist with Lanjump.command on
# a case-insensitive volume.
{
  print '#!/bin/zsh'
  print 'LANJUMP_NO_GROK_WRAP=1'
  tail -n +2 "$ROOT/bin/lanjump.command"
} >"$fakehome/Desktop/lanjump.command"
chmod 755 "$fakehome/Desktop/lanjump.command"

# Old GitHub payload: old CLI + an install.zsh that would drop Lanjump.command
# if we mistakenly ran it. Upgrade must use the saved installer instead.
oldpkg=$(mktemp -d)
mkdir -p "$oldpkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$oldpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$oldpkg/lanjump-main/bin/"
cp "$ROOT/lib/"* "$oldpkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$oldpkg/lanjump-main/src/"
cat >"$oldpkg/lanjump-main/bin/lanjump" <<'EOF'
#!/bin/zsh
set -u
APP="$HOME/Library/Application Support/lanjump"
exec /bin/zsh "$APP/lanjump.zsh" "$@"
EOF
cat >"$oldpkg/lanjump-main/install.zsh" <<'EOF'
#!/bin/zsh
print 'RAN-OLD-INSTALLER'
mkdir -p "$HOME/Desktop"
cp -f "${0:A:h}/bin/lanjump.command" "$HOME/Desktop/Lanjump.command"
exit 0
EOF
oldtar=$(mktemp)
tar -czf "$oldtar" -C "$oldpkg" lanjump-main
new_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$new_sha LANJUMP_ARCHIVE_URL="file://${oldtar}" "$fakehome/.local/bin/lanjump" upgrade)
if [[ $out == *RAN-OLD-INSTALLER* ]]; then
  fail "upgrade ran the tarball's old install.zsh"
fi
if [[ $out != *从\ ${local_sha[1,7]}\ 升级到\ aaaaaaa* ]]; then
  fail "missing from-to progress: $out"
fi
if [[ $out != *已从\ ${local_sha[1,7]}\ 升级到\ aaaaaaa* ]]; then
  fail "missing from-to result: $out"
fi
if has_desktop_name "$fakehome/Desktop" 'Lanjump.command' || has_desktop_name "$fakehome/Desktop" '启动 lanjump.command'; then
  fail "upgrade created a .command on desktop: $(desktop_names "$fakehome/Desktop")"
fi
if [[ ! -e "$fakehome/Desktop/启动 lanjump" ]]; then
  fail "alias missing after upgrade"
fi
if [[ ! -f "$fakehome/Desktop/my-custom-tool.command" ]]; then
  fail "upgrade deleted custom desktop script that only mentioned lanjump"
fi
if [[ ! -f "$fakehome/Desktop/lanjump.command" ]]; then
  fail "upgrade deleted user-copied lanjump.command with extra env line"
fi
n=0
for f in "$fakehome/Desktop/"*; do
  [[ ${f:t} == 启动\ lanjump* ]] && n=$(( n + 1 ))
done
if (( n != 1 )); then
  fail "expected 1 desktop item after upgrade, got $n: $(desktop_names "$fakehome/Desktop")"
fi
if ! grep -q 'INSTALLER=' "$fakehome/.local/bin/lanjump"; then
  fail "upgrade overwrote launcher and dropped upgrade"
fi

out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$new_sha LANJUMP_ARCHIVE_URL="file://${oldtar}" "$fakehome/.local/bin/lanjump" upgrade)
if [[ $out != *没有新版本* || $out != *aaaaaaa* ]]; then
  fail "second upgrade should be no-op: $out"
fi
if [[ $out == *RAN-OLD-INSTALLER* ]]; then
  fail "second upgrade ran old installer"
fi
if has_desktop_name "$fakehome/Desktop" 'Lanjump.command'; then
  fail "second upgrade created Lanjump.command"
fi

# #210: upgrade must overwrite the saved installer with the tarball's newer
# install.zsh. Today $SELF is already $APP/install.zsh, so the -ef self-skip
# keeps the first-install copy forever and later installer-added files never land.
newpkg=$(mktemp -d)
mkdir -p "$newpkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$newpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$newpkg/lanjump-main/bin/"
cp "$ROOT/lib/"* "$newpkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$newpkg/lanjump-main/src/"
{
  print '# FETCHED-INSTALLER-MARKER'
  cat "$ROOT/install.zsh"
} >"$newpkg/lanjump-main/install.zsh"
newtar=$(mktemp)
tar -czf "$newtar" -C "$newpkg" lanjump-main
newer_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$newer_sha LANJUMP_ARCHIVE_URL="file://${newtar}" "$fakehome/.local/bin/lanjump" upgrade)
if [[ $out != *从\ aaaaaaa\ 升级到\ bbbbbbb* ]]; then
  fail "newer-installer upgrade missing from-to progress: $out"
fi
if ! grep -q 'FETCHED-INSTALLER-MARKER' "$fakehome/Library/Application Support/lanjump/install.zsh"; then
  fail "upgrade kept first-install install.zsh; tarball installer was ignored"
fi

# #229: upgrade must download archive/<sha>.tar.gz, not heads/main.tar.gz.
# If those two requests diverge (CDN lag), version is new while files stay old
# and later upgrades keep saying 没有新版本.
sha229=dddddddddddddddddddddddddddddddddddddddd
curl_log=$(mktemp)
fakebin=$(mktemp -d)
mainpkg=$(mktemp -d)
shapkg=$(mktemp -d)
mkdir -p "$mainpkg/lanjump-main"/{bin,lib,src} "$shapkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$mainpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump.command" "$shapkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$mainpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$shapkg/lanjump-main/bin/"
cp "$ROOT/lib/"* "$mainpkg/lanjump-main/lib/"
cp "$ROOT/lib/"* "$shapkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$mainpkg/lanjump-main/src/"
cp "$ROOT/src/lanjump-keys.c" "$shapkg/lanjump-main/src/"
print -r -- '# HEADS-MAIN-TREE' >>"$mainpkg/lanjump-main/lib/lanjump.zsh"
print -r -- '# SHA-ARCHIVE-TREE' >>"$shapkg/lanjump-main/lib/lanjump.zsh"
maintar=$(mktemp)
shatar=$(mktemp)
tar -czf "$maintar" -C "$mainpkg" lanjump-main
tar -czf "$shatar" -C "$shapkg" lanjump-main
cat >"$fakebin/curl" <<EOF
#!/bin/zsh
url=\${@[-1]}
print -r -- "\$url" >>$(printf %q "$curl_log")
if [[ \$url == *"/archive/${sha229}.tar.gz" ]]; then
  cat $(printf %q "$shatar")
  exit 0
fi
if [[ \$url == *'/archive/refs/heads/main.tar.gz' ]]; then
  cat $(printf %q "$maintar")
  exit 0
fi
print -u2 "curl-stub unexpected url: \$url"
exit 1
EOF
chmod 755 "$fakebin/curl"

out=$(HOME=$fakehome PATH="$fakebin:$PATH" LANJUMP_REMOTE_SHA=$sha229 env -u LANJUMP_ARCHIVE_URL "$fakehome/.local/bin/lanjump" upgrade)
if [[ $out != *从\ bbbbbbb\ 升级到\ ddddddd* ]]; then
  fail "#229 upgrade missing from-to progress: $out"
fi
if ! grep -q "/archive/${sha229}.tar.gz" "$curl_log"; then
  fail "upgrade archive URL was not built from fetched sha: $(<"$curl_log")"
fi
if grep -q 'heads/main' "$curl_log"; then
  fail "upgrade still requested heads/main archive: $(<"$curl_log")"
fi
if ! grep -q 'SHA-ARCHIVE-TREE' "$fakehome/Library/Application Support/lanjump/lanjump.zsh"; then
  fail "upgrade did not install the sha tarball"
fi
if grep -q 'HEADS-MAIN-TREE' "$fakehome/Library/Application Support/lanjump/lanjump.zsh"; then
  fail "upgrade installed heads/main tree for a pinned sha"
fi

# #311: piped install records fetch_remote_ver sha but used to download
# heads/main.tar.gz. If those diverge, version is new while files stay old
# and later upgrades keep saying 没有新版本.
sha311=3113113113113113113113113113113113113113
curl_log311=$(mktemp)
fakebin311=$(mktemp -d)
mainpkg311=$(mktemp -d)
shapkg311=$(mktemp -d)
home311=$(mktemp -d)
mkdir -p "$home311/Desktop" "$home311/.ssh" "$home311/Library/Application Support"
mkdir -p "$mainpkg311/lanjump-main"/{bin,lib,src} "$shapkg311/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$mainpkg311/lanjump-main/bin/"
cp "$ROOT/bin/lanjump.command" "$shapkg311/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$mainpkg311/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$shapkg311/lanjump-main/bin/"
cp "$ROOT/lib/"* "$mainpkg311/lanjump-main/lib/"
cp "$ROOT/lib/"* "$shapkg311/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$mainpkg311/lanjump-main/src/"
cp "$ROOT/src/lanjump-keys.c" "$shapkg311/lanjump-main/src/"
cp "$ROOT/install.zsh" "$mainpkg311/lanjump-main/install.zsh"
cp "$ROOT/install.zsh" "$shapkg311/lanjump-main/install.zsh"
print -r -- '# HEADS-MAIN-TREE' >>"$mainpkg311/lanjump-main/lib/lanjump.zsh"
print -r -- '# SHA-ARCHIVE-TREE' >>"$shapkg311/lanjump-main/lib/lanjump.zsh"
maintar311=$(mktemp)
shatar311=$(mktemp)
tar -czf "$maintar311" -C "$mainpkg311" lanjump-main
tar -czf "$shatar311" -C "$shapkg311" lanjump-main
cat >"$fakebin311/curl" <<EOF
#!/bin/zsh
url=\${@[-1]}
print -r -- "\$url" >>$(printf %q "$curl_log311")
if [[ \$url == *"/archive/${sha311}.tar.gz" ]]; then
  cat $(printf %q "$shatar311")
  exit 0
fi
if [[ \$url == *'/archive/refs/heads/main.tar.gz' ]]; then
  cat $(printf %q "$maintar311")
  exit 0
fi
print -u2 "curl-stub unexpected url: \$url"
exit 1
EOF
chmod 755 "$fakebin311/curl"

HOME=$home311 PATH="$fakebin311:$PATH" LANJUMP_REMOTE_SHA=$sha311 env -u LANJUMP_ARCHIVE_URL /bin/zsh <"$ROOT/install.zsh" >/dev/null
if ! grep -q "/archive/${sha311}.tar.gz" "$curl_log311"; then
  fail "#311 piped install archive URL was not built from fetched sha: $(<"$curl_log311")"
fi
if grep -q 'heads/main' "$curl_log311"; then
  fail "#311 piped install still requested heads/main archive: $(<"$curl_log311")"
fi
if ! grep -q 'SHA-ARCHIVE-TREE' "$home311/Library/Application Support/lanjump/lanjump.zsh"; then
  fail "#311 piped install did not install the sha tarball"
fi
if grep -q 'HEADS-MAIN-TREE' "$home311/Library/Application Support/lanjump/lanjump.zsh"; then
  fail "#311 piped install installed heads/main tree for a pinned sha"
fi
ver311=$home311/Library/Application\ Support/lanjump/version
if [[ ! -f $ver311 ]]; then
  fail "#311 piped install wrote no version file"
elif [[ $(<$ver311) != "$sha311" ]]; then
  fail "#311 piped install version: $(<$ver311)"
fi

# #220: missing tarball file must not leave live APP as a mixed old/new tree.
appdir="$fakehome/Library/Application Support/lanjump"
print -r -- 'OLD-MAIN' >"$appdir/lanjump.zsh"
print -r -- 'OLD-PICK' >"$appdir/lanjump-pick.zsh"
badpkg=$(mktemp -d)
mkdir -p "$badpkg/lanjump-main"/{bin,lib,src}
print -r -- 'NEW-MAIN' >"$badpkg/lanjump-main/lib/lanjump.zsh"
cp "$ROOT/bin/lanjump.command" "$badpkg/lanjump-main/bin/"
cp "$ROOT/lib/lanjump-keys.py" "$badpkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$badpkg/lanjump-main/src/"
badtar=$(mktemp)
tar -czf "$badtar" -C "$badpkg" lanjump-main
fail_sha=cccccccccccccccccccccccccccccccccccccccc

out=$(HOME=$fakehome LANJUMP_REMOTE_SHA=$fail_sha LANJUMP_ARCHIVE_URL="file://${badtar}" "$fakehome/.local/bin/lanjump" upgrade 2>&1) || true
if [[ $(<"$appdir/lanjump.zsh") != OLD-MAIN ]]; then
  fail "failed upgrade left mixed lanjump.zsh: $(<"$appdir/lanjump.zsh")"
fi
if [[ $(<"$appdir/lanjump-pick.zsh") != OLD-PICK ]]; then
  fail "failed upgrade left mixed lanjump-pick.zsh: $(<"$appdir/lanjump-pick.zsh")"
fi

# #278: the live switch is now two directory mvs (APP→APP.old, then
# APP.new→APP). The inject must actually hit that commit — a file-level
# lanjump.new→lanjump stub stays silent and the upgrade just succeeds.
# Live $APP must stay all-old or become all-new, never mixed.
print -r -- 'OLD-MAIN' >"$appdir/lanjump.zsh"
print -r -- 'OLD-IME' >"$appdir/lanjump-ime.py"
print -r -- 'KEEP-SETTINGS' >"$appdir/settings"
cp -f "$ROOT/install.zsh" "$appdir/install.zsh"
chmod 755 "$appdir/install.zsh"

mixpkg=$(mktemp -d)
mkdir -p "$mixpkg/lanjump-main"/{bin,lib,src}
print -r -- 'NEW-MAIN' >"$mixpkg/lanjump-main/lib/lanjump.zsh"
print -r -- 'NEW-IME' >"$mixpkg/lanjump-main/lib/lanjump-ime.py"
cp "$ROOT/lib/lanjump-pick.zsh" "$mixpkg/lanjump-main/lib/"
cp "$ROOT/lib/lanjump-keys.py" "$mixpkg/lanjump-main/lib/"
cp "$ROOT/bin/lanjump.command" "$mixpkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$mixpkg/lanjump-main/bin/"
cp "$ROOT/src/lanjump-keys.c" "$mixpkg/lanjump-main/src/"
cp "$ROOT/install.zsh" "$mixpkg/lanjump-main/"
mixtar=$(mktemp)
tar -czf "$mixtar" -C "$mixpkg" lanjump-main

mvwrap=$(mktemp -d)
cat >"$mvwrap/mv" <<'EOF'
#!/bin/zsh
src= dest=
for a in "$@"; do
  [[ $a == -* ]] && continue
  src=$dest
  dest=$a
done
# Current commit is directory-level: APP→APP.old, then APP.new→APP.
# Fail the second rename so install.zsh must restore APP.old.
# A file-level ${src:h:t}==lanjump.new check never matches a directory source.
if [[ -n $src && -n $dest && -d $src && ${src:t} == lanjump.new && ${dest:t} == lanjump ]]; then
  print -u2 'mv-stub: mid-commit failure'
  exit 1
fi
exec /bin/mv "$@"
EOF
chmod 755 "$mvwrap/mv"

mix_sha=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
out=$(HOME=$fakehome PATH="$mvwrap:$PATH" LANJUMP_REMOTE_SHA=$mix_sha LANJUMP_ARCHIVE_URL="file://${mixtar}" "$fakehome/.local/bin/lanjump" upgrade 2>&1) || true
if [[ $out != *'mv-stub: mid-commit failure'* ]]; then
  fail "#278 directory-level commit was not interrupted: $out"
fi
main=$(<"$appdir/lanjump.zsh")
ime=$(<"$appdir/lanjump-ime.py")
if [[ $main == NEW-MAIN && $ime == OLD-IME ]] || [[ $main == OLD-MAIN && $ime == NEW-IME ]]; then
  fail "#278 mixed upgrade tree: lanjump.zsh=$main lanjump-ime.py=$ime"
fi
if [[ $main != NEW-MAIN && $main != OLD-MAIN ]]; then
  fail "#278 unexpected lanjump.zsh after interrupted commit: $main"
fi
if [[ $ime != NEW-IME && $ime != OLD-IME ]]; then
  fail "#278 unexpected lanjump-ime.py after interrupted commit: $ime"
fi
if [[ ! -f $appdir/settings || $(<"$appdir/settings") != KEEP-SETTINGS ]]; then
  fail "#278 commit dropped user settings"
fi

# #281: curl | zsh makes $0 /bin/zsh, so local_git_ver cannot see the repo.
# Piped install must still write the remote SHA so the first upgrade can skip.
pipe_sha=ffffffffffffffffffffffffffffffffffffffff
pipehome=$(mktemp -d)
mkdir -p "$pipehome/Desktop" "$pipehome/.ssh" "$pipehome/Library/Application Support"
pipepkg=$(mktemp -d)
mkdir -p "$pipepkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$pipepkg/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$pipepkg/lanjump-main/bin/"
cp "$ROOT/lib/"* "$pipepkg/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$pipepkg/lanjump-main/src/"
cp "$ROOT/install.zsh" "$pipepkg/lanjump-main/install.zsh"
pipetar=$(mktemp)
tar -czf "$pipetar" -C "$pipepkg" lanjump-main
HOME=$pipehome LANJUMP_REMOTE_SHA=$pipe_sha LANJUMP_ARCHIVE_URL="file://${pipetar}" /bin/zsh <"$ROOT/install.zsh" >/dev/null
pipe_ver=$pipehome/Library/Application\ Support/lanjump/version
if [[ ! -f $pipe_ver ]]; then
  fail "piped install wrote no version file"
elif [[ $(<$pipe_ver) != "$pipe_sha" ]]; then
  fail "piped install version: $(<$pipe_ver)"
fi
out=$(HOME=$pipehome LANJUMP_REMOTE_SHA=$pipe_sha LANJUMP_ARCHIVE_URL="file:///dev/null" "$pipehome/.local/bin/lanjump" upgrade)
if [[ $out != *没有新版本* ]]; then
  fail "piped install first upgrade should skip: $out"
fi

# #282: a commented PATH line must not count as already configured.
pathhome=$(mktemp -d)
mkdir -p "$pathhome/Desktop" "$pathhome/.ssh" "$pathhome/Library/Application Support"
print -r -- '# export PATH="$HOME/.local/bin:$PATH"' >"$pathhome/.zshrc"
HOME=$pathhome /bin/zsh "$ROOT/install.zsh" >/dev/null
if ! grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$pathhome/.zshrc"; then
  fail "#282 commented PATH line counted as configured: $(<"$pathhome/.zshrc")"
fi

# #283: cc failure must not install a python helper when python3 cannot run.
home283=$(mktemp -d)
mkdir -p "$home283/Desktop" "$home283/.ssh" "$home283/Library/Application Support"
bin283=$(mktemp -d)
cat >"$bin283/cc" <<'EOF'
#!/bin/zsh
print -u2 'cc stub: compile failed'
exit 1
EOF
cat >"$bin283/python3" <<'EOF'
#!/bin/zsh
print -u2 'python3 stub: cannot run'
exit 127
EOF
chmod 755 "$bin283/cc" "$bin283/python3"
st283=0
out283=$(HOME=$home283 PATH="$bin283:$PATH" /bin/zsh "$ROOT/install.zsh" 2>&1) || st283=$?
if (( st283 == 0 )); then
  fail "#283 install succeeded without a runnable python3 when cc failed: $out283"
fi
if [[ $out283 == *安装完成* ]]; then
  fail "#283 install reported success without python3: $out283"
fi
if [[ $out283 != *python3* ]]; then
  fail "#283 failure did not mention python3: $out283"
fi
app283="$home283/Library/Application Support/lanjump"
if [[ -x $app283/lanjump-keys || -x $home283/.local/bin/lanjump-keys ]]; then
  fail "#283 installed a fake helper without python3"
fi

# #306: SIGKILL/power-loss after APP→APP.old and before APP.new→APP leaves
# user data only in APP.old. The next install must restore that copy, not
# mkdir -p an empty APP and then rm -rf the only remaining tree.
home306=$(mktemp -d)
mkdir -p "$home306/Desktop" "$home306/.ssh" "$home306/Library/Application Support"
HOME=$home306 /bin/zsh "$ROOT/install.zsh" >/dev/null
app306="$home306/Library/Application Support/lanjump"
print -r -- 'KEEP-HOSTS' >"$app306/hosts"
print -r -- 'KEEP-SETTINGS' >"$app306/settings"
print -r -- 'KEEP-PINS' >"$app306/pinned-sessions"
print -r -- 'KEEP-SNAPSHOT' >"$app306/session-snapshot"
mv "$app306" "$app306.old"
HOME=$home306 /bin/zsh "$ROOT/install.zsh" >/dev/null
if [[ ! -d $app306 ]]; then
  fail "#306 reinstall left live APP missing after interrupted commit"
fi
if [[ ! -f $app306/hosts || $(<"$app306/hosts") != KEEP-HOSTS ]]; then
  fail "#306 reinstall wiped hosts after interrupted commit"
fi
if [[ ! -f $app306/settings || $(<"$app306/settings") != KEEP-SETTINGS ]]; then
  fail "#306 reinstall wiped settings after interrupted commit"
fi
if [[ ! -f $app306/pinned-sessions || $(<"$app306/pinned-sessions") != KEEP-PINS ]]; then
  fail "#306 reinstall wiped pins after interrupted commit"
fi
if [[ ! -f $app306/session-snapshot || $(<"$app306/session-snapshot") != KEEP-SNAPSHOT ]]; then
  fail "#306 reinstall wiped snapshot after interrupted commit"
fi

# #334: after APP→APP.old, a concurrent mkdir -p $APP (snapshot tick /
# replace_file_atomic) makes BSD mv nest APP.new as $APP/lanjump.new/.
# The switch must not delete APP.old unless $APP/lanjump.zsh is at the
# app root; otherwise roll back. Live keepers must survive either way.
home334=$(mktemp -d)
mkdir -p "$home334/Desktop" "$home334/.ssh" "$home334/Library/Application Support"
HOME=$home334 /bin/zsh "$ROOT/install.zsh" >/dev/null
app334="$home334/Library/Application Support/lanjump"
print -r -- 'KEEP-HOSTS' >"$app334/hosts"
print -r -- 'KEEP-SETTINGS' >"$app334/settings"
print -r -- 'KEEP-PINS' >"$app334/pinned-sessions"
mvwrap334=$(mktemp -d)
cat >"$mvwrap334/mv" <<'EOF'
#!/bin/zsh
src= dest=
for a in "$@"; do
  [[ $a == -* ]] && continue
  src=$dest
  dest=$a
done
# Recreate empty APP after the first rename, then let the second mv run.
if [[ -n $src && -n $dest && -d $src && ${src:t} == lanjump && ${dest:t} == lanjump.old ]]; then
  /bin/mv "$@"
  st=$?
  mkdir -p "$src"
  exit $st
fi
exec /bin/mv "$@"
EOF
chmod 755 "$mvwrap334/mv"
HOME=$home334 PATH="$mvwrap334:$PATH" /bin/zsh "$ROOT/install.zsh" >/dev/null 2>&1 || true
if [[ ! -f $app334/lanjump.zsh ]]; then
  fail "#334 switch left lanjump.zsh off the app root (nested or wiped)"
fi
if [[ -d $app334/lanjump.new ]]; then
  fail "#334 second mv nested APP.new under live APP"
fi
if [[ ! -f $app334/hosts || $(<"$app334/hosts") != KEEP-HOSTS ]]; then
  fail "#334 mkdir-during-switch dropped hosts"
fi
if [[ ! -f $app334/settings || $(<"$app334/settings") != KEEP-SETTINGS ]]; then
  fail "#334 mkdir-during-switch dropped settings"
fi
if [[ ! -f $app334/pinned-sessions || $(<"$app334/pinned-sessions") != KEEP-PINS ]]; then
  fail "#334 mkdir-during-switch dropped pins"
fi

# #335: keepers are copied into APP.new once, then the live tree is renamed
# away. A write that lands on $APP after that copy (hosts/settings change
# while upgrade is in the copy-to-stage window) must still be on the
# switched tree, not left behind on APP.old.
home335=$(mktemp -d)
mkdir -p "$home335/Desktop" "$home335/.ssh" "$home335/Library/Application Support"
HOME=$home335 /bin/zsh "$ROOT/install.zsh" >/dev/null
app335="$home335/Library/Application Support/lanjump"
print -r -- 'OLD-HOSTS' >"$app335/hosts"
print -r -- 'OLD-SETTINGS' >"$app335/settings"
cpwrap335=$(mktemp -d)
cat >"$cpwrap335/cp" <<'EOF'
#!/bin/zsh
src= dest=
for a in "$@"; do
  [[ $a == -* ]] && continue
  src=$dest
  dest=$a
done
# After each first-pass keeper copy into APP.new, change the live file so
# the staged tree is stale unless install recopies immediately before switch.
if [[ -n $src && -n $dest && ${src:h:t} == lanjump && ${dest:h:t} == lanjump.new ]]; then
  /bin/cp "$@"
  st=$?
  live=${src:h}
  case ${src:t} in
    hosts)
      print -r -- 'NEW-HOSTS' >"$live/hosts"
      ;;
    settings)
      print -r -- 'NEW-SETTINGS' >"$live/settings"
      ;;
  esac
  exit $st
fi
exec /bin/cp "$@"
EOF
chmod 755 "$cpwrap335/cp"
HOME=$home335 PATH="$cpwrap335:$PATH" /bin/zsh "$ROOT/install.zsh" >/dev/null
if [[ ! -f $app335/hosts || $(<"$app335/hosts") != NEW-HOSTS ]]; then
  fail "#335 upgrade kept stale hosts after a mid-copy write: $(<"$app335/hosts" 2>/dev/null || print missing)"
fi
if [[ ! -f $app335/settings || $(<"$app335/settings") != NEW-SETTINGS ]]; then
  fail "#335 upgrade kept stale settings after a mid-copy write: $(<"$app335/settings" 2>/dev/null || print missing)"
fi

# #358: #335 recopies keepers, then immediately mv APP→APP.old and
# APP.new→APP. A hosts/settings writer in that last window lands on the
# tree about to become APP.old and is deleted. Recopy+switch must be
# exclusive with data-file writers so the write is on the live tree.
home358=$(mktemp -d)
mkdir -p "$home358/Desktop" "$home358/.ssh" "$home358/Library/Application Support"
HOME=$home358 /bin/zsh "$ROOT/install.zsh" >/dev/null
app358="$home358/Library/Application Support/lanjump"
print -r -- 'OLD-HOSTS' >"$app358/hosts"
print -r -- 'OLD-SETTINGS' >"$app358/settings"
mark358=$(mktemp -d)
mvwrap358=$(mktemp -d)
cat >"$mvwrap358/mv" <<EOF
#!/bin/zsh
src= dest=
for a in "\$@"; do
  [[ \$a == -* ]] && continue
  src=\$dest
  dest=\$a
done
mark=$(printf %q "$mark358")
if [[ -n \$src && -n \$dest && -d \$src && \${src:t} == lanjump && \${dest:t} == lanjump.old ]]; then
  live=\$src
  (
    lock_write() {
      local dest=\$1 val=\$2 lock
      local -i fd=-1 n=0
      lock=\${dest}.lock
      [[ -e \$lock ]] || : >"\$lock"
      if zmodload zsh/system 2>/dev/null && zsystem supports flock; then
        zsystem flock -f fd "\$lock" || exit 1
        print -r -- "\$val" >"\$dest"
        zsystem flock -u fd
        return
      fi
      while ! mkdir "\${lock}.d" 2>/dev/null; do
        sleep 0.05
        (( ++n > 200 )) && exit 1
      done
      print -r -- "\$val" >"\$dest"
      rmdir "\${lock}.d" 2>/dev/null
    }
    lock_write "\$live/hosts" NEW-HOSTS
    lock_write "\$live/settings" NEW-SETTINGS
    : >"\$mark/wrote"
  ) &!
  for _ in {1..80}; do
    [[ -f \$mark/wrote ]] && break
    sleep 0.01
  done
  /bin/mv "\$@"
  exit \$?
fi
exec /bin/mv "\$@"
EOF
chmod 755 "$mvwrap358/mv"
HOME=$home358 PATH="$mvwrap358:$PATH" /bin/zsh "$ROOT/install.zsh" >/dev/null
for _ in {1..200}; do
  [[ -f $mark358/wrote ]] && break
  sleep 0.05
done
if [[ ! -f $app358/hosts || $(<"$app358/hosts") != NEW-HOSTS ]]; then
  fail "#358 switch discarded a hosts write after last recopy: $(<"$app358/hosts" 2>/dev/null || print missing)"
fi
if [[ ! -f $app358/settings || $(<"$app358/settings") != NEW-SETTINGS ]]; then
  fail "#358 switch discarded a settings write after last recopy: $(<"$app358/settings" 2>/dev/null || print missing)"
fi

# #338: piped/file:// tarball install has no git history in ROOT.
# fetch_remote_ver must surface the commit epoch to the parent so the
# picker gets `# lanjump-pick-version <epoch> <sha>`. Today that assignment
# dies in the $(...) subshell and the stamp is skipped.
home338=$(mktemp -d)
mkdir -p "$home338/Desktop" "$home338/.ssh" "$home338/Library/Application Support"
pkg338=$(mktemp -d)
mkdir -p "$pkg338/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$pkg338/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$pkg338/lanjump-main/bin/"
cp "$ROOT/lib/"* "$pkg338/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$pkg338/lanjump-main/src/"
cp "$ROOT/install.zsh" "$pkg338/lanjump-main/install.zsh"
tar338=$(mktemp)
tar -czf "$tar338" -C "$pkg338" lanjump-main
sha338=3383383383383383383383383383383383383383
api338=$(mktemp)
print -r -- '{"sha":"'"$sha338"'","commit":{"committer":{"date":"2026-09-17T00:00:00Z"}}}' >"$api338"
HOME=$home338 LANJUMP_VERSION_API="file://${api338}" LANJUMP_ARCHIVE_URL="file://${tar338}" env -u LANJUMP_REMOTE_SHA /bin/zsh <"$ROOT/install.zsh" >/dev/null
picker338="$home338/Library/Application Support/lanjump/lanjump-pick.zsh"
if [[ ! -f $picker338 ]]; then
  fail "#338 tarball install wrote no picker"
elif ! grep -qxF "# lanjump-pick-version 1789603200 $sha338" "$picker338"; then
  fail "#338 tarball install wrote no picker version stamp: $(head -n 3 "$picker338")"
fi

# #339: piped/fresh install pins archive/<api-sha>.tar.gz. If that URL 404s,
# install falls back to heads/main. It must not record the unused API sha as
# the installed version (or must fail cleanly). Empty-dir cleanup must not
# NOMATCH-abort before the fallback runs.
sha339=3393393393393393393393393393393393393393
home339=$(mktemp -d)
mkdir -p "$home339/Desktop" "$home339/.ssh" "$home339/Library/Application Support"
pkg339=$(mktemp -d)
mkdir -p "$pkg339/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$pkg339/lanjump-main/bin/"
cp "$ROOT/bin/lanjump-ghostty-attach" "$pkg339/lanjump-main/bin/"
cp "$ROOT/lib/"* "$pkg339/lanjump-main/lib/"
cp "$ROOT/src/lanjump-keys.c" "$pkg339/lanjump-main/src/"
cp "$ROOT/install.zsh" "$pkg339/lanjump-main/install.zsh"
print -r -- '# HEADS-MAIN-TREE' >>"$pkg339/lanjump-main/lib/lanjump.zsh"
tar339=$(mktemp)
tar -czf "$tar339" -C "$pkg339" lanjump-main
api339=$(mktemp)
print -r -- '{"sha":"'"$sha339"'","commit":{"committer":{"date":"2026-09-17T00:00:00Z"}}}' >"$api339"
curl_log339=$(mktemp)
fakebin339=$(mktemp -d)
cat >"$fakebin339/curl" <<EOF
#!/bin/zsh
url=\${@[-1]}
print -r -- "\$url" >>$(printf %q "$curl_log339")
if [[ \$url == $(printf %q "file://${api339}") ]]; then
  cat $(printf %q "$api339")
  exit 0
fi
if [[ \$url == *"/archive/${sha339}.tar.gz" ]]; then
  exit 22
fi
if [[ \$url == *'/archive/refs/heads/main.tar.gz' ]]; then
  cat $(printf %q "$tar339")
  exit 0
fi
print -u2 "curl-stub unexpected url: \$url"
exit 1
EOF
chmod 755 "$fakebin339/curl"

st339=0
out339=$(HOME=$home339 PATH="$fakebin339:$PATH" LANJUMP_VERSION_API="file://${api339}" env -u LANJUMP_REMOTE_SHA env -u LANJUMP_ARCHIVE_URL /bin/zsh <"$ROOT/install.zsh" 2>&1) || st339=$?
ver339=$home339/Library/Application\ Support/lanjump/version
picker339=$home339/Library/Application\ Support/lanjump/lanjump-pick.zsh
main339=$home339/Library/Application\ Support/lanjump/lanjump.zsh
if ! grep -q 'heads/main' "$curl_log339"; then
  fail "#339 sha 404 did not fall back to heads/main: $(<"$curl_log339") status=$st339 out=$out339"
fi
if [[ -f $ver339 && $(<$ver339) == "$sha339" ]]; then
  fail "#339 fallback recorded unused API sha as version"
fi
if [[ -f $picker339 ]] && grep -q "$sha339" "$picker339"; then
  fail "#339 fallback stamped unused API sha on picker: $(head -n 3 "$picker339")"
fi
if (( st339 == 0 )); then
  if [[ ! -f $main339 ]] || ! grep -q 'HEADS-MAIN-TREE' "$main339"; then
    fail "#339 fallback install did not land heads/main tree"
  fi
  out=$(HOME=$home339 LANJUMP_REMOTE_SHA=$sha339 LANJUMP_ARCHIVE_URL="file:///dev/null" "$home339/.local/bin/lanjump" upgrade 2>&1) || true
  if [[ $out == *没有新版本* ]]; then
    fail "#339 next upgrade skipped as if unused sha was installed: $out"
  fi
fi

rm -rf "$fakehome" "$oldpkg" "$oldtar" "$newpkg" "$newtar" "$badpkg" "$badtar" "$fakebin" "$mainpkg" "$shapkg" "$maintar" "$shatar" "$curl_log" "$repairpkg" "$repairtar" "$home311" "$fakebin311" "$mainpkg311" "$shapkg311" "$maintar311" "$shatar311" "$curl_log311" "$mixpkg" "$mixtar" "$mvwrap" "$pipehome" "$pipepkg" "$pipetar" "$pathhome" "$home283" "$bin283" "$home306" "$home334" "$mvwrap334" "$home335" "$cpwrap335" "$home358" "$mvwrap358" "$mark358" "$home338" "$pkg338" "$tar338" "$api338" "$home339" "$pkg339" "$tar339" "$api339" "$curl_log339" "$fakebin339"

if (( fails )); then
  exit 1
fi
print 'upgrade-selftest ok'
