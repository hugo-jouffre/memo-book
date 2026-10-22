// La capture audio — comme `MemoBookRecording`, elle ne dépend que de `core`.
// La sérialisation pour la fiche d'un tour en attente (`PendingTurn`, le
// `Codable` d'iOS), les coroutines pour l'état observé (le `@Observable`).
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.memobook.recording"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // Les tests tournent sur la JVM : un appel au SDK d'Android y rend sa
    // valeur par défaut au lieu de lever (le lecteur de fichier qui ne lit rien).
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    implementation(project(":core"))
    api(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
}
