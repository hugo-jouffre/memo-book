import java.util.Properties

// La cible app : volontairement mince, comme `ios/App`. Elle lit la
// configuration de build et assemble `AppDependencies` ; tout le reste vit dans
// les modules.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// `secrets.properties` est local et ignoré par Git — son modèle documenté,
// `secrets.example.properties`, est versionné. C'est là qu'on pointe un
// téléphone sur l'IP du Mac, comme `ios/Config/Secrets.xcconfig`.
val secrets = Properties().apply {
    rootProject.file("secrets.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val productionApiBaseUrl: String = providers.gradleProperty("memobook.productionApiBaseUrl").get()

android {
    namespace = "com.memobook.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.memobook.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "PRODUCTION_API_BASE_URL", "\"$productionApiBaseUrl\"")
    }

    buildTypes {
        debug {
            // L'émulateur joint le Mac à 10.0.2.2. Un téléphone qui recevrait
            // cette adresse retombe sur la production : `ApiConfiguration.effective`.
            val local = secrets.getProperty("MEMOBOOK_API_BASE_URL") ?: "http://10.0.2.2:3000"
            buildConfigField("String", "API_BASE_URL", "\"$local\"")
        }
        release {
            buildConfigField("String", "API_BASE_URL", "\"$productionApiBaseUrl\"")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":design"))
    implementation(project(":networking"))
    implementation(project(":feature"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
}
