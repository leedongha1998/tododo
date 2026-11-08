# redesign 구현 계획

입력: `CLAUDE.md`, `docs/specs/redesign/spec.md`(끝의 "## 오너 결정 (2026-11-06)"이 최종),
`docs/specs/redesign/design.md`(끝의 "## 오너 결정 (2026-11-06)"이 최종 — **시안 A**(`#3355FF` + 앰버), 대결 아이콘
`sports_mma`, 홈 위젯 글자 제목 14sp / 보조 12sp, 로그인 ▶ 커서 제거, Pretendard 실측 어긋남은 기본 대응, **0단계는 승인으로
갈음**), dev-standards, 그리고 실제 코드(`lib/`, `test/`, `tool/`, `android/app/src/main/res`·Kotlin, `pubspec.yaml`, `assets/`).

이 문서는 **계획만** 담는다. 작성 세션(2026-11-06)은 코드를 고치지 않았다.

---

## 공통 규칙

- **이 계획을 쓴 환경(클라우드 컨테이너)에는 Flutter SDK가 없다.** `flutter analyze`/`flutter test`/빌드를 여기서 돌릴 수 없다.
  그래서 (1) 커밋을 작게 자르고 **각 커밋이 단독으로 컴파일되게** 순서를 잡았고, (2) 커밋마다 "남아 있으면 안 되는 참조"를
  grep 명령으로 적었고, (3) 오너가 Windows 로컬에서 돌릴 검증 명령과 육안 확인 목록을 단계별로 붙였다.
  구현 세션도 SDK가 없다면 **커밋마다 오너의 analyze/test 결과를 받은 뒤 다음 커밋으로 간다**(한 번에 여러 커밋을 쌓으면 깨진 곳을
  찾기 어렵다).
- 이름 바꾸기 원칙: **새 조각 추가 → 호출부 교체 → 옛 조각 삭제.** 옛 `Pixel*`/`Retro*` 파일은 마지막 사용처가 사라지는
  커밋까지 그대로 둔다(그 사이 화면은 새 테마 위에 옛 조각이 섞여 보인다 — 아래 "릴리스 규칙").
- `flutter analyze`는 `lib/`·`test/`·`tool/`을 모두 본다(`analysis_options.yaml`은 `android/**` 등만 제외). **`tool/`의 두
  생성기도 컴파일 대상**이므로 `RetroPalette`·`AppMark` API를 바꾸는 커밋은 생성기까지 같이 고친다.
- 파일 하나에서 옛 조각을 모두 걷어 냈으면 그 파일의 옛 `import`도 지운다(`unused_import` 경고 = analyze 이슈).
  반대로 아직 옛 조각을 쓰는 파일에서 import를 지우지 않는다.
- 사용자에게 보이는 문자열은 **추가·변경 0**(`lib/core/strings.dart` diff 없음 — design API 계약). 커밋마다
  `git diff --stat -- lib/core/strings.dart`가 비어 있어야 한다.
- 커밋 메시지: `<type>: <한국어 설명>` + 본문(이유) + 시스템이 지정한 attribution 줄. 새 패키지 없음(design "API 계약").
- **릴리스 규칙(spec)**: C1~C26의 P0는 한 릴리스로 공개한다. 중간 커밋을 Play 프로덕션(내부 테스트 트랙 제외)에 올리지 않는다.
- 스키마·RPC·Edge Function·`supabase/` 변경 없음 → 원격 적용 승인 지점이 없다.

## CLAUDE.md·dev-standards와의 충돌 점검 (구현 전)

**구현을 멈춰야 하는 충돌은 없다.** 대조한 항목:
- 도메인 규칙(판정·상태 전이·점수·한도·탈퇴): 손대지 않는다. `battle_chips.dart`의 매핑 함수는 서버 값 → **모양**만 고른다(승패
  계산 없음). 모양 매핑이 바뀌므로 `battle_chips_test`를 같은 커밋에서 새 기대값으로 고친다("테스트 없이 판정 로직 수정 금지"의
  정신 — 판정 로직은 아니지만 의미 구분 규칙을 테스트로 고정한다).
- "하드코딩된 문자열은 strings.dart": 새 문자열 없음. 라이선스 등록의 패키지 이름 `'Pretendard'`는 갈무리 선례(`const ['Galmuri']`)와
  같은 식별자 성격이라 `main.dart`에 둔다.
- "새 패키지 전에 기존 수단 확인": 새 패키지 0. 서체는 자산 파일, 아이콘은 Flutter 내장 Material Icons(`uses-material-design: true`).
- "에러는 삼키지 않는다"·VS 인트로 예외: 동작 변경 없음.
- "네이티브 변경은 릴리스 빌드까지": C24(런처·알림 PNG, colors.xml)·C25(위젯 drawable·layout·리소스)는 `flutter build apk --release`를
  종료 코드로 확인한다.
- "범위 밖 추상화 금지(테마 두 벌)": 시안 A 토큰만 넣는다. B·C 토큰은 코드에 남기지 않는다. 애니메이션 줄이기용 `reduceMotion` 인자
  (아래 C4)는 테마 두 벌이 아니라 같은 테마의 움직임 길이 하나다.
- dev-standards: 공용 조각은 `lib/core/{theme,widgets}/`, 테스트는 lib 구조 미러링(`test/core/theme/...`), 파일명 snake_case =
  클래스명, mocking 프레임워크 없음 — 그대로 따른다.
- spec "깨지는 기존 테스트는 지우지 않고 새 기대값으로 고친다": 테마 변경으로 깨지는 테스트(`retro_text_test`, `battle_chips_test`,
  `recruit_browse_test`, `my_battles_sections_test`, `vs_intro_test`, `app_mark_test`, `widget_test`의 배율 테스트)는 고친다.
  **대상 코드 자체가 삭제되는** 테스트(`pixel_icons_test`, `pixel_border_test`, `retro_palette_test`)는 대상과 함께 지우고 같은 역할의
  새 테스트(`app_icons_test`, `depth_border_test`, `app_palette_test`)가 이어받는다 — design 9장 2단계가 정한 처리다.
- 골든(이미지 비교) 테스트는 저장소에 **없다**(`matchesGoldenFile` 0건). 새로 만들지 않는다(테스트 글꼴이 정사각형이라 실기기와 달라
  의미가 약하다 — `.claude/agent-memory/developer/flutter_widget_test_gotchas.md` 6).

## 착수 전 확인 (작성 세션이 2026-11-06에 확인한 사실)

- 작업 트리 깨끗함, HEAD `1dac7df`(redesign 설계 결정 확정).
- **Pretendard 실측(design 결정 5)** — npm 레지스트리의 공식 패키지 `pretendard@1.3.9`(저장소 `orioncactus/pretendard`의
  `packages/pretendard`, 라이선스 `OFL-1.1`)를 받아 fontTools 4.68로 확인했다. **세 굵기 모두 통과 → design 결정 5의 예외 대응은
  발동하지 않는다.**

  | 파일(OTF, `package/dist/public/static/`) | 크기 | 한글 U+AC00–D7A3 | `tnum` | sha256 |
  |---|---|---|---|---|
  | `Pretendard-Regular.otf` (400) | 1,574,352 B | 11,172 / 11,172 | 있음 | `3ffbacde6ab8411f1d2db54bb9b1f0b3ee2a738932033722cf0388c06aed1c93` |
  | `Pretendard-Bold.otf` (700) | 1,576,660 B | 11,172 / 11,172 | 있음 | `2e91915fab54df71cc9598ebf608b2bdb54c6fe3c066ac61dff0bc44fca71cc7` |
  | `Pretendard-ExtraBold.otf` (800) | 1,568,512 B | 11,172 / 11,172 | 있음 | `c35fe941b7568d52a96010561540e47f9d3948dfde66ba25bc1908233e0a40cd` |
  | `package/dist/LICENSE.txt` | 4,419 B | — | — | `b04538c9abec39a3db75108cf0af0fd9c77032fe8aa2cf38345b4d250e98e38e` |

  - tarball: `https://registry.npmjs.org/pretendard/-/pretendard-1.3.9.tgz`, sha256 `0ffc240cee83be02520fb4ac1b2a0a51052b9d13506ade0ba90c591dbbb3bd53`(72 MB).
  - 같은 tarball의 TTF(`static/alternative/*.ttf`)는 굵기당 약 2.7 MB로 OTF보다 1.1 MB씩 크다. 한글·`tnum` 결과는 같다.
  - LICENSE 첫 줄: `Copyright (c) 2021, Kil Hyung-jin (https://github.com/orioncactus/pretendard), with Reserved Font Name Pretendard.`
  - ExtraBold 파일의 내부 패밀리 이름은 `Pretendard ExtraBold`(굵기 등급 800)다. Flutter는 pubspec이 적은 패밀리·`weight`로 등록하므로
    문제없다. 파일 이름·내부 이름을 바꾸지 않는다(OFL 예약 이름).
- 빠지는 갈무리: `Galmuri11.ttf` 5,376,428 B + `Galmuri11-Bold.ttf` 2,613,660 B = 7.99 MB. 넣는 Pretendard OTF 3개 = 4.72 MB →
  **자산 기준 약 3.27 MB 감소**(AAB 실측은 C2·C26 커밋 메시지에 남긴다).
- 대비비 재계산: design 2.2·2.3(시안 A) 표의 **모든 쌍을 WCAG 공식으로 독립 계산해 설계값과 ±0.05 안에서 일치**함을 확인했다
  (`mint / surface`만 2.04 vs 설계 2.05 — 장식 쌍이고 허용 오차 안).
- 현재 테스트 기준선은 오너 로컬에서 측정해야 한다(0단계).

---

## 0단계 — 착수 전 기준선 (커밋 없음, 오너 로컬)

반드시 **C1 전에** 현재 `main`에서 한다. 개편 뒤에는 "전" 상태를 다시 만들 수 없다.

1. 기준선 숫자: `flutter analyze` 이슈 수, `flutter test` 통과 개수(이 문서 "진행 기록"에 적는다).
2. AAB 크기 전: `flutter build appbundle --release --dart-define-from-file=env.json` → `build/app/outputs/bundle/release/app-release.aab`
   크기(바이트). C2·C26 커밋 메시지가 이 값과 비교한다.
3. **전 스크린샷**(design 9.1): `tool/screenshot_seed.sql`로 데이터를 맞추고 할 일 목록(안 한 일 3 + 완료 2 + 긴 제목 1)과 품질전 판정 창
   (최소 기준 3 + 우열 기준 2, 아무것도 안 고른 상태 / 둘 다 고른 상태)을 배율 1.0과 최대 배율로 찍는다.
   - 주의: 현재 앱은 배율을 **1.3에서 자른다**(`maxTextScale = 1.3`). 기기 설정을 1.5 이상으로 둬도 "전" 사진은 1.3으로 찍힌다.
     전/후 비교표에 "전 = 1.3(당시 상한), 후 = 1.5"로 적는다(아래 "설계와 다른 점" 14).
   - 사진은 저장소 밖(또는 `docs/specs/redesign/screenshots/`)에 둔다. `store/screenshots/`는 건드리지 않는다(spec 범위 밖).

---

## 1단계 — 기반 (P0-1) · 커밋 5개

### C1 `feat: redesign 팔레트(AppPalette)와 대비 테스트`
- 새 파일 `lib/core/theme/app_palette.dart` — `class AppPalette`(정적 `Color` 상수):
  공통 토큰 `background, surface, sunken, line, edge, outline, ink, inkMuted, inkDisabled, success, successPale, danger, dangerPale,
  warning, warningPale, amber, mint` + 시안 A 브랜드 묶음 `primary #3355FF, primaryDeep #2238C8, primaryPale #E3E9FF,
  secondary(= amber), judging #6247D6, judgingPale #ECE6FF`(이름 → "설계와 다른 점" 9).
  - 면색 → 글자색 매핑 함수 `static Color onFill(Color fill)`(design 5.2 InitialBadge: `primary` → `surface`, 그 밖 → `ink`).
  - `double contrastRatio(Color, Color)`를 **이 파일로 옮기고** `retro_palette.dart`에서 지운다(두 파일을 함께 import하는 곳에서 이름이
    겹치지 않게). 지금 `contrastRatio` 사용처는 `retro_palette_test.dart` 하나뿐이다 → 그 테스트에 `app_palette.dart` import 한 줄 추가.
- 새 테스트 `test/core/theme/app_palette_test.dart`:
  - design 2.2 공통 글자 쌍 표의 모든 행(29행, 기준 4.5 — 비활성 3행은 3.0) + 2.2 비텍스트 쌍(기준 3.0) + 2.3 시안 A 표: **설계값 ±0.05 + 기준 이상**
    (현 `retro_palette_test`와 같은 형식).
  - "글자 불가/장식으로만" 쌍(`danger/dangerPale` 4.27, `primary/primaryPale` 4.47, `amber/surface` 1.83, `mint/surface` 2.05,
    `line·edge/background`, `amber/primary` 2.96)은 설계값만 고정하고, 주석으로 "글자에 쓰지 않는다 / 장식"을 적는다.
  - `onFill`: `primary` → `surface`, `secondary`·`amber`·`surface` → `ink`, 그리고 두 결과 모두 해당 면과 4.5 이상.
  - IP 가드: `primary`·`primaryDeep`의 색상(hue)이 초록 범위가 아니고, 의미색 `success`·`mint`의 hue가 `#58CC02`의 hue와 30° 이상 떨어져
    있다(`HSLColor.fromColor`).
- 사용처 없음(아직 아무도 import하지 않음) → 화면 변화 없음.
- grep: `grep -rn "contrastRatio" lib test tool` → `app_palette.dart`, `app_palette_test.dart`, `retro_palette_test.dart`만.

