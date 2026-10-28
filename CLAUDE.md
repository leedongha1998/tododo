# CLAUDE.md — 투두두두 (TODODUDU)

## 프로젝트 요약
친구와 같은 투두를 걸고 대결하는 경쟁형 투두리스트 모바일 앱.
1인 개발, 2주 안에 MVP를 완성해 Google Play 스토어에 배포하는 것이 1차 목표.
포트폴리오는 부산물이지 목표가 아니다. 앱이 동작하고 배포되는 것이 항상 우선이다.

## 현재 단계
- MVP 개발 중 (배포 전). 2026-09-14에 판정 주체를 참가자(상호 승인)에서 AI 심판으로 바꿨고,
  이 정체성을 확정한 뒤 배포한다. 아래 "도메인 규칙"은 `docs/specs/ai-judge/spec.md`(오너 승인)
  기준으로 다시 쓴 것이다. 확정/미결 사항은 `docs/specs/ai-judge/decisions.md`에 있다.
- 범위: 개인 투두 CRUD, 대결 생성/모집(첫 참가자와 자동 매칭), 속도전, 품질전,
  AI 판정 기준 생성·판정(Gemini), AI 데이터 제공 동의, 무료 사용자 하루 1대결 제한, 결과/점수/전적
- 배포 전 별도 feature로 진행: 푸시 알림(`push-notification`), 카카오 로그인(`kakao-login`),
  친구(`friends`)
- 범위 밖: AI 판정 불복 재심(유료, 배포 후), 유료 결제, 그룹 대결, 랭킹,
  대결 상대·모집 생성자가 아닌 임의 사용자의 전적 조회
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
deno test supabase/functions/_shared/   # Edge Function 순수 함수 테스트
supabase start            # 로컬 DB
supabase db reset         # 마이그레이션 재적용
supabase functions deploy <name>   # Edge Function 배포 (계정 소유자가 실행)
supabase secrets set KEY=VALUE     # Edge Function 시크릿 (계정 소유자가 실행, 값은 코드·로그에 남기지 않는다)
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
- Deno 2.9.6은 `C:\workspaces\devtools\deno\deno.exe`에 설치됨(공식 GitHub 릴리스 zip), PATH 등록됨.
  Edge Function의 순수 함수 테스트(`deno test`)에 쓴다. 한글 경로를 피해 devtools 아래에 둔다.
- Supabase CLI(v2.115.0)는 `C:\workspaces\devtools\supabase-cli\supabase.exe`에 설치됨, PATH 등록됨.
  `supabase login`은 브라우저 인증이 필요해 계정 소유자(사용자)가 직접 실행해야 함.
