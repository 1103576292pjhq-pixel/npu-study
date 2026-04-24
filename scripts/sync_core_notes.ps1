Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StudyRoot = 'C:\Users\11035\Desktop\ic\npu\study\NPU_从0到设计'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$VaultRoot = 'C:\Users\11035\Desktop\学习\刘帅'
$NotebookId = '20260411155319-2osvx5a'
$RootTitle = 'NPU从0到设计（核心阅读版）'
$SiYuanAssetsRoot = Join-Path $VaultRoot 'data\assets'
$ConfPath = Join-Path $VaultRoot 'conf\conf.json'
$ArchiveRoot = Join-Path $RepoRoot 'archive\siyuan-sync'
$ArchiveRoot = Join-Path $ArchiveRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

function Read-JsonFile {
  param([string]$Path)
  return (Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Invoke-SiYuanApi {
  param(
    [string]$Endpoint,
    [object]$Payload
  )

  $conf = Read-JsonFile -Path $ConfPath
  $token = $conf.api.token
  $body = $Payload | ConvertTo-Json -Depth 20 -Compress
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  return Invoke-RestMethod -Uri ("http://127.0.0.1:6806/api" + $Endpoint) `
    -Method Post `
    -Headers @{ Authorization = "Token $token" } `
    -ContentType 'application/json; charset=utf-8' `
    -Body $bodyBytes
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
  }
}

function Remove-PathIfExists {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Copy-CoreFile {
  param(
    [string]$RelativeSource,
    [string]$RelativeTarget
  )

  $src = Join-Path $StudyRoot $RelativeSource
  $dst = Join-Path $RepoRoot $RelativeTarget
  $dstDir = Split-Path -Parent $dst
  Ensure-Dir -Path $dstDir
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

function Copy-CoreDir {
  param(
    [string]$RelativeSource,
    [string]$RelativeTarget
  )

  $src = Join-Path $StudyRoot $RelativeSource
  $dst = Join-Path $RepoRoot $RelativeTarget
  Remove-PathIfExists -Path $dst
  Ensure-Dir -Path (Split-Path -Parent $dst)
  Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
}

function Get-RepoMarkdownForSiyuan {
  param([string]$Path)

  $content = Get-Content -Path $Path -Raw -Encoding UTF8
  $content = $content -replace "!\[([^\]]*)\]\(\.\./assets/figures/([^)]+)\)", "![`$1](assets/npu-study-`$2)"
  $content = $content -replace "\[([^\]]+)\]\(([^)]+\.md)\)", '$1'
  return $content
}

function List-RootDocs {
  $resp = Invoke-SiYuanApi -Endpoint '/filetree/listDocsByPath' -Payload @{ notebook = $NotebookId; path = '/' }
  if ($resp.code -ne 0) {
    throw 'Failed to list SiYuan docs.'
  }
  return $resp.data.files
}

function Backup-And-RemoveRootDoc {
  param([object]$Doc)

  Ensure-Dir -Path $ArchiveRoot
  $notebookRoot = Join-Path $VaultRoot ('data\' + $NotebookId)
  $syPath = Join-Path $notebookRoot ($Doc.path.TrimStart('/'))
  if (Test-Path -LiteralPath $syPath) {
    Copy-Item -LiteralPath $syPath -Destination (Join-Path $ArchiveRoot (Split-Path -Leaf $syPath)) -Force
  }
  $childDir = Join-Path $notebookRoot $Doc.id
  if (Test-Path -LiteralPath $childDir) {
    Copy-Item -LiteralPath $childDir -Destination (Join-Path $ArchiveRoot $Doc.id) -Recurse -Force
  }
  $removeResp = Invoke-SiYuanApi -Endpoint '/filetree/removeDoc' -Payload @{ notebook = $NotebookId; path = $Doc.path }
  if ($removeResp.code -ne 0) {
    throw "Failed to remove existing root doc: $($Doc.name)"
  }
}

function Create-Doc {
  param(
    [string]$Path,
    [string]$Markdown
  )

  $attempt = 0
  while ($attempt -lt 4) {
    $attempt += 1
    $resp = Invoke-SiYuanApi -Endpoint '/filetree/createDocWithMd' -Payload @{
      notebook = $NotebookId
      path = $Path
      markdown = $Markdown
    }
    if ($resp.code -eq 0) {
      return
    }
    Start-Sleep -Milliseconds 600
  }
  throw "Failed to create doc at $Path"
}

$coreDirs = @(
  '01_前置基础',
  '02_NPU全景与问题定义',
  '03_计算核心与阵列架构',
  '04_数据流_硬件循环_片上存储',
  '05_量化_稀疏_算子融合',
  '06_编译器_图优化_后端生成',
  '07_Runtime_驱动_系统集成',
  '08_性能_功耗_安全_多核_Chiplet',
  '09_厂商案例与平台实践',
  '10_综合案例'
)

$coreFiles = @(
  '00_学习地图.md',
  '90_术语表.md'
)

$supportFiles = @(
  @{ Src = 'sources\local\00_本地来源台账.md'; Dst = 'sources\00_本地来源台账.md' },
  @{ Src = 'sources\local\01_主线专题映射.md'; Dst = 'sources\01_主线专题映射.md' },
  @{ Src = 'sources\external\00_权威来源索引.md'; Dst = 'sources\02_权威来源索引.md' }
)

$figureFiles = @(
  '04_tile_pipeline.svg',
  '06_multilevel_ir_pipeline.svg',
  '08_latency_boundary.svg',
  '10_end_to_end_closed_loop.svg'
)

foreach ($dir in $coreDirs) {
  Copy-CoreDir -RelativeSource $dir -RelativeTarget $dir
}

foreach ($file in $coreFiles) {
  Copy-CoreFile -RelativeSource $file -RelativeTarget $file
}

foreach ($entry in $supportFiles) {
  Copy-CoreFile -RelativeSource $entry.Src -RelativeTarget $entry.Dst
}

Ensure-Dir -Path (Join-Path $RepoRoot 'assets')
Copy-CoreDir -RelativeSource 'assets\figures' -RelativeTarget 'assets\figures'

Ensure-Dir -Path $SiYuanAssetsRoot
foreach ($figure in $figureFiles) {
  $src = Join-Path (Join-Path $StudyRoot 'assets\figures') $figure
  $dst = Join-Path $SiYuanAssetsRoot ('npu-study-' + $figure)
  Copy-Item -LiteralPath $src -Destination $dst -Force
}

$rootDocs = List-RootDocs
$existing = $rootDocs | Where-Object { $_.name -eq ($RootTitle + '.sy') } | Select-Object -First 1
if ($existing) {
  Backup-And-RemoveRootDoc -Doc $existing
}

$rootMd = @'
# __ROOTTITLE__

这是一棵同步到思源的核心阅读树，来源仓库位于：

- `D:\github\npu-study`

阅读建议：

1. 先看 `00 学习地图`
2. 再顺读 `01` 到 `10`
3. 遇到跨章术语回看 `90 术语表`

当前同步范围只保留最核心的阅读笔记，不把执行态台账和中间状态文件混进主树。
'@
$rootMd = $rootMd.Replace('__ROOTTITLE__', $RootTitle)

Create-Doc -Path ('/' + $RootTitle) -Markdown $rootMd
Start-Sleep -Seconds 1

$siyuanDocs = @(
  @{ Path = '00_学习地图'; Source = Join-Path $RepoRoot '00_学习地图.md' },
  @{ Path = '01_前置基础'; Source = Join-Path $RepoRoot '01_前置基础\01_前置基础.md' },
  @{ Path = '02_NPU全景与问题定义'; Source = Join-Path $RepoRoot '02_NPU全景与问题定义\01_NPU全景与问题定义.md' },
  @{ Path = '03_计算核心与阵列架构'; Source = Join-Path $RepoRoot '03_计算核心与阵列架构\01_计算核心与阵列架构.md' },
  @{ Path = '04_数据流_硬件循环_片上存储'; Source = Join-Path $RepoRoot '04_数据流_硬件循环_片上存储\01_数据流_硬件循环_片上存储.md' },
  @{ Path = '05_量化_稀疏_算子融合'; Source = Join-Path $RepoRoot '05_量化_稀疏_算子融合\01_量化_稀疏_算子融合.md' },
  @{ Path = '06_编译器_图优化_后端生成'; Source = Join-Path $RepoRoot '06_编译器_图优化_后端生成\01_编译器_图优化_后端生成.md' },
  @{ Path = '07_Runtime_驱动_系统集成'; Source = Join-Path $RepoRoot '07_Runtime_驱动_系统集成\01_Runtime_驱动_系统集成.md' },
  @{ Path = '08_性能_功耗_安全_多核_Chiplet'; Source = Join-Path $RepoRoot '08_性能_功耗_安全_多核_Chiplet\01_性能_功耗_安全_多核_Chiplet.md' },
  @{ Path = '09_厂商案例与平台实践'; Source = Join-Path $RepoRoot '09_厂商案例与平台实践\01_厂商案例与平台实践.md' },
  @{ Path = '10_综合案例'; Source = Join-Path $RepoRoot '10_综合案例\01_从模型到系统的闭环案例.md' },
  @{ Path = '90_术语表'; Source = Join-Path $RepoRoot '90_术语表.md' }
)

foreach ($doc in $siyuanDocs) {
  $md = Get-RepoMarkdownForSiyuan -Path $doc.Source
  Create-Doc -Path ('/' + $RootTitle + '/' + $doc.Path) -Markdown $md
}

Write-Host 'SYNC_OK'
