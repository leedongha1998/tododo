# retro-theme 설계

## 참고
- spec.md: `docs/specs/retro-theme/spec.md` (오너 승인 완료, 유일한 요구사항). 결정 번호 출처: `docs/specs/retro-theme/decisions.md`. 아래 "확정 1~4", "결정 A~H"는 spec.md 표기를 그대로 쓴다.
- 대조 대상: `docs/specs/ai-judge/design.md` "화면" 절 1~8.
- 근거로 읽은 현재 코드: `lib/core/theme/app_theme.dart`, `lib/core/navigation/{main_shell,app_tab}.dart`, `lib/core/strings.dart`, `lib/main.dart`, `lib/features/auth/presentation/{login_screen,auth_gate}.dart`, `lib/features/todo/presentation/todo_list_screen.dart`, `lib/features/profile/presentation/profile_screen.dart`, `lib/features/profile/domain/battle_record.dart`, `lib/features/battle/presentation/*`, `lib/features/battle/domain/{battle_providers,battle_detail}.dart`, `lib/features/battle/data/{battle_repository,profile}.dart`, `pubspec.yaml`, `pubspec.lock`, `tool/generate_launcher_icons.dart`, `android/app/src/main/res/{drawable,drawable-v21,mipmap-anydpi-v26,values,values-night}/*`, `DEPLOY.md` 4번, `test/widget_test.dart`.
- 이 기능은 데이터·판정·상태 전이를 바꾸지 않는다. 설계는 "어떻게 보이는가"만 다룬다(spec "ai-judge와의 경계").

---

## 1. 시각 규칙

### 1.1 팔레트 (라이트 하나, 결정 B·F)

방향: **크림색 종이 화면 + 짙은 남색 잉크 + 원색 강조 몇 개.** 초기 휴대용 게임기의 "밝은 화면에 진한 도트" 인상을 내되, 특정 기기의 연두색 4단계 LCD 톤이나 특정 게임의 빨강·흰색 조합은 쓰지 않는다. 색 수를 15개로 묶어 "제한 팔레트" 느낌을 유지한다. 앱 안의 모든 색은 이 표에서만 고른다(`Color(0x...)` 직접 작성 금지, `Colors.*` 금지 — 투명만 예외).

| 토큰 | hex | 역할 |
|---|---|---|
| `paper` | `#F3EAD3` | 화면 배경(scaffold), 스플래시 배경 |
| `surface` | `#FFF8E7` | 프레임·카드·대화상자·시트·입력 필드 면, 어두운 면 위 글자 |
| `sunken` | `#E3D6B8` | 눌린/가라앉은 면, 중립 칩, 비활성 버튼 면, 사진 여백 |
| `line` | `#C9BA98` | 장식용 구분선(의미 없는 선에만. 조작 요소의 테두리에는 쓰지 않음) |
| `ink` | `#231F3A` | 본문 글자, 테두리, 바닥 두께(그림자), 토스트 면 |
| `inkMuted` | `#57506B` | 보조 글자, 약한 테두리, 패 라벨 면 |
| `inkDisabled` | `#756E84` | 비활성 글자·테두리 |
| `primary` | `#2F48B8` | 주 강조(주 버튼, 선택된 탭, 진행 중, 런처 아이콘 배경) |
| `primaryPale` | `#C5CDF0` | 안내(정보) 블록 면 |
| `amber` | `#F2B233` | 속도전 표지 칸, 승 라벨, 런처 아이콘 체크 |
| `mint` | `#6CC5B0` | 품질전 표지 칸 |
| `lavender` | `#B7A4E6` | 판정 중 |
| `success` | `#27714A` | 종료, 합격 |
| `danger` | `#B8323A` | 위험 동작, 오류 테두리 |
| `dangerPale` | `#F4C7C0` | 미결, 차단·오류 블록 면 |

**Material `ColorScheme` 매핑** (`ColorScheme.fromSeed`를 버리고 명시 생성. 개별 화면이 `scheme.xxx`를 써도 팔레트 안의 색이 나오게):

| ColorScheme 슬롯 | 토큰 |
|---|---|
| primary / onPrimary | primary / surface |
| primaryContainer / onPrimaryContainer | primaryPale / ink |
| secondary / onSecondary, secondaryContainer / onSecondaryContainer | amber / ink (둘 다) |
| tertiary / onTertiary | mint / ink |
| tertiaryContainer / onTertiaryContainer | lavender / ink |
| error / onError | danger / surface |
| errorContainer / onErrorContainer | dangerPale / ink |
| surface / onSurface / onSurfaceVariant | surface / ink / inkMuted |
| surfaceContainerLowest, Low | surface |
| surfaceContainer | paper |
| surfaceContainerHigh, Highest, surfaceDim | sunken |
| outline / outlineVariant | ink / line |
| shadow, scrim, inverseSurface / onInverseSurface | ink, ink, ink / surface |
| inversePrimary | primaryPale |
| surfaceTint | 투명(M3 틴트 제거) |

`scaffoldBackgroundColor = paper`.

#### 대비비 표 (WCAG 2.x 상대 휘도 공식으로 계산)

기준: **본문 글자 4.5:1 이상(AA), 24dp 이상 픽셀 제목·굵은 18.66dp 이상 3:1 이상, 조작 요소의 테두리·아이콘 3:1 이상(1.4.11).** 비활성 요소는 WCAG 예외지만 3:1을 목표로 둔다. 이 앱은 12dp 픽셀 글꼴을 버튼·칩에 쓰므로 칩·버튼 조합도 전부 4.5:1 기준으로 맞췄다.

| 글자 / 배경 | 대비비 | 쓰는 곳 | 기준 |
|---|---|---|---|
| ink / paper | 13.2 | 화면 본문 | 4.5 ✓ |
| ink / surface | 14.9 | 프레임 안 본문, 보조 버튼 | 4.5 ✓ |
| inkMuted / paper | 6.3 | 보조 문장, 무효 라벨 | 4.5 ✓ |
| inkMuted / surface | 7.2 | 보조 문장 | 4.5 ✓ |
| inkMuted / sunken | 5.3 | 취소 칩, 가라앉은 면의 보조 글자 | 4.5 ✓ |
| ink / sunken | 11.0 | 무승부 칩, 완료한 할 일 행 | 4.5 ✓ |
| surface / primary | 7.2 | 주 버튼, 진행 중 칩, 선택 탭 아이콘 | 4.5 ✓ |
| primary / surface | 7.2 | 링크 글자 | 4.5 ✓ |
| primary / primaryPale | 4.9 | 안내 블록 안 강조 | 4.5 ✓ |
| ink / primaryPale | 10.1 | 안내 블록 본문 | 4.5 ✓ |
| ink / amber | 8.4 | 속도전 표지 칸 아이콘, 승 라벨 | 4.5 ✓ |
| ink / mint | 7.7 | 품질전 표지 칸 아이콘 | 4.5 ✓ |
| ink / lavender | 7.1 | 판정 중 칩 | 4.5 ✓ |
| surface / success | 5.6 | 종료 칩, 합격 태그 | 4.5 ✓ |
| success / paper | 4.9 | 성공 톤 블록의 강조 글자 | 4.5 ✓ |
| surface / danger | 5.6 | 위험 버튼 | 4.5 ✓ |
| danger / paper | 4.9 | 위험 텍스트 버튼(현재 포기·탈퇴 코드) | 4.5 ✓ |
| danger / surface | 5.6 | 위험 텍스트 버튼 | 4.5 ✓ |
| ink / dangerPale | 10.4 | 미결 칩, 차단 블록 본문 | 4.5 ✓ |
| surface / inkMuted | 7.2 | 패 라벨 | 4.5 ✓ |
| surface / ink | 14.9 | 토스트 본문, 창 제목 띠 | 4.5 ✓ |
| amber / ink | 8.4 | 토스트 동작 버튼 글자 | 4.5 ✓ |
| inkDisabled / surface | 4.6 | 비활성 글자(프레임 위) | 3.0 목표 ✓ |
| inkDisabled / sunken | 3.4 | 비활성 버튼 글자 | 3.0 목표 ✓ |

이 표는 테스트로 고정한다(6장). `line`은 장식 선 전용이라 표에 넣지 않는다. 조작 요소의 경계는 항상 `ink`(paper 대비 13.2)나 `danger`(4.9)로 그린다.

#### 팔레트 대안 (오너 시안 확인용)
주 강조를 파랑 대신 **청록 `#1F6F6B`**(surface 글자 대비 5.6)로 바꾸는 안. 나머지 토큰은 그대로이고 런처 아이콘 배경만 따라 바뀐다. 파랑안은 "진행 중·주 동작"이 앰버·민트와 색상환에서 멀어 구분이 강하고, 청록안은 민트(품질전)와 같은 계열이라 구분이 약해지는 대신 화면이 더 차분하다. 설계 기본값은 파랑안이다.

### 1.2 글꼴 (결정 A)

#### 넣는 파일 (번들, 네트워크 없음)
- 출처: 갈무리 공식 배포처 https://quiple.dev/font/galmuri → 연결된 GitHub 릴리스(`quiple/galmuri`)의 배포 zip.
- 넣는 것: **`Galmuri11.ttf`(Regular), `Galmuri11-Bold.ttf`, 배포 zip 안의 OFL 라이선스 전문 파일**을 `assets/fonts/galmuri/`에. `pubspec.yaml`에 `family: Galmuri11`(400 = Regular, 700 = Bold)로 등록.
- 넣지 않는 것: Galmuri7(작은 크기 가독성 부족), Galmuri9·Galmuri14(아래 크기 규칙이 Galmuri11 한 벌의 정수배로 모든 역할을 덮으므로 불필요 — 크기별 여러 벌을 넣을수록 앱이 커진다는 spec 트레이드오프를 줄인다), Condensed·Mono 변형.
- **서브셋(글자 줄이기)·변환(woff2 등)을 하지 않는다.** OFL상 수정본은 예약 이름을 쓸 수 없고, 한글 11,172자 전부가 필요하다(수용 기준). 원본 TTF를 파일명·패밀리명 그대로 넣는다.
- 용량: TTF 두 벌 합계 수 MB 수준으로 예상. 1단계 구현 시 실측해 커밋 메시지에 적는다.

#### 본문 글꼴
**기기 기본 글꼴을 쓰고 번들하지 않는다**(`fontFamily` 미지정 → Android 기본 한글 글꼴). 앱 크기를 늘리지 않고, 한글 전 음절과 이모지를 기기가 이미 지원한다. 픽셀 스타일에는 `fontFamilyFallback`을 두지 않아 갈무리에 없는 글자(이모지 등)는 Flutter 기본 폴백으로 기기 글꼴이 그린다(빈 네모 방지).

