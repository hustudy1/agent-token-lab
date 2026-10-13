#Requires -Version 5.1
<#
.SYNOPSIS
  agent-token-lab 설정 (Windows)

.DESCRIPTION
  setup.bat 을 더블클릭하거나 아래처럼 실행합니다.
    powershell -ExecutionPolicy Bypass -File .\setup.ps1                 메뉴에서 고르기
    powershell -ExecutionPolicy Bypass -File .\setup.ps1 caveman -Yes    메뉴 없이 바로 실행

  명령: caveman | rtk | all | status | remove-caveman | remove-rtk | remove-all
        usage | sessions | context [프로젝트 폴더] | gain | results
  설치·제거 로직은 Caveman\scripts, RTK\scripts 의 스크립트에 있고, 이 파일은 그것을 불러 쓴다.
  실행 순서: 계획 보여주기(dry-run) → 확인 → 실행. -Yes 를 주면 확인 없이 진행한다.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('', 'caveman', 'rtk', 'all', 'status', 'remove-caveman', 'remove-rtk', 'remove-all',
               'usage', 'sessions', 'context', 'gain', 'results')]
  [string]$Command = '',
  # context 명령에서 함께 점검할 프로젝트 폴더
  [Parameter(Position = 1)]
  [string]$Path = '',
  [switch]$Yes
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

function Write-Title { param([string]$Text) Write-Host ''; Write-Host $Text -ForegroundColor White }
function Write-Info  { param([string]$Text) Write-Host "  $Text" }
function Write-Ok    { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn  { param([string]$Text) Write-Host "  [주의] $Text" -ForegroundColor Yellow }
function Test-Have   { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ---------- 상태 확인 ----------

function Show-Status {
  Write-Title '설치 상태'
  $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  $lines = @()
  foreach ($d in @(([IO.Path]::Combine($HOME, '.claude', 'skills')), ([IO.Path]::Combine($HOME, '.agents', 'skills')), (Join-Path $codexDir 'skills'))) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    $names = @(Get-ChildItem -LiteralPath $d -Filter '*cave*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($names.Count -gt 0) { $lines += "    ${d}: $($names -join ' ')" }
  }
  if ($lines.Count -gt 0) { Write-Ok 'Caveman 스킬:'; $lines | ForEach-Object { Write-Host $_ } }
  else { Write-Info 'Caveman: 설치 안 됨' }

  $rtk = Get-Command rtk -ErrorAction SilentlyContinue
  if ($rtk) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $ver = (& rtk --version 2>$null) -join ' '
    $ErrorActionPreference = $prev
    Write-Ok "RTK: $ver ($($rtk.Source))"
    $settings = [IO.Path]::Combine($HOME, '.claude', 'settings.json')
    if ((Test-Path -LiteralPath $settings) -and (Select-String -LiteralPath $settings -Pattern 'rtk hook' -SimpleMatch -Quiet)) {
      Write-Ok 'RTK Claude Code 훅: 연결됨'
    }
    else { Write-Warn 'RTK Claude Code 훅: 연결 안 됨' }
    $hooks = Join-Path $codexDir 'hooks.json'
    if ((Test-Path -LiteralPath $hooks) -and (Select-String -LiteralPath $hooks -Pattern 'rtk hook' -SimpleMatch -Quiet)) {
      Write-Ok 'RTK Codex 훅: 연결됨'
    }
  }
  else { Write-Info 'RTK: 설치 안 됨' }

  if (Test-Have 'claude') { Write-Info 'Claude Code: CLI 있음' }
  elseif (Test-Path -LiteralPath (Join-Path $HOME '.claude') -PathType Container) { Write-Info 'Claude Code: VS Code 확장 등 (.claude 있음)' }
  if (Test-Have 'codex') { Write-Info 'Codex: CLI 있음' }
}

# ---------- 사용량·절약 ----------
# setup.sh 의 tools/usage_report.py 와 같은 내용을 PowerShell로 구현 (Windows에는 python이 없는 경우가 많음)

$Weight = @{ read = 0.1; write = 1.25; output = 5.0; input = 1.0 }

# 화면 폭 기준 왼쪽 정렬 (한글 등 전각 문자는 2칸)
function Format-Pad {
  param([string]$Text, [int]$Width)
  $w = 0
  foreach ($ch in $Text.ToCharArray()) { if ([int]$ch -ge 0x1100) { $w += 2 } else { $w += 1 } }
  return $Text + (' ' * [Math]::Max(0, $Width - $w))
}

# 대략적인 토큰 수 (추정): 영문·기호 4글자당 1, 한글 등 그 밖의 글자 1.5글자당 1
function Get-TokenEstimate {
  param([string]$Text)
  $ascii = 0
  foreach ($ch in $Text.ToCharArray()) { if ([int]$ch -lt 128) { $ascii++ } }
  return [int]($ascii / 4 + ($Text.Length - $ascii) / 1.5)
}

function Get-SinceDate { return (Get-Date).AddDays(-30).ToString('yyyyMMdd') }

# ccusage 를 실행해 JSON을 돌려준다. 실패하면 $null
function Invoke-CcusageJson {
  param([string[]]$Arguments)
  if (-not (Test-Have 'npx')) { Write-Warn 'npx가 없어 사용량을 볼 수 없습니다. Node.js를 설치하세요.'; return $null }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $raw = (& npx --yes ccusage@latest @Arguments --json 2>$null) -join "`n" }
  finally { $ErrorActionPreference = $prev }
  try { return ($raw | ConvertFrom-Json) } catch { Write-Info '사용 기록을 읽지 못했습니다.'; return $null }
}

