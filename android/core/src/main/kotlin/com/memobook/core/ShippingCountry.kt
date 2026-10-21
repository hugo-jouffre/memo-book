package com.memobook.core

// Le jumeau de `ShippingCountry` (`MemoBookCore/PrintOrderFlow.swift`). Le
// décodage JSON et la règle `matching` (un nom tapé à la main qui retombe sur sa
// ligne) arrivent avec le reste du tunnel de commande, en phase A3.

/**
 * Un pays où l'imprimeur livre. **Servi par le serveur**, jamais codé en dur :
 * la liste suit l'imprimeur, elle ne doit pas attendre une version de l'app.
 *
 * @property code ISO 3166-1 alpha-2. C'est la seule forme que la base garde.
 */
data class ShippingCountry(val code: String, val name: String) {
    /** L'identité du pays dans une liste : son code, comme `Identifiable` sur iOS. */
    val id: String get() = code
}
