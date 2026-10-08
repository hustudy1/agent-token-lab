# RTK 구축 방법

> 확인 기준: RTK v0.50.0 (2026-09-24 릴리스) · 2026-09-29 · macOS / Linux / Windows

## 개요

에이전트가 실행하는 **셸 명령의 출력**을 압축하는 CLI 프록시입니다. 필터링, 그룹화, 잘라내기, 중복 제거로 100개 이상 명령의 출력을 줄입니다. 대상은 git, 테스트 러너, 빌드·린트, 패키지 매니저, docker/kubectl 등입니다.

- 라이선스: Apache-2.0
- 텔레메트리: 기본으로 꺼져 있고, 동의해야 켜집니다(opt-in).

### 에이전트별 연동 방식

| 에이전트 | 설치 명령 | 방식 |
|---|---|---|
| Claude Code | `rtk init -g` | PreToolUse 훅. 실행 전에 Bash 명령을 `rtk ...`로 자동으로 바꿈 |
| Codex | `rtk init -g --codex` | PreToolUse 훅(`updatedInput`) + AGENTS.md. v0.50.0부터 훅 방식이고, 그 전 버전은 AGENTS.md 지시문만 넣음 |

훅이 적용되는 범위는 Bash 명령뿐입니다. Claude Code의 내장 도구인 `Read`, `Grep`, `Glob`은 훅을 거치지 않습니다.

