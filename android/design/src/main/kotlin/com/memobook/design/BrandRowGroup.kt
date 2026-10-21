package com.memobook.design

import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.pow

/**
 * Une pile de lignes réunies dans une même carte, séparées par un filet : le
 * motif des écrans de réglages. Jumeau de `BrandRowGroup.swift`.
 *
 * C'est **le** composant de ce motif — profil, paramètres du voyage,
 * personnalisations —, et c'est cette unicité qui fait qu'une ligne se touche,
 * se lit et sonne pareil d'un écran à l'autre.
 *
 * ```kotlin
 * BrandRowGroup {
 *     +BrandRow("E-mail", value = account.email)
 *     +BrandRow("Adresse postale", value = address, action = openAddress)
 *     +BrandRow("Newsletter mensuelle MemoBook", isOn = wantsNewsletter, onIsOnChange = { … })
 * }
 * ```
 *
 * Ce que le groupe prend en charge, et qu'aucun écran n'a donc à refaire : la
 * coque, les filets (posés **entre** les lignes, jamais aux extrémités), la
 * hauteur minimale de cible tactile, le passage en colonne aux tailles de
 * texte accessibles, et la manière dont TalkBack lit chaque ligne.
 *
 * @param rows les lignes, écrites les unes sous les autres avec les `if` qu'un
 *   écran a le droit d'avoir — voir [BrandRowBuilder].
 */
@Composable
fun BrandRowGroup(
    modifier: Modifier = Modifier,
    tone: BrandRowGroup.Tone = BrandRowGroup.Tone.Plain,
    rows: BrandRowBuilder.() -> Unit,
) {
    BrandRowGroup(BrandRowBuilder().apply(rows).rows, modifier, tone)
}

/** Le même groupe, pour des lignes déjà en liste — celles qu'on tire d'un modèle. */
@Composable
fun BrandRowGroup(
    rows: List<BrandRow>,
    modifier: Modifier = Modifier,
    tone: BrandRowGroup.Tone = BrandRowGroup.Tone.Plain,
) {
    val shape = RoundedCornerShape(MemoBookSpacing.largeCornerRadius)
    Column(
        modifier
            // Le rognage garde les coins arrondis sous une ligne pressée, dont
            // l'aplat de sélection déborderait sinon en haut et en bas du groupe.
            .clip(shape)
            .background(MemoBookColor.surface, shape)
            .border(tone.borderWidth, tone.separator, shape),
    ) {
        rows.forEachIndexed { index, row ->
            key(row.id) {
                if (index > 0) {
                    // Le filet sépare, il n'encadre pas : il vit entre deux
                    // lignes et s'arrête aux marges du texte.
                    Box(
                        Modifier
                            .padding(horizontal = MemoBookSpacing.s)
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(tone.separator)
                            .clearAndSetSemantics {},
                    )
                }
                BrandRowContent(row)
            }
        }
    }
}

object BrandRowGroup {
    /** Comment le groupe se cerne. Le filet entre deux lignes suit le contour : un trait gris dans un cadre vert se lirait comme un oubli. */
    enum class Tone(internal val separator: Color, internal val borderWidth: Dp) {
        /** Le filet discret du motif courant : le groupe range des lignes, il ne les met pas en avant. */
        Plain(MemoBookColor.hairline, 1.dp),

        /**
         * Le contour vert. Pour **un** groupe par écran, celui qu'on vient
         * chercher du regard — les chiffres du profil. Deux groupes cerclés sur
         * le même écran ne mettraient plus rien en avant.
         */
        Highlighted(MemoBookColor.action, 1.5.dp),
    }
}

/**
 * De quoi écrire les lignes d'un [BrandRowGroup] les unes sous les autres — le
 * `@resultBuilder` de Swift : `+BrandRow(…)` ajoute une ligne, `+lignes` une
 * liste, et un `if` fait une ligne qui n'apparaît que si la donnée existe.
 */