### C2 `chore: Pretendard 글꼴 번들`
- 자산 배치(파일 이름은 원본 그대로):
  ```
  assets/fonts/pretendard/Pretendard-Regular.otf
  assets/fonts/pretendard/Pretendard-Bold.otf
  assets/fonts/pretendard/Pretendard-ExtraBold.otf
  assets/fonts/pretendard/LICENSE.txt
  ```
- `pubspec.yaml`: `assets:`에 `assets/fonts/pretendard/LICENSE.txt` 추가, `fonts:`에
  `family: Pretendard` + `weight: 400 / 700 / 800` 세 항목 추가(주석: 출처·OFL 예약 이름 규칙). **Galmuri 항목은 그대로 둔다**(C26까지
  옛 조각이 쓴다).
- `lib/main.dart`: `pretendardLicenseAsset` 상수 + `LicenseRegistry.addLicense`에 `['Pretendard']` 항목 추가. Galmuri 등록은 C26까지 유지.
- 새 테스트 `test/core/theme/font_manifest_test.dart`: `pubspec.yaml`을 문자열로 읽어 `family: Pretendard`와 세 `asset:` 경로·
  `weight: 700`/`800`이 있고, 그 파일들과 LICENSE가 실제로 존재한다(`File(...).existsSync()`). (C26에서 "Galmuri 없음"을 더한다.)
- 아직 `fontFamily: 'Pretendard'`를 쓰는 곳이 없어 화면 변화 없음.
- 커밋 메시지 본문에 적을 것: 출처 URL·버전·sha256(위 표), 한글 11,172자 × 3 확인, `tnum` 확인, AAB 크기(0단계 대비 증가분).
- **글꼴 파일을 받는 방법과 대안**
  1. (기본) npm 레지스트리 tarball — 이 컨테이너에서 접근 가능함을 확인했다:
     ```
     mkdir -p /tmp/pretendard-dl && cd /tmp/pretendard-dl
     curl -sSLO https://registry.npmjs.org/pretendard/-/pretendard-1.3.9.tgz
     sha256sum pretendard-1.3.9.tgz   # 0ffc240c…bbb3bd53
     tar xzf pretendard-1.3.9.tgz package/dist/LICENSE.txt \
       package/dist/public/static/Pretendard-{Regular,Bold,ExtraBold}.otf
     cp package/dist/public/static/Pretendard-{Regular,Bold,ExtraBold}.otf package/dist/LICENSE.txt \
       /home/user/tododo/assets/fonts/pretendard/
     ```
     복사 후 네 파일의 sha256이 위 표와 같은지 확인한다.
  2. (오너 Windows) GitHub 릴리스 `https://github.com/orioncactus/pretendard/releases/tag/v1.3.9`의 `Pretendard-1.3.9.zip` →
     `public/static/` 안의 같은 세 OTF와 루트 `LICENSE.txt`. sha256을 위 표와 대조한다(이 컨테이너에서는 GitHub가 막혀 확인 못 함).
  3. OTF가 기기에서 이상하게 그려지면(가능성 낮음 — Android Skia는 CFF를 지원) 같은 tarball의 `static/alternative/*.ttf`로 바꾼다
     (굵기당 +1.1 MB, pubspec 경로만 바뀜).
  4. **어느 경로로도 받을 수 없으면** C2를 건너뛰고 C3부터 진행한다. `fontFamily: 'Pretendard'`가 등록되지 않으면 Flutter는 조용히
     시스템 글꼴로 대체하므로 앱이 깨지지 않는다(`font_manifest_test`만 C2와 함께 미룬다). 오너가 로컬에서 2번으로 받아 C2를 나중에
     커밋한다. **pubspec에 존재하지 않는 자산 경로를 적은 채 커밋하지 않는다**(빌드가 깨진다).
  - 서브셋·이름 변경·병합 금지(OFL). 가변 글꼴(`PretendardVariable`)은 쓰지 않는다(design 3.1).

### C3 `feat: 둥근 모서리·아래 두께 모양(DepthBorder)`
- 새 파일 `lib/core/theme/depth_border.dart` — `class DepthBorder extends OutlinedBorder`, 인자 `side, radius, depth, depthColor,
  pressed, dashed, topOnly`(design 5.2). 구현 메모:
  - 두께는 바깥 상자 **안쪽**: `dimensions` = 안 눌림 `fromLTRB(w, w, w, w + depth)` / 눌림 `fromLTRB(w, w + depth, w, w)` → 바깥 크기 불변.
    `Container(decoration: ShapeDecoration(...))`는 `decoration.padding`(= `dimensions`)만큼 자식을 밀어 주므로 `AppPanel`의 내용은 눌릴 때
    자동으로 같이 내려간다.
  - 안 눌림: 아래 `depth` 띠를 `depthColor`로 칠하고 면은 그 위. 눌림: 면이 `depth`만큼 내려와 띠를 덮는다(띠 0). `getOuterPath`는 눌림일 때
    위 `depth`만큼 비운 둥근 사각을 돌려준다(Material이 그 경로를 면색으로 칠하므로).
  - 점선(`dashed`)은 둥근 사각 경로를 `PathMetrics`로 일정 간격 끊는다. `topOnly`는 바텀시트용(위 두 모서리만 둥글고 위 테두리만).
  - **보간(눌림 움직임)**: `lerpFrom/lerpTo`에서 **눌림 쪽으로 가는 보간은 즉시(t > 0이면 눌림 상태)**, 되돌아오는 보간만 `depth`·면 위치를
    연속 보간한다 → design 4.2 "누를 때 0ms, 뗄 때 120ms"를 Material의 모양 애니메이션 안에서 낸다("설계와 다른 점" 1).
  - 안티에일리어싱 켬(현 `PixelBorder`의 `isAntiAlias = false` 폐기).
- 새 테스트 `test/core/theme/depth_border_test.dart`: 눌림 전후 `getOuterPath(rect).getBounds()`가 같은 바깥 상자 안, `dimensions` 값, 모서리
  점(0.5, 0.5)이 경로 밖(둥근 모서리), 눌림으로 가는 `lerp(…, 0.1)`은 눌림과 같고 되돌아오는 `lerp(…, 0.5)`는 중간 두께, `copyWith(side:)`가
  `depth`·`pressed` 유지, `scale` 동작.
- 사용처 없음 → 화면 변화 없음. `PixelBorder`·`pixel_border_test`는 C26까지 그대로.

### C4 `feat: Pretendard 글자 역할표와 새 ThemeData`
- 새 파일 `lib/core/theme/app_text.dart` — `class AppText`: `family = 'Pretendard'`, `textTheme()`(design 3.2 표 15슬롯, 모든 슬롯
  `fontFamily: family`, `letterSpacing: 0`, 색 `AppPalette.ink`), 숫자 슬롯 `numberLarge 32/800/1.2`, `numberMedium 20/800/1.3`,
  `numberSmall 16/700/1.4`(모두 `fontFeatures: [FontFeature.tabularFigures()]`), 마감 줄용 `tabular` 헬퍼(문장 슬롯에 고정폭 숫자만 켜는
  `TextStyle` 조각).
- 새 파일 `lib/core/theme/app_icons.dart` — `class AppIcons`: design 5.4 표의 26개(`cursor` 제외) + 탭 비선택 변형
  (`battleOutlined = sports_mma_outlined`, `todoOutlined = check_box_outlined`, `profileOutlined = person_outline_rounded`)을
  `static const IconData`로. **반드시 `Icons.*` 상수를 그대로 대입**(동적 `IconData(...)` 생성 금지 — 릴리스 아이콘 트리 셰이킹이 깨진다).
  상수 이름이 없으면 analyze가 바로 잡으므로 design 표의 "대안" 열로 바꾼다. `search`는 윤곽 변형이 없다("설계와 다른 점" 5).
- `lib/core/theme/app_theme.dart` 재작성: import를 `app_palette`·`app_text`·`depth_border`·`app_icons`로 교체(`pixel_*`·`retro_*` import 0).
  - `ThemeData(fontFamily: AppText.family, textTheme: AppText.textTheme(), ...)`, `ColorScheme`는 슬롯마다 `AppPalette`로 명시
    (`tertiaryContainer` = `judgingPale`, `outline` = `outline`, `outlineVariant` = `line`, `surfaceContainer` = `background` 등).
  - design 5.1 표 그대로: 앱바·탭바·버튼 4위계(4.2)·대화상자·바텀시트·스낵바·입력 필드(이중선 `_DoubleOutlineInputBorder` 삭제, 모서리 12)·
    세그먼트·체크박스(모서리 6)·ListTile·구분선 1dp `line`·진행 표시·툴팁·ExpansionTile.
  - 버튼: `shape`는 상태별 `DepthBorder`(눌림·비활성 납작), 라벨이 면과 함께 내려가도록 **`padding`을 상태별로**(기본 `fromLTRB(16,0,16,3)`,
    눌림 `fromLTRB(16,3,16,0)`) — ButtonStyleButton은 모양의 `dimensions`로 자식을 밀지 않는다. `minimumSize` 높이 52. 포커스 = 2dp
    `primary` 링(`side`).
  - `animationDuration`: 120 ms. **애니메이션 줄이기**: `AppTheme.build({bool reduceMotion = false})`를 두고 `light => build()`로 유지,
    `reduceMotion: true`면 버튼 `animationDuration: Duration.zero`. `lib/main.dart`의 `MaterialApp.builder`에서
    `MediaQuery.disableAnimationsOf(context)`가 참이면 `Theme(data: AppTheme.build(reduceMotion: true), child: …)`로 감싼다.
  - 뒤로 아이콘 `Icon(AppIcons.back)`, 세그먼트 `selectedIcon: Icon(AppIcons.check)`.
  - FAB: 56dp, 모서리 16, 3dp ink 두께(정적 — "설계와 다른 점" 2).
  - 탭바: 표시기 `primaryPale` 알약(StadiumBorder, 높이 32), 라벨 `labelSmall`(선택 700 ink / 비선택 400 inkMuted), 아이콘 선택
    `primaryDeep` / 비선택 `inkMuted`, 높이 72 유지.
- 테스트:
  - `git mv test/core/theme/retro_text_test.dart test/core/theme/app_text_test.dart` 후 전부 새 기대값으로: 15슬롯 크기·굵기·행간이
    design 3.2 표와 같다, **모든 슬롯·숫자 슬롯 `fontFamily == 'Pretendard'`**, 최소 12, 문장 슬롯(`bodyMedium`·`bodyLarge`) ≥ 14,
    본문 3슬롯 행간 ≥ 1.5, 자간 0(음수 없음), 굵기 ≥ w400, 숫자 슬롯에 `tabularFigures`. 런타임 머지 테스트(`MaterialApp(theme:
    AppTheme.light)` 안에서 `Theme.of(context).textTheme`)가 `fontFamily 'Pretendard'`·행간 1.6/1.6/1.55를 유지(현 테스트의
    'Roboto' 머지 검사를 이어받음).
    (이 커밋에서 이 테스트가 깨지기 때문에 여기서 고친다 — 현 테스트는 `titleLarge`가 픽셀 글꼴이라고 단정한다.)
  - 새 `test/core/theme/app_theme_test.dart`: 모든 elevation 0·`surfaceTint` 투명, `FilledButton` 스타일의 `shape`가 `{pressed}`에서
    `DepthBorder(pressed: true)`, `{disabled}`에서 `depth == 0`, 면색 = `primary`/`sunken`, `build(reduceMotion: true)`의 버튼
    `animationDuration == Duration.zero`, 입력 필드 포커스 테두리가 `OutlineInputBorder`(이중선 클래스 아님) 2dp `primary`,
    `ColorScheme`의 모든 색이 `AppPalette` 값 집합 안(팔레트 밖 색 없음 — retro-theme 운영 규칙 승계).
  - 새 `test/core/theme/app_icons_test.dart`: 모든 상수가 서로 다르고(`codePoint` 기준), 금지 도형(불꽃 `local_fire_department`,
    하트 `favorite`, 보석 `diamond`, 얼굴 `face`·`mood_bad`·`sentiment_*`)과 같지 않다.
- 이 커밋 뒤의 상태: Material 기본 위젯(앱바·대화상자·버튼·입력·스낵바·탭바 면)은 새 테마. `PixelFrame`·`PixelTag`·`PixelIcon`·
  `RetroText.pixel`을 쓰는 곳은 아직 옛 모양(Galmuri 번들 유지 중이라 깨지지 않음).
- grep(0이어야 함): `grep -nE "pixel_|retro_|Pixel|Retro" lib/core/theme/app_theme.dart`

### C5 `feat: 시스템 글자 크기 상한 1.5배`
- `lib/main.dart`: `maxTextScale = 1.5`, 주석 갱신(design 3.3).
- 새 테스트 `test/main_text_scale_test.dart`: `expect(maxTextScale, 1.5)`.
- `widget_test.dart`의 1.3 배율 테스트 2개(VS 인트로, 탭바)와 `my_battles_sections_test`의 1.3 테스트는 **아직 그대로** — 각 화면 커밋
  (C10, C14, C21)에서 1.5로 올린다(화면이 옛 조각인 채로 1.5를 단정하면 의미 없이 깨질 수 있다).

**1단계 끝 검증(오너)**: analyze 0, test 전부. 육안: 앱바·대화상자·입력·스낵바·버튼이 둥글고 Pretendard인지, 버튼 눌림이 보이는지
(9.2-11), 애니메이션 줄이기 켰을 때 되돌아옴이 즉시인지. 카드·칩·아이콘은 아직 옛 모양이 정상.

---

## 2단계 — 공용 구성 요소와 앱 안 아이콘 (P0-2, P0-3) · 커밋 5개

