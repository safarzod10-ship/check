import java.util.Base64
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

fun props(name: String) = Properties().apply {
    rootProject.file(name).takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val local = props("local.properties")
val keystore = props("keystore.properties")

/** Значение из local.properties или переменной окружения (для CI). Секретов здесь быть не должно. */
fun cfg(key: String): String = (local.getProperty(key) ?: System.getenv(key) ?: "").trim()
fun signing(key: String): String? = (keystore.getProperty(key) ?: System.getenv(key))?.takeIf { it.isNotBlank() }

android {
    namespace = "tj.payvand.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "tj.payvand.app"
        minSdk = 28            // Android 9
        targetSdk = 35
        versionCode = (System.getenv("PAYVAND_VERSION_CODE") ?: "1").toInt()
        versionName = "0.1.0"

        // Публичные параметры сервера. anon-ключ Supabase рассчитан на публикацию в клиенте;
        // service_role-ключ сюда попадать НЕ должен — сборка упадёт, если его подставить.
        val anon = cfg("PAYVAND_SUPABASE_ANON_KEY")
        require(!anon.contains("service_role") && !String(Base64.getUrlDecoder().decode(
            anon.split(".").getOrNull(1)?.let { it + "=".repeat((4 - it.length % 4) % 4) } ?: "")).contains("service_role")) {
            "PAYVAND_SUPABASE_ANON_KEY содержит service_role-ключ. В APK допускается только anon/publishable ключ."
        }
        buildConfigField("String", "SUPABASE_URL", "\"${cfg("PAYVAND_SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$anon\"")
        // Firebase Cloud Messaging (необязательно; значения из google-services.json — не секретны)
        buildConfigField("String", "FCM_APP_ID", "\"${cfg("PAYVAND_FCM_APP_ID")}\"")
        buildConfigField("String", "FCM_API_KEY", "\"${cfg("PAYVAND_FCM_API_KEY")}\"")
        buildConfigField("String", "FCM_PROJECT_ID", "\"${cfg("PAYVAND_FCM_PROJECT_ID")}\"")
        buildConfigField("String", "FCM_SENDER_ID", "\"${cfg("PAYVAND_FCM_SENDER_ID")}\"")
        vectorDrawables { useSupportLibrary = true }
    }

    signingConfigs {
        // Собственный ключ подписи: keystore.properties (в .gitignore) или переменные окружения CI.
        signing("PAYVAND_KEYSTORE_FILE")?.let { path ->
            create("release") {
                storeFile = rootProject.file(path)
                storePassword = signing("PAYVAND_KEYSTORE_PASSWORD")
                keyAlias = signing("PAYVAND_KEY_ALIAS")
                keyPassword = signing("PAYVAND_KEY_PASSWORD") ?: signing("PAYVAND_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["cleartext"] = "true"   // локальный сервер разработки по http
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            manifestPlaceholders["cleartext"] = "false"  // только HTTPS
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    androidResources { generateLocaleConfig = false }
    packaging { resources { excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/INDEX.LIST", "META-INF/DEPENDENCIES", "META-INF/versions/9/OSGI-INF/MANIFEST.MF") } }
    lint { abortOnError = false; checkReleaseBuilds = false }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.coroutines.android)

    implementation(platform(libs.compose.bom))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.0")
    implementation("androidx.lifecycle:lifecycle-process:2.9.0")
    implementation("androidx.navigation:navigation-compose:2.9.0")
    implementation("androidx.exifinterface:exifinterface:1.4.1")
    implementation(libs.coil.compose)
    implementation("io.coil-kt.coil3:coil-network-okhttp:${libs.versions.coil.get()}")
    implementation("com.google.firebase:firebase-messaging:24.1.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
}
