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

// La clé d'importation du Play Store, **jamais dans le dépôt** : la CI la pose
// depuis ses secrets (`.github/workflows/play-internal.yml`), un poste depuis
// son environnement. Sans elle, le Release se compile non signé — c'est ce que
// la CI de chaque PR vérifie.
val uploadKeystore: String? = System.getenv("ANDROID_UPLOAD_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }

// Le numéro de version que le Play Store exige croissant à chaque envoi : la
// CI le passe (le numéro du workflow), un poste garde 1.
val versionCodeOverride: Int? = providers.gradleProperty("memobook.versionCode").orNull?.toIntOrNull()

android {
    namespace = "com.memobook.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.memobook.app"
        minSdk = 26
        targetSdk = 36
        versionCode = versionCodeOverride ?: 1
        versionName = "0.1.0"
        buildConfigField("String", "PRODUCTION_API_BASE_URL", "\"$productionApiBaseUrl\"")
    }

    signingConfigs {
        if (uploadKeystore != null) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("ANDROID_UPLOAD_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_UPLOAD_KEY_PASSWORD")
            }
        }
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
            if (uploadKeystore != null) signingConfig = signingConfigs.getByName("upload")
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

    // L'app ne parle que français (`FrenchLocale`) : on n'embarque que les
    // traductions françaises des bibliothèques, et le Play Store ne découpe pas
    // le paquet par langue — un téléphone réglé en anglais recevrait sinon les
    // textes anglais des bibliothèques, et non les français que l'app affiche.
    androidResources { localeFilters += setOf("fr") }
    bundle { language { enableSplit = false } }
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
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
}
