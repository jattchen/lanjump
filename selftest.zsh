#!/bin/zsh
# Run every repo selftest, then show each suite's wall time.
# Entry: zsh install.zsh --selftest
#
# Eight suites. Issue #461 named seven entry points and did not mention
# lib/lanjump-keys-selftest.zsh; that file is the same kind of regression
# (C helper and Python fallback) and runs here too.
#
# Not in this branch yet, so those issues can add their own assertions:
#   #463 / #464 tmux call budgets inside pick-selftest
#   #466 dns-sd early-stop inside host-selftest
emulate zsh
setopt no_unset pipefail
zmodload zsh/datetime

ROOT=${0:A:h}
typeset -a SUITES
SUITES=(digit host ssh ime cli pick keys upgrade)

fingerprint_roots() {
  python3 - "$HOME" <<'PY'
import hashlib, os, stat, sys

home = sys.argv[1]
if not home:
    print("fingerprint: empty HOME", file=sys.stderr)
    raise SystemExit(1)

roots = (
    ("ssh", os.path.join(home, ".ssh")),
    ("lanjump", os.path.join(home, "Library", "Application Support", "lanjump")),
)

def fail(path, err):
    print(f"fingerprint unreadable: {path}: {err}", file=sys.stderr)
    raise SystemExit(1)

def digest(root):
    if not os.path.lexists(root):
        return "ABSENT"
    h = hashlib.sha256()

    def add(path, rel):
        try:
            st = os.lstat(path)
        except OSError as err:
            fail(path, err.strerror)
        mode = f"{st.st_mode:o}"
        if stat.S_ISLNK(st.st_mode):
            try:
                target = os.readlink(path)
            except OSError as err:
                fail(path, err.strerror)
            h.update(f"L\0{rel}\0{mode}\0{target}\n".encode())
            return
        if stat.S_ISDIR(st.st_mode):
            h.update(f"D\0{rel}\0{mode}\n".encode())
            try:
                names = sorted(os.listdir(path))
            except OSError as err:
                fail(path, err.strerror)
            for name in names:
                child = name if rel == "" else rel + "/" + name
                add(os.path.join(path, name), child)
            return
        if stat.S_ISREG(st.st_mode):
            fh = hashlib.sha256()
            try:
                with open(path, "rb") as handle:
                    for chunk in iter(lambda: handle.read(1 << 20), b""):
                        fh.update(chunk)
            except OSError as err:
                fail(path, err.strerror)
            h.update(f"F\0{rel}\0{mode}\0{fh.hexdigest()}\n".encode())
            return
        h.update(f"O\0{rel}\0{mode}\n".encode())

    add(root, "")
    return h.hexdigest()

for name, path in roots:
    print(f"{name} {digest(path)}")
PY
}

if [[ ${1:-} == --fingerprint ]]; then
  if [[ $# -ne 1 ]]; then
    print -u2 "usage: zsh selftest.zsh --fingerprint"
    exit 2
  fi
  fingerprint_roots
  exit $?
fi

if [[ $# -ne 0 ]]; then
  print -u2 "usage: zsh install.zsh --selftest"
  exit 2
fi

main() {
  local before after name file t0 t1 st label secs
  local -i failed=0 syntax_st=0
  local -a zsh_files
  local -A suite_status suite_secs

  before=$(fingerprint_roots) || {
    print -u2 "FAIL real-config fingerprint"
    exit 1
  }
  local -a before_lines
  before_lines=("${(f)before}")
  if (( ${#before_lines} != 2 )); then
    print -u2 "FAIL real-config fingerprint shape"
    exit 1
  fi

  t0=$EPOCHREALTIME
  # zsh scalars cannot hold NUL, so the list is newline-delimited.
  local raw_files
  raw_files=$(find "$ROOT" -type f -name '*.zsh' | LC_ALL=C sort) || syntax_st=1
  if [[ -n $raw_files ]]; then
    zsh_files=("${(f)raw_files}")
  fi
  if (( syntax_st == 0 && ${#zsh_files} == 0 )); then
    print -u2 "FAIL syntax: no .zsh files under $ROOT"
    syntax_st=1
  else
    for file in "${zsh_files[@]}"; do
      if ! /bin/zsh -n "$file"; then
        print -u2 "FAIL syntax: $file"
        syntax_st=1
      fi
    done
  fi
  t1=$EPOCHREALTIME
  suite_secs[syntax]=$(( t1 - t0 ))
  suite_status[syntax]=$syntax_st

  if (( syntax_st )); then
    for name in "${SUITES[@]}"; do
      suite_status[$name]=-1
      suite_secs[$name]=0
    done
  else
    for name in "${SUITES[@]}"; do
      print -u2 -- "==> $name"
      t0=$EPOCHREALTIME
      st=0
      case $name in
        digit) /bin/zsh "$ROOT/lib/lanjump.zsh" --digit-selftest || st=$? ;;
        host) /bin/zsh "$ROOT/lib/lanjump.zsh" --host-selftest || st=$? ;;
        ssh) /bin/zsh "$ROOT/lib/lanjump.zsh" --ssh-selftest || st=$? ;;
        ime) /bin/zsh "$ROOT/lib/lanjump.zsh" --ime-selftest || st=$? ;;
        cli) /bin/zsh "$ROOT/lib/lanjump-cli-selftest.zsh" || st=$? ;;
        pick) /bin/zsh "$ROOT/lib/lanjump-pick.zsh" --pick-selftest || st=$? ;;
        keys) /bin/zsh "$ROOT/lib/lanjump-keys-selftest.zsh" || st=$? ;;
        upgrade) /bin/zsh "$ROOT/lib/lanjump-upgrade-selftest.zsh" || st=$? ;;
      esac
      t1=$EPOCHREALTIME
      suite_status[$name]=$st
      suite_secs[$name]=$(( t1 - t0 ))
    done
  fi

  after=$(fingerprint_roots) || {
    print -u2 "FAIL real-config fingerprint"
    exit 1
  }
  local -i config_st=0
  if [[ $before != "$after" ]]; then
    config_st=1
    print -u2 "FAIL real-config ~/.ssh or ~/Library/Application Support/lanjump changed"
    print -u2 "before:"
    print -u2 -- "$before"
    print -u2 "after:"
    print -u2 -- "$after"
  fi

  print "selftest timings:"
  for name in syntax "${SUITES[@]}"; do
    secs=$suite_secs[$name]
    st=$suite_status[$name]
    if (( st == 0 )); then
      label=ok
    elif (( st < 0 )); then
      label=skip
    else
      label=FAIL
      failed+=1
    fi
    LC_ALL=C printf '  %-12s %-6s %8.3fs\n' "$name" "$label" "$secs"
  done
  if (( config_st )); then
    print "  real-config  FAIL"
    failed+=1
  else
    print "  real-config  ok"
  fi
  if (( failed )); then
    print "selftest: $failed failed"
    exit 1
  fi
  print "selftest ok"
}

main
