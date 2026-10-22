package com.memobook.feature.order

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.memobook.core.OrderCopy
import com.memobook.core.PrintedCopyOption
import com.memobook.core.ShippingSpeed
import com.memobook.design.BrandButton
import com.memobook.design.BrandCountryField
import com.memobook.design.BrandNotice
import com.memobook.design.BrandOptionGroup
import com.memobook.design.BrandOptionRow
import com.memobook.design.BrandSkeleton
import com.memobook.design.BrandStepper
import com.memobook.design.BrandText
import com.memobook.design.BrandTextField
import com.memobook.design.ErrorBanner
import com.memobook.design.MemoBookColor
import com.memobook.design.MemoBookFont
import com.memobook.design.MemoBookSpacing
import com.memobook.design.PlainButtonIndication
import com.memobook.design.R
import com.memobook.design.SwiftMotion
import com.memobook.design.isAccessibilityTextSize
import com.memobook.design.scaled
import com.memobook.feature.profile.euros
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Les quatre premières étapes : de quoi on part, où ça va, en combien
// d'exemplaires, et à quelle vitesse. Le jumeau de `Order/OrderSteps.swift`.

// MARK: - Étape 1 — Démarrage

/**
 * Ce qu'on s'apprête à commander.
 *
 * La carte se dessine **tout de suite**, squelettes compris : on sait à quoi
 * ressemble l'écran avant de savoir ce qu'il y a dessus. Voir `BrandSkeleton`.
 *
 * Elle était coiffée d'une carte de la cagnotte — « Montant disponible » et
 * l'estimation du carnet —, partie avec elle (Hugo, 06/10/2026, T230).
 */
@Composable
internal fun OrderStartStep(state: OrderModel.State, model: OrderModel, onHelp: () -> Unit) {
    val scope = rememberCoroutineScope()
    val phase = state.phase

    OrderStepLayout(
        help = onHelp,
        content = {
            // La carte se remplit en douceur, d'un seul tenant.
            OrderTripCard(
                trip = state.context?.trip,
                isLoading = phase == OrderModel.Phase.Loading,
                modifier = Modifier.animateContentSize(SwiftMotion.snappy(0.3f)),
            )

            // Le carnet n'a jamais été composé : il n'y a rien à imprimer, et
            // c'est dit ici plutôt que découvert au moment de payer. La boîte
            // porte **la porte de service** : on peut passer commande quand
            // même, et c'est elle qui débloque le bouton du bas — voir
            // `OrderModel.orderWithoutRender`.
            if (phase == OrderModel.Phase.Ready && state.context?.renderId == null) {
                BrandNotice(
                    "**${OrderCopy.Start.notComposed}** " + OrderCopy.Start.notComposedDetail,
                    footer = if (state.ordersWithoutRender) {
                        null
                    } else {
                        {
                            BrandButton(
                                OrderCopy.Start.orderAnyway,
                                style = BrandButton.Style.Link,
                                action = model::orderWithoutRender,
                            )
                        }
                    },
                )
            }

            if (phase is OrderModel.Phase.Failed) {
                ErrorBanner(phase.message, retry = { scope.launch { model.retry() } })
            }
        },
        actions = {
            BrandButton(
                OrderCopy.Start.cta,
                fillsWidth = true,
                enabled = state.canContinue,
                action = model::advance,
            )
        },
    )
}

// MARK: - Étape 2 — Livraison

/**
 * Où le carnet doit arriver.
 *
 * Les champs sont **préremplis avec l'adresse du profil** : personne ne
 * ressaisit ce qu'on sait déjà. C'est une amorce, pas un verrou — tout reste
 * corrigeable, et l'adresse de la commande se fige à la commande.
 */
@Composable
internal fun OrderShippingStep(
    state: OrderModel.State,
    model: OrderModel,
    focus: OrderField?,
    onFocusChange: (OrderField?) -> Unit,
) {
    OrderStepLayout(
        content = {
            OrderSectionHeader(OrderCopy.Shipping.title)

            if (state.phase == OrderModel.Phase.Loading) {
                OrderShippingSkeleton()
            } else {
                OrderShippingFields(state, model, focus, onFocusChange)
            }
        },
        actions = {
            BrandButton(
                OrderCopy.next,
                fillsWidth = true,
                enabled = state.canContinue,
                action = model::advance,
            )
        },
    )
}