function Show-Daily {
  Write-Title '일별 사용량 (최근 30일)'
  if (-not (Test-Have 'npx')) { Write-Warn 'npx가 없어 사용량을 볼 수 없습니다. Node.js를 설치하세요.'; return }
  Write-Info 'ccusage가 이 컴퓨터의 Claude Code 기록(로컬 파일)을 읽습니다. 처음에는 내려받느라 시간이 걸립니다.'
  $since = Get-SinceDate
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    & npx --yes ccusage@latest claude daily --since $since | Out-Host
    if (Test-Have 'codex') {
      Write-Title 'Codex 일별 사용량 (최근 30일)'
      & npx --yes ccusage@latest codex daily --since $since | Out-Host
    }
  }
  finally { $ErrorActionPreference = $prev }
  Write-Info 'Cost는 API 단가로 환산한 값입니다. 구독이면 실제로는 사용 한도에서 차감됩니다.'
}

function Show-Mix {
  Write-Title '사용량 구성 (최근 30일)'
  $d = Invoke-CcusageJson @('claude', 'daily', '--since', (Get-SinceDate))
  if ($null -eq $d) { return }
  $t = $d.totals
  $rows = @(
    @('캐시 읽기 (매 턴 이전 대화 다시 읽기)', [double]$t.cacheReadTokens, $Weight.read),
    @('캐시 쓰기 (새 내용 저장)', [double]$t.cacheCreationTokens, $Weight.write),
    @('출력 (모델이 쓴 글)', [double]$t.outputTokens, $Weight.output),
    @('입력 (캐시 안 된 입력)', [double]$t.inputTokens, $Weight.input)
  )
  $tok = 0; $cost = 0
  foreach ($r in $rows) { $tok += $r[1]; $cost += $r[1] * $r[2] }
  if ($tok -eq 0) { Write-Info '기록이 없습니다.'; return }
  Write-Host ('  ' + (Format-Pad '항목' 40) + (Format-Pad '토큰' 16) + (Format-Pad '토큰 비율' 12) + '비용 비율(추정)')
  foreach ($r in $rows) {
    Write-Host ('  ' + (Format-Pad $r[0] 40) + (Format-Pad ('{0:N0}' -f $r[1]) 16) +
      (Format-Pad ('{0:N1}%' -f ($r[1] / $tok * 100)) 12) + ('{0:N1}%' -f ($r[1] * $r[2] / $cost * 100)))
  }
  $ctx = ($rows[0][1] * $Weight.read + $rows[1][1] * $Weight.write) / $cost * 100
  $out = $rows[2][1] * $Weight.output / $cost * 100
  Write-Host ''
  Write-Info '비용 비율은 가격 비율(캐시 읽기 0.1, 캐시 쓰기 1.25, 출력 5, 입력 1)로 추정한 값입니다.'
  Write-Info ('- 컨텍스트(캐시 읽기+쓰기)가 비용의 약 {0:N0}%입니다. 가장 큰 절약 지점입니다.' -f $ctx)
  Write-Info "  주제가 바뀌면 /clear 로 새 대화를 시작하고, 상시 로딩을 줄이세요 (메뉴의 '상시 로딩 점검')."
  Write-Info ('- 출력은 비용의 약 {0:N0}%입니다. Caveman이 줄일 수 있는 건 이 부분뿐입니다.' -f $out)
  Write-Info ('총합: {0:N0} 토큰, API 단가 환산 ${1:N2}' -f [double]$t.totalTokens, [double]$t.totalCost)
}