class BrandRowBuilder internal constructor() {
    internal val rows = mutableListOf<BrandRow>()

    operator fun BrandRow.unaryPlus() {
        rows += this
    }

    operator fun Iterable<BrandRow>.unaryPlus() {
        rows += this
    }
}

/**
 * Une ligne d'un [BrandRowGroup].
 *
 * C'est une **description**, pas une vue libre : l'écran dit ce que la ligne
 * porte, le composant décide comment ça se dessine. C'est ce qui garantit que
 * deux écrans n'inventent pas deux hauteurs de ligne ni deux chevrons.
 *
 * Trois façons d'en faire une, comme les trois `init` de Swift : une ligne de
 * lecture (qui mène quelque part si on lui donne une action), une ligne qu'on
 * corrige sur place (`text` / `onTextChange`), une ligne à interrupteur
 * (`isOn` / `onIsOnChange`).
 */
class BrandRow private constructor(
    internal val title: String,
    internal val value: String?,
    internal val valuePlacement: ValuePlacement,
    internal val valueTone: ValueTone,
    internal val titleTone: TitleTone,
    internal val titleIcon: TitleIcon?,
    internal val badge: String?,
    internal val isValueLoading: Boolean,
    internal val accessory: Accessory,
    internal val footnote: Footnote?,
    internal val isConfirmed: Boolean,
    internal val action: (() -> Unit)?,
) {
    /**
     * Une ligne qui montre une valeur, et qui mène quelque part si on lui
     * donne une action.
     *
     * @param value `null` quand la ligne n'a qu'un intitulé.
     * @param valueTone comment la valeur se lit — voir [ValueTone].
     * @param titleTone [TitleTone.Accent] pour les lignes d'un groupe cerclé de
     *   vert, dont l'intitulé se lit comme un surtitre.
     * @param titleIcon un petit logo après l'intitulé, à la place d'une note
     *   qui dirait la même chose en une phrase.
     * @param badge une pastille en bout de ligne, pour dire d'un mot ce que la
     *   valeur ne dit pas — qu'elle est sous clé, par exemple. Un mot, pas une
     *   phrase : « LOCKED », « BIENTÔT ».
     * @param isValueLoading la valeur est encore en route : une barre d'attente
     *   tient sa place ([BrandSkeleton]). **L'intitulé, lui, s'affiche tout de
     *   suite** : il appartient à l'app, pas au serveur.
     * @param note une précision affichée sous la ligne, en petit — qu'une valeur
     *   vient d'ailleurs et ne se corrige pas ici, par exemple.
     * @param isConfirmed la valeur vient d'être **enregistrée par le serveur** :
     *   le chevron devient une coche verte le temps qu'on la voie — pour une
     *   ligne dont la feuille s'est refermée avant que la réponse arrive
     *   (l'adresse postale).
     * @param action `null` fait une ligne de lecture, sans chevron ni retour
     *   tactile.
     */
    constructor(
        title: String,
        value: String? = null,
        valuePlacement: ValuePlacement = ValuePlacement.Trailing,
        valueTone: ValueTone = ValueTone.Plain,
        titleTone: TitleTone = TitleTone.Plain,
        titleIcon: TitleIcon? = null,
        badge: String? = null,
        isValueLoading: Boolean = false,
        note: String? = null,
        isConfirmed: Boolean = false,
        action: (() -> Unit)? = null,
    ) : this(
        title = title,
        value = value,
        valuePlacement = valuePlacement,
        valueTone = valueTone,
        titleTone = titleTone,
        titleIcon = titleIcon,
        badge = badge,
        isValueLoading = isValueLoading,
        accessory = if (action == null) Accessory.None else Accessory.Disclosure,
        footnote = note?.let { Footnote.Note(it) },
        isConfirmed = isConfirmed,
        action = action,
    )

    /**
     * Une ligne dont la valeur se corrige **sur place**.
     *
     * Le clavier s'ouvre sur cet écran, sans feuille ni écran intermédiaire, et
     * la valeur est enregistrée quand le champ perd le focus — clavier refermé,
     * passage à un autre champ, ou sortie de l'écran. C'est le comportement des
     * Réglages d'iOS : on corrige une ligne, on ne « valide » pas un formulaire.
     *
     * **La ligne ne change pas d'apparence en se corrigeant** : ni cadre, ni
     * aplat, ni déplacement. Seul le curseur apparaît.
     *
     * La valeur du modèle n'est touchée qu'**à la sortie du champ**, pas à
     * chaque frappe : un appel réseau par correction et non un par caractère.
     *
     * @param error ce qui ne va pas dans ce qui vient d'être saisi, en rouge sous la ligne.
     * @param textContentType le `textContentType` d'iOS : ce que le remplissage
     *   automatique peut proposer.
     * @param isConfirmed la correction est **enregistrée côté serveur** : le
     *   crayon devient une coche verte le temps qu'on la voie. C'est le seul
     *   accusé de réception d'une ligne qui s'enregistre toute seule.
     */
    constructor(
        title: String,
        text: String,
        onTextChange: (String) -> Unit,
        placeholder: String? = null,
        error: String? = null,
        keyboardType: KeyboardType = KeyboardType.Text,
        textContentType: ContentType? = null,
        isValueLoading: Boolean = false,
        isConfirmed: Boolean = false,
    ) : this(
        title = title,
        value = null,
        valuePlacement = ValuePlacement.Trailing,
        valueTone = ValueTone.Plain,
        titleTone = TitleTone.Plain,
        titleIcon = null,
        badge = null,
        isValueLoading = isValueLoading,
        accessory = Editable(text, onTextChange, placeholder, keyboardType, textContentType, isConfirmed),
        footnote = error?.let { Footnote.Problem(it) },
        isConfirmed = isConfirmed,
        action = null,
    )

    /** Une ligne qui porte un interrupteur. Elle n'a pas d'action : c'est l'interrupteur qui agit, et lui seul. */
    constructor(title: String, isOn: Boolean, onIsOnChange: (Boolean) -> Unit) : this(
        title = title,
        value = null,
        valuePlacement = ValuePlacement.Trailing,
        valueTone = ValueTone.Plain,
        titleTone = TitleTone.Plain,
        titleIcon = null,
        badge = null,
        isValueLoading = false,
        accessory = Accessory.Toggle(isOn, onIsOnChange),
        footnote = null,
        isConfirmed = false,
        action = null,
    )

    /** L'identité d'une ligne dans son groupe : son intitulé. */
    val id: String get() = title

    /** Ce qui se pose à droite de la ligne, et qui décide de sa nature. */
    sealed interface Accessory {
        /** Rien : la ligne se lit, elle ne se touche pas. */
        data object None : Accessory

        /** Le chevron : la ligne mène ailleurs — un écran, une feuille. */
        data object Disclosure : Accessory

        /** L'interrupteur : la ligne **est** le réglage. */
        class Toggle internal constructor(
            internal val isOn: Boolean,
            internal val onIsOnChange: (Boolean) -> Unit,
        ) : Accessory
    }

    /** Le crayon : la valeur se corrige **sur place**, sans quitter l'écran. */
    class Editable internal constructor(
        internal val text: String,
        internal val onTextChange: (String) -> Unit,
        internal val placeholder: String?,
        internal val keyboardType: KeyboardType,
        internal val textContentType: ContentType?,
        /** La correction vient d'être enregistrée : le crayon laisse la place à une coche verte. */
        internal val isConfirmed: Boolean,
    ) : Accessory

    /** Une ligne de plus, sous la ligne : soit une précision, soit un reproche. */
    sealed interface Footnote {
        /** Une précision neutre — pourquoi la ligne ne se corrige pas, d'où vient sa valeur. */
        class Note(val message: String) : Footnote

        /** Ce qui ne va pas dans ce qui vient d'être saisi. */
        class Problem(val message: String) : Footnote
    }

    /** Comment l'intitulé s'écrit. */
    enum class TitleTone {
        /** Le corps de texte : l'intitulé nomme une valeur qu'on lit à côté. */
        Plain,

        /**
         * Le surtitre vert en capitales : l'intitulé **est** le sujet de la
         * ligne, et la valeur n'en est que le chiffre. Réservé aux groupes
         * [BrandRowGroup.Tone.Highlighted], dont il reprend la couleur.
         */
        Accent,
    }

    /** Comment la valeur se lit. */
    enum class ValueTone {
        /** Le gris de la marque : une valeur qu'on lit. */
        Plain,

        /** Gras et encre pleine : ce qu'on vient chercher du regard — un solde, un total. */
        Prominent,

        /**
         * **La valeur manque, et la ligne propose de la donner** — « Ajouter une
         * adresse ». En vert d'action et un cran plus petit
         * ([MemoBookFont.rowAction]) : c'est une invitation, pas une donnée
         * (Hugo, 14/09/2026, T22).
         */
        Invitation,
    }

    /** Où se pose la valeur par rapport à l'intitulé. */
    enum class ValuePlacement {
        /** Sur la même ligne, poussée à droite. Le cas courant. */
        Trailing,

        /** Sous l'intitulé, alignée à gauche : pour une valeur trop longue ou trop importante pour finir en bout de ligne — un numéro de carte. */
        Below,
    }

    /**
     * Le logo d'intitulé — l'autocollant Apple ou Google qui dit d'où vient
     * une adresse (Hugo, 17/09/2026) —, et ce que TalkBack en dit : un dessin
     * ne parle pas, la phrase qu'il remplace reste pour qui ne le voit pas.
     * Posé tel quel, sans teinte : c'est un logo, il garde ses couleurs.
     */
    class TitleIcon(@param:DrawableRes internal val image: Int, internal val label: String)
}

