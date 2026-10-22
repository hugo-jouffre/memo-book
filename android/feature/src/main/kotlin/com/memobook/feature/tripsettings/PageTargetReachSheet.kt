package com.memobook.feature.tripsettings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import com.memobook.core.BookCopy
import com.memobook.core.PageTargetReach
import com.memobook.design.BrandButton
import com.memobook.design.BrandSheet
import com.memobook.design.MemoBookSpacing

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
 * Elle passe **avant** la feuille du changement de cible
 * ([PageTargetChangeSheet]) : rien n'a changé tant qu'on n'a pas répondu.
 */
@Composable
internal fun PageTargetReachSheet(reach: PageTargetReach, model: BookCustomisationModel) {
    BrandSheet(
        BookCopy.Pages.reachTitle,
        paragraphs = listOf(BookCopy.Pages.reachToday(reach), BookCopy.Pages.reachLevers(reach)),
    ) {
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
