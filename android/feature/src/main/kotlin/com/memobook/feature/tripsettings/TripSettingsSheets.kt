package com.memobook.feature.tripsettings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.AsyncImagePainter
import coil3.compose.rememberAsyncImagePainter
import com.memobook.core.BookCopy
import com.memobook.core.NarrationPace
import com.memobook.core.TripNotificationPreferences
import com.memobook.core.TripTheme
import com.memobook.design.BrandAlert
import com.memobook.design.BrandAvatar
import com.memobook.design.BrandButton
import com.memobook.design.BrandDateField
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandSwipeAction
import com.memobook.design.BrandSwipeDrawer
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.BrandToggleCard
import com.memobook.design.ErrorBanner
import com.memobook.design.LocalBrandSheetDismiss
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import com.memobook.feature.notifications.rememberNotificationPermissionRequest
import com.memobook.feature.notifications.LocalPushNotifications
import com.memobook.feature.notifications.NotificationAuthorization
import com.memobook.feature.notifications.PushNotifications

// Les feuilles des paramètres d'un voyage. Jumeau de
// `TripSettings/TripSettingsSheets.swift` ; l'énumération des feuilles,
// `TripSettingsSheet`, est dans `Navigation.kt` avec les autres routes.
//
// **Elles règlent sans quitter l'écran**, et c'est tout leur intérêt : on est
// en plein voyage, on veut décaler une date ou couper une alerte, et on ne
// veut pas traverser trois écrans pour ça. Chacune tient la hauteur de son
// contenu (`BrandSheet`), fait reculer l'écran du dessous, et se referme au
// glissé.
//
// **Elles enregistrent en se fermant, jamais avant.** Enfin, presque : c'est
// vrai des quatre qui n'ont pas de bouton — dates, rythme, notifications,
// co-voyageurs —, où chaque geste part seul, comme les lignes de réglages
// partout ailleurs dans l'app. Le thème, lui, porte un « Valider » parce que
// la maquette lui en donne un : on y **tape** un texte, et un champ qui
// s'enregistre à chaque lettre enverrait dix requêtes par mot.

// MARK: - Dates

/**
 * « Dates » — les deux bornes du voyage, chacune ouvrant le sélecteur
 * par-dessus la feuille.
 *
 * **Une date posée se change, elle ne s'efface plus** (Clara, 26/09/2026) :
 * pas de croix sur les deux lignes. On pouvait retirer le départ d'un voyage
 * déjà configuré, ce qui n'a pas de sens — c'est lui qui range le voyage dans
 * « à venir » ou « en cours ».
 */
@Composable
internal fun TripDatesSheet(model: TripSettingsModel) {
    val zone = remember { ZoneId.systemDefault() }

    // Les dates **de la feuille**, et non celles du modèle.
    //
    // Les deux se bornent l'une l'autre : poser une fin avant le début est
    // refusé par le serveur, et par le sélecteur lui-même. On tient donc les
    // deux ensemble ici, et on n'envoie qu'une fois la paire cohérente.
    var start by remember { mutableStateOf(model.state.value.settings?.startDate) }
    var end by remember { mutableStateOf(model.state.value.settings?.endDate) }
    val startDay = start?.atZone(zone)?.toLocalDate()
    val endDay = end?.atZone(zone)?.toLocalDate()

    BrandSheet(BookCopy.Dates.title) {
        // Un seul envoi pour les deux, et **au changement** : la feuille n'a
        // pas de bouton, c'est le geste qui vaut validation.
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            BrandDateField(
                BookCopy.Dates.start,
                date = startDay,
                onDateChange = { day ->
                    start = start.onDay(day, zone)
                    model.setDates(start = start, end = end)
                },
                // Une fin déjà posée borne le début : l'inverse n'a pas de
                // sens, et le serveur le refuserait.
                range = LocalDate.MIN..(endDay ?: LocalDate.MAX),
                isClearable = false,
            )

            BrandDateField(
                BookCopy.Dates.end,
                date = endDay,
                onDateChange = { day ->
                    end = end.onDay(day, zone)
                    model.setDates(start = start, end = end)
                },
                range = (startDay ?: LocalDate.MIN)..LocalDate.MAX,
                isClearable = false,
            )
        }
    }
}

