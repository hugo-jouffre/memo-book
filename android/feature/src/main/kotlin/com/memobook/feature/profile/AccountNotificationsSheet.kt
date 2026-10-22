package com.memobook.feature.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.memobook.core.AccountNotificationPreferences
import com.memobook.core.BookCopy
import com.memobook.design.BrandNotice
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.BrandToggleCard
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.feature.notifications.LocalPushNotifications
import com.memobook.feature.notifications.NotificationAuthorization
import com.memobook.feature.notifications.PushNotifications
import com.memobook.feature.notifications.rememberNotificationPermissionRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * « Notifications » du profil — celles **du compte**, qui ne parlent d'aucun
 * voyage : rappel de renouvellement, vacances scolaires, l'an dernier à la
 * même époque, anniversaire (D13, Hugo, 19/10/2026). Une carte chacune.
 * Jumeau de `Profile/AccountNotificationsSheet.swift`.
 *
 * Elles n'avaient aucun interrupteur : seul le réglage du téléphone les
 * coupait, et lui coupe tout. Celles d'un voyage restent dans ses réglages
 * (`TripNotificationsSheet`), et ne valent que pour soi.
 *
 * ⚠️ **Aucune maquette** : dessinée exactement sur la feuille
 * « Notifications » d'un voyage — même chapeau, mêmes cartes, même avis quand
 * le téléphone refuse tout —, et à dessiner dans Figma.
 */
@Composable
internal fun AccountNotificationsSheet(model: ProfileModel) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)
    val pushNotifications = LocalPushNotifications.current
    val askSystem = rememberNotificationPermissionRequest()
    val context = LocalContext.current
    val preferences = state.profile?.notifications

    // Tout est coupé dans les Paramètres du téléphone : les cartes enregistrent
    // toujours, mais rien n'arrivera tant qu'on n'y retourne pas.
    val isBlockedBySystem = pushNotifications?.authorization == NotificationAuthorization.Denied

    // On revient peut-être des Paramètres : ce que le téléphone autorise a pu
    // changer. À l'ouverture, comme sur iOS — et au retour dans l'app, parce
    // que la feuille reste ouverte pendant qu'on y va.
    LaunchedEffect(pushNotifications) { pushNotifications?.refreshAuthorization() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { pushNotifications?.refreshAuthorization() }

    // La bascule d'une carte : elle lit le modèle et lui repasse le bloc
    // entier, parce que c'est le bloc entier que la route accepte — comme
    // `TripNotificationsSheet`. Les bascules **agissent** : les toucher avant
    // que le profil soit là enverrait un état qu'on n'a pas lu, elles ne font
    // alors rien.
    fun toggle(isOn: Boolean, change: (AccountNotificationPreferences, Boolean) -> AccountNotificationPreferences) {
        val current = model.profile?.notifications ?: return
        model.setNotifications(change(current, isOn))
        // Allumer une notification sans avoir jamais répondu au téléphone :
        // c'est le moment de lui poser la question.
        val push = pushNotifications ?: return
        if (isOn && push.authorization == NotificationAuthorization.NotDetermined) {
            model.viewModelScope.launch { push.requestAuthorization(askSystem) }
        }
    }

    BrandSheet(AccountNotificationsCopy.title, subtitle = AccountNotificationsCopy.subtitle) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
            if (isBlockedBySystem) {
                BrandNotice(
                    AccountNotificationsCopy.systemDeniedNotice,
                    footer = { OpenSettingsButton { PushNotifications.openSystemSettings(context) } },
                )
            }

            BrandToggleCard(
                title = AccountNotificationsCopy.renewalReminder,
                detail = AccountNotificationsCopy.renewalReminderDetail,
                isOn = preferences?.renewalReminder ?: false,
                onIsOnChange = { toggle(it) { preferences, isOn -> preferences.copy(renewalReminder = isOn) } },
            )
            BrandToggleCard(
                title = AccountNotificationsCopy.schoolHolidays,
                detail = AccountNotificationsCopy.schoolHolidaysDetail,
                isOn = preferences?.schoolHolidays ?: false,
                onIsOnChange = { toggle(it) { preferences, isOn -> preferences.copy(schoolHolidays = isOn) } },
            )
            BrandToggleCard(
                title = AccountNotificationsCopy.learnedPeriod,
                detail = AccountNotificationsCopy.learnedPeriodDetail,
                isOn = preferences?.learnedPeriod ?: false,
                onIsOnChange = { toggle(it) { preferences, isOn -> preferences.copy(learnedPeriod = isOn) } },
            )
            BrandToggleCard(
                title = AccountNotificationsCopy.birthday,
                detail = AccountNotificationsCopy.birthdayDetail,
                isOn = preferences?.birthday ?: false,
                onIsOnChange = { toggle(it) { preferences, isOn -> preferences.copy(birthday = isOn) } },
            )
        }
    }
}

