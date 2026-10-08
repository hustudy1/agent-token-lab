# Caveman 구축 방법

> 확인 기준: caveman v2.7.0 · 2026-09-29 · macOS / Linux / Windows

스킬(1~3단계)로 시작하고, 프록시(4단계)는 필요할 때만 추가하는 순서를 권장합니다.

## 구성요소

| 구성요소 | 줄이는 곳 | 라이선스 | 이 폴더에서 다룸 |
|---|---|---|---|
| 스킬 | 에이전트가 쓰는 설명 문장 | MIT | O |
| 프록시 | 에이전트가 읽는 로그, 테스트 출력, JSON, diff, 웹 페이지 | BSL-1.1 | O (선택) |
| 미들웨어 | 직접 만든 에이전트 앱의 도구 결과 | MIT 클라이언트(알파) + BSL-1.1 런타임 | X |

BSL-1.1 부분은 소스를 공개하지만 OSI 오픈소스 라이선스는 아닙니다. 자기 트래픽에는 무료로 쓸 수 있고, 제3자에게 호스팅하려면 상용 라이선스가 필요합니다. 각 버전은 2030-06-21과 출시 4년 뒤 중 이른 날짜에 Apache-2.0으로 바뀝니다.

## 측정 결과 요약

| 출처 | 대상 | 결과 |
|---|---|---|
| Caveman 광고 | 채팅형 답변 | 토큰 −65% |
| JetBrains (2026-07) | 스킬, Sonnet 5 low, 86개 작업 | 출력 토큰 −8.5% (592k → 542k), 품질 차이 없음 (p=0.82) |
| Caveman 자체 벤치마크 | 스킬 + 프록시, Claude Code 54회 | 입력 토큰 −33.2% (독립 검증 없음) |

광고 수치와 차이가 나는 이유가 있습니다. 코딩 에이전트의 출력은 대부분 코드, diff, 도구 호출입니다. 스킬은 이것들을 일부러 건드리지 않고, 그 사이의 설명 문장만 줄입니다.

## 적용 범위

Claude Code의 터미널(CLI)과 **VS Code 확장**은 스킬 폴더(`~/.claude/skills/`)를 같이 씁니다. 한 번 설치하면 둘 다에서 `/caveman`을 쓸 수 있습니다. 확장에서는 `/skills`로 설치된 스킬을 확인할 수 있습니다(Claude Code v2.1.280 이상).

## 설치 방식 한눈에

공식 README에 있는 방식 가운데 Claude Code·Codex에 해당하는 것 전부와, 이 저장소의 스크립트입니다.

