# CLAUDE.md — 투두두두 (TODODUDU)

## 프로젝트 요약
친구와 같은 투두를 걸고 대결하는 경쟁형 투두리스트 모바일 앱.
1인 개발, 2주 안에 MVP를 완성해 Google Play 스토어에 배포하는 것이 1차 목표.
포트폴리오는 부산물이지 목표가 아니다. 앱이 동작하고 배포되는 것이 항상 우선이다.

## 현재 단계
- MVP 개발 중 (배포 전). 2026-09-14에 판정 주체를 참가자(상호 승인)에서 AI 심판으로 바꾸기로 결정했고,
  이 정체성을 확정한 뒤 배포한다. 확정/미결 사항은 `docs/specs/ai-judge/decisions.md`에 있다.
  아래 "도메인 규칙"의 상호 승인 관련 조항은 ai-judge spec이 승인되면 그에 맞춰 다시 쓴다.
- 범위: 개인 투두 CRUD, 대결 생성/모집(첫 참가자와 자동 매칭), 속도전, 품질전, AI 판정, 푸시 알림(FCM),
  무료 사용자 하루 1대결 제한, 결과/전적
- 범위 밖: AI 판정 불복(유료, 배포 후), 유료 결제, 그룹 대결, 랭킹
- 범위 밖 기능을 구현하거나 그를 위한 추상화를 미리 만들지 말 것

## 기술 스택
<!-- 스택 확정 시 이 섹션을 갱신할 것 -->
- 클라이언트: Flutter (Android 우선, iOS는 고려하지 않음)
- 백엔드/DB/인증: Supabase (Postgres, Auth, Storage, Edge Functions)
- 상태 관리: Riverpod
- 언어: Dart, SQL, Edge Function은 TypeScript
- 소셜 로그인: Google + 카카오 (2026-09-14 결정. 계정 연결 없음, 카카오 친구 목록 API는 MVP에서 안 씀.
  `docs/specs/ai-judge/decisions.md` G-2 참고)

## 개발 명령어
```
flutter pub get
flutter run
flutter analyze
flutter test
flutter build appbundle --release --dart-define-from-file=env.json  # env.json 없으면 죽은 앱이 나온다
flutter test tool/generate_launcher_icons.dart  # 런처/스토어 아이콘 다시 생성
supabase start            # 로컬 DB
supabase db reset         # 마이그레이션 재적용
```
새 명령어가 생기면 여기에 추가할 것.

## 개발 환경 (Windows)
- Windows 계정명이 한글(`이동하`)이면 `C:\Users\이동하\...` 경로에서 Gradle/Dart 툴체인이 깨진다
  (경로의 한글이 mojibake로 손상되어 `dev.flutter.flutter-plugin-loader`를 못 찾거나 pub 패키지
  타입 인식이 실패함). Flutter SDK, JDK, Android SDK, `PUB_CACHE`는 전부 한글이 섞이지 않은
  경로에 설치할 것 — 이 머신에서는 `C:\workspaces\devtools\`(flutter/, jdk-17.0.20+8/,
  Android/sdk/, pub-cache/) 사용 중.
- 관련 환경변수(User 레벨로 영구 등록됨): `JAVA_HOME`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
  `PUB_CACHE`, PATH에 `flutter\bin`/`Android\sdk\platform-tools`/
  `Android\sdk\cmdline-tools\latest\bin`/`jdk-17.0.20+8\bin` 추가됨.
  `flutter config --android-sdk` / `--jdk-dir`도 같은 경로로 설정됨.
- 이상하게 실패하는 빌드/컴파일 에러(원인 불명의 "isn't a type", 경로를 못 찾음 등)를 만나면
  먼저 관련 경로에 비-ASCII 문자가 섞여 있는지부터 의심할 것.
- 로컬에 Docker가 없어 `supabase start`(로컬 DB)는 아직 실행 불가. 클라우드 프로젝트를
  만들고 `supabase link`로 연결하는 방식을 쓰거나, Docker Desktop을 설치해야 함(설치는
  Windows 가상화 기능 활성화가 필요해 사용자가 직접 진행).
- Supabase CLI(v2.115.0)는 `C:\workspaces\devtools\supabase-cli\supabase.exe`에 설치됨, PATH 등록됨.
  `supabase login`은 브라우저 인증이 필요해 계정 소유자(사용자)가 직접 실행해야 함.
- Android 에뮬레이터(AVD) `todododo_avd`(Pixel 6, API 36, google_apis x86_64) 생성됨.
  AVD 데이터도 한글 경로를 피해 `ANDROID_SDK_HOME`/`ANDROID_AVD_HOME`을
  `C:\workspaces\devtools\android-home`(User 환경변수, 영구 등록)로 지정함 — 기본값인
  `%USERPROFILE%\.android`를 쓰면 안 됨. 실행: `emulator -avd todododo_avd`
  (헤드리스로 확인만 하려면 `-no-window -no-audio -gpu swiftshader_indirect` 추가).
  하드웨어 가속용 하이퍼바이저는 이 머신에 이미 있음(Hyper-V 감지됨).

## 디렉토리 구조
```
lib/
  core/          # 공통 유틸, 테마, 라우팅, Supabase 클라이언트
  features/
    auth/
    todo/        # 개인 투두
    battle/      # 대결
    profile/     # 전적/프로필
  main.dart
