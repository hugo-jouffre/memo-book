// Le client d'API — comme `MemoBookNetworking`, il ne dépend que de `core`.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.memobook.networking"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
}
