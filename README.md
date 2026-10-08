# agent-token-lab

Claude Code와 Codex 같은 AI 코딩 에이전트의 토큰 사용량을 줄이는 방법을 모으고, **실제로 줄어드는지 측정해서** 정리하는 저장소입니다.

> 확인 기준일: 2026-09-29. 도구와 공식 문서는 자주 바뀌므로 각 문서 상단의 버전과 날짜를 먼저 확인하세요.

## 요지

1. **토큰 대부분은 "매 턴 다시 보내는 컨텍스트"에서 나옵니다.**
   에이전트는 요청마다 시스템 프롬프트, 도구 정의, 지시문(CLAUDE.md/AGENTS.md), 지금까지의 대화 전체를 다시 보냅니다.

2. **그래서 출력보다 컨텍스트가 더 큰 레버입니다.**
   Claude Code 공식 비용 문서에 나온 `/usage` 예시(Sonnet 4.6, 합계 $0.55)를 API 단가로 나누면 다음과 같습니다.

   | 항목 | 토큰 | 비용 비중 |
   |---|---|---|
   | 캐시 읽기 (이전 대화 재전송) | 940k | 51% |
   | 캐시 쓰기 | 50k | 34% |
   | 출력 | 5.3k | 14% |
   | 일반 입력 | 1.2k | 1% |

3. **도구가 스스로 보고하는 절약량은 청구액이 아닙니다.**
   이 저장소는 같은 작업을 도구를 켠 상태와 끈 상태로 비교하고, 실제 청구 토큰(`/usage`, `ccusage` 등)으로 판단합니다.

## 다루는 도구

### Caveman

에이전트가 **쓰는 말**과 **읽는 도구 출력**을 줄이는 도구입니다.

- **스킬** (MIT): 에이전트가 군더더기 없이 짧게 답하게 하는 규칙 파일입니다. Claude Code, Codex 등 30개 이상의 에이전트를 지원합니다.
- **프록시** (BSL-1.1): 에이전트와 API 사이에서 로그, 테스트 출력, JSON, diff를 압축합니다. 원본은 로컬 SQLite에 보관합니다.
- **광고 vs 독립 측정**: 광고는 토큰 −65%입니다. JetBrains 측정(2026-07, Sonnet 5, 86개 작업)에서는 스킬 단독으로 **출력 토큰 −8.5%**, 품질 차이는 없었습니다. 프록시는 독립 측정이 없습니다.
- **자체 측정** (2026-10-08, Sonnet, 5회 평균): 스킬이 출력 토큰을 **−30%** 줄였지만, 캐시 영향을 뺀 비용으로는 **약 −7%**입니다. 비용의 대부분이 매 턴 다시 읽는 컨텍스트라서, 출력을 줄여도 전체 효과는 한 자릿수에 그칩니다.

→ [Caveman/01_install.md](Caveman/01_install.md)

### RTK (Rust Token Killer)

에이전트가 실행하는 **셸 명령의 출력**을 압축하는 CLI 프록시입니다 (Apache-2.0).

- **Claude Code**: PreToolUse 훅으로 `git status`를 `rtk git status`처럼 자동으로 바꿔 실행합니다.
- **Codex**: v0.50.0(2026-09-24)부터 Claude Code처럼 PreToolUse 훅으로 명령을 바꿉니다. 그 전 버전은 AGENTS.md 지시문만 넣었습니다.
- **광고 vs 독립 측정**: 광고는 셸 출력 −60~90%입니다. JetBrains 측정(2026-07, Sonnet 5)에서는 추론 강도 low에서 **총비용 +7.6%**, high에서 ±0%였고 품질 차이는 없었습니다.
- **자체 측정** (2026-10-08, Sonnet, 5회 평균): 셸 출력이 큰 작업(`git log -50 --stat` 요약)에서도 **효과가 없었습니다**(+4%, 오차 범위). RTK는 `git log`(−59%), `ls -la`(−80%) 같은 기본 형태만 줄이고 `--stat`, `--oneline`이 붙으면 그대로 내보내는데, 에이전트는 명령에 옵션과 `| head`를 붙여 실행하는 경우가 많았습니다.

→ [RTK/01_install.md](RTK/01_install.md)

