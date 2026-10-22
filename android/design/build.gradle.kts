// Tokens, composants `Brand…` et ressources de marque — comme `MemoBookDesign`.
//
// Pas de Material : la marque dessine chacune de ses surfaces, comme sur iOS où
// `BrandButton` est **le** bouton. Compose Foundation suffit.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.roborazzi)
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
    testOptions { unitTests.isIncludeAndroidResources = true }
}

// Chaque @Preview du module est aussi un test de capture : `make snapshots`
// enregistre les images de référence dans `src/test/screenshots`, la CI les
// compare. Les previews privées comptent — ce sont celles des composants.
roborazzi {
    outputDir.set(file("src/test/screenshots"))
    @OptIn(com.github.takahirom.roborazzi.ExperimentalRoborazziApi::class)
    generateComposePreviewRobolectricTests {
        enable.set(true)
        packages.set(listOf("com.memobook.design"))
        includePrivatePreviews.set(true)
        // Une tolérance d'1 % des pixels entre le Mac qui enregistre et la CI
        // Linux qui compare : voir `MemoBookPreviewTester`.
        testerQualifiedClassName.set("com.memobook.design.MemoBookPreviewTester")
        // Le testeur garde la recherche des previews de Roborazzi, privées comprises.
        useScanOptionParametersInTester.set(true)
        // La langue vient de chaque preview (`@Preview(locale = "fr-rFR")`), comme
        // l'app est en français (`FrenchLocale`) : le testeur l'applique par-dessus.
        robolectricConfig.set(mapOf("sdk" to "[36]", "qualifiers" to "RobolectricDeviceQualifiers.Pixel7"))
    }
}

// Robolectric lit les descripteurs de fichiers par un accès interne du JDK,
// que le JDK 21 ferme par défaut.
tasks.withType<Test>().configureEach {
    jvmArgs("--add-exports=java.base/jdk.internal.access=ALL-UNNAMED", "--add-opens=java.base/jdk.internal.access=ALL-UNNAMED")
    maxHeapSize = "2g"
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
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.preview.scanner)
    testImplementation(libs.preview.scanner)
    debugImplementation(libs.compose.ui.test.manifest)
}