#### 크기 규칙 (픽셀 격자 정수배)
- 갈무리11의 설계 격자(공식 README의 권장 픽셀 크기)를 기준값 `g`로 둔다. **구현 1단계에서 README로 확인하고, 12가 아니면 아래 표의 모든 픽셀 크기를 `g`의 같은 배수로 바꾼다.** 설계 가정은 `g = 12dp`.
- 픽셀 글꼴 크기는 `g × 1, 2, 3, 4, 6`(= 12 / 24 / 36 / 48 / 72dp)만 쓴다. 18dp 같은 1.5배는 획 굵기가 들쭉날쭉해져 쓰지 않는다.
- 한계: 기기 화면 배율(예: 2.625)이 정수가 아니면 논리 dp 정수배라도 물리 픽셀은 약간 번진다. 정수배 규칙은 "획 비율이 글자마다 고르게 유지된다"는 효과를 노린 것이고, 완전한 도트 선명도는 보장하지 않는다(spec P1 "흐려지는 것은 허용, 읽을 수 없는 수준은 안 됨").
- 픽셀 스타일은 `height: 1.34`(12dp 글자에 16dp 줄). 굵기는 400/700 두 가지만. `copyWith(fontWeight: FontWeight.bold)`는 등록된 Bold 파일로 해석되므로 가짜 굵기가 생기지 않는다.

#### `TextTheme` 역할 분담 (ThemeData로 자동 적용)

| 슬롯 | 글꼴 | 크기/굵기 | 쓰는 곳 |
|---|---|---|---|
| displayLarge | 갈무리11 Bold | 72 | VS 인트로의 "VS" |
| displayMedium | 갈무리11 Bold | 48 | 로그인 타이틀 |
| displaySmall | 갈무리11 Bold | 36 | VS 인트로 이니셜, 큰 숫자(ai-judge 점수) |
| headlineLarge/Medium/Small | 갈무리11 Bold | 24 | 빈·오류 상태 제목, 결과 라벨(큰) |
| titleLarge | 갈무리11 Bold | 24 | 앱바 제목 |
| titleMedium | 갈무리11 Bold | 24 | 섹션 제목, 대화상자 제목, 시트 제목, VS 인트로 이름 |
| titleSmall | 갈무리11 Bold | 12 | 작은 소제목("기간", "나 (이름)") |
| labelLarge | 갈무리11 Bold | 12 | 모든 버튼 글자 |
| labelMedium | 갈무리11 Regular | 12 | 칩, 탭 이름, 입력 필드 카운터 |
| labelSmall | 갈무리11 Regular | 12 | 유형 배지, 결과 라벨(작은), 태그 |
| bodyLarge / bodyMedium / bodySmall | 기기 기본 | 16 / 14 / 12 | 할 일 내용, 목록 본문(대결 제목·상대 이름), 안내·오류 문장, 대화상자 본문, 토스트, 입력한 글자, 라이선스 고지 |

추가로 `RetroText.numeric`(갈무리11 Regular 12, 필요 시 24/36으로 `copyWith`)을 테마 확장 없이 정적 상수로 둔다 — "숫자가 독립적으로 표시될 때"(점수, 남은 시간 칸, n/5 카운터, 전적 수) 쓰는 스타일.

Material 위젯 기본 슬롯이 이 분담과 맞는지 확인: AppBar 제목=titleLarge, AlertDialog 제목=headlineSmall(→24 픽셀)·본문=bodyMedium, 버튼=labelLarge, NavigationBar 라벨=labelMedium, ListTile 제목=bodyLarge·부제=bodyMedium, SnackBar=bodyMedium, TextField 입력=bodyLarge. 따라서 **할 일 내용·토스트·대화상자 본문은 자동으로 본문 글꼴, 제목·버튼·탭은 자동으로 픽셀 글꼴**이 된다.

#### 한 요소 안 혼용 규칙 (spec "설계에서 정한다")
1. **Text 위젯 하나에는 글꼴 하나.** 한 줄 안에서 글꼴을 섞지 않는다(`TextSpan`으로 섞기 금지).
2. **짧은 라벨(버튼·칩·배지·탭·태그)은 괄호 설명까지 통째로 픽셀.** 예: ai-judge "다시 검사하기(1회 차감)", "제출(한 번만 낼 수 있어요)"는 전부 픽셀 12.
3. **설명이 한 줄을 넘거나 문장이면 라벨에서 떼어** 버튼 아래 별도 `bodySmall` 줄로 둔다(예: ai-judge "판정 n/5회 남음 · AI 실패는 횟수에서 빠져요"는 버튼 아래 본문 줄).
4. **문장 속 숫자는 문장 글꼴을 따른다.** 숫자만 픽셀로 바꾸는 것은 숫자가 독립된 칸(점수, 남은 시간 칩, 카운터)일 때만.
5. 사용자가 입력한 문자열(할 일, 대결 제목, 표시 이름)은 **목록·본문 자리에서는 본문 글꼴**, 제목 자리(앱바, VS 인트로 이름, 프로필 이름)에서는 픽셀 글꼴. 갈무리는 한글 11,172자와 라틴 문자를 지원하므로 제목 자리에서도 빈 네모가 생기지 않는다.

### 1.3 텍스트 크기 상한 (결정 E)
- **앱 전체에 최대 배율 1.3.** `MaterialApp.builder`에서 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3)`으로 감싼다. 최소 배율은 제한하지 않는다.
- 근거: Android 글꼴 크기 단계는 0.85 / 1.0 / 1.15 / 1.3 / (Android 14+) 1.5 / 1.8 / 2.0이다. 1.3까지는 사용자가 키운 만큼 그대로 따르고, 그 위는 1.3에서 멈춘다. 1.3에서 24dp 픽셀 제목은 31dp, 12dp 버튼 글자는 16dp가 되어 360dp 폭 화면에서 탭바 라벨 5글자("대결 찾기" ≈ 78dp)가 한 칸(90dp)에 들어간다. 1.5부터는 탭 라벨이 칸을 넘는다.
- 픽셀 글꼴과 본문 글꼴에 같은 상한을 쓴다. 따로 두면 한 화면 안에서 제목과 본문의 크기 관계가 뒤집힐 수 있다.
- VS 인트로·로그인 타이틀처럼 큰 글자는 상한 안에서도 넘칠 수 있으므로 해당 위젯이 자체적으로 줄 수 제한 + 말줄임 / `FittedBox(scaleDown)`을 쓴다(4장).

### 1.4 모양 규칙

| 항목 | 규칙 |
|---|---|
| 간격 단위 | 4dp. 쓰는 값은 4 / 8 / 12 / 16 / 24 / 32. 화면 가장자리 16, 목록 항목 사이 8, 프레임 안쪽 12, 섹션 사이 24 |
| 모서리 | 둥근 모서리 금지(`BorderRadius.circular` 전면 제거). **계단 모서리**: 네 모서리에서 테두리 두께와 같은 크기의 정사각형 한 칸을 비운다(2dp 테두리면 2×2dp 한 칸). 입력 필드만 예외로 모서리 없는 직각(입력 테두리 클래스 제약) |
| 테두리 | 조작 요소·칩·프레임 2dp `ink`. 대화상자·바텀시트·VS 인트로 명판은 4dp(바깥 2dp `ink` + 안쪽 2dp `surface` 이중선 = "창" 느낌) |
| 그림자(바닥 두께) | 흐린 그림자·`elevation` 전부 0. 대신 **떠 있는 요소는 아래·오른쪽 테두리를 2dp 더 두껍게(합 4dp) 그린다.** 두께는 요소의 바깥 크기 안쪽에 그리므로 레이아웃 크기와 겹침이 변하지 않는다 |
| 눌림 | 바닥 두께를 위·왼쪽으로 옮기고(안으로 꺼진 모양) 면에 `ink` 12% 겹침. 물결(ripple) 효과 없음(`splashFactory: NoSplash`) |
| 포커스 | 2dp `primary` 바깥 테두리 추가 |
| 선 | 구분선 2dp `line`. 점선이 필요하면 2dp 켜짐·2dp 꺼짐 |
| 움직임 | 장식 애니메이션(로딩 표시, 로그인 커서, VS 인트로)은 **계단식**(연속 곡선 대신 50ms 단위로 끊어 움직임). 화면 이동 전환은 기존 Material 기본 유지(spec "화면 이동 순서 동일") |
| 소리·진동 | 없음(결정 G). `HapticFeedback`, `SystemSound` 호출 금지. 기본 `enableFeedback`도 테마에서 끈다 |

이 모양은 **`PixelBorder`**(Flutter `OutlinedBorder` 구현 하나)가 담당한다. 속성: 테두리 색·두께, 바닥 두께(0 또는 2dp), 눌림 여부, 점선 여부. `getOuterPath`가 계단 모서리 다각형을 돌려주므로 Material의 클리핑·겹침 색도 계단 모서리를 따른다. ThemeData의 모든 `shape`에 이 클래스를 넣고, `WidgetStateProperty`로 눌림 상태에서 눌림 변형을 돌려준다.

---

## 2. 픽셀 아이콘 (결정 B)

### 2.1 방식
- **코드 안 비트맵으로 직접 그린다.** 새 패키지·이미지 에셋·아이콘 글꼴 없음. 아이콘 하나 = 12줄짜리 문자열 목록(`#` 켜짐, `.` 꺼짐). `PixelIcon` 위젯이 `CustomPainter`로 셀마다 사각형을 칠한다(`isAntiAlias = false`).
- 색은 `IconTheme.of(context).color`를 따른다. 그래서 탭바 선택·비선택, 버튼 글자색 등이 테마만으로 바뀐다.
- 기존 `Icon(Icons.xxx)`를 `PixelIcon(PixelIcons.xxx)`로 바꿔 끼운다. `NavigationDestination.icon`, `IconButton.icon`, `FloatingActionButton.child`, `TextButton.icon` 등은 모두 `Widget`을 받으므로 배치가 바뀌지 않는다.
- Material이 내부에서 그리는 아이콘은 테마로 교체: 앱바 뒤로 가기(`ActionIconThemeData.backButtonIconBuilder`), SegmentedButton 선택 체크(`SegmentedButtonThemeData.selectedIcon`), 펼침 화살표(ExpansionTile은 ai-judge가 `trailing`으로 지정).

### 2.2 규칙 (ai-judge가 새 아이콘을 만들 때도 그대로)
| 항목 | 규칙 |
|---|---|
| 격자 | 12×12 셀 |
| 여백 | 바깥 1셀 비움 → 실제 그림은 10×10 |
| 선 굵기 | 1셀. 강조가 필요한 한 획(체크 등)만 2셀 |
| 사선 | 1:1 계단만(한 칸 오른쪽·한 칸 아래). 다른 기울기 금지 |
| 채움 | 기본은 외곽선. "선택됨"을 뜻할 때만 안을 채운 변형을 따로 둔다 |
| 색 | 한 아이콘 = 한 색(현재 IconTheme 색). 두 색이 필요하면 아이콘이 아니라 배지처럼 **색 칸 + 한 색 아이콘**으로 만든다 |
| 표시 크기 | 12 / 24 / 36 / 48dp(셀 1·2·3·4dp). 기본 24 |
| 금지 | 얼굴(눈·입) 모양, 캐릭터·마스코트, 특정 게임 고유 도형(몬스터볼류 반원+띠+가운데 원 조합 등) |

