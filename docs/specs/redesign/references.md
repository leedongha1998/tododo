# redesign — 레퍼런스 조사

작성: 2026-11-06. 오너 요청: "디자인 개편이 필요해. 지금 도트 테마가 가독성이 많이 떨어져. 레퍼런스 사이트 먼저 조사해줘."
다음 단계(pm `spec.md`)가 이 파일만 읽고 방향을 고를 수 있게 적는다. 출처는 각 항목 끝에.

## 0. 출발점 — 이미 해 본 것
- `docs/specs/retro-theme/readability.md`(2026-10-29)가 한 번 손봤다: 12dp 픽셀 라벨 → 본문 글꼴 14dp 굵게,
  본문 행간 1.55~1.6. 팔레트 24쌍은 WCAG AA(4.5:1) 통과로 테스트에 고정돼 있다.
- 그런데도 "많이 떨어진다"는 피드백이 다시 나왔다. 즉 **글자 크기 조정만으로는 부족했다.**
  남은 후보 원인(추정, 실제 화면 확인 전):
  1. 24dp 이상 제목·숫자에 남은 갈무리 — 안티에일리어싱으로 여전히 번진다.
  2. 모든 요소에 두른 2dp ink 테두리 + 계단 모서리 → 시각 잡음, 위계가 평평해짐.
  3. 배경 층 대비가 약함: `paper #F3EAD3` / `surface #FFF8E7` / `sunken #E3D6B8` 크림 계열끼리라 카드가 배경에서 안 떨어진다.
  4. 작은 픽셀 아이콘(격자 아이콘은 축소하면 형태가 뭉개짐).
  → 어느 화면이 제일 읽기 힘든지 오너 스크린샷으로 확인 필요.

## 1. 레퍼런스 탐색용 사이트
| 사이트 | 쓰임 | 비고 |
|---|---|---|
| Mobbin (mobbin.com) | 실제 출시 앱의 화면·플로우 스크린샷 검색. 모바일 강함 | 무료 티어 + 유료(약 $15/월, 출처마다 다름) |
| Refero (refero.design) | 페이지 유형·UI 요소·업종 필터. 웹 쪽 비중 큼 | Pro 약 $12/월(연간). 스타일 요약 페이지(styles.refero.design)도 있음 |
| Dribbble | 콘셉트 시안. 출시 앱이 아니라서 구현 가능성 따로 판단 | Strava Design 팀 계정 등 |
| NN/g "Neobrutalism" 글 | 굵은 테두리 스타일의 가독성 주의점 | 색 대비 검사 필수, 노랑+청록 같은 조합 주의 |

출처: lazyweb.com/compare/mobbin-vs-refero (경쟁사 비교 페이지라 수치는 참고만), nngroup.com/articles/neobrutalism/

