package com.memobook.feature.home

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import coil3.compose.AsyncImage
import com.memobook.core.HomeFeed
import com.memobook.core.Trip
import com.memobook.design.BrandAlert
import com.memobook.design.BrandButton
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.HomeIntent
import kotlinx.coroutines.launch

/**
 * Par où commence un carnet. Jumeau de `NewNotebookSheet`
 * (`Home/NewNotebookSheets.swift`).
 *
 * Trois portes, et rien d'autre : partir de zéro, rejoindre l'aventure de
 * quelqu'un, ou reprendre ce qu'une autre app sait déjà du voyage. Elles sont
 * **du même poids** — trois cartes identiques, aucune mise en avant — parce
 * qu'aucune n'est le chemin normal : elles dépendent de ce que la personne a
 * déjà, pas de ce qu'on préfère qu'elle fasse.
 *
 * **La feuille ne navigue pas**, comme l'accueil qui la présente : elle émet
 * une [HomeIntent] et se referme. La seule exception est « Rejoins une
 * aventure », qui a besoin d'un code avant de mener quelque part : elle ouvre
 * alors [JoinTripSheet] par-dessus elle, qui fait vérifier le code par
 * l'accueil ([HomeModel.join]) — c'est le voyage retrouvé qui devient
 * l'intention.
 *
 * @param resumableTrip le carnet que la dernière ligne propose de retrouver :
 *   celui qui est ouvert, sinon le prochain voyage prévu. `null` quand il n'y a
 *   ni l'un ni l'autre — la ligne et son filet disparaissent alors ensemble,
 *   plutôt que de laisser un séparateur qui ne sépare plus rien.
 * @param join fait vérifier un code d'accès — voir [JoinTripSheet].
 */
@Composable
fun NewNotebookSheet(
    resumableTrip: Trip?,
    join: suspend (String) -> JoinOutcome = { JoinOutcome.NotFound },
    onIntent: (HomeIntent) -> Unit,
) {
    var isJoining by remember { mutableStateOf(false) }
    val dismiss = LocalBrandSheetDismiss.current

    /**
     * Referme la feuille, **puis** dit ce qu'on a choisi : la destination
     * s'ouvre derrière une feuille qui descend, et non sous elle.
     */
    fun choose(intent: HomeIntent) {
        dismiss()
        onIntent(intent)
    }

    BrandSheet(
        "Nouveau carnet",
        subtitle = "L’aventure commence maintenant",
        titleAlignment = BrandSheet.TitleAlignment.Centered,
    ) {
        // 12 entre les cartes, et non 16 : ce sont trois formulations d'un même
        // choix, pas trois blocs indépendants. Elles doivent se lire comme une
        // liste.
        Column(
            Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            NewNotebookOptionCard(
                icon = NewNotebookOptionCard.Icon.Brand(R.drawable.icon_plus),
                title = "À partir de zéro",
                detail = "Raconte ton histoire, simplement",
            ) { choose(HomeIntent.CreateTrip) }

            NewNotebookOptionCard(
                icon = NewNotebookOptionCard.Icon.Brand(R.drawable.icon_link),
                title = "Rejoins une aventure",
                // ⚠️ La maquette vouvoie ici (« Écrivez »), alors que l'app
                // tutoie partout ailleurs. Même cas que les cartes du Welcome
                // (T8 de `docs/archive/ui-development-journal.md`) : on
                // implémente la copie de Figma en l'état, la correction se fait
                // dans Figma.
                detail = "Écrivez l’aventure à plusieurs",
            ) { isJoining = true }

            // ⚠️ **Pas dans la V1** (Hugo, 16/09/2026). La porte reste dessinée
            // — elle dit ce que l'app saura faire — mais elle s'efface et
            // annonce son délai, au lieu de mener à une intention que `RootView`
            // ignore en silence.
            NewNotebookOptionCard(
                icon = NewNotebookOptionCard.Icon.ThirdParty(R.drawable.icon_polarsteps),
                title = "Importe depuis Polarsteps",
                detail = "On récupérera toutes tes étapes",
                availability = NewNotebookOptionCard.Availability.ComingSoon,
            ) { choose(HomeIntent.ImportFromPolarsteps) }

            if (resumableTrip != null) {
                ResumeSection(resumableTrip) { choose(HomeIntent.OpenTrip(resumableTrip.id)) }
            }
        }
    }

    BrandSheetHost(isPresented = isJoining, onDismissRequest = { isJoining = false }) {
        JoinTripSheet(join = join) { tripId ->
            // La feuille du code se referme elle-même ; celle-ci s'efface
            // derrière, et on arrive dans le voyage qu'on vient de rejoindre
            // plutôt que sur le choix qu'on vient de faire.
            dismiss()
            onIntent(HomeIntent.OpenTrip(tripId))
        }
    }
}

