// L'outillage de l'app, hors de l'app : rien ici n'est embarqué.
//
//   ./gradlew :tools:importBrandAssets
//
// recopie le catalogue d'images de l'app iOS dans `:design` (voir
// `ImportBrandAssets.kt`).
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
    implementation(libs.android.sdk.common)
    testImplementation(libs.kotlin.test)
}

tasks.register<JavaExec>("importBrandAssets") {
    group = "memobook"
    description = "Recopie MemoBookAssets.xcassets dans :design (VectorDrawables et images)."
    mainClass.set("com.memobook.tools.ImportBrandAssetsKt")
    classpath = sourceSets["main"].runtimeClasspath
    args(rootDir.parentFile.absolutePath)
}