### 2.3 아이콘 목록

**현재 앱에서 교체하는 것**

| 이름 | 모양 | 대체하는 현재 아이콘 / 쓰는 곳 |
|---|---|---|
| `battle` | 교차한 두 칼 | `sports_kabaddi` — 내 대결 탭, 대결 만들기 FAB |
| `search` | 돋보기 | `search` — 대결 찾기 탭 |
| `todo` | 체크된 네모 칸 | `check_circle(_outline)` — 할 일 탭 |
| `profile` | 머리+어깨 윤곽(얼굴 요소 없음) | `person(_outline)` — 프로필 탭 |
| `add` | 더하기 | `add` — 할 일 FAB |
| `back` | 왼쪽 화살표 | 앱바 뒤로 가기(테마) |
| `logout` | 문 + 밖을 향한 화살표 | `logout` |
| `accountDelete` | 머리+어깨 윤곽 + 빼기 | `person_remove_outlined` |
| `delete` | 휴지통 | `delete_outline` — 할 일 행 |
| `check` | 체크 표시(2셀 획) | SegmentedButton 선택(테마), 품질전 완료 배너(`check_circle_outline`) |
| `speed` | 번개 | `bolt` — 속도전 배지 |
| `quality` | 톱니 테두리 인장 안의 체크 | `verified_outlined` — 품질전 배지 |
| `flag` | 깃발 | `flag_outlined` — 포기 |
| `camera` | 카메라 | `photo_camera_outlined` |
| `gallery` | 산+해가 든 액자 | `photo_library_outlined`(ai-judge에서 제거됨, 현재 화면 유지용) |
| `brokenImage` | 금 간 액자 | `broken_image_outlined` |
| `trophy` | 컵 | `emoji_events_outlined` — 승리 배너 |
| `lose` | 아래로 꺾인 화살표 | `sentiment_dissatisfied_outlined` — 패배 배너. **얼굴 아이콘 금지 규칙 때문에 모양을 바꾼다** |
| `hourglass` | 모래시계 | `timer_off_outlined` — 무승부 배너 |
| `warning` | 삼각형 + 느낌표 | `report_problem_outlined` — 미결 배너 |

**ai-judge 화면에만 필요한 것(규칙 확정 + 이번에 함께 그림. 그리는 비용이 작고 대조표가 이 목록을 전제로 한다)**

| 이름 | 모양 | ai-judge 쓰는 곳 |
|---|---|---|
| `pass` | 굵은 동그라미(8각 계단 원) | 합격 |
| `fail` | 굵은 X | 불합격 |
| `retry` | 끝이 화살표인 ㄷ자 순환 | 재시도, 다시 찍기, 다시 검사하기 |
| `edit` | 연필 | 기준 수정 |
| `remove` | 빼기 | 기준 항목 삭제 |
| `expand` / `collapse` | 아래 / 위 꺾쇠 | 접이식 기준 목록 |
| `info` | 네모 안 i | 안내 블록 |
| `clock` | 시계 | 남은 시간, 제출 시각 |
| `lock` | 자물쇠 | 제출 잠금 |
| `document` | 모서리 접힌 종이 | 동의 문구, 오픈소스 라이선스 진입 |
| `openExternal` | 네모 + 바깥 화살표 | 개인정보처리방침 링크 |
| `close` | 가는 X(1셀) | 시트 닫기 |

---

## 3. 구성 요소

"자동" = ThemeData에만 규칙을 넣으면 기존·신규 화면의 Material 위젯에 저절로 입혀진다(개별 화면이 규칙을 지정하지 않아도 됨 — spec P0). "위젯" = Material에 대응 위젯이 없거나 테마로 표현할 수 없어 공용 위젯으로 만든다.

### 3.1 자동 (ThemeData)

| 요소 | Material 위젯 | 테마 규칙 |
|---|---|---|
| 앱바 | `AppBar` | 면 `paper`, 글자·아이콘 `ink`, 아래 4dp `ink` 선(`shape`), `elevation`·`scrolledUnderElevation` 0, 상태바 아이콘 어둡게(`systemOverlayStyle`), 제목 titleLarge(픽셀 24, 한 줄 말줄임은 AppBar 기본) |
| 탭바 | `NavigationBar` | 면 `surface`, 높이 72, 라벨 항상 표시, 라벨 labelMedium `ink`(선택 시 Bold), 선택 표시기 `primary` 면 + 2dp `ink` 테두리 + `PixelBorder`, 선택 아이콘 `surface`, 비선택 아이콘 `inkMuted`. 위 경계선은 NavigationBar에 shape가 없어 셸에서 2dp `ink` 윗줄로 감싼다(3.3 화면 절) |
| 주 버튼 | `FilledButton` | 면 `primary`, 글자 `surface`, `PixelBorder`(2dp `ink`, 바닥 두께 2dp), 최소 높이 48, 좌우 16, 글자 labelLarge. 눌림 = 눌림 변형. 비활성 = 면 `sunken`·글자 `inkDisabled`·테두리 `inkDisabled`·바닥 두께 0 |
| 보조 버튼 | `OutlinedButton` | 면 `surface`, 글자 `ink`, 나머지 주 버튼과 같음 |
| 보조(낮음) | `TextButton` | 면 투명, 글자 `ink`, 테두리·바닥 두께 없음, 눌림 시 `sunken` 면. 대화상자 "취소", "다시 시도" 등 |
| 위험 버튼 | `FilledButton` + `RetroButtonStyles.danger` | 면 `danger`, 글자 `surface`, 나머지 주 버튼과 같음. 기존 코드의 `FilledButton.styleFrom(backgroundColor: scheme.error)`도 테마와 합쳐져 같은 결과가 나온다. 텍스트형 위험 버튼(`TextButton` + `foregroundColor: scheme.error`)은 `danger` 글자로 자동 |
| 떠 있는 버튼 | `FloatingActionButton`(.extended) | 주 버튼과 같은 면·테두리·바닥 두께, 모든 elevation 0, 크기 56 |
| 아이콘 버튼 | `IconButton` | 48dp 터치 영역, 아이콘 24, 눌림 시 `sunken` 면 + `PixelBorder` |
| 카드(프레임 기본형) | `Card` | 면 `surface`, `PixelBorder`(2dp `ink`, 바닥 두께 2dp), elevation 0, margin 0. `InkWell` 겹침 색도 계단 모서리를 따른다 |
| 대화상자 | `AlertDialog` / `Dialog` | 면 `surface`, 4dp 이중 테두리 `PixelBorder`, 제목 픽셀 24, 본문 bodyMedium, 바깥 가림막 `ink` 55%, 좌우 여백 24 |
| 바텀시트 | `showModalBottomSheet` | 면 `surface`, 위쪽만 4dp `ink` 선 + 위 두 모서리 계단, 끌기 손잡이 대신 폭 32×4dp `ink` 막대, 가림막 `ink` 55% |
| 토스트 | `SnackBar` | floating, 면 `ink`, 글자 `surface` bodyMedium, 계단 모서리 2dp, 동작 글자 `amber`, 좌우 여백 16. 모든 `ScaffoldMessenger.showSnackBar` 호출에 자동 |
| 입력 필드 | `TextField` / `InputDecorationTheme` | 채움 `surface`, 테두리 2dp `ink` 직각, 포커스 2dp `primary` + 안쪽 2dp `ink`(합 4dp), 오류 테두리 `danger`, 힌트 `inkMuted` bodyLarge, 카운터 labelMedium(픽셀), 커서 `ink`, 선택 영역 `amber` 50% |
| 선택 컨트롤 | `SegmentedButton` | 각 칸 `PixelBorder` 2dp `ink`, 선택 = 면 `primary`·글자 `surface`·`PixelIcons.check`, 비선택 = 면 `surface`·글자 `ink`, 글자 labelLarge |
| 체크박스 | `Checkbox` | 20dp 칸, 2dp `ink` 직각 테두리, 체크됨 = 면 `ink` + 체크 `surface`(체크 모양은 Material 벡터 그대로 — 테마로 교체 불가, 칸 모양만 픽셀) |
| 목록 행 | `ListTile` | 아이콘 `ink`, 제목 bodyLarge, 부제 bodyMedium `inkMuted` |
| 구분선 | `Divider` | 2dp `line` |
| 진행 표시(Material) | `CircularProgressIndicator`, `RefreshIndicator`, `LinearProgressIndicator` | 색 `ink`, 배경 `sunken`. 모양 교체가 필요한 곳은 `PixelLoader`로 바꾼다(3.2) |
| 툴팁 | `Tooltip` | 면 `ink`, 글자 `surface` bodySmall, 직각 |
| 라이선스 화면 | `LicensePage` | 위 앱바·목록·글자 규칙이 그대로 적용됨 |
| 확장 목록 | `ExpansionTile` | `shape`/`collapsedShape` 투명(프레임 안에서 쓰는 것을 전제) |
| 공통 | — | `useMaterial3: true`, `splashFactory: NoSplash.splashFactory`, `materialTapTargetSize: padded`, `visualDensity: standard` |

`MaterialApp`에는 `theme: AppTheme.light`만 두고 `darkTheme`을 주지 않으며 `themeMode: ThemeMode.light`를 명시한다(결정 F).

### 3.2 위젯 (공용)