function Show-Sessions {
  Write-Title '사용량이 큰 대화(세션) 상위 10개 (최근 30일)'
  $d = Invoke-CcusageJson @('claude', 'session', '--since', (Get-SinceDate))
  if ($null -eq $d -or -not $d.sessions) { Write-Info '기록이 없습니다.'; return }
  $all = @($d.sessions | Sort-Object -Property totalCost -Descending)
  $total = ($all | Measure-Object -Property totalCost -Sum).Sum
  if (-not $total) { $total = 1 }
  Write-Host ('  ' + (Format-Pad '#' 4) + (Format-Pad '마지막 활동(현지)' 18) + (Format-Pad '비용($)' 10) +
    (Format-Pad '캐시 읽기' 15) + (Format-Pad '출력' 10) + '프로젝트')
  $i = 0
  foreach ($s in ($all | Select-Object -First 10)) {
    $i++
    # ccusage는 경로의 구분자를 - 로 바꿔 저장한다. 홈 폴더 부분만 ~/ 로 줄여 보여준다 (근사)
    $proj = [string]$s.projectPath -replace '^(-Users-|-home-|C--Users-)[^-]+-', '~/'
    # PowerShell 7은 JSON 날짜를 DateTime으로 자동 변환하고 5.1은 문자열로 둔다. 둘 다 현지 시각으로 맞춘다
    $la = $s.lastActivity
    if ($la -is [datetime]) { $dt = if ($la.Kind -eq 'Local') { $la } else { $la.ToLocalTime() } }
    else { try { $dt = ([DateTimeOffset]::Parse([string]$la)).LocalDateTime } catch { $dt = $null } }
    $when = if ($dt) { $dt.ToString('yyyy-MM-dd HH:mm') } else { [string]$la }
    Write-Host ('  ' + (Format-Pad "$i" 4) + (Format-Pad $when 18) + (Format-Pad ('{0:N2}' -f [double]$s.totalCost) 10) +
      (Format-Pad ('{0:N0}' -f [double]$s.cacheReadTokens) 15) + (Format-Pad ('{0:N0}' -f [double]$s.outputTokens) 10) + $proj)
  }
  $top = ($all | Select-Object -First 10 | Measure-Object -Property totalCost -Sum).Sum
  Write-Host ''
  Write-Info ('전체 {0}개 대화 중 상위 10개가 비용의 {1:N0}%입니다.' -f $all.Count, ($top / $total * 100))
  Write-Info '비싼 대화는 대개 오래 이어진 대화입니다. 매 턴 앞의 대화를 전부 다시 읽기 때문입니다.'
  Write-Info '주제가 바뀌면 /clear 로 새로 시작하는 것이 가장 확실한 절약입니다.'
}