@Composable
private fun OrderShippingFields(
    state: OrderModel.State,
    model: OrderModel,
    focus: OrderField?,
    onFocusChange: (OrderField?) -> Unit,
) {
    val shipping = state.draft.shipping
    val next = { field: OrderField -> KeyboardActions(onNext = { onFocusChange(field) }) }
    val words = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next)

    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        BrandTextField(
            OrderCopy.Shipping.name,
            shipping.name,
            { value -> model.editShipping { it.copy(name = value) } },
            field = OrderField.Name,
            focus = focus,
            onFocusChange = onFocusChange,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = OrderCopy.Shipping.placeholder,
            keyboardOptions = words,
            keyboardActions = next(OrderField.Line1),
            contentType = ContentType.PersonFullName,
        )

        BrandTextField(
            OrderCopy.Shipping.line1,
            shipping.line1,
            { value -> model.editShipping { it.copy(line1 = value) } },
            field = OrderField.Line1,
            focus = focus,
            onFocusChange = onFocusChange,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = OrderCopy.Shipping.placeholder,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = next(OrderField.Line2),
            contentType = ContentType.AddressStreet,
        )

        // La deuxième ligne d'adresse est optionnelle côté modèle, obligatoire
        // côté champ de texte : ce pont traduit « rien » en chaîne vide et
        // l'inverse, pour qu'une ligne effacée reparte bien à `null`.
        BrandTextField(
            OrderCopy.Shipping.line2,
            shipping.line2.orEmpty(),
            { value -> model.editShipping { it.copy(line2 = value.ifEmpty { null }) } },
            field = OrderField.Line2,
            focus = focus,
            onFocusChange = onFocusChange,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = "Bâtiment, étage…",
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = next(OrderField.PostalCode),
            contentType = ContentType.AddressAuxiliaryDetails,
        )

        OrderPostalCodeAndCity(state, model, focus, onFocusChange)

        BrandCountryField(
            countries = state.context?.countries ?: emptyList(),
            code = shipping.country,
            onCodeChange = { code -> model.editShipping { it.copy(country = code) } },
            label = OrderCopy.Shipping.country,
        )
    }
}

/**
 * Code postal et ville côte à côte, comme la maquette — et **empilés** dès que
 * le texte grandit : à deux colonnes, « Code postal » n'y tient plus.
 */
@Composable
private fun OrderPostalCodeAndCity(
    state: OrderModel.State,
    model: OrderModel,
    focus: OrderField?,
    onFocusChange: (OrderField?) -> Unit,
) {
    val shipping = state.draft.shipping
    val postalCode: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            OrderCopy.Shipping.postalCode,
            shipping.postalCode,
            { value -> model.editShipping { it.copy(postalCode = value) } },
            field = OrderField.PostalCode,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = OrderCopy.Shipping.placeholder,
            // Le clavier texte et non le pavé numérique : le `.numbersAndPunctuation`
            // d'iOS garde les lettres à portée, et un code postal britannique ou
            // canadien en a. Android n'a pas de clavier entre les deux.
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { onFocusChange(OrderField.City) }),
            contentType = ContentType.PostalCode,
        )
    }
    val city: @Composable (Modifier) -> Unit = { modifier ->
        BrandTextField(
            OrderCopy.Shipping.city,
            shipping.city,
            { value -> model.editShipping { it.copy(city = value) } },
            field = OrderField.City,
            focus = focus,
            onFocusChange = onFocusChange,
            modifier = modifier,
            labelPlacement = BrandTextField.LabelPlacement.Above,
            placeholder = OrderCopy.Shipping.placeholder,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onFocusChange(null) }),
            contentType = ContentType.AddressLocality,
        )
    }

    if (isAccessibilityTextSize()) {
        Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
            postalCode(Modifier)
            city(Modifier)
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.s), verticalAlignment = Alignment.Top) {
            postalCode(Modifier.weight(1f))
            city(Modifier.weight(1f))
        }
    }
}

@Composable
private fun OrderShippingSkeleton() {
    Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s)) {
        repeat(4) {
            Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                BrandSkeleton(width = 110.dp)
                BrandSkeleton(height = MemoBookSpacing.fieldHeight, cornerRadius = MemoBookSpacing.controlCornerRadius)
            }
        }
    }
}

// MARK: - Étape 3 — Exemplaires

