#Requires -Version 5.1
<#
.SYNOPSIS
  Caveman 제거 (Windows)

.DESCRIPTION
  확인 기준: caveman v2.7.0 · 2026-09-29 · PowerShell 5.1 이상
  기본: Caveman 공식 제거 명령으로 스킬 등 설치한 것을 되돌립니다.
  -WithProxy: 직접 설치한 프록시 연결과 CLI(@caveman-ai/cli)까지 제거합니다.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$WithProxy,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '2026-09-29'
$BackupRoot    = Join-Path $HOME '.ai_tokens_backup'
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
Caveman 제거 (Windows)

  .\uninstall.ps1              Caveman 스킬 등 설치한 것 제거
  .\uninstall.ps1 -WithProxy   프록시 연결과 CLI까지 제거

옵션
  -Yes         확인 질문 없이 진행
  -DryRun      실행할 명령만 출력 (아무것도 바꾸지 않음)
  -WithProxy   caveman disable claude/codex + npm uninstall -g @caveman-ai/cli
  -Help        이 도움말
'@
}

if ($Help) { Show-Usage; exit 0 }

# ---------- 설치 흔적 검사 ----------
# Find-Leftovers        : 제거 전에 무엇이 설치돼 있는지 보여준다 (dry-run에서도 실행, 읽기만 함)
# Find-Leftovers -After : 제거 후 남은 것을 경고로 보여준다
# 찾은 개수는 $script:LeftCount 에 담긴다

$CodexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

# Caveman 저장소 skills/ 폴더의 스킬 이름 (2026-09-29, v2.7.0 기준)
$SkillNames = @(
  'caveman', 'cavecrew', 'caveman-commit', 'caveman-compress', 'caveman-discover',
  'caveman-evidence-review', 'caveman-explore', 'caveman-help', 'caveman-learn', 'caveman-manage',
  'caveman-optimize', 'caveman-review', 'caveman-setup', 'caveman-stats', 'investigate-first',
  'lean-build', 'megacave', 'migration', 'safe-refactor', 'surgical-patch', 'ultracave', 'verify-and-stop'
)
# 위 목록은 --skill '*'로 설치되는 22개 (2026-10-07 실제 설치로 확인, v2.7.0).
# 이름에 cave가 들어간 폴더는 목록에 없어도 함께 찾는다 (스킬이 늘어날 때 대비)

# 에이전트별 전역 스킬 폴더
#   Claude Code: .claude\skills
#   Codex: skills CLI는 .agents\skills 에 설치한다 (2026-10-07 실제 확인). .codex\skills 도 함께 본다
$ClaudeSkillDirs = @((Join-Path $HOME '.claude\skills'))
$CodexSkillDirs  = @((Join-Path $HOME '.agents\skills'), (Join-Path $CodexDir 'skills'))
$SkillDirs = $ClaudeSkillDirs + $CodexSkillDirs + @((Join-Path $HOME '.config\agents\skills'))

# 폴더들에 있는 Caveman 스킬 이름을 중복 없이 돌려준다
function Get-CavemanNames {
  param([string[]]$Dirs)
  $found = New-Object System.Collections.ArrayList
  foreach ($d in $Dirs) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    foreach ($n in $SkillNames) {
      if ((Test-Path -LiteralPath (Join-Path $d $n)) -and -not $found.Contains($n)) { [void]$found.Add($n) }
    }
    Get-ChildItem -LiteralPath $d -Filter '*cave*' -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not $found.Contains($_.Name)) { [void]$found.Add($_.Name) }
    }
  }
  # 이름을 하나씩 파이프라인으로 내보낸다. 받는 쪽은 @( )로 감싸 항상 배열로 쓴다
  $found.ToArray()
}

$script:LeftCount = 0
function Write-Found {
  param([string]$Text, [switch]$After)
  $script:LeftCount++
  if ($After) { Write-Warn $Text } else { Write-Info "- $Text" }
}

function Find-Leftovers {
  param([switch]$After)
  $script:LeftCount = 0
  foreach ($base in $SkillDirs) {
    foreach ($n in @(Get-CavemanNames @($base))) { Write-Found "스킬: $(Join-Path $base $n)" -After:$After }
  }
  $plugins = Join-Path $HOME '.claude\plugins'
  if (Test-Path -LiteralPath $plugins -PathType Container) {
    Get-ChildItem -LiteralPath $plugins -Recurse -Depth 3 -Filter '*caveman*' -ErrorAction SilentlyContinue |
      Select-Object -First 10 | ForEach-Object { Write-Found "플러그인: $($_.FullName)" -After:$After }
  }
  $settings = Join-Path $HOME '.claude\settings.json'
  if ((Test-Path -LiteralPath $settings -PathType Leaf) -and
      (Select-String -LiteralPath $settings -Pattern 'caveman' -SimpleMatch -Quiet)) {
    Write-Found '설정: .claude\settings.json 에 caveman 항목 (훅·상태줄)' -After:$After
  }
  $cli = Get-Command caveman -ErrorAction SilentlyContinue
  if ($cli) { Write-Found "CLI: $($cli.Source)" -After:$After }
}

