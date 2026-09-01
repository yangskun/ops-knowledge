---
日期: 2026-08-20
tags: [ai, tokenhub, 大模型, 免费额度, 配置, hermes]
适用环境: 个人设备
风险等级: 低（仅 API Key 与配置文件操作，无破坏性动作）
权限要求: 无（普通用户）
---

# TokenHub 免费额度与 Hermes 辅助模型配置

## 结论先行

腾讯云 TokenHub（`tokenhub.tencentmaas.com`）的免费体验资源**按模型独立发放**：每个模型各 1M tokens、有效期一年（本账号 2027-08-20 到期）。同一个 API Key 可访问全部已领取模型，把 Hermes 的辅助模型切到这些免费额度上，实现 **vision 用 hy-vision-2.0-instruct、文本辅助用 deepseek-v4-flash，各吃各的 1M 额度、互不挤占**。

## 现象：两个页面的"1M"口径不一样

- **API Key 管理**页显示"总额度: 0 / 1 M tokens"——这是 Key 级配额上限（创建时可编辑），容易误读成"所有模型共享一个池子"
- **启用管理**页（模型 Tab）显示每个模型独立一行：免费额度余量 100%、到期时间 2027-08-20、领取状态——这是**模型级免费资源**
- 实测确认：`deepseek-v4-flash`（别名）测试消耗后显示 99.9%，其他模型仍是 100%，互不影响

## 原因 / 机制

| 概念 | 说明 |
|---|---|
| 免费体验资源 | 模型级赠送，领取后独立计数，45 个可领已领 37 个 |
| 按量计费 | 独立开关，未开启（0 开启 / 80 未开启）；免费额度耗尽后需开启或换模型 |
| 别名 vs 快照 | `deepseek-v4-flash` = 别名跟随最新；`deepseek-v4-flash-202605` = 0731 固定版快照（name 字段标注"正式版"） |
| API Key 范围 | 可设"全部模型和服务"或指定推理服务；Key 级配额限制可编辑 |

## 分步操作

### 第 1 步：领取免费资源（控制台）

TokenHub 控制台 → 平台管理 → **启用管理** → 免费体验 → **领取免费资源**。每个模型独立领取，共 45 个。

### 第 2 步：获取 API Key（控制台）

平台管理 → **API Key 管理** → 创建 API Key → 可访问范围选"全部模型和服务"。Key 形如 `sk-xxxx`，仅显示一次，妥善保存。

### 第 3 步：配置 Hermes 辅助模型（本机实测命令）

```powershell
# Hermes CN Desktop CLI 入口（hermes 不在 PATH）
$h = "E:\Software\Hermes Agent CN Desktop\data\desktop-bin\hermes.bat"
$key = "sk-你的TokenHubKey"          # 第 2 步获取
$url = "https://tokenhub.tencentmaas.com/v1"

# vision（图片识别）→ 混元视觉模型，用它的独立 1M 额度
cmd /c "`"$h`" config set auxiliary.vision.provider openai"
cmd /c "`"$h`" config set auxiliary.vision.model hy-vision-2.0-instruct"
cmd /c "`"$h`" config set auxiliary.vision.base_url $url"
cmd /c "`"$h`" config set auxiliary.vision.api_key $key"

# 非视觉辅助任务（压缩/标题/审批/网页摘要）→ deepseek-v4-flash
$tasks = @("compression", "title_generation", "approval", "web_extract")
foreach ($t in $tasks) {
  cmd /c "`"$h`" config set auxiliary.$t.provider openai"
  cmd /c "`"$h`" config set auxiliary.$t.model deepseek-v4-flash"
  cmd /c "`"$h`" config set auxiliary.$t.base_url $url"
  cmd /c "`"$h`" config set auxiliary.$t.api_key $key"
}
# 改配置后需新开会话生效
```

> 说明：`provider` 填 `openai` 表示走 OpenAI 兼容协议，真正路由由 `base_url` 决定（自定义 endpoint 时 provider 被忽略）；用 `cmd /c` 包装是因为 PowerShell 的 `&` 调用符会被 Hermes 终端误判为后台执行。

## 验证方法

```powershell
# 1. 模型列表（应有 100+ 模型，含 name/status 字段）
curl.exe -s -H "Authorization: Bearer sk-xxx" https://tokenhub.tencentmaas.com/v1/models

# 2. 单次调用实测（文本）
# POST https://tokenhub.tencentmaas.com/v1/chat/completions
# body: {"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Say OK"}],"max_tokens":300}

# 3. 日志确认辅助任务实际走了 TokenHub
Select-String -Path "E:\Software\Hermes Agent CN Desktop\data\hermes-home\profiles\bendi\logs\agent.log" -Pattern "tokenhub"
```

实测延迟参考（2026-08-20）：`deepseek-v4-flash` 1.5~2.6s；`qwen3.5-plus` 26s（1M 上下文）；`qwen3.5-flash` 14.5s；`glm-5-turbo` 41s（偏慢）。

## 注意事项 / 踩坑记录

- **504 网关超时偶发**：快照版（-202605）首次调用即 504，重试即好；辅助任务建议用别名版（更稳）
- **deepseek-v4-flash 是推理模型**：输出含 reasoning_tokens，压缩长会话时消耗偏大，注意额度余量
- **compression 硬约束**：压缩模型上下文必须 ≥ 主模型，否则静默丢上下文。主模型 deepseek-v4-flash 为 128K，TokenHub 同款匹配；换 qwen3.5-plus（1M）更宽裕但慢
- **到期提醒**：免费额度 2027-08-20 到期，届时需重新领取或开启按量计费
- **Key 保密**：API Key 仅显示一次，知识库/脚本中只写掩码（`sk-oEiLrj***`）
- **备用资源**：45 个免费资源还剩 8 个未领（如 glm-5-turbo、kimi-k2.6），主模型额度耗尽时可一键领取并改一行配置切换

## 关联文档

- 模板参考: `../../99-模板/故障排查模板.md`
- 待积累: Hermes 模型与 provider 配置详解（主模型/回退链/额度池）
- 待积累: 国内大模型 API 平台对比（智谱/通义/Kimi/硅基流动的免费额度与直连性）
