package com.memobook.feature.profile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import com.memobook.core.CurrentTrip
import com.memobook.core.Gender
import com.memobook.core.PostalAddress
import com.memobook.core.Subscription
import com.memobook.core.TermsOfUse
import com.memobook.core.TravellerProfile
import com.memobook.design.ActivitySpinner
import com.memobook.design.BrandAlert
import com.memobook.design.BrandButton
import com.memobook.design.BrandComingSoonBadge
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandNotice
import com.memobook.design.BrandRefreshFlash
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandTagPill
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
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
import com.memobook.feature.PhotoFlowHost
import com.memobook.feature.ProfileIntent
import com.memobook.feature.paywall.LocalSubscriptionPurchase
import com.memobook.feature.paywall.PaywallView
import com.memobook.feature.rememberPhotoFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import com.memobook.feature.order.finishAbandonedOrder
import com.memobook.feature.order.AbandonedOrderPayment

/**
 * Le profil : qui tu es pour MemoBook, ce que tu lui as confié, et par où on
 * sort. Jumeau de `Profile/ProfileView.swift`.
 *
 * **L'écran ne contient aucun contenu.** Nom, adresse, carte, connecteurs,
 * commandes : tout vient du [TravellerProfile] que porte [ProfileModel]. Ce
 * qui est écrit ici, ce sont les seuls libellés qui appartiennent à
 * l'interface.
 *
 * **Il ne navigue pas non plus, sauf pour sortir.** Les lignes ouvrent des
 * feuilles, qui vivent dans cet écran ; la déconnexion, elle, change l'étape
 * de l'app entière et remonte donc à `RootView`.
 *
 * @param statistics les chiffres du compte, pour la feuille « Statistiques ».
 *   Un modèle à part : il a sa route, sa case de cache et sa veille — voir
 *   [StatisticsModel].
 * @param opening la feuille à ouvrir une fois le profil lu — « Mon
 *   abonnement », depuis « Résilier » des réglages d'un voyage. Après la
 *   lecture : la feuille se construit sur l'abonnement servi.
 * @param managePaymentMethods la feuille « Moyens de paiement » de Stripe —
 *   `dependencies.managePaymentMethods()`. `null` en aperçu, où la ligne ne
 *   fait rien.
 * @param finishAbandonedOrder « Finaliser ma commande » du suivi des commandes
 *   — `dependencies.finishAbandonedOrder(orderId)`. `null` en aperçu, où le
 *   bouton ne s'affiche pas.
 * @param opensStorePage faux dans le bac à sable : « Gérer » n'ouvre pas la
 *   page du Play Store — voir [SubscriptionSheet].
 */
