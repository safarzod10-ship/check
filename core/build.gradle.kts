plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    api(platform(libs.supabase.bom))
    api(libs.supabase.auth)
    api(libs.supabase.postgrest)
    api(libs.supabase.realtime)
    api(libs.supabase.storage)
    api(libs.ktor.okhttp)
    api(libs.coroutines.core)
    api(libs.serialization.json)

    testImplementation(kotlin("test"))
    testImplementation(libs.coroutines.test)
}

tasks.test {
    useJUnitPlatform()
    // Интеграционные тесты идут против настоящего Supabase (локального или облачного).
    listOf("PAYVAND_TEST_URL", "PAYVAND_TEST_ANON_KEY", "PAYVAND_TEST_MAIL_URL").forEach { k ->
        System.getenv(k)?.let { environment(k, it) }
    }
    // локальный стек не должен ходить через системный HTTPS-прокси
    systemProperty("http.nonProxyHosts", "localhost|127.0.0.1")
    testLogging { events("passed", "failed", "skipped") }
    outputs.upToDateWhen { false }
}

// «Второй пользователь» для ручной проверки приложения, см. PeerTool.kt
tasks.register<JavaExec>("peer") {
    group = "verification"
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("tj.payvand.core.PeerTool")
    environment("LC_ALL", "C.UTF-8")   // аргументы командной строки в UTF-8 (кириллица)
    jvmArgs("-Dfile.encoding=UTF-8", "-Dstdout.encoding=UTF-8")
    systemProperty("http.nonProxyHosts", "localhost|127.0.0.1")
}
