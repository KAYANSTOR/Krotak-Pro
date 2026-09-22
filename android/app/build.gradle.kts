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
        applicationId = "com.kayan.net_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // مفتاح توقيع ثابت — نفس الشهادة عبر كل بناءات التحديث حتى يثبّت
        // APK فوق النسخة المثبتة بدون «حزمة التثبيت لا تتوافق».
        create("upload") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val props = Properties().apply {
                    load(FileInputStream(keystorePropertiesFile))
                }
                keyAlias = props.getProperty("keyAlias")
                    ?: error("key.properties: keyAlias مفقود")
                keyPassword = props.getProperty("keyPassword")
                    ?: error("key.properties: keyPassword مفقود")
                storePassword = props.getProperty("storePassword")
                    ?: error("key.properties: storePassword مفقود")
                val storePath = props.getProperty("storeFile")
                    ?: error("key.properties: storeFile مفقود")
                val resolved = file(storePath)
                if (!resolved.isFile) {
                    error(
                        "ملف الـ keystore غير موجود: ${resolved.absolutePath}\n" +
                            "انظر android/key.properties.example و docs/signing-and-updates-ar.md",
                    )
                }
                storeFile = resolved
                storeType = props.getProperty("storeType") ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            // لا نسقط صامتاً إلى debug: ذلك يسبب «حزمة التثبيت لا تتوافق»
            // عند محاولة التحديث فوق نسخة موقّعة بمفتاح الإصدار.
            val keyProps = rootProject.file("key.properties")
            val allowDebugRelease =
                project.hasProperty("allowDebugRelease") &&
                    project.property("allowDebugRelease").toString() == "true"
            signingConfig = when {
                keyProps.exists() -> signingConfigs.getByName("upload")
                allowDebugRelease -> {
                    logger.warn(
                        "WARNING: release موقّع بمفتاح debug (−PallowDebugRelease=true). " +
                            "لن يتوافق مع APK الإصدار التجاري المثبّت على الأجهزة.",
                    )
                    signingConfigs.getByName("debug")
                }
                else -> error(
                    """
                    |رفض بناء release: ملف android/key.properties غير موجود.
                    |
                    |بدون نفس مفتاح التوقيع الثابت، أندرويد يرفض التحديث برسالة
                    |«حزمة التثبيت لا تتوافق» ويطلب إلغاء التثبيت.
                    |
                    |الحل:
                    |1) انسخ أسرار التوقيع من GitHub Secrets إلى android/key.properties
                    |   (انظر android/key.properties.example و docs/signing-and-updates-ar.md)
                    |2) أو ابنِ من CI على main (artifact موقّع بالمفتاح التجاري)
                    |3) للاختبار المحلي فقط: flutter build apk --release -PallowDebugRelease=true
                    """.trimMargin(),
                )
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
