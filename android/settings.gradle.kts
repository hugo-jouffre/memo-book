pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // Un module ne déclare pas ses propres dépôts : tout passe par ici.
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "MemoBook"

// Les mêmes modules que l'app iOS (`ios/Modules/Sources`), dans le même sens de
// dépendance : `core` ne dépend de rien, `networking`, `recording`, `payments`
// et `design` de `core` seulement, `feature` de tous, `app` assemble.
include(
    ":core",
    ":design",
    ":networking",
    ":recording",
    ":payments",
    ":feature",
    ":app",
    // Outillage, hors de l'app : l'import des images de marque.
    ":tools",
)
