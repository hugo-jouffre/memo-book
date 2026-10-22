package com.memobook.feature.welcome

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Account
import com.memobook.design.BrandScrollWithoutBounce
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.InMemoryAppSettings
import com.memobook.feature.auth.AppleSignInError
import com.memobook.feature.auth.AppleSignInService
import com.memobook.feature.auth.AuthModel
import com.memobook.feature.auth.GoogleSignInService
import com.memobook.feature.auth.previewApi
import com.memobook.feature.auth.rememberLast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.net.URI

/**
 * L'écran d'entrée de MemoBook : ce que l'app fait, en trois mots, et les deux
 * façons d'entrer sans taper quoi que ce soit. Jumeau de `WelcomeView.swift`.
 *
 * **C'est la seule porte de l'app**, et c'est ce qui a changé : Apple et Google
 * ne vivent plus dans le formulaire, ils vivent ici. Le formulaire — inscription
 * et connexion par e-mail — est devenu un écran poussé, qu'on atteint par
 * « S'inscrire avec un e-mail » et qu'on quitte par une flèche de retour.
 *
 * **Une photo, puis une carte posée dessus.** L'image tient le haut de l'écran
 * et ne bouge pas ; la carte crème monte par-dessus, coins arrondis et ombre
 * portée vers le haut. Sur un grand écran elle se pose au bas de la dalle et
 * laisse voir la photo ; sur un petit téléphone le contenu dépasse et défile —
 * la carte glisse alors sur la photo au lieu de la pousser, ce qui garde le
 * haut de l'écran habité.
 *
 * **Rien n'attend le réseau.** Aucun appel n'est fait ici : l'écran est
 * entièrement dessiné par l'app, et les deux boutons n'ouvrent leur feuille
 * qu'au doigt. C'est le premier écran, celui qu'on voit avant d'avoir un
 * compte : il doit apparaître à l'ouverture de l'app, pas après un
 * aller-retour.
 *
 * @param onAuthenticated un fournisseur tiers a répondu, et le serveur a ouvert la session.
 * @param onEmail « S'inscrire avec un e-mail » — l'écran poussé qui porte le formulaire.
 * @param onTermsOfUse « Conditions d'utilisation », dans la mention légale (T151).
 * @param googleWebClientId l'audience des jetons Google. `null` : pas de bouton Google.
 * @param apple le Services ID et l'adresse de retour de l'entrée par Apple sur
 *   le web. `null` : pas de bouton Apple (lot B2).
 * @param showsTestingMode le `#if DEBUG` d'iOS : l'entrée de chantier par le
 *   compte de test, dans un build débogable seulement.
 */
@Composable
fun WelcomeView(
    model: AuthModel,
    onAuthenticated: (Account) -> Unit,
    onEmail: () -> Unit,
    onTermsOfUse: () -> Unit = {},
    googleWebClientId: String? = null,
    apple: AppleEntry? = null,
    showsTestingMode: Boolean = false,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    fun signInWithGoogle() {
        scope.launch {
            try {
                // `null` : l'utilisateur a refermé la feuille. Rien à dire.
                val credential = GoogleSignInService.signIn(context, googleWebClientId) ?: return@launch
                model.accept(credential)?.let(onAuthenticated)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                model.report(error)
            }
        }
    }

    fun signInWithApple() {
        val entry = apple ?: return
        val page = model.beginAppleSignIn(entry.servicesId, entry.redirectUri)
        // Le retour (`memobook://auth/apple…`) arrive avec le lot B2 — voir `AppleSignInService`.
        if (!AppleSignInService.open(context, page)) model.report(AppleSignInError.NotHandled)
    }

    fun signInAsTestAccount() {
        scope.launch { model.signInAsTestAccount()?.let(onAuthenticated) }
    }

    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            // Le crème de la marque ne se retourne pas en sombre.
            .background(MemoBookColor.background),
    ) {
        val screenHeight = maxHeight
        val isCompact = screenHeight < WelcomeLayout.compactHeight
        val revealRatio = if (isCompact) WelcomeLayout.compactHeroRevealRatio else WelcomeLayout.heroRevealRatio

        Hero(Modifier.fillMaxSize())

        // **La carte bloque en bas** (Clara, 17/09/2026) : une fois entièrement
        // montrée, on ne tire plus vers le haut — ni élastique, ni étirement.
        BrandScrollWithoutBounce {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                // Ce qu'on laisse voir de la photo. Sur un grand écran, la carte
                // se pose au bas de la dalle et la photo prend tout le reste ;
                // sur un petit, la réserve tombe à son minimum et la carte
                // défile — sauf en compact, où elle tient (voir `compactHeight`).
                Column(
                    Modifier
                        .fillMaxWidth()
                        .heightIn(min = screenHeight),
                    verticalArrangement = Arrangement.Bottom,
                ) {
                    Spacer(
                        Modifier
                            .height(screenHeight * revealRatio)
                            .clearAndSetSemantics {},
                    )
                    Card(
                        state = state,
                        isCompact = isCompact,
                        showsApple = apple != null,
                        showsGoogle = googleWebClientId != null,
                        showsTestingMode = showsTestingMode,
                        onApple = ::signInWithApple,
                        onGoogle = ::signInWithGoogle,
                        onEmail = onEmail,
                        onTermsOfUse = onTermsOfUse,
                        onTestingMode = ::signInAsTestAccount,
                    )
                }
            }
        }
    }
}

