#Requires -Version 5.1
<#
.SYNOPSIS
  Caveman 업데이트 (Windows)

.DESCRIPTION
  확인 기준: caveman v4.0.1 · skills CLI 1.7.4 · 2026-10-22 · PowerShell 5.1 이상
  설치되어 있는 것만 최신으로 올린다. 새로 설치하지 않는다.
    스킬(npx skills)    → npx skills update <설치된 스킬> -g -y
    Claude Code 플러그인 → claude plugin update caveman@caveman
    CLI·프록시(npm -g)  → npm install -g @caveman-ai/cli@latest

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

# Caveman CLI(3.0.0부터)와 일부 하위 도구는 사용 통계를 기본으로 보낸다. 이 스크립트가 부르는 명령은 모두 끈다.
$env:DO_NOT_TRACK = '1'

$ScriptVersion = '2026-10-22'
$Failed        = New-Object System.Collections.ArrayList

$SkillNames = @(
  'caveman', 'cavecrew', 'caveman-commit', 'caveman-compress', 'caveman-discover',
  'caveman-evidence-review', 'caveman-explore', 'caveman-help', 'caveman-learn', 'caveman-manage',
  'caveman-optimize', 'caveman-review', 'caveman-setup', 'caveman-stats', 'investigate-first',
  'lean-build', 'megacave', 'migration', 'safe-refactor', 'surgical-patch', 'ultracave', 'verify-and-stop'
)
$CodexDir  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$SkillDirs = @(
  ([IO.Path]::Combine($HOME, '.claude', 'skills')),
  ([IO.Path]::Combine($HOME, '.agents', 'skills')),
  (Join-Path $CodexDir 'skills')
)

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

# 외부 명령을 조용히 실행해 성공 여부만 돌려준다
function Test-Cmd {
  param([string]$File, [string[]]$Arguments = @(), [string]$Match = '')
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $global:LASTEXITCODE = 0
    $out = (& $File @Arguments 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { return $false }
    if ($Match) { return ($out -match $Match) }
    return $true
  }
  catch { return $false }
  finally { $ErrorActionPreference = $prev }
}

function Confirm-Continue {
  if ($Yes -or $DryRun) { return }
  Write-Host ''
  $answer = Read-Host '계속할까요? [y/N]'
  if ($answer -notmatch '^(y|Y|yes|YES)$') { Stop-Script '사용자가 취소했습니다.' }
}

function Show-Usage {
  Write-Host @'
Caveman 업데이트 (Windows)

  .\update.ps1              설치된 Caveman을 최신으로 올림 (새로 설치하지 않음)

옵션
  -Yes        확인 질문 없이 진행
  -DryRun     실행할 명령만 출력 (아무것도 바꾸지 않음)
  -Help       이 도움말

올리는 것 (설치되어 있는 것만)
  스킬                 npx skills update <설치된 스킬> -g -y
  Claude Code 플러그인  claude plugin update caveman@caveman
  CLI·프록시           npm install -g @caveman-ai/cli@latest
'@
}

# 설치된 Caveman 스킬 이름 (중복 없이)
function Get-InstalledSkills {
  $found = New-Object System.Collections.ArrayList
  foreach ($d in $SkillDirs) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    foreach ($n in $SkillNames) {
      if ((Test-Path -LiteralPath (Join-Path $d $n)) -and -not $found.Contains($n)) { [void]$found.Add($n) }
    }
    Get-ChildItem -LiteralPath $d -Filter '*cave*' -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $found.Contains($_.Name)) { [void]$found.Add($_.Name) }
    }
  }
  $found.ToArray()
}

# caveman 스킬 내용의 지문. 업데이트 전후를 비교해 바뀌었는지 알려 준다
function Get-SkillFingerprint {
  $hashes = foreach ($d in $SkillDirs) {
    $f = Join-Path (Join-Path $d 'caveman') 'SKILL.md'
    if (Test-Path -LiteralPath $f) { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
  }
  (@($hashes) | Sort-Object -Unique) -join ' '
}

if ($Help) { Show-Usage; exit 0 }

# ---------- 실행 ----------

Write-Host "Caveman 업데이트 ($ScriptVersion)" -ForegroundColor White
if ($DryRun) { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }

$skills    = @(Get-InstalledSkills)
$hasPlugin = (Test-Have 'claude') -and (Test-Cmd 'claude' @('plugin', 'list') 'caveman@caveman')
$hasCli    = (Test-Have 'npm') -and (Test-Cmd 'npm' @('ls', '-g', '@caveman-ai/cli', '--depth=0'))

Write-Info ("스킬: " + $(if ($skills.Count) { $skills -join ' ' } else { '없음' }))
Write-Info ("Claude Code 플러그인: " + $(if ($hasPlugin) { '있음' } else { '없음' }))
Write-Info ("CLI(@caveman-ai/cli): " + $(if ($hasCli) { '있음' } else { '없음' }))

if ($skills.Count -eq 0 -and -not $hasPlugin -and -not $hasCli) {
  Write-Ok '설치된 Caveman이 없어 올릴 것이 없습니다. 설치는 .\install.ps1'
  exit 0
}

Confirm-Continue

$before = Get-SkillFingerprint

if ($skills.Count -gt 0) {
  Write-Step '스킬 업데이트 (skills CLI)'
  if (Test-Have 'npx') {
    $updateArgs = @('--yes', 'skills', 'update') + $skills + @('-g', '-y')
    if (-not (Invoke-Cmd 'npx' $updateArgs)) { Add-Failure '스킬 업데이트 실패' }
  }
  else {
    Add-Failure 'npx가 없어 스킬을 올릴 수 없습니다. Node.js를 설치하세요.'
  }
}

if ($hasPlugin) {
  Write-Step 'Claude Code 플러그인 업데이트'
  if (-not (Invoke-Cmd 'claude' @('plugin', 'update', 'caveman@caveman'))) { Add-Failure '플러그인 업데이트 실패' }
}

if ($hasCli) {
  Write-Step 'CLI·프록시 업데이트'
  if (-not (Invoke-Cmd 'npm' @('install', '-g', '@caveman-ai/cli@latest'))) { Add-Failure 'CLI 업데이트 실패' }
  Write-Warn 'Caveman CLI는 사용 통계를 기본으로 보냅니다. 끄기: caveman telemetry off (또는 DO_NOT_TRACK=1)'
}

Write-Step '결과'
if (-not $DryRun -and $skills.Count -gt 0) {
  if ((Get-SkillFingerprint) -eq $before) { Write-Info 'caveman 스킬 내용: 이미 최신 (바뀐 것 없음)' }
  else { Write-Ok 'caveman 스킬 내용: 새 버전으로 바뀜' }
}
if ($Failed.Count -gt 0) {
  Write-Err ('실패한 단계가 있습니다: ' + ($Failed -join '; '))
  exit 1
}
elseif ($DryRun) { Write-Ok 'dry-run 완료 (실제로 바꾼 것은 없습니다)' }
else { Write-Ok '업데이트 완료. 에이전트를 새 세션으로 시작하면 반영됩니다.' }
# 확인용으로 실행한 명령(npm ls 등)의 종료 코드가 남지 않게 성공을 명시한다
exit 0
