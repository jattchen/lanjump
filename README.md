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

主机列表：`↑` `↓` / `j` `k` 选择，`Enter` 连接（或进入本机），`r` 扫描，`d` 忘掉，`q` 退出。

tmux 列表：`Enter` 进入，`n` 新建，`e` 重命名，`d` 删除，`h` 换机器，`s` 普通 shell（`exit` 返回），`q` 退出。

上次连的是本机还是远程，下次打开会记住并跳过扫描。

## 要求

macOS；对方打开远程登录。tmux 可选。连远程且要把 Grok 选中复制写到本机时，这台电脑需要有 `grok`。Shift+Enter 换行要装在敲键盘的那台 Mac 上。
