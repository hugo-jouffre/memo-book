package com.memobook.feature.debug

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.memobook.core.ChatAuthor
import com.memobook.core.ShippingCountry
import com.memobook.design.BrandAvatar
import com.memobook.design.BrandCountryField
import com.memobook.design.BrandDateField
import com.memobook.design.BrandKeyboardDismissBar
import com.memobook.design.BrandRangeCalendar
import com.memobook.design.BrandSearchField
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandTextBox
import com.memobook.design.BrandTextField
import com.memobook.design.DateRangeSelection
import com.memobook.design.BrandChatBubble
import com.memobook.design.BrandComingSoon
import com.memobook.design.BrandDisclosureCard
import com.memobook.design.BrandFilterChip
import com.memobook.design.BrandGauge
import com.memobook.design.BrandHeaderAction
import com.memobook.design.BrandLimitBanner
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandRow
import com.memobook.design.BrandRowGroup
import com.memobook.design.BrandScreenHeader
import com.memobook.design.BrandSegmentedPicker
import com.memobook.design.BrandSlider
import com.memobook.design.BrandStepper
import com.memobook.design.BrandSwipeAction
import com.memobook.design.BrandSwipeDrawer
import com.memobook.design.BrandText
import com.memobook.design.BrandToggleCard
import com.memobook.design.BrandWaveform
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.RecordButton
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandButton
import com.memobook.design.BrandIconBadge
import com.memobook.design.BrandProgressBar
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandTagPill
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookSpacing
import com.memobook.design.R as DesignR

/** Les sections de composants de l'écran-catalogue, une par famille de `Brand…`. */
internal object DesignCatalogueSections {
    val all: List<Pair<String, @Composable () -> Unit>> = listOf(
        "Boutons" to { Buttons() },
        "Pastilles et jauges" to { Pills() },
        "Erreurs et attente" to { Feedback() },
        "Lignes et choix" to { Rows() },
        "Cartes et réglages" to { Cards() },
        "Avis et limites" to { Notices() },
        "Conversation et voix" to { Voice() },
        "En-têtes, filtres et tiroirs" to { Headers() },
        "Champs" to { Fields() },
        "Feuille" to { Sheet() },
        "Calendrier" to { Calendar() },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Buttons() {
    val arrow = painterResource(DesignR.drawable.icon_arrow_right)
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandButton("Découvre MemoBook", icon = arrow, fillsWidth = true) {}
        BrandButton(
            "Découvrir l’abonnement",
            icon = arrow,
            iconPlacement = BrandButton.IconPlacement.Trailing,
            style = BrandButton.Style.Accent,
            fillsWidth = true,
        ) {}
        BrandButton("Continuer", style = BrandButton.Style.Blue, fillsWidth = true) {}
        FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandButton("Secondary", style = BrandButton.Style.Secondary) {}
            BrandButton("Soft", style = BrandButton.Style.Soft) {}
            BrandButton("Raised", style = BrandButton.Style.Raised) {}
            BrandButton("Small", size = BrandButton.Size.Small) {}
            BrandButton("Medium", size = BrandButton.Size.Medium) {}
            BrandButton(icon = arrow, isRound = true, contentDescription = "Suivant") {}
            BrandButton("Link", style = BrandButton.Style.Link) {}
        }
        BrandButton("Résilier mon abonnement", style = BrandButton.Style.Destructive, fillsWidth = true) {}
        BrandButton("Chargement", isLoading = true, fillsWidth = true) {}
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Pills() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandTagPill("Illimité")
            BrandTagPill("En cours", tone = BrandTagPill.Tone.Outlined, isUppercased = true)
            BrandTagPill("×3", tone = BrandTagPill.Tone.Info)
            BrandTagPill("Abonnée", tone = BrandTagPill.Tone.AccentOutlined, isUppercased = true)
        }
        BrandProgressBar(0.4, label = "12 souvenirs et 32/80 pages")
        BrandIconBadge(DesignR.drawable.icon_locker)
    }
}

