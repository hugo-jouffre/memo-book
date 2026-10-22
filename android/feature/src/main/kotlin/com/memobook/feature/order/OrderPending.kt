package com.memobook.feature.order

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.memobook.core.Destination
import com.memobook.core.TripStage
import com.memobook.core.TripStats
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.feature.home.inlineSummary

// À brancher : Home/TripCards.swift (StageBadge, DestinationLabel, TripStatsRow).
//
// Le lot de l'accueil porte ces trois pièces communes des cartes ; la carte du
// voyage du tunnel (`OrderTripCard`) les emploie sous leur nom Swift et leur
// signature probable. Ici, le strict nécessaire pour que la carte ne soit pas
// vide. L'intégrateur supprime ce fichier à la fusion, et importe celles de
// `com.memobook.feature.home`.

/** La pastille d'état d'un voyage. */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun StageBadge(stage: TripStage) = Unit

/** Le drapeau et le pays, en capitales. */
@Composable
internal fun DestinationLabel(destination: Destination) {
    BrandText(destination.name.uppercase(), MemoBookFont.overline)
}

/** Durée, distance, photos. */
@Suppress("UNUSED_PARAMETER")
@Composable
internal fun TripStatsRow(stats: TripStats, tint: Color? = null, isSpread: Boolean = true) {
    stats.inlineSummary?.let { BrandText(it, MemoBookFont.label, color = tint ?: MemoBookColor.ink) }
}
