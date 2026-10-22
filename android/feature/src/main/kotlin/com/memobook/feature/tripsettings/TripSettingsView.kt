package com.memobook.feature.tripsettings

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.BookCopy
import com.memobook.core.DailyCredit
import com.memobook.core.DailyCreditCopy
import com.memobook.core.Gender
import com.memobook.core.Subscription
import com.memobook.core.TripSettings
import com.memobook.core.rowAccessibilityLabel
import com.memobook.design.BrandButton
import com.memobook.design.BrandComingSoon
import com.memobook.design.BrandGauge
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandNotice
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandTagPill
import com.memobook.design.ErrorBanner
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.LocalSubscriptionSession
import com.memobook.feature.PaywallVariant
import com.memobook.feature.TripSettingsIntent
import com.memobook.feature.TripSettingsSheet
import com.memobook.feature.paywall.PaywallView
import com.memobook.feature.profile.dayAndMonth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.URI

/**
 * Les paramètres d'un voyage : tout ce qui se règle sur le carnet sans quitter
 * le voyage. Jumeau de `TripSettings/TripSettingsView.swift`.
 *
 * On y arrive par la roue crantée, posée au même endroit sur les deux écrans
 * du voyage — son accueil et la conversation. C'est voulu : les réglages
 * appartiennent au **voyage**, pas à l'écran depuis lequel on les ouvre.
 *
 * **L'écran ne contient aucun contenu.** Nom, dates, rythme, co-voyageurs,
 * solde : tout vient du [TripSettings] que porte [TripSettingsModel]. Ce qui
 * est écrit ici, ce sont les intitulés — et ils viennent tous de
 * `BookCopy.Settings`.
 *
 * **Il ne navigue pas.** Les lignes ouvrent des feuilles ou remontent une
 * intention à `RootView`, qui seul tient la pile.
 *
 * @param opening la feuille à ouvrir dès l'arrivée — celle des co-voyageurs
 *   quand on vient du « + » de l'accueil du voyage. `null` depuis la roue
 *   crantée.
 * @param onBack la flèche de l'en-tête — le `dismiss()` d'iOS.
 * @param inviteBase l'adresse de production, d'où le lien d'invitation est
 *   tiré (`InviteLink.url`) — voir la feuille « Inviter un proche ».
 * @param showsDebugPanel le bac à sable sous l'écran — le `#if DEBUG` d'iOS,
 *   que `:feature` ne peut pas lire : c'est la porte qui le dit.
 */