자체 측정 방법과 전체 결과는 [test/01_measure.md](test/01_measure.md#측정-기록)에 있습니다.

### 함께 쓸 때

| 조합 | 판단 |
|---|---|
| Caveman 스킬 + RTK | 줄이는 곳이 달라서 함께 써도 됩니다. |
| Caveman 프록시 + RTK | 둘 다 Claude Code에서 Bash 명령 출력을 줄이는 훅을 겁니다. 겹치므로 하나만 쓰세요. |

## 처음 시작하기

clone한 뒤 아래 순서대로 진행하세요. 명령은 macOS 기준이고, Windows는 [다른 컴퓨터에 바로 적용](#다른-컴퓨터에-바로-적용)의 PowerShell 명령을 쓰면 됩니다.

**1. 받기**

```bash
git clone https://github.com/hustudy1/agent-token-lab.git
cd agent-token-lab
```

**2. 준비물 확인**

```bash
node --version    # 22.13 이상 (Caveman에 필요)
brew --version    # macOS에서 RTK 설치에 사용
claude --version  # 연결할 에이전트 (codex --version 도)
```

**3. 설치 전 사용량 기록 (기준선)**

```bash
npx ccusage@latest claude daily | tee ~/ai_tokens_baseline.txt
```

**4. Caveman 스킬 설치** — 먼저 `--dry-run`으로 무엇을 하는지 확인한 뒤 실행합니다.

```bash
cd Caveman/scripts
bash install.sh --dry-run
bash install.sh
```

Claude Code를 새 세션으로 열고 `/caveman`이 켜지는지 확인합니다.

**5. 효과 측정** — 정확하게 보려면 [test/](test/01_measure.md)의 A/B 실험을 쓰세요. 간단히는 며칠 쓴 뒤 다시 기록해 비교합니다.

```bash
npx ccusage@latest claude daily
```

기준선과 비교합니다.

**6. (선택) RTK 설치** — 측정 결과를 보고 필요할 때만 설치합니다. 독립 측정에서는 비용이 줄지 않았습니다([RTK 측정 결과](RTK/01_install.md#측정-결과-요약) 참고).

```bash
cd ../../RTK/scripts
bash install.sh --dry-run
bash install.sh
```

**되돌리기:** 각 폴더의 `bash uninstall.sh`를 실행합니다. 설치 전 설정 백업은 `~/.ai_tokens_backup/`에 있습니다.

`./install.sh`처럼 직접 실행하다가 권한 오류(`permission denied`)가 나면 `bash install.sh`로 실행하세요. ZIP으로 내려받는 등 실행 권한이 빠진 경우에도 동작합니다.

## 다른 컴퓨터에 바로 적용

새 Mac이나 Windows PC에서 바로 설치할 수 있도록 도구마다 설치·제거 스크립트가 있습니다. 먼저 `dry-run`으로 무엇이 바뀌는지 확인한 뒤 실행하세요.

| 위치 | macOS / Linux | Windows |
|---|---|---|
| `Caveman/scripts/` | `install.sh`, `uninstall.sh` | `install.ps1`, `uninstall.ps1` |
| `RTK/scripts/` | `install.sh`, `uninstall.sh` | `install.ps1`, `uninstall.ps1` |

```bash
# macOS / Linux — 예: RTK
cd agent-token-lab/RTK/scripts
./install.sh --dry-run
./install.sh
./uninstall.sh
```

```powershell
# Windows — 예: Caveman
cd agent-token-lab\Caveman\scripts
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\install.ps1
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

옵션은 [Caveman](Caveman/01_install.md#스크립트로-설치제거)과 [RTK](RTK/01_install.md#스크립트로-설치제거) 구축 문서에 있습니다.

모든 스크립트의 공통 동작:

- **백업:** 설치 전에 관련 설정 파일을 `~/.ai_tokens_backup/<타임스탬프>-<도구>/`로 복사합니다.
- **대상 선택:** 쓰고 있는 에이전트에만 설치합니다. Claude Code는 `claude` 명령이나 `~/.claude` 폴더가 있으면, Codex는 `codex` 명령이 있으면 설치 대상으로 봅니다.
- **VS Code 확장도 적용:** Claude Code의 터미널(CLI)과 VS Code 확장은 설정 파일(`~/.claude/settings.json`)과 스킬 폴더(`~/.claude/skills/`)를 같이 씁니다. 그래서 한 번 설치하면 둘 다에 적용됩니다. CLI 없이 VS Code 확장만 써도 됩니다. 적용하려면 새 대화를 여세요.
- **셸 설정 보존:** PATH나 셸 설정 파일은 고치지 않습니다. 추가할 줄만 알려줍니다.

검증 상태:

- **`.sh`:** macOS 기본 bash 3.2에서 문법 검사, `--dry-run`, 옵션별 분기까지 확인했습니다. 실제 설치·제거는 돌려보지 않았습니다.
- **`.ps1`:** 작성 환경에 PowerShell이 없어 실행 검증을 하지 못했습니다. Windows에서는 반드시 `-DryRun`부터 돌려 보세요.

## 폴더 구성

```
agent-token-lab/
├── README.md            # 이 문서 (프로젝트 전체 안내)
├── Caveman/
│   ├── 01_install.md    # 구성요소, 측정 결과, 설치 방식, 스크립트 옵션, 구축 방법
│   └── scripts/
│       ├── install.sh    install.ps1
│       └── uninstall.sh  uninstall.ps1
├── RTK/
│   ├── 01_install.md    # 개요, 측정 결과, 설치 방식, 스크립트 옵션, 구축 방법
│   └── scripts/
│       ├── install.sh    install.ps1
│       └── uninstall.sh  uninstall.ps1
└── test/                # 효과 측정 (A/B 실험 스크립트, 결과 요약)
    ├── 01_measure.md    # 측정 방법, 결과 읽는 법, 시험 실행 기록
    ├── ab_test.sh
    └── summarize.py
```

## 출처

공식 문서
- [Claude Code: Manage costs](https://code.claude.com/docs/en/costs) — `/usage` 예시, 절감 권장 사항
- [Claude API Pricing](https://platform.claude.com/docs/en/about-claude/pricing) — 캐시 읽기·쓰기 단가

도구
- [Caveman](https://github.com/JuliusBrussee/caveman)
- [RTK](https://github.com/rtk-ai/rtk)
- [ccusage](https://ccusage.com/)

독립 측정
- [JetBrains: Speaking to AI Agents like Cavemen (2026-07)](https://blog.jetbrains.com/ai/2026/07/speak-to-ai-agents-like-cavemen-tosave-tokens/)
- [JetBrains: rtk Claude Code Token Savings (2026-07)](https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/)