/**
 * Le jour choisi, **à l'heure de la date qu'il remplace** : le sélecteur
 * d'iOS ne change que le jour d'une `Date`, et garde son heure — une date du
 * serveur posée à minuit UTC reste à minuit UTC. Une date neuve prend l'heure
 * qu'il est, comme le `.now` que `BrandDateField` pose sur iOS en s'ouvrant.
 */
private fun Instant?.onDay(day: LocalDate?, zone: ZoneId): Instant? {
    day ?: return null
    val time = this?.atZone(zone)?.toLocalTime() ?: LocalTime.now(zone)
    return day.atTime(time).atZone(zone).toInstant()
}

// MARK: - Rythme du récit

/** « Rythme du récit » — cinq cadences, une seule choisie. */
@Composable
internal fun TripPaceSheet(model: TripSettingsModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val dismiss = LocalBrandSheetDismiss.current
    val scope = rememberCoroutineScope()

    // Ce qu'on vient de toucher, le temps que la feuille parte — la coche se
    // pose sur **cette** valeur, pas sur celle du modèle, dont l'aller-retour
    // ne doit pas la faire clignoter. Même mécanique que « Genre ».
    var chosen by remember { mutableStateOf<NarrationPace?>(null) }

    // Coche, enregistre, puis referme — dans cet ordre. Choisir, c'est finir :
    // la feuille n'a rien d'autre à proposer, et la garder ouverte obligerait
    // à la refermer pour voir la valeur posée sur la ligne. Mais on voit la
    // coche avant (Hugo, 18/09/2026). Un second toucher pendant l'attente ne
    // fait rien : le premier est déjà parti.
    fun select(pace: NarrationPace) {
        if (chosen != null) return
        chosen = pace
        model.setPace(pace)
        scope.launch {
            delay(BrandOptionRow.lingerBeforeDismiss)
            dismiss()
        }
    }

    BrandSheet(BookCopy.Pace.title, subtitle = BookCopy.Pace.subtitle) {
        BrandOptionGroup {
            NarrationPace.selectable.forEach { pace ->
                BrandOptionRow(
                    pace.displayName,
                    isSelected = (chosen ?: state.settings?.narrationPace) == pace,
                    subtitle = pace.detail,
                ) {
                    select(pace)
                }
            }
        }
    }
}

// MARK: - Notifications

