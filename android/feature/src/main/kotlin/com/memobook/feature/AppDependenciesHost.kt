package com.memobook.feature

/**
 * Celui qui tient les dépendances de l'app — `MemoBookApplication`. Sans
 * jumeau iOS : c'est par lui qu'un travail d'arrière-plan
 * ([RecordingOutboxWorker]), que WorkManager construit lui-même, retrouve la
 * file des envois.
 *
 * Une interface dans `:feature` et non une référence à l'`Application` de
 * `:app` : la dépendance ne remonte jamais.
 */
interface AppDependenciesHost {
    /**
     * Les dépendances de ce processus. `null` quand il n'y en a pas encore et
     * qu'on ne peut pas les construire — le travail repassera.
     */
    val dependencies: AppDependencies?
}