@Composable
internal fun ProfileView(
    model: ProfileModel,
    statistics: StatisticsModel,
    onSignOut: () -> Unit,
    onBack: () -> Unit,
    onIntent: (ProfileIntent) -> Unit = {},
    opening: ProfileSheet? = null,
    managePaymentMethods: (suspend () -> String?)? = null,
    finishAbandonedOrder: (suspend (String) -> AbandonedOrderPayment.Outcome)? = null,
    opensStorePage: Boolean = true,
) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val subscriptionSession = LocalSubscriptionSession.current
    // Le store, pour remettre au serveur un achat qu'il n'a pas encore reçu —
    // voir `loadProfile`.
    val subscriptionPurchase = LocalSubscriptionPurchase.current
    val scope = rememberCoroutineScope()

    var sheet by rememberSaveable { mutableStateOf<ProfileSheet?>(null) }
    // La feuille du mot de passe a son modèle à elle, un par ouverture.
    var passwordModel by remember { mutableStateOf<PasswordChangeModel?>(null) }
    val passwordState = passwordModel?.let { it.state.collectAsStateWithLifecycle().value }

    // Le paywall se présente **par-dessus tout**, feuille comprise : c'est un
    // écran entier, pas une feuille de plus. La feuille qui l'a ouvert se
    // referme donc d'abord, sans quoi on la retrouverait dessous en sortant.
    var showsPaywall by rememberSaveable { mutableStateOf(false) }

    // La confirmation de la suppression du compte — voir `DeleteAccountSheet`.
    var isConfirmingDeletion by rememberSaveable { mutableStateOf(false) }

    // Le parcours de choix de la photo de profil — la feuille « Prendre une
    // photo / Choisir dans la galerie », comme dans la conversation (Clara,
    // 17/09/2026, T165).
    val avatarPhotos = rememberPhotoFlow()

    // La photo qu'on vient de choisir, posée dans le rond le temps que le
    // serveur la reçoive — et gardée ensuite, tant que l'adresse distante ne
    // charge pas. Voir `ProfileAvatar`.
    var pendingAvatar by remember { mutableStateOf<ImageBitmap?>(null) }

    // Ce qui a empêché la feuille de Stripe de s'ouvrir.
    var paymentMethodsError by remember { mutableStateOf<String?>(null) }

    val profile = state.profile

    // MARK: - L'abonnement, tel qu'il faut le lire ici

    // L'abonnement du profil, **corrigé par la session**.
    //
    // Le modèle se reconstruit à chaque fois qu'on revient sur l'écran, et
    // repartirait donc du jeu d'essai. La session pouvait donc **imposer**
    // l'abonnement, et elle avait le dernier mot.
    //
    // ⚠️ **Elle ne l'a plus sur une résiliation** (Hugo, 19/09/2026), et c'est
    // la seconde moitié du défaut qu'il a vu : après avoir confirmé trois
    // fois, la feuille rouvrait sur « ABONNÉE ». La session ne sait pas si on
    // est abonné, elle sait si l'on raconte sans limite — et pendant le mois
    // déjà réglé, on le peut encore (`ProfileModel.subscriptionGrantsAccess`).
    //
    // Elle peut toujours en **donner** un — un achat que le serveur n'a pas
    // encore reçu, le bac à sable qui fait jouer un abonné —, jamais en
    // **rendre** un.
    //
    // **Ce qu'elle donne est tenu par le store** (03/10/2026). Tout achat fait
    // dans l'app passe par Google Play ; un abonnement que le serveur n'a pas
    // encore vu (`AwaitingServer`) se résilie donc sur la page du Play Store,
    // jamais par la route qui ne coupe rien chez lui — voir `isHeldByPlay`.
    val isHeldByPlay = profile != null && model.isHeldByAppleOnly(subscriptionSession)
    val effectiveSubscription: Subscription? = profile?.subscription?.let { subscription ->
        if (isHeldByPlay) subscription.updating(isActive = true, cancelledAt = null) else subscription
    }

    // L'abonnement va se renouveler chez Apple : supprimer le compte ne
    // l'arrêtera pas, et la feuille de suppression doit le dire — **à lui
    // seul** (03/10/2026). Sans profil chargé, on le dit, par prudence.
    val renewsAtApple = effectiveSubscription?.let { it.managedByAppStore && it.cancelledAt == null && it.isUnlimited } ?: true

    // Le compte raconte-t-il sans limite — lu sur le modèle **et** sur le
    // dernier geste de la session (un achat, une résiliation, le bac à
    // sable). Vrai tant que le profil n'est pas là : les trois blocs qui en
    // dépendent attendent de le savoir plutôt que d'apparaître puis partir.
    val isSubscriber = profile?.let { subscriptionSession?.override ?: it.isSubscriber } ?: true

    // « Jusqu’au 12 octobre », sur la ligne « Mon abonnement », quand le
    // renouvellement est coupé et que l'illimité court encore. Juste après un
    // geste, c'est la session qui sait : un achat n'a pas de fin, une
    // résiliation a celle du mois payé.
    val subscriptionEnd = if (subscriptionSession?.override == true) {
        subscriptionSession.endsAt
    } else {
        profile?.subscription?.unlimitedUntil()
    }
    val subscriptionEndLabel = subscriptionEnd?.let(SubscriptionCopy::rowUntil)

    // Qui a déjà été abonné revoit **deux** écrans au lieu de trois : il
    // connaît déjà le produit. Le profil le sait par `hasEndedBefore`, la
    // session par ce que l'accueil lui a appris.
    val paywallVariant = if (profile?.subscription?.hasEndedBefore == true) {
        PaywallVariant.Returning
    } else {
        subscriptionSession?.paywallVariant ?: PaywallVariant.FirstTime
    }

    // Remet à l'API l'achat que le store garde ouvert, puis relit le profil :
    // le serveur tranche.
    suspend fun deliverPurchaseAndReload() {
        val purchase = subscriptionPurchase ?: return
        purchase.deliverUnfinished()
        model.load()
    }

    // Charge le profil — et, **quand un achat attend encore le serveur**,
    // remet d'abord la transaction que le store garde ouverte, puis relit
    // (03/10/2026). Le store ne la redonne de lui-même qu'au prochain
    // lancement ; l'ouverture du profil est le moment où l'on vient vérifier.
    suspend fun loadProfile() {
        model.load()
        if (!model.isHeldByAppleOnly(subscriptionSession)) return
        deliverPurchaseAndReload()
    }

    fun newPasswordModel() = PasswordChangeModel(
        email = model.profile?.email.orEmpty(),
        change = model.changePassword,
        requestReset = model.requestPasswordReset,
    )

    // Un modèle neuf à chaque ouverture de « Modifier mon mot de passe ».
    fun open(destination: ProfileSheet) {
        if (destination == ProfileSheet.Password) passwordModel = newPasswordModel()
        sheet = destination
    }

    // La feuille du mot de passe rouverte après une recréation de l'activité :
    // son modèle, lui, n'a pas survécu.
    LaunchedEffect(sheet) {
        if (sheet == ProfileSheet.Password && passwordModel == null) passwordModel = newPasswordModel()
    }

    LaunchedEffect(model) {
        loadProfile()
        if (opening != null && sheet == null) open(opening)
    }

    // Ce que le profil sait de l'abonnement sert aux autres écrans : la
    // version du paywall, et l'illimité, qu'on ouvre l'offre depuis la
    // conversation ou les réglages d'un voyage.
    LaunchedEffect(profile, subscriptionSession) { profile?.let { subscriptionSession?.learn(it) } }

    // **Le profil suit l'abonnement réel** (Hugo, 06/10/2026 : « quand
    // quelqu'un se désabonne, attention à ce que tous les endroits qui
    // indiquaient “abonné” ne l'indiquent plus »). Il ne se relisait qu'à
    // l'ouverture : la pastille « Abonné(e) » et « Mon abonnement »
    // survivaient au retour du store, à un remboursement, à la fin du mois
    // payé. Il se relit donc au retour au premier plan, et quand la session
    // apprend un changement venu d'ailleurs.
    var hasResumed by remember { mutableStateOf(false) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        // La première reprise est l'ouverture de l'écran, déjà lue.
        if (!hasResumed) {
            hasResumed = true
            return@LifecycleEventEffect
        }
        if (model.profile != null) scope.launch { model.load() }
    }
    LaunchedEffect(subscriptionSession) {
        val session = subscriptionSession ?: return@LaunchedEffect
        snapshotFlow { session.revision }.drop(1).collect { model.load() }
    }

    Box(Modifier.fillMaxSize().background(MemoBookColor.background)) {
        BrandKeyboardDismissBar(Modifier.fillMaxSize()) {
            ProfileContent(
                state = state,
                isSubscriber = isSubscriber,
                subscriptionEndLabel = subscriptionEndLabel,
                pendingAvatar = pendingAvatar,
                avatarDeniedMessage = avatarPhotos.deniedMessage,
                onBack = onBack,
                onAvatarTap = avatarPhotos::begin,
                onOpen = ::open,
                onShowPaywall = { showsPaywall = true },
                onIntent = onIntent,
                onSignOut = onSignOut,
                onConfirmDeletion = { isConfirmingDeletion = true },
                onRetry = { scope.launch { model.load() } },
                onManageCards = {
                    val manage = managePaymentMethods
                    if (manage != null) scope.launch { paymentMethodsError = manage() }
                },
                onFullName = model::setFullName,
                onPhoneNumber = { if (model.profile != null) model.setPhoneNumber(it) },
                onNewsletter = { if (model.profile != null) model.setNewsletter(it) },
            )
        }

        PhotoFlowHost(
            avatarPhotos,
            title = "Photo de profil",
            maxSelection = 1,
            // « Supprimer la photo » n'est proposé que s'il y en a une : le
            // rond revient alors aux initiales (Hugo, 29/09/2026).
            onRemove = if (profile?.avatarUrl != null || pendingAvatar != null) {
                {
                    pendingAvatar = null
                    model.viewModelScope.launch { model.removeAvatar() }
                }
            } else {
                null
            },
        ) { images ->
            val data = images.firstOrNull() ?: return@PhotoFlowHost
            model.viewModelScope.launch {
                val jpeg = withContext(Dispatchers.Default) { ProfileAvatar.jpeg(data) } ?: return@launch
                // Le rond porte la photo **avant** l'aller-retour — voir
                // `ProfileAvatar`.
                pendingAvatar = withContext(Dispatchers.Default) {
                    BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)?.asImageBitmap()
                }
                model.setAvatar(jpeg)
            }
        }

        // MARK: - Feuilles

        BrandSheetHost(
            item = sheet,
            onDismissRequest = { sheet = null },
            // Le temps d'un appel, la feuille ne se referme pas au glissé : un
            // export ou un mot de passe parti à moitié n'a pas de sens.
            dismissDisabled = when (sheet) {
                ProfileSheet.DataExport -> state.dataExport == ProfileModel.DataExportState.Requesting
                ProfileSheet.Password -> passwordState?.isWorking == true
                else -> false
            },
        ) { destination ->
            when (destination) {
                ProfileSheet.PostalAddress -> PostalAddressSheet(
                    address = profile?.address ?: PostalAddress(),
                    countries = profile?.shippingCountries.orEmpty(),
                ) { model.save(it) }
                ProfileSheet.Gender -> GenderSheet(current = profile?.gender ?: Gender.Undisclosed) {
                    model.setGender(it)
                }
                ProfileSheet.Notifications -> AccountNotificationsSheet(model)
                ProfileSheet.Password -> passwordModel?.let { PasswordChangeSheet(it) }
                ProfileSheet.Subscription -> SubscriptionSheet(
                    subscription = effectiveSubscription,
                    onActivate = {
                        model.activateSubscription()
                        subscriptionSession?.record(isSubscribed = true)
                    },
                    onCancel = { reason ->
                        model.cancelSubscription(reason)
                        // **Le mois payé compte comme un abonnement** :
                        // l'illimité reste ouvert jusqu'à sa fin. La session
                        // retient donc l'accès réel, pas le geste — sans ça,
                        // la conversation recompterait les secondes de
                        // quelqu'un qui a encore trois semaines réglées
                        // devant lui.
                        subscriptionSession?.record(
                            isSubscribed = model.subscriptionGrantsAccess,
                            until = model.subscriptionUnlimitedUntil,
                        )
                    },
                    onRecordReason = { model.recordCancellationReason(it) },
                    onAppStoreRenewal = { renews ->
                        // Même règle qu'au-dessus — le mois payé garde
                        // l'illimité, même renouvellement coupé —, sauf pour un
                        // achat que le serveur n'a pas encore reçu : le store
                        // tient la période, la ligne du serveur n'en sait rien.
                        // On remet la transaction et on relit. Voir
                        // `ProfileModel.settleAppStoreRenewal`.
                        if (model.settleAppStoreRenewal(renews, subscriptionSession)) {
                            scope.launch { deliverPurchaseAndReload() }
                        }
                    },
                    gender = profile?.gender ?: Gender.Undisclosed,
                    isHeldByPlay = isHeldByPlay,
                    opensStorePage = opensStorePage,
                )
                ProfileSheet.Connectors -> ConnectorsSheet(model)
                ProfileSheet.Statistics -> StatisticsSheet(statistics)
                ProfileSheet.DataExport -> DataExportSheet(model)
                ProfileSheet.OrderTracking -> OrderTrackingSheet(
                    orders = profile?.orders.orEmpty(),
                    ongoingTrip = profile?.currentTrip,
                    onPlanTrip = {
                        // La feuille se referme **avant** que la galerie
                        // s'ouvre : c'est un écran poussé sur la pile du
                        // profil, pas une feuille de plus.
                        sheet = null
                        onIntent(ProfileIntent.OpenGallery)
                    },
                    onOrder = { trip: CurrentTrip ->
                        sheet = null
                        onIntent(ProfileIntent.OrderBook(memoId = trip.id))
                    },
                    onOrdersChanged = { scope.launch { model.load() } },
                    finishAbandonedOrder = finishAbandonedOrder,
                )
            }
        }

        // Les deux modales dessinées dans Figma (`3203:21809` sans voyage en
        // cours, `3206:21854` avec) remplacent l'alerte du système qui tenait
        // la place — Hugo, 14/09/2026 (T23). C'est une feuille de l'app, avec
        // le paragraphe entier : une alerte n'en tenait qu'un résumé.
        BrandSheetHost(
            isPresented = isConfirmingDeletion,
            onDismissRequest = { isConfirmingDeletion = false },
            dismissDisabled = state.isDeletingAccount,
        ) {
            DeleteAccountSheet(
                hasOngoingTrip = profile?.currentTrip != null,
                mentionsSubscription = renewsAtApple,
                isDeleting = state.isDeletingAccount,
                onKeep = { isConfirmingDeletion = false },
                onDelete = {
                    // Sur la portée du modèle, comme le `Task` d'iOS : la
                    // demande va à son terme.
                    model.viewModelScope.launch {
                        // La sortie est la même que la déconnexion : le compte
                        // n'existe plus, l'app ne peut que revenir à l'entrée.
                        if (model.deleteAccount()) {
                            isConfirmingDeletion = false
                            onSignOut()
                        }
                    }
                },
            )
        }

        BrandAlert(
            isPresented = paymentMethodsError != null,
            title = "Moyens de paiement indisponibles",
            message = paymentMethodsError,
            actions = listOf(BrandAlert.Action("OK", BrandAlert.Role.Cancel)),
            onDismissRequest = { paymentMethodsError = null },
        )

        // Le paywall, plein écran par-dessus le profil — le `fullScreenCover`
        // d'iOS. Il gère lui-même le retour du système.
        AnimatedVisibility(
            visible = showsPaywall,
            enter = slideInVertically(SwiftMotion.smooth(0.35f)) { it } + fadeIn(),
            exit = slideOutVertically(SwiftMotion.smooth(0.3f)) { it } + fadeOut(),
        ) {
            PaywallView(
                subscription = effectiveSubscription,
                variant = paywallVariant,
                previewMemoId = profile?.currentTrip?.id,
                onSubscribe = {
                    // **Le geste, pas une copie locale** (03/10/2026) : la
                    // session fait l'écran d'un abonné tout de suite, et le
                    // profil se relit pour que le serveur le confirme — c'est
                    // cette confirmation qui rend la main au serveur.
                    // Retoucher le profil sur place l'aurait « confirmé » sans
                    // lui, et un serveur qui n'avait pas encore reçu l'achat
                    // aurait fait recompter un abonné qui paie.
                    subscriptionSession?.record(isSubscribed = true)
                    showsPaywall = false
                    scope.launch { model.load() }
                },
                onDismiss = { showsPaywall = false },
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

/** La page elle-même, sous ses feuilles. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProfileContent(
    state: ProfileModel.State,
    isSubscriber: Boolean,
    subscriptionEndLabel: String?,
    pendingAvatar: ImageBitmap?,
    avatarDeniedMessage: String?,
    onBack: () -> Unit,
    onAvatarTap: () -> Unit,
    onOpen: (ProfileSheet) -> Unit,
    onShowPaywall: () -> Unit,
    onIntent: (ProfileIntent) -> Unit,
    onSignOut: () -> Unit,
    onConfirmDeletion: () -> Unit,
    onRetry: () -> Unit,
    onManageCards: () -> Unit,
    onFullName: (String) -> Unit,
    onPhoneNumber: (String) -> Unit,
    onNewsletter: (Boolean) -> Unit,
) {
    val profile = state.profile
    val focusManager = LocalFocusManager.current

    // Faire défiler referme le clavier — et refermer le clavier enregistre la
    // ligne qu'on était en train de corriger. C'est la moitié du contrat des
    // lignes modifiables ; l'autre moitié est dans `BrandRow`. Au premier
    // glissé du doigt, et pas à la fin : une ligne corrigée ne doit pas rester
    // en attente pendant qu'on lit le bas de l'écran.
    val dismissesKeyboard = remember(focusManager) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y != 0f) focusManager.clearFocus()
                return Offset.Zero
            }
        }
    }

    BrandRefreshFlash(state.freshness.isUpdated, Modifier.fillMaxSize()) {
        // **L'écran se dessine tout de suite, entier.** Il n'attendait rien de
        // tout ça : ses intitulés, ses groupes, ses boutons et ses actions de
        // sortie appartiennent à l'app, pas au serveur. Seules les valeurs
        // viennent du réseau, et elles seules portent une barre d'attente —
        // voir `BrandSkeleton`.
        //
        // Trois blocs font exception et n'apparaissent qu'une fois le profil
        // connu, parce qu'ils **existent ou non** selon que le compte est
        // abonné : la pastille « Abonné(e) », le bouton « Découvrir
        // l'abonnement » et la ligne « Mon abonnement ». Les montrer par
        // défaut puis les retirer serait pire que de les voir arriver.
        Column(
            Modifier
                .fillMaxSize()
                .nestedScroll(dismissesKeyboard)
                .verticalScroll(rememberScrollState())
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(top = MemoBookSpacing.xs, bottom = MemoBookSpacing.l)
                .animateContentSize(SwiftMotion.snappy(0.25f)),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
        ) {
            ProfileHeader(profile = profile, isSubscriber = isSubscriber, onBack = onBack)

            Identity(
                state = state,
                pendingAvatar = pendingAvatar,
                deniedMessage = avatarDeniedMessage,
                onAvatarTap = onAvatarTap,
                onFullName = onFullName,
            )

            // Le gros bouton lime de la maquette, et **rien d'autre
            // au-dessus** : pour quelqu'un qui n'a pas d'abonnement, c'est la
            // première chose de l'écran après son nom.
            //
            // Il disparaît une fois abonné, où la ligne « Mon abonnement » des
            // services suffit : on ne revend pas ce qui est déjà acheté. C'est
            // aussi ce qui fait que **résilier le fait revenir** — une fois le
            // mois payé écoulé, le profil n'a plus d'abonnement, et l'offre
            // reprend sa place.
            //
            // **Il ouvre le paywall directement** (Hugo, 03/10/2026) : la
            // feuille « Comment ça fonctionne ? » qui le précédait racontait
            // l'essai gratuit d'avant le crédit du jour, et elle est partie
            // avec lui.
            if (!isSubscriber) {
                // La même limite que les autres CTA de l'app (accueil, offre) :
                // en très grand texte, « Découvrir l’abonnement » se coupait en
                // plein mot (recette du 03/10/2026). TalkBack lit le libellé
                // entier quelle que soit la taille.
                CappedFontScale(CTA_MAXIMUM_FONT_SCALE) {
                    BrandButton(
                        "Découvrir l’abonnement",
                        icon = painterResource(R.drawable.icon_arrow_forward),
                        iconPlacement = BrandButton.IconPlacement.Trailing,
                        style = BrandButton.Style.Accent,
                        fillsWidth = true,
                        action = onShowPaywall,
                    )
                }
            }

            StatsGroup(profile, onOpen = onOpen, onIntent = onIntent)
            ContactGroup(state, onOpen = onOpen, onPhoneNumber = onPhoneNumber, onNewsletter = onNewsletter)
            ServicesGroup(showsSubscription = profile != null && isSubscriber, subscriptionEndLabel = subscriptionEndLabel, onOpen = onOpen)
            PaymentGroup(isLoading = profile == null, onManageCards = onManageCards)
            LegalGroup(onIntent)

            // **À venir** (Hugo, 08/10/2026) : les connecteurs ne se branchent
            // pas encore au serveur (T76). La carte se montre dans la version
            // livrée aussi — elle ne vivait qu'en Debug depuis le 29/09 —, avec
            // sa pastille, et ouvre la liste de ce qui arrive, pâli.
            ConnectorsCallout { onOpen(ProfileSheet.Connectors) }

            state.errorMessage?.let { message -> ErrorBanner(message, retry = onRetry) }

            // Le même lien qu'en bas de l'accueil, dans le même dessin : c'est
            // la sortie de secours de l'app, et il mène désormais au support.
            //
            // Il passe **avant** les actions de sortie, et pas après : demander
            // de l'aide n'est pas quitter. Le laisser sous « Supprimer mon
            // compte » le rangeait avec les portes de sortie, alors qu'il est
            // là pour éviter d'en prendre une.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                BrandButton("Besoin d’aide ?", style = BrandButton.Style.Link, isSubdued = true) {
                    onIntent(ProfileIntent.OpenHelp)
                }
            }

            ExitActions(
                isDeletingAccount = state.isDeletingAccount,
                onExport = { onOpen(ProfileSheet.DataExport) },
                onSignOut = onSignOut,
                onDelete = onConfirmDeletion,
            )

            // La mention de bas de page. **Du texte, et rien d'autre** : ni
            // bouton, ni lien, ni cible tactile — on la lit une fois, on
            // n'appuie jamais dessus. Elle ferme l'écran, sous le dernier
            // bouton.
            BrandText(
                "MemoBook v1.0 | Tous droits réservés",
                MemoBookFont.mention,
                Modifier
                    .fillMaxWidth()
                    .padding(top = MemoBookSpacing.s),
                color = MemoBookColor.inkFaint,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** Le cran de texte où le CTA de l'abonnement s'arrête de grandir — l'`accessibility1` d'iOS. */
private const val CTA_MAXIMUM_FONT_SCALE = 1.5f

/** Le cran où la pastille « ABONNÉ(E) » s'arrête de grandir — le `xxxLarge` d'iOS. */
private const val PILL_MAXIMUM_FONT_SCALE = 1.35f

/**
 * Le `.dynamicTypeSize(...)` d'iOS : ce qui est dedans cesse de grandir passé
 * un cran de texte — le reste de l'écran, lui, continue.
 */
@Composable
private fun CappedFontScale(maximum: Float, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    if (density.fontScale <= maximum) {
        content()
        return
    }
    CompositionLocalProvider(LocalDensity provides Density(density.density, maximum), content = content)
}

// MARK: - En-tête

@Composable
private fun ProfileHeader(profile: TravellerProfile?, isSubscriber: Boolean, onBack: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
        // La cible tactile est alignée à gauche sur la marge de la colonne, et
        // le dessin est centré dedans. Elle débordait de la colonne ; la
        // moitié gauche des touches tombait alors à côté, et le retour ne
        // marchait qu'une fois sur deux.
        Box(
            Modifier
                .size(MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = onBack,
                )
                .semantics { contentDescription = "Retour" },
            contentAlignment = Alignment.Center,
        ) {
            // La bichrome : c'est le seul retour de l'écran, et la maquette le
            // pose en bleu.
            Image(
                painterResource(R.drawable.icon_arrow_duo),
                contentDescription = null,
                modifier = Modifier.size(MemoBookSpacing.navigationIcon),
            )
        }

        // « Profil », en français : la maquette écrivait « Profile », et Clara
        // l'a corrigée (14/09/2026, T17).
        BrandText("Profil", MemoBookFont.h2, Modifier.semantics { heading() })

        Spacer(Modifier.weight(1f))

        // « ABONNÉ(E) », sur la ligne du titre — **pour un abonné seulement**
        // (Hugo, 03/10/2026). Il n'y a plus d'étapes à décompter : sans
        // abonnement, c'est le bouton « Découvrir l'abonnement » qui parle,
        // et la pastille se tait. Un constat, qui ne mène nulle part.
        //
        // **Elle partage la ligne du titre et ne flotte pas dans le coin** :
        // c'est une étiquette posée sur l'écran, droite parce qu'alignée sur
        // un titre. À partir des tailles accessibles elle prendrait la ligne
        // entière et pousserait le titre hors de l'écran : elle garde alors
        // sa taille, et elle seule.
        if (profile != null && isSubscriber) {
            CappedFontScale(PILL_MAXIMUM_FONT_SCALE) {
                BrandTagPill(
                    SubscriptionCopy.currentBadge(profile.gender),
                    tone = BrandTagPill.Tone.AccentOutlined,
                    isUppercased = true,
                    // Elle se resserre plutôt que de renvoyer « Profil » à la ligne.
                    shrinksToFit = true,
                )
            }
        }
    }
}

// MARK: - Qui l'on est

@Composable
private fun Identity(
    state: ProfileModel.State,
    pendingAvatar: ImageBitmap?,
    deniedMessage: String?,
    onAvatarTap: () -> Unit,
    onFullName: (String) -> Unit,
) {
    val profile = state.profile
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            ProfileAvatar(profile = profile, pending = pendingAvatar, isUploading = state.isUploadingAvatar, onTap = onAvatarTap)

            deniedMessage?.let { BrandNotice(it, tone = BrandNotice.Tone.Information) }

            // L'échec se dit là où l'on a touché — voir
            // `ProfileModel.State.avatarErrorMessage`. « Réessayer » rouvre la
            // feuille : on ne sait pas si c'était un envoi ou un retrait.
            state.avatarErrorMessage?.let { ErrorBanner(it, retry = onAvatarTap) }
        }

        if (profile != null) {
            EditableName(name = profile.fullName, onCommit = onFullName)
        } else {
            // Le nom est un titre : sa barre d'attente est plus large et
            // centrée comme lui, pour que la page ne se recompose pas quand il
            // arrive.
            BrandSkeleton(width = 180.dp, height = MemoBookSpacing.m)
        }
    }
}