### C6 `feat: 공용 묶음 AppPanel`
- 새 파일 `lib/core/widgets/app_panel.dart` — `enum AppTone { info, success, danger, neutral }`, `class AppPanel`
  (`.raised/.flat/.inset/.tone`, 인자 `child, title, onTap, padding(기본 16), tone, icon(IconData?)` — `PixelFrame`과 같은 생성자 모양).
  - raised = `surface` + 1dp `line` + 2dp `edge` 두께, `onTap`이면 누르는 동안 눌림(`AnimatedContainer` 120 ms `easeOutCubic`, 애니메이션
    줄이기면 `Duration.zero`). flat = `surface` + 1dp `line`. inset = `sunken`, 테두리 없음. 모서리 16.
  - **제목 띠 없음**: `title`은 묶음 안 첫 줄 `titleSmall` ink 글자(+ 아래 간격 12).
  - tone = 연한 면(primaryPale / successPale / dangerPale / sunken) + 테두리 없음 + 왼쪽 24dp 아이콘(primary / success / danger / inkMuted)
    + 제목 `titleSmall` + 본문 `bodyMedium` ink, 모서리 12. 기본 아이콘: info `AppIcons.info`, success `AppIcons.pass`, danger
    `AppIcons.warning`, neutral 없음.
- 새 테스트 `test/core/widgets/app_panel_test.dart`: raised의 `ShapeDecoration.shape`가 `DepthBorder(depth: 2, depthColor: edge)`,
  flat은 `depth 0`, inset·tone은 `side == BorderSide.none`, 제목이 `ColoredBox(ink)` 띠 없이 `Text`로만 그려진다, `onTap` 있을 때
  `Semantics(button: true)`, 애니메이션 줄이기(`MediaQuery(disableAnimations: true)`)에서 `AnimatedContainer.duration == Duration.zero`.
- 호출부 없음(화면은 3단계에서 하나씩 옮긴다). `pixel_frame.dart`는 C26까지 유지.

### C7 `feat: 공용 태그 AppTag와 상태 칩·결과 라벨 새 매핑`
- 새 파일 `lib/core/widgets/app_tag.dart` — `AppTagStyle(fill, textColor, borderColor, dashed, raised, icon)`(값 비교 `==`/`hashCode`에
  `icon` 포함 — "설계와 다른 점" 6), `enum AppTagSize { small, large }`, `class AppTag(label, style, size, leading)`,
  `const neutralTagStyle`. small 최소 높이 28·좌우 10·`labelMedium` / large 최소 높이 40·좌우 14·`titleMedium`, 모서리 8, 테두리 1.5dp,
  raised = 2dp ink 두께. `style.icon`이 있으면 16dp 아이콘(테두리색)을 글자 앞에.
- `lib/features/battle/presentation/battle_chips.dart`: 반환 타입 `AppTagStyle`, design 5.3 표대로(진행중 primary/흰 글자/테두리 없음,
  판정중 judgingPale + 1.5dp judging 실선, 종료 success/흰 글자, 무 surface + outline 실선, **미결 warningPale + warning 테두리 +
  `AppIcons.warning`**, 취소 sunken/inkMuted, 무효 투명 + inkMuted 점선, 모집 중 surface + outline 점선; 결과 승 amber + raised, 패
  inkMuted/흰 글자 테두리 없음, 무 = 무 칩, 무효 = 무효 칩). `battleTypeAccent` → `AppPalette.amber/mint`.
  `BattleTypeBadge`: `surface` 면 모서리 8, 24×24 색 칸(모서리 6) 안 16dp `Icon(AppIcons.speed/quality)` ink + `labelMedium`.
- **같은 커밋에서 바꿀 호출부(컴파일 유지용 기계적 교체만)**:
  - `my_battles_screen.dart` `PixelTag(` 2곳 → `AppTag(`
  - `recruit_detail_sheet.dart` `PixelTag(` 1곳 → `AppTag(`
  - `battle_recruits_screen.dart` `PixelTag(` 1곳 → `AppTag(`, `neutralPixelTagStyle` → `neutralTagStyle`. 기간 칩의
    `leading: PixelIcon(PixelIcons.clock)`은 **그대로 둔다**(`leading`이 `Widget`이라 컴파일됨 — C15에서 바꾼다).
  - 각 파일에서 `pixel_tag.dart` import → `app_tag.dart`.
- 삭제: `lib/core/widgets/pixel_tag.dart`(사용처 0이 됨).
- 테스트:
  - `test/features/battle/presentation/battle_chips_test.dart`: 8종 매핑·결과 매핑 기대값을 5.3 표로, "무 ≠ 미결", "무에
    `danger`·`dangerPale`·`warning`·`warningPale` 없음", **"미결에 아이콘 있음, 무에 아이콘 없음"**, "8종 서로 다름", "모집 중과 무는 점선
    여부로 갈림", 무효 = 면 투명 + 점선 + inkMuted, 승만 raised, 배지 테스트는 `DepthBorder`의 `side.style == none` +
    `find.byIcon(AppIcons.speed)`.
  - `test/features/battle/recruit_browse_test.dart`: `PixelTag` → `AppTag`, `neutralPixelTagStyle` → `neutralTagStyle`,
    `RetroPalette.amber/mint` → `AppPalette.amber/mint`(색 띠 단정). 시계 아이콘 finder(`PixelIcon`)와 띠 폭 8은 C15까지 그대로.
  - `test/features/battle/my_battles_sections_test.dart`: `find.byType(PixelTag)` → `find.byType(AppTag)`(배율 1.3은 C14까지 그대로).
- grep(0이어야 함): `grep -rnE "PixelTag|neutralPixelTagStyle|pixel_tag" lib test tool`

### C8 `feat: 로딩 표시 AppLoader와 상태 문구·증거 사진 틀 새 모양`
- 새 파일 `lib/core/widgets/app_loader.dart` — `AppLoader.small/.medium`(design 5.2: 둥근 점 3개 6/8dp, 간격 4/6, `inkMuted` ↔ `line` 부드러운
  투명도 물결 900 ms 주기, 애니메이션 줄이기면 셋 다 `inkMuted` 정지, `Semantics(label: AppStrings.loading)`).
- `lib/core/widgets/status_message.dart`: `icon` 타입 `IconData?`, 아이콘 40(빈 상태 `inkMuted`, 오류 `danger` + `AppIcons.warning`),
  문장 `bodyMedium`, 보조 `bodySmall inkMuted`, 간격 12, 로더 `AppLoader.medium`.
- `lib/core/widgets/evidence_photo_frame.dart`: 모서리 12 `sunken` 면 + 안쪽 여백 6, **사진에 clip 없음**, `BoxFit.contain`·`filterQuality`
  기본·`cacheWidth` 없음 유지, 실패 아이콘 `AppIcons.brokenImage` 40, 로더 `AppLoader.medium`.
- **같은 커밋에서 바꿀 호출부(`StatusMessage.empty(icon:)` 인자 타입 때문)**:
  - `todo_list_screen.dart`: `icon: PixelIcons.todo` → `icon: AppIcons.todoOutlined`(+ `app_icons.dart` import; `PixelIcons`는 그 파일에서
    아직 다른 곳이 쓰므로 import 유지)
  - `battle_recruits_screen.dart`: `PixelIcons.battle` → `AppIcons.battle`, `PixelIcons.search` → `AppIcons.search`
- 새 테스트 `test/core/widgets/app_loader_test.dart`: 애니메이션 줄이기에서 `pumpAndSettle`이 끝난다(티커 정지) + 세 점 색이 모두 `inkMuted`,
  시맨틱 라벨 `AppStrings.loading`. (선택) `EvidencePhotoFrame`의 `Image`가 `ClipRRect`·`ClipPath` 자손이 아니고 `fit == BoxFit.contain`.
- `pixel_loader.dart`는 C26까지 유지(화면들이 아직 쓴다).

### C9 `feat: 이니셜 배지와 위험 버튼 스타일 새 모양`
- `lib/core/widgets/initial_badge.dart`: 둥근 사각(카드 40/모서리 12, 인트로 72/모서리 16), 글자 Pretendard 800(카드 20, 인트로 32),
  글자색 `AppPalette.onFill(fill)`, 두께는 인트로만 3dp ink. `displayInitial`은 손대지 않는다.
- 새 파일 `lib/core/widgets/app_button_styles.dart` — `AppButtonStyles.danger`(면 `danger`, 라벨·아이콘 `surface`, 비활성 `sunken`/
  `inkDisabled`, 두께·눌림은 테마).
- **같은 커밋에서 바꿀 호출부**: `ai_consent_section.dart`·`profile_screen.dart`의 `RetroButtonStyles` → `AppButtonStyles`(import 교체),
  `player_card_view.dart`의 `InitialBadge(fill: RetroPalette.amber)` → `AppPalette.secondary`, `vs_intro.dart`의 명판 `fill:`
  `RetroPalette.amber/primary` → `AppPalette.secondary/primary`(이니셜 글자색 매핑이 새 `primary`를 기준으로 하므로 같이 옮겨야 대비가
  유지된다. 두 파일의 다른 `RetroPalette`·`RetroText` 사용은 각자 화면 커밋까지 둔다).
- 삭제: `lib/core/widgets/retro_button_styles.dart`.
- 테스트 `test/core/widgets/initial_badge_test.dart`: `displayInitial` 테스트 유지 + `InitialBadge` 위젯 테스트(`fill: primary`면 글자색
  `surface`, `fill: secondary`면 `ink`, 인트로 크기 72).
- grep(0): `grep -rnE "RetroButtonStyles|retro_button_styles" lib test`

### C10 `feat: 하단 탭바 새 아이콘과 경계`  (화면: 탭 셸)
- `lib/core/navigation/main_shell.dart`: 셸의 2dp ink 선 → 1dp `line`(`AppPalette.line`), `NavigationDestination`에 `icon`(윤곽) +
  `selectedIcon`(채움) — battle/battleOutlined, search/search, todo/todoOutlined, profile/profileOutlined. `pixel_*`·`retro_*` import 삭제.
- `test/widget_test.dart` 탭바 스모크 테스트: 배율 1.3 → **1.5**, 테스트 이름·주석 갱신(높이 72 단정 유지). 라벨 넘침은 여전히 육안
  확인 대상(주석 유지).
- grep(0): `grep -nE "Pixel|Retro" lib/core/navigation/main_shell.dart`

**2단계 끝 검증(오너)**: analyze 0, test 전부. 육안: 9.2-1(탭 라벨 4개 한 줄, 배율 1.0/1.5), 9.2-4·5(칩 줄 줄바꿈), 9.2-14(16dp 유형
아이콘), 칩 8종 구분(모집 중 점선 / 무 실선 / 미결 경고 아이콘).

---

## 3단계 — 화면별 정리 (P0-4) · 화면 하나 = 커밋 하나 · 10개

각 커밋 공통: 그 화면 파일의 `PixelFrame.* → AppPanel.*`, `PixelTone → AppTone`, `PixelIcon(PixelIcons.x[, size]) → Icon(AppIcons.x[, size])`
(크기 12 → 16 이상, 24는 기본이라 생략 가능), `PixelLoader → AppLoader`, `RetroText.numeric → AppText.numberSmall`(design이 정한 슬롯),
`RetroPalette.x → AppPalette.x`(`paper` → `background`, `lavender` → `judgingPale`), `FontWeight.w600 → w700`(Pretendard 600 미번들),
design 5.5 화면별 메모(간격: 가장자리 20, 섹션 사이 24, 목록 항목 사이 12). 옛 import 삭제. **문구·정보·흐름 변경 없음.**
커밋마다 해당 기존 테스트가 그대로 통과해야 한다(조작 경로가 바뀌지 않으므로).