@Composable
private fun Feedback() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        ErrorBanner("Connexion impossible.", retry = {})
        ErrorBanner("Le serveur ne répond pas.", advice = "La panne est chez nous : réessaie dans quelques minutes.", retry = {}, help = {})
        BrandSkeleton(width = 180.dp)
    }
}

@Composable
private fun Rows() {
    var newsletter by remember { mutableStateOf(true) }
    var pace by remember { mutableStateOf("Soutenu") }
    var tab by remember { mutableStateOf("Inscription") }
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandSegmentedPicker(
            values = listOf("Inscription", "Connexion"),
            selection = tab,
            onSelectionChange = { tab = it },
            title = { it },
        )
        BrandRowGroup {
            +BrandRow("E-mail", value = "maylis.garde@icloud.com", valuePlacement = BrandRow.ValuePlacement.Below)
            +BrandRow("Adresse postale", value = "7 rue Simon Fryd, Lyon", action = {})
            +BrandRow("Newsletter mensuelle", isOn = newsletter, onIsOnChange = { newsletter = it })
        }
        BrandOptionGroup {
            listOf("Tranquille", "Régulier", "Soutenu").forEach { option ->
                BrandOptionRow(option, isSelected = pace == option) { pace = option }
            }
        }
    }
}

@Composable
private fun Cards() {
    var funFacts by remember { mutableStateOf(true) }
    var expanded by remember { mutableStateOf(false) }
    var copies by remember { mutableIntStateOf(2) }
    var ratio by remember { mutableIntStateOf(50) }
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandToggleCard("Insérer des fun facts", "Encarts de culture générale toutes les 3 pages", funFacts, { funFacts = it })
        BrandToggleCard("Pointillés", "Lignes en pointillé sous le texte", false, {}, isAvailable = false, onUnavailable = {})
        BrandDisclosureCard("1. Objet", expanded, { expanded = it }, lineFont = MemoBookFont.body) {
            BrandText(
                "Les présentes conditions encadrent l’usage de MemoBook, de l’enregistrement des souvenirs à " +
                    "l’impression du carnet. En créant un compte, tu les acceptes sans réserve.",
                MemoBookFont.body,
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandText("Exemplaires", MemoBookFont.bodySemibold, modifier = Modifier.weight(1f))
            BrandStepper(copies, canDecrement = copies > 1, onDecrement = { copies-- }, onIncrement = { copies++ })
        }
        BrandSlider(ratio, { ratio = it }, 0..100, 25, listOf("Texte", "", "Équilibré", "", "Photos"), voiceLabel = "Ratio texte et photos")
        BrandGauge(0.65, accessibilityLabel = "Crédit du jour")
        BrandGauge(1.0, accessibilityLabel = "Crédit du jour", isExhausted = true)
    }
}

@Composable
private fun Notices() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandNotice("Tu sembles hors ligne. **Tu peux consulter tes récits**, qui seront envoyés plus tard.")
        BrandNotice("Les pointillés arrivent avec la prochaine version.", tone = BrandNotice.Tone.Information)
        BrandNotice("**La cible de pages ne peut plus changer** pour ce voyage.", tone = BrandNotice.Tone.Warning)
        BrandLimitBanner("Plus que 30 secondes aujourd’hui", detail = "Passe en illimité pour continuer", isPulsing = true, action = {})
        BrandComingSoon {
            BrandRowGroup { +BrandRow("Importer depuis Polarsteps", action = {}) }
        }
    }
}

