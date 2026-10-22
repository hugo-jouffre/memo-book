package com.memobook.feature.tripsettings

import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.memobook.core.BookCopy
import com.memobook.core.Gender
import com.memobook.core.InviteLink
import com.memobook.core.TripTheme
import com.memobook.design.BrandButton
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import java.net.URI

// Les pièces d'autres lots que les réglages du voyage emploient, sous leur nom
// Swift et leur signature probable. Rien ici n'est un portage : de quoi
// compiler et voir l'écran, au plus simple. **L'intégrateur supprime ce
// fichier à la fusion**, ajoute les imports des vraies pièces, et recale les
// appels sur leurs vraies signatures.

// MARK: - À brancher : TripCreation/TripCreationSteps.swift (lot du voyage)

/** La rangée des thèmes, celle de la création du voyage. Ici, de simples émojis à toucher. */
@Composable
internal fun TripThemePicker(
    themes: List<TripTheme>,
    selection: TripTheme?,
    onSelectionChange: (TripTheme?) -> Unit,
    onSelect: (TripTheme) -> Unit,
) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            themes.forEach { theme ->
                BrandText(
                    theme.emoji,
                    MemoBookFont.h2,
                    Modifier.clickable(role = Role.Button) {
                        onSelect(theme)
                        onSelectionChange(theme)
                    },
                    color = if (theme == selection) MemoBookColor.ink else MemoBookColor.ink.copy(alpha = 0.6f),
                )
            }
        }
        BrandText(selection?.label ?: " ", MemoBookFont.label, color = MemoBookColor.inkMuted, maxLines = 1)
    }
}

/** La rangée, le temps que les thèmes arrivent. */
@Composable
internal fun TripThemePickerPlaceholder() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.height(54.dp), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.l), verticalAlignment = Alignment.CenterVertically) {
            repeat(5) { Box(Modifier.size(25.dp).background(MemoBookColor.ink.copy(alpha = 0.07f), CircleShape)) }
        }
        BrandSkeleton(width = 120.dp)
    }
}

/**
 * « Code d’accès : JHKFDA », et « Partager » — la feuille de partage d'Android,
 * le lien d'invitation d'abord, le code ensuite.
 *
 * @param inviteBase l'adresse de **production** (`AppDependencies.productionApiBaseUrl`),
 *   dont `InviteLink.url` tire le lien : un lien vers l'émulateur ne mènerait
 *   nulle part sur le téléphone de l'invité. Le vrai `TripAccessCode` devra la
 *   recevoir aussi, sur iOS il la lit dans le bundle.
 */
@Composable
internal fun TripAccessCode(code: String?, tripTitle: String, inviteBase: URI?, waitingNote: String? = null) {
    val context = LocalContext.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.l), horizontalAlignment = Alignment.CenterHorizontally) {
        if (code != null) {
            BrandText(BookCopy.Invite.accessCode(code), MemoBookFont.body, color = MemoBookColor.inkMuted)
        } else {
            BrandSkeleton(width = 88.dp)
            waitingNote?.let { BrandText(it, MemoBookFont.caption, color = MemoBookColor.inkMuted, textAlign = TextAlign.Center) }
        }
        BrandButton(
            BookCopy.Invite.share,
            icon = painterResource(R.drawable.icon_share_system),
            fillsWidth = true,
            enabled = code != null,
        ) {
            code ?: return@BrandButton
            val text = BookCopy.Invite.invitation(tripTitle, code, InviteLink.url(code, inviteBase)?.toString())
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            context.startActivity(Intent.createChooser(send, null))
        }
    }
}

// MARK: - À brancher : BookPreview/BookCompositionPage.swift (lot de l'aperçu)

/** La page de la composition, figée à `progress`. Ici, une page de papier nue. */
@Composable
internal fun BookCompositionPage(@Suppress("UNUSED_PARAMETER") progress: Double, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(4.dp)
    Box(modifier.background(MemoBookColor.surface, shape).border(1.dp, MemoBookColor.hairline, shape).padding(4.dp))
}

// MARK: - À brancher : Profile/SubscriptionSheet.swift (lot du profil)

/** Les mots de l'abonnement — la pastille « Abonné(e) » seulement. */
internal object SubscriptionCopy {
    /** La maquette écrit « Abonnée » ; l'app accorde sur ce que le profil sait de la personne (T76). */
    fun currentBadge(gender: Gender): String = gender.agreed("Abonné")
}
