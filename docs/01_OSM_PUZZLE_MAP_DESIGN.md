# Bus Master — OSM Puzzle Map Design

> Status: Design draft v0.1
> Date: 2026-09-10

## 1. 목적

이 문서는 Bus Master에서 **실제 지도 한 구획을 어떻게 한 판짜리 버스 퍼즐 보드로 변환할지** 정의한다.

핵심 원칙:

> **OSM은 배경 이미지가 아니라 퍼즐 생성 데이터다.**

실제 도시의 도로 구조, 수변, 공원, 철도, 건물 밀도, 주요 POI가 해당 판의 난이도와 전략을 만든다.

---

## 2. 플레이어 플로우

### 2.1 지역 선택

1. 게임 시작
2. 세계 지도 또는 검색창에서 장소 검색
3. 지도를 이동/확대
4. 고정 크기 또는 선택 가능한 크기의 플레이 프레임을 배치
5. `Analyze Area`
6. 게임이 지도 품질과 예상 난이도를 분석
7. 플레이 시작

초기 Vertical Slice에서는 세계 지도 UI까지 만들지 않고, 미리 지정된 좌표/Bounding Box 하나를 사용한다.

### 2.2 추천 플레이 영역 크기 — 가설

초기 후보:

- Small: 2 km × 2 km
- Standard: 4 km × 4 km
- Large: 6 km × 6 km

첫 프로토타입 기준은 **약 3~4 km 폭**을 추천한다.

너무 작으면 노선 선택이 단순하고, 너무 크면 화면 가독성과 경로 탐색이 급격히 복잡해진다.

---

## 3. 지도 레이어

### 3.1 필수 레이어

#### Roads

퍼즐의 핵심 공간 그래프.

최소 분류:

- Major arterial
- Secondary road
- Local road
- Service/access road

표현:

- 도로 등급에 따라 선 굵기 차이
- 색상은 저채도
- 노선보다 항상 낮은 시각 우선순위

#### Buildings

실제 footprint를 단순 polygon으로 표시.

목적:

- 실제 지역 인식
- 밀도 표현
- Demand Zone 생성 보조

게임플레이 중에는 클릭 대상이 아닌 배경에 가깝다.

#### Water

강, 호수, 운하 등.

목적:

- 강력한 시각적 지역성
- 자연스러운 이동 장벽
- 다리/터널 병목 생성

#### Parks / Green Areas

공원, 숲, 광장 등.

목적:

- 지역 인식
- Leisure Demand 후보
- 지도 가독성

#### Railway

철도와 주요 역.

목적:

- 도시 구조 표현
- Transport Hub Demand 생성

### 3.2 선택 레이어

- Administrative labels
- Minor POI labels
- Existing bus stops
- Existing bus routes

기본 플레이에서는 정보 과밀을 막기 위해 숨기고 필요 시 토글한다.

---

## 4. 지도 단순화 규칙

OSM 데이터를 그대로 모두 그리면 게임 화면이 지저분해진다.

따라서 렌더링 전에 단순화한다.

### 4.1 도로

- 보행자 전용 통로는 기본적으로 버스 그래프에서 제거
- 주차장 내부 service road는 우선순위 낮춤
- 너무 짧고 의미 없는 segment는 병합
- 동일 도로가 여러 lane geometry로 분리된 경우 게임 그래프용으로 단순화 검토
- 화면 줌 레벨에 따라 작은 도로를 숨길 수 있음

### 4.2 건물

- 매우 작은 shed/utility structure는 생략 가능
- 인접한 작은 건물은 렌더링 단순화를 위해 묶을 수 있음
- Demand 계산에는 원본 정보를 유지할 수 있음

### 4.3 POI

화면에 직접 라벨링하는 POI는 소수만 유지한다.

우선순위:

1. Major station
2. School / University
3. Hospital
4. Large commercial area
5. Major park
6. Tourist attraction

---

## 5. Road Graph

### 5.1 그래프 구성

- 교차로/도로 연결점 = Node
- 도로 segment = Edge

Edge 기본 속성 후보:

- length
- road_class
- speed
- capacity
- one_way
- bus_allowed
- congestion

### 5.2 속성 추론

OSM에 직접 값이 있으면 우선 사용.

값이 없으면 road class 기반 기본값 사용.

예시 초기값:

| Road Class | Base Speed | Capacity Weight |
|---|---:|---:|
| Major | 50 | 1.0 |
| Secondary | 40 | 0.75 |
| Local | 30 | 0.45 |
| Service | 20 | 0.25 |

실제 단위보다 게임 밸런스가 우선이며, 이후 조정한다.

---

## 6. 정류장 배치

### 6.1 기본 규칙

플레이어는 도로 위 또는 도로 근처를 클릭해서 정류장을 설치한다.

게임은 클릭 위치를 가장 가까운 유효한 Road Edge에 snap한다.

### 6.2 정류장 효과 반경

정류장은 주변 Demand Zone을 일정 거리까지 서비스한다.

초기 가설:

- 기본 보행 반경: 300~500 m

거리 패널티를 둘 수 있다.

예:

