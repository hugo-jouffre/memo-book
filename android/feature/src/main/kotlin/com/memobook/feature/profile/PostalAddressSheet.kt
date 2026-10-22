package com.memobook.feature.profile

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.core.PostalAddress
import com.memobook.core.ShippingCountry
import com.memobook.core.TravellerProfile
import com.memobook.core.matching
import com.memobook.design.BrandButton
import com.memobook.design.BrandCountryField
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandNotice
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandTextField
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.isReduceMotionEnabled

/**
 * Où envoyer le carnet imprimé — à donner, ou à corriger. Jumeau de
 * `Profile/PostalAddressSheet.swift`.
 *
 * La feuille travaille sur une **copie** de l'adresse : tant qu'on n'a pas
 * validé, rien ne change dans le profil. Refermer d'un glissé revient donc à
 * annuler, ce que le geste laisse attendre. Ouverte sur une adresse déjà
 * connue, elle la montre telle quelle et tout s'y corrige : c'est la même
 * feuille qui ajoute et qui modifie, seule sa phrase d'en-tête change.
 *
 * **Le pays se choisit, il ne se tape pas.** La liste est celle de
 * l'imprimeur, servie avec le profil (`TravellerProfile.shippingCountries`)
 * — la même que celle du tunnel de commande, dont cette adresse est l'amorce.
 * Un texte libre laissait écrire un pays où le carnet ne partira jamais, ou
 * trois graphies pour le même.
 *
 * **Sauf quand la liste n'est pas là.** Un profil relu depuis le cache, ou
 * servi par un back-end qui ne l'envoie pas encore, arrive sans elle : le
 * champ redevient alors une saisie libre, et c'est le serveur qui ramène
 * « France » à son code. Un menu vide et grisé laissait la feuille sans issue
 * — « Choisir un pays » qu'on ne pouvait pas choisir, et « Valider » qui
 * n'y arrivait jamais (Paul, 21/09/2026). La liste arrive souvent une
 * seconde après, avec le profil frais : le menu prend alors la place du
 * champ, sans perdre ce qui y était tapé.
 *
 * **« Valider » ne se désactive pas.** Il pâlit tant qu'il manque une ligne,
 * et l'appui dit laquelle au lieu d'avaler le geste — la règle de l'app pour
 * tout ce qu'on ne peut pas encore faire. Un bouton gris qui ne répond pas
 * laissait chercher ce qu'on avait mal fait : les exemples dans les champs
 * vides (« 7 rue Simon Fryd », « Lyon ») se lisaient comme une adresse déjà
 * remplie, et rien ne disait pourquoi elle ne partait pas (Paul, 18/09/2026).
 *
 * @param address celle du profil. Vide pour un compte qui n'en a pas encore.
 * @param countries les pays livrables, dans l'ordre du serveur. Le premier
 *   — la France — est proposé d'office quand l'adresse n'a pas encore de
 *   pays : c'est celui de presque tous les carnets, et il se change d'un
 *   geste.
 */
