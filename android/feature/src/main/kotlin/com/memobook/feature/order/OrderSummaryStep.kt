package com.memobook.feature.order

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.memobook.core.OrderCopy
import com.memobook.core.OrderQuote
import com.memobook.core.OrderQuoteGroup
import com.memobook.design.BrandButton
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandText
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.SwiftMotion

/**
 * Étape 5 — le récapitulatif : ce qu'on imprime, en combien d'exemplaires, et
 * ce qu'il y a à payer. Jumeau de `Order/OrderSummaryStep.swift`.
 *
 * **Aucun montant n'est calculé ici.** Tout arrive de
 * `POST /v1/memos/:id/orders/quote`, y compris les sous-totaux : deux calculs
 * pour un même total finiraient par se contredire, et c'est l'app qui aurait
 * tort devant la personne qui paie.
 *
 * Il est le plus souvent **déjà là** quand on arrive : le devis part dès que le
 * nombre d'exemplaires ou la rapidité changent, donc bien avant cette étape. Le
 * squelette ne se voit que sur un réseau lent.
 */
@Composable
internal fun OrderSummaryStep(state: OrderModel.State, model: OrderModel) {
    val quote = state.quote
    val error = state.quoteError
    val shown: SummaryContent = when {
        quote != null -> SummaryContent.Card(quote)
        error != null -> SummaryContent.Failure(error)
        else -> SummaryContent.Waiting
    }

    OrderStepLayout(
        content = {
            OrderSectionHeader(OrderCopy.Summary.title)

            AnimatedContent(
                targetState = shown,
                contentKey = { it::class },
                transitionSpec = { fadeIn(SwiftMotion.smooth(0.3f)) togetherWith fadeOut(SwiftMotion.smooth(0.3f)) },
                label = "récapitulatif",
            ) { content ->
                when (content) {
                    is SummaryContent.Card -> SummaryCard(content.quote)
                    is SummaryContent.Failure -> ErrorBanner(content.message, retry = model::refreshQuote)
                    SummaryContent.Waiting -> SummarySkeleton()
                }
            }
        },
        actions = {
            BrandButton(
                OrderCopy.Summary.cta,
                fillsWidth = true,
                enabled = state.canContinue,
                action = model::advance,
            )
        },
    )
}

/** Ce que l'étape montre sous son titre — chaque cas garde sa valeur pendant qu'il s'efface. */
private sealed interface SummaryContent {
    data class Card(val quote: OrderQuote) : SummaryContent

    data class Failure(val message: String) : SummaryContent

    data object Waiting : SummaryContent
}

/**
 * Le bloc bleu de la maquette : deux groupes qui portent chacun leur
 * sous-total, puis le total. Les déductions de la cagnotte, qui se posaient
 * entre les deux, sont parties avec elle (T230).
 */
@Composable
private fun SummaryCard(quote: OrderQuote) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Column(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.listeningBackground.copy(alpha = 0.45f), shape)
            .border(1.dp, MemoBookColor.outline.copy(alpha = 0.6f), shape)
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandText(OrderCopy.Summary.book(quote.bookTitle), MemoBookFont.bodySemibold)

        SummaryGroup(quote.book)

        // La fabrication ne se choisit pas : elle se **lit**, sous le prix. Elle
        // était facturée en trois lignes, ce qui laissait croire à trois
        // options — alors qu'il n'y a qu'un papier, qu'une couverture et
        // qu'une reliure, et que le prix ne suit que les pages.
        if (quote.specifications.isNotEmpty()) {
            SummarySpecifications(quote.specifications)
        }

        SummarySeparator()
        SummaryGroup(quote.fulfilment)

        SummarySeparator()

        OrderPriceRow(OrderCopy.Summary.total, amount = quote.total, isProminent = true)
    }
}

/**
 * Un groupe de lignes, et le sous-total qui les ferme.
 *
 * **Le sous-total disparaît quand il ne fait que répéter.** Depuis que le
 * carnet ne se facture qu'en une ligne, le groupe du haut affichait deux fois
 * le même montant l'un sous l'autre — un total de rien du tout.
 *
 * **Il porte son libellé** (Hugo, 06/10/2026, T216) : un montant seul sous
 * « Livraison » se lisait comme le prix de la livraison. Le motif est celui des
 * autres lignes : le libellé à gauche, le montant en semi-gras à droite, comme
 * il l'était déjà.
 */
@Composable
private fun SummaryGroup(group: OrderQuoteGroup) {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        group.lines.forEach { line ->
            OrderPriceRow(line.label, detail = line.detail, amount = line.amount)
        }

        if (group.lines.size > 1) {
            OrderPriceRow(OrderCopy.Summary.subtotal, amount = group.subtotal)
        }
    }
}

/** La petite boîte qui décrit le carnet, sous son prix. */
@Composable
private fun SummarySpecifications(items: List<String>) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.surface.copy(alpha = 0.7f), RoundedCornerShape(MemoBookSpacing.cornerRadius))
            .padding(horizontal = MemoBookSpacing.snug, vertical = MemoBookSpacing.xs)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        BrandText(OrderCopy.Summary.specifications.uppercase(), MemoBookFont.overline, color = MemoBookColor.inkMuted)

        // Séparés par des points médians plutôt qu'en liste à puces : c'est une
        // description, pas un choix, et trois puces rendraient la hiérarchie des
        // lignes facturées au-dessus.
        BrandText(items.joinToString(" · "), MemoBookFont.label)

        BrandText(OrderCopy.Summary.pricedByPages, MemoBookFont.caption, color = MemoBookColor.inkMuted)
    }
}

@Composable
private fun SummarySeparator() {
    Box(
        Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(MemoBookColor.ink.copy(alpha = 0.12f))
            .clearAndSetSemantics {},
    )
}

@Composable
private fun SummarySkeleton() {
    Column(
        Modifier
            .fillMaxWidth()
            .background(MemoBookColor.listeningBackground.copy(alpha = 0.45f), RoundedCornerShape(MemoBookSpacing.largeCornerRadius))
            .padding(MemoBookSpacing.s),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandSkeleton(width = 200.dp, height = 18.dp)
        repeat(6) {
            Row {
                BrandSkeleton(width = 150.dp)
                Spacer(Modifier.weight(1f))
                BrandSkeleton(width = 60.dp)
            }
        }
    }
}
