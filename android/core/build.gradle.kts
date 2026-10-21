// Modèles et règles pures, sans Android : comme `MemoBookCore`, ce module ne
// dépend de rien. Ses tests tournent sur la JVM, sans émulateur.
plugins {
    alias(libs.plugins.kotlin.jvm)
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
    testImplementation(libs.kotlin.test)
}