# ---------- 실행 ----------

Write-Host "Caveman 제거 ($ScriptVersion)" -ForegroundColor White
if ($DryRun)    { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }
if ($WithProxy) { Write-Info '프록시 연결과 CLI까지 제거합니다.' }

Write-Step '현재 설치 상태 (제거 대상)'
Find-Leftovers
if ($script:LeftCount -eq 0) { Write-Ok '설치된 Caveman을 찾지 못했습니다.' }
else { Write-Info "총 $($script:LeftCount)개" }

Confirm-Continue

if ($WithProxy) {
  Write-Step '프록시 연결 해제와 CLI 제거'
  if (Test-Have 'caveman') {
    foreach ($agent in @('claude', 'codex')) {
      if (-not (Invoke-Cmd 'caveman' @('disable', $agent))) {
        Write-Warn "caveman disable $agent 실패 (연결된 적이 없으면 정상)"
      }
    }
  }
  else {
    Write-Info 'caveman CLI가 없어 프록시 연결 해제는 건너뜁니다.'
  }
  if (Test-Have 'npm') {
    if (-not (Invoke-Cmd 'npm' @('uninstall', '-g', '@caveman-ai/cli'))) {
      Add-Failure 'npm uninstall -g @caveman-ai/cli 실패'
    }
  }
  else {
    Write-Warn 'npm이 없어 CLI 제거를 건너뜁니다.'
  }
}
elseif (Test-Have 'caveman') {
  Write-Warn 'caveman CLI(프록시)가 설치되어 있습니다. 함께 지우려면 -WithProxy 로 다시 실행하세요.'
}

Write-Step '스킬 제거 (skills CLI)'
# Caveman 공식 제거 명령은 npx skills로 설치한 스킬을 지우지 않는다 (2026-10-07 실제 실행으로 확인).
# 그래서 에이전트별 스킬 폴더에 있는 Caveman 스킬만 골라 skills CLI로 지운다.
function Remove-SkillsFor {
  param([string]$Agent, [string[]]$Dirs)
  $names = @(Get-CavemanNames $Dirs)
  if ($names.Count -eq 0) { Write-Info "${Agent}: 지울 Caveman 스킬 없음"; return }
  $removeArgs = @('--yes', 'skills', 'remove', '-g', '-a', $Agent, '-y') + $names
  if (-not (Invoke-Cmd 'npx' $removeArgs)) { Add-Failure "$Agent 스킬 제거 실패" }
}
if (Test-Have 'npx') {
  Remove-SkillsFor 'claude-code' $ClaudeSkillDirs
  Remove-SkillsFor 'codex' $CodexSkillDirs
}
else {
  Add-Failure 'npx가 없어 스킬을 지울 수 없습니다. Node.js를 설치한 뒤 다시 실행하세요.'
}

Write-Step '나머지 제거 (Caveman 공식 제거 명령: 훅, 플러그인, MCP)'
if (Test-Have 'npx') {
  if (-not (Invoke-Cmd 'npx' @('-y', 'github:JuliusBrussee/caveman', '--', '--uninstall'))) {
    Add-Failure 'Caveman 제거 실패'
  }
}
else {
  Add-Failure 'npx가 없어 제거할 수 없습니다. Node.js를 설치한 뒤 다시 실행하세요.'
}

if (-not $DryRun) {
  Write-Step '제거 확인'
  Find-Leftovers -After
  if ($script:LeftCount -eq 0) {
    Write-Ok '남은 흔적이 없습니다.'
  }
  else {
    Write-Warn "위 $($script:LeftCount)개가 남아 있습니다."
    Write-Info "남은 줄·파일을 직접 지우거나 설치 전 백업($BackupRoot)에서 복원하세요."
    [void]$Failed.Add("제거 후 $($script:LeftCount)개 남음")
  }
}

Write-Step '결과'
if ($Failed.Count -gt 0) {
  Write-Err '실패한 단계가 있습니다:'
  foreach ($f in $Failed) { Write-Info "  - $f" }
}
elseif ($DryRun) {
  Write-Ok 'dry-run 완료 (실제로 지운 것은 없습니다)'
}
else {
  Write-Ok '제거 완료'
}

Write-Host @'

    참고
      - Claude Code 플러그인 방식(-Plugin)으로 설치했다면
        Claude Code의 /plugin 메뉴에서도 caveman이 지워졌는지 확인하세요.
      - 에이전트를 새 세션으로 시작해야 반영됩니다.
'@
Write-Info "설치 전 백업: $BackupRoot"