| 커밋 | 화면 | 파일 | 메모(design 5.5 외 구현 판단) | 함께 고칠 테스트 |
|---|---|---|---|---|
| C11 `feat: 할 일 목록 새 모양` | 할 일 목록 + 추가·수정 대화상자 (기준 화면 1) | `lib/features/todo/presentation/todo_list_screen.dart` | 안 한 일 `AppPanel.raised`, 완료 `AppPanel.inset` + 취소선 `inkMuted`(`decorationColor`). 체크박스 24dp는 `Transform.scale(scale: 24/18)`("설계와 다른 점" 3). 목록 패딩 `fromLTRB(20,16,20,96)` | `widget_test.dart` 할 일 테스트들(변경 없이 통과 확인) |
| C12 `feat: 대결 상세 판정 창 새 모양` | 대결 상세 ① 판정 창·기준·상대 카드 (기준 화면 2) | `judgment_section.dart`, `criteria_views.dart`, `player_card_view.dart` | 판정 질문 `titleSmall`, 판정 세그먼트 2개 `showSelectedIcon: true`, 기준 번호 `AppText.numberSmall` + `primaryDeep`(현 `RetroText.pixel(12)`), 상대 점수·전적 `numberSmall`, "판정은 한 번만" 줄 왼쪽 `Icon(AppIcons.info, size: 20)` inkMuted. `criteria_views`는 만들기·기준 수정 화면도 쓴다(그 두 화면의 기준 묶음 모양이 여기서 같이 바뀜) | `battle_judgment_test`, `create_battle_test`, `edit_recruit_criteria_test` 통과 확인 |
| C13 `feat: 대결 상세 머리·증거·결과 배너 새 모양` | 대결 상세 ② 머리·증거 제출/교체·결과 배너·포기 | `battle_detail_screen.dart`, `evidence_section.dart` | 마감 두 줄 사이 8 + 고정폭 숫자, 결과 배너(승 = raised + 48dp amber 칸 `emoji_events`, 그 외 tone neutral, 헤드라인 `titleMedium`, 점수 변화 `numberMedium`), 제출 시각 `numberSmall`, 촬영 = 주 버튼 + camera, 다시 찍기 = 보조 + refresh, 포기 = 위험 낮음(TextButton `danger` 글자) + flag | `battle_evidence_test`, `battle_detail_load_test`, `battle_join_vs_intro_test` 통과 확인 |
| C14 `feat: 내 대결 목록 새 모양` | 내 대결 | `my_battles_screen.dart`, `battle_summary_list.dart` | 요약 카드 `Card`+`InkWell` → `AppPanel.raised(onTap:)`(design 5.5 — 물결 없음, 눌림 두께), "내 차례" 강조 글자 `scheme.primary` → `AppPalette.primaryDeep`, w600 3곳 → w700 | `my_battles_sections_test`: 배율 1.3 → **1.5**, 이름·주석 갱신 |
| C15 `feat: 대결 찾기 새 모양` | 대결 찾기(모집 목록·조작판·FAB) | `battle_recruits_screen.dart` | 조작판 `sunken` 유지, 조작판-목록 사이 4dp ink 선 → 1dp `line`, 모집 카드 왼쪽 색 띠 8 → **4dp**(카드 모서리 16 안), 기간 칩 `leading: Icon(AppIcons.clock, size: 16)`, 검색 지우기 아이콘 12 → 16·터치 48, w600 → w700 | `recruit_browse_test`: 띠 폭 8 → 4, 시계 finder `PixelIcon` → `find.byIcon(AppIcons.clock)`; `find.byType(IconButton)` 하나뿐 전제 유지 확인 |
| C16 `feat: 모집 상세 시트 새 모양` | 모집 상세 바텀시트 | `recruit_detail_sheet.dart` | 생성자 카드 raised, 참가 버튼 주 버튼, tone info | `recruit_sheet_test` 통과 확인 |
| C17 `feat: 대결 만들기 새 모양` | 대결 만들기(기준 생성 단계 포함) | `create_battle_screen.dart` | 차단·한도 안내 tone danger, 생성 중 `StatusMessage.loading` | `create_battle_test` 통과 확인 |
| C18 `feat: 모집 기준 수정 새 모양` | 모집 기준 수정 | `edit_recruit_criteria_screen.dart` | | `edit_recruit_criteria_test` 통과 확인 |
| C19 `feat: AI 데이터 제공 동의 화면 새 모양` | 동의 화면 | `ai_consent_screen.dart` | 동의 문구 묶음 flat, 문서 아이콘 `description_outlined` | `ai_consent_test` 통과 확인 |
| C20 `feat: 프로필 새 모양` | 프로필 전체(점수·전적·기록·동의·알림·계정) | `profile_screen.dart`, `ai_consent_section.dart`, `notification_section.dart` | 점수 `AppText.numberLarge`(현 `RetroText.pixel(20)`), 전적 `numberSmall`, 기록 줄 w600 → w700, 동의 철회·계정 삭제 = 위험 버튼, 로그아웃·라이선스 = 보조/낮음 + 아이콘 | `notification_section_test`, `widget_test.dart` 프로필 관련 통과 확인 |

- 3단계 순서는 design 9장의 순서(할 일 → 대결 상세 → 내 대결 → 찾기·시트 → 만들기·기준 수정 → 동의 → 프로필 → 로그인·시작 → 라이선스)를
  따르되, **로그인·시작(C23)은 4단계로 옮겼다**(아래 "순서를 바꾼 기록" 1). 오픈소스 라이선스 화면은 `showLicensePage`라 코드 커밋이 없고
  확인만 한다(6단계).
- 대결 상세를 C12·C13 둘로 나눈 이유: 한 화면이지만 파일이 다섯 개로 나뉘어 있고, 기준 화면 2(판정 창)를 먼저 오너 비교에 올릴 수 있게
  하려는 것이다. 두 커밋은 서로 다른 파일만 고친다.
- 3단계 끝 잔존 참조 grep(아래 결과 **외에는** 0이어야 함):
  ```
  grep -rnE "PixelFrame|PixelTone|PixelIcon\b|PixelIcons|PixelLoader|RetroText|RetroPalette|FontWeight\.w[56]00" lib
  ```
  허용: `lib/core/widgets/pixel_frame.dart`, `pixel_icon.dart`, `pixel_loader.dart`, `lib/core/theme/pixel_icons.dart`, `retro_palette.dart`,
  `retro_text.dart`, `pixel_border.dart`, `app_mark.dart`(C24까지), `lib/features/auth/presentation/login_screen.dart`·`auth_gate.dart`(C23까지),
  `lib/features/battle/presentation/vs_intro.dart`(C21까지).

**3단계 검증(커밋마다, 오너)**: analyze 0, test 전부 + 그 화면의 기능을 끝까지 한 번(spec 수용 기준 "전 화면 적용"의 기능 목록 중 그 화면 몫).
육안(배율 1.0 / 1.5, 360dp 폭 에뮬레이터): C11 할 일 목록 전/후 비교, C12 9.2-2(판정 세그먼트 두 줄 허용·체크 아이콘이 라벨을 안 밀어냄)·전/후
비교, C13 9.2-4·10, C14·C15 9.2-5, C17 9.2-3, C20 9.2-9, 각 화면 대화상자 9.2-7, 토스트 9.2-8.

---

## 4단계 — 순간 연출 (P0-5, P1-1, P1-2) · 커밋 3개

### C21 `feat: VS 인트로 새 스타일`
- `lib/features/battle/presentation/vs_intro.dart`: design 6.2·6.3. 타임라인 `bandOpen 0–200`, `slide 150–550`, `versus 550–750`
  (배율 1.6 → 1.0 + 투명도 0 → 1, `easeOutBack`), `flash 750–850`(100 ms 연속, 1회), `hold 850–1300`, `fade 1300–1500`,
  `stillFrameMs 1300`, `safetyTimeout 3s` 유지. `stepMs`·`stepsSince` 삭제 → 구간 진행률을 곡선으로 보간하는 순수 함수
  (`VsIntroFrame.at(ms)`에 `versusOpacity` 필드 추가). 명판 = 흰 면·모서리 20·1dp `line`·4dp ink 두께(`DepthBorder`), 이름 `titleMedium`
  최대 2줄, "상대"/"나" `labelMedium inkMuted`, "VS" Pretendard 800 64dp 흰색 + 아래 4dp amber 단단한 `Shadow`(흐림 0), 배경·덮개
  `background`, compact(높이 < 520) 이니셜 48 / 띠 64 / "VS" 44. `RetroText`·`RetroPalette`·`PixelBorder` import 삭제.
- 테스트:
  - `test/features/battle/presentation/vs_intro_test.dart`: "구간이 겹치지 않고 이어진다"는 새 타임라인(띠·명판이 150–200에서 겹침)과 맞지
    않으므로 **"모든 구간이 0~1500 안, 시작 < 끝, fade 끝 = 1500 = totalMs"**로 바꾼다. "50ms 계단" 테스트 삭제(규칙 폐기). 기대값:
    `at(0)` 띠 0·명판 0·VS 없음, `at(200).band == 1`, `at(550).slide == 1`, `at(550).versusScale == 1.6`, `at(750).versusScale == 1.0`,
    10 ms 간격 표본에서 flash 참이 **한 덩어리**(750 이상 850 미만, 표본 10개), `at(1299).cover == 0`, `at(1500).cover == 1`, 정지 화면 =
    완성 상태, 진행률이 각 구간 안에서 단조 증가.
  - `test/widget_test.dart` VS 인트로 긴 이름 테스트: 배율 1.3 → **1.5**, 이름 "상한(1.5)".
  - `battle_join_vs_intro_test`, `vs_intro_rules_test`, `vs_intro_seen_store_test`는 그대로 통과해야 한다(표시 규칙 불변).
- 육안: 9.2-6(긴 이름 20자·한 글자·"탈퇴한 사용자"·가로 모드), 애니메이션 줄이기 시 정지 화면·번쩍임 없음.

### C22 `feat: 앱 마크를 벡터로 다시 그림`
- `lib/core/theme/app_mark.dart`: design 7.1의 24u 격자 벡터 마크를 **새 API로 추가**(예: `AppMark.paint(Canvas canvas, Rect box,
  {bool monochrome = false, Color? monoColor})` + 기하 상수 `boxRect`, `boxRadius`, `boxStroke`, `checkPoints`, `checkStroke`,
  `cutGap`, `shadowOffset`). 뚫린 자리는 체크 둘레 1.5u를 `BlendMode.clear`(또는 `Path.combine(difference)`)로 칸 선에서 지운다.
  **옛 16×16 비트맵 API(`rows`, `monochromeRows`, `colorOf`, `size`)는 이 커밋에서 지우지 않는다** — 로그인(C23)과 런처 생성기(C24)가 아직
  쓴다. 색은 `AppPalette`(배경 `primary`, 칸 `surface`, 체크 `amber`, 두께 `ink`).
- `test/core/theme/app_mark_test.dart`: 옛 비트맵 테스트는 남기고, 벡터 테스트 추가 — 108dp 캔버스 가운데 44dp 상자에 그렸을 때 모든 경로 경계
  (선 굵기 절반·두께 오프셋 포함)가 중심에서 33dp 안, 단색 그리기에 `ink` 두께가 없음, 칸과 체크 사이 뚫린 간격 > 0.
- 화면 변화 없음(아직 아무도 새 API를 안 씀).

### C23 `feat: 로그인·시작 화면 새 모양`  (화면: 로그인 + 인증 대기)
- `lib/features/auth/presentation/login_screen.dart`: 마크 112dp `primary` 둥근 사각(모서리 28) + 4dp ink 두께 안에 `AppMark.paint`(상자 72dp),
  앱 이름 `displayMedium` ink **amber 그림자 제거**, `_BlinkingCursor` 삭제(오너 결정 4), 로그인 버튼 주 버튼 최소 240×56. 옛 비트맵 painter 삭제.
- `lib/features/auth/presentation/auth_gate.dart`: `PixelLoader.medium` → `AppLoader.medium`, 배경 `background`(테마 기본).
- 테스트: `widget_test.dart` "로그인 화면에 구글 로그인 버튼이 보인다" 통과 확인. (선택) 로그인 화면에 반복 애니메이션이 없어
  `pumpAndSettle`이 끝난다.
- P1-2(마크 등장 움직임)는 넣지 않는다 — 시간이 남으면 6단계 뒤 별도 커밋.

**4단계 검증(오너)**: analyze 0, test 전부. 육안: 로그인 첫 화면의 대표색이 브랜드 파랑, 9.2-6, 애니메이션 줄이기.

---

## 5단계 — 앱 밖 정체성 (P0-6) · 커밋 2개

### C24 `feat: 런처·스토어·알림 아이콘과 시작 창 색을 새 마크로`
- `tool/generate_launcher_icons.dart`: `RetroPalette` → `AppPalette`, 비트맵 셀 → `AppMark.paint` 벡터, **안티에일리어싱 켬**, 밀도별 셀 표 삭제 →
  밀도 배율만. 생성물(design 7.2): `mipmap-*/ic_launcher_foreground.png`(108dp, 마크 상자 44dp), `ic_launcher_monochrome.png`(두께 없음),
  `ic_launcher.png`(48dp, 브랜드 둥근 사각 모서리 10dp, 상자 34dp), `drawable-*/ic_notification.png`(**밀도마다 정확히 24dp**, 흰 실루엣,
  상자 20dp), `store/icon-512.png`(꽉 찬 정사각, 상자 300px), `values/colors.xml`(`ic_launcher_background` = `primary`
  `#FF3355FF`, `launch_background` = `background` `#FFEEF1F6`, 주석의 출처 경로 `app_palette.dart`).
- 생성기 실행 후 산출물 **전부 같은 커밋**에 넣는다: `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher{,_foreground,_monochrome}.png`
  (15개), `drawable-{…}/ic_notification.png`(5개), `values/colors.xml`, `store/icon-512.png`.
- `lib/core/theme/app_mark.dart`: 옛 비트맵 API 삭제. `app_mark_test`의 비트맵 테스트 삭제(벡터 테스트만 남음).
- `android/app/src/main/res/drawable/launch_background.xml`·`values-night/styles.xml` 주석의 "paper" → "background"(구조는 그대로 — 다크
  모드에서도 라이트 시작 창).
- `DEPLOY.md` 116행의 `lib/core/theme/retro_palette.dart` → `lib/core/theme/app_palette.dart`(15–17·112–115행 명령 문장은 그대로 맞는다.
  "도트"·"16×16" 문구는 DEPLOY.md에 없음을 확인했다).
- **릴리스 빌드 확인 필수**(네이티브 리소스 변경).
- grep(0): `grep -rnE "AppMark\.(rows|monochromeRows|colorOf|size)|isAntiAlias = false|RetroPalette" tool lib/core/theme/app_mark.dart lib/features/auth`

### C25 `feat: 홈 화면 투두 위젯 새 색·모양`
- `tool/generate_widget_resources.dart`: `RetroPalette` → `AppPalette`, 색 이름 표 = `widget_background, widget_surface, widget_sunken,
  widget_line, widget_outline, widget_ink, widget_ink_muted, widget_danger`(**Kotlin이 쓰는 `widget_danger`·`widget_ink_muted`는 이름 유지**),
  주석 "레트로 색" → 새 설명.
- 생성 후 커밋: `android/app/src/main/res/values/widget_resources.xml`.
- 손으로 고치는 XML:
  - `res/drawable/widget_frame.xml`: layer-list(두께) → 단일 `shape`, `@color/widget_background` 면, 모서리 16dp, 테두리·두께 없음.
    **`widget_paper` 참조를 반드시 없앤다**(생성기에서 이름이 사라져 리소스 링크 오류가 난다 — 이 커밋에서 같이 고쳐야 빌드가 산다).
  - `res/drawable/widget_row.xml`: `widget_surface` + 1dp `widget_line`, `<corners android:radius="10dp"/>`.
  - `res/drawable/widget_check.xml`: `widget_surface` + 2dp `widget_outline`, 모서리 4dp(주석의 "PixelIcons" 설명 갱신).
  - `res/layout/todo_widget.xml`: 제목 13sp → **14sp**(6곳), 보조 10/11/12sp → **12sp**(`widget_pending_*` 6곳, `widget_more`, `widget_center`,
    `widget_note`). id·구조·`maxLines`·`ellipsize`는 그대로.