function Show-Context {
  param([string]$Project = '')
  Write-Title '상시 로딩 점검 (매 세션 항상 실리는 것)'
  $script:CtxTotal = 0
  $tips = New-Object System.Collections.ArrayList

  function Write-FileRow {
    param([string]$Label, [string]$Path, [string]$Note = '', [int]$Depth = 0)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $text = [IO.File]::ReadAllText($Path)
    $n = Get-TokenEstimate $text
    $script:CtxTotal += $n
    $lines = ($text -split "`n").Count
    if ($text.EndsWith("`n")) { $lines-- }
    $short = $Path.Replace($HOME, '~')
    Write-Host ('  ' + (Format-Pad $Label 26) + (Format-Pad "${lines}줄" 8) + (Format-Pad ('{0:N0}바이트' -f [Text.Encoding]::UTF8.GetByteCount($text)) 14) +
      (Format-Pad ('약 {0:N0}토큰' -f $n) 14) + $short + $Note)
    if ([IO.Path]::GetFileName($Path) -eq 'CLAUDE.md' -and $lines -gt 200) {
      [void]$tips.Add("$short 가 ${lines}줄입니다. 공식 권장은 200줄 미만입니다. 특정 작업용 지시는 스킬로 옮기세요.")
    }
    if ($Depth -lt 3) {
      foreach ($m in [regex]::Matches($text, '(?m)^@(\S+)')) {
        $ref = $m.Groups[1].Value
        if ($ref.StartsWith('~')) { $ref = $HOME + $ref.Substring(1) }
        if (-not [IO.Path]::IsPathRooted($ref)) { $ref = [IO.Path]::Combine([IO.Path]::GetDirectoryName($Path), $ref) }
        [void](Write-FileRow '  └ @import' ([IO.Path]::GetFullPath($ref)) ' (시작할 때 함께 로딩)' ($Depth + 1))
      }
    }
    return $true
  }

  Write-Host '[Claude Code]'
  [void](Write-FileRow '전역 CLAUDE.md' ([IO.Path]::Combine($HOME, '.claude', 'CLAUDE.md')))
  $rulesDir = [IO.Path]::Combine($HOME, '.claude', 'rules')
  if (Test-Path -LiteralPath $rulesDir) {
    foreach ($r in @(Get-ChildItem -LiteralPath $rulesDir -Filter '*.md' -ErrorAction SilentlyContinue)) {
      $head = [IO.File]::ReadAllText($r.FullName)
      if ($head.Length -gt 500) { $head = $head.Substring(0, 500) }
      if ($head -match '(?m)^paths:') { Write-Host ('  ' + (Format-Pad '규칙 (필요할 때만)' 26) + $r.FullName.Replace($HOME, '~')) }
      else { [void](Write-FileRow '규칙 (항상)' $r.FullName) }
    }
  }

  if ($Project) {
    if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
      Write-Warn "프로젝트 폴더가 없습니다: $Project (전역 설정만 점검합니다)"; $Project = ''
    }
    else { $Project = (Resolve-Path -LiteralPath $Project).Path }
  }
  if ($Project) {
    $hasClaude = $false
    foreach ($name in @('CLAUDE.md', [IO.Path]::Combine('.claude', 'CLAUDE.md'), 'CLAUDE.local.md')) {
      if (Write-FileRow "프로젝트 $name" ([IO.Path]::Combine($Project, $name))) { $hasClaude = $true }
    }
    $agents = [IO.Path]::Combine($Project, 'AGENTS.md')
    if (Test-Path -LiteralPath $agents) {
      if ($hasClaude) {
        Write-Host ('  ' + (Format-Pad '프로젝트 AGENTS.md' 26) + 'CLAUDE.md가 있어 Claude Code는 기본으로 읽지 않음 (Codex는 읽음)')
        $claudeText = ''
        foreach ($name in @('CLAUDE.md', [IO.Path]::Combine('.claude', 'CLAUDE.md'))) {
          $p = [IO.Path]::Combine($Project, $name)
          if (Test-Path -LiteralPath $p) { $claudeText += [IO.File]::ReadAllText($p) }
        }
        if ($claudeText -notmatch '@AGENTS\.md') {
          [void]$tips.Add("이 프로젝트는 CLAUDE.md가 있어 Claude Code가 AGENTS.md를 읽지 않습니다. 같은 지시를 쓰려면 CLAUDE.md에 '@AGENTS.md' 한 줄을 넣으세요 (링크만으로는 자동으로 읽지 않음).")
        }
      }
      else { [void](Write-FileRow '프로젝트 AGENTS.md' $agents ' (CLAUDE.md가 없어 Claude Code도 읽음)') }
    }
  }

  $skillsDir = [IO.Path]::Combine($HOME, '.claude', 'skills')
  $skills = @()
  if (Test-Path -LiteralPath $skillsDir) {
    $skills = @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue |
      Where-Object { Test-Path -LiteralPath ([IO.Path]::Combine($_.FullName, 'SKILL.md')) })
  }
  $desc = 0
  foreach ($sk in $skills) {
    $text = [IO.File]::ReadAllText([IO.Path]::Combine($sk.FullName, 'SKILL.md'))
    $fm = [regex]::Match($text, '(?s)^---\r?\n(.*?)\r?\n---')
    if ($fm.Success) {
      $dm = [regex]::Match($fm.Groups[1].Value, '(?ms)^description:\s*[>|]?\s*(.*?)(?=^[\w-]+:|\z)')
      if ($dm.Success) { $desc += Get-TokenEstimate $dm.Groups[1].Value }
    }
  }
  $script:CtxTotal += $desc
  Write-Host ('  ' + (Format-Pad '스킬 이름·설명' 26) + (Format-Pad "$($skills.Count)개" 22) + (Format-Pad ('약 {0:N0}토큰' -f $desc) 14) + '~/.claude/skills (본문은 쓸 때만 로딩)')
  if ($skills.Count -gt 10) {
    [void]$tips.Add("스킬이 $($skills.Count)개입니다. 설명이 매 세션 실립니다. 안 쓰는 스킬은 지우거나 /skills 에서 'Name only'로 바꾸세요.")
  }

  $mcp = [ordered]@{}
  $cjPath = [IO.Path]::Combine($HOME, '.claude.json')
  if (Test-Path -LiteralPath $cjPath) {
    try {
      $cj = [IO.File]::ReadAllText($cjPath) | ConvertFrom-Json
      if ($cj.PSObject.Properties['mcpServers'] -and $cj.mcpServers) { foreach ($p in $cj.mcpServers.PSObject.Properties) { $mcp[$p.Name] = '전역' } }
      if ($Project -and $cj.PSObject.Properties['projects'] -and $cj.projects.PSObject.Properties[$Project]) {
        $pj = $cj.projects.PSObject.Properties[$Project].Value
        if ($pj.PSObject.Properties['mcpServers'] -and $pj.mcpServers) { foreach ($p in $pj.mcpServers.PSObject.Properties) { $mcp[$p.Name] = '이 프로젝트' } }
      }
    } catch { }
  }
  if ($Project) {
    $mj = [IO.Path]::Combine($Project, '.mcp.json')
    if (Test-Path -LiteralPath $mj) {
      try {
        $m = [IO.File]::ReadAllText($mj) | ConvertFrom-Json
        if ($m.PSObject.Properties['mcpServers'] -and $m.mcpServers) { foreach ($p in $m.mcpServers.PSObject.Properties) { $mcp[$p.Name] = '.mcp.json' } }
      } catch { }
    }
  }
  $names = @($mcp.Keys | ForEach-Object { "$_($($mcp[$_]))" }) -join ', '
  if (-not $names) { $names = '-' }
  Write-Host ('  ' + (Format-Pad 'MCP 서버' 26) + (Format-Pad "$($mcp.Count)개" 8) + $names)
  if ($mcp.Count -gt 0) {
    [void]$tips.Add("MCP 서버 $($mcp.Count)개: 도구 정의는 기본으로 필요할 때만 로딩되지만, 안 쓰는 서버는 /mcp 에서 끄세요. 가능하면 CLI 도구(gh 등)가 더 가볍습니다.")
  }

  $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { [IO.Path]::Combine($HOME, '.codex') }
  if (Test-Path -LiteralPath $codexDir -PathType Container) {
    Write-Host ''
    Write-Host '[Codex]'
    foreach ($name in @('AGENTS.override.md', 'AGENTS.md')) { [void](Write-FileRow "전역 $name" ([IO.Path]::Combine($codexDir, $name))) }
    $cfg = [IO.Path]::Combine($codexDir, 'config.toml')
    $n = 0
    if (Test-Path -LiteralPath $cfg) { $n = [regex]::Matches([IO.File]::ReadAllText($cfg), '(?m)^\[mcp_servers\.[^.\]]+\]').Count }
    Write-Host ('  ' + (Format-Pad 'MCP 서버 (config.toml)' 26) + "${n}개")
  }

  Write-Host ''
  Write-Info ('상시 로딩 합계 (추정): 약 {0:N0}토큰. 시스템 프롬프트·도구 정의(보통 수천~수만 토큰)는 빠진 값입니다.' -f $script:CtxTotal)
  Write-Info '정확한 수치는 Claude Code 안에서 /context 로 확인하세요.'
  if (-not $Project) { Write-Info '프로젝트별 CLAUDE.md·AGENTS.md도 보려면: setup.bat context <프로젝트 폴더>' }
  if ($tips.Count -gt 0) {
    Write-Host ''
    Write-Info '줄일 수 있는 곳'
    foreach ($t in $tips) { Write-Info "- $t" }
  }
}

