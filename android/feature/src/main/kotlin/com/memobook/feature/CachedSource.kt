package com.memobook.feature

/**
 * Une source d'écran qui peut répondre **deux fois** : ce qu'on avait, puis ce
 * qui arrive. Jumeau de `CachedSource.swift`.
 *
 * **C'est la seule pièce que le cache ajoute aux modèles d'écran.** Ils
 * recevaient une fonction `suspend () -> Value` ; ils reçoivent en plus une
 * fonction qui rend ce qui est sur le disque, sans pouvoir échouer. Le modèle
 * s'en sert dans cet ordre :
 *
 * ```kotlin
 * fun load() = viewModelScope.launch {
 *     if (state.value.content == null) cached?.invoke()?.let { apply(it, isFresh = false) }
 *     try { apply(source(), isFresh = true) } catch (error: Exception) { … }
 * }
 * ```
 *
 * **Le cache n'est jamais la réponse finale.** Un écran servi par le disque
 * reste « en chargement » — la lecture réseau continue derrière —, et un échec
 * de celle-ci laisse le contenu du disque en place avec son bandeau.
 */
typealias CachedValue<Value> = suspend () -> Value?

/**
 * Ce qu'un écran vient d'apprendre, et s'il faut l'animer.
 *
 * **L'animation ne se joue que sur un vrai changement**, jamais à la première
 * arrivée ni sur une réponse identique : un écran qui clignote à chaque
 * ouverture apprend à ne plus être regardé.
 */
enum class ContentFreshness {
    /** Rien n'est encore arrivé. */
    Unknown,

    /** Ce qui est à l'écran vient du disque : on attend le serveur. */
    Restored,

    /** Le serveur a répondu, et disait la même chose. Rien à signaler. */
    Unchanged,

    /** Le serveur a répondu, et **ce n'est plus la même chose**. Le seul cas qui s'anime. */
    Updated,
    ;

    /** Faut-il jouer l'animation de mise à jour ? */
    val isUpdated: Boolean get() = this == Updated
}

/**
 * Décide de la fraîcheur d'une valeur qui arrive. Une fonction libre : les
 * modèles font exactement le même raisonnement, et le seul moyen de garantir
 * qu'ils le font pareil est qu'il n'existe qu'une fois.
 *
 * @param incoming ce que le serveur vient de rendre.
 * @param shown ce qui est à l'écran, s'il y a quelque chose.
 */
fun <Value> contentFreshness(incoming: Value, shown: Value?): ContentFreshness {
    // Rien n'était affiché : c'est une première arrivée, pas une mise à jour.
    if (shown == null) return ContentFreshness.Unchanged
    return if (shown == incoming) ContentFreshness.Unchanged else ContentFreshness.Updated
}
