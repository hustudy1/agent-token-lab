#Requires -Version 5.1
<#
.SYNOPSIS
  RTK 설치 (Windows)

.DESCRIPTION
  확인 기준: RTK v0.50.0 · 2026-09-29 · PowerShell 5.1 이상
  설치 방식: winget (rtk-ai.rtk)
  연결: Claude Code와 Codex 모두 PreToolUse 훅 (Codex 훅은 v0.50.0부터)
  제거: .\uninstall.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [switch]$NoCodex,
  [switch]$HookOnly,
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptVersion = '2026-09-29'
$BackupRoot    = Join-Path $HOME '.ai_tokens_backup'
$BackupDir     = Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-rtk')
$Failed        = New-Object System.Collections.ArrayList
$CodexDir      = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$CodexHookMin  = [version]'0.50.0'

# "rtk 0.50.0" 같은 출력에서 버전만 꺼낸다. 실패하면 $null
function Get-RtkVersion {
  $ErrorActionPreference = 'Continue'   # 함수 안에서만 적용
  $raw = (& rtk --version 2>$null) -join ' '
  if ($raw -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
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
  try { & $File @Arguments } finally { $ErrorActionPreference = $prev }
  return ($LASTEXITCODE -eq 0)
}

function Confirm-Continue {
  if ($Yes -or $DryRun) { return }
  Write-Host ''
  $answer = Read-Host '계속할까요? [y/N]'
  if ($answer -notmatch '^(y|Y|yes|YES)$') { Stop-Script '사용자가 취소했습니다.' }
}

# winget으로 설치한 직후에는 현재 세션 PATH에 반영되지 않으므로 레지스트리 값으로 다시 읽는다
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$machine;$user"
}

function Show-Usage {
  Write-Host @'
RTK 설치 (Windows)

  .\install.ps1              RTK 설치 + Claude Code(와 Codex) 연결
  .\uninstall.ps1            제거

옵션
  -Yes        확인 질문 없이 진행
  -DryRun     실행할 명령만 출력 (아무것도 바꾸지 않음)
  -NoCodex    Codex는 건드리지 않음
  -HookOnly   Claude Code에 훅만 등록 (.claude\CLAUDE.md에 @RTK.md를 넣지 않음)
  -Help       이 도움말

바꾸는 파일
  %USERPROFILE%\.claude\settings.json   PreToolUse 훅 등록 (RTK가 .bak 백업을 만듦)
  %USERPROFILE%\.claude\CLAUDE.md       @RTK.md 한 줄 추가 (-HookOnly면 안 함)
  %USERPROFILE%\.claude\RTK.md          10줄 파일 생성 (-HookOnly면 안 함)
  %USERPROFILE%\.codex\hooks.json       Codex PreToolUse 훅 등록 (Codex가 있을 때)
  %USERPROFILE%\.codex\AGENTS.md        @RTK.md 한 줄 추가 (Codex가 있을 때)
  %USERPROFILE%\.codex\RTK.md           RTK가 만드는 파일 (Codex가 있을 때)
                                        (CODEX_HOME 환경변수가 있으면 그 폴더)

  바꾸기 전에 %USERPROFILE%\.ai_tokens_backup\<타임스탬프>-rtk\ 로 백업합니다.

주의
  rtk.exe를 더블클릭하지 마세요. 항상 터미널에서 실행합니다.
'@
}

if ($Help) { Show-Usage; exit 0 }

# Claude Code: CLI가 있거나 .claude 폴더가 있으면 사용 중으로 본다
# (VS Code 확장만 쓰면 claude 명령이 PATH에 없을 수 있다. 설정 폴더는 CLI와 확장이 같이 쓴다)
$HasClaude = (Test-Have 'claude') -or (Test-Path -LiteralPath (Join-Path $HOME '.claude') -PathType Container)
$HasCodex  = (Test-Have 'codex') -and (-not $NoCodex)

# ---------- 실행 ----------

Write-Host "RTK 설치 ($ScriptVersion, windows)" -ForegroundColor White
if ($DryRun) { Write-Info 'dry-run: 아무것도 바꾸지 않습니다.' }
$claudeText = if ($HasClaude) { '있음' } else { '없음' }
$codexText  = if ($HasCodex)  { '있음' } else { '없음' }
Write-Info "대상: Claude Code=$claudeText, Codex=$codexText"
if ($HookOnly) { Write-Info 'Claude Code: 훅만 등록 (-HookOnly)' }
if (-not $HasClaude -and -not $HasCodex) {
  Write-Warn 'claude도 codex도 찾지 못했습니다. 바이너리만 설치하고 연결은 건너뜁니다.'
}

Confirm-Continue

