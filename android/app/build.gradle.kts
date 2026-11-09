import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // google-services는 Flutter 플러그인 뒤에 둔다(앞에 두면 적용 순서가 어긋나 설정을 못 읽는다).
    id("com.google.gms.google-services")
}

// 릴리스 서명 키. 키스토어와 비밀번호는 저장소 밖에 두고 android/key.properties로만 참조한다
// (key.properties와 *.jks는 gitignore됨). 작성법은 저장소 루트의 DEPLOY.md 1번 참고.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

fun requiredKeystoreProperty(name: String): String {
    val value = keystoreProperties.getProperty(name)
    if (value.isNullOrBlank()) {
        throw GradleException("android/key.properties에 $name 값이 없습니다. DEPLOY.md 1번을 참고하세요.")
    }
    return value
}

// 디버그 키로 서명된 AAB는 Play가 거부한다. 키 없이 릴리스를 만들려 하면 조용히 디버그 키로
// 넘어가지 않고 여기서 즉시 실패시킨다.
gradle.taskGraph.whenReady {
    if (!hasReleaseKeystore && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "릴리스 빌드에 필요한 android/key.properties가 없습니다. " +
                "업로드 키를 만들고 key.properties를 작성하세요 (DEPLOY.md 1번). " +
                "디버그 키로 서명된 빌드는 Play에 올릴 수 없습니다."
        )
    }
}

android {
    namespace = "com.todododo.todododo"
    // flutter.compileSdkVersion(36)이 아니라 37로 **고정**한다. flutter_local_notifications 23이
    // compileSdk 37로 컴파일돼서, 36으로 두면 AGP가 "이 라이브러리에 의존하는 앱은 37 이상으로
    // 컴파일해야 한다"며 릴리스·디버그 둘 다 실패시킨다. 빌드 시점의 API 수준이고 런타임 동작은
    // targetSdk가 정하므로(여기선 36 그대로) 기기 쪽 변화는 없다.
    // Flutter SDK 기본값이 37 이상으로 올라가면 이 줄을 flutter.compileSdkVersion으로 되돌린다.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications가 요구하는 설정. 이 플러그인은 예약 알림을 옛 안드로이드
        // 판에서도 쓰려고 java.time을 desugaring에 맡긴다 — 끄면 빌드가 깨진다
        // (todo-due-date design 8.2, 패키지 README "Gradle setup").
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // flutter_local_notifications README가 desugaring과 함께 요구한다.
        multiDexEnabled = true
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.todododo.todododo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = requiredKeystoreProperty("keyAlias")
                keyPassword = requiredKeystoreProperty("keyPassword")
                storeFile = file(requiredKeystoreProperty("storeFile"))
                storePassword = requiredKeystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
        }
    }
}

dependencies {
    // isCoreLibraryDesugaringEnabled의 상대. 판 번호는 flutter_local_notifications가 자기
    // 모듈에서 쓰는 것과 같게 맞춘다(둘이 어긋나면 중복 클래스로 깨진다).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
