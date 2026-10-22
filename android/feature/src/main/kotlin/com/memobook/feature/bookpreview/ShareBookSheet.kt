package com.memobook.feature.bookpreview

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.service.chooser.ChooserAction
import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil3.compose.AsyncImage
import com.memobook.core.BookCopy
import com.memobook.core.BookPreview
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookShadow
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.design.brandShadow
import com.memobook.feature.PhotoFlow
import com.memobook.feature.tripsettings.fixture
import java.io.File
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

/**
 * « Partager ton MemoBook » : le choix entre un fichier et un lien. Jumeau de
 * `BookPreview/ShareBookSheet.swift`.
 *
 * Deux façons de partager, et elles ne disent pas la même chose :
 *
 * - **Le PDF** est le carnet tel qu'il est aujourd'hui. Il s'ouvre hors
 *   connexion, il s'imprime, il ne bougera plus.
 * - **Le lien** est le carnet tel qu'il sera. Il suit la conversation : ceux
 *   qui l'ouvrent voient les étapes s'ajouter.
 *
 * La carte du haut n'est pas décorative : c'est **l'aperçu de ce que le
 * destinataire verra**. Le lien de prévisualisation porte des métadonnées Open
 * Graph, et c'est cette vignette-là qui apparaîtra dans WhatsApp. La montrer
 * avant d'envoyer évite la surprise.
 */
@Composable
internal fun ShareBookSheet(
    preview: BookPreview?,
    isPreparingLink: Boolean,
    onSharePdf: () -> Unit,
    onShareLink: () -> Unit,
) {
    BrandSheet(BookCopy.Share.title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            SharePreviewCard(preview)

            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                BrandText(BookCopy.Share.message, MemoBookFont.caption, color = MemoBookColor.ink)

                // Deux gestes, deux icônes (Hugo, 17/09/2026, T68) : le fichier
                // porte le PDF, le lien porte l'œil de la prévisualisation. Le
                // cube Relume de la maquette était un reste de composant.
                BrandButton(
                    BookCopy.Share.sharePdf,
                    icon = painterResource(R.drawable.icon_pdf),
                    style = BrandButton.Style.Secondary,
                    fillsWidth = true,
                    action = onSharePdf,
                )

                BrandButton(
                    BookCopy.Share.shareLink,
                    icon = painterResource(R.drawable.icon_view),
                    style = BrandButton.Style.Primary,
                    isLoading = isPreparingLink,
                    fillsWidth = true,
                    action = onShareLink,
                )
            }
        }
    }
}

/** La carte que le destinataire verra : la couverture, le voyage, sa date, et deux lignes du récit. */
@Composable
private fun SharePreviewCard(preview: BookPreview?) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val description = listOfNotNull(preview?.title, preview?.excerpt?.quote, preview?.excerpt?.detail).joinToString(". ")

    Column(
        Modifier
            .fillMaxWidth()
            .brandShadow(MemoBookShadow.Soft, shape)
            .background(MemoBookColor.background, shape)
            .clip(shape)
            .border(1.dp, MemoBookColor.hairline, shape)
            .clearAndSetSemantics { contentDescription = description },
    ) {
        ShareCover(preview)
        ShareExcerpt(preview)
    }
}

/**
 * La couverture, sous un dégradé qui part du milieu : le titre posé dessus doit
 * rester lisible quelle que soit la photo, et une photo claire en bas est le
 * cas courant — c'est là que tombe la plage ou le ciel.
 */
@Composable
private fun ShareCover(preview: BookPreview?) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(150.dp)
            // Pas de couverture : le bleu de la marque plutôt qu'un gris. La
            // carte reste une carte de voyage.
            .background(MemoBookColor.outline),
    ) {
        preview?.coverPhotoUrl?.let { url ->
            AsyncImage(
                model = url,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        }
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0.5f to Color.Transparent,
                        1f to Color(red = 0.102f, green = 0.184f, blue = 0.145f).copy(alpha = 0.63f),
                    ),
                ),
        )

        ShareTripInfo(preview, Modifier.align(Alignment.BottomStart))
        ShareMark(Modifier.align(Alignment.TopEnd))
    }
}

@Composable
private fun ShareTripInfo(preview: BookPreview?, modifier: Modifier = Modifier) {
    Column(modifier.padding(MemoBookSpacing.s), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        BrandText(preview?.title ?: "", MemoBookFont.heading, color = MemoBookColor.onAction, maxLines = 2)

        preview?.tripDate?.let { tripDate ->
            // « 12 oct. 2026 » — le `.dateTime.day().month(.abbreviated).year()` d'iOS.
            val date = DateTimeFormatter.ofPattern("d MMM yyyy", Locale.FRENCH).format(tripDate.atZone(ZoneId.systemDefault()))
            Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2), verticalAlignment = Alignment.CenterVertically) {
                Image(
                    painter = painterResource(R.drawable.icon_lucide_calendar),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(MemoBookColor.onAction.copy(alpha = 0.8f)),
                    modifier = Modifier.size(10.dp),
                )
                BrandText(date, MemoBookFont.caption, color = MemoBookColor.onAction.copy(alpha = 0.8f))
            }
        }
    }
}