| 위젯 | 목적과 변형 | 상태 |
|---|---|---|
| `PixelIcon` | 2장 참고 | 색은 IconTheme, 크기 12/24/36/48 |
| `PixelFrame` | "무언가를 감싸는" 영역. 변형: **raised**(surface + 2dp ink + 바닥 두께 — 카드·상대 카드·결과 배너 바탕), **flat**(surface + 2dp ink, 바닥 두께 없음 — 섹션 묶음·기준 목록 블록), **inset**(sunken 면, 테두리 없음 — 인용된 텍스트 증거·짧은 요약), **tone**(아래 표). 선택 속성: `title`(위쪽에 `ink` 띠 + `surface` 픽셀 12 글자 = 창 제목 띠), `onTap`(누르면 눌림 변형) | 기본 / 눌림(onTap 있을 때) |
| `PixelFrame.tone` (안내 블록) | 문장이 들어가는 강조 블록. `info`: primaryPale 면 + 2dp primary 테두리 + `info` 아이콘. `success`: surface 면 + 2dp success 테두리 + `pass` 아이콘. `danger`: dangerPale 면 + 2dp danger 테두리 + `warning` 아이콘. `neutral`: sunken 면 + 2dp inkMuted 테두리. 제목(선택, 픽셀 12 Bold) + 본문(bodyMedium ink) | — |
| `PixelTag` | 짧은 글자 한 덩어리의 기본 조각. 속성: 면색, 테두리(실선/점선/없음, 색), 글자색, 크기(small: 높이 24·글자 12 / large: 높이 40·글자 24). 계단 모서리 2dp, 좌우 8 | — |
| `BattleTypeBadge` (기존 유지·재작성) | `PixelTag` 기반. surface 면 + 2dp ink 테두리 + **왼쪽 색 칸**(속도전 amber / 품질전 mint, 20×20) 안에 ink 픽셀 아이콘(`speed`/`quality`, 12dp) + 오른쪽 글자 labelSmall ink. 색·아이콘·글자 세 가지로 구분 | — |
| `BattleStatusChip` (기존 유지·재작성) | 아래 표의 스타일 매핑을 `PixelTag`로 그림. 글자는 기존 `battleStatusLabel` 그대로 | — |
| `ResultLabel` (신규, `battle_chips.dart`에 함께) | 결과 라벨. 아래 표. small(프로필 기록 목록 오른쪽) / large(결과 배너) | — |
| `PixelLoader` | 8×8dp 사각형 3개가 가로로. 150ms마다 하나씩 `ink`로 켜지고 나머지는 `line`. 크기 small(버튼 안, 높이 12) / medium(화면·영역, 높이 16). **애니메이션 줄이기면 3개 모두 `ink`로 정지.** 시맨틱 라벨 `AppStrings.loading` | 움직임 / 정지 |
| `StatusMessage` | 로딩·빈·오류 상태를 한 모양으로. 구성: 픽셀 아이콘 36(선택) 또는 `PixelLoader`, 문장 bodyMedium(가운데 정렬), 보조 문장 bodySmall inkMuted(선택), 동작 버튼 하나(선택). 변형 `loading` / `empty` / `error`(아이콘 `warning`). `compact`(영역 안, 세로 여백 12) / `fill`(화면 전체, 세로 가운데). 긴 기다림(ai-judge "AI가 기준을 만들고 있어요")은 `loading` + 문장 + 보조 문장으로 해결 | — |
| `EvidencePhotoFrame` | 증거 사진 틀(결정 C). 바깥 2dp `ink` 계단 테두리 → 안쪽 4dp `sunken` 여백 → 사진. **사진은 여백 안쪽에만 그려 테두리·모서리 계단이 사진 픽셀을 덮지 않는다.** `BoxFit.contain`(자르지 않음, 남는 곳은 `sunken`), `filterQuality`는 Flutter 기본값(`medium`) 유지 — `none`(도트화)·색 필터·`cacheWidth` 축소 금지. 변형 `thumbnail`(높이 160, 기존 자리 크기) / `large`(가로 꽉 참, 높이는 사진 비율). 하위 상태: 로딩 = 같은 크기 틀 안 `PixelLoader`, 실패 = 같은 틀 안 `brokenImage` 아이콘 + 문장 + "다시 시도" `TextButton`(글자가 넘치면 줄바꿈) | 로딩 / 표시 / 실패 |
| `InitialBadge` | 표시 이름의 이니셜 한 글자를 담는 정사각 칸. 크기 40(카드용, 글자 24) / 72(VS 인트로, 글자 36). 면색은 호출자가 `primary`(나) / `amber`(상대) 중 지정, 글자는 면에 맞는 on 색(surface / ink), 2dp ink 테두리 + 바닥 두께 | — |
| `RetroButtonStyles.danger` | 위험 버튼 `ButtonStyle` 상수(FilledButton·OutlinedButton 겸용) | — |
| 버튼 진행 중 | 새 위젯 없음. 규칙: 진행 중이면 `onPressed: null` + 라벨 자리에 `PixelLoader.small`(버튼 크기 유지). 비활성 모양이 적용되어 누를 수 없음이 보인다 | — |

#### 상태 칩 8종 (`battleStatusTagStyle(status)` 순수 함수로 매핑)

| status | 글자(기존 문자열) | 면 | 테두리 | 글자색 | 의도 |
|---|---|---|---|---|---|
| `pending` | (현재 칩으로 안 보임) | surface | 2dp ink **점선** | ink | 빈 자리 = 점선 |
| `active` | 진행중 | primary | 2dp ink | surface | 주 강조 |
| `judging` | 판정중 | lavender | 2dp ink | ink | 기다림 |
| `finished` | 종료 | success | 2dp ink | surface | 정상 종결 |
| `draw` | 무승부 | sunken | 2dp ink | ink | **중립. 위험색 쓰지 않음** |
| `disputed` | 미결 | dangerPale | 2dp danger | ink | 이의제기로 끝남(기존에도 error 계열) |
| `cancelled` | (현재 칩으로 안 보임) | sunken | 없음 | inkMuted | 흐려진 끝 |
| `voided` | (ai-judge가 "무효" 문자열 추가) | 투명 | 2dp inkMuted **점선** | inkMuted | 전적에 안 들어가는 약한 끝 |

- `draw`와 `disputed`는 면·테두리·글자가 모두 달라 합쳐 보이지 않는다(수용 기준).
- 사용자에게 보이는 글자는 바꾸지 않는다(spec "문구 동일"): 기존 문자열 "진행중", "판정중", "무승부"를 그대로 쓴다. `pending`/`cancelled`/`voided`의 라벨 문자열은 이번에 추가하지 않는다 — 현재 어느 화면도 이 세 상태의 칩을 보여 주지 않고, "무효" 문자열은 ai-judge 몫이다. 모양 매핑만 미리 둔다.
- 알 수 없는 status → `draw`와 같은 중립 스타일(기존 `_` 분기와 같은 동작).

#### 결과 라벨 (`resultTagStyle(label)` 순수 함수로 매핑)

| 결과 | 면 | 테두리 | 글자색 | 강도 |
|---|---|---|---|---|
| 승 | amber | 2dp ink + 바닥 두께 | ink | 가장 강함(유일하게 떠 있음) |
| 패 | inkMuted | 2dp ink | surface | 보통 |
| 무 | sunken | 2dp ink | ink | 중립 |
| 무효 | 투명 | 2dp inkMuted 점선 | inkMuted | **가장 약함**(면 없음·점선·흐린 글자) |
| 종료(현재 품질전 기록) | success | 2dp ink | surface | 보통 |
| 미결(현재 기록) | dangerPale | 2dp danger | ink | 보통 |

현재 `BattleRecord.resultLabel`은 문자열이라 매핑 함수도 `AppStrings` 값을 키로 받는다. ai-judge 7단계에서 `outcome` 기반으로 바뀌면 키만 바꾼다. "종료"·"미결" 행은 ai-judge에서 사라진다.

### 3.3 ai-judge 대조표 (design.md "화면" 1~8)

| ai-judge 화면 | 요소 | retro-theme 구성 요소 |
|---|---|---|
| 1. 동의 화면 | 앱바 | AppBar(자동) |
| | 받는 자·항목·목적·보유·거부 권리 본문 | `PixelFrame.flat` + bodyMedium(본문 글꼴, 혼용 규칙 5) |
| | 개인정보처리방침 링크 | `TextButton` + `PixelIcons.openExternal` |
| | "동의하고 계속" / "동의하지 않음" | FilledButton(주) / OutlinedButton(보조) |
| | 로딩 / 제출 중 / 실패 | `StatusMessage.loading(fill)` / 버튼 진행 중 규칙 / SnackBar(자동) |
| 2. 동의 철회 | 프로필 동의 한 줄 + 날짜 | `PixelFrame.flat(title)` + bodyMedium(문장 속 날짜라 본문 글꼴) |
| | "동의 철회" / "동의하기" | 위험 버튼 / 주 버튼 |
| | 철회 확인 대화상자(서버 조회 문장, 로딩 중 확인 비활성) | AlertDialog(자동) + 본문 bodyMedium + 비활성 버튼 모양 + 본문 자리 `PixelLoader.small` |
| 3. 대결 만들기 | 유형 선택, 기간 선택 | SegmentedButton(자동). 유형 칸 안에 `speed`/`quality` 아이콘을 넣어도 됨 |
| | 제목 입력(60자) | TextField(자동, 카운터 픽셀) |
| | "오늘 남은 기준 생성 n/10회" | 버튼 아래 bodySmall 줄(혼용 규칙 3·4) |
| | 사전 차단 안내 | `PixelFrame.tone(info)` / 한도류는 `tone(neutral)` |
| | 단계 B 전체 로딩(최대 30초) | `StatusMessage.loading(fill)` + 보조 문장 |
| | 차단 빨간 블록 + AI 사유 | `PixelFrame.tone(danger)` |
| | 최소 기준 / 우열 기준 두 블록 | `PixelFrame.flat(title: …)` 두 개 + 번호는 `RetroText.numeric`, 항목은 bodyMedium |
| | 수정 모드 항목 편집·추가·삭제 | TextField(자동) + `IconButton(PixelIcons.add / remove)` |
| | "수정" / "이 기준으로 올리기" / "다시 검사하기(1회 차감)" / "원래 기준으로 되돌리기" / "제목 고치기" | OutlinedButton / FilledButton / FilledButton(괄호까지 픽셀, 규칙 2) / TextButton / OutlinedButton |
| | AI 실패 + 재시도 | `StatusMessage.error` + `PixelIcons.retry` 버튼 |
| 4. 모집 목록 | 열린 모집 카드(탭 → 시트) | `PixelFrame.raised(onTap)` 또는 Card(자동) |
| | 유형 배지, 기간 | `BattleTypeBadge`, `PixelTag.small(neutral)` |
| | 생성자 이름 + 점수 + 승/패/무 | `InitialBadge(40)` + 이름 bodyLarge + `RetroText.numeric` |
| | 기준 첫 항목 미리보기 | bodySmall inkMuted, 한 줄 말줄임 |
| | 모집 상세 바텀시트 | showModalBottomSheet(자동) + `PixelFrame.flat(title)` 기준 블록 + 생성자 카드(`PixelFrame.raised` + `InitialBadge`) + 주 버튼 |
| | "생성자가 기준을 바꿨어요" 배너 | `PixelFrame.tone(info)` |
| | 참가 성공 | SnackBar + **VS 인트로**(4장 연결 지점) |
| | 한도·이미 참가됨 오류 | SnackBar |
| | 내 모집 카드: 기준 보기/수정, 모집 취소 | Card + OutlinedButton + TextButton |
| 5. 내 대결 목록 | 카드, 유형 배지, 상태 칩 | Card(자동), `BattleTypeBadge`, `BattleStatusChip` |
| | 상태 줄("상대가 제출했어요", "AI 판정 중", "마감됨 · 판정 마무리 중") | `PixelIcon(12)` + bodySmall 한 줄(문장이라 본문 글꼴) |
| 6. 대결 상세 | 헤더 배지·칩(무효 포함) | `BattleTypeBadge`, `BattleStatusChip`(`voided` 매핑 준비됨) |
| | 마감·남은 시간 | `PixelIcons.clock` + 남은 시간 칸 `PixelTag.small` 안 `RetroText.numeric` |
| | 상대 카드(이름·점수·승/패/무) | `PixelFrame.raised` + `InitialBadge(40)` + numeric |
| | 접이식 기준 목록(두 블록) | `PixelFrame.flat(title)` 안 `ExpansionTile`(자동) + `expand`/`collapse` 아이콘 |
| | "사진 찍기" / 미리보기 / "제출" / "다시 찍기" | FilledButton + `camera` / `EvidencePhotoFrame.large` / FilledButton / OutlinedButton + `retry` |
| | "판정 n/5회 남음 · …" 안내 | 버튼 아래 bodySmall |
| | 업로드 중 / AI 판정 중 | `StatusMessage.loading(compact)` |
| | 합격 / 불합격 / AI 실패 결과 + 사유 | `PixelFrame.tone(success)` + `pass` / `tone(danger)` + `fail` / `tone(neutral)` + `warning`. 정적 표시(판정 연출 아님, 확정 3) |
| | 거부 사유 문구 | SnackBar |
| | 제출 이력(시각, 합격/불합격/실패, 사유, 썸네일) | 목록 행 + `PixelTag.small`(합격 = success 면/surface 글자, 불합격 = dangerPale 면/danger 테두리, 실패 = 투명/inkMuted 점선) + `EvidencePhotoFrame.thumbnail` + `lock` 아이콘(잠금) |
| | 품질전 "제출(한 번만 낼 수 있어요)" 확인 | AlertDialog(자동) |
| | 상대 영역 "아직 제출 전" / "제출했어요(hh:mm)" | bodyMedium |
| | 결과 배너(승/패/무/무효/취소 + 부제 + 점수 변화) | `PixelFrame.raised` + `ResultLabel.large` + 부제 bodyMedium + 점수 변화 `RetroText.numeric`. "취소"는 `BattleStatusChip(cancelled)` 모양 |
| | 양쪽 이력 공개 | 위 이력 행과 같음 |
| | 포기 버튼 + 확인 | 위험 버튼(`flag`) + AlertDialog(확인 버튼 위험 스타일) |
| 7. 앱 내 카메라 | 시스템 카메라 호출 | 앱 밖 화면. 앱 안은 `camera` 아이콘 버튼뿐 |
| 8. 프로필 | 점수(큰 글씨) | `RetroText.numeric` 36(displaySmall과 같은 크기) |
| | 승 n · 패 n · 무 n | numeric 12 줄 |
| | 기록 목록 라벨 승/패/무/무효(무효는 약하게) | `ResultLabel.small` |
| | 동의 섹션 | `PixelFrame.flat(title)` |

