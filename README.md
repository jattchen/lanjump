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

在你敲键盘的那台 Mac 上安装后，Shift+Enter 会换成 Grok 能认的换行（系统「终端」本身分不出 Shift+Enter）。打开 tmux 列表时也会加上这条换行，并把底部 session 名字显示加长，不需要你自己改 Ghostty 或 tmux 配置。不记录按键，只看回车时 Shift 有没有按住。

## 快捷键

主机列表：`↑` `↓` / `j` 上 `k` 下 选择，`Enter` 连接（或进入本机），`r` 扫描，`d` 忘掉，`i` 开关打开时切英文输入法，`q` 退出。

tmux 列表：`↑` `↓` / `j` 上 `k` 下 选择，`Enter` 进入，`n` 新建，`e` 重命名，`d` 删除，`p` 常驻，`X` 删空闲，`h` 换机器，`o` 时间/占用/常驻，`v` 开关预览，`/` 包含，`!` 排除，`f` 开关上次筛选，`,` 设置，`s` 普通 shell（`exit` 返回），`q` 退出。

重启电脑或 `tmux kill-server` 之后再打开 tmux 列表：会重建常驻、以及改过名/进过的命名 session（回到当时目录；纯数字名不重建）。然后弹出勾选列表：默认打开「常驻」和「最近 48 小时占用过」的窗口（空格或鼠标勾选，Enter 打开并续上，`2` 只要空 shell，`q` 不打开）。超过 48 小时且非常驻的命名 session 只建在 tmux 里，不自动开窗。没有 Ghostty 时用「终端」标签。

从列表 Enter 进入空 shell、且上次能续时，会再问要不要续上。窗格里已经有程序在跑则直接进去。有 Ghostty 时 Enter 会用 Ghostty 打开并退出列表；没有则在当前窗口进入。`,` 打开设置：用 Ghostty / 系统终端 / 当前窗口，以及新开窗口还是在已有窗口加标签。

命令：`lanjump help` 查看说明；`lanjump list [机器]` 列出 session；`lanjump last [机器]` 显示最近进入的 session；`lanjump update` 同 `upgrade`；`lanjump go [机器:]名字` 打开最近或指定 session（默认有 Ghostty 用 Ghostty，没有则当前窗口进入；已打开则跳到那个窗口）；`lanjump new [名字] --grok` 在当前窗口新建 session 并启动 grok（名字可省；有名字时按现有项目目录匹配，没有则用敲命令时的当前目录）；`lanjump work` 打开工作区；`lanjump pins` 打开常驻。默认机器是上次进的那台。名字不存在会问要不要新建。

上次连的是本机还是远程，下次打开会记住并跳过扫描。

## 要求

macOS；对方打开远程登录。tmux 可选。连远程且要把 Grok 选中复制写到本机时，这台电脑需要有 `grok`。Shift+Enter 换行要装在敲键盘的那台 Mac 上。
