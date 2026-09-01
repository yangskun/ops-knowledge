<#
.SYNOPSIS
  运维知识库站点一键更新(方案1: GitHub API 直连,无需代理)

.DESCRIPTION
  执行 mkdocs build 并将构建产物上传到 gh-pages 分支。
  基于 GitHub Contents API(curl 直连 api.github.com),国内直连稳定,不需要代理。
  注意: 不用 Invoke-RestMethod(PS5.1 对 query string 有 bug),统一用 curl。

.PARAMETER Token
  GitHub Personal Access Token(repo 权限)。也可通过环境变量 GH_TOKEN 提供。

.PARAMETER Prune
  删除远端 gh-pages 分支上本地已不存在的文件(文档改名/删除后同步清理用)。

.EXAMPLE
  .\update-site.ps1 -Token ghp_xxxxx
  $env:GH_TOKEN = "ghp_xxxxx"; .\update-site.ps1 -Prune
#>
param(
  [string]$Token = $env:GH_TOKEN,
  [switch]$Prune
)

$ErrorActionPreference = 'Stop'
if (-not $Token) { Write-Error "需要 GitHub Token(用 -Token 参数或设置环境变量 GH_TOKEN)"; exit 1 }

$repo    = 'yangskun/ops-knowledge'
$base    = "https://api.github.com/repos/$repo"
$auth    = "Authorization: token $Token"
$kbRoot  = Split-Path -Parent $PSScriptRoot                                          # 知识库根
$siteDir = Join-Path (Split-Path -Parent $kbRoot) 'knowledge-site'                   # 构建输出
$tmpBody = Join-Path $env:TEMP "gh-body-$(Get-Random).json"

function Write-BodyNoBom([hashtable]$obj) {
    $json = $obj | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($tmpBody, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# [1/3] 构建
Write-Output '[1/3] mkdocs build ...'
& py -3.11 -m mkdocs build -f (Join-Path $kbRoot 'mkdocs.yml') | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error 'mkdocs build 失败'; exit 1 }

# [2/3] 上传全部 site 文件(已存在则带 sha 更新)
Write-Output '[2/3] 上传 site 到 gh-pages ...'
$files = Get-ChildItem $siteDir -Recurse -File | ForEach-Object { $_.FullName.Substring($siteDir.Length + 1) }
$ok = 0; $fail = 0
foreach ($f in $files) {
    $fsPath  = Join-Path $siteDir $f
    $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fsPath))
    $apiPath = (($f -replace '\\', '/') -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    # GET sha(文件存在时;404 表示新文件)
    $sha = $null
    $getOut = curl.exe -s --connect-timeout 20 -H $auth "$base/contents/$apiPath`?ref=gh-pages" 2>$null
    if ($LASTEXITCODE -eq 0 -and $getOut) {
        try { $sha = ($getOut | ConvertFrom-Json).sha } catch { }
    }
    # PUT
    $body = @{ message = 'update site'; content = $content; branch = 'gh-pages' }
    if ($sha) { $body['sha'] = $sha }
    Write-BodyNoBom $body
    $code = curl.exe -s --connect-timeout 20 -o NUL -w "%{http_code}" -X PUT -H $auth -H "Content-Type: application/json" --data-binary "@$tmpBody" "$base/contents/$apiPath" 2>$null
    if ($code -eq '200' -or $code -eq '201') { $ok++ }
    else { Write-Output "FAIL $f (HTTP $code)"; $fail++ }
}
Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
Write-Output "上传完成: ok=$ok fail=$fail"

# [3/3] 可选:删除远端多余文件
if ($Prune) {
    Write-Output '[3/3] 清理远端多余文件 ...'
    $tree = curl.exe -s --connect-timeout 20 -H $auth "$base/git/trees/gh-pages`?recursive=1" 2>$null | ConvertFrom-Json
    $local = @($files) + @('.nojekyll')
    $stale = $tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path -notin $local }
    foreach ($f in $stale) {
        $apiPath = (($f.path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        Write-BodyNoBom @{ message = 'prune'; sha = $f.sha; branch = 'gh-pages' }
        $code = curl.exe -s --connect-timeout 20 -o NUL -w "%{http_code}" -X DELETE -H $auth -H "Content-Type: application/json" --data-binary "@$tmpBody" "$base/contents/$apiPath" 2>$null
        if ($code -eq '200') { Write-Output "PRUNE $($f.path)" }
        else { Write-Output "FAIL prune $($f.path) (HTTP $code)" }
    }
    Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
}
Write-Output '=== 更新完成 ==='