- 0~200m: 100% 이용 가능
- 200~400m: 70%
- 400~600m: 30%
- 그 이상: 이용 불가

정확한 수치는 퍼즐 테스트 후 결정한다.

### 6.3 정류장 간격의 전략성

정류장이 많을수록:

- 커버리지 증가
- 승객 접근성 증가
- 버스 정차 횟수 증가
- 노선 운행시간 증가

정류장이 적을수록 반대다.

이 트레이드오프는 Bus Master의 핵심 차별화 요소 중 하나로 본다.

---

## 7. Demand Zone 생성

### 7.1 목적

건물 하나마다 승객을 생성하지 않고, 주변 건물/POI를 묶어 퍼즐용 수요 중심을 만든다.

### 7.2 후보 분류

- Residential
- Office
- Education
- Commercial
- Medical
- Transport
- Leisure/Tourism

### 7.3 생성 입력

가능한 입력:

- building tag
- building footprint area
- building count density
- landuse
- amenity
- shop
- office
- tourism
- railway/public transport POI

### 7.4 생성 방법 — 초기안

1. 지도를 일정 셀 크기로 분할
2. 각 셀의 건물/POI 점수 계산
3. 인접 셀의 유사한 점수를 클러스터링
4. 가장 강한 성격으로 Zone type 결정
5. Zone 중심점과 규모 결정

예:

`주거 건물 밀도 높음 + 상업 POI 낮음 → Residential Zone`

`office/shop 밀도 높음 + 역 인접 → Commercial/Office Hub`

### 7.5 불확실성 처리

OSM 태그가 부족한 곳에서도 판이 생성돼야 한다.

따라서:

- 태그가 풍부함 → 실제 분류 적극 반영
- 태그가 부족함 → 건물 밀도/도로 등급 기반 절차 생성

실제성보다 **플레이 가능한 퍼즐 생성**이 우선이다.

---

## 8. 수요 발생 모델

### 8.1 기본 개념

Demand Zone A에서 Zone B로 이동 수요가 발생한다.

예:

- Residential → Office
- Residential → Education
- Residential → Commercial
- Transport → Office/Commercial
- Residential → Leisure

### 8.2 시간대

한 판 안에서 하루가 빠르게 반복되는 구조를 우선 검토한다.

- Morning: 출근/통학
- Midday: 상업/의료/관광
- Evening: 귀가

### 8.3 난이도 상승

실제 도시 자체는 변하지 않는다.

대신 다음이 점차 증가한다.

- 활성 Demand Zone 수
- Zone별 발생량
- 피크 시간 강도
- 특정 이벤트 수요

따라서 플레이어가 만든 초기 노선은 시간이 지나면 자연스럽게 부족해진다.

---

## 9. 노선 생성 UX

### 9.1 초기안

1. `Create Route` 선택
2. 첫 정류장 선택
3. 다음 정류장 선택
4. 실제 도로 경로 자동 계산
5. 계속 정류장을 추가
6. 완료

### 9.2 경로 선택

두 정류장 사이에 여러 경로가 있을 때:

- 기본: 가장 빠른 유효 경로 자동 선택
- 향후: 플레이어가 중간 도로를 드래그해 경로 수정 가능

초기 프로토타입에서는 자동 경로만 지원한다.

### 9.3 노선 시각화

- 각 노선은 명확한 고유 색상
- 실제 도로 위를 따라 약간 offset된 굵은 선
- 방향 표시 최소화
- 여러 노선 중첩 시 읽기 쉬운 offset 또는 parallel rendering 필요

---

## 10. 버스 시뮬레이션

### 10.1 최소 규칙

- 노선 양 끝 왕복
- 정원 제한
- 정류장 도착 시 승하차
- 이동시간 = Edge length / effective speed

### 10.2 승객 선택

초기에는 단순하게 시작한다.

- 목적지가 같은 노선에 있으면 탑승
- 환승 없음

환승은 핵심 재미가 확인된 뒤 추가한다.

### 10.3 혼잡

첫 OSM Vertical Slice에서는 다음 두 단계 중 선택.

#### Phase A

도로 등급에 따른 고정 속도만 사용.

#### Phase B

시간대별 절차 혼잡 추가.

예:

- Major road morning peak + congestion
- Commercial core evening congestion

실제 실시간 교통 데이터는 사용하지 않는다.

---

## 11. 퍼즐 난이도와 Map Personality

같은 시스템이라도 실제 지도 구조에서 난이도가 달라져야 한다.

자동 분석 후보:

### Grid Score

교차로가 규칙적인가?

높을수록 우회 경로가 많고 노선 설계가 쉽다.

### Bottleneck Score

강, 철도, 고속도로 등으로 인해 통과 지점이 제한되는가?

높을수록 다리/터널/교차점 의존도가 높다.

### Road Connectivity

도로 그래프 연결성이 높은가?

### Density

건물과 POI 밀도가 높은가?

### Centralization

수요가 한 곳에 몰리는가, 분산되는가?

이 값으로 맵에 게임용 특성 태그를 붙일 수 있다.

예:

