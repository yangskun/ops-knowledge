---
日期: 2026-08-20
tags: [windows, 故障排查, 蓝屏, 驱动, 内存]
适用环境: 个人设备 / 生产环境(需先确认维护窗口)
风险等级: 低(分析为主,部分操作需重启)
权限要求: 管理员(配置 dump、读 dump)
---

# 蓝屏(BSOD)分析 SOP

## 结论先行

蓝屏排查三分法:**先确保能抓到 dump 文件 → 读 bugcheck 代码定方向 → 用 WinDbg 定位故障模块**。驱动问题是第一大类(约 70%),其次是内存、硬盘等硬件。不要靠"闪一下的蓝屏代码"猜,必须分析 minidump 才靠谱。

## 现象

- 蓝屏一闪而过自动重启,看不到错误代码
- 蓝屏后循环重启、卡在转圈、进桌面后再次蓝屏
- 特定操作触发(游戏/睡眠唤醒/插拔外设)或随机蓝屏

## 原因推测(按概率排序)

| 类别 | 典型代码 | 说明 |
|---|---|---|
| 驱动(最常见) | `0xD1` `0x3B` `0x50` `0x116` `0x9F` | 显卡/网卡/主板/外设驱动冲突或损坏 |
| 内存 | `0x1A` `0x50` `0x7E` | 内存条故障、超频不稳、插槽接触不良 |
| CPU/主板/电源 | `0x124` `0x101` | 硬件错误(WHEA)、供电不足、过热 |
| 硬盘/阵列 | `0x7B` `0x133` | 启动设备不可访问、SSD 固件/掉盘 |
| 系统损坏 | `0xEF` `0xC2` | 关键系统文件损坏、更新失败 |

## 分步操作

### 第 1 步:配置蓝屏转储,确保能抓到 dump(预防)

```powershell
# 管理员 PowerShell:关闭"蓝屏自动重启"(否则一闪而过看不到)
# 0=不自动重启(蓝屏停留等待),1=自动重启
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "AutoReboot" -Value 0

# 确认小内存转储已启用(1=启用,目录默认 C:\Windows\Minidump)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "CrashDumpEnabled" -Value 1
```

> ⚠️ 前提:**虚拟内存必须设为"系统管理"或分页文件 ≥ 2GB**,否则无法生成 dump。
> 图形界面:系统属性 → 高级 → 启动和故障恢复 → 取消勾选"自动重新启动",写入调试信息选"小内存转储(256KB)"。

### 第 2 步:确认是否产生 dump 文件

```powershell
# 查看蓝屏 dump 列表(按时间排序)
Get-ChildItem C:\Windows\Minidump\*.dmp -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object LastWriteTime, Length, FullName

# 事件查看器确认蓝屏记录(Event ID 1001 = BugCheck)
Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001} -MaxEvents 5 |
  Select-Object TimeCreated, @{n='信息';e={$_.Message.Substring(0, [Math]::Min(200, $_.Message.Length))}}
```

- 有 `.dmp` → 进入第 4 步分析
- **没有 dump** → 先排查:分页文件是否够、CrashDumpEnabled 是否开启、是否磁盘空间不足;同时查 `Event ID 41`(Kernel-Power,意外断电/电源问题,不是蓝屏)与 `Event ID 1001` 区分

### 第 3 步:读蓝屏代码,缩小范围(1 分钟)

蓝屏停留时记录:`STOP: 0x000000D1 (参数…)` 与底部 `xxx.sys`。

| 代码 | 含义 | 优先排查方向 |
|---|---|---|
| `0x7B` | 启动设备不可访问 | 硬盘/阵列卡/启动驱动(SATA/NVMe 模式) |
| `0x7E` | 系统线程异常 | 驱动、内存 |
| `0x50` | 非分页区页错误 | 内存、驱动 |
| `0x3B` | 系统服务异常 | 驱动(常为显卡/网卡) |
| `0xD1` | 驱动 IRQL 访问错误 | 驱动(网卡/声卡/外设) |
| `0x9F` | 电源状态驱动失败 | 睡眠/唤醒相关驱动 |
| `0x124` | WHEA 硬件错误 | CPU/内存/电源/主板,查事件日志 WHEA-Logger |
| `0x101` | 时钟看门狗超时 | CPU(超频/过热/供电) |
| `0x116` | 显卡 TDR 超时 | 显卡驱动/硬件 |
| `0x1A` | 内存管理错误 | 内存条(优先 MemTest) |
| `0xEF` | 关键进程死亡 | 系统损坏/杀软误杀 |
| `0x133` | DPC 看门狗 | SSD 固件/驱动/存储 |

