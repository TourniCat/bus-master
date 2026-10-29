## 공통 필수 운영 규칙 — 반복 실패·범위 확대 방지 (2026-10-29)

이 절은 모든 개발 세션에 적용한다. 기존 제품별 승인 규칙은 보존하며, 사용자가 확정한 작업 제약과 충돌하면 사용자에게 확인하고 임의로 확대하지 않는다.

- **사용자 확정 지시 준수:** 중단·제외하라고 명시된 작업을 다른 명목으로 다시 추가하지 않는다. 기술적으로 불가피하다는 실제 증거가 있을 때만 최소 차단 사유를 보고하고 승인 전 실행하지 않는다.
- **최소 변경·기존 자원 우선:** 실제 사용자 목표와 완료 조건을 먼저 명시하고 기존 코드·러너·환경을 재사용한다. 필요하면 최소 변경안과 대안을 비교하며, 관련 없는 인프라 재설계·추가 감사·조사를 자동 선행 작업으로 만들지 않는다.
- **Stop-loss:** 같은 문제에 2회 실패하거나 조사만 2회 연속 반복되면 해당 접근을 중단하고 원인과 더 작은 해결책으로 재평가한다. 진전 없는 세 번째 진단을 반복하지 않는다.
- **범위 확대 제한:** 원래 목표에 없는 저장소·기기·계정·서비스 변경은 사용자 승인 없이는 하지 않는다. 기존 작업 결과와 검증 증거를 폐기하거나 다시 조사하지 않는다.
- **Self-hosted CI:** GitHub-hosted 러너(`ubuntu-latest`, `windows-latest` 등)는 사용자가 명시적으로 승인한 경우 외에는 사용하지 않는다. 등록된 호환 Self-hosted Runner를 우선 사용하고, Workflow의 실제 `runs-on`을 확인한다. 미전환 시 원격 CI는 BLOCKED/NOT_RUN으로 기록하고 가능한 로컬 작업을 진행한다. CI 성공을 위해 테스트를 생략·완화하지 않는다.
- **실행 결과와 보고 구분:** 조사·문서·커밋·로컬 테스트·원격 CI·배포는 서로 다른 완료 상태다. 각 결과에 정확한 SHA, PR, 실행 환경, PASS/FAIL/NOT_RUN/BLOCKED 근거를 기록한다.
- **협업·자원:** 메인 개발 세션은 `SCRM-S 개발과정`, 병렬 세션은 `Codex 1`~`Codex 4`로 지칭한다. 기존 파일 소유권과 수신 확인을 존중한다. GitHub 인증정보와 사용자 데이터는 노출하지 않는다.
- **사용자 개입 최소화:** 필요 작업은 검증된 한 번의 실행 절차로 제시한다. 기존 승인 요청을 반복하지 않는다. Main 제품 변경·운영 배포·설치 EXE·실데이터 변경은 별도 명시적 승인을 요구한다.

# Project Working Rules

## Product direction

This repository contains a character-focused tactical auto battler built around three fixed protagonists.

Read these before making design or implementation changes:

- `docs/DESIGN_FOUNDATION.md`
- `docs/DECISIONS.md`
- `docs/PMM_REFERENCE.md`
- `docs/PLANNING.md`

## Non-negotiable current principles

- Three persistent protagonists.
- All three normally deploy.
- No large mercenary roster or company-management loop.
- Combat AI behaves professionally.
- Relationships do not cause irrational tactical decisions.
- Pre-mission planning is lightweight doctrine, not detailed waypoint scripting.
- Injury usually becomes downtime rather than forced roster substitution.

## PMM reference boundary

PMM files may be analyzed to understand behavior and system architecture.

Do not copy PMM source, assets, text, UI graphics, map content or other proprietary expression into this repository.

Reimplement mechanics independently.

## Design workflow

When a design decision becomes settled:

1. update `docs/DECISIONS.md`
2. update the relevant design document
3. remove contradictory stale notes

Do not silently treat brainstorming as a final requirement.