| 방식 | 설치되는 것 | 명령 / 방법 | 비고 |
|---|---|---|---|
| 이 저장소 스크립트 | 스킬 | `scripts/install.sh`, `scripts/install.ps1` | 백업, Node 확인, 에이전트 지정까지 한 번에. [아래](#스크립트로-설치제거) 참고 |
| skills CLI | 스킬 | `npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -a codex -y -g` | README 기본 방식에서 설치 스킬을 2개로 좁힘. [1단계](#1-스킬-설치) 참고 |
| Claude Code 플러그인 | 스킬 (Claude Code만) | `claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman` | skills CLI의 `-a claude-code`와 **함께 쓰지 말 것** |
| 공식 전체 설치 스크립트 | 스킬 + Claude Code 훅 + 상태줄 배지 | macOS/Linux: `curl ... install.sh \| bash`, Windows: `irm ... install.ps1 \| iex` | 설치된 에이전트를 모두 찾아 설정. [아래](#공식-전체-설치-스크립트-다른-방법) 참고 |
| 프록시 CLI (선택) | 프록시 | `npm install -g @caveman-ai/cli && caveman setup --install` | 부작용 있음. [4단계](#4-선택-프록시) 참고 |

이 문서에서 다루지 않는 방식:

- **미들웨어**(`npm install @caveman-ai/middleware`, `pip install caveman-middleware`): 직접 만든 에이전트 앱용입니다.
- **Gemini CLI, Cursor 등 다른 에이전트용 설치**: 공식 [INSTALL.md](https://github.com/JuliusBrussee/caveman/blob/main/INSTALL.md)를 보세요.

아래 명령은 macOS/Linux 터미널과 Windows PowerShell에서 똑같이 동작합니다(`npx`, `claude`는 두 OS 공통). OS별로 다른 부분만 따로 적었습니다.

## 스크립트로 설치·제거

직접 명령을 치는 대신 스크립트로 설치·제거할 수 있습니다. 스크립트가 설치하는 건 **스킬뿐**이고, 프록시는 설치하지 않습니다.

| 파일 | OS | 동작 |
|---|---|---|
| [scripts/install.sh](scripts/install.sh) | macOS, Linux | 스킬 설치 |
| [scripts/install.ps1](scripts/install.ps1) | Windows | 스킬 설치 |
| [scripts/uninstall.sh](scripts/uninstall.sh) | macOS, Linux | 제거 |
| [scripts/uninstall.ps1](scripts/uninstall.ps1) | Windows | 제거 |

```bash
# macOS / Linux
cd Caveman/scripts
./install.sh --dry-run    # 먼저 실행할 명령만 확인
./install.sh
./uninstall.sh
```

```powershell
# Windows
cd Caveman\scripts
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

| 옵션 (sh / ps1) | 스크립트 | 동작 |
|---|---|---|
| `--dry-run` / `-DryRun` | 둘 다 | 실행할 명령만 출력 |
| `-y`, `--yes` / `-Yes` | 둘 다 | 확인 질문 없이 진행 |
| `--no-codex` / `-NoCodex` | install | Codex는 건드리지 않음 |
| `--all-skills` / `-AllSkills` | install | 스킬 22개 전부 설치. 기본은 `caveman`, `caveman-compress` 2개 |
| `--plugin` / `-Plugin` | install | Claude Code는 플러그인 방식으로 설치. 설치 범위를 고를 수 없으니 설치 후 [조회](#설치된-스킬-조회)로 확인 |
| `--with-proxy` / `-WithProxy` | uninstall | 직접 설치한 프록시 연결과 CLI까지 제거 |

**요구사항:** Node.js 22.13 이상. 없으면 스크립트가 멈추고 설치하라고 알려줍니다.

**제거 스크립트가 하는 일:** 제거 전에 지금 설치된 것을 보여줍니다(dry-run에서도). 그다음 skills CLI로 스킬을 지우고(`npx skills remove`), Caveman 공식 제거 명령으로 훅·플러그인·MCP 설정을 지웁니다. 끝으로 남은 것이 있으면 경고합니다. 확인하는 곳은 다음과 같습니다.

- 스킬 폴더: `~/.claude/skills/`(Claude Code), `~/.agents/skills/`·`~/.codex/skills/`(Codex), `~/.config/agents/skills/` 아래의 Caveman 스킬 22개 이름과 이름에 `cave`가 들어간 폴더
- 플러그인: `~/.claude/plugins/` 아래 caveman 폴더
- 설정: `~/.claude/settings.json`의 caveman 항목 (공식 전체 설치 스크립트가 넣는 훅·상태줄)
- CLI: `caveman` 명령 (프록시)

**백업:** `~/.claude/settings.json`, `~/.claude/CLAUDE.md` → `~/.ai_tokens_backup/<타임스탬프>-caveman/`

## 빠른 실행 (명령어만)

각 단계의 설명과 주의사항은 아래 본문에 있습니다.

**터미널**

```bash
# 0. 준비
node --version                      # 22.13 이상인지 확인
npx ccusage@latest claude daily     # 기준선 (Claude Code)
npx ccusage@latest codex daily      # 기준선 (Codex)

# 1. 스킬 설치 (쓰는 에이전트에 맞게 한 줄만)
npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -a codex -y -g   # Claude Code + Codex
# npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -y -g          # Claude Code만
# npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a codex -y -g                # Codex만
npx skills ls -g                    # 설치된 스킬 확인

# 4. (선택) 프록시
npm install -g @caveman-ai/cli && caveman setup --install
caveman telemetry off
caveman trial -- claude             # 효과 A/B 측정
caveman trial report
caveman claude                      # 프록시 켜고 실행 (또는 caveman codex, caveman wrap claude)

# 5. 제거
npx skills remove -g -a claude-code -y caveman caveman-compress   # 스킬 (Codex는 -a codex)
npx -y github:JuliusBrussee/caveman -- --uninstall               # 훅·플러그인·MCP
caveman disable claude
npm uninstall -g @caveman-ai/cli
```

**에이전트 안에서 입력**

```text
/caveman            켜기 (자동으로 켜지지 않았을 때)
/caveman lite       모드 변경: lite | full | ultra
stop caveman        끄기
```

## 0. 준비

### 요구사항

- Node.js 22.13 이상
- Claude Code 또는 Codex CLI

```bash
node --version
```

### 설치 전 기준선 측정

설치 후 효과를 비교하려면 먼저 평소 사용량을 기록해 두세요.

```bash
# 로컬 사용 기록으로 일별 리포트 만들기
npx ccusage@latest claude daily
npx ccusage@latest codex daily
```

세션 안에서는 Claude Code의 `/usage`, Codex의 `/status`로 현재 세션 사용량을 볼 수 있습니다.

## 1. 스킬 설치

설치 도구는 skills CLI(`npx skills add`)입니다. 쓰는 에이전트에 맞는 **한 줄만** 실행하세요.

```bash
# Claude Code와 Codex를 둘 다 쓰는 경우
npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -a codex -y -g

# Claude Code만
npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a claude-code -y -g

# Codex만
npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a codex -y -g
```

| 옵션 | 뜻 |
|---|---|
| `-a claude-code`, `-a codex` | 설치할 에이전트. Claude Code는 `~/.claude/skills/`, Codex는 `~/.agents/skills/`에 들어가서 서로 겹치지 않습니다 (2026-10-07 실제 설치로 확인. skills CLI 문서 표에는 `~/.codex/skills/`로 적혀 있음) |
| `--skill caveman --skill caveman-compress` | 답변 압축(`caveman`)과 메모리 파일 압축(`caveman-compress`) 두 개만 설치합니다 |
| `--skill '*'` (쓰지 않음) | 저장소의 스킬 22개를 모두 설치합니다. 스킬마다 이름과 설명이 매 세션 컨텍스트에 들어가서 약 1,000토큰(추정)이 상시 추가됩니다. `/caveman-commit`, `/caveman-review` 같은 추가 명령이 필요할 때만 쓰세요 |
| `-y` | 질문 없이 진행합니다 |
| `-g` | 프로젝트가 아니라 사용자 전체(홈 폴더)에 설치합니다 |

`-a`를 빼면(Caveman README의 기본 명령 `npx skills add JuliusBrussee/caveman -g`) 설치된 에이전트를 자동으로 찾아 설치합니다. 찾지 못하면 어디에 설치할지 묻습니다. 어디에 들어가는지 분명히 하려고 이 문서는 `-a`를 명시합니다.

### Claude Code 플러그인 방식 (다른 방법)

Claude Code에는 플러그인으로도 설치할 수 있습니다. 이 방법을 쓰면 위의 `-a claude-code` 설치는 **하지 마세요.** 플러그인과 `~/.claude/skills/`는 위치가 달라서, 둘 다 하면 Claude Code 안에 caveman이 두 벌 생깁니다. 이 경우 Codex는 `-a codex`로 따로 설치합니다.

```bash
claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman
npx skills add JuliusBrussee/caveman --skill caveman --skill caveman-compress -a codex -y -g   # Codex도 쓰면
```

### 공식 전체 설치 스크립트 (다른 방법)

Caveman이 제공하는 설치 스크립트입니다. 스킬 외에 **Claude Code 훅과 상태줄 배지**까지 설정하고, 컴퓨터에 설치된 지원 에이전트를 모두 찾아 설정합니다(없는 에이전트는 건너뜀). 다시 실행해도 안전하다고 README에 적혀 있습니다. Node.js 22.13 이상이 필요합니다.

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/JuliusBrussee/caveman/v2.7.0/install.sh | bash
```

```powershell
# Windows (PowerShell 5.1 이상)
irm https://raw.githubusercontent.com/JuliusBrussee/caveman/v2.7.0/install.ps1 | iex
```

위 skills CLI 방식보다 바꾸는 범위가 넓습니다. 무엇이 설치되는지 정확히 통제하고 싶다면 skills CLI 방식을 쓰세요.

### Windows에서 Node.js 준비

skills CLI(`npx`)는 Node.js 22.13 이상이 필요합니다. 없으면 먼저 설치하세요.

```powershell
winget install OpenJS.NodeJS
node --version   # 새 터미널에서 확인
```

PowerShell에서도 명령은 같습니다. `--skill '*'`를 쓸 때는 작은따옴표를 그대로 쓰면 됩니다.

## 2. 동작 확인

1. 에이전트를 새 세션으로 시작합니다.
2. 평소처럼 코딩 질문을 합니다. 서두나 마무리 인사 없이 짧게 답하면 켜진 것입니다.
3. 자동으로 켜지지 않으면 `/caveman`을 입력합니다.
4. 설치된 스킬은 아래 [설치된 스킬 조회](#설치된-스킬-조회)로 확인합니다.

Codex는 스킬을 부르는 방식이 Claude Code와 다를 수 있습니다. [Codex: Build skills](https://learn.chatgpt.com/docs/build-skills)를 참고하세요.

### 설치된 스킬 조회

다른 컴퓨터에서 설치 결과를 확인하거나, 필요 없는 스킬이 남아 있는지 볼 때 씁니다.

```bash
npx skills ls -g                     # 전역으로 설치된 스킬 전체 (skills CLI)
npx skills ls -g -a claude-code      # Claude Code 것만 (Codex는 -a codex)
ls ~/.claude/skills                  # 폴더로 직접 확인 (Codex: ~/.agents/skills)
bash scripts/uninstall.sh --dry-run  # Caveman 스킬·플러그인·설정만 골라서 보기. 아무것도 지우지 않음
```

- Windows: `dir $HOME\.claude\skills`
- Claude Code 안에서: `/skills`(v2.1.280 이상)로 목록, `/context`로 스킬이 차지하는 토큰을 봅니다.
- 정상 결과(기본 설치): `caveman`, `caveman-compress` 두 개. 다른 도구가 넣은 스킬(예: `synced`)은 함께 보일 수 있습니다.

필요 없는 스킬만 지우려면 이름을 넣어 지웁니다.

```bash
npx skills remove -g -a claude-code -y <스킬 이름> [<스킬 이름> ...]
```

## 3. 모드와 명령

| 명령 | 동작 |
|---|---|
| `/caveman lite` | 짧지만 정중하게 |
| `/caveman` 또는 `/caveman full` | 기본값. 강하게 줄임 |
| `/caveman ultra` | 최소 단어만 |
| `/caveman wenyan-lite` / `wenyan-full` / `wenyan-ultra` | 고전 중국어 문체 |
| `stop caveman`, `normal mode`, `/caveman off` | 끄기 |

| 추가 명령 | 동작 | 기본 설치 |
|---|---|---|
| `/caveman-compress <파일>` | 마크다운 메모리 파일(예: CLAUDE.md)을 줄이고 원본은 백업 | 포함 |
| `/caveman-commit` | 한 줄짜리 Conventional Commit 메시지 | `--all-skills` 필요 |
| `/caveman-review` | 한 줄에 하나씩 리뷰 지적 | `--all-skills` 필요 |
| `/caveman-stats` | 이번 Claude Code 세션의 토큰 사용량 (비교 측정 없이는 절약량을 알 수 없음) | `--all-skills` 필요 |
| `/caveman-help` | 모드와 명령 목록 | `--all-skills` 필요 |

참고할 점:

- **캐시**: Claude Code는 스킬 지시를 호출 시점의 메시지로 붙입니다. 그래서 세션 중에 모드를 바꿔도 프롬프트 캐시가 깨지지 않습니다.
- **`/caveman-compress CLAUDE.md`**: CLAUDE.md는 매 세션 로딩되므로 줄이면 효과가 계속 누적됩니다. 결과는 diff로 꼭 검토하세요. 줄인 CLAUDE.md는 다음 세션부터 적용됩니다(`/clear`, `/compact`, 재시작 후).
- **한국어**: 한국어 답변이나 한국어 문서에서 얼마나 줄어드는지 측정한 자료는 찾지 못했습니다. 직접 측정이 필요합니다.

## 4. (선택) 프록시

프록시는 에이전트와 API 사이에서 로그, 테스트 출력, JSON, diff를 압축합니다. 원본은 로컬 SQLite에 보관하므로 에이전트가 필요하면 전체 내용을 다시 가져올 수 있습니다.

### 설치

```bash
npm install -g @caveman-ai/cli && caveman setup --install
```

### 텔레메트리 끄기

CLI는 익명 사용 통계를 **기본으로 보냅니다**. 원하지 않으면 끄세요.

```bash
caveman telemetry off   # 또는 환경변수 DO_NOT_TRACK=1
```

README에 따르면 프록시 경로에 Caveman 서버는 없고, 스킬과 훅은 로컬에서만 동작합니다.

### 에이전트 연결

```bash
caveman claude        # 프록시를 계속 켜 두고 Claude Code 실행
caveman codex         # Codex
caveman wrap claude   # 이번 세션만. 끝나면 흔적을 남기지 않음
```

- 설정 파일은 수정하지 않습니다.
- Claude Code는 환경변수로 연결합니다. Pro/Max 로그인은 그대로 Anthropic으로 전달됩니다.
- Codex는 API 키를 쓰면 환경변수로, ChatGPT 로그인을 쓰면 임시 `CODEX_HOME`으로 연결합니다.

기본 연결 시 함께 켜지는 것:

- MCP 도구 5개: `caveman_compress`, `caveman_retrieve`, `caveman_stats`, `caveman_toon_encode`, `caveman_toon_decode`
- Chrome이 있으면 웹 페이지 압축용 browse 서버
- Claude Code의 명령 출력 축소 훅. Codex에는 걸지 않습니다. Caveman README는 그 이유를 Codex 런타임이 명령 재작성을 거부하기 때문이라고 설명합니다. 다만 RTK는 v0.50.0부터 Codex에서 재작성 훅을 쓰므로, 이 설명은 오래된 것일 수 있습니다.
- 새로 설치하는 스킬의 pixel mode (스킬 본문을 PNG 이미지로 바꿔 읽게 함)

위 기능은 `~/.caveman-cloud/config.json`에서 끌 수 있습니다.

### 주의: Claude Code의 MCP tool search가 꺼질 수 있음

Claude Code 공식 문서에 따르면 `ANTHROPIC_BASE_URL`이 Anthropic이 아닌 호스트를 가리키면 MCP tool search가 꺼집니다. 대부분의 프록시가 `tool_reference` 블록을 전달하지 않기 때문입니다. tool search가 꺼지면 **모든 MCP 도구 정의를 처음부터 컨텍스트에 로딩**합니다.

- MCP 서버가 많으면 프록시 때문에 오히려 컨텍스트가 커질 수 있습니다.
- `ENABLE_TOOL_SEARCH=true`로 강제로 켤 수 있습니다. 다만 프록시가 `tool_reference`를 전달하지 않으면 요청이 실패합니다. Caveman 프록시가 이를 전달하는지는 확인하지 못했습니다. [UNKNOWN]
- 프롬프트 캐시가 프록시를 거쳐도 유지되는지도 README에서 확인하지 못했습니다. [UNKNOWN]

**확인 방법:** 프록시를 켠 세션과 끈 세션에서 다음을 비교하세요.

- `/context`: MCP 도구가 차지하는 양
- `/usage`의 `Prompt cache (main)` 줄: 캐시 적중률

### 효과 확인

```bash
caveman trial -- claude   # 같은 작업을 caveman을 켠 상태와 끈 상태로 실행
caveman trial report      # 차이 보고서
caveman stats             # 사용 기록과 비용 추정
```

`trial`은 자체 프록시가 필요합니다. 이미 `caveman claude`를 켰다면 먼저 `caveman disable claude`를 실행하고, 끝나면 `caveman enable claude`로 되돌리세요.

## 5. 제거

```bash
# 1) skills CLI로 설치한 스킬 (Codex는 -a codex)
npx skills remove -g -a claude-code -y caveman caveman-compress

# 2) 공식 제거 명령: 훅, 플러그인, MCP 설정
npx -y github:JuliusBrussee/caveman -- --uninstall

# 3) 프록시를 설치했다면
caveman disable claude                               # 프록시 연결 해제 (codex 등도 같은 방식)
npm uninstall -g @caveman-ai/cli                     # CLI 제거
```

> **주의:** 공식 제거 명령(`npx -y github:JuliusBrussee/caveman -- --uninstall`)은 `npx skills`로 설치한 스킬을 **지우지 않습니다**. 2026-10-07 실제 실행에서 확인했습니다. 실행 결과에도 "npx-skills installs … remove via your IDE's skill manager"라고 나옵니다. 그래서 스킬은 1)처럼 `npx skills remove`로 지워야 합니다. 이 저장소의 `scripts/uninstall.sh`는 두 단계를 모두 실행합니다.

플러그인(방법 B)으로 설치했다면 Claude Code의 `/plugin` 메뉴에서 제거하세요.

## 6. RTK와 함께 쓸 때

- **스킬 + RTK**: 줄이는 곳이 달라서 함께 써도 됩니다.
- **프록시 + RTK**: 겹칩니다.
  - 프록시 기본 연결은 Claude Code에 명령 출력 축소 훅을 겁니다. RTK도 같은 Bash 명령에 PreToolUse 훅을 겁니다.
  - Claude Code는 매칭되는 훅을 병렬로 실행합니다. 두 훅이 모두 명령을 바꾸면 어느 쪽이 적용되는지 공식 문서에 없습니다. [UNKNOWN]
  - 둘 중 하나만 쓰거나, `~/.caveman-cloud/config.json`에서 축소 훅을 끄세요.

## 출처

- [Caveman README](https://github.com/JuliusBrussee/caveman) — 설치, 모드, 프록시, 텔레메트리, 라이선스
- [Caveman INSTALL.md](https://github.com/JuliusBrussee/caveman/blob/main/INSTALL.md) — 에이전트별 설치
- [Claude Code: MCP (tool search)](https://code.claude.com/docs/en/mcp) — `ANTHROPIC_BASE_URL`과 tool search
- [Claude Code: Hooks](https://code.claude.com/docs/en/hooks) — 매칭 훅 병렬 실행
- [Claude Code: Prompt caching](https://code.claude.com/docs/en/prompt-caching) — 스킬 호출과 캐시, 게이트웨이 경유 시 캐시
- [ccusage](https://ccusage.com/) — 사용량 리포트
- [JetBrains: Speaking to AI Agents like Cavemen Saves 65% of Tokens. We Test. (2026-07)](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/) — 스킬 독립 측정