/** « Notifications » — les quatre alertes du voyage, une carte chacune. */
@Composable
internal fun TripNotificationsSheet(model: TripSettingsModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val settings = state.settings
    val pushNotifications = LocalPushNotifications.current
    val askSystem = rememberNotificationPermissionRequest()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Tout est coupé dans les Paramètres du téléphone : les quatre cartes
    // enregistrent toujours, mais rien n'arrivera tant qu'on n'y retourne pas.
    val isBlockedBySystem = pushNotifications?.authorization == NotificationAuthorization.Denied

    // Le chapeau de la maquette, et sur un voyage partagé une phrase de plus :
    // ces alertes sont **les tiennes** (D13, 19/10/2026). Seul, on n'a
    // personne à qui les comparer, et la phrase n'aurait rien à dire.
    val subtitle = BookCopy.Notifications.subtitle(trip = settings?.name.orEmpty())
    val headerParagraphs = if (settings?.guests.isNullOrEmpty()) {
        listOf(subtitle)
    } else {
        listOf(subtitle, BookCopy.Notifications.personalNote)
    }

    // La bascule d'une alerte : elle lit le modèle et lui repasse le bloc
    // entier, parce que c'est le bloc entier que la route accepte.
    fun toggle(isOn: Boolean, set: (TripNotificationPreferences, Boolean) -> TripNotificationPreferences) {
        val preferences = model.state.value.settings?.notifications ?: return
        model.setNotificationPreferences(set(preferences, isOn))
        // Allumer une alerte sans avoir jamais répondu au téléphone : c'est le
        // moment de lui poser la question — sans quoi l'alerte serait réglée
        // pour rien.
        if (isOn && pushNotifications?.authorization == NotificationAuthorization.NotDetermined) {
            scope.launch { pushNotifications.requestAuthorization(askSystem) }
        }
    }

    // On revient peut-être des Paramètres : ce que le téléphone autorise a pu
    // changer.
    LaunchedEffect(pushNotifications) { pushNotifications?.refreshAuthorization() }

    BrandSheet(BookCopy.Notifications.title, paragraphs = headerParagraphs) {
        Column(
            // Les quatre bascules **agissent** : les toucher avant que les
            // réglages soient là enverrait un état qu'on n'a pas lu.
            Modifier.blocksTouches(settings == null),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        ) {
            // L'interrupteur maître est baissé : les quatre cartes restent
            // réglables — on prépare ce qu'on recevra —, mais l'écran dit que
            // rien ne partira d'ici là. Sans cette phrase, on croit à quatre
            // interrupteurs morts.
            if (isBlockedBySystem) {
                BrandNotice(TripNotificationsCopy.systemDeniedNotice) {
                    BrandButton(TripNotificationsCopy.openSettings, style = BrandButton.Style.Link) {
                        PushNotifications.openSystemSettings(context)
                    }
                }
            } else if (settings?.wantsNotifications == false) {
                BrandNotice(BookCopy.Notifications.mutedNotice)
            }

            val preferences = settings?.notifications
            BrandToggleCard(
                title = BookCopy.Notifications.writingReminder,
                detail = BookCopy.Notifications.writingReminderDetail,
                isOn = preferences?.writingReminder ?: false,
                onIsOnChange = { isOn -> toggle(isOn) { p, on -> p.copy(writingReminder = on) } },
            )
            BrandToggleCard(
                title = BookCopy.Notifications.newStory,
                detail = BookCopy.Notifications.newStoryDetail,
                isOn = preferences?.newStory ?: false,
                onIsOnChange = { isOn -> toggle(isOn) { p, on -> p.copy(newStory = on) } },
            )
            BrandToggleCard(
                title = BookCopy.Notifications.weeklyDigest,
                detail = BookCopy.Notifications.weeklyDigestDetail,
                isOn = preferences?.weeklyDigest ?: false,
                onIsOnChange = { isOn -> toggle(isOn) { p, on -> p.copy(weeklyDigest = on) } },
            )
            BrandToggleCard(
                title = BookCopy.Notifications.tripEnd,
                detail = BookCopy.Notifications.tripEndDetail,
                isOn = preferences?.tripEndReminder ?: false,
                onIsOnChange = { isOn -> toggle(isOn) { p, on -> p.copy(tripEndReminder = on) } },
            )
        }
    }
}

/**
 * Ce que la feuille dit quand le téléphone refuse tout. `BookCopy` l'écrit pour
 * l'iPhone (« les réglages de ton iPhone ») : la copie est partagée, et
 * Android dit « téléphone » et « Paramètres » là où elle parle de la
 * plateforme. ⚠️ Pas dans la maquette — texte à relire par Clara, comme sur iOS.
 */
internal object TripNotificationsCopy {
    const val systemDeniedNotice =
        "Les notifications de MemoBook sont coupées dans les paramètres de ton téléphone : aucune de ces alertes ne t’arrivera."
    const val openSettings = "Ouvrir les paramètres"
}

// MARK: - Thème de l'aventure

/**
 * « Thème de l'aventure » — le même carrousel qu'à la création du voyage, et
 * le champ libre qu'il ouvre.
 *
 * **Le carrousel est celui de la création**, à la lettre : c'est la note
 * « Logique » du nœud — « les thèmes doivent venir de la même base de données
 * que lors de la création du voyage ». Un second jeu de thèmes ici ferait
 * dériver `memos.theme`, que l'agent de rédaction lit tel quel.
 */