// Le dessin d'une ligne

/** Les marges d'une ligne : 16 sur les côtés, 12 en haut et en bas, et la cible tactile pour plancher. */
private fun Modifier.rowFrame(minimumHeight: Dp): Modifier = this
    .fillMaxWidth()
    .heightIn(min = minimumHeight)
    .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.xs + 4.dp)

@Composable
private fun BrandRowContent(row: BrandRow) {
    Column(Modifier.fillMaxWidth()) {
        when (val accessory = row.accessory) {
            is BrandRow.Editable -> EditableRow(row, accessory)
            is BrandRow.Accessory.Toggle -> ToggleRow(row, accessory)
            BrandRow.Accessory.None, BrandRow.Accessory.Disclosure -> ReadingRow(row)
        }
        row.footnote?.let { Footnote(it) }
    }
}

/** Une ligne de lecture, ou qui mène ailleurs. */
@Composable
private fun ReadingRow(row: BrandRow) {
    val minimumHeight = scaled(MemoBookSpacing.minimumTapTarget)
    val chevronSide = scaled(22.dp)
    val pencilSide = scaled(16.dp)
    val action = row.action
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // Une ligne pressée s'éclaire, elle ne s'enfonce pas : elle est solidaire
    // de la carte qui la porte, et une carte ne se plie pas ligne par ligne.
    val highlight by animateColorAsState(
        if (pressed) MemoBookColor.background else MemoBookColor.background.copy(alpha = 0f),
        tween(120, easing = SwiftMotion.easeOut),
        label = "pression",
    )
    val container = if (action != null) {
        Modifier
            .clickable(interaction, indication = null, role = Role.Button, onClick = action)
            .background(highlight)
    } else {
        Modifier.semantics(mergeDescendants = true) {}
    }
    Row(
        container.rowFrame(minimumHeight),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LabelAndValue(row, Modifier.weight(1f))
        // La pastille passe **après** la valeur : c'est un commentaire sur
        // elle, pas un second intitulé.
        row.badge?.let { BrandTagPill(it, isUppercased = true) }
        if (row.accessory == BrandRow.Accessory.Disclosure) {
            // La coche remplace le chevron en fondu, comme elle remplace le
            // crayon d'une ligne corrigée sur place.
            ConfirmableMark(row.isConfirmed, side = chevronSide, glyphSide = pencilSide) {
                RowGlyph(R.drawable.icon_chevron, chevronSide, MemoBookColor.inkMuted)
            }
        }
    }
}