**빠진 것 없음.** 이 대조 과정에서 추가한 것: `PixelTag`(판정 이력 태그·기간 칸 공용 바탕), `PixelFrame.tone` 4변형(차단·안내·합격·불합격 블록), `InitialBadge`(VS 인트로와 상대·생성자 카드 공용), `RetroText.numeric`, 아이콘 12종(2.3 두 번째 표), 대화상자 확인 버튼 로딩 규칙.

---

## 4. VS 매칭 인트로 (확정 3·4, 결정 D·E)

### 4.1 표시 여부 판단 (순수 함수)
`shouldShowVsIntro({required String status, required bool alreadySeen})` → `status`가 `active` 또는 `judging`이고 `!alreadySeen`이면 `true`.
- `pending`(상대 없음), `finished`/`disputed`/`draw`/`cancelled`, ai-judge의 `voided`는 모두 `false`(종결 대결 제외, 수용 기준).

### 4.2 "봤다" 기억 방식
- **기기 로컬 + 계정별 키.** 키 `vs_intro_seen/<userId>/<battleId>` = `true`. 같은 기기에서 다른 계정으로 로그인하면 그 계정 기준으로 한 번 더 뜬다(대결마다 "한 사람에게 한 번"). 재설치·다른 기기에서 다시 뜨는 것은 spec이 허용.
- 서버 저장은 쓰지 않는다(스키마 변경 없음이 이 기능의 전제).
- 저장소: **`shared_preferences`.** 이미 `supabase_flutter`의 전이 의존성으로 `pubspec.lock`에 들어 있어(설치 크기·빌드 영향 없음), `pubspec.yaml`에 직접 의존성으로 **같은 버전대를 명시만** 한다. 전이 의존성을 import만 하면 `depend_on_referenced_packages` 린트에 걸리기 때문이다. 커밋 메시지에 "supabase_flutter가 이미 쓰는 shared_preferences를 직접 의존성으로 명시 — VS 인트로 본 기록"을 적는다.
- **표시를 시작하는 순간 기록한다**(끝난 뒤가 아니라). 인트로 도중 앱이 죽거나 사용자가 건너뛰어도 다시 뜨지 않게 하기 위함이다.
- 접근은 `VsIntroSeenStore`(읽기 `hasSeen`, 쓰기 `markSeen`) 하나로 감싸고 Riverpod provider로 둔다. 위젯 테스트에서 가짜로 바꾸기 위함이다(추상 인터페이스를 따로 두지 않고 provider override로 해결).
- 저장소 읽기·쓰기 실패 → `debugPrint`로 로그를 남기고 **인트로를 건너뛴다**(대결 진입은 계속). **토스트는 띄우지 않는다**(2026-09-15 오너 확정). 인트로 표시 실패(4.5)도 같다. CLAUDE.md "에러는 토스트로 알린다" 규칙의 예외이며, 해당 catch 블록에 이유 주석을 남기고 4단계에서 CLAUDE.md에 예외 한 줄을 추가한다.

### 4.3 레이아웃 (세로 화면 기준)
```
┌───────────────────────────── paper ─┐
│                     상대(12, inkMuted)│
│  ┌──────────── 명판(상대) ─────────┐ │  ← 오른쪽에서 들어옴
│  │ 표시 이름(픽셀 24, 오른쪽 정렬) [이니셜72·amber] │
│  └────────────────────────────────┘ │
│ ████████████  V S  ████████████████ │  ← ink 띠(높이 96) 위 surface "VS"(72)
│  ┌──────────── 명판(나) ───────────┐ │  ← 왼쪽에서 들어옴
│  │ [이니셜72·primary] 표시 이름(픽셀 24, 왼쪽 정렬) │
│  └────────────────────────────────┘ │
│ 나(12, inkMuted)                     │
└─────────────────────────────────────┘
```
- 세로로 쌓는 이유: 360dp 폭에서 좌우로 나누면 이름 칸이 약 130dp라 긴 이름이 금방 잘린다. 위아래 배치면 이름 칸이 약 240dp다.
- 명판: 4dp 이중 테두리 `PixelFrame`(raised) + 안쪽 12 여백. "나"/"상대" 작은 글자는 기존 `AppStrings.battleMe`/`battleOpponent` 재사용. "VS"는 `AppStrings.vsIntroVersus = 'VS'`로 추가(라틴 문자 두 글자, 특정 게임 고유 문구 아님).
- 캐릭터·사진·마스코트 없음(확정 4). 이니셜 칸은 글자만.
- 전체를 `Semantics(label: AppStrings.vsIntroSemantics(나, 상대), liveRegion: true)` 하나로 묶어 화면 읽기 사용자에게 "나 대 상대"를 한 번 읽어 준다.

**이름 처리 (`displayInitial(String name)` 순수 함수)**
- 앞뒤 공백 제거 후 **첫 번째 글자 단위(grapheme)** 하나. 라틴 소문자는 대문자로. 이모지·결합 문자도 한 글자 단위로 자른다(`characters` — Flutter SDK의 `widgets.dart`가 이미 export).
- 비었거나 공백뿐이면 `?`.
- "탈퇴한 사용자"(서버 묘비 표시명) → 이니셜 "탈", 이름은 그대로 표시. 서버가 준 문자열을 특별 취급하지 않는다(문자열 비교로 분기하면 서버 문구가 바뀔 때 깨짐). provider의 폴백 "알 수 없음"도 같은 규칙.
- 긴 이름: 최대 2줄 + 말줄임(`maxLines: 2, overflow: ellipsis`). 한 글자 이름: 이니셜과 이름이 같아도 그대로 둔다.
- 글자 크기 상한 1.3에서도 명판이 넘치지 않도록 이름 영역은 `Flexible`, 화면 높이가 520dp 미만(가로 모드·작은 화면)이면 이니셜 칸을 40으로, "VS"를 48로 줄인다(`LayoutBuilder`).

### 4.4 연출 타임라인 (총 1500ms)
모든 움직임은 50ms 단위 계단식.

| 구간(ms) | 내용 |
|---|---|
| 0–150 | paper 배경 위 가운데 `ink` 띠가 높이 0 → 96으로 3단계(50ms씩) 펼쳐짐 |
| 150–550 | 위 명판(상대)은 화면 오른쪽 밖 → 제자리, 아래 명판(나)은 왼쪽 밖 → 제자리. 8단계(50ms씩) 동시 |
| 550–750 | "VS"가 3배 → 1배로 4단계 축소하며 나타남 |
| 750–850 | 띠 색이 `amber`로 한 번 바뀌었다가(750–800) `ink`로 돌아옴(800–850) — 부딪히는 순간 표현. 번쩍임은 1회, 100ms로 짧게(광과민 기준 초당 3회 미만) |
| 850–1300 | 정지(이름을 읽는 시간) |
| 1300–1500 | 전체가 paper로 4단계(50ms씩) 덮이며 사라짐 |
| 1500 | 인트로 닫힘. 원래 화면이 보임(닫힘 전환 애니메이션 0ms) |

- **건너뛰기**: 인트로 어디를 눌러도(`GestureDetector` 전체 영역) 즉시 닫힘. 시스템 뒤로 가기도 닫힘.
- **애니메이션 줄이기**(`MediaQuery.disableAnimationsOf(context) == true`, Android "애니메이션 삭제"): 1300ms 시점의 완성 화면(띠 ink, 명판 제자리, VS 1배)을 처음부터 정지 상태로 보여 주고 1500ms 뒤 닫힘. 누르면 즉시 닫힘. 번쩍임·덮기 없음.
- 효과음·진동 없음(결정 G).