supabase/
  migrations/    # SQL 마이그레이션 (스키마 변경은 반드시 여기로)
  functions/     # Edge Functions
test/
```
각 feature 폴더는 `data/`(모델, 레포지토리) `domain/`(비즈니스 로직) `presentation/`(화면, 위젯, 프로바이더)로 나눈다.

## 도메인 규칙 (반드시 지킬 것)
- 대결 유형은 두 가지: `speed`(속도전), `quality`(품질전)
- 속도전 판정: 완료 주장 시 증거(사진 또는 텍스트 중 최소 하나) 제출이 필수이고, 양쪽 참가자가 각자 제출한 뒤 서로의 증거를 `approve`/`dispute`해야 결과가 확정된다. 이의제기는 그 참가자의 완료를 무효화한다 — 양쪽 다 승인이면 `evidence_submitted_at`이 이른 쪽 승리, 한쪽만 승인이면 제출이 늦었더라도 승인받은 쪽 승리, 양쪽 다 이의제기면 유효한 완료가 없어 승자 없이 `disputed`. 클라이언트 시간을 신뢰하지 않는다.
- 품질전 판정: 완료 시 증거(사진 필수, 텍스트만으로는 불가) 제출 → 상대가 `approve` / `dispute` 선택. 양쪽 다 approve면 `finished`, 하나라도 dispute면 `disputed`.
- 증거 제출은 유형에 상관없이 양쪽 참가자가 각자 한다(한쪽만 제출하는 방식 아님). 서로 상대방의 증거를 approve/dispute한다.
- 증거 재제출은 판정 전이든 이의제기당한 뒤든 항상 허용하되, `evidence_submitted_at`이 갱신되어 속도전 승부 기준 시각이 밀린다.
- 품질전은 속도 경쟁이 아니므로 승자(`winner_id`)를 두지 않는다. 양쪽 증거가 모두 approve되면 `finished`.
- `disputed`로 끝난 대결은 MVP에서 "미결"(승자 없음)로 남긴다. AI 심판은 나중에 붙인다. 단, 속도전에서 한쪽만 이의제기당한 경우는 `disputed`가 아니라 상대 승리로 종결된다.
- 대결 상태 전이: `pending`(모집 중, 상대 없음) → `active`(참가자가 매칭됨) → `judging`(증거 제출 후 상호 판정 대기 — 속도전/품질전 모두 거침) → `finished` | `disputed` | `draw` | `cancelled`
- 대결에는 마감이 있다. 기간(`battles.duration_hours`, 1일/3일/7일)은 만든 사람이 정하고, 마감(`deadline_at`)은 매칭되는 순간부터 흐른다(모집 중에는 null). 마감이 지나면 `settle_expired_battles()`가 그 시점 상태로 종결시킨다 — pg_cron이 5분마다 돌린다. **마감은 판정을 대신한다: 증거를 냈고 이의제기를 받지 않았으면 미판정이어도 유효한 완료로 본다.** 그러지 않으면 잠수한 상대가 내 승리를 막을 수 있다. 속도전은 유효한 완료가 양쪽이면 이른 쪽, 한쪽이면 그쪽이 이기고 없으면 `draw`. 품질전은 양쪽 다 유효하면 `finished`, 아니면 `draw`.
- `draw`(무승부)는 "시간이 다 됐다"이고 `disputed`(미결)는 "이의제기로 끝났다"이다. 둘을 합치지 말 것. 전적에서 `draw`는 유형과 상관없이 `무`로 표시한다.
- 대결 생성은 특정 상대 지목 초대가 아니라 주제 모집 방식이다. 유형/제목만 정해 올리면 누구든 먼저 참가하는 사람과 자동 매칭된다(opponent_id는 매칭 전까지 null).
- 매칭된 대결에서 빠져나가는 길은 포기(기권, `forfeit_battle`)뿐이다. 포기한 쪽이 진다 — 속도전은 상대가 `winner_id`로 기록되며 `finished`, 품질전은 승자를 두지 않으므로 `disputed`. 누가 포기했는지는 `battles.forfeited_by`에 남는다. 승자 없이 취소로 끝내지 않는 이유는 "질 것 같으면 포기"가 패배 회피 수단이 되기 때문이다. 모집 취소(`cancel_battle`)는 여전히 상대가 없는 `pending`에서만 가능하다.
- 대결은 2인만. 3인 이상 구조를 미리 만들지 말 것.
- 판정 로직은 클라이언트가 아니라 DB(RLS/트리거) 또는 Edge Function에서 처리한다.
- 계정 삭제(탈퇴)는 `auth.users` 행을 실제로 지우되 `profiles` 행은 "탈퇴한 사용자" 묘비로 남긴다(`profiles.deleted_at`). 상대방의 대결 전적이 통째로 사라지지 않게 하기 위함이다. 그래서 사용자 FK는 `auth.users`가 아니라 `public.profiles`를 가리킨다 — 새 테이블도 반드시 profiles를 참조할 것. 탈퇴 시 끝나지 않은 대결(`pending`/`active`/`judging`)은 승자 없이 `cancelled`가 된다.

## 코딩 규칙
- 함수/변수는 영어, 사용자에게 보이는 문자열은 한국어
- 하드코딩된 문자열은 `lib/core/strings.dart`에 모은다
- 에러는 삼키지 않는다. 최소한 로그를 남기고 사용자에게 토스트로 알린다
  - 예외: 장식 연출(VS 인트로)의 표시 실패, 인트로에 쓸 내 이름 조회 실패(이때는 "나"로 대신 표시), 그 "봤음" 기록 읽기·쓰기 실패는 `debugPrint` 로그만 남기고 토스트를 띄우지 않는다. 연출은 관문이 아니므로 대결 진입은 어느 경우에도 막지 않는다
- 새 화면 하나 = 새 커밋 하나. 큰 덩어리로 커밋하지 않는다
- 새 패키지 추가 전에 이미 있는 패키지로 가능한지 먼저 확인하고, 추가하면 이유를 커밋 메시지에 적는다
- 스키마 변경은 마이그레이션 파일로만. Supabase 대시보드에서 직접 수정 금지
- RLS 정책은 테이블 만들 때 같이 작성한다. 나중에 붙이지 않는다
- 새 RPC 함수를 만들면 `grant execute ... to authenticated`만으로는 부족하다. Postgres는 PUBLIC에,
  Supabase는 anon에 EXECUTE를 기본으로 주므로 `revoke execute ... from public, anon`을 같이 쓴다
- SECURITY DEFINER 함수는 첫 줄에 `if auth.uid() is null then raise exception '로그인이 필요합니다.'` 가드를 둔다
- 참가자 검사에 `auth.uid() not in (a, b)`를 쓰지 말 것. 비로그인이면 NULL이 되어 예외 없이 통과한다.
  `auth.uid() is distinct from a and auth.uid() is distinct from b`를 쓴다

## 테스트
- 도메인 로직(판정, 상태 전이)은 반드시 유닛 테스트
- 화면은 위젯 테스트 선택 사항. MVP 단계에서 강제하지 않는다
- 기능 구현 후 `flutter analyze`와 `flutter test`가 통과해야 완료로 본다

## 작업 방식
- 작업 시작 전에 이 파일과 관련 feature 폴더를 먼저 읽는다
- 요구사항이 모호하면 추측해서 구현하지 말고 물어본다. 단, 사소한 UI 결정은 알아서 하고 결과만 보고한다
- 기능 하나 완료 시: 무엇을 만들었는지, 테스트 결과, 남은 문제를 3줄 이내로 보고
- 범위 밖 기능이 필요해 보이면 구현하지 말고 `TODO_BACKLOG.md`에 한 줄 추가
- 기존 코드 스타일을 따른다. 리팩토링은 요청받았을 때만

## 기능 개발 파이프라인
- 새 기능은 `/feature <name>`으로 시작한다 — pm→designer→developer→reviewer 순으로 진행되며 승인 지점마다 멈춘다.
- 기획만 따로 논의하고 싶으면 `claude --agent pm`으로 별도 세션을 연다.
- 각 단계 산출물은 `docs/specs/<name>/`(spec.md, design.md, plan.md)에 쌓인다.

## 하지 말 것
- iOS 대응 코드
- 다국어(i18n) 세팅
- 범위 밖 기능을 위한 "미래 대비" 추상화
- 클라이언트에서 승패 계산
- 테스트 없이 판정 로직 수정
- 시크릿/키를 코드나 커밋에 포함 (`.env`는 gitignore)

## 배포
- 타깃: Google Play 내부 테스트 트랙 → 프로덕션
- 빌드: `flutter build appbundle --release --dart-define-from-file=env.json`
- 서명 키, 스토어 자산, 개인정보처리방침은 별도 체크리스트(`DEPLOY.md`)로 관리