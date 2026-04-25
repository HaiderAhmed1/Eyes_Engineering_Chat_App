import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader().use { reader ->
        localProperties.load(reader)
    }
}

// تعيين القيم الافتراضية
val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

// --- إعدادات التوقيع (Keystore) ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.haider.chat.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // تفعيل Desugaring لدعم ميزات Java الحديثة
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    defaultConfig {
        applicationId = "com.haider.chat.app"
        // الحد الأدنى للإصدار لضمان توافق المكتبات
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName

        multiDexEnabled = true
    }

    // --- تعريف إعدادات التوقيع ---
    signingConfigs {
        val keyAliasVal = keystoreProperties["keyAlias"] as String?
        val keyPasswordVal = keystoreProperties["keyPassword"] as String?
        val storeFileVal = keystoreProperties["storeFile"] as String?
        val storePasswordVal = keystoreProperties["storePassword"] as String?

        if (keyAliasVal != null && keyPasswordVal != null && storeFileVal != null && storePasswordVal != null) {
            create("release") {
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
                storeFile = file(storeFileVal)
                storePassword = storePasswordVal
            }
        }
    }

    buildTypes {
        getByName("release") {
            // --- تفعيل التوقيع للنسخة النهائية فقط إذا كان التوقيع موجوداً ---
            if (signingConfigs.findByName("release") != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // --- تم التعديل: استخدام الإصدار 2.1.4 المتوفر والمطلوب ---
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    implementation(platform("com.google.firebase:firebase-bom:33.1.2"))
    implementation("com.google.firebase:firebase-messaging")

    implementation("androidx.multidex:multidex:2.0.1")
}