/**
 * Le nom du voyageur, corrigeable sur place.
 *
 * C'est toujours un champ de saisie, jamais un texte qu'on remplace par un
 * champ : le dessin est le même dans les deux états, et le crayon n'a pas à
 * faire apparaître quoi que ce soit — il donne juste le focus. Sans lui, rien
 * ne dirait que ce nom se corrige.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditableName(name: String, onCommit: (String) -> Unit) {
    // Ce qu'on est en train de taper. Le modèle ne change qu'à la sortie du
    // champ. Le curseur part du bout du nom, comme sur iOS.
    var draft by remember { mutableStateOf(TextFieldValue(name, TextRange(name.length))) }
    // Deux états distincts, et non un seul : le champ n'existe que pendant
    // l'édition, donc on ne peut pas lui donner le focus avant de l'avoir
    // posé. Le premier ouvre l'édition, le second suit le clavier.
    var isEditing by remember { mutableStateOf(false) }
    var hadFocus by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val commit by rememberUpdatedState(onCommit)
    // **Petit**, comme celui des lignes (`BrandRow`) : 1 rem de dessin, sans
    // cerne ni fond, dans une cible de 48 — Hugo, 14/09/2026 (T24).
    val pencilSide = scaled(16.dp)

    LaunchedEffect(name) { if (!isEditing) draft = TextFieldValue(name, TextRange(name.length)) }

    fun beginEditing() {
        if (isEditing) return
        draft = TextFieldValue(name, TextRange(name.length))
        hadFocus = false
        isEditing = true
    }

    fun endEditing() {
        if (!isEditing) return
        isEditing = false
        commit(draft.text)
    }

    // Le champ n'est posé qu'au rendu suivant : lui donner le focus tout de
    // suite ne toucherait rien.
    LaunchedEffect(isEditing) { if (isEditing) focusRequester.requestFocus() }

    // Android : le retour referme le clavier **sans ôter le focus**, là où iOS
    // le rend. Sans ce relais, la correction ne s'enregistrerait jamais.
    val imeVisible = WindowInsets.isImeVisible
    LaunchedEffect(imeVisible) { if (!imeVisible && isEditing) focusManager.clearFocus() }

    // Même contrat que les lignes : quitter l'écran en éditant enregistre.
    DisposableEffect(Unit) { onDispose { if (isEditing) commit(draft.text) } }

    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        // Le nom se centre dans la colonne entière, et laisse de chaque côté la
        // place du crayon : c'est cette limite qui déclenche la coupure du
        // texte au lieu de le laisser filer dessous.
        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = MemoBookSpacing.minimumTapTarget),
            contentAlignment = Alignment.Center,
        ) {
            if (isEditing) {
                // Pendant l'édition, le champ prend toute la place restante :
                // on doit pouvoir lire ce qu'on tape, y compris au-delà de ce
                // que la vue au repos montrait.
                BasicTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequester)
                        // `onFocusChanged` se lit aussi à la pose du champ,
                        // avant qu'il ait le focus : seule une vraie perte
                        // referme l'édition.
                        .onFocusChanged { focus ->
                            if (focus.isFocused) {
                                hadFocus = true
                            } else if (hadFocus) {
                                hadFocus = false
                                endEditing()
                            }
                        }
                        .semantics { contentDescription = "Ton nom" },
                    textStyle = MemoBookFont.h2.copy(color = MemoBookColor.ink, textAlign = TextAlign.Center),
                    singleLine = true,
                    cursorBrush = SolidColor(MemoBookColor.action),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                )
            } else {
                // Le nom au repos. **Aucune limite de caractères** : c'est la
                // largeur disponible qui décide, et un nom trop long se termine
                // par des points de suspension plutôt que de pousser le crayon
                // hors de l'écran.
                BrandText(
                    name,
                    MemoBookFont.h2,
                    Modifier
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = ::beginEditing,
                        )
                        .semantics { contentDescription = "Ton nom, $name" },
                    maxLines = 1,
                    textAlign = TextAlign.Center,
                )
            }
        }

        // Le crayon est **au bord droit de la colonne**, à l'aplomb des
        // chevrons et des crayons des lignes du dessous — pas collé au nom, qui
        // se décalerait avec lui à chaque lettre (T24).
        Box(
            Modifier
                .align(Alignment.CenterEnd)
                .size(MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClick = ::beginEditing,
                )
                .semantics { contentDescription = "Modifier ton nom" },
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.icon_pen),
                contentDescription = null,
                colorFilter = ColorFilter.tint(if (isEditing) MemoBookColor.action else MemoBookColor.inkMuted),
                modifier = Modifier.size(pencilSide),
            )
        }
    }
}

/**
 * La photo du voyageur, ou ses initiales. Jamais un rond gris vide : un profil
 * sans photo reste un profil.
 *
 * Tant que le profil n'est pas arrivé, le rond est là quand même, vide : c'est
 * **la seule valeur de l'écran qui n'a pas besoin de barre d'attente**, parce
 * qu'un rond vide est déjà exactement ce qu'on verra si la personne n'a pas de
 * photo. Rien ne bouge quand elle arrive.
 *
 * @param pending la photo qu'on vient de choisir, avant même que le serveur
 *   l'ait reçue. **Elle se pose tout de suite** (Hugo, 19/09/2026). Le rond
 *   n'affichait que `avatarUrl`, c'est-à-dire la photo *du serveur* : entre le
 *   moment où l'on choisit dans sa galerie et celui où l'API répond, le rond
 *   gardait ses initiales — et si l'API déployée ne sert pas encore les
 *   avatars, il les gardait pour toujours. On montre donc ce qu'on vient de
 *   choisir, et l'adresse distante prend le relais quand elle arrive : elle se
 *   pose par-dessus.
 * @param isUploading la photo est en route : le rond s'assombrit et tourne.
 * @param onTap le rond **se touche** : il ouvre la feuille « Prendre une photo
 *   / Choisir dans la galerie » (Clara, 17/09/2026, T165).
 */