@Composable
internal fun TripThemeSheet(model: TripSettingsModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val themes = state.themes
    val dismiss = LocalBrandSheetDismiss.current

    // Le focus appartient à l'écran, pas au champ — et une feuille à un champ
    // n'échappe pas à la règle.
    var focus by remember { mutableStateOf<ThemeField?>(null) }

    // Le thème choisi dans le carrousel, ou `null` quand c'est un texte libre
    // qui ne correspond à aucun.
    var selection by remember { mutableStateOf<TripTheme?>(null) }

    // Ce que le champ contient — **le nom d'un thème libre**, seulement
    // derrière « Autre ». Un thème de la rangée n'a rien à taper : son nom
    // est le thème (Hugo, 17/09/2026).
    var text by remember { mutableStateOf(model.state.value.settings?.theme.orEmpty()) }

    // Le champ n'existe que derrière « Autre » — et derrière un thème libre
    // déjà enregistré, que la rangée ne connaît pas : sans champ, on ne
    // pourrait ni le relire ni le corriger.
    val showsField = selection?.isOther == true || (selection == null && themes.isNotEmpty())

    // Ce que « Valider » enregistre : le nom du thème choisi, ou le texte
    // libre derrière « Autre ».
    val chosenTheme = selection?.takeIf { !it.isOther }?.name ?: text.trim()

    fun validate() {
        focus = null
        model.setTheme(chosenTheme)
        dismiss()
    }

    // Les thèmes viennent du serveur, et la rangée montre sa barre d'attente
    // le temps qu'ils arrivent. Sans effet s'ils sont déjà là.
    LaunchedEffect(model) {
        model.loadThemes()
        val loaded = model.state.value.themes
        // Le thème enregistré, s'il est dans la rangée ; sinon c'est un thème
        // libre, et « Autre » le porte.
        val known = loaded.firstOrNull { it.name == text }
        if (known != null) {
            selection = known
        } else if (text.isNotEmpty()) {
            selection = loaded.firstOrNull { it.isOther }
        }
    }

    BrandSheet(BookCopy.Theme.title, subtitle = BookCopy.Theme.subtitle) {
        Column(
            Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            if (themes.isEmpty()) {
                TripThemePickerPlaceholder()
            } else {
                TripThemePicker(
                    themes = themes,
                    selection = selection,
                    onSelectionChange = { selection = it },
                ) { theme ->
                    // « Autre » ouvre la saisie libre, avec le clavier ; un
                    // thème de la rangée referme le champ — il n'y a plus que
                    // « Valider ».
                    if (theme.isOther) {
                        if (themes.any { it.name == text }) text = ""
                        focus = ThemeField.Theme
                    } else {
                        focus = null
                    }
                }
            }

            AnimatedVisibility(
                visible = showsField,
                enter = fadeIn(tween(250)) + slideInVertically(tween(250)) { -it / 2 },
                exit = fadeOut(tween(200)),
            ) {
                BrandTextField(
                    BookCopy.Theme.title,
                    value = text,
                    onValueChange = { text = it },
                    field = ThemeField.Theme,
                    focus = focus,
                    onFocusChange = { focus = it },
                    labelPlacement = BrandTextField.LabelPlacement.Hidden,
                    placeholder = BookCopy.Theme.placeholder,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { validate() }),
                )
            }

            BrandButton(BookCopy.Theme.validate, fillsWidth = true, enabled = chosenTheme.isNotEmpty()) { validate() }
        }
    }
}

/** Le seul champ de la feuille du thème. `BrandTextField` veut une énumération de champs. */
private enum class ThemeField { Theme }

// MARK: - Inviter un proche

/**
 * « Inviter un proche » — qui raconte déjà, et de quoi faire venir les autres.
 *
 * @param inviteBase l'adresse de production, d'où `InviteLink.url` tire le lien
 *   qu'on partage : un lien vers l'émulateur ne mènerait nulle part sur le
 *   téléphone de l'invité.
 */
