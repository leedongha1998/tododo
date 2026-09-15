# retro-theme 구현 계획

입력: `spec.md`, `design.md`(승인), `decisions.md` 15·16번. 순서는 design.md 9장 6단계를 따른다.
공통 규칙: 각 커밋 전에 `flutter analyze` 이슈 0 + `flutter test` 전부 통과. 판정 로직·스키마·마이그레이션·원격 DB는 건드리지 않는다.
커밋은 master에 단계/화면 단위로, `feat: ...` 한국어 제목 + 이유 본문 + `Co-Authored-By` 줄. push 없음.

## 착수 전 확인 (2026-09-15)
- 기준선: `flutter analyze` 이슈 0, `flutter test` 57개 통과.
- 주 강조색: 파랑안 `#2F48B8` 확정(decisions 15). 청록안 코드 없음.
- 대비비 표 24개 조합을 WCAG 공식으로 다시 계산 → 설계 값과 소수 첫째 자리까지 일치, 전부 기준 통과.
- 갈무리 g값: 공식 README 표 `Galmuri11 (12px, 9pt)` → **g = 12 확인, 설계 크기표 그대로.**
- 글꼴 출처: GitHub 릴리스 `quiple/galmuri` v2.40.4 `Galmuri-v2.40.4.zip`만 사용.
  - 넣는 파일: `Galmuri11.ttf`(5,376,428 B), `Galmuri11-Bold.ttf`(2,613,660 B), `LICENSE.txt`(4,360 B, OFL 1.1 원문).
  - **설계와 다른 점: 라이선스 파일 이름.** design.md 7장은 `OFL.txt`로 적었으나 배포 zip의 원문 파일은 `LICENSE.txt`다. "파일 이름을 바꾸지 않는다" 지시에 따라 `LICENSE.txt` 그대로 두고 `LicenseRegistry`가 이 경로를 읽는다.
- 에뮬레이터 `emulator-5554`(todododo_avd) 실행 중, `env.json` 있음. 단 로그인 뒤 화면은 Google 계정 로그인(브라우저 인증)이 필요해 에이전트가 직접 들어갈 수 없을 수 있다 → 그런 항목은 "수동 확인 필요"로 남긴다.
- 작업 트리에 오너의 커밋 안 된 `CLAUDE.md`·`TODO_BACKLOG.md` 변경이 있다. 4단계에서 CLAUDE.md에 한 줄을 추가할 때 **내 줄만** 스테이징한다(`git apply --cached`로 해당 hunk만). 오너 변경은 커밋하지 않는다.
- `docs/specs/retro-theme/*`는 아직 추적되지 않은 오너 문서라 커밋에 넣지 않는다.

## 파일 배치 결정 (설계가 위치를 정하지 않은 것)
- `lib/core/theme/`: `retro_palette.dart`(15색 + `contrastRatio`), `retro_text.dart`, `pixel_border.dart`, `app_theme.dart`(재작성), `pixel_icons.dart`, `app_mark.dart`(5단계).
- `lib/core/widgets/`: `pixel_icon.dart`, `pixel_frame.dart`, `pixel_tag.dart`, `pixel_loader.dart`, `status_message.dart`, `evidence_photo_frame.dart`, `initial_badge.dart`(+`displayInitial`), `retro_button_styles.dart`.
- `lib/features/battle/presentation/battle_chips.dart`: `BattleTypeBadge`/`BattleStatusChip`/`ResultLabel` + `battleStatusTagStyle`/`resultTagStyle`.
- VS 인트로: `lib/features/battle/domain/vs_intro_rules.dart`(`shouldShowVsIntro`), `lib/features/battle/data/vs_intro_seen_store.dart`(+provider는 `battle_providers.dart`), `lib/features/battle/presentation/vs_intro.dart`(위젯·`showVsIntro`·타임라인 상수).
- 테스트는 lib 구조를 미러링(`test/core/...`, `test/features/battle/...`). 위젯 테스트는 기존대로 `test/widget_test.dart`.

---

