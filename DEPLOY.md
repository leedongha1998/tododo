# DEPLOY.md — 배포 체크리스트

Google Play 내부 테스트 → 프로덕션까지의 절차. 한 번 하고 끝나는 항목(서명 키, 개인정보처리방침)과
릴리스마다 반복하는 항목(버전 올리기, 빌드, 업로드)을 나눠서 적는다.

현재 상태 기준: `applicationId = com.todododo.todododo`, `version: 1.0.0+1`, 앱 이름 `투두두두`.

---

## 0. 지금 막혀 있는 것 (배포 전 반드시 해결)

- [ ] **업로드 키가 아직 없다** — Gradle 배선은 끝났다(키가 있으면 release 서명을 쓰고, 없으면
      릴리스 빌드가 즉시 실패한다 — 디버그 키로 서명된 AAB가 나갈 일은 이제 없다).
      남은 것은 키스토어 생성과 `android/key.properties` 작성뿐이고, **비밀번호가 들어가므로
      직접 하셔야 한다** → 1번
- [x] ~~런처 아이콘이 Flutter 기본 아이콘이다~~ — 자체 아이콘으로 교체했다(적응형 아이콘 포함).
      그림은 `tool/generate_launcher_icons.dart`에 코드로 들어 있고, 다시 뽑으려면
      `flutter test tool/generate_launcher_icons.dart` → 4번
- [x] ~~앱 내 계정 삭제 수단이 없다~~ — 프로필 화면에 계정 삭제(탈퇴)를 추가했다.
      `delete_account()` RPC가 투두·증거·표시 이름을 지우고 auth 계정을 삭제하며,
      대결 기록은 "탈퇴한 사용자" 묘비로 남는다. 원격에 push하고 스모크 테스트
      (`supabase db query --linked -f supabase/tests/delete_account_smoke.sql`)로
      실제 탈퇴까지 확인 완료. 남은 확인은 실기기에서의 앱 경로(증거 사진 삭제 포함) → 7번
- [ ] **개인정보처리방침·계정 삭제 요청 페이지가 아직 게시되지 않았다** — 문서 자체는 다 썼다.
      `C:\workspaces\todododo-legal`(별도 저장소, 커밋까지 완료)를 GitHub에 공개 저장소로
      올리고 Pages를 켜면 끝난다. 절차는 그 저장소의 `README.md` → 5번

---

## 1. 서명 키 (최초 1회)

업로드 키를 만든다. **이 키를 잃어버리면 같은 앱을 업데이트할 수 없다** — 별도 백업 필수.