- Kotlin(`TodoWidgetProvider.kt`)은 고치지 않는다. 단 줄 수 임계값(`rowCountFor`: 80/120/180/250dp)이 글자 크기와 무관한 고정값이라 글자가
  커지면 마지막 줄이 잘릴 수 있다 → "결정 필요" 2. 이 커밋은 임계값을 바꾸지 않고, 오너 육안 결과로 판단한다.
- **릴리스 빌드 확인 필수**(위젯 리소스·레이아웃).
- grep(0): `grep -rn "widget_paper" android tool`

**5단계 검증(오너)**: 두 생성 명령 재실행 → `git status`에 차이 없음(커밋된 산출물이 생성기와 일치), 릴리스 APK 빌드 + `EXIT=0`, 에뮬레이터에서
9.2-12(위젯 최소 크기 줄 수·말줄임 — 위젯 높이를 임계값 경계 80/120/180/250dp 근처로 바꿔 가며 마지막 줄이 잘리는지), 9.2-13(다크 모드에서 앱·
시작 창·위젯 라이트), 9.2-14(알림 아이콘), 런처 아이콘 원형·사각·물방울 모양과 Android 13 테마 아이콘에서 체크가 잘리지 않음.

---

## 6단계 — 잔재 제거와 가독성 검증 · 커밋 1개 + 검증

### C26 `chore: 레트로 테마 잔재와 갈무리 글꼴 제거`
- 삭제(lib): `lib/core/theme/retro_palette.dart`, `retro_text.dart`, `pixel_border.dart`, `pixel_icons.dart`,
  `lib/core/widgets/pixel_icon.dart`, `pixel_frame.dart`, `pixel_loader.dart`.
- 삭제(자산): `assets/fonts/galmuri/Galmuri11.ttf`, `Galmuri11-Bold.ttf`, `LICENSE.txt`(폴더째).
- `pubspec.yaml`: `Galmuri11` 글꼴 항목과 `assets/fonts/galmuri/LICENSE.txt` 자산 줄 삭제(주석 포함).
- `lib/main.dart`: `galmuriLicenseAsset`와 Galmuri `LicenseEntryWithLineBreaks` 삭제(Pretendard만 남김).
- 삭제(test): `test/core/theme/retro_palette_test.dart`, `pixel_border_test.dart`, `pixel_icons_test.dart`(대상이 사라짐 — 각각
  `app_palette_test`·`depth_border_test`·`app_icons_test`가 이어받았다).
- `test/core/theme/font_manifest_test.dart`에 "pubspec에 `Galmuri`가 없다, `assets/fonts/galmuri`가 없다" 추가.
- 커밋 메시지: AAB 크기 0단계 → C2 → C26(갈무리 제거분 포함 최종 증감).
- **최종 잔존 참조 grep — 결과 0이어야 한다**(`docs/`와 `.claude/agent-memory/`의 과거 기록은 대상 아님):
  ```
  grep -rnE "RetroPalette|RetroText|PixelBorder|PixelIcons?\b|PixelIconData|PixelFrame|PixelTone|PixelTag|PixelLoader|neutralPixelTagStyle|RetroButtonStyles|_DoubleOutlineInputBorder|_BlinkingCursor|Galmuri|galmuri|lavender|widget_paper|isAntiAlias = false|stepsSince|FontWeight\.w[56]00" \
    lib test tool pubspec.yaml DEPLOY.md CLAUDE.md android/app/src/main
  grep -rnE "retro_palette|retro_text|pixel_border|pixel_icons?|pixel_frame|pixel_tag|pixel_loader|retro_button_styles" lib test tool DEPLOY.md
  grep -rnE "RetroPalette\.paper|\.paper\b" lib test tool
  git diff --stat 1dac7df -- lib/core/strings.dart   # 비어 있어야 함(문구 변경 0)
  ```

### 6단계 검증 (오너, 코드 커밋 없음 — 고칠 게 나오면 그 화면 이름으로 fix 커밋)
1. `flutter analyze` 이슈 0, `flutter test` 전부 통과(0단계 개수 대비 증감을 진행 기록에 남김).
2. 두 생성 명령 재실행 후 `git status` 깨끗함.
3. `flutter build appbundle --release --dart-define-from-file=env.json` 성공을 **종료 코드로** 확인, AAB 크기 기록.
4. 오픈소스 라이선스 화면(프로필 → 라이선스): **Pretendard 항목이 보이고 Galmuri 항목이 없다.** **Material Icons**(CC BY 4.0 —
   2026-11-08 후속 F3에서 직접 등록. 옛 기재 "Apache 2.0"은 틀렸다) 항목도 보인다.
5. design 9.2 육안 목록 1~14 전부(배율 1.0 / 1.5, 360dp 폭).
6. design 9.3 "사라지는 것" 목록: 픽셀 글꼴(앱·위젯), 계단 모서리, 2dp 전면 잉크 테두리, 창 제목 띠, 12×12 아이콘, 16×16 도트 마크(로그인·
   런처·스토어·알림), 계단식 움직임, ▶ 커서, 이중선 포커스, 크림 팔레트 — 하나도 없음.
7. 9.1 전/후 비교: 0단계 사진과 같은 상태로 다시 찍어 나란히 두고 오너가 "읽힌다" 확인.
8. 다크 모드 기기에서 앱·시작 창·위젯이 라이트 그대로(9.2-13).
9. 효과음·진동 없음, 애니메이션 줄이기에서 버튼 되돌아옴 즉시·로더 정지·VS 정지 화면.

---

## 오너 로컬 검증 명령 (Windows)

Git Bash 기준. 로그를 `tail`로 파이프하면 종료 코드가 가려지므로(CLAUDE.md) **명령 직후 `EXIT=$?`**를 따로 찍는다.

```bash
cd /c/workspaces/<저장소 경로>     # 한글 없는 경로(CLAUDE.md "개발 환경")

flutter pub get;     echo "PUB EXIT=$?"
flutter analyze;     echo "ANALYZE EXIT=$?"
flutter test;        echo "TEST EXIT=$?"

# 5단계(C24·C25)와 6단계: 생성기 — 실행 후 git status로 산출물 차이 확인
flutter test tool/generate_launcher_icons.dart;  echo "ICONS EXIT=$?"
flutter test tool/generate_widget_resources.dart; echo "WIDGET RES EXIT=$?"
git status --short

# C2·C24·C25·C26·6단계: 릴리스 빌드(디버그만으로는 검증되지 않는다)
flutter build apk --release --dart-define-from-file=env.json > build-release.log 2>&1
EXIT=$?; tail -n 30 build-release.log; echo "RELEASE APK EXIT=$EXIT"

# 0단계·C2·C26·6단계: AAB 크기
flutter build appbundle --release --dart-define-from-file=env.json > build-aab.log 2>&1
EXIT=$?; echo "AAB EXIT=$EXIT"; ls -l build/app/outputs/bundle/release/app-release.aab
```

PowerShell이면 `echo` 자리에 `"EXIT=$LASTEXITCODE"`. 실패 메시지가 엉뚱한 플러그인 이름(`FlutterFirebaseCorePlugin not found` 등)으로
나오면 먼저 `android/gradle.properties`의 `android.builtInKotlin=true`를 확인한다(CLAUDE.md 2026-11-05 기록).

| 단계 | analyze/test | 생성기 | 릴리스 APK | AAB 크기 |
|---|---|---|---|---|
| 0 | O(기준선) | | | O(전) |
| C1–C5 | 커밋마다 | | C2만 | C2 |
| C6–C23 | 커밋마다 | | (선택) C10·C20 | |
| C24·C25 | O | O | **O** | |
| C26·6단계 | O | O | **O** | O(후) |

---

## 테스트 변경 요약 (파일 단위)

| 파일 | 처리 | 커밋 |
|---|---|---|
| `test/core/theme/app_palette_test.dart` | **신규** — design 2.2·2.3(A) 대비표 고정, `onFill`, IP hue 가드 | C1 |
| `test/core/theme/retro_palette_test.dart` | C1에서 import 한 줄 추가(`contrastRatio` 이동), C26에서 삭제 | C1, C26 |
| `test/core/theme/font_manifest_test.dart` | **신규** — pubspec의 Pretendard 3굵기·자산 존재, C26에서 Galmuri 부재 추가 | C2, C26 |
| `test/core/theme/depth_border_test.dart` | **신규** — 바깥 크기 불변, 두께 위치, 비대칭 보간, copyWith | C3 |
| `test/core/theme/pixel_border_test.dart` | 대상과 함께 삭제 | C26 |
| `test/core/theme/retro_text_test.dart` → `app_text_test.dart` | **git mv + 새 기대값**(이 커밋에서 깨지므로) | C4 |
| `test/core/theme/app_theme_test.dart` | **신규** — 버튼 상태별 모양, 줄이기 시 0ms, 팔레트 밖 색 없음, 이중선 제거 | C4 |
| `test/core/theme/app_icons_test.dart` | **신규** — 상수 서로 다름, 금지 도형 없음 | C4 |
| `test/core/theme/pixel_icons_test.dart` | 대상과 함께 삭제(design 9장 2단계) | C26 |
| `test/main_text_scale_test.dart` | **신규** — `maxTextScale == 1.5` | C5 |
| `test/core/widgets/app_panel_test.dart` | **신규** — 변형별 모양, 제목 띠 없음, 줄이기 | C6 |
| `test/features/battle/presentation/battle_chips_test.dart` | 새 기대값 — 5.3 표, 미결 아이콘, 무에 위험·경고색 없음, 배지 `byIcon` | C7 |
| `test/features/battle/recruit_browse_test.dart` | C7: `AppTag`/`neutralTagStyle`/`AppPalette`; C15: 띠 4dp, `byIcon(AppIcons.clock)` | C7, C15 |
| `test/features/battle/my_battles_sections_test.dart` | C7: `byType(AppTag)`; C14: 배율 1.5 | C7, C14 |
| `test/core/widgets/app_loader_test.dart` | **신규** — 줄이기 시 정지·색, 시맨틱 라벨 | C8 |
| `test/core/widgets/initial_badge_test.dart` | 위젯 테스트 추가(면 → 글자색, 크기) | C9 |
| `test/widget_test.dart` | C10: 탭바 스모크 1.5; C21: VS 긴 이름 1.5 | C10, C21 |
| `test/features/battle/presentation/vs_intro_test.dart` | 새 타임라인 기대값, 50ms 계단 테스트 삭제, 겹침 허용 검사 | C21 |
| `test/core/theme/app_mark_test.dart` | C22: 벡터 안전 원 테스트 추가; C24: 비트맵 테스트 삭제 | C22, C24 |
| 그 밖 `test/features/**`(battle_judgment, battle_evidence, battle_detail_load, create_battle, edit_recruit_criteria, recruit_sheet, ai_consent, notification_section, battle_join_vs_intro 등) | 변경 없이 통과해야 함 — 실패하면 화면 커밋이 조작 경로를 바꿨다는 신호 | 해당 화면 커밋 |
| 골든 테스트 | 없음(만들지 않음) | — |

배율·넘침 테스트는 테스트 글꼴(정사각형)과 `NavigationBar`·`SegmentedButton`·`Wrap`의 clamp 때문에 넘침을 보장하지 못한다
(agent-memory gotchas 6). 1.5로 올린 테스트는 "예외 없이 그려진다"까지만 보장한다고 주석에 적고, 나머지는 육안 목록에 맡긴다.

---

## 설계와 다른 점

구현 세션이 따를 결정이다. 오너 확인이 필요한 것은 "## 결정 필요"로 따로 올렸다.

1. **버튼 눌림의 곡선과 줄이기 처리.** Material 버튼의 모양 애니메이션은 `ButtonStyle.animationDuration` 하나로 양방향 같은 길이이고 곡선도
   Material 내부값이다. design 4.2의 "누를 때 0 ms / 뗄 때 120 ms `easeOutCubic`"은 `DepthBorder`의 보간을 비대칭으로 만들어(눌림 쪽은 즉시)
   낸다. 버튼의 되돌아옴 곡선은 Material 내부 곡선이 되어 `easeOutCubic`과 조금 다를 수 있다(`AppPanel`은 `AnimatedContainer`라 정확히
   `easeOutCubic`). 애니메이션 줄이기는 테마가 `MediaQuery`를 못 보므로 `MaterialApp.builder`에서 `AppTheme.build(reduceMotion: true)`로
   감싸 처리한다. 라벨이 면과 함께 내려가는 것은 상태별 `padding`으로 낸다(즉시 이동이라 뗄 때 라벨이 면보다 120 ms 먼저 올라온다 —
   육안 9.2-11에서 거슬리면 라벨 이동을 빼고 면만 움직인다).
2. **FAB은 눌림 없이 정적 두께.** `FloatingActionButtonThemeData.shape`는 상태별 값을 받지 않는다. 현행(레트로)도 FAB은 눌림이 없었다.
   FAB 전용 위젯을 새로 만들지 않는다(사소한 UI 결정 — 결과만 보고).
3. **체크박스 24dp.** Flutter `Checkbox`는 18dp 고정이라 테마로 키울 수 없다. 쓰는 곳이 할 일 목록 하나뿐이므로 그 자리에서
   `Transform.scale(24/18)`로 키운다(터치 영역 48은 `materialTapTargetSize.padded`가 유지).