## 1단계 — 팔레트·글꼴·모양·ThemeData (커밋 1개)
바꿀 파일
- 추가: `assets/fonts/galmuri/{Galmuri11.ttf, Galmuri11-Bold.ttf, LICENSE.txt}`
- `pubspec.yaml`: fonts `Galmuri11`(400/700), assets `LICENSE.txt`
- 추가: `lib/core/theme/retro_palette.dart`, `retro_text.dart`, `pixel_border.dart`
- 재작성: `lib/core/theme/app_theme.dart`(3.1 표 전체; 아이콘 교체가 필요한 뒤로 가기·SegmentedButton 체크는 2단계)
- `lib/main.dart`: `themeMode: ThemeMode.light`, `builder`로 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`
- 추가: `test/core/theme/retro_palette_test.dart`(대비비 표), `test/core/theme/pixel_border_test.dart`(계단 모서리 경로)

완료 조건
- 자동: 대비비 테스트 통과, 기존 위젯 테스트 통과, `lib/`에 `0xFFE04A16` 없음.
- 커밋 메시지에 글꼴 용량 기록, g = 12 확인 기록.
- 수동(에뮬레이터): 비행기 모드 첫 실행에서 제목·버튼·탭이 갈무리, 할 일 내용·토스트는 기기 글꼴, 주황 없음.

## 2단계 — 픽셀 아이콘과 공용 위젯 (커밋 1개)
바꿀 파일
- 추가: `lib/core/theme/pixel_icons.dart`(2.3 두 표 전체, 12×12 문자열), `lib/core/widgets/*`(위 목록)
- `app_theme.dart`: `actionIconTheme.backButtonIconBuilder`, `segmentedButtonTheme.selectedIcon`
- 재작성: `battle_chips.dart`(`BattleTypeBadge`, `BattleStatusChip`, `ResultLabel`, 매핑 함수)
- 추가 테스트: `test/core/theme/pixel_icons_test.dart`, `test/features/battle/presentation/battle_chips_test.dart`(8종 상태·결과 매핑), `test/core/widgets/initial_badge_test.dart`(`displayInitial`)

완료 조건
- 자동: 매핑·비트맵·이니셜 테스트 통과, 기존 `find.text` 기반 테스트 통과.
- 수동: 내 대결·대결 상세에서 새 배지·칩이 보임.

## 3단계 — ai-judge가 건드리지 않는 화면 (화면마다 커밋, 4개)
- 3-1 탭바: `main_shell.dart`(픽셀 아이콘 4개, `selectedIcon` 제거, 2dp ink 윗선).
- 3-2 로그인·AuthGate: `login_screen.dart`(마크 96dp는 5단계 전까지 `PixelIcons.todo`, 타이틀 48 + amber 그림자, 깜빡이는 커서), `auth_gate.dart`(`PixelLoader.medium`).
- 3-3 할 일 목록: `todo_list_screen.dart`(행 `PixelFrame.raised`/`inset`, 삭제 아이콘, FAB 아이콘, `StatusMessage` 빈/로딩/오류).
- 3-4 프로필: `profile_screen.dart`(계정 섹션 `PixelFrame.flat(title)`, 로그아웃 Outlined, 라이선스 TextButton, 위험 버튼, 기록 행 `ResultLabel.small`, 로딩 교체), `main.dart`(`LicenseRegistry`), `strings.dart`(`openSourceLicenses`).

완료 조건
- 자동: 기존 위젯 테스트 통과(할 일 취소선, 탭바 4개, 계정 삭제 확인 흐름).
- 수동: 화면별 spec 수용 기준, 글자 크기 1.3에서 잘림·겹침 없음, 라이선스 화면에 Galmuri 항목.

## 4단계 — VS 인트로 (커밋 1개)
바꿀 파일
- `pubspec.yaml`: `shared_preferences: ^2.5.5` 직접 의존성 명시(잠금 버전 2.5.5, 이미 전이 의존성).
- 추가: `vs_intro_rules.dart`, `vs_intro_seen_store.dart`, `vs_intro.dart`; `battle_providers.dart`에 store provider.
- 연결 A: `battle_recruits_screen.dart` `_join`(battleId 대신 recruit 전달, 성공 → invalidate → 인트로 → 토스트).
- 연결 B: `battle_detail_screen.dart`(첫 데이터 도착 시 한 번 판단하는 작은 상태 위젯; userId는 `detail.me.userId`).
- `strings.dart`: `vsIntroVersus`, `vsIntroSemantics`.
- `CLAUDE.md` 코딩 규칙에 장식 연출 실패 예외 한 줄(내 줄만 스테이징).
- 테스트: `shouldShowVsIntro`, 타임라인 합 1500ms, `VsIntroSeenStore`(mock prefs), 위젯(탭하면 닫힘 / 애니메이션 끔 첫 프레임 / 60자 이름 overflow 없음), 기존 상세 테스트에 store "봤음" override.

완료 조건
- 자동: 위 테스트 통과.
- 수동: 두 계정 실제 매칭(참가자 직후 1회, 생성자 상세 첫 진입 1회, 재진입 안 뜸), 탭 즉시 닫힘, 애니메이션 삭제 정지 화면, 탈퇴한 사용자·60자·한 글자 이름, 성공 토스트가 인트로 뒤, 참가 실패 시 인트로 없음, 저장소 실패 강제 시 로그만.

## 5단계 — 런처·스토어 아이콘과 Android 시작 창 (커밋 1개)
바꿀 파일
- 추가: `lib/core/theme/app_mark.dart`(16×16 색 인덱스 비트맵 + 단색용).
- 재작성: `tool/generate_launcher_icons.dart`(팔레트 import, 셀 정수 px, foreground/monochrome/정사각/스토어, `colors.xml` 작성).
- 생성물: `mipmap-*/ic_launcher{,_foreground,_monochrome}.png`, `store/icon-512.png`, `res/values/colors.xml`.
- 삭제: `res/drawable/ic_launcher_background.xml`. 수정: `mipmap-anydpi-v26/ic_launcher.xml`, `drawable(-v21)/launch_background.xml`, `values-night/styles.xml`.
- `login_screen.dart` 마크를 새 비트맵으로, `DEPLOY.md` 4번 괄호 문장.
- 테스트: 마크 비트맵(16×16, 허용 문자, 모서리 2×2 비움, 안전 원 33dp 안) — `test/core/theme/app_mark_test.dart`.

완료 조건
- 자동: 생성 명령 한 번으로 전부 재생성, `android/`·`store/`·`tool/`에서 `E04A16`/`FF7A3D` grep 없음, 테스트 통과.
- 수동: 원형·사각 아이콘 모양, 테마 아이콘, 다크 모드 시작 창 paper, 가장 작은 크기 판별(생성 PNG 육안 확인은 자동 단계에서 가능).

## 6단계 — 현재 대결 화면 4개 깨짐 점검 (화면마다 커밋, 4개)
design.md 5.5 표의 "허용하는 수정"만. 배치 변경 없음.
- 6-1 대결 찾기 `battle_recruits_screen.dart`: #4(넘치면 해당 버튼만), #5 FAB 아이콘, #6 로더 2곳.
- 6-2 대결 만들기 `create_battle_screen.dart`: #6 버튼 진행 중 로더, #7(테마로 이미 해결).
- 6-3 내 대결 `my_battles_screen.dart` + `battle_summary_list.dart`: #2 카드 제목 스타일, #6 로더.
- 6-4 대결 상세 `battle_detail_screen.dart`: #8·#9 `EvidencePhotoFrame`, #10 결과 배너, #11 시트 아이콘, #12 포기 아이콘, #6 로더 3곳, #13은 수동 확인 후 필요 시 `Wrap`.

완료 조건
- 자동: `lib/`에서 `Icons.`·`BorderRadius.circular`·`CircularProgressIndicator`·`Color(0x`(팔레트 파일 제외) grep 없음, 테스트 통과.
- 수동: 네 화면에서 모집 등록·취소, 참가, 증거 제출(사진·텍스트), 승인/이의제기, 포기를 1.0·1.3·다크 모드·애니메이션 삭제에서 끝까지.

---

## 진행 기록
(단계 완료 시 커밋 해시, 순서 변경 사유, 설계와 달라진 점, 수동 확인 결과를 여기에 적는다.)

### 1단계 — `e0cb169` feat: 레트로 팔레트·갈무리 글꼴·픽셀 모양 테마
- analyze 0, test 88 통과.
- 에뮬레이터(1단계 debug APK, 이미 로그인된 계정, 글자 1.0·라이트): **확인함** — 앱바·탭 이름·칩이 갈무리, 목록 보조 문장("vs 이름")은 기기 글꼴, paper 배경·계단 모서리 카드·바닥 두께, 주황 없음.
- 수동 확인 필요: 비행기 모드 첫 실행, 토스트 글꼴.
- 설계와 다른 소소한 결정: 버튼 포커스는 "primary 테두리 추가" 대신 테두리 색을 primary로 바꿈. 바텀시트 끌기 막대는 Material drag handle(32×4 ink)을 써서 양끝 2dp가 둥글다.

### 2단계
- analyze 0, test 173 통과.
- 추가 아이콘: `cursor`(로그인 타이틀 5.1의 ▶ 커서용, 2.3 표에 없던 것).
- `displayInitial`: "라틴 소문자만 대문자" 대신 "대문자로 바꿔도 한 글자면 대문자"(합성 é → É, ß는 그대로).
- 무효 결과 라벨은 문자열이 없어 `resultTagStyle` 키가 아니라 `voidedResultTagStyle` 상수로 둠(ai-judge가 매핑).
- 커밋 `12be527` feat: 픽셀 아이콘과 레트로 공용 위젯.

### 3단계 — 화면마다 커밋
- 3-1 `0f83eb5` 탭바 / 3-2 `aca590e` 로그인 / 3-3 `5ad2b64` 할 일 목록 / 3-4 `da3c8ad` 프로필·라이선스. 각 커밋 전 analyze 0, test 173 통과.
- 3-3 중 발견: `PixelFrame` 면이 장식이라 안의 `ListTile`이 프레임워크 검사("ink splashes may be invisible")에 걸림 → 프레임 안에 투명 `Material`을 둠(공용 위젯 수정, 3-3 커밋에 포함).
- 에뮬레이터(3단계 debug APK, 글자 1.0·라이트) **확인함**: 탭바 픽셀 아이콘·위 경계선·선택 표시기, 할 일 FAB·삭제 아이콘·완료 행(가라앉은 면·취소선·채운 체크), 할 일 로딩 픽셀 로더, 프로필 계정 창(로그아웃·라이선스·구분선·위험 버튼), 기록 행 "승" 결과 라벨·유형 배지.
- 수동 확인 필요: 로그인 화면(로그인된 계정이라 못 봄), 안 한 할 일 행(데이터 없음), 라이선스 화면 안 Galmuri 항목, 글자 크기 1.3.

### 4단계
- analyze 0, test 190 통과(`shouldShowVsIntro`, 타임라인·프레임, 저장소, 위젯 3개: 첫 진입 1회·재진입 없음 / 애니메이션 줄이기 첫 프레임 / 60자·글자 1.3 넘침 없음·자동 닫힘).
- 설계와 다른 점: 상세 첫 진입 판단의 userId는 `detail.me.userId`(Supabase 전역 없이 테스트 가능). 참가 흐름의 내 이름은 `myProfileProvider.future`, 실패하면 "나".
- CLAUDE.md 예외 한 줄 추가. 오너의 미커밋 CLAUDE.md 변경은 스테이징하지 않음.
  - 처음 커밋(`f6d9acd`)에서 문맥 없는 hunk 적용이 줄을 "RLS 정책" 아래로 잘못 넣음 → 푸시 전이라 같은 커밋을 amend해 "에러는 삼키지 않는다" 바로 아래로 옮김. **최종 커밋 `48f1ccc` feat: VS 매칭 인트로.** 오너의 미커밋 CLAUDE.md 변경(+8/−4)은 그대로 작업 트리에 남아 있음.
- 에뮬레이터(4단계 debug APK, 이미 로그인된 계정) **확인함**: 매칭된 진행 중 대결("zzz")에 처음 들어가자 인트로가 뜸(띠·양옆에서 들어오는 명판·"상대/나" 라벨 프레임 캡처), 스스로 닫힌 뒤 상세 화면, 뒤로 갔다 다시 들어가면 인트로 없음.
- 수동 확인 필요: 두 계정 실제 매칭(참가자 쪽 참가 직후 인트로, 성공 토스트가 인트로 뒤), 참가 실패 시 인트로 없음, 탭해서 즉시 닫기(에뮬레이터에서는 자동 닫힘만 봄), 애니메이션 삭제 정지 화면(위젯 테스트로만), 탈퇴한 사용자·한 글자 이름, 저장소 실패 강제.

### 5단계
- analyze 0, test 194 통과. 생성 명령 한 번으로 PNG 16개 + colors.xml 재생성.
- 마크 비트맵은 규칙(모서리 2×2 비움, 안전 원)을 스크립트로 확인하며 만들었고, 첫 안은 그림이 아래로 치우쳐 한 줄 위로 다시 짬.
- 설계와 다른 점: `values/styles.xml`의 NormalTheme 배경도 `@drawable/launch_background`(paper)로 바꿈(설계는 values-night만 언급). 라이트 모드에서도 Flutter 첫 프레임 전 흰 창 대신 paper가 보이게 하려는 것.
- 생성 PNG 육안 **확인함**: 스토어 512px(파랑 바탕·칸·앰버 체크·그림자), mdpi 48px에서도 칸+체크 형태 식별. 옛 주황 값 grep 없음.
- 커밋 `696c63d` feat: 픽셀 런처·스토어 아이콘과 밝은 시작 창.
- 에뮬레이터(5단계 debug APK) **확인함**: 기기 다크 모드(`cmd uimode night yes`)로 콜드 스타트 시 시작 창이 paper 배경 + 원형 마스크 안의 새 마크(잘림 없음), 검은 화면 없음.
- 수동 확인 필요: 홈·앱 서랍 아이콘(서랍 캡처에서 시스템 안내 말풍선에 가려 판별 불가), 사각·스쿼클 아이콘 모양 설정, 테마(단색) 아이콘 켬, 다크 모드에서 시작 창 이후 앱 화면(캡처가 시작 창 페이드 중에 끝남), 로그인 화면 마크(로그인된 계정).

### 6단계 — 화면마다 커밋
- 6-1 `6f8a1d6` 대결 찾기(FAB 아이콘, 로더 2곳) / 6-2 `2b63247` 대결 만들기(등록 중 로더) / 6-3 `867736b` 내 대결(카드 제목 bodyLarge w600, 로더) / 6-4 `29fbdb3` 대결 상세(증거 사진 틀 2곳, 사진 실패 상태, 결과 배너 프레임·아이콘·본문 글꼴 헤드라인, 시트·첨부·포기 아이콘, 로더 2곳). 각 커밋 전 analyze 0, test 194 통과.
- 6-4에 함께 넣은 것: `PixelIcon`의 IconTheme 색 없음 폴백을 `Color(0xFF000000)` → `RetroPalette.ink`(완료 조건 grep에 걸려서).
- 완료 조건 grep **확인함**: `lib/`에서 Material `Icons.`(단어 경계), `BorderRadius.circular`, `CircularProgressIndicator`, 팔레트 파일 밖 `Color(0x`, 투명 외 `Colors.` 모두 0건.
- 5.5 #4(모집 목록 참가 버튼 1.3배 넘침)·#13(승인/이의제기 Row 1.3배)은 수정하지 않음 — 넘칠 때만 고치는 항목이라 수동 확인 대상으로 남김.
- 배치 변경 없음: 네 화면 모두 위젯 트리 순서 그대로(대결 상세에는 크기 0인 인트로 판단 조각만 4단계에서 추가).
- 에뮬레이터(6단계 debug APK, 시스템 글꼴 크기 1.3, 확인 후 1.0으로 되돌림) **확인함**: 내 대결 카드 제목이 본문 글꼴이고 잘림 없음, 대결 상세에서 내·상대 증거 사진이 틀 안에 잘리지 않고(contain) 보임, 승인/이의제기 두 버튼이 1.3배에서 한 줄에 들어감(#13 수정 불필요), 대결 찾기 섹션 제목·빈 문구·FAB, 프로필 계정 창.
- 수동 확인 필요: 모집 목록 참가 버튼 1.3배(#4, 열린 모집이 없어 못 봄), 결과 배너 5종 실제 모양(종결 대결 상세), 사진 불러오기 실패 상태, 모집 등록·취소·참가·증거 제출·승인/이의제기·포기 전체 흐름(데이터를 바꾸는 동작이라 실행하지 않음), 다크 모드·애니메이션 삭제에서 네 화면.

## 최종 상태 (2026-09-15)
- 커밋 12개: `e0cb169` `12be527` `0f83eb5` `aca590e` `5ad2b64` `da3c8ad` `48f1ccc` `696c63d` `6f8a1d6` `2b63247` `867736b` `29fbdb3`. push 안 함.
- 마지막 검증: `flutter analyze` 이슈 0, `flutter test` 194개 통과.
- 계획 순서 변경 없음(1→6단계 그대로).