@Composable
fun TripSettingsView(
    model: TripSettingsModel,
    onIntent: (TripSettingsIntent) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    opening: TripSettingsSheet? = null,
    inviteBase: URI? = null,
    showsDebugPanel: Boolean = false,
) {
    // L'immédiat du fil principal : le nom se corrige sur place, et sa ligne
    // relit le modèle sans attendre l'image suivante.
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val scope = rememberCoroutineScope()

    // La feuille ouverte, s'il y en a une. Six lignes de l'écran en ouvrent
    // une désormais ; les autres remontent toujours une intention à
    // `RootView`, qui seul tient la pile.
    var sheet by rememberSaveable { mutableStateOf(opening) }

    // Le paywall, en plein écran par-dessus les réglages — ouvert par
    // « Passer en illimité » dans la feuille du crédit du jour, **après**
    // l'avoir refermée : une feuille ne s'empile pas sur une autre.
    //
    // Présenté ici plutôt que remonté à `RootView` : c'est le motif de
    // l'accueil du voyage et du profil, et une intention qui remonte pour
    // redescendre aussitôt n'apprendrait rien à personne.
    var showsPaywall by rememberSaveable { mutableStateOf(false) }

    // La feuille qui confirme la suppression du voyage — une feuille de
    // l'app, comme celle du compte, et non une alerte : le paragraphe qui dit
    // ce qui part mérite sa place.
    var isConfirmingDeletion by remember { mutableStateOf(false) }

    // La confirmation avant d'effacer la conversation. Une seconde feuille
    // et non un second temps de la première : les deux gestes ne se suivent
    // jamais, et chacun a sa porte.
    var isConfirmingConversationClearing by remember { mutableStateOf(false) }

    // La notice posée par un co-voyageur qui a touché le lien pâli.
    var explainsOwnerOnlyClearing by remember { mutableStateOf(false) }

    // L'abonnement tel que la session le connaît : la version du paywall à
    // montrer, et le geste d'achat qui rend la ligne « Illimité » tout de
    // suite. `null` dans un aperçu isolé.
    val subscriptionSession = LocalSubscriptionSession.current

    // Le crédit servi avec les réglages, relu avec le dernier geste de la
    // session : la ligne passe à « Illimité » dès l'achat, avant même que les
    // réglages soient relus. Par le modèle, qui recharge le crédit d'hier
    // passé minuit.
    val served = state.dailyCredit
    val dailyCredit = subscriptionSession?.applied(served) ?: served

    // Le serveur l'a dit ; sans réponse — un jeu d'essai —, on laisse faire
    // et c'est lui qui refusera.
    val canClearConversation = state.settings?.canClearConversation ?: true

    // Le serveur l'a dit (T233) ; sans réponse, on montre la ligne et c'est
    // lui qui refusera.
    val canDelete = state.settings?.canDelete ?: true

    LaunchedEffect(model) { model.load() }

    // Le nom du voyage se corrige sur place : la barre qui range le clavier,
    // la même que sur le profil.
    BrandKeyboardDismissBar(modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(MemoBookColor.background)) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(horizontal = MemoBookSpacing.screenMargin)
                    .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l),
            ) {
                // **L'écran se dessine tout de suite, entier.** Il n'attend
                // rien de tout ça : ses intitulés, ses groupes et ses lignes
                // appartiennent à l'app. Seules les valeurs viennent du réseau,
                // et elles seules portent une barre d'attente — voir
                // `BrandSkeleton`.
                //
                // **Et quand elles changent, ça se voit.** L'écran s'ouvre sur
                // ce qu'on avait en cache ; si le serveur dit autre chose,
                // trente valeurs bougent en silence sous les yeux de quelqu'un
                // qui lisait. Le balayage le dit — voir `BrandRefreshFlash`.
                BrandRefreshFlash(state.freshness.isUpdated) {
                    Column(
                        // Les valeurs se posent en douceur quand elles
                        // arrivent, au lieu de remplacer les barres d'attente
                        // d'un coup sec.
                        Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
                        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
                    ) {
                        // L'écran dessine son propre en-tête, comme la
                        // maquette : la flèche et le titre partagent une ligne,
                        // à la marge de la colonne.
                        BrandScreenHeader(BookCopy.Settings.title, onBack = onBack)

                        AdventureSection(
                            state = state,
                            dailyCredit = dailyCredit,
                            onSetName = model::setName,
                            onSetNotifications = model::setNotifications,
                            onSetPublicGallery = model::setPublicGallery,
                            onSheet = { sheet = it },
                            onIntent = onIntent,
                        )
                        QuickAccessSection(onIntent)

                        state.errorMessage?.let { message ->
                            // Le constat, le conseil, et les deux gestes :
                            // réessayer, ou nous écrire. Un 500 nu disait
                            // « Erreur interne du serveur » et rien d'autre
                            // (Hugo, 15/09/2026).
                            ErrorBanner(
                                message = message,
                                advice = state.errorAdvice,
                                retry = { scope.launch { model.load() } },
                                help = { onIntent(TripSettingsIntent.OpenHelp) },
                            )
                        }

                        BrandButton(
                            BookCopy.Settings.help,
                            style = BrandButton.Style.Link,
                            isSubdued = true,
                            fillsWidth = true,
                        ) {
                            onIntent(TripSettingsIntent.OpenHelp)
                        }

                        // **Les deux suppressions vont ensemble** (Hugo,
                        // 19/09/2026) : à 24, elles se lisaient comme deux
                        // blocs sans rapport, au milieu de rien. Douze les
                        // rapprochent en un groupe, et les deux gardent leur
                        // cible tactile — il en faut assez pour ne pas
                        // supprimer un voyage en visant la conversation.
                        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                            // « Supprimer la conversation », juste au-dessus du
                            // voyage — à l'encre et avec la bulle, sur le
                            // dessin de « Me déconnecter » : c'est un geste qui
                            // se rattrape moins qu'un réglage et plus qu'une
                            // suppression de voyage, et deux croix rouges
                            // l'une sur l'autre auraient dit deux fois la même
                            // chose (Hugo, 17/09/2026).
                            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                                ExitLink(
                                    icon = R.drawable.icon_bubble,
                                    title = BookCopy.Settings.clearConversation,
                                    tint = MemoBookColor.ink,
                                    enabled = !state.isClearingConversation,
                                    modifier = Modifier.alpha(if (canClearConversation) 1f else 0.4f),
                                ) {
                                    // **Ce qu'on ne peut pas faire pâlit, ça ne
                                    // se désactive pas** : un co-voyageur ne
                                    // supprime pas le fil de tout le monde, et
                                    // l'appui le lui dit au lieu d'avaler le
                                    // geste.
                                    if (canClearConversation) {
                                        isConfirmingConversationClearing = true
                                    } else {
                                        explainsOwnerOnlyClearing = true
                                    }
                                }

                                AnimatedVisibility(
                                    visible = explainsOwnerOnlyClearing,
                                    enter = fadeIn(tween(250)) + slideInVertically(tween(250)) { -it / 2 },
                                    exit = fadeOut(tween(200)),
                                ) {
                                    BrandNotice(BookCopy.Settings.ClearConversation.ownerOnly, tone = BrandNotice.Tone.Information)
                                }
                            }

                            // **Pas même montrée à un co-voyageur** (T233,
                            // Hugo, 06/10/2026) — contrairement à la
                            // conversation, qui pâlit et s'explique : il n'y a
                            // rien à lui expliquer, supprimer le récit de tout
                            // le monde n'est pas à lui.
                            //
                            // « Supprimer ce voyage », tout en bas — le même
                            // dessin que « Supprimer mon compte » sur le
                            // profil : une croix rouge et un mot, centrés, sans
                            // carte ni bouton plein. On ne met pas en avant la
                            // porte de sortie, mais elle existe (Hugo,
                            // 15/09/2026). La confirmation est dans la feuille ;
                            // après elle, il n'y a plus rien à annuler.
                            if (canDelete) {
                                ExitLink(
                                    icon = R.drawable.icon_cross,
                                    title = BookCopy.Settings.delete,
                                    tint = MemoBookColor.error,
                                    enabled = !state.isDeleting,
                                ) {
                                    isConfirmingDeletion = true
                                }
                            }
                        }

                        if (showsDebugPanel) TripSettingsDebugPanel(model)
                    }
                }
            }

            AnimatedVisibility(
                visible = showsPaywall,
                enter = slideInVertically(tween(350)) { it },
                exit = slideOutVertically(tween(300)) { it },
            ) {
                PaywallView(
                    subscription = Subscription.offer,
                    variant = subscriptionSession?.paywallVariant ?: PaywallVariant.FirstTime,
                    previewMemoId = state.settings?.tripId,
                    onSubscribe = {
                        subscriptionSession?.record(isSubscribed = true)
                        showsPaywall = false
                        // Le geste a déjà rendu la ligne « Illimité » (voir
                        // `SubscriptionSession.applied`) ; les réglages relus
                        // le font dire au serveur, qui seul sait que l'achat
                        // est passé.
                        scope.launch { model.load() }
                    },
                    onDismiss = { showsPaywall = false },
                )
            }
        }
    }

    BrandSheetHost(item = sheet, onDismissRequest = { sheet = null }) { destination ->
        when (destination) {
            TripSettingsSheet.Dates -> TripDatesSheet(model)
            TripSettingsSheet.Pace -> TripPaceSheet(model)
            TripSettingsSheet.Notifications -> TripNotificationsSheet(model)
            TripSettingsSheet.Theme -> TripThemeSheet(model)
            TripSettingsSheet.Companions -> TripInviteSheet(model, inviteBase)
            TripSettingsSheet.DailyCredit -> DailyCreditSheet(
                model = model,
                onSubscribe = {
                    sheet = null
                    showsPaywall = true
                },
            )
        }
    }

    BrandSheetHost(
        isPresented = isConfirmingConversationClearing,
        onDismissRequest = { isConfirmingConversationClearing = false },
        dismissDisabled = state.isClearingConversation,
    ) {
        ClearConversationSheet(
            isClearing = state.isClearingConversation,
            errorMessage = state.errorMessage,
            onKeep = { isConfirmingConversationClearing = false },
            onClear = {
                scope.launch {
                    // On reste sur les réglages : c'est le fil, en dessous
                    // dans la pile, qui se vide — et c'est lui qu'on retrouve
                    // en revenant.
                    if (model.clearConversation()) isConfirmingConversationClearing = false
                }
            },
        )
    }

    BrandSheetHost(
        isPresented = isConfirmingDeletion,
        onDismissRequest = { isConfirmingDeletion = false },
        dismissDisabled = state.isDeleting,
    ) {
        DeleteTripSheet(
            tripName = state.settings?.name,
            isDeleting = state.isDeleting,
            errorMessage = state.errorMessage,
            onKeep = { isConfirmingDeletion = false },
            onDelete = {
                scope.launch {
                    // Le voyage n'existe plus : l'app ne peut que revenir à
                    // l'accueil, et c'est `RootView` qui vide la pile.
                    if (model.delete()) {
                        isConfirmingDeletion = false
                        onIntent(TripSettingsIntent.TripDeleted)
                    }
                }
            },
        )
    }
}

