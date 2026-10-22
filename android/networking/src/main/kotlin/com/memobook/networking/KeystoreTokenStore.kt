package com.memobook.networking

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Le magasin de jetons de l'app : le pendant du `KeychainTokenStore` d'iOS.
 *
 * Le jeton identifie l'appareil — ou ouvre la session — auprès de l'API : il
 * n'a rien à faire en clair dans des `SharedPreferences`, qu'une sauvegarde
 * emporte. Il y est donc écrit **chiffré** (AES-GCM), par une clé qui vit dans
 * le Keystore d'Android et n'en sort jamais.
 *
 * Pas d'`androidx.security.crypto` : la bibliothèque est dépréciée, et ce
 * qu'elle faisait tient ici en une clé et deux appels.
 *
 * Une sauvegarde restaurée sur un autre téléphone rapporte le texte chiffré,
 * pas la clé : le déchiffrement échoue, l'entrée est oubliée et [read] rend
 * `null` — exactement ce que fait un trousseau `AfterFirstUnlock` qui ne
 * migre pas. On se reconnecte, rien ne casse.
 *
 * @param service le nom du fichier de préférences, comme le `service` du trousseau.
 * @param account l'entrée : `device-token` pour l'appareil, `session-token` pour la session.
 */
class KeystoreTokenStore(
    context: Context,
    private val service: String = "com.memobook.app",
    private val account: String = "device-token",
) : TokenStore {
    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences("$service.tokens", Context.MODE_PRIVATE)

    /** Une clé par entrée : effacer la session ne touche pas à l'appareil. */
    private val keyAlias = "$service.$account"

    private val lock = Any()

    override fun read(): String? = synchronized(lock) {
        val stored = preferences.getString(account, null) ?: return null
        try {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            if (bytes.size <= IV_LENGTH) throw GeneralSecurityException("Entrée tronquée.")
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                existingKey() ?: throw GeneralSecurityException("Clé absente."),
                GCMParameterSpec(TAG_LENGTH_BITS, bytes, 0, IV_LENGTH),
            )
            String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH), Charsets.UTF_8)
        } catch (_: GeneralSecurityException) {
            // Illisible — clé perdue, sauvegarde d'un autre appareil : on
            // l'oublie, comme un trousseau qui ne la retrouve pas.
            preferences.edit().remove(account).apply()
            null
        } catch (_: IllegalArgumentException) {
            preferences.edit().remove(account).apply()
            null
        }
    }

    override fun write(token: String) {
        synchronized(lock) {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            // Le Keystore tire lui-même l'IV : on le range devant le chiffré.
            cipher.init(Cipher.ENCRYPT_MODE, existingKey() ?: createKey())
            val sealed = cipher.iv + cipher.doFinal(token.toByteArray(Charsets.UTF_8))
            // `commit` et non `apply` : la ligne suivante de l'appelant peut
            // très bien être un `read` depuis un autre fil.
            preferences.edit().putString(account, Base64.encodeToString(sealed, Base64.NO_WRAP)).commit()
        }
    }

    override fun clear() {
        synchronized(lock) {
            preferences.edit().remove(account).commit()
        }
    }

    private fun existingKey(): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        return (keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry)?.secretKey
    }

    private fun createKey(): SecretKey {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_LENGTH_BITS = 128
    }
}
