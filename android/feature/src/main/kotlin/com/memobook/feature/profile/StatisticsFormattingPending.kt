package com.memobook.feature.profile

import java.time.Instant

// À brancher : Profile/StatisticsFormatting.swift
//
// Le lot du profil porte `StatisticsFormatting` ; `ProfileFormatting.kt` en lit
// une seule fonction, déclarée ici sous son nom Swift en attendant. L'intégrateur
// supprime ce fichier à la fusion.

/**
 * « 10/12/2026 - 02/01/2027 » : deux dates numériques sur une ligne — le
 * `Date.numericRangeLabel(from:to:)` d'iOS. Rend `null` en attendant le portage.
 */
@Suppress("UNUSED_PARAMETER")
internal fun numericRangeLabel(from: Instant?, to: Instant?): String? = null
