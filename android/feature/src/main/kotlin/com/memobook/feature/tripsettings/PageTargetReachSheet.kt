package com.memobook.feature.tripsettings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import com.memobook.core.BookCopy
import com.memobook.core.PageTargetReach
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.MemoBookSpacing
import com.memobook.feature.profile.euros

/**
 * **Une cible personnalisée hors d'atteinte** (Hugo, 18/10/2026). Jumeau de
 * `TripSettings/PageTargetReachSheet.swift`.
 *
 * Elle dit, dans l'ordre : ce que le carnet peut faire avec les réglages du
 * moment, puis comment aller chercher la cible voulue — raconter plus,
 * envoyer plus de photos, monter le ratio. Trois réponses : la cible
 * atteignable la plus proche (le bouton plein), le ratio qui ouvre la cible
 * voulue quand il y en a un, et garder la cible telle quelle — le carnet s'en
 * approchera sans rien forcer.
 *
 * **Les deux premières réponses s'appliquent d'un seul appui** (Hugo,
 * 04/11/2026). Elles ouvraient derrière elles la feuille qui redemande
 * « Changer le nombre de pages cible ? » : on venait de choisir, et la même
 * question revenait. Ce que cette confirmation disait — la règle des deux
 * changements — se lit donc **ici**, avant l'appui.
 *
 * Elle annonce aussi **le prix de la cible proposée**, à la tolérance près —
 * la même règle que les paliers de l'écran (`BookCopy.Pages.reachPrice`).
 * Rien sans grille servie : mieux vaut pas de prix qu'un prix faux.
 */
@Composable
internal fun PageTargetReachSheet(reach: PageTargetReach, model: BookCustomisationModel) {
    val allowance = model.pageTargetAllowance
    val paragraphs = buildList {
        add(BookCopy.Pages.reachToday(reach))
        add(BookCopy.Pages.reachLevers(reach))
        // Le prix du carnet à la cible proposée. `null` sans grille : la
        // ligne ne paraît pas.
        model.printPricing?.displayedPrice(forTarget = reach.closestTarget)?.let { prix ->
            add(BookCopy.Pages.reachPrice(pages = reach.closestTarget, price = prix.euros))
        }
        // Un changement qui ne compte pas — avant le premier souvenir — n'a
        // rien à annoncer : la phrase ne paraît que quand le décompte court.
        if (allowance.changesCount && allowance.changesLeft > 0) {
            add(BookCopy.Pages.reachCountsAsChange(allowance.changesLeft))
        }
    }

    BrandSheet(BookCopy.Pages.reachTitle, paragraphs = paragraphs) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandButton(
                BookCopy.Pages.chooseReachable(reach.closestTarget),
                fillsWidth = true,
                action = model::chooseReachableTarget,
            )
            reach.ratioThatReaches?.let { ratio ->
                BrandButton(
                    BookCopy.Pages.raiseRatio(ratio),
                    style = BrandButton.Style.Secondary,
                    fillsWidth = true,
                    action = model::raiseRatioForTarget,
                )
            }
            BrandButton(
                BookCopy.Pages.keepAnyway(reach.target),
                style = BrandButton.Style.Link,
                fillsWidth = true,
                action = model::keepUnreachableTarget,
            )
        }
    }
}