/**
 * Une ligne à interrupteur. **Toute la ligne bascule le réglage**, et pas
 * seulement l'interrupteur : c'est le comportement des Réglages d'iOS, et une
 * question de taille de cible. TalkBack y lit un seul interrupteur, « activé »
 * ou « désactivé », nommé par l'intitulé.
 */
@Composable
private fun ToggleRow(row: BrandRow, toggle: BrandRow.Accessory.Toggle) {
    val minimumHeight = scaled(MemoBookSpacing.minimumTapTarget)
    Row(
        Modifier
            .toggleable(
                value = toggle.isOn,
                interactionSource = null,
                indication = null,
                role = Role.Switch,
                onValueChange = toggle.onIsOnChange,
            )
            .rowFrame(minimumHeight),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TitleText(row, Modifier.weight(1f))
        BrandSwitch(toggle.isOn, toggle.onIsOnChange, isTapTarget = false)
    }
}

/**
 * Une ligne qu'on corrige sur place. Elle a **exactement** le dessin d'une
 * ligne de lecture : mêmes marges, même typographie, même hauteur. Rien ne
 * bouge quand le champ prend le focus.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditableRow(row: BrandRow, field: BrandRow.Editable) {
    val minimumHeight = scaled(MemoBookSpacing.minimumTapTarget)
    val pencilSide = scaled(16.dp)
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val currentField by rememberUpdatedState(field)
    val isLoading by rememberUpdatedState(row.isValueLoading)

    // Ce qu'on est en train de taper. La valeur du modèle ne bouge qu'à la
    // sortie du champ ; entre les deux, c'est ce brouillon qui vit.
    var draft by remember { mutableStateOf(field.text) }
    var isEditing by remember { mutableStateOf(false) }
    var commits by remember { mutableIntStateOf(0) }

    // La valeur peut changer sous le champ (un rechargement) : on la reprend
    // tant qu'on n'est pas en train de taper dedans. Et après chaque
    // enregistrement, la ligne reprend ce que le modèle a **gardé** — il a pu
    // refuser (un nom vide) ou normaliser (des espaces autour).
    LaunchedEffect(field.text, commits) {
        if (!isEditing) draft = field.text
    }

    // Android : le retour referme le clavier **sans ôter le focus**, là où iOS
    // le rend. Sans ce relais, la correction ne s'enregistrerait jamais.
    val imeVisible = WindowInsets.isImeVisible
    LaunchedEffect(imeVisible) {
        if (!imeVisible && isEditing) focusManager.clearFocus()
    }

    // Quitter l'écran clavier ouvert compte aussi comme une sortie.
    DisposableEffect(Unit) {
        onDispose {
            if (isEditing) {
                isEditing = false
                currentField.onTextChange(draft)
            }
        }
    }

    val email = field.keyboardType == KeyboardType.Email
    val editor: @Composable (Modifier, TextAlign) -> Unit = { modifier, alignment ->
        BasicTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = modifier
                .focusRequester(focusRequester)
                .onFocusChanged { state ->
                    if (state.isFocused) {
                        isEditing = true
                    } else if (isEditing) {
                        // **L'enregistrement.** Sortir du champ suffit : refermer
                        // le clavier, toucher un autre champ. Rien à valider.
                        isEditing = false
                        currentField.onTextChange(draft)
                        commits++
                    }
                }
                .semantics {
                    contentDescription = row.title
                    field.textContentType?.let { contentType = it }
                },
            // La même encre que la valeur d'une ligne de lecture : le champ ne
            // s'annonce pas, il prend la place du texte.
            textStyle = MemoBookFont.body.copy(color = MemoBookColor.inkMuted, textAlign = alignment),
            singleLine = true,
            cursorBrush = SolidColor(MemoBookColor.action),
            keyboardOptions = KeyboardOptions(
                capitalization = if (email) KeyboardCapitalization.None else KeyboardCapitalization.Sentences,
                autoCorrectEnabled = !email,
                keyboardType = field.keyboardType,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
            decorationBox = { inner ->
                Box(contentAlignment = if (alignment == TextAlign.End) Alignment.CenterEnd else Alignment.CenterStart) {
                    if (draft.isEmpty() && field.placeholder != null) {
                        BrandText(field.placeholder, MemoBookFont.body, color = MemoBookColor.inkFaint, maxLines = 1)
                    }
                    inner()
                }
            },
        )
    }

    Row(
        Modifier
            // Toute la ligne ouvre le champ, pas seulement les quelques
            // caractères de la valeur — et une ligne vide s'ouvre aussi. Tant
            // que la valeur n'est pas arrivée, il n'y a rien à corriger : ouvrir
            // le clavier écraserait ce qui est encore en route.
            .pointerInput(Unit) { detectTapGestures { if (!isLoading) focusRequester.requestFocus() } }
            .rowFrame(minimumHeight),
        horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f)) {
            when {
                row.isValueLoading -> Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                    TitleText(row, Modifier.alignByBaseline())
                    Spacer(Modifier.weight(1f))
                    BrandSkeleton(Modifier.alignBy { it.measuredHeight }, width = 120.dp)
                }
                isAccessibilityTextSize() -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    TitleText(row)
                    editor(Modifier.fillMaxWidth(), TextAlign.Start)
                }
                else -> Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
                    TitleText(row, Modifier.alignByBaseline())
                    editor(Modifier.weight(1f).alignByBaseline(), TextAlign.End)
                }
            }
        }
        // Le crayon : sans lui, rien ne dirait qu'une ligne se corrige. Il prend
        // la place du chevron, à la même distance du bord.
        ConfirmableMark(field.isConfirmed, side = pencilSide, glyphSide = pencilSide) {
            RowGlyph(R.drawable.icon_pen, pencilSide, if (isEditing) MemoBookColor.action else MemoBookColor.inkMuted)
        }
    }
}

/** La ligne de dessous. Elle occupe les mêmes marges que la ligne, pour se lire comme sa suite. */
@Composable
private fun Footnote(footnote: BrandRow.Footnote) {
    val (text, tint) = when (footnote) {
        is BrandRow.Footnote.Note -> footnote.message to MemoBookColor.inkMuted
        is BrandRow.Footnote.Problem -> footnote.message to MemoBookColor.error
    }
    BrandText(
        text,
        MemoBookFont.caption,
        Modifier
            .fillMaxWidth()
            .padding(horizontal = MemoBookSpacing.s)
            .padding(bottom = MemoBookSpacing.xs + 4.dp),
        color = tint,
    )
}

