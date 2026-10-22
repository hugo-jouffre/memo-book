package com.memobook.core

import kotlinx.serialization.Serializable
import java.text.Normalizer

// Le jumeau de `ShippingCountry` (`MemoBookCore/PrintOrderFlow.swift`), et de
// sa règle `matching` : un nom tapé à la main qui retombe sur sa ligne. Il vit
// dans son fichier parce que le design system s'en servait avant le tunnel de
// commande (`PrintOrderFlow.kt`).

/**
 * Un pays où l'imprimeur livre. **Servi par le serveur**, jamais codé en dur :
 * la liste suit l'imprimeur, elle ne doit pas attendre une version de l'app.
 *
 * @property code ISO 3166-1 alpha-2. C'est la seule forme que la base garde.
 */
@Serializable
data class ShippingCountry(val code: String, val name: String) {
    /** L'identité du pays dans une liste : son code, comme `Identifiable` sur iOS. */
    val id: String get() = code
}

/**
 * Le pays que désigne ce texte : son code (« FR », « fr ») ou son nom
 * (« France », « FRANCE »), sans tenir compte de la casse.
 *
 * La même règle que celle du serveur (`findShippingCountry`) : un profil
 * enregistré avant la liste porte un nom tapé à la main, et il doit retomber
 * sur sa ligne du menu plutôt que d'y apparaître comme un inconnu. `null` quand
 * rien ne correspond — c'est à l'appelant de dire ce qu'il en fait.
 *
 * Le nom se compare aussi sans les accents (« Etats-Unis » trouve
 * « États-Unis »), comme `.diacriticInsensitive` d'iOS.
 */
fun List<ShippingCountry>.matching(raw: String): ShippingCountry? {
    val value = raw.trim()
    if (value.isEmpty()) return null
    return firstOrNull { it.code.equals(value, ignoreCase = true) }
        ?: firstOrNull { it.name.withoutDiacritics().equals(value.withoutDiacritics(), ignoreCase = true) }
}

private fun String.withoutDiacritics(): String =
    Normalizer.normalize(this, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