@Composable
private fun Voice() {
    var recording by remember { mutableStateOf(false) }
    val levels = remember { List(48) { i -> 0.2 + 0.8 * kotlin.math.abs(kotlin.math.sin(i / 3.0)) } }
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandChatBubble(ChatAuthor.Memo) { BrandText("Comment ça se passe à Trastevere ?", MemoBookFont.bubble) }
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
            BrandChatBubble(ChatAuthor.Traveller) { BrandText("On a pris un café debout au comptoir.", MemoBookFont.bubble) }
        }
        BrandWaveform(levels = levels, progress = 0.4)
        BrandWaveform(live = levels.take(24))
        Box(Modifier.fillMaxWidth().height(140.dp), contentAlignment = Alignment.Center) {
            RecordButton(isRecording = recording, level = if (recording) 0.6 else 0.0) { recording = !recording }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Headers() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandScreenHeader("Aperçu PDF", onBack = {}, subtitle = "Rome et la Dolce Vita – 10 pages") {
            BrandHeaderAction(DesignR.drawable.icon_share_system, label = "Partager") {}
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandFilterChip("Toutes les catégories")
            BrandFilterChip("Transports", icon = painterResource(DesignR.drawable.icon_lucide_train_front), kind = BrandFilterChip.Kind.Toggle, isActive = true)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
            BrandAvatar(photo = null, initials = "MG")
            BrandAvatar(photo = painterResource(DesignR.drawable.photo_founders), initials = "HJ")
        }
        BrandSwipeDrawer(
            actions = listOf(
                BrandSwipeAction(DesignR.drawable.icon_trash, MemoBookColor.error, "Supprimer") {},
                BrandSwipeAction(DesignR.drawable.icon_share_nodes, MemoBookColor.ink, "Partager") {},
            ),
        ) { accessibility ->
            BrandRowGroup(modifier = accessibility) { +BrandRow("Glisse-moi vers la gauche", action = {}) }
        }
    }
}

/** Les champs du formulaire d'entrée, dans l'ordre où le clavier les enchaîne. */
private enum class CatalogueField { Email, Password, Note }

@Composable
private fun Fields() {
    var focus by remember { mutableStateOf<CatalogueField?>(null) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("memobook2026") }
    var search by remember { mutableStateOf("") }
    var country by remember { mutableStateOf("FR") }
    var departure by remember { mutableStateOf<java.time.LocalDate?>(java.time.LocalDate.of(2026, 10, 21)) }
    var note by remember { mutableStateOf("") }
    val today = java.time.LocalDate.of(2026, 10, 21)
    BrandKeyboardDismissBar {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandTextField("E-mail", email, { email = it }, CatalogueField.Email, focus, { focus = it })
            BrandTextField(
                "Mot de passe", password, { password = it }, CatalogueField.Password, focus, { focus = it },
                isSecure = true, labelPlacement = BrandTextField.LabelPlacement.Above,
                hint = "8 caractères, une lettre et un chiffre",
            )
            BrandSearchField("Rechercher un pays", search, { search = it }, onClear = { search = "" })
            BrandCountryField(
                listOf(ShippingCountry("FR", "France"), ShippingCountry("BE", "Belgique"), ShippingCountry("CH", "Suisse")),
                country,
                { country = it },
            )
            BrandDateField("Départ", departure, { departure = it }, today.minusYears(1)..today.plusYears(2))
            BrandTextBox(
                "Raconte ce qui t’a marqué aujourd’hui",
                note,
                { note = it },
                isFocused = focus == CatalogueField.Note,
                onFocusChange = { focus = if (it) CatalogueField.Note else null },
            )
        }
    }
}

@Composable
private fun Sheet() {
    var isPresented by remember { mutableStateOf(false) }
    BrandButton("Ouvrir une feuille", style = BrandButton.Style.Secondary, fillsWidth = true) { isPresented = true }
    BrandSheetHost(isPresented, onDismissRequest = { isPresented = false }) {
        BrandSheet(
            "Mot de passe oublié",
            paragraphs = listOf(
                "Indique l’adresse de ton compte : on t’envoie un lien pour choisir un nouveau mot de passe.",
                "Le lien vaut trente minutes.",
            ),
            icon = DesignR.drawable.icon_locker,
            badge = "Compte",
        ) {
            BrandButton("Envoyer le lien", fillsWidth = true) { isPresented = false }
        }
    }
}

@Composable
private fun Calendar() {
    var selection by remember {
        mutableStateOf(DateRangeSelection(java.time.LocalDate.of(2026, 10, 21), java.time.LocalDate.of(2026, 10, 28)))
    }
    BrandRangeCalendar(selection, { selection = it })
}