/** « Ouvrir les réglages », sous l'avis : le texte seul, au vert d'action, dans une cible entière. */
@Composable
private fun OpenSettingsButton(action: () -> Unit) {
    Box(
        Modifier
            .heightIn(min = MemoBookSpacing.minimumTapTarget)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = PlainButtonIndication,
                role = Role.Button,
                onClick = action,
            ),
        contentAlignment = Alignment.CenterStart,
    ) {
        BrandText(BookCopy.Notifications.openSettings, MemoBookFont.bodySemibold, color = MemoBookColor.action)
    }
}

/**
 * Les mots de la feuille. ⚠️ **Aucun ne vient d'une maquette** — textes à
 * relire par Clara, sur le ton de la feuille d'un voyage.
 */
internal object AccountNotificationsCopy {
    const val rowTitle = "Notifications"

    const val title = "Notifications"
    const val subtitle =
        "Choisis ce que MemoBook peut te rappeler en dehors de tes voyages. Les alertes d’un voyage se règlent dans ses réglages."

    const val renewalReminder = "Rappel de renouvellement"
    const val renewalReminderDetail = "Trois jours avant que ton abonnement reparte"
    const val schoolHolidays = "Vacances scolaires"
    const val schoolHolidaysDetail = "Une semaine avant, puis le jour même"
    const val learnedPeriod = "L’an dernier à la même époque"
    const val learnedPeriodDetail = "Quand revient la période d’un voyage passé"
    const val birthday = "Anniversaire"
    const val birthdayDetail = "Une semaine avant le tien"

    /**
     * L'avis de `BookCopy.Notifications.systemDeniedNotice`, qui dit « les
     * réglages de ton iPhone » : la copie partagée parle d'iOS. Ici, le
     * téléphone et ses Paramètres — la seule adaptation de la phrase.
     */
    const val systemDeniedNotice =
        "Les notifications de MemoBook sont coupées dans les paramètres de ton téléphone : aucune de ces alertes ne t’arrivera."

    /**
     * Ce que la ligne du profil résume : « Toutes actives », « 3 sur 4 »,
     * « Aucune ».
     */
    fun summary(preferences: AccountNotificationPreferences): String {
        val flags = listOf(
            preferences.renewalReminder,
            preferences.schoolHolidays,
            preferences.learnedPeriod,
            preferences.birthday,
        )
        val on = flags.count { it }
        return when (on) {
            flags.size -> "Toutes actives"
            0 -> "Aucune"
            else -> "$on sur ${flags.size}"
        }
    }
}

@Preview(locale = "fr-rFR", name = "Notifications du compte", heightDp = 800)
@Composable
private fun AccountNotificationsSheetPreview() {
    // Le jeu d'essai, chargé : l'anniversaire coupé, le reste allumé.
    val model = remember { ProfileModel() }
    LaunchedEffect(model) { model.load() }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { AccountNotificationsSheet(model) }
}