```bash
keytool -genkey -v -keystore C:\workspaces\todododo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

키스토어는 **저장소 밖**에 둔다(위 경로처럼). `android/app/*.jks`는 gitignore돼 있지만 애초에 넣지 않는 게 낫다.

`android/key.properties` 생성 (gitignore 처리됨):

```properties
storePassword=<키스토어 비밀번호>
keyPassword=<키 비밀번호>
keyAlias=upload
storeFile=C:\\workspaces\\todododo-upload.jks
```

`android/app/build.gradle.kts`는 **이미 이 파일을 읽도록 배선돼 있다.** 키가 있으면 release 서명에
쓰고, 없으면 릴리스 빌드를 이런 메시지와 함께 즉시 실패시킨다(디버그 키로 서명된 AAB 방지):

> 릴리스 빌드에 필요한 android/key.properties가 없습니다. 업로드 키를 만들고 key.properties를 작성하세요 (DEPLOY.md 1번).

- [ ] 키스토어 생성 및 저장소 밖에 보관 + 백업 (비밀번호는 비밀번호 관리자에)
- [ ] `key.properties` 작성 (커밋 안 됨 확인: `git status`에 안 뜨는지)
- [ ] `flutter build appbundle --release --dart-define-from-file=env.json`이 성공하는지 확인
- [ ] 서명 확인: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`로
      나온 지문이 디버그 키가 아니라 방금 만든 업로드 키인지

> **Play 앱 서명 참고:** Play가 업로드 키와 별개의 앱 서명 키로 재서명한다. 이 앱의 구글 로그인은
> `signInWithOAuth`(브라우저 리디렉션 방식)라 앱 서명 SHA-1을 어디에도 등록하지 않는다. 즉 재서명돼도
> 로그인은 깨지지 않는다. (네이티브 `google_sign_in`으로 바꾸면 그때부터는 SHA-1 등록이 필요해진다.)

---

## 2. 빌드 설정 (릴리스마다)

**`--dart-define` 없이 빌드하면 "Supabase 설정이 필요합니다" 화면만 뜨는 죽은 앱이 나온다.**
매번 손으로 치지 말고 파일로 관리한다.

`env.json` (저장소 루트, **gitignore에 추가할 것**):

```json
{
  "SUPABASE_URL": "https://xskasyzbsnctycaxpbsr.supabase.co",
  "SUPABASE_ANON_KEY": "<Supabase 대시보드 → Project Settings → API Keys의 publishable 키>"
}
```

빌드:

```bash
flutter build appbundle --release --dart-define-from-file=env.json
```

산출물: `build/app/outputs/bundle/release/app-release.aab`

- [ ] `.gitignore`에 `env.json` 추가
- [ ] `env.json` 작성
- [ ] 빌드 후 **설치해서 로그인까지 되는지 확인** (설정 누락은 실행해봐야만 드러난다)

---

## 3. 버전 (릴리스마다)

`pubspec.yaml`의 `version: <이름>+<코드>`. Play는 같은 `versionCode`를 두 번 받지 않는다.

- [ ] `version:` 올리기 (예: `1.0.0+1` → `1.0.1+2`)

---

## 4. 스토어 자산

- [x] ~~**앱 아이콘** 512×512 PNG~~ — `store/icon-512.png`. Play Console에 이 파일을 올린다.
      런처 아이콘(mipmap 전 해상도 + API 26+ 적응형 + 안드로이드 13 테마 아이콘)도 같이 만들어져 있다.
      그림은 `tool/generate_launcher_icons.dart`에 코드로 있고, 색이나 모양을 바꾸면
      `flutter test tool/generate_launcher_icons.dart`로 전부 다시 뽑는다
      (적응형 배경색은 `res/drawable/ic_launcher_background.xml`에도 같은 값이 있으니 함께 고칠 것)
- [ ] **그래픽 이미지(feature graphic)** 1024×500 PNG
- [ ] **스크린샷** 최소 2장 (폰 기준) — 홈(내 대결 + 투두), 대결 진행(증거 제출), 결과 화면이 앱을 잘 보여준다
- [ ] **짧은 설명** 80자 이내
- [ ] **자세한 설명** 4000자 이내
- [ ] 앱 이름 (`투두두두`), 카테고리, 콘텐츠 등급 설문

---

## 5. 정책 문서 (최초 1회)

이 앱이 수집하는 것: **Google 계정 이메일·이름**(프로필 표시용), **사용자가 올린 증거 사진**,
**투두/대결 내용**. 전부 Supabase(외부 서버)에 저장되고 HTTPS로 전송된다.

문서는 **별도 공개 저장소** `C:\workspaces\todododo-legal`에 작성해뒀다(앱 소스는 비공개로 두고
문서만 공개하기 위함). 게시 절차는 그 저장소의 `README.md`에 있다.

- [x] ~~개인정보처리방침 작성~~ — `privacy.html`. 수집 항목, 이용 목적, 보유 기간(탈퇴 시 처리 표),
      위탁(Supabase/Google), 이용자 권리, 안전성 확보 조치, 보호책임자까지 포함
- [x] ~~앱 내 계정 삭제 경로~~ — 프로필 화면 → 계정 삭제 (0번 참고)
- [x] ~~웹 계정 삭제 요청 안내 작성~~ — `account-deletion.html`. 앱 내 경로 + 이메일 요청 양식,
      삭제/보존 데이터 표를 `delete_account()` RPC의 실제 동작대로 적었다
- [ ] **GitHub에 공개 저장소 `todododo-legal` 생성 후 push, Pages 켜기** (사용자 직접 — 계정 작업)
- [ ] **Play Console에 URL 2개 등록**
      — 앱 콘텐츠 → 개인정보처리방침: `https://<사용자명>.github.io/todododo-legal/privacy.html`
      — 데이터 보안 → 계정 삭제: `https://<사용자명>.github.io/todododo-legal/account-deletion.html`
- [ ] **Play Console → 데이터 보안(Data safety)** 양식 작성 — 아래 내용과 어긋나면 심사에서 걸린다.
      수집: 이메일 주소, 이름, 사용자 생성 콘텐츠(투두·대결 제목·증거 텍스트), 사진.
      목적: 앱 기능 제공. 전송 중 암호화: 예. 삭제 요청 가능: 예.
      광고·분석 SDK 없음, 제3자 판매 없음
- [ ] 정책 문서 내용이 앱 동작과 계속 일치하는지 — 기능을 바꾸면 `privacy.html`의 시행일과 함께 갱신

---

## 6. Play Console

- [ ] 개발자 계정 등록 (최초 1회, 등록비 $25)
- [ ] 앱 만들기 → 패키지명 `com.todododo.todododo` (**한 번 정하면 변경 불가**)
- [ ] 내부 테스트 트랙에 AAB 업로드, 테스터 계정 등록
- [ ] 내부 테스트로 실기기 설치 → 로그인 → 대결 한 판 전 과정 확인
- [ ] 프로덕션 심사 제출

---

## 7. 배포 전 최종 확인

```bash
flutter analyze
flutter test
supabase migration list          # local/remote 마이그레이션이 전부 일치하는지
```

- [ ] `flutter analyze` 이슈 0, `flutter test` 전부 통과
- [ ] 마이그레이션이 원격에 전부 적용됨 (local/remote 목록 일치)
- [ ] Supabase 대시보드 → Authentication → URL Configuration → **Redirect URLs**에
      `com.todododo.todododo://login-callback/`이 들어 있는지
      (빠지면 로그인 후 `localhost:3000`으로 튕긴다 — 실제로 겪은 문제)
- [ ] 릴리스 빌드를 **실기기**에 설치해 로그인 → 대결 생성 → 증거 사진 촬영 → 판정까지 확인
      (에뮬레이터 기본 카메라는 셔터가 동작하지 않아 촬영 경로 검증이 안 된다)
- [ ] 런처에 아이콘이 제대로 보이는지 (홈 화면·앱 서랍·최근 앱). 기기 모양 설정을 원형으로 바꿔도
      체크 표시가 잘리지 않는지 — 적응형 아이콘은 가장자리가 기기마다 다르게 깎인다
- [ ] 실기기에서 **탈퇴 한 번** — 증거 사진이 있는 계정으로 프로필 → 계정 삭제까지 해보고,
      Storage 대시보드의 `battle_evidence` 버킷에서 그 계정 폴더가 비었는지 확인
      (RPC 자체는 스모크 테스트로 검증됐지만, 사진 삭제는 앱이 Storage API로 하는 부분이라
      실제로 돌려봐야 확인된다)
- [ ] `targetSdk`가 Play의 현재 최소 요구치를 만족하는지 확인
      (Flutter가 정하는 값이라 SDK 버전에 따라 달라진다)

---

## 8. 배포 후

- [ ] Play Console 크래시/ANR 지표 확인
- [ ] Supabase 대시보드에서 에러 로그·사용량 확인 (무료 플랜 한도)