4. **앱바 "스크롤되면 1dp 선"은 생략.** `AppBarTheme.shape`는 스크롤 상태를 받지 않는다. 기준 화면 표(5.5)의 "경계선 없음"으로 통일한다.
5. **찾기 탭 아이콘은 채움/윤곽 구분 없음.** `search_rounded`에 윤곽 변형이 없다. 선택은 표시기·색·라벨 굵기 셋으로 구분된다.
6. **미결 칩의 경고 아이콘은 `AppTagStyle.icon`에 싣는다**(design 5.2는 `AppTag`의 인자로 적음). 매핑 함수의 결과로 테스트할 수 있게
   하려는 것이고, 화면 쪽 사용법은 같다.
7. **승 라벨 두께 2dp.** design 4.1 표는 승 라벨을 3dp `depthButton` 줄에 넣었지만 5.2(`AppTag` raised = 2dp)·5.3(승 = 2dp ink 두께) 두 곳이
   2dp라 2dp를 따른다.
8. **VS 타임라인 구간이 겹친다**(띠 0–200, 명판 150–550). 현 테스트의 "구간이 겹치지 않고 이어진다" 검사는 새 설계와 모순이라 "구간이 0~1500
   안"으로 바꾼다. compact 이니셜은 design 6.2의 48(현행 40)을 따른다.
9. **브랜드 묶음 토큰 이름은 역할 이름**(`primary/primaryDeep/primaryPale/secondary/judging/judgingPale`). design 2.2는 `violet/violetPale`로
   적었지만 같은 문서가 "C는 judging/Pale로 이름 통일 권장"이라 했고, 오너 결정이 "이견이 나오면 토큰 값만 바꾸면 되도록"이므로 색 이름이
   아니라 역할 이름을 쓴다. `secondary`는 `amber`와 같은 값의 별칭이다.
10. **서체 파일은 OTF**(design "OTF 또는 TTF"). 같은 굵기의 TTF보다 굵기당 1.1 MB 작다. 버전 1.3.9.
11. **홈 위젯 "그 외 N개가 대신 받는다"는 자동이 아니다.** 줄 수는 Kotlin `rowCountFor`가 위젯 높이만 보고 고정 임계값으로 정한다. 글자를
    키워도 줄 수가 줄지 않고 마지막 줄이 잘릴 수 있다 → "결정 필요" 2.
12. **DEPLOY.md 116행은 고쳐야 한다**(design 7.2는 "문장 그대로 맞는다"고 했지만 그 행이 `retro_palette.dart` 경로를 적고 있다).
13. **로그인을 3단계에서 4단계로 옮겼다**("순서를 바꾼 기록" 1).
14. **전/후 비교의 "전 1.5" 사진은 1.3으로 찍힌다**(현행 상한 1.3).
15. **세그먼트 체크 아이콘은 판정 창 2개에만 켠다**(design 5.5 기준 화면 2가 명시한 곳). 나머지 5개(대결 만들기 유형·기간 단위, 찾기 필터 2개 등)는
    지금처럼 `showSelectedIcon: false` → "결정 필요" 1.
16. **탭 라벨이 14 → 12dp로 작아진다**(design 3.2 `labelSmall`). 10-29 가독성 개정이 올린 값을 되돌리는 것이라 육안 9.2-1에서 오너가 함께 본다.
    그대로 design을 따른다.

## 순서를 바꾼 기록
1. **로그인·시작 화면(C23)을 3단계 화면 목록에서 빼 4단계 앱 마크(C22) 뒤로 옮겼다.** 로그인 마크는 design 9.4가 7.1의 벡터 마크를 쓰라고
   했는데 그 마크는 design 9장에서 5단계 작업이다. 3단계에 두면 로그인을 옛 비트맵 마크로 한 번, 벡터로 또 한 번 고쳐야 한다. 벡터 마크를
   새 API로 먼저 추가(C22)하고 로그인(C23) → 런처 생성기(C24) 순으로 옮긴 뒤 옛 비트맵 API를 지운다.
2. **잔재 제거(C26)를 5단계 뒤로 미뤘다.** 생성기 두 개(`tool/`)가 C24·C25까지 `RetroPalette`를 쓰고, `analyze`가 `tool/`도 보기 때문에 그 전에
   지우면 컴파일이 깨진다.
3. **`maxTextScale` 1.5(C5)는 design대로 1단계에 두되, 배율 테스트 세 개는 각 화면 커밋에서 1.5로 올린다.** 옛 조각이 남은 화면에 1.5 단정을
   먼저 걸면 개편과 무관한 이유로 깨질 수 있다.
(구현 중 순서를 또 바꾸면 이 절에 이유를 적는다.)

---

## 결정 필요

1. **세그먼트 선택 체크 아이콘을 어디까지 켤까?** design 5.1은 세그먼트 일반 규칙으로 "선택 시 체크 아이콘(색에만 기대지 않게)"을 적고, 바꿀 곳으로는
   판정 창만 짚었다. 지금 앱의 세그먼트 7개는 전부 `showSelectedIcon: false`다.
   - (a) 판정 창 2개만(계획 기본값) — 되돌릴 수 없는 선택이라 가장 필요한 곳, 360dp·1.5배에서 칸이 좁은 찾기 필터(3~4칸)를 건드리지 않는다.
   - (b) 7개 전부 — 앱 전체 규칙이 하나가 되지만 찾기 필터·기간 단위 칸에서 라벨 줄바꿈이 늘 수 있다(육안 9.2-3 재확인).
   - 추천: **(a)로 구현하고 6단계 육안 때 (b)를 한 번 켜 보고 결정.**
2. **홈 위젯 글자를 14/12sp로 키운 뒤 마지막 줄이 잘리면?** `TodoWidgetProvider.rowCountFor`(Kotlin)의 임계값(80/120/180/250dp → 1/2/3/5/6줄)은
   글자 크기와 무관하다. 시스템 글꼴 크기(`sp`)까지 커지면 더 쉽게 잘린다.
   - (a) 임계값을 실측에 맞춰 조금 올린다(예: 3줄 기준 120 → 130dp) — 네이티브 동작 변경이지만 Dart `visibleRows` 규칙(유닛 테스트 고정)은
     그대로라 두 언어 규칙이 어긋나지 않는다.
   - (b) 글자 크기를 design 이전 값으로 되돌린다(오너 결정 3을 뒤집음).
   - 추천: **C25 뒤 육안에서 실제로 잘릴 때만 (a).** 안 잘리면 아무것도 하지 않는다.
3. **Material Icons 라이선스(Apache 2.0) 고지가 라이선스 화면에 없으면?** design 5.4가 "없으면 추가"라고 했다. 추가하려면 원문 파일이 필요하다.
   - 출처 후보: `google/material-design-icons` 저장소의 `LICENSE`(GitHub), 또는 npm `material-icons` 패키지의 LICENSE(이 컨테이너에서는 npm만
     닿는다). `assets/licenses/material-icons-LICENSE.txt` + `LicenseRegistry`에 `['Material Icons']`로 등록.
   - 추천: 6단계 4번 확인 결과가 "없음"일 때만 추가(별도 `chore` 커밋).
4. **CLAUDE.md "개발 명령어"에 `flutter test tool/generate_widget_resources.dart`가 없다.** 이번에 두 생성 명령을 함께 돌리므로 한 줄 추가를 제안한다
   (CLAUDE.md "새 명령어가 생기면 여기에 추가" — 수정은 메인 세션·오너 몫).
5. **`TODO_BACKLOG.md` 9행("레트로 테마 가독성 2차")은 이번 개편으로 대상이 사라진다.** 지우거나 "redesign으로 대체"로 닫을지 메인 세션이 정한다.

---

## 위험 요소

1. **이 환경에서 한 번도 컴파일·테스트하지 못한다.** 가장 흔할 실패: 없는 `Icons.*` 상수 이름(analyze가 즉시 잡음 → design 5.4 대안 열),
   `unused_import`, `const` 생성자 불일치(`AppPanel`·`AppTag`를 `const`로 쓰던 호출부). 커밋마다 오너 결과를 받고 넘어간다.
2. **1.5배 레이아웃.** `Row`가 넘치면 `RenderFlex` 예외로 기존 위젯 테스트가 깨질 수 있다(특히 C14 내 대결 카드, C12 상대 카드·우열 세그먼트,
   C21 VS 명판). 테스트 글꼴이 실제보다 넓어 실기기에서는 멀쩡한데 테스트만 깨질 수도 있다(gotchas 6) — 그때는 테스트 기대를 낮추지 말고
   레이아웃을 `Wrap`/`Flexible`로 고친다.
3. **버튼 눌림 구현의 불확실성**("설계와 다른 점" 1). Material 내부 동작(모양 보간·padding 재배치)에 기대므로 실기기에서 눌림이 덜 보이거나 라벨이
   튈 수 있다. 9.2-11 육안이 관문이다.
4. **중간 상태가 섞여 보인다.** C4~C25 사이 화면은 새 테마 위에 옛 픽셀 조각이 섞인다. 이 상태를 Play(내부 테스트 제외)에 올리지 않는다. 중간 육안
   확인은 "그 커밋이 바꾼 화면"만 본다.
5. **홈 위젯 줄 잘림**("결정 필요" 2)과 **RemoteViews 둥근 모서리**: 런처마다 위젯 바깥 모서리를 따로 깎는다(Android 12+ 시스템 반지름). 위젯 틀
   모서리 16dp가 시스템 모서리와 어긋나 보일 수 있다 — 육안 9.2-12.
6. **글꼴 획득 경로**: 구현 환경에서 npm·GitHub 모두 막히면 C2를 미룬다(C2 대안 4). 그동안 앱은 시스템 글꼴로 보여 Pretendard 기준 육안 확인이
   늦어진다.
7. **AAB 크기**: 자산 기준으로는 줄지만(−3.27 MB) Material Icons 글리프가 늘어난다(트리 셰이킹으로 쓰는 것만). 실측 전까지 확정이 아니다.
8. **`flutter analyze`가 `tool/`을 본다**는 사실을 잊고 C24·C25 전에 `RetroPalette`/비트맵 `AppMark`를 지우면 analyze가 깨진다(C26을 마지막에 둔 이유).
9. **위젯 리소스 이름 변경**(`widget_paper` → `widget_background`): 생성기와 `widget_frame.xml`을 같은 커밋에서 바꾸지 않으면 리소스 링크 오류로
   **릴리스·디버그 빌드가 모두** 깨진다(이것은 `flutter test`로는 안 잡힌다 — C25의 릴리스 빌드 확인이 관문).
10. **전/후 스크린샷을 0단계에서 놓치면 다시 못 찍는다**(수용 기준 "오너 확인" 항목). C1 전에 반드시.

---

## 진행 기록
(구현 세션이 커밋마다 해시·analyze/test 결과·특이사항을 적는다.)

- 0단계 기준선: analyze __ / test __개 / AAB __ B
- 1단계(2026-11-08, 클라우드 세션 — Flutter SDK 없음, analyze/test 미실행. 오너 로컬 결과 대기):
  - C1 `f228076` AppPalette + app_palette_test. 모든 대비 쌍을 WCAG 공식으로 다시 계산해 설계값 ±0.05 확인.
  - C2 `aeb85df` Pretendard 번들. npm tarball·OTF 3개·LICENSE sha256 모두 이 문서 표와 일치. cmap 한글 11,172 × 3,
    GSUB `tnum` × 3을 이 세션에서 다시 셌다. AAB 크기 미측정(오너 로컬).
  - C3 `fb00ede` DepthBorder + depth_border_test.
  - C4 `ab6cdd2` AppText·AppIcons·AppTheme 재작성 + app_text_test(git mv)·app_theme_test·app_icons_test.
    plan과 다른 작은 결정: 주 버튼 포커스 링은 ink 2dp(primary 면 위 primary 링이 안 보임), 비활성 버튼 라벨 여백 위아래 0.
  - C5 `45cecd3` `maxTextScale` 1.5 + main_text_scale_test.
  - 순서 변경 없음.
  - 1단계 끝 검증: 2단계 세션이 C6 착수 전에 HEAD `45cecd3`에서 다시 돌림 — analyze 0건, test 566개 통과.
- 2단계(2026-11-08, 클라우드 세션 — 이번에는 Flutter SDK 있음. 커밋마다 `flutter analyze`·`flutter test`를 돌려 둘 다 통과한 뒤 커밋.
  Android SDK가 없어 릴리스 빌드는 못 돌림 — 2단계는 네이티브 변경이 없어 plan상 필수 아님, C10 선택 확인은 오너 로컬 몫):
  - C6 `5fd75a6` AppPanel + app_panel_test(8). analyze 0 / test 574.
  - C7 `2943fd3` AppTag·상태 칩·결과 라벨 새 매핑, pixel_tag.dart 삭제. battle_chips_test 새 기대값(12 → 19개),
    recruit_browse_test·my_battles_sections_test 이름 교체. analyze 0 / test 581. grep `PixelTag|neutralPixelTagStyle|pixel_tag` 0.
  - C8 `49b7ce9` AppLoader, StatusMessage·EvidencePhotoFrame 새 모양, 할 일·찾기의 `StatusMessage.empty(icon:)` 호출부 교체.
    app_loader_test(5, 선택 항목인 증거 사진 clip 없음·contain 포함). analyze 0 / test 586.
  - C9 `c293cfd` InitialBadge 새 모양, AppButtonStyles.danger, retro_button_styles.dart 삭제, 호출부 4파일. initial_badge_test 위젯
    테스트 4개 추가. analyze 0 / test 590. grep `RetroButtonStyles|retro_button_styles` 0.
  - C10 `a43d5bc` 탭바 1dp line 경계, 윤곽/채움 아이콘. widget_test 탭바 스모크 1.3 → 1.5. analyze 0 / test 590.
    grep `Pixel|Retro` in main_shell.dart 0.
  - 커밋마다 `git diff --stat -- lib/core/strings.dart` 비어 있음(문구 변경 0). 새 패키지 0, `pubspec.lock` 변경 없음.
  - 순서 변경 없음. plan과 다르게 한 작은 결정(사소한 UI — 결과만 보고):
    1. `AppTag`의 `style.icon` 색은 테두리색, 테두리가 없으면 글자색(plan 그대로). 상태 칩 `voided`는 `voidedResultTagStyle` 상수를
       그대로 쓴다(값이 같아 두 상수를 따로 둘 이유가 없음 — 무효 칩 = 무효 라벨이 테스트로 고정됨).
    2. `StatusMessage`의 문장 ↔ 보조 문장 간격 4 → 12(design 5.2 "간격 12"를 모든 요소 사이로 읽음).
    3. `EvidencePhotoFrame` 실패 아이콘 색은 기존대로 `ink`(plan·design에 색 지정 없음).
    4. `AppPanel.tone` 제목은 `titleSmall` ink(옛 `labelLarge`), 제목 ↔ 본문 간격 4(design 4.1 "제목 ↔ 본문 4").
    5. widget_test 탭바 스모크에 "선택 탭만 채운 아이콘" 단정을 더했다(1.5 배율 변경과 같은 테스트).