@Composable
internal fun TripInviteSheet(model: TripSettingsModel, inviteBase: URI?) {
    val state by model.state.collectAsStateWithLifecycle()
    val settings = state.settings

    // Le co-voyageur dont on a demandé le retrait. La confirmation est une
    // alerte et non une feuille de plus : retirer quelqu'un est irréversible,
    // et c'est exactement ce qu'une alerte sait dire.
    var pendingRemoval by remember { mutableStateOf<com.memobook.core.Companion?>(null) }

    BrandSheet(BookCopy.Invite.title, subtitle = BookCopy.Invite.subtitle) {
        Column(
            Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
        ) {
            CompanionList(
                state = state,
                onRemove = { pendingRemoval = it },
                onResend = { model.resendInvitation(it) },
            )

            // Un seul bouton, « Partager » (Hugo, 29/09/2026) : la feuille de
            // partage du téléphone, WhatsApp compris. Le code attend sa barre.
            if (settings?.accessCode != null || state.isLoading) {
                TripAccessCode(
                    code = settings?.accessCode,
                    tripTitle = settings?.name.orEmpty(),
                    inviteBase = inviteBase,
                )
            }

            AnimatedVisibility(visible = state.confirmation != null, enter = fadeIn(tween(250)), exit = fadeOut(tween(250))) {
                BrandText(
                    state.confirmation.orEmpty(),
                    MemoBookFont.caption,
                    Modifier.fillMaxWidth(),
                    color = MemoBookColor.valid,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }

    val removal = pendingRemoval
    BrandAlert(
        isPresented = removal != null,
        title = removal?.name?.let(BookCopy.Invite::removeConfirmation).orEmpty(),
        message = BookCopy.Invite.removeMessage,
        actions = listOf(
            BrandAlert.Action(BookCopy.Invite.cancel, BrandAlert.Role.Cancel) { pendingRemoval = null },
            BrandAlert.Action(BookCopy.Invite.remove, BrandAlert.Role.Destructive) {
                removal?.let(model::remove)
                pendingRemoval = null
            },
        ),
        onDismissRequest = { pendingRemoval = null },
    )
}

@Composable
private fun CompanionList(
    state: TripSettingsModel.State,
    onRemove: (com.memobook.core.Companion) -> Unit,
    onResend: (com.memobook.core.Companion) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        BrandText(
            BookCopy.Invite.listTitle.uppercase(),
            MemoBookFont.overline,
            Modifier.semantics { heading() },
            color = MemoBookColor.inkMuted,
        )

        val companions = state.settings?.companions.orEmpty()
        when {
            companions.isNotEmpty() -> {
                companions.forEach { companion ->
                    androidx.compose.runtime.key(companion.id) {
                        CompanionRow(companion, onRemove = { onRemove(companion) }, onResend = { onResend(companion) })
                    }
                }

                if (companions.any { !it.isOwner }) {
                    BrandText(BookCopy.Invite.gestureHint, MemoBookFont.mention, color = MemoBookColor.inkMuted)
                }
            }
            state.isLoading -> {
                BrandSkeleton(height = 66.dp)
                BrandSkeleton(height = 66.dp)
            }
            else -> BrandText(BookCopy.Invite.empty, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }
    }
}

/**
 * Une ligne de co-voyageur : son portrait, son nom, ce qu'il est pour toi — et,
 * au glissé comme à l'appui long, de quoi le retirer ou lui renvoyer son lien.
 *
 * **Deux gestes pour les mêmes deux actions**, et c'est ce que demande la note
 * « Logique » de la maquette. Le glissé vers la gauche est celui des listes ;
 * l'appui long ouvre le menu de la carte, et TalkBack reçoit les deux actions
 * sur la ligne. Les trois viennent de `BrandSwipeDrawer`, que les cartes de
 * l'accueil partagent.
 */
@Composable
private fun CompanionRow(companion: com.memobook.core.Companion, onRemove: () -> Unit, onResend: () -> Unit) {
    // Le propriétaire ne se retire pas — première règle de la note —, et on ne
    // se retire pas soi-même d'un glissé.
    val canRemove = !companion.isOwner && !companion.isViewer
    // On ne renvoie un lien qu'à quelqu'un qui n'est jamais entré.
    val canResend = companion.isPending

    // Renvoyer d'abord, retirer ensuite — le geste qui défait est le plus
    // loin sous le doigt.
    val actions = buildList {
        if (!canRemove) return@buildList
        if (canResend) {
            add(BrandSwipeAction(R.drawable.icon_televerser, MemoBookColor.action, BookCopy.Invite.resend, action = onResend))
        }
        add(BrandSwipeAction(R.drawable.icon_cross, MemoBookColor.error, BookCopy.Invite.remove, action = onRemove))
    }

    BrandSwipeDrawer(actions) { accessibility ->
        CompanionCard(companion, Modifier.then(accessibility).semantics(mergeDescendants = true) {})
    }
}

@Composable
private fun CompanionCard(companion: com.memobook.core.Companion, modifier: Modifier) {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)

    // La seconde ligne : « Moi » sous **le compte connecté** — et non plus
    // sous le propriétaire, qui n'est « moi » que pour lui (Hugo,
    // 18/10/2026) —, « Invitation envoyée » tant que personne n'est entré, le
    // rôle déduit s'il y en a un, sinon « Co-voyageur ».
    val detail = when {
        companion.isViewer -> BookCopy.Invite.me
        companion.isPending -> BookCopy.Invite.pending
        else -> companion.role ?: BookCopy.Invite.companion
    }

    Row(
        modifier
            .fillMaxWidth()
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandAvatar(photo = rememberAvatarPhoto(companion.avatarUrl), initials = companion.initials, side = 42.dp)

        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BrandText(companion.name, MemoBookFont.tagline)
            BrandText(detail, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }

        if (companion.isOwner && !isAccessibilityTextSize()) {
            BrandText(BookCopy.Invite.owner, MemoBookFont.caption, color = MemoBookColor.inkMuted, textAlign = TextAlign.End)
        }
    }
}

/**
 * La photo d'un co-voyageur, une fois chargée — l'`AsyncImage` que
 * `BrandAvatar` porte sur iOS. `null` tant qu'elle n'est pas là, ou si elle
 * n'a pas pu l'être : les initiales tiennent la place.
 */
@Composable
private fun rememberAvatarPhoto(url: URI?): Painter? {
    url ?: return null
    val painter = rememberAsyncImagePainter(url.toString())
    val state by painter.state.collectAsStateWithLifecycle()
    return painter.takeIf { state is AsyncImagePainter.State.Success }
}

// MARK: - Supprimer le voyage

/**
 * La confirmation avant de supprimer un voyage — **une feuille de l'app**, sur
 * le modèle de `DeleteAccountSheet` : le bouton plein garde, le rouge
 * supprime, et le paragraphe dit ce qui part avant qu'on appuie.
 *
 * Elle vit ici, avec les cinq autres feuilles des réglages, parce que c'est de
 * cet écran qu'on supprime : la porte de sortie d'un voyage est au bout de ses
 * réglages, comme celle d'un compte est au bout du profil (Hugo, 15/09/2026).
 *
 * L'écran la présente dans un `BrandSheetHost` avec `dismissDisabled =
 * isDeleting` — l'`interactiveDismissDisabled` d'iOS.
 *
 * @param tripName le nom du voyage, s'il est arrivé : les réglages peuvent ne
 *   pas avoir chargé, et la feuille doit se lire quand même.
 * @param isDeleting la suppression est partie. Le bouton rouge tourne et plus
 *   rien ne se touche : la demande est définitive, elle ne part pas deux fois.
 * @param errorMessage ce que le serveur a répondu si la suppression a échoué —
 *   un co-voyageur qui essaie, par exemple : seul le propriétaire y a droit. Il
 *   se lit **dans** la feuille : la fermer pour lire pourquoi obligerait à la
 *   rouvrir.
 */
@Composable
internal fun DeleteTripSheet(
    tripName: String?,
    isDeleting: Boolean,
    errorMessage: String?,
    onKeep: () -> Unit,
    onDelete: () -> Unit,
) {
    BrandSheet(BookCopy.Settings.Delete.title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandText(BookCopy.Settings.Delete.body(trip = tripName), MemoBookFont.body, Modifier.fillMaxWidth())

            errorMessage?.let { ErrorBanner(message = it) }

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                // Le bouton plein est celui qui **ne détruit rien** : sur une
                // feuille dont l'autre issue est sans retour, l'action la plus
                // visible doit être la plus sûre.
                BrandButton(BookCopy.Settings.Delete.keep, fillsWidth = true, enabled = !isDeleting, action = onKeep)

                BrandButton(
                    BookCopy.Settings.Delete.confirm,
                    style = BrandButton.Style.Destructive,
                    isLoading = isDeleting,
                    fillsWidth = true,
                    action = onDelete,
                )
            }
        }
    }
}