@Composable
private fun ProfileAvatar(profile: TravellerProfile?, pending: ImageBitmap?, isUploading: Boolean, onTap: () -> Unit) {
    // Taille **fixe**, comme l'avatar de l'accueil. Une photo n'est pas du
    // texte : la faire grandir avec la taille de police lui faisait prendre la
    // moitié de l'écran aux tailles accessibles, au détriment de ce qui, lui,
    // se lit.
    val side = ProfileAvatar.side
    Box(
        Modifier
            .size(side)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                enabled = !isUploading && profile != null,
                role = Role.Button,
                onClickLabel = "Prendre une photo, en choisir une dans la galerie, ou retirer celle-ci",
                onClick = onTap,
            )
            .semantics { contentDescription = "Photo de profil" },
    ) {
        Box(
            Modifier
                .size(side)
                .clip(CircleShape)
                .background(MemoBookColor.outline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (pending != null) {
                Image(pending, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(side))
            } else {
                // Les initiales suivent le texte — mais dans un cadre qui ne
                // bouge pas : elles se réduisent plutôt que de déborder du rond.
                BrandText(
                    profile?.initials.orEmpty(),
                    MemoBookFont.h2,
                    Modifier.padding(horizontal = MemoBookSpacing.xs),
                    maxLines = 1,
                    minimumScaleFactor = 0.5f,
                )
            }
            profile?.avatarUrl?.let { url ->
                AsyncImage(
                    model = url.toString(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(side),
                )
            }
            if (isUploading) {
                Box(Modifier.size(side).background(MemoBookColor.ink.copy(alpha = 0.35f), CircleShape))
                ActivitySpinner(MemoBookColor.onAction)
            }
        }

        // Le petit crayon cerclé, à cheval sur le bord du rond : c'est lui qui
        // dit que la photo se change — le même dessin que les crayons des
        // couvertures.
        Box(
            Modifier
                .align(Alignment.BottomEnd)
                .offset(4.dp, 4.dp)
                .size(MemoBookSpacing.m + 4.dp)
                .background(MemoBookColor.surface, CircleShape)
                .border(1.5.dp, MemoBookColor.outline, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Image(
                painterResource(R.drawable.icon_pen),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.action),
                modifier = Modifier.size(MemoBookSpacing.snug),
            )
        }
    }
}

internal object ProfileAvatar {
    /** Le rond fait 80, fixe. */
    val side = 80.dp

    /**
     * Le plus grand côté envoyé au serveur. Le rond fait 80, l'accueil 40 :
     * 512 px couvre trois fois l'écran le plus dense, et pèse quelques
     * dizaines de kilo-octets au lieu des mégaoctets d'une photo de téléphone.
     */
    private const val UPLOAD_SIDE = 512

    /**
     * Réduit la photo choisie à ce que le serveur a besoin de garder, en JPEG.
     * `null` si ce n'est pas une image lisible.
     */
    fun jpeg(data: ByteArray): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        // Un premier sous-échantillonnage par puissances de deux : décoder une
        // photo de 48 Mpx entière pour en garder 512 px ne tiendrait pas en
        // mémoire.
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= UPLOAD_SIDE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(data, 0, data.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val longest = max(decoded.width, decoded.height)
        val scale = min(1f, UPLOAD_SIDE / max(longest, 1).toFloat())
        val resized = if (scale < 1f) {
            Bitmap.createScaledBitmap(decoded, (decoded.width * scale).roundToInt(), (decoded.height * scale).roundToInt(), true)
        } else {
            decoded
        }
        return ByteArrayOutputStream().use { out ->
            resized.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        }
    }
}

// MARK: - Les groupes de lignes

/**
 * Les chiffres du compte : combien de voyages, et lequel est en cours.
 *
 * **Le seul groupe cerclé de vert de l'écran.** C'est ce qu'on vient chercher
 * du regard en ouvrant son profil ; tout le reste se range.
 *
 * **Les statistiques sont à tout le monde** (Hugo, 03/10/2026) : elles étaient
 * « Réservé aux abonnés », sous un badge « Locked ». L'abonnement n'ouvre plus
 * que l'illimité.
 */
@Composable
private fun StatsGroup(profile: TravellerProfile?, onOpen: (ProfileSheet) -> Unit, onIntent: (ProfileIntent) -> Unit) {
    val isLoading = profile == null
    val currentTrip = profile?.let { it.currentTrip?.dateRangeLabel ?: "Aucun pour l’instant" }
    // Le voyage en cours s'ouvre depuis sa ligne — l'accueil du voyage, celui
    // de la carte de l'accueil (Clara, 17/09/2026).
    val openCurrentTrip = profile?.currentTrip?.let { trip -> { onIntent(ProfileIntent.OpenTrip(trip.id)) } }

    BrandRowGroup(tone = BrandRowGroup.Tone.Highlighted) {
        // ⚠️ La feuille existait et ne s'ouvrait plus : la ligne était revenue
        // sur `notYetRouted()` (constaté en recette le 30/09/2026).
        +BrandRow(
            "Statistiques",
            value = profile?.tripCountLabel,
            titleTone = BrandRow.TitleTone.Accent,
            isValueLoading = isLoading,
            action = { onOpen(ProfileSheet.Statistics) },
        )
        // La ligne reste, même sans voyage en cours : sa disparition ferait
        // sauter la carte d'une hauteur de ligne à chaque chargement. Elle dit
        // alors qu'il n'y en a pas.
        +BrandRow(
            "Voyage en cours",
            value = currentTrip,
            titleTone = BrandRow.TitleTone.Accent,
            isValueLoading = isLoading,
            action = openCurrentTrip,
        )
    }
}

@Composable
private fun ContactGroup(
    state: ProfileModel.State,
    onOpen: (ProfileSheet) -> Unit,
    onPhoneNumber: (String) -> Unit,
    onNewsletter: (Boolean) -> Unit,
) {
    val profile = state.profile
    // L'interrupteur est le seul contrôle du groupe qui **agit** avant que la
    // valeur soit là : le basculer sur un profil pas encore chargé enverrait
    // un réglage qu'on n'a pas lu. Le groupe entier attend, ce qui ne coûte
    // rien — les autres lignes ne font qu'ouvrir des feuilles.
    val opens: (ProfileSheet) -> () -> Unit = { destination -> { if (profile != null) onOpen(destination) } }

    BrandRowGroup {
        // **L'adresse se lit, elle ne se corrige pas.** Elle n'est pas un champ
        // de plus : c'est l'identifiant de connexion. En changer demande de
        // vérifier la nouvelle, de refuser celles déjà prises et de décider du
        // sort de la session ouverte avec l'ancienne — un écran à part
        // entière, que cette ligne ne peut pas tenir.
        //
        // **Le fournisseur se dit, il ne se dessine pas** (Hugo, 19/09/2026).
        // Trois mots en gris sous l'adresse disent d'où elle vient sans rien
        // salir — et l'adresse, elle, garde toute la ligne et s'abrège par la
        // fin si elle est longue.
        +BrandRow(
            "E-mail",
            value = profile?.email,
            isValueLoading = profile == null,
            note = profile?.signInProvider?.let { "Compte ${it.displayName}" },
        )
        // Sous l'adresse, **quand le compte a un mot de passe** (Hugo,
        // 29/09/2026) : un compte entré par Apple ou Google seul n'en a pas à
        // changer. La valeur est un masque — on ne montre jamais rien.
        if (profile?.hasPassword == true) {
            +BrandRow("Mot de passe", value = "••••••••", action = opens(ProfileSheet.Password))
        }
        +BrandRow(
            "Téléphone",
            text = profile?.phoneNumber.orEmpty(),
            onTextChange = onPhoneNumber,
            placeholder = "+33 6 00 00 00 00",
            keyboardType = KeyboardType.Phone,
            textContentType = ContentType.PhoneNumber,
            isValueLoading = profile == null,
            isConfirmed = state.justSaved == ProfileModel.SavedField.PhoneNumber,
        )
        // Sans adresse, la ligne **invite** à en donner une, en vert et un cran
        // plus petit — Hugo, 14/09/2026 (T22). Une valeur vide se lisait comme
        // une ligne cassée.
        //
        // Avec une adresse, la ligne la résume et **la rouvre** : c'est la même
        // feuille qui corrige. La coche dit que le serveur l'a bien reçue — la
        // feuille s'est refermée avant sa réponse.
        val hasAddress = profile?.address?.singleLine?.isNotEmpty() == true
        +BrandRow(
            "Adresse postale",
            value = profile?.let { if (hasAddress) it.address.singleLine else "Ajouter une adresse" },
            valueTone = if (hasAddress) BrandRow.ValueTone.Plain else BrandRow.ValueTone.Invitation,
            isValueLoading = profile == null,
            isConfirmed = state.justSaved == ProfileModel.SavedField.Address,
            action = opens(ProfileSheet.PostalAddress),
        )
        // Juste sous l'adresse (Hugo, 17/09/2026, T76) : deviné sur le prénom
        // par le serveur, corrigé ici. Voir `Gender`.
        +BrandRow(
            "Genre",
            value = profile?.gender?.label,
            isValueLoading = profile == null,
            action = opens(ProfileSheet.Gender),
        )
        +BrandRow("Newsletter mensuelle MemoBook", isOn = profile?.wantsNewsletter ?: false, onIsOnChange = onNewsletter)
        // Les notifications du compte — celles qui ne parlent d'aucun voyage
        // (D13, Hugo, 19/10/2026). Sous la newsletter : ce sont les deux
        // façons dont MemoBook vient te chercher. La coche dit que le serveur
        // a reçu la dernière bascule de la feuille.
        +BrandRow(
            AccountNotificationsCopy.rowTitle,
            value = profile?.let { AccountNotificationsCopy.summary(it.notifications) },
            isValueLoading = profile == null,
            isConfirmed = state.justSaved == ProfileModel.SavedField.Notifications,
            action = opens(ProfileSheet.Notifications),
        )
    }
}

@Composable
private fun ServicesGroup(showsSubscription: Boolean, subscriptionEndLabel: String?, onOpen: (ProfileSheet) -> Unit) {
    // « Ma cagnotte » ouvrait ce groupe ; elle est partie avec la cagnotte
    // (Hugo, 06/10/2026, T230).
    BrandRowGroup {
        // Elle ne s'affiche qu'une fois abonné : sans abonnement, c'est le
        // bouton lime du haut qui porte la proposition, et deux entrées vers la
        // même feuille sur un même écran se marcheraient dessus.
        //
        // **Renouvellement coupé, elle dit jusqu'à quand** (06/10/2026) :
        // « Jusqu’au 12 octobre » — puis elle disparaît avec l'illimité.
        if (showsSubscription) {
            +BrandRow("Mon abonnement", value = subscriptionEndLabel, action = { onOpen(ProfileSheet.Subscription) })
        }
        +BrandRow("Suivi des commandes", action = { onOpen(ProfileSheet.OrderTracking) })
        // « Confidentialité » n'est plus ici : la maquette la montrait dans ce
        // groupe **et** dans celui des conditions d'utilisation, et c'est une
        // erreur — elle ne vit que là-bas (Hugo, 14/09/2026, T18).
    }
}

/**
 * **Les cartes du compte, chez Stripe** (01/10/2026). La ligne ouvrait un
 * formulaire fait main qui demandait le numéro complet et ne parlait à
 * personne ; elle ouvre désormais la feuille « Moyens de paiement » de Stripe,
 * qui tient les cartes, en ajoute et en retire. L'app ne voit plus passer un
 * seul numéro — et ne sait donc plus en afficher un ici : la ligne **invite**,
 * comme celle de l'adresse (T22).
 */
@Composable
private fun PaymentGroup(isLoading: Boolean, onManageCards: () -> Unit) {
    BrandRowGroup {
        +BrandRow(
            "Cartes bancaires",
            value = "Gérer mes cartes",
            valuePlacement = BrandRow.ValuePlacement.Below,
            valueTone = BrandRow.ValueTone.Invitation,
            isValueLoading = isLoading,
            action = onManageCards,
        )
    }
}

@Composable
private fun LegalGroup(onIntent: (ProfileIntent) -> Unit) {
    BrandRowGroup {
        +BrandRow("Confidentialité", action = { onIntent(ProfileIntent.OpenPrivacyPolicy) })
        +BrandRow(TermsOfUse.document.title, action = { onIntent(ProfileIntent.OpenTermsOfUse) })
    }
}

// MARK: - Sortir

@Composable
private fun ExitActions(isDeletingAccount: Boolean, onExport: () -> Unit, onSignOut: () -> Unit, onDelete: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = MemoBookSpacing.xs),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        // `Export data.svg`, dessiné pour cette ligne (Clara, 17/09/2026,
        // T162) — `Export.svg` est le partage d'un fichier. Le halo orange que
        // l'export portait autour du signe est retiré du fichier : la ligne se
        // dessine comme les deux d'en dessous, le signe seul dans sa teinte
        // (Hugo, 18/09/2026). Le lien part par e-mail ; l'archive se compose
        // quand on l'ouvre — voir `DataExportSheet`.
        ProfileExitAction(R.drawable.icon_export_data, "Exporter mes données", tint = MemoBookColor.warning, action = onExport)
        ProfileExitAction(R.drawable.icon_exit, "Me déconnecter", tint = MemoBookColor.ink, action = onSignOut)
        // La confirmation est ici, pas dans le modèle : après elle, il n'y a
        // plus rien à annuler.
        ProfileExitAction(
            R.drawable.icon_cross,
            "Supprimer mon compte",
            tint = MemoBookColor.error,
            isDestructive = true,
            enabled = !isDeletingAccount,
            action = onDelete,
        )
    }
}

