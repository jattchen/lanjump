## 改动

## 手测基准

性能 PR 在描述里贴前后数字。下面两条不进 CI，会用本机配置，交互那条还会碰本机正在跑的 tmux。

在仓库根目录，伪终端里启动列表后立刻按 `q`，看从启动到退出的时间：

```zsh
python3 - <<'PY'
import os, pty, time
t0 = time.monotonic()
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/zsh", ["/bin/zsh", "lib/lanjump.zsh"])
os.write(fd, b"q")
_, status = os.waitpid(pid, 0)
print(f"list-quit {time.monotonic() - t0:.3f}s exit {os.waitstatus_to_exitcode(status)}")
PY
```

再量命令行列出 session 的时间：

```zsh
time zsh lib/lanjump.zsh list
```

自动化回归（含语法检查、八套 selftest，以及真实 `~/.ssh` 与 `~/Library/Application Support/lanjump` 前后比对）：

```zsh
zsh install.zsh --selftest
```