/**
 * Ce que l'entrée par Apple sur le web demande — voir `AppleSignInService`.
 *
 * @param redirectUri l'adresse du serveur qui reçoit le `form_post` d'Apple (lot B2).
 */
data class AppleEntry(val servicesId: String, val redirectUri: URI)

/** Les mesures de la mise en page, celles de la maquette. */
private object WelcomeLayout {
    /**
     * Largeur du cadre de la maquette : au-delà, la colonne se centre au lieu
     * de s'étirer — même règle que partout ailleurs dans l'app.
     */
    val contentWidth: Dp = 390.dp

    /**
     * La part de l'écran que la photo garde pour elle au-dessus de la carte.
     * La maquette en laisse voir 201 sur 844 : la proportion suit l'écran pour
     * qu'un modèle plus court ne réduise pas la photo à un bandeau.
     *
     * La photo elle-même, en revanche, ne fait plus 380 de haut : elle
     * **couvre la dalle entière**, sous la carte comprise (Hugo, 15/09/2026).
     * Sur un petit écran la carte défile, et tirer dessus la fait glisser vers
     * le bas — ce qui apparaît alors est la photo, jamais le crème du fond.
     */
    const val heroRevealRatio: Float = 201f / 844f

    /**
     * En deçà de cette hauteur de dalle — l'iPhone SE et ses 667 pt, un
     * téléphone de 640 dp —, la carte se resserre pour **tenir entière sans
     * défiler** (Hugo, 29/09/2026, T146) : moins de photo au-dessus, des écarts
     * de section plus courts. Au format de référence et au-delà, rien ne change.
     */
    val compactHeight: Dp = 700.dp
    const val compactHeroRevealRatio: Float = 0.11f
}

// MARK: - La photo

/**
 * Elle couvre la dalle entière — sous la barre d'état, sous la carte, jusqu'à
 * la barre de navigation : c'est un fond d'écran, pas une illustration posée
 * dans une page. La carte crème ne recouvre que ce qu'elle a besoin de
 * recouvrir.
 */
@Composable
private fun Hero(modifier: Modifier = Modifier) {
    Box(modifier.semantics { contentDescription = WelcomeCopy.Voice.hero }) {
        Image(
            painter = painterResource(R.drawable.photo_welcome_hero),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        // Le dégradé qui protège l'heure et la batterie, sans poser un bandeau
        // opaque sur l'image. Le voile d'encre à 40 % de l'ancienne photo est
        // parti avec elle : il servait un texte blanc que la nouvelle image ne
        // porte plus, et l'assombrissait pour rien.
        Box(
            Modifier
                .fillMaxWidth()
                .height(MemoBookSpacing.l + MemoBookSpacing.m)
                .background(Brush.verticalGradient(listOf(MemoBookColor.ink.copy(alpha = 0.25f), MemoBookColor.ink.copy(alpha = 0f)))),
        )
    }
}

// MARK: - La carte

@Composable
private fun Card(
    state: AuthModel.State,
    isCompact: Boolean,
    showsApple: Boolean,
    showsGoogle: Boolean,
    showsTestingMode: Boolean,
    onApple: () -> Unit,
    onGoogle: () -> Unit,
    onEmail: () -> Unit,
    onTermsOfUse: () -> Unit,
    onTestingMode: () -> Unit,
) {
    val shape = RoundedCornerShape(
        topStart = MemoBookSpacing.largeCornerRadius + MemoBookSpacing.s,
        topEnd = MemoBookSpacing.largeCornerRadius + MemoBookSpacing.s,
    )
    Box(
        Modifier
            .fillMaxWidth()
            // L'ombre de la maquette monte : c'est la carte qui est posée sur
            // la photo, pas l'inverse.
            .dropShadow(shape, Shadow(radius = 2.dp, color = Color.Black.copy(alpha = 0.25f), offset = DpOffset(0.dp, (-4).dp)))
            // Le crème descend jusqu'au bas de l'écran, **sous** la barre de
            // navigation : la bande du bas reste crème, pas la photo. Sans
            // élastique, il n'y a rien à découvrir plus bas (voir
            // `BrandScrollWithoutBounce`) : la réserve de crème sous la dalle
            // qu'iOS pose pour son rebond n'a pas lieu d'être ici.
            .background(MemoBookColor.background, shape)
            .windowInsetsPadding(WindowInsets.navigationBars),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier
                .widthIn(max = WelcomeLayout.contentWidth)
                .fillMaxWidth()
                .padding(horizontal = MemoBookSpacing.screenMargin)
                .padding(
                    top = if (isCompact) MemoBookSpacing.s else MemoBookSpacing.m,
                    bottom = if (isCompact) MemoBookSpacing.s else MemoBookSpacing.l,
                ),
            verticalArrangement = Arrangement.spacedBy(if (isCompact) MemoBookSpacing.s else MemoBookSpacing.l),
        ) {
            TitleBlock()
            FeaturesBlock()
            AuthBlock(state, showsApple, showsGoogle, showsTestingMode, onApple, onGoogle, onEmail, onTermsOfUse, onTestingMode)
        }
    }
}