Write-Step '설정 백업'
Write-Info "위치: $BackupDir"
if ($DryRun) { Write-Info "[dry-run] mkdir $BackupDir" }
else { [void](New-Item -ItemType Directory -Force -Path $BackupDir) }
$targets = @(
  (Join-Path $HOME '.claude\settings.json'),
  (Join-Path $HOME '.claude\CLAUDE.md'),
  (Join-Path $CodexDir 'AGENTS.md'),
  (Join-Path $CodexDir 'hooks.json'),
  (Join-Path $CodexDir 'config.toml')
)
foreach ($f in $targets) {
  if (Test-Path -LiteralPath $f -PathType Leaf) {
    if ($DryRun) { Write-Info "[dry-run] copy $f" }
    else { Copy-Item -LiteralPath $f -Destination $BackupDir -Force; Write-Ok $f }
  }
}

Write-Step '바이너리 설치'
if (Test-Have 'rtk') {
  Write-Ok '이미 설치됨'
}
elseif (Test-Have 'winget') {
  $wingetArgs = @('install', '--id', 'rtk-ai.rtk', '-e', '--accept-package-agreements', '--accept-source-agreements')
  if (-not (Invoke-Cmd 'winget' $wingetArgs)) { Stop-Script 'winget install rtk-ai.rtk 실패' }
  if (-not $DryRun) { Update-SessionPath }
}
else {
  Stop-Script 'winget이 없습니다. https://github.com/rtk-ai/rtk/releases 에서 rtk-x86_64-pc-windows-msvc.zip 을 내려받아 PATH에 넣고 다시 실행하세요.'
}

Write-Step '설치 확인'
if ($DryRun) {
  Write-Info '[dry-run] rtk --version; rtk gain'
}
else {
  if (-not (Test-Have 'rtk')) { Stop-Script 'rtk 명령을 찾을 수 없습니다. 새 터미널을 열고 다시 실행하세요.' }
  $global:LASTEXITCODE = 0
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & rtk gain *> $null
  $ErrorActionPreference = $prev
  if ($LASTEXITCODE -ne 0) {
    Stop-Script 'rtk gain이 실패했습니다. 다른 프로젝트의 rtk일 수 있습니다(crates.io의 Rust Type Kit).'
  }
  Write-Ok "$(& rtk --version)"
}
if (-not (Test-Have 'rg')) {
  Write-Warn 'ripgrep(rg)이 없으면 일부 필터가 경고를 냅니다. 설치 권장: winget install BurntSushi.ripgrep.MSVC'
}

if ($HasClaude) {
  Write-Step 'Claude Code 연결'
  if ($HookOnly) {
    # -HookOnly와 --auto-patch를 함께 쓰는 조합은 README에 없어서, 실패하면 질문 방식으로 다시 시도한다
    $ok = Invoke-Cmd 'rtk' @('init', '-g', '--hook-only', '--auto-patch')
    if (-not $ok) { $ok = Invoke-Cmd 'rtk' @('init', '-g', '--hook-only') }
    if (-not $ok) { Add-Failure 'rtk init -g --hook-only 실패' }
  }
  else {
    if (-not (Invoke-Cmd 'rtk' @('init', '-g', '--auto-patch'))) { Add-Failure 'rtk init -g --auto-patch 실패' }
  }
  if (-not $DryRun) {
    $global:LASTEXITCODE = 0
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & rtk init --show
    $ErrorActionPreference = $prev
    if ($LASTEXITCODE -ne 0) { Write-Warn 'rtk init --show 결과를 확인하세요.' }
  }
}
else {
  Write-Warn 'claude 명령이 없어 Claude Code 연결은 건너뜁니다.'
}

if ($HasCodex) {
  Write-Step 'Codex 연결'
  if (-not $DryRun) {
    $ver = Get-RtkVersion
    if (($null -eq $ver) -or ($ver -lt $CodexHookMin)) {
      Write-Warn "rtk $ver 은 Codex 훅을 지원하지 않습니다 (v$CodexHookMin 부터)."
      Write-Warn '이 버전은 AGENTS.md 지시문만 넣습니다. 업데이트 권장: winget upgrade rtk-ai.rtk'
    }
  }
  Write-Info "$CodexDir 에 hooks.json 훅, AGENTS.md(@RTK.md), RTK.md를 씁니다."
  if (-not (Invoke-Cmd 'rtk' @('init', '-g', '--codex'))) { Add-Failure 'rtk init -g --codex 실패' }
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
      - 새 터미널에서 Claude Code를 시작합니다 (훅과 CLAUDE.md는 새 세션부터 적용).
      - Claude Code에서 git status 실행을 요청 → rtk git status로 바뀌는지 확인합니다.
      - 며칠 쓴 뒤 npx ccusage@latest claude daily 로 설치 전과 비교합니다.

    주의: rtk gain 수치는 RTK의 자체 추정이지 청구액이 아닙니다.
    제거: .\uninstall.ps1
'@
if ($HasCodex) {
  Write-Info '  - Codex를 재시작합니다. 훅 신뢰 확인이 나오면 승인하세요 (/hooks 에서도 확인 가능).'
  Write-Info '    Codex에서 git status 실행을 요청 → rtk git status로 바뀌는지 확인합니다.'
}
Write-Info "백업: $BackupDir"
