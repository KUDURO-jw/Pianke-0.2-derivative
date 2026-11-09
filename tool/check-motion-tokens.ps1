# Modified for the personal UI edition, 2026-11-08. Apache-2.0.
<#
.SYNOPSIS
    检查动效时长是否只从设计令牌取值。

.DESCRIPTION
    T9 的目标：除 `lib/config/design_tokens.dart` 外，代码里不再出现
    `Duration(milliseconds: N)` 这类魔法数字。

    这条检查放进 CI，可以防止以后又有人随手写死一个 200ms——那样
    「减少动态效果」的开关就会静默失效，而现象很难被测试发现。

    用法：pwsh tool/check-motion-tokens.ps1
    退出码：0 = 干净；1 = 发现魔法数字。
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$LibDir = 'lib'
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot 不能作为参数默认值使用（默认值在脚本目录确定之前求值），
# 所以放到函数体里解析：默认是仓库根（tool/ 的上一级）。
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$libPath = Join-Path $Root $LibDir
if (-not (Test-Path $libPath)) {
    Write-Error "找不到目录：$libPath"
    exit 1
}

# 令牌定义文件本身允许出现 Duration(milliseconds: N)。
$allowList = @('design_tokens.dart')

$offenders = @()
Get-ChildItem -Path $libPath -Recurse -Filter '*.dart' | ForEach-Object {
    if ($allowList -contains $_.Name) { return }

    $lines = Get-Content -LiteralPath $_.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        # 注释里的示例不算违规。
        if ($lines[$i] -match '^\s*//') { continue }
        if ($lines[$i] -match 'Duration\(milliseconds:\s*\d') {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $offenders += [pscustomobject]@{
                File = $relative
                Line = $i + 1
                Code = $lines[$i].Trim()
            }
        }
    }
}

if ($offenders.Count -eq 0) {
    Write-Host '动效令牌检查通过：没有硬编码的 Duration(milliseconds:)。'
    exit 0
}

Write-Host "发现 $($offenders.Count) 处硬编码动效时长，请改用 Motion 令牌：" -ForegroundColor Red
Write-Host ''
foreach ($item in $offenders) {
    Write-Host ("  {0}:{1}" -f $item.File, $item.Line)
    Write-Host ("      {0}" -f $item.Code)
}
Write-Host ''
Write-Host '规则：新增动画一律写 Motion.of(context, Motion.xxx)，时长只在 lib/config/design_tokens.dart 定义。'
exit 1
