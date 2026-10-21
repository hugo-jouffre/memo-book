package com.memobook.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * **Le** bloc d'information de l'app : une phrase posée sur un aplat beige, qui
 * dit à quoi s'en tenir sans rien demander. Jumeau de `BrandNotice.swift`.
 *
 * Ce n'est ni une erreur ni une alerte. [ErrorBanner] dit « quelque chose a
 * raté, voilà le bouton pour réessayer » ; celui-ci dit « voilà où on en est,
 * tu peux continuer » — pas de rouge, pas d'action. Il disparaît tout seul
 * quand la situation qu'il décrit a changé.
 *
 * Il a **trois tons** — voir [Tone] : le beige de l'état des choses, le bleu
 * d'information pour ce qu'on vient d'expliquer à quelqu'un qui a tapé là où ça
 * ne mène pas encore, et l'orange d'une porte qui ne s'ouvrira plus.
 *
 * **Le gras n'est pas une décoration** : chaque message porte une phrase qui
 * compte — ce que la personne peut faire malgré la panne, ou ce qui est garanti
 * malgré elle — et c'est elle qu'on lit en diagonale. Elle se marque avec
 * `**…**`, comme en Markdown, résolu une fois par message et non à chaque image.
 *
 * @param markup le message, dont la partie qui compte est entourée de `**`. Un
 *   balisage invalide n'efface rien : la phrase s'affiche telle quelle, sans gras.
 * @param tone neutre par défaut, c'est-à-dire le bloc d'avant.
 * @param footer ce qui se pose **sous la phrase, dans la boîte** : un lien,
 *   jamais un pavé. Quand la boîte explique pourquoi une porte est fermée, elle
 *   peut porter celle qui reste ouverte, et c'est plus honnête que de renvoyer
 *   ailleurs (Hugo, 19/09/2026). `null` dans la quasi-totalité des cas.
 */
@Composable
fun BrandNotice(
    markup: String,
    modifier: Modifier = Modifier,
    tone: BrandNotice.Tone = BrandNotice.Tone.Neutral,
    footer: (@Composable () -> Unit)? = null,
) {
    val message = remember(markup) { BrandNotice.resolved(markup) }
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    val accent = tone.accent

    // Le fond. Sur iOS, **un verre dépoli sous un beige doux** pour le ton
    // neutre (Hugo, 17/09/2026) : l'aplat `Beige Darker` d'avant était trop
    // foncé. Compose Foundation ne floute pas ce qui passe dessous : l'aplat
    // beige à 70 % reste seul, avec le liseré blanc qui fait le bord du verre.
    val backdrop = if (accent == null) {
        Modifier
            .background(MemoBookColor.noticeBeige.copy(alpha = 0.7f), shape)
            .border(1.dp, Color.White.copy(alpha = 0.45f), shape)
    } else {
        Modifier
            .background(tone.background, shape)
            .border(1.dp, accent, shape)
    }

    Column(
        modifier
            .then(backdrop)
            .padding(MemoBookSpacing.s)
            .semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (accent == null) {
            NoticeText(message, TextAlign.Center, Modifier.fillMaxWidth())
        } else {
            // Le pictogramme se cale sur la **première ligne** du texte et non
            // sur le milieu du bloc : sur trois lignes, un centrage vertical le
            // faisait descendre au milieu de la phrase. Son centre se pose à
            // mi-hauteur des capitales, comme un symbole SF sur sa ligne.
            val capHalf = with(LocalDensity.current) { (MemoBookFont.body.fontSize * 0.7f).toPx() / 2 }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                Image(
                    painter = painterResource(
                        if (tone == BrandNotice.Tone.Warning) R.drawable.system_exclamation_circle_fill else R.drawable.system_info_circle_fill,
                    ),
                    contentDescription = null,
                    colorFilter = ColorFilter.tint(accent),
                    modifier = Modifier
                        .size(scaled(22.dp))
                        .alignBy { it.measuredHeight / 2 + capHalf.roundToInt() },
                )
                NoticeText(message, TextAlign.Start, Modifier.weight(1f).alignByBaseline())
            }
        }
        footer?.invoke()
    }
}

