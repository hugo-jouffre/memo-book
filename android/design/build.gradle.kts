// Tokens, composants `Brand…` et ressources de marque — comme `MemoBookDesign`.
//
// Pas de Material : la marque dessine chacune de ses surfaces, comme sur iOS où
// `BrandButton` est **le** bouton. Compose Foundation suffit.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.memobook.design"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

// `res-brand/` est écrit par `./gradlew :tools:importBrandAssets`, et par lui
// seul : le catalogue d'images de l'app iOS, converti.
androidComponents {
    onVariants { variant ->
        variant.sources.res?.addStaticSourceDirectory("src/main/res-brand")
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.compose.bom))
    api(libs.compose.foundation)
    api(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
}
