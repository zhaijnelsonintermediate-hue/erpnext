# 构建同时包含 ERPNext 和 Frappe CRM 的自定义 bench 镜像（Windows PowerShell 版）。
#
# 与 build-image.sh 等价，行为一致。为什么必须自建镜像见 README.md。
#
# 用法（在仓库根目录）：
#   .\docker\build-image.ps1
#   .\docker\build-image.ps1 -ForceRebuild      # 强制重装应用，拿上游最新提交

[CmdletBinding()]
param(
    [string]$Image,
    [string]$FrappeBranch,
    [string]$FrappeDockerRef,
    [switch]$ForceRebuild
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 读 docker/.env，让 PowerShell 和 make 两条路径用同一份配置
$envFile = Join-Path $root 'docker\.env'
$conf = @{}
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $conf[$Matches[1]] = $Matches[2].Trim()
        }
    }
}

function Get-Setting($name, $param, $fallback) {
    if ($param) { return $param }
    if ($conf.ContainsKey($name) -and $conf[$name]) { return $conf[$name] }
    return $fallback
}

$Image           = Get-Setting 'IMAGE'             $Image           'erpnext-crm:local'
$FrappeBranch    = Get-Setting 'FRAPPE_BRANCH'     $FrappeBranch    'version-16'
$FrappeDockerRef = Get-Setting 'FRAPPE_DOCKER_REF' $FrappeDockerRef 'main'

$context = Join-Path $root '.cache\frappe_docker'
$appsJson = Join-Path $root 'docker\apps.json'

# frappe_docker 只作为构建上下文使用（Containerfile + resources/ 下的入口脚本），
# 不进版本库，所以放在 .cache 里按需拉取。
if (Test-Path (Join-Path $context '.git')) {
    Write-Host "==> 更新构建上下文 frappe_docker@$FrappeDockerRef"
    git -C $context fetch --depth 1 origin $FrappeDockerRef
    git -C $context checkout -q FETCH_HEAD
} else {
    Write-Host "==> 拉取构建上下文 frappe_docker@$FrappeDockerRef"
    if (Test-Path $context) { Remove-Item -Recurse -Force $context }
    git clone --depth 1 --branch $FrappeDockerRef https://github.com/frappe/frappe_docker $context
}

# apps.json 是以 build secret 挂进去的，Docker 不会因为它的内容变化而让缓存失效。
# 用它的哈希做 CACHE_BUST，改了应用清单就会重新装应用，没改则命中缓存。
$cacheBust = (Get-FileHash -Algorithm SHA256 $appsJson).Hash.ToLower()
if ($ForceRebuild) {
    $cacheBust = "$cacheBust-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
}

Write-Host "==> 构建镜像 $Image (frappe $FrappeBranch)"
Write-Host "    应用清单："
Get-Content $appsJson | ForEach-Object { Write-Host "      $_" }

$env:DOCKER_BUILDKIT = '1'
docker build `
    --secret "id=apps_json,src=$appsJson" `
    --build-arg "FRAPPE_BRANCH=$FrappeBranch" `
    --build-arg "CACHE_BUST=$cacheBust" `
    --tag $Image `
    --file (Join-Path $context 'images\layered\Containerfile') `
    $context

if ($LASTEXITCODE -ne 0) { throw "镜像构建失败，退出码 $LASTEXITCODE" }

Write-Host "==> 完成：$Image"
Write-Host "    镜像内应用："
docker run --rm --entrypoint cat $Image /home/frappe/frappe-bench/sites/apps.txt
