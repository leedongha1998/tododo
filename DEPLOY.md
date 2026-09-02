# DEPLOY.md — 배포 체크리스트

Google Play 내부 테스트 → 프로덕션까지의 절차. 한 번 하고 끝나는 항목(서명 키, 개인정보처리방침)과
릴리스마다 반복하는 항목(버전 올리기, 빌드, 업로드)을 나눠서 적는다.

현재 상태 기준: `applicationId = com.todododo.todododo`, `version: 1.0.0+1`, 앱 이름 `투두두두`.

---

## 0. 지금 막혀 있는 것 (배포 전 반드시 해결)

- [ ] **릴리스 빌드가 디버그 키로 서명된다** — `android/app/build.gradle.kts`의 `buildTypes.release`가
      `signingConfigs.getByName("debug")`를 그대로 쓴다. 디버그 키로 서명된 AAB는 Play가 거부한다. → 1번
- [ ] **런처 아이콘이 Flutter 기본 아이콘이다** (`android/app/src/main/res/mipmap-*/ic_launcher.png`) → 4번
- [x] ~~앱 내 계정 삭제 수단이 없다~~ — 프로필 화면에 계정 삭제(탈퇴)를 추가했다.
      `delete_account()` RPC가 투두·증거 사진·표시 이름을 지우고 auth 계정을 삭제하며,
      대결 기록은 "탈퇴한 사용자" 묘비로 남는다. **원격에 `supabase db push` 후 실제 탈퇴를
      한 번 돌려서 확인할 것** (`delete from auth.users`가 권한 문제로 막히지 않는지).
- [ ] **웹 계정 삭제 요청 URL이 없다** — Play 정책상 앱 밖(웹)에서도 접근 가능한 삭제 요청
      경로가 필요하다. 개인정보처리방침과 같은 페이지에 삭제 요청 안내를 넣으면 된다. → 5번
- [ ] **개인정보처리방침 URL이 없다** → 5번

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

`android/app/build.gradle.kts` 수정 — `android { }` 블록 앞에 로드 코드를 넣고 release 서명을 교체한다:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

- [ ] 키스토어 생성 및 저장소 밖에 보관 + 백업
- [ ] `key.properties` 작성 (커밋 안 됨 확인: `git status`에 안 뜨는지)
- [ ] `build.gradle.kts` release 서명 교체
- [ ] `flutter build appbundle --release`가 성공하는지 확인

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

- [ ] **앱 아이콘** 512×512 PNG — 앱 내 런처 아이콘도 같이 교체할 것
      (`flutter_launcher_icons` 패키지를 쓰면 mipmap 전 해상도를 한 번에 생성한다. 새 패키지이므로
      추가 시 이유를 커밋 메시지에 남길 것)
- [ ] **그래픽 이미지(feature graphic)** 1024×500 PNG
- [ ] **스크린샷** 최소 2장 (폰 기준) — 홈(내 대결 + 투두), 대결 진행(증거 제출), 결과 화면이 앱을 잘 보여준다
- [ ] **짧은 설명** 80자 이내
- [ ] **자세한 설명** 4000자 이내
- [ ] 앱 이름 (`투두두두`), 카테고리, 콘텐츠 등급 설문

---

## 5. 정책 문서 (최초 1회)

이 앱이 수집하는 것: **Google 계정 이메일·이름**(프로필 표시용), **사용자가 올린 증거 사진**,
**투두/대결 내용**. 전부 Supabase(외부 서버)에 저장되고 HTTPS로 전송된다.

- [ ] **개인정보처리방침** 작성 후 공개 URL로 호스팅 (GitHub Pages, Notion 공개 페이지 등 무료로 가능)
      — 수집 항목, 이용 목적, 보관 기간, 제3자(Supabase/Google) 제공, 삭제 요청 방법을 포함
- [ ] **Play Console → 데이터 보안(Data safety)** 양식 작성 — 위 수집 항목과 개인정보처리방침이
      서로 어긋나면 심사에서 걸린다
- [x] ~~앱 내 계정 삭제 경로~~ — 프로필 화면 → 계정 삭제 (0번 참고)
- [ ] **웹 계정 삭제 요청 URL** — 개인정보처리방침 페이지에 "탈퇴는 앱 내 프로필 → 계정 삭제,
      앱을 지운 뒤라면 이 메일로 요청" 형태로 안내하고 그 URL을 Play Console에 등록한다.
      앱 내 삭제가 지우는 범위(투두·증거 사진·표시 이름·auth 계정)와 남기는 범위(익명 처리된
      대결 기록)를 그대로 적어야 데이터 보안 양식과 어긋나지 않는다

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
- [ ] `targetSdk`가 Play의 현재 최소 요구치를 만족하는지 확인
      (Flutter가 정하는 값이라 SDK 버전에 따라 달라진다)

---

## 8. 배포 후

- [ ] Play Console 크래시/ANR 지표 확인
- [ ] Supabase 대시보드에서 에러 로그·사용량 확인 (무료 플랜 한도)
