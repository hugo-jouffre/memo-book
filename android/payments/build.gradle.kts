// L'abonnement (Google Play Billing) et le paiement du carnet (Stripe) —
// comme `MemoBookPayments`, isolés ici pour que leurs SDK ne touchent rien d'autre.
//
// Compose, parce que la feuille de Stripe s'enregistre **dans la composition**
// (`PaymentSheetsHost`) : c'est le seul endroit où ce module dessine — rien,
// d'ailleurs, il n'y pose que les feuilles du SDK.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.memobook.payments"
    compileSdk = 37
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.play.billing.ktx)
    implementation(libs.stripe.android)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.kotlinx.coroutines.test)
}
