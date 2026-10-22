package com.memobook.core

/**
 * La règle qui dit si une adresse est plausible. Le jumeau de
 * `MemoBookCore/EmailAddress.swift`.
 *
 * **Volontairement permissive** : une adresse n'est vraiment validée que par
 * l'envoi d'un message. Ce qu'on écarte ici, ce sont les fautes de frappe
 * grossières — l'arobase oubliée, le domaine sans point — et rien d'autre.
 * Une règle plus stricte refuserait des adresses valides, ce qui coûte plus
 * cher qu'un aller-retour serveur.
 *
 * Elle vit dans `:core` parce que **deux écrans la posent** : l'entrée
 * dans l'app et la correction de l'adresse depuis le profil. Deux copies
 * auraient fini par diverger, et un formulaire aurait accepté ce que l'autre
 * refuse.
 */
object EmailAddress {
    fun isValid(email: String): Boolean {
        val parts = email.trim().split('@')

        if (parts.size != 2 || parts[0].isEmpty()) return false

        val host = parts[1]
        return host.contains('.') && !host.startsWith('.') && !host.endsWith('.')
    }
}