// MARK: - Gère ton aventure

@Composable
private fun AdventureSection(
    state: TripSettingsModel.State,
    dailyCredit: DailyCredit?,
    onSetName: (String) -> Unit,
    onSetNotifications: (Boolean) -> Unit,
    onSetPublicGallery: (Boolean) -> Unit,
    onSheet: (TripSettingsSheet) -> Unit,
    onIntent: (TripSettingsIntent) -> Unit,
) {
    val settings = state.settings
    val isLoading = state.isLoading

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        SectionTitle(BookCopy.Settings.adventureSection)

        // Le nom a **sa carte**, et ce n'est pas un oubli de la maquette :
        // c'est une valeur qu'on vient chercher du regard, pas un réglage. La
        // carte de la cagnotte, à côté, est partie avec elle (Hugo,
        // 06/10/2026, T230).
        // Le nom se corrige **sur la ligne**, comme le téléphone du profil :
        // toucher ouvre le clavier, sortir du champ enregistre, la coche verte
        // accuse réception (Hugo, 18/09/2026). Il menait avant à une intention
        // que personne ne routait — la ligne s'ouvrait sur rien.
        BrandRowGroup {
            +BrandRow(
                BookCopy.Settings.name,
                text = settings?.name.orEmpty(),
                onTextChange = onSetName,
                isValueLoading = isLoading,
                isConfirmed = state.justSaved == TripSettingsModel.SavedField.Name,
            )
        }

        // **Le crédit du jour, toujours visible** (Hugo, 03/10/2026). Ce n'est
        // plus un garde-fou discret qu'on ne remarque qu'au seuil : c'est le
        // levier de l'abonnement. Un non-abonné y lit en permanence ce que le
        // voyage peut encore raconter aujourd'hui, la jauge comprise ; un
        // abonné y lit « Illimité ». Sans crédit servi (un serveur plus
        // ancien), la ligne se tait plutôt que d'inventer.
        if (dailyCredit != null) {
            DailyCreditRow(dailyCredit) { onSheet(TripSettingsSheet.DailyCredit) }
            // **Abonné : de quoi résilier, là où on lit « Illimité »** (Hugo,
            // 18/10/2026). Hors de la ligne, qui est déjà un bouton : « Mon
            // abonnement » du profil fait la suite.
            if (dailyCredit.isUnlimited) {
                BrandButton(DailyCreditCopy.cancelSubscription, style = BrandButton.Style.Destructive, fillsWidth = true) {
                    onIntent(TripSettingsIntent.ManageSubscription)
                }
            }
        }

        BrandRowGroup(
            // Le groupe attend **le temps de la lecture**, et pas plus : les
            // interrupteurs agissent, et les basculer sur des réglages pas
            // encore lus enverrait un état qu'on n'a pas. Mais une lecture qui
            // a échoué ne doit pas geler l'écran — les lignes rouvraient leurs
            // feuilles quand même, elles ne le pouvaient plus derrière un 500
            // (Hugo, 15/09/2026) ; une bascule sans réglages, elle, reste sans
            // effet (le modèle la refuse).
            Modifier.blocksTouches(isLoading),
        ) {
            +BrandRow(
                BookCopy.Settings.dates,
                value = settings?.dateRangeLabel ?: BookCopy.Settings.noValue,
                isValueLoading = isLoading,
                action = { onSheet(TripSettingsSheet.Dates) },
            )
            +BrandRow(
                BookCopy.Settings.pace,
                value = settings?.narrationPace?.displayName ?: BookCopy.Settings.noValue,
                isValueLoading = isLoading,
                action = { onSheet(TripSettingsSheet.Pace) },
            )
            +BrandRow(BookCopy.Settings.notifications, isOn = settings?.wantsNotifications ?: false, onIsOnChange = onSetNotifications)
            +BrandRow(BookCopy.Settings.manageNotifications, action = { onSheet(TripSettingsSheet.Notifications) })
            +BrandRow(
                BookCopy.Settings.companions,
                value = settings?.companionsLabel ?: BookCopy.Settings.noValue,
                isValueLoading = isLoading,
                action = { onSheet(TripSettingsSheet.Companions) },
            )
        }

        BrandRowGroup(Modifier.blocksTouches(isLoading)) {
            +BrandRow(
                BookCopy.Settings.theme,
                value = settings?.theme ?: BookCopy.Settings.noValue,
                isValueLoading = isLoading,
                action = { onSheet(TripSettingsSheet.Theme) },
            )
            +BrandRow(BookCopy.Settings.publicGallery, isOn = settings?.isPublicGallery ?: false, onIsOnChange = onSetPublicGallery)
        }

        BrandRowGroup {
            +BrandRow(
                BookCopy.Settings.style,
                value = settings?.styleSummary ?: BookCopy.Settings.noValue,
                isValueLoading = isLoading,
                action = { onIntent(TripSettingsIntent.OpenCustomisation) },
            )
        }

        // **À venir** (Hugo, 08/10/2026), comme les connecteurs du profil :
        // rien ne se branche encore (T76). La carte se montre dans la version
        // livrée — elle ne vivait qu'en Debug depuis le 29/09 —, pâlie, sa
        // pastille sur le coin, et ne répond pas au doigt.
        BrandComingSoon(Modifier.padding(top = MemoBookSpacing.xs)) {
            TricountCallout(
                connected = settings?.tricountLabel,
                isLoading = isLoading,
                isEnabled = false,
                action = { onIntent(TripSettingsIntent.ConnectTricount) },
            )
        }
    }
}

