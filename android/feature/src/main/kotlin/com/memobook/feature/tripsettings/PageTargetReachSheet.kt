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
 * **Les deux premières réponses s'appliquent d'un seul appui** (Hugo,
 * 04/11/2026). Elles ouvraient derrière elles la feuille qui redemande
 * « Changer le nombre de pages cible ? » : on venait de choisir, et la même
 * question revenait. Ce que cette confirmation disait — la règle des deux
 * changements — se lit donc **ici**, avant l'appui.
 *
 * ⚠️ **Le prix de la cible proposée manque encore ici**, là où iOS l'affiche
 * (`BookCopy.Pages.reachPrice`) : `PrintPricing` n'est pas porté sur Android,
 * et cet écran n'affiche aucun prix nulle part. À reprendre avec le portage
 * des prix, pas avant — une seule ligne chiffrée sur un écran qui n'en a
 * aucune se lirait comme une erreur.
 */
@Composable
internal fun PageTargetReachSheet(reach: PageTargetReach, model: BookCustomisationModel) {
    val allowance = model.pageTargetAllowance
    val paragraphs = buildList {
        add(BookCopy.Pages.reachToday(reach))
        add(BookCopy.Pages.reachLevers(reach))
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
