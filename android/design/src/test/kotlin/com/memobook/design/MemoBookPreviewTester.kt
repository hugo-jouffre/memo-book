package com.memobook.design

import com.github.takahirom.roborazzi.AndroidComposePreviewTester
import com.github.takahirom.roborazzi.ComposePreviewTester
import com.github.takahirom.roborazzi.RoborazziOptions

/**
 * Le testeur des previews de `:design` : celui de Roborazzi, avec une
 * tolérance d'**1 % des pixels**.
 *
 * Les images de référence sont enregistrées sur un Mac, la CI les compare sous
 * Linux, et Robolectric n'y lisse pas le texte tout à fait de la même façon :
 * au premier passage (#140, 21/10/2026), cinq previews sur quarante-deux
 * différaient, de 0,0005 % à 0,5 % de leurs pixels, et aucun pixel de plus d'un
 * quart de son intensité. Un composant qui change vraiment — une marge, une
 * couleur, un mot — en déplace bien davantage.
 */
class MemoBookPreviewTester :
    ComposePreviewTester<ComposePreviewTester.TestParameter.JUnit4TestParameter.AndroidPreviewJUnit4TestParameter> by AndroidComposePreviewTester(
        capturer = object : AndroidComposePreviewTester.Capturer {
            override fun capture(parameter: AndroidComposePreviewTester.CaptureParameter) {
                val options = parameter.roborazziOptions
                val tolerant = options.copy(
                    compareOptions = RoborazziOptions.CompareOptions(
                        outputDirectoryPath = options.compareOptions.outputDirectoryPath,
                        changeThreshold = CHANGE_THRESHOLD,
                    ),
                )
                AndroidComposePreviewTester.DefaultCapturer().capture(parameter.copy(roborazziOptions = tolerant))
            }
        },
    )

/** La part des pixels qui peut changer d'un système à l'autre sans que ce soit une régression. */
private const val CHANGE_THRESHOLD = 0.01f
