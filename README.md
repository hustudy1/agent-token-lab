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

## 시작하기

**1. 받기**

```bash
git clone https://github.com/hustudy1/agent-token-lab.git
cd agent-token-lab
```

**2. 실행**

| OS | 방법 |
|---|---|
| macOS / Linux | `bash setup.sh` (macOS는 Finder에서 `setup.command` 더블클릭도 됨) |
| Windows | `setup.bat` 더블클릭 |

**3. 메뉴에서 번호 고르기**

먼저 할 작업을 고르고, 다음 화면에서 서비스를 고릅니다.

```
==============================================================
  Caveman · RTK 구성 작업 (agent-token-lab)
==============================================================
  현재 상태 — Caveman: 없음 · RTK: 없음
  원하는 작업을 고르세요
  1) 설치
  2) 삭제
  3) 설치 상태 자세히 보기
  4) 사용량·절약 보기
  0) 끝내기
  선택: 1

  설치할 서비스를 고르세요
  1) Caveman   답변을 짧게 해 출력 토큰 절약 · 자체 측정: 비용 약 -7%    [현재: 없음]
  2) RTK       셸 명령 출력 압축 · 자체 측정: 효과 없음                [현재: 없음]
  3) 둘 다
  9) 뒤로
  선택: 1
```

서비스를 고르면 **무엇을 바꿀지 먼저 보여주고**(아직 아무것도 바꾸지 않음) "진행할까요?"를 묻습니다. `y`를 누르면 실행하고, 끝나면 처음 메뉴로 돌아갈지 묻습니다. 목록에 없는 번호를 넣으면 다시 묻습니다.

**4) 사용량·절약 보기**에서는 이 컴퓨터의 실제 사용 기록으로 어디에 토큰이 쓰이는지 봅니다.