function Show-Gain {
  Write-Title 'RTK 자체 추정 절약량'
  if (-not (Test-Have 'rtk')) { Write-Info 'RTK가 설치되어 있지 않습니다.'; return }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & rtk gain 2>&1 | Select-Object -First 12 | Out-Host }
  finally { $ErrorActionPreference = $prev }
  Write-Warn 'RTK가 스스로 추정한 값입니다. 청구액이 아닙니다.'
  Write-Info '글자수÷4로 토큰을 추정하고, 잘리기 전 원본 전체를 기준으로 계산하며, 캐시 재읽기는 보지 못합니다.'
  Write-Info "실제 효과는 메뉴의 '자체 측정 결과'를 보세요 (RTK: 효과 없음)."
}

function Show-Results {
  Write-Title '자체 측정 결과 (2026-10-08, sonnet, 5회 평균)'
  Write-Host @'
  | 도구     | 출력 토큰 | 실제 효과 (캐시 영향을 뺀 비용) |
  |----------|-----------|----------------------------------|
  | Caveman  | -30%      | 약 -7%                           |
  | RTK      | 변화 없음 | +4% (효과 없음)                  |

  - Caveman: 출력은 크게 줄지만 비용의 대부분이 컨텍스트라 전체 효과는 한 자릿수입니다.
  - RTK: 에이전트가 옵션·| head 를 붙여 실행해 RTK가 줄일 출력이 없었습니다.
  - 더 큰 절약: 대화를 짧게 끊기(/clear), 상시 로딩 줄이기 (메뉴의 '상시 로딩 점검').
  자세한 내용: test\01_measure.md
'@
}