// MARK: - Accès rapide

@Composable
private fun QuickAccessSection(onIntent: (TripSettingsIntent) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
        SectionTitle(BookCopy.Settings.quickAccessSection)

        PdfPreviewRow { onIntent(TripSettingsIntent.OpenBookPreview) }

        // « Commander le carnet » ouvre le tunnel de commande, toujours :
        // c'est lui qui sait dire s'il y a un carnet à imprimer, et une ligne
        // qui ne mène nulle part se lit comme une ligne cassée (Hugo,
        // 15/09/2026). Elle attendait un `isPrintable` que l'écran ne peut pas
        // lire quand les réglages ne chargent pas.
        BrandRowGroup {
            +BrandRow(BookCopy.Settings.order, action = { onIntent(TripSettingsIntent.OrderBook) })
        }
    }
}

@Composable
private fun SectionTitle(title: String) {
    BrandText(
        title.uppercase(),
        MemoBookFont.sectionOverline,
        Modifier.semantics { heading() },
        color = MemoBookColor.inkMuted,
    )
}

/**
 * Le dessin commun des deux portes de sortie : une icône et un mot, centrés,
 * sans carte ni bouton plein — celui des actions de sortie du profil.
 */
@Composable
private fun ExitLink(
    @DrawableRes icon: Int,
    title: String,
    tint: Color,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    action: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = interaction,
                indication = PlainButtonIndication,
                enabled = enabled,
                role = Role.Button,
                onClick = action,
            )
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painter = painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(MemoBookSpacing.contentIcon),
        )
        BrandText(title, MemoBookFont.button, color = tint)
    }
}

