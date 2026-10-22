// L'abonnement (Google Play Billing) et le paiement du carnet (Stripe) —
// comme `MemoBookPayments`, isolés ici pour que leurs SDK ne touchent rien d'autre.
plugins {
    alias(libs.plugins.android.library)
}

android {
    namespace = "com.memobook.payments"
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