/**
 * Le carnet déjà commencé, séparé des trois portes par un filet court.
 *
 * Il n'est pas une quatrième option : c'est un rappel. Le filet dit exactement
 * ça — au-dessus on commence quelque chose, en dessous on revient à ce qui
 * existe.
 */
@Composable
private fun ResumeSection(trip: Trip, onOpen: () -> Unit) {
    Column(
        Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                .padding(vertical = MemoBookSpacing.xs - 4.dp)
                .width(48.dp)
                .height(1.dp)
                .background(MemoBookColor.hairline)
                .clearAndSetSemantics {},
        )

        NewNotebookOptionCard(
            icon = NewNotebookOptionCard.Icon.Cover(trip),
            title = NewNotebookCopy.resumeTitle(trip),
            detail = NewNotebookCopy.resumeDetail(trip),
            action = onOpen,
        )
    }
}

/** Les phrases de la dernière ligne, qui dépendent du voyage. */
internal object NewNotebookCopy {
    /**
     * Un carnet ouvert se **reprend** ; un voyage qui n'a pas commencé
     * s'annonce. Deux situations, deux phrases : « reprendre » devant un voyage
     * qui n'a pas encore eu lieu ne veut rien dire.
     */
    fun resumeTitle(trip: Trip): String =
        if (trip.stage.isOngoing) "Reprendre ton carnet en cours" else "Ton voyage en approche"

    /**
     * La précision nomme le voyage : c'est elle qui dit *lequel* on reprend.
     *
     * ⚠️ « commence bientôt » ne vient pas de la maquette, qui ne montre que le
     * cas du carnet en cours — à confirmer avec Clara, en même temps que
     * l'usage éventuel de la date de départ.
     */
    fun resumeDetail(trip: Trip): String =
        if (trip.stage.isOngoing) "${trip.title} n’est pas terminé" else "${trip.title} commence bientôt"
}

// MARK: - Une porte

/**
 * Une des façons de commencer : une icône, ce qu'elle fait, et la flèche qui
 * dit que ça mène quelque part.
 *
 * Le contour est **vert** et non gris : ces cartes ne rangent pas de
 * l'information, elles proposent d'agir. C'est la seule chose qui les
 * distingue d'une carte de contenu, et c'est assez.
 */