/**
 * Le `.disabled` de SwiftUI sur un groupe de lignes : le doigt s'arrête au
 * groupe, sans changer son dessin. Posé dans la passe initiale, il prend le
 * toucher avant les lignes.
 */
internal fun Modifier.blocksTouches(isBlocked: Boolean): Modifier =
    if (!isBlocked) {
        this
    } else {
        pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
            }
        }
    }

// MARK: - Les blocs qui ne sont pas des lignes

/**
 * La ligne du **crédit du jour** : ce qui reste aujourd'hui sur ce voyage, et
 * la jauge qui le montre.
 *
 * **Elle parle tout le temps**, et c'est le changement de fond (Hugo,
 * 03/10/2026) : la ligne des limites de souvenirs se taisait tant qu'il
 * restait de la marge, parce qu'elle n'était qu'un garde-fou de coût. Le
 * crédit du jour, lui, est ce que l'abonnement lève — un non-abonné doit
 * pouvoir le lire d'un regard, à 4 min comme à 30 s. La jauge est donc
 * toujours là : vide et grise au matin, le vert y avance à mesure qu'on
 * raconte, et rougit quand tout est dit (Hugo, 08/10/2026 ; `BrandGauge` n'a
 * que ces deux couleurs). Le chiffre, lui, dit **ce qui reste** — « 3 min 20
 * restantes ». Un abonné lit « Illimité », sans jauge : il n'a rien à compter.
 *
 * Ce n'est pas une `BrandRow` : celle-ci porte un intitulé et une valeur, et
 * n'a pas de place pour une barre qui pousse sous elle. Elle en reprend la
 * coque — même fond, même filet, même chevron.
 *
 * ⚠️ **Aucune maquette ne la dessine** (T248) : elle reste à valider dans
 * Figma, avec la feuille qu'elle ouvre.
 */
