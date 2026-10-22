package com.memobook.feature.profile

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.memobook.core.Connector
import com.memobook.design.BrandComingSoon
import com.memobook.design.BrandImages
import com.memobook.design.BrandSheet
import com.memobook.design.BrandSheetHost
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import kotlinx.coroutines.Dispatchers

/**
 * Brancher MemoBook sur les apps qui savent déjà où tu es allé. Jumeau de
 * `Profile/ConnectorsSheet.swift`.
 *
 * Chaque ligne était un **consentement** : le nom de l'app, ce que MemoBook
 * fera de l'accès, et l'interrupteur. **Aucun ne se branche encore** (T76) :
 * depuis le 08/10/2026, les six se montrent « À venir », pâlis et sans
 * interrupteur (Hugo : « pour montrer que ce n'est pas encore disponible »).
 * La promesse reste écrite en toutes lettres : c'est elle qu'on annonce.
 */
@Composable
internal fun ConnectorsSheet(model: ProfileModel) {
    val state by model.state.collectAsStateWithLifecycle(context = Dispatchers.Main.immediate)

    BrandSheet(ConnectorsCopy.title, subtitle = ConnectorsCopy.promise) {
        Column(
            // La pastille du premier dépasse au-dessus de sa carte.
            Modifier.padding(top = MemoBookSpacing.xs),
            verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
        ) {
            state.profile?.connectors.orEmpty().forEach { connector -> ConnectorCard(connector) }
        }
    }
}

/**
 * Une app tierce et sa promesse, **à venir**.
 *
 * L'interrupteur reviendra le jour où le serveur saura brancher le
 * connecteur : un interrupteur qui bascule sans rien brancher mentirait.
 */
@Composable
private fun ConnectorCard(connector: Connector) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    BrandComingSoon {
        Box(
            Modifier
                .fillMaxWidth()
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .padding(MemoBookSpacing.s),
        ) {
            val text: @Composable () -> Unit = {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    BrandText(connector.name, MemoBookFont.bodySemibold, Modifier.fillMaxWidth())
                    BrandText(connector.promise, MemoBookFont.body, Modifier.fillMaxWidth(), color = MemoBookColor.inkMuted)
                }
            }

            // En taille accessible, le logo passe au-dessus : lui garder sa
            // colonne laisserait à la promesse une largeur de deux mots.
            if (isAccessibilityTextSize()) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    ConnectorLogo(connector)
                    text()
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.Top) {
                    ConnectorLogo(connector)
                    text()
                }
            }
        }
    }
}

/**
 * Le logo d'une app tierce.
 *
 * Ce sont des marques qui ne nous appartiennent pas : elles gardent leurs
 * couleurs — donc **pas** de teinte — et ne sont jamais remplacées par une
 * icône du jeu MemoBook, qui induirait en erreur. La pastille à initiale reste
 * le repli quand un connecteur arrive sans logo.
 */
@Composable
private fun ConnectorLogo(connector: Connector) {
    val side = scaled(40.dp)
    val shape = RoundedCornerShape(MemoBookSpacing.cornerRadius - 2.dp)
    val logo = connector.logoAssetName?.let { BrandImages[it] }
    Box(
        Modifier
            .size(side)
            .clip(shape)
            // Un filet très clair : plusieurs de ces logos sont blancs sur
            // blanc et se dissoudraient dans la carte sans lui.
            .border(1.dp, MemoBookColor.hairline, shape)
            .clearAndSetSemantics {},
        contentAlignment = Alignment.Center,
    ) {
        if (logo != null) {
            Image(painterResource(logo), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(side))
        } else {
            Box(Modifier.size(side).background(MemoBookColor.outline), contentAlignment = Alignment.Center) {
                BrandText(connector.name.take(1).uppercase(), MemoBookFont.bodySemibold)
            }
        }
    }
}

@Preview(locale = "fr-rFR", name = "Connecteurs", heightDp = 900)
@Composable
private fun ConnectorsSheetPreview() {
    val model = remember { ProfileModel() }
    LaunchedEffect(model) { model.load() }
    BrandSheetHost(isPresented = true, onDismissRequest = {}) { ConnectorsSheet(model) }
}
