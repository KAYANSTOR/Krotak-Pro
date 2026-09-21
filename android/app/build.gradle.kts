import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.kayan.net_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.kayan.krotak_pro"
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
        // مفتاح توقيع ثابت — نفس المفتاح عبر كل بناءات CI والمحلية حتى يثبّت
        // APK الجديد مباشرة فوق النسخة المثبتة بدون «حزمة التثبيت لا تتوافق».
        create("upload") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val props = Properties().apply {
                    load(FileInputStream(keystorePropertiesFile))
                }
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
                storeFile = props.getProperty("storeFile")?.let { file(it) }
                storePassword = props.getProperty("storePassword")
                // المفتاح محفوظ بصيغة PKCS12؛ نحدّد النوع صراحةً حتى لا يعتمد
                // البناء على تخمين Gradle من امتداد الملف.
                storeType = props.getProperty("storeType") ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("upload")
            } else {
                // محلي بلا key.properties: مفتاح debug حتى يبقى flutter run --release يعمل.
                signingConfigs.getByName("debug")
            }
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
