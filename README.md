# lanjump

macOS 局域网 SSH 启动器：扫描网上的机器、记住免密登录，再选 tmux session。

首次安装（任意 Mac）：

```zsh
curl -fsSL https://raw.githubusercontent.com/jattchen/lanjump/main/install.zsh | zsh
```

已经装过的，终端输入：

```zsh
lanjump upgrade
```

没有新版本会直接告诉你。有的话会显示从哪个版本升到哪个。

装完重新开一次 `lanjump`，或双击桌面上的 **启动 lanjump**。

第一次连接某台机器时输入 SSH 用户名。若需要密码，只用来安装公钥，不会保存。

本机装了 Grok 时，连远程会走 `grok wrap`，方便把对面 Grok 的选中复制写进这台电脑的剪贴板（自带「终端」需要这一层）。不是两台电脑剪贴板互相同步。不想用时：`LANJUMP_NO_GROK_WRAP=1 lanjump`。

连同一台机器时会复用已经打开的 SSH，避免每一步都重新握手。不想复用时：`LANJUMP_NO_SSH_MUX=1 lanjump`。

在你敲键盘的那台 Mac 上安装后，Shift+Enter 会换成 Grok 能认的换行（系统「终端」本身分不出 Shift+Enter）。打开 tmux 列表时也会加上这条换行，并把底部 session 名字显示加长，不需要你自己改 Ghostty 或 tmux 配置。不记录按键，只看回车时 Shift 有没有按住。

## 快捷键

主机列表：`↑` `↓` / `j` 上 `k` 下 选择，`Enter` 连接（或进入本机），`r` 扫描，`d` 忘掉，`e` 给已保存的机器改名，`i` 开关打开时切英文输入法，`q` 退出。

tmux 列表：`↑` `↓` / `j` 上 `k` 下 选择，`Enter` 当前窗口进入，`t` 新窗口进入，`n` 新建，`e` 重命名，`d` 删除，`p` 常驻，`X` 删空闲，`h` 换机器，`o` 时间/占用/常驻，`v` 开关预览，`/` 包含，`!` 排除，`f` 开关上次筛选，`,` 设置，`s` 普通 shell（`exit` 返回），`q` 退出。开不了外部窗口时（SSH / 没有本机键盘）Enter 和 `t` 都在当前窗口进入，不提示。Shift+Enter 仍是 Grok 换行，不开新窗口。预览默认关闭；`v` 打开或关上后会记住，下次打开列表保持上次的状态。

重启电脑或 `tmux kill-server` 之后再打开 tmux 列表：若还有没建出来的常驻 session，先整屏显示恢复进度，完成后再进入列表，顶上留「已恢复 N 个」。只把 pin 建回 tmux，回到记下的目录。不开窗口，也不询问。没标 pin 的 session 不重建。命令行 `list` / `go` 仍静默恢复。纯数字名只有按 `p` 时先改成 `s-` 加时间戳并写成 pin 才会回来。

从列表 Enter 进入：窗格保持原样，不把已退出的 Grok 再拉起来。窗格里 Grok 还在跑则跳到那一格。`,` 打开设置：新窗口用 Ghostty 还是系统终端，新开窗口还是在已有窗口加标签，以及多个项目根（顺序即优先级；Enter 添加，d 删除）。

命令：

| 写法 | 作用 |
|---|---|
| `lanjump` | 主机列表 |
| `lanjump <机器>` | 那台的 session 列表 |
| `lanjump help` | 查看说明 |
| `lanjump [<机器>] go [名字]` | 进入 session，没有就建。不写名字则按当前目录新建 |
| `lanjump go demo -g` | 进入并续上 Grok |
| `lanjump <机器> go -G` | 在那台另开一个全新 Grok |
| `lanjump [<机器>] list` | 列出 session |
| `lanjump [<机器>] last [N]` | 最近的 session 里选一个进入 |
| `lanjump [<机器>] pin` | 已常驻的 session 里选一个进入 |
| `lanjump [<机器>] on` | 那台占用中的 session |
| `lanjump upgrade` | 升级到最新版本 |
| `lanjump update` | 同 `upgrade` |

机器写在最前面。省略则是本机，写 `local` 也是本机。`lanjump 别名` 进那台的 tmux 列表。常驻在列表里按 p。

上次连的是本机还是远程，下次打开主机会记住并跳过扫描（只影响列表，不影响省略机器名的命令）。

## 要求

macOS；对方打开远程登录。tmux 可选。连远程且要把 Grok 选中复制写到本机时，这台电脑需要有 `grok`。Shift+Enter 换行要装在敲键盘的那台 Mac 上。
