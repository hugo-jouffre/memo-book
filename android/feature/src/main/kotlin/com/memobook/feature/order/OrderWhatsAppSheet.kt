package com.memobook.feature.order

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import com.memobook.core.OrderCopy
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.BrandTextField
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookSpacing
import kotlinx.coroutines.delay

/**
 * Le numéro à prévenir, demandé depuis l'écran de confirmation. Jumeau de
 * `Order/OrderWhatsAppSheet.swift`.
 *
 * Elle n'existe que pour les comptes qui n'ont pas encore de numéro : les
 * autres acceptent le suivi d'un seul geste. Le numéro saisi ici **remonte sur
 * le compte** — c'est aujourd'hui le seul endroit qui le demande, et le
 * redemander à la commande suivante serait une question déjà posée.
 */
@Composable
internal fun OrderWhatsAppSheet(suggested: String?, onConfirm: (String) -> Unit) {
    var phone by rememberSaveable { mutableStateOf(suggested.orEmpty()) }

    /**
     * Une énumération à un seul cas plutôt qu'un booléen : `BrandTextField`
     * attend un focus **optionnel**, parce que « aucun champ » est un état.
     */
    var focus by remember { mutableStateOf<WhatsAppField?>(null) }

    // Volontairement permissif : les formats internationaux sont nombreux, et
    // c'est l'envoi qui validera vraiment. Assez pour écarter un champ à moitié
    // rempli, pas assez pour refuser un numéro valide qu'on n'a pas su lire.
    val canConfirm = phone.count { it.isDigit() } >= 6

    BrandSheet(
        OrderCopy.Confirmation.whatsappSheetTitle,
        subtitle = OrderCopy.Confirmation.whatsappSheetSubtitle,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m)) {
            BrandTextField(
                OrderCopy.Confirmation.whatsappField,
                phone,
                { phone = it },
                field = WhatsAppField.Phone,
                focus = focus,
                onFocusChange = { focus = it },
                labelPlacement = BrandTextField.LabelPlacement.Above,
                placeholder = OrderCopy.Confirmation.whatsappPlaceholder,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focus = null }),
                contentType = ContentType.PhoneNumber,
            )

            BrandButton(
                OrderCopy.Confirmation.whatsappConfirm,
                fillsWidth = true,
                enabled = canConfirm,
            ) {
                onConfirm(phone.trim())
            }
        }
    }

    LaunchedEffect(Unit) {
        // Le champ est le seul de la feuille : le clavier arrive avec elle
        // plutôt que d'attendre une touche de plus.
        delay(250)
        focus = WhatsAppField.Phone
    }
}

private enum class WhatsAppField { Phone }

@Preview(locale = "fr-rFR", name = "Numéro WhatsApp", widthDp = 390)
@Composable
private fun OrderWhatsAppSheetPreview() {
    Box(Modifier.background(MemoBookColor.background)) {
        OrderWhatsAppSheet(suggested = null) {}
    }
}