- 3단계(2026-11-08, 클라우드 세션 — Flutter SDK 있음, Android SDK 없음. 커밋마다 `flutter analyze`·`flutter test`를
  돌려 둘 다 통과한 뒤 커밋. 릴리스 빌드는 못 돌림 — 3단계는 네이티브 변경이 없어 plan상 필수 아님, C20 선택 확인은 오너 로컬 몫):
  - C11 `9dc2fe1` 할 일 목록. analyze 0 / test 590.
  - C12 `719a577` 판정 창·기준 묶음·상대 카드. recruit_sheet_test `_tapJoin` 앞에 `ensureVisible` 추가(시트가 길어져 참가 버튼이
    800x600 화면 밖 y=600으로 밀림 — 단정·기대값 변경 없음). analyze 0 / test 590.
  - C13 `0be46ba` 대결 상세 머리·증거·결과 배너·포기. analyze 0 / test 590.
  - C14 `5ed36eb` 내 대결. my_battles_sections_test 배율 1.3 → 1.5, 강조 줄 굵기 기대값 w600 → w700 2곳. analyze 0 / test 590.
  - C15 `52e00cd` 대결 찾기. recruit_browse_test 띠 폭 8 → 4, 시계 finder `Icon(AppIcons.clock)`. analyze 0 / test 590.
  - C16 `73eb637` 모집 상세 시트. analyze 0 / test 590.
  - C17 `f90dcf1` 대결 만들기. analyze 0 / test 590.
  - C18 `3a98644` 모집 기준 수정. analyze 0 / test 590.
  - C19 `52d9206` AI 데이터 제공 동의. analyze 0 / test 590.
  - C20 `083aff5` 프로필(점수·전적·기록·동의·알림·계정). analyze 0 / test 590.
  - C12 후속 `0693eff` `fix:` 판정 창 info 아이콘을 첫 줄 높이(글자 배율 반영) 가운데로 — 1.5배 스크린샷에서 첫 줄보다 위로 붙어
    보여서. analyze 0 / test 590.
  - 커밋마다 `git diff --stat -- lib/core/strings.dart` 비어 있음(문구 변경 0). 새 패키지 0, `pubspec.lock` 변경 없음.
  - 3단계 끝 잔존 참조 grep(`PixelFrame|PixelTone|PixelIcon\b|PixelIcons|PixelLoader|RetroText|RetroPalette|FontWeight\.w[56]00` in lib):
    허용 목록과 정확히 같다 — `app_mark.dart`, `pixel_border/pixel_icons/retro_palette/retro_text.dart`, `pixel_frame/pixel_icon/
    pixel_loader.dart`, `auth_gate.dart`·`login_screen.dart`(C23), `vs_intro.dart`(C21).
  - 순서 변경 없음(C12 후속 fix 한 개가 더해졌을 뿐 화면 순서는 plan 그대로).
  - plan과 다르게 한 작은 결정(사소한 UI — 결과만 보고):
    1. 할 일 수정 열기 탭을 `ListTile.onTap`에서 `AppPanel(onTap:)`으로 옮겼다 — design 5.5 "누르면 두께가 꺼진다"를 내려면 묶음이
       탭을 받아야 한다. 체크박스·삭제 버튼은 안쪽 위젯이라 그대로 먼저 받는다. 할 일 줄 최소 높이 60은 `ListTile.minTileHeight`.
    2. 기준 번호·결과 배너 점수 변화는 옆 문장과 글자 기준선을 맞췄다(`CrossAxisAlignment.baseline`).
    3. 줄이 넘칠 수 있는 칩·숫자 줄은 `Row` → `Wrap`: 대결 상세 머리(배지+상태 칩), 상대 카드 점수·전적, 모집 카드·모집 시트의
       배지+기간 칩, 프로필 점수+전적(기준선 대신 아래 끝 맞춤). 동의 화면 개인정보처리방침 라벨은 `Flexible`.
    4. 모집 카드 유형 색 띠(4dp)는 카드 가장자리가 아니라 안쪽 여백(왼쪽 12) 안에 끝이 둥근 띠로 뒀다. 모서리 16 카드가 내용을 깎지
       않아(clip 없음) 가장자리에 붙이면 띠가 둥근 모서리 밖으로 삐져나온다. 띠는 여전히 카드 내용 높이를 채운다(테스트 유지).
    5. 대결 만들기 입력 단계의 동의 전·한도 소진 안내를 tone neutral → danger로 바꿨다(design 5.5 "차단·한도 안내 tone danger").
    6. 포기 확인 대화상자의 [포기]를 `FilledButton.styleFrom(backgroundColor: error)` → `AppButtonStyles.danger`(같은 색, 비활성 규칙 통일).
    7. 모집 시트 위 여백 16 → 8(테마 손잡이가 이미 띄움), 찾기 조작판 요소 사이는 8 유지(목록 높이를 아끼려고 — design "묶음 안 12"의
       예외로 둔다).
    8. "판정은 한 번만" info 아이콘은 첫 줄 높이 상자 가운데(위 fix).
  - **전/후 스크린샷**(design 9.1, 저장소 밖): 위젯 테스트 환경에서 360x800 논리 크기 · devicePixelRatio 2, 실제 Pretendard·
    Material Icons·Galmuri(전) 글꼴을 로드해 PNG로 떴다. "전"은 C1 직전 `cb7f1bc`의 git worktree. 기기 기본 글꼴 자리는 Noto Sans KR
    (npm `@expo-google-fonts/noto-sans-kr` 0.4.4)로 대신했다 — 실기기의 Noto Sans CJK KR과 같은 계열이지만 같은 파일은 아니다.
    배율은 전 1.0·1.3(당시 상한), 후 1.0·1.5. 사진은 가짜 HTTP로 넣은 그림. 골든 테스트로 저장소에 넣지 않았다.
  - 육안으로 확인할 것(스크린샷에서 본 것): 판정 세그먼트는 배율 1.0에서 "상대가 더 잘했어요"(체크 아이콘 포함)가 두 줄, 1.5에서 네 칸 모두
    두 줄이고 "통과했어\n요"처럼 음절 단위로 끊긴다 — design 5.5가 허용한 "라벨 두 줄"이지만 끊김이 어색하면 "두 칸 위아래로 쌓기"를 오너가
    판단(9.2-2). 할 일 1.5배에서 마지막 완료 줄이 FAB에 일부 가리지만 아래 여백 96으로 스크롤하면 드러난다.

- 4~6단계(2026-11-08, 클라우드 세션 — Flutter SDK 있음, Android SDK 없음. 커밋마다 `flutter analyze`·`flutter test`를 돌려
  둘 다 통과한 뒤 커밋. 릴리스 빌드·AAB 크기는 못 돌림 → 오너 로컬 몫):
  - 선행 fix `3e3bf16` 판정 선택지 라벨이 단어 중간에서 줄바꿈되지 않게. `KeepWordsText`(`lib/core/widgets/keep_words_text.dart`)가
    그릴 때만 어절 안 글자 사이에 WORD JOINER(U+2060)를 끼운다(strings.dart 그대로, semanticsLabel 원문). 그래도 한 어절이 칸보다
    넓으면(360dp·1.5배에서 체크 아이콘이 붙은 "통과했어요" — Material이 체크가 붙은 칸의 여백을 덮어써 여백 조정으로는 못 넓힘)
    가장 넓은 어절을 재서 두 칸을 위아래로 쌓는다(`SegmentedButton.direction`, 판정 두 질문 공용 `_ChoicePair`). 테스트: keepWords 단위,
    좁은 폭 비교(그냥 Text는 어절 중간·KeepWordsText는 경계), 판정 창 360dp 1.0·1.5에서 네 라벨 모두 어절 경계에서만 끊김 + 1.5에서
    최소 기준 쌍은 세로. `battle_judgment_test`의 선택지 finder는 `KeepWordsText.text`(원문)로 찾게 바꿨다(단정 그대로).
    analyze 0 / test 599. 버튼 라벨("판정 보내기" 등)은 1.5배에서도 한 줄이라 손대지 않았다.
  - C21 `882629a` VS 인트로. analyze 0 / test 601.
  - C22 `55cfb96` 벡터 앱 마크(옛 비트맵 API 유지). app_mark_test에 벡터 테스트 4개(실제로 그려 픽셀 확인). analyze 0 / test 605.
  - C23 `cd5797b` 로그인·인증 대기. widget_test에 "로그인 화면에는 반복 움직임이 없다" 추가. analyze 0 / test 606.
  - C24 `2230624` 런처·알림·스토어 아이콘·colors.xml(생성기 실제 실행 산출물 22개), 옛 비트맵 API·테스트 4개 삭제, launch_background
    주석, DEPLOY.md 4번. 생성기 재실행 → `git status` 깨끗(재현됨). analyze 0 / test 602.
  - C25 `828b722` 홈 위젯 색·모양·글자. 생성기 재실행 → 깨끗. `widget_paper` 잔존 0(android·tool·lib), android/ 안의 모든
    `@color/`·`@drawable/` 참조가 정의돼 있음을 스크립트로 대조, Kotlin이 쓰는 리소스(`R.color.widget_danger`·`widget_ink_muted`,
    `R.string.todo_widget_no_cache`, `R.layout.todo_widget`) 존재. analyze 0 / test 602.
  - C26 `fd55d2a` 잔재·갈무리 제거. 최종 grep 세 명령 0건, `git diff --stat 1dac7df -- lib/core/strings.dart` 비어 있음,
    `pubspec.lock` 변경 없음. analyze 0 / test 504(삭제 100 = retro_palette 3 + pixel_border 5 + pixel_icons 92, 추가 2).
  - 순서 변경 없음.
  - plan과 다르게 한 것(사소한 UI·구현 판단 — 결과만 보고):
    1. 판정 선택지 세로 쌓기(위 fix). plan "위험 요소" 2·3단계 기록의 "두 칸 위아래로 쌓기(오너 판단)"를 **넓이가 모자랄 때만**
       자동으로 적용했다. 배율 1.0 360dp에서는 지금처럼 가로 두 칸이다.
    2. C21 VS 명판·라벨 좌우 여백 16 → 20(화면 가장자리 규칙 4.1).
    3. C22 뚫린 자리는 체크 긴 획의 **가운데~끝** 둘레로만 낸다(긴 획 전체면 아래 꺾임의 둥근 끝이 칸 아랫선을 갉는다). 색 마크는
       체크 두께(아래 1.5u)까지 둘레로 지운다(체크 면만 지우면 두께가 간격을 메운다).
    4. C24 plan의 grep(`... RetroPalette" tool ...`)은 C25 전까지 `tool/generate_widget_resources.dart`에 걸린다(plan 자체의 순서
       모순). C24 시점에는 런처 생성기·app_mark·auth만 0이었고 C26 최종 grep은 0.
    5. C24 DEPLOY.md는 116행 외에 113행("그림은 tool/에 코드로")도 실제 위치(`app_mark.dart`)로 고쳤다.
    6. C26 font_manifest_test의 "갈무리 없음"은 옛 글꼴 이름을 적지 않고 "패밀리·글꼴 자산·assets/fonts 폴더가 Pretendard뿐"으로
       고정했다(이름을 적으면 plan의 최종 grep이 test/에서 걸린다).
    7. C26 TODO_BACKLOG: 9행(가독성 2차)뿐 아니라 8행(배율 상한 1.5 재검증, `maxTextScale = 1.3` 서술)도 C5로 사실이 바뀌어 닫았다.
       DEPLOY.md에 "스토어 스크린샷은 옛 화면" 주의와 라이선스 화면 Pretendard 확인 항목을 더했다.
  - **하지 않은 것(메인 세션·오너 판단 필요)**:
    1. CLAUDE.md "개발 명령어"에 `flutter test tool/generate_widget_resources.dart  # 홈 위젯 색·문구 리소스 다시 생성` 한 줄
       (결정 4). 서브에이전트는 CLAUDE.md를 고치지 않는다 — 메인 세션이 넣는다. CLAUDE.md 본문에는 레트로·도트 테마를 전제로 한
       문장이 없음을 확인했다(도메인 규칙·VS 인트로 예외 문장은 테마와 무관).
    2. Material Icons 라이선스 고지(결정 3): Flutter 도구는 NOTICES를 pub 패키지 LICENSE와 sky_engine LICENSE로만 만들고
       (`flutter_tools/lib/src/license_collector.dart`), sky_engine LICENSE에 Material Icons 항목이 없다 → 라이선스 화면에 **없을
       가능성이 높다**. 그런데 Flutter SDK가 아이콘 글꼴과 함께 두는 원문(`bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt`,
       sha256 `be698262…8a9e74`)은 design 5.4가 적은 Apache 2.0이 아니라 **CC BY 4.0**이다. 어느 원문을 넣을지 확정하지 못해 추가하지
       않았다 — 오너가 6단계 4번 육안으로 "없음"을 확인하면 원문 선택과 함께 별도 `chore` 커밋으로.
  - 스크린샷(저장소 밖, `final_` 접두어): 판정 창 1.0·1.5(위·빈 상태·고른 상태), VS 인트로 정지 화면(짧은/긴 이름, 가로 모드)·
    진행 중 180/650/800ms, 로그인 1.0·1.5, 할 일 1.0·1.5.
  - 육안으로 볼 것(스크린샷에서 본 것): 판정 질문·안내 **문장**(titleSmall·bodyMedium)은 여전히 음절 단위로 끊긴다("통과 / 했나요?") —
    이번 fix는 선택지 라벨만 대상. 1.5배에서 최소 기준 쌍은 세로, 우열 쌍은 가로 두 줄이라 두 질문의 배치가 다르다. VS 가로 모드
    1.5배는 아래 "나" 라벨이 화면 끝에 붙는다(잘리지는 않음).

