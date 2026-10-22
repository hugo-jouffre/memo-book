// Les écrans et leurs modèles — comme `MemoBookFeature`, le seul module qui
// dépend de tous les autres.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.memobook.feature"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":design"))
    implementation(project(":networking"))
    implementation(project(":recording"))
    implementation(project(":payments"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
}