/**
 * L'intitulé et sa valeur. Ils partagent une ligne tant qu'ils y tiennent : en
 * taille accessible, la valeur passe dessous plutôt que de rogner l'un ou
 * l'autre.
 */
@Composable
private fun LabelAndValue(row: BrandRow, modifier: Modifier) {
    if (row.valuePlacement == BrandRow.ValuePlacement.Below || isAccessibilityTextSize()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            TitleText(row)
            ValueText(row, stacked = true, Modifier)
        }
    } else {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            // **L'intitulé tient sur sa ligne, c'est la valeur qui s'abrège.**
            // Mesuré le premier, il prend ce qu'il lui faut ; la valeur a le
            // reste. Sans cette priorité, « Décorations & stickers » passait à
            // la ligne dès que « 2 / étape » demandait sa place (Clara,
            // 17/09/2026).
            TitleText(row, Modifier.alignByBaseline())
            ValueText(
                row,
                stacked = false,
                Modifier.weight(1f).alignByBaseline(),
                skeletonModifier = Modifier.weight(1f).alignBy { it.measuredHeight },
            )
        }
    }
}

@Composable
private fun TitleText(row: BrandRow, modifier: Modifier = Modifier) {
    when (row.titleTone) {
        BrandRow.TitleTone.Plain -> {
            val icon = row.titleIcon
            if (icon == null) {
                BrandText(row.title, MemoBookFont.body, modifier)
            } else {
                // Le logo suit l'intitulé, à la taille d'une ligne de corps de
                // texte : il précise le mot, il ne le concurrence pas.
                Row(
                    modifier,
                    horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    BrandText(row.title, MemoBookFont.body, Modifier.weight(1f, fill = false))
                    Image(
                        painter = painterResource(icon.image),
                        contentDescription = icon.label,
                        modifier = Modifier.size(scaled(20.dp)),
                    )
                }
            }
        }
        BrandRow.TitleTone.Accent -> BrandText(
            row.title.uppercase(),
            MemoBookFont.overline.copy(letterSpacing = MemoBookFont.tracking),
            // Les capitales sont un dessin, pas une manière de crier : TalkBack
            // lit l'intitulé tel qu'il est écrit.
            modifier.clearAndSetSemantics { contentDescription = row.title },
            color = MemoBookColor.action,
        )
    }
}