### 4.5 구조 — 실패해도 진입을 막지 않음
- 인트로는 **전체 화면 불투명 route**(열기·닫기 전환 0ms, `Scaffold` 없음)로 띄우는 함수 `showVsIntro(context, {myName, opponentName})` → `Future<void>`. `Scaffold`를 쓰지 않으므로 토스트가 인트로 위에 붙지 않는다.
- 함수 안에서 모든 예외를 잡아 `debugPrint` 로그 후 정상 반환한다(토스트 없음, 4.2 참고). 호출자는 인트로 결과와 무관하게 다음 동작을 이어 간다.
- 인트로 route의 자동 닫힘은 route가 아직 최상단일 때만 pop한다(사용자가 이미 눌러 닫았으면 아무것도 안 함).
- 안전장치: 인트로 route가 어떤 이유로 3초 넘게 남아 있으면 자동으로 닫는다(애니메이션 컨트롤러가 멈춘 경우 대비).
- 호출 지점의 판단 순서: (1) status로 `shouldShowVsIntro` 1차 판단 → (2) 저장소 `hasSeen` → (3) `markSeen` → (4) `showVsIntro`. 어느 단계에서 실패해도 인트로만 건너뛴다.

### 4.6 붙이는 지점 (현재 코드)

**A. 참가 성공 직후 — `BattleRecruitsScreen._join`**
현재: `joinBattle` 성공 → 목록 invalidate → 토스트 "매칭되어 대결이 시작됐습니다." (화면은 대결 찾기에 머무름)
변경 후 순서:
1. `joinBattle` 성공 → `openRecruitsProvider`/`myBattlesProvider` invalidate(기존).
2. 인트로 이름: 나 = `myProfileProvider` 값(읽기 실패 시 `AppStrings.battleMe`), 상대 = `recruit.creatorName`(이미 목록에 있음 — `_join`에 battleId 대신 recruit를 넘긴다). battleId·userId로 4.5 순서 실행.
3. `await showVsIntro(...)`가 끝난 뒤 → 토스트 "매칭되어 대결이 시작됐습니다."
4. 실패 경로: `joinBattle` 예외 → 인트로 없이 즉시 오류 토스트(기존 그대로).

→ 인트로가 성공 토스트를 가리지 않는다(토스트가 인트로 뒤에 나온다). 성공 토스트가 1.5초 늦게 나오는 대신, 인트로 자체가 "매칭 성공"을 보여 준다. 참가 status는 서버가 `active`로 바꾼 직후이므로 1차 판단에 `'active'`를 넘긴다.

**B. 매칭된 대결 첫 진입 — `BattleDetailScreen`**
- 대결 상세 데이터(`battleDetailProvider`)가 **처음 성공적으로 도착한 뒤 한 번만** 판단한다(새로고침·재빌드마다 판단하지 않도록 화면 상태에 "이번 진입에서 판단함" 플래그). 이를 위해 `BattleDetailScreen`을 상태가 있는 위젯으로 바꾸거나 판단 전용 작은 상태 위젯을 헤더 옆에 둔다 — 화면 배치는 바뀌지 않는다.
- 이름: 나 = `detail.myName`, 상대 = `detail.opponentName`. status = `detail.battle.status`.
- 판단이 참이면 다음 프레임에 `showVsIntro`를 띄운다. 인트로 아래에서 상세 화면은 이미 그려져 있으므로 닫히면 곧바로 상세가 보인다.
- 로딩 실패·오류 상태에서는 판단하지 않는다.
- 이 한 지점이 모집 올린 사람의 모든 진입 경로(내 대결 카드, 이후 생길 경로)를 덮는다. 참가자는 A에서 이미 기록했으므로 B에서 다시 뜨지 않는다. A에서 기록이 실패한 참가자는 B에서 한 번 보게 되는데, 이것도 "한 번" 규칙 안이다.
- 프로필 기록 목록에서 들어가는 대결은 종결 상태라 뜨지 않는다.

**C. ai-judge에서 다시 연결할 지점**
- 화면 4 모집 상세 시트의 "참가 성공" 분기: **시트 닫기 → invalidate → `await showVsIntro` → 토스트 → 내 대결 탭 이동** 순서. 이름은 시트가 가진 생성자 카드의 이름.
- 화면 6 대결 상세(대폭 변경)의 첫 데이터 도착 시점에 B와 같은 판단을 유지. `voided`는 4.1에서 이미 제외됨.
- `showVsIntro`, `shouldShowVsIntro`, `displayInitial`, `VsIntroSeenStore`는 그대로 재사용하고 새로 만들지 않는다.

---

## 5. 화면별 적용

### 5.1 로그인 (게임 타이틀 느낌, 구성·기능 그대로)
- 배경 `paper`. 세로 가운데 묶음:
  1. **런처 아이콘과 같은 픽셀 마크**(6장의 16×16 비트맵을 셀 6dp로 = 96dp, `primary` 계단 사각 바탕 위). 아이콘 → 로그인 화면 색·모양이 이어진다.
  2. 간격 24.
  3. 앱 이름 "투두두두": displayMedium(픽셀 48) `ink` + 4dp 오른쪽·아래 `amber` 그림자(흐림 0). 폭이 모자라면 `FittedBox(scaleDown)`.
  4. 간격 40.
  5. 행: 왼쪽 `▶` 모양 픽셀 커서(12×12 격자, 24dp, 500ms 켜짐/500ms 꺼짐 깜빡임, 애니메이션 줄이기면 켜진 채 정지) + 간격 8 + "구글로 로그인" 주 버튼(최소 폭 200, 높이 56).
- 새 문구 없음. 로그인 실패 토스트 그대로(자동 모양).
- `AuthGate` 로딩 화면: `paper` 배경 + `PixelLoader.medium`.

### 5.2 하단 탭바 (4탭·순서·이름 그대로)
- `NavigationBar` 위젯은 유지(기존 테스트가 `NavigationBar`/`NavigationDestination` 4개를 찾음). 3.1 테마 + 아이콘 교체(`battle`, `search`, `todo`, `profile`). 선택 표시는 표시기 면색으로 하므로 `selectedIcon`은 두지 않는다.
- 셸에서 탭바를 2dp `ink` 윗선으로 감싼다.

### 5.3 할 일 목록 (조작·구성 그대로)
- 앱바: 자동.
- 목록: 기존 `ListView.builder` + `ListTile` 구조 유지. 각 행을 `PixelFrame`으로 감싸고 행 사이 8, 화면 가장자리 16.
  - 안 한 할 일: `PixelFrame.raised`(surface), 체크박스 비어 있음, 내용 bodyLarge `ink`.
  - 완료한 할 일: `PixelFrame.inset`(sunken 면, 바닥 두께 없음 = 가라앉음), 체크박스 채움, 내용 bodyLarge `inkMuted` + **취소선 유지**(기존 테스트 확인 항목).
  - → 면색·높낮이·체크·취소선 네 가지로 한눈에 구분(수용 기준).
  - 행 탭 = 수정 대화상자(기존), 오른쪽 `IconButton(PixelIcons.delete)`(툴팁 기존 문자열).
- FAB: `PixelIcons.add`, 자동 모양. 기존 테스트가 `FloatingActionButton`을 찾으므로 위젯 유지.
- 빈 상태: `StatusMessage.empty(fill)` + `todo` 아이콘 + 기존 문구.
- 로딩: `StatusMessage.loading(fill)`. 오류: `StatusMessage.error(fill)` + 기존 문구(동작 버튼 없음 — 기존에도 없음).
- 입력 대화상자: 자동(AlertDialog·TextField·버튼). 버튼 순서·문구 그대로.

### 5.4 프로필 (결정 H)
**계정 섹션만 정리** — 기존 `Divider` + 제목 + 버튼 두 개 자리를 하나의 프레임으로 바꾼다:
- `PixelFrame.flat(title: AppStrings.accountSection)` 안에 세로로(간격 8):
  1. 로그아웃: `OutlinedButton`(가로 꽉 참) + `PixelIcons.logout`.
  2. 오픈소스 라이선스: `TextButton`(가로 꽉 참, 왼쪽 정렬) + `PixelIcons.document` → `showLicensePage(context: context, applicationName: AppStrings.appName)`. 새 문자열 `AppStrings.openSourceLicenses = '오픈소스 라이선스'`.
  3. 2dp `line` 구분선.
  4. 계정 삭제: 위험 버튼(`FilledButton` + `RetroButtonStyles.danger`, 가로 꽉 참) + `PixelIcons.accountDelete`. 진행 중 = 버튼 진행 중 규칙(`PixelLoader.small`). 문구 그대로.
- 삭제 확인 대화상자: 자동 모양 + 확인 버튼 위험 스타일(기존 `styleFrom(error)`를 `RetroButtonStyles.danger`로 교체). 순서·문구 그대로.
- 위험 버튼(danger 빨강 면)은 주 버튼(primary 파랑 면)과 면색이 다르고 섹션 맨 아래 구분선 뒤에 따로 있어 한눈에 구분된다.

**이름·전적 요약·기록 목록**: 배치 그대로. 자동 테마 + 기존 공용 조각(`BattleTypeBadge`)만 따라 바뀌고, 기록 행 오른쪽의 결과 글자(`titleMedium` bold Text)만 `ResultLabel.small`로 바꿔 끼운다(spec "공용 조각(배지, 결과 라벨)이 입혀지는 수준"). 로딩 표시는 `PixelLoader.medium`으로 교체.

### 5.5 현재 대결 화면 4개 — 자동 적용 + 깨짐 점검 목록
배치는 바꾸지 않는다. 아래는 코드에서 찾은 **테마만으로는 해결되지 않거나 깨질 위험이 있는 곳**과 허용하는 최소 수정이다.