# ---------- 실행: 계획 → 확인 → 실행 ----------

function Confirm-Step {
  param([string]$Question)
  if ($Yes) { return $true }
  Write-Host ''
  $answer = Read-Host "$Question [y/N]"
  return ($answer -match '^(y|Y|yes|YES)$')
}

function Invoke-Step {
  param([string]$Tool, [string]$Action)
  $script = [IO.Path]::Combine($Root, $Tool, 'scripts', "$Action.ps1")
  if (-not (Test-Path -LiteralPath $script)) { throw "스크립트가 없습니다: $script" }
  $label = if ($Action -eq 'install') { "$Tool 설치" } else { "$Tool 삭제" }

  Write-Title "[$label] 계획 (아직 아무것도 바꾸지 않습니다)"
  $global:LASTEXITCODE = 0
  & $script -DryRun -Yes | Out-Host
  if ($LASTEXITCODE -ne 0) { Write-Warn "$label 계획 단계에서 멈췄습니다. 위 메시지를 확인하세요."; return }

  if (-not (Confirm-Step "위 계획대로 진행할까요? ($label)")) { Write-Info "${label}: 건너뜁니다."; return }

  Write-Title "[$label] 실행"
  $global:LASTEXITCODE = 0
  & $script -Yes | Out-Host
}

function Start-SetupCommand {
  param([string]$Name)
  switch ($Name) {
    'caveman'        { Invoke-Step 'Caveman' 'install' }
    'rtk'            { Invoke-Step 'RTK' 'install' }
    'all'            { Invoke-Step 'Caveman' 'install'; Invoke-Step 'RTK' 'install' }
    'status'         { Show-Status }
    'remove-caveman' { Invoke-Step 'Caveman' 'uninstall' }
    'remove-rtk'     { Invoke-Step 'RTK' 'uninstall' }
    'remove-all'     { Invoke-Step 'Caveman' 'uninstall'; Invoke-Step 'RTK' 'uninstall' }
    'usage'          { Show-Daily; Show-Mix }
    'sessions'       { Show-Sessions }
    'context'        { Show-Context $Path }
    'gain'           { Show-Gain }
    'results'        { Show-Results }
  }
}

if ($Command) { Start-SetupCommand $Command; exit 0 }

# ---------- 메뉴 ----------
# 1단계: 작업(설치/삭제/상태) → 2단계: 서비스(Caveman/RTK/둘 다) → 계획 → 확인 → 실행 → 처음 메뉴

function Get-CaveState {
  $codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  foreach ($d in @(([IO.Path]::Combine($HOME, '.claude', 'skills')), ([IO.Path]::Combine($HOME, '.agents', 'skills')), (Join-Path $codexDir 'skills'))) {
    if ((Test-Path -LiteralPath $d -PathType Container) -and
        @(Get-ChildItem -LiteralPath $d -Filter '*cave*' -ErrorAction SilentlyContinue).Count -gt 0) { return '설치됨' }
  }
  return '없음'
}

