param(
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [string]$ManifestPath,
    [string]$PublicApkUrl,
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$policy = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'release-policy.json') | ConvertFrom-Json
$tracked = & git -C $root ls-files
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect source paths for signing materials' }
$sensitive = $tracked | Where-Object { $_ -match '(^|/)(key\.properties|[^/]+\.(jks|keystore|p12|pfx))$' }
if ($sensitive) { throw 'Signing materials must not be tracked or included in the source archive' }
$pubspec = Get-Content -Raw -LiteralPath (Join-Path $root 'pubspec.yaml')
$version = [regex]::Match($pubspec, '(?m)^version:\s*([^+\s]+)\+(\d+)\s*$')
if (!$version.Success) { throw 'pubspec version must contain name+code' }
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $env:ANDROID_HOME }
if (!$sdk) { throw 'Set ANDROID_SDK_ROOT first' }
$buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory |
    Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe')) -and (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$buildTools) { throw 'Android build-tools with aapt and apksigner are required' }
$badging = (& (Join-Path $buildTools.FullName 'aapt.exe') dump badging $apk 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect APK' }
$package = [regex]::Match($badging, "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
if (!$package.Success -or $package.Groups[1].Value -ne $policy.packageName) { throw 'Package name mismatch' }
if ($package.Groups[2].Value -ne $version.Groups[2].Value -or $package.Groups[3].Value -ne $version.Groups[1].Value) { throw 'Version mismatch' }
$abi = [regex]::Match($badging, "(?m)^native-code: (.+)$").Groups[1].Value.Trim()
if ($abi -ne "'$($policy.abi)'") { throw "Unexpected ABI: $abi" }
$signature = (& (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs $apk 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
$certificates = [regex]::Matches($signature, 'Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)')
if ($certificates.Count -ne 1 -or $certificates[0].Groups[1].Value.ToLowerInvariant() -ne $policy.signerSha256) { throw 'Certificate changed: this build cannot cover the installed edition' }
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$bytes = (Get-Item -LiteralPath $apk).Length
if ($ManifestPath) {
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
    if ($manifest.versionName -ne $version.Groups[1].Value -or [string]$manifest.versionCode -ne $version.Groups[2].Value -or $manifest.sha256 -ne $hash) { throw 'Manifest does not match the verified APK' }
    if ($manifest.forceUpdate -eq $true) { throw 'UI channel updates must remain optional' }
    $expectedDownload = '^https://github\.com/' + [regex]::Escape($policy.repository) + '/releases/download/v' + [regex]::Escape($version.Groups[1].Value) + '-ui\.\d+/Pianke-UI-arm64-release\.apk$'
    if ($manifest.downloadUrl -notmatch $expectedDownload) { throw 'Manifest points outside this edition release channel' }
    if (!$PublicApkUrl) { $PublicApkUrl = $manifest.downloadUrl }
    if ($PublicApkUrl -ne $manifest.downloadUrl) { throw 'Manifest download URL mismatch' }
}
if ($PublicApkUrl) {
    $uri = [uri]$PublicApkUrl
    if ($uri.Scheme -ne 'https') { throw 'Public downloads must use HTTPS' }
    $download = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.apk')
    try {
        Invoke-WebRequest -Uri $uri -OutFile $download
        if ((Get-Item -LiteralPath $download).Length -ne $bytes -or (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Public APK differs from the local verified artifact' }
    } finally { if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download } }
}
if (!$OutputDirectory) { $OutputDirectory = Split-Path -Parent $apk }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$report = [ordered]@{ version = $package.Groups[3].Value; versionCode = [int]$package.Groups[2].Value; packageName = $policy.packageName; signerSha256 = $policy.signerSha256; abi = $policy.abi; bytes = $bytes; sha256 = $hash; publicDownloadVerified = [bool]$PublicApkUrl }
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'release-report.json') -Encoding utf8
"$hash  $([System.IO.Path]::GetFileName($apk))" | Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding ascii
$report | ConvertTo-Json