@Composable
private fun DailyCreditRow(credit: DailyCredit, action: () -> Unit) {
    val chevronSide = scaled(14.dp)
    val isAccessibilitySize = isAccessibilityTextSize()
    val subscriptionSession = LocalSubscriptionSession.current
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)

    // La règle avant qu'on la demande : la durée du crédit, et qu'elle se
    // partage.
    val caption = if (credit.isUnlimited) {
        DailyCreditCopy.rowCaptionUnlimited(until = subscriptionSession?.endsAt?.dayAndMonth)
    } else {
        DailyCreditCopy.rowCaption(limitMs = credit.limitMs)
    }
    val label = DailyCreditCopy.rowAccessibilityLabel(credit)

    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            )
            .clearAndSetSemantics { contentDescription = label }
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                BrandText(DailyCreditCopy.title, MemoBookFont.body)
                BrandText(caption, MemoBookFont.caption, color = MemoBookColor.inkMuted)
                // Aux tailles accessibles, la valeur passe **sous** l'intitulé,
                // comme celle des lignes d'à côté : à côté, elle gardait sa
                // largeur et coupait les mots en deux (recette du 30/09/2026).
                if (isAccessibilitySize) DailyCreditValue(credit)
            }

            if (!isAccessibilitySize) DailyCreditValue(credit)

            Image(
                painter = painterResource(R.drawable.icon_chevron),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                modifier = Modifier.size(chevronSide),
            )
        }

        if (!credit.isUnlimited) {
            // Vide et grise au matin, le vert avance à mesure qu'on raconte, et
            // rougit quand tout est dit (Hugo, 08/10/2026). Le chiffre d'à côté
            // dit le reste. TalkBack le lit déjà dans le libellé de la ligne ;
            // la jauge ne le redit pas.
            BrandGauge(
                fraction = credit.fraction,
                accessibilityLabel = DailyCreditCopy.title,
                isExhausted = credit.isExhausted,
            )
        }
    }
}