/**
 * Une action de sortie : une icône, un mot, centrés. Ni carte ni bouton plein
 * — on ne met pas en avant la porte de sortie.
 */
@Composable
private fun ProfileExitAction(
    icon: Int,
    title: String,
    tint: Color,
    isDestructive: Boolean = false,
    enabled: Boolean = true,
    action: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                enabled = enabled,
                role = Role.Button,
                onClick = action,
            ),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Image(
            painterResource(icon),
            contentDescription = null,
            colorFilter = ColorFilter.tint(tint),
            modifier = Modifier.size(MemoBookSpacing.contentIcon),
        )
        // Sora, comme les libellés de bouton de la marque : ce sont des
        // boutons, pas des lignes de réglage. Voir `MemoBookFont.button`.
        BrandText(title, MemoBookFont.button, color = if (isDestructive) MemoBookColor.error else MemoBookColor.ink)
    }
}

/**
 * La carte bleue qui invite à brancher MemoBook sur le reste de ses apps.
 *
 * Elle n'est pas une ligne de plus dans un groupe : c'est une proposition, et
 * c'est l'aplat bleu qui le dit. Elle s'enfonce légèrement sous le doigt, sans
 * changer d'opacité : c'est du papier, pas un bouton (le `CardPressStyle`
 * d'iOS).
 */