## 2. 앱 레퍼런스 — 무엇을 볼지
| 앱 | 볼 점 | 투두두두와의 관계 |
|---|---|---|
| **Duolingo** | 게임감을 픽셀 없이 낸다: 밝은 단일 브랜드색(#58CC02), 둥근 디스플레이 서체 + 평범한 본문 서체, 버튼 아래 4px 단단한 그림자(눌림 효과) | "게임 같지만 읽힌다"의 대표 사례. 단 서체는 자체 제작이라 대체 필요 |
| **챌린저스** | 국내 인증샷 챌린지 앱. 습관·투두·인증샷·실시간 랭킹 | 기능 구조가 가장 가깝다(사진 인증). 화면은 직접 설치해 확인해야 함 — 검색으로 UI 자료는 안 나옴 |
| **Habitica** | 픽셀 RPG 투두 앱. "art가 강점이지만 UI가 busy하다"는 리뷰 | **지금 우리가 겪는 문제의 선례.** 반면교사 |
| **Strava** (챌린지·트로피) | 경쟁·기록·트로피 케이스를 차분한 UI로 표현 | 전적/점수/결과 화면 참고 |
| **BeReal** | 시간 제한 촬영, 편집 없음, 두 사진을 한 장면에 배치 | 증거 사진 공개(양쪽 동시 공개) 화면 참고 |
| **토스** | 고대비·단순 구조. Pretendard 계열 + 단일 강조색(#0064FF, 제3자 정리) | 한국어 가독성 기준선. 게임감은 없음 |
| **원티드 디자인 시스템** | 오픈소스 공개(2025-04). Pretendard + Wanted Sans | 한국어 토큰·컴포넌트 구성 참고 |

**IP 제약은 그대로다**: 특정 게임/앱의 로고·캐릭터·고유 레이아웃을 베끼지 않는다(retro-theme spec). Duolingo의 초록·부엉이·버튼 모양을 그대로 쓰지 않는다.

## 3. 글꼴 후보 (전부 SIL OFL 1.1 — 앱 번들 가능, 라이선스 화면 고지)
| 글꼴 | 특징 |
|---|---|
| Pretendard | Inter + 본고딕 기반, 한영 혼용 본문용으로 다듬어짐. 9굵기 + 가변. 국내 앱 사실상 표준 |
| Wanted Sans | 기하학적이되 인간적인 산세리프, 7굵기 + 가변. Pretendard보다 개성 있음 → 제목용 후보 |
| SUIT | 국내 OFL 산세리프(제3자 목록 기준) |
| 갈무리(현행) | 남긴다면 VS 인트로·로고 같은 장식 한두 곳에만 |

## 4. 방향 후보 (오너 결정 필요)
- **안 A. 단단한 플레이풀 (Duolingo류)** — 픽셀 폐기, Pretendard/Wanted Sans, 밝은 강조색 1~2개, 두툼한 눌림 버튼, 둥근 모서리.
  게임감은 색·버튼 촉감·VS 인트로·숫자 연출로. 가독성 개선 폭 큼, 작업량 큼(아이콘·런처 아이콘 다시).
- **안 B. 네오브루탈리즘 (현 테마의 연장)** — 굵은 테두리·단단한 그림자는 유지, 서체만 Pretendard로 전면 교체,
  배경을 흰색 계열로 올려 층 대비 확보, 테두리는 카드·버튼에만. 기존 `pixel_border`·팔레트 토큰을 재사용해 작업량 최소.
  NN/g 지적대로 강한 색 조합의 대비 검사 필요.
- **안 C. 차분한 기본 + 순간 연출 (토스류)** — 화면은 Material 3 기반의 깔끔한 UI, 게임감은 VS 인트로·결과 순간에만.
  가독성 최고, 2026-09-14 확정 1("앱 전체를 게임풍으로")을 뒤집는 결정이 된다.

추천: **안 B** — 문제(글꼴·층 대비·잡음)를 직접 겨냥하면서 기존 테마 자산을 가장 많이 살린다. 배포가 우선이라는 원칙에도 맞다.
단, 오너가 "도트를 아예 버리고 싶다"면 안 A.

## 결정 필요
1. 어느 화면이 가장 읽기 힘든가(스크린샷 1~2장) — 원인 추정 검증용.
2. 도트를 완전히 버릴지(안 A/C) / 테두리 인상은 남길지(안 B).
3. 확정 1("앱 전체 게임풍")을 유지할지.

## 출처
- https://apps.apple.com/bg/app/id1438855824 (챌린저스)
- https://www.webdesignhot.com/design.md/duolingo/ , https://www.oppadu.com/tools/design-systems-site/brand/duolingo.html (Duolingo, 제3자 정리)
- https://www.nngroup.com/articles/neobrutalism/
- https://productivity-apps.com/apps/compare/habitica-vs-habitkit-habit-tracker (Habitica 리뷰)
- https://fontsource.org/fonts/pretendard/about , https://office.dooray.com/cloud-office/help/Hcell/ko_kr/oss/Pretendard-1.3.9_Notice.txt
- https://github.com/wanteddev/wanted-sans , https://designcompass.org/2025/04/11/wanted-design-system-open-source/
- https://www.oppadu.com/tools/design-systems-site/brand/toss.html (토스, 제3자 정리)
- https://www.lazyweb.com/compare/mobbin-vs-refero
- https://petapixel.com/bereal-guide/
- https://medium.com/strava-engineering/scaling-challenge-leaderboards-for-millions-of-athletes-9ab09ef01381