| 메뉴 | 보여주는 것 |
|---|---|
| 일별 사용량 | 최근 30일 날짜별 토큰·비용 ([ccusage](https://ccusage.com/)로 로컬 기록을 읽음. Codex가 있으면 Codex도) |
| 사용량이 큰 대화 10개 | 비용이 큰 대화(세션) 순위. 오래 이어진 대화를 찾는 데 씀 |
| 사용량 구성 | 캐시 읽기·캐시 쓰기·출력이 각각 비용의 몇 %인지와 해석 |
| 상시 로딩 점검 | 매 세션 항상 실리는 CLAUDE.md·AGENTS.md(@import 포함)·스킬 설명·MCP 서버와 줄일 곳 |
| RTK 자체 추정 절약량 | `rtk gain` 결과 (RTK 자체 추정이라 청구액이 아니라는 안내와 함께) |
| 자체 측정 결과 | 이 저장소의 A/B 측정 요약 |

비용은 API 단가로 환산한 값입니다. 구독이면 실제로는 사용 한도에서 차감됩니다. 사용량 기능에는 Node.js(ccusage용)가 필요하고, macOS·Linux에서는 python3도 씁니다.

추천은 **Caveman만 설치**입니다. RTK는 자체 측정에서 효과가 없었습니다([측정 기록](test/01_measure.md#측정-기록)).

설치가 끝나면 Claude Code에서 **새 대화**를 열고 `/caveman`을 입력해 켜지는지 확인하세요. 터미널과 VS Code 확장 모두 적용됩니다.

### 메뉴 없이 실행 (에이전트에게 맡길 때)

에이전트에게 "agent-token-lab 폴더에서 `bash setup.sh caveman -y` 실행해서 Caveman 설치해줘"처럼 시키면 됩니다. `-y`를 빼면 계획을 보여준 뒤 확인을 묻습니다.

| 하려는 것 | macOS / Linux | Windows |
|---|---|---|
| Caveman 설치 | `bash setup.sh caveman -y` | `setup.bat caveman -Yes` |
| RTK 설치 | `bash setup.sh rtk -y` | `setup.bat rtk -Yes` |
| 둘 다 설치 | `bash setup.sh all -y` | `setup.bat all -Yes` |
| 설치 상태 확인 | `bash setup.sh status` | `setup.bat status` |
| Caveman 제거 | `bash setup.sh remove-caveman -y` | `setup.bat remove-caveman -Yes` |
| RTK 제거 | `bash setup.sh remove-rtk -y` | `setup.bat remove-rtk -Yes` |
| 둘 다 제거 | `bash setup.sh remove-all -y` | `setup.bat remove-all -Yes` |
| 일별 사용량·구성 | `bash setup.sh usage` | `setup.bat usage` |
| 사용량이 큰 대화 10개 | `bash setup.sh sessions` | `setup.bat sessions` |
| 상시 로딩 점검 | `bash setup.sh context <프로젝트 폴더>` | `setup.bat context <프로젝트 폴더>` |
| RTK 자체 추정 절약량 | `bash setup.sh gain` | `setup.bat gain` |
| 자체 측정 결과 | `bash setup.sh results` | `setup.bat results` |

### 준비물

설정 메뉴가 확인해서 없으면 알려줍니다.

- **Caveman:** Node.js 22.13 이상
- **RTK:** macOS는 Homebrew(없으면 공식 설치 스크립트로 대신 설치), Windows는 winget
- **에이전트:** Claude Code(터미널 또는 VS Code 확장)나 Codex. 설치된 것에만 연결합니다.

### 알아둘 점

- **백업:** 설치·제거 전에 관련 설정 파일을 `~/.ai_tokens_backup/<날짜-시간>-<도구>/`로 복사합니다.
- **되돌리기:** 메뉴 5~7번. 제거 후 남은 흔적이 있으면 경고합니다.
- **셸 설정은 그대로 둡니다:** PATH나 셸 설정 파일을 고치지 않고, 필요하면 추가할 줄만 알려줍니다.
- **효과 측정:** 실제로 얼마나 줄었는지는 [test/01_measure.md](test/01_measure.md)의 A/B 실험으로 잽니다.
- **세부 옵션:** 도구별 스크립트를 직접 실행하는 방법(`--hook-only`, `--all-skills` 등)은 [Caveman](Caveman/01_install.md#스크립트로-설치제거)·[RTK](RTK/01_install.md#스크립트로-설치제거) 구축 문서에 있습니다.

### 검증 상태

2026-10-13에 모든 기능을 실제로 실행해 확인했습니다. 설치·삭제는 실제 환경을 건드리지 않도록 격리한 홈 폴더에서 돌렸습니다(103개 항목 모두 통과).

| 범위 | 확인한 것 |
|---|---|
| 설정 메뉴 (`setup.sh`, `setup.command`) | 설치·삭제 × Caveman·RTK·둘 다, 뒤로, 잘못된 번호 재질문, 처음 메뉴로 돌아가기, 메뉴 없이 쓰는 명령 전체 |
| 도구별 스크립트 | 실제 설치 → 삭제 후 흔적 없음, 옵션(`--hook-only`, `--keep-binary`, `--all-skills`, `--no-codex`), Linux용 설치 경로(curl), Codex 연결 |
| Windows 스크립트 (`.ps1` 5개) | PowerShell 파서 문법 검사, Windows 기본 PowerShell 5.1에서 안 되는 문법 없음, Mac용 PowerShell 7로 메뉴·Caveman 실제 설치·삭제 |
| 측정 도구 | 옵션·오류 처리, 결과 요약 |
| 사용량·절약 보기 | macOS(bash)·PowerShell 두 버전 모두 실제 사용 기록으로 실행, 기록·Node.js·RTK가 없는 경우의 안내, 메뉴 4번 경로 |

**아직 확인하지 못한 것:** 실제 Windows PC에서의 실행(winget으로 RTK 설치, `setup.bat` 더블클릭), Caveman의 Claude Code 플러그인 방식(`--plugin`) 실제 설치. 계획 단계가 먼저 나오니 내용을 보고 진행하세요.

## 폴더 구성

```
agent-token-lab/
├── README.md            # 이 문서 (프로젝트 전체 안내)
├── setup.sh             # 설정 메뉴 (macOS / Linux)
├── setup.command        # macOS 더블클릭용 → setup.sh 실행
├── setup.ps1            # 설정 메뉴 (Windows)
├── setup.bat            # Windows 더블클릭용 → setup.ps1 실행
├── tools/
│   └── usage_report.py  # 사용량 구성·대화 순위·상시 로딩 점검 (setup.sh가 호출)
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