@Composable
private fun DailyCreditValue(credit: DailyCredit) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
        // La pastille lime de l'abonné (18/10/2026) : la même que celle du
        // profil — le lime ne dit que l'abonnement.
        if (credit.isUnlimited) {
            // Le genre du compte n'est pas lu ici : la forme non marquée,
            // comme à qui ne l'a pas dit. iOS plafonne la pastille à la plus
            // grande taille ordinaire ; Compose n'a pas ce plafond, elle suit
            // la police.
            BrandTagPill(SubscriptionCopy.currentBadge(Gender.Undisclosed), tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
        }
        BrandText(
            DailyCreditCopy.rowValue(credit),
            MemoBookFont.label.copy(fontFeatureSettings = "tnum"),
            color = if (credit.isExhausted) MemoBookColor.error else MemoBookColor.inkMuted,
            maxLines = 1,
        )
    }
}

/**
 * L'invitation à relier son Tricount : une carte à trois étages — le
 * pictogramme, ce que ça apporte, et le chevron.
 *
 * Ce n'est pas une `BrandRow` parce que son texte fait deux lignes et porte
 * une explication, pas une valeur. Une ligne de réglage qui explique n'est
 * plus une ligne de réglage.
 *
 * @param isEnabled faux tant que la carte est « À venir » : Compose ne sait pas
 *   retirer à un enfant son rôle de bouton — voir `BrandComingSoon`.
 */
@Composable
private fun TricountCallout(connected: String?, isLoading: Boolean, isEnabled: Boolean, action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val markSide = scaled(MemoBookSpacing.l)
    val container = Modifier
        .fillMaxWidth()
        .clip(shape)
        .background(MemoBookColor.surface, shape)
        .border(1.dp, MemoBookColor.hairline, shape)
        .clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = PlainButtonIndication,
            enabled = isEnabled,
            role = Role.Button,
            onClick = action,
        )
        .semantics(mergeDescendants = true) {}
        .padding(MemoBookSpacing.s)

    // Le logo de Tricount, tel que Tricount le dessine (`assets/logos/Tricount
    // Icon.png`, importé par `import-brand-logos.py`). Il a longtemps été un
    // « tt » dans le bleu de la marque, faute d'asset — Hugo l'a déposé le
    // 15/09/2026, ce qui clôt T73. Jamais teinté : c'est la marque d'un
    // tiers, elle garde ses couleurs.
    val mark: @Composable () -> Unit = {
        Image(
            painter = painterResource(R.drawable.logo_tricount),
            contentDescription = null,
            modifier = Modifier.size(markSide).clip(RoundedCornerShape(MemoBookSpacing.xs)),
        )
    }
    val text: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            BrandText(connected ?: BookCopy.Settings.tricountTitle, MemoBookFont.bodySemibold)
            if (isLoading) {
                BrandSkeleton()
            } else {
                BrandText(BookCopy.Settings.tricountMessage, MemoBookFont.caption, color = MemoBookColor.inkMuted)
            }
        }
    }

    // En taille accessible, le pictogramme passe au-dessus du texte : lui
    // garder une colonne ne laisserait au titre que deux mots de large.
    if (isAccessibilityTextSize()) {
        Column(container, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            mark()
            text()
        }
    } else {
        // Sans chevron tant que la carte est « À venir » : il promettait un
        // écran derrière elle.
        Row(container, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.CenterVertically) {
            mark()
            Box(Modifier.weight(1f)) { text() }
        }
    }
}

