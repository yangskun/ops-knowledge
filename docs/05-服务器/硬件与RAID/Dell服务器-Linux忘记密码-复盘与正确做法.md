---
日期: 2026-09-01
标签: [服务器, RAID, Linux, 排错]
适用环境: 生产环境
风险等级: 高
权限要求: root
---

# Dell服务器-Linux忘记密码误操作致重装-复盘

> 本文既是本次 Dell 服务器事故的复盘记录，也是"Linux 忘记 root 密码"的正确处置 SOP。核心教训：**本可 5 分钟解决的问题，因改错对象系统 + 误执行 `touch /.autorelabel` / `fsck -y`，升级为文件系统元数据彻底损坏、必须重装。**

## 结论先行

- **故障**：Dell 服务器（AliOS 7，RAID 启动 + PXE 网启并存）忘记 root 密码
- **原因**：① 改密码改错了系统（GRUB 显示 2.6.32/aliOS6，实际运行 3.10.0/aliOS7）；② 单用户模式下执行 `touch /.autorelabel` 触发全盘 SELinux 重标记，海量 I/O 压垮原本脆弱的 ext4 元数据；③ 随后在已损坏文件系统上跑 `fsck -y`，写坏备份超级块，不可逆
- **解法**：走 chroot 改 shadow 一步到位；禁用 `/.autorelabel` 和盲目 `fsck -y`

## 现象

- 修改 iDRAC 带外 IP 后，系统出现 `megaraid_sas` 相关 Kernel Panic（`bad_area_nosemaphore` / `do_page_fault`，出现在 `complete_cmd_fusion` / `megasas_isr_fusion`）
- 重启能进 `login:` 但密码不对
- 进单用户时卡在 ALICLONE（阿里装机）PXE 界面，抓不到 GRUB
- 后续报错：`EXT4-fs (sda2): group descriptors corrupted!` / `bad superblock on /dev/sda2` / Kernel panic `Attempted to kill init!`

## 原因推测（分层定位）

| 层级 | 原因 | 依据 |
|------|------|------|
| 硬件/存储 | RAID 卡（PERC H730）或磁盘底层 I/O 异常 | `megaraid_sas` 驱动崩溃、superblock 损坏 |
| 系统（根因） | 文件系统元数据被破坏 | `touch /.autorelabel` 全盘重标记海量写入压垮 ext4 |
| 系统（加重） | 盲目 `fsck -y` 写坏备份超级块 | `group descriptors corrupted`、`bad superblock` |
| 引导 | PXE 网启优先 + 双系统混淆 | 抓不到 GRUB；GRUB 0.97 只显 2.6.32 但实际跑 3.10.0 |

**根因定性**：本次事故不是 RAID 卡硬件坏了（后来正常启动过），而是**软件操作失误叠加**导致。

## 分步操作

### 正确做法：Linux 忘记 root 密码（本应 5 分钟解决）

> ⚠️ 风险等级：中。全程只读挂载 + 改 shadow，**不要**触发全盘重标记，**不要**盲目 fsck。

```bash
# 1. 进 GRUB，选目标系统内核，按 e 编辑，kernel 行尾加：
rw init=/bin/bash
# 按 Ctrl+X（GRUB2）或 b（GRUB 0.97）启动

# 2. 挂载真实根分区（先 df / fdisk -l / lvs 确认它在哪）
mkdir -p /mnt/sys
mount /dev/sda2 /mnt/sys

# 3. chroot 进入目标系统（务必改对系统！）
chroot /mnt/sys /bin/bash
# 注意：接下来所有 passwd 都在 chroot 环境里执行

# 4. 设置新密码（交互式，不要写成 passwd 后跟密码，避免"Unknown user"）
passwd root

# 5. 【看清执行方式】：SELinux 重标记 vs 不改
#    - 如果系统本来就正常启动、只是忘记密码 → 通常不用重标记
#    - 如果必须 → touch /.autorelabel 只在【文件系统健康】时用！
touch /.autorelabel

# 6. 退出 chroot 重启
exit
reboot -f
```

### 不要这样做（本次踩坑的"禁止清单"）

| 危险操作 | 后果 |
|---------|------|
| `touch /.autorelabel` 在文件系统已受损时执行 | 全盘 SELinux 重标记 → 海量 I/O → 压垮元数据 |
| 在 ext4 元数据已损坏时执行 `fsck -y` | 强制修复会**写坏备份超级块**，不可逆 |
| `exec /sbin/init` 在 chroot / 跨 init 版本下执行 | SysVinit 环境拉起 systemd 失败，系统行为不可预测 |
| `passwd 密码`（把密码当用户名） | 报 `passwd: Unknown user name 'xxx'` |
| 不核对内核就改密码 | 改到 GRUB 里的旧内核（2.6.32），实际系统跑的是 3.10.0 |

### 正确的 fsck 姿势（如果非 fscK 不可）

```bash
# 先用 dumpe2fs 找备份超级块，不要直接 fsck -y
dumpe2fs /dev/sda2 2>/dev/null | grep -i superblock
# 例：Superblock backups stored on blocks: 32768, 98304, ...

# 用备用超级块修复（替换成实际块号）
fsck.ext4 -b 32768 -y /dev/sda2
```

### 若已无法引导（重装前置）

1. 确认启动顺序：F11 Boot Manager 指定硬盘启动，或 BIOS 把 PXE 移后
2. 若 PXE 网启优先 → 先确认引导架构（是否无盘/网络引导），别贸然改硬盘
3. 重装时 **Use All Space 可能清空数据盘** → 必须勾选 **Review and modify partitioning layout** 手动指定只装系统盘

## 验证方法

```bash
# 改完后能正常登录
# 检查文件系统是否健康
dmesg | grep -iE "error|corrupt"
# RAID 卡日志：iDRAC → System Event Log 看是否有 Degraded / Predictive Failure
```

## 注意事项 / 踩坑记录（用户实操复盘）

1. **没有核对系统内核**——后来才知道进入的系统是网络启动的，不是 RAID 装的系统
2. **启动顺序没有确认**——PXE 网启优先，反复卡在 ALICLONE 装机界面
3. **不知道 `touch /.autorelabel` 的危害**——导致知道问题后也无法进入真正系统
4. **不清楚操作的危害**——每个命令在已受损系统上的破坏性
5. **不知道操作有什么用**——盲目执行，缺少"这条命令会做什么"的判断
6. **重装在另外一台网络启动的机器上**（详见后续补充）

**关键禁止**：文件系统已不稳定时，任何全盘写入（重标记、fsck -y、大文件复制）都可能压垮它。**先只读挂载评估，再决定是否写入。**

## 关联文档

- [DELL-BIOS配置RAID-图文教程](DELL-BIOS配置RAID-图文教程.md)
- [RAID灯码-解读](RAID灯码-解读.md)
- Hermes Skill `raid-troubleshooting`（RAID 阵列故障排查 SOP）