/**
 * Le signe de la marque, dans une pastille. C'est la seule marque que porte la
 * carte partagée : elle voyage hors de l'app, elle doit dire d'où elle vient.
 * Android n'a pas le verre dépoli d'iOS (`.ultraThinMaterial`) derrière une
 * vue : un voile clair en tient lieu.
 */
@Composable
private fun ShareMark(modifier: Modifier = Modifier) {
    Image(
        painter = painterResource(R.drawable.logo_memobook_creme),
        contentDescription = null,
        modifier = modifier
            .padding(MemoBookSpacing.s)
            .background(Color.White.copy(alpha = 0.25f), RoundedCornerShape(MemoBookSpacing.xs))
            .padding(horizontal = MemoBookSpacing.xs, vertical = MemoBookSpacing.xs / 2)
            .size(width = 38.dp, height = 26.dp),
    )
}

@Composable
private fun ShareExcerpt(preview: BookPreview?) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs / 2),
    ) {
        // Les guillemets font partie de la citation et non du récit : c'est la
        // carte qui cite, le carnet écrit au fil de l'eau.
        BrandText("« ${preview?.excerpt?.quote ?: ""} »", MemoBookFont.bodySemibold, color = MemoBookColor.ink, maxLines = 1)

        preview?.excerpt?.detail?.let { detail ->
            BrandText(detail, MemoBookFont.body, color = MemoBookColor.inkMuted, maxLines = 1)
        }
    }
}

// MARK: - La feuille de partage du système

/**
 * Ce qui part dans la feuille de partage : un message, et au plus un fichier.
 *
 * L'identité change à chaque partage ([id]), ce qui garantit que la feuille se
 * rouvre même si on repartage la même chose.
 *
 * @property pages les pages déjà composées, que le message annonce.
 * @property file le PDF écrit sur le disque, quand c'est lui qu'on partage.
 * @property link le lien de prévisualisation. Il accompagne **les deux** modes
 *   de partage : c'est le message qui dit où suivre le carnet, pas la pièce
 *   jointe.
 * @property coverPhotoUrl la photo du voyage, en tête de la feuille — la
 *   vignette de la maquette (`3551:26331`). ⚠️ Pas encore montrée sur Android :
 *   la feuille du système n'y lit qu'une image **déjà sur le téléphone**,
 *   prêtée par un `FileProvider`, là où iOS la télécharge quand la feuille la
 *   demande. La feuille s'ouvrirait donc après la photo ; elle s'ouvre sans.
 * @property actions les gestes que la feuille ajoute aux apps du système :
 *   « Commander », « Partager sur Whatsapp ».
 */
internal data class BookSharePayload(
    val title: String,
    val pages: Int,
    val file: File?,
    val link: String?,
    val coverPhotoUrl: String? = null,
    val actions: List<ShareAction> = emptyList(),
    val id: String = UUID.randomUUID().toString(),
) {
    /**
     * Le message pré-rempli. C'est lui qui apparaît dans WhatsApp, Messages ou
     * Snapchat dès que l'app de destination est choisie.
     */
    val message: String?
        get() = link?.let { BookCopy.Share.invitation(title = title, pages = pages, link = it) }
}

/**
 * Un geste de plus dans la feuille du système — une ligne sous les apps.
 *
 * @property icon une image du catalogue de la marque.
 * @property perform appelé par l'app quand la feuille du système le demande.
 * @property opens ce que la feuille du système ouvre **elle-même**, sans
 *   repasser par l'app — WhatsApp. `null` : elle prévient l'app, qui appelle
 *   [perform].
 */
internal class ShareAction(
    val title: String,
    @param:DrawableRes val icon: Int,
    val perform: () -> Unit,
    val opens: Intent? = null,
) {
    val id: String = UUID.randomUUID().toString()

    companion object {
        /**
         * « Partager sur Whatsapp » : WhatsApp ouvert sur le message, sans
         * passer par son entrée de partage. `null` quand WhatsApp n'est pas
         * installé — la question se pose par le `<queries>` du manifeste de
         * l'app, le `LSApplicationQueriesSchemes` d'iOS.
         */
        fun whatsApp(context: Context, message: String): ShareAction? {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("whatsapp://send?text=${Uri.encode(message)}"))
                // Ouvert par la feuille du système, hors de l'activité de l'app.
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(context.packageManager) == null) return null
            return ShareAction(
                title = BookCopy.Share.whatsAppAction,
                icon = R.drawable.logo_whats_app,
                perform = { context.startActivity(intent) },
                opens = intent,
            )
        }
    }
}