/**
 * La valeur, ou sa barre d'attente.
 *
 * @param stacked la valeur est sous l'intitulé. En bout de ligne, elle tient sur
 *   une ligne et s'abrège par la fin — la fin d'une adresse en dit autant que
 *   son début.
 * @param skeletonModifier la place de la barre d'attente : son pied se pose sur
 *   la ligne de base de l'intitulé, comme une vue sans texte dans SwiftUI.
 */
@Composable
private fun ValueText(row: BrandRow, stacked: Boolean, modifier: Modifier, skeletonModifier: Modifier = modifier) {
    val value = row.value
    when {
        row.isValueLoading -> {
            // Une barre de la largeur d'une valeur courante, pas de la ligne
            // entière : elle doit se lire comme « la valeur arrive », pas comme
            // « la ligne est vide ».
            Box(skeletonModifier, contentAlignment = if (stacked) Alignment.CenterStart else Alignment.CenterEnd) {
                BrandSkeleton(width = if (row.valuePlacement == BrandRow.ValuePlacement.Below) 180.dp else 120.dp)
            }
        }
        value != null -> {
            val (style, color) = when (row.valueTone) {
                BrandRow.ValueTone.Plain -> MemoBookFont.body to MemoBookColor.inkMuted
                BrandRow.ValueTone.Prominent -> MemoBookFont.bodySemibold to MemoBookColor.ink
                BrandRow.ValueTone.Invitation -> MemoBookFont.rowAction to MemoBookColor.action
            }
            BrandText(
                value,
                style,
                modifier,
                color = color,
                textAlign = if (stacked) null else TextAlign.End,
                maxLines = if (stacked) Int.MAX_VALUE else 1,
                // **Elle ne rapetisse que dans un groupe mis en avant.** Une
                // adresse écrite un poil plus petit que le téléphone au-dessus
                // se lit comme un défaut ; les chiffres d'un groupe cerclé, eux,
                // sont le sujet de la ligne et doivent se lire entiers.
                minimumScaleFactor = if (row.titleTone == BrandRow.TitleTone.Accent) 0.85f else 1f,
            )
        }
    }
}