/**
 * La ligne « Prévisualisation PDF » : l'intitulé, sa précision, et en
 * vignette **la page de la composition, toute montée**.
 *
 * La vignette était un livre gris vide tant qu'aucune couverture n'était
 * servie — c'est-à-dire presque toujours. Hugo veut à la place le squelette de
 * chargement du PDF dans son état final, « quand tous les morceaux de la page
 * ont fini de se placer » (06/10/2026, T220) : la même page que l'écran de
 * composition, figée à la fin de sa cascade. La ligne annonce ainsi ce qu'elle
 * ouvre — on y retrouve la page, cette fois en train de se monter.
 */
@Composable
private fun PdfPreviewRow(action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val label = "${BookCopy.Settings.pdfPreview}. ${BookCopy.Settings.pdfPreviewDetail}"
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            )
            .clearAndSetSemantics { contentDescription = label }
            .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            BrandText(BookCopy.Settings.pdfPreview, MemoBookFont.body)
            BrandText(BookCopy.Settings.pdfPreviewDetail, MemoBookFont.caption, color = MemoBookColor.inkMuted)
        }

        Spacer(Modifier.width(MemoBookSpacing.xs))

        // Pas d'attente à dessiner : la page ne dépend de rien que le serveur
        // doive envoyer. `progress = 1`, c'est la cascade finie — chaque
        // morceau à sa place, sans mouvement. La vignette garde le rapport
        // d'une page A5 — le format du carnet (`MemoBook
        // Generator/templates/travel-journal/print.json`). Fixe, hors taille
        // de police : une image n'est pas du texte.
        BookCompositionPage(
            progress = 1.0,
            modifier = Modifier.size(width = PdfThumbnail.width, height = PdfThumbnail.width * PdfThumbnail.ratio),
        )
        BrandChevron()
    }
}

private object PdfThumbnail {
    val width = 56.dp
    const val ratio = 1.414f
}

/**
 * Le chevron de bout de ligne, à la taille et à la couleur des lignes de
 * réglages.
 *
 * Il vit ici et non dans `BrandRowGroup` parce que trois blocs de cet écran
 * ne sont pas des lignes de réglage — la carte, l'aperçu PDF, le Tricount — et
 * doivent pourtant porter le même chevron qu'elles.
 */
@Composable
internal fun BrandChevron() {
    Image(
        painter = painterResource(R.drawable.icon_chevron),
        contentDescription = null,
        colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
        modifier = Modifier.size(scaled(22.dp)),
    )
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Paramètres du voyage", widthDp = 390, heightDp = 1400)
@Composable
private fun TripSettingsViewPreview() {
    TripSettingsView(remember { TripSettingsModel(tripId = "preview") }, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Paramètres — valeurs en route", widthDp = 390, heightDp = 1400)
@Composable
private fun TripSettingsLoadingPreview() {
    // Une source qui ne répond jamais : c'est l'état de chargement, celui que
    // la maquette ne dessine pas et que R11 réclame.
    val model = remember {
        TripSettingsModel(
            tripId = "preview",
            source = {
                kotlinx.coroutines.awaitCancellation()
            },
        )
    }
    TripSettingsView(model, onIntent = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Paramètres — AX3", widthDp = 390, heightDp = 2000, fontScale = 2f)
@Composable
private fun TripSettingsLargeTextPreview() {
    TripSettingsView(remember { TripSettingsModel(tripId = "preview") }, onIntent = {}, onBack = {})
}
