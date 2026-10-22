// Modèles et règles pures, sans Android : comme `MemoBookCore`, ce module ne
// dépend que de la bibliothèque JSON de Kotlin — le `Codable` que Swift a de
// naissance. Ses tests tournent sur la JVM, sans émulateur.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

java {
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    api(libs.kotlinx.serialization.json)
    testImplementation(libs.kotlin.test)
}
