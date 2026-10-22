package com.memobook.app

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * **L'app ne parle que français**, comme sur iOS : la langue est le français,
 * la **région** reste celle du téléphone — un lecteur aux États-Unis lit bien
 * des miles.
 *
 * Sur iOS, c'est `CFBundleLocalizations: [fr]` qui le dit (`ios/project.yml`) :
 * sans lui, un iPhone réglé en anglais affichait « 26 Aug–15 Sep » au milieu
 * d'une interface entièrement française. Android n'a pas d'équivalent dans le
 * manifeste ; on pose donc la locale à la main, sur le contexte de l'activité
 * (ce que lisent Compose et ses formats de date) et par défaut pour le
 * processus (ce que lit `java.time`).
 */
internal object FrenchLocale {
    fun of(context: Context): Locale {
        val device = context.resources.configuration.locales[0]
        return Locale.Builder().setLanguage("fr").setRegion(device.country.takeIf { it.length == 2 } ?: "").build()
    }

    /** Le contexte de l'activité, en français. */
    fun wrap(base: Context): Context {
        val locale = of(base)
        Locale.setDefault(locale)
        val configuration = Configuration(base.resources.configuration).apply { setLocale(locale) }
        return base.createConfigurationContext(configuration)
    }
}
