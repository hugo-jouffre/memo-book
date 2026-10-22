package com.memobook.feature.support

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.FaqEntry
import com.memobook.core.SupportCopy
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandNotice
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSearchField
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.feature.LocalTravellerFirstName
import kotlinx.coroutines.Dispatchers
import java.util.Locale

/**
 * Le support : qui nous sommes, ce qu'on nous demande le plus souvent, et
 * comment nous écrire. Jumeau de `Support/SupportView.swift`.
 *
 * **On y arrive de partout où l'app écrit « Besoin d'aide ? »** — le bas de
 * l'accueil, le bas du profil, la barre du paywall et la dernière ligne des
 * paramètres d'un voyage. C'est la raison d'être de l'écran : des liens qui ne
 * menaient nulle part mènent maintenant au même endroit.
 *
 * L'écran ne fait que **lister** : chaque question ouvre une feuille, et c'est
 * la feuille qui porte la réponse, le vote et le passage au formulaire. Une
 * réponse dépliée dans la liste aurait fait sauter tout ce qui est en dessous à
 * chaque touche.
 *
 * La photo et les deux paragraphes du haut ne sont pas de la décoration : la
 * page de support est l'endroit où quelqu'un arrive **contrarié**, et deux
 * visages avant une liste de liens changent le ton de ce qui suit.
 *
 * @param onBack la flèche de l'en-tête — le `dismiss()` d'iOS.
 * @param tripId le voyage d'où l'on est venu, s'il y en a un : il part avec le
 *   message (T226).
 */
@Composable
fun SupportView(model: SupportModel, onBack: () -> Unit, modifier: Modifier = Modifier, tripId: String? = null) {
    // L'immédiat du fil principal : le champ de recherche relit sa valeur sans
    // attendre l'image suivante, sans quoi le curseur saute.
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    var sheet by remember { mutableStateOf<SupportSheetRoute?>(null) }
    val context = LocalContext.current
    val version = remember(context) { SupportDevice.shortVersion(context) ?: "1.0" }

    // Le clavier de la recherche se range depuis sa barre (Hugo, 29/09/2026) :
    // sans ça, il restait levé sur une liste qu'il cachait à moitié. (Le geste
    // d'iOS qui le range en faisant défiler n'a pas d'équivalent ici.)
    BrandKeyboardDismissBar(modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .background(MemoBookColor.background)
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l),
        ) {
            // La photo se rapproche du titre : un écart de section entre les
            // deux les faisait lire comme deux blocs, alors que le bonjour
            // **suit** le titre (Hugo, 15/09/2026).
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                BrandScreenHeader(SupportCopy.title, onBack = onBack)
                SupportGreeting(LocalTravellerFirstName.current)
                SupportSearch(state, onSearchChange = { model.search = it })
            }

            SupportTopics(state) { sheet = SupportSheetRoute.Answer(it) }
            SupportContact(state) { sheet = SupportSheetRoute.Contact(about = it) }

            BrandText(
                SupportCopy.legal(version),
                MemoBookFont.caption,
                Modifier.fillMaxWidth(),
                color = MemoBookColor.disabledOutline,
                textAlign = TextAlign.Center,
            )
        }
    }

    BrandSheetHost(item = sheet, onDismissRequest = { sheet = null }) { route ->
        SupportSheet(model, route, tripId = tripId)
    }

    // Les votes déjà donnés, relus à chaque visite : un vote fait sur un autre
    // appareil y garde son « Merci ! ».
    LaunchedEffect(model) { model.loadVotes() }
}

// MARK: - Les deux visages, et le bonjour

@Composable
private fun SupportGreeting(firstName: String?) {
    Column(
        Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Les deux visages ne disent rien que la signature ne dise : la photo
        // est décorative, et TalkBack passe au texte.
        Image(
            painterResource(R.drawable.photo_founders),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(SupportViewMetrics.portraitSide)
                .clip(CircleShape)
                .border(2.dp, MemoBookColor.surface, CircleShape)
                .clearAndSetSemantics {},
        )

        // Le corps de texte, et non l'accroche de 14 : ce sont deux paragraphes
        // qu'on lit, pas une légende (Hugo, 15/09/2026).
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandText(SupportCopy.hello(firstName), MemoBookFont.body)
            SupportCopy.intro.forEach { BrandText(it, MemoBookFont.body) }
        }
    }
}

private object SupportViewMetrics {
    /** La photo des fondateurs, ronde. 112 sur la maquette — 7 rem. */
    val portraitSide = 112.dp
}

// MARK: - La recherche

/**
 * Le champ, et ce qu'il a trouvé.
 *
 * **Sous le chapeau et au-dessus des paquets**, là où Hugo l'a demandé
 * (16/09/2026) : on lit qui nous parle, puis on cherche, puis on parcourt.
 *
 * **Le résultat est vivant** : le modèle refiltre à chaque frappe, et l'écran
 * s'anime plutôt que de sauter — quarante-cinq lignes qui disparaissent d'un
 * coup se lisent comme un écran qui s'est vidé.
 */