/**
 * Le chevron du jeu de marque, ou le crayon. Le cadre est plus grand que le
 * trait qu'on voit : comme toutes les icônes du jeu, le glyphe est dessiné au
 * milieu d'une boîte de 24 et n'en occupe que le tiers. C'est la boîte qu'on
 * dimensionne.
 */
@Composable
private fun RowGlyph(@DrawableRes icon: Int, side: Dp, tint: Color) {
    Image(
        painter = painterResource(icon),
        contentDescription = null,
        colorFilter = ColorFilter.tint(tint),
        modifier = Modifier.size(side),
    )
}

/**
 * Le crayon ou le chevron, et la coche d'accusé de réception qui le remplace :
 * une ligne qui s'enregistre toute seule ne dit rien de ce qui s'est passé.
 * La coche arrive en fondu, de 70 % de sa taille : apparue net, elle
 * ressemblerait à un changement d'icône plutôt qu'à une confirmation.
 *
 * @param side la boîte de ce qu'elle remplace, pour que la valeur ne bouge pas
 *   d'un point quand l'un prend la place de l'autre.
 * @param glyphSide le corps du symbole — celui du crayon.
 */
@Composable
private fun ConfirmableMark(isConfirmed: Boolean, side: Dp, glyphSide: Dp, idle: @Composable () -> Unit) {
    val motion = SwiftMotion.snappy<Float>(0.25f)
    AnimatedContent(
        targetState = isConfirmed,
        transitionSpec = {
            if (targetState) {
                (fadeIn(motion) + scaleIn(motion, initialScale = 0.7f)) togetherWith fadeOut(motion)
            } else {
                fadeIn(motion) togetherWith (fadeOut(motion) + scaleOut(motion, targetScale = 0.7f))
            } using SizeTransform(clip = false)
        },
        contentAlignment = Alignment.Center,
        label = "accusé de réception",
    ) { confirmed ->
        if (confirmed) {
            // Le symbole système et non le jeu de marque, qui n'a pas de
            // coche : « checkmark.circle.fill », redessiné.
            Box(Modifier.size(side), contentAlignment = Alignment.Center) {
                Image(
                    painter = painterResource(R.drawable.system_checkmark_circle_fill),
                    contentDescription = "Enregistré",
                    colorFilter = ColorFilter.tint(MemoBookColor.valid),
                    // Le disque du symbole occupe 20 des 24 de sa boîte : il
                    // fait ainsi le corps du crayon, comme le symbole SF.
                    modifier = Modifier.requiredSize(glyphSide * 1.2f),
                )
            }
        } else {
            idle()
        }
    }
}

