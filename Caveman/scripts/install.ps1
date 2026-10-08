#Requires -Version 5.1
<#
.SYNOPSIS
  Caveman 스킬 설치 (Windows)

.DESCRIPTION
  확인 기준: caveman v2.7.0 · 2026-09-29 · PowerShell 5.1 이상
  설치하는 것: Caveman 스킬 (MIT)
  설치하지 않는 것: Caveman 프록시와 CLI (BSL-1.1).
    프록시는 API 주소를 로컬 프록시로 바꿔서 Claude Code의 MCP tool search를
    끄는 부작용이 있습니다. ..\01_install.md 4단계를 읽고 직접 설치하세요.
  제거: .\uninstall.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$NoCodex,
  [switch]$Plugin,
  [switch]$AllSkills,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '2026-09-29'
$NodeMinMajor  = 22
$NodeMinMinor  = 13
$BackupRoot    = Join-Path $HOME '.ai_tokens_backup'
$BackupDir     = Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-caveman')
$Failed        = New-Object System.Collections.ArrayList

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
  try { & $File @Arguments } finally { $ErrorActionPreference = $prev }
  return ($LASTEXITCODE -eq 0)
}

function Confirm-Continue {
  if ($Yes -or $DryRun) { return }
  Write-Host ''
  $answer = Read-Host '계속할까요? [y/N]'
  if ($answer -notmatch '^(y|Y|yes|YES)$') { Stop-Script '사용자가 취소했습니다.' }
}

function Show-Usage {
  Write-Host @'
Caveman 스킬 설치 (Windows)

  .\install.ps1             Claude Code(와 Codex)에 Caveman 스킬 설치
  .\uninstall.ps1           제거

옵션
  -Yes        확인 질문 없이 진행
  -DryRun     실행할 명령만 출력 (아무것도 바꾸지 않음)
  -NoCodex    Codex는 건드리지 않음
  -AllSkills  스킬 22개 전부 설치 (기본은 caveman, caveman-compress 2개)
  -Plugin     Claude Code는 플러그인 방식으로 설치
              (claude plugin marketplace add + plugin install)
  -Help       이 도움말

요구사항
  Node.js 22.13 이상 (없으면: winget install OpenJS.NodeJS)

실행 정책 때문에 막히면
  powershell -ExecutionPolicy Bypass -File .\install.ps1
'@
}

function Test-NodeVersion {
  if (-not (Test-Have 'node')) { return $false }
  $parts = ((& node -v) -replace '^v', '').Split('.')
  $major = 0; $minor = 0
  [void][int]::TryParse($parts[0], [ref]$major)
  if ($parts.Length -gt 1) { [void][int]::TryParse($parts[1], [ref]$minor) }
  if ($major -gt $NodeMinMajor) { return $true }
  return ($major -eq $NodeMinMajor -and $minor -ge $NodeMinMinor)
}

if ($Help) { Show-Usage; exit 0 }

# Claude Code: CLI가 있거나 .claude 폴더가 있으면 사용 중으로 본다
# (VS Code 확장만 쓰면 claude 명령이 PATH에 없을 수 있다. 설정 폴더는 CLI와 확장이 같이 쓴다)
$HasClaude = (Test-Have 'claude') -or (Test-Path -LiteralPath (Join-Path $HOME '.claude') -PathType Container)
$HasCodex  = (Test-Have 'codex') -and (-not $NoCodex)

# ---------- 실행 ----------

Write-Host "Caveman 스킬 설치 ($ScriptVersion)" -ForegroundColor White
if ($DryRun) { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }
$claudeText = if ($HasClaude) { '있음' } else { '없음' }
$codexText  = if ($HasCodex)  { '있음' } else { '없음' }
Write-Info "대상: Claude Code=$claudeText, Codex=$codexText"
if ($Plugin) { Write-Info 'Claude Code 설치 방식: 플러그인' }
if (-not $HasClaude -and -not $HasCodex) {
  Stop-Script 'claude도 codex도 찾지 못해 설치할 곳이 없습니다. 에이전트를 먼저 설치하세요.'
}

