package com.memobook.feature.debug

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.memobook.design.BrandImages
import com.memobook.design.BrandText
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing

/**
 * L'écran-catalogue du design system : chaque couleur, chaque style de texte,
 * chaque image du catalogue et chaque composant `Brand…`, sur une seule page.
 *
 * **Un outil de développement, sans jumeau iOS** : là-bas, les previews Xcode
 * jouent ce rôle écran par écran. Ici, on le parcourt dans l'émulateur à côté
 * de l'iPhone, et c'est ce qui permet de vérifier la parité d'un coup d'œil.
 * Il ne s'ouvre qu'en Debug : `make run ARGS="--ez designCatalogue true"`.
 */
@Composable
fun DesignCatalogueView() {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(MemoBookColor.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
        contentPadding = PaddingValues(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.m),
    ) {
        item { BrandText("Design system", MemoBookFont.h1) }
        catalogueSection("Couleurs") { Colors() }
        catalogueSection("Textes") { Typography() }
        DesignCatalogueSections.all.forEach { (title, content) -> catalogueSection(title, content) }
        catalogueSection("Images (${BrandImages.names.size})") { Images() }
    }
}

private fun LazyListScope.catalogueSection(title: String, content: @Composable () -> Unit) {
    item(key = title) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            BrandText(title.uppercase(), MemoBookFont.sectionOverline, color = MemoBookColor.inkMuted)
            content()
        }
    }
}

private val colors: List<Pair<String, Color>> = listOf(
    "action" to MemoBookColor.action, "actionLight" to MemoBookColor.actionLight,
    "ink" to MemoBookColor.ink, "inkMuted" to MemoBookColor.inkMuted, "gray" to MemoBookColor.gray,
    "background" to MemoBookColor.background, "surface" to MemoBookColor.surface, "beige" to MemoBookColor.beige,
    "noticeBeige" to MemoBookColor.noticeBeige, "listening" to MemoBookColor.listeningBackground,
    "outline" to MemoBookColor.outline, "accent" to MemoBookColor.accent, "blueText" to MemoBookColor.blueText,
    "separator" to MemoBookColor.separator, "disabled" to MemoBookColor.disabled, "valid" to MemoBookColor.valid,
    "warning" to MemoBookColor.warning, "error" to MemoBookColor.error, "errorSoft" to MemoBookColor.errorSoft,
    "information" to MemoBookColor.information, "coverForest" to MemoBookColor.coverForest,
    "coverPostmark" to MemoBookColor.coverPostmark, "coverMint" to MemoBookColor.coverMint,
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Colors() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        colors.forEach { (name, color) ->
            Column(Modifier.width(76.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier
                        .size(48.dp)
                        .background(color, RoundedCornerShape(MemoBookSpacing.pageCornerRadius))
                        .border(1.dp, MemoBookColor.hairline, RoundedCornerShape(MemoBookSpacing.pageCornerRadius)),
                )
                BrandText(name, MemoBookFont.mention, color = MemoBookColor.inkMuted, maxLines = 1)
            }
        }
    }
}

private val textStyles: List<Pair<String, TextStyle>> = listOf(
    "h1" to MemoBookFont.h1, "h1Light" to MemoBookFont.h1Light, "h2" to MemoBookFont.h2,
    "heading" to MemoBookFont.heading, "button" to MemoBookFont.button, "cardTitle" to MemoBookFont.cardTitle,
    "eyebrow" to MemoBookFont.eyebrow, "body" to MemoBookFont.body, "bodySemibold" to MemoBookFont.bodySemibold,
    "bubble" to MemoBookFont.bubble, "label" to MemoBookFont.label, "caption" to MemoBookFont.caption,
    "overline" to MemoBookFont.overline, "handwriting" to MemoBookFont.handwriting,
)

@Composable
private fun Typography() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        textStyles.forEach { (name, style) ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                BrandText(name, MemoBookFont.mention, color = MemoBookColor.inkMuted, modifier = Modifier.width(88.dp))
                BrandText("Mon carnet de voyage", style, maxLines = 1)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Images() {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs), verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
        BrandImages.names.sorted().forEach { name ->
            Column(Modifier.width(76.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Image(
                    painter = painterResource(BrandImages[name]!!),
                    contentDescription = name,
                    modifier = Modifier
                        .size(56.dp)
                        .background(MemoBookColor.surface, RoundedCornerShape(MemoBookSpacing.pageCornerRadius))
                        .padding(6.dp),
                )
                BrandText(name.removePrefix("Icon"), MemoBookFont.mention, color = MemoBookColor.inkMuted, maxLines = 1)
            }
        }
    }
    Spacer(Modifier.height(MemoBookSpacing.xl).fillMaxWidth())
}