// Aperçus

@Preview(name = "Lignes groupées", widthDp = 390, heightDp = 640)
@Composable
private fun BrandRowGroupPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        BrandRowGroup {
            +BrandRow("E-mail", value = "maylis.garde@icloud.com")
            +BrandRow("Téléphone", value = "+33 6 98 69 34 48")
            +BrandRow("Adresse postale", value = "7 Rue Simon Fryd, Lyon, France") {}
            +BrandRow("Newsletter mensuelle MemoBook", isOn = true, onIsOnChange = {})
        }
        BrandRowGroup {
            +BrandRow("Dernière commande", value = "129,50 €", valueTone = BrandRow.ValueTone.Prominent) {}
            +BrandRow("Adresse postale", value = "Ajouter une adresse", valueTone = BrandRow.ValueTone.Invitation) {}
            +BrandRow("Mon abonnement") {}
            +BrandRow("Partager sur la galerie", isOn = false, onIsOnChange = {})
        }
        BrandRowGroup {
            +BrandRow(
                "Carte bancaire enregistrée",
                value = "XXXX XXXX XXXX 1820",
                valuePlacement = BrandRow.ValuePlacement.Below,
            ) {}
        }
    }
}

@Preview(name = "Lignes groupées — AX3", widthDp = 390, heightDp = 640, fontScale = 2f)
@Composable
private fun BrandRowGroupAccessibilityPreview() {
    Column(
        Modifier
            .background(MemoBookColor.background)
            .padding(MemoBookSpacing.screenMargin),
    ) {
        BrandRowGroup {
            +BrandRow("E-mail", value = "maylis.garde@icloud.com")
            +BrandRow("Adresse postale", value = "7 Rue Simon Fryd, Lyon, France") {}
            +BrandRow("Newsletter mensuelle MemoBook", isOn = true, onIsOnChange = {})
        }
    }
}
