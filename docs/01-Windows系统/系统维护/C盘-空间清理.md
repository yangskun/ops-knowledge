---
日期: 2026-08-20
tags: [windows, 系统维护, 磁盘清理, 脚本]
适用环境: 个人设备(生产环境需评估角色依赖)
风险等级: 中
权限要求: 管理员(部分步骤)
---

# C 盘空间清理 SOP

## 结论先行

按"先看去向 → 系统工具清理 → 专项清理 → 大文件定位"四层推进。收益最高的是:**Windows.old 升级残留(10~30GB)、休眠文件 hiberfil.sys(≈内存 40~75%)、DISM 组件清理、更新缓存**。全部操作可逆(除 DISM `/ResetBase` 与 `/h off` 需评估),高危项已标注。

## 现象

- 系统盘变红,提示"磁盘空间不足"
- C 盘可用空间 < 10%,程序报错、系统卡顿、更新失败

## 原因推测

| 占用来源 | 典型大小 | 说明 |
|---|---|---|
| Windows.old | 10~30 GB | 大版本升级残留,30 天后自动清,可手动删 |
| hiberfil.sys | 内存的 40~75% | 休眠文件,默认隐藏 |
| WinSxS 组件库 | 5~15 GB | **不可手动删**,只能用 DISM 清理 |
| 更新缓存 | 1~5 GB | `SoftwareDistribution\Download` |
| 用户缓存/临时文件 | 1~10 GB | 浏览器、AppData、%TEMP% |
| 虚拟内存 pagefile | 1~8 GB | 可移至其他盘,不建议关闭 |
| 回收站 | 不定 | 常被忽略 |

## 分步操作

### 第 1 步:先看空间去向(2 分钟,低风险)

```powershell
# 管理员 PowerShell:扫描 C 盘前 20 大文件(排除系统目录噪音)
Get-ChildItem C:\ -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Length -gt 100MB } |
  Sort-Object Length -Descending |
  Select-Object -First 20 @{n='大小MB';e={[math]::Round($_.Length/1MB)}}, FullName |
  Format-Table -AutoSize
```

> 💡 更直观:用 WizTree / SpaceSniffer 图形化查看(个人设备推荐 WizTree,秒级扫描)。

### 第 2 步:系统自带清理(低风险,先做这个)

**1. 存储感知(自动)**

```powershell
# 打开存储感知设置
start ms-settings:storagesense
```

开启"自动清理临时文件",手动点"立即清理"。

**2. 磁盘清理(含系统文件,重点勾选)**

```cmd
:: 管理员 CMD;先跑普通清理,再点"清理系统文件"重复一次
cleanmgr /d C:

:: 一键启动"清理系统文件"模式(手动勾选)
cleanmgr /sageset:1 & cleanmgr /sagerun:1
```

必勾项:**Windows 更新清理、以前的 Windows 安装(Windows.old)、传递优化文件、临时文件、缩略图、回收站**。

### 第 3 步:专项清理(中风险,收益大)

**1. 更新缓存(安全,服务会自动重建)**

```cmd
:: 管理员 CMD;停止服务 → 删缓存 → 重启服务
net stop wuauserv
net stop bits
del /f /s /q C:\Windows\SoftwareDistribution\Download\*.*
del /f /s /q C:\Windows\Temp\*.*
net start bits
net start wuauserv
```

**2. DISM 组件清理(⚠️ `/ResetBase` 不可逆)**

```cmd
:: 管理员 CMD;先做保守清理,空间仍不足再考虑 ResetBase
dism /Online /Cleanup-Image /StartComponentCleanup
dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase
```

> `/ResetBase` 会固化当前组件、清理旧版本,**之后无法卸载已装更新**。个人设备可接受,生产环境先评估。

**3. 休眠文件(⚠️ 影响休眠与快速启动)**

```cmd
:: 管理员 CMD;关闭休眠 = 删除 hiberfil.sys,释放 ≈40~75% 内存大小
powercfg /h off

:: 恢复:powercfg /h on
```

> 代价:失去"休眠"功能,"快速启动"失效(开机变慢几秒)。台式机/常驻机器可接受,笔记本注意。

**4. 虚拟内存(可选,不建议关闭)**

```cmd
:: 管理员 CMD;查看当前设置
wmic pagefile list /format:list
```

建议:保留系统管理,或把 pagefile 移到 D 盘(系统属性 → 高级 → 性能设置 → 高级 → 虚拟内存)。**不要设为"无分页文件"**,易蓝屏(0x0000007E 等)。

### 第 4 步:用户目录大文件定位(中风险,需人工判断)

```powershell
# 管理员 PowerShell:扫用户目录大文件(含隐藏 AppData)
Get-ChildItem "$env:USERPROFILE" -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Length -gt 200MB } |
  Sort-Object Length -Descending |
  Select-Object -First 30 @{n='大小MB';e={[math]::Round($_.Length/1MB)}}, FullName |
  Format-Table -AutoSize
```

清理建议(人工确认后删):

| 路径 | 内容 | 处理 |
|---|---|---|
| `AppData\Local\Temp` | 用户临时文件 | 全删 |
| `AppData\Local\Microsoft\Windows\INetCache` | 浏览器缓存 | 可删 |
| `AppData\Local\Google\Chrome\User Data\*\Cache` | Chrome 缓存 | 可删 |
| `AppData\Local\NVIDIA\DXCache` 等 | 着色器缓存 | 可删 |
| `Downloads` | 下载目录 | 人工筛选 |
| 微信/QQ 文件目录 | 聊天文件 | 设置里迁移/清理 |

⚠️ **不要动** `AppData\Local\Microsoft\WindowsApps`、`AppData\Roaming` 下不认识的应用数据。

## 验证方法

```powershell
# 清理前后对比
Get-PSDrive C | Select-Object @{n='可用GB';e={[math]::Round($_.Free/1GB,2)}}
```

- 目标:可用空间释放 5GB 以上(有 Windows.old 时可达 20GB+)
- 系统稳定性验证:重启一次,确认无报错、应用正常启动

## 注意事项 / 踩坑记录

- **WinSxS 禁止手动删除**(`C:\Windows\WinSxS`),会破坏系统组件,只能用 DISM
- `Windows.old` 删除窗口:升级后 30 天内可手动删,超期系统自动清;删了无法回退系统版本
- 清理前**务必先看第 1 步的大文件扫描结果**,对症下药,避免白忙
- 生产服务器:先确认角色依赖(如 SQL Server 的 tempdb、IIS 日志、AD 数据库),**禁止**直接 `del` 系统目录,用厂商工具或维护窗口操作
- 固态硬盘(SSD):不建议频繁大文件删除/碎片整理,影响寿命;空间不足优先考虑换盘/迁移,而非极限清理
- 清理完成建议创建还原点(操作多时),异常可回滚

## 关联文档

- [Windows 更新:禁用与恢复](Windows更新-禁用与恢复.md)(更新缓存清理共用第 3 步)
- 待积累:存储NAS/存储空间管理