// Le texte, en `BasicText` et non en `BrandText` : c'est le seul texte du design
// system qui porte des portions en demi-gras.
@Composable
private fun NoticeText(message: AnnotatedString, alignment: TextAlign, modifier: Modifier) {
    BasicText(
        message,
        modifier,
        style = MemoBookFont.body.copy(color = MemoBookColor.ink, textAlign = alignment),
    )
}

object BrandNotice {
    /** Ce que le bloc dit de lui-même. */
    enum class Tone(internal val accent: Color?, internal val background: Color) {
        /** L'état des choses, sur le beige de la marque. Le cas courant. */
        Neutral(null, MemoBookColor.noticeBeige),

        /**
         * **Une explication qu'on vient de demander** : pourquoi un réglage n'est
         * pas ouvert, pourquoi une porte ne mène nulle part. Un filet, un
         * pictogramme et un aplat très clair en [MemoBookColor.information] —
         * elle répond à un geste au lieu de décrire un fond de situation. Le bleu
         * est très dilué : un fond bleu franc sous du texte encre tombe sous le
         * contraste demandé.
         */
        Information(MemoBookColor.information, MemoBookColor.information.copy(alpha = 0.12f)),

        /**
         * **Une limite atteinte, définitive** : ce qu'on a demandé ne se fera pas,
         * et ce n'est pas une panne — la seconde fois qu'on change le nombre de
         * pages cible d'un voyage (Hugo, 15/10/2026). Même dessin, à l'orange
         * [MemoBookColor.warning] : le bleu dit « pas encore » ou « voilà
         * pourquoi », l'orange « plus jamais pour ce voyage ». Ce n'est pas le
         * rouge d'[ErrorBanner] : rien n'a raté.
         */
        Warning(MemoBookColor.warning, MemoBookColor.warning.copy(alpha = 0.12f)),
    }

    /**
     * Traduit `**…**` en portions de texte en demi-gras.
     *
     * Le gras est une **autre police** — General Sans Semibold —, pas un
     * épaississement du tracé : demander une graisse que la famille embarquée
     * n'a pas donnerait un faux gras synthétique.
     *
     * iOS passe par le Markdown d'`AttributedString` ; seul `**` y sert, et
     * c'est lui seul qu'on lit ici. Une paire mal formée — sans fermeture, ou
     * qui s'ouvre ou se ferme sur une espace, comme en Markdown — reste écrite
     * telle quelle.
     */
    internal fun resolved(markup: String): AnnotatedString = buildAnnotatedString {
        val emphasis = MemoBookFont.bodySemibold.toSpanStyle()
        var index = 0
        while (index < markup.length) {
            val open = markup.indexOf("**", index)
            if (open < 0) break
            val close = markup.indexOf("**", open + 2)
            if (close < 0) break
            val inner = markup.substring(open + 2, close)
            if (inner.isEmpty() || inner.first().isWhitespace() || inner.last().isWhitespace()) {
                append(markup, index, open + 2)
                index = open + 2
                continue
            }
            append(markup, index, open)
            withStyle(emphasis) { append(inner) }
            index = close + 2
        }
        append(markup, index, markup.length)
    }
}

@Preview(name = "Bloc d’information", widthDp = 390)
@Composable
private fun BrandNoticePreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandNotice(
            "Tu sembles hors ligne. **Tu peux consulter tes récits et enregistrer des étapes**, qui seront retranscrites plus tard.",
        )
        BrandNotice("**Tes vocaux enregistrés hors ligne sont bien conservés.** Ils seront envoyés dès ta reconnexion.")
        BrandNotice("**Ton vocal est bien arrivé.** Il sera retranscrit dans quelques instants.")
        BrandNotice(
            "Les pointillés arrivent avec la prochaine version. **Ton carnet les recevra sans rien perdre.**",
            tone = BrandNotice.Tone.Information,
        ) {
            BrandButton("Ouvrir les Réglages", style = BrandButton.Style.Link) {}
        }
        BrandNotice("**La cible de pages ne peut plus changer** pour ce voyage.", tone = BrandNotice.Tone.Warning)
    }
}