function Get-RtkState {
  if (-not (Test-Have 'rtk')) { return '없음' }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $ver = (& rtk --version 2>$null) -join ' '
  $ErrorActionPreference = $prev
  return ("설치됨 " + ($ver -replace '^rtk\s*', '')).Trim()
}

# 허용된 번호가 들어올 때까지 다시 묻는다
function Read-Choice {
  param([string[]]$Allowed)
  while ($true) {
    Write-Host ''
    $c = (Read-Host '  선택').Trim()
    if ($Allowed -contains $c) { return $c }
    Write-Warn "목록에 있는 번호를 입력하세요 ($($Allowed -join ' '))"
  }
}

function Write-Line { Write-Host '  ------------------------------------------------------------' }

# 사용량·절약 보기. 뒤로 가면 $false
function Show-UsageMenu {
  Write-Title '  사용량·절약 보기'
  Write-Line
  Write-Host '  1) 일별 사용량            최근 30일 (Claude Code, Codex 있으면 Codex도)'
  Write-Host '  2) 사용량이 큰 대화 10개   비싼 대화 찾기'
  Write-Host '  3) 사용량 구성            캐시 읽기·쓰기·출력이 각각 비용의 몇 %인지'
  Write-Host '  4) 상시 로딩 점검         CLAUDE.md·AGENTS.md·스킬·MCP 서버'
  Write-Host '  5) RTK 자체 추정 절약량    rtk gain (청구액 아님)'
  Write-Host '  6) 자체 측정 결과          Caveman 약 -7%, RTK 효과 없음'
  Write-Host '  9) 뒤로'
  Write-Line
  switch (Read-Choice @('1', '2', '3', '4', '5', '6', '9')) {
    '1' { Show-Daily }
    '2' { Show-Sessions }
    '3' { Show-Mix }
    '4' { $p = Read-Host '  함께 점검할 프로젝트 폴더 경로 (엔터: 전역 설정만)'; Show-Context $p.Trim() }
    '5' { Show-Gain }
    '6' { Show-Results }
    '9' { return $false }
  }
  return $true
}

# 고른 서비스를 실행한다. 뒤로 가면 $false
function Show-ServiceMenu {
  param([string]$Action)
  $verb = if ($Action -eq 'install') { '설치' } else { '삭제' }
  Write-Title "  ${verb}할 서비스를 고르세요"
  Write-Line
  Write-Host "  1) Caveman   답변을 짧게 해 출력 토큰 절약 · 자체 측정: 비용 약 -7%    [현재: $(Get-CaveState)]"
  Write-Host "  2) RTK       셸 명령 출력 압축 · 자체 측정: 효과 없음                [현재: $(Get-RtkState)]"
  Write-Host '  3) 둘 다'
  Write-Host '  9) 뒤로'
  Write-Line
  switch (Read-Choice @('1', '2', '3', '9')) {
    '1' { Invoke-Step 'Caveman' $Action }
    '2' { Invoke-Step 'RTK' $Action }
    '3' { Invoke-Step 'Caveman' $Action; Invoke-Step 'RTK' $Action }
    '9' { return $false }
  }
  return $true
}

while ($true) {
  Write-Title '=============================================================='
  Write-Title '  Caveman · RTK 구성 작업 (agent-token-lab)'
  Write-Title '=============================================================='
  Write-Info "현재 상태 — Caveman: $(Get-CaveState) · RTK: $(Get-RtkState)"
  Write-Title '  원하는 작업을 고르세요'
  Write-Line
  Write-Host '  1) 설치'
  Write-Host '  2) 삭제'
  Write-Host '  3) 설치 상태 자세히 보기'
  Write-Host '  4) 사용량·절약 보기'
  Write-Host '  0) 끝내기'
  Write-Line
  $choice = Read-Choice @('1', '2', '3', '4', '0')
  if ($choice -eq '0') { Write-Info '끝냅니다.'; exit 0 }
  if ($choice -eq '3') { Show-Status }
  elseif ($choice -eq '4') { if (-not (Show-UsageMenu)) { continue } }
  else {
    $action = if ($choice -eq '1') { 'install' } else { 'uninstall' }
    if (-not (Show-ServiceMenu $action)) { continue }
  }
  Write-Host ''
  $again = Read-Host '  처음 메뉴로 돌아갈까요? [Y/n]'
  if ($again -match '^(n|N|no|NO)$') { Write-Info '끝냅니다.'; exit 0 }
}
