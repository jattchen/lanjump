# lanjump

macOS LAN SSH launcher: discover machines on the local network, remember them with key-based login, then pick a tmux session from a terminal UI.

Run `lanjump` in a terminal, or double-click the Desktop shortcut. First run scans the LAN (Bonjour `_ssh._tcp` plus TCP/22). After you choose a host and install a dedicated key once, later launches open the saved list and connect without a password. If you last chose **进入本机**, the next launch skips the scan and opens the host list with the cursor on this Mac. From the tmux picker, `h` returns to the host list; `q` quits. From a plain shell, `exit` or Ctrl+D returns to the tmux list.

## Features

- LAN discovery (mDNS SSH services + port 22)
- Merges dual-NIC hosts that share an SSH host key
- One LAN SSH key (`~/.ssh/id_ed25519_lanjump`); login password is never stored
- Saved hosts with last-used first
- Interactive tmux session list, preview, create/delete, attach
- Local entry from the host list: skip SSH and open this Mac's tmux picker
- Last-used this Mac skips the next LAN scan and leaves the cursor on 进入本机
- `h` returns to the host picker (remote SSH disconnects; remote sessions stay running)

## Install (macOS)

From this repo:

```zsh
zsh install.zsh
```

That copies:

- `lib/lanjump.zsh` and `lib/lanjump-pick.zsh` → `~/Library/Application Support/lanjump/`
- `bin/lanjump` → `~/.local/bin/lanjump`
- `bin/lanjump.command` → `~/Desktop/Lanjump.command`

Then in any terminal:

```zsh
lanjump
```

Or double-click **Lanjump.command** on the Desktop. The filename is ASCII-only so Ghostty can open it (Ghostty 1.3.1 corrupts Chinese `.command` names and exits immediately).

A previous `lan-ssh` install is migrated: saved hosts, last-used target, and the LAN key move over; old Desktop shortcuts and the old Application Support folder are removed.

## Usage

| Host list | Action |
|---|---|
| `↑` `↓` / `j` `k` | Move |
| `Enter` | Connect to a host, or open this Mac |
| `r` | Rescan LAN |
| `d` | Forget a saved host (local record only) |
| `q` | Quit |

Choose **进入本机** to skip SSH and open the same tmux picker on this Mac. The next launch remembers whether you last used this Mac or a remote host, and skips the LAN scan in either case.

| tmux list | Action |
|---|---|
| `Enter` | Attach session |
| `n` | New session |
| `d` | Kill session (confirms) |
| `h` | Back to host list |
| `s` | Plain shell (no tmux); `exit` or Ctrl+D returns to this list |
| `q` | Quit |

On first connect to a new host, type the SSH username (nothing is prefilled). If no existing key works, you will be asked for the login password once to install the LAN public key.

## Layout

```
lib/lanjump.zsh       Host picker, scan, key setup
lib/lanjump-pick.zsh  Remote tmux session UI
bin/lanjump           Terminal command
bin/lanjump.command   Desktop double-click launcher
install.zsh           Install to Application Support, PATH, and Desktop
```

Saved host metadata lives in `~/Library/Application Support/lanjump/hosts` (not committed). Last-used target (this Mac vs a remote host) is `last_target` in the same folder. SSH config blocks are tagged `# BEGIN LANJUMP …` in `~/.ssh/config`.

## Requirements

- macOS (uses `dns-sd`, `nc`, Keychain `ssh-add --apple-use-keychain`)
- Remote: SSH (Remote Login) enabled; tmux optional (falls back to a plain shell)