/** Combien de carnets, et dans quelle version chacun. */
@Composable
internal fun OrderCopiesStep(state: OrderModel.State, model: OrderModel, onHelp: () -> Unit) {
    OrderStepLayout(
        help = onHelp,
        content = {
            OrderCopiesCounter(state, model)
            OrderCopiesCustomisation(state, model)
        },
        actions = {
            BrandButton(
                OrderCopy.next,
                fillsWidth = true,
                enabled = state.canContinue,
                action = model::advance,
            )
        },
    )
}

@Composable
private fun OrderCopiesCounter(state: OrderModel.State, model: OrderModel) {
    val shape = RoundedCornerShape(MemoBookSpacing.controlCornerRadius)
    Column(
        Modifier.animateContentSize(SwiftMotion.snappy(0.25f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        OrderSectionHeader(OrderCopy.Copies.title, subtitle = OrderCopy.Copies.subtitle)

        BrandStepper(
            value = state.draft.copies,
            modifier = Modifier.align(Alignment.CenterHorizontally),
            canDecrement = state.draft.copies > 1,
            canIncrement = state.draft.copies < OrderModel.MAXIMUM_COPIES,
            onDecrement = model::removeCopy,
            onIncrement = model::addCopy,
        )

        // La limite du compteur, dite sous lui ; elle arrive et repart en
        // glissant, sans faire sauter la ligne du prix.
        AnimatedContent(
            targetState = state.errorMessage,
            transitionSpec = {
                (fadeIn(SwiftMotion.snappy(0.25f)) + slideInVertically(SwiftMotion.snappy(0.25f)) { -it / 2 }) togetherWith
                    fadeOut(SwiftMotion.snappy(0.25f))
            },
            label = "limite",
        ) { message ->
            if (message != null) {
                BrandText(
                    message,
                    MemoBookFont.h3,
                    Modifier.fillMaxWidth(),
                    color = MemoBookColor.warning,
                    textAlign = TextAlign.Center,
                )
            }
        }

        OrderPriceRow(
            OrderCopy.Copies.unitPrice,
            modifier = Modifier
                .background(MemoBookColor.surface, shape)
                .border(1.dp, MemoBookColor.hairline, shape)
                .padding(horizontal = MemoBookSpacing.s, vertical = MemoBookSpacing.snug),
            amount = state.context?.unitPrice,
        )
    }
}

@Composable
private fun OrderCopiesCustomisation(state: OrderModel.State, model: OrderModel) {
    // Les exemplaires apparaissent et disparaissent avec le compteur : la liste
    // grandit en douceur au lieu de sauter.
    Column(
        Modifier.animateContentSize(SwiftMotion.snappy(0.3f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.s),
    ) {
        OrderSectionHeader(OrderCopy.Copies.customiseTitle, subtitle = OrderCopy.Copies.customiseSubtitle)

        state.draft.copyOptions.forEach { copy ->
            key(copy.position) { OrderCopyDisclosure(state, model, copy.position) }
        }
    }
}

/**
 * Un exemplaire et ses quatre options, repliables.
 *
 * Le premier carnet s'ouvre sur ses options ; les suivants annoncent d'abord
 * qu'ils reprennent sa version, et ne montrent leurs propres réglages que si
 * on demande à les détacher.
 *
 * **Ce qu'on vient de déplier est amené sous les yeux** : sans ça, les options
 * d'un carnet déplié en bas de page apparaissent **sous** la barre du bouton,
 * et rien ne dit qu'elles sont là. iOS le cale en haut de la vue ; ici, la
 * liste défile juste assez pour le montrer en entier.
 */
@Composable
private fun OrderCopyDisclosure(state: OrderModel.State, model: OrderModel, position: Int) {
    // Le premier carnet s'ouvre : c'est celui qu'on règle, et les autres en
    // découlent.
    var isExpanded by remember { mutableStateOf(position == 1) }
    val copy = state.draft.copyOptions.firstOrNull { it.position == position }
    val followsFirst = state.followsFirstCopy(position)
    val title = OrderCopy.Copies.copyTitle(position)

    val requester = remember { BringIntoViewRequester() }
    var reveals by remember { mutableIntStateOf(0) }
    LaunchedEffect(reveals) {
        if (reveals == 0) return@LaunchedEffect
        // Après l'ouverture, pas pendant : le pli et le défilement se
        // marcheraient dessus.
        delay(REVEAL_DELAY_MS)
        requester.bringIntoView()
    }

    val chevronTurn by animateFloatAsState(if (isExpanded) 0f else -90f, SwiftMotion.snappy(0.28f), label = "chevron")

    Column(
        Modifier
            .bringIntoViewRequester(requester)
            .padding(vertical = MemoBookSpacing.xs)
            .animateContentSize(SwiftMotion.snappy(0.28f)),
        verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = MemoBookSpacing.minimumTapTarget)
                .clickable(
                    interactionSource = null,
                    indication = PlainButtonIndication,
                    role = Role.Button,
                    onClickLabel = if (isExpanded) "Replier" else "Déplier",
                ) {
                    isExpanded = !isExpanded
                    if (isExpanded) reveals++
                },
            horizontalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandText(title, MemoBookFont.bodySemibold, Modifier.weight(1f))
            // Le `chevron.right` d'iOS : le chevron vers le bas, tourné d'un
            // quart vers la droite tant que le carnet est replié.
            Image(
                painterResource(R.drawable.system_chevron_down),
                contentDescription = null,
                colorFilter = ColorFilter.tint(MemoBookColor.inkMuted),
                modifier = Modifier
                    .size(scaled(14.dp))
                    .rotate(chevronTurn),
            )
        }

        AnimatedVisibility(
            visible = isExpanded,
            enter = fadeIn(SwiftMotion.snappy(0.28f)) + expandVertically(SwiftMotion.snappy(0.28f)),
            exit = fadeOut(SwiftMotion.snappy(0.28f)) + shrinkVertically(SwiftMotion.snappy(0.28f)),
        ) {
            if (position > 1 && followsFirst) {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.snug)) {
                    BrandText(OrderCopy.Copies.sameAsFirst, MemoBookFont.h3, color = MemoBookColor.inkMuted)

                    BrandButton(
                        OrderCopy.Copies.differentFromFirst,
                        style = BrandButton.Style.Secondary,
                        fillsWidth = true,
                    ) {
                        model.setFollowsFirstCopy(false, forCopyAt = position)
                        reveals++
                    }
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(MemoBookSpacing.xs)) {
                    if (copy != null) {
                        PrintedCopyOption.entries.forEach { option ->
                            OrderToggleCard(
                                title = option.title,
                                isOn = option.value(copy),
                                onIsOnChange = { model.setOption(option, it, forCopyAt = position) },
                            )
                        }
                    }

                    if (position > 1) {
                        BrandButton(
                            OrderCopy.Copies.backToSameAsFirst,
                            style = BrandButton.Style.Link,
                            fillsWidth = true,
                        ) {
                            model.setFollowsFirstCopy(true, forCopyAt = position)
                        }
                    }
                }
            }
        }
    }
}

