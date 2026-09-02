import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