- 후속(2026-11-08, 클라우드 세션 — Flutter SDK 있음, Android SDK 없음. 커밋마다 `flutter analyze`·`flutter test` 종료 코드를
  따로 확인해 둘 다 0일 때 커밋. 오너 결정 "2026-11-08 후속" F1–F8):
  - `64c0eea` docs: 오너 결정·후속 순서 기록.
  - F1 `9305e6a` 어절 줄바꿈 전역. `KeepWordsText`를 `Text` 하위 클래스로(data는 원문, build 동안만 WORD JOINER 글자를 RichText로,
    글자가 바뀐 경우에만 semanticsLabel=원문). lib의 표시용 `Text(` 206곳 교체. 제외: `SelectableText`(개인정보처리방침 URL 복사),
    TextField 입력값·InputDecoration 문자열(힌트·라벨·카운터, Material 내부 Text), 툴팁 문자열, Material 내부 화면(라이선스 페이지 등).
    `keepWords`는 양쪽 다 ASCII인 글자 사이에는 끼우지 않음. 기존 테스트 finder는 원문 그대로 동작해 1개(낭독 테스트)만 고침.
    analyze 0 / test 513.
  - F2 `eff6845` "내 차례" 줄 titleSmall(16/700), 편집·기간 오류 bodyMedium. analyze 0 / test 513.
  - F3 `3e3e72c` Material Icons CC BY 4.0 고지 자산·등록(`registerFontLicenses`)·테스트, design.md 정정 4곳, DEPLOY.md 항목. analyze 0 / test 515.
  - F4 `03b2f35` `AppTheme.fabClearance`(값 96 그대로) + 할 일·찾기 1.5배 끝까지 내렸을 때 가림 없음 테스트. 스크린샷의 가림은
    스크롤 전 모습이었다(여백 16으로 줄이면 두 테스트 실패 확인). analyze 0 / test 517.
  - F5 `dec10ff` 모집 카드 두 버튼 모두 보조 버튼, 동의 철회 `AppButtonStyles.dangerOutlined`. analyze 0 / test 520.
  - F6 `c54bb3a` 상대 카드 이름 titleMedium(18/700). analyze 0 / test 521.
  - F7 `4438636` 카운터 inkMuted·400, "직접 입력" −12 이동 정렬. analyze 0 / test 522.
  - F7 `d3d5858` 교체 가능 상태의 안내 블록(SubmittedWaitingOpponent) 표시 제거, 힌트(ReplaceHint) 유지. analyze 0 / test 522.
  - F7 `0181b7b` VS 인트로: 명판 이름이 자리 이름("나"/"상대")과 같으면 자리 이름 줄 숨김. analyze 0 / test 524.
  - F8 이 커밋: TODO_BACKLOG 다섯 줄(스토어 스크린샷 재촬영은 이미 백로그·DEPLOY.md 4번에 있어 추가 안 함), 이 기록.
  - 커밋마다 `git diff --stat -- lib/core/strings.dart pubspec.lock` 비어 있음. 새 패키지 0.
  - 순서 변경 없음(F7을 작은 커밋 셋으로 나눴을 뿐).
  - 스크린샷(저장소 밖, `fixed_` 접두어): 0181b7b에서 두 촬영 스크립트를 수정 없이 실행.

## 오너 결정 (2026-11-08)
- 검증 방식: **구현은 클라우드 세션, 검증은 오너가 Windows 로컬에서.** 단계 단위로 끊는다 — 1단계(C1–C5)를 푸시하고 멈춘 뒤,
  오너의 `flutter analyze`/`flutter test` 결과를 받고 다음 단계로 간다.
- "## 결정 필요" 5건은 **developer 기본안대로**.
- 0단계 "전" 스크린샷은 개편 커밋 이전 커밋(이 브랜치의 C1 직전)을 체크아웃해 언제든 찍을 수 있다.

## 오너 결정 (2026-11-08 후속)
redesign HEAD `faf9058`(analyze 0 / test 504) 이후 스크린샷 검토에서 나온 후속 수정. 전부 추천안.

1. **한글 어절 단위 줄바꿈을 앱 전체 본문에 적용.** 원칙: `strings.dart` 원문 불변, 낭독(semanticsLabel)·복사·TextField 입력값에는
   넣지 않는다(편집 가능한 텍스트에는 적용 금지). 기존 테스트 finder가 깨지면 원문으로 찾게 고친다. 한 어절이 칸보다 길면 그 어절은
   끊겨도 된다(무한 넘침 없음을 테스트로 확인). 대표 화면(할 일 긴 내용, 판정 질문, 동의 문구, 1.0/1.5배)을 위젯 테스트로 고정.
2. 내 대결 카드 "내 차례" 줄(과 같은 성격의 놓치면 손해 보는 강조 문장)을 bodySmall 13 → 16dp 계열 슬롯으로.
3. **Material Icons 라이선스 고지 추가.** Flutter SDK `bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt` 원문(CC BY 4.0)을
   자산으로 넣고 Pretendard와 같은 곳에서 `LicenseRegistry.addLicense`로 등록. design.md의 "Apache 2.0" 기재는 틀렸으므로 정정.
4. FAB가 목록 끝 항목을 가리지 않게(할 일·대결 찾기) 목록 아래 여백 = FAB 높이 + 여백.
5. 버튼 무게: 모집 카드 "기준 수정" vs "취소" 균형, 프로필 "동의 철회"를 빨간 채움에서 덜 위험한 스타일로.
6. 상대 카드: 이름을 점수 줄보다 위계상 위로.
7. 작은 것: 대결 만들기 글자 수 카운터 보조색·보통 굵기, "직접 입력" 텍스트 버튼 들여쓰기 정렬, 속도전 진행 중 "상대가 제출하기 전까지
   바꿀 수 있어요" 중복 표시 하나 제거(문구 불변), VS 인트로 "나" 세 번 중복 제거(이름 조회 실패 시 "나" 대체 표시 예외는 유지).
8. 백로그에 한 줄씩만 추가(구현 금지): AI 동의 첫 문장 현행 구조 불일치[배포 전 필수], 결과 화면 제출 시각 라벨 없음, 촬영 중 최소 기준
   안 보임, 남은 시간 내림 표시, 전적 카드 날짜 없음·포기 패배 구분 없음. 스토어 스크린샷 재촬영은 이미 백로그·DEPLOY.md에 있어 중복 추가 안 함.

### 후속 작업 순서(F1–F8)
충돌 확인: 위 결정과 CLAUDE.md·dev-standards 사이 충돌 없음(문구 변경 0, 판정 로직 무관, 새 화면 없음, 새 패키지 없음).

- F1 `fix:` 어절 줄바꿈 전역 적용. `KeepWordsText`를 `Text`의 하위 클래스로 바꿔(`data`는 원문 그대로 — `find.text(원문)`·
  `tester.widget<Text>`가 그대로 동작) 그릴 때만 `keepWords`를 거친 글자를 `RichText`에 넘긴다. lib의 표시용 `Text(`를
  `KeepWordsText(`로 일괄 교체. 제외: `SelectableText`(복사 대상 URL), `TextField`/`InputDecoration` 문자열(힌트·라벨·카운터 —
  Material 내부 Text), 툴팁 문자열. `keepWords`는 양쪽이 모두 ASCII인 글자 사이에는 끼우지 않는다(영문·숫자의 커닝·URL 줄바꿈 보존).
  테스트: 긴 어절 넘침 없음, 할 일 긴 내용·판정 질문·동의 문구 1.0/1.5배 어절 경계.
- F2 `fix:` "내 차례" 줄 bodySmall → titleSmall(16/700). 편집 오류 문장(bodySmall)도 design 역할표 "오류 = bodyMedium"으로.
- F3 `chore:` Material Icons CC BY 4.0 고지 등록 + 자산 + 테스트, design.md 정정.
- F4 `fix:` FAB 여백(공용 상수) + 할 일·찾기 1.5배 끝까지 스크롤 시 겹침 없음 테스트.
- F5 `fix:` 버튼 무게(모집 카드 두 버튼 보조 버튼으로 통일, 동의 철회 위험 윤곽 버튼).
- F6 `fix:` 상대 카드 이름 titleMedium.
- F7 `fix:` 카운터·직접 입력 정렬·중복 문장·VS 라벨 중복.
- F8 `docs:` TODO_BACKLOG 다섯 줄, 진행 기록.

## 후속 2 — 줄넘김 가독성 (W1–W4, 2026-11-08)
입력: 오너 요청 "텍스트들 가독성 좋게 줄넘김 처리 해봐"(메인 세션 전달). HEAD `a6ac909`(analyze 0 / test 524) 기준.
360dp 스크린샷에서 남은 문제: 마지막 줄 한 어절(고아), 2~3줄 제목·라벨의 들쭉날쭉한 줄 길이, 1.5배 할 일 행의 좁은 텍스트 칸.

충돌 확인: CLAUDE.md·dev-standards와 충돌 없음 — 문구(`strings.dart`) 변경 0, 판정 로직 무관, 새 화면 없음, 새 패키지 없음.
design 3.2 역할표·5.5 "할 일 행 터치 영역 48"을 그대로 지킨다.

### 순서
- W1 `refactor:` `KeepWordsText`를 `Text` 하위 클래스(static 플래그로 build 중 `data` 바꿔치기)에서 **`Text`를 상속하지 않는
  StatelessWidget**으로. 원문 `text`를 들고, `Text.build`가 하던 스타일 합성(DefaultTextStyle·굵은 글씨 설정·글자 배율)을 공개 API로 직접 해
  `RichText`를 그린다. 낭독은 `Semantics(label: 원문)` + `ExcludeSemantics`. 테스트는 `test/helpers/text_finders.dart`의 `findText`·
  `findTextContaining`·`findWidgetWithText`(Text·EditableText·KeepWordsText 원문을 모두 찾는 공용 finder)로 기계적으로 바꾼다
  (18개 파일, `find.text(` → `findText(` 등 치환 + `tester.widget<Text>` → `<KeepWordsText>`). 동작(줄바꿈) 변화 없음.
- W2 `feat:` 줄 모양 옵션 `KeepWordsWrap { balanced, pretty, none }`. 그리기를 레이아웃 단계 빌더(`AbstractLayoutBuilder`, 계획값이 같으면
  다시 빌드하지 않음)로 옮겨 칸 폭을 알고 결정한다. 고유 크기(IntrinsicWidth·대화상자)는 TextPainter로 직접 답한다.
  - balanced: 4줄 이하에서 줄 수를 유지하는 최소 폭을 TextPainter 이분 탐색. 글자는 그 폭으로 그리되 위젯 폭은 원래 제약(`textWidthBasis.parent`면
    칸 전체)을 차지하고, 정렬(왼쪽/가운데/오른쪽)에 맞춰 그 안에 놓는다. justify·한 줄·maxLines 초과는 건너뜀.
  - pretty: 문단마다 마지막 공백 뒤에 WORD JOINER를 넣어 마지막 두 어절을 붙인다. 붙인 두 어절이 칸 폭보다 넓으면 그 문단은 붙이지 않는다.
  - 기본값(`wrap` 생략): 합성된 스타일의 행간으로 역할을 가린다 — design 3.2에서 본문 슬롯(bodyLarge·bodyMedium·bodySmall)은 행간 ≥ 1.55,
    제목·라벨·숫자 슬롯은 ≤ 1.5다. 행간 < 1.55 → balanced, 그 밖(행간 없음 포함) → pretty. 호출부가 역할과 다르게 쓰는 곳만 `wrap:`으로 고른다.
  - 계획값은 (모드·글자·스타일·배율·폭·maxLines·정렬…) 키로 전역 LRU 캐시.
  - 테스트: 균형(줄 수 유지 + 줄 길이 차 감소), 고아 방지(마지막 줄 어절 ≥ 2), 붙인 두 어절이 칸보다 넓으면 미적용, 한 어절이 칸보다 길 때 넘침 없음,
    위젯 폭·정렬 유지, IntrinsicWidth 안에서 동작. 기능을 끄면(`none`) 실패하는지 확인.
- W3 `fix:` 할 일 행 텍스트 칸 넓히기 — `ListTile` 좌우 여백·`minLeadingWidth`·`horizontalTitleGap` 축소, 체크박스·삭제 버튼 48dp 터치 영역 유지.
  테스트: 360dp·1.5배 긴 할 일 줄 수가 W2 기준보다 줄었는지, 두 버튼 터치 영역 ≥ 48.
- W4 `docs:` 이 절의 진행 기록.