@Composable
private fun TitleBlock() {
    val title = remember {
        buildAnnotatedString {
            withStyle(MemoBookFont.h1Light.toSpanStyle()) { append(WelcomeCopy.titleLead) }
            withStyle(MemoBookFont.h1.toSpanStyle().copy(color = MemoBookColor.action)) { append(WelcomeCopy.titleStrong) }
        }
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BasicText(
            title,
            Modifier.semantics { heading() },
            style = MemoBookFont.h1Light.copy(color = MemoBookColor.ink, letterSpacing = (-0.41).sp),
        )
        BrandText(WelcomeCopy.subtitle, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted)
    }
}

// MARK: Les trois temps, et la note

@Composable
private fun FeaturesBlock() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        Features()
        SocialProof()
    }
}

/**
 * En taille accessible les trois colonnes deviennent trois lignes : à 118 de
 * large, « 1. Raconte » se coupe au milieu.
 */
@Composable
private fun Features() {
    val iconSide = scaled(MemoBookSpacing.xl)
    if (isAccessibilityTextSize()) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            WelcomeCopy.features.forEach { feature ->
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug), verticalAlignment = Alignment.CenterVertically) {
                    FeatureIcon(feature, iconSide)
                    BrandText(feature.label, MemoBookFont.overline)
                }
            }
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalAlignment = Alignment.Top) {
            WelcomeCopy.features.forEach { feature ->
                Column(
                    Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                ) {
                    FeatureIcon(feature, iconSide)
                    BrandText(feature.label, MemoBookFont.overline, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

/**
 * ⚠️ **Sans teinte**, contrairement aux icônes de barre : ces trois-là sont
 * bichromes, et une teinte les aplatirait en une seule couleur — c'est-à-dire
 * qu'elle effacerait exactement le bleu pour lequel on les a choisies.
 */
@Composable
private fun FeatureIcon(feature: WelcomeCopy.Feature, side: Dp) {
    Image(
        painter = painterResource(feature.icon),
        contentDescription = null,
        modifier = Modifier.size(side),
    )
}

@Composable
private fun SocialProof() {
    val shape = RoundedCornerShape(MemoBookSpacing.snug)
    Row(
        Modifier
            .fillMaxWidth()
            .border(1.dp, MemoBookColor.hairline, shape)
            .padding(MemoBookSpacing.xs + 2.dp)
            .clearAndSetSemantics { contentDescription = WelcomeCopy.Voice.rating },
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandText(WelcomeCopy.rating, MemoBookFont.tagline, color = MemoBookColor.action, textAlign = TextAlign.Center)
        Box(
            Modifier
                .size(MemoBookSpacing.xs / 2)
                .background(MemoBookColor.inkMuted, CircleShape),
        )
        BrandText(WelcomeCopy.community, MemoBookFont.caption, Modifier.weight(1f, fill = false), textAlign = TextAlign.Center)
    }
}

// MARK: Entrer

@Composable
private fun AuthBlock(
    state: AuthModel.State,
    showsApple: Boolean,
    showsGoogle: Boolean,
    showsTestingMode: Boolean,
    onApple: () -> Unit,
    onGoogle: () -> Unit,
    onEmail: () -> Unit,
    onTermsOfUse: () -> Unit,
    onTestingMode: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2)) {
            BrandText(WelcomeCopy.hello, MemoBookFont.calloutTitle)
            BrandText(WelcomeCopy.helloDetail, MemoBookFont.taglineRegular, color = MemoBookColor.inkMuted)
        }

        WelcomeSocialButtons(
            showsApple = showsApple,
            showsGoogle = showsGoogle,
            enabled = !state.isWorking,
            onApple = onApple,
            onGoogle = onGoogle,
        )

        val message = rememberLast(state.errorMessage)
        AnimatedVisibility(
            visible = state.errorMessage != null,
            enter = fadeIn(SwiftMotion.snappy(0.2f)),
            exit = fadeOut(SwiftMotion.snappy(0.2f)),
        ) {
            BrandText(message.orEmpty(), MemoBookFont.notification, Modifier.fillMaxWidth(), color = MemoBookColor.error)
        }

        Footer(isWorking = state.isWorking, showsTestingMode, onEmail, onTermsOfUse, onTestingMode)
    }
}

@Composable
private fun Footer(
    isWorking: Boolean,
    showsTestingMode: Boolean,
    onEmail: () -> Unit,
    onTermsOfUse: () -> Unit,
    onTestingMode: () -> Unit,
) {
    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(interactionSource = null, indication = PlainButtonIndication, enabled = !isWorking, role = Role.Button, onClick = onEmail),
            contentAlignment = Alignment.Center,
        ) {
            BrandText(
                WelcomeCopy.email,
                MemoBookFont.tagline.copy(textDecoration = TextDecoration.Underline),
                color = MemoBookColor.action,
                textAlign = TextAlign.Center,
            )
        }

        LegalMention(onTermsOfUse)

        // ⚠️ PROVISOIRE — l'entrée de chantier, par le compte que le seed
        // pose. Absente de la version livrée : seul un build débogable la montre.
        if (showsTestingMode) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = MemoBookSpacing.minimumTapTarget)
                    .clickable(interactionSource = null, indication = PlainButtonIndication, role = Role.Button, onClick = onTestingMode),
                contentAlignment = Alignment.Center,
            ) {
                BrandText("Testing mode →", MemoBookFont.caption, color = MemoBookColor.inkMuted)
            }
        }
    }
}