@Composable
private fun SupportSearch(state: SupportModel.State, onSearchChange: (String) -> Unit) {
    Column(
        Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        BrandSearchField(SupportCopy.searchPlaceholder, value = state.search, onValueChange = onSearchChange)

        if (state.hasNoResults) {
            BrandNotice(SupportCopy.searchEmpty(state.search), tone = BrandNotice.Tone.Information)
        } else if (state.isSearching) {
            BrandText(
                SupportCopy.searchResults(state.resultCount),
                MemoBookFont.caption,
                // Le compte change à chaque frappe : TalkBack le relit sans
                // qu'on y revienne.
                Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                color = MemoBookColor.inkMuted,
            )
        }
    }
}

// MARK: - Les sujets courants

/**
 * Les neuf paquets de la foire aux questions, chacun dans son groupe.
 *
 * Un groupe par thème et non une seule liste de quarante-cinq lignes : on ne
 * cherche pas une réponse en lisant tout, on cherche d'abord le rayon.
 */
@Composable
private fun SupportTopics(state: SupportModel.State, onOpen: (FaqEntry) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
        // Plus de chapeau « Sujets courants » au-dessus des paquets (Clara,
        // 17/09/2026) : chaque paquet porte son titre, **en surtitre** — Sora
        // Semibold 12, gris, capitales —, le même dessin que « Nous contacter ».
        state.visibleTopics.forEach { category ->
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                SupportSectionTitle(category.title)
                BrandRowGroup {
                    category.entries.forEach { entry -> +BrandRow(entry.question) { onOpen(entry) } }
                }
            }
        }
    }
}

// MARK: - Nous contacter

/**
 * Les deux questions qui mènent à nous écrire, et la ligne qui y mène
 * directement.
 *
 * La ligne directe est en dernier, et c'est l'ordre qui compte : on propose
 * d'abord les deux réponses qui évitent d'écrire, on ouvre le formulaire
 * ensuite.
 */
@Composable
private fun SupportContact(state: SupportModel.State, onWrite: (FaqEntry?) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        SupportSectionTitle(SupportCopy.contactSection)
        BrandRowGroup {
            // Les deux questions se filtrent comme les autres… et **ouvrent le
            // formulaire**, pas une réponse : on est là pour écrire (Hugo,
            // 17/09/2026). Leur chapeau est une phrase, celle de
            // `SupportCopy.Contact.brief`.
            state.visibleContact?.entries.orEmpty().forEach { entry -> +BrandRow(entry.question) { onWrite(entry) } }
            // …mais la ligne qui mène au formulaire **reste toujours**. C'est
            // la sortie de secours d'une recherche qui ne trouve rien, et c'est
            // précisément là qu'on en a besoin.
            +BrandRow(SupportCopy.writeToUs) { onWrite(null) }
        }
    }
}

/**
 * Le chapeau d'une des sections de l'écran.
 *
 * La maquette écrit le titre en minuscules et le dessine en capitales : c'est
 * une casse d'affichage. TalkBack lit donc le titre tel qu'il est écrit au lieu
 * de l'épeler.
 */
@Composable
private fun SupportSectionTitle(title: String) {
    BrandText(
        title.uppercase(Locale.FRENCH),
        MemoBookFont.sectionOverline,
        Modifier.semantics {
            heading()
            contentDescription = title
        },
        color = MemoBookColor.inkMuted,
    )
}

/**
 * Ce que la feuille de support peut porter.
 *
 * Une seule feuille pour les deux, et non deux feuilles empilées : le design
 * system l'interdit, et « J'ai encore une question » doit pouvoir mener au
 * formulaire depuis une réponse.
 */
sealed interface SupportSheetRoute {
    val id: String

    data class Answer(val entry: FaqEntry) : SupportSheetRoute {
        override val id: String get() = entry.id
    }

    /**
     * Le formulaire, ouvert tel quel ou **au sujet** d'une des deux questions
     * de « Nous contacter » — qui donne alors son titre et son chapeau court.
     */
    data class Contact(val about: FaqEntry?) : SupportSheetRoute {
        override val id: String get() = about?.let { "faq.contact.${it.id}" } ?: "faq.contact"
    }
}

@Preview(locale = "fr-rFR", name = "Support et retours", heightDp = 1400)
@Composable
private fun SupportViewPreview() {
    CompositionLocalProvider(LocalTravellerFirstName provides "Margaux") {
        Box(Modifier.background(MemoBookColor.background)) {
            SupportView(remember { SupportModel() }, onBack = {})
        }
    }
}

@Preview(locale = "fr-rFR", name = "Support et retours — AX3", heightDp = 1400, fontScale = 2f)
@Composable
private fun SupportViewLargePreview() {
    CompositionLocalProvider(LocalTravellerFirstName provides "Margaux") {
        SupportView(remember { SupportModel() }, onBack = {})
    }
}