@Composable
fun NewNotebookOptionCard(
    icon: NewNotebookOptionCard.Icon,
    title: String,
    detail: String,
    modifier: Modifier = Modifier,
    availability: NewNotebookOptionCard.Availability = NewNotebookOptionCard.Availability.Available,
    action: () -> Unit,
) {
    val isComingSoon = availability == NewNotebookOptionCard.Availability.ComingSoon
    // Le gris des portes fermées : contour et titre. Le vert dit « appuie », et
    // il n'y a rien à appuyer.
    val accentColor = if (isComingSoon) MemoBookColor.disabledOutline else MemoBookColor.action
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val label = if (isComingSoon) "$title. $detail. ${NewNotebookOptionCard.comingSoonLabel}" else "$title. $detail"

    Box(modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                // Le même fond que les autres cartes : c'est le contenu qui
                // s'efface, pas la carte qui change de couleur.
                .background(MemoBookColor.surface, shape)
                .border(1.dp, accentColor, shape)
                // On ne désactive pas la carte : `enabled = false` emporterait
                // la pastille dans le gris avec le reste. On lui retire son geste
                // et son rôle — c'est une annonce, pas une action.
                .then(if (isComingSoon) Modifier else Modifier.cardButton(action))
                .clearAndSetSemantics {
                    contentDescription = label
                    if (!isComingSoon) role = Role.Button
                }
                .padding(MemoBookSpacing.xs + 4.dp)
                // À demi effacée : assez pour que la carte recule franchement
                // derrière les deux autres, pas assez pour qu'on cesse de lire ce
                // qu'elle promet. Le logo de Polarsteps s'efface avec le reste —
                // pas de teinte, une marque repeinte n'est plus la marque — et le
                // voile ne touche que le contenu : la pastille, posée
                // par-dessus, reste franche.
                .alpha(if (isComingSoon) 0.45f else 1f),
        ) {
            OptionContent(icon, title, detail, accentColor, isComingSoon)
        }

        // La pastille qui dit quand. Posée **à cheval sur le coin**, comme les
        // pastilles de sélection des couvertures : dans la carte, elle se serait
        // lue comme une ligne de plus.
        if (isComingSoon) {
            BrandText(
                NewNotebookOptionCard.comingSoonLabel,
                MemoBookFont.overline,
                // À l'encre pleine sur le crème : c'est la seule chose de la
                // carte qui doit rester franchement lisible.
                color = MemoBookColor.ink,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(end = MemoBookSpacing.snug)
                    .offset(y = -MemoBookSpacing.xs)
                    .background(MemoBookColor.surface, RoundedCornerShape(percent = 50))
                    .border(1.dp, MemoBookColor.separator, RoundedCornerShape(percent = 50))
                    .padding(horizontal = MemoBookSpacing.xs, vertical = MemoBookSpacing.xs / 2)
                    .clearAndSetSemantics {},
            )
        }
    }
}

object NewNotebookOptionCard {
    /** Ce qui se pose dans la plaque de gauche. */
    sealed interface Icon {
        /**
         * Une icône du jeu de marque. Teintée à l'encre par la carte : les
         * tracés sont livrés dans une couleur figée dont on ne dépend pas.
         */
        data class Brand(@param:DrawableRes val drawable: Int) : Icon

        /**
         * La marque d'un service tiers, redessinée à l'encre de MemoBook pour
         * tenir dans la plaque. Elle garde **ses** couleurs telles qu'elles sont
         * dessinées — jamais de teinte : une marque qu'on repeint n'est plus la
         * marque. À ne pas confondre avec les logos de `ConnectorsSheet`, qui
         * sont les vrais logotypes en couleurs.
         */
        data class ThirdParty(@param:DrawableRes val drawable: Int) : Icon

        /**
         * La couverture d'un voyage, à la place de l'icône : la ligne parle d'un
         * carnet précis, autant le montrer.
         */
        data class Cover(val trip: Trip) : Icon
    }

    /** Est-ce qu'on peut y aller, ou seulement l'entrevoir. */
    enum class Availability {
        /** La porte s'ouvre. Le cas de toutes, sauf une. */
        Available,

        /**
         * La porte est dessinée mais ne s'ouvre pas encore : elle **s'efface**
         * — contour et titre au gris des contrôles inactifs, contenu à demi
         * transparent — et porte une pastille qui dit quand.
         *
         * Au gris et non au beige (Hugo, 18/09/2026) : le beige la faisait
         * ressembler à une carte d'un autre genre, alors qu'elle est la même
         * carte que les deux autres, en retrait. Elle reste **lisible** — on la
         * laisse justement pour qu'elle se lise, et une pastille posée sur un
         * texte qu'on ne déchiffre plus n'expliquerait rien. Elle sort en
         * revanche du parcours au doigt et de TalkBack comme bouton — c'est une
         * annonce, pas une action.
         */
        ComingSoon,
    }

    const val comingSoonLabel = "Bientôt disponible"
}

/**
 * En taille accessible le texte prend toute la largeur : lui laisser deux
 * colonnes de plus ne lui laisserait que deux mots par ligne.
 */
@Composable
private fun OptionContent(
    icon: NewNotebookOptionCard.Icon,
    title: String,
    detail: String,
    accentColor: androidx.compose.ui.graphics.Color,
    isComingSoon: Boolean,
) {
    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                OptionPlate(icon)
                Spacer(Modifier.weight(1f))
                OptionArrow(accentColor, isComingSoon)
            }
            OptionText(title, detail, accentColor)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs + 4.dp), verticalAlignment = Alignment.CenterVertically) {
            OptionPlate(icon)
            OptionText(title, detail, accentColor, Modifier.weight(1f))
            OptionArrow(accentColor, isComingSoon)
        }
    }
}