/**
 * La mention légale, son lien souligné au milieu. « Conditions d'utilisation »
 * est un lien (T151) : on doit pouvoir lire ce qu'on accepte avant d'avoir un
 * compte. Un lien **dans** la phrase et non un bouton sous elle — c'est la
 * phrase qu'on lit.
 */
@Composable
private fun LegalMention(onTermsOfUse: () -> Unit) {
    val open by rememberUpdatedState(onTermsOfUse)
    val mention = remember {
        buildAnnotatedString {
            append(WelcomeCopy.legalLead)
            withLink(
                LinkAnnotation.Clickable(
                    tag = "conditions-d-utilisation",
                    styles = TextLinkStyles(SpanStyle(textDecoration = TextDecoration.Underline, color = MemoBookColor.inkMuted)),
                ) { open() },
            ) { append(WelcomeCopy.legalLink) }
            append(WelcomeCopy.legalTail)
        }
    }
    BasicText(
        mention,
        Modifier.fillMaxWidth(),
        style = MemoBookFont.mention.copy(color = MemoBookColor.inkMuted, textAlign = TextAlign.Center),
    )
}

@Preview(locale = "fr-rFR", name = "Accueil — 1ère connexion", widthDp = 390, heightDp = 844)
@Composable
private fun WelcomeViewPreview() {
    val model = remember { AuthModel(previewApi(), InMemoryAppSettings()) }
    WelcomeView(
        model,
        onAuthenticated = {},
        onEmail = {},
        googleWebClientId = "aperçu",
        apple = AppleEntry("aperçu", URI("https://exemple.com")),
        showsTestingMode = true,
    )
}

@Preview(locale = "fr-rFR", name = "Accueil — petit téléphone", widthDp = 360, heightDp = 640)
@Composable
private fun WelcomeViewSmallPreview() {
    val model = remember { AuthModel(previewApi(), InMemoryAppSettings()) }
    WelcomeView(model, onAuthenticated = {}, onEmail = {}, googleWebClientId = "aperçu", apple = AppleEntry("aperçu", URI("https://exemple.com")))
}

@Preview(locale = "fr-rFR", name = "Accueil — AX3", widthDp = 390, heightDp = 844, fontScale = 2f)
@Composable
private fun WelcomeViewAccessibilityPreview() {
    val model = remember { AuthModel(previewApi(), InMemoryAppSettings()) }
    WelcomeView(model, onAuthenticated = {}, onEmail = {}, googleWebClientId = "aperçu", apple = AppleEntry("aperçu", URI("https://exemple.com")))
}
