---
日期: 2026-08-20
tags: [网络, 排错, vlan, ac-ap, 无线, 交换机]
适用环境: 办公/园区网络(生产环境,操作交换机前确认影响面)
风险等级: 中(交换机配置变更可能影响整网,先备份配置)
权限要求: 设备管理员(交换机/AC 控制台)
---

# AC+AP 与 VLAN 网络排错 SOP

## 结论先行

网络问题先**分域**:终端 → AP(无线) → 交换机(有线/VLAN) → AC/网关,用 ping 逐跳定位到"断在哪一跳",再针对性查 VLAN 配置或无线参数。⚠️ 改交换机/AC 配置前**先备份配置**,trunk/PVID 类变更可能瞬间影响整网。

## 现象

- 部分终端上网慢/不通,但交换机指示灯正常
- VLAN 划分后,跨 VLAN 互访失败、或同一 VLAN 内不通
- AP 掉线、AC 控制台 AP 离线、漫游时掉线重连
- 信号满格但网速差、2.4G/5G 频段异常
- 终端获取不到 IP / 拿到错误网段 IP

## 原因推测(分层定位)

| 层 | 常见原因 |
|---|---|
| 物理 | 网线/水晶头、**POE 供电不足**(AP 反复重启)、AP 安装位置 |
| 链路(VLAN) | 端口模式错误(access/trunk)、**PVID/允许列表不一致**、tag 配置错误 |
| 网络 | DHCP 冲突/地址池耗尽、网关/路由缺失(跨 VLAN) |
| 无线 | 信道干扰、漫游阈值(RSSI)不当、AP 管理通道异常 |
| 应用/认证 | 802.1X/Portal 认证、MAC 过滤、DHCP snooping 误拦 |

## 分步操作

### 第 1 步:逐跳定位断点(2 分钟)

```bash
# 终端侧:先确认自己拿到 IP 与网关
ipconfig /all            # Windows 看 IPv4 地址、网关、DNS

# 逐跳 ping:网关 → AC/AP 管理地址 → 外网,断在哪一跳问题就在哪段
ping 192.168.1.1         # 网关
ping 192.168.1.250       # AP/AC 管理地址
ping 8.8.8.8             # 外网
tracert -d 8.8.8.8       # 看路径在哪一跳超时
```

| ping 结果 | 故障段 | 排查方向 |
|---|---|---|
| 网关通、外网不通 | 上联/出口 | 路由、出口设备、NAT |
| 网关不通 | 接入层 | DHCP/VLAN/端口 |
| 无线通、有线通、仅部分终端 | 终端或认证 | 终端配置、认证策略 |

### 第 2 步:VLAN 排查(有线侧,核心)

```bash
# 登录交换机(华为/H3C 语法,思科为 show 系列)
display vlan                    # 查看全部 VLAN 及端口成员
display port vlan               # 端口 VLAN 模式/类型(access/trunk)
display interface brief         # 端口状态与速率

# 关键:查终端 MAC 在哪个端口、哪个 VLAN
display mac-address | include 88-66-5a-xx-xx-xx   # 终端 MAC
# 思科:show mac address-table | include xxxx.xxxx.xxxx
```

**VLAN 三大经典配置错误**:

| 错误 | 现象 | 修复 |
|---|---|---|
| trunk 端口**忘加 tag**(allow 列表缺 VLAN) | 该 VLAN 终端全不通 | `port trunk allow-pass vlan 10 20` |
| **PVID 不一致**(两端 trunk 默认 VLAN 不同) | 无标签帧走错 VLAN | 两端 PVID 统一(如 `port trunk pvid vlan 1`) |
| access 端口配错 VLAN | 单终端进错网段/不通 | `port link-type access; port default vlan 10` |

```bash
# 修复示例(华为):接入端口划分到 VLAN 10
interface GigabitEthernet0/0/1
 port link-type access
 port default vlan 10

# trunk 示例(上联口):放行 10/20 两个业务 VLAN
interface GigabitEthernet0/0/24
 port link-type trunk
 port trunk allow-pass vlan 10 20
```

> ⚠️ 改端口前 `display current-configuration` 备份;跨 VLAN 互访需三层(网关/VLANIF + 路由),纯二层交换机做不到。

### 第 3 步:无线侧排查(AC+AP)

```bash
# AC 上确认 AP 在线状态
display ap all                  # 看 AP 状态:Idle(离线)/Run(正常)
display ap run-info             # 信号强度、信道、功率
# 思科 WLC:show ap inventory;show ap summary
```

**AP 离线排查顺序**:
1. POE 供电:AP 反复重启 = 供电不足(换 POE+ 口/供电模块)
2. 网线/交换机端口:`display interface` 看协商速率(应 1000M)
3. AC 与 AP 间管理通道:VLAN/三层可达性
4. AP 版本与 AC 不匹配 → 升级/降级 AP 版本

**漫游掉线/粘滞(信号满但体验差)**:

```bash
# 调整漫游阈值(AC 上,RSSI 阈值过低=终端不主动切换)
# 华为:WLAN 模板下
display wlan client rssi       # 看终端信号
# 常见值:漫游触发阈值 -75dBm,弱信号剔除 -80dBm
```

- **信道规划**:相邻 AP 用不重叠信道(2.4G 用 1/6/11,5G 错开),避免同信道自干扰
- **2.4G vs 5G**:信号满但慢多为 2.4G 干扰,优先连 5G(可关 2.4G 低速率)
- **漫游粘滞**:阈值调高(-70dBm)促使终端切换

### 第 4 步:DHCP 与终端侧

```bash
# 交换机查 DHCP 租约/统计
display dhcp server statistics
display dhcp server conflict    # 地址冲突

# 终端拿到错误网段:查是否接了多个 DHCP(路由器/AC/交换机都开了 DHCP)
```

- IP 冲突 → `display dhcp server conflict` 定位,重启终端/释放租约
- 地址池耗尽 → 扩容地址池或调整租期
- **多个 DHCP 源**(光猫、路由器、AP 网关都在发地址)→ 只保留一个,其余关闭

## 验证方法

```bash
# 1. 终端侧:拿到正确网段 IP、网关、DNS
ipconfig /all

# 2. 连通性:目标业务 ping 通,延迟稳定
ping -t 192.168.10.100         # Windows 持续 ping,观察有无丢包

# 3. 交换机侧:终端 MAC 出现在正确端口+正确 VLAN
display mac-address | include <终端MAC>

# 4. 无线:AC 上 AP 全 Run,终端关联正常
display ap all
```

## 注意事项 / 踩坑记录

- **改配置先备份**:`display current-configuration` 导出,回滚有据
- **trunk 两端都要放行**,只配一端 = 单通或全断;PVID 两端必须一致
- **VLAN 隔离 ≠ 无法互访**:要互访就配 VLANIF + 路由,别用"全部划到 VLAN1"解决(失去隔离意义)
- **AP 管理 VLAN 与业务 VLAN 分离**:管理 VLAN 不通会导致 AP 反复重启/离线,但业务 VLAN 看起来正常
- **POE 供电不足是 AP 问题的第一嫌疑**:AP 指示灯规律闪 + 反复重启,先查供电再查配置
- **"信号满但慢"别只调功率**:多数是信道干扰或回程瓶颈(AP 上联口 100M/半双工)
- 漫游问题先确认**所有 AP 同一 SSID/同一加密方式**,SSID 不一致必然掉线重连
- 生产网络变更选**低峰期**,变更后 30 分钟内盯 `display logbuffer` 有无异常

## 关联文档

- 待积累:AC+AP 组网与漫游配置
- 待积累:无线漫游问题(本文第 3 步展开)