// MARK: - Supprimer la conversation

/**
 * La confirmation avant d'effacer la conversation d'un voyage — le même
 * dessin que [DeleteTripSheet] : le bouton plein garde, le rouge efface, et
 * le paragraphe dit ce qui part **et ce qui reste** avant qu'on appuie. Ce qui
 * reste compte ici plus qu'ailleurs : le mot d'accueil de MEMO revient, et
 * les souvenirs du carnet ne sont pas la conversation.
 */
@Composable
internal fun ClearConversationSheet(
    isClearing: Boolean,
    errorMessage: String?,
    onKeep: () -> Unit,
    onClear: () -> Unit,
) {
    BrandSheet(BookCopy.Settings.ClearConversation.title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandText(BookCopy.Settings.ClearConversation.body, MemoBookFont.body, Modifier.fillMaxWidth())

            errorMessage?.let { ErrorBanner(message = it) }

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                BrandButton(BookCopy.Settings.ClearConversation.keep, fillsWidth = true, enabled = !isClearing, action = onKeep)

                BrandButton(
                    BookCopy.Settings.ClearConversation.confirm,
                    style = BrandButton.Style.Destructive,
                    isLoading = isClearing,
                    fillsWidth = true,
                    action = onClear,
                )
            }
        }
    }
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Supprimer la conversation", widthDp = 390, heightDp = 640)
@Composable
private fun ClearConversationSheetPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        ClearConversationSheet(isClearing = false, errorMessage = null, onKeep = {}, onClear = {})
    }
}

