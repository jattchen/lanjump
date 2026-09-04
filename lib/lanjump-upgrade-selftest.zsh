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

fakehome=$(mktemp -d)
mkdir -p "$fakehome/Desktop" "$fakehome/.ssh" "$fakehome/Library/Application Support"
cp "$ROOT/bin/lanjump.command" "$fakehome/Desktop/启动 xx.command"
chmod 755 "$fakehome/Desktop/启动 xx.command"
print old >"$fakehome/Desktop/Lanjump.command"
HOME=$fakehome /bin/zsh "$ROOT/install.zsh" >/dev/null

if [[ -e "$fakehome/Desktop/启动 xx.command" || -e "$fakehome/Desktop/Lanjump.command" || -e "$fakehome/Desktop/启动 lanjump.command" ]]; then
  fail "old desktop scripts still present: $(desktop_names "$fakehome/Desktop")"
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

# Old GitHub payload: old CLI + an install.zsh that would drop Lanjump.command
# if we mistakenly ran it. Upgrade must use the saved installer instead.
oldpkg=$(mktemp -d)
mkdir -p "$oldpkg/lanjump-main"/{bin,lib,src}
cp "$ROOT/bin/lanjump.command" "$oldpkg/lanjump-main/bin/"
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
if [[ -e "$fakehome/Desktop/Lanjump.command" || -e "$fakehome/Desktop/启动 lanjump.command" ]]; then
  fail "upgrade created a .command on desktop: $(desktop_names "$fakehome/Desktop")"
fi
if [[ ! -e "$fakehome/Desktop/启动 lanjump" ]]; then
  fail "alias missing after upgrade"
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
if [[ -e "$fakehome/Desktop/Lanjump.command" ]]; then
  fail "second upgrade created Lanjump.command"
fi

rm -rf "$fakehome" "$oldpkg" "$oldtar"

if (( fails )); then
  exit 1
fi
print 'upgrade-selftest ok'