- Grid City
- Dense Core
- River Bottleneck
- Dispersed Suburb
- Old Town Maze
- Rail Barrier

이 태그는 현실을 평가하는 문구가 아니라 **해당 선택 영역의 게임 그래프 특성**을 표현한다.

---

## 12. 실패 조건

초기 추천:

### Stop Overload

각 정류장에 capacity meter 존재.

- 대기 승객이 임계치 이상이면 Overloaded
- Overloaded 상태가 일정 시간 지속되면 Danger meter 증가
- 해결하면 Danger meter 감소
- 한 정류장의 meter가 끝까지 차면 Game Over

장점:

- 실패 원인이 화면에서 명확함
- 플레이어가 어디를 고쳐야 하는지 즉시 이해
- Mini 계열의 압박감과 잘 맞음

---

## 13. 자원 지급

일정 게임 시간마다 두 선택지 중 하나를 제공하는 구조를 우선 검토한다.

기본 후보:

- Bus +1 or +2
- Route Slot +1
- Stop Capacity Upgrade

향후 후보:

- Express Permit
- Larger Bus
- Bus Lane Token
- Transfer Hub

첫 플레이테스트에서는 자원 종류를 늘리지 않는다.

---

## 14. 점수

메인 점수는 가능한 단순해야 한다.

추천 우선순위:

1. **Total Passengers Delivered** — 메인 점수
2. Survival Time — 보조 기록
3. Peak Waiting — 통계
4. Average Waiting — 통계

지역별 최고 기록을 저장한다.

장기적으로 동일 Bounding Box / 동일 Seed 기준 리더보드를 만들 수 있다.

---

## 15. Seed와 공정성

실제 지도만 같아도 수요 생성 랜덤에 따라 난이도가 크게 달라질 수 있다.

따라서 한 판은 다음 두 값으로 정의할 수 있다.

`Map ID = Bounding Box + Map Data Version`

`Game Seed = Demand sequence seed`

활용:

- 자유 플레이: 랜덤 seed
- Daily Challenge: 전 세계 동일 seed
- 친구 도전: map + seed 공유

이 기능은 실제 지도 사용과 퍼즐 경쟁을 강하게 연결할 수 있다.

---

## 16. 지도 선택 시 사전 분석 화면

플레이 전 다음 정보만 간단히 보여준다.

예:

**Selected Area: Seoul / Gangnam**

- Road Complexity: High
- Demand Density: Very High
- Bottlenecks: Medium
- Map Data Quality: Good

`[PLAY]`

정확한 현실 통계처럼 보이지 않게 모두 **게임 분석값**임을 명확히 한다.

---

## 17. 지도 데이터 품질

### Good

도로 연결성과 건물/POI 데이터가 충분함.

### Limited

도로는 충분하지만 POI/건물 분류 부족.

→ Demand를 절차적으로 보완.

### Poor

도로 연결 자체가 깨져있거나 게임 영역이 너무 비어 있음.

→ 지역 선택 단계에서 경고.

목표는 "OSM이 완벽한 지역만 플레이 가능"이 아니라 **부족한 데이터에서도 최소한의 퍼즐이 생성되는 것**이다.

---

## 18. 지도 보정 기능 — 출시 후 우선순위

초기 출시 필수는 아니다.

장기적으로:

- Building category correction
- POI correction
- Road access correction
- User override save
- Workshop map correction pack

을 지원할 수 있다.

중요 원칙:

사용자 보정은 OSM 원본을 직접 수정하지 않고 게임의 override layer로 유지한다.

---

## 19. Vertical Slice 목표

첫 실제 지도 프로토타입은 딱 여기까지만 만든다.

### 필요한 것

- 한 개 고정 OSM 영역
- 2D 도로 렌더링
- 건물 footprint 렌더링
- 물/공원 표시
- Road Graph
- 지도 위 정류장 설치
- 정류장 2개 선택 시 실제 도로 경로 계산
- 노선 시각화
- 단순 버스 이동
- 수동으로 정의한 Demand Zone 4~6개
- 대기열
- 실패 조건

### 아직 하지 않는 것

- 전 세계 검색
- 자동 Demand Zone 분류
- 실제 POI 완전 분석
- 환승
- 도로 혼잡
- Workshop
- 모바일 빌드
- 리더보드

첫 번째 목표는 단 하나다.

> **실제 도로망 위에서 버스 노선을 짜는 것이 추상 맵보다 더 재미있는가?**

YES가 나온 뒤 자동화 범위를 늘린다.

---

## 20. 지금 결정된 디자인 요약

Bus Master의 맵은 다음 구조로 정의한다.

`실제 OSM 지역 선택`

↓

`도로 / 건물 / 수변 / 공원 / POI 단순화`

↓

`게임용 Road Graph + Demand Zone 생성`

↓

`플레이어가 도로 위에 정류장 설치`

↓

`실제 도로를 따라 버스 노선 운행`

↓

`시간에 따라 수요 증가`

↓

`병목과 과밀 해결`

↓

`결국 붕괴 → 점수 → 재도전`

핵심 제품 문구 후보:

> **Every city is a puzzle.**
