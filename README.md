# lanjump

macOS 局域网 SSH 启动器：扫描网上的机器、记住免密登录，再选 tmux session。

```zsh
git clone https://github.com/jattchen/lanjump.git
cd lanjump
zsh install.zsh
```

之后在终端运行 `lanjump`，或双击桌面上的 **Lanjump.command**。

第一次连接某台机器时输入 SSH 用户名。若需要密码，只用来安装公钥，不会保存。

## 快捷键

主机列表：`↑` `↓` / `j` `k` 选择，`Enter` 连接（或进入本机），`r` 扫描，`d` 忘掉，`q` 退出。

tmux 列表：`Enter` 进入，`n` 新建，`d` 删除，`h` 换机器，`s` 普通 shell（`exit` 返回），`q` 退出。

上次连的是本机还是远程，下次打开会记住并跳过扫描。

## 要求

macOS；对方打开远程登录。tmux 可选。