/** Le pli dure 0,28 s ; le défilement part juste après — le `.delay(0.08)` d'iOS, compté depuis la fin du pli. */
private const val REVEAL_DELAY_MS = 360L

// MARK: - Étape 4 — Rapidité

/** À quelle vitesse le carnet part. */
@Composable
internal fun OrderSpeedStep(state: OrderModel.State, model: OrderModel, onHelp: () -> Unit) {
    OrderStepLayout(
        help = onHelp,
        content = {
            OrderSectionHeader(OrderCopy.Speed.title)

            BrandOptionGroup {
                ShippingSpeed.entries.forEach { speed ->
                    BrandOptionRow(
                        speed.title,
                        isSelected = state.draft.shippingSpeed == speed,
                        subtitle = state.context?.days(speed)?.label,
                        value = price(state, speed),
                    ) {
                        model.select(speed)
                    }
                }
            }

            state.quoteError?.let { message ->
                ErrorBanner(message, retry = model::refreshQuote)
            }
        },
        actions = {
            BrandButton(
                OrderCopy.Speed.cta,
                fillsWidth = true,
                enabled = state.canContinue,
                action = model::advance,
            )
        },
    )
}

/**
 * « Inclus » pour le standard, le supplément pour l'express. Rien tant que le
 * tarif n'est pas arrivé : un prix inventé serait pire qu'un blanc.
 */
private fun price(state: OrderModel.State, speed: ShippingSpeed): String? {
    val context = state.context ?: return null
    return when (speed) {
        ShippingSpeed.Standard -> OrderCopy.Speed.included
        ShippingSpeed.Express -> context.expressPrice.euros
    }
}
