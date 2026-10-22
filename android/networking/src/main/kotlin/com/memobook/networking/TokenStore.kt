package com.memobook.networking

/**
 * Conservation d'un jeton — celui de l'appareil, ou celui de la session —
 * entre deux lancements. Le jumeau de `MemoBookNetworking/TokenStore.swift`.
 *
 * Une interface, et non le magasin chiffré lui-même : le client d'API ne
 * dépend pas d'Android, ce qui laisse ses tests tourner sur la JVM. Le vrai
 * magasin de l'app est [KeystoreTokenStore], dans un fichier à part qui ne
 * compile qu'avec le SDK.
 */
interface TokenStore {
    fun read(): String?
    fun write(token: String)
    fun clear()
}

/** Stockage en mémoire, pour les tests, les aperçus et le bac à sable. */
class InMemoryTokenStore(token: String? = null) : TokenStore {
    private val lock = Any()
    private var token: String? = token

    override fun read(): String? = synchronized(lock) { token }

    override fun write(token: String) {
        synchronized(lock) { this.token = token }
    }

    override fun clear() {
        synchronized(lock) { token = null }
    }
}
