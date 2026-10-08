#Requires -Version 5.1
<#
.SYNOPSIS
  RTK 제거 (Windows)

.DESCRIPTION
  확인 기준: RTK v0.50.0 · 2026-09-29 · PowerShell 5.1 이상
  순서: 설치 상태 표시 → Claude Code 연결 해제 → Codex 연결 해제 → 바이너리 삭제 → 제거 확인
    (바이너리를 먼저 지우면 rtk 명령이 없어 연결 해제를 못 하므로 이 순서를 지킨다)

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$KeepBinary,
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
RTK 제거 (Windows)

  .\uninstall.ps1               연결 해제 + 바이너리 삭제
  .\uninstall.ps1 -KeepBinary   연결만 해제하고 rtk 바이너리는 남김

옵션
  -Yes          확인 질문 없이 진행
  -DryRun       실행할 명령만 출력 (아무것도 바꾸지 않음)
  -KeepBinary   rtk 바이너리는 지우지 않음
  -Help         이 도움말
'@
}

if ($Help) { Show-Usage; exit 0 }

# ---------- 설치 흔적 검사 ----------
# Find-Leftovers        : 제거 전에 무엇이 설치돼 있는지 보여준다 (dry-run에서도 실행, 읽기만 함)
# Find-Leftovers -After : 제거 후 남은 것을 경고로 보여준다
# 찾은 개수는 $script:LeftCount 에 담긴다

$CodexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }

$script:LeftCount = 0
function Write-Found {
  param([string]$Text, [switch]$After)
  $script:LeftCount++
  if ($After) { Write-Warn $Text } else { Write-Info "- $Text" }
}

function Find-Leftovers {
  param([switch]$After)
  $script:LeftCount = 0
  $textChecks = @(
    @{ Label = 'Claude Code 훅';   Path = (Join-Path $HOME '.claude\settings.json'); Pattern = 'rtk hook|rtk-rewrite' },
    @{ Label = 'Claude Code 참조'; Path = (Join-Path $HOME '.claude\CLAUDE.md');     Pattern = '@\S*RTK\.md' },
    @{ Label = 'Codex 훅';         Path = (Join-Path $CodexDir 'hooks.json');        Pattern = 'rtk hook' },
    @{ Label = 'Codex 참조';       Path = (Join-Path $CodexDir 'AGENTS.md');         Pattern = '@\S*RTK\.md' }
  )
  foreach ($c in $textChecks) {
    if (-not (Test-Path -LiteralPath $c.Path -PathType Leaf)) { continue }
    $hits = @(Select-String -LiteralPath $c.Path -Pattern $c.Pattern -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) { continue }
    Write-Found "$($c.Label): $($c.Path)" -After:$After
    if ($After) {
      $hits | Select-Object -First 5 | ForEach-Object { Write-Info ("      {0}: {1}" -f $_.LineNumber, $_.Line.Trim()) }
    }
  }
  foreach ($f in @(@{ Label = 'Claude Code 파일'; Path = (Join-Path $HOME '.claude\RTK.md') },
                   @{ Label = 'Codex 파일';       Path = (Join-Path $CodexDir 'RTK.md') })) {
    if (Test-Path -LiteralPath $f.Path -PathType Leaf) { Write-Found "$($f.Label): $($f.Path)" -After:$After }
  }
  # 바이너리 (제거 후 검사에서 -KeepBinary면 남는 게 정상이므로 세지 않음)
  $bin = Get-Command rtk -ErrorAction SilentlyContinue
  if ($bin -and (-not $KeepBinary)) { Write-Found "바이너리: $($bin.Source)" -After:$After }
  elseif ($bin -and (-not $After)) { Write-Info "- 바이너리: $($bin.Source) (-KeepBinary: 남김)" }
}

# ---------- 실행 ----------

Write-Host "RTK 제거 ($ScriptVersion, windows)" -ForegroundColor White
if ($DryRun)     { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }
if ($KeepBinary) { Write-Info '바이너리는 남깁니다 (-KeepBinary).' }

Write-Step '현재 설치 상태 (제거 대상)'
Find-Leftovers
if ($script:LeftCount -eq 0) { Write-Ok '설치된 RTK를 찾지 못했습니다.' }
else { Write-Info "총 $($script:LeftCount)개" }

Confirm-Continue

Write-Step 'Claude Code 연결 해제'
if (Test-Have 'rtk') {
  if (-not (Invoke-Cmd 'rtk' @('init', '-g', '--uninstall'))) { Add-Failure 'rtk init -g --uninstall 실패' }
}
else {
  Write-Info 'rtk가 없어 건너뜁니다.'
}

Write-Step 'Codex 연결 해제'
if (Test-Path -LiteralPath $CodexDir -PathType Container) {
  if (Test-Have 'rtk') {
    if (-not (Invoke-Cmd 'rtk' @('init', '-g', '--codex', '--uninstall'))) {
      Add-Failure 'rtk init -g --codex --uninstall 실패'
    }
  }
  else {
    Write-Info 'rtk가 없어 건너뜁니다.'
  }
}
else {
  Write-Info "$CodexDir 가 없어 건너뜁니다."
}

if (-not $KeepBinary) {
  Write-Step '바이너리 삭제'
  if (-not (Test-Have 'rtk') -and -not $DryRun) {
    Write-Info 'rtk 바이너리가 없습니다.'
  }
  elseif (Test-Have 'winget') {
    if (-not (Invoke-Cmd 'winget' @('uninstall', '--id', 'rtk-ai.rtk', '-e'))) {
      $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
      $where = if ($rtkCmd) { $rtkCmd.Source } else { '(위치 모름)' }
      Write-Warn "winget으로 설치한 게 아니면 rtk.exe를 직접 지우세요: $where"
    }
  }
  else {
    $rtkCmd = Get-Command rtk -ErrorAction SilentlyContinue
    $where = if ($rtkCmd) { $rtkCmd.Source } else { '(위치 모름)' }
    Write-Warn "winget이 없어 rtk.exe를 직접 지우세요: $where"
  }
}

if (-not $DryRun) {
  Write-Step '제거 확인'
  Find-Leftovers -After
  if ($script:LeftCount -eq 0) {
    Write-Ok '남은 흔적이 없습니다.'
  }
  else {
    Write-Warn "위 $($script:LeftCount)개가 남아 있습니다. rtk가 v0.50.0 이전이면 Codex 제거를 지원하지 않을 수 있습니다."
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
      - Claude Code와 Codex를 재시작해야 반영됩니다.
      - 설정이 꼬였다면 백업에서 복원하세요.
          RTK가 만든 백업: %USERPROFILE%\.claude\settings.json.bak
'@
Write-Info "설치 스크립트 백업: $BackupRoot"