Claude Code의 **VS Code 확장**도 같은 훅을 씁니다. 확장과 CLI가 `~/.claude/settings.json`을 같이 쓰기 때문입니다. 확장의 Customize > Hooks 메뉴(Claude Code v2.1.269 이상)에서 RTK 훅이 등록됐는지 볼 수 있습니다. 이 저장소는 GitHub Copilot, Cursor 같은 다른 에이전트용 연결(`rtk init -g --copilot` 등)은 다루지 않습니다. 필요하면 [RTK 공식 가이드](https://github.com/rtk-ai/rtk/blob/master/docs/guide/getting-started/supported-agents.md)를 보세요.

## 측정 결과 요약

| 출처 | 조건 | 결과 |
|---|---|---|
| RTK 광고 | 일반 개발 명령 | 셸 출력 −60~90% |
| JetBrains (2026-07) | Sonnet 5 **low**, 86개 작업 | 총비용 **+7.6%** (p=0.004), 턴 +13.8%, 캐시 읽기 +14.3%, 품질 차이 없음 |
| JetBrains (2026-07) | Sonnet 5 **high**, 86개 작업 | 총비용 +0.1% (p=0.99), 품질 차이 없음 |

JetBrains 측정 조건은 rtk v0.43.0, Claude Code 2.1.201입니다. 이후 버전에서는 결과가 달라졌을 수 있습니다.

광고 수치가 청구액으로 이어지지 않은 이유(JetBrains 분석):

- 훅이 보는 건 Bash 도구 출력의 약 1/5뿐입니다. 아주 큰 출력은 Claude Code가 원래 잘라내고 있었습니다.
- 비용의 대부분은 매 턴 이전 대화를 다시 읽는 캐시 읽기인데, RTK는 여기에 영향을 주지 못합니다.
- 압축 때문에 정보가 빠지면 모델이 명령을 다시 실행해서 턴이 늘어납니다.
- `rtk gain`은 잘리기 전 원본 전체를 기준으로 절약량을 세고, 토큰을 글자수÷4로 추정합니다. 이 실험에서 `rtk gain`은 99.8% 절약을 보고했지만 실제 청구액은 늘었습니다.

Codex에서의 독립 측정은 찾지 못했습니다. [UNKNOWN]

## 설치 방식 한눈에

공식 README에 있는 설치 방식 전부와, 이 저장소의 스크립트입니다. **하나만** 고르세요.

| 방식 | OS | 명령 / 방법 | 비고 |
|---|---|---|---|
| 이 저장소 스크립트 | 전부 | `scripts/install.sh`, `scripts/install.ps1` | 백업, 설치, 에이전트 연결까지 한 번에. [아래](#스크립트로-설치제거) 참고 |
| Homebrew | macOS, Linux | `brew install rtk` | README 권장 방식 |
| 공식 설치 스크립트 | macOS, Linux, WSL | `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \| sh` | `~/.local/bin`에 설치 |
| Cargo | 전부 | `cargo install --git https://github.com/rtk-ai/rtk` | 반드시 `--git`. `cargo install rtk`는 다른 프로젝트 |
| winget | Windows | `winget install rtk-ai.rtk` | |
| 릴리스 바이너리 | 전부 | [releases](https://github.com/rtk-ai/rtk/releases)에서 내려받아 PATH에 둠 | 아래 [직접 내려받기](#직접-내려받기-릴리스-바이너리) 참고 |

바이너리를 설치한 뒤 에이전트 연결(`rtk init`)은 방식과 관계없이 같습니다. 아래 3·4단계를 보세요.

## 스크립트로 설치·제거

직접 명령을 치는 대신 스크립트로 설치·제거할 수 있습니다.

| 파일 | OS | 동작 |
|---|---|---|
| [scripts/install.sh](scripts/install.sh) | macOS, Linux | 바이너리 설치(Homebrew, 없으면 공식 설치 스크립트) + 에이전트 연결 |
| [scripts/install.ps1](scripts/install.ps1) | Windows | 바이너리 설치(winget) + 에이전트 연결 |
| [scripts/uninstall.sh](scripts/uninstall.sh) | macOS, Linux | 연결 해제 + 바이너리 삭제 |
| [scripts/uninstall.ps1](scripts/uninstall.ps1) | Windows | 연결 해제 + 바이너리 삭제 |

```bash
# macOS / Linux
cd RTK/scripts
./install.sh --dry-run    # 먼저 실행할 명령만 확인
./install.sh
./uninstall.sh
```

```powershell
# Windows
cd RTK\scripts
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

| 옵션 (sh / ps1) | 스크립트 | 동작 |
|---|---|---|
| `--dry-run` / `-DryRun` | 둘 다 | 실행할 명령만 출력 |
| `-y`, `--yes` / `-Yes` | 둘 다 | 확인 질문 없이 진행 |
| `--no-codex` / `-NoCodex` | install | Codex는 건드리지 않음 |
| `--hook-only` / `-HookOnly` | install | Claude Code에 훅만 등록 (CLAUDE.md에 `@RTK.md`를 넣지 않음) |
| `--keep-binary` / `-KeepBinary` | uninstall | 연결만 해제하고 rtk 바이너리는 남김 |

설치 스크립트가 하는 일:

- 설치 직후 `rtk gain`을 실행해서, crates.io에 있는 같은 이름의 다른 프로젝트(Rust Type Kit)면 멈춥니다.
- Windows에서는 winget으로 설치한 뒤 현재 창의 PATH를 다시 읽어서, 새 터미널을 열지 않아도 이어서 진행합니다.
- Codex가 있으면 rtk 버전을 확인합니다. v0.50.0보다 낮으면 Codex 훅을 지원하지 않는다고 경고하고 업데이트를 권합니다.

제거 스크립트가 하는 일:

- 순서는 Claude Code 연결 해제(`rtk init -g --uninstall`) → Codex 연결 해제(`rtk init -g --codex --uninstall`) → 바이너리 삭제입니다. 바이너리를 먼저 지우면 연결 해제를 못 하기 때문입니다.
- 제거 전에 지금 설치된 것을 보여주고(dry-run에서도), 제거 후에 남은 것이 있으면 해당 줄까지 경고합니다. 확인하는 곳은 다음과 같습니다.
  - Claude Code: `~/.claude/settings.json`의 RTK 훅, `~/.claude/CLAUDE.md`의 `@RTK.md`, `~/.claude/RTK.md`
  - Codex: `~/.codex/hooks.json`의 RTK 훅, `~/.codex/AGENTS.md`의 RTK.md 참조(`@/…/.codex/RTK.md` 절대 경로 형식), `~/.codex/RTK.md`
  - 바이너리: `rtk` 명령 (`--keep-binary`면 제외)

**백업:** `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex/hooks.json`, `~/.codex/config.toml` → `~/.ai_tokens_backup/<타임스탬프>-rtk/` (`$CODEX_HOME`이 있으면 그 폴더 기준)

## 빠른 실행 (명령어만)

각 단계의 설명과 주의사항은 아래 본문에 있습니다.

```bash
# 0. 준비: 기준선 측정과 백업
npx ccusage@latest claude daily
npx ccusage@latest codex daily
cp ~/.claude/settings.json ~/.claude/settings.json.before-rtk 2>/dev/null
cp ~/.claude/CLAUDE.md     ~/.claude/CLAUDE.md.before-rtk     2>/dev/null
cp ~/.codex/AGENTS.md      ~/.codex/AGENTS.md.before-rtk      2>/dev/null
cp ~/.codex/hooks.json     ~/.codex/hooks.json.before-rtk     2>/dev/null

# 1. 설치 (macOS: Homebrew / Windows: winget install rtk-ai.rtk)
brew install rtk

# 2. 설치 확인
rtk --version
rtk gain

# 3. Claude Code 연결 (둘 중 하나) → 끝나면 Claude Code 재시작
rtk init -g
# rtk init -g --hook-only           # CLAUDE.md에 아무것도 추가하지 않는 최소 설치
rtk init --show

# 4. Codex 연결 → 끝나면 Codex 재시작, 훅 신뢰 확인이 나오면 승인
rtk init -g --codex

# 6. 효과 확인 (rtk gain은 자체 추정치이므로 실제 사용량과 함께 비교)
rtk gain --daily
npx ccusage@latest claude daily

# 7. 제거 → 끝나면 Claude Code·Codex 재시작
rtk init -g --uninstall            # Claude Code 연결 해제
rtk init -g --codex --uninstall    # Codex 연결 해제
brew uninstall rtk                 # Windows: winget uninstall rtk-ai.rtk
```

## 0. 준비

### 설치 전 기준선 측정

설치 후 효과를 비교하려면 먼저 평소 사용량을 기록해 두세요.

```bash
npx ccusage@latest claude daily
npx ccusage@latest codex daily
```

### 설정 백업

RTK는 `settings.json`을 바꾸기 전에 `~/.claude/settings.json.bak`을 만듭니다. 하지만 `~/.claude/CLAUDE.md`와 Codex 쪽 파일(`AGENTS.md`, `hooks.json`)도 수정하므로, 직접 백업해 두면 되돌리기 쉽습니다.

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.before-rtk 2>/dev/null
cp ~/.claude/CLAUDE.md     ~/.claude/CLAUDE.md.before-rtk     2>/dev/null
cp ~/.codex/AGENTS.md      ~/.codex/AGENTS.md.before-rtk      2>/dev/null
cp ~/.codex/hooks.json     ~/.codex/hooks.json.before-rtk     2>/dev/null
```

`$CODEX_HOME`을 설정해 두었다면 `~/.codex` 대신 그 폴더입니다.

## 1. 바이너리 설치

위 [설치 방식 한눈에](#설치-방식-한눈에) 중 하나를 고르세요.

### macOS / Linux

```bash
# 방법 A: Homebrew (README 권장)
brew install rtk

# 방법 B: 공식 설치 스크립트 (~/.local/bin에 설치)
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc   # PATH에 없으면 추가 (bash는 ~/.bashrc)

# 방법 C: Cargo (반드시 --git으로 설치)
cargo install --git https://github.com/rtk-ai/rtk
```

> **이름 충돌 주의:** crates.io에 있는 `rtk`는 다른 프로젝트(Rust Type Kit)입니다. `cargo install rtk`로 설치하지 마세요.

### Windows

```powershell
# 방법 A: winget
winget install rtk-ai.rtk

# 방법 B: Cargo
cargo install --git https://github.com/rtk-ai/rtk

# 권장: 일부 필터가 ripgrep을 쓰므로 함께 설치 (없으면 'rg not found' 경고)
winget install BurntSushi.ripgrep.MSVC
```

- v0.37.2부터 Claude Code 훅이 네이티브 바이너리(`rtk hook claude`)로 동작합니다. bash나 jq 없이 PowerShell, 명령 프롬프트, Windows Terminal에서 모두 됩니다.
- **v0.37.2 이전에 설치했다면** 예전 셸 훅(`rtk-rewrite.sh`)이 남아 있을 수 있습니다. `rtk init -g`를 다시 실행하면 네이티브 훅으로 바뀝니다.
- `rtk.exe`를 **더블클릭하지 마세요.** 사용법만 출력하고 바로 닫힙니다. 항상 터미널에서 실행합니다.

### WSL

WSL 안에서는 Linux와 똑같이 동작합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
rtk init -g
```

### 직접 내려받기 (릴리스 바이너리)

[releases](https://github.com/rtk-ai/rtk/releases)에서 OS에 맞는 파일을 내려받아 압축을 풀고, `rtk`(Windows는 `rtk.exe`)를 PATH에 있는 폴더에 둡니다.

| OS | 파일 |
|---|---|
| macOS (Apple Silicon) | `rtk-aarch64-apple-darwin.tar.gz` |
| macOS (Intel) | `rtk-x86_64-apple-darwin.tar.gz` |
| Linux (x86_64) | `rtk-x86_64-unknown-linux-musl.tar.gz` |
| Linux (ARM64) | `rtk-aarch64-unknown-linux-gnu.tar.gz` |
| Windows (x86_64) | `rtk-x86_64-pc-windows-msvc.zip` → 예: `C:\Users\<you>\.local\bin` |

## 2. 설치 확인

```bash
rtk --version
rtk gain        # 절약 대시보드가 나오면 정상
```

`rtk gain`이 실패하면 다른 `rtk`가 설치된 것입니다. README 예시에는 `rtk 0.28.2`로 나오지만 이는 오래된 값이고, 2026-09-29 기준 최신 릴리스는 v0.50.0입니다. Codex 훅 연동은 v0.50.0부터이므로 Codex를 쓴다면 v0.50.0 이상인지 확인하세요.

## 3. Claude Code 연결

```bash
rtk init -g
```

실행하면 다음이 일어납니다.

1. `~/.claude/RTK.md`를 만듭니다 (10줄).
2. `~/.claude/CLAUDE.md`에 `@RTK.md` 참조를 추가합니다.
3. `settings.json`을 수정할지 묻습니다. `y`를 누르면 PreToolUse 훅을 등록하고 `~/.claude/settings.json.bak`으로 백업합니다.

설치가 끝나면 **Claude Code를 재시작**하세요.

| 옵션 | 동작 |
|---|---|
| `rtk init -g --hook-only` | 훅만 등록합니다. CLAUDE.md에는 아무것도 추가하지 않습니다 |
| `rtk init -g --auto-patch` | 묻지 않고 설치합니다 (CI용) |
| `rtk init --show` | 설치 상태를 확인합니다 |

기본 `RTK.md`는 RTK 자체에 대해 거의 아무 말도 하지 않고, 명령 재작성은 훅이 알아서 합니다. 상시 로딩되는 지시문을 최소로 하고 싶다면 `--hook-only`가 가장 가볍습니다.

> **주의:** `-g` 없이 `rtk init`을 실행하면 현재 폴더에 **137줄짜리 CLAUDE.md**를 만듭니다. 이 파일은 매 세션 컨텍스트에 로딩되므로 토큰 절약 목적과 반대입니다. 쓰지 마세요.

### 동작 확인

```bash
rtk init --show   # 훅이 설치되어 있고 실행 가능한지 확인
```

Claude Code를 새 세션으로 열고 `git status`를 실행해 달라고 요청하세요. 실행된 명령이 `rtk git status`로 바뀌어 있으면 정상입니다.

## 4. Codex 연결

```bash
rtk init -g --codex        # 사용자 전체 (~/.codex 또는 $CODEX_HOME)
# rtk init --codex         # 현재 프로젝트만 (.codex/hooks.json + AGENTS.md)
```

**v0.50.0부터 Codex도 훅 방식입니다.** 이전 버전은 AGENTS.md 지시문만 넣어서 모델이 스스로 `rtk`를 붙여야 했습니다. 지금은 Claude Code처럼 훅이 명령을 자동으로 바꿉니다.

- **동작:** `rtk hook codex`가 PreToolUse의 `updatedInput`으로 지원하는 Bash 명령을 `rtk ...`로 바꿉니다. 바뀐 명령에도 Codex의 평소 승인·샌드박스 검사가 그대로 적용됩니다.
- **바뀌는 파일** (전역 설치 기준, `~/.codex` 또는 `$CODEX_HOME`):
  - `hooks.json`: PreToolUse 훅 등록
  - `AGENTS.md`: RTK.md 참조 한 줄 추가. Claude Code와 달리 `@/Users/…/.codex/RTK.md`처럼 **절대 경로**로 씁니다 (2026-10-07 실제 설치로 확인)
  - `RTK.md`: RTK가 만드는 파일
- **설치 후:** Codex를 재시작하세요. Codex는 직접 관리하지 않는 훅을 실행 전에 검토·신뢰하도록 요구합니다. 확인 창이 나오면 승인하고, Codex의 `/hooks`에서도 확인할 수 있습니다.
- **프로젝트 범위 설치의 주의점:** 저장소에 이미 있는 `AGENTS.md`·`RTK.md`가 심볼릭 링크라면 링크된 파일을 수정할 수 있습니다. 직접 읽지 않은 저장소에 설치할 때는 두 파일을 먼저 확인하라고 공식 가이드가 경고합니다.

### 동작 확인

Codex를 새 세션으로 열고 `git status` 실행을 요청하세요. 실행된 명령이 `rtk git status`로 바뀌어 있으면 정상입니다.

## 5. 설정 (선택)

설정 파일 위치:

- macOS: `~/Library/Application Support/rtk/config.toml`
- Linux: `~/.config/rtk/config.toml`

```toml
[hooks]
exclude_commands = ["curl", "playwright"]  # 이 명령들은 재작성하지 않음 (npx playwright도 포함)

[retriever]
mode = "sqlite"   # sqlite(기본) | tee(예전 파일 방식) | disabled
```

- **실패 출력 복구:** 명령이 실패하면 RTK가 필터링 전 전체 출력을 저장합니다. 에이전트는 명령을 다시 돌리지 않고 `rtk recall <id>`로 원본을 불러올 수 있습니다.
- **v0.49.0 변경:** 이 복구 저장소가 파일(tee) 방식에서 SQLite로 바뀌었습니다. 예전 `[tee]` 설정은 자동으로 대응되는 값으로 바뀝니다.

텔레메트리는 기본으로 꺼져 있습니다. 확인하거나 완전히 막으려면:

```bash
rtk telemetry status
export RTK_TELEMETRY_DISABLED=1   # 동의 여부와 관계없이 차단
```

## 6. 효과 확인

```bash
rtk gain           # RTK 자체 추정 절약량
rtk gain --daily   # 일별
rtk discover       # 놓친 절약 기회 찾기
```

> **`rtk gain`은 청구액이 아닙니다.** 토큰을 글자수÷4로 추정하고, 잘리기 전 원본 전체를 기준으로 계산하며, 캐시 재읽기는 보지 못합니다. JetBrains 실험에서 `rtk gain`은 99.8% 절약을 보고했지만 실제 청구액은 늘었습니다.

효과는 같은 작업을 RTK를 켠 상태와 끈 상태로 실행해서 비교하세요. 비교 기준은 `ccusage`나 Claude Code `/usage` 같은 **실제 사용량**입니다.

## 7. 제거

먼저 에이전트 연결을 해제하고, 그다음 바이너리를 지웁니다. 순서가 바뀌면 `rtk` 명령이 없어서 연결 해제를 못 합니다.

```bash
# 1) 연결 해제
rtk init -g --uninstall           # Claude Code: 훅, RTK.md, CLAUDE.md의 @RTK.md, settings.json 항목
rtk init -g --codex --uninstall   # Codex: hooks.json 훅, AGENTS.md의 @RTK.md, RTK.md

# 2) 바이너리 삭제 (설치한 방식에 맞게 하나)
brew uninstall rtk                # Homebrew
rm ~/.local/bin/rtk               # 공식 설치 스크립트
cargo uninstall rtk               # Cargo
winget uninstall rtk-ai.rtk       # Windows winget
# 릴리스 바이너리로 설치했다면 PATH에 둔 rtk(.exe)를 직접 지움
```

- 제거 후 Claude Code와 Codex를 재시작하세요.
- 설정이 꼬였다면 `cp ~/.claude/settings.json.bak ~/.claude/settings.json`으로 복원하거나, 0단계 백업을 쓰세요.

## 8. Caveman과 함께 쓸 때

- **Caveman 스킬 + RTK**: 줄이는 곳이 달라서 함께 써도 됩니다.
- **Caveman 프록시 + RTK**: 겹칩니다.
  - 둘 다 Claude Code의 Bash 명령에 훅을 겁니다.
  - Claude Code는 매칭되는 훅을 병렬로 실행하므로, 어느 쪽 재작성이 적용될지 공식 문서에 없습니다. [UNKNOWN]
  - 하나만 쓰세요. 자세한 내용은 [Caveman 구축 방법](../Caveman/01_install.md#6-rtk와-함께-쓸-때)을 보세요.
  - Codex에서는 겹치지 않습니다. Caveman README에 따르면 Caveman 프록시는 Codex에 명령 축소 훅을 걸지 않습니다.

## 출처

- [RTK README](https://github.com/rtk-ai/rtk) — 설치, 에이전트별 연동 방식, 설정, 텔레메트리, 제거
- [RTK INSTALL.md](https://github.com/rtk-ai/rtk/blob/master/INSTALL.md) — `rtk init`이 만드는 파일, 백업, 137줄 CLAUDE.md 주의
- [RTK Supported Agents 가이드](https://github.com/rtk-ai/rtk/blob/master/docs/guide/getting-started/supported-agents.md) — Codex 훅 연동, 바뀌는 파일, `--codex --uninstall`
- [RTK 릴리스 v0.50.0](https://github.com/rtk-ai/rtk/releases/tag/v0.50.0) — Codex 명령 직접 재작성 훅 추가
- [RTK 릴리스 v0.49.0](https://github.com/rtk-ai/rtk/releases/tag/v0.49.0) — 복구 저장소 SQLite 전환
- [Codex: Hooks](https://learn.chatgpt.com/docs/hooks) — PreToolUse `updatedInput`
- [Codex: AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) — 로딩된 지시문 확인 방법
- [Claude Code: Hooks](https://code.claude.com/docs/en/hooks) — 매칭 훅 병렬 실행
- [JetBrains: rtk Claude Code Token Savings (2026-07)](https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/)