### 第 4 步:WinDbg 分析 minidump(核心,定位故障模块)

```cmd
:: 管理员 CMD;使用 WinDbg(Windows SDK 或 Microsoft Store 版)
:: 打开 WinDbg → File → Open Crash Dump → 选 C:\Windows\Minidump\ 最新 .dmp
:: 命令行模式:
windbg -z C:\Windows\Minidump\xxxxx.dmp -c "!analyze -v; q"
```

分析输出重点读三处:

1. **`BUGCHECK_CODE`** —— 蓝屏代码
2. **`PROCESS_NAME`** —— 触发进程(如 `nvcontainer.exe` 指向显卡)
3. **`MODULE_NAME` / `IMAGE_NAME`** —— **故障驱动文件**(如 `dxgkrnl.sys`=显卡、`e1i65x64.sys`=Intel 网卡、`ntoskrnl.exe`=内核层,需再查)

> 💡 不想装 WinDbg:用 **BlueScreenView**(NirSoft 免费工具)快速看故障驱动名,适合现场快速定位;WinDbg 输出更权威。

### 第 5 步:针对故障模块处理

**驱动类(多数情况)**

```powershell
# 查驱动文件归属(以某驱动为例)
driverquery /v | findstr /i "xxx.sys"
```

- 故障驱动是**第三方**(非微软):官网下载最新版覆盖安装;或用"设备管理器 → 回退驱动程序"
- 故障驱动是**微软自带**但指向硬件:查对应硬件(显卡/网卡/SSD 固件)
- 最近装了软件/驱动后开始蓝屏 → 优先**系统还原**到蓝屏前

**内存类**

```cmd
:: 快速内存测试(不够全面,只作初筛;全盘用 MemTest86 启动盘跑 4 轮以上)
mdsched.exe
```

- MemTest86 报错 → 单条内存逐个测,清理金手指/换插槽;超频的先恢复默认

**硬件类(0x124 等)**

```powershell
# 查 WHEA 硬件错误日志
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 10 |
  Select-Object TimeCreated, Id, LevelDisplayName
```

- 检查:CPU 温度/散热器、电源功率是否足够、主板供电;BIOS 更新
- 硬盘类(`0x7B`):进 BIOS 确认启动盘识别、SATA/NVMe 模式(ACHI vs RAID)、阵列卡状态

**系统损坏类**

```cmd
:: 管理员 CMD;系统文件检查 + 组件修复(先 SFC 后 DISM,顺序别反)
sfc /scannow
dism /Online /Cleanup-Image /RestoreHealth
```

## 验证方法

```powershell
# 确认无新蓝屏记录(记录数不再增长)
(Get-WinEvent -FilterHashtable @{LogName='System'; Id=1001} -ErrorAction SilentlyContinue).Count

# 正常重启进入系统,连续运行 24~72 小时无蓝屏
```

- 修复后**再触发一次原操作**(如睡眠唤醒/游戏),确认复现路径已通
- 记录修复前后的 dump 时间戳,确认不再新增

## 注意事项 / 踩坑记录

- **先关"自动重新启动"再等下次蓝屏**:不然永远看不到代码,只能等 dump
- **Event ID 41 ≠ 蓝屏**:Kernel-Power 41 是意外断电/强制关机,常见于电源、过热、插排,别当蓝屏查
- **`ntoskrnl.exe` 是"背锅侠"**:蓝屏代码指向它 ≠ 系统问题,要看 `!analyze -v` 里 `IMAGE_NAME` 指向的具体驱动
- **WinDbg 第一次打开很慢**:要下载符号文件,耐心等;离线环境可 `!sym noisy` 后手动加载
- **驱动"更新"未必解决问题**:官网驱动 > 驱动精灵类工具;新版驱动也可能引入新问题,必要时**回退**而非升级
- **内存测试别用 Windows 自带当结论**:`mdsched.exe` 只测基础,MemTest86(启动盘)跑 4 轮(约 4~6 小时)才算可靠
- **生产环境**:蓝屏频繁先切备用机/迁移业务,分析放维护窗口;禁止在业务机直接跑 MemTest 重启
- **0x124 与超频强相关**:恢复 BIOS 默认(XMP/EXPO 关闭)先排除

## 关联文档

- [C 盘空间清理 SOP](../系统维护/C盘-空间清理.md)(dump 生成依赖分页文件空间)
- [RAID 故障灯码解读](../../05-服务器/硬件与RAID/RAID灯码-解读.md)(服务器蓝屏转硬件排查)
