# Bus Master — OSM Puzzle Map Prototype

현재 Bus Master는 **OpenStreetMap 원본을 그대로 보여주는 게임이 아니라, 실제 도시 데이터에서 작은 버스 퍼즐을 추출하는 방식**을 검증하는 단계입니다.

핵심 질문:

> **실제 도시 구조를 단순화해서 단계적으로 공개했을 때, 한 판짜리 버스 노선 퍼즐로 읽히고 재미있는가?**

현재 기본 테스트 지역은 강남역 주변 약 0.9 km급 구역입니다.

## Windows 빠른 실행

최신 버전을 받은 뒤 저장소 루트에서:

```powershell
git pull
.\run_prototype.bat
```

처음 실행할 때는 인터넷 연결이 필요합니다. OpenStreetMap 데이터를 Overpass API에서 받아 로컬 캐시에 저장합니다. 같은 버전의 맵은 이후 캐시를 사용합니다.

## v0.3.0 핵심 변화

이 버전부터 OSM은 **배경 원본 데이터**로 취급하고, 화면에는 퍼즐에 필요한 정보만 강하게 보여줍니다.

- 내부 도로 노드 점 표시 제거
- 대부분의 작은 도로는 기본 줌에서 숨김
- 건물 footprint는 확대했을 때만 약하게 표시
- 주요 도로는 항상 표시
- OSM `oneway`를 경로 그래프에 반영
- 일방통행 주요 도로에는 방향 화살표 표시
- OSM 건물/POI를 분석해 5개의 `Puzzle District` 생성
- 시작 시 District 2개만 활성화
- District를 클릭해 정류장 배치
- 첫 두 정류장을 Route 1으로 연결한 뒤 `START`
- 수송량이 늘면 새 District가 단계적으로 공개
- 대기 수요가 임계치를 넘으면 게임 종료
- 노선 위에 간단한 버스 표시

현재 District 후보:

- Residential
- Transit Hub
- Commercial
- Office District
- Education

OSM 데이터가 부족한 카테고리는 도로망과 건물 분포를 이용한 fallback 위치를 사용합니다. 이 부분은 아직 정교한 도시 분석기가 아니라 **퍼즐 생성용 휴리스틱 v0.1**입니다.

## 첫 플레이 흐름

처음 화면에는 활성 District 두 곳만 강조됩니다.

1. 두 District를 각각 클릭해 정류장을 만듭니다.
2. 두 번째 정류장을 만들면 Route 1 편집 모드로 전환됩니다.
3. 두 정류장을 차례로 클릭해 Route 1을 만듭니다.
4. 오른쪽 `START`를 누릅니다.
5. 연결된 District 사이 수요가 처리되면서 `Delivered`가 올라갑니다.
6. `20 Delivered`에서 세 번째 District가 공개되고 Route 2가 열립니다.
7. `50 Delivered`에서 네 번째 District가 공개됩니다.
8. `60 Delivered`에서 Route 3이 열립니다.
9. `90 Delivered`에서 마지막 District가 공개됩니다.
10. 연결되지 않은 District의 대기 수요가 계속 쌓이면 네트워크가 붕괴합니다.

이 수치는 밸런스 확정값이 아니라 **점진적 공개 UX를 테스트하기 위한 임시값**입니다.

## 지도 조작

- 마우스 휠: 커서 기준 확대/축소
- 마우스 가운데 버튼 드래그: 지도 이동
- `Zoom - / Zoom +`: 확대/축소
- `Reset View`: 기본 시점

줌 범위는 100%~400%이며, 기본 줌은 125%입니다.

## 게임 조작

- `Add District Stop`: District 정류장 배치 모드
- `R1 / R2 / R3`: 노선 편집
- `START / PAUSE / RESUME`: 시뮬레이션 제어
- `Reset Run`: 현재 판 초기화
- `Reload OSM`: 캐시 삭제 후 OSM 재다운로드

키보드:

- `S`: District 정류장 배치 모드
- `1 / 2 / 3`: 노선 선택
- `Space`: 시작/일시정지
- `R`: 판 초기화
- `0`: 시점 초기화

## 이번 테스트에서 볼 것

이번 버전의 목적은 세부 밸런스가 아니라 **OSM → Puzzle Map 변환 방향**을 확인하는 것입니다.

- 화면을 보자마자 무엇을 해야 하는지 이해되는가?
- 처음 두 District만 보일 때 부담이 줄었는가?
- 실제 도로 형태는 남아 있으면서 지도 정보량은 충분히 단순한가?
- 상하행/일방통행 방향이 이전보다 이해되는가?
- 새 District가 하나씩 공개될 때 자연스럽게 문제가 커지는가?
- 실제 도시라는 느낌이 퍼즐을 방해하지 않고 오히려 개성을 만드는가?

## 데이터와 출시 관련 메모

공용 Overpass API는 프로토타입 개발용입니다. 정식 제품은 공용 Overpass 서버를 게임 백엔드처럼 사용하는 구조로 출시하지 않습니다.

지도 데이터 출처 표시는 게임 화면에 유지합니다.

## 오류 로그 보내는 방법

`run_prototype.bat`으로 실행하면 최신 로그가 다음 파일에 저장됩니다.

```text
logs/prototype_latest.log
```

오류가 나면:

```text
copy_latest_log.bat
```

을 실행한 뒤 이 채팅에 `Ctrl+V`로 붙여넣으면 됩니다.

기획 문서:

- `docs/00_PRODUCT_VISION.md`
- `docs/01_OSM_PUZZLE_MAP_DESIGN.md`
