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

rm -rf "$fakehome" "$oldpkg" "$oldtar" "$newpkg" "$newtar" "$badpkg" "$badtar" "$fakebin" "$mainpkg" "$shapkg" "$maintar" "$shatar" "$curl_log"

if (( fails )); then
  exit 1
fi
print 'upgrade-selftest ok'