@Composable
internal fun PostalAddressSheet(
    address: PostalAddress,
    countries: List<ShippingCountry>,
    onSave: (PostalAddress) -> Unit,
) {
    // Le même critère que la ligne du profil, qui écrit « Ajouter une
    // adresse » quand il n'y a rien à résumer.
    val hasAddress = remember { address.singleLine.isNotEmpty() }
    var draft by remember { mutableStateOf(address.settled(countries)) }

    // « Valider » a été touché trop tôt : on nomme ce qui manque, tant que ça
    // manque. La phrase se lit sur le brouillon, pas sur un instantané — elle
    // se raccourcit à mesure qu'on remplit, et s'efface toute seule à la
    // dernière ligne.
    var isExplainingWhatIsMissing by remember { mutableStateOf(false) }
    var focus by remember { mutableStateOf<PostalAddress.Field?>(null) }
    val dismiss = LocalBrandSheetDismiss.current
    val reduceMotion = isReduceMotionEnabled()

    val missingSentence = draft.missingFieldsDescription
        ?.takeIf { isExplainingWhatIsMissing }
        ?.let { "Il manque **$it** pour que ton carnet arrive." }

    // La liste arrive après l'ouverture — le profil frais a remplacé celui du
    // cache : ce qui était tapé retombe sur sa ligne du menu.
    LaunchedEffect(countries) { draft = draft.settled(countries) }

    // Enregistre si tout y est ; sinon, dit ce qui manque et ouvre le premier
    // champ vide, clavier compris — le pays, lui, se choisit dans son menu,
    // sauf quand il se tape.
    fun validate() {
        if (!draft.isComplete) {
            isExplainingWhatIsMissing = true
            focus = draft.missingFields.firstOrNull { countries.isEmpty() || it != PostalAddress.Field.Country }
            return
        }
        focus = null
        onSave(draft.trimmed)
        dismiss()
    }

    val buttonAlpha by animateFloatAsState(if (draft.isComplete) 1f else 0.45f, SwiftMotion.snappy(0.25f), label = "valider")

    // La barre du clavier de l'app — l'icône qui le range —, et non un « OK »
    // qui laisserait croire qu'on valide quelque chose.
    BrandKeyboardDismissBar {
        BrandSheet(
            "Adresse postale",
            subtitle = if (hasAddress) {
                "Modifie l’adresse où tu souhaites recevoir ton carnet."
            } else {
                "Ajoute l’adresse où tu souhaites recevoir ton carnet."
            },
        ) {
            Column(
                if (reduceMotion) Modifier else Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
                verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
            ) {
                // Pas de majuscule à chaque mot : « 18 avenue des Ternes »
                // s'écrit ainsi, et le tunnel de commande fait pareil.
                BrandTextField(
                    "Adresse",
                    draft.street,
                    { draft = draft.copy(street = it) },
                    field = PostalAddress.Field.Street,
                    focus = focus,
                    onFocusChange = { focus = it },
                    labelPlacement = BrandTextField.LabelPlacement.Above,
                    placeholder = "7 rue Simon Fryd",
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Next),
                    keyboardActions = KeyboardActions(onNext = { focus = PostalAddress.Field.PostalCode }),
                    contentType = ContentType.AddressStreet,
                )

                PostalCodeAndCity(
                    draft = draft,
                    onDraftChange = { draft = it },
                    focus = focus,
                    onFocusChange = { focus = it },
                    countryIsTyped = countries.isEmpty(),
                )

                // Le menu quand la liste est là, la saisie libre sinon — voir l'en-tête.
                if (countries.isEmpty()) {
                    BrandTextField(
                        "Pays",
                        draft.country,
                        { draft = draft.copy(country = it) },
                        field = PostalAddress.Field.Country,
                        focus = focus,
                        onFocusChange = { focus = it },
                        labelPlacement = BrandTextField.LabelPlacement.Above,
                        placeholder = "France",
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { focus = null }),
                        contentType = ContentType.AddressCountry,
                    )
                } else {
                    BrandCountryField(countries = countries, code = draft.country, onCodeChange = { draft = draft.copy(country = it) }, label = "Pays")
                }

                AnimatedVisibility(
                    visible = missingSentence != null,
                    enter = if (reduceMotion) fadeIn() else fadeIn() + expandVertically(expandFrom = Alignment.Top),
                    exit = if (reduceMotion) fadeOut() else fadeOut() + shrinkVertically(shrinkTowards = Alignment.Top),
                ) {
                    // La dernière phrase reste le temps de disparaître.
                    val sentence = remember { mutableStateOf("") }
                    missingSentence?.let { sentence.value = it }
                    BrandNotice(sentence.value, tone = BrandNotice.Tone.Information)
                }

                BrandButton(
                    "Valider",
                    // Pâli, pas désactivé : il reste tapable pour expliquer.
                    modifier = Modifier
                        .padding(top = MemoBookSpacing.xs)
                        .alpha(buttonAlpha)
                        .semantics { if (!draft.isComplete) stateDescription = "Il manque une ligne à l’adresse" },
                    fillsWidth = true,
                    action = ::validate,
                )
            }
        }
    }
}