@Composable
private fun OptionText(title: String, detail: String, accentColor: androidx.compose.ui.graphics.Color, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Le vert d'action, comme le contour : le titre **est** l'action — et le
        // gris quand il n'y en a pas encore.
        BrandText(title, MemoBookFont.bodySemibold, color = accentColor)
        BrandText(detail, MemoBookFont.caption, color = MemoBookColor.inkMuted)
    }
}

/**
 * La plaque d'icône du design system : 44 × 40, rayon 12, bleu à 30 %. Voir
 * « Fond d'icône » dans `docs/archive/ui-development-journal.md`. Le glyphe
 * remplit presque la plaque : dessiné à 20, il n'en faisait que la moitié —
 * voir `MemoBookSpacing.contentIcon`.
 */
@Composable
private fun OptionPlate(icon: NewNotebookOptionCard.Icon) {
    val plateWidth = scaled(44.dp)
    val plateHeight = scaled(40.dp)
    val glyphSide = scaled(28.dp)
    val plateShape = RoundedCornerShape(12.dp)

    when (icon) {
        is NewNotebookOptionCard.Icon.Brand, is NewNotebookOptionCard.Icon.ThirdParty -> Box(
            Modifier
                .size(plateWidth, plateHeight)
                .background(MemoBookColor.outline.copy(alpha = 0.3f), plateShape),
            contentAlignment = Alignment.Center,
        ) {
            val drawable = if (icon is NewNotebookOptionCard.Icon.Brand) icon.drawable else (icon as NewNotebookOptionCard.Icon.ThirdParty).drawable
            Image(
                painterResource(drawable),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                colorFilter = if (icon is NewNotebookOptionCard.Icon.Brand) ColorFilter.tint(MemoBookColor.ink) else null,
                modifier = Modifier.size(glyphSide),
            )
        }

        is NewNotebookOptionCard.Icon.Cover -> Box(
            Modifier
                .size(plateWidth, plateHeight)
                .clip(plateShape),
        ) {
            TripCoverPlaceholder(icon.trip.id, Modifier.fillMaxSize())
            icon.trip.coverPhotoUrl?.let { url ->
                AsyncImage(
                    model = url.toString(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
    }
}

/**
 * `IconArrowRight` et non `IconArrow` : celle du jeu de marque pointe à
 * **gauche**, c'est une flèche de retour.
 *
 * La flèche dit « ça mène quelque part » : elle s'efface quand ça ne mène
 * encore nulle part, plutôt que de promettre en gris.
 */
@Composable
private fun OptionArrow(accentColor: androidx.compose.ui.graphics.Color, isComingSoon: Boolean) {
    Image(
        painterResource(R.drawable.icon_arrow_right),
        contentDescription = null,
        colorFilter = ColorFilter.tint(accentColor),
        modifier = Modifier
            .size(scaled(24.dp))
            .alpha(if (isComingSoon) 0f else 1f),
    )
}

// MARK: - Rejoindre

/** Le seul champ de la feuille. */
private enum class JoinField { Code }

/**
 * Entrer le code d'accès d'un voyage qui existe déjà. Jumeau de
 * `JoinTripSheet` (`Home/NewNotebookSheets.swift`).
 *
 * Un seul champ, et le geste qui le remplit : un code d'accès arrive presque
 * toujours par message, donc il se **colle** — le taper à la main est le cas
 * rare, pas l'inverse. C'est pour ça que « Coller » est posé à côté du champ
 * et non caché dans le menu d'un appui long.
 *
 * @param join fait vérifier le code saisi, une fois nettoyé.
 * @param onJoined le voyage est rejoint : son identifiant.
 */
@Composable
fun JoinTripSheet(join: suspend (String) -> JoinOutcome, onJoined: (String) -> Unit) {
    val context = LocalContext.current
    val dismiss = LocalBrandSheetDismiss.current
    val scope = rememberCoroutineScope()

    var code by rememberSaveable { mutableStateOf("") }

    // Le code part au serveur : le bouton tourne, et un second appui ne repart
    // pas.
    var isJoining by remember { mutableStateOf(false) }

    // L'alerte « Oups, voyage introuvable » (`3561:21647`).
    var showsNotFound by remember { mutableStateOf(false) }

    // Ce que le serveur a répondu d'autre qu'un code inconnu.
    var failure by remember { mutableStateOf<String?>(null) }

    // Le presse-papiers a quelque chose à coller. Relu à l'ouverture et au
    // retour dans l'app — c'est là qu'on revient du message où on a copié le
    // code. `hasPrimaryClip` ne lit pas le contenu : il ne déclenche donc aucun
    // avis de lecture du presse-papiers.
    var canPaste by remember { mutableStateOf(JoinTripClipboard.hasText(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { canPaste = JoinTripClipboard.hasText(context) }

    var focus by remember { mutableStateOf<JoinField?>(null) }

    fun updateCode(value: String) {
        // Un code d'accès s'écrit en capitales et sans séparateur. On le nettoie
        // **à la frappe** plutôt que de le refuser à l'envoi : collé depuis un
        // message, il arrive presque toujours avec une espace ou un retour à la
        // ligne au bout.
        val cleaned = JoinTripCode.normalized(value)
        if (cleaned != code) failure = null
        code = cleaned
    }

    fun submit() {
        if (code.isEmpty() || isJoining) return
        focus = null
        failure = null
        isJoining = true
        scope.launch {
            val outcome = join(code)
            isJoining = false
            when (outcome) {
                is JoinOutcome.Joined -> {
                    dismiss()
                    onJoined(outcome.tripId)
                }
                JoinOutcome.NotFound -> showsNotFound = true
                is JoinOutcome.Failed -> failure = outcome.message
            }
        }
    }

    /**
     * Colle le presse-papiers dans le champ, nettoyé.
     *
     * Le bouton lit le presse-papiers directement : Android affiche alors son
     * avis « MemoBook a collé depuis le presse-papiers », qui reste rare — on ne
     * le lit que sur ce geste-là. Le code est complet : on rend l'écran plutôt
     * que de garder le clavier devant le bouton qui suit.
     */
    fun paste() {
        val pasted = JoinTripClipboard.text(context) ?: return
        updateCode(pasted)
        focus = null
    }

    BrandKeyboardDismissBar {
        BrandSheet(
            "Rejoindre",
            subtitle = "Colle ici le code d’accès d’un voyage existant",
            titleAlignment = BrandSheet.TitleAlignment.Centered,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                JoinCodeEntry(
                    code = code,
                    onCodeChange = ::updateCode,
                    focus = focus,
                    onFocusChange = { focus = it },
                    canPaste = canPaste,
                    onPaste = ::paste,
                )

                AnimatedVisibility(
                    visible = failure != null,
                    enter = fadeIn(SwiftMotion.snappy(0.2f)),
                    exit = fadeOut(SwiftMotion.snappy(0.2f)),
                ) {
                    BrandText(
                        failure.orEmpty(),
                        MemoBookFont.notification,
                        color = MemoBookColor.error,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                BrandButton("Rejoindre", isLoading = isJoining, fillsWidth = true, enabled = code.isNotEmpty(), action = ::submit)

                // La sortie, en rouge et sans cadre : elle annule ce qu'on était
                // en train de faire, elle ne le fait pas. Même dessin que
                // « Supprimer mon compte » au bas du profil.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = MemoBookSpacing.minimumTapTarget)
                        .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = dismiss),
                    contentAlignment = Alignment.Center,
                ) {
                    BrandText("Annuler", MemoBookFont.button, color = MemoBookColor.error, textAlign = TextAlign.Center)
                }
            }
        }
    }

    // L'alerte **du système** sur iOS, et non une feuille de la marque : la
    // maquette dessine celle d'Apple (R6). « Réessayer » rend le champ pour
    // corriger la faute de frappe ; « Annuler » renonce.
    BrandAlert(
        isPresented = showsNotFound,
        title = JoinCopy.notFoundTitle,
        message = JoinCopy.notFoundMessage,
        actions = listOf(
            BrandAlert.Action(JoinCopy.cancel, BrandAlert.Role.Cancel) {
                showsNotFound = false
                dismiss()
            },
            BrandAlert.Action(JoinCopy.retry) {
                showsNotFound = false
                focus = JoinField.Code
            },
        ),
        onDismissRequest = { showsNotFound = false },
    )
}

/**
 * Le champ et son bouton « Coller », côte à côte.
 *
 * Les deux n'ont pas la même hauteur — 56 pour un champ, 50 pour un bouton — et
 * c'est voulu : ce sont deux hauteurs du design system. Ils s'alignent donc sur
 * leur milieu.
 *
 * En taille accessible, « Coller » passe sous le champ : à côté, il ne
 * resterait au code que la place de deux caractères.
 */
@Composable
private fun JoinCodeEntry(
    code: String,
    onCodeChange: (String) -> Unit,
    focus: JoinField?,
    onFocusChange: (JoinField?) -> Unit,
    canPaste: Boolean,
    onPaste: () -> Unit,
) {
    val field: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            "Code d’accès",
            code,
            onCodeChange,
            field = JoinField.Code,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            labelPlacement = BrandTextField.LabelPlacement.Hidden,
            placeholder = "JHKFDA",
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.Characters,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { onFocusChange(null) }),
        )
    }

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            field(Modifier.fillMaxWidth())
            BrandButton("Coller", style = BrandButton.Style.Secondary, fillsWidth = true, enabled = canPaste, action = onPaste)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            field(Modifier.weight(1f))
            BrandButton("Coller", style = BrandButton.Style.Secondary, enabled = canPaste, action = onPaste)
        }
    }
}

/** Le nettoyage d'un code d'accès — à part, pour qu'il se teste. */
internal object JoinTripCode {
    /** Un code d'accès s'écrit en capitales et sans séparateur. */
    fun normalized(value: String): String = value.uppercase().filter { it.isLetterOrDigit() }
}

/**
 * Le presse-papiers du système, lu pour « Coller ». `UIPasteboard` sur iOS ; ici
 * le `ClipboardManager` d'Android, dont `hasPrimaryClip` ne lit pas le contenu.
 */
private object JoinTripClipboard {
    private fun manager(context: Context): ClipboardManager? =
        context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    fun hasText(context: Context): Boolean {
        val manager = manager(context) ?: return false
        if (!manager.hasPrimaryClip()) return false
        val description = manager.primaryClipDescription ?: return false
        return description.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN) ||
            description.hasMimeType(ClipDescription.MIMETYPE_TEXT_HTML)
    }

    fun text(context: Context): String? {
        val clip = manager(context)?.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(context)?.toString()
    }
}

