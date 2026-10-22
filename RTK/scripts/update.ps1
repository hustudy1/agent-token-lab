#Requires -Version 5.1
<#
.SYNOPSIS
  RTK 업데이트 (Windows)

.DESCRIPTION
  확인 기준: RTK v1.0.1 · 2026-10-22 · PowerShell 5.1 이상
  설치되어 있을 때만 최신으로 올린다. 새로 설치하지 않는다.
    바이너리: winget upgrade rtk-ai.rtk
    연결:     이미 연결된 에이전트만 같은 방식으로 다시 연결한다.
              새 버전의 지시문(RTK.md)을 받기 위해서다. 다시 연결해도 훅은 하나만 남는다 (2026-10-22 확인).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\update.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '2026-10-22'
$BackupRoot    = Join-Path $HOME '.ai_tokens_backup'
$BackupDir     = Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-rtk-update')
$Failed        = New-Object System.Collections.ArrayList
$CodexDir      = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$ClaudeDir     = Join-Path $HOME '.claude'
$LatestApi     = 'https://api.github.com/repos/rtk-ai/rtk/releases/latest'

# "rtk 1.0.1" 같은 출력에서 버전만 꺼낸다. 실패하면 $null
function Get-RtkVersion {
  $ErrorActionPreference = 'Continue'   # 함수 안에서만 적용
  $raw = (& rtk --version 2>$null) -join ' '
  if ($raw -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
  return $null
}

# GitHub의 최신 정식 릴리스 버전. 실패하면 $null
function Get-LatestVersion {
  try {
    $r = Invoke-RestMethod -Uri $LatestApi -TimeoutSec 10 -Headers @{ 'User-Agent' = 'agent-token-lab' }
    if ($r.tag_name -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
  }
  catch { }
  return $null
}

# ---------- 공통 헬퍼 ----------

function Write-Step  { param([string]$Text) Write-Host ''; Write-Host "==> $Text" -ForegroundColor White }
function Write-Info  { param([string]$Text) Write-Host "    $Text" }
function Write-Ok    { param([string]$Text) Write-Host "    [OK] $Text" -ForegroundColor Green }
function Write-Warn  { param([string]$Text) Write-Host "    [주의] $Text" -ForegroundColor Yellow }
function Write-Err   { param([string]$Text) Write-Host "    [실패] $Text" -ForegroundColor Red }
function Add-Failure { param([string]$Text) Write-Err $Text; [void]$Failed.Add($Text) }
function Stop-Script { param([string]$Text) Write-Host ''; Write-Host "[중단] $Text" -ForegroundColor Red; exit 1 }

function Test-Have {
  param([string]$Name)
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Cmd {
  param([string]$File, [string[]]$Arguments = @())
  $display = (@($File) + $Arguments) -join ' '
  if ($DryRun) { Write-Info "[dry-run] $display"; return $true }
  Write-Info "$ $display"
  $global:LASTEXITCODE = 0
  # PowerShell 5.1은 EAP=Stop일 때 외부 명령의 stderr 출력을 오류로 바꿔 멈출 수 있어,
  # 호출하는 동안만 Continue로 둔다
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  # 출력은 화면으로 바로 보낸다. 그러지 않으면 함수 반환값에 섞여 실패 판정이 틀어진다
  try { & $File @Arguments | Out-Host } finally { $ErrorActionPreference = $prev }
  return ($LASTEXITCODE -eq 0)
}

function Confirm-Continue {
  if ($Yes -or $DryRun) { return }
  Write-Host ''
  $answer = Read-Host '계속할까요? [y/N]'
  if ($answer -notmatch '^(y|Y|yes|YES)$') { Stop-Script '사용자가 취소했습니다.' }
}

# winget으로 올린 직후에는 현재 세션 PATH에 반영되지 않을 수 있어 레지스트리 값으로 다시 읽는다
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($machine -or $user) { $env:Path = "$machine;$user" }
}

function Test-FileContains {
  param([string]$Path, [string]$Pattern)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  return [bool](Select-String -LiteralPath $Path -Pattern $Pattern -Quiet)
}

function Show-Usage {
  Write-Host @'
RTK 업데이트 (Windows)

  .\update.ps1              설치된 RTK를 최신으로 올리고 기존 연결을 다시 맺음

옵션
  -Yes        확인 질문 없이 진행
  -DryRun     실행할 명령만 출력 (아무것도 바꾸지 않음)
  -Help       이 도움말

하는 일
  1. 설치된 버전과 GitHub 최신 버전 비교 (같으면 끝)
  2. 바이너리: winget upgrade rtk-ai.rtk
  3. 연결이 있던 에이전트만 다시 연결
       Claude Code  rtk init -g --auto-patch  (훅만 쓰던 경우 --hook-only 유지)
       Codex        rtk init -g --codex
'@
}

if ($Help) { Show-Usage; exit 0 }

# ---------- 실행 ----------

Write-Host "RTK 업데이트 ($ScriptVersion)" -ForegroundColor White
if ($DryRun) { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }

if (-not (Test-Have 'rtk')) {
  Write-Ok 'RTK가 설치되어 있지 않아 올릴 것이 없습니다. 설치는 .\install.ps1'
  exit 0
}

$current = Get-RtkVersion
$latest  = Get-LatestVersion
Write-Info ("설치된 버전: " + $(if ($current) { "$current" } else { '확인 실패' }) + " ($((Get-Command rtk).Source))")
Write-Info ("최신 버전:   " + $(if ($latest) { "$latest" } else { '확인 실패 (네트워크 확인)' }))

$claudeHook = Test-FileContains (Join-Path $ClaudeDir 'settings.json') 'rtk hook'
$claudeMd   = Test-Path -LiteralPath (Join-Path $ClaudeDir 'RTK.md')
$codexHook  = Test-FileContains (Join-Path $CodexDir 'hooks.json') 'rtk hook'
$claudeState = if (-not $claudeHook) { '없음' } elseif ($claudeMd) { '훅+RTK.md' } else { '훅만' }
Write-Info ("연결: Claude Code=$claudeState, Codex=" + $(if ($codexHook) { '훅' } else { '없음' }))

if ($current -and $latest -and ($current -eq $latest)) {
  Write-Ok '이미 최신입니다.'
  exit 0
}

Confirm-Continue

Write-Step '설정 백업'
Write-Info "위치: $BackupDir"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }
foreach ($f in @(
    (Join-Path $ClaudeDir 'settings.json'), (Join-Path $ClaudeDir 'CLAUDE.md'), (Join-Path $ClaudeDir 'RTK.md'),
    (Join-Path $CodexDir 'AGENTS.md'), (Join-Path $CodexDir 'hooks.json'), (Join-Path $CodexDir 'RTK.md'))) {
  if (Test-Path -LiteralPath $f) {
    $dest = Join-Path $BackupDir ((Split-Path (Split-Path $f -Parent) -Leaf) + '-' + (Split-Path $f -Leaf))
    if ($DryRun) { Write-Info "[dry-run] copy $f" }
    else { Copy-Item -LiteralPath $f -Destination $dest -Force; Write-Ok $f }
  }
}

Write-Step '바이너리 업데이트'
$failedBefore = $Failed.Count
if (Test-Have 'winget') {
  $wingetArgs = @('upgrade', '--id', 'rtk-ai.rtk', '-e', '--accept-package-agreements', '--accept-source-agreements')
  if (-not (Invoke-Cmd 'winget' $wingetArgs)) {
    Add-Failure 'winget upgrade rtk-ai.rtk 실패 (winget으로 설치하지 않았다면 설치한 방식대로 직접 올리세요)'
  }
  if (-not $DryRun) { Update-SessionPath }
}
else {
  Add-Failure 'winget이 없습니다. https://github.com/rtk-ai/rtk/releases 에서 새 rtk-x86_64-pc-windows-msvc.zip 으로 바꾸세요.'
}

if (-not $DryRun) {
  $new = Get-RtkVersion
  $global:LASTEXITCODE = 0
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & rtk gain *> $null
  $ErrorActionPreference = $prev
  if ($LASTEXITCODE -eq 0) { Write-Ok "rtk $new" } else { Add-Failure '업데이트 후 rtk gain이 실패했습니다.' }
}

Write-Step '연결 다시 맺기 (새 버전의 지시문 반영)'
if ($Failed.Count -gt $failedBefore) {
  Write-Info '바이너리 업데이트가 실패해 연결은 그대로 둡니다.'
}
elseif ($claudeHook) {
  $initArgs = if ($claudeMd) { @('init', '-g', '--auto-patch') } else { @('init', '-g', '--hook-only', '--auto-patch') }
  if (-not (Invoke-Cmd 'rtk' $initArgs)) { Add-Failure ('rtk ' + ($initArgs -join ' ') + ' 실패') }
}
else { Write-Info 'Claude Code: 연결된 적이 없어 건너뜁니다.' }
if ($Failed.Count -gt $failedBefore) { }
elseif ($codexHook) {
  if (-not (Invoke-Cmd 'rtk' @('init', '-g', '--codex'))) { Add-Failure 'rtk init -g --codex 실패' }
}
else { Write-Info 'Codex: 연결된 적이 없어 건너뜁니다.' }

Write-Step '결과'
if ($Failed.Count -gt 0) {
  Write-Err ('실패한 단계가 있습니다: ' + ($Failed -join '; '))
  Write-Info "되돌리기: $BackupDir 의 파일을 원래 위치로 복사하세요."
  exit 1
}
elseif ($DryRun) { Write-Ok 'dry-run 완료 (실제로 바꾼 것은 없습니다)' }
else {
  Write-Ok '업데이트 완료. Claude Code와 Codex를 다시 시작하면 반영됩니다.'
  Write-Info '참고: RTK 1.0부터 rtk proxy <명령> 은 rtk bypass <명령> 입니다 (옛 이름도 동작).'
}
# 확인용으로 실행한 명령의 종료 코드가 남지 않게 성공을 명시한다
exit 0