@Composable
private fun ConnectorsCallout(action: () -> Unit) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val interaction = remember { MutableInteractionSource() }
    val isPressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.985f else 1f, SwiftMotion.smooth(0.18f), label = "carte")

    Box {
        Column(
            Modifier
                .fillMaxWidth()
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .background(MemoBookColor.outline.copy(alpha = 0.35f), shape)
                .border(1.dp, MemoBookColor.outline, shape)
                .clip(shape)
                .clickable(interactionSource = interaction, indication = null, onClick = action)
                .padding(MemoBookSpacing.s)
                .clearAndSetSemantics {
                    contentDescription = "${ConnectorsCopy.title}, ${ConnectorsCopy.promise}"
                    stateDescription = BrandComingSoonBadge.defaultLabel
                    role = Role.Button
                    onClick { action(); true }
                },
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        ) {
            val icon: @Composable () -> Unit = {
                Image(
                    painterResource(R.drawable.icon_plus),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.ink),
                    modifier = Modifier.size(MemoBookSpacing.contentIcon),
                )
            }
            val label: @Composable () -> Unit = { BrandText(ConnectorsCopy.title, MemoBookFont.bodySemibold) }
            if (isAccessibilityTextSize()) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    icon()
                    label()
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.CenterVertically) {
                    icon()
                    label()
                }
            }
            BrandText(ConnectorsCopy.promise, MemoBookFont.body, Modifier.fillMaxWidth(), color = MemoBookColor.blueText)
        }

        // La carte reste une porte — elle ouvre la liste de ce qui arrive —, et
        // sa pastille dit d'avance que rien ne s'y branche encore.
        BrandComingSoonBadge(
            Modifier
                .align(Alignment.TopEnd)
                .padding(end = MemoBookSpacing.snug)
                .offset(y = -MemoBookSpacing.xs),
        )
    }
}