| # | 위치 | 문제 | 허용하는 수정 |
|---|---|---|---|
| 1 | `battle_chips.dart` 배지·칩 | `BorderRadius.circular(999)` 알약 모양, 품질전 배지 글자색 `scheme.tertiary`(새 팔레트에서 mint 글자 = surface 대비 1.9로 읽을 수 없음), Material 아이콘 | 3.2 `BattleTypeBadge`/`BattleStatusChip` 재작성(공용 조각 본체) |
| 2 | `battle_summary_list.dart` `_BattleCard` 제목 | `titleMedium` bold → 픽셀 24가 되어 대결 제목(목록 본문, 결정 A)이 픽셀로 바뀌고 긴 제목이 여러 줄로 커짐 | 스타일 한 줄만 `bodyLarge` + `FontWeight.w600`으로 |
| 3 | `battle_summary_list.dart` Card+InkWell | `clipBehavior: antiAlias` + 테마 shape → 계단 모서리 클립 확인 필요 | 테마로 해결. 수정 없음, 수동 확인 |
| 4 | `battle_recruits_screen.dart` 목록 `ListTile.trailing` `FilledButton` | 최소 높이 48 + 바닥 두께 + 1.3배 글자에서 trailing 폭·높이 넘침 위험 | 넘치면 해당 버튼만 `visualDensity: compact`/`minimumSize` 조정 |
| 5 | `battle_recruits_screen.dart` FAB.extended 아이콘, 섹션 제목 `titleMedium` | Material 아이콘 / 섹션 제목은 픽셀 24가 맞음 | 아이콘만 `PixelIcons.battle` |
| 6 | `battle_recruits_screen.dart`, `my_battles_screen.dart`, `create_battle_screen.dart`, `battle_detail_screen.dart`, `profile_screen.dart`, `auth_gate.dart`, `todo_list_screen.dart`의 `CircularProgressIndicator` (총 10곳) | Material 원형 스피너 | 같은 크기 자리에 `PixelLoader`로 교체 |
| 7 | `create_battle_screen.dart` `SegmentedButton` 2개 | 선택 체크 아이콘 | 테마 `selectedIcon`으로 해결 |
| 8 | `battle_detail_screen.dart` 사진 미리보기·네트워크 사진 | `ClipRRect(BorderRadius.circular(8))` + `BoxFit.cover`(사진 잘림 = 내용 가림) | `EvidencePhotoFrame.thumbnail`로 교체(높이 160 유지, contain). 로딩·실패 상태도 틀 안으로 |
| 9 | `battle_detail_screen.dart` `_EvidencePhotoState._failed` | `Row(Icon, Text, TextButton)`에 `Flexible` 없음 → 1.3배 글자에서 가로 넘침 | `EvidencePhotoFrame` 실패 상태로 흡수(줄바꿈 허용) |
| 10 | `battle_detail_screen.dart` `_ResultBanner` | `BorderRadius.circular(12)`, Material 아이콘 5종(얼굴 아이콘 포함), 헤드라인 `titleMedium` bold → 픽셀 24로 긴 문장("이의제기가 있어 아직 미결 상태예요." 등)이 3~4줄 | 컨테이너를 `PixelFrame.tone`(승 = raised, 패·무 = neutral, 미결 = danger, 품질전 완료 = success)으로, 아이콘을 `trophy`/`lose`/`hourglass`/`warning`/`check`로, 헤드라인 스타일을 `bodyLarge` + w700으로(문장이므로 본문 글꼴) |
| 11 | `battle_detail_screen.dart` 사진 고르기 바텀시트 `ListTile.leading` | Material 아이콘 2개 | `camera`/`gallery` |
| 12 | `battle_detail_screen.dart` 포기 `TextButton.icon` | `foregroundColor: scheme.error` → danger/paper 4.9로 통과, 아이콘 `flag_outlined` | 아이콘만 `PixelIcons.flag` |
| 13 | `battle_detail_screen.dart` 승인·이의제기 `Row(FilledButton, OutlinedButton)` | `Row`에 줄바꿈 없음 → 1.3배에서 두 버튼 합 폭 확인 필요("승인" 2자·"이의제기" 4자라 여유 있음) | 수동 확인만. 넘치면 `Wrap`으로(배치 의미 동일) |
| 14 | `battle_detail_screen.dart` 대화상자 2개의 `FilledButton.styleFrom(backgroundColor: scheme.error)` | 테마와 합쳐져 danger 면 + 계단 모양 | 수정 없음(자동) |
| 15 | `battle_detail_screen.dart` 앱바 제목 = 대결 제목 | 픽셀 24 한 줄 → AppBar 기본 말줄임으로 잘림 표시 | 수정 없음(자동) |
| 16 | `battle_detail_screen.dart` `_EvidenceSection` 소제목 `titleSmall`("나 (이름)") | 픽셀 12 Bold, 긴 이름은 줄바꿈 | 수정 없음 |
| 17 | `battle_detail_screen.dart` `TextField` 텍스트 증거(maxLines 3) | 자동 | 수정 없음 |
| 18 | `profile_screen.dart` 기록 행 결과 글자 | `titleMedium` bold Text | `ResultLabel.small`(5.4) |
| 19 | 앱 전체 `RefreshIndicator` | Material 원형 새로고침 표시 | 색만 테마. 모양 교체 없음(당겨서 새로고침 전용 위젯이라 교체하면 동작을 새로 만들어야 함) |
| 20 | Android 시작 창 `values-night/styles.xml` | 다크 모드 기기에서 `Theme.Black` → 첫 프레임 전 검은 화면(수용 기준 "일부만 어둡게 바뀌는 곳 없음" 위반) | 7장에서 night 스타일도 라이트 부모 + `paper` 배경으로 |

수동 점검 조건(각 대결 화면에서 모집 등록·취소, 참가, 증거 제출, 승인/이의제기, 포기를 끝까지): 글자 크기 1.0 / 1.3(상한) / 기기 최대(=1.3에서 멈추는지), 기기 다크 모드, 애니메이션 삭제 켬.

---

## 6. 런처·스토어 아이콘 (결정 B)

### 6.1 모티프
**계단 모서리 체크 칸에서 체크 표시가 칸 밖으로 튀어나오는 모양 + 1셀 오른쪽·아래 단단한 그림자.**
- 체크 칸 = 할 일(투두), 칸을 뚫고 나가는 굵은 체크 = "먼저 해치운다"(대결·완료), 단단한 그림자 = 레트로 UI의 바닥 두께 규칙과 같은 표현. 현재 아이콘의 의미("할 일 완료 체크")를 유지하되 픽셀로 옮긴다.
- 캐릭터·얼굴·원형 볼·특정 게임 고유 도형 없음.
- 색: 배경 `primary`(아이콘의 주된 색 = 앱의 주 강조색 → 선택 탭·주 버튼과 이어짐), 체크 칸 테두리 `surface`, 체크 `amber`, 그림자 `ink`. 모두 팔레트 안.

### 6.2 격자와 크기
- 런처 전용 **16×16 셀 비트맵**(앱 안 아이콘의 12×12보다 세밀. 작은 크기에서도 체크 획이 2셀 굵기로 남도록). 비트맵은 색 인덱스 문자열(`.` 투명, `s` surface, `a` amber, `k` ink).
- **셀 크기는 밀도마다 정수 픽셀**로 맞춰 번짐을 없앤다. 그림 영역 = 16 × 셀px, 가운데 정렬.

| 대상 | 캔버스 | 셀px(mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi) | 그림 영역 |
|---|---|---|---|
| 적응형 전경 `ic_launcher_foreground.png` | 108dp | 3 / 4 / 6 / 9 / 12 | 48dp(가운데) |
| 단색 `ic_launcher_monochrome.png` | 108dp | 위와 같음 | 48dp |
| 정사각 `ic_launcher.png`(API 25 이하) | 48dp | 1 / 2 / 2 / 3 / 4 | 16~22dp → 셀을 가능한 최대 정수로 |
| 스토어 `store/icon-512.png` | 512px | 20 | 320px(62.5%, 기존 비율과 비슷) |

- **적응형 안전 영역**: 108dp 중 기기 마스크가 원형이면 지름 66dp 원만 보장된다. 그림 영역 48dp 정사각의 모서리는 원 밖(반지름 약 33.9dp)으로 살짝 나가므로 **비트맵의 네 모서리 2×2셀은 반드시 비워 둔다.** 생성 도구 테스트가 "켜진 모든 셀의 네 꼭짓점이 중심에서 33dp 안"을 검사한다.
- 정사각 아이콘 배경: `primary` 면에 **계단 모서리**(모서리 1셀 크기만큼 비움) — 기존 22% 둥근 모서리를 대체.
- 스토어 아이콘: 꽉 찬 `primary` 정사각(Play가 모서리를 깎음, 기존과 같음).
- 가장 작은 크기(mdpi 정사각 48px, 셀 1~2px)에서 칸+체크 두 형태가 남는지 생성 결과 PNG를 눈으로 확인(완료 조건).

### 6.3 Android 13 테마(단색) 아이콘
- 현재는 `monochrome`이 전경 PNG를 재사용해 알파만 쓰인다. 새 전경은 그림자(ink)까지 불투명이라 단색으로 뭉개지므로 **그림자를 뺀 칸+체크만 담은 `ic_launcher_monochrome.png`를 따로 생성**하고 `mipmap-anydpi-v26/ic_launcher.xml`의 `monochrome`이 이것을 가리키게 한다.

### 6.4 `tool/generate_launcher_icons.dart` 변경
- 실행 명령은 그대로 `flutter test tool/generate_launcher_icons.dart`(CLAUDE.md·DEPLOY.md 절차 유지).
- 주황 그라디언트 상수와 벡터 `_drawMark`를 제거하고, 16×16 비트맵 + 셀 단위 사각형 칠하기(`isAntiAlias = false`)로 바꾼다.
- **색을 `lib/core/theme/retro_palette.dart`에서 import**한다(도구도 같은 패키지 안이라 가능). 아이콘과 앱 색의 출처가 한 곳이 된다.
- 적응형 배경색 중복 제거: 도구가 `android/app/src/main/res/values/colors.xml`에 `ic_launcher_background`(= primary)와 `launch_background`(= paper) 색 값을 함께 써 넣는다. `ic_launcher_background.xml`(그라디언트 drawable)은 삭제하고 적응형 XML의 `background`가 `@color/ic_launcher_background`를 가리키게 한다. 시작 창 `drawable(-v21)/launch_background.xml`은 `@color/launch_background`, `values-night/styles.xml`은 라이트 부모로. → DEPLOY.md 4번의 "적응형 배경색은 xml에도 같은 값이 있으니 함께 고칠 것" 괄호 문장을 "색은 앱 팔레트에서 가져오며 colors.xml도 같은 명령이 다시 쓴다"로 고친다.
- 로그인 화면 마크(5.1)도 같은 비트맵을 쓰도록 비트맵 상수는 `lib/` 쪽(`pixel_icons.dart` 옆 `app_mark.dart`)에 두고 도구가 import한다.
- 생성 결과: `mipmap-*/ic_launcher.png`, `mipmap-*/ic_launcher_foreground.png`, `mipmap-*/ic_launcher_monochrome.png`, `store/icon-512.png`, `res/values/colors.xml`. 옛 주황 파일은 전부 덮어쓰거나 삭제되어 남지 않는다.

---

## 7. 오픈소스 라이선스 (P1)
- **Flutter 기본 수단으로 된다.** `LicenseRegistry.addLicense`로 갈무리 항목을 등록하면 `showLicensePage`가 pub 패키지 라이선스와 함께 보여 준다. 새 패키지 없음.
- 등록: `main()`에서 `runApp` 전에 `LicenseRegistry.addLicense(() async* { yield LicenseEntryWithLineBreaks(['Galmuri'], await rootBundle.loadString('assets/fonts/galmuri/OFL.txt')); })`. 파일은 배포 zip의 원문 그대로(`pubspec.yaml` assets에 등록).
- 진입: 프로필 계정 섹션의 "오픈소스 라이선스"(5.4). 라이선스 화면 본문은 본문 글꼴(자동).
- OFL 예약 이름: 글꼴 파일·패밀리 이름을 바꾸지 않고, 서브셋·변환 등 수정본을 만들지 않는다(1.2).