Confirm-Continue

Write-Step '설정 백업'
Write-Info "위치: $BackupDir"
if ($DryRun) { Write-Info "[dry-run] mkdir $BackupDir" }
else { [void](New-Item -ItemType Directory -Force -Path $BackupDir) }
foreach ($f in @((Join-Path $HOME '.claude\settings.json'), (Join-Path $HOME '.claude\CLAUDE.md'))) {
  if (Test-Path -LiteralPath $f -PathType Leaf) {
    if ($DryRun) { Write-Info "[dry-run] copy $f" }
    else { Copy-Item -LiteralPath $f -Destination $BackupDir -Force; Write-Ok $f }
  }
}

Write-Step 'Node.js 확인'
if (Test-NodeVersion) {
  Write-Ok "Node.js $(& node -v)"
}
elseif (Test-Have 'node') {
  Stop-Script "Node.js $NodeMinMajor.$NodeMinMinor 이상이 필요합니다. 현재: $(& node -v)"
}
else {
  Stop-Script "Node.js $NodeMinMajor.$NodeMinMinor 이상을 먼저 설치하세요. (winget install OpenJS.NodeJS)"
}

Write-Step '스킬 설치'
# 설치 대상을 -a로 명시한다. -a가 없으면 skills CLI가 에이전트를 자동으로 찾고,
# 못 찾으면 질문하므로 -Yes 실행이 멈출 수 있다.
$agentArgs = @()
if ($HasClaude) {
  if ($Plugin) {
    if (-not (Test-Have 'claude')) { Stop-Script '-Plugin 방식은 claude CLI가 필요합니다. CLI를 설치하거나 -Plugin 없이 실행하세요.' }
    Write-Info 'Claude Code: 플러그인 방식'
    if (-not (Invoke-Cmd 'claude' @('plugin', 'marketplace', 'add', 'JuliusBrussee/caveman'))) {
      Add-Failure '플러그인 마켓플레이스 추가 실패'
    }
    if (-not (Invoke-Cmd 'claude' @('plugin', 'install', 'caveman@caveman'))) {
      Add-Failure '플러그인 설치 실패'
    }
  }
  else {
    $agentArgs += @('-a', 'claude-code')
  }
}
if ($HasCodex) { $agentArgs += @('-a', 'codex') }

if ($agentArgs.Count -gt 0) {
  $skillSel = if ($AllSkills) { @('--skill', '*') } else { @('--skill', 'caveman', '--skill', 'caveman-compress') }
  $skillArgs = @('--yes', 'skills', 'add', 'JuliusBrussee/caveman') + $skillSel + $agentArgs + @('-y', '-g')
  if (-not (Invoke-Cmd 'npx' $skillArgs)) { Add-Failure 'Caveman 스킬 설치 실패' }
}

Write-Step '결과'
if ($Failed.Count -gt 0) {
  Write-Err '실패한 단계가 있습니다:'
  foreach ($f in $Failed) { Write-Info "  - $f" }
}
else {
  Write-Ok '설치 완료'
}

Write-Host @'

    다음은 직접 확인하세요.
      1. 에이전트를 새 세션으로 시작합니다.
      2. 아무 코딩 질문을 합니다. 서두 없이 짧게 답하면 켜진 것입니다.
      3. 자동으로 켜지지 않으면 /caveman 을 입력합니다.
      4. npx skills ls -g 로 설치된 스킬을 확인합니다 (기본: caveman, caveman-compress).
      5. 며칠 쓴 뒤 npx ccusage@latest claude daily 로 설치 전과 비교합니다.

    모드: /caveman lite | full | ultra   끄기: stop caveman
    제거: .\uninstall.ps1
'@
Write-Info "백업: $BackupDir"