/**
 * L'alerte d'un code qui ne mène nulle part, recopiée du nœud `3561:21647` au
 * caractère près (R8).
 */
object JoinCopy {
    const val notFoundTitle = "Oups, voyage introuvable"
    const val notFoundMessage = "On ne trouve aucun voyage associé à ce code. Une petite faute de saisie ?"
    const val cancel = "Annuler"
    const val retry = "Réessayer"
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Nouveau carnet", widthDp = 390, heightDp = 700)
@Composable
private fun NewNotebookSheetPreview() {
    SheetPreviewFrame { NewNotebookSheet(resumableTrip = HomeFeed.fixture.ongoingTrips.firstOrNull()) {} }
}

@Preview(locale = "fr-rFR", name = "Nouveau carnet — aucun carnet", widthDp = 390, heightDp = 600)
@Composable
private fun NewNotebookSheetEmptyPreview() {
    SheetPreviewFrame { NewNotebookSheet(resumableTrip = null) {} }
}

@Preview(locale = "fr-rFR", name = "Nouveau carnet — AX3", widthDp = 390, heightDp = 1000, fontScale = 2f)
@Composable
private fun NewNotebookSheetAccessibilityPreview() {
    SheetPreviewFrame { NewNotebookSheet(resumableTrip = HomeFeed.fixture.ongoingTrips.firstOrNull()) {} }
}

@Preview(locale = "fr-rFR", name = "Rejoindre", widthDp = 390, heightDp = 500)
@Composable
private fun JoinTripSheetPreview() {
    SheetPreviewFrame { JoinTripSheet(join = { JoinOutcome.NotFound }, onJoined = {}) }
}

@Composable
private fun SheetPreviewFrame(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) { content() }
}
