---
日期: 2026-08-21
tags: [linux, centos, ubuntu, 运维, 命令, systemd]
适用环境: 生产环境
风险等级: 中
权限要求: root（标注处）
---

# Linux 服务器基础运维速查

## 结论先行

本文汇总 Linux（CentOS / Ubuntu / 银河麒麟）服务器日常运维的核心操作：**systemd 服务管理、日志排查、用户权限、软件源、磁盘与进程管理**。所有命令按"操作 → 命令 → 参数注释"组织，可直接复制执行。覆盖面试与日常排障的高频场景。

## 现象 / 适用场景

- 服务器服务异常（起不来/自动退出/端口不通）
- 系统日志排查（应用报错、内核信息）
- 用户权限管理（新建账号、sudo 授权）
- 软件安装与源配置（含离线安装）
- 磁盘空间不足、进程异常占用

## 分步操作

### 第 1 步:systemd 服务管理（CentOS 7+ / Ubuntu 16.04+ / 麒麟）

```bash
# 查看服务状态(含运行状态、最近日志、PID)
systemctl status nginx

# 启动/停止/重启(需 root)
sudo systemctl start nginx        # 启动
sudo systemctl stop nginx         # 停止
sudo systemctl restart nginx      # 重启(改配置后常用)
sudo systemctl reload nginx       # 热加载配置(不中断服务, 支持时优先用)

# 开机自启管理
sudo systemctl enable nginx       # 设置开机自启
sudo systemctl disable nginx      # 取消开机自启
systemctl is-enabled nginx        # 查看是否自启(enabled/disabled)

# 服务挂了自动拉起(改 service 文件后)
sudo systemctl edit nginx         # 打开覆盖片段, 添加 Restart=always 后保存
```

**踩坑**:服务启动失败先看 `systemctl status` 输出的最后几行，别急着看 journal；`Restart=always` 要写在 `[Service]` 段，改完 `systemctl daemon-reload` 才生效。

### 第 2 步:日志排查（journalctl + 传统日志）

```bash
# 查看某服务全部日志(实时跟踪用 -f)
sudo journalctl -u nginx --since "1 hour ago"   # 最近1小时
sudo journalctl -u nginx -f                     # 实时跟踪(排障时挂着看)
sudo journalctl -u nginx -p err                 # 只看错误级(err 及以上)

# 内核日志(硬件/驱动问题必看)
dmesg | tail -50                  # 最近内核消息
journalctl -k --since "10 min ago" # 内核日志(带时间)

# 传统日志位置(老习惯, 部分服务仍写这里)
tail -100 /var/log/messages       # CentOS 通用
tail -100 /var/log/syslog         # Ubuntu
tail -100 /var/log/nginx/error.log # 应用日志
```

**踩坑**:journald 日志默认有大小上限（`/etc/systemd/journald.conf` 的 `SystemMaxUse`，默认可能只有几十 MB），生产环境建议调大，否则排查时日志已被覆盖。

### 第 3 步:用户与权限

```bash
# 新建用户并设密码(需 root)
sudo useradd -m -s /bin/bash zhangsan   # -m 建家目录, -s 指定shell
sudo passwd zhangsan                    # 设置密码

# sudo 授权:把用户加进 wheel 组(CentOS)或 sudo 组(Ubuntu)
sudo usermod -aG wheel zhangsan         # CentOS
sudo usermod -aG sudo zhangsan          # Ubuntu/麒麟

# 验证
sudo -l -U zhangsan                     # 查看该用户 sudo 权限

# 修改属主/属组
sudo chown -R zhangsan:zhangsan /data/app   # -R 递归
```

**踩坑**:加组后用户需**重新登录**才生效；`chown -R` 用在 `/` 或系统目录上会破坏系统权限，务必限定路径。

### 第 4 步:软件源与安装（含离线）

```bash
# CentOS / 麒麟
sudo yum install -y htop             # 在线安装(-y 免确认)
sudo yum search 关键字
sudo yum list installed | grep nginx  # 确认已装

# Ubuntu
sudo apt update && sudo apt install -y htop

# 离线安装(内网服务器常用)
# 有网机器下载 rpm/deb 包, 拷贝到目标机
sudo yum install -y ./xxx.rpm        # CentOS 本地 rpm
sudo apt install -y ./xxx.deb        # Ubuntu 本地 deb
```

**踩坑**:离线装 rpm 遇到依赖缺失用 `sudo yum localinstall` 或 `rpm -Uvh --nodeps`（后者慎用，会绕过依赖检查导致运行时报错）。

### 第 5 步:磁盘与进程

```bash
# 磁盘空间
df -h                               # 各分区使用率(重点看 / 和 /var)
du -sh /var/log/* | sort -rh | head -10   # 找出大文件/大目录

# 进程管理
ps aux | grep java                  # 查进程(PID、CPU/内存)
top -c                              # 实时监控(按P按CPU, 按M按内存)
kill -9 <PID>                       # 强杀(先kill <PID> 优雅退出, 不行再-9)

# 端口占用
ss -tlnp | grep :80                 # 查80端口被谁占用(ss 替代 netstat)
lsof -i :3306                       # 按端口查进程
```

**踩坑**:`kill -9` 是最后手段（数据库/中间件强杀可能丢数据或损坏），先试 `kill`（SIGTERM）；`df` 显示 100% 但 `du` 找不到大文件时，多半是**已删除但被进程占用的文件**——`lsof | grep deleted` 定位。

## 验证方法

```bash
# 服务是否正常(返回 active (running) 即正常)
systemctl is-active nginx

# 端口是否监听(有 LISTEN 行即正常)
ss -tln | grep :80

# 用户能否正常登录与提权
su - zhangsan && sudo whoami        # 输出 root 即 sudo 配置正确

# 磁盘告警是否解除
df -h | awk '$5 ~ /%$/ && $5+0 > 85 {print}'
```

## 注意事项 / 踩坑记录

- **命令版本差异**:CentOS 7+ 用 `systemctl`/`ss`；老系统(CentOS 6)用 `service`/`netstat`。面试常问新旧命令差异
- **sudo 与 root 区分**:日常操作用 sudo 而非直接 root 登录；改系统级配置（/etc 下）务必先备份
- **生产环境操作**：改配置前备份原文件（`cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak-日期`），重启服务前先 `nginx -t` 类语法检查
- **日志先于重启**：服务挂了先看日志找原因，别盲目 restart（重启后日志丢失现场）
- 本文为通用速查，CentOS/Ubuntu/麒麟具体版本差异以实际系统为准

## 关联文档

- [银河麒麟 + 鲲鹏(ARM)适配要点](../银河麒麟/银河麒麟-鲲鹏适配.md)
- 待积累:Linux 网络排查（连通性/路由/抓包）
- 待积累:LVM 逻辑卷管理