/**
 * Les libellés des connecteurs, partagés par la carte du profil et la feuille
 * qu'elle ouvre : la promesse doit être **exactement la même** des deux côtés.
 */
internal object ConnectorsCopy {
    const val title = "Ajouter des connecteurs"

    /**
     * La copie corrigée dans Figma le 14/09/2026 (T17) : « à », « permet »,
     * et le tutoiement de R9. Elle a longtemps été recopiée avec ses trois
     * coquilles, parce que R8 interdit de corriger en silence.
     */
    const val promise =
        "Connecter MemoBook à des applications externes te permet d’étoffer tes aventures de manière intelligente."
}

/** Où mène chaque ligne du profil. */
enum class ProfileSheet {
    PostalAddress,
    Gender,
    Notifications,
    Password,
    Subscription,
    Connectors,
    OrderTracking,
    Statistics,
    DataExport,
}

// MARK: - Aperçus

@Preview(locale = "fr-rFR", name = "Profil", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewPreview() {
    ProfileView(remember { ProfileModel() }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Profil — sans abonnement", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewFreePreview() {
    ProfileView(remember { ProfileModel(source = { TravellerProfile.freeFixture }) }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Profil — abonné", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewSubscriberPreview() {
    ProfileView(remember { ProfileModel(source = { TravellerProfile.subscriberFixture }) }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Profil — entré par Apple", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewApplePreview() {
    ProfileView(remember { ProfileModel(source = { TravellerProfile.appleFixture }) }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Profil — compte neuf", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewEmptyPreview() {
    ProfileView(remember { ProfileModel(source = { TravellerProfile.emptyFixture }) }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}

@Preview(locale = "fr-rFR", name = "Profil — erreur", widthDp = 390, heightDp = 1400)
@Composable
private fun ProfileViewErrorPreview() {
    ProfileView(
        remember { ProfileModel(source = { throw java.io.IOException("Connexion impossible. Vérifie ton réseau.") }) },
        remember { StatisticsModel() },
        onSignOut = {},
        onBack = {},
    )
}

@Preview(locale = "fr-rFR", name = "Profil — AX3", widthDp = 390, heightDp = 2000, fontScale = 2f)
@Composable
private fun ProfileViewLargePreview() {
    ProfileView(remember { ProfileModel() }, remember { StatisticsModel() }, onSignOut = {}, onBack = {})
}