/**
 * Deux colonnes égales, comme prénom/nom de l'écran d'entrée — et une
 * colonne unique en taille accessible, où chacune tomberait à quelques
 * caractères de large.
 */
@Composable
private fun PostalCodeAndCity(
    draft: PostalAddress,
    onDraftChange: (PostalAddress) -> Unit,
    focus: PostalAddress.Field?,
    onFocusChange: (PostalAddress.Field?) -> Unit,
    countryIsTyped: Boolean,
) {
    // Le clavier du texte et non des chiffres : Android n'a pas le pavé
    // « chiffres et ponctuation » d'iOS, et un code postal britannique ou
    // néerlandais porte des lettres.
    val postalCode: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            "Code postal",
            draft.postalCode,
            { onDraftChange(draft.copy(postalCode = it)) },
            field = PostalAddress.Field.PostalCode,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = "69007",
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { onFocusChange(PostalAddress.Field.City) }),
            contentType = ContentType.PostalCode,
        )
    }

    // Dernier champ tapé quand le pays se choisit : le clavier se range, et
    // « Valider » est là. Quand le pays se tape, il est le suivant.
    val city: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            "Ville",
            draft.city,
            { onDraftChange(draft.copy(city = it)) },
            field = PostalAddress.Field.City,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = "Lyon",
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Words,
                imeAction = if (countryIsTyped) ImeAction.Next else ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onNext = { onFocusChange(PostalAddress.Field.Country) },
                onDone = { onFocusChange(null) },
            ),
            contentType = ContentType.AddressLocality,
        )
    }

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            postalCode(Modifier)
            city(Modifier)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.Top) {
            postalCode(Modifier.weight(1f))
            city(Modifier.weight(1f))
        }
    }
}

/**
 * L'adresse telle que la feuille la présente, la liste des pays en main.
 *
 * Le pays retombe sur son code si la liste le connaît — par son code ou
 * par son nom, tapé du temps où il se tapait — ; la France est proposée
 * quand il n'y en a pas encore ; et sans liste, rien ne bouge : ce qui
 * est écrit reste écrit, y compris ce qui vient d'être tapé.
 */
private fun PostalAddress.settled(countries: List<ShippingCountry>): PostalAddress {
    val known = countries.matching(country)
    return when {
        known != null -> copy(country = known.code)
        country.trim().isEmpty() && countries.isNotEmpty() -> copy(country = countries.first().code)
        else -> this
    }
}

/**
 * Les espaces de bord d'un clavier tactile ne font pas partie de l'adresse :
 * on les retire avant d'envoyer, pas avant de comparer.
 */
private val PostalAddress.trimmed: PostalAddress
    get() = PostalAddress(
        street = street.trim(),
        postalCode = postalCode.trim(),
        city = city.trim(),
        country = country.trim(),
        countryName = countryName,
    )

@Preview(locale = "fr-rFR", name = "Adresse postale — à modifier", heightDp = 800)
@Composable
private fun PostalAddressSheetEditPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        PostalAddressSheet(TravellerProfile.fixture.address, TravellerProfile.fixture.shippingCountries) {}
    }
}

@Preview(locale = "fr-rFR", name = "Adresse postale — sans liste de pays", heightDp = 800)
@Composable
private fun PostalAddressSheetNoCountriesPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        PostalAddressSheet(PostalAddress(), emptyList()) {}
    }
}

@Preview(locale = "fr-rFR", name = "Adresse postale — à ajouter", heightDp = 800)
@Composable
private fun PostalAddressSheetAddPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        PostalAddressSheet(PostalAddress(), TravellerProfile.fixture.shippingCountries) {}
    }
}
