// La capture audio — comme `MemoBookRecording`, elle ne dépend que de `core`.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.memobook.recording"
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