@Preview(locale = "fr-rFR", name = "Supprimer le voyage", widthDp = 390, heightDp = 640)
@Composable
private fun DeleteTripSheetPreview() {
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        DeleteTripSheet(tripName = "Rome entre amis", isDeleting = false, errorMessage = null, onKeep = {}, onDelete = {})
    }
}

@Preview(locale = "fr-rFR", name = "Inviter un proche", widthDp = 390, heightDp = 900)
@Composable
private fun TripInviteSheetPreview() {
    val model = remember { TripSettingsModel(tripId = "preview") }
    LaunchedEffect(model) { model.load() }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        TripInviteSheet(model, inviteBase = URI("https://api.memo-book.com"))
    }
}

@Preview(locale = "fr-rFR", name = "Notifications du voyage", widthDp = 390, heightDp = 900)
@Composable
private fun TripNotificationsSheetPreview() {
    val model = remember { TripSettingsModel(tripId = "preview") }
    LaunchedEffect(model) { model.load() }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        TripNotificationsSheet(model)
    }
}

@Preview(locale = "fr-rFR", name = "Rythme du récit", widthDp = 390, heightDp = 800)
@Composable
private fun TripPaceSheetPreview() {
    val model = remember { TripSettingsModel(tripId = "preview") }
    LaunchedEffect(model) { model.load() }
    Box(Modifier.fillMaxSize().background(MemoBookColor.background), contentAlignment = Alignment.BottomCenter) {
        TripPaceSheet(model)
    }
}