/**
 * La feuille de partage d'Android, avec le message et le fichier dedans.
 *
 * **Celle du système et pas la nôtre.** Elle seule connaît les apps installées,
 * le partage à proximité, les contacts récents et l'ordre dans lequel on
 * partage d'habitude. En redessiner une ne donnerait qu'une liste plus courte
 * et périmée — c'est pour ça que les deux maquettes « Modale - Partager son
 * MB - 2 » et « - 5 » ne sont pas implémentées : elles dessinent la feuille du
 * système, elles ne la remplacent pas.
 *
 * Ce qu'on y met, en revanche, suit la maquette `3551:26331` : le titre du
 * voyage en tête, et deux gestes sous les apps — « Commander », « Partager sur
 * Whatsapp ». **Depuis Android 14 seulement** (`EXTRA_CHOOSER_CUSTOM_ACTIONS`) :
 * avant, la feuille n'accepte pas de gestes à elle ; « Commander » reste sous la
 * page de l'aperçu, et WhatsApp est dans la liste des apps.
 */
internal object BookShareSheet {
    private const val ACTION = "com.memobook.share.ACTION"
    private const val EXTRA_ID = "com.memobook.share.id"

    /** L'intention à lancer : le choix d'une app, sur un `ACTION_SEND` préparé. */
    fun chooser(context: Context, payload: BookSharePayload): Intent {
        val send = Intent(Intent.ACTION_SEND)
        val file = payload.file
        if (file != null) {
            // Prêté par le `FileProvider` de l'app (`res/xml/photo_paths.xml`,
            // dossier `books/`), le temps du partage.
            val uri = FileProvider.getUriForFile(context, PhotoFlow.authority(context), file)
            send.type = "application/pdf"
            send.putExtra(Intent.EXTRA_STREAM, uri)
            send.clipData = ClipData.newRawUri(file.name, uri)
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else {
            send.type = "text/plain"
        }
        // Le message d'abord, le fichier ensuite : c'est le corps du message
        // dans une app de messagerie, la pièce jointe à côté. Ni message ni
        // fichier ne devrait pas arriver — la vue ne présente la feuille
        // qu'avec l'un des deux — mais un partage vide vaut mieux qu'un plantage.
        val text = payload.message ?: payload.title.takeIf { file == null }
        if (text != null) send.putExtra(Intent.EXTRA_TEXT, text)
        send.putExtra(Intent.EXTRA_SUBJECT, BookCopy.Share.subject(payload.title))
        // L'en-tête de la feuille : le titre du voyage plutôt que le début du
        // message tronqué.
        send.putExtra(Intent.EXTRA_TITLE, payload.title.ifEmpty { BookCopy.Share.title })

        val chooser = Intent.createChooser(send, null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && payload.actions.isNotEmpty()) {
            val actions = payload.actions.mapIndexed { index, action ->
                ChooserAction.Builder(Icon.createWithResource(context, action.icon), action.title, pendingIntent(context, action, index)).build()
            }
            chooser.putExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS, actions.toTypedArray())
        }
        return chooser
    }

    private fun pendingIntent(context: Context, action: ShareAction, index: Int): PendingIntent {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        action.opens?.let { return PendingIntent.getActivity(context, index, it, flags) }
        val notice = Intent(ACTION).setPackage(context.packageName).putExtra(EXTRA_ID, action.id)
        return PendingIntent.getBroadcast(context, index, notice, flags)
    }

    /**
     * Écoute les gestes que la feuille du système renvoie à l'app — le
     * `UIActivity.perform()` d'iOS. Posé pour toute la vie de l'écran, et non
     * celle de la feuille : le geste et la fermeture de la feuille arrivent
     * dans un ordre que l'app ne choisit pas.
     */
    @Composable
    fun ActionsReceiver(actions: () -> List<ShareAction>) {
        val context = LocalContext.current
        val latest by rememberUpdatedState(actions)
        DisposableEffect(context) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val id = intent.getStringExtra(EXTRA_ID) ?: return
                    latest().firstOrNull { it.id == id }?.perform?.invoke()
                }
            }
            ContextCompat.registerReceiver(context, receiver, IntentFilter(ACTION), ContextCompat.RECEIVER_NOT_EXPORTED)
            onDispose { context.unregisterReceiver(receiver) }
        }
    }
}

@Preview(locale = "fr-rFR", name = "Partager ton MemoBook", heightDp = 800)
@Composable
private fun ShareBookSheetPreview() {
    BrandSheetHost(isPresented = true, onDismissRequest = {}) {
        ShareBookSheet(preview = BookPreview.fixture, isPreparingLink = false, onSharePdf = {}, onShareLink = {})
    }
}