- `supabase storage cp`로 파일을 올릴 때 **소스를 절대 경로로 주면 `Unsupported operation`으로 거부된다.**
  Git Bash의 `/c/...`든 Windows의 `C:\...`든 마찬가지다(CLI가 양쪽을 로컬-로컬 복사로 본다).
  소스 폴더로 `cd`한 뒤 **상대 경로**(`./1.jpg`)로 주면 올라간다 — 필요하면 `--workdir`로 프로젝트를
  따로 가리킨다. 2026-10-28에 v2.115.0·v2.122.0 둘 다에서 확인했다. `storage ls`는 절대 경로와
  무관하게 잘 된다.
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
- 대결 유형은 두 가지: `speed`(속도전), `quality`(품질전). **둘 다 승자가 있다.**
- 판정은 참가자가 아니라 **AI 심판**이 한다. 사용자끼리 서로의 증거를 승인(`approve`)/이의제기(`dispute`)하는 절차는 없다.
- 증거는 **앱 카메라로 찍은 사진만**이다. 갤러리 업로드도, 텍스트만의 증거도, 사진에 붙이는 설명 텍스트도 없다. 촬영 시각을 사진과 함께 받아 서버 수신 시각과 대조해 매칭 전에 찍은 사진과 10분 이상 차이 나는 사진은 거부한다(거부된 사진은 제출로 치지 않는다). 승부 기준 시각은 언제나 서버 시각이다 — 클라이언트 시간을 신뢰하지 않는다.
- 판정 기준은 대결을 만들 때 AI가 만들고 생성자가 확인·수정해 확정한다. 사진으로 증명할 수 없는 미션(독서·명상 등)은 생성이 **차단**된다. 품질전은 최소 기준과 별도로 **우열 기준**도 만든다. 확정된 기준은 참가 전에 공개되고, 참가자는 자기가 확인한 기준 버전(`criteria_version`)으로만 참가한다.
- 속도전 판정: 제출 즉시 AI가 최소 기준 통과 여부를 본다. **통과한 제출** 중 서버 제출 시각이 이른 쪽이 이긴다. 불합격이면 마감 전까지 다시 낼 수 있지만 AI 판정은 참가자당 대결마다 **5회**까지이고, 통과하면 그 참가자의 제출은 잠긴다. AI 호출 실패는 그 제출만 무효이며 5회에 세지 않는다. 진 쪽도 마감까지 통과하면 "완료한 패배"로 기록된다.
- 품질전 판정: 제출은 **한 번뿐**이고 재제출이 없다. 두 사진이 모두 올라오면 AI가 (1) 각 사진의 최소 기준 통과 여부를 보고, (2) 둘 다 통과했으면 참가 전에 공개된 우열 기준으로 **반드시 한쪽을 승자로** 고른다(동점 없음). 한쪽만 미달이면 미달 쪽 패배, 둘 다 미달이면 `draw`. 마감까지 한쪽만 냈으면 AI 판정 없이 낸 쪽 승리, 아무도 안 냈으면 `draw`.
- AI 판정은 최종이다. 사용자가 항소·이의제기할 수단은 없다. `disputed`(미결)는 배포 후 유료 재심을 위해 **개념만 남겨 두고 MVP에서는 어떤 경로로도 도달하지 않는다.**
- 상대의 증거 사진과 판정 사유는 대결이 **종결된 뒤에만** 볼 수 있다(화면이 가리는 게 아니라 서버가 내주지 않는다). 진행 중에는 "상대가 제출했다"는 사실과, 속도전이면 상대 제출의 합격/불합격 결과만 보인다.
- 대결 상태 전이: `pending`(모집 중, 상대 없음) → `active`(참가자가 매칭됨) → (품질전만) `judging`(두 사진이 모두 올라와 **AI 판정 대기**) → `finished` | `draw` | `voided` | `cancelled`. 속도전은 `judging`을 거치지 않는다.
- 대결에는 마감이 있다. 기간(`battles.duration_hours`, 1일/3일/7일)은 만든 사람이 정하고, 마감(`deadline_at`)은 매칭되는 순간부터 흐른다(모집 중에는 null). 마감이 지나면 `settle_expired_battles()`가 정산한다 — pg_cron이 5분마다 돌린다. **마감은 판정을 대신하지 않는다**: 서버 제출 시각이 마감 전이면 판정이 마감 뒤에 끝나도 인정하고, 진행 중인 판정(품질전 자동 재시도 포함)이 있으면 그 판정이 끝난 뒤 확정한다. 반대로 더 이상 결과가 바뀔 수 없으면 마감을 기다리지 않고 즉시 종결한다.
- `draw`(무승부)는 "가를 근거가 없다", `voided`(무효)는 "AI 판정이 끝내 실패했다", `disputed`(미결)는 "이의제기로 끝났다"(MVP 미도달)이다. 셋을 합치지 말 것. `draw`는 전적에서 유형과 상관없이 `무`로 표시하고, `voided`는 점수·전적에 반영하지 않으며 내 기록 목록에만 "무효"로 보인다.
- 점수: 승 +3, 속도전 완료한 패배 -1, 완료 못 한 패배·품질전 패배·포기 -3, `draw` 양쪽 -1, `voided`·`cancelled` 0. 시작 점수 0점, **하한 0점**. 점수와 승/패/무는 프로필에 나란히 보여 주고 사용자 간 순위표(랭킹)는 만들지 않는다. "완료한 패배"는 전적에서 그냥 `패`이고 차이는 점수에만 있다.
- 무료 사용자는 하루(KST 자정 기준) **매칭된 대결 1개**, 기준 생성 AI 호출 10회, 모집 중 대결 1개까지다. 한도 판단은 서버가 한다(클라이언트 시계로 우회할 수 없다).
- AI 데이터 제공 동의(제3자 제공·국외 이전)를 받기 전에는 기준 생성·대결 생성·참가를 막는다. 개인 투두 기능은 그대로 쓸 수 있다. 동의를 철회하면 진행 중 대결은 모두 포기 처리되고 모집 중인 대결은 취소된다.
- 대결 생성은 특정 상대 지목 초대가 아니라 주제 모집 방식이다. 유형/제목만 정해 올리면 누구든 먼저 참가하는 사람과 자동 매칭된다(opponent_id는 매칭 전까지 null).
- 매칭된 대결에서 빠져나가는 길은 포기(기권, `forfeit_battle`)뿐이다. **유형과 상관없이** 포기한 쪽이 지고 상대가 `winner_id`로 기록되며 `finished`로 끝난다. 누가 포기했는지는 `battles.forfeited_by`에 남는다. 승자 없이 취소로 끝내지 않는 이유는 "질 것 같으면 포기"가 패배 회피 수단이 되기 때문이다. 모집 취소(`cancel_battle`)는 여전히 상대가 없는 `pending`에서만 가능하다.
- 대결은 2인만. 3인 이상 구조를 미리 만들지 말 것.
- 판정 로직은 클라이언트가 아니라 DB(RLS/트리거/함수) 또는 Edge Function에서 처리한다. 화면은 서버가 기록한 `status`/`winner_id`/`outcome`/`score_delta_applied`를 **표시만** 한다.
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
  - 예외: Edge Function·cron 전용 함수는 서비스 롤·cron에 `auth.uid()`가 없어 그 가드가 항상 실패하므로 두지 않는다. 대신 `revoke execute ... from public, anon, authenticated` + `grant execute ... to service_role`로 막고, 사용자 id는 Edge Function이 JWT로 검증해 인자로 넘기며, 함수 주석에 이 예외의 이유를 적는다(`settle_expired_battles` 선례)
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
- **사용자가 `/feature`를 치지 않아도 Claude가 먼저 이 순서를 돌린다**(2026-10-28 결정). 새 기능·새 화면·스키마 변경이 생기는 작업이면 메인 세션에서 바로 구현하지 말고 pm(`spec.md`) → designer(`design.md`) → developer(`plan.md`·구현) → reviewer 순으로 서브에이전트에 위임하고, 단계마다 산출물을 보여 주고 승인 지점에서 멈춘다.
- 예외 — 메인 세션에서 그대로 처리한다: 버그 수정, 문구·UI 소소한 변경, 질문·설명, 커밋·푸시·원격 적용 같은 운영 작업, 이미 `docs/specs/<name>/`에 기획·설계가 끝난 기능의 이어 하기(그때는 developer부터).
- **서브에이전트끼리 직접 대화하지는 못한다.** 각자 새 맥락으로 시작하고 결과는 메인 세션에만 돌아온다. 단계 간 공유는 전부 `docs/specs/<name>/` 파일로만 이뤄지므로, 각 문서는 다음 단계가 그것만 읽고 일할 수 있을 만큼 적는다. 사용자 판단이 필요한 것은 문서의 "## 결정 필요"에 남기고 메인 세션이 대신 묻는다.

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