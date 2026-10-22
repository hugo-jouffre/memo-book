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
import androidx.lifecycle.ViewModel
import com.memobook.core.BookCopy
import com.memobook.core.Gender
import com.memobook.core.InviteLink
import com.memobook.core.PageTargetReach
import com.memobook.core.PageTargetTripStage
import com.memobook.core.TripSettings
import com.memobook.core.TripTheme
import com.memobook.design.BrandButton
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R
import com.memobook.feature.home.TripDates
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.URI
import java.util.Locale
import java.util.UUID
import java.time.ZoneId

// Les pièces d'autres lots que les réglages du voyage emploient, sous leur nom
// Swift et leur signature probable. Rien ici n'est un portage : de quoi
// compiler et voir l'écran, au plus simple. **L'intégrateur supprime ce
// fichier à la fusion**, ajoute les imports des vraies pièces, et recale les
// appels sur leurs vraies signatures.

// MARK: - À brancher : TripSettings/BookCustomisationModel.swift (lot des personnalisations)

/**
 * Le modèle des personnalisations du carnet, réduit à ce que
 * [PageTargetChangeSheet] et [PageTargetReachSheet] en lisent et en appellent.
 * Le lot des personnalisations le porte en entier.
 */
class BookCustomisationModel(val tripId: String) : ViewModel() {
    /**
     * @property pageTargetChange le changement de cible en cours, que la feuille
     *   déroule.
     * @property pageTargetReach la cible personnalisée hors d'atteinte, que la
     *   feuille propose de corriger.
     */
    data class State(
        val settings: TripSettings? = null,
        val pageTargetChange: PageTargetChange? = null,
        val pageTargetReach: PageTargetReach? = null,
    ) {
        val customisation get() = settings?.customisation
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    fun confirmPageTargetChange() = Unit
    fun choosePageTargetStage(@Suppress("UNUSED_PARAMETER") stage: PageTargetTripStage) = Unit
    fun dismissPageTargetChange() = Unit
    suspend fun rewriteWrittenSteps() = Unit
    fun chooseReachableTarget() = Unit
    fun raiseRatioForTarget() = Unit
    fun keepUnreachableTarget() = Unit
}

/**
 * Un changement du nombre de pages cible, d'une étape à l'autre de sa feuille —
 * `PageTargetChange` de `BookCustomisationModel.swift`.
 */
data class PageTargetChange(
    val from: Int,
    val to: Int,
    val tripDays: Int?,
    val step: Step,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
    val id: String = UUID.randomUUID().toString(),
) {
    sealed interface Step {
        data class Confirm(val changesLeft: Int) : Step
        data object Stage : Step
        data object LimitReached : Step
        data class Done(val stage: PageTargetTripStage) : Step
    }

    /** La cible monte : le récit s'étoffe. Sinon il se condense. */
    val isLonger: Boolean get() = to > from
}

// MARK: - À brancher : TripSettings/BookFormatting.swift (lot des personnalisations)

/** La ligne de dates du voyage — « 26 août – 15 sept. 2026 », `null` sans aucune date. */
internal val TripSettings.dateRangeLabel: String?
    get() {
        val locale = Locale.getDefault()
        val zone = ZoneId.systemDefault()
        val start = startDate
        val end = endDate
        return when {
            start != null && end != null && start < end -> TripDates.interval(start, end, locale, zone)
            start != null -> TripDates.day(start, locale, zone)
            end != null -> TripDates.day(end, locale, zone)
            else -> null
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