---

## 데이터 흐름
- 테마: `main()` → `LicenseRegistry` 등록 → `runApp` → `MaterialApp(theme: AppTheme.light, themeMode: light, builder: 글자 크기 상한 1.3)` → 모든 화면이 `Theme.of`로 규칙을 받는다. 서버 호출 없음.
- VS 인트로 (참가자): "참가하기" → `BattleRepository.joinBattle`(기존 RPC `join_battle`, 변경 없음) → 성공 → provider invalidate → `shouldShowVsIntro('active', hasSeen)` → `VsIntroSeenStore.markSeen` → `showVsIntro` → 닫힘 → 성공 토스트. 실패 → 오류 토스트.
- VS 인트로 (모집 올린 사람): 내 대결 카드 탭 → `BattleDetailScreen` → `battleDetailProvider`(기존) 첫 데이터 → `shouldShowVsIntro(status, hasSeen)` → `markSeen` → `showVsIntro` → 닫힘 → 이미 그려진 상세 화면.
- 라이선스: 프로필 "오픈소스 라이선스" → `showLicensePage` → `LicenseRegistry`(갈무리 + pub 패키지).
- 판정·상태 전이·승패 표시 값은 모두 기존과 같은 서버 값을 읽는다. 상태 칩·결과 라벨 매핑 함수는 서버 값의 **모양 변환**만 하고 승패를 계산하지 않는다(CLAUDE.md "클라이언트에서 승패 계산 금지"와 충돌 없음).

## API 계약
**해당 없음(스키마·RPC 변경 없음).** 기존 `join_battle`, `battleDetailProvider` 조회를 그대로 쓴다.

- 로컬 저장소 사용: **있음.** `shared_preferences`(기기 로컬), 키 `vs_intro_seen/<userId>/<battleId>` → `bool true`. 읽기 `hasSeen(userId, battleId)`, 쓰기 `markSeen(userId, battleId)`. 삭제·만료 없음(키 하나당 수십 바이트, MVP 규모에서 정리 불필요). 로그아웃·탈퇴 시에도 지우지 않는다(다른 계정 키와 섞이지 않음).
- CLAUDE.md 도메인 규칙 확인: 대결 상태 전이·판정 위치·speed/quality 구분·`draw`와 `disputed` 비합병 모두 건드리지 않는다. 시각적으로도 `draw`(중립)와 `disputed`(dangerPale)를 다른 모양으로 둔다.

---

## 8. 테스트

**순수 함수 유닛 테스트 (`flutter test` 대상)**

| 대상 | 케이스 |
|---|---|
| `contrastRatio(Color, Color)` + 대비비 표 | 1.1 표의 모든 조합이 표의 기준 이상. 검증용으로 흑/백 = 21.0 |
| `battleStatusTagStyle(status)` | 8종 각각의 면·테두리·글자색이 표와 같음, `draw`와 `disputed`의 스타일이 다름, `draw` 스타일에 danger/dangerPale이 없음, 8종 스타일이 서로 모두 다름, 알 수 없는 status = 중립 |
| `resultTagStyle(label)` | 승/패/무/종료/미결 매핑, 무효 스타일이 면 투명·점선(가장 약함) |
| `displayInitial(name)` | "홍길동"→"홍", "  alice"→"A", ""→"?", "   "→"?", "탈퇴한 사용자"→"탈", "가"→"가", 이모지로 시작하는 이름 → 이모지 한 글자 단위, 결합 문자 |
| `shouldShowVsIntro(status, alreadySeen)` | active/judging × seen/unseen, pending·finished·disputed·draw·cancelled·voided = false |
| `PixelIcons` 비트맵 | 모든 아이콘이 12줄·각 12자·`#`/`.`만, 바깥 1셀 여백이 비어 있음 |
| 런처 마크 비트맵 | 16×16, 허용 문자만, 네 모서리 2×2 비어 있음, 켜진 셀이 적응형 안전 원(반지름 33dp) 안 |
| VS 인트로 타임라인 상수 | 구간이 겹치지 않고 합이 1500ms |
| `VsIntroSeenStore` | `SharedPreferences.setMockInitialValues`로 markSeen → hasSeen true, 다른 userId/battleId는 false |

**위젯 테스트(선택, 기존 것 유지)**
- 기존 `test/widget_test.dart` 전부 통과 유지. 대결 상세 테스트는 `VsIntroSeenStore` provider를 "봤음"으로 override해 인트로가 끼어들지 않게 한다.
- 추가 권장(짧게): VS 인트로를 띄우고 탭하면 닫힘 / `MediaQuery(disableAnimations: true)`에서 첫 프레임에 이름·VS가 보임 / 이름 60자에서 overflow 예외 없음.

---

## 9. 구현 단계 분할
각 단계 끝에 `flutter analyze` 이슈 0 + `flutter test` 통과 후 커밋. "새 화면 하나 = 커밋 하나"에 따라 3단계는 화면별로 커밋을 나눈다. 판정 로직·스키마는 어느 단계도 건드리지 않는다.

**1단계 — 팔레트·글꼴·모양·ThemeData**
- 범위: `retro_palette.dart`, `contrastRatio`, 글꼴 파일·OFL 파일 추가와 `pubspec.yaml` 등록(g값 README 확인), `RetroText`, `PixelBorder`, `AppTheme.light` 재작성(3.1 표 전체), `MaterialApp`에 `themeMode: light` + 글자 크기 상한 builder, 대비비 테스트.
- 완료 조건: 대비비 테스트 통과, 에뮬레이터에서 첫 실행부터(비행기 모드) 제목·버튼·탭이 갈무리, 할 일 내용·토스트는 기기 글꼴, 주황이 화면에 남지 않음, 기존 위젯 테스트 통과, 커밋 메시지에 글꼴 용량 기록.

**2단계 — 픽셀 아이콘과 공용 위젯**
- 범위: `PixelIcon`/`PixelIcons`(2.3 전체), 뒤로 가기·SegmentedButton 체크 테마 연결, `PixelFrame`(+tone), `PixelTag`, `BattleTypeBadge`·`BattleStatusChip` 재작성, `ResultLabel`, `PixelLoader`, `StatusMessage`, `EvidencePhotoFrame`, `InitialBadge`, `RetroButtonStyles.danger`, 매핑 함수 테스트·비트맵 테스트.
- 완료 조건: 테스트 통과, 내 대결·대결 상세에서 새 배지·칩이 보이고 기존 테스트(`find.text` 기반) 통과.

**3단계 — ai-judge가 건드리지 않는 화면 (화면마다 커밋)**
- 3-1 탭바(5.2). 3-2 로그인·AuthGate 로딩(5.1, 런처 마크 비트맵은 5단계에서 생기므로 그 전까지 `todo` 픽셀 아이콘 96dp로 두고 5단계에서 교체). 3-3 할 일 목록(5.3). 3-4 프로필 계정 섹션 + 기록 행 `ResultLabel` + 로딩 교체 + 라이선스 경로·`LicenseRegistry`(5.4, 7장).
- 완료 조건: 각 화면의 spec 수용 기준(화면별 적용·라이선스) 수동 확인, 글자 크기 1.3에서 잘림·겹침 없음, 기존 위젯 테스트 통과.

**4단계 — VS 인트로**
- 범위: `shared_preferences` 직접 의존성 명시, `displayInitial`·`shouldShowVsIntro`·타임라인 상수, `VsIntroSeenStore`+provider, 인트로 위젯·`showVsIntro`, 연결 A(참가 직후)·B(상세 첫 진입), 문자열 `vsIntroVersus`·`vsIntroSemantics`, 유닛 테스트, 기존 상세 테스트에 store override.
- 완료 조건: 두 계정으로 실제 매칭 — 참가자는 참가 직후 한 번, 생성자는 상세 첫 진입 한 번, 재진입 시 안 뜸, 탭하면 즉시 닫힘, 애니메이션 삭제 켜면 정지 화면, "탈퇴한 사용자"·60자·한 글자 이름에서 깨짐 없음, 성공 토스트가 인트로 뒤에 보임, 참가 실패 시 인트로 없이 오류 토스트, 인트로·기록 저장소 실패를 강제로 일으켜도 로그만 남고 토스트 없이 대결 화면에 진입함, **CLAUDE.md 코딩 규칙에 "장식 연출(VS 인트로)의 실패는 로그만 남긴다(토스트 없음)" 예외 한 줄 추가.**

**5단계 — 런처·스토어 아이콘과 Android 시작 창**
- 범위: 런처 마크 비트맵(`app_mark.dart`), 생성 도구 재작성(6.4), `colors.xml` 생성, 그라디언트 drawable 삭제, 적응형 XML(`background`·`monochrome`), `launch_background` 두 파일, `values-night/styles.xml`, 로그인 마크를 새 비트맵으로, DEPLOY.md 4번 문장 수정.
- 완료 조건: 생성 명령 한 번으로 모든 파일 재생성, 에뮬레이터에서 원형·사각 아이콘 모양 설정과 테마 아이콘 켬 상태 확인, 다크 모드 기기에서 시작 창이 paper, `store/icon-512.png`가 런처와 같은 그림, 옛 주황 색 값이 `android/`·`store/`·`tool/`에서 grep 되지 않음.

**6단계 — 현재 대결 화면 4개 깨짐 점검**
- 범위: 5.5 표의 허용 수정(대결 찾기 / 대결 만들기 / 내 대결 / 대결 상세 — 화면마다 커밋), 수동 점검 조건 전부.
- 완료 조건: 네 화면에서 모집 등록·취소, 참가, 증거 제출(사진·텍스트), 승인/이의제기, 포기를 1.0·1.3배·다크 모드·애니메이션 삭제에서 끝까지 수행, 배치 변경 없음(diff에 위젯 트리 순서 변경 없음), `lib/`에서 `Icons.`·`BorderRadius.circular`·`CircularProgressIndicator`·`Color(0x`(팔레트 파일 제외)가 grep 되지 않음.

---

## 결정 필요

없음

(2026-09-15 오너 답변 반영: 1. VS 인트로 표시나 "이미 봤음" 기록 읽기·쓰기가 실패하면 `debugPrint` 로그만 남기고 토스트는 띄우지 않으며, 대결 화면 진입은 어느 경우에도 막지 않는다 — 4.2·4.5에 반영. CLAUDE.md 코딩 규칙 예외 한 줄 추가는 9장 4단계 완료 조건에 포함.)
